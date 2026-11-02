// 编译入口装配：给 mngkit 接上文件系统端口，按模板所在包解析组件签名。
// 端口口径与 mngkit/resolve.mbt 一致（读失败 None、列失败空数组）。

///|
fn fs_read(p : String) -> String? {
  let s = @fs.read_file_to_string(p) catch {
    _ => return None
  }
  Some(s)
}

///|
fn fs_ls(p : String) -> Array[String] {
  let out : Array[String] = []
  let dir_ok = @fs.is_dir(p) catch {
    _ => false
  }
  if !dir_ok {
    return out
  }
  let entries = @fs.read_dir(p) catch {
    _ => return out
  }
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
fn slice_path(a : Array[Char], lo : Int, hi : Int) -> String {
  if hi <= lo {
    ""
  } else {
    a[lo:hi].map(fn(c) { c.to_string() }).join("")
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
    let up = parent_of(cur)
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
fn parent_of(p : String) -> String {
  dir_of(p)
}

///|
/// 编译（生产形态）：模板源码 + 路径 → 生成码与 source map（跨包组件签名按源码解析）。
fn mng_compile(src : String, path : String) -> Result[@mngkit.GenOut, String] {
  let dir = dir_of(path)
  let sigs = @mngkit.sigs_new(ws_root(dir), dir, @mngkit.io_new(fs_read, fs_ls))
  @mngkit.compile_with(src, path, fn(p : String) { sigs.resolve(p) })
}

///|
/// 编译（dev 形态）：多出页面注册表与 holder 落点（状态保活骨架）。
fn mng_compile_dev(src : String, path : String) -> Result[@mngkit.GenOut, String] {
  let dir = dir_of(path)
  let sigs = @mngkit.sigs_new(ws_root(dir), dir, @mngkit.io_new(fs_read, fs_ls))
  @mngkit.compile_dev(src, path, fn(p : String) { sigs.resolve(p) })
}

///|
/// 文件名 → 生成函数名（与 mngkit 同规则：去首个扩展段、非法字符转下划线）。
fn stem_of_file(name : String) -> String {
  let base = basename(name)
  let a = chars_of(base)
  let mut end = a.length()
  let mut k = 0
  while k < a.length() {
    if a[k] == '.' {
      end = k
      break
    }
    k += 1
  }
  let mut out = ""
  for i in 0..<end {
    let c = a[i]
    out = out + (if is_ident_char(c) { c.to_string() } else { "_" })
  }
  if out.length() == 0 {
    "page"
  } else if is_digit_m(chars_of(out)[0]) {
    "_" + out
  } else {
    out
  }
}

///|
fn is_digit_m(c : Char) -> Bool {
  c >= '0' && c <= '9'
}

///|
/// 同包 stem 撞名：同目录下多个 .mng 产出同名生成函数（同包 pub fn 冲突）。
fn stem_conflicts(path : String) -> Array[String] {
  let dir = dir_of(path)
  let self = basename(path)
  let stem = stem_of_file(self)
  let out : Array[String] = []
  for f in fs_ls(dir) {
    if f.has_suffix(".mng") && f != self && stem_of_file(f) == stem {
      out.push(dir + "/" + f)
    }
  }
  out
}

///|
/// 撞名报错文本（build/dev 共用）；无撞名返回 None。
fn stem_conflict_msg(path : String) -> String? {
  let c = stem_conflicts(path)
  if c.length() == 0 {
    None
  } else {
    let head = path + " 与同包的 " + c.join("、")
    let tail = "生成同名函数 `" + stem_of_file(path) + "`（生成函数名取文件 stem）——改一个文件名"
    Some(head + " " + tail)
  }
}
