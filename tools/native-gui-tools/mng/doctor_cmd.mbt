// mng doctor 命令面：渲染 @doctor 的体检结果并收尾 ready。探针与判据在 @doctor。

///|
/// 取双语文案的一侧（语言开关与命令面其余文案同源）。
fn dbi_pick(b : @doctor.DBi) -> String {
  if cli_zh[0] {
    b.zh
  } else {
    b.en
  }
}

///|
fn status_glyph(s : @doctor.DStatus) -> String {
  match s {
    Ok => "[✓]"
    Warn => "[!]"
    Fail => "[✗]"
  }
}

///|
/// `mng doctor [-f]`：环境体检；全绿写 `~/.mng/ready`。返回进程退出码。
fn cmd_doctor(force~ : Bool = false) -> Int32 {
  let home = @doctor.home_dir()
  let path = @doctor.ready_path(home~)
  if !force && @doctor.ready_valid(path~, version=MNG_VERSION) {
    println(
      tmsg(
        "环境已就绪（\{path}，mng \{MNG_VERSION}）；-f 强制重检",
        "Environment already verified (\{path}, mng \{MNG_VERSION}); pass -f to re-check",
      ),
    )
    return 0
  }
  println(
    tmsg(
      "mng doctor — 开发环境体检（mng \{MNG_VERSION}）",
      "mng doctor — environment health check (mng \{MNG_VERSION})",
    ),
  )
  let items = @doctor.run_all()
  let mut fails = 0
  for it in items {
    println(
      "\{status_glyph(it.status)} \{dbi_pick(it.title)} — \{dbi_pick(it.detail)}",
    )
    if it.status is Fail {
      fails += 1
      match it.fix {
        Some(f) => println("  \{tmsg("修复", "fix")}: \{dbi_pick(f)}")
        None => ()
      }
    }
  }
  if @doctor.required_ok(items) {
    if @doctor.ready_write(home~, version=MNG_VERSION) {
      println(
        tmsg(
          "环境就绪：已写 \{path}（mng \{MNG_VERSION}，版本变更时自动重检）",
          "Environment ready: wrote \{path} (mng \{MNG_VERSION}; re-checked on version change)",
        ),
      )
    } else {
      println(
        tmsg(
          "环境就绪，但 ready 写盘失败（\{path}）——不影响本次结论",
          "Environment ready, but writing \{path} failed; this run's verdict stands",
        ),
      )
    }
    0
  } else {
    println(
      tmsg(
        "有 \{fails} 项缺失——按「修复」行处理后重跑 mng doctor",
        "\{fails} check(s) failed — apply the fix hints and re-run mng doctor",
      ),
    )
    1
  }
}

///|
/// 兄弟可执行查找：依次试 `<dir>/<名>` 与 `<dir>/<名>.exe`；都在位给全路径。
fn sibling_exe(dir : String, name : String) -> String? {
  let a = dir + "/" + name
  if @fs.path_exists(a) {
    return Some(a)
  }
  let b = a + ".exe"
  if @fs.path_exists(b) {
    return Some(b)
  }
  None
}

///|
/// 裸 mng 在 ready 有效后的下一跳：让位给 mngui 向导。
/// 目录解析：进程真实路径（argv[0] 是 shell 敲进去的名字，常无目录）
/// → argv0 带 目录时用它的目录 → 兜底 ~/.moon/bin（标准安装位）。
/// 返回 (mngui 是否在位, 退出码)；「没装上」与「无显示服务」都回落 usage，
/// 但前者要给安装提示——调用方按首位区分。
/// proj 非空 = 工程面板模式（裸 mng 在已有工程里跑）；空 = 新建向导。
fn mngui_hop(argv0 : String, proj : String) -> (Bool, Int32) {
  let mut last = -1
  for i, c in argv0 {
    if c == '/' || c == '\\' {
      last = i
    }
  }
  let candidates : Array[String] = []
  match @proc.self_path() {
    Some(p) => {
      let mut l = -1
      for i, c in p {
        if c == '/' || c == '\\' {
          l = i
        }
      }
      if l > 0 {
        candidates.push(p[0:l].to_owned())
      }
    }
    None => ()
  }
  if last > 0 {
    candidates.push(argv0[0:last].to_owned())
  }
  match @doctor.home_dir() {
    h if h.length() > 0 => candidates.push(h + "/.moon/bin")
    _ => ()
  }
  let args : Array[String] = if proj.length() > 0 {
    ["--project", proj]
  } else {
    []
  }
  for dir in candidates {
    match sibling_exe(dir, "mngui") {
      Some(exe) =>
        match @proc.spawn_wait(exe, args, "", 0x7fffffff) {
          Ok(code) => return (true, code)
          Err(_) => return (true, 3)
        }
      None => ()
    }
  }
  (false, 3)
}
