// i18n 内核：自带一个够用的极简 TOML 读器（[section] / key = "值" / 内联表复数），
// 加查译、命名插值、复数选择、回退。纯 MoonBit，零外部依赖。

///|
pub(all) struct Catalog {
  locale : String
  texts : Array[(String, String)]
  plurals : Array[(String, Array[(String, String)])]
}

///|
fn chars(s : String) -> Array[Char] {
  let a : Array[Char] = []
  for c in s {
    a.push(c)
  }
  a
}

///|
fn join(arr : Array[Char], from : Int, to : Int) -> String {
  let mut s = ""
  let mut i = from
  while i < to {
    s = s + arr[i].to_string()
    i += 1
  }
  s
}

///|
fn trim_str(s : String) -> String {
  let a = chars(s)
  let n = a.length()
  let mut i = 0
  while i < n && (a[i] == ' ' || a[i] == '\t' || a[i] == '\r') {
    i += 1
  }
  let mut j = n
  while j > i && (a[j - 1] == ' ' || a[j - 1] == '\t' || a[j - 1] == '\r') {
    j -= 1
  }
  join(a, i, j)
}

///|
fn split_lines(s : String) -> Array[String] {
  let out : Array[String] = []
  let a = chars(s)
  let n = a.length()
  let mut start = 0
  let mut i = 0
  while i < n {
    if a[i] == '\n' {
      out.push(join(a, start, i))
      start = i + 1
    }
    i += 1
  }
  out.push(join(a, start, n))
  out
}

///|
// 去外层引号并解一层常见转义。
fn unquote(s : String) -> String {
  let a = chars(s)
  let n = a.length()
  if n >= 2 && a[0] == '"' && a[n - 1] == '"' {
    let mut out = ""
    let mut i = 1
    while i < n - 1 {
      if a[i] == '\\' && i + 1 < n - 1 {
        let nx = a[i + 1]
        if nx == 'n' {
          out = out + "\n"
        } else if nx == 't' {
          out = out + "\t"
        } else {
          out = out + nx.to_string()
        }
        i += 2
      } else {
        out = out + a[i].to_string()
        i += 1
      }
    }
    out
  } else {
    s
  }
}

///|
// 顶层逗号切分（尊重双引号，值里的逗号不误切）。
fn split_top_commas(s : String) -> Array[String] {
  let out : Array[String] = []
  let a = chars(s)
  let n = a.length()
  let mut start = 0
  let mut in_q = false
  let mut i = 0
  while i < n {
    let c = a[i]
    if c == '"' {
      in_q = !in_q
    } else if c == ',' && !in_q {
      out.push(join(a, start, i))
      start = i + 1
    }
    i += 1
  }
  out.push(join(a, start, n))
  out
}

///|
// 解析内联表 `{ one = "x", other = "y" }` → [(form, text)]。
fn parse_inline_table(val : String) -> Array[(String, String)] {
  let forms : Array[(String, String)] = []
  let v = trim_str(val)
  let a = chars(v)
  let n = a.length()
  if n < 2 || a[0] != '{' {
    return forms
  }
  let inner = join(a, 1, n - 1)
  for part in split_top_commas(inner) {
    let p = trim_str(part)
    if p.length() == 0 {
      continue
    }
    match split_kv(p) {
      Some((k, val)) => forms.push((trim_str(k), unquote(trim_str(val))))
      None => ()
    }
  }
  forms
}

///|
// 按第一个 '=' 分成 (key, value)。
fn split_kv(line : String) -> (String, String)? {
  let a = chars(line)
  let n = a.length()
  let mut i = 0
  while i < n {
    if a[i] == '=' {
      return Some((join(a, 0, i), join(a, i + 1, n)))
    }
    i += 1
  }
  None
}

///|
/// 解析翻译 TOML 文本为 Catalog（[meta].locale 抽出；[section] 前缀扁平成 a.b）。
pub fn parse_catalog(text : String) -> Catalog {
  let texts : Array[(String, String)] = []
  let plurals : Array[(String, Array[(String, String)])] = []
  let mut prefix = ""
  for line in split_lines(text) {
    let t = trim_str(line)
    if t.length() == 0 || t[0] == '#' {
      continue
    }
    if t[0] == '[' {
      // [section] 或 [a.b]
      let end = find_char(t, ']')
      let sec = if end > 0 { slice(t, 1, end) } else { slice(t, 1, t.length()) }
      prefix = sec + "."
      continue
    }
    match split_kv(t) {
      None => ()
      Some((raw_key, raw_val)) => {
        let key = trim_str(raw_key)
        let full = prefix + key
        let val = trim_str(raw_val)
        if val.length() > 0 && val[0] == '{' {
          plurals.push((full, parse_inline_table(val)))
        } else {
          texts.push((full, unquote(val)))
        }
      }
    }
  }
  let locale = match find_text_raw(texts, "meta.locale") {
    Some(l) => l
    None => ""
  }
  { locale, texts, plurals }
}

///|
fn find_char(s : String, c : Char) -> Int {
  let a = chars(s)
  let n = a.length()
  let mut i = 0
  while i < n {
    if a[i] == c {
      return i
    }
    i += 1
  }
  -1
}

///|
fn slice(s : String, from : Int, to : Int) -> String {
  join(chars(s), from, to)
}

///|
fn find_text_raw(texts : Array[(String, String)], key : String) -> String? {
  for (k, v) in texts {
    if k == key {
      return Some(v)
    }
  }
  None
}

///|
fn find_plural_raw(
  plurals : Array[(String, Array[(String, String)])],
  key : String,
) -> Array[(String, String)]? {
  for (k, v) in plurals {
    if k == key {
      return Some(v)
    }
  }
  None
}

///|
// 命名插值：把 {name} 换成 vars 里的值。
pub fn interp(tmpl : String, vars : Array[(String, String)]) -> String {
  let a = chars(tmpl)
  let n = a.length()
  let mut out = ""
  let mut i = 0
  while i < n {
    if a[i] == '{' {
      let mut j = i + 1
      while j < n && a[j] != '}' {
        j += 1
      }
      if j < n && j > i + 1 {
        let name = join(a, i + 1, j)
        match find_text_raw(vars, name) {
          Some(v) => {
            out = out + v
            i = j + 1
            continue
          }
          None => ()
        }
      }
    }
    out = out + a[i].to_string()
    i += 1
  }
  out
}

///|
/// 简单查译。
pub fn t(cat : Catalog, key : String) -> String? {
  find_text_raw(cat.texts, key)
}

///|
/// 带插值查译。
pub fn t_with(cat : Catalog, key : String, vars : Array[(String, String)]) -> String? {
  match t(cat, key) {
    Some(s) => Some(interp(s, vars))
    None => None
  }
}

///|
// locale 的主语言子tag（截到首个 '-'/'_'）。
fn primary_lang(locale : String) -> String {
  let a = chars(locale)
  let n = a.length()
  let mut i = 0
  while i < n {
    if a[i] == '-' || a[i] == '_' {
      break
    }
    i += 1
  }
  join(a, 0, i)
}

///|
// CLDR 简化复数：东亚语言恒 other，其余 one/other。按主语言判。
pub fn select_plural(locale : String, n : Int) -> String {
  match primary_lang(locale) {
    "zh" | "ja" | "ko" | "vi" | "th" | "id" => "other"
    _ => if n == 1 { "one" } else { "other" }
  }
}

///|
/// 复数查译：优先内联表按形式取，退普通串；n 填 {n}/{count}。
pub fn t_count(cat : Catalog, key : String, n : Int) -> String? {
  let vars = [("n", n.to_string()), ("count", n.to_string())]
  match find_plural_raw(cat.plurals, key) {
    Some(forms) => {
      let want = select_plural(cat.locale, n)
      let tmpl =
        match find_text_raw(forms, want) {
          Some(s) => s
          None => match find_text_raw(forms, "other") {
            Some(s) => s
            None => if forms.length() > 0 { forms[0].1 } else { "" }
          }
        }
      Some(interp(tmpl, vars))
    }
    None => match t(cat, key) {
      Some(s) => Some(interp(s, vars))
      None => None
    }
  }
}

///|
/// 回退查译：主目录缺失时取回退目录。
pub fn t_fb(primary : Catalog, fallback : Catalog, key : String) -> String? {
  match t(primary, key) {
    Some(s) => Some(s)
    None => t(fallback, key)
  }
}
