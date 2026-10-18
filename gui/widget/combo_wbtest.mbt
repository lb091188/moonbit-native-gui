test "parse_combo：Ctrl+S 解析" {
  match parse_combo("Ctrl+S") {
    Some((m, k)) => {
      assert_eq(m, @base.MOD_CTRL)
      assert_eq(k, 115)
    }
    None => assert_eq(true, false)
  }
}

test "parse_combo：Alt+Shift+Tab 多修饰键" {
  match parse_combo("Alt+Shift+Tab") {
    Some((m, k)) => {
      assert_eq(m, @base.MOD_ALT | @base.MOD_SHIFT)
      assert_eq(k, @base.KS_TAB)
    }
    None => assert_eq(true, false)
  }
}

test "parse_combo：大小写不敏感" {
  match parse_combo("ctrl+enter") {
    Some((m, k)) => {
      assert_eq(m, @base.MOD_CTRL)
      assert_eq(k, @base.KS_RETURN)
    }
    None => assert_eq(true, false)
  }
}

test "parse_combo：无修饰键的单键" {
  match parse_combo("Escape") {
    Some((m, k)) => {
      assert_eq(m, 0)
      assert_eq(k, @base.KS_ESCAPE)
    }
    None => assert_eq(true, false)
  }
}

test "ev_is_combo：按下且 mods 匹配才命中" {
  let ev : KeyEvent = {
    press: true,
    keysym: 115,
    mods: @base.MOD_CTRL,
  }
  assert_true(ev_is_combo(ev, "Ctrl+S"))
  assert_false(ev_is_combo(ev, "Ctrl+Shift+S"))
  let up : KeyEvent = {
    press: false,
    keysym: 115,
    mods: @base.MOD_CTRL,
  }
  assert_false(ev_is_combo(up, "Ctrl+S"))
}

test "parse_combo：CmdOrCtrl 按平台落地（mac=Cmd、其余=Ctrl）" {
  match parse_combo("CmdOrCtrl+Shift+M", mac=true) {
    Some((m, k)) => {
      assert_eq(m, @base.MOD_META | @base.MOD_SHIFT)
      assert_eq(k, 109)
    }
    None => assert_eq(true, false)
  }
  match parse_combo("CmdOrCtrl+Shift+M", mac=false) {
    Some((m, _k)) => assert_eq(m, @base.MOD_CTRL | @base.MOD_SHIFT)
    None => assert_eq(true, false)
  }
  // 缺省（不传 mac）= 非 mac 档
  match parse_combo("CommandOrControl+S") {
    Some((m, _k)) => assert_eq(m, @base.MOD_CTRL)
    None => assert_eq(true, false)
  }
}

test "parse_combo：修饰键别名与 win 侧词表同源" {
  // control/option/command/win 都认（同一串 spec 在窗口内与全局热键不该两个意思）
  for pair in [
    ("Control+S", @base.MOD_CTRL), ("Option+S", @base.MOD_ALT),
    ("Opt+S", @base.MOD_ALT), ("Command+S", @base.MOD_META),
    ("Win+S", @base.MOD_META),
  ] {
    match parse_combo(pair.0) {
      Some((m, _k)) => assert_eq(m, pair.1, msg=pair.0)
      None => assert_eq(true, false, msg=pair.0)
    }
  }
}

test "system_key_action：mac 三条系统档，非 mac 一律不抢" {
  let cmd = @base.MOD_META
  assert_eq(system_key_action(cmd, 113, true, true), 1) // Cmd+Q 退出
  assert_eq(system_key_action(cmd, 119, true, true), 2) // Cmd+W 关本窗
  assert_eq(system_key_action(cmd | @base.MOD_CTRL, 102, true, true), 3) // Ctrl+Cmd+F 翻全屏
  // 多按一个 Shift 不算命中、抬起不算命中
  assert_eq(system_key_action(cmd | @base.MOD_SHIFT, 113, true, true), 0)
  assert_eq(system_key_action(cmd, 113, false, true), 0)
  // 非 macOS：同样的组合留给桌面，不抢
  assert_eq(system_key_action(cmd, 113, true, false), 0)
  assert_eq(system_key_action(@base.MOD_CTRL, 113, true, false), 0)
}
