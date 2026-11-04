// Linux AT-SPI 桥（无障碍阶段 2）：把帧尾语义快照导出成 AT-SPI 对象树，
// 让 Orca 等读屏经 D-Bus 查询本应用的界面。
//
// 链路（at-spi2-core 2.52 实测口径，见 experience/adaptation.md）：
//   ① 会话总线 org.a11y.Bus.GetAddress 取 a11y 总线地址（回落
//      AT_SPI_BUS_ADDRESS 环境变量、再回落 $XDG_RUNTIME_DIR/at-spi/bus）；
//   ② 连 a11y 总线（dbus 包第三条连接，bus=2）；
//   ③ org.a11y.atspi.Socket.Embed((本端唯一名, /org/a11y/atspi/accessible/root))
//      向 registryd 注册——registry 随即将本端挂上它的根、广播
//      ChildrenChanged，并给本端发 Properties.Set(Application, Id)；
//   ④ 对象树：应用根 /org/a11y/atspi/accessible/root（role application）→
//      窗口根 /org/a11y/atspi/accessible/win（快照里 parent==0 那行）→
//      控件 /org/a11y/atspi/accessible/win/<widget id>（快照行按 id 稳态
//      寻址，不做递增编号——编号每帧重排会让客户端缓存的身份抖动）；
//   ⑤ 接口：Accessible + Component 全体挂，Text（文本件）/Value（滑杆进度）
//      /Action（可点击件）按角色挂；事件经广播信号上行（ChildrenChanged /
//      Focus / StateChanged，监听方按 match 规则收，与 GTK 桥同形态）。
//
// 数据源是 @win 的语义快照通道（wm_a11y_row_tsv，与发布侧同一份 TSV）——
// 本包不依赖 widget 层；动作侧（DoAction）压「点一下」进跨平台动作队列
// （@win.a11y_action_push，与 Windows UIA 的 Invoke、macOS AX 的 press 同
// 一条队列），由 widget 层每帧抽走合成指针点击。
//
// 无 a11y 总线（Windows/macOS/无 at-spi 的会话）时启动即失败并按背间隔
// 重试——不崩、不假成功；读屏查询走宿主每帧的 atspi_tick 泵。总线断线
// 自愈重建后唯一名会变，tick 核对不符即重新 Embed（registry 挂旧名=读屏
// 静默丢失）。

///|
/// AT-SPI 桥的一行快照（从 @win 的 TSV 通道解析；字段序与发布侧一致）。
pub(all) struct AtspiNode {
  id : Int
  parent : Int
  enabled : Bool
  role : String
  name : String
  state : String
  value : String
  text : String
  x : Double
  y : Double
  w : Double
  h : Double
}

///|
/// 有符号十进制整数（"-1" → -1；空串或含非数字 None）。
fn atspi_parse_int(s : String) -> Int? {
  if s == "" {
    return None
  }
  let mut v = 0
  let mut k = 0
  let mut neg = false
  match s.get_char(0) {
    Some('-') => {
      neg = true
      k = 1
      if s.length() == 1 {
        return None
      }
    }
    _ => ()
  }
  while k < s.length() {
    match s.get_char(k) {
      Some(c) =>
        if c < '0' || c > '9' {
          return None
        } else {
          v = v * 10 + (c.to_int() - 48)
        }
      None => return None
    }
    k = k + 1
  }
  if neg {
    Some(-v)
  } else {
    Some(v)
  }
}

///|
/// 十进制小数（"-1.5" → -1.5；解析不了 None）。认科学计数法——C 侧
/// `%.10g` 对大/小值就产出 `1e+300` / `1e-05` 形态，不认整行会被读屏树
/// 静默丢弃。
fn atspi_parse_double(s : String) -> Double? {
  if s == "" {
    return None
  }
  let mut v = 0.0
  let mut frac = 0.0
  let mut scale = 1.0
  let mut k = 0
  let mut neg = false
  let mut seen_digit = false
  let mut in_frac = false
  match s.get_char(0) {
    Some('-') => {
      neg = true
      k = 1
    }
    _ => ()
  }
  // 尾数（整数位 + 小数位）；遇 e/E Break 进指数段
  while k < s.length() {
    match s.get_char(k) {
      Some(c) =>
        if c >= '0' && c <= '9' {
          seen_digit = true
          if in_frac {
            frac = frac * 10.0 + (c.to_int() - 48).to_double()
            scale = scale * 10.0
          } else {
            v = v * 10.0 + (c.to_int() - 48).to_double()
          }
        } else if c == '.' && !in_frac {
          in_frac = true
        } else if (c == 'e' || c == 'E') && seen_digit {
          break
        } else {
          return None
        }
      None => return None
    }
    k = k + 1
  }
  if !seen_digit {
    return None
  }
  let mut out = if frac > 0.0 {
    v + frac / scale
  } else {
    v
  }
  // 指数段（k 停在 e/E 上）：带符号十进制，按位乘除 10（%.10g 的指数范围
  // 内够用，且不引数学依赖）
  if k < s.length() {
    let mut e = 0
    let mut eneg = false
    k = k + 1
    match s.get_char(k) {
      Some('-') => {
        eneg = true
        k = k + 1
      }
      Some('+') => {
        k = k + 1
      }
      _ => ()
    }
    let mut eseen = false
    while k < s.length() {
      match s.get_char(k) {
        Some(c) =>
          if c >= '0' && c <= '9' {
            eseen = true
            e = e * 10 + (c.to_int() - 48)
          } else {
            return None
          }
        None => return None
      }
      k = k + 1
    }
    if !eseen {
      return None
    }
    let mut i = 0
    while i < e {
      if eneg {
        out = out / 10.0
      } else {
        out = out * 10.0
      }
      i = i + 1
    }
  }
  if neg {
    Some(-out)
  } else {
    Some(out)
  }
}

///|
/// 解析一行快照 TSV（字段序：id/parent/enabled/role/name/state/value/text/
/// x/y/w/h，制表符分隔）。字段不够或数字解析失败给 None。
pub fn atspi_row_parse(tsv : String) -> AtspiNode? {
  let f : Array[String] = []
  for part in tsv.split("\t") {
    f.push(part.to_owned())
  }
  if f.length() < 12 {
    return None
  }
  match (
    atspi_parse_int(f[0]),
    atspi_parse_int(f[1]),
    atspi_parse_int(f[2]),
    atspi_parse_double(f[8]),
    atspi_parse_double(f[9]),
    atspi_parse_double(f[10]),
    atspi_parse_double(f[11]),
  ) {
    (Some(id), Some(parent), Some(en), Some(x), Some(y), Some(w), Some(h)) =>
      Some({
        id,
        parent,
        enabled: en != 0,
        role: f[3],
        name: f[4],
        state: f[5],
        value: f[6],
        text: f[7],
        x,
        y,
        w,
        h,
      })
    _ => None
  }
}

///|
/// 应用根对象路径（AT-SPI 约定：每应用在自己的连接上把根挂在这里）。
pub const ATSPI_ROOT_PATH : String = "/org/a11y/atspi/accessible/root"

///|
/// 窗口根对象路径（快照里 parent==0 的那行）。
pub const ATSPI_WIN_PATH : String = "/org/a11y/atspi/accessible/win"

///|
/// 控件对象路径（按 widget id 稳态寻址）。
pub fn atspi_widget_path(id : Int) -> String {
  "\{ATSPI_WIN_PATH}/\{id}"
}

///|
/// 快照行里窗口根（parent==0）。
fn atspi_window_row(rows : Array[AtspiNode]) -> AtspiNode? {
  for r in rows {
    if r.parent == 0 {
      return Some(r)
    }
  }
  None
}

///|
/// 按 id 找快照行。
fn atspi_row_by_id(rows : Array[AtspiNode], id : Int) -> AtspiNode? {
  for r in rows {
    if r.id == id {
      return Some(r)
    }
  }
  None
}

///|
/// parent 的直接子行（按快照序）。
fn atspi_children_of(rows : Array[AtspiNode], parent : Int) -> Array[AtspiNode] {
  let out : Array[AtspiNode] = []
  for r in rows {
    if r.parent == parent {
      out.push(r)
    }
  }
  out
}

// ---- 角色 / 状态 / 接口映射（枚举值取自 Atspi-2.0.gir 的 AtspiRole /
// AtspiStateType，at-spi2-core 2.52 实物核对）----

///|
/// 库内 role 串 → AtspiRole 枚举值（未登记的面板容器给 panel）。
pub fn atspi_role_of(role : String) -> Int {
  match role {
    "button" => 43 // push_button
    "checkbox" => 7 // check_box
    "radio" => 44 // radio_button
    "switch" => 7 // check_box（与 UIA/AX 两桥同口径）
    "slider" => 51 // slider
    "stepper" => 52 // spin_button
    "text_input" => 61 // text（单行编辑；Text 接口承载内容）
    "text_area" => 61 // text（多行由 multi_line 状态位表达）
    "select" => 11 // combo_box
    "progress" => 42 // progress_bar
    "text" => 61 // text
    "heading" => 83 // heading
    "link" => 88 // link
    "image" => 27 // image
    "tab" => 37 // page_tab
    "menuitem" => 35 // menu_item
    "date_picker" => 12 // date_editor
    "color_picker" => 9 // color_chooser
    "rate" => 114 // rating
    "window" => 23 // frame
    "group" => 99 // grouping
    _ => 39 // panel
  }
}

///|
/// 角色名（读屏朗读用；未登记给 panel）。
pub fn atspi_role_name_of(role : String) -> String {
  match role {
    "button" => "push button"
    "checkbox" | "switch" => "check box"
    "radio" => "radio button"
    "slider" => "slider"
    "stepper" => "spin button"
    "text_input" | "text_area" | "text" => "text"
    "select" => "combo box"
    "progress" => "progress bar"
    "heading" => "heading"
    "link" => "link"
    "image" => "image"
    "tab" => "page tab"
    "menuitem" => "menu item"
    "date_picker" => "date editor"
    "color_picker" => "color chooser"
    "rate" => "rating"
    "window" => "frame"
    "group" => "grouping"
    _ => "panel"
  }
}

///|
/// AtspiStateType 状态位集合（au）：快照行 + 焦点 id → 状态数组。
pub fn atspi_states_of(n : AtspiNode, focus_id : Int) -> Array[Int] {
  let st : Array[Int] = []
  st.push(25) // showing（快照只收可见行）
  st.push(30) // visible
  if n.enabled {
    st.push(8) // enabled
    st.push(24) // sensitive
  }
  if focus_id > 0 && n.id == focus_id {
    st.push(12) // focused
  }
  if n.state == "checked" {
    st.push(4) // checked
  }
  if n.state == "read_only" {
    st.push(43) // read_only
  }
  if n.role == "text_area" {
    st.push(17) // multi_line
  }
  if n.role == "select" {
    st.push(42) // has_popup
  }
  if (n.role == "text_input" || n.role == "text_area") && n.state != "read_only" {
    st.push(7) // editable
  }
  st
}

///|
/// 该行挂哪些接口（GetInterfaces 的答案；Accessible/Component 全体有）。
pub fn atspi_ifaces_of(n : AtspiNode) -> Array[String] {
  let ifs : Array[String] = [
    "org.a11y.atspi.Accessible",
    "org.a11y.atspi.Component",
  ]
  if n.role == "text" || n.role == "text_input" || n.role == "text_area" {
    ifs.push("org.a11y.atspi.Text")
  }
  if n.role == "slider" || n.role == "stepper" || n.role == "progress" {
    ifs.push("org.a11y.atspi.Value")
  }
  if
    n.role == "button" || n.role == "link" || n.role == "menuitem" ||
    n.role == "checkbox" ||
    n.role == "switch" ||
    n.role == "radio" ||
    n.role == "tab" ||
    n.role == "select" {
    ifs.push("org.a11y.atspi.Action")
  }
  ifs
}

///|
/// 百分比值串（"50%" / "50"）→ 数值；解析不了 0。
pub fn atspi_pct(s : String) -> Double {
  let mut v = 0.0
  let mut seen = false
  for c in s {
    if c >= '0' && c <= '9' {
      v = v * 10.0 + (c.to_int() - 48).to_double()
      seen = true
    } else if c == '.' {
      continue
    } else if seen {
      break
    }
  }
  v
}

// ---- 生命周期 ----

///|
/// 桥状态：未启动 / 已连 / 暂时不可用（背间隔重试）。
priv enum AtspiState {
  AtspiIdle
  AtspiLive
  AtspiDown
}

let g_atspi_state : Ref[AtspiState] = Ref(AtspiIdle)
let g_atspi_retry : Ref[Int] = Ref(0)
let g_atspi_name : Ref[String] = Ref("")
let g_atspi_last_rows : Ref[Array[AtspiNode]] = Ref([])
let g_atspi_last_digest : Ref[String] = Ref("")
let g_atspi_last_focus : Ref[Int] = Ref(0)
let g_atspi_handler_on : Ref[Bool] = Ref(false)

///|
/// 连接活性判据（纯函数）：Embed 时记下的唯一名与当前不一致、或连接不在，
/// 就该重新走注册。dbus 包对 bus=2 断线自愈重建后本端唯一名会变，而
/// registry 里挂的还是旧名——不重Embed 读屏静默丢失，atspi_alive() 还报
/// true（状态说谎比重启更糟）。
fn atspi_needs_reembed(stored : String, now : String, alive : Bool) -> Bool {
  !alive || now == "" || now != stored
}

///|
/// 解析 a11y 总线地址（DBUS_SESSION_BUS_ADDRESS 同款 unix:path= 形态）；
/// 不是 unix:path 给 None。
fn atspi_parse_addr(addr : String) -> String? {
  for part in addr.split(",") {
    let t = part.to_owned()
    if t.has_prefix("unix:path=") {
      return Some(t[10:].to_owned())
    }
  }
  None
}

///|
/// 取 a11y 总线 socket 路径：会话总线 GetAddress 优先，回落环境变量，
/// 再回落 XDG_RUNTIME_DIR/at-spi/bus。
fn atspi_bus_path() -> String? {
  match
    @dbus.gdbus_call_session(
      "org.a11y.Bus",
      "/org/a11y/bus",
      "org.a11y.Bus",
      "GetAddress",
      [],
    ) {
    Ok(@dbus.GVString(addr)) =>
      match atspi_parse_addr(addr) {
        Some(p) => Some(p)
        None => atspi_bus_path_fallback()
      }
    _ => atspi_bus_path_fallback()
  }
}

///|
fn atspi_bus_path_fallback() -> String? {
  match @env.get_env_var("AT_SPI_BUS_ADDRESS") {
    Some(a) =>
      match atspi_parse_addr(a) {
        Some(p) => Some(p)
        None => None
      }
    None =>
      match @env.get_env_var("XDG_RUNTIME_DIR") {
        Some(dir) => Some(dir + "/at-spi/bus")
        None => None
      }
  }
}

///|
/// 启动：连 a11y 总线 + Socket.Embed 注册。任一步失败即整体失败（调用方
/// 按背间隔重试）。已启动时幂等。
pub fn atspi_start() -> Result[Unit, String] {
  if g_atspi_state.val is AtspiLive {
    return Ok(())
  }
  let path = match atspi_bus_path() {
    Some(p) => p
    None => return Err("找不到 a11y 总线地址（无 at-spi 会话？）")
  }
  match @dbus.dbus_connect_a11y(path) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let mine = @dbus.dbus_a11y_unique_name()
  if mine == "" {
    return Err("a11y 总线连上但取不到本端唯一名")
  }
  // Embed：plug = 本端根引用；registry 随即将我们挂上它的根
  match
    @dbus.gdbus_call_a11y(
      "org.a11y.atspi.Registry",
      ATSPI_ROOT_PATH,
      "org.a11y.atspi.Socket",
      "Embed",
      [
        @dbus.GVStruct([
          @dbus.GVString(mine),
          @dbus.GVPath(ATSPI_ROOT_PATH),
        ]),
      ],
    ) {
    Ok(_) => ()
    Err(e) => return Err("Socket.Embed 失败: \{e.name} \{e.message}")
  }
  atspi_install_handler()
  g_atspi_name.val = mine
  // 重新 Embed 后让下一拍重发一次 ChildrenChanged：registry 虽会因 Embed
  // 广播，本端也补发保证客户端刷新（digest 置空即触发）。
  g_atspi_last_digest.val = ""
  g_atspi_state.val = AtspiLive
  g_atspi_retry.val = 0
  Ok(())
}

///|
/// 装入站调用处理者（只装一次）：AT-SPI 查询全过这里应答。
fn atspi_install_handler() -> Unit {
  if g_atspi_handler_on.val {
    return
  }
  g_atspi_handler_on.val = true
  @dbus.dbus_set_call_handler(fn(req : @dbus.CallReq) -> Unit {
    if !atspi_handle(req) {
      (req.reply_error)(
        "org.freedesktop.DBus.Error.UnknownMethod",
        "非 AT-SPI 对象或不支持的方法",
      )
    }
  })
}

///|
/// 桥是否活着（已注册）。
pub fn atspi_alive() -> Bool {
  g_atspi_state.val is AtspiLive
}

///|
/// 读屏查询的入站派发：认 a11y 总线（bus=2）上 /org/a11y/atspi/accessible
/// 前缀路径的方法调用与属性读；认下返回 true（已应答），否则 false。
pub fn atspi_handle(req : @dbus.CallReq) -> Bool {
  if req.bus != 2 || !req.path.has_prefix("/org/a11y/atspi/accessible") {
    return false
  }
  let rows = atspi_rows_now()
  let focus = @win.a11y_focus()
  match req.iface {
    "org.freedesktop.DBus.Properties" => atspi_props(req, rows)
    "org.a11y.atspi.Accessible" => atspi_accessible(req, rows, focus)
    "org.a11y.atspi.Component" => atspi_component(req, rows)
    "org.a11y.atspi.Text" => atspi_text(req, rows)
    "org.a11y.atspi.Action" => atspi_action(req, rows)
    "org.a11y.atspi.Application" =>
      // Application 接口只读属性（Id/ToolkitName/Version）；Id 由 registry
      // 经 Properties.Set 告知，这里不另存——查询回落 ToolkitName 即可
      match req.action {
        "GetToolkitName" => {
          (req.reply)([@dbus.GVString("native-gui")])
          true
        }
        "GetVersion" => {
          (req.reply)([@dbus.GVString("0")])
          true
        }
        "GetId" => {
          (req.reply)([@dbus.GVInt32(0)])
          true
        }
        _ => false
      }
    _ => false
  }
}

///|
/// 取当前快照行（读 @win 的 TSV 通道；解析失败的行跳过）。
fn atspi_rows_now() -> Array[AtspiNode] {
  let out : Array[AtspiNode] = []
  let n = @win.a11y_row_count()
  let mut i = 0
  while i < n {
    match @win.a11y_row_tsv(i) {
      Some(tsv) =>
        match atspi_row_parse(tsv) {
          Some(r) => out.push(r)
          None => ()
        }
      None => ()
    }
    i += 1
  }
  out
}

///|
/// 路径 → 快照行（应用根给 None——它是合成节点）。
fn atspi_row_at(rows : Array[AtspiNode], path : String) -> AtspiNode? {
  if path == ATSPI_ROOT_PATH {
    return None
  }
  if path == ATSPI_WIN_PATH {
    return atspi_window_row(rows)
  }
  let prefix = ATSPI_WIN_PATH + "/"
  if path.has_prefix(prefix) {
    match atspi_parse_int(path[prefix.length():].to_owned()) {
      Some(id) => atspi_row_by_id(rows, id)
      None => None
    }
  } else {
    None
  }
}

// ---- org.a11y.atspi.Accessible ----
//
// 属性（org.freedesktop.DBus.Properties.Get 走 atspi_props）：Name /
// Description / Parent / ChildCount / Locale / AccessibleId / HelpText；
// 方法：GetChildAtIndex / GetChildren / GetIndexInParent / GetRelationSet /
// GetRole / GetRoleName / GetLocalizedRoleName / GetState / GetAttributes /
// GetApplication / GetInterfaces。签名按 registryd 实物 introspection 核对
// （(so)=GVStruct[GVString, GVPath]，a(so)=GVArray("(so)", …)）。

///|
/// (so) 引用值（bus 名 + 对象路径）。
fn atspi_ref(bus : String, path : String) -> @dbus.GDBusValue {
  @dbus.GVStruct([@dbus.GVString(bus), @dbus.GVPath(path)])
}

///|
/// 本端在 a11y 总线上的引用（对象树里父子关系都用它）。
fn atspi_self_ref(path : String) -> @dbus.GDBusValue {
  atspi_ref(@dbus.dbus_a11y_unique_name(), path)
}

///|
/// 应用根的 Accessible 视图（合成节点：role application，唯一子行是窗口根）。
fn atspi_root_accessor(rows : Array[AtspiNode]) -> AtspiNode {
  // 应用根是合成节点：身份取窗口根行（名字/几何），id=0、parent=0
  match atspi_window_row(rows) {
    Some(w) => {
      id: 0,
      parent: 0,
      enabled: w.enabled,
      role: "window",
      name: w.name,
      state: w.state,
      value: w.value,
      text: w.text,
      x: w.x,
      y: w.y,
      w: w.w,
      h: w.h,
    }
    None => {
      id: 0,
      parent: 0,
      enabled: true,
      role: "window",
      name: "",
      state: "",
      value: "",
      text: "",
      x: 0.0,
      y: 0.0,
      w: 0.0,
      h: 0.0,
    }
  }
}

///|
fn atspi_accessible(req : @dbus.CallReq, rows : Array[AtspiNode], focus_id : Int) -> Bool {
  let is_root = req.path == ATSPI_ROOT_PATH
  let node = if is_root {
    Some(atspi_root_accessor(rows))
  } else {
    atspi_row_at(rows, req.path)
  }
  let n = match node {
    Some(x) => x
    None => return false
  }
  let kids = if is_root {
    match atspi_window_row(rows) {
      Some(w) => [w]
      None => []
    }
  } else {
    atspi_children_of(rows, n.id)
  }
  let arg = fn(i : Int) -> @dbus.GDBusValue? {
    match req.args.get(i) {
      Some(v) => Some(v)
      None => None
    }
  }
  let arg_i = fn(i : Int) -> Int? {
    match arg(i) {
      Some(@dbus.GVInt32(v)) => Some(v)
      Some(@dbus.GVUInt32(v)) => Some(v)
      _ => None
    }
  }
  match req.action {
    "GetRole" => {
      (req.reply)([@dbus.GVUInt32(if is_root { 75 } else { atspi_role_of(n.role) })])
      true
    }
    "GetRoleName" => {
      (req.reply)([@dbus.GVString(if is_root { "application" } else { atspi_role_name_of(n.role) })])
      true
    }
    "GetLocalizedRoleName" => {
      (req.reply)([@dbus.GVString(if is_root { "application" } else { atspi_role_name_of(n.role) })])
      true
    }
    "GetChildCount" => {
      (req.reply)([@dbus.GVInt32(kids.length())])
      true
    }
    "GetChildAtIndex" =>
      match arg_i(0) {
        Some(i) => {
          if i >= 0 && i < kids.length() {
            let k = kids[i]
            (req.reply)([atspi_self_ref(atspi_widget_path(k.id))])
          } else {
            (req.reply_error)(
              "org.a11y.atspi.Error.Failed",
              "子下标越界: \{i}",
            )
          }
          true
        }
        None => false
      }
    "GetChildren" => {
      let arr : Array[@dbus.GDBusValue] = []
      for k in kids {
        arr.push(atspi_self_ref(atspi_widget_path(k.id)))
      }
      (req.reply)([@dbus.GVArray("(so)", arr)])
      true
    }
    "GetIndexInParent" => {
      // 应用根是 registry 的孩子；其余按快照序在父行的子表里找
      if is_root {
        (req.reply)([@dbus.GVInt32(0)])
        return true
      }
      let sibs = atspi_children_of(rows, n.parent)
      let mut idx = -1
      for i, s in sibs {
        if s.id == n.id {
          idx = i
          break
        }
      }
      (req.reply)([@dbus.GVInt32(idx)])
      true
    }
    "GetRelationSet" => {
      (req.reply)([@dbus.GVArray("(ua(so))", [])])
      true
    }
    "GetState" => {
      let st : Array[@dbus.GDBusValue] = []
      for v in atspi_states_of(n, focus_id) {
        st.push(@dbus.GVUInt32(v))
      }
      (req.reply)([@dbus.GVArray("u", st)])
      true
    }
    "GetAttributes" => {
      (req.reply)([@dbus.GVDict((Map([]) : Map[String, @dbus.GDBusValue]))])
      true
    }
    "GetApplication" => {
      (req.reply)([atspi_self_ref(ATSPI_ROOT_PATH)])
      true
    }
    "GetInterfaces" => {
      let arr : Array[@dbus.GDBusValue] = []
      for f in atspi_ifaces_of(n) {
        arr.push(@dbus.GVString(f))
      }
      (req.reply)([@dbus.GVArray("s", arr)])
      true
    }
    _ => false
  }
}

// ---- org.a11y.atspi.Component ----
//
// Contains(i,i,u)→b；GetAccessibleAtPoint(i,i,u)→(so)；GetExtents(u)→(iiii)；
// GetPosition(u)→(i,i)；GetSize()→(i,i)；GetLayer()→u；GrabFocus()→b；
// GetAlpha()→d。坐标口径：coord_type 0=screen 1=window 2=parent——快照矩形
// 是窗口坐标，屏幕坐标 = 窗口原点（@win.a11y_window_origin，宿主每帧报）+
// 矩形；父坐标 = 矩形 − 父行矩形。GetMDIZOrder 返回 'n'（int16），本仓
// GDBusValue 无 int16 变体，如实不实现（回 UnknownMethod），不装。

///|
/// 屏幕坐标矩形（窗口原点 + 快照矩形）。
fn atspi_screen_rect(n : AtspiNode) -> (Int, Int, Int, Int) {
  let (ox, oy) = @win.a11y_window_origin()
  (
    (ox + n.x).to_int(),
    (oy + n.y).to_int(),
    n.w.to_int(),
    n.h.to_int(),
  )
}

///|
/// 按 coord_type 取矩形（0=screen 1=window 2=parent-relative）。
fn atspi_rect_for(
  rows : Array[AtspiNode],
  n : AtspiNode,
  coord : Int,
) -> (Int, Int, Int, Int) {
  match coord {
    0 => atspi_screen_rect(n)
    2 =>
      match atspi_row_by_id(rows, n.parent) {
        Some(p) => (
          (n.x - p.x).to_int(),
          (n.y - p.y).to_int(),
          n.w.to_int(),
          n.h.to_int(),
        )
        None => (n.x.to_int(), n.y.to_int(), n.w.to_int(), n.h.to_int())
      }
    _ => (n.x.to_int(), n.y.to_int(), n.w.to_int(), n.h.to_int())
  }
}

///|
/// 点是否落在行矩形里（coord_type 口径同上）。
fn atspi_contains(
  rows : Array[AtspiNode],
  n : AtspiNode,
  x : Int,
  y : Int,
  coord : Int,
) -> Bool {
  let (rx, ry, rw, rh) = atspi_rect_for(rows, n, coord)
  x >= rx && x < rx + rw && y >= ry && y < ry + rh
}

///|
fn atspi_component(req : @dbus.CallReq, rows : Array[AtspiNode]) -> Bool {
  let is_root = req.path == ATSPI_ROOT_PATH
  let node = if is_root {
    atspi_window_row(rows)
  } else {
    atspi_row_at(rows, req.path)
  }
  let n = match node {
    Some(x) => x
    None => return false
  }
  let arg_i = fn(i : Int) -> Int? {
    match req.args.get(i) {
      Some(@dbus.GVInt32(v)) => Some(v)
      Some(@dbus.GVUInt32(v)) => Some(v)
      _ => None
    }
  }
  match req.action {
    "Contains" =>
      match (arg_i(0), arg_i(1), arg_i(2)) {
        (Some(x), Some(y), Some(ct)) => {
          (req.reply)([@dbus.GVBool(atspi_contains(rows, n, x, y, ct))])
          true
        }
        _ => false
      }
    "GetAccessibleAtPoint" =>
      match (arg_i(0), arg_i(1), arg_i(2)) {
        (Some(x), Some(y), Some(ct)) => {
          // 最深命中：前序展开里最后一个包含该点的行
          let mut best : AtspiNode? = None
          for r in rows {
            if atspi_contains(rows, r, x, y, ct) {
              best = Some(r)
            }
          }
          match best {
            Some(b) => {
              (req.reply)([atspi_self_ref(atspi_widget_path(b.id))])
            }
            None => (req.reply)([atspi_self_ref(ATSPI_WIN_PATH)])
          }
          true
        }
        _ => false
      }
    "GetExtents" =>
      match arg_i(0) {
        Some(ct) => {
          let (x, y, w, h) = atspi_rect_for(rows, n, ct)
          (req.reply)(
            [
              @dbus.GVStruct([
                @dbus.GVInt32(x),
                @dbus.GVInt32(y),
                @dbus.GVInt32(w),
                @dbus.GVInt32(h),
              ]),
            ],
          )
          true
        }
        None => false
      }
    "GetPosition" =>
      match arg_i(0) {
        Some(ct) => {
          let (x, y, _w, _h) = atspi_rect_for(rows, n, ct)
          (req.reply)([@dbus.GVInt32(x), @dbus.GVInt32(y)])
          true
        }
        None => false
      }
    "GetSize" => {
      let (_x, _y, w, h) = atspi_rect_for(rows, n, 1)
      (req.reply)([@dbus.GVInt32(w), @dbus.GVInt32(h)])
      true
    }
    "GetLayer" => {
      // 窗口根=canvas(2)，控件=widget(3)
      (req.reply)([@dbus.GVUInt32(if n.parent == 0 { 2 } else { 3 })])
      true
    }
    "GrabFocus" =>
      // 焦点栈在 widget 层，桥不直改——如实回false（读屏回落键盘交互）
      {
        (req.reply)([@dbus.GVBool(false)])
        true
      }
    "GetAlpha" => {
      (req.reply)([@dbus.GVDouble(1.0)])
      true
    }
    _ => false
  }
}

// ---- org.a11y.atspi.Text ----
//
// 偏移单位是**字符**（AT-SPI 口径；与 Editor 的字节口径的换算是本桥的活，
// 单测钉住——方案坑清单「三平台偏移单位」的 Linux 半边）。逐字几何
// （GetCharacterExtents/GetOffsetAtPoint/GetRangeExtents）等 @text 逐字几何
// 接口落地后才能答，当前如实回 0/-1，不编。属性 CharacterCount/CaretOffset；
// CaretOffset 快照无光标字段，回 -1（未知）。

///|
/// 字符数组（码点）——AT-SPI 偏移单位。
fn atspi_chars(s : String) -> Array[Char] {
  s.to_array()
}

///|
/// 字符区间 → 子串（越界钳制；end<start 给空）。
fn atspi_slice_chars(s : String, start : Int, end : Int) -> String {
  let cs = atspi_chars(s)
  let n = cs.length()
  let a = if start < 0 { 0 } else if start > n { n } else { start }
  let b = if end < a { a } else if end > n { n } else { end }
  let sb = StringBuilder()
  for i in a..<b {
    sb.write_char(cs[i])
  }
  sb.to_string()
}

///|
fn atspi_text(req : @dbus.CallReq, rows : Array[AtspiNode]) -> Bool {
  let n = match atspi_row_at(rows, req.path) {
    Some(x) => x
    None => return false
  }
  // 接口广告与实现严格一致：没挂 Text 的控件一律拒（客户端据此判支持）
  if !atspi_ifaces_of(n).contains("org.a11y.atspi.Text") {
    return false
  }
  let body = if n.role == "text_input" || n.role == "text_area" {
    n.value
  } else {
    n.text
  }
  let cs = atspi_chars(body)
  let arg_i = fn(i : Int) -> Int? {
    match req.args.get(i) {
      Some(@dbus.GVInt32(v)) => Some(v)
      Some(@dbus.GVUInt32(v)) => Some(v)
      _ => None
    }
  }
  match req.action {
    "GetCharacterCount" => {
      (req.reply)([@dbus.GVInt32(cs.length())])
      true
    }
    "GetCaretOffset" => {
      // 快照无光标字段（光标在 Editor 闭包里）——如实报未知
      (req.reply)([@dbus.GVInt32(-1)])
      true
    }
    "SetCaretOffset" => {
      (req.reply)([@dbus.GVBool(false)])
      true
    }
    "GetText" =>
      match (arg_i(0), arg_i(1)) {
        (Some(a), Some(b)) => {
          (req.reply)([@dbus.GVString(atspi_slice_chars(body, a, b))])
          true
        }
        _ => false
      }
    "GetStringAtOffset" =>
      match (arg_i(0), arg_i(1)) {
        (Some(off), Some(gran)) => {
          // granularity：0=字符 1=词 2=句 3=行 4=段；非字符档按字符近似
          let n2 = cs.length()
          let o = if off < 0 { 0 } else if off > n2 { n2 } else { off }
          let _ = gran
          let s = if o < n2 { cs[o].to_string() } else { "" }
          (req.reply)(
            [
              @dbus.GVString(s),
              @dbus.GVInt32(o),
              @dbus.GVInt32(o + 1),
              @dbus.GVString(""),
            ],
          )
          true
        }
        _ => false
      }
    "GetCharacterAtOffset" =>
      match arg_i(0) {
        Some(off) => {
          let n2 = cs.length()
          let o = if off < 0 { 0 } else if off > n2 { n2 } else { off }
          let c = if o < n2 { cs[o].to_int() } else { 0xFFFF }
          (req.reply)([@dbus.GVInt32(c)])
          true
        }
        None => false
      }
    "GetTextAtOffset" | "GetTextBeforeOffset" | "GetTextAfterOffset" =>
      match (arg_i(0), arg_i(1)) {
        (Some(off), Some(gran)) => {
          // 三个变体返回 (s, start, end)：字符档给单字符；其余档钳空
          let n2 = cs.length()
          let o = if off < 0 { 0 } else if off > n2 { n2 } else { off }
          let _ = gran
          let s = if o < n2 { cs[o].to_string() } else { "" }
          (req.reply)([
            @dbus.GVString(s),
            @dbus.GVInt32(o),
            @dbus.GVInt32(o + 1),
          ])
          true
        }
        _ => false
      }
    "GetCharacterExtents" | "GetRangeExtents" => {
      // 逐字几何待 @text 逐字几何接口（AttributedText 逐字选中批）——如实回 0
      (req.reply)([
        @dbus.GVStruct([
          @dbus.GVInt32(0),
          @dbus.GVInt32(0),
          @dbus.GVInt32(0),
          @dbus.GVInt32(0),
        ]),
      ])
      true
    }
    "GetOffsetAtPoint" => {
      // 同上：无逐字几何，回 -1（未知）
      (req.reply)([@dbus.GVInt32(-1)])
      true
    }
    "GetNSelections" => {
      (req.reply)([@dbus.GVInt32(0)])
      true
    }
    "GetSelection" => {
      (req.reply)([@dbus.GVInt32(-1), @dbus.GVInt32(-1)])
      true
    }
    "GetDefaultAttributes" | "GetDefaultAttributeSet" => {
      (req.reply)([@dbus.GVDict((Map([]) : Map[String, @dbus.GDBusValue]))])
      true
    }
    "GetAttributes" => {
      (req.reply)([
        @dbus.GVDict((Map([]) : Map[String, @dbus.GDBusValue])),
        @dbus.GVInt32(0),
        @dbus.GVInt32(0),
      ])
      true
    }
    _ => false
  }
}

// ---- org.a11y.atspi.Value ----
//
// 全是属性：MinimumValue/MaximumValue/MinimumIncrement/CurrentValue/Text。
// 口径与 Windows UIA 的 RangeValue 一致——快照值本来就是范围百分比，
// 故 min=0/max=100，CurrentValue 解析 "50%" → 50.0，Text 给原串。

///|
fn atspi_value_props(n : AtspiNode) -> Map[String, @dbus.GDBusValue] {
  let m : Map[String, @dbus.GDBusValue] = Map([])
  m.set("MinimumValue", @dbus.GVDouble(0.0))
  m.set("MaximumValue", @dbus.GVDouble(100.0))
  m.set("MinimumIncrement", @dbus.GVDouble(1.0))
  m.set("CurrentValue", @dbus.GVDouble(atspi_pct(n.value)))
  m.set("Text", @dbus.GVString(n.value))
  m
}

// ---- org.a11y.atspi.Action ----
//
// 单一「click」动作：DoAction 压「点一下」进跨平台动作队列（与 UIA Invoke、
// AX press 同队列，widget 层每帧抽走合成指针点击）。NActions 属性 +
// GetName/GetLocalizedName/GetDescription/GetKeyBinding/GetActions。

///|
fn atspi_action_entries() -> Array[@dbus.GDBusValue] {
  [
    @dbus.GVStruct([
      @dbus.GVString("click"),
      @dbus.GVString("点击"),
      @dbus.GVString("按一下这个控件"),
    ]),
  ]
}

///|
fn atspi_action(req : @dbus.CallReq, rows : Array[AtspiNode]) -> Bool {
  let n = match atspi_row_at(rows, req.path) {
    Some(x) => x
    None => return false
  }
  if !atspi_ifaces_of(n).contains("org.a11y.atspi.Action") {
    return false
  }
  let arg_i = fn(i : Int) -> Int? {
    match req.args.get(i) {
      Some(@dbus.GVInt32(v)) => Some(v)
      _ => None
    }
  }
  match req.action {
    "GetNActions" | "GetNActions_" => {
      (req.reply)([@dbus.GVInt32(1)])
      true
    }
    "GetName" | "GetLocalizedName" => {
      (req.reply)([@dbus.GVString("点击")])
      true
    }
    "GetDescription" => {
      (req.reply)([@dbus.GVString("按一下这个控件")])
      true
    }
    "GetKeyBinding" => {
      (req.reply)([@dbus.GVString("")])
      true
    }
    "GetActions" => {
      (req.reply)([@dbus.GVArray("(sss)", atspi_action_entries())])
      true
    }
    "DoAction" =>
      match arg_i(0) {
        Some(i) => {
          if i == 0 {
            @win.a11y_action_push(n.id, @win.A11Y_ACT_CLICK)
            (req.reply)([@dbus.GVBool(true)])
          } else {
            (req.reply_error)("org.a11y.atspi.Error.Failed", "未知动作下标 \{i}")
          }
          true
        }
        None => false
      }
    _ => false
  }
}

// ---- org.freedesktop.DBus.Properties ----
//
// 读屏侧大量走属性读（Name/ChildCount/Parent/… 与 Value/Text 的各属性）。
// Get(iface, prop) → v；GetAll(iface) → a{sv}。

///|
fn atspi_props(req : @dbus.CallReq, rows : Array[AtspiNode]) -> Bool {
  let is_root = req.path == ATSPI_ROOT_PATH
  let node = if is_root {
    Some(atspi_root_accessor(rows))
  } else {
    atspi_row_at(rows, req.path)
  }
  let n = match node {
    Some(x) => x
    None => return false
  }
  let prop_of = fn(i : Int) -> String? {
    match req.args.get(i) {
      Some(@dbus.GVString(s)) => Some(s)
      _ => None
    }
  }
  let parent_path = if is_root {
    "" // 应用根的父是 registry（不在本连接上），回空串=无
  } else if n.parent == 0 {
    ATSPI_ROOT_PATH
  } else {
    atspi_widget_path(n.parent)
  }
  let kids = if is_root {
    match atspi_window_row(rows) {
      Some(w) => [w]
      None => []
    }
  } else {
    atspi_children_of(rows, n.id)
  }
  // 属性值表（Accessible + 按角色的 Value/Text 属性）
  let props : Map[String, @dbus.GDBusValue] = Map([])
  props.set("Name", @dbus.GVString(if is_root { n.name } else { n.name }))
  props.set("Description", @dbus.GVString(""))
  props.set(
    "Parent",
    if is_root {
      @dbus.GVStruct([@dbus.GVString(""), @dbus.GVPath("/")])
    } else {
      atspi_self_ref(parent_path)
    },
  )
  props.set("ChildCount", @dbus.GVInt32(kids.length()))
  props.set("Locale", @dbus.GVString(""))
  props.set("AccessibleId", @dbus.GVString("w\{n.id}"))
  props.set("HelpText", @dbus.GVString(n.state))
  if !is_root {
    if n.role == "slider" || n.role == "stepper" || n.role == "progress" {
      for k, v in atspi_value_props(n) {
        props.set(k, v)
      }
    }
    if n.role == "text" || n.role == "text_input" || n.role == "text_area" {
      let body = if n.role == "text_input" || n.role == "text_area" {
        n.value
      } else {
        n.text
      }
      props.set("CharacterCount", @dbus.GVInt32(atspi_chars(body).length()))
      props.set("CaretOffset", @dbus.GVInt32(-1))
    }
  }
  match req.action {
    "Get" =>
      match prop_of(1) {
        Some(p) =>
          match props.get(p) {
            Some(v) => {
              (req.reply)([@dbus.GVVariant(v)])
              true
            }
            None => {
              (req.reply_error)(
                "org.freedesktop.DBus.Error.InvalidArgs",
                "无此属性: \{p}",
              )
              true
            }
          }
        None => false
      }
    "GetAll" => {
      let arr : Array[@dbus.GDBusValue] = []
      for k, v in props {
        arr.push(
          @dbus.GVStruct([@dbus.GVString(k), @dbus.GVVariant(v)]),
        )
      }
      (req.reply)([@dbus.GVArray("{sv}", arr)])
      true
    }
    "Set" =>
      // 属性只读（registry 的 Application.Id 走标准 Properties 实现，不归本桥）
      {
        (req.reply_error)(
          "org.freedesktop.DBus.Error.PropertyReadOnly",
          "AT-SPI 桥的属性只读",
        )
        true
      }
    _ => false
  }
}

// ---- 事件上行 + 每拍泵 ----
//
// 事件形态（at-spi2-core 2.52 源码 + 实物抓包双核对）：
//   - org.a11y.atspi.Event.Object:ChildrenChanged — (s "add", i 数量, i 0,
//     v (so) 窗口引用, a{sv} {})，路径挂窗口根；快照内容变了发；
//   - org.a11y.atspi.Event.Focus:Focus — ("", 0, 0, v (so) 新焦点元素,
//     (so) 应用根引用)，路径挂新焦点元素；
//   - org.a11y.atspi.Event.Object:StateChanged — ("focused", 1, 0, v (so)
//     新焦点元素, (so) 应用根引用)。
// 监听方（Orca）按 match 规则收广播，与 GTK 桥发射形态一致。静止界面
// 不发（逐帧全同不扰民）。

///|
/// 快照内容的「变了没有」判据：行数 + 每行身份字段拼串（不含几何——几何
/// 每帧可能因布局抖动变化，那不是语义变化；Orca 查询时现取几何即可）。
fn atspi_digest(rows : Array[AtspiNode]) -> String {
  let sb = StringBuilder()
  for r in rows {
    sb.write_string("\{r.id}/\{r.parent}/\{r.role}/\{r.name}/\{r.state}/\{r.value}/\{r.enabled}\n")
  }
  sb.to_string()
}

///|
/// 发 ChildrenChanged（树内容变了）。
fn atspi_emit_children_changed(count : Int) -> Unit {
  let _ = @dbus.dbus_emit_signal_a11y(
    ATSPI_WIN_PATH,
    "org.a11y.atspi.Event.Object",
    "ChildrenChanged",
    [
      @dbus.GVString("add"),
      @dbus.GVInt32(count),
      @dbus.GVInt32(0),
      @dbus.GVVariant(atspi_self_ref(ATSPI_WIN_PATH)),
      @dbus.GVArray("{sv}", []),
    ],
  )
}

///|
/// 发焦点事件（Focus + StateChanged:focused）。
fn atspi_emit_focus(path : String) -> Unit {
  let el = atspi_self_ref(path)
  let app = atspi_self_ref(ATSPI_ROOT_PATH)
  let _ = @dbus.dbus_emit_signal_a11y(
    path,
    "org.a11y.atspi.Event.Focus",
    "Focus",
    [
      @dbus.GVString(""),
      @dbus.GVInt32(0),
      @dbus.GVInt32(0),
      @dbus.GVVariant(el),
      app,
    ],
  )
  let _ = @dbus.dbus_emit_signal_a11y(
    path,
    "org.a11y.atspi.Event.Object",
    "StateChanged",
    [
      @dbus.GVString("focused"),
      @dbus.GVInt32(1),
      @dbus.GVInt32(0),
      @dbus.GVVariant(el),
      app,
    ],
  )
}

///|
/// 每拍推进：没启动先试着启动（背间隔 ~2s 重试，不每帧连）；启动后抽干
/// 入站查询（读屏的 Get* / Properties.Get）、比对新旧快照发事件。宿主每帧
/// 调（排在 a11y_frame_sync 之后——快照必须是这一帧的）。
pub fn atspi_tick() -> Unit {
  match g_atspi_state.val {
    AtspiLive => {
      // 自愈重连会换唯一名：核对不齐就回 Idle 重走 Embed（背间隔见下），
      // 不带着旧注册名假装活着。
      let broken = atspi_needs_reembed(
        g_atspi_name.val,
        @dbus.dbus_a11y_unique_name(),
        @dbus.dbus_a11y_alive(),
      )
      if broken {
        g_atspi_state.val = AtspiIdle
        g_atspi_retry.val = 60
        return
      }
    }
    AtspiIdle | AtspiDown =>
      // 背间隔：60 帧一轮（约 1s @60fps），不每帧重连
      if g_atspi_retry.val <= 0 {
        match atspi_start() {
          Ok(_) => ()
          Err(_) => {
            g_atspi_state.val = AtspiDown
            g_atspi_retry.val = 60
          }
        }
      } else {
        g_atspi_retry.val = g_atspi_retry.val - 1
        return
      }
  }
  if !(g_atspi_state.val is AtspiLive) {
    return
  }
  let rows = atspi_rows_now()
  let focus = @win.a11y_focus()
  // 树内容变了：通知重读（窗口根路径上广播）
  let digest = atspi_digest(rows)
  if digest != g_atspi_last_digest.val {
    g_atspi_last_rows.val = rows
    g_atspi_last_digest.val = digest
    atspi_emit_children_changed(rows.length())
  }
  // 焦点换了：Focus + StateChanged
  if focus != g_atspi_last_focus.val {
    g_atspi_last_focus.val = focus
    if focus > 0 {
      atspi_emit_focus(atspi_widget_path(focus))
    }
  }
  // 抽干入站查询（读屏的 Get* 全在这条连接上）
  let _ = @dbus.dbus_pump()
}
