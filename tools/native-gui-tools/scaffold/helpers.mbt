// 内核自带的小助手（与 mng 各持一份的口径一致：工具包间不共享私有件）。

///|
fn spit(p : String, s : String) -> Bool {
  @fs.write_string_to_file(p, s) catch {
    _ => return false
  }
  true
}

///|
fn mkdir_p(dir : String) -> Bool {
  let parts = dir
    .split("/")
    .filter(fn(x) { x.length() > 0 })
    .map(fn(x) { x.to_owned() })
  let mut cur = if dir.has_prefix("/") { "/" } else { "" }
  for p in parts {
    if cur == "/" {
      cur = "/" + p
    } else if cur.length() == 0 {
      cur = p
    } else {
      cur = cur + "/" + p
    }
    // is_dir 对不存在的路径会 raise，按「还不是目录」处理继续建
    let isdir = @fs.is_dir(cur) catch { _ => false }
    if !isdir {
      @fs.create_dir(cur) catch {
        _ => return false
      }
    }
  }
  true
}

///|
fn chars_of(s : String) -> Array[Char] {
  let out : Array[Char] = []
  for c in s {
    out.push(c)
  }
  out
}

///|
fn is_digit_m(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
fn basename(p : String) -> String {
  let a = chars_of(p)
  let mut start = 0
  for k, c in a {
    if c == '/' {
      start = k + 1
    }
  }
  a[start:].map(fn(c) { c.to_string() }).join("")
}

///|
fn slice_path(a : Array[Char], lo : Int32, hi : Int32) -> String {
  if hi <= lo {
    ""
  } else {
    a[lo:hi].map(fn(c) { c.to_string() }).join("")
  }
}

///|
fn trim_spaces(s : String) -> String {
  s.trim().to_owned()
}

///|
/// `"串"` → 内容（去引号）。
fn unquote(v : String) -> String {
  let s = trim_spaces(v)
  if s.length() >= 2 && s.has_prefix("\"") && s.has_suffix("\"") {
    s[1:s.length() - 1].to_owned()
  } else {
    s
  }
}

///|
fn index_of_char(s : String, c : Char) -> Int32? {
  let a = chars_of(s)
  let mut i = 0
  while i < a.length() {
    if a[i] == c {
      return Some(i)
    }
    i += 1
  }
  None
}

///|
/// `-` → `_`，其余原样（文件名 stem → 生成函数名）。
fn snake_of(s : String) -> String {
  let cs = chars_of(s)
  let out : Array[String] = []
  for c in cs {
    if c == '-' {
      out.push("_")
    } else {
      out.push(c.to_string())
    }
  }
  out.join("")
}

///|
/// 工程名合法化：字母/数字/下划线/连字符；首字符数字垫 _。
fn mod_name(raw : String) -> String {
  let a = chars_of(raw)
  let out = StringBuilder()
  for c in a {
    if (c >= 'a' && c <= 'z') ||
      (c >= 'A' && c <= 'Z') ||
      (c >= '0' && c <= '9') ||
      c == '_' ||
      c == '-' {
      out.write_char(c)
    }
  }
  let s = out.to_string()
  if s.length() == 0 || is_digit_m(s.to_array()[0]) {
    "_" + s
  } else {
    s
  }
}

///|
/// 版本现读：向上找 moon.work → 读 gui/moon.mod 的 version 与 yoga import；
/// 不在仓库内给兜底值。
fn versions(from : String) -> (String, String) {
  let mut cur = from
  let mut hops = 0
  while hops < 24 {
    if (match fs_read(cur + "/moon.work") {
        Some(_) => true
        None => false
      }) {
      let gmod = match fs_read(cur + "/gui/moon.mod") {
        Some(t) => t
        None => return (SCAFFOLD_GUI_FALLBACK, SCAFFOLD_YOGA_FALLBACK)
      }
      let gui_ver = match line_value(gmod, "version") {
        Some(v) => v
        None => SCAFFOLD_GUI_FALLBACK
      }
      let yoga_ver = match import_ver(gmod, "NoahLiu/yoga-mbt") {
        Some(v) => v
        None => SCAFFOLD_YOGA_FALLBACK
      }
      return (gui_ver, yoga_ver)
    }
    let up = dir_up(cur)
    if up == cur {
      break
    }
    cur = up
    hops += 1
  }
  (SCAFFOLD_GUI_FALLBACK, SCAFFOLD_YOGA_FALLBACK)
}

///|
/// moon.mod 顶层键取值：`version = "0.3.1"` → 0.3.1。
fn line_value(text : String, key : String) -> String? {
  for line0 in text.split("\n") {
    let line = trim_spaces(line0.to_owned())
    if line.has_prefix(key + " ") || line.has_prefix(key + "=") {
      let rest = trim_spaces(line[key.length():].to_owned())
      if rest.has_prefix("=") {
        return Some(unquote(rest[1:].to_owned()))
      }
    }
  }
  None
}

///|
/// moon.mod import 块里 `"<pkg>@<ver>"` 的版本。
fn import_ver(text : String, pkg : String) -> String? {
  for line0 in text.split("\n") {
    let line = trim_spaces(line0.to_owned())
    if line.has_prefix("\"" + pkg + "@") && line.has_suffix("\",") {
      let body = line[1:line.length() - 2].to_owned()
      let at = match index_of_char(body, '@') {
        Some(i) => i
        None => continue
      }
      return Some(body[at + 1:].to_owned())
    }
  }
  None
}

///|
/// 目录部分：`a/b/c` → `a/b`；无分隔符原样返回。
fn dir_up(p : String) -> String {
  let a = chars_of(p)
  let mut last = -1
  for i, c in a {
    if c == '/' {
      last = i
    }
  }
  if last <= 0 {
    p
  } else {
    slice_path(a, 0, last)
  }
}

///|
fn fs_read(p : String) -> String? {
  let s = @fs.read_file_to_string(p) catch { _ => return None }
  Some(s)
}

///|
fn fs_ls(p : String) -> Array[String] {
  let out : Array[String] = []
  let dir_ok = @fs.is_dir(p) catch { _ => false }
  if !dir_ok {
    return out
  }
  let entries = @fs.read_dir(p) catch { _ => return out }
  for f in entries {
    out.push(f.to_string())
  }
  out
}

///|
/// 目录部分：`a/b/c.mng` → `a/b`（无斜杠返回 `.`）。
fn dir_of(p : String) -> String {
  let a = chars_of(p)
  let mut last = -1
  let mut i = 0
  while i < a.length() {
    if a[i] == '/' {
      last = i
    }
    i += 1
  }
  if last <= 0 {
    "."
  } else if last == a.length() - 1 {
    "."
  } else {
    slice_path(a, 0, last)
  }
}

///|
/// workspace 根：从模板目录向上找 moon.work；退到模块根（moon.mod）；再退本目录。
fn ws_root(dir : String) -> String {
  let mut cur = dir
  let mut hops = 0
  let mut mod_root = ""
  while hops < 24 {
    let has_work = match fs_read(cur + "/moon.work") {
      Some(_) => true
      None => false
    }
    if has_work {
      return cur
    }
    if mod_root.length() == 0 {
      match fs_read(cur + "/moon.mod") {
        Some(_) => mod_root = cur
        None => ()
      }
    }
    let up = dir_of(cur)
    if up == cur {
      break
    }
    cur = up
    hops += 1
  }
  if mod_root.length() > 0 {
    mod_root
  } else {
    dir
  }
}

///|
/// 编译（dev 形态）：多出页面注册表与 holder 落点（状态保活骨架）。
fn compile_dev(src : String, path : String) -> Result[@mngkit.GenOut, String] {
  let dir = dir_of(path)
  let sigs = @mngkit.sigs_new(ws_root(dir), dir, @mngkit.io_new(fs_read, fs_ls))
  @mngkit.compile_dev(src, path, fn(p : String) { sigs.resolve(p) })
}
