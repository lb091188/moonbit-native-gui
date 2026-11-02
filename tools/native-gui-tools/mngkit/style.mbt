// 样式章：`<style>` 段解析与摊平。类选择器 → `define_class` 注册条目；
// 元素 `class="a b"` → `class_of(["a","b"])`。属性名 = `@style.style` 工厂的参数名
// （CSS kebab 写法自动转 snake），值形态四档：数字、`var(--令牌)`、颜色字面量、关键字。
// 深浅两份值：`.a:dark { … }` 注册成第二枚同名加 `:dark` 的类，选用在生成码里按
// `@win.sys_color_scheme()` 判定（应用自管深浅请走 token，主题表本身就是两份值）。
// 不做：运行时级联、特异性、继承、伪类、后代选择器（冲突编译期报错）。

///|
priv struct StyleProp {
  name : String
  expr : String
}

///|
priv struct StyleRule {
  class : String
  dark : Bool
  props : Array[StyleProp]
}

///|
/// 主题色令牌（Theme 的 20 个字段名，绘制期按当前主题落色）。
fn color_tokens() -> Array[String] {
  [
    "primary",
    "primary_light",
    "primary_hover",
    "danger",
    "danger_light",
    "danger_hover",
    "success",
    "success_light",
    "warning",
    "warning_light",
    "info",
    "info_light",
    "text_primary",
    "text_regular",
    "text_secondary",
    "border",
    "fill_hover",
    "fill_zebra",
    "bg_page",
    "bg_panel",
  ]
}

///|
/// 数值尺度令牌 → MoonBit 表达式（`pub let` 直取、`pub fn` 带括号）。
fn scale_token_expr(tok : String) -> String? {
  match tok {
    "control_height" => Some("@theme.control_height")
    "font_size_body" => Some("@theme.font_size_body")
    "font_size_secondary" => Some("@theme.font_size_secondary")
    "font_size_section" => Some("@theme.font_size_section")
    "font_size_title" => Some("@theme.font_size_title")
    "radius_ctrl" => Some("@theme.radius_ctrl()")
    "radius_card" => Some("@theme.radius_card()")
    "radius_overlay" => Some("@theme.radius_overlay()")
    _ => None
  }
}

///|
/// 属性名 → 类别（决定允许的值形态与字面量强制范围）。
priv enum PropKind {
  PKColor
  PKNumber
  PKInt
  PKString
  PKEnum(String, String) // (类型全路径, 关键字表 `键=MoonBit 构造子` 串)
  PKUnknown
}

///|
fn prop_kind_of(name : String) -> PropKind {
  match name {
    "color" | "background_color" | "border_color" => PKColor
    "font_family" => PKString
    "z_index" | "cursor" => PKInt
    "font_weight" => PKEnum("@text.FontWeight", "thin=Thin,extra_light=ExtraLight,light=Light,normal=Normal,medium=Medium,semi_bold=SemiBold,bold=Bold,extra_bold=ExtraBold,black=Black")
    "text_align" => PKEnum("@text.TextAlign", "start=Start,left=Start,center=Center,end=End,right=End")
    "white_space" => PKEnum("@style.WhiteSpace", "normal=Normal,no_wrap=NoWrap")
    "border_style" => PKEnum("@style.BorderStyle", "solid=Solid,dashed=Dashed,dotted=Dotted")
    "visibility" => PKEnum("@style.Visibility", "visible=Visible,hidden=Hidden")
    _ =>
      if arr_contains(number_props(), name) {
        PKNumber
      } else {
        PKUnknown
      }
  }
}

///|
fn number_props() -> Array[String] {
  [
    "font_size",
    "line_height",
    "letter_spacing",
    "width",
    "width_percent",
    "height",
    "height_percent",
    "min_width",
    "min_height",
    "max_width",
    "max_height",
    "padding",
    "padding_left",
    "padding_right",
    "padding_top",
    "padding_bottom",
    "margin",
    "margin_left",
    "margin_right",
    "margin_top",
    "margin_bottom",
    "border_width",
    "border_radius",
    "flex",
    "gap",
    "row_gap",
    "column_gap",
    "top",
    "right",
    "bottom",
    "left",
    "opacity",
    "transition_ms",
  ]
}

///|
/// 「样式字面量」强制范围：这几档属性值必须进 `<style>` 或 `class`，
/// 模板里写死字面量即编译报错（它们正是随主题变的那一组）。
fn themed_props() -> Array[String] {
  [
    "color",
    "background_color",
    "border_color",
    "border_width",
    "border_radius",
    "font_size",
    "font_family",
    "font_weight",
    "opacity",
  ]
}

///|
/// 十六进制颜色串校验（#rgb / #rrggbb）。
fn is_hex_color(v : String) -> Bool {
  let a = chars_of(v)
  let n = a.length()
  if n != 4 && n != 7 {
    return false
  }
  if a[0] != '#' {
    return false
  }
  let mut ok = true
  for k in 1..<n {
    let c = a[k]
    let hex = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F')
    if !hex {
      ok = false
    }
  }
  ok
}

///|
/// 数值串 → MoonBit Double 字面量（无小数点补 `.0`）。
fn num_lit(v : String) -> String {
  if contains_sub(v, ".") || contains_sub(v, "e") || contains_sub(v, "E") {
    v
  } else {
    v + ".0"
  }
}

///|
/// 属性值原文 → MoonBit 表达式。
fn style_value_of(prop : String, raw : String, pos : Pos) -> Result[String, String] {
  let v = raw.trim().to_owned()
  let kind = prop_kind_of(prop)
  if v.length() == 0 {
    return Err("\{pos_str(pos)}：属性 `\{prop}` 缺值")
  }
  if v.has_prefix("var(") {
    let inner = v[4:v.length() - 1].to_owned().trim().to_owned()
    if !inner.has_prefix("--") {
      return Err("\{pos_str(pos)}：`var()` 里要写 `--令牌`")
    }
    let tok = inner[2:].to_owned()
    match kind {
      PKColor =>
        if arr_contains(color_tokens(), tok) {
          Ok(q(tok))
        } else {
          Err("\{pos_str(pos)}：`--\{tok}` 不是主题色令牌（20 枚：primary/text_primary/bg_panel…）")
        }
      PKNumber =>
        match scale_token_expr(tok) {
          Some(e) => Ok(e)
          None => Err("\{pos_str(pos)}：`--\{tok}` 不是数值尺度令牌（control_height/font_size_*/radius_*）")
        }
      _ => Err("\{pos_str(pos)}：`var()` 只用于颜色属性与数值尺度属性")
    }
  } else {
    match kind {
      PKColor =>
        if is_hex_color(v) {
          Ok(q(v))
        } else {
          Err("\{pos_str(pos)}：颜色要写 `var(--令牌)` 或 `#rrggbb`，见到 `\{v}`")
        }
      PKNumber =>
        if is_number_text(v) {
          Ok(num_lit(v))
        } else {
          Err("\{pos_str(pos)}：`\{prop}` 要数值或 `var(--令牌)`，见到 `\{v}`")
        }
      PKInt =>
        if is_number_text(v) {
          Ok(int_text(v))
        } else {
          Err("\{pos_str(pos)}：`\{prop}` 要整数，见到 `\{v}`")
        }
      PKString =>
        if (v.has_prefix("\"") && v.has_suffix("\"")) || (v.has_prefix("'") && v.has_suffix("'")) {
          Ok("\"" + v[1:v.length() - 1].to_owned() + "\"")
        } else {
          Err("\{pos_str(pos)}：`\{prop}` 要引号包裹的串，见到 `\{v}`")
        }
      PKEnum(path, table) => {
        let key = snake(v)
        let toks = split_arr(table, ",")
        let mut found = ""
        for t in toks {
          let kv = split_arr(t, "=")
          if kv.length() == 2 && kv[0] == key {
            found = path + "::" + kv[1]
            break
          }
        }
        if found.length() > 0 {
          Ok(found)
        } else {
          Err("\{pos_str(pos)}：`\{prop}` 不认关键字 `\{v}`")
        }
      }
      PKUnknown => Err("\{pos_str(pos)}：`\{prop}` 不是 Style 属性")
    }
  }
}

///|
/// 整数文本（去掉小数尾巴）。
fn int_text(v : String) -> String {
  let dot = dot_pos(v)
  match dot {
    Some(d) => v[:d].to_owned()
    None => v
  }
}

///|
fn dot_pos(v : String) -> Int? {
  let a = chars_of(v)
  let mut i = 0
  while i < a.length() {
    if a[i] == '.' {
      return Some(i)
    }
    i += 1
  }
  None
}

///|
/// 数值文本判定：可选负号 + 数字 + 可选小数/指数。
fn is_number_text(v : String) -> Bool {
  let a = chars_of(v)
  let n = a.length()
  if n == 0 {
    return false
  }
  let mut i = if a[0] == '-' || a[0] == '+' { 1 } else { 0 }
  let mut digits = 0
  let mut dots = 0
  let mut ok = true
  while i < n {
    let c = a[i]
    if is_digit(c) {
      digits += 1
    } else if c == '.' {
      dots += 1
    } else if c == 'e' || c == 'E' {
      i += 1
      if i < n && (a[i] == '+' || a[i] == '-') {
        i += 1
      }
      continue
    } else {
      ok = false
    }
    i += 1
  }
  ok && digits > 0 && dots <= 1
}

///|
/// 选择器原文 → (类名, 是否深色档)：只认 `.名` 与 `.名:dark`。
fn parse_selector(sel : String, pos : Pos) -> Result[(String, Bool), String] {
  let s = sel.trim().to_owned()
  if !s.has_prefix(".") {
    return Err("\{pos_str(pos)}：`<style>` v1 只支持类选择器 `.名`（元素/ID/属性/后代选择器不做）")
  }
  let body = s[1:].to_owned()
  let a = chars_of(body)
  let mut i = 0
  while i < a.length() && (is_ident_char(a[i]) || a[i] == '-') {
    i += 1
  }
  let name = slice_str(a, 0, i)
  let rest = slice_str(a, i, a.length()).trim().to_owned()
  if name.length() == 0 {
    return Err("\{pos_str(pos)}：类名缺失")
  }
  if rest.length() == 0 {
    Ok((name, false))
  } else if rest == ":dark" {
    Ok((name, true))
  } else {
    Err("\{pos_str(pos)}：选择器只允许 `.名` 或 `.名:dark`，见到 `\{s}`")
  }
}

///|
/// `<style>` 段原文 → 规则表。重复声明同类同名属性以最后一次为准（编译期摊平）。
fn parse_style(text : String) -> Result[Array[StyleRule], String] {
  let c = make_cur(text)
  let rules : Array[StyleRule] = []
  let n = text.length()
  while true {
    skip_ws(c)
    if c.i >= n {
      break
    }
    if skip_comment(c) {
      continue
    }
    let sel_pos = pos_at(c, c.i)
    let sel = read_while(c, fn(ch) { ch != '{' })
    if sel.trim().to_owned().length() == 0 {
      return Err(cur_err(c, "选择器缺失"))
    }
    let (cls, dark) = match parse_selector(sel, sel_pos) {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    match expect(c, '{', "规则块开始") {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
    let props : Array[StyleProp] = []
    let mut loop_guard = 0
    while loop_guard < 200 {
      loop_guard += 1
      skip_ws(c)
      if c.i >= n {
        return Err(cur_err(c, "规则块 `.\{cls}` 未闭合"))
      }
      if cur_peek(c) == '}' {
        c.i += 1
        break
      }
      if skip_comment(c) {
        continue
      }
      let ppos = pos_at(c, c.i)
      let pname = read_while(c, fn(ch) { ch != ':' && ch != '}' && ch != ';' })
      let key = snake(pname.trim().to_owned())
      if key.length() == 0 {
        return Err(cur_err(c, "属性名缺失"))
      }
      if c.i < n && cur_peek(c) == ':' {
        c.i += 1
      } else {
        return Err(cur_err(c, "属性 `\{key}` 缺冒号"))
      }
      let raw = read_while(c, fn(ch) { ch != ';' && ch != '}' })
      let e = match style_value_of(key, raw, ppos) {
        Ok(v) => v
        Err(x) => return Err(x)
      }
      props.push({ name: key, expr: e })
      if c.i < n && cur_peek(c) == ';' {
        c.i += 1
      }
    }
    rules.push({ class: cls, dark, props })
  }
  Ok(rules)
}

///|
/// 跳过 `/* … */` 与 `// …` 注释；命中返回 true。
fn skip_comment(c : Cur) -> Bool {
  let n = c.cs.length()
  if c.i + 1 < n && c.cs[c.i] == '/' && c.cs[c.i + 1] == '*' {
    c.i += 2
    while c.i + 1 < n && !(c.cs[c.i] == '*' && c.cs[c.i + 1] == '/') {
      c.i += 1
    }
    if c.i + 1 < n {
      c.i += 2
    }
    true
  } else if c.i + 1 < n && c.cs[c.i] == '/' && c.cs[c.i + 1] == '/' {
    while c.i < n && c.cs[c.i] != '\n' {
      c.i += 1
    }
    true
  } else {
    false
  }
}

///|
/// 规则表 → `define_class` 注册语句（深色档注册成 `名:dark` 独立条目）。
fn style_defs(rules : Array[StyleRule]) -> Array[String] {
  let out : Array[String] = []
  for r in rules {
    let args : Array[String] = []
    for p in r.props {
      args.push(p.name + "=" + p.expr)
    }
    let key = if r.dark { r.class + ":dark" } else { r.class }
    out.push(
      "  @style.define_class(" + q(key) + ", @style.style(" + args.join(", ") + "))",
    )
  }
  out
}

///|
/// 规则表里是否存在该类名的深色档。
fn has_dark_variant(rules : Array[StyleRule], cls : String) -> Bool {
  for r in rules {
    if r.dark && r.class == cls {
      return true
    }
  }
  false
}

///|
/// `class="a b"` → `class_of(…)` 表达式；带深色档的类按系统深浅偏好选两枚之一。
fn class_expr(rules : Array[StyleRule], names : Array[String]) -> String {
  let mut any_dark = false
  for nm in names {
    if has_dark_variant(rules, nm) {
      any_dark = true
    }
  }
  let light : Array[String] = []
  let dark : Array[String] = []
  for nm in names {
    light.push(q(nm))
    dark.push(q(nm))
    if has_dark_variant(rules, nm) {
      dark.push(q(nm + ":dark"))
    }
  }
  let base = "@style.class_of([" + light.join(", ") + "])"
  if any_dark {
    let d = dark.join(", ")
    let l = light.join(", ")
    let pre = "@style.class_of(if @win.sys_color_scheme() == \"dark\" { ["
    let mid = "] } else { ["
    pre + d + mid + l + "] })"
  } else {
    base
  }
}

///|
/// 属性值原文 → 类名数组（`class="a b"` 空白分隔）。
fn class_names_of(raw : String) -> Array[String] {
  let out : Array[String] = []
  let a = chars_of(raw)
  let mut cur = ""
  for c in a {
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      if cur.length() > 0 {
        out.push(cur)
        cur = ""
      }
    } else if c != '"' && c != '\'' {
      cur = cur + c.to_string()
    }
  }
  if cur.length() > 0 {
    out.push(cur)
  }
  out
}
