// 源码跳转：把 `@别名.成员` / 同包裸名换成「源码文件 + 行号」。
// 别名表与包目录沿用 resolve.mbt 的口径（moon.pkg → workspace 成员 / .mooncakes）；
// 包内成员表优先读生成的 `.mbti`（公开 API 一览），缺文件时扫源码顶层声明。

///|
/// 源码位置：文件路径 + 0 基行号。
pub struct Loc {
  path : String
  line : Int32
}

///|
/// 建源码位置（跨包构造用）。
pub fn loc_new(path : String, line : Int32) -> Loc {
  { path, line, }
}

///|
/// 包入口文件：优先生成的 `.mbti`（包 API 一览），其次 `moon.pkg`，最后第一个源码文件。
fn pkg_entry(s : Sigs, dir : String) -> String? {
  for f in ["pkg.generated.mbti", "moon.pkg"] {
    match io_read(s, dir + "/" + f) {
      Some(_) => return Some(dir + "/" + f)
      None => ()
    }
  }
  let files = io_ls(s, dir)
  files.sort()
  for f in files {
    if f.has_suffix(".mbt") &&
      !f.has_suffix("_test.mbt") &&
      !f.has_suffix("_wbtest.mbt") {
      return Some(dir + "/" + f)
    }
  }
  None
}

///|
/// 去掉可见性前缀（`pub(all) enum` → `enum`）。
fn strip_vis(l : String) -> String {
  for p in ["pub(all) ", "pub(fn) ", "pub ", "priv "] {
    if l.has_prefix(p) {
      return l[p.length():].to_owned()
    }
  }
  l
}

///|
/// 跳过 `[..]`（泛型参数块），返回 `]` 之后的位置。
fn skip_bracket(cs : Array[Char], from : Int32) -> Int32 {
  let n = cs.length()
  let mut i = from
  if i >= n || cs[i] != '[' {
    return i
  }
  let mut depth = 0
  let mut done = false
  while i < n && !done {
    if cs[i] == '[' {
      depth += 1
    } else if cs[i] == ']' {
      depth -= 1
      if depth == 0 {
        done = true
      }
    }
    i += 1
  }
  i
}

///|
/// 从 `i` 起读一个名字（标识符，允许 `::`）。
fn read_name(cs : Array[Char], from : Int32) -> String {
  let n = cs.length()
  let mut i = from
  while i < n && (is_ident_char(cs[i]) || cs[i] == ':') {
    i += 1
  }
  slice_str(cs, from, i)
}

///|
/// 名字后跟的字符是否断词（`Store` 不匹配 `StoreX`）。
fn name_boundary(cs : Array[Char], at : Int32) -> Bool {
  if at >= cs.length() {
    return true
  }
  let c = cs[at]
  c == '(' ||
  c == '[' ||
  c == '{' ||
  c == '<' ||
  c == ' ' ||
  c == '\t' ||
  c == ':' ||
  c == '=' ||
  c == '?' ||
  c == ',' ||
  c == ')'
}

///|
/// 一行顶层声明 → 声明的名字：`fn[T] Store::new(...)` → `Store::new`；
/// 非声明行返回 None。
fn decl_name_of(l : String) -> String? {
  let body = strip_vis(l)
  let cs = chars_of(body)
  let n = cs.length()
  if n == 0 {
    return None
  }
  if body.has_prefix("fn") &&
    (n == 2 || cs[2] == ' ' || cs[2] == '\t' || cs[2] == '[') {
    let mut i = 2
    while i < n && (cs[i] == ' ' || cs[i] == '\t') {
      i += 1
    }
    i = skip_bracket(cs, i)
    while i < n && (cs[i] == ' ' || cs[i] == '\t') {
      i += 1
    }
    let name = read_name(cs, i)
    if name.length() > 0 && name_boundary(cs, i + name.length()) {
      return Some(name)
    }
    return None
  }
  for kw in ["struct", "enum", "typealias", "type", "const", "let"] {
    if body.has_prefix(kw) {
      let mut i = kw.length()
      while i < n && (cs[i] == ' ' || cs[i] == '\t') {
        i += 1
      }
      let name = read_name(cs, i)
      if name.length() > 0 && name_boundary(cs, i + name.length()) {
        return Some(name)
      }
      return None
    }
  }
  None
}

///|
/// 目录里找 `name` 的声明行（跳过测试文件）；文件名先排序保证选取确定。
fn scan_dir_for_decl(s : Sigs, dir : String, name : String) -> Loc? {
  let files = io_ls(s, dir)
  files.sort()
  for f in files {
    if !f.has_suffix(".mbt") ||
      f.has_suffix("_test.mbt") ||
      f.has_suffix("_wbtest.mbt") {
      continue
    }
    match io_read(s, dir + "/" + f) {
      Some(text) => {
        let lines = split_arr(text, "\n")
        let mut idx = 0
        for raw in lines {
          if !(raw.has_prefix(" ") || raw.has_prefix("\t")) {
            match decl_name_of(raw.trim().to_owned()) {
              Some(n) =>
                if n == name {
                  return Some({ path: dir + "/" + f, line: idx, })
                }
              None => ()
            }
          }
          idx += 1
        }
      }
      None => ()
    }
  }
  None
}

///|
/// 包目录里找成员声明（同名成员可能带 `::`）；先精确名，再按 `::尾段` 找方法。
fn member_decl(s : Sigs, dir : String, name : String) -> Loc? {
  match scan_dir_for_decl(s, dir, name) {
    Some(loc) => Some(loc)
    None =>
      match last_seg(name) {
        Some(n) =>
          if n != name {
            scan_dir_for_decl_suffix(s, dir, "::" + n)
          } else {
            None
          }
        None => None
      }
  }
}

///|
/// 目录里找声明名以 `suffix` 结尾的行（`Store.get` → `Store::get`）。
fn scan_dir_for_decl_suffix(s : Sigs, dir : String, suffix : String) -> Loc? {
  let files = io_ls(s, dir)
  files.sort()
  for f in files {
    if !f.has_suffix(".mbt") ||
      f.has_suffix("_test.mbt") ||
      f.has_suffix("_wbtest.mbt") {
      continue
    }
    match io_read(s, dir + "/" + f) {
      Some(text) => {
        let lines = split_arr(text, "\n")
        let mut idx = 0
        for raw in lines {
          if !(raw.has_prefix(" ") || raw.has_prefix("\t")) {
            match decl_name_of(raw.trim().to_owned()) {
              Some(n) =>
                if n.has_suffix(suffix) {
                  return Some({ path: dir + "/" + f, line: idx, })
                }
              None => ()
            }
          }
          idx += 1
        }
      }
      None => ()
    }
  }
  None
}

///|
/// 最后一个 `.` 之后的片段（`Store.new` → `new`）；无分隔符返回 None。
fn last_seg(s : String) -> String? {
  let cs = chars_of(s)
  let mut last = -1
  let mut i = 0
  while i < cs.length() {
    if cs[i] == '.' {
      last = i
    }
    i += 1
  }
  if last < 0 {
    None
  } else {
    Some(slice_str(cs, last + 1, cs.length()))
  }
}

///|
/// `@别名.成员` → (别名, 成员)；裸名返回 ("", 原文)。
fn split_alias(path : String) -> (String, String) {
  if !path.has_prefix("@") {
    return ("", path)
  }
  let body = path[1:].to_owned()
  match dot_index(body) {
    Some(d) => (body[:d].to_owned(), body[d + 1:].to_owned())
    None => (body, "")
  }
}

///|
/// moon.pkg 的别名表（只列解析到目录的），按名字排序。
pub fn Sigs::pkg_aliases(self : Sigs) -> Array[String] {
  sigs_ready(self)
  let out : Array[String] = []
  for (al, dir) in self.aliases {
    if dir.length() > 0 {
      out.push(al)
    }
  }
  out.sort()
  out
}

///|
/// 别名对应的包目录。
pub fn Sigs::alias_dir(self : Sigs, al : String) -> String? {
  sigs_ready(self)
  match self.aliases.get(al) {
    Some(d) => if d.length() > 0 { Some(d) } else { None }
    None => None
  }
}

///|
/// 跳转入口：`@别名` / `@别名.成员` / 同包裸名 → 文件 + 行号。
pub fn Sigs::locate_decl(self : Sigs, path : String) -> Loc? {
  sigs_ready(self)
  if path.length() == 0 {
    return None
  }
  let (al, rest) = split_alias(path)
  if al.length() == 0 {
    return scan_dir_for_decl(self, self.pkg_dir, path)
  }
  let dir = match self.alias_dir(al) {
    Some(d) => d
    None => return None
  }
  if rest.length() == 0 {
    match pkg_entry(self, dir) {
      Some(p) => Some({ path: p, line: 0, })
      None => None
    }
  } else {
    member_decl(self, dir, rest)
  }
}

///|
/// 跳转目标的原文行（hover 用）；定位失败返回 None。
pub fn Sigs::decl_text(self : Sigs, path : String) -> String? {
  match self.locate_decl(path) {
    Some(loc) =>
      match io_read(self, loc.path) {
        Some(text) => {
          let lines = split_arr(text, "\n")
          if loc.line >= 0 && loc.line < lines.length() {
            Some(lines[loc.line].trim().to_owned())
          } else {
            None
          }
        }
        None => None
      }
    None => None
  }
}

///|
/// `.mbti` 里的公开声明名（`fn[T] Store::new(...)`、`struct Store[T] {` …）。
fn mbti_members(text : String, out : Array[String]) -> Unit {
  for raw in split_arr(text, "\n") {
    match decl_name_of(raw.trim().to_owned()) {
      Some(name) =>
        if name.length() > 0 && !arr_contains(out, name) {
          out.push(name)
        }
      None => ()
    }
  }
}

///|
/// 是否公开声明（`pub ` / `pub(all) ` / `pub(fn) `）。
fn is_pub(l : String) -> Bool {
  l.has_prefix("pub ") || l.has_prefix("pub(all) ") || l.has_prefix("pub(fn) ")
}

///|
/// 缺 `.mbti` 时扫源码：只收 `pub` 开头的顶层声明，避免把私有辅助函数列进补全。
fn source_members(s : Sigs, dir : String, out : Array[String]) -> Unit {
  let files = io_ls(s, dir)
  files.sort()
  for f in files {
    if !f.has_suffix(".mbt") ||
      f.has_suffix("_test.mbt") ||
      f.has_suffix("_wbtest.mbt") {
      continue
    }
    match io_read(s, dir + "/" + f) {
      Some(text) =>
        for raw in split_arr(text, "\n") {
          let l = raw.trim().to_owned()
          if !is_pub(l) {
            continue
          }
          match decl_name_of(l) {
            Some(n) => if !arr_contains(out, n) { out.push(n) }
            None => ()
          }
        }
      None => ()
    }
  }
}

///|
/// `@别名.` 后的补全候选：优先生成的 `.mbti`，缺文件时扫源码公开声明。
pub fn Sigs::members(self : Sigs, al : String) -> Array[String] {
  sigs_ready(self)
  let out : Array[String] = []
  match self.alias_dir(al) {
    Some(dir) =>
      match io_read(self, dir + "/pkg.generated.mbti") {
        Some(text) => mbti_members(text, out)
        None => source_members(self, dir, out)
      }
    None => ()
  }
  out
}
