// 菜单栏登记口：构建器随语言广播重算；无宿主窗时只跑链不触原生调用。

///|
fn clear_locale_subs() -> Unit {
  // 链是进程级的：反复退掉号段内的全部监听，直到链尾句柄号不再增长
  let mut hi = @i18n.on_locale_change(fn(_l) { () })
  let mut rounds = 0
  while rounds < 12 {
    let mut i = 1
    while i <= hi {
      @i18n.off_locale_change(i)
      i = i + 1
    }
    let next = @i18n.on_locale_change(fn(_l) { () })
    if next == hi {
      rounds = 12
    }
    hi = next
    rounds = rounds + 1
  }
}

///|
test "set_menu_bar_localized：注册即建一次，换目录再建一次，重复登记替换旧构建器" {
  clear_locale_subs()
  @i18n.i18n_reset()
  let builds : Ref[Int] = Ref(0)
  set_menu_bar_localized(fn(_w : @win.Window) -> @shell.MenuBar {
    builds.val += 1
    @shell.MenuBar::new()
  })
  assert_true(builds.val >= 1)
  // 宿主窗数在多测试二进制里会漂移：只断言「每次广播旧构建器都被叫到、且只按窗次计」
  let a = builds.val
  @i18n.i18n_load("[meta]\nlocale = \"en\"\n")
  let b = builds.val
  assert_true(b > a)
  // 重复登记替换：之后换目录只叫新构建器，旧的那位计数停住
  set_menu_bar_localized(fn(_w : @win.Window) -> @shell.MenuBar {
    @shell.MenuBar::new()
  })
  let c = builds.val
  @i18n.i18n_load("[meta]\nlocale = \"de\"\n")
  assert_eq(builds.val, c)
  @i18n.i18n_reset()
  clear_locale_subs()
}
