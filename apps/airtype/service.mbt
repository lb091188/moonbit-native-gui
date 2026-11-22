// 投字服务：HTTP 出扫码页 + WebSocket 收文上屏。token 一次生成拼进网址，
// 页与升级口都校验；上屏结果回执 ok / err:…。多台手机可同时连。

///|
/// 默认端口，AIRTYPE_PORT 覆盖（1~65535，非法值回落默认）。
const DEFAULT_PORT : Int32 = 8787

///|
fn service_port() -> Int32 {
  match @env.get_env_var("AIRTYPE_PORT") {
    Some(s) => {
      if s.length() == 0 || s.length() > 5 {
        return DEFAULT_PORT
      }
      let mut v = 0
      for ch in s {
        let d = ch.to_int() - 48
        if d < 0 || d > 9 {
          return DEFAULT_PORT
        }
        v = v * 10 + d
      }
      if v >= 1 && v <= 65535 {
        v
      } else {
        DEFAULT_PORT
      }
    }
    None => DEFAULT_PORT
  }
}

///|
/// URL 安全 token：两个平台熵 uint64 拼字节串转 hex，32 字符。
fn gen_token() -> String {
  let a = @random.uint64()
  let b = @random.uint64()
  let bytes = Bytes::makei(16, fn(i) {
    let w = if i < 8 {
      a >> ((i % 8) * 8)
    } else {
      b >> ((i % 8) * 8)
    }
    (w & 0xFFUL).to_int().to_byte()
  })
  @hex.encode(bytes)
}

///|
/// 局域网出口 IP（UDP connect 只选路由不发包）。两个探测目标，都失败给
/// None——UI 报无网络。
async fn lan_ip() -> String? {
  for target in ["8.8.8.8:53", "114.114.114.114:53"] {
    let addr = @socket.Addr::parse(target) catch {
      _ => continue
    }
    let probe = @socket.UdpClient(addr) catch {
      _ => continue
    }
    let ip = probe.addr.ip.to_string()
    probe.close()
    // 回环地址不是手机扫码可达的地址
    if ip != "127.0.0.1" && ip != "::1" {
      return Some(ip)
    }
  }
  None
}

///|
/// 当前手机连接数（多条 WS 并发各算一）。
let g_ws_conns : Ref[Int32] = Ref(0)

///|
/// 上屏记录：新条目进前头，最多 8 条；预览截 24 个字符。
fn push_history(app : App, text : String) -> Unit {
  let preview = if text.length() > 24 {
    text[:24].to_owned() + "…"
  } else {
    text
  }
  let next : Array[String] = [preview]
  for h in app.history.get() {
    if next.length() >= 8 {
      break
    }
    next.push(h)
  }
  app.history.set(next)
}

///|
/// 从路径里取查询参数值："/ws?t=abc" 的 "t" → "abc"。
fn query_of(path : String, key : String) -> String? {
  let qi = match path.find("?") {
    Some(i) => i
    None => return None
  }
  for kv in path[qi + 1:].split("&") {
    let kv = kv.to_owned()
    match kv.find("=") {
      Some(i) =>
        if kv[:i] == key {
          return Some(kv[i + 1:].to_owned())
        }
      None => ()
    }
  }
  None
}

///|
/// 一条手机连接的收发环：收文本 → 注入 → 回执。
async fn serve_ws(app : App, ws : @websocket.Conn) -> Unit {
  g_ws_conns.val += 1
  app.conns.set("\{g_ws_conns.val}")
  defer {
    g_ws_conns.val -= 1
    app.conns.set("\{g_ws_conns.val}")
    ws.close()
  }
  for ;; {
    let msg = ws.recv() catch {
      _ => break
    }
    if msg.kind is Text {
      let text = msg.text.read_all() catch {
        _ => continue
      }
      if text.length() == 0 {
        continue
      }
      match @sys.inject_text(text) {
        Ok(_) => {
          push_history(app, text)
          ws.send_text("ok") catch {
            _ => break
          }
        }
        Err(e) => {
          ws.send_text("err:\{e}") catch {
            _ => break
          }
        }
      }
    }
  }
}

///|
/// 起服务并跑到被取消（async main 的任务组收口时自动关停）。地址与二维码
/// 在监听成功后写进状态面板。
async fn service_run(app : App, token : String) -> Unit {
  let ip = match lan_ip() {
    Some(v) => v
    None => {
      app.state.set("无网络（局域网出口不可达）")
      return
    }
  }
  let port = service_port()
  let addr = @socket.Addr::parse("0.0.0.0:\{port}") catch {
    _ => {
      app.state.set("监听地址错误")
      return
    }
  }
  let server = @http.Server(addr, reuse_addr=true) catch {
    e => {
      app.state.set("端口占用（\{e}）")
      return
    }
  }
  let real_port = server.addr.port
  app.state.set("服务已启动")
  app.addr.set("\{ip}:\{real_port}")
  let url = "http://\{ip}:\{real_port}/?t=\{token}"
  app.url.set(url)
  app.qr.set(qr_image_of(url))
  @widget.invalidate()
  server.run_forever(
    (req, conn) => {
      // token 门禁：页与升级口都只认 ?t=<token>，不符一律 403
      if query_of(req.path, "t") != Some(token) {
        conn.send_response(403, "Forbidden")
        return
      }
      let base = match req.path.find("?") {
        Some(i) => req.path[:i].to_owned()
        None => req.path
      }
      if base == "/ws" {
        // 非法握手 from_http_server 自己回 400 并抛错
        let ws = @websocket.from_http_server(req, conn) catch {
          _ => return
        }
        serve_ws(app, ws)
      } else {
        conn.send_response(
          200,
          "OK",
          extra_headers={ "Content-Type": "text/html; charset=utf-8" },
        )
        conn.text.write(page_html(token))
        conn.end_response()
      }
    },
    allow_failure=true,
  )
}
