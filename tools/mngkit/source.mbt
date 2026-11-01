// 公共类型与小助手：位置、错误、属性分类、模板树、字面量判定。

///|
priv struct Pos {
  line : Int
  col : Int
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
  KPlain
}

///|
/// 组件声明：模板标签 → 调用路径 + 位置参数顺序（children/child/text 特殊名）。
priv struct CompDecl {
  path : String
  positional : Array[String]
}

///|
priv struct MapEntry {
  gen_line : Int
  src_line : Int
  src_col : Int
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
fn ind_str(n : Int) -> String {
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
  chars_of(s).map(fn(c) {
    if c == '-' {
      '_'
    } else {
      c
    }
  }).map(fn(c) { c.to_string() }).join("")
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
fn scan_idents(a : Array[Char], lo : Int, hi : Int, f : (String) -> Unit) -> Unit {
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
