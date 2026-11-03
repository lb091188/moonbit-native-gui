// GPU 地基回归：探测不抛错、详情可打印；没装归档是「不可用」而不是失败。

///|
test "probe：无归档时如实报不可用，且详情是给人看的" {
  let p = probe()
  // 两种环境都必须给一句可读的 detail（装了的报 loaded(路径)，没装的报
  // not-found: 原因），不允许空串把问题藏起来
  assert_true(p.detail.length() > 0, msg="探测详情不能为空")
  if p.loaded {
    assert_true(
      p.detail.has_prefix("loaded"),
      msg="可用时详情应以 loaded 开头：\{p.detail}",
    )
  } else {
    assert_true(
      p.detail.has_prefix("not-found") || p.detail.has_prefix("env-lib"),
      msg="不可用时详情应说明缺什么：\{p.detail}",
    )
  }
}

///|
test "probe：同进程内二次探测幂等" {
  let a = probe()
  let b = probe()
  assert_eq(a.loaded, b.loaded)
  assert_eq(a.detail, b.detail)
}
