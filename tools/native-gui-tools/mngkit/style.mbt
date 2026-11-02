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
  // "" = 基档；dark = 深色档（独立类）；hover/active/focus = 状态桶
  state : String
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
/// `<style>` 可用的主题色令牌名（不带 `--`，编辑器补全用）。
pub fn style_color_tokens() -> Array[String] {
  color_tokens()
}

///|
/// `<style>` 可用的数值尺度令牌名（不带 `--`）。
pub fn style_scale_tokens() -> Array[String] {
  [
    "control_height",
    "font_size_body",
    "font_size_secondary",
    "font_size_section",
    "font_size_title",
    "radius_ctrl",
    "radius_card",
    "radius_overlay",
  ]
}

///|
/// `<style>` 可写的属性名（kebab 写法，编辑器补全用）。
pub fn style_props() -> Array[String] {
  let snake_names : Array[String] = [
    "color",
    "background_color",
    "border_color",
    "font_family",
    "z_index",
    "cursor",
    "font_weight",
    "text_align",
    "white_space",
    "border_style",
    "visibility",
    "display",
    "flex_direction",
    "flex_wrap",
    "justify_content",
    "align_items",
    "align_self",
    "position",
    "flex",
    "flex-shrink",
    "opacity",
    "transition-duration",
  ]
  let out : Array[String] = []
  for n in snake_names {
    out.push(kebab_name(n))
  }
  for n in number_props() {
    let k = kebab_name(n)
    if !arr_contains(out, k) {
      out.push(k)
    }
  }
  out
}

///|
fn kebab_name(s : String) -> String {
  let out = StringBuilder()
  for c in s {
    if c == '_' {
      out.write_char('-')
    } else {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
/// 属性名 → 类别（决定允许的值形态与字面量强制范围）。
priv enum PropKind {
  PKColor
  PKNumber // 长度：`16px` / 0 / width·height 的 `%`
  PKFactor // 无单位数值：opacity / flex-shrink
  PKTime // 时间：transition-duration（毫秒）
  PKInt
  PKString
  PKEnum(String, String) // (类型全路径, 关键字表 `键=MoonBit 构造子` 串)
  PKKwInt(String) // 关键字 → 整数（cursor）
  PKUnknown
}

///|
fn prop_kind_of(name : String) -> PropKind {
  match name {
    "color" | "background_color" | "border_color" => PKColor
    "font_family" => PKString
    "z_index" => PKInt
    "cursor" => PKKwInt("default=0,pointer=1,text=2")
    "opacity" | "flex_shrink" => PKFactor
    "transition_duration" => PKTime
    "font_weight" =>
      PKEnum("@text.FontWeight", "normal=Normal,bold=Bold,100=Thin,200=ExtraLight,300=Light,400=Normal,500=Medium,600=SemiBold,700=Bold,800=ExtraBold,900=Black")
    "text_align" => PKEnum("@text.TextAlign", "start=Start,left=Start,center=Center,end=End,right=End")
    "white_space" => PKEnum("@style.WhiteSpace", "normal=Normal,no_wrap=NoWrap")
    "border_style" => PKEnum("@style.BorderStyle", "solid=Solid,dashed=Dashed,dotted=Dotted")
    "visibility" => PKEnum("@style.Visibility", "visible=Visible,hidden=Hidden")
    // 布局枚举（@yoga 类型；模板所在包需 import NoahLiu/yoga-mbt/src as @yoga）
    "display" => PKEnum("@yoga.Display", "flex=Flex,none=None")
    "flex_direction" =>
      PKEnum("@yoga.FlexDirection", "row=Row,row_reverse=RowReverse,column=Column,column_reverse=ColumnReverse")
    "flex_wrap" => PKEnum("@yoga.FlexWrap", "nowrap=NoWrap,no_wrap=NoWrap,wrap=Wrap,wrap_reverse=WrapReverse")
    "justify_content" =>
      PKEnum("@yoga.JustifyContent", "flex_start=FlexStart,start=FlexStart,left=FlexStart,flex_end=FlexEnd,end=FlexEnd,right=FlexEnd,center=Center,space_between=SpaceBetween,space_around=SpaceAround,space_evenly=SpaceEvenly")
    "align_items" | "align_self" =>
      PKEnum("@yoga.AlignItems", "stretch=Stretch,flex_start=FlexStart,start=FlexStart,flex_end=FlexEnd,end=FlexEnd,center=Center,baseline=Baseline")
    "position" => PKEnum("@yoga.PositionType", "relative=Relative,absolute=Absolute")
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
    "height",
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
    "gap",
    "row_gap",
    "column_gap",
    "top",
    "right",
    "bottom",
    "left",
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
/// 无单位数值（flex-grow / flex-shrink / opacity）：CSS 的 `<number>`。
fn bare_number(v : String) -> String? {
  let s = v.trim().to_owned()
  if is_number_text(s) {
    Some(num_lit(s))
  } else {
    None
  }
}

///|
/// 文本是否是「零」（`0` / `0.0` / `-0`）——CSS 长度里只有 0 可省略单位。
fn is_zero_text(s : String) -> Bool {
  let a = chars_of(s)
  let mut i = 0
  if i < a.length() && (a[i] == '-' || a[i] == '+') {
    i += 1
  }
  let mut digits = 0
  while i < a.length() {
    let c = a[i]
    if c >= '0' && c <= '9' {
      if c != '0' {
        return false
      }
      digits += 1
    } else if c != '.' {
      return false
    }
    i += 1
  }
  digits > 0
}

///|
/// CSS 长度：`16px`，或零可省略单位；百分比只走 width/height。
fn length_or_zero(v : String) -> String? {
  let s = v.trim().to_owned()
  if s.length() > 2 && s.has_suffix("px") {
    let head = s[:s.length() - 2].to_owned().trim().to_owned()
    if is_number_text(head) {
      return Some(num_lit(head))
    }
  }
  if is_zero_text(s) {
    Some("0.0")
  } else {
    None
  }
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
/// 空白切分（非空段）。
fn split_ws(s : String) -> Array[String] {
  let out : Array[String] = []
  let a = chars_of(s)
  let mut cur = ""
  for c in a {
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      if cur.length() > 0 {
        out.push(cur)
        cur = ""
      }
    } else {
      cur = cur + c.to_string()
    }
  }
  if cur.length() > 0 {
    out.push(cur)
  }
  out
}

///|
/// flex basis：`<n>%` 进百分比字段，数字进像素字段；`auto` 等不收。
fn flex_basis_pair(tok : String, pos : Pos) -> Result[(String, String), String] {
  let a = chars_of(tok)
  if a.length() > 1 && a[a.length() - 1] == '%' {
    let num = slice_str(a, 0, a.length() - 1).trim().to_owned()
    if is_number_text(num) {
      return Ok(("flex_basis_percent", num_lit(num)))
    }
  }
  match length_or_zero(tok) {
    Some(e) => Ok(("flex_basis", e))
    None => {
      Err(
        "\{pos_str(pos)}：flex basis 要像素或百分比（`100%` / `120px` / `0`）；`auto` 用 width/height 表达",
      )
    }
  }
}

///|
/// 属性展开：`flex` 按 CSS 简写拆成 grow/shrink/basis 三件套，`flex_basis` 认百分比，
/// 其余属性单值直传。
fn style_expand(prop : String, raw : String, pos : Pos) -> Result[Array[(String, String)], String] {
  if prop == "flex" {
    let toks = split_ws(raw)
    if toks.length() == 0 {
      return Err("\{pos_str(pos)}：flex 缺值")
    }
    if toks.length() > 3 {
      return Err("\{pos_str(pos)}：flex 最多三段：grow shrink basis")
    }
    let grow = match bare_number(toks[0]) {
      Some(e) => e
      None =>
        return Err(
          "\{pos_str(pos)}：flex 要 CSS 简写（grow / grow shrink / grow shrink basis），grow 是无单位数，见到 `\{toks[0]}`",
        )
    }
    let out : Array[(String, String)] = []
    out.push(("flex", grow))
    let shrink = if toks.length() >= 2 {
      match bare_number(toks[1]) {
        Some(e) => e
        None => return Err("\{pos_str(pos)}：flex shrink 要无单位数值，见到 `\{toks[1]}`")
      }
    } else {
      "1.0"
    }
    out.push(("flex_shrink", shrink))
    let basis_tok = if toks.length() == 3 { toks[2] } else { "0" }
    match flex_basis_pair(basis_tok, pos) {
      Ok(p) => out.push(p)
      Err(e) => return Err(e)
    }
    Ok(out)
  } else if prop == "flex_basis" {
    match flex_basis_pair(raw.trim().to_owned(), pos) {
      Ok(p) => Ok([p])
      Err(e) => Err(e)
    }
  } else {
    match style_value_of(prop, raw, pos) {
      Ok(p) => Ok([p])
      Err(x) => Err(x)
    }
  }
}

///|
/// 百分比属性 → Style 字段名（`width: 100%` → `width_percent`）。
fn percent_prop(prop : String) -> String? {
  match prop {
    "width" => Some("width_percent")
    "height" => Some("height_percent")
    _ => None
  }
}

///|
/// 属性值原文 → (Style 字段名, MoonBit 表达式)。
fn style_value_of(prop : String, raw : String, pos : Pos) -> Result[(String, String), String] {
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
          Ok((prop, q(tok)))
        } else {
          Err("\{pos_str(pos)}：`--\{tok}` 不是主题色令牌（20 枚：primary/text_primary/bg_panel…）")
        }
      PKNumber =>
        match scale_token_expr(tok) {
          Some(e) => Ok((prop, e))
          None => Err("\{pos_str(pos)}：`--\{tok}` 不是数值尺度令牌（control_height/font_size_*/radius_*）")
        }
      _ => Err("\{pos_str(pos)}：`var()` 只用于颜色属性与数值尺度属性")
    }
  } else {
    match kind {
      PKColor =>
        if is_hex_color(v) {
          Ok((prop, q(v)))
        } else {
          Err("\{pos_str(pos)}：颜色要写 `var(--令牌)` 或 `#rrggbb`，见到 `\{v}`")
        }
      PKNumber =>
        if v.has_suffix("%") {
          let head = v[:v.length() - 1].to_owned().trim().to_owned()
          let target = match percent_prop(prop) {
            Some(t) => t
            None =>
              return Err(
                "\{pos_str(pos)}：`\{prop}` 不吃百分比（`width` / `height` 可写 `100%`）",
              )
          }
          if is_number_text(head) {
            Ok((target, num_lit(head)))
          } else {
            Err("\{pos_str(pos)}：`\{prop}` 的百分比要数值，见到 `\{v}`")
          }
        } else {
          match length_or_zero(v) {
            Some(e) => Ok((prop, e))
            None =>
              Err(
                "\{pos_str(pos)}：`\{prop}` 要像素长度（`16px`；0 可省略单位）或 `var(--令牌)`，见到 `\{v}`",
              )
          }
        }
      PKFactor =>
        match bare_number(v) {
          Some(e) => Ok((prop, e))
          None => Err("\{pos_str(pos)}：`\{prop}` 要无单位数值（如 `1`），见到 `\{v}`")
        }
      PKTime =>
        if v.length() > 2 && v.has_suffix("ms") {
          let head = v[:v.length() - 2].to_owned().trim().to_owned()
          if is_number_text(head) {
            Ok(("transition_ms", num_lit(head)))
          } else {
            Err("\{pos_str(pos)}：`transition-duration` 的时长要数值 + `ms`，见到 `\{v}`")
          }
        } else {
          Err(
            "\{pos_str(pos)}：`transition-duration` 要毫秒（`120ms`）；秒制请先换算成毫秒",
          )
        }
      PKKwInt(table) => {
        let key = snake(v)
        let toks = split_arr(table, ",")
        let mut found = ""
        for t in toks {
          let kv = split_arr(t, "=")
          if kv.length() == 2 && kv[0] == key {
            found = kv[1]
            break
          }
        }
        if found.length() > 0 {
          Ok((prop, found))
        } else {
          Err("\{pos_str(pos)}：`cursor` 只认 default / pointer / text，见到 `\{v}`")
        }
      }
      PKInt =>
        if is_number_text(v) {
          Ok((prop, int_text(v)))
        } else {
          Err("\{pos_str(pos)}：`\{prop}` 要整数，见到 `\{v}`")
        }
      PKString =>
        if (v.has_prefix("\"") && v.has_suffix("\"")) || (v.has_prefix("'") && v.has_suffix("'")) {
          Ok((prop, "\"" + v[1:v.length() - 1].to_owned() + "\""))
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
          Ok((prop, found))
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
fn parse_selector(sel : String, pos : Pos) -> Result[(String, String), String] {
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
    Ok((name, ""))
  } else if rest == ":dark" {
    Ok((name, "dark"))
  } else if rest == ":hover" || rest == ":active" || rest == ":focus" {
    Ok((name, rest[1:].to_owned()))
  } else {
    Err(
      "\{pos_str(pos)}：选择器只允许 `.名` / `.名:dark` / `.名:hover` / `.名:active` / `.名:focus`，见到 `\{s}`",
    )
  }
}

///|
/// 段内位置 → 模板文件位置。`line0` 是内容首行的 1 基行号，段内 `pos.line` 也是
/// 1 基，首行重叠一次故减 1。
fn shift_pos(pos : Pos, line0 : Int) -> Pos {
  { line: pos.line + line0 - 1, col: pos.col }
}

///|
/// 段内打错的坐标补上 `<style>` 的行偏移。
fn style_err(c : Cur, line0 : Int, msg : String) -> String {
  "\{pos_str(shift_pos(pos_at(c, c.i), line0))}：\{msg}"
}

///|
/// `<style>` 段原文 → 规则表。重复声明同类同名属性以最后一次为准（编译期摊平）。
fn parse_style(text : String, line0 : Int) -> Result[Array[StyleRule], String] {
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
    let sel_pos = shift_pos(pos_at(c, c.i), line0)
    let sel = read_while(c, fn(ch) { ch != '{' })
    if sel.trim().to_owned().length() == 0 {
      return Err(style_err(c, line0, "选择器缺失"))
    }
    let (cls, state) = match parse_selector(sel, sel_pos) {
      Ok(v) => v
      Err(e) => return Err(e)
    }
    if c.i < n && cur_peek(c) == '{' {
      c.i += 1
    } else {
      return Err(style_err(c, line0, "规则块开始要写 `{`"))
    }
    let props : Array[StyleProp] = []
    let mut loop_guard = 0
    while loop_guard < 200 {
      loop_guard += 1
      skip_ws(c)
      if c.i >= n {
        return Err(style_err(c, line0, "规则块 `.\{cls}` 未闭合"))
      }
      if cur_peek(c) == '}' {
        c.i += 1
        break
      }
      if skip_comment(c) {
        continue
      }
      let ppos = shift_pos(pos_at(c, c.i), line0)
      let pname = read_while(c, fn(ch) { ch != ':' && ch != '}' && ch != ';' })
      let key = snake(pname.trim().to_owned())
      if key.length() == 0 {
        return Err(style_err(c, line0, "属性名缺失"))
      }
      if c.i < n && cur_peek(c) == ':' {
        c.i += 1
      } else {
        return Err(style_err(c, line0, "属性 `\{key}` 缺冒号"))
      }
      let raw = read_while(c, fn(ch) { ch != ';' && ch != '}' })
      let pairs = match style_expand(key, raw, ppos) {
        Ok(v) => v
        Err(x) => return Err(x)
      }
      for (n, e) in pairs {
        props.push({ name: n, expr: e })
      }
      if c.i < n && cur_peek(c) == ';' {
        c.i += 1
      }
    }
    rules.push({ class: cls, state, props })
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
fn props_expr(props : Array[StyleProp]) -> String {
  let order : Array[String] = []
  let vals : Map[String, String] = Map([])
  for p in props {
    if !arr_contains(order, p.name) {
      order.push(p.name)
    }
    let _ = vals.set(p.name, p.expr)
  }
  let args : Array[String] = []
  for n in order {
    args.push(n + "=" + vals.get_or_default(n, ""))
  }
  args.join(", ")
}

///|
/// 规则表 → `define_class` 注册语句。同名类收成一条：基档进 `style(...)`，
/// `:hover` / `:active` / `:focus` 各挂成状态桶（`.hover(style(...))`…）；
/// `:dark` 仍是独立的 `名:dark` 类（深浅两份值）。
fn style_defs(rules : Array[StyleRule]) -> Array[String] {
  let out : Array[String] = []
  let names : Array[String] = []
  let darks : Array[String] = []
  for r in rules {
    let bucket = if r.state == "dark" { darks } else { names }
    if !arr_contains(bucket, r.class) {
      bucket.push(r.class)
    }
  }
  for n in names {
    let base : Array[StyleProp] = []
    for r in rules {
      if r.class == n && r.state == "" {
        for p in r.props {
          base.push(p)
        }
      }
    }
    let mut expr = "@style.style(" + props_expr(base) + ")"
    for st in ["hover", "active", "focus"] {
      let ps : Array[StyleProp] = []
      for r in rules {
        if r.class == n && r.state == st {
          for p in r.props {
            ps.push(p)
          }
        }
      }
      if ps.length() > 0 {
        expr = expr + "." + st + "(" + props_expr(ps) + ")"
      }
    }
    out.push("  @style.define_class(" + q(n) + ", " + expr + ")")
  }
  for n in darks {
    let ps : Array[StyleProp] = []
    for r in rules {
      if r.class == n && r.state == "dark" {
        for p in r.props {
          ps.push(p)
        }
      }
    }
    out.push("  @style.define_class(" + q(n + ":dark") + ", @style.style(" + props_expr(ps) + "))")
  }
  out
}

///|
/// 规则表里是否存在该类名的深色档。
fn has_dark_variant(rules : Array[StyleRule], cls : String) -> Bool {
  for r in rules {
    if r.state == "dark" && r.class == cls {
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

///|
/// `<style>` 规则 → 补丁用类定义数据：`[{n:类名, s:状态, props:[{p,e}]}]`。
/// `e` 是编译期已算好的 MoonBit 值表达式，应用侧按属性名落到 Style 字段。
fn style_classes_json(text : String, line0 : Int) -> Result[String, String] {
  let rules = match parse_style(text, line0) {
    Ok(v) => v
    Err(e) => return Err(e)
  }
  let xs : Array[String] = []
  for r in rules {
    let ps : Array[String] = []
    for p in r.props {
      ps.push("{\"p\":\"" + jstr(p.name) + "\",\"e\":\"" + jstr(p.expr) + "\"}")
    }
    xs.push(
      "{\"n\":\"" + jstr(r.class) + "\",\"s\":\"" + jstr(r.state) + "\",\"props\":[" +
      ps.join(",") +
      "]}",
    )
  }
  Ok("[" + xs.join(",") + "]")
}
