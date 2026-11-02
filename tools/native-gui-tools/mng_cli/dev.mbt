// dev 子命令：watch 模板 → 内存编译 → hot_ir 分类 → HOT 推 IR 补丁 /
// COLD 回退编排（moon build → 杀旧 → 带参重启 → 唤醒回改动页）。
// 分类判据与边界见 proposals/native-template.md「开发循环」二轮节。

fn usage_dev() -> Unit {
  println("用法：moon run tools/native-gui-tools/mng_cli -- dev [<某个 .mng 或目录>] [--build-cmd …] [--run-cmd …] [--app-id …] [--poll-ms 300] [--out-dir <目录>]")
  println("  工程级：无参时向上找 mng.toml（没有就按 moon.mod / moon.work 推默认值），递归扫 templates 里的 *.mng")
  println("  位置参数：只盯这一个文件/目录（可选过滤）")
  println("  生成码落到模板自己所在的包目录（<stem>.gen.mbt，dev 形态）；--out-dir 仅供调试强行指定")
  println("  build-cmd / run-cmd / app-id / poll-ms：覆盖 mng.toml；run 留空 = 跑一次 build 后从 Artifacts 抓可执行")
  println("  一拍内多个改动合并成一次 build/重启；HOT 的逐个推补丁；COLD 重启后回到改动页")
  println("  dev 产物不进源码树：应用日志 / source map / IR 补丁统一落 <项目根>/.mng/（logs / map / ir）")
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
    if !cand.has_prefix("/") {
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
  // 合并拍次的 watch 循环：一拍内的改动合并成一次 build/重启，HOT 的逐个推补丁
  while true {
    @proc.sleep_ms(conf.poll_ms)
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
    if changed.length() == 0 {
      continue
    }
    let mut cold = false
    let mut had_err = false
    let patches : Array[String] = []
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
    if cold && !had_err {
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
                    wake_page(conf.app_id, stem_of_file(changed[0]))
                  }
                  Err(e) => eprintln("[COLD] 重启失败：" + e)
                }
              }
          }
        None => eprintln("[COLD] build 为空")
      }
    } else if cold && had_err {
      eprintln("[COLD] 有编译错误，本拍不重启（修好保存后自动重试）")
    }
    if !cold {
      for p in patches {
        match @inst.wake(conf.app_id, ["--mng-hot", p]) {
          Ok(_) => eprintln("[HOT] 补丁已推送（" + p + "）")
          Err(e) => eprintln("[HOT] 补丁已备 " + p + "，但唤起失败（" + e + "）——应用未运行？")
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
/// new 子命令：生成 .mng 页样板（script setup + 最小模板 + props 头与组件调用提示）。
fn cmd_new(args : Array[String]) -> Int {
  if args.length() != 1 {
    println("new 需要一个页名（生成 <名字>.mng）")
    return 2
  }
  let name = args[0]
  if !name.has_suffix(".mng") {
    return cmd_new([name + ".mng"])
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
