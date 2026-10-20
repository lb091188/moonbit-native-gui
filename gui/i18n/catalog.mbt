// i18n 运行时机制：自带极简 TOML 读 + 查译/插值/复数，并持当前与回退两本目录。
// 文件读取归应用层（本包只吃字符串），切语言后由应用 invalidate 重绘。

///|
pub(all) struct Catalog {
  locale : String
  texts : Array[(String, String)]
  plurals : Array[(String, Array[(String, String)])]
}

fn i_chars(s : String) -> Array[Char] {
  let a : Array[Char] = []
  for c in s {
    a.push(c)
  }
  a
}

fn i_join(a : Array[Char], from : Int, to : Int) -> String {
  let mut s = ""
  let mut i = from
  while i < to {
    s = s + a[i].to_string()
    i += 1
  }
  s
}

fn i_trim(s : String) -> String {
  let a = i_chars(s)
  let n = a.length()
  let mut i = 0
  while i < n && (a[i] == ' ' || a[i] == '\t' || a[i] == '\r') {
    i += 1
  }
  let mut j = n
  while j > i && (a[j - 1] == ' ' || a[j - 1] == '\t' || a[j - 1] == '\r') {
    j -= 1
  }
  i_join(a, i, j)
}

fn i_unquote(s : String) -> String {
  let a = i_chars(s)
  let n = a.length()
  if n >= 2 && a[0] == '"' && a[n - 1] == '"' {
    i_join(a, 1, n - 1)
  } else {
    s
  }
}

fn i_split_eq(line : String) -> (String, String)? {
  let a = i_chars(line)
  let n = a.length()
  let mut i = 0
  while i < n {
    if a[i] == '=' {
      return Some((i_join(a, 0, i), i_join(a, i + 1, n)))
    }
    i += 1
  }
  None
}

fn i_split_lines(s : String) -> Array[String] {
  let out : Array[String] = []
  let a = i_chars(s)
  let n = a.length()
  let mut start = 0
  let mut i = 0
  while i < n {
    if a[i] == '\n' {
      out.push(i_join(a, start, i))
      start = i + 1
    }
    i += 1
  }
  out.push(i_join(a, start, n))
  out
}

fn i_split_top_commas(s : String) -> Array[String] {
  let out : Array[String] = []
  let a = i_chars(s)
  let n = a.length()
  let mut start = 0
  let mut in_q = false
  let mut i = 0
  while i < n {
    let c = a[i]
    if c == '"' {
      in_q = !in_q
    } else if c == ',' && !in_q {
      out.push(i_join(a, start, i))
      start = i + 1
    }
    i += 1
  }
  out.push(i_join(a, start, n))
  out
}

fn i_inline_table(val : String) -> Array[(String, String)] {
  let forms : Array[(String, String)] = []
  let v = i_trim(val)
  let a = i_chars(v)
  let n = a.length()
  if n < 2 || a[0] != '{' {
    return forms
  }
  let inner = i_join(a, 1, n - 1)
  for part in i_split_top_commas(inner) {
    let p = i_trim(part)
    if p.length() == 0 {
      continue
    }
    match i_split_eq(p) {
      Some((k, val)) => forms.push((i_trim(k), i_unquote(i_trim(val))))
      None => ()
    }
  }
  forms
}

///|
/// 解析翻译 TOML 文本为目录。
pub fn parse_catalog(text : String) -> Catalog {
  let texts : Array[(String, String)] = []
  let plurals : Array[(String, Array[(String, String)])] = []
  let mut prefix = ""
  for line in i_split_lines(text) {
    let t = i_trim(line)
    if t.length() == 0 || t[0] == '#' {
      continue
    }
    if t[0] == '[' {
      let a = i_chars(t)
      let n = a.length()
      let mut end = n
      let mut i = 0
      while i < n {
        if a[i] == ']' {
          end = i
          break
        }
        i += 1
      }
      prefix = i_join(a, 1, end) + "."
      continue
    }
    match i_split_eq(t) {
      None => ()
      Some((raw_key, raw_val)) => {
        let full = prefix + i_trim(raw_key)
        let val = i_trim(raw_val)
        let a = i_chars(val)
        if a.length() > 0 && a[0] == '{' {
          plurals.push((full, i_inline_table(val)))
        } else {
          texts.push((full, i_unquote(val)))
        }
      }
    }
  }
  let mut locale = ""
  for (k, v) in texts {
    if k == "meta.locale" {
      locale = v
    }
  }
  { locale, texts, plurals }
}

fn find_text(arr : Array[(String, String)], key : String) -> String? {
  for (k, v) in arr {
    if k == key {
      return Some(v)
    }
  }
  None
}

fn find_plural(
  arr : Array[(String, Array[(String, String)])],
  key : String,
) -> Array[(String, String)]? {
  for (k, v) in arr {
    if k == key {
      return Some(v)
    }
  }
  None
}

///|
/// 命名插值。
pub fn interp(tmpl : String, vars : Array[(String, String)]) -> String {
  let a = i_chars(tmpl)
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
        let name = i_join(a, i + 1, j)
        match find_text(vars, name) {
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

fn primary_lang(locale : String) -> String {
  let a = i_chars(locale)
  let n = a.length()
  let mut i = 0
  while i < n {
    if a[i] == '-' || a[i] == '_' {
      break
    }
    i += 1
  }
  i_join(a, 0, i)
}

fn select_plural(locale : String, n : Int) -> String {
  match primary_lang(locale) {
    "zh" | "ja" | "ko" | "vi" | "th" | "id" => "other"
    _ => if n == 1 { "one" } else { "other" }
  }
}

// —— 运行时当前/回退目录（字段可换，绑定不可变）——
priv struct Store {
  mut cur : Catalog
  mut fb : Catalog?
}

let g_store : Store = Store::{
  cur: { locale: "", texts: [], plurals: [] },
  fb: None,
}

///|
/// 装入当前目录（覆盖）。
pub fn i18n_load(text : String) -> Unit {
  g_store.cur = parse_catalog(text)
}

///|
/// 装入回退目录。
pub fn i18n_load_fallback(text : String) -> Unit {
  g_store.fb = Some(parse_catalog(text))
}

///|
/// 当前语言标签。
pub fn i18n_locale() -> String {
  g_store.cur.locale
}

///|
/// 查译，主目录缺失时退到回退目录。
pub fn t(key : String) -> String? {
  match find_text(g_store.cur.texts, key) {
    Some(s) => Some(s)
    None => match g_store.fb {
      Some(f) => find_text(f.texts, key)
      None => None
    }
  }
}

///|
/// 带插值查译。
pub fn t_with(key : String, vars : Array[(String, String)]) -> String? {
  match t(key) {
    Some(s) => Some(interp(s, vars))
    None => None
  }
}

///|
/// 复数查译。
pub fn t_count(key : String, n : Int) -> String? {
  let vars = [("n", n.to_string()), ("count", n.to_string())]
  match find_plural(g_store.cur.plurals, key) {
    Some(forms) => {
      let want = select_plural(g_store.cur.locale, n)
      let tmpl =
        match find_text(forms, want) {
          Some(s) => s
          None => match find_text(forms, "other") {
            Some(s) => s
            None => if forms.length() > 0 { forms[0].1 } else { "" }
          }
        }
      Some(interp(tmpl, vars))
    }
    None => match t(key) {
      Some(s) => Some(interp(s, vars))
      None => None
    }
  }
}
