// 检查器模式（--inspect）：仿 Chrome DevTools 的独立检查器窗。
// 数据全走 @insp 连应用内检查服务：异步客户端（工作线程收发）+ 50ms 轻拍
// 状态机——单在途请求，点行发 `select <id>`（样式读数 + 高亮一次往返），
// 树每秒拉一次且没变不重建表。mng 侧的 `mng inspect --gui` 经 hop 进本
// 模式，本进程链 GUI 库、mng 本体不链。

///|
/// 一行树数据（与服务端 tree 命令的 13 列一一对应）。
struct InspRow {
  kind : String
  role : String
  name : String
  id : Int32
  parent : Int32
  x : Double
  y : Double
  w : Double
  h : Double
  state : String
  value : String
  text : String
  enabled : Bool
}

///|
/// 检查器页状态（静态树 + Store 驱动刷新）。
/// 取数是异步的：定时器每拍只推进状态机，socket 等待在工作线程里，
/// 界面线程从不阻塞在收发上。
struct InspPage {
  app_id : String
  rows : @base.Store[Array[@ui.TableRow]]
  sel : @base.Store[Array[Int32]]
  /// 选中行详情（desc 列表项；选中即本地出，不等网络）
  detail : @base.Store[Array[(String, String)]]
  styles : @base.Store[String]
  status : @base.Store[String]
  /// 树视图档：false 组件视图（每个模板标签一行）/ true 全量（组件内部实现件也在）
  full : @base.Store[Bool]
  mut last_rows : Array[InspRow]
  /// 上一份 tree 响应原文：没变不重建表（避免每秒整表重排）
  mut last_tree_text : String
  /// 当前选中控件 id（按 id 保位；树行下标会随增删挪动）
  mut cur_id : Int32
  /// 在途请求：0 空闲 / 1 tree / 2 样式（select 或 style）
  mut busy : Int32
  /// 待发起的选中控件 id（0 = 无）
  mut want_select : Int32
  /// 距上次树刷新的拍数
  mut tick_tree : Int
  /// 距上次选中样式重读的拍数
  mut tick_style : Int
  /// 最近一次发出的树视图档（切换后强制重拉）
  mut tree_full_sent : Bool
}

///|
/// 整数解析（id 列；失败给 0）。
fn insp_p_int(s : String) -> Int32 {
  let mut v = 0
  let mut neg = false
  let mut i = 0
  for c in s.to_array() {
    if i == 0 && c == '-' {
      neg = true
    } else if c >= '0' && c <= '9' {
      v = v * 10 + (c.to_int() - '0'.to_int())
    }
    i += 1
  }
  if neg {
    -v
  } else {
    v
  }
}

///|
/// 浮点解析（矩形列；负号/整数/小数三档，其余字符忽略）。
fn insp_p_double(s : String) -> Double {
  let t = s.trim().to_owned()
  let mut i = 0
  let mut neg = false
  let mut whole = 0.0
  let mut frac = 0.0
  let mut scale = 1.0
  let mut in_frac = false
  for c in t.to_array() {
    if i == 0 && c == '-' {
      neg = true
    } else if c == '.' {
      in_frac = true
    } else if c >= '0' && c <= '9' {
      let d = (c.to_int() - '0'.to_int()).to_double()
      if in_frac {
        scale = scale * 10.0
        frac = frac + d / scale
      } else {
        whole = whole * 10.0 + d
      }
    }
    i += 1
  }
  let r = whole + frac
  if neg {
    -r
  } else {
    r
  }
}

///|
/// 按 `\n` 切行（跳过空行）。
fn insp_lines(s : String) -> Array[String] {
  let out : Array[String] = []
  for line in s.split("\n") {
    let l = line.trim().to_owned()
    if l.length() > 0 {
      out.push(l)
    }
  }
  out
}

///|
/// 按 `\t` 切字段。
fn insp_tabs(s : String) -> Array[String] {
  let out : Array[String] = []
  for p in s.split("\t") {
    out.push(p.to_owned())
  }
  out
}

///|
/// 解析 tree 响应（首行 # 列头跳过；列序
/// kind/role/name/id/parent/x/y/w/h/state/value/text/enabled）。
fn insp_parse_tree(s : String) -> Array[InspRow] {
  let out : Array[InspRow] = []
  for line in insp_lines(s) {
    if line.has_prefix("#") {
      continue
    }
    let f = insp_tabs(line)
    if f.length() < 13 {
      continue
    }
    out.push({
      kind: f[0],
      role: f[1],
      name: f[2],
      id: insp_p_int(f[3]),
      parent: insp_p_int(f[4]),
      x: insp_p_double(f[5]),
      y: insp_p_double(f[6]),
      w: insp_p_double(f[7]),
      h: insp_p_double(f[8]),
      state: f[9],
      value: f[10],
      text: f[11],
      enabled: f[12] == "1",
    })
  }
  out
}

///|
/// 按父链算每行深度（父不在表里视作根；有环防护按表长截断）。
fn insp_depths(rows : Array[InspRow]) -> Array[Int32] {
  let n = rows.length()
  let idx : Map[Int32, Int32] = Map([])
  let mut i = 0
  while i < n {
    idx[rows[i].id] = i
    i += 1
  }
  let out : Array[Int32] = []
  let mut k = 0
  while k < n {
    let mut d = 0
    let mut cur = rows[k].parent
    let mut steps = 0
    while steps < n {
      match idx.get(cur) {
        Some(pi) if pi != k => {
          d += 1
          cur = rows[pi].parent
          steps += 1
        }
        _ => steps = n
      }
    }
    out.push(d)
    k += 1
  }
  out
}

///|
/// 树列行文本：缩进 + 类型名（空省略）+ 角色 + 「名」+ #id。
fn insp_row_label(r : InspRow, depth : Int32) -> String {
  let b = StringBuilder()
  let mut i = 0
  while i < depth {
    b.write_string("  ")
    i += 1
  }
  if r.kind.length() > 0 {
    b.write_string(r.kind)
    b.write_string("·")
  }
  b.write_string(r.role)
  if r.name.length() > 0 {
    b.write_string("「")
    b.write_string(r.name)
    b.write_string("」")
  }
  b.write_string(" #")
  b.write_string(r.id.to_string())
  b.to_string()
}

///|
/// 树表行（列：控件 / id）。
fn insp_table_rows(rows : Array[InspRow]) -> Array[@ui.TableRow] {
  let depths = insp_depths(rows)
  let out : Array[@ui.TableRow] = []
  let mut i = 0
  while i < rows.length() {
    out.push(
      @ui.TableRow::make([
        insp_row_label(rows[i], depths[i]),
        rows[i].id.to_string(),
      ]),
    )
    i += 1
  }
  out
}

///|
/// 选中行详情读数（desc 列表项：标签 + 值）。
fn insp_detail_items(r : InspRow) -> Array[(String, String)] {
  [
    ("id", r.id.to_string()),
    ("parent", r.parent.to_string()),
    ("kind", if r.kind.length() > 0 { r.kind } else { "(无)" }),
    ("role", r.role),
    ("name", if r.name.length() > 0 { r.name } else { "(空)" }),
    ("enabled", if r.enabled { "是" } else { "否" }),
    ("state", if r.state.length() > 0 { r.state } else { "(无)" }),
    ("value", if r.value.length() > 0 { r.value } else { "(无)" }),
    ("text", if r.text.length() > 0 { r.text } else { "(无)" }),
    (
      "rect",
      "\{r.x.round().to_int()},\{r.y.round().to_int()} \{r.w.round().to_int()}×\{r.h.round().to_int()}",
    ),
  ]
}

///|
/// 样式字段分组名（字段名点分前缀 → 组标题）。
fn insp_group_of(field : String) -> String {
  let mut pre = ""
  for part in field.split(".") {
    pre = part.to_owned()
    break
  }
  match pre {
    "text" => "文字"
    "box" => "尺寸"
    "edge" => "内外边距"
    "border" => "边框圆角"
    "flex" => "布局"
    "pos" => "定位层级"
    _ => "其它"
  }
}

///|
/// 解析 style 响应（`field\tvalue` 行；# 列头跳过）。
fn insp_parse_style(s : String) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  for line in insp_lines(s) {
    if line.has_prefix("#") {
      continue
    }
    let f = insp_tabs(line)
    if f.length() >= 2 {
      out.push((f[0], f[1]))
    }
  }
  out
}

///|
/// 样式全量文本：编辑器五字段在前，其余按组归档（组标题行 + 缩进行）。
fn insp_style_text(s : String) -> String {
  let fields = insp_parse_style(s)
  let b = StringBuilder()
  b.write_string("样式（编辑器五字段）\n")
  let five = [
    "background", "color", "border_color", "border_width", "border_radius",
  ]
  for f in fields {
    if five.contains(f.0) {
      b.write_string("  \{f.0} = \{f.1}\n")
    }
  }
  let groups = ["文字", "尺寸", "内外边距", "边框圆角", "布局", "定位层级", "其它"]
  for g in groups {
    let mut head = false
    for f in fields {
      if five.contains(f.0) {
        continue
      }
      if insp_group_of(f.0) == g {
        if !head {
          b.write_string(g + "\n")
          head = true
        }
        b.write_string("  \{f.0} = \{f.1}\n")
      }
    }
  }
  b.to_string()
}

///|
/// 发命令收响应（短超时：只用于开窗/关窗这类一次性收尾）。
fn insp_call_short(app_id : String, req : String) -> Result[String, String] {
  @insp.call(app_id, req, timeout_ms=1500)
}

///|
/// 轮询节拍（毫秒）：每拍只查完成标记与发起下一条，不做阻塞 I/O。
const INSP_TICK_MS : Int = 50

///|
/// 树刷新周期（拍数）：50ms × 20 ≈ 1s。
const INSP_TREE_TICKS : Int = 20

///|
/// 选中样式重读周期（拍数）：≈1s（样式实时读数，不附带高亮重发）。
const INSP_STYLE_TICKS : Int = 20

///|
/// 按控件 id 找行下标（树增删后选中按 id 保位）。
fn insp_find_row(rows : Array[InspRow], id : Int32) -> Int? {
  let mut i = 0
  while i < rows.length() {
    if rows[i].id == id {
      return Some(i)
    }
    i += 1
  }
  None
}

///|
/// 点一行：详情本地即时出（不等网络），样式与高亮交给状态机发一次
/// `select <id>`（服务端一次往返完成两件事）。
fn insp_select(p : InspPage, i : Int32) -> Unit {
  if i < 0 || i >= p.last_rows.length() {
    return
  }
  let row = p.last_rows[i]
  p.sel.set([i])
  p.cur_id = row.id
  p.detail.set(insp_detail_items(row))
  p.styles.set("样式读取中…")
  p.want_select = row.id
  p.tick_style = 0
}

///|
/// 应用 tree 响应：内容没变不重建表；变了按 id 保住选中（控件没了就取消）。
fn insp_apply_tree(p : InspPage, resp : String) -> Unit {
  if resp == p.last_tree_text {
    p.status.set("已连接 \{p.app_id} · 节点 \{p.last_rows.length()}")
    return
  }
  p.last_tree_text = resp
  let rows = insp_parse_tree(resp)
  p.last_rows = rows
  p.rows.set(insp_table_rows(rows))
  p.status.set("已连接 \{p.app_id} · 节点 \{rows.length()}")
  if p.cur_id != 0 {
    match insp_find_row(rows, p.cur_id) {
      Some(i) => {
        p.sel.set([i])
        p.detail.set(insp_detail_items(rows[i]))
      }
      None => {
        p.cur_id = 0
        p.sel.set([])
        p.detail.set([])
        p.styles.set("")
      }
    }
  }
}

///|
/// 应用样式响应（`select` 与 `style` 同一格式）。
fn insp_apply_style(p : InspPage, resp : String) -> Unit {
  if resp.has_prefix("error:") {
    p.styles.set(resp.trim().to_owned())
  } else {
    p.styles.set(insp_style_text(resp))
  }
}

///|
/// 状态机一拍：收在途结果 → 发起下一条（选中优先，其次到期的树/样式刷新）。
fn insp_tick(p : InspPage) -> Unit {
  if p.app_id.length() == 0 {
    return // 没应用 id：只显示用法提示，不发网络请求
  }
  // 视图档切换：清缓存并立即重拉树
  if p.full.get() != p.tree_full_sent {
    p.tree_full_sent = p.full.get()
    p.tick_tree = INSP_TREE_TICKS
    p.last_tree_text = ""
  }
  p.tick_tree += 1
  if p.cur_id != 0 {
    p.tick_style += 1
  }
  if p.busy != 0 && @insp.call_poll() {
    let kind = p.busy
    p.busy = 0
    match @insp.call_take() {
      Ok(resp) =>
        if kind == 1 {
          insp_apply_tree(p, resp)
        } else {
          insp_apply_style(p, resp)
        }
      Err(e) =>
        if kind == 1 {
          p.last_rows = []
          p.last_tree_text = ""
          p.rows.set([])
          p.status.set("未连接：" + e)
        } else {
          p.styles.set("样式读取失败：" + e)
          p.status.set("未连接：" + e)
        }
    }
  }
  if p.busy != 0 {
    return
  }
  if p.want_select != 0 {
    let id = p.want_select
    p.want_select = 0
    match @insp.call_begin(p.app_id, "select \{id}") {
      Ok(_) => p.busy = 2
      Err(e) => p.styles.set("样式读取失败：" + e)
    }
  } else if p.tick_tree >= INSP_TREE_TICKS {
    p.tick_tree = 0
    let req = if p.full.get() { "tree --full" } else { "tree" }
    match @insp.call_begin(p.app_id, req) {
      Ok(_) => p.busy = 1
      Err(e) => p.status.set("未连接：" + e)
    }
  } else if p.cur_id != 0 && p.tick_style >= INSP_STYLE_TICKS {
    p.tick_style = 0
    match @insp.call_begin(p.app_id, "style \{p.cur_id}") {
      Ok(_) => p.busy = 2
      Err(e) => p.styles.set("样式读取失败：" + e)
    }
  }
}

///|
/// 详情 desc 块：信号驱动的描述列表（标签列对齐、值列折行）。
fn insp_desc_block(
  sig : @base.Signal[Array[(String, String)]],
) -> @widget.Node {
  @widget.bind_node(sig, fn(items : Array[(String, String)]) -> @widget.Node {
    if items.length() == 0 {
      return @ui.text("点左侧一行看读数", font_size=12.0, class=[
        @style.text_secondary,
      ])
    }
    @ui.descriptions(items, label_width=64.0)
  })
}

///|
/// 多行文本 → 一行一个 text 节点（12px 次要色）。
fn insp_text_block(sig : @base.Signal[String]) -> @widget.Node {
  @widget.bind_node(sig, fn(s : String) -> @widget.Node {
    let lines : Array[@widget.Node] = []
    for t in insp_lines(s) {
      lines.push(@ui.text(t, font_size=12.0, class=[@style.text_secondary]))
    }
    @ui.view(lines, row_gap=2.0)
  })
}

///|
/// 检查器窗主入口：起窗、装 300ms 轮询泵、跑事件循环。
/// 无显示服务与向导同口径回 3（mng 侧据此提示）。
pub fn run_inspector(app_id : String) -> Unit {
  let p : InspPage = {
    app_id,
    rows: @base.Store::new([]),
    sel: @base.Store::new([]),
    detail: @base.Store::new([]),
    styles: @base.Store::new("点左侧一行看样式"),
    status: @base.Store::new(
      if app_id.length() > 0 {
        "连接中 \{app_id}…"
      } else {
        "没有应用 id——用 `mng inspect --gui --app <id>` 指定"
      },
    ),
    full: @base.Store::new(false),
    last_rows: [],
    last_tree_text: "",
    cur_id: 0,
    busy: 0,
    want_select: 0,
    tick_tree: INSP_TREE_TICKS,
    tick_style: 0,
    tree_full_sent: false,
  }
  let cols : Array[@ui.TableColumn] = [
    @ui.TableColumn::make("控件", 0.0, sortable=false),
    @ui.TableColumn::make("id", 56.0, sortable=false),
  ]
  // 树表：宽 0 = 跟分栏容器（弹性列跟宽），拖动手柄时表格跟着伸缩
  let tree_section = @ui.table_v(
    cols,
    p.rows,
    width=0.0,
    height=620.0,
    selection=p.sel,
    on_row_click=fn(i : Int32, _r : @ui.TableRow) -> Unit {
      insp_select(p, i)
    },
  )
  // 右栏：详情在上（最高占一半，不足按实际高），余下全部给样式区（滚动）
  let detail_section = @ui.view(
    [
      @ui.text("详情", class=[@style.text_heading]),
      insp_desc_block(p.detail.signal()),
    ],
    row_gap=6.0,
    handle=fn(v : @widget.Widget) -> Unit {
      v.node.set_max_height(@yoga.percent(50.0))
    },
  )
  let styles_section = @ui.scroll_view(
    [insp_text_block(p.styles.signal())],
    @ui.ScrollState::new(),
    handle=fn(v : @widget.Widget) -> Unit {
      v.node.set_flex_grow(1.0)
      v.node.set_min_height(@yoga.fixed(0.0))
    },
  )
  let right_section = @ui.col(
    [
      detail_section,
      @ui.divider(),
      @ui.text("样式", class=[@style.text_heading]),
      styles_section,
    ],
    row_gap=8.0,
    grow=1.0,
  )
  let toolbar = @ui.row(
    [
      @ui.switch(
        p.full,
        on_text="内部实现",
        off_text="内部实现",
      ),
      @ui.bind_label(p.status, fn(s) { s }),
    ],
    column_gap=12.0,
  )
  let root = @ui.col(
    [
      toolbar,
      @ui.divider(),
      // 左树右详情：表格两份、详情一份，手柄可拖
      @ui.split(
        tree_section,
        right_section,
        ratio=2.0 / 3.0,
        min_first=320.0,
        min_second=320.0,
      ),
    ],
    padding=16.0,
    row_gap=10.0,
    grow=1.0,
  )
  let mounted = @ui.mount_window(
    [root],
    title=if app_id.length() > 0 {
      "mng 检查器 — " + app_id
    } else {
      "mng 检查器"
    },
    width=1080,
    height=720,
    handle=fn(h : @widget.WindowHost) {
      let tick : Ref[() -> Unit] = Ref(fn() { () })
      tick.val = fn() -> Unit {
        insp_tick(p)
        let _ = h.timer(INSP_TICK_MS, tick.val)
      }
      // 首拍立即拉一次（不等一拍）
      insp_tick(p)
      let _ = h.timer(INSP_TICK_MS, tick.val)
    },
  )
  match mounted {
    None => {
      println("mngui: 本平台无窗口后端或无显示服务")
      @sys.exit(3)
    }
    Some(host) => {
      host.run()
      // 关窗前收掉在途请求，再取消目标应用上的高亮（尽力而为）
      @insp.call_abort()
      let _ = insp_call_short(app_id, "highlight 0")
    }
  }
}
