// 语义面（读屏）：控件类名与状态的**解析视图**。
//
// 单一事实源是字符串：`Widget.role` / `Widget.name` 由组件与 `Node::named` /
// `Node::with_role` 写，测试（@uitest）与桥都读同一份。本文件只把字符串翻成
// 枚举供桥内部用（避免「测试一套 role、读屏一套 role」的双源），不反向驱动组件。
//
// 状态与值不进 Widget 字段：`enabled` 是例外（组件闭包私有、桥拿不到，见
// widget.mbt 的字段注释），其余（focus / 可聚焦 / 屏显）由桥在推送时现算。

///|
/// 控件语义角色（桥的解析视图；字符串是事实源，未知一律 `Unknown`）。
pub(all) enum ARole {
  Button
  Checkbox
  RadioButton
  Switch
  Slider
  Stepper
  TextInput
  TextArea
  Select
  DatePicker
  ColorPicker
  Rate
  Progress
  Tab
  MenuItem
  Link
  Image
  Heading
  Text
  Window
  Group
  Unknown
}

///|
/// 角色字符串 → 枚举（未登记的字符串给 `Unknown`，桥按 Group 处理并保留原名）。
pub fn arole_of(role : String) -> ARole {
  match role {
    "button" => Button
    "checkbox" => Checkbox
    "radio" => RadioButton
    "switch" => Switch
    "slider" => Slider
    "stepper" => Stepper
    "text_input" => TextInput
    "text_area" => TextArea
    "select" => Select
    "date_picker" => DatePicker
    "color_picker" => ColorPicker
    "rate" => Rate
    "progress" => Progress
    "tab" => Tab
    "menuitem" => MenuItem
    "link" => Link
    "image" => Image
    "heading" => Heading
    "text" => Text
    "window" => Window
    "group" => Group
    _ => Unknown
  }
}

///|
/// 枚举 → 角色字符串（`arole_of` 的逆；`Unknown` 给空串）。
pub fn arole_name(r : ARole) -> String {
  match r {
    Button => "button"
    Checkbox => "checkbox"
    RadioButton => "radio"
    Switch => "switch"
    Slider => "slider"
    Stepper => "stepper"
    TextInput => "text_input"
    TextArea => "text_area"
    Select => "select"
    DatePicker => "date_picker"
    ColorPicker => "color_picker"
    Rate => "rate"
    Progress => "progress"
    Tab => "tab"
    MenuItem => "menuitem"
    Link => "link"
    Image => "image"
    Heading => "heading"
    Text => "text"
    Window => "window"
    Group => "group"
    Unknown => ""
  }
}

///|
/// 控件的语义状态与值（现算）：组件挂了 `a11y_state` 就调它，否则 None。
/// 回调首参是控件本身——与 `im_cursor` 同形，不把控件捕进闭包（防引用环）。
pub fn Widget::a11y_state_now(self : Widget) -> (String, String)? {
  match self.a11y_state {
    Some(f) => f(self)
    None => None
  }
}

///|
/// 控件的语义文本（现算）：挂了 `a11y_text` 就调它，否则回落 `label`；
/// 两者都空给 None（读屏据此判「无内容」，不朗读空串）。
pub fn Widget::a11y_text_now(self : Widget) -> String? {
  let t = match self.a11y_text {
    Some(f) => f(self)
    None => None
  }
  match t {
    Some(s) =>
      if s.length() > 0 {
        Some(s)
      } else {
        None
      }
    None =>
      if self.label.length() > 0 {
        Some(self.label)
      } else {
        None
      }
  }
}

///|
/// 语义包装器：按需挂状态/文本回调（与 `named` / `with_role` 同一形态，纯增量）。
pub fn Node::a11y(
  self : Node,
  state? : (Widget) -> (String, String)?,
  text? : (Widget) -> String?,
) -> Node {
  {
    mount: fn(parent : Widget) -> Widget {
      let w = (self.mount)(parent)
      match state {
        Some(f) => w.a11y_state = Some(f)
        None => ()
      }
      match text {
        Some(f) => w.a11y_text = Some(f)
        None => ()
      }
      w
    },
  }
}

// ---- 帧尾对账：语义快照 ----
//
// 每帧画完（present 前）把整棵树的语义面重扫一遍，产出一份**快照**，平台臂
// （NSAccessibility / AT-SPI / UIA）从这份快照推给读屏。快照重扫而不是增量
// 打补丁：一屏几十个控件量级，重建成本远低于维护「谁删了」；「幽灵控件」
// （已删控件还被读到）在这条路上根本不会出现。
//
// 平台臂的钩子：`a11y_last_frame()` 读快照即可，不需要回调进 MoonBit。

///|
/// 一个控件的语义快照（矩形是窗口坐标，读屏拿去做屏上高亮框）。
pub(all) struct A11yNode {
  id : Int
  parent : Int
  role : String
  name : String
  /// 状态串（如 "checked" / "password" / "read_only"），空串 = 无
  state : String
  /// 值串（如 "50%"，复选框为空）
  value : String
  /// 朗读正文（`a11y_text` 现算，回落 `label`）
  text : String
  enabled : Bool
  x : Double
  y : Double
  w : Double
  h : Double
}

///|
/// 最近一帧的语义快照（平台臂 / 用例读；未跑过对账时为空数组）。
let g_a11y_last : Ref[Array[A11yNode]] = Ref([])

///|
fn a11y_walk(w : Widget, parent : Int, out : Array[A11yNode]) -> Unit {
  if !w.visible {
    return
  }
  let (state, value) = match w.a11y_state_now() {
    Some(p) => p
    None => ("", "")
  }
  out.push({
    id: w.id,
    parent,
    role: w.role,
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
  for k in w.kids {
    a11y_walk(k, w.id, out)
  }
}

///|
/// 帧尾对账：重扫整棵树的语义面，替换上一帧快照并返回控件数。
/// 排在上屏（present）之前——推给读屏的矩形必须是这一帧的。
pub fn a11y_frame_sync(root : Widget) -> Int {
  let out : Array[A11yNode] = []
  a11y_walk(root, 0, out)
  g_a11y_last.val = out
  // 平台臂吃的是同一份快照：摊成 TSV 推过去（字段里的制表/换行换空格，
  // 不然会把一行切成两行）
  let sb = StringBuilder()
  for n in out {
    sb.write_string(n.id.to_string())
    sb.write_string("\t")
    sb.write_string(n.parent.to_string())
    sb.write_string("\t")
    sb.write_string(if n.enabled { "1" } else { "0" })
    sb.write_string("\t")
    sb.write_string(tsv_clean(n.role))
    sb.write_string("\t")
    sb.write_string(tsv_clean(n.name))
    sb.write_string("\t")
    sb.write_string(tsv_clean(n.state))
    sb.write_string("\t")
    sb.write_string(tsv_clean(n.value))
    sb.write_string("\t")
    sb.write_string(tsv_clean(n.text))
    sb.write_string("\t")
    sb.write_string(n.x.to_string())
    sb.write_string("\t")
    sb.write_string(n.y.to_string())
    sb.write_string("\t")
    sb.write_string(n.w.to_string())
    sb.write_string("\t")
    sb.write_string(n.h.to_string())
    sb.write_string("\n")
  }
  @win.a11y_publish(@utf8.encode(sb.to_string()), out.length())
  out.length()
}

///|
/// TSV 字段清洗：制表符与换行换成空格（保持「一行一控件」的对齐）。
fn tsv_clean(s : String) -> String {
  let b = StringBuilder()
  for c in s.to_array() {
    if c == '\t' || c == '\n' || c == '\r' {
      b.write_char(' ')
    } else {
      b.write_char(c)
    }
  }
  b.to_string()
}

///|
/// 读最近一帧快照（平台臂与用例的观察面；返回的是同一份引用，别改它）。
pub fn a11y_last_frame() -> Array[A11yNode] {
  g_a11y_last.val
}

// ---- 读屏动作派发 ----
//
// 平台臂（Windows UIA 的 Invoke/Toggle/Expand）只递「点一下这个控件」——
// 组件闭包里的 Store / Editor 桥够不着也不该够着。这里把动作合成成指针
// Down+Up，走与真实点击同一条 `route_pointer`：按钮的点闭包、勾选的翻转、
// 下拉的弹收都由组件自己的点击链路驱动，桥不碰业务。

///|
/// 抽干待办的读屏动作并逐个派发；返回更新后的 `(hover, capture, changed,
/// consumed)` 会话状态（合成点击与真实点击同链，状态要接回宿主）。
pub fn a11y_pump_actions(
  root : Widget,
  hover : Int,
  capture : Int,
) -> (Int, Int, Bool, Bool) {
  let mut h = hover
  let mut c = capture
  let mut ch = false
  let mut consumed = false
  for ;; {
    match @win.a11y_action_poll() {
      None => break
      Some((id, act)) => {
        let r = a11y_action_dispatch(root, id, act, h, c)
        h = r.0
        c = r.1
        ch = ch || r.2
        consumed = consumed || r.3
      }
    }
  }
  (h, c, ch, consumed)
}

///|
/// 把一个读屏动作派发到控件：目前只有「点击」一档（`A11Y_ACT_CLICK`），
/// 按控件中心合成 Down+Up。控件不在树里（已删/跨窗 id）时原样返回状态。
pub fn a11y_action_dispatch(
  root : Widget,
  id : Int,
  act : Int,
  hover : Int,
  capture : Int,
) -> (Int, Int, Bool, Bool) {
  match root.by_id(id) {
    None => (hover, capture, false, false)
    Some(w) =>
      if act != @win.A11Y_ACT_CLICK || w.rect.w <= 0.0 || w.rect.h <= 0.0 {
        (hover, capture, false, false)
      } else {
        let cx = w.rect.x + w.rect.w / 2.0
        let cy = w.rect.y + w.rect.h / 2.0
        let down = route_pointer(
          root,
          { kind: Down, x: cx, y: cy, button: 0, mods: 0, },
          hover,
          capture,
        )
        route_pointer(
          root,
          { kind: Up, x: cx, y: cy, button: 0, mods: 0, },
          down.0,
          down.1,
        )
      }
  }
}
