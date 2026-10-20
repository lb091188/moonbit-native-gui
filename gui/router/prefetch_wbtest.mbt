// 空闲预建回归：先序环形队列、当前路径插队、thunk 只跑一次、Lazy/Eager 策略、
// 换页重新锚定、建完停链。队列都用 `prefetch_step` 逐拍手动驱动（不起定时器）。

fn pf_node() -> @widget.Node {
  @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget { w })
}

fn pf_lf(k : String, hits : Ref[Int]) -> Route {
  route_leaf(k, fn() -> @widget.Node {
    hits.val += 1
    pf_node()
  })
}

fn pf_lazy(k : String, hits : Ref[Int]) -> Route {
  route_leaf(k, fn() -> @widget.Node {
    hits.val += 1
    pf_node()
  }, load=Lazy)
}

fn pf_eager(k : String, hits : Ref[Int]) -> Route {
  route_leaf(k, fn() -> @widget.Node {
    hits.val += 1
    pf_node()
  }, load=Eager)
}

fn pf_br(k : String, kids : Array[Route]) -> Route {
  route_branch(k, kids)
}

///|
/// 三层等深树，先序叶序为：甲/子/a1、甲/子/a2、甲/丑/a3、甲/丑/a4、
/// 乙/子/b1、乙/子/b2、乙/丑/b3、乙/丑/b4。
fn pf_tree(hits : Ref[Int]) -> Array[Route] {
  [
    pf_br("甲", [
      pf_br("子", [pf_lf("a1", hits), pf_lf("a2", hits)]),
      pf_br("丑", [pf_lf("a3", hits), pf_lf("a4", hits)]),
    ]),
    pf_br("乙", [
      pf_br("子", [pf_lf("b1", hits), pf_lf("b2", hits)]),
      pf_br("丑", [pf_lf("b3", hits), pf_lf("b4", hits)]),
    ]),
  ]
}

///|
test "首屏插队 + 先序环形逐拍" {
  let hits = Ref(0)
  let r = new_router(pf_tree(hits))
  assert_eq(r.path(), "甲/子/a1")
  r.ensure_current()
  assert_eq(hits.val, 1)
  assert_true(r.is_built("甲/子/a1"))
  r.reanchor()
  assert_true(r.prefetch_step())
  assert_true(r.is_built("甲/子/a2"))
  assert_true(r.prefetch_step())
  assert_true(r.is_built("甲/丑/a3"))
  assert_eq(hits.val, 3)
  assert_eq(r.pending_count(), 5)
}

///|
test "同一节点的 thunk 只跑一次" {
  let hits = Ref(0)
  let r = new_router(pf_tree(hits))
  let _ = r.build_now("甲/子/a1")
  let _ = r.build_now("甲/子/a1")
  r.ensure_current()
  assert_eq(hits.val, 1)
  assert_true(r.built_node("甲/子/a1") is Some(_))
  assert_true(r.built_node("甲/子/a2") is None)
}

///|
test "Lazy 节点不进空闲队列" {
  let hits = Ref(0)
  let roots = [
    pf_br("甲", [pf_br("子", [pf_lf("a1", hits), pf_lazy("a2", hits)])]),
    pf_br("乙", [pf_br("子", [pf_lf("b1", hits), pf_lf("b2", hits)])]),
  ]
  let r = new_router(roots)
  r.ensure_current()
  r.reanchor()
  let mut more = true
  let mut steps = 0
  while more && steps < 10 {
    more = r.prefetch_step()
    steps += 1
  }
  assert_false(r.is_built("甲/子/a2"))
  assert_true(r.is_built("乙/子/b2"))
  assert_eq(r.pending_count(), 0)
  // 重新锚定之后也一样：被豁免的 Lazy 节点不算欠账
  r.goto("甲/子")
  r.ensure_current()
  r.reanchor()
  assert_eq(r.pending_count(), 0)
  assert_false(r.is_built("甲/子/a2"))
}

///|
test "默认策略 Lazy 时整棵树都不预建" {
  let hits = Ref(0)
  let r = new_router(pf_tree(hits), default_load=Lazy)
  r.ensure_current()
  r.reanchor()
  assert_false(r.prefetch_step())
  assert_eq(r.pending_count(), 0)
  assert_eq(hits.val, 1)
}

///|
test "Eager 只由启动那一步建，跟空闲队列无关" {
  let hits = Ref(0)
  let roots = [
    pf_br("甲", [pf_br("子", [pf_lf("a1", hits), pf_lf("a2", hits)])]),
    pf_br("乙", [pf_br("子", [pf_eager("b1", hits), pf_lf("b2", hits)])]),
  ]
  let r = new_router(roots)
  r.build_eager()
  assert_true(r.is_built("乙/子/b1"))
  assert_false(r.is_built("甲/子/a1"))
  assert_eq(hits.val, 1)
}

///|
test "换页后重新锚定，就近先建" {
  let hits = Ref(0)
  let r = new_router(pf_tree(hits))
  r.ensure_current()
  r.reanchor()
  let _ = r.prefetch_step()
  r.goto("乙/丑")
  assert_eq(r.path(), "乙/丑/b3")
  r.ensure_current()
  r.reanchor()
  assert_true(r.is_built("乙/丑/b3"))
  let _ = r.prefetch_step()
  assert_true(r.is_built("乙/丑/b4"))
}

///|
test "建完停链" {
  let hits = Ref(0)
  let r = new_router(pf_tree(hits))
  r.ensure_current()
  r.reanchor()
  let mut more = true
  let mut steps = 0
  while more && steps < 20 {
    more = r.prefetch_step()
    steps += 1
  }
  assert_false(more)
  assert_eq(r.pending_count(), 0)
  // 全树 8 个叶，首屏那个已建，剩 7 个逐拍建完
  assert_eq(hits.val, 8)
}
