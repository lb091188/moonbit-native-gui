// iconfont 运行时加载器回归：解析 [icons]、装入、查表、计数。

test "parse_icons 只取 [icons] 段的键值" {
  let text =
    "# 头\n[icons]\n\"home\" = \"M-1000,-1000L0,0Z\"\n\"tri\" = \"M-1000,0C-667,-800,-333,-800,0,0Z\"\n[other]\n\"x\" = \"should-be-ignored\"\n"
  let entries = parse_icons(text)
  assert_eq(entries.length(), 2)
  assert_eq(entries[0].0, "home")
  assert_eq(entries[0].1, "M-1000,-1000L0,0Z")
}

test "iconfont_load 覆盖旧表并可查" {
  let n = iconfont_load("[icons]\n\"a\" = \"M0,0L1,1Z\"\n\"b\" = \"M2,2Z\"\n")
  assert_eq(n, 2)
  assert_eq(iconfont_count(), 2)
  assert_eq(iconfont_get("a"), Some("M0,0L1,1Z"))
  assert_eq(iconfont_get("nope"), None)
  // 覆盖
  let m = iconfont_load("[icons]\n\"only\" = \"M0,0Z\"\n")
  assert_eq(m, 1)
  assert_eq(iconfont_count(), 1)
  assert_eq(iconfont_get("a"), None)
}
