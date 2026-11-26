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
/// 局域网地址：网卡枚举 + RFC1918 过滤（`@sys.netif_lan_ip`）。不走 UDP
/// connect 出口探测——代理 TUN 接管默认路由时会拿到 198.18.x 假地址。
fn lan_ip() -> String? {
  @sys.netif_lan_ip()
}

///|
/// 当前手机连接数（多条 WS 并发各算一）。
let g_ws_conns : Ref[Int32] = Ref(0)

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
async fn serve_ws(ws : @websocket.Conn) -> Unit {
  g_ws_conns.val += 1
  s_conns.set("\{g_ws_conns.val}")
  defer {
    g_ws_conns.val -= 1
    s_conns.set("\{g_ws_conns.val}")
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
      // 心跳：页面每 10 秒发 ping，回 pong 作探活凭证（15 秒无回包页面
      // 主动断开重连）——假死连接靠页面侧检测，不走 TCP 超时熬
      if text == "ping" {
        ws.send_text("pong") catch {
          _ => break
        }
        continue
      }
      if text.length() == 0 {
        continue
      }
      // 协议 v2：首行命令 + \n + 载荷；未知命令整条按文本投（兼容纯文本）
      //   enter      投真实回车键
      //   type\n文   投文本
      //   te\n文     投文本后跟回车（快捷指令的原子动作）
      let nl = text.find("\n")
      let cmd = match nl {
        Some(i) => text[:i].to_owned()
        None => ""
      }
      let payload = match nl {
        Some(i) => text[i + 1:].to_owned()
        None => text
      }
      let res : Result[Unit, @sys.InjectError] = match cmd {
        "enter" => @sys.inject_key(@sys.Key::Enter)
        "type" => @sys.inject_text(payload)
        "te" =>
          if payload.length() == 0 {
            @sys.inject_key(@sys.Key::Enter)
          } else {
            match @sys.inject_text(payload) {
              Ok(_) => @sys.inject_key(@sys.Key::Enter)
              Err(e) => Err(e)
            }
          }
        _ => @sys.inject_text(text)
      }
      // 回车动作不进记录；文本类记真实载荷
      let hist = match cmd {
        "enter" => ""
        "type" | "te" => payload
        _ => text
      }
      match res {
        Ok(_) => {
          if hist.length() > 0 {
            push_history(hist)
          }
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
async fn service_run(token : String) -> Unit {
  let ip = match lan_ip() {
    Some(v) => v
    None => {
      s_state.set("无网络（局域网出口不可达）")
      return
    }
  }
  let port = service_port()
  let addr = @socket.Addr::parse("0.0.0.0:\{port}") catch {
    _ => {
      s_state.set("监听地址错误")
      return
    }
  }
  let server = @http.Server(addr, reuse_addr=true) catch {
    e => {
      s_state.set("端口占用（\{e}）")
      return
    }
  }
  let real_port = server.local_addr().port
  s_state.set("服务已启动")
  s_addr.set("\{ip}:\{real_port}")
  let url = "http://\{ip}:\{real_port}/?t=\{token}"
  s_url.set(url)
  s_qr.set(qr_image_of(url))
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
      if base == "/cfg" {
        // 快捷指令配置：手机页加载与亮屏回前台时拉取
        conn.send_response(
          200,
          "OK",
          extra_headers={ "Content-Type": "application/json; charset=utf-8" },
        )
        conn.text.write(shortcuts_json())
        conn.end_response()
      } else if base == "/ws" {
        // 非法握手 from_http_server 自己回 400 并抛错
        let ws = @websocket.from_http_server(req, conn) catch {
          _ => return
        }
        serve_ws(ws)
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
