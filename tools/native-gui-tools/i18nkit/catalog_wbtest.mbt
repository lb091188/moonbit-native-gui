// i18nkit 内核测试：解析、查译、插值、复数、回退。

test "解析 + 查译 + 命名插值" {
  let c = parse_catalog(
    "[meta]\nlocale = \"zh-CN\"\n[common]\nok = \"确定\"\n[error]\nnot_found = \"文件不存在：{path}\"\n",
  )
  assert_eq(c.locale, "zh-CN")
  assert_eq(t(c, "common.ok"), Some("确定"))
  assert_eq(
    t_with(c, "error.not_found", [("path", "/tmp/x")]),
    Some("文件不存在：/tmp/x"),
  )
  assert_eq(t(c, "common.missing"), None)
}

test "复数内联表按 one/other" {
  let en = parse_catalog(
    "[meta]\nlocale = \"en\"\n[items]\ncount = { one = \"{n} item\", other = \"{n} items\" }\n",
  )
  assert_eq(t_count(en, "items.count", 1), Some("1 item"))
  assert_eq(t_count(en, "items.count", 5), Some("5 items"))
}

test "中文复数恒 other（zh-CN 归 zh）" {
  let zh = parse_catalog(
    "[meta]\nlocale = \"zh-CN\"\n[items]\ncount = { one = \"{n} 项\", other = \"{n} 个项目\" }\n",
  )
  assert_eq(t_count(zh, "items.count", 1), Some("1 个项目"))
}

test "缺失回退到备用目录" {
  let p = parse_catalog("[meta]\nlocale = \"ja\"\n[common]\nsave = \"保存\"\n")
  let f = parse_catalog("[meta]\nlocale = \"en\"\n[common]\nsave = \"Save\"\nclose = \"Close\"\n")
  assert_eq(t_fb(p, f, "common.save"), Some("保存"))
  assert_eq(t_fb(p, f, "common.close"), Some("Close"))
}

test "值里逗号不误切" {
  let en = parse_catalog(
    "[meta]\nlocale = \"en\"\n[misc]\nmsg = { one = \"1, saved\", other = \"n, saved\" }\n",
  )
  assert_eq(t_count(en, "misc.msg", 2), Some("n, saved"))
}
