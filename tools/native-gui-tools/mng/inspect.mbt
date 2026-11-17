// `mng inspect`：一次性 CLI，连应用内 inspector 服务取数打印。
// 子命令：tree [--full]（组件视图 dump，--full 全量）/ style <id>（生效样式
// 读数）/ shot [路径]（截帧落盘）。
// 应用要用 MNG_INSPECT=1 起过（`mng dev` 注入，或 `mng mcp --run` 拉起）。

///|
fn usage_inspect() -> Unit {
  println(tmsg(
    "inspect 用法：`mng inspect tree [--full]` / `mng inspect style <id>` / `mng inspect shot [--full] [路径]`\n  " +
    "`mng inspect --gui` 开图形检查器（经 mngui，仿 Chrome DevTools）。\n  " +
    "tree 缺省组件视图（每个模板标签一行），--full 全量（组件内部实现件也在）。\n  " +
    "shot 缺省截视口帧，--full 整页内容重画（滚动截图语义）。\n  " +
    "连应用内的检查服务（应用需 MNG_INSPECT=1 起过——mng dev 自动注入）。\n  " +
    "--app <id> 显式给应用 id；缺省读工程 mng.toml / moon.mod 推导。",
    "inspect usage: `mng inspect tree [--full]` / `mng inspect style <id>` / `mng inspect shot [--full] [path]`\n  " +
    "`mng inspect --gui` opens the graphical inspector (via mngui, Chrome-DevTools-like).\n  " +
    "tree shows the component view by default (one row per template tag); --full lists everything.\n  " +
    "shot captures the viewport frame by default; --full repaints the whole scrolled content.\n  " +
    "Talks to the in-app inspector service (requires MNG_INSPECT=1 — injected by mng dev).\n  " +
    "Pass --app <id> explicitly; defaults to the project mng.toml / moon.mod.",
  ))
}

///|
fn cmd_inspect(argv0 : String, args : Array[String]) -> Int32 {
  let mut app_override = ""
  let mut gui = false
  let sub : Array[String] = []
  let mut k = 0
  while k < args.length() {
    let a = args[k]
    if a == "--app" && k + 1 < args.length() {
      app_override = args[k + 1]
      k += 2
    } else if a == "--gui" || a == "-g" {
      gui = true
      k += 1
    } else if a == "-h" || a == "--help" {
      usage_inspect()
      return 0
    } else {
      sub.push(a)
      k += 1
    }
  }
  // --gui：让位给 mngui 的检查器窗（mng 本体不链 GUI 库，只做参数透传）。
  // app_id 与 CLI 同一推导口径，hop 时必带（mngui 侧不再推）。
  if gui || (sub.length() == 1 && sub[0] == "gui") {
    let app = if app_override.length() > 0 {
      app_override
    } else {
      let cwd = match @env.current_dir() {
        Some(d) => d
        None => "."
      }
      match load_dev_conf("", "", "", None, cwd) {
        Ok(c) => c.app_id
        Err(e) => {
          eprintln(e)
          return 2
        }
      }
    }
    let (installed, code) = mngui_hop_args(argv0, [
      "--inspect", "--app", app,
    ])
    if !installed {
      eprintln(
        tmsg(
          "mngui 未安装——moon install ./tools/native-gui-tools/mngui",
          "mngui is not installed — moon install ./tools/native-gui-tools/mngui",
        ),
      )
      return 3
    }
    return code
  }
  if sub.length() == 0 {
    usage_inspect()
    return 2
  }
  let app_id = if app_override.length() > 0 {
    app_override
  } else {
    let cwd = match @env.current_dir() {
      Some(d) => d
      None => "."
    }
    match load_dev_conf("", "", "", None, cwd) {
      Ok(c) => c.app_id
      Err(e) => {
        eprintln(e)
        return 2
      }
    }
  }
  let req = match sub[0] {
    // `tree [--full]`：默认组件视图，--full 全量（组件内部实现件也在）
    "tree" => {
      let buf = StringBuilder()
      buf.write_string("tree")
      let mut j = 1
      while j < sub.length() {
        buf.write_string(" \{sub[j]}")
        j += 1
      }
      buf.to_string()
    }
    "style" =>
      if sub.length() > 1 {
        "style \{sub[1]}"
      } else {
        eprintln(tmsg("style 需要 <id>", "style needs <id>"))
        return 2
      }
    "shot" => {
      // `shot [--full] [路径]` 原样透传服务端（--full 走整页内容重画档）
      let buf = StringBuilder()
      buf.write_string("shot")
      let mut j = 1
      while j < sub.length() {
        buf.write_string(" \{sub[j]}")
        j += 1
      }
      buf.to_string()
    }
    _ => {
      eprintln(tmsg("未知子命令：" + sub[0], "Unknown subcommand: " + sub[0]))
      usage_inspect()
      return 2
    }
  }
  match @insp.call(app_id, req) {
    Ok(resp) => {
      println(resp)
      // shot 回执给真实路径，退出码 0；error 行按失败退出
      if resp.has_prefix("error:") {
        1
      } else {
        0
      }
    }
    Err(e) => {
      eprintln(tmsg(e, e))
      return 1
    }
  }
}
