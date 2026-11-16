// `mng inspect`：一次性 CLI，连应用内 inspector 服务取数打印。
// 子命令：tree（整树 dump）/ style <id>（生效样式读数）/ shot [路径]（截帧落盘）。
// 应用要用 MNG_INSPECT=1 起过（`mng dev` 注入，或 `mng mcp --run` 拉起）。

///|
fn usage_inspect() -> Unit {
  println(tmsg(
    "inspect 用法：`mng inspect tree` / `mng inspect style <id>` / `mng inspect shot [路径]`\n  " +
    "连应用内的检查服务（应用需 MNG_INSPECT=1 起过——mng dev 自动注入）。\n  " +
    "--app <id> 显式给应用 id；缺省读工程 mng.toml / moon.mod 推导。",
    "inspect usage: `mng inspect tree` / `mng inspect style <id>` / `mng inspect shot [path]`\n  " +
    "Talks to the in-app inspector service (requires MNG_INSPECT=1 — injected by mng dev).\n  " +
    "Pass --app <id> explicitly; defaults to the project mng.toml / moon.mod.",
  ))
}

///|
fn cmd_inspect(args : Array[String]) -> Int32 {
  let mut app_override = ""
  let sub : Array[String] = []
  let mut k = 0
  while k < args.length() {
    let a = args[k]
    if a == "--app" && k + 1 < args.length() {
      app_override = args[k + 1]
      k += 2
    } else if a == "-h" || a == "--help" {
      usage_inspect()
      return 0
    } else {
      sub.push(a)
      k += 1
    }
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
    "tree" => "tree"
    "style" =>
      if sub.length() > 1 {
        "style \{sub[1]}"
      } else {
        eprintln(tmsg("style 需要 <id>", "style needs <id>"))
        return 2
      }
    "shot" => {
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
