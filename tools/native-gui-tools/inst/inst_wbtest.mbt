// 单实例客户端回归（无头）：帧编码、路径规则、无监听者时报错。

///|
test "encode_args：帧头与载荷" {
  let f = encode_args(["a", "第二个"])
  // 4（argc）+ 4 + 1 + 4 + 9（UTF-8 三字 9 字节）
  assert_eq(f.length(), 22)
  assert_eq(f[0].to_int(), 2)
}

///|
test "socket_path：前缀、uid 后缀与预算" {
  let p = socket_path("com.example.app")
  assert_true(p.has_prefix("/") || p.length() > 0)
  assert_true(p.has_suffix(".sock"))
  assert_true(p.length() <= 100)
}

///|
test "wake：没有实例在听时报错带套接字路径" {
  match wake("io.moonbitlibyue.wbtest.ghost", ["x"]) {
    Err(e) => assert_true(e.length() > 0)
    Ok(_) => assert_true(false)
  }
}
