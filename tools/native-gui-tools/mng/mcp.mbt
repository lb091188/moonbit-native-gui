// `mng mcp`：stdio 传输的 MCP server，把应用内 inspector 的三个能力包装成
// tools：inspector_tree / inspector_style / inspector_shot。
// 协议要点（MCP stdio）：换行分隔的 JSON-RPC、UTF-8、消息内不得有嵌入换行
// （响应串一律经 jq 转义）、stdout 只出合法 MCP 消息、日志走 stderr。
// 纯 MoonBit 手写 initialize / tools/list / tools/call 三方法（JSON 复用
// lsp_json 的解析与拼装），不引第三方包。
// 连接形态：`--run <命令>` 拉起应用并注入 MNG_INSPECT=1；或不带 --run 直连
// 已起应用（不拉起）。app_id 同 inspect：--app 显式给，缺省按工程推导。

///|
const MCP_PROTOCOL_VERSION : String = "2024-11-05"

///|
const MCP_SERVER_NAME : String = "mng-inspector"

///|
fn mcp_log(line : String) -> Unit {
  eprintln("[mcp] " + line)
}

///|
/// 写一条响应到 stdout（换行结尾；串已转义，报文内无裸换行）。
fn mcp_send(payload : String) -> Unit {
  let data = @utf8.encode(payload + "\n")
  let _ = @proc.write_stdout(data, data.length())
}

///|
/// 三个 tool 的清单（name / description / inputSchema）。
fn mcp_tools_list_json() -> String {
  let tree_schema = "{\"type\":\"object\",\"properties\":{},\"required\":[]}"
  let style_schema =
    "{\"type\":\"object\",\"properties\":{\"id\":{\"type\":\"integer\",\"description\":\"控件 id（inspector_tree 的 id 列）\"}},\"required\":[\"id\"]}"
  let shot_schema =
    "{\"type\":\"object\",\"properties\":{\"path\":{\"type\":\"string\",\"description\":\"PNG 落盘路径；缺省写系统临时目录\"},\"full\":{\"type\":\"boolean\",\"description\":\"true = 整页内容重画（滚动截图语义，含视口外内容）；缺省 false 截视口帧\"}},\"required\":[]}"
  let sb = StringBuilder()
  sb.write_string("{\"tools\":[")
  sb.write_string(
    "{\"name\":\"inspector_tree\",\"description\":\"读取当前应用的控件树：一行一个控件，列序 kind/role/name/id/parent/x/y/w/h/state/value/text/enabled，首行是列头\",\"inputSchema\":\{tree_schema}}",
  )
  sb.write_string(",")
  sb.write_string(
    "{\"name\":\"inspector_style\",\"description\":\"按控件 id 读生效样式五字段（background/color/border_color/border_width/border_radius）\",\"inputSchema\":\{style_schema}}",
  )
  sb.write_string(",")
  sb.write_string(
    "{\"name\":\"inspector_shot\",\"description\":\"把应用截图成 PNG 落盘，回执带实际路径（二进制不进对话）；缺省视口帧，full=true 整页内容重画\",\"inputSchema\":\{shot_schema}}",
  )
  sb.write_string("]}")
  sb.to_string()
}

///|
/// tools/call 分发：按工具名拼服务端命令、连检查通道、包成 MCP content。
fn mcp_tools_call(app_id : String, params : LJson) -> Result[String, String] {
  let name = match jpath(params, "name") {
    Some(v) =>
      match json_str(v) {
        Some(s) => s
        None => return Err("tools/call 缺工具名")
      }
    None => return Err("tools/call 缺工具名")
  }
  let args = match jpath(params, "arguments") {
    Some(a) => a
    None => LObj(Map([]))
  }
  let req = if name == "inspector_tree" {
    "tree"
  } else if name == "inspector_style" {
    let id = match jpath(args, "id") {
      Some(v) => json_num(v)
      None => None
    }
    match id {
      Some(n) => "style \{n}"
      None => return Err("inspector_style 需要整数参数 id")
    }
  } else if name == "inspector_shot" {
    let full = match jpath(args, "full") {
      Some(LBool(true)) => true
      _ => false
    }
    let flag = if full { " --full" } else { "" }
    match jpath(args, "path") {
      Some(v) =>
        match json_str(v) {
          Some(p) => "shot\{flag} \{p}"
          None => "shot\{flag}"
        }
      None => "shot\{flag}"
    }
  } else {
    return Err("未知工具 \{name}")
  }
  match @insp.call(app_id, req) {
    Ok(resp) => Ok(resp)
    Err(e) => Err(e)
  }
}

///|
/// 处理一条 JSON-RPC 请求，回响应串（通知给 None）。
fn mcp_handle(app_id : String, line : String) -> String? {
  let msg = match json_parse(line) {
    Ok(m) => m
    Err(e) => {
      mcp_log("JSON 解析失败：" + e)
      return Some(
        "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32700,\"message\":\"parse error\"}}",
      )
    }
  }
  let m = match jget(msg, "method") {
    Some(v) =>
      match json_str(v) {
        Some(s) => s
        None => return None
      }
    None => return None
  }
  let id = match jget(msg, "id") {
    Some(v) =>
      match v {
        LNum(_) =>
          match json_num(v) {
            Some(n) => n.to_string()
            None => "null"
          }
        LStr(s) => jq(s)
        _ => "null"
      }
    None => return None
  }
  let params = match jget(msg, "params") {
    Some(p) => p
    None => LObj(Map([]))
  }
  if m == "initialize" {
    Some(
      "{\"jsonrpc\":\"2.0\",\"id\":\{id},\"result\":{\"protocolVersion\":\{jq(MCP_PROTOCOL_VERSION)},\"capabilities\":{\"tools\":{}},\"serverInfo\":{\"name\":\{jq(MCP_SERVER_NAME)},\"version\":\{jq(MNG_VERSION)}}}}",
    )
  } else if m == "tools/list" {
    Some("{\"jsonrpc\":\"2.0\",\"id\":\{id},\"result\":\{mcp_tools_list_json()}}")
  } else if m == "tools/call" {
    match mcp_tools_call(app_id, params) {
      Ok(text) =>
        Some(
          "{\"jsonrpc\":\"2.0\",\"id\":\{id},\"result\":{\"content\":[{\"type\":\"text\",\"text\":\{jq(text)}}],\"isError\":false}}",
        )
      Err(e) =>
        Some(
          "{\"jsonrpc\":\"2.0\",\"id\":\{id},\"result\":{\"content\":[{\"type\":\"text\",\"text\":\{jq(e)}}],\"isError\":true}}",
        )
    }
  } else if m.has_prefix("notifications/") {
    None
  } else {
    Some(
      "{\"jsonrpc\":\"2.0\",\"id\":\{id},\"error\":{\"code\":-32601,\"message\":\"method not found\"}}",
    )
  }
}

///|
fn usage_mcp() -> Unit {
  println(tmsg(
    "mcp 用法：`mng mcp`（直连已起应用）/ `mng mcp --run \"<起应用命令>\"`（拉起并注入 MNG_INSPECT=1）\n  " +
    "--app <id> 显式给应用 id；缺省读工程 mng.toml / moon.mod 推导。\n  " +
    "stdio 传输：AI 客户端把本命令配成 MCP server 即可。",
    "mcp usage: `mng mcp` (connect to a running app) / `mng mcp --run \"<command>\"` (spawn with MNG_INSPECT=1)\n  " +
    "Pass --app <id> explicitly; defaults to the project mng.toml / moon.mod.\n  " +
    "stdio transport: configure this command as an MCP server in your AI client.",
  ))
}

///|
fn cmd_mcp(args : Array[String]) -> Int32 {
  let mut run_cmd = ""
  let mut app_override = ""
  let mut k = 0
  while k < args.length() {
    let a = args[k]
    if a == "--run" && k + 1 < args.length() {
      run_cmd = args[k + 1]
      k += 2
    } else if a == "--app" && k + 1 < args.length() {
      app_override = args[k + 1]
      k += 2
    } else if a == "-h" || a == "--help" {
      usage_mcp()
      return 0
    } else {
      eprintln(tmsg("未知参数：" + a, "Unknown argument: " + a))
      usage_mcp()
      return 2
    }
  }
  let cwd = match @env.current_dir() {
    Some(d) => d
    None => "."
  }
  let app_id = if app_override.length() > 0 {
    app_override
  } else {
    match load_dev_conf("", "", "", None, cwd) {
      Ok(c) => c.app_id
      Err(e) => {
        eprintln(e)
        return 2
      }
    }
  }
  // --run：拉起应用并注入检查开关，等 socket 出现（照 dev 的就绪轮询）
  let mut child_pid = 0
  if run_cmd.length() > 0 {
    let (rfile, rargs) = match split_cmd(run_cmd) {
      Some(p) => p
      None => {
        eprintln(tmsg("--run 命令为空", "--run command is empty"))
        return 2
      }
    }
    match
      @proc.spawn(rfile, rargs, "", env=[
        ("MNG_INSPECT", "1"),
        ("MNG_INSPECT_APP", app_id),
      ]) {
      Ok(pid) => child_pid = pid
      Err(e) => {
        eprintln(tmsg("应用起不来：" + e, "cannot start app: " + e))
        return 1
      }
    }
    mcp_log("应用已拉起 pid=\{child_pid}（MNG_INSPECT=1）")
    let ready_sock = @inst.socket_path(app_id)
    let insp_sock = @insp.insp_socket_path(app_id)
    let mut waited = 0
    while waited < 15000 {
      let ok = @fs.is_file(insp_sock) catch { _ => false }
      if ok {
        break
      }
      // 应用先死了就别等
      if !@proc.alive(child_pid) {
        mcp_log("应用已退出（检查通道没起来）")
        return 1
      }
      @proc.sleep_ms(100)
      waited += 100
    }
    let ok = @fs.is_file(insp_sock) catch { _ => false }
    if !ok {
      // Windows 无文件面：socket 文件判不了，靠 tools/call 的连接错误兜底
      mcp_log("检查通道未就绪（\{ready_sock}），工具调用时再试")
    } else {
      mcp_log("检查通道就绪 " + insp_sock)
    }
  }
  // stdio 循环（照 lsp 的逐行读；MCP 是换行分隔 JSON，不用 Content-Length）
  while true {
    let line = match lsp_read_line() {
      Some(l) => l
      None => break
    }
    if line.trim().length() == 0 {
      continue
    }
    match mcp_handle(app_id, line) {
      Some(resp) => mcp_send(resp)
      None => ()
    }
  }
  if child_pid > 0 {
    let _ = @proc.kill(child_pid)
  }
  0
}
