// iconfont 运行时加载器（消费面）：读工具产出的 `[icons]` TOML 文本，
// 存 name→定点路径串，绘制复用同包的 fill_icon_path（与内置矢量图标同口径）。
// 与 tools/i18nkit·iconkit「共享格式不共享代码」：这里自带一份够用的极简读器，
// gui 不引 fs/FFI——文件读取由应用层负责，本层只吃字符串。

let g_iconfont : Array[(String, String)] = []

///|
fn ic_chars(s : String) -> Array[Char] {
  let a : Array[Char] = []
  for c in s {
    a.push(c)
  }
  a
}

///|
fn ic_join(a : Array[Char], from : Int, to : Int) -> String {
  let mut s = ""
  let mut i = from
  while i < to {
    s = s + a[i].to_string()
    i += 1
  }
  s
}

///|
fn ic_trim(s : String) -> String {
  let a = ic_chars(s)
  let n = a.length()
  let mut i = 0
  while i < n && (a[i] == ' ' || a[i] == '\t' || a[i] == '\r') {
    i += 1
  }
  let mut j = n
  while j > i && (a[j - 1] == ' ' || a[j - 1] == '\t' || a[j - 1] == '\r') {
    j -= 1
  }
  ic_join(a, i, j)
}

///|
fn ic_unquote(s : String) -> String {
  let a = ic_chars(s)
  let n = a.length()
  if n >= 2 && a[0] == '"' && a[n - 1] == '"' {
    ic_join(a, 1, n - 1)
  } else {
    s
  }
}

///|
fn ic_split_eq(line : String) -> (String, String)? {
  let a = ic_chars(line)
  let n = a.length()
  let mut i = 0
  while i < n {
    if a[i] == '=' {
      return Some((ic_join(a, 0, i), ic_join(a, i + 1, n)))
    }
    i += 1
  }
  None
}

///|
fn ic_split_lines(s : String) -> Array[String] {
  let out : Array[String] = []
  let a = ic_chars(s)
  let n = a.length()
  let mut start = 0
  let mut i = 0
  while i < n {
    if a[i] == '\n' {
      out.push(ic_join(a, start, i))
      start = i + 1
    }
    i += 1
  }
  out.push(ic_join(a, start, n))
  out
}

///|
/// 解析 `[icons]` 段为 (name, path) 列表。
pub fn parse_icons(text : String) -> Array[(String, String)] {
  let out : Array[(String, String)] = []
  let mut in_sec = false
  for raw in ic_split_lines(text) {
    let line = ic_trim(raw)
    if line.length() == 0 || line[0] == '#' {
      continue
    }
    if line[0] == '[' {
      in_sec = line == "[icons]"
      continue
    }
    if in_sec {
      match ic_split_eq(line) {
        None => ()
        Some((k, v)) => out.push((ic_unquote(ic_trim(k)), ic_unquote(ic_trim(v))))
      }
    }
  }
  out
}

///|
/// 用工具产出的 TOML 文本装入图标表（覆盖旧表）。返回装入条数。
pub fn iconfont_load(text : String) -> Int {
  let entries = parse_icons(text)
  g_iconfont.clear()
  for e in entries {
    g_iconfont.push(e)
  }
  entries.length()
}

///|
/// 查表：图标名对应的定点路径串。
pub fn iconfont_get(name : String) -> String? {
  for (k, v) in g_iconfont {
    if k == name {
      return Some(v)
    }
  }
  None
}

///|
/// 已装入的图标数。
pub fn iconfont_count() -> Int {
  g_iconfont.length()
}

///|
/// 已装入的图标名列表（保持装入顺序）。
pub fn iconfont_names() -> Array[String] {
  let out : Array[String] = []
  for (k, _) in g_iconfont {
    out.push(k)
  }
  out
}

///|
/// 绘制 iconfont 图标：中心 (cx,cy)、内容半径 s、color 十六进制。
/// 未装入或查无此名时静默（调用方先 iconfont_get 判存在再决定降级）。
pub fn draw_iconfont(
  p : @render.Painter,
  name : String,
  cx : Double,
  cy : Double,
  s : Double,
  color : String,
) -> Unit {
  match iconfont_get(name) {
    Some(path) => {
      p.set_fill_color(color)
      fill_icon_path(p, path, cx, cy, s)
    }
    None => ()
  }
}
