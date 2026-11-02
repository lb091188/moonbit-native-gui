// 语言变更广播：换目录触发订阅、退订后不再触发、复位也算一次变更。

///|
test "on_locale_change：load/extend/reset 各广播一次，退订后静默" {
  let hits : Ref[Array[String]] = Ref([])
  i18n_reset()
  assert_eq(hits.val.length(), 0)
  let h = on_locale_change(loc => hits.val.push(loc))
  i18n_load("[meta]\nlocale = \"en\"\n")
  assert_eq(hits.val, ["en"])
  off_locale_change(h)
  i18n_reset()
  assert_eq(hits.val.length(), 1)
}

///|
test "广播带的是换完之后的 locale，不是旧值" {
  let seen : Ref[String] = Ref("")
  let h = on_locale_change(loc => seen.val = loc)
  i18n_load("[meta]\nlocale = \"de\"\n")
  assert_eq(seen.val, "de")
  assert_eq(i18n_locale(), "de")
  i18n_reset()
  assert_true(seen.val != "de")
  off_locale_change(h)
  i18n_reset()
}

///|
test "内置默认态：未装外置目录时 reset 前后查译链不变" {
  i18n_reset()
  assert_true(t_or("some.missing.key", "兜底") == "兜底")
}
