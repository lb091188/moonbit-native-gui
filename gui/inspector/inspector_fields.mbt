// 样式全量读数：把 `@style.Style` 里**已设**的字段逐项摊成
// (字段名, 显示值) 表，供 inspector 服务 `style <id>` 命令与 GUI 检查器
// 的样式面板使用。字段名即 @style.Style 字段本名（与模板 CSS 属性同
// 口径），按组序输出；未设（None）的字段省略。
// 读数口径与样式编辑器一致：颜色走 `@style.resolve_color`（token 解析成
// 实际值）、数值直出、枚举出名字、百分比单列带 % 后缀。

///|
fn insp_fw_name(f : @text.FontWeight) -> String {
  match f {
    Thin => "Thin"
    ExtraLight => "ExtraLight"
    Light => "Light"
    Normal => "Normal"
    Medium => "Medium"
    SemiBold => "SemiBold"
    Bold => "Bold"
    ExtraBold => "ExtraBold"
    Black => "Black"
  }
}

///|
fn insp_align_name(a : @text.TextAlign) -> String {
  match a {
    Start => "Start"
    Center => "Center"
    End => "End"
  }
}

///|
fn insp_deco_name(d : @style.TextDecoration) -> String {
  match d {
    Underline => "Underline"
    LineThrough => "LineThrough"
    Overline => "Overline"
    DecoNone => "none"
  }
}

///|
fn insp_ws_name(w : @style.WhiteSpace) -> String {
  match w {
    Normal => "normal"
    NoWrap => "nowrap"
  }
}

///|
fn insp_display_name(d : @yoga.Display) -> String {
  match d {
    Flex => "flex"
    None => "none"
  }
}

///|
fn insp_direction_name(d : @style.Direction) -> String {
  match d {
    Ltr => "ltr"
    Rtl => "rtl"
  }
}

///|
fn insp_flexdir_name(d : @yoga.FlexDirection) -> String {
  match d {
    Row => "row"
    RowReverse => "row-reverse"
    Column => "column"
    ColumnReverse => "column-reverse"
  }
}

///|
fn insp_wrap_name(w : @yoga.FlexWrap) -> String {
  match w {
    NoWrap => "nowrap"
    Wrap => "wrap"
    WrapReverse => "wrap-reverse"
  }
}

///|
fn insp_justify_name(j : @yoga.JustifyContent) -> String {
  match j {
    FlexStart => "flex-start"
    FlexEnd => "flex-end"
    Center => "center"
    SpaceBetween => "space-between"
    SpaceAround => "space-around"
    SpaceEvenly => "space-evenly"
  }
}

///|
fn insp_align_items_name(a : @yoga.AlignItems) -> String {
  match a {
    Stretch => "stretch"
    FlexStart => "flex-start"
    FlexEnd => "flex-end"
    Center => "center"
    Baseline => "baseline"
  }
}

///|
fn insp_position_name(p : @yoga.PositionType) -> String {
  match p {
    Relative => "relative"
    Absolute => "absolute"
  }
}

///|
fn insp_visibility_name(v : @style.Visibility) -> String {
  match v {
    Visible => "visible"
    Hidden => "hidden"
  }
}

///|
fn insp_border_style_name(b : @style.BorderStyle) -> String {
  match b {
    Solid => "solid"
    Dashed => "dashed"
    Dotted => "dotted"
  }
}

///|
fn insp_blend_name(b : @render.BlendMode) -> String {
  match b {
    Normal => "normal"
    Multiply => "multiply"
    Screen => "screen"
    Overlay => "overlay"
    Darken => "darken"
    Lighten => "lighten"
    ColorDodge => "color-dodge"
    ColorBurn => "color-burn"
    HardLight => "hard-light"
    SoftLight => "soft-light"
    Difference => "difference"
    Exclusion => "exclusion"
    Hue => "hue"
    Saturation => "saturation"
    Color => "color"
    Luminosity => "luminosity"
    Clear => "clear"
    Copy => "copy"
    SourceIn => "source-in"
    SourceOut => "source-out"
    SourceAtop => "source-atop"
    DestinationOver => "destination-over"
    DestinationIn => "destination-in"
    DestinationAtop => "destination-atop"
    Xor => "xor"
  }
}

///|
fn insp_gradient_text(g : @style.GradientSpec) -> String {
  let stops = StringBuilder()
  let mut i = 0
  for s in g.stops {
    if i > 0 {
      stops.write_string(", ")
    }
    stops.write_string(@style.resolve_color(s.1))
    stops.write_string(" ")
    stops.write_string(s.0.to_string())
    i += 1
  }
  stops.to_string()
}

///|
/// 只收 Some 的助手：给一些就拼进表。
fn insp_push_num(
  out : Array[(String, String)],
  name : String,
  v : Double?,
) -> Unit {
  match v {
    Some(d) => out.push((name, d.to_string()))
    None => ()
  }
}

///|
/// 只收 Some 的助手：百分比字段（值 + `%`）。
fn insp_push_pct(
  out : Array[(String, String)],
  name : String,
  v : Double?,
) -> Unit {
  match v {
    Some(d) => out.push((name, d.to_string() + "%"))
    None => ()
  }
}

///|
/// Style 里**已设**字段的全量表（字段名即 @style.Style 字段本名，与模板
/// CSS 属性同口径；输出顺序仍按组）。
pub fn insp_style_all(st : @style.Style) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  // —— text.：文本与颜色
  match st.color {
    Some(c) => out.push(("color", @style.resolve_color(c)))
    None => ()
  }
  match st.background_color {
    Some(c) => out.push(("background", @style.resolve_color(c)))
    None => ()
  }
  insp_push_num(out, "font_size", st.font_size)
  match st.font_family {
    Some(f) => out.push(("font_family", f))
    None => ()
  }
  match st.font_weight {
    Some(f) => out.push(("font_weight", insp_fw_name(f)))
    None => ()
  }
  match st.text_align {
    Some(a) => out.push(("text_align", insp_align_name(a)))
    None => ()
  }
  insp_push_num(out, "line_height", st.line_height)
  insp_push_num(out, "letter_spacing", st.letter_spacing)
  match st.text_decoration {
    Some(d) => out.push(("text_decoration", insp_deco_name(d)))
    None => ()
  }
  match st.white_space {
    Some(w) => out.push(("white_space", insp_ws_name(w)))
    None => ()
  }
  // —— box.：尺寸
  insp_push_num(out, "width", st.width)
  insp_push_pct(out, "width_percent", st.width_percent)
  insp_push_num(out, "height", st.height)
  insp_push_pct(out, "height_percent", st.height_percent)
  insp_push_num(out, "min_width", st.min_width)
  insp_push_num(out, "min_height", st.min_height)
  insp_push_num(out, "max_width", st.max_width)
  insp_push_num(out, "max_height", st.max_height)
  // —— edge.：内外边距
  insp_push_num(out, "padding_top", st.padding_top)
  insp_push_num(out, "padding_right", st.padding_right)
  insp_push_num(out, "padding_bottom", st.padding_bottom)
  insp_push_num(out, "padding_left", st.padding_left)
  insp_push_num(out, "margin_top", st.margin_top)
  insp_push_num(out, "margin_right", st.margin_right)
  insp_push_num(out, "margin_bottom", st.margin_bottom)
  insp_push_num(out, "margin_left", st.margin_left)
  // —— border.：边框与圆角
  insp_push_num(out, "border_width", st.border_width)
  match st.border_color {
    Some(c) => out.push(("border_color", @style.resolve_color(c)))
    None => ()
  }
  insp_push_num(out, "border_radius", st.border_radius)
  match st.border_style {
    Some(b) => out.push(("border_style", insp_border_style_name(b)))
    None => ()
  }
  insp_push_num(out, "border_top_left_radius", st.border_top_left_radius)
  insp_push_num(out, "border_top_right_radius", st.border_top_right_radius)
  insp_push_num(
    out,
    "border_bottom_right_radius",
    st.border_bottom_right_radius,
  )
  insp_push_num(out, "border_bottom_left_radius", st.border_bottom_left_radius)
  insp_push_num(out, "border_top_width", st.border_top_width)
  match st.border_top_color {
    Some(c) => out.push(("border_top_color", @style.resolve_color(c)))
    None => ()
  }
  insp_push_num(out, "border_right_width", st.border_right_width)
  match st.border_right_color {
    Some(c) => out.push(("border_right_color", @style.resolve_color(c)))
    None => ()
  }
  insp_push_num(out, "border_bottom_width", st.border_bottom_width)
  match st.border_bottom_color {
    Some(c) => out.push(("border_bottom_color", @style.resolve_color(c)))
    None => ()
  }
  insp_push_num(out, "border_left_width", st.border_left_width)
  match st.border_left_color {
    Some(c) => out.push(("border_left_color", @style.resolve_color(c)))
    None => ()
  }
  // —— flex.：布局
  match st.display {
    Some(d) => out.push(("display", insp_display_name(d)))
    None => ()
  }
  match st.direction {
    Some(d) => out.push(("direction", insp_direction_name(d)))
    None => ()
  }
  match st.flex_direction {
    Some(d) => out.push(("flex_direction", insp_flexdir_name(d)))
    None => ()
  }
  match st.flex_wrap {
    Some(w) => out.push(("flex_wrap", insp_wrap_name(w)))
    None => ()
  }
  match st.justify_content {
    Some(j) => out.push(("justify_content", insp_justify_name(j)))
    None => ()
  }
  match st.align_items {
    Some(a) => out.push(("align_items", insp_align_items_name(a)))
    None => ()
  }
  match st.align_self {
    Some(a) => out.push(("align_self", insp_align_items_name(a)))
    None => ()
  }
  insp_push_num(out, "flex", st.flex)
  insp_push_num(out, "flex_shrink", st.flex_shrink)
  insp_push_num(out, "flex_basis", st.flex_basis)
  insp_push_pct(out, "flex_basis_percent", st.flex_basis_percent)
  insp_push_num(out, "row_gap", st.row_gap)
  insp_push_num(out, "column_gap", st.column_gap)
  // —— pos.：定位与层级
  match st.position {
    Some(p) => out.push(("position", insp_position_name(p)))
    None => ()
  }
  insp_push_num(out, "top", st.top)
  insp_push_num(out, "right", st.right)
  insp_push_num(out, "bottom", st.bottom)
  insp_push_num(out, "left", st.left)
  match st.z_index {
    Some(z) => out.push(("z_index", z.to_string()))
    None => ()
  }
  insp_push_num(out, "opacity", st.opacity)
  insp_push_num(out, "transition_ms", st.transition_ms)
  // —— misc.：其它
  match st.visibility {
    Some(v) => out.push(("visibility", insp_visibility_name(v)))
    None => ()
  }
  match st.cursor {
    Some(c) => out.push(("cursor", c.to_string()))
    None => ()
  }
  match st.background_gradient {
    Some(g) => out.push(("background_gradient", insp_gradient_text(g)))
    None => ()
  }
  match st.blend_mode {
    Some(b) => out.push(("blend_mode", insp_blend_name(b)))
    None => ()
  }
  out
}
