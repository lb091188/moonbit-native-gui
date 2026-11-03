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
