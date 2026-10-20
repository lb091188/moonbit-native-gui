// gui/i18n 运行时回归。

test "i18n_load + t + 插值 + locale" {
  i18n_load(
    "[meta]\nlocale = \"zh-CN\"\n[common]\nok = \"确定\"\n[error]\nnf = \"不存在：{path}\"\n",
  )
  assert_eq(i18n_locale(), "zh-CN")
  assert_eq(t("common.ok"), Some("确定"))
  assert_eq(t_with("error.nf", [("path", "/x")]), Some("不存在：/x"))
  assert_eq(t("nope"), None)
}

test "回退目录补主目录缺项" {
  i18n_load("[meta]\nlocale = \"ja\"\n[common]\nsave = \"保存\"\n")
  i18n_load_fallback("[meta]\nlocale = \"en\"\n[common]\nclose = \"Close\"\n")
  assert_eq(t("common.save"), Some("保存"))
  assert_eq(t("common.close"), Some("Close"))
}

test "复数按主语言选择" {
  i18n_load(
    "[meta]\nlocale = \"en\"\n[items]\ncount = { one = \"{n} item\", other = \"{n} items\" }\n",
  )
  assert_eq(t_count("items.count", 1), Some("1 item"))
  assert_eq(t_count("items.count", 3), Some("3 items"))
}

test "t_or 行为不变 + chrome 段键扁平化" {
  // 加载 en：命中 gui.ui.dialog.confirm → "OK"；未命中 → 回落字面量
  i18n_load("[meta]\nlocale = \"en\"\n[gui.ui.dialog]\nconfirm = \"OK\"\n")
  assert_eq(t_or("gui.ui.dialog.confirm", "确定"), "OK")
  assert_eq(t_or("gui.ui.dialog.missing", "默认值"), "默认值")
  // 不加载任何该键的目录：chrome 逐字回到旧硬编码，行为不变
  i18n_load("[meta]\nlocale = \"none\"\n")
  assert_eq(t_or("gui.ui.dialog.confirm", "确定"), "确定")
}
