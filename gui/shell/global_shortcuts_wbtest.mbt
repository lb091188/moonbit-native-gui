// GlobalShortcuts 门面的无头回归：加速串 → portal trigger / shortcut id 的
// 纯函数。绑定握手（CreateSession/BindShortcuts + 授权框）要真 portal，
// 归真机清单。

///|
test "gs：加速串转 portal 的 preferred_trigger（GTK 加速器形态）" {
  assert_eq(gs_trigger_of("Ctrl+Alt+C"), Some("<Control><Alt>c"))
  assert_eq(gs_trigger_of("Ctrl+Shift+M"), Some("<Shift><Control>m"))
  assert_eq(gs_trigger_of("F9"), Some("F9"))
  // CmdOrCtrl 落平台主修饰：Linux/Windows 落 Control，mac 落 Super（Cmd）
  let coc = if platform_is_macos() {
    "<Alt><Super>c"
  } else {
    "<Control><Alt>c"
  }
  assert_eq(gs_trigger_of("CmdOrCtrl+Alt+C"), Some(coc))
  // 解析不了的串给 None（不许硬编）
  assert_true(gs_trigger_of("不是加速串") is None)
}

///|
test "gs：shortcut id 路径/标识安全（非字母数字统一下杠）" {
  assert_eq(gs_id_of("Ctrl+Alt+C"), "Ctrl_Alt_C")
  assert_eq(gs_id_of("F9"), "F9")
  assert_eq(gs_id_of("CmdOrCtrl+Shift+M"), "CmdOrCtrl_Shift_M")
}
