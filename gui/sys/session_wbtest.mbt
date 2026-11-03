// 会话类型：纯解析 + 读本机环境（改完还原），以及 X 工具族按 Wayland 的降级。

///|
test "session_type_of：XDG_SESSION_TYPE 说话在先，WAYLAND_DISPLAY 只作回落" {
  assert_true(session_type_of("wayland", "") is Wayland)
  assert_true(session_type_of("Wayland", "") is Wayland)
  assert_true(session_type_of(" wayland ", "") is Wayland)
  // XDG 已写 x11 时不再看 WAYLAND_DISPLAY（XWayland 应用环境里两者常同时在）
  assert_true(session_type_of("x11", "wayland-0") is X11)
  assert_true(session_type_of("", "wayland-0") is Wayland)
  assert_true(session_type_of("", "") is Unknown)
  assert_true(session_type_of("", "   ") is Unknown)
  // tty / display-manager 一类值既不是 X11 也不是 Wayland
  assert_true(session_type_of("tty", "") is Unknown)
  assert_true(session_type_of("display-manager", "") is Unknown)
}

///|
test "session_type 随进程环境变（前后还原本机值）" {
  let had_xdg = envx_get("XDG_SESSION_TYPE")
  let had_wl = envx_get("WAYLAND_DISPLAY")
  let _ = envx_set("XDG_SESSION_TYPE", "wayland")
  assert_true(session_type() is Wayland)
  assert_true(in_wayland_session())
  let _ = envx_set("XDG_SESSION_TYPE", "x11")
  let _ = envx_set("WAYLAND_DISPLAY", "wayland-1")
  assert_true(session_type() is X11)
  assert_false(in_wayland_session())
  let _ = envx_unset("XDG_SESSION_TYPE")
  assert_true(session_type() is Wayland) // 回落到 WAYLAND_DISPLAY
  // 还原：原本没有的删掉，原本有的写回
  match had_xdg {
    Some(v) => {
      let _ = envx_set("XDG_SESSION_TYPE", v)
    }
    None => {
      let _ = envx_unset("XDG_SESSION_TYPE")
    }
  }
  match had_wl {
    Some(v) => {
      let _ = envx_set("WAYLAND_DISPLAY", v)
    }
    None => {
      let _ = envx_unset("WAYLAND_DISPLAY")
    }
  }
  // 还原后与直接按原值解析同一形态（本机的值不参与断言内容）
  let back = session_type()
  let want = session_type_of(had_xdg.unwrap_or(""), had_wl.unwrap_or(""))
  assert_true(back is X11 || back is Wayland || back is Unknown)
  assert_true(
    (back is X11 && want is X11) || (back is Wayland && want is Wayland) ||
      (back is Unknown && want is Unknown),
  )
}

///|
test "Wayland 会话下 X 工具族显式降级：夜灯与窗口管理都不报支持" {
  // 非 Linux 平台在各自的支里先返回（Windows 走 SetDeviceGammaRamp、mac 走覆盖层
  // 与 CGWindowList），这一档只钉 Linux 的会话门。
  if sys_platform() != "linux" {
    println("session gate: skip (非 Linux)")
    return
  }
  let had_xdg = envx_get("XDG_SESSION_TYPE")
  let had_wl = envx_get("WAYLAND_DISPLAY")
  let _ = envx_set("XDG_SESSION_TYPE", "wayland")
  assert_false(nl_supported())
  assert_true(nl_set_temperature(30) is Err(Unsupported))
  assert_true(nl_reset() is Err(Unsupported))
  assert_false(win_supported())
  assert_true(win_activate("0x12345") is Err(Unsupported))
  assert_true(win_close("某窗口") is Err(Unsupported))
  assert_true(win_list() is Err(Unsupported))
  match had_xdg {
    Some(v) => {
      let _ = envx_set("XDG_SESSION_TYPE", v)
    }
    None => {
      let _ = envx_unset("XDG_SESSION_TYPE")
    }
  }
  match had_wl {
    Some(v) => {
      let _ = envx_set("WAYLAND_DISPLAY", v)
    }
    None => {
      let _ = envx_unset("WAYLAND_DISPLAY")
    }
  }
}
