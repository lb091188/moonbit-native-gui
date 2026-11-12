// xdg-desktop-portal 客户端通用层（Wayland 原生路径 P1 地基）。
//
// portal 全族方法调用形态（xdg-desktop-portal 规格 + 本机 frontend 1.18.4
// 抓包定案）：入参末位带 `a{sv} options`，其中 `handle_token` 由调用方自造；
// portal 随即建一个 Request 对象，路径
// `/org/freedesktop/portal/desktop/request/<sender>/<token>`，**结果走信号**
// `org.freedesktop.portal.Request.Response(u code, a{sv} results)` 回到该
// 路径（code 0=成功 1=用户取消 2=失败）。sender 段 = 本端唯一名去掉冒号、
// 点换下杠（`:1.42` → `1_42`）。
//
// 本层管四件事：token 生成、request 路径派生、Response 一次性订阅（收到即
// 退订，不攒回调）、以及后端不应答时的静默（订阅挂着但不卡调用方——宿主
// 每帧泵，信号到了才回调）。**同步调用仍走 `gdbus_call_session`**（拿
// handle 那种），本层只包「结果在信号里」的异步握手。

///|
/// portal 前端的目标名与对象路径（规格钉死）。
pub const PORTAL_DEST : String = "org.freedesktop.portal.Desktop"

///|
pub const PORTAL_PATH : String = "/org/freedesktop/portal/desktop"

///|
/// Request 对象路径前缀。
pub const PORTAL_REQUEST_PREFIX : String = "/org/freedesktop/portal/desktop/request/"

///|
/// 自增 token（进程内唯一即可——request 路径已在 sender 段隔离）。
let g_portal_seq : Ref[Int32] = Ref(0)

///|
/// 造一个 handle_token（`mng<序号>` 形态；D-Bus 对象路径段安全字符）。
pub fn portal_next_token() -> String {
  g_portal_seq.val = g_portal_seq.val + 1
  "mng\{g_portal_seq.val}"
}

///|
/// sender 唯一名 → request 路径段：去冒号、点换下杠（`:1.42` → `1_42`；
/// 前端实物抓包口径，不是猜的）。
pub fn portal_sender_seg(sender : String) -> String {
  let sb = StringBuilder()
  for c in sender {
    if c == ':' {
      continue
    } else if c == '.' {
      sb.write_char('_')
    } else {
      sb.write_char(c)
    }
  }
  sb.to_string()
}

///|
/// 派生 Request 对象路径（本端 sender + 调用方 token）。
pub fn portal_request_path(token : String) -> String {
  "\{PORTAL_REQUEST_PREFIX}\{portal_sender_seg(dbus_unique_name())}/\{token}"
}

///|
/// Response 信号回调的载荷：应答码（0=成功 1=取消 2=失败）+ 结果字典。
pub(all) struct PortalResponse {
  code : Int32
  results : Map[String, GDBusValue]
}

///|
/// portal 异步调用：`iface.action(args)`，结果经 `on_response` 回调回来
/// （宿主每帧泵，信号到了才触发；一次性订阅收到即撤）。返回 Request 路径
/// （调用方无事可做就丢）；调用本身失败（连不上/编不过）给 Err。
pub fn portal_call(
  iface : String,
  action : String,
  args : Array[GDBusValue],
  token : String,
  on_response : (PortalResponse) -> Unit,
) -> Result[String, GDBusError] {
  let path = portal_request_path(token)
  let key = "portal.request.\{token}"
  let rule = "type='signal',sender='\{PORTAL_DEST}',interface='org.freedesktop.portal.Request',member='Response',path='\{path}'"
  match
    dbus_subscribe_session(rule, key, fn(vals : Array[GDBusValue]) -> Unit {
      // 一次性：先撤订阅再回调（回调里可能再发起下一轮 portal 调用）
      let _ = dbus_unsubscribe_session(rule, key)
      let code = match vals.get(0) {
        Some(GVUInt32(c)) => c
        Some(GVInt32(c)) => c
        _ => 2
      }
      let results : Map[String, GDBusValue] = match vals.get(1) {
        Some(GVDict(m)) => m
        _ => Map([])
      }
      on_response({ code, results, })
    }) {
    Err(e) => Err(gdbus_err("gdbus.io", e))
    Ok(_) =>
      match gdbus_call_session(PORTAL_DEST, PORTAL_PATH, iface, action, args) {
        Ok(_) => Ok(path)
        Err(e) => {
          // 调用就没出去：撤掉挂着的订阅，别留孤儿回调
          let _ = dbus_unsubscribe_session(rule, key)
          Err(e)
        }
      }
  }
}

///|
/// portal 是否可达（前端在会话总线上有名）。Wayland 原生会话才有意义；
/// X11/Windows/macOS 上一般没有——由调用方判会话类型。
pub fn portal_available() -> Bool {
  match
    gdbus_call_session(
      PORTAL_DEST,
      PORTAL_PATH,
      "org.freedesktop.DBus.Peer",
      "Ping",
      [],
    ) {
    Ok(_) => true
    Err(_) => false
  }
}
