// 检查器客户端纯函数用例：slug 净化与 socket 路径（与单实例客户端同规）。

///|
test "insp_slug：净化、截断加哈希" {
  assert_eq(insp_slug("a b/c"), "a_b_c")
  let long = insp_slug("x-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa")
  assert_true(long.length() < 60)
  assert_true(long.contains("-"))
}

///|
test "insp_strip_trailing_slash：mac TMPDIR 尾斜杠归一" {
  assert_eq(insp_strip_trailing_slash("/var/folders/x/T/"), "/var/folders/x/T")
  assert_eq(insp_strip_trailing_slash("/"), "/")
}

///|
test "insp_socket_path：前缀、uid 尾与预算内" {
  let p = insp_socket_path("libyue.hello")
  assert_true(p.contains("/moonbit-inspect-"))
  assert_true(p.has_suffix(".sock"))
  assert_true(!p.contains("libyue.hello"))
  assert_true(p.length() < 140)
}

///|
test "call_begin：超长请求同步拒绝（不发起线程）" {
  let b = StringBuilder()
  let mut i = 0
  while i < REQUEST_CAP + 1 {
    b.write_string("x")
    i += 1
  }
  match call_begin("app", b.to_string()) {
    Err(e) => assert_true(e.contains("4096"))
    Ok(_) => fail("超长请求应拒绝")
  }
}

///|
test "call_take：没有在途请求时报错" {
  match call_take() {
    Err(e) => assert_true(e.contains("没有在途") || e.contains("errno"))
    Ok(_) => fail("无在途请求不该有结果")
  }
}
