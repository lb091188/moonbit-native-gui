// extract 内核测试。

test "scan_keys 抓 t 系列、避开 emit 误匹配" {
  let src =
    "let x = t(\"common.ok\")\nignore(t_with(\"error.nf\", vars))\nignore(t_count(\"items.count\", n))\nignore(emit(\"fake\"))\n@i18n.t(\"dotted.key\")\n"
  let keys = scan_keys(src)
  assert_eq(has(keys, "common.ok"), true)
  assert_eq(has(keys, "error.nf"), true)
  assert_eq(has(keys, "items.count"), true)
  assert_eq(has(keys, "dotted.key"), true)
  assert_eq(has(keys, "fake"), false)
}

test "diff 出缺失与残项" {
  let (missing, unused) = diff(["a", "b"], ["b", "c"])
  assert_eq(missing, ["a"])
  assert_eq(unused, ["c"])
}

test "defined_keys 排除 meta.*" {
  let cat = parse_catalog("[meta]\nlocale = \"en\"\n[common]\nok = \"OK\"\n")
  let dk = defined_keys(cat)
  assert_eq(has(dk, "common.ok"), true)
  assert_eq(has(dk, "meta.locale"), false)
}
