// dev 子命令：watch 模板 → 内存编译 → 契约分类 → HOT 打标 / COLD 回退编排
// （moon build → 杀旧 → 带参重启）。分类判据与边界见
// proposals/native-template.md「开发循环」二轮节；HOT 的进程内补丁推送
// 等应用侧 dev 监听落地，本轮占位不打断应用。

fn usage_dev() -> Unit {
  println("用法：moon run tools/mng_cli -- dev --watch <文件或目录[,...]> --out-dir <生成码目录> --build-cmd <可执行 [参数...]> --run-cmd <可执行 [参数...]> [--poll-ms 300]")
  println("  watch：.mng.html 文件或目录（目录取其中 *.mng.html）")
  println("  out-dir：生成码落点（<stem>.gen.mbt），应指向应用包内同包目录")
  println("  build-cmd / run-cmd：按首个空格拆成可执行 + 参数直起，不穿 shell")
  println("  分类：script 段未变且表达式集合 ⊆ 基线 → HOT（只更新生成码并打标，不打断应用）；否则 COLD（build 成功后杀旧起新）")
}

///|
fn collect_array_dev(it : Iter[String]) -> Array[String] {
  let out : Array[String] = []
  for x in it {
    out.push(x)
  }
  out
}

///|
fn split_cmd(cmd : String) -> (String, Array[String])? {
  let xs = collect_array_dev(cmd.split(" ").map(fn(x) { x.trim().to_owned() }))
  let rest : Array[String] = []
  if xs.length() == 0 {
    return None
  }
  let mut k = 1
  while k < xs.length() {
    rest.push(xs[k])
    k += 1
  }
  Some((xs[0], rest))
}

///|
/// 收集 watch 目标：目录取其中 *.mng.html，文件原样。
fn collect_watch(p : String) -> Array[String] {
  let isdir = @fs.is_dir(p) catch {
    _ => false
  }
  if isdir {
    let out : Array[String] = []
    let entries = @fs.read_dir(p) catch {
      _ => return out
    }
    for f in entries {
      if f.has_suffix(".mng.html") {
        out.push(p + "/" + f)
      }
    }
    out
  } else {
    [p]
  }
}

///|
/// 文件名首段（到首个点为止）。
fn first_seg(name : String) -> String {
  let a = chars_of(name)
  let mut end = a.length()
  for k, c in a {
    if c == '.' {
      end = k
      break
    }
  }
  a[0:end].map(fn(c) { c.to_string() }).join("")
}

///|
fn cmd_dev(args : Array[String]) -> Int {
  let mut watch_spec = ""
  let mut out_dir = ""
  let mut build_cmd = ""
  let mut run_cmd = ""
  let mut poll_ms = 300
  let mut k = 0
  while k < args.length() {
    let a = args[k]
    if a == "--watch" && k + 1 < args.length() {
      watch_spec = args[k + 1]
      k += 2
    } else if a == "--out-dir" && k + 1 < args.length() {
      out_dir = args[k + 1]
      k += 2
    } else if a == "--build-cmd" && k + 1 < args.length() {
      build_cmd = args[k + 1]
      k += 2
    } else if a == "--run-cmd" && k + 1 < args.length() {
      run_cmd = args[k + 1]
      k += 2
    } else if a == "--poll-ms" && k + 1 < args.length() {
      match parse_int(args[k + 1]) {
        Some(n) => {
          poll_ms = n
          k += 2
        }
        None => {
          eprintln("--poll-ms 需要整数")
          return 2
        }
      }
    } else {
      eprintln("未知参数：" + a)
      usage_dev()
      return 2
    }
  }
  if watch_spec.length() == 0 || out_dir.length() == 0 || build_cmd.length() == 0 || run_cmd.length() == 0 {
    usage_dev()
    return 2
  }
  let (bfile, bargs) = match split_cmd(build_cmd) {
    Some(p) => p
    None => {
      eprintln("build-cmd 为空")
      return 2
    }
  }
  let (rfile, rargs) = match split_cmd(run_cmd) {
    Some(p) => p
    None => {
      eprintln("run-cmd 为空")
      return 2
    }
  }
  // watch 文件清单
  let files : Array[String] = []
  for spec in watch_spec.split(",") {
    let p = spec.trim().to_owned()
    if p.length() > 0 {
      for f in collect_watch(p) {
        files.push(f)
      }
    }
  }
  if files.length() == 0 {
    eprintln("watch 目标里没有 .mng.html")
    return 2
  }
  // 应用输出日志
  let app_log = out_dir + "/.mng-dev-app.log"
  // 首轮：全部编译 + 写生成码 + 记基线
  let baselines : Map[String, String] = Map([])
  let mut ok = true
  for f in files {
    let src = match slurp(f) {
      Some(s) => s
      None => {
        eprintln("读不到：" + f)
        ok = false
        continue
      }
    }
    match @mngkit.compile(src, f) {
      Err(e) => {
        eprintln(f + " 编译失败：")
        eprintln(e)
        ok = false
      }
      Ok(r) => {
        let stem = first_seg(basename(f))
        let _ = spit(out_dir + "/" + stem + ".gen.mbt", r.code)
        let _ = baselines.set(f, src)
      }
    }
  }
  if !ok {
    return 1
  }
  // build + 起应用
  match @sysx.pr_run(bfile, bargs, timeout_ms=600000) {
    Err(e) => {
      eprintln("build 失败：" + e.to_string())
      return 1
    }
    Ok(_) => ()
  }
  let mut app_pid = match @sysx.pr_spawn(rfile, rargs, out_path=app_log, err_path=app_log) {
    Ok(pid) => pid
    Err(e) => {
      eprintln("应用起不来：" + e.to_string())
      return 1
    }
  }
  eprintln(
    "DEV 起应用 pid=\{app_pid}（输出 → \{app_log}）；watch \{files.length()} 个模板，\{poll_ms}ms 一拍。Ctrl-C 退出。",
  )
  // watch 循环
  while true {
    @sysx.pr_sleep_ms(poll_ms)
    for f in files {
      let src = match slurp(f) {
        Some(s) => s
        None => continue
      }
      if src == baselines.get_or_default(f, "") {
        continue
      }
      let name = basename(f)
      let stem = first_seg(name)
      match @mngkit.compile(src, f) {
        Err(e) => {
          // 编译失败：错误已映射回模板行列，应用不动
          eprintln("[ERR] " + f + "：")
          eprintln(e)
          continue
        }
        Ok(r) => {
          let cur = match @mngkit.contract_of(src, f) {
            Ok(c) => c
            Err(e) => {
              eprintln("[ERR] " + f + "：" + e)
              continue
            }
          }
          let is_hot = match @mngkit.contract_of(baselines.get_or_default(f, ""), f) {
            Ok(base) => cur.hot_ok(base)
            Err(_) => false
          }
          let _ = spit(out_dir + "/" + stem + ".gen.mbt", r.code)
          if is_hot {
            eprintln("[HOT] \{name}：结构变更已生成（亚秒补丁通道待应用侧监听落地，本次不打断应用）")
          } else {
            eprintln("[COLD] \{name}：行为/表达式变更，重启编排…")
            match @sysx.pr_run(bfile, bargs, timeout_ms=600000) {
              Err(e) => eprintln("[COLD] build 失败，应用不动：" + e.to_string())
              Ok(_) => {
                if @sysx.pr_alive(app_pid) {
                  let _ = @sysx.pr_kill(app_pid)
                  let mut waited = 0
                  while @sysx.pr_alive(app_pid) && waited < 3000 {
                    @sysx.pr_sleep_ms(50)
                    waited += 50
                  }
                }
                match @sysx.pr_spawn(rfile, rargs, out_path=app_log, err_path=app_log) {
                  Ok(pid) => {
                    app_pid = pid
                    eprintln("[COLD] 应用已重启 pid=\{pid}")
                  }
                  Err(e) => eprintln("[COLD] 重启失败：" + e.to_string())
                }
              }
            }
          }
          let _ = baselines.set(f, src)
        }
      }
    }
  }
  0
}
