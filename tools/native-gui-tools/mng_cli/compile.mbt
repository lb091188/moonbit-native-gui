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
/// 编译：模板源码 + 路径 → 生成码与 source map（跨包组件签名按源码解析）。
fn mng_compile(src : String, path : String) -> Result[@mngkit.GenOut, String] {
  let dir = dir_of(path)
  let sigs = @mngkit.sigs_new(ws_root(dir), dir, @mngkit.io_new(fs_read, fs_ls))
  @mngkit.compile_with(src, path, fn(p : String) { sigs.resolve(p) })
}
