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

///|
/// 脱引号 + 解转义：TOML 基本串认的 `\\n \\t \\r \\" \\\\` 在此还原。
/// 键与值同一条口径——键写成 `"中文原文"` 时也必须能按裸文本查到。
fn i_unquote(s : String) -> String {
  let a = i_chars(s)
  let n = a.length()
  let body =
    if n >= 2 && a[0] == '"' && a[n - 1] == '"' {
      i_join(a, 1, n - 1)
    } else {
      s
    }
  i_unescape(body)
}

fn i_unescape(s : String) -> String {
  if !s.to_array().exists(c => c == '\\') {
    return s
  }
  let a = i_chars(s)
  let n = a.length()
  let out : Array[Char] = []
  let mut i = 0
  while i < n {
    if a[i] == '\\' && i + 1 < n {
      let nx = a[i + 1]
      let rep : Char? = match nx {
        'n' => Some('\n')
        't' => Some('\t')
        'r' => Some('\r')
        '"' => Some('"')
        '\\' => Some('\\')
        _ => None
      }
      match rep {
        Some(c) => {
          out.push(c)
          i = i + 2
          continue
        }
        None => ()
      }
    }
    out.push(a[i])
    i += 1
  }
  i_join(out, 0, out.length())
}

///|
/// 行内第一个「引号外」的 `=` 才是键值分隔符——键里带 `=`（如
/// `white_space=NoWrap` 这类原文当键）时不能被截断。
fn i_split_eq(line : String) -> (String, String)? {
  let a = i_chars(line)
  let n = a.length()
  let mut i = 0
  let mut in_str = false
  while i < n {
    let c = a[i]
    if in_str {
      if c == '\\' {
        i = i + 1
      } else if c == '"' {
        in_str = false
      }
    } else if c == '"' {
      in_str = true
    } else if c == '=' {
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
        let full = prefix + i_unquote(i_trim(raw_key))
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

// —— 运行时目录：内置默认（源语言）+ 当前 + 回退 ——
// 默认语言**内置**：下面这份编译期就写死，应用不加载任何外置文件也能 t() 出中文 chrome。
// 其它语言是**独立文件**（locales/*.toml），通过 i18n_extend/i18n_load 从外置文件夹读入文本后启用。

const BUILTIN_DEFAULT : String =
  "[meta]\nlocale = \"default\"\n[gui.ui.dialog]\nconfirm = \"确定\"\ncancel = \"取消\"\n[gui.ui.message_box]\nok = \"确定\"\n[gui.ui.datepicker]\ncancel = \"取消\"\nok = \"确定\"\nplaceholder = \"请选择日期\"\nrange_placeholder = \"请选择日期区间\"\ntitle = \"选择日期\"\nmonth_year = \"{y} 年 {m} 月\"\nunit.h = \"时\"\nunit.m = \"分\"\nunit.s = \"秒\"\nwd.0 = \"日\"\nwd.1 = \"一\"\nwd.2 = \"二\"\nwd.3 = \"三\"\nwd.4 = \"四\"\nwd.5 = \"五\"\nwd.6 = \"六\"\n[gui.ui.validation]\nrequired = \"不能为空\"\nmin_len = \"至少 {n} 个字符\"\nemail = \"邮箱格式不对\"\nint_range = \"须在 {lo}.. {hi} 之间\"\n[gui.ui.edit]\ncut = \"剪切\"\ncopy = \"复制\"\npaste = \"粘贴\"\nselect_all = \"全选\"\n"

let g_builtin : Catalog = parse_catalog(BUILTIN_DEFAULT)

priv struct Store {
  mut cur : Catalog
  mut fb : Catalog?
}

let g_store : Store = Store::{
  cur: g_builtin,
  fb: None,
}

///|
/// 内置默认目录（源语言 chrome），任何查译的最终兜底。
pub fn builtin_default() -> Catalog {
  g_builtin
}

///|
/// 装入当前目录（覆盖）——应用从外置 locale 文件读到的文本走这里。
/// 尾部广播原生表面（菜单栏这类画在控件树之外的东西，见 `locale.mbt`）。
pub fn i18n_load(text : String) -> Unit {
  g_store.cur = parse_catalog(text)
  locale_notify()
}

///|
/// 扩展一门语言：读入外置 locale 文本并设为当前。语义等同 i18n_load，
/// 命名点明「默认语言已内置，这是往外挂一门语言」。
pub fn i18n_extend(text : String) -> Unit {
  g_store.cur = parse_catalog(text)
  locale_notify()
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
/// 复位到「只有内置默认」：清空当前/回退，回到不加载任何外置文件的初始态。
/// 应用整体换语言前的干净起点，也供测试隔离全局态。
pub fn i18n_reset() -> Unit {
  g_store.cur = g_builtin
  g_store.fb = None
  locale_notify()
}

///|
/// 查译链：当前目录 → 回退目录 → 内置默认目录。
/// 零外置文件时即命中内置默认，故默认语言无需任何加载就能用。
pub fn t(key : String) -> String? {
  match find_text(g_store.cur.texts, key) {
    Some(s) => Some(s)
    None =>
      match g_store.fb {
        Some(f) => {
          match find_text(f.texts, key) {
            Some(s) => Some(s)
            None => find_text(g_builtin.texts, key)
          }
        }
        None => find_text(g_builtin.texts, key)
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

///|
/// 行为不变取译：目录里有该键就用译文，否则用调用方给的字面量默认值。
/// 框架 chrome 文案用它——不加载目录时与旧硬编码逐字一致，加载了才本地化。
pub fn t_or(key : String, default : String) -> String {
  match t(key) {
    Some(s) => s
    None => default
  }
}

///|
/// 带插值的行为不变取译。
pub fn t_with_or(
  key : String,
  vars : Array[(String, String)],
  default : String,
) -> String {
  match t_with(key, vars) {
    Some(s) => s
    None => default
  }
}
