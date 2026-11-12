// 组件签名解析：`@别名.函数名` → 该函数的源码签名原文。内核零依赖，文件访问
// 由工具侧注入（mng build/dev/lsp 共用）。定位口径：当前包的 moon.pkg 取
// 别名 → 包标识，workspace 成员（moon.work + 各 moon.mod 的 name）与
// .mooncakes 依赖目录把包标识换成目录，再扫 *.mbt（含生成的 *.gen.mbt）与 *.mng。

///|
/// 文件访问端口：读文件（失败 None）与列目录（失败空数组）。
pub struct Io {
  read : (String) -> String?
  list_dir : (String) -> Array[String]
}

///|
/// 建文件访问端口（工具侧把 @fs 包进来）。
pub fn io_new(
  read : (String) -> String?,
  list_dir : (String) -> Array[String],
) -> Io {
  { read, list_dir, }
}

///|
/// 解析器：以某个 .mng 文件所在包为上下文，可复用（内部有目录与签名缓存）。
pub struct Sigs {
  root : String
  pkg_dir : String
  io : Io
  // 别名 → 包目录（首轮解析 moon.pkg 时建好）
  aliases : Map[String, String]
  fn_cache : Map[String, String]
  mut ready : Bool
}

///|
/// 建解析器：`root` 是 workspace 根（含 moon.work；单模块工程传模块目录），
/// `pkg_dir` 是模板文件所在目录。
pub fn sigs_new(root : String, pkg_dir : String, io : Io) -> Sigs {
  { root, pkg_dir, io, aliases: Map([]), fn_cache: Map([]), ready: false, }
}

///|
fn io_read(s : Sigs, p : String) -> String? {
  (s.io.read)(p)
}

///|
fn io_ls(s : Sigs, p : String) -> Array[String] {
  (s.io.list_dir)(p)
}

///|
/// moon.pkg 的 import 行 → 别名 → 包标识：`"a/b/c" @x` 取 x，`"a/b/c"` 取末段 c。
fn parse_imports(text : String, out : Map[String, String]) -> Unit {
  for raw in split_arr(text, "\n") {
    let l = raw.trim().to_owned()
    let cs = chars_of(l)
    let n = cs.length()
    if n == 0 || cs[0] != '"' {
      continue
    }
    let mut i = 1
    while i < n && cs[i] != '"' {
      i += 1
    }
    if i >= n {
      continue
    }
    let pkg = slice_str(cs, 1, i)
    let rest = slice_str(cs, i + 1, n).trim().to_owned()
    let al = if rest.has_prefix("@") {
      let a = chars_of(rest)
      let mut k = 1
      while k < a.length() && (is_ident_char(a[k]) || a[k] == '.') {
        k += 1
      }
      slice_str(a, 1, k)
    } else {
      let segs = split_arr(pkg, "/")
      if segs.length() > 0 {
        segs[segs.length() - 1]
      } else {
        ""
      }
    }
    if al.length() > 0 {
      let _ = out.set(al, pkg)
    }
  }
}

///|
/// moon.work 的 members 数组 → 成员目录数组。
fn parse_members(text : String) -> Array[String] {
  let out : Array[String] = []
  let mut in_members = false
  for raw in split_arr(text, "\n") {
    let l = raw.trim().to_owned()
    if l.has_prefix("members") {
      in_members = true
    }
    if !in_members {
      continue
    }
    let cs = chars_of(l)
    let n = cs.length()
    let mut i = 0
    while i < n {
      if cs[i] == '"' {
        let mut j = i + 1
        while j < n && cs[j] != '"' {
          j += 1
        }
        if j > i + 1 {
          out.push(slice_str(cs, i + 1, j))
        }
        i = j + 1
      } else {
        i += 1
      }
    }
    if l.has_prefix("]") || l.has_suffix("]") {
      in_members = false
    }
  }
  out
}

///|
/// moon.mod 的 `name = "…"` → 模块名。
fn parse_mod_name(text : String) -> String {
  for raw in split_arr(text, "\n") {
    let l = raw.trim().to_owned()
    if l.has_prefix("name") {
      let cs = chars_of(l)
      let mut i = 0
      while i < cs.length() && cs[i] != '"' {
        i += 1
      }
      if i < cs.length() {
        let mut j = i + 1
        while j < cs.length() && cs[j] != '"' {
          j += 1
        }
        return slice_str(cs, i + 1, j)
      }
    }
  }
  ""
}

///|
/// 包标识 → 目录：先查 workspace 成员（模块名最长前缀），再查各 .mooncakes。
fn dir_of_pkg(s : Sigs, pkg : String) -> String {
  match s.fn_cache.get("@dir:" + pkg) {
    Some(d) => d
    None => {
      let found = find_pkg_dir(s, pkg)
      let _ = s.fn_cache.set("@dir:" + pkg, found)
      found
    }
  }
}

///|
fn mooncake_bases(s : Sigs) -> Array[String] {
  let out : Array[String] = []
  for b in [s.root, module_root(s), s.pkg_dir] {
    let cand = b + "/.mooncakes"
    if !arr_contains(out, cand) {
      out.push(cand)
    }
  }
  out
}

///|
/// 从模板包目录向上找模块根（含 moon.mod 的目录），到 root 为止。
fn module_root(s : Sigs) -> String {
  let mut cur = s.pkg_dir
  let mut hops = 0
  while hops < 24 {
    match io_read(s, cur + "/moon.mod") {
      Some(_) => return cur
      None => ()
    }
    let up = parent_dir(cur)
    if up == cur || up.length() == 0 {
      return s.root
    }
    cur = up
    hops += 1
  }
  s.root
}

///|
fn parent_dir(p : String) -> String {
  let cs = chars_of(p)
  let mut last = -1
  let mut i = 0
  while i < cs.length() {
    if cs[i] == '/' {
      last = i
    }
    i += 1
  }
  if last <= 0 {
    p
  } else {
    slice_str(cs, 0, last)
  }
}

///|
fn find_pkg_dir(s : Sigs, pkg : String) -> String {
  // ① workspace 成员：模块名是 pkg 前缀（且其后为 / 或结束）
  match io_read(s, s.root + "/moon.work") {
    Some(wt) =>
      for m in parse_members(wt) {
        match io_read(s, s.root + "/" + m + "/moon.mod") {
          Some(mt) => {
            let mn = parse_mod_name(mt)
            if mn.length() > 0 && pkg.has_prefix(mn) {
              let rest = pkg[mn.length():].to_owned()
              if rest.length() == 0 {
                return s.root + "/" + m
              }
              if chars_of(rest)[0] == '/' {
                return s.root + "/" + m + rest
              }
            }
          }
          None => ()
        }
      }
    None => ()
  }
  // ② 依赖缓存：.mooncakes/<author>/<name>[/<子包>]（模块名取前两段）
  let segs = split_arr(pkg, "/")
  if segs.length() >= 2 {
    let mn = segs[0] + "/" + segs[1]
    let sub = if segs.length() > 2 { "/" + join_segs(segs, 2) } else { "" }
    for base in mooncake_bases(s) {
      let cand = base + "/" + mn + sub
      match io_read(s, cand + "/moon.pkg") {
        Some(_) => return cand
        None => ()
      }
      // 依赖包目录里未必留 moon.pkg，退一步：能列出文件即认它
      let listing = io_ls(s, cand)
      if listing.length() > 0 {
        return cand
      }
    }
  }
  ""
}

///|
fn join_segs(segs : Array[String], from : Int32) -> String {
  let mut out = ""
  for k in from..<segs.length() {
    out = out + (if k > from { "/" } else { "" }) + segs[k]
  }
  out
}

///|
/// 从第 idx 行起的签名块：括号配平后含 `->` 或到出现 `{` 的行止。
fn sig_block(lines : Array[String], idx : Int32) -> String? {
  let n = lines.length()
  let mut depth = 0
  let mut opened = false
  let mut closed = false
  let block : Array[String] = []
  let mut j = idx
  let mut hops = 0
  while j < n && hops < 60 {
    let l = lines[j].trim().to_owned()
    block.push(l)
    hops += 1
    for c in chars_of(l) {
      if c == '(' {
        depth += 1
        opened = true
      } else if c == ')' {
        depth -= 1
      }
    }
    if opened && depth <= 0 {
      closed = true
    }
    if closed && (l.has_suffix("{") || contains_sub(l, "->")) {
      return Some(block.join("\n"))
    }
    if closed {
      j += 1
      continue
    }
    j += 1
  }
  if closed {
    Some(block.join("\n"))
  } else {
    None
  }
}

///|
/// 一行是否是 `fn <名>(` 声明（允许 `pub` / `pub(all)` / `pub(fn)` 前缀）。
fn decl_head_matches(l : String, fname : String) -> Bool {
  for kw in ["fn ", "pub fn ", "pub(all) fn ", "pub(fn) fn "] {
    if l.has_prefix(kw) {
      let rest = l[kw.length():].to_owned()
      if rest.has_prefix(fname) {
        let after = rest[fname.length():].trim_start().to_owned()
        if after.has_prefix("(") || after.has_prefix(")") {
          return true
        }
      }
    }
  }
  false
}

///|
/// 一个源码文本里找顶层 `fn <名>(` 的签名块（行首无缩进——缩进的是函数体内的辅助函数）。
fn find_fn_in_text(text : String, fname : String) -> String? {
  let lines = split_arr(text, "\n")
  let mut i = 0
  let n = lines.length()
  while i < n {
    let raw = lines[i]
    if !(raw.has_prefix(" ") || raw.has_prefix("\t")) {
      let l = raw.trim().to_owned()
      if decl_head_matches(l, fname) {
        match sig_block(lines, i) {
          Some(b) => return Some(b)
          None => ()
        }
      }
    }
    i += 1
  }
  None
}

///|
/// 一个源码文本里顶层 `fn <名>` 上方的 `///` 文档注释（到 `///|` 分隔符为止）。
fn find_doc_in_text(text : String, fname : String) -> String? {
  let lines = split_arr(text, "\n")
  let mut i = 0
  let n = lines.length()
  while i < n {
    let raw = lines[i]
    if !(raw.has_prefix(" ") || raw.has_prefix("\t")) {
      if decl_head_matches(raw.trim().to_owned(), fname) {
        let out : Array[String] = []
        let mut k = i - 1
        while k >= 0 {
          let d = lines[k].trim().to_owned()
          if d == "///|" || !d.has_prefix("///") {
            break
          }
          let cs = chars_of(d)
          out.push(slice_str(cs, 3, cs.length()).trim().to_owned())
          k -= 1
        }
        if out.length() == 0 {
          return None
        }
        let joined = out.rev().join("\n")
        return Some(joined)
      }
    }
    i += 1
  }
  None
}

///|
/// 目录里的源码找文档注释（与签名扫描同一选取口径）。
fn scan_dir_for_doc(s : Sigs, dir : String, fname : String) -> String? {
  let files = io_ls(s, dir)
  files.sort()
  for f in files {
    if f.has_suffix("_test.mbt") || f.has_suffix("_wbtest.mbt") {
      continue
    }
    if f.has_suffix(".mbt") {
      match io_read(s, dir + "/" + f) {
        Some(text) =>
          match find_doc_in_text(text, fname) {
            Some(d) => return Some(d)
            None => ()
          }
        None => ()
      }
    }
  }
  None
}

///|
/// 组件路径 → 声明上方的文档注释原文（编辑器 hover 用）；没有给 None。
pub fn Sigs::doc_of(self : Sigs, path : String) -> String? {
  let (dir, fname) = self.path_dir(path)
  if dir.length() == 0 {
    None
  } else {
    scan_dir_for_doc(self, dir, fname)
  }
}

///|
/// 一个 .mng 里找同名 props 头（生成的 .gen.mbt 未必已落盘）。
fn find_fn_in_mng(text : String, fname : String) -> String? {
  let sfc = match parse_sfc(text) {
    Ok(v) => v
    Err(_) => return None
  }
  let (head, _) = find_head(split_arr(sfc.script, "\n"))
  if head.length() == 0 {
    return None
  }
  match parse_fn_sig(head.join("\n")) {
    Some(sig) => if sig.name == fname { Some(head.join("\n")) } else { None }
    None => None
  }
}

///|
/// 目录里的源码扫签名：*.mbt 优先（含生成码），再扫 *.mng 的 props 头；
/// 文件名先排序，保证同名声明的选取是确定的。
fn scan_dir_for_fn(s : Sigs, dir : String, fname : String) -> String? {
  let files = io_ls(s, dir)
  files.sort()
  for f in files {
    if f.has_suffix("_test.mbt") || f.has_suffix("_wbtest.mbt") {
      continue
    }
    if f.has_suffix(".mbt") {
      match io_read(s, dir + "/" + f) {
        Some(text) =>
          match find_fn_in_text(text, fname) {
            Some(b) => return Some(b)
            None => ()
          }
        None => ()
      }
    }
  }
  for f in files {
    if f.has_suffix(".mng") {
      match io_read(s, dir + "/" + f) {
        Some(text) =>
          match find_fn_in_mng(text, fname) {
            Some(b) => return Some(b)
            None => ()
          }
        None => ()
      }
    }
  }
  None
}

///|
/// 首次使用时装载 `moon.pkg` 的别名表（别名 → 包目录）。
fn sigs_ready(s : Sigs) -> Unit {
  if s.ready {
    return
  }
  let pkgs : Map[String, String] = Map([])
  match io_read(s, s.pkg_dir + "/moon.pkg") {
    Some(text) => parse_imports(text, pkgs)
    None => ()
  }
  for (al, pkg) in pkgs {
    let _ = s.aliases.set(al, dir_of_pkg(s, pkg))
  }
  s.ready = true
}

///|
/// `@别名.名` / 同包裸名 → (所在包目录, 函数名)；解析不出给 ("", "")。
fn Sigs::path_dir(self : Sigs, path : String) -> (String, String) {
  sigs_ready(self)
  if path.length() == 0 {
    return ("", "")
  }
  let (al, fname) = if path.has_prefix("@") {
    let body = path[1:].to_owned()
    match dot_index(body) {
      Some(d) => (body[:d].to_owned(), body[d + 1:].to_owned())
      None => ("", "")
    }
  } else {
    ("", path)
  }
  if fname.length() == 0 {
    return ("", "")
  }
  let dir = if al.length() == 0 {
    self.pkg_dir
  } else {
    match self.aliases.get(al) {
      Some(d) => d
      None => ""
    }
  }
  (dir, fname)
}

///|
/// 解析入口：`@别名.名` 或同包裸名 `名` → 签名原文；解析不到返回 None（组件需 `// @mng` 覆盖）。
pub fn Sigs::resolve(self : Sigs, path : String) -> String? {
  let (dir, fname) = self.path_dir(path)
  if fname.length() == 0 {
    return None
  }
  match self.fn_cache.get(path) {
    Some(cached) => if cached.length() > 0 { Some(cached) } else { None }
    None => {
      let found = if dir.length() == 0 {
        None
      } else {
        scan_dir_for_fn(self, dir, fname)
      }
      match found {
        Some(text) => {
          let _ = self.fn_cache.set(path, text)
          Some(text)
        }
        None => {
          let _ = self.fn_cache.set(path, "")
          None
        }
      }
    }
  }
}

///|
fn dot_index(s : String) -> Int32? {
  let cs = chars_of(s)
  let mut i = 0
  while i < cs.length() {
    if cs[i] == '.' {
      return Some(i)
    }
    i += 1
  }
  None
}

///|
/// 目录里找顶层 `fn <名>` 所在的源码文件（跳转用）；扫描顺序与签名解析一致。
fn scan_dir_for_file(s : Sigs, dir : String, fname : String) -> String? {
  let files = io_ls(s, dir)
  files.sort()
  for f in files {
    if f.has_suffix("_test.mbt") || f.has_suffix("_wbtest.mbt") {
      continue
    }
    if f.has_suffix(".mbt") {
      match io_read(s, dir + "/" + f) {
        Some(text) =>
          match find_fn_in_text(text, fname) {
            Some(_) => return Some(dir + "/" + f)
            None => ()
          }
        None => ()
      }
    }
  }
  for f in files {
    if f.has_suffix(".mng") {
      match io_read(s, dir + "/" + f) {
        Some(text) =>
          match find_fn_in_mng(text, fname) {
            Some(_) => return Some(dir + "/" + f)
            None => ()
          }
        None => ()
      }
    }
  }
  None
}

///|
/// 组件路径 → 定义所在源码文件（`@别名.名` 或同包裸名）；找不到返回 None。
pub fn Sigs::locate(self : Sigs, path : String) -> String? {
  let (dir, fname) = self.path_dir(path)
  if fname.length() == 0 {
    return None
  }
  if dir.length() == 0 {
    None
  } else {
    scan_dir_for_file(self, dir, fname)
  }
}
