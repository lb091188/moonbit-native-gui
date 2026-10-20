// 原地重挂回归：remount_all 重建树但停在原页；i18n 广播驱动 localize_remount。

///|
fn rm_lf(k : String, hits : Ref[Int]) -> Route {
  route_leaf(k, fn() -> @widget.Node {
    hits.val += 1
    @ui.text("内容", role=@ui.Body)
  })
}

///|
test "remount_all：当前页原地重建，路径与挂载表回到自洽态" {
  let hits = Ref(0)
  let tree = [
    route_branch("组件", [rm_lf("按钮", hits), rm_lf("消息框", hits)]),
    route_branch("系统", [rm_lf("托盘", hits), rm_lf("通知", hits)]),
  ]
  let r = new_router(tree)
  let root = @widget.Widget::new()
  root.set_size(1200.0, 800.0)
  root.set_column()
  let _ = r.view(None).mount_into(root)
  root.relayout(1200.0, 800.0)
  assert_eq(hits.val, 1)
  r.goto("系统/托盘")
  assert_eq(hits.val, 2)
  assert_true(r.is_mounted("系统/托盘"))
  r.remount_all()
  // 重建分支壳 + 当前叶两层，选中路径不变
  assert_eq(hits.val, 3)
  assert_eq(r.path(), "系统/托盘")
  assert_true(r.is_mounted("系统/托盘"))
}

///|
/// 预建过但没点开过的页只活在缓存里：重挂必须把它一起丢掉，否则下次点开复用的是旧语言节点。
test "remount_all：未挂载的预建页一并丢缓存，再点开按当前目录重建" {
  let hits = Ref(0)
  let r = new_router([rm_lf("甲", hits), rm_lf("乙", hits)])
  let root = @widget.Widget::new()
  root.set_size(600.0, 400.0)
  root.set_column()
  let _ = r.view(None).mount_into(root)
  root.relayout(600.0, 400.0)
  // 「乙」相当于空闲预建的产物：建进缓存，但从未挂上树
  let _ = r.build_now("乙")
  assert_eq(hits.val, 2)
  assert_true(r.is_built("乙"))
  r.remount_all()
  assert_false(r.is_built("乙"))
  // 点开时才重建，thunk 再跑一次
  r.goto("乙")
  assert_true(r.is_built("乙"))
  assert_eq(hits.val, 4)
}

///|
test "localize_remount：换目录广播即原地重挂" {
  let hits = Ref(0)
  let r = new_router([rm_lf("页", hits)])
  let root = @widget.Widget::new()
  root.set_size(400.0, 300.0)
  root.set_column()
  let _ = r.view(None).mount_into(root)
  root.relayout(400.0, 300.0)
  assert_eq(hits.val, 1)
  r.localize_remount()
  @i18n.i18n_load("[meta]\nlocale = \"en\"\n")
  assert_eq(hits.val, 2)
  @i18n.i18n_reset()
  assert_eq(hits.val, 3)
  // 重复登记替换：再来一次广播只重挂一次
  r.localize_remount()
  @i18n.i18n_load("[meta]\nlocale = \"en\"\n")
  assert_eq(hits.val, 4)
  @i18n.i18n_reset()
}
