// 样式全量读数：把 `@style.Style` 里**已设**的字段逐项摊成
// (字段名, 显示值) 表，供 inspector 服务 `style <id>` 命令与 GUI 检查器
// 的样式面板使用。字段名带点分组前缀（text. / box. / edge. / border. /
// flex. / pos. / misc.），按组序输出；未设（None）的字段省略。
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
/// Style 里**已设**字段的全量表（字段名带分组前缀，按组序输出）。
pub fn insp_style_all(st : @style.Style) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  // —— text.：文本与颜色
  match st.color {
    Some(c) => out.push(("text.color", @style.resolve_color(c)))
    None => ()
  }
  match st.background_color {
    Some(c) => out.push(("text.background", @style.resolve_color(c)))
    None => ()
  }
  insp_push_num(out, "text.font_size", st.font_size)
  match st.font_family {
    Some(f) => out.push(("text.font_family", f))
    None => ()
  }
  match st.font_weight {
    Some(f) => out.push(("text.font_weight", insp_fw_name(f)))
    None => ()
  }
  match st.text_align {
    Some(a) => out.push(("text.align", insp_align_name(a)))
    None => ()
  }
  insp_push_num(out, "text.line_height", st.line_height)
  insp_push_num(out, "text.letter_spacing", st.letter_spacing)
  match st.text_decoration {
    Some(d) => out.push(("text.decoration", insp_deco_name(d)))
    None => ()
  }
  match st.white_space {
    Some(w) => out.push(("text.white_space", insp_ws_name(w)))
    None => ()
  }
  // —— box.：尺寸
  insp_push_num(out, "box.width", st.width)
  insp_push_pct(out, "box.width_percent", st.width_percent)
  insp_push_num(out, "box.height", st.height)
  insp_push_pct(out, "box.height_percent", st.height_percent)
  insp_push_num(out, "box.min_width", st.min_width)
  insp_push_num(out, "box.min_height", st.min_height)
  insp_push_num(out, "box.max_width", st.max_width)
  insp_push_num(out, "box.max_height", st.max_height)
  // —— edge.：内外边距
  insp_push_num(out, "edge.padding_top", st.padding_top)
  insp_push_num(out, "edge.padding_right", st.padding_right)
  insp_push_num(out, "edge.padding_bottom", st.padding_bottom)
  insp_push_num(out, "edge.padding_left", st.padding_left)
  insp_push_num(out, "edge.margin_top", st.margin_top)
  insp_push_num(out, "edge.margin_right", st.margin_right)
  insp_push_num(out, "edge.margin_bottom", st.margin_bottom)
  insp_push_num(out, "edge.margin_left", st.margin_left)
  // —— border.：边框与圆角
  insp_push_num(out, "border.width", st.border_width)
  match st.border_color {
    Some(c) => out.push(("border.color", @style.resolve_color(c)))
    None => ()
  }
  insp_push_num(out, "border.radius", st.border_radius)
  match st.border_style {
    Some(b) => out.push(("border.style", insp_border_style_name(b)))
    None => ()
  }
  insp_push_num(out, "border.top_left_radius", st.border_top_left_radius)
  insp_push_num(out, "border.top_right_radius", st.border_top_right_radius)
  insp_push_num(
    out,
    "border.bottom_right_radius",
    st.border_bottom_right_radius,
  )
  insp_push_num(out, "border.bottom_left_radius", st.border_bottom_left_radius)
  insp_push_num(out, "border.top_width", st.border_top_width)
  match st.border_top_color {
    Some(c) => out.push(("border.top_color", @style.resolve_color(c)))
    None => ()
  }
  insp_push_num(out, "border.right_width", st.border_right_width)
  match st.border_right_color {
    Some(c) => out.push(("border.right_color", @style.resolve_color(c)))
    None => ()
  }
  insp_push_num(out, "border.bottom_width", st.border_bottom_width)
  match st.border_bottom_color {
    Some(c) => out.push(("border.bottom_color", @style.resolve_color(c)))
    None => ()
  }
  insp_push_num(out, "border.left_width", st.border_left_width)
  match st.border_left_color {
    Some(c) => out.push(("border.left_color", @style.resolve_color(c)))
    None => ()
  }
  // —— flex.：布局
  match st.display {
    Some(d) => out.push(("flex.display", insp_display_name(d)))
    None => ()
  }
  match st.direction {
    Some(d) => out.push(("flex.direction", insp_direction_name(d)))
    None => ()
  }
  match st.flex_direction {
    Some(d) => out.push(("flex.flex_direction", insp_flexdir_name(d)))
    None => ()
  }
  match st.flex_wrap {
    Some(w) => out.push(("flex.wrap", insp_wrap_name(w)))
    None => ()
  }
  match st.justify_content {
    Some(j) => out.push(("flex.justify_content", insp_justify_name(j)))
    None => ()
  }
  match st.align_items {
    Some(a) => out.push(("flex.align_items", insp_align_items_name(a)))
    None => ()
  }
  match st.align_self {
    Some(a) => out.push(("flex.align_self", insp_align_items_name(a)))
    None => ()
  }
  insp_push_num(out, "flex.grow", st.flex)
  insp_push_num(out, "flex.shrink", st.flex_shrink)
  insp_push_num(out, "flex.basis", st.flex_basis)
  insp_push_pct(out, "flex.basis_percent", st.flex_basis_percent)
  insp_push_num(out, "flex.row_gap", st.row_gap)
  insp_push_num(out, "flex.column_gap", st.column_gap)
  // —— pos.：定位与层级
  match st.position {
    Some(p) => out.push(("pos.position", insp_position_name(p)))
    None => ()
  }
  insp_push_num(out, "pos.top", st.top)
  insp_push_num(out, "pos.right", st.right)
  insp_push_num(out, "pos.bottom", st.bottom)
  insp_push_num(out, "pos.left", st.left)
  match st.z_index {
    Some(z) => out.push(("pos.z_index", z.to_string()))
    None => ()
  }
  insp_push_num(out, "pos.opacity", st.opacity)
  insp_push_num(out, "pos.transition_ms", st.transition_ms)
  // —— misc.：其它
  match st.visibility {
    Some(v) => out.push(("misc.visibility", insp_visibility_name(v)))
    None => ()
  }
  match st.cursor {
    Some(c) => out.push(("misc.cursor", c.to_string()))
    None => ()
  }
  match st.background_gradient {
    Some(g) => out.push(("misc.gradient", insp_gradient_text(g)))
    None => ()
  }
  match st.blend_mode {
    Some(b) => out.push(("misc.blend_mode", insp_blend_name(b)))
    None => ()
  }
  out
}
