// 检查器客户端纯函数用例：slug 净化与 socket 路径（与单实例客户端同规）。

///|
test "insp_slug：净化、截断加哈希" {
  assert_eq(insp_slug("a b/c"), "a_b_c")
  let long = insp_slug("x-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
  assert_true(long.length() < 60)
  assert_true(long.contains("-"))
}

///|
test "insp_socket_path：前缀、uid 尾与预算内" {
  let p = insp_socket_path("libyue.hello")
  assert_true(p.contains("/moonbit-inspect-"))
  assert_true(p.has_suffix(".sock"))
  assert_true(!p.contains("libyue.hello"))
  assert_true(p.length() < 140)
}
