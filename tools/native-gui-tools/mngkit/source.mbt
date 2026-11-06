// 公共类型与小助手：位置、错误、属性分类、模板树、字面量判定。

///|
priv struct Pos {
  line : Int32
  col : Int32
}

///|
fn pos_str(p : Pos) -> String {
  "行 \{p.line} 列 \{p.col}"
}

///|
priv enum AttrKind {
  Plain
  Dyn
  Event
  Model
  If
  ElseIf
  Else
  Show
  For
  Key
}

///|
priv struct Attr {
  kind : AttrKind
  name : String
  value : String
  has_value : Bool
  pos : Pos
}

///|
priv enum TNode {
  Elem(String, Array[Attr], Array[TNode], Pos)
  Text(String, Pos)
}

///|
priv enum SlotKind {
  KStore
  KSignal
  KList // @base.ListStore[T]：keyed 列表源（v-for）；方法调用保持原样，不补 .get()
  KPlain
}

///|
/// 组件声明：模板标签 → 调用路径 + 位置参数顺序（children/child/text 特殊名）。
priv struct CompDecl {
  path : String
  positional : Array[String]
}

///|
/// 函数参数：`labelled` = 写了 `?`（可具名传、可省）；`ty` = 类型原文。
priv struct Param {
  name : String
  labelled : Bool
  ty : String
  // `= 默认值` 原文（无默认给空串）
  default : String
  // 参数上方紧贴的 `///` 文档行（没有给空串）
  doc : String
}

///|
/// 函数签名：名字 + 参数表 + 返回类型原文（无返回类型为空串）。
priv struct FnSig {
  name : String
  params : Array[Param]
  ret : String
}

///|
fn skip_ws_at(a : Array[Char], i : Int32) -> Int32 {
  let mut k = i
  while k < a.length() &&
        (a[k] == ' ' || a[k] == '\t' || a[k] == '\n' || a[k] == '\r') {
    k += 1
  }
  k
}

///|
fn slice_str(a : Array[Char], lo : Int32, hi : Int32) -> String {
  if hi <= lo {
    ""
  } else {
    a[lo:hi].map(fn(c) { c.to_string() }).join("")
  }
}

///|
/// 一个参数段 → Param：`名` / `名?` + `: 类型`（默认值原文丢弃，已由函数体承接）。
/// 注释行、`self`、无名段返回 None（调用方跳过）。

///|
/// 参数段拆出上方紧贴的 `///` 文档行与参数本体。
fn split_param_doc(seg : String) -> (String, String) {
  let doc : Array[String] = []
  let body : Array[String] = []
  let mut seen_body = false
  for l in split_arr(seg, "\n") {
    let t = l.trim().to_owned()
    if !seen_body && t.length() == 0 {
      continue
    }
    if !seen_body && t.has_prefix("///") {
      let cs = chars_of(t)
      doc.push(slice_str(cs, 3, cs.length()).trim().to_owned())
    } else {
      seen_body = true
      body.push(l)
    }
  }
  (doc.join("\n"), body.join("\n").trim().to_owned())
}

///|
fn parse_param(seg : String) -> Param? {
  let (pdoc, pbody) = split_param_doc(seg)
  let s = pbody.trim().to_owned()
  if s.length() == 0 || s.has_prefix("//") {
    return None
  }
  let a = chars_of(s)
  let n = a.length()
  let mut i = 0
  while i < n && is_ident_char(a[i]) {
    i += 1
  }
  if i == 0 {
    return None
  }
  let name = slice_str(a, 0, i)
  if name == "self" {
    return None
  }
  let mut j = skip_ws_at(a, i)
  let labelled = j < n && a[j] == '?'
  if labelled {
    j = skip_ws_at(a, j + 1)
  }
  if j >= n || a[j] != ':' {
    return None
  }
  j = skip_ws_at(a, j + 1)
  // 类型：到深度 0 的 `=` 为止（`=` 之后是默认值）
  let mut depth = 0
  let mut k = j
  let mut eq = n
  while k < n {
    let c = a[k]
    if c == '(' || c == '[' || c == '{' {
      depth += 1
    } else if c == ')' || c == ']' || c == '}' {
      depth -= 1
    } else if c == '=' && depth == 0 {
      eq = k
      break
    }
    k += 1
  }
  let ty = slice_str(a, j, eq).trim().to_owned()
  if ty.length() == 0 {
    return None
  }
  let default = if eq < n {
    slice_str(a, eq + 1, n).trim().to_owned()
  } else {
    ""
  }
  Some({ name, labelled, ty, default, doc: pdoc, })
}

///|
/// 参数区原文 → Param 数组（按深度 0 的逗号切分，括号/方括号/花括号一起计深）。
fn parse_params(inner : String) -> Array[Param] {
  let a = chars_of(inner)
  let n = a.length()
  let out : Array[Param] = []
  let mut depth = 0
  let mut start = 0
  let mut i = 0
  while i <= n {
    if i < n {
      let c = a[i]
      if c == '(' || c == '[' || c == '{' {
        depth += 1
        i += 1
        continue
      }
      if c == ')' || c == ']' || c == '}' {
        depth -= 1
        i += 1
        continue
      }
      if c == ',' && depth == 0 {
        match parse_param(slice_str(a, start, i)) {
          Some(p) => out.push(p)
          None => ()
        }
        start = i + 1
        i += 1
        continue
      }
    }
    if i == n {
      match parse_param(slice_str(a, start, n)) {
        Some(p) => out.push(p)
        None => ()
      }
    }
    i += 1
  }
  out
}

///|
/// 签名原文 → FnSig：接受 `pub fn 名(…)`、`fn 名(…) -> T {`、多行参数与尾逗号。
/// 找不到 `fn`、无名或缺左括号即 None。
fn parse_fn_sig(text : String) -> FnSig? {
  let a = chars_of(text)
  let n = a.length()
  let mut i = 0
  let mut kw = -1
  while i + 2 < n {
    if a[i] == 'f' &&
      a[i + 1] == 'n' &&
      (a[i + 2] == ' ' || a[i + 2] == '\t' || is_ident_start(a[i + 2])) {
      kw = i
      break
    }
    i += 1
  }
  if kw < 0 {
    return None
  }
  let j = skip_ws_at(a, kw + 2)
  let mut k = j
  while k < n && is_ident_char(a[k]) {
    k += 1
  }
  let name = slice_str(a, j, k).trim().to_owned()
  if name.length() == 0 {
    return None
  }
  k = skip_ws_at(a, k)
  if k >= n || a[k] != '(' {
    return None
  }
  let mut depth = 0
  let mut p = k
  let mut close = -1
  while p < n {
    if a[p] == '(' {
      depth += 1
    } else if a[p] == ')' {
      depth -= 1
      if depth == 0 {
        close = p
        break
      }
    }
    p += 1
  }
  if close < 0 {
    return None
  }
  let inner = slice_str(a, k + 1, close)
  // 尾段：`)` 之后到函数体 `{` 前；返回类型取 `->` 右侧
  let mut q = close + 1
  while q < n && a[q] != '{' {
    q += 1
  }
  let tail = slice_str(a, close + 1, q).trim().to_owned()
  let ret = match arrow_index(tail) {
    Some(x) => tail[x + 2:].trim().to_owned()
    None => ""
  }
  Some({ name, params: parse_params(inner), ret, })
}

///|
/// 签名原文 → 参数表（名, 类型, 是否可省, 默认值, 参数文档）：编辑器 hover / 补全用。
pub fn sig_params(
  text : String,
) -> Array[(String, String, Bool, String, String)] {
  let out : Array[(String, String, Bool, String, String)] = []
  match parse_fn_sig(text) {
    Some(sig) =>
      for p in sig.params {
        out.push((p.name, p.ty, p.labelled, p.default, p.doc))
      }
    None => ()
  }
  out
}

///|
/// 顶层 `->` 的位置（跳过括号内的箭头）；无则 None。
fn arrow_index(s : String) -> Int32? {
  let a = chars_of(s)
  let n = a.length()
  let mut depth = 0
  let mut i = 0
  while i + 1 < n {
    let c = a[i]
    if c == '(' || c == '[' || c == '{' {
      depth += 1
    } else if c == ')' || c == ']' || c == '}' {
      depth -= 1
    } else if c == '-' && a[i + 1] == '>' && depth == 0 {
      return Some(i)
    }
    i += 1
  }
  None
}

///|
/// 类型原文 → 响应槽种类（与 script 段 `let` 注解同一判据）。
fn kind_of_ty(ty : String) -> SlotKind {
  // ListStore 必须先判（它包含 "Store[" 子串，会被误判成 KStore 然后 .get() 出数组）
  if contains_sub(ty, "ListStore[") {
    KList
  } else if contains_sub(ty, "Store[") {
    KStore
  } else if contains_sub(ty, "Signal[") {
    KSignal
  } else {
    KPlain
  }
}

///|
priv struct MapEntry {
  gen_line : Int32
  src_line : Int32
  src_col : Int32
}

///|
pub struct GenOut {
  code : String
  map : String
}

///|
fn chars_of(s : String) -> Array[Char] {
  let a : Array[Char] = []
  for c in s {
    a.push(c)
  }
  a
}

///|
fn ind_str(n : Int32) -> String {
  let b : Array[String] = Array::make(n, "  ")
  b.join("")
}

///|
fn is_ident_start(c : Char) -> Bool {
  (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || c == '_'
}

///|
fn is_ident_char(c : Char) -> Bool {
  is_ident_start(c) || (c >= '0' && c <= '9')
}

///|
fn is_digit(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn snake(s : String) -> String {
  chars_of(s)
  .map(fn(c) { if c == '-' { '_' } else { c } })
  .map(fn(c) { c.to_string() })
  .join("")
}

///|
/// MoonBit 字符串字面量转义（插值文本与裸串属性都用它）。
fn escape_mbt(s : String) -> String {
  let out : Array[String] = []
  for c in s {
    let piece = if c == '\\' {
      "\\\\"
    } else if c == '"' {
      "\\\""
    } else if c == '\n' {
      "\\n"
    } else if c == '\r' {
      "\\r"
    } else if c == '\t' {
      "\\t"
    } else {
      c.to_string()
    }
    out.push(piece)
  }
  out.join("")
}

///|
/// 静态属性值 → MoonBit 表达式：单引号包裹 / 双引号开头 / true / false / 数字
/// 原样透传（视为 MoonBit 字面量）；其余按字符串字面量转义。
fn lit_of(value : String) -> String {
  let v = value.trim().to_owned()
  let n = chars_of(v).length()
  if n >= 2 {
    let cs = chars_of(v)
    if cs[0] == '\'' && cs[n - 1] == '\'' {
      return v[1:n - 1].to_owned()
    }
  }
  if v.has_prefix("\"") {
    return v
  }
  if v == "true" || v == "false" {
    return v
  }
  // 数字：可选负号 + 数字 + 可选小数段
  let cs = chars_of(v)
  let mut i = 0
  let mut ok = n > 0
  if ok && cs[0] == '-' {
    i = 1
  }
  let mut dots = 0
  let mut digits = 0
  while i < n {
    let c = cs[i]
    if is_digit(c) {
      digits += 1
    } else if c == '.' {
      dots += 1
    } else {
      ok = false
    }
    i += 1
  }
  if ok && digits > 0 && dots <= 1 {
    return v
  }
  "\"" + escape_mbt(v) + "\""
}

///|
/// 标识符扫描：对 [lo,hi) 内每个最大标识符 run 调 f(名字)。
fn scan_idents(
  a : Array[Char],
  lo : Int32,
  hi : Int32,
  f : (String) -> Unit,
) -> Unit {
  let mut i = lo
  while i < hi {
    let c = a[i]
    if is_ident_start(c) {
      let start = i
      while i < hi && is_ident_char(a[i]) {
        i += 1
      }
      let name = a[start:i].map(fn(c) { c.to_string() }).join("")
      f(name)
    } else {
      i += 1
    }
  }
}

///|
/// 文本里出现过的全部标识符（含重复），供「名字是否被引用」判定。
fn idents_in(hay : String) -> Array[String] {
  let a = chars_of(hay)
  let out : Array[String] = []
  scan_idents(a, 0, a.length(), fn(name) { out.push(name) })
  out
}

///|
/// 值语义改写：表达式中裸引用的 Store/Signal 槽名补 `.get()`（后随 `.` 的
/// 跳过——调用链如 `qty.get()` 不重复补）。
fn rewrite_value(e : String, slots : Map[String, SlotKind]) -> String {
  let a = chars_of(e)
  let out : Array[String] = []
  let mut i = 0
  let n = a.length()
  while i < n {
    let c = a[i]
    if is_ident_start(c) {
      let start = i
      while i < n && is_ident_char(a[i]) {
        i += 1
      }
      let name = a[start:i].map(fn(c) { c.to_string() }).join("")
      let kind = slots.get(name)
      let reactive = match kind {
        Some(KStore) | Some(KSignal) => true
        _ => false
      }
      if reactive && !(i < n && a[i] == '.') {
        out.push(name + ".get()")
      } else {
        out.push(name)
      }
    } else {
      out.push(c.to_string())
      i += 1
    }
  }
  out.join("")
}

///|
/// String::split 返回 Iter——转 Array 的统一口（本工具链无 collect_array）。
fn split_arr(s : String, sep : String) -> Array[String] {
  let out : Array[String] = []
  for x in s.split(sep) {
    out.push(x.to_owned())
  }
  out
}

///|
/// 子串包含（工具链 String 无 contains，自备）。
fn contains_sub(s : String, sub : String) -> Bool {
  let a = chars_of(s)
  let b = chars_of(sub)
  let n = a.length()
  let m = b.length()
  if m == 0 || m > n {
    return m == 0
  }
  let mut i = 0
  while i + m <= n {
    let mut ok = true
    for k in 0..<m {
      if a[i + k] != b[k] {
        ok = false
      }
    }
    if ok {
      return true
    }
    i += 1
  }
  false
}

///|
/// 文本归一化：空白 run 折叠成单空格、去首尾——模板缩进不进生成串。
fn normalize_text(s : String) -> String {
  let a = chars_of(s)
  let out : Array[String] = []
  let mut pending_space = false
  for c in a {
    if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
      pending_space = true
    } else {
      if pending_space && out.length() > 0 {
        out.push(" ")
      }
      pending_space = false
      out.push(c.to_string())
    }
  }
  out.join("")
}

///|
/// 文本是否含插值 `{{`。
fn has_interp(s : String) -> Bool {
  let a = chars_of(s)
  let mut i = 0
  while i + 1 < a.length() {
    if a[i] == '{' && a[i + 1] == '{' {
      return true
    }
    i += 1
  }
  false
}

///|
/// 响应源提取：表达式中出现过的 Store/Signal 槽名（去重、按首现序）。
fn sources_of(e : String, slots : Map[String, SlotKind]) -> Array[String] {
  let a = chars_of(e)
  let seen : Map[String, Bool] = Map([])
  let out : Array[String] = []
  scan_idents(a, 0, a.length(), fn(name) {
    match slots.get(name) {
      Some(KStore) | Some(KSignal) =>
        if !seen.get_or_default(name, false) {
          let _ = seen.set(name, true)
          out.push(name)
        }
      _ => ()
    }
  })
  out
}

///|
/// 表达式文本里的单引号串 → 双引号串（JS 习惯兼容）。
/// 只换「多字符、无转义、无内嵌双引号」的 span；单字符保持 Char 字面量，
/// 含转义/双引号的原样留着交给 `char_literal_hint` 报错。双引号串内部一律跳过。
fn requote_expr(e : String) -> String {
  let a = chars_of(e)
  let n = a.length()
  let out = StringBuilder()
  let mut i = 0
  while i < n {
    let c = a[i]
    if c == '"' {
      out.write_char(c)
      i += 1
      while i < n {
        let ch = a[i]
        out.write_char(ch)
        if ch == '\\' && i + 1 < n {
          out.write_char(a[i + 1])
          i += 2
          continue
        }
        i += 1
        if ch == '"' {
          break
        }
      }
      continue
    }
    if c == '\'' {
      let start = i
      let mut j = i + 1
      while j < n && a[j] != '\'' {
        if a[j] == '\\' {
          j += 1
        }
        j += 1
      }
      if j < n && a[j] == '\'' {
        let body = slice_str(a, start + 1, j)
        let safe = chars_of(body).length() != 1 &&
          !body.has_prefix("\\") &&
          !contains_sub(body, "\\") &&
          !contains_sub(body, "\"")
        if safe {
          out.write_char('"')
          out.write_string(body)
          out.write_char('"')
        } else {
          out.write_string(slice_str(a, start, j + 1))
        }
        i = j + 1
        continue
      }
      out.write_char(c)
      i += 1
      continue
    }
    out.write_char(c)
    i += 1
  }
  out.to_string()
}

///|
/// 表达式里的单引号误用：MoonBit 没有单引号串，`'多字符'` 是非法字符字面量。
/// 扫描时跳过双引号串；`'x'` / `'\n'` 这类合法字符字面量放过。
fn char_literal_hint(e : String) -> String? {
  let a = chars_of(e)
  let n = a.length()
  let mut i = 0
  while i < n {
    let c = a[i]
    if c == '"' {
      i += 1
      while i < n && a[i] != '"' {
        if a[i] == '\\' {
          i += 1
        }
        i += 1
      }
      i += 1
      continue
    }
    if c == '\'' {
      let start = i
      let mut j = i + 1
      let mut closed = false
      while j < n && a[j] != '\'' {
        if a[j] == '\\' {
          j += 1
        }
        j += 1
      }
      if j < n && a[j] == '\'' {
        closed = true
      }
      if closed {
        let body = slice_str(a, start + 1, j)
        let b = chars_of(body)
        let legal = b.length() == 1 || (b.length() > 0 && b[0] == '\\')
        if !legal {
          return Some(body)
        }
        i = j + 1
        continue
      }
      i += 1
      continue
    }
    i += 1
  }
  None
}

///|
/// 模板里所有表达式位置的单引号串误用检查（属性表达式 / 事件 / v-model / 条件 / 插值）。
/// 命中即编译报错并给两种可行写法，别丢给 moon check 的字符字面量报错。
fn check_expr_quotes(
  nodes : Array[TNode],
  filename : String,
) -> Result[Unit, String] {
  for n in nodes {
    match n {
      Elem(_, attrs, kids, _) => {
        for a in attrs {
          match a.kind {
            Dyn | Event | Model | If | ElseIf | Show =>
              if a.has_value {
                match char_literal_hint(a.value) {
                  Some(body) =>
                    return Err(
                      "\{filename}：\{pos_str(a.pos)}：`'\{body}'` 是 MoonBit 字符字面量，不是字符串——外层用单引号包双引号串（如 :text='@shared.tx(\"\{body}\")'），或外层双引号里写 \\\" 转义",
                    )
                  None => ()
                }
              }
            _ => ()
          }
        }
        match check_expr_quotes(kids, filename) {
          Ok(_) => ()
          Err(e) => return Err(e)
        }
      }
      Text(raw, pos) =>
        match split_interp(raw, pos) {
          Ok(pieces) =>
            for p in pieces {
              match p {
                PExpr(e) =>
                  match char_literal_hint(e) {
                    Some(body) =>
                      return Err(
                        "\{filename}：\{pos_str(pos)}：插值里的 `'\{body}'` 是 MoonBit 字符字面量，不是字符串——写双引号串（如 \"\{body}\"）",
                      )
                    None => ()
                  }
                _ => ()
              }
            }
          Err(_) => ()
        }
    }
  }
  Ok(())
}
