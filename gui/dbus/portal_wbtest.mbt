// portal 通用层的无头回归：只钉纯函数面（sender 段派生 / token 唯一性 /
// request 路径形态）。Request/Response 的活线路由要有真 portal 前端，归
// 真机清单（GNOME 48+/KDE 5.27+ 的 Wayland 会话）。

///|
test "portal：sender 段按前端口径派生（去冒号、点换下杠）" {
  // 本机 frontend 1.18.4 实物抓包：:1.850 → 1_850
  assert_eq(portal_sender_seg(":1.42"), "1_42")
  assert_eq(portal_sender_seg(":1.850"), "1_850")
  assert_eq(portal_sender_seg(":2.0"), "2_0")
}

///|
test "portal：token 进程内唯一、request 路径拼装正确" {
  let a = portal_next_token()
  let b = portal_next_token()
  assert_true(a != b, msg="token 重复：\{a}")
  assert_true(a.has_prefix("mng"), msg="token 形态不对：\{a}")
  // 路径 = 前缀 + sender 段 + token（sender 段此时可能为空串——测试进程
  // 未连总线；路径形态仍然要拼对）
  let path = portal_request_path(a)
  assert_true(path.has_prefix(PORTAL_REQUEST_PREFIX), msg=path)
  assert_true(path.has_suffix("/\{a}"), msg=path)
}
