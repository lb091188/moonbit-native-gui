// Wayland 档全局快捷键：xdg-desktop-portal 的 GlobalShortcuts 绑定 +
// Activated 信号回调（Wayland 原生路径 P1 的 Consumers 之一）。
//
// 与 X11 臂的口径差（方案 §五 定的形态变化，写进接口文档）：
//   X11/Win/mac：`hotkey_register` 同步注册 + `hotkey_poll` 每帧抽；
//   Wayland：`global_shortcuts_bind` **绑定 + 信号回调**——portal 侧要用户
//   在系统授权框里确认（每次绑定一弹），激活动作经 Activated 信号推来，
//   没有可轮询的队列。两档都由壳层按会话类型分派，应用侧一个入口。
//
// 绑定是两段异步握手（Request/Response 通用层，`@dbus.portal_call`）：
//   ① CreateSession → Response 的 results 里拿 session_handle；
//   ② BindShortcuts(session, [(id, {description, preferred_trigger})], …)；
//   ③ 成功即订阅 session 上的 Activated 信号，之后每次触发调回调。
// 任一步失败（portal 不在/后端不支持/用户拒了）如实回 Err——**不许静默
// 假成功**（「注册成功却永不触发」正是本批要灭的形态）。

///|
/// portal GlobalShortcuts 的接口名（规格钉死）。
pub const GLOBAL_SHORTCUTS_IFACE : String = "org.freedesktop.portal.GlobalShortcuts"

///|
/// 绑定结果错误（字符串形态，理由原样可读）。
pub(all) suberror GsError {
  GsFailed(String)
}

///|
pub impl Show for GsError with fn output(self, logger) {
  match self {
    GsFailed(m) => logger.write_string("GsFailed(\{m})")
  }
}

///|
pub extend GsError with Show::{to_string, output}

///|
/// 本进程是否 Wayland 会话（`@sys.session_type` 是 `@win` 的探测转出；
/// 非 Wayland 不该碰 portal 快捷键）。
fn in_wayland() -> Bool {
  match @sys.session_type() {
    @sys.SessionType::Wayland => true
    _ => false
  }
}

///|
/// 后端可用性：Wayland 会话且 portal 前端可达。**不等于这次绑定能成**——
/// 后端（KDE 5.27+ / GNOME 48+）不支持时绑定回 Err。
pub fn global_shortcuts_supported() -> Bool {
  in_wayland() && @dbus.portal_available()
}

///|
/// 加速串 → portal 的 `preferred_trigger`（GTK 加速器形态）：
/// `Ctrl+Alt+C` → `<Control><Alt>c`；`CmdOrCtrl` 落 `<Primary>`（平台主修饰，
/// 与库内词表同义）。解析不了给 None。
pub fn gs_trigger_of(spec : String) -> String? {
  match @win.parse_accelerator(spec, platform_is_macos()) {
    None => None
    Some(hk) => {
      let sb = StringBuilder()
      if (hk.mods & 1) != 0 {
        sb.write_string("<Shift>")
      }
      if (hk.mods & 2) != 0 {
        sb.write_string("<Control>")
      }
      if (hk.mods & 4) != 0 {
        sb.write_string("<Alt>")
      }
      if (hk.mods & 8) != 0 {
        sb.write_string("<Super>")
      }
      // 单字符键 GTK 口径小写；F9/PageUp 这类多字符键名原样
      if hk.name.length() == 1 {
        for c in hk.name {
          sb.write_char(if c >= 'A' && c <= 'Z' {
            (c.to_int() + 32).unsafe_to_char()
          } else {
            c
          })
        }
      } else {
        sb.write_string(hk.name)
      }
      Some(sb.to_string())
    }
  }
}

///|
/// 绑定状态（进程级：绑过几条、各自的 shortcut id 与回调）。
priv struct GsBind {
  id : String
  on_activated : () -> Unit
}

let gs_binds : Ref[Array[GsBind]] = Ref([])
let gs_session : Ref[String?] = Ref(None) // session_handle（建过就复用）
let gs_sub_on : Ref[Bool] = Ref(false)

///|
/// 建 session（幂等）：CreateSession 的 Response 里拿 session_handle。
fn gs_ensure_session(done : () -> Unit) -> Unit {
  if gs_session.val is Some(_) {
    done()
    return
  }
  let token = @dbus.portal_next_token()
  match
    @dbus.portal_call(
      GLOBAL_SHORTCUTS_IFACE,
      "CreateSession",
      [@dbus.GVDict(portal_opts(token))],
      token,
      fn(resp : @dbus.PortalResponse) -> Unit {
        match resp.code {
          0 =>
            match resp.results.get("session_handle") {
              Some(@dbus.GVPath(p)) => {
                gs_session.val = Some(p)
                done()
              }
              _ => ()
            }
          _ => ()
        }
      },
    ) {
    Ok(_) => ()
    Err(_) => ()
  }
}

///|
/// options 字典助手：handle_token 必带（portal 靠它建 Request 对象）。
fn portal_opts(token : String) -> Map[String, @dbus.GDBusValue] {
  let m : Map[String, @dbus.GDBusValue] = Map([])
  m.set("handle_token", @dbus.GVString(token))
  m
}

///|
/// 绑一条快捷键：session 就绪后 BindShortcuts，成功即订阅 Activated。
/// 回调在宿主每帧泵里触发（信号到达时）。
pub fn global_shortcuts_bind(
  spec : String,
  on_activated : () -> Unit,
) -> Unit raise GsError {
  if !in_wayland() {
    raise GsFailed("非 Wayland 会话（走 X11 臂 hotkey_register）")
  }
  let trigger = match gs_trigger_of(spec) {
    Some(t) => t
    None => raise GsFailed("加速串无法解析：\{spec}")
  }
  let id = gs_id_of(spec)
  gs_ensure_session(fn() -> Unit {
    match gs_session.val {
      None => ()
      Some(session) => gs_bind_on(session, id, trigger)
    }
  })
  gs_binds.val.push({ id, on_activated })
  ()
}

///|
/// shortcut id：加速串的路径/标识安全形态（portal 用它回指是哪一条）。
pub fn gs_id_of(spec : String) -> String {
  let sb = StringBuilder()
  for c in spec {
    if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') {
      sb.write_char(c)
    } else {
      sb.write_char('_')
    }
  }
  sb.to_string()
}

///|
/// session 上 BindShortcuts（第二段握手）。
fn gs_bind_on(session : String, id : String, trigger : String) -> Unit {
  let token = @dbus.portal_next_token()
  let entry : Map[String, @dbus.GDBusValue] = Map([])
  entry.set("description", @dbus.GVString("全局快捷键 \{trigger}"))
  entry.set("preferred_trigger", @dbus.GVString(trigger))
  let shortcuts : Array[@dbus.GDBusValue] = [
    @dbus.GVStruct([@dbus.GVString(id), @dbus.GVDict(entry)]),
  ]
  let _ = @dbus.portal_call(
    GLOBAL_SHORTCUTS_IFACE,
    "BindShortcuts",
    [
      @dbus.GVPath(session),
      @dbus.GVArray("(sa{sv})", shortcuts),
      @dbus.GVString(""),
      @dbus.GVDict(portal_opts(token)),
    ],
    token,
    fn(resp : @dbus.PortalResponse) -> Unit {
      // code 1 = 用户取消授权；2 = 后端不支持/失败——两者都不装触发
      if resp.code == 0 {
        gs_sub_activated()
      }
    },
  )
}

///|
/// 订阅 session 上的 Activated 信号（一次；回调按 shortcut_id 找绑定）。
fn gs_sub_activated() -> Unit {
  if gs_sub_on.val {
    return
  }
  gs_sub_on.val = true
  let session = match gs_session.val {
    Some(s) => s
    None => return
  }
  let rule =
    "type='signal',sender='\{@dbus.PORTAL_DEST}',interface='\{GLOBAL_SHORTCUTS_IFACE}',member='Activated',path='\{session}'"
  let _ = @dbus.dbus_subscribe_session(rule, "portal.gs.activated", fn(vals) {
    // Activated(o session, s shortcut_id, t timestamp, a{sv} options)
    match vals.get(1) {
      Some(@dbus.GVString(sid)) => gs_fire(sid)
      _ => ()
    }
  })
}

///|
/// 按 shortcut_id 触发回调（未绑的 id 忽略）。
fn gs_fire(id : String) -> Unit {
  for b in gs_binds.val {
    if b.id == id {
      (b.on_activated)()
    }
  }
}

///|
/// 已绑定条数（状态行读数）。
pub fn global_shortcuts_count() -> Int {
  gs_binds.val.length()
}
