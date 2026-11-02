// gui/i18n 运行时回归。各例开头 i18n_reset() 隔离全局态。

test "零外置文件即命中内置默认（默认语言内置）" {
  i18n_reset()
  assert_eq(i18n_locale(), "default")
  assert_eq(t("gui.ui.dialog.confirm"), Some("确定"))
  assert_eq(t("gui.ui.message_box.ok"), Some("确定"))
}

test "i18n_load + t + 插值 + locale" {
  i18n_reset()
  i18n_load(
    "[meta]\nlocale = \"zh-CN\"\n[common]\nok = \"确定\"\n[error]\nnf = \"不存在：{path}\"\n",
  )
  assert_eq(i18n_locale(), "zh-CN")
  assert_eq(t("common.ok"), Some("确定"))
  assert_eq(t_with("error.nf", [("path", "/x")]), Some("不存在：/x"))
  assert_eq(t("totally_unknown_key"), None)
}

test "回退目录补主目录缺项" {
  i18n_reset()
  i18n_load("[meta]\nlocale = \"ja\"\n[common]\nsave = \"保存\"\n")
  i18n_load_fallback("[meta]\nlocale = \"en\"\n[common]\nclose = \"Close\"\n")
  assert_eq(t("common.save"), Some("保存"))
  assert_eq(t("common.close"), Some("Close"))
}

test "外置语言覆盖内置 chrome（en 覆盖默认确定→OK）" {
  i18n_reset()
  i18n_extend("[meta]\nlocale = \"en\"\n[gui.ui.dialog]\nconfirm = \"OK\"\n")
  assert_eq(t("gui.ui.dialog.confirm"), Some("OK"))
  // 未在 en 里定义的其它 chrome 键，仍兜底到内置默认（中文）
  assert_eq(t("gui.ui.datepicker.cancel"), Some("取消"))
}

test "复数按主语言选择" {
  i18n_reset()
  i18n_load(
    "[meta]\nlocale = \"en\"\n[items]\ncount = { one = \"{n} item\", other = \"{n} items\" }\n",
  )
  assert_eq(t_count("items.count", 1), Some("1 item"))
  assert_eq(t_count("items.count", 3), Some("3 items"))
}

test "t_or 未定义键回落字面量" {
  i18n_reset()
  assert_eq(t_or("gui.ui.dialog.confirm", "X"), "确定") // 内置默认命中
  assert_eq(t_or("some.unknown.key", "默认值"), "默认值") // 皆无 → 字面量
}

///|
test "键里带等号：引号内的 `=` 不当分隔符" {
  i18n_load(
    "\"white_space=NoWrap 的说明\" = \"No-wrap note\"\nplain = \"Plain\"\n",
  )
  assert_eq(t_or("white_space=NoWrap 的说明", "?"), "No-wrap note")
  assert_eq(t_or("plain", "?"), "Plain")
  i18n_reset()
}

///|
/// 静默失效的三种写法都要能查到：带引号的顶层键、`[段]` 前缀键、值里的 `\n`
/// 转义；顶层键必须写在任何段头之前，`[meta]` 放最后。
test "顶层键引号 / 段前缀 / 值内转义 / `[meta]` 顺序" {
  i18n_load(
    "\"圆角与柔焦\" = \"Corners\"\n\"两行\\n文本\" = \"Two\\nlines\"\n[menu]\nnav = \"Navigation\"\n[meta]\nlocale = \"en\"\n",
  )
  assert_eq(t_or("圆角与柔焦", "FALLBACK"), "Corners")
  assert_eq(t_or("两行\n文本", "FALLBACK"), "Two\nlines")
  assert_eq(t_or("menu.nav", "FALLBACK"), "Navigation")
  assert_eq(i18n_locale(), "en")
  i18n_reset()
  assert_eq(t_or("圆角与柔焦", "FALLBACK"), "FALLBACK")
}
