// inspector 服务核（只读检查通道）：应用进程内监听一个 socket，mng（inspect /
// mcp）连上来发一行命令、收回一段 TSV 响应。
//
// 开关纯注入式：`MNG_INSPECT=1` 由 mng dev / mng mcp 起应用时注入，未注入
// 不启动、零监听；socket 文件名带 `MNG_INSPECT_APP`（缺省 "app"）净化的 slug，
// 与单实例通道（moonbit-instance-*）互不干扰。占用即静默降级不监听。
//
// 泵：`inspect_auto_install` 往 shell 帧泵钩子表注册一拍（declarative 挂窗后
// 每 200ms 遍历），命令式应用不经 declarative 泵，直接在自己的循环里调
// `inspect_pump`。两路共用同一个处理体。
//
// 协议：请求是单行命令（tree / style <id> / select <id> / highlight <id> /
// shot [路径]），响应是 TSV 行文本，上限 256KB，超限截到最近完整行并尾行
// 标注 truncated；二进制不过管道（shot 落盘、回执只带路径）。

///|
/// 响应字节上限（256KB）。
pub const INSP_RESPONSE_CAP : Int32 = 262144

///|
/// 单条请求字节上限（单行命令足够，与桩内一致）。
const INSP_REQUEST_CAP : Int32 = 4096

// ---- 原生口：POSIX 套接字臂（inspector/stub.c）+ Windows 命名管道臂
//（gui/win/stub.c 的 _WIN32 分支），同符号族每平台恰好一份定义 ----

///|
#borrow(path, slug)
extern "c" fn yi_insp_listen(path : Bytes, slug : Bytes) -> Int32 = "yi_insp_listen"

///|
extern "c" fn yi_insp_poll() -> Int32 = "yi_insp_poll"

///|
#borrow(out)
extern "c" fn yi_insp_take(out : Bytes, cap : Int32) -> Int32 = "yi_insp_take"

///|
#borrow(data)
extern "c" fn yi_insp_respond(data : Bytes, len : Int32) -> Int32 = "yi_insp_respond"

///|
extern "c" fn yi_insp_last_errno() -> Int32 = "yi_insp_last_errno"

///|
extern "c" fn yi_insp_getuid() -> Int32 = "yi_insp_getuid"

// ---- socket 路径 ----

///|
/// app_id 的 djb2 哈希，十六进制定长 8 位（与单实例 slug 同规）。
fn insp_hash8(s : String) -> String {
  let mut h : Int32 = 5381
  for i = 0; i < s.length(); i = i + 1 {
    h = ((h << 5) + h + s.unsafe_get(i).to_int()) & 0x7FFF_FFFF
  }
  let digits : Array[String] = [
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f",
  ]
  let out = StringBuilder()
  let mut i = 7
  while i >= 0 {
    out.write_string(digits[(h >> (i * 4)) & 15])
    i = i - 1
  }
  out.to_string()
}

///|
/// slug 净化：非 [A-Za-z0-9_-] 换下划线；超 40 截断并附内容哈希
/// （与单实例通道同规，前缀不同互不干扰）。
fn insp_slug(app_id : String) -> String {
  let out = StringBuilder()
  for c in app_id.to_array() {
    let ok = (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '_' ||
      c == '-'
    out.write_char(if ok { c } else { '_' })
  }
  let s = out.to_string()
  if s.length() <= 40 {
    s
  } else {
    s[:40].to_owned() + "-" + insp_hash8(app_id)
  }
}

///|
/// socket 文件名安全的应用名净化（shot 缺省文件名用）：非文件字符换下划线。
fn insp_file_slug(name : String) -> String {
  let out = StringBuilder()
  for c in name.to_array() {
    let ok = (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '_' ||
      c == '-' ||
      c == '.'
    out.write_char(if ok { c } else { '_' })
  }
  let s = out.to_string()
  if s.length() > 0 {
    s
  } else {
    "app"
  }
}

///|
/// 目录归一：去掉尾部 `/`（mac 的 `$TMPDIR` 自带尾斜杠，直接拼会出 `//`；
/// 根目录 `/` 保持不变）。
fn insp_strip_trailing_slash(d : String) -> String {
  let mut end = d.length()
  while end > 1 && d[end - 1] == '/' {
    end -= 1
  }
  if end == d.length() {
    d
  } else {
    d[:end].to_owned()
  }
}

///|
/// socket 所在目录：`$XDG_RUNTIME_DIR` → `$TMPDIR` → `/tmp`（Windows 认
/// `$TEMP`，管道臂实际只用 slug，目录仅供路径构造完整）。
fn insp_socket_dir() -> String {
  let d = match @env.get_env_var("XDG_RUNTIME_DIR") {
    Some(d) if d != "" => d
    _ =>
      match @env.get_env_var("TMPDIR") {
        Some(t) if t != "" => t
        _ => "/tmp"
      }
  }
  insp_strip_trailing_slash(d)
}

///|
/// inspector 服务 socket 路径：`moonbit-inspect-<slug>.<uid>.sock`。
/// 三平台同一构造（Windows 的 uid 段为 0）：完整路径供 POSIX 套接字臂与
/// 测试断言用，Windows 管道臂实际只用 slug——listen 时两个参数都传，
/// C 臂各取所需（与客户端 mnginsp_call 的双参契约同形）。
pub fn inspect_socket_path(app_id : String) -> String {
  let dir = insp_socket_dir()
  let base = "moonbit-inspect-"
  let tail = ".\{yi_insp_getuid()}.sock"
  let slug = insp_slug(app_id)
  let sep = if dir == "/" { "" } else { "/" }
  "\{dir}\{sep}\{base}\{slug}\{tail}"
}

// ---- 开关与泵 ----

///|
/// 服务是否在听（观察面：文档与诊断用）。
let g_insp_started : Ref[Bool] = Ref(false)

///|
/// 降级标记：listen 失败（占用等）后不再重试。
let g_insp_failed : Ref[Bool] = Ref(false)

///|
/// 泵已注册进 shell 帧泵表（inspect_auto_install 幂等用）。
let g_insp_installed : Ref[Bool] = Ref(false)

///|
/// 服务在听与否。
pub fn inspect_running() -> Bool {
  g_insp_started.val
}

///|
/// 最近一次 listen 的 errno（诊断观察面：静默降级时可查原因）。
pub fn inspect_last_errno() -> Int32 {
  yi_insp_last_errno()
}

///|
/// 往 shell 帧泵钩子表注册泵（幂等）。装表本身零监听——每拍先探测
/// `MNG_INSPECT`，未注入一直是空转判断。声明式应用由本函数接线；
/// 命令式应用直接在自己的循环里调 [inspect_pump]。
pub fn inspect_auto_install() -> Unit {
  if g_insp_installed.val {
    return
  }
  g_insp_installed.val = true
  @shell.add_frame_pump(fn() { inspect_pump() })
}

///|
/// 服务泵一拍：未启动则探测注入开关（未注入零监听，直接返回）；已启动则
/// 收一条请求、执行、写回。命令式应用在自己的事件循环里定时调它。
pub fn inspect_pump() -> Unit {
  if !g_insp_started.val {
    if g_insp_failed.val {
      return
    }
    match @env.get_env_var("MNG_INSPECT") {
      Some("1") => ()
      _ => return
    }
    let app_id = match @env.get_env_var("MNG_INSPECT_APP") {
      Some(a) if a != "" => a
      _ => "app"
    }
    match yi_insp_listen(
        @utf8.encode(inspect_socket_path(app_id)),
        @utf8.encode(insp_slug(app_id)),
      ) {
      1 => g_insp_started.val = true
      _ => g_insp_failed.val = true
    }
    return
  }
  insp_serve_once()
  insp_highlight_tick()
}

///|
/// 收一条请求并写回响应。无请求（poll 0）原样返回。
fn insp_serve_once() -> Unit {
  if yi_insp_poll() != 1 {
    return
  }
  let buf = Bytes::make(INSP_REQUEST_CAP, b'\x00')
  let n = yi_insp_take(buf, INSP_REQUEST_CAP)
  if n <= 0 {
    let _ = yi_insp_respond(@utf8.encode("error: 空请求\n"), 15)
    return
  }
  let req = @utf8.decode_lossy(buf[0:n].to_owned())
  let resp = insp_truncate(inspect_handle(req), INSP_RESPONSE_CAP)
  let data = @utf8.encode(resp)
  let _ = yi_insp_respond(data, data.length())
}

///|
/// 响应截断：超上限时切到上限内最后一个完整行（\n 是单字节，切点不会碎
/// 字符），尾行标注 truncated。
fn insp_truncate(s : String, cap : Int32) -> String {
  let data = @utf8.encode(s)
  if data.length() <= cap {
    return s
  }
  let mut cut = cap
  while cut > 0 && data[cut] != b'\n' {
    cut -= 1
  }
  let head = @utf8.decode_lossy(data[0:cut].to_owned())
  "\{head}\ntruncated\n"
}

// ---- 取数口（面板与 dump 共用同一份） ----

///|
/// 控件树收集：默认组件视图——只收模板标签产出的件（`comp` 非空）与
/// 组件子树之外的件；组件内部实现件不占行，其子件挂回最近已收祖先。
/// `full` 全量收。隐藏子树与命中穿透层不收。
fn insp_tree_walk(
  w : @widget.Widget,
  shown_parent : Int32,
  in_comp : Bool,
  full : Bool,
  out : Array[@widget.A11yNode],
) -> Unit {
  if !w.visible || w.hit_pass_through {
    return
  }
  let keep = full || !in_comp || w.comp != ""
  if keep {
    let (state, value) = match w.a11y_state_now() {
      Some(p) => p
      None => ("", "")
    }
    out.push({
      id: w.id,
      parent: shown_parent,
      role: w.role,
      kind: w.kind,
      name: w.name,
      state,
      value,
      text: match w.a11y_text_now() {
        Some(s) => s
        None => ""
      },
      enabled: w.enabled,
      x: w.rect.x,
      y: w.rect.y,
      w: w.rect.w,
      h: w.rect.h,
    })
  }
  let kid_parent = if keep { w.id } else { shown_parent }
  for k in w.kids {
    insp_tree_walk(k, kid_parent, in_comp || w.comp != "", full, out)
  }
}

///|
/// 当前树快照（统一取数口）：直走最近上屏帧的控件树。面板刷新与 `tree`
/// 命令都走这里——dump 与面板看到的是同一份数据；`full` 为组件子树
/// 全量档（`tree --full`）。
pub fn insp_tree_snapshot(full~ : Bool = false) -> Array[@widget.A11yNode] {
  let out : Array[@widget.A11yNode] = []
  match @widget.last_frame_root() {
    Some(root) => insp_tree_walk(root, 0, false, full, out)
    None => ()
  }
  out
}

// ---- 命令处理 ----

///|
/// 请求分发：`tree [--full]` / `style <id>` / `select <id>` /
/// `highlight <id>` / `shot [路径]`。未知命令回一行 error。
pub fn inspect_handle(req : String) -> String {
  let line = req.trim().to_owned()
  let words : Array[String] = []
  for w in line.split(" ") {
    let s = w.trim().to_owned()
    if s != "" {
      words.push(s)
    }
  }
  let cmd = if words.length() > 0 { words[0] } else { "" }
  if cmd == "tree" {
    insp_tree_dump(full=words.contains("--full"))
  } else if cmd == "style" {
    match words.get(1) {
      Some(w) =>
        match parse_insp_int(w) {
          Some(id) => insp_style_dump(id)
          None => "error: style 需要 <id>（整数）\n"
        }
      None => "error: style 需要 <id>\n"
    }
  } else if cmd == "select" {
    match words.get(1) {
      Some(w) =>
        match parse_insp_int(w) {
          Some(id) => insp_select_dump(id)
          None => "error: select 需要 <id>（整数）\n"
        }
      None => "error: select 需要 <id>\n"
    }
  } else if cmd == "highlight" {
    match words.get(1) {
      Some(w) =>
        match parse_insp_int(w) {
          Some(id) => insp_highlight(id)
          None => "error: highlight 需要 <id>（整数，0 取消）\n"
        }
      None => "error: highlight 需要 <id>\n"
    }
  } else if cmd == "shot" {
    // `shot [--full] [路径]`：--full 档整页内容重画（滚动截图语义），
    // 缺省档是最近上屏帧（视口所见）
    let mut full = false
    let mut path : String? = None
    for i = 1; i < words.length(); i = i + 1 {
      if words[i] == "--full" {
        full = true
      } else if path is None {
        path = Some(words[i])
      }
    }
    insp_shot(path, full)
  } else if cmd == "" {
    "error: 空请求\n"
  } else {
    "error: 未知命令 \{cmd}（可用：tree / style <id> / select <id> / highlight <id> / shot [--full] [路径]）\n"
  }
}

///|
/// 整数解析（style <id> 的 id 段；全数字带符号）。
fn parse_insp_int(s : String) -> Int32? {
  let t = s.trim().to_owned()
  if t.length() == 0 {
    return None
  }
  let neg = t[0] == '-'
  let body = if t[0] == '-' || t[0] == '+' {
    t[1:].to_owned()
  } else {
    t
  }
  if body.length() == 0 {
    return None
  }
  let mut v = 0
  for c in body.to_array() {
    if c < '0' || c > '9' {
      return None
    }
    v = v * 10 + (c.to_int() - '0'.to_int())
  }
  Some(if neg { -v } else { v })
}

///|
/// `tree`：整树 dump，一行一控件。首行列头（# 开头），列序
/// kind/role/name/id/parent/x/y/w/h/state/value/text/enabled。
/// 默认组件视图（每个模板标签一行），`full` 全量（组件内部实现件也在）。
pub fn insp_tree_dump(full~ : Bool = false) -> String {
  let sb = StringBuilder()
  sb.write_string(
    "#kind\trole\tname\tid\tparent\tx\ty\tw\th\tstate\tvalue\ttext\tenabled\n",
  )
  for n in insp_tree_snapshot(full~) {
    sb.write_string(n.kind)
    sb.write_string("\t")
    sb.write_string(n.role)
    sb.write_string("\t")
    sb.write_string(n.name)
    sb.write_string("\t")
    sb.write_string(n.id.to_string())
    sb.write_string("\t")
    sb.write_string(n.parent.to_string())
    sb.write_string("\t")
    sb.write_string(n.x.to_string())
    sb.write_string("\t")
    sb.write_string(n.y.to_string())
    sb.write_string("\t")
    sb.write_string(n.w.to_string())
    sb.write_string("\t")
    sb.write_string(n.h.to_string())
    sb.write_string("\t")
    sb.write_string(n.state)
    sb.write_string("\t")
    sb.write_string(n.value)
    sb.write_string("\t")
    sb.write_string(n.text)
    sb.write_string("\t")
    sb.write_string(if n.enabled { "1" } else { "0" })
    sb.write_string("\n")
  }
  sb.to_string()
}

///|
/// `style <id>`：按 id 现取生效样式读数，五字段与样式编辑器对齐
/// （背景/文字/边框色/边框宽/圆角），读数走 `insp_field_get` 口径。
/// id 不在当前树快照里回 error 行。
pub fn insp_style_dump(id : Int32) -> String {
  let mut found = false
  // id 寻址不看视图档：组件视图藏掉的内部件同样能读样式
  for n in insp_tree_snapshot(full=true) {
    if n.id == id {
      found = true
    }
  }
  if !found {
    return "error: id \{id} 不在当前树快照\n"
  }
  let st = @style.resolved_by_id(id)
  let sb = StringBuilder()
  sb.write_string("#field\tvalue\n")
  // 编辑器口径的五字段在前（名字稳定，GUI 样式面板与旧消费方依赖）
  let names = ["background", "color", "border_color", "border_width", "border_radius"]
  for i = 0; i < 5; i = i + 1 {
    sb.write_string(names[i])
    sb.write_string("\t")
    sb.write_string(insp_field_get(st, i))
    sb.write_string("\n")
  }
  // 全量已设字段（带分组前缀，字段名看名知组）
  for kv in insp_style_all(st) {
    sb.write_string(kv.0)
    sb.write_string("\t")
    sb.write_string(kv.1)
    sb.write_string("\n")
  }
  sb.to_string()
}

///|
/// `select <id>`：一次往返完成「样式读数 + 目标高亮」——GUI 检查器点行
/// 专用（省一次往返）；高亮失败不影响读数返回（无上屏帧等场景仍能看样式）。
pub fn insp_select_dump(id : Int32) -> String {
  let s = insp_style_dump(id)
  if s.has_prefix("error:") {
    return s
  }
  let _ = insp_highlight(id)
  s
}

///|
/// `shot [--full] [路径]`：位图落盘 PNG（`png_write_bitmap`），二进制不过
/// 管道。缺省档取最近上屏帧（视口所见）；`--full` 档对页面滚动容器的内容
/// 按全内容高重画（滚动截图语义，虚拟列表只含已挂载行）。不带路径写
/// `$TMPDIR/mng-shot-<窗题>-<毫秒时间戳>.png`（full 档文件名带 `-full`）。
/// 回执一行带实际路径；full 档因尺寸上限截断时追加一行注明。
pub fn insp_shot(path : String?, full : Bool) -> String {
  let (frame_bm, title) = @widget.last_frame_bitmap()
  let (bm, clipped) = if full {
    match @widget.last_frame_root() {
      Some(root) =>
        match @widget.paint_full_page(root) {
          (Some(b), c) => (Some(b), c)
          (None, _) => {
            // 页内没有滚动容器：没有「整页」可言，如实报错让调用方改 shot
            return "error: 页内无滚动容器（无整页可截），改用 shot 截视口帧\n"
          }
        }
      None => (None, false)
    }
  } else {
    (frame_bm, false)
  }
  match bm {
    None => "error: 尚无上屏帧\n"
    Some(b) => {
      let p = match path {
        Some(p) if p != "" => p
        _ => {
          let dir = match @env.get_env_var("TMPDIR") {
            Some(t) if t != "" => t
            _ => "/tmp"
          }
          let ts = @win.now_ms()
          let tag = if full { "mng-shot-full-" } else { "mng-shot-" }
          "\{insp_strip_trailing_slash(dir)}/\{tag}\{insp_file_slug(title)}-\{ts}.png"
        }
      }
      if @render.png_write_bitmap(b, p) {
        if clipped {
          "ok \{p}\n# 注：内容超出 \{b.width}×\{b.height} 上限，已截断\n"
        } else {
          "ok \{p}\n"
        }
      } else {
        "error: 写不出 \{p}\n"
      }
    }
  }
}

// ---- 选中高亮（在目标应用上画框） ----

///|
/// 高亮框控件（进程级一个）：挂在最近帧根上、命中穿透、不占布局。
let g_insp_hl_widget : Ref[@widget.Widget?] = Ref(None)

///|
/// 当前高亮目标控件 id（0 = 不高亮）。
let g_insp_hl_target : Ref[Int32] = Ref(0)

///|
/// 上一次摆放的矩形：没变不重设不重绘（高亮跟随的每拍零成本——目标应用
/// 开着高亮不被强制按帧重画）。
let g_insp_hl_rect : Ref[(Double, Double, Double, Double)] = Ref(
  (0.0, 0.0, 0.0, 0.0),
)

///|
/// 建高亮框（首次）并挂到根控件末尾（最后画、盖在内容与浮层上）。
fn insp_highlight_ensure(root : @widget.Widget) -> @widget.Widget {
  match g_insp_hl_widget.val {
    Some(w) => w
    None => {
      let w = @widget.Widget::new()
      w.kind = "InspectorHighlight"
      w.hit_pass_through = true // 不参与命中与语义树：纯展示覆盖层
      w.node.set_position(@yoga.Absolute)
      w.node.set_left(@yoga.fixed(0.0))
      w.node.set_top(@yoga.fixed(0.0))
      w.node.set_width(@yoga.fixed(0.0))
      w.node.set_height(@yoga.fixed(0.0))
      w.visible = false
      // Chrome DevTools 同款观感：淡蓝半透明填充 + 2px 实线描边
      w.on_draw = Some(fn(
        _self : @widget.Widget,
        p : @render.Painter,
        r : @base.Rect,
      ) -> Unit {
        p.set_fill_color("#1A73E840")
        p.fill_rect(0.0, 0.0, r.w, r.h)
        p.set_stroke_color("#1A73E8")
        p.set_line_width(2.0)
        p.stroke_rect(1.0, 1.0, (r.w - 2.0).max(0.0), (r.h - 2.0).max(0.0))
      })
      root.append_child(w)
      g_insp_hl_widget.val = Some(w)
      w
    }
  }
}

///|
/// 把高亮框摆到目标控件矩形上（root 原点即窗口原点，直接用绝对矩形）。
/// 矩形没变时零操作：每拍重定位不会让目标应用反复重绘。
fn insp_highlight_place(root : @widget.Widget, id : Int32) -> Bool {
  match root.by_id(id) {
    Some(t) => {
      let w = insp_highlight_ensure(root)
      let r = (t.rect.x, t.rect.y, t.rect.w, t.rect.h)
      let prev = g_insp_hl_rect.val
      let moved = r.0 != prev.0 ||
        r.1 != prev.1 ||
        r.2 != prev.2 ||
        r.3 != prev.3
      if moved || !w.visible {
        w.node.set_left(@yoga.fixed(r.0))
        w.node.set_top(@yoga.fixed(r.1))
        w.node.set_width(@yoga.fixed(r.2))
        w.node.set_height(@yoga.fixed(r.3))
        if !w.visible {
          w.visible = true
        }
        g_insp_hl_rect.val = r
        @widget.invalidate()
      }
      true
    }
    None => false
  }
}

///|
/// `highlight <id>`：在目标应用上高亮某控件（id <= 0 取消）。目标不在当前
/// 树快照里回 error。
pub fn insp_highlight(id : Int32) -> String {
  if id <= 0 {
    g_insp_hl_target.val = 0
    match g_insp_hl_widget.val {
      Some(w) => {
        w.visible = false
        @widget.invalidate()
      }
      None => ()
    }
    return "ok highlight off\n"
  }
  // 先核目标在树里（全量口径：内部件同样可高亮）
  let mut found = false
  for n in insp_tree_snapshot(full=true) {
    if n.id == id {
      found = true
    }
  }
  if !found {
    return "error: id \{id} 不在当前树快照\n"
  }
  match @widget.last_frame_root() {
    Some(root) => {
      if insp_highlight_place(root, id) {
        g_insp_hl_target.val = id
        "ok highlight \{id}\n"
      } else {
        "error: id \{id} 不在当前控件树\n"
      }
    }
    None => "error: 尚无上屏帧\n"
  }
}

///|
/// 每拍重定位：目标控件的布局会随内容/窗口变化，高亮框跟着走；目标消失
/// 则取消。没高亮时零操作。
fn insp_highlight_tick() -> Unit {
  let id = g_insp_hl_target.val
  if id <= 0 {
    return
  }
  match @widget.last_frame_root() {
    Some(root) =>
      if !insp_highlight_place(root, id) {
        g_insp_hl_target.val = 0
        match g_insp_hl_widget.val {
          Some(w) => {
            w.visible = false
            @widget.invalidate()
          }
          None => ()
        }
      }
    None => ()
  }
}
