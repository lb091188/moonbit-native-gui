// dev 子命令：watch 模板 → 内存编译 → hot_ir 分类 → HOT 推 IR 补丁 /
// COLD 回退编排（moon build → 杀旧 → 带参重启 → 唤醒回改动页）。
// 分类判据与边界见 proposals/native-template.md「开发循环」二轮节。

fn usage_dev() -> Unit {
  println("用法：moon run tools/native-gui-tools/mng -- dev [<某个 .mng 或目录>] [--build-cmd …] [--run-cmd …] [--app-id …] [--poll-ms 300] [--out-dir <目录>]")
  println("  工程级：无参时向上找 mng.toml（没有就按 moon.mod / moon.work 推默认值），递归扫 templates 里的 *.mng")
  println("  位置参数：只盯这一个文件/目录（可选过滤）")
  println("  生成码落到模板自己所在的包目录（<stem>.gen.mbt，dev 形态）；--out-dir 仅供调试强行指定")
  println("  build-cmd / run-cmd / app-id / poll-ms：覆盖 mng.toml；run 留空 = 跑一次 build 后从 Artifacts 抓可执行")
  println("  一拍内多个改动合并成一次 build/重启；HOT 的逐个推补丁；COLD 重启后回到改动页")
  println("  dev 产物不进源码树：应用日志 / source map / IR 补丁统一落 <项目根>/.mng/（logs / map / ir）")
  println("  mng.toml 配 theme = \"theme.json\" 即接 reload-theme 通道：主题文件一存即推 --mng-theme 重载")
}

///|
/// 逐级建目录（已存在视为成功）。
fn mkdir_p(dir : String) -> Bool {
  let parts = collect_array_dev(dir.split("/").filter(fn(x) { x.length() > 0 }).map(fn(x) { x.to_owned() }))
  let mut cur = if dir.has_prefix("/") { "/" } else { "" }
  for p in parts {
    if cur == "/" {
      cur = "/" + p
    } else if cur.length() == 0 {
      cur = p
    } else {
      cur = cur + "/" + p
    }
    let isdir = @fs.is_dir(cur) catch {
      _ => false
    }
    if !isdir {
      @fs.create_dir(cur) catch {
        _ => return false
      }
    }
  }
  true
}

///|
/// 路径 → 相对项目根的包路径（不在根下则退回其目录名）。
fn rel_under(root : String, p : String) -> String {
  if p.has_prefix(root + "/") {
    p[root.length() + 1:].to_owned()
  } else {
    basename(p)
  }
}

///|
/// app-id → 日志文件名安全段（非法字符转下划线）。
fn safe_filename(s : String) -> String {
  let out = StringBuilder()
  for c in s {
    if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '.' || c == '-' || c == '_' {
      out.write_char(c)
    } else {
      out.write_char('_')
    }
  }
  out.to_string()
}

///|
/// dev 的 source map 落点：`.mng/map/<模板相对包路径>/<stem>.gen.mbt.map`。
fn dev_map_path(mng_root : String, conf_dir : String, f : String) -> String {
  let rel = rel_under(conf_dir, parent_dir_of(f))
  mng_root + "/map/" + rel + "/" + stem_of_file(f) + ".gen.mbt.map"
}

///|
/// 写 dev source map（父目录不存在先建；失败只提示，不影响编译主流程）。
fn write_dev_map(mappath : String, map : String, gen_name : String) -> Bool {
  if !mkdir_p(parent_dir_of(mappath)) {
    return false
  }
  spit(mappath, map + "gen " + gen_name + "\n")
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
/// 生成码落点：默认与模板同包；`--out-dir` 给了就强行指过去（调试用）。
fn gen_path(out_dir : String, f : String) -> String {
  let stem = stem_of_file(f)
  if out_dir.length() > 0 {
    out_dir + "/" + stem + ".gen.mbt"
  } else {
    parent_dir_of(f) + "/" + stem + ".gen.mbt"
  }
}

///|
/// 可选过滤：文件原样、目录递归扫。
fn filter_files(spec : String) -> Array[String] {
  let isdir = @fs.is_dir(spec) catch {
    _ => false
  }
  if isdir {
    scan_templates([spec])
  } else {
    [spec]
  }
}

///|
/// 跑一次 build 并从输出里抓可执行路径（`Artifacts:` 段里属于本模块的那一行）。
/// 只在 `run` 未配置时用；build 本身走 `sh -c` 以拿到输出。
fn derive_run(build_cmd : String, module_name : String) -> Result[String, String] {
  let tmp = match @env.get_env_var("TMPDIR") {
    Some(d) if d != "" => d
    _ => "/tmp"
  }
  let log = tmp + "/mng-dev-build.log"
  let cmd = build_cmd + " > " + log + " 2>&1"
  match @proc.run_wait("sh", ["-c", cmd], 600000) {
    Err(e) => return Err("build 跑不起来（" + e + "）——Windows 请显式配置 run")
    Ok(code) =>
      if code != 0 {
        // 构建失败：把日志尾巴打出来
        match slurp(log) {
          Some(t) => eprintln(t)
          None => ()
        }
        return Err("build 失败（退出码 " + code.to_string() + "）")
      }
  }
  let text = match slurp(log) {
    Some(t) => t
    None => return Err("读不到 build 日志 " + log)
  }
  match artifact_of_log(text, module_name) {
    Some(p) => Ok(p)
    None => Err("build 输出里没抓到本模块的可执行路径——在 mng.toml 补 run")
  }
}

///|
/// 绝对路径判据：POSIX 以 `/` 起头，Windows 认 `C:\…` / `C:/…` 与 UNC `\\…`
/// （moon 的 Artifacts 行在 Windows 上给盘符路径，只认 `/` 会把整段抓空）。
fn is_abs_path(p : String) -> Bool {
  let cs = p.to_array()
  let n = cs.length()
  if n == 0 {
    return false
  }
  if cs[0] == '/' {
    return true
  }
  let is_letter = (cs[0] >= 'a' && cs[0] <= 'z') || (cs[0] >= 'A' && cs[0] <= 'Z')
  if n >= 3 && is_letter && cs[1] == ':' && (cs[2] == '\\' || cs[2] == '/') {
    return true
  }
  n >= 2 && cs[0] == '\\' && cs[1] == '\\'
}

///|
/// `moon build` 的 `Artifacts:` 段 → **属于本模块**的可执行绝对路径。
/// 行形如 `  <包路径>  native  /abs/path`：包路径等于模块名（模块根包）优先，
/// 其次取模块下的子包（如 `cmd/main`）；别家模块的行一律不认（裸 `moon build`
/// 会构建整个 workspace，取「最后一条」会抓错应用）。
fn artifact_of_log(text : String, module_name : String) -> String? {
  if module_name.length() == 0 {
    return None
  }
  let mut artifacts = false
  let mut exact = ""
  let mut prefix = ""
  for raw in text.split("\n") {
    let line = raw.to_owned()
    let t = line.trim_end().to_owned()
    if t.trim().to_owned() == "Artifacts:" {
      artifacts = true
      continue
    }
    if !artifacts {
      continue
    }
    if t.length() == 0 || !line.has_prefix("  ") {
      artifacts = false
      continue
    }
    let xs = collect_array_dev(t.split(" ").filter(fn(x) { x.length() > 0 }).map(fn(x) { x.to_owned() }))
    if xs.length() < 2 {
      continue
    }
    let pkg = xs[0]
    let cand = xs[xs.length() - 1]
    if !is_abs_path(cand) {
      continue
    }
    let exists = @fs.is_file(cand) catch {
      _ => false
    }
    if !exists {
      continue
    }
    if pkg == module_name {
      exact = cand
      break
    }
    if prefix.length() == 0 && pkg.has_prefix(module_name + "/") {
      prefix = cand
    }
  }
  if exact.length() > 0 {
    Some(exact)
  } else if prefix.length() > 0 {
    Some(prefix)
  } else {
    None
  }
}

///|
/// dev 主流程：工程级扫描 → 首轮 dev 编译 → build/起应用 → 合并拍次的 watch 循环。
fn cmd_dev(args : Array[String]) -> Int {
  let mut filter = ""
  let mut out_dir = ""
  let mut build_cmd = ""
  let mut run_cmd = ""
  let mut app_id = ""
  let mut poll_override : Int? = None
  let mut k = 0
  while k < args.length() {
    let a = args[k]
    if (a == "--watch" || a == "-w") && k + 1 < args.length() {
      filter = args[k + 1]
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
    } else if a == "--app-id" && k + 1 < args.length() {
      app_id = args[k + 1]
      k += 2
    } else if a == "--poll-ms" && k + 1 < args.length() {
      match parse_int(args[k + 1]) {
        Some(n) => {
          poll_override = Some(n)
          k += 2
        }
        None => {
          eprintln("--poll-ms 需要整数")
          return 2
        }
      }
    } else if a.has_prefix("--") {
      eprintln("未知参数：" + a)
      usage_dev()
      return 2
    } else {
      filter = a
      k += 1
    }
  }
  let cwd = match @env.current_dir() {
    Some(d) => d
    None => "."
  }
  let conf = match load_dev_conf(build_cmd, run_cmd, app_id, poll_override, cwd) {
    Ok(c) => c
    Err(e) => {
      eprintln(e)
      return 2
    }
  }
  let files = if filter.length() > 0 {
    filter_files(filter)
  } else {
    scan_templates(conf.templates)
  }
  if files.length() == 0 {
    eprintln("没扫到 .mng（templates = " + conf.templates.join(", ") + "）")
    return 2
  }
  match collision_msg(files) {
    Some(m) => {
      eprintln(m)
      return 2
    }
    None => ()
  }
  let mng_root = conf.dir + "/.mng"
  let app_log = mng_root + "/logs/" + safe_filename(conf.app_id) + ".log"
  if !mkdir_p(mng_root + "/logs") {
    eprintln("建不出目录：" + mng_root + "/logs")
    return 1
  }
  // 首轮：全部 dev 编译 + 生成码落各自包目录 + 记基线
  // baselines = 最后一次编译成功的原文（hot_ir 分类用）；seen = 最后一次尝试过的原文
  // （编译失败也记，避免同一个错误每拍重复刷屏）
  let baselines : Map[String, String] = Map([])
  let seen : Map[String, String] = Map([])
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
    match mng_compile_dev(src, f) {
      Err(e) => {
        eprintln(f + " 编译失败：")
        eprintln(e)
        ok = false
      }
      Ok(r) => {
        let gp = gen_path(out_dir, f)
        if !spit(gp, r.code) {
          eprintln("写不出生成码：" + gp)
          ok = false
        } else {
          let mappath = dev_map_path(mng_root, conf.dir, f)
          if !write_dev_map(mappath, r.map, basename(gp)) {
            eprintln("写不出 source map：" + mappath)
          }
          let _ = baselines.set(f, src)
          let _ = seen.set(f, src)
        }
      }
    }
  }
  if !ok {
    return 1
  }
  // build（run 留空时顺带从 Artifacts 推导启动命令）
  let mut run_expr = conf.run
  if run_expr.length() == 0 {
    match derive_run(conf.build, module_name_at(conf.dir)) {
      Ok(cmd) => {
        run_expr = cmd
        eprintln("DEV 从 Artifacts 抓到可执行：" + cmd)
      }
      Err(e) => {
        eprintln(e)
        return 1
      }
    }
  } else {
    match split_cmd(conf.build) {
      Some((bfile, bargs)) =>
        match @proc.run_wait(bfile, bargs, 600000) {
          Err(e) => {
            eprintln("build 失败：" + e)
            return 1
          }
          Ok(code) =>
            if code != 0 {
              eprintln("build 退出码 " + code.to_string())
              return 1
            }
        }
      None => {
        eprintln("build 为空")
        return 1
      }
    }
  }
  let (rfile, rargs) = match split_cmd(run_expr) {
    Some(p) => p
    None => {
      eprintln("run 为空")
      return 1
    }
  }
  let mut app_pid = match @proc.spawn(rfile, rargs, app_log) {
    Ok(pid) => pid
    Err(e) => {
      eprintln("应用起不来：" + e)
      return 1
    }
  }
  eprintln(
    "DEV 起应用 pid=\{app_pid}（输出 → \{app_log}）；工程级 watch \{files.length()} 个模板，\{conf.poll_ms}ms 一拍。Ctrl-C 退出。",
  )
  // 合并拍次的 watch 循环：一拍内的改动合并成一次 build/重启，HOT 的逐个推补丁。
  // watch 面 = 模板（内容 + 新增/删除）+ 工程源文件（.mbt/moon.pkg/moon.mod/…）
  // + 主题文件；生成码 *.gen.mbt 不监听（dev 自己每拍写它，监听会自激）。
  let mut files = files
  let src_seen : Map[String, String] = Map([])
  for p in scan_source_files(conf.dir) {
    match slurp(p) {
      Some(t) => {
        let _ = src_seen.set(p, t)
      }
      None => ()
    }
  }
  let mut theme_seen = match conf.theme {
    t if t.length() > 0 => slurp(t)
    _ => None
  }
  while true {
    @proc.sleep_ms(conf.poll_ms)
    // 主题文件变更（reload-theme 通道）：内容变了就推送重载——应用侧
    // from_json + theme_apply，不走模板编译/重启
    match conf.theme {
      t if t.length() > 0 => {
        let cur = slurp(t)
        if cur != theme_seen {
          theme_seen = cur
          match cur {
            Some(_) =>
              match @inst.wake(conf.app_id, ["--mng-theme", t]) {
                Ok(_) => eprintln("[THEME] 主题重载已推送（" + t + "）")
                Err(e) => eprintln("[THEME] 主题推送失败（" + e + "）——应用未运行？")
              }
            None => ()
          }
        }
      }
      _ => ()
    }
    let changed : Array[String] = []
    for f in files {
      match slurp(f) {
        Some(src) =>
          if src != seen.get_or_default(f, "") {
            changed.push(f)
          }
        None => ()
      }
    }
    let mut cold = false
    let mut had_err = false
    let patches : Array[String] = []
    // —— 模板新增/删除：重扫 → 差分（新增并入本拍构建，删除清登记与生成码）——
    let rescanned = if filter.length() > 0 {
      filter_files(filter)
    } else {
      scan_templates(conf.templates)
    }
    let added_removed = diff_file_sets(files, rescanned)
    for f in added_removed.0 {
      match slurp(f) {
        Some(src) =>
          match mng_compile_dev(src, f) {
            Ok(r) => {
              let gp = gen_path(out_dir, f)
              if spit(gp, r.code) {
                let mappath = dev_map_path(mng_root, conf.dir, f)
                let _ = write_dev_map(mappath, r.map, basename(gp))
                let _ = baselines.set(f, src)
                let _ = seen.set(f, src)
                eprintln("[NEW] " + f + " 已生成（并入本拍构建）")
              } else {
                eprintln("[ERR] 写不出生成码：" + gp)
                had_err = true
              }
            }
            Err(e) => {
              eprintln("[ERR] " + f + "：")
              eprintln(e)
              let _ = seen.set(f, src)
              had_err = true
            }
          }
        None => ()
      }
    }
    for f in added_removed.1 {
      let _ = baselines.remove(f)
      let _ = seen.remove(f)
      let gp = gen_path(out_dir, f)
      let old_gen = read_or_empty(gp)
      if old_gen.has_prefix("// GENERATED by mngc") {
        let _ = @fs.remove_file(gp) catch { _ => () }
        eprintln("[GONE] " + f + "，已清生成码 " + gp)
      } else if old_gen.length() > 0 {
        eprintln("[GONE] " + f + "；生成码 " + gp + " 非生成头，未自动删")
      }
    }
    files = rescanned
    if added_removed.0.length() > 0 {
      cold = true
    }
    // —— 工程源文件变更（.mbt/moon.pkg/moon.mod/…）：并入本拍 COLD ——
    let srcs = scan_source_files(conf.dir)
    let src_gone : Array[String] = []
    for p in srcs {
      match slurp(p) {
        Some(t) =>
          if src_seen.get_or_default(p, "") != t {
            if src_seen.contains(p) {
              eprintln("[SRC] " + p + " 变更，并入本拍构建")
              cold = true
            }
            let _ = src_seen.set(p, t)
          }
        None => ()
      }
    }
    for (p, _) in src_seen {
      if !arr_has_cli(srcs, p) {
        src_gone.push(p)
      }
    }
    for p in src_gone {
      let _ = src_seen.remove(p)
      eprintln("[SRC] " + p + " 已删除，并入本拍构建")
      cold = true
    }
    if changed.length() == 0 && !cold {
      continue
    }
    for f in changed {
      let src = match slurp(f) {
        Some(s) => s
        None => continue
      }
      match mng_compile_dev(src, f) {
        Err(e) => {
          eprintln("[ERR] " + f + "：")
          eprintln(e)
          let _ = seen.set(f, src)
          had_err = true
          continue
        }
        Ok(r) => {
          let gp = gen_path(out_dir, f)
          if !spit(gp, r.code) {
            eprintln("[ERR] 写不出生成码：" + gp)
            let _ = seen.set(f, src)
            had_err = true
            continue
          }
          let mappath = dev_map_path(mng_root, conf.dir, f)
          if !write_dev_map(mappath, r.map, basename(gp)) {
            eprintln("[ERR] 写不出 source map：" + mappath)
          }
          match @mngkit.hot_ir(src, baselines.get_or_default(f, ""), f) {
            Err(reason) => {
              eprintln("[HOT→COLD] " + f + "：" + reason)
              cold = true
            }
            Ok(irjson) => {
              let irpath = mng_root + "/ir/" + rel_under(conf.dir, parent_dir_of(f)) + "/" + stem_of_file(f) + ".ir.json"
              if !mkdir_p(parent_dir_of(irpath)) || !spit(irpath, irjson) {
                eprintln("[HOT] 写不出 " + irpath)
                cold = true
              } else {
                patches.push(irpath)
              }
            }
          }
          let _ = baselines.set(f, src)
          let _ = seen.set(f, src)
        }
      }
    }
    // COLD 编排抽成一拍内可复用：本拍分类要重启、或 HOT 回执判 stale 后补重启
    let do_cold = fn() -> Unit {
      eprintln("[COLD] 本拍 \{changed.length()} 个改动，合并 build 一次…")
      match split_cmd(conf.build) {
        Some((bfile, bargs)) =>
          match @proc.run_wait(bfile, bargs, 600000) {
            Err(e) => eprintln("[COLD] build 失败，应用不动：" + e)
            Ok(code) =>
              if code != 0 {
                eprintln("[COLD] build 退出码 " + code.to_string() + "，应用不动")
              } else {
                if @proc.alive(app_pid) {
                  let _ = @proc.kill(app_pid)
                  let mut waited = 0
                  while @proc.alive(app_pid) && waited < 3000 {
                    @proc.sleep_ms(50)
                    waited += 50
                  }
                }
                match @proc.spawn(rfile, rargs, app_log) {
                  Ok(pid) => {
                    app_pid = pid
                    eprintln("[COLD] 应用已重启 pid=" + pid.to_string())
                    if changed.length() > 0 {
                      wake_page(conf.app_id, stem_of_file(changed[0]))
                    }
                  }
                  Err(e) => eprintln("[COLD] 重启失败：" + e)
                }
              }
          }
        None => eprintln("[COLD] build 为空")
      }
    }
    if cold && !had_err {
      do_cold()
    } else if cold && had_err {
      eprintln("[COLD] 有编译错误，本拍不重启（修好保存后自动重试）")
    }
    if !cold {
      let mut stale = false
      for p in patches {
        if push_hot(conf.app_id, p) {
          stale = true
        }
      }
      if stale {
        // 应用侧握手不符（注册表键集落后）：不留在旧树，补一次重启回改动页
        if had_err {
          eprintln("[COLD] 握手不符但有编译错误，本拍不重启")
        } else {
          eprintln("[COLD] 握手不符，补一次重启")
          do_cold()
        }
      }
    } else if patches.length() > 0 {
      // COLD 重启后应用已按新生成码起，补丁不再需要
      eprintln("[HOT] 本拍有 COLD 改动，\{patches.length()} 个热补丁并入重启")
    }
  }
  0
}

///|
/// 读回执文件，读不到当空串（应用侧握手后写 `<补丁>.ack`）。
fn read_or_empty(path : String) -> String {
  let s = @fs.read_file_to_string(path) catch {
    _ => return ""
  }
  s
}

///|
/// 推一条 HOT 补丁并等握手回执：`ok`=已应用；`stale`=协议/键集对不上，返回 true
/// 让本拍转 COLD；`err`=应用侧建树失败（如实报，不重启）；等不到回执只报「已推送」，
/// 不虚报已应用。
fn push_hot(app_id : String, p : String) -> Bool {
  let ack = p + ".ack"
  let _ = @fs.remove_file(ack) catch {
    _ => ()
  }
  match @inst.wake(app_id, ["--mng-hot", p]) {
    Err(e) => {
      eprintln("[HOT] 补丁已备 " + p + "，但唤起失败（" + e + "）——应用未运行？")
      false
    }
    Ok(_) => {
      let mut tries = 0
      while tries < 40 {
        let line = read_or_empty(ack)
        if line.length() > 0 {
          if line.has_prefix("stale") {
            eprintln("[HOT→COLD] 握手不符：" + line[6:].to_owned())
            return true
          } else if line.has_prefix("ok") {
            eprintln("[HOT] 补丁已应用（" + p + "）")
            return false
          } else {
            eprintln("[HOT] 补丁应用失败：" + line[4:].to_owned())
            return false
          }
        }
        @proc.sleep_ms(50)
        tries += 1
      }
      eprintln("[HOT] 补丁已推送（" + p + "），未收到应用回执")
      false
    }
  }
}

///|
/// COLD 重启后把新进程带回改动所在的模板页（新应用可能还没开始监听，重试）。
fn wake_page(app_id : String, page : String) -> Unit {
  let args = ["--mng-page", page]
  let mut tries = 0
  while tries < 40 {
    match @inst.wake(app_id, args) {
      Ok(_) => {
        eprintln("[COLD] 已请求回到模板页 " + page)
        return
      }
      Err(_) => {
        @proc.sleep_ms(100)
        tries += 1
      }
    }
  }
  eprintln("[COLD] 回页请求未送达（应用未就绪或单实例通道不可用）")
}

///|
/// 项目级生产构建：按 mng.toml（或默认推导）扫全工程 .mng，逐个产生产形态
/// 生成码写回模板同包 `<stem>.gen.mbt`，source map 落 `.mng/map/`。
/// 与 dev 形态共用同一条生成码路径，会互相覆盖——提交前选一种并保持一致。
fn build_project_at(root : String) -> Int {
  let conf = match load_dev_conf("", "", "", None, root) {
    Ok(c) => c
    Err(e) => {
      eprintln(e)
      return 2
    }
  }
  let files = scan_templates(conf.templates)
  if files.length() == 0 {
    eprintln("没扫到 .mng（templates = " + conf.templates.join(", ") + "）")
    return 2
  }
  match collision_msg(files) {
    Some(m) => {
      eprintln(m)
      return 2
    }
    None => ()
  }
  let mng_root = conf.dir + "/.mng"
  if !mkdir_p(mng_root + "/map") {
    eprintln("建不出目录：" + mng_root + "/map")
    return 1
  }
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
    match mng_compile(src, f) {
      Err(e) => {
        eprintln(f + " 编译失败：")
        eprintln(e)
        ok = false
      }
      Ok(r) => {
        let gp = gen_path("", f)
        if !spit(gp, r.code) {
          eprintln("写不出生成码：" + gp)
          ok = false
          continue
        }
        let mappath = dev_map_path(mng_root, conf.dir, f)
        if !write_dev_map(mappath, r.map, basename(gp)) {
          eprintln("写不出 source map：" + mappath)
        }
        println("OK " + gp)
      }
    }
  }
  if !ok {
    return 1
  }
  println("BUILD " + files.length().to_string() + " 个模板 → 生产形态生成码")
  0
}

///|
fn cmd_build_project() -> Int {
  let cwd = match @env.current_dir() {
    Some(d) => d
    None => "."
  }
  build_project_at(cwd)
}

///|
/// init 子命令：在模块根写 mng.toml 样板（已有则不动）。
fn cmd_init(_args : Array[String]) -> Int {
  let cwd = match @env.current_dir() {
    Some(d) => d
    None => "."
  }
  let (root, _kind) = match find_project_root(cwd) {
    Some(x) => x
    None => {
      println("找不到 moon.mod / moon.work——在模块里跑")
      return 1
    }
  }
  let path = root + "/mng.toml"
  match fs_read(path) {
    Some(_) => {
      println("已存在：" + path + "（未覆盖）")
      return 0
    }
    None => ()
  }
  if !spit(path, mng_toml_template()) {
    println("写不出：" + path)
    return 1
  }
  println("OK " + path)
  0
}

///|
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
/// ir 子命令：打印模板的 IR 补丁（调试 + 应用侧注册表键校准）。
fn cmd_ir(args : Array[String]) -> Int {
  if args.length() != 1 {
    println("ir 需要一个 .mng 路径")
    return 2
  }
  let src = match slurp(args[0]) {
    Some(s) => s
    None => {
      println("读不到文件：" + args[0])
      return 1
    }
  }
  match @mngkit.ir_of(src, args[0]) {
    Ok(j) => {
      println(j)
      0
    }
    Err(e) => {
      println(args[0] + " IR 产出失败：")
      println(e)
      1
    }
  }
}

///|
/// new 子命令：`new <工程名>` / `new app <工程名>` 生成可跑工程脚手架；
/// `new page <路径>` 生成单页 .mng 样板（可带包内路径，如 pages/about）。
fn cmd_new(args : Array[String]) -> Int {
  if args.length() == 1 {
    return scaffold_new_app(args[0])
  }
  if args.length() == 2 {
    if args[0] == "app" {
      return scaffold_new_app(args[1])
    }
    if args[0] == "page" {
      return new_page(args[1])
    }
    if args[0] == "--app" {
      println("new 的 --app 已改版：`mng new <工程名>` 即建工程（或显式 `mng new app <工程名>`）")
      return 2
    }
  }
  println("new 用法：`mng new <工程名>` 建工程；`mng new page <页路径>` 出单页样板")
  2
}

///|
/// 工程脚手架入口：在当前目录下建 `<名字>/` 工程。
fn scaffold_new_app(raw_name : String) -> Int {
  let cwd = match @env.current_dir() {
    Some(d) => d
    None => "."
  }
  scaffold_app_at(cwd, raw_name)
}

///|
/// 单页样板：写 `<路径>.mng`（script setup + 最小模板 + props 头与组件调用提示）。
/// 路径带目录时父目录不存在则现建（如 pages/about.mng 的 pages/）。
fn new_page(raw : String) -> Int {
  let name = if raw.has_suffix(".mng") {
    raw
  } else {
    raw + ".mng"
  }
  // 父目录补齐：取最后一个 / 之前的部分，非空且不存在时 mkdir_p
  let chars = chars_of(name)
  let mut last = -1
  for i, c in chars {
    if c == '/' {
      last = i
    }
  }
  if last > 0 {
    let dir = slice_path(chars, 0, last)
    if !@fs.path_exists(dir) && !mkdir_p(dir) {
      println("建不出目录：" + dir)
      return 1
    }
  }
  let stem = basename(name)
  let stem = if stem.has_suffix(".mng") {
    stem[:stem.length() - 4].to_owned()
  } else {
    stem
  }
  let snake = snake_of(stem)
  let tpl = [
    "<script setup lang=\"moonbit\">",
    "// props（可选）：script 段第一行只写签名、不写函数体的 fn 头就是本组件的参数表；",
    "// 必填走位置参数，可选走 `名? : 类型 = 默认值`。不写即零参组件。",
    "// fn " + snake + "(title : String, qty : @base.Store[Int], on_reset : () -> Unit, wide? : Bool = false) -> @widget.Node",
    "",
    "// 页状态：Store/Signal 声明在此；被模板引用的 let 绑定即响应槽。",
    "let qty : @base.Store[Int] = @base.Store::new(0)",
    "",
    "// 组件调用零声明：ui-* 走内置表；同包 `fn 组件名` 直接当标签用；",
    "// 跨包写 `let 组件名 = @包.函数`，路径取自右值、参数顺序取自源码签名。",
    "// 只有不规则落点（子元素不是 Array[@widget.Node] 之类）才需要一行覆盖：",
    "// @mng sh-page = @shared.page positional(children)",
    "</script>",
    "",
    "<template>",
    "  <ui-col row_gap=\"8.0\">",
    "    <ui-stepper v-model=\"qty\" max=\"10\" />",
    "    当前数量：{{ qty }}",
    "  </ui-col>",
    "</template>",
    "",
  ].join("\n")
  if !spit(name, tpl) {
    println("写不出文件：" + name)
    return 1
  }
  println("OK " + name + "（生成函数名 " + snake + "；把生成码接进包内即可编译）")
  0
}

///|
/// 工程源文件扫描（watch 面）：递归 `*.mbt`（排除 `*.gen.mbt`）、`moon.pkg`、
/// `moon.pkg.json`、`moon.mod`、`moon.work`；跳过 `_build` / `.mooncakes` /
/// `.mng` / `target` / `.git` / `node_modules` 与点目录。
fn scan_source_files(root : String) -> Array[String] {
  let out : Array[String] = []
  scan_source_dir(root, out)
  out.sort()
  out
}

///|
fn scan_source_dir(dir : String, out : Array[String]) -> Unit {
  let entries = fs_ls(dir)
  entries.sort()
  for name in entries {
    if name == "_build" || name == ".mooncakes" || name == "node_modules" || name == "target" || name == ".git" {
      continue
    }
    // 点目录先跳过（含 dev 产物目录 `.mng/`）
    if name.has_prefix(".") {
      continue
    }
    let p = dir + "/" + name
    let isdir = @fs.is_dir(p) catch {
      _ => false
    }
    if isdir {
      scan_source_dir(p, out)
      continue
    }
    if (name.has_suffix(".mbt") && !name.has_suffix(".gen.mbt")) || name == "moon.pkg" || name == "moon.pkg.json" || name == "moon.mod" || name == "moon.work" {
      if !arr_has_cli(out, p) {
        out.push(p)
      }
    }
  }
}

///|
/// 文件清单差分（均按原样集合）：返回 (新增, 删除)，各自按输入序。
fn diff_file_sets(
  old : Array[String],
  new : Array[String],
) -> (Array[String], Array[String]) {
  let added : Array[String] = []
  let removed : Array[String] = []
  for x in new {
    if !arr_has_cli(old, x) {
      added.push(x)
    }
  }
  for x in old {
    if !arr_has_cli(new, x) {
      removed.push(x)
    }
  }
  (added, removed)
}
