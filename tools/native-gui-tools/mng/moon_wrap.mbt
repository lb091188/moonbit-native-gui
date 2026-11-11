// run / check / test 子命令：工程中心化的 moon 包装层。
// run = mng.toml 的 build/run（或 Artifacts 推导）+ 前台执行；check/test =
// 透传 moon 同名子命令（stdio 继承，退出码透传）。都在 cwd 所在工程里跑。

///|
/// run 子命令：构建当前工程并前台运行可执行。
/// `mng run [子目录]`——缺省当前目录；子目录用于 monorepo 里指定工程。
fn cmd_run(args : Array[String]) -> Int32 {
  if args.length() > 1 {
    println(tmsg("run 最多带一个子目录参数", "run takes at most one subdirectory"))
    return 2
  }
  let cwd = match @env.current_dir() {
    Some(d) => d
    None => "."
  }
  let dir = if args.length() == 1 {
    let d = join_under(cwd, args[0])
    if !is_dir(d) {
      println(tmsg("目录不存在：" + d, "No such directory: " + d))
      return 1
    }
    d
  } else {
    cwd
  }
  let conf = match
    load_dev_conf("", "", "", None, dir) {
    Ok(c) => c
    Err(e) => {
      eprintln(e)
      return 2
    }
  }
  let mut run_expr = conf.run
  if run_expr.length() == 0 {
    match derive_run(conf.build, module_name_at(conf.dir)) {
      Ok(cmd) => run_expr = cmd
      Err(e) => {
        eprintln(e)
        return 1
      }
    }
  } else {
    // run 配置了也要先跑 build（dev 同口径）
    match split_cmd(conf.build) {
      Some((bfile, bargs)) =>
        match @proc.run_wait(bfile, bargs, 600000) {
          Err(e) => {
            eprintln(tmsg("build 失败：" + e, "build failed: " + e))
            return 1
          }
          Ok(code) =>
            if code != 0 {
              eprintln(tmsg("build 退出码 " + code.to_string(), "build exit code " + code.to_string()))
              return 1
            }
        }
      None => {
        eprintln(tmsg("build 为空", "build is empty"))
        return 1
      }
    }
  }
  let (rfile, rargs) = match split_cmd(run_expr) {
    Some(p) => p
    None => {
      eprintln(tmsg("run 为空", "run is empty"))
      return 1
    }
  }
  // 前台执行：stdio 继承终端，退出码透传（与 dev 的后台落日志区分——
  // 这条面向「我就想跑一下」，不是 watch 循环）
  match @proc.run_wait(rfile, rargs, 2_000_000_000) {
    Err(e) => {
      eprintln(tmsg("跑不起来：" + e, "cannot run: " + e))
      1
    }
    Ok(code) => code
  }
}

///|
/// check / test 子命令：透传 moon 同名子命令与全部参数，退出码透传。
fn cmd_moon_passthrough(moon_args : Array[String], label : String) -> Int32 {
  match @proc.run_wait("moon", moon_args, 2_000_000_000) {
    Err(e) => {
      eprintln(tmsg("moon " + label + " 跑不起来：" + e, "cannot run moon " + label + ": " + e))
      1
    }
    Ok(code) => code
  }
}

///|
fn cmd_check(args : Array[String]) -> Int32 {
  cmd_moon_passthrough(["check"] + args, "check")
}

///|
fn cmd_test(args : Array[String]) -> Int32 {
  cmd_moon_passthrough(["test"] + args, "test")
}

///|
fn is_dir(p : String) -> Bool {
  (@fs.is_dir(p) catch { _ => false })
}
