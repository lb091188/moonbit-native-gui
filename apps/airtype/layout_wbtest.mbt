// 布局回归：mng 模板页挂载冒烟——airtype() 在 420×560 无头宿主里挂得稳，
// 根容器宽度钉满（宽被内容顶爆的回归面）。

///|
test "布局：mng 模板页挂载冒烟" {
  // 模拟服务已启动的真实地址长度（单行省略口径的回归面）
  s_url.set("http://192.168.0.35:8787/?t=0123456789abcdef0123456789abcdef")
  let t = @uitest.mount_all([airtype()], 420.0, 560.0)
  t.frame()
  t.frame()
  t.frame()
  let top = t.root.children()[0]

  assert_true(top.rect.w > 419.0 && top.rect.w < 421.0)
  assert_true(top.rect.h > 0.0)
}
