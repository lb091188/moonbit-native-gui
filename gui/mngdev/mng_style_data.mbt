// 类定义数据 → Style：补丁携带 `<style>` 的规则（属性名 + 编译期值表达式），
// 应用侧按属性名落到 Style 字段并重注册命名类。样式值改动因此可以热更。

///|
priv suberror SdRaise {
  SdRaise(String)
}

///|
fn[A] sd_need(r : Result[A, String]) -> A raise SdRaise {
  match r {
    Ok(v) => v
    Err(e) => raise SdRaise(e)
  }
}

///|
fn sd_parse_double(s : String) -> Double? {
  let cs = s.to_array()
  let n = cs.length()
  if n == 0 {
    return None
  }
  let mut neg = false
  let mut i = 0
  if cs[0] == '-' {
    neg = true
    i = 1
  }
  let mut v = 0.0
  let mut frac = 0.0
  let mut scale = 0.1
  let mut seen = false
  let mut dot = false
  while i < n {
    let c = cs[i]
    if c >= '0' && c <= '9' {
      let d = (c.to_int() - '0'.to_int()).to_double()
      if dot {
        frac = frac + d * scale
        scale = scale * 0.1
      } else {
        v = v * 10.0 + d
      }
      seen = true
    } else if c == '.' && !dot {
      dot = true
    } else {
      return None
    }
    i += 1
  }
  if !seen {
    return None
  }
  let out = v + frac
  Some(if neg { -out } else { out })
}

///|
fn sd_unquote(e : String) -> String {
  let n = e.length()
  if n >= 2 && e[0] == '"' && e[n - 1] == '"' {
    e[1:n - 1].to_owned()
  } else {
    e
  }
}

///|
fn sd_variant(e : String) -> String {
  let a = e.to_array()
  let mut start = 0
  let mut i = 0
  while i + 1 < a.length() {
    if a[i] == ':' && a[i + 1] == ':' {
      start = i + 2
      i += 2
    } else {
      i += 1
    }
  }
  a[start:].map(fn(c) { c.to_string() }).join("")
}

///|
fn sd_theme_num(e : String) -> Double? {
  match e {
    "@theme.control_height" => Some(@theme.control_height)
    "@theme.font_size_body" => Some(@theme.font_size_body)
    "@theme.font_size_secondary" => Some(@theme.font_size_secondary)
    "@theme.font_size_section" => Some(@theme.font_size_section)
    "@theme.font_size_title" => Some(@theme.font_size_title)
    "@theme.radius_ctrl()" => Some(@theme.radius_ctrl())
    "@theme.radius_card()" => Some(@theme.radius_card())
    "@theme.radius_overlay()" => Some(@theme.radius_overlay())
    _ => None
  }
}

///|
fn sd_num(e : String) -> Result[Double, String] {
  match sd_theme_num(e) {
    Some(v) => Ok(v)
    None =>
      match sd_parse_double(e) {
        Some(v) => Ok(v)
        None => Err("样式数据：数值无法解析「" + e + "」")
      }
  }
}

///|
fn sd_int(e : String) -> Result[Int32, String] {
  match sd_num(e) {
    Ok(v) => Ok(v.to_int())
    Err(x) => Err(x)
  }
}

///|
fn sd_set_color(
  field : String,
  e : String,
  s : @style.Style,
) -> Result[Unit, String] {
  let v = sd_unquote(e)
  let tmp = if field == "background_color" {
    @style.style(background_color=v)
  } else if field == "border_color" {
    @style.style(border_color=v)
  } else {
    @style.style(color=v)
  }
  if field == "background_color" {
    s.background_color = tmp.background_color
  } else if field == "border_color" {
    s.border_color = tmp.border_color
  } else {
    s.color = tmp.color
  }
  Ok(())
}

///|
fn sd_set_prop(
  s : @style.Style,
  name : String,
  e : String,
) -> Result[Unit, String] raise SdRaise {
  match name {
    "color" | "background_color" | "border_color" => sd_set_color(name, e, s)
    "font_family" => {
      s.font_family = Some(sd_unquote(e))
      Ok(())
    }
    "font_weight" => {
      let v = sd_variant(e)
      let w = match v {
        "Thin" => @text.FontWeight::Thin
        "ExtraLight" => @text.FontWeight::ExtraLight
        "Light" => @text.FontWeight::Light
        "Normal" => @text.FontWeight::Normal
        "Medium" => @text.FontWeight::Medium
        "SemiBold" => @text.FontWeight::SemiBold
        "Bold" => @text.FontWeight::Bold
        "ExtraBold" => @text.FontWeight::ExtraBold
        "Black" => @text.FontWeight::Black
        _ => return Err("样式数据：font_weight「" + v + "」")
      }
      s.font_weight = Some(w)
      Ok(())
    }
    "text_align" => {
      let v = sd_variant(e)
      let a = match v {
        "Start" => @text.TextAlign::Start
        "Center" => @text.TextAlign::Center
        "End" => @text.TextAlign::End
        _ => return Err("样式数据：text_align「" + v + "」")
      }
      s.text_align = Some(a)
      Ok(())
    }
    "white_space" => {
      let v = sd_variant(e)
      let w = match v {
        "Normal" => @style.WhiteSpace::Normal
        "NoWrap" => @style.WhiteSpace::NoWrap
        _ => return Err("样式数据：white_space「" + v + "」")
      }
      s.white_space = Some(w)
      Ok(())
    }
    "border_style" => {
      let v = sd_variant(e)
      let b = match v {
        "Solid" => @style.BorderStyle::Solid
        "Dashed" => @style.BorderStyle::Dashed
        "Dotted" => @style.BorderStyle::Dotted
        _ => return Err("样式数据：border_style「" + v + "」")
      }
      s.border_style = Some(b)
      Ok(())
    }
    "visibility" => {
      let v = sd_variant(e)
      let x = match v {
        "Visible" => @style.Visibility::Visible
        "Hidden" => @style.Visibility::Hidden
        _ => return Err("样式数据：visibility「" + v + "」")
      }
      s.visibility = Some(x)
      Ok(())
    }
    "display" => {
      let v = sd_variant(e)
      let x = match v {
        "Flex" => @yoga.Display::Flex
        "None" => @yoga.Display::None
        _ => return Err("样式数据：display「" + v + "」")
      }
      s.display = Some(x)
      Ok(())
    }
    "flex_direction" => {
      let v = sd_variant(e)
      let x = match v {
        "Row" => @yoga.FlexDirection::Row
        "RowReverse" => @yoga.FlexDirection::RowReverse
        "Column" => @yoga.FlexDirection::Column
        "ColumnReverse" => @yoga.FlexDirection::ColumnReverse
        _ => return Err("样式数据：flex_direction「" + v + "」")
      }
      s.flex_direction = Some(x)
      Ok(())
    }
    "flex_wrap" => {
      let v = sd_variant(e)
      let x = match v {
        "NoWrap" => @yoga.FlexWrap::NoWrap
        "Wrap" => @yoga.FlexWrap::Wrap
        "WrapReverse" => @yoga.FlexWrap::WrapReverse
        _ => return Err("样式数据：flex_wrap「" + v + "」")
      }
      s.flex_wrap = Some(x)
      Ok(())
    }
    "justify_content" => {
      let v = sd_variant(e)
      let x = match v {
        "FlexStart" => @yoga.JustifyContent::FlexStart
        "FlexEnd" => @yoga.JustifyContent::FlexEnd
        "Center" => @yoga.JustifyContent::Center
        "SpaceBetween" => @yoga.JustifyContent::SpaceBetween
        "SpaceAround" => @yoga.JustifyContent::SpaceAround
        "SpaceEvenly" => @yoga.JustifyContent::SpaceEvenly
        _ => return Err("样式数据：justify_content「" + v + "」")
      }
      s.justify_content = Some(x)
      Ok(())
    }
    "align_items" | "align_self" => {
      let v = sd_variant(e)
      let x = match v {
        "Stretch" => @yoga.AlignItems::Stretch
        "FlexStart" => @yoga.AlignItems::FlexStart
        "FlexEnd" => @yoga.AlignItems::FlexEnd
        "Center" => @yoga.AlignItems::Center
        "Baseline" => @yoga.AlignItems::Baseline
        _ => return Err("样式数据：align_items「" + v + "」")
      }
      if name == "align_self" {
        s.align_self = Some(x)
      } else {
        s.align_items = Some(x)
      }
      Ok(())
    }
    "position" => {
      let v = sd_variant(e)
      let x = match v {
        "Relative" => @yoga.PositionType::Relative
        "Absolute" => @yoga.PositionType::Absolute
        _ => return Err("样式数据：position「" + v + "」")
      }
      s.position = Some(x)
      Ok(())
    }
    "z_index" => {
      s.z_index = Some(sd_need(sd_int(e)))
      Ok(())
    }
    "cursor" => {
      s.cursor = Some(sd_need(sd_int(e)))
      Ok(())
    }
    "padding" => {
      let v = sd_need(sd_num(e))
      s.padding_left = Some(v)
      s.padding_right = Some(v)
      s.padding_top = Some(v)
      s.padding_bottom = Some(v)
      Ok(())
    }
    "margin" => {
      let v = sd_need(sd_num(e))
      s.margin_left = Some(v)
      s.margin_right = Some(v)
      s.margin_top = Some(v)
      s.margin_bottom = Some(v)
      Ok(())
    }
    "gap" => {
      let v = sd_need(sd_num(e))
      s.row_gap = Some(v)
      s.column_gap = Some(v)
      Ok(())
    }
    "font_size" => {
      s.font_size = Some(sd_need(sd_num(e)))
      Ok(())
    }
    "line_height" => {
      s.line_height = Some(sd_need(sd_num(e)))
      Ok(())
    }
    "letter_spacing" => {
      s.letter_spacing = Some(sd_need(sd_num(e)))
      Ok(())
    }
    "width" => {
      s.width = Some(sd_need(sd_num(e)))
      Ok(())
    }
    "width_percent" => {
      s.width_percent = Some(sd_need(sd_num(e)))
      Ok(())
    }
    "height" => {
      s.height = Some(sd_need(sd_num(e)))
      Ok(())
    }
    "height_percent" => {
      s.height_percent = Some(sd_need(sd_num(e)))
      Ok(())
    }
    "min_width" => {
      s.min_width = Some(sd_need(sd_num(e)))
      Ok(())
    }
    "min_height" => {
      s.min_height = Some(sd_need(sd_num(e)))
      Ok(())
    }
    "max_width" => {
      s.max_width = Some(sd_need(sd_num(e)))
      Ok(())
    }
    "max_height" => {
      s.max_height = Some(sd_need(sd_num(e)))
      Ok(())
    }
    "padding_left" => {
      s.padding_left = Some(sd_need(sd_num(e)))
      Ok(())
    }
    "padding_right" => {
      s.padding_right = Some(sd_need(sd_num(e)))
      Ok(())
    }
    "padding_top" => {
      s.padding_top = Some(sd_need(sd_num(e)))
      Ok(())
    }
    "padding_bottom" => {
      s.padding_bottom = Some(sd_need(sd_num(e)))
      Ok(())
    }
    "margin_left" => {
      s.margin_left = Some(sd_need(sd_num(e)))
      Ok(())
    }
    "margin_right" => {
      s.margin_right = Some(sd_need(sd_num(e)))
      Ok(())
    }
    "margin_top" => {
      s.margin_top = Some(sd_need(sd_num(e)))
      Ok(())
    }
    "margin_bottom" => {
      s.margin_bottom = Some(sd_need(sd_num(e)))
      Ok(())
    }
    "border_width" => {
      s.border_width = Some(sd_need(sd_num(e)))
      Ok(())
    }
    "border_radius" => {
      s.border_radius = Some(sd_need(sd_num(e)))
      Ok(())
    }
    "flex" => {
      s.flex = Some(sd_need(sd_num(e)))
      Ok(())
    }
    "flex_shrink" => {
      s.flex_shrink = Some(sd_need(sd_num(e)))
      Ok(())
    }
    "flex_basis" => {
      s.flex_basis = Some(sd_need(sd_num(e)))
      Ok(())
    }
    "flex_basis_percent" => {
      s.flex_basis_percent = Some(sd_need(sd_num(e)))
      Ok(())
    }
    "row_gap" => {
      s.row_gap = Some(sd_need(sd_num(e)))
      Ok(())
    }
    "column_gap" => {
      s.column_gap = Some(sd_need(sd_num(e)))
      Ok(())
    }
    "top" => {
      s.top = Some(sd_need(sd_num(e)))
      Ok(())
    }
    "right" => {
      s.right = Some(sd_need(sd_num(e)))
      Ok(())
    }
    "bottom" => {
      s.bottom = Some(sd_need(sd_num(e)))
      Ok(())
    }
    "left" => {
      s.left = Some(sd_need(sd_num(e)))
      Ok(())
    }
    "opacity" => {
      s.opacity = Some(sd_need(sd_num(e)))
      Ok(())
    }
    "transition_ms" => {
      s.transition_ms = Some(sd_need(sd_num(e)))
      Ok(())
    }
    _ => Err("样式数据：属性「" + name + "」不在补丁表")
  }
}

///|
fn sd_build_style(
  props : Array[MJ],
) -> Result[@style.Style, String] raise SdRaise {
  let s = @style.empty_style()
  for p in props {
    let name = match mj_str(mj_get(p, "p")) {
      Some(v) => v
      None => return Err("样式数据：属性缺 p")
    }
    let e = match mj_str(mj_get(p, "e")) {
      Some(v) => v
      None => return Err("样式数据：属性缺 e")
    }
    match sd_set_prop(s, name, e) {
      Ok(_) => ()
      Err(x) => return Err(x)
    }
  }
  Ok(s)
}

///|
/// 补丁的 classes 数组 → 重注册命名类（同名覆盖，后写赢）。
fn mng_reg_classes_inner(
  rules : Array[MJ],
) -> Result[Unit, String] raise SdRaise {
  let base : Map[String, @style.Style] = Map([])
  let hover : Map[String, @style.Style] = Map([])
  let active : Map[String, @style.Style] = Map([])
  let focus : Map[String, @style.Style] = Map([])
  for r in rules {
    let name = match mj_str(mj_get(r, "n")) {
      Some(v) => v
      None => return Err("样式数据：规则缺 n")
    }
    let state = match mj_str(mj_get(r, "s")) {
      Some(v) => v
      None => ""
    }
    let props = match mj_arr(mj_get(r, "props")) {
      Some(v) => v
      None => []
    }
    let st = sd_need(sd_build_style(props))
    let key = if state == "dark" { name + ":dark" } else { name }
    if state == "" || state == "dark" {
      match base.get(key) {
        Some(prev) => {
          let _ = base.set(key, @style.merge(prev, st))
        }
        None => {
          let _ = base.set(key, st)
        }
      }
    } else if state == "hover" {
      match hover.get(name) {
        Some(prev) => {
          let _ = hover.set(name, @style.merge(prev, st))
        }
        None => {
          let _ = hover.set(name, st)
        }
      }
    } else if state == "active" {
      match active.get(name) {
        Some(prev) => {
          let _ = active.set(name, @style.merge(prev, st))
        }
        None => {
          let _ = active.set(name, st)
        }
      }
    } else if state == "focus" {
      match focus.get(name) {
        Some(prev) => {
          let _ = focus.set(name, @style.merge(prev, st))
        }
        None => {
          let _ = focus.set(name, st)
        }
      }
    } else {
      return Err("样式数据：状态「" + state + "」")
    }
  }
  // 只有 :hover/:active/:focus 的类也要有基档（空 Style）
  for (n, _) in hover {
    if base.get(n) is None {
      let _ = base.set(n, @style.empty_style())
    }
  }
  for (n, _) in active {
    if base.get(n) is None {
      let _ = base.set(n, @style.empty_style())
    }
  }
  for (n, _) in focus {
    if base.get(n) is None {
      let _ = base.set(n, @style.empty_style())
    }
  }
  for (n, s) in base {
    match hover.get(n) {
      Some(h) => s.hover = Some(h)
      None => ()
    }
    match active.get(n) {
      Some(a) => s.active = Some(a)
      None => ()
    }
    match focus.get(n) {
      Some(f) => s.focus = Some(f)
      None => ()
    }
    @style.define_class(n, s)
  }
  Ok(())
}

///|
fn mng_reg_classes(rules : Array[MJ]) -> Result[Unit, String] {
  mng_reg_classes_inner(rules) catch {
    SdRaise(e) => Err(e)
  }
}
