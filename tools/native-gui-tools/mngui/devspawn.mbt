// 兄弟可执行定位与 mng dev 后台启动。

///|
/// argv0 去文件名留目录（认 / 与 \ 两种分隔）。
fn argv0_dir(argv0 : String) -> String {
  let mut last = -1
  for i, c in argv0 {
    if c == '/' || c == '\\' {
      last = i
    }
  }
  if last <= 0 {
    "."
  } else {
    argv0[0:last].to_owned()
  }
}

///|
fn exe_exists(base : String, name~ : String) -> String? {
  let a = base + "/" + name
  let b = a + ".exe"
  if @fs.path_exists(a) {
    Some(a)
  } else if @fs.path_exists(b) {
    Some(b)
  } else {
    None
  }
}

///|
fn mkdir_p(dir : String) -> Unit {
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
    // is_dir 对不存在的路径会 raise，按「还不是目录」继续建
    let isdir = @fs.is_dir(cur) catch { _ => false }
    if !isdir {
      @fs.create_dir(cur) catch {
        _ => return
      }
    }
  }
}

///|
/// 后台启动 mng dev：cwd 要在工程目录而 proc 无 cwd 参，走 shell 包装
/// （win 用 cmd /C，POSIX 用 sh -c）。dev 形态（moon run 起的向导）经
/// `moon -C <仓库> run …` 回仓库调 mng。日志落 `<工程>/.mng/wizard/dev.log`。
fn start_dev(w : Wizard) -> Unit {
  let proj = w.proj.get()
  if proj.length() == 0 {
    w.dev_hint.set("还没有工程目录——先在上一页创建应用")
    return
  }
  let mng_part : String = if w.dev_form {
    "moon -C \"" + w.repo_cwd + "\" run tools/native-gui-tools/mng -- dev"
  } else {
    match exe_exists(w.argv0_dir, name="mng") {
      Some(p) => "\"" + p + "\" dev"
      None => {
        w.dev_hint.set(
          "在向导旁边找不到 mng（" +
          w.argv0_dir +
          "）——在工程目录手动跑 mng dev",
        )
        return
      }
    }
  }
  mkdir_p(proj + "/.mng/wizard")
  let log = proj + "/.mng/wizard/dev.log"
  let cmd = "cd \"" + proj + "\" && " + mng_part
  let res = if @doctor.host() == "win" {
    @proc.spawn("cmd", ["/C", cmd], log)
  } else {
    @proc.spawn("sh", ["-c", cmd], log)
  }
  match res {
    Ok(pid) =>
      w.dev_hint.set("mng dev 已启动（pid \{pid}，日志 " + log + "）")
    Err(e) => w.dev_hint.set("启动失败：" + e)
  }
}
