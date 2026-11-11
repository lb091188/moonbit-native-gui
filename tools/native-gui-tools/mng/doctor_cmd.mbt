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
/// 裸 mng 在 ready 有效后的下一跳：让位给同目录的 mngui 向导。
/// 返回 mngui 退出码；起不来（没装上/路径异常）返回 3，调用方回 usage。
/// 退出码 3 同时是 mngui「无显示服务」的信号——两种都回落 usage。
fn mngui_hop(argv0 : String) -> Int32 {
  let mut last = -1
  for i, c in argv0 {
    if c == '/' || c == '\\' {
      last = i
    }
  }
  if last <= 0 {
    return 3
  }
  let dir = argv0[0:last].to_owned()
  let exe = dir + "/mngui"
  let exe = if @fs.path_exists(exe) {
    exe
  } else if @fs.path_exists(exe + ".exe") {
    exe + ".exe"
  } else {
    return 3
  }
  match @proc.spawn_wait(exe, [], "", 0x7fffffff) {
    Ok(code) => code
    Err(_) => 3
  }
}
