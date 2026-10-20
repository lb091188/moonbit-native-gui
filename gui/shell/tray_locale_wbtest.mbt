// 托盘语言口登记链回归：登记即算一次、换目录再算一次、remove 撤下、
// 普通写入口以最后一次写法为准。

///|
fn locale_count_for_test() -> Int {
  let mut n = 0
  for (_k, _s) in locale_surfaces {
    n += 1
  }
  n
}

///|
test "语言口登记链：广播叫到每条在册口，撤下后不再叫" {
  // 直接摆一个假口进登记表，只验广播链本身（不触原生调用）
  locale_ensure_hook()
  let tips = Ref(0)
  let menus = Ref(0)
  locale_surfaces.set(9001, {
    tip: Some(fn() { tips.val += 1 }),
    menu: Some(fn() { menus.val += 1 }),
  })
  locale_refresh_all()
  assert_eq(tips.val, 1)
  assert_eq(menus.val, 1)
  // 换目录广播：两条口各再算一次
  @i18n.i18n_load("[meta]\nlocale = \"en\"\n")
  assert_eq(tips.val, 2)
  assert_eq(menus.val, 2)
  // 只留提示语口：菜单口清掉后广播不再叫它
  match locale_surfaces.get(9001) {
    Some(s) => s.menu = None
    None => ()
  }
  @i18n.i18n_load("[meta]\nlocale = \"de\"\n")
  assert_eq(tips.val, 3)
  assert_eq(menus.val, 2)
  let _ = locale_surfaces.remove(9001)
  @i18n.i18n_reset()
}

///|
test "Tray 语言口：登记即写一次，换语言重算，普通写口接管后不再重算" {
  if !Tray::is_supported() {
    return
  }
  let n = locale_count_for_test()
  let calls = Ref(0)
  match Tray::new("libyue-wbtest-locale") {
    Err(_) => ()
    Ok(t) => {
      t.set_tooltip_localized(
        fn() -> String {
          calls.val += 1
          "wb 标题"
        },
        fn() -> String { "wb 正文 \{calls.val.to_string()}" },
      )
      assert_eq(calls.val, 1)
      assert_eq(locale_count_for_test(), n + 1)
      @i18n.i18n_load("[meta]\nlocale = \"en\"\n")
      assert_eq(calls.val, 2)
      // 普通写口接管：之后的广播不再重算这条
      t.set_tooltip("静态", "静态正文")
      @i18n.i18n_load("[meta]\nlocale = \"de\"\n")
      assert_eq(calls.val, 2)
      t.remove()
      assert_eq(locale_count_for_test(), n)
      @i18n.i18n_reset()
    }
  }
}
