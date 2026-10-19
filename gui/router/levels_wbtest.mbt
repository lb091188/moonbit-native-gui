// 层级状态与路径回归：首屏取法、goto 的归一化与回落、层数恒定、children_at 随父层
// 变化、同值不重复唤醒与重入不成环、route_at 取当前路径上的节点。

fn t_lf(k : String) -> Route {
  route_leaf(k, fn() -> @widget.Node {
    @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget { w })
  })
}

fn t_br(k : String, kids : Array[Route]) -> Route {
  route_branch(k, kids)
}

///|
/// 「组件」「系统」两支各有「消息框」——跨父重名合法，用它一起验路径解析。
fn t_tree() -> Array[Route] {
  [
    t_br("组件", [t_lf("按钮"), t_lf("消息框")]),
    t_br("系统", [t_lf("托盘"), t_lf("消息框")]),
  ]
}

///|
test "首屏路径 = 首个根一路到首个叶" {
  let r = new_router(t_tree())
  assert_eq(r.level_count(), 2)
  assert_eq(r.path(), "组件/按钮")
}

///|
test "goto 只写一层时深层回落首个候选" {
  let r = new_router(t_tree())
  r.goto("系统")
  assert_eq(r.path(), "系统/托盘")
}

///|
test "goto 一次写多层" {
  let r = new_router(t_tree())
  r.goto("组件/消息框")
  assert_eq(r.path(), "组件/消息框")
  r.goto("系统/消息框")
  assert_eq(r.path(), "系统/消息框")
}

///|
test "找不到的段回落该层首项，超深的段忽略" {
  let r = new_router(t_tree())
  r.goto("没这页/按钮/多余")
  assert_eq(r.path(), "组件/按钮")
  r.goto("系统/没这段")
  assert_eq(r.path(), "系统/托盘")
  assert_eq(r.resolve("").length(), r.level_count())
}

///|
test "resolve 长度恒等于层数" {
  let r = new_router(t_tree())
  assert_eq(r.resolve("组件/按钮"), ["组件", "按钮"])
  assert_eq(r.resolve("组件"), ["组件", "按钮"])
  assert_eq(r.resolve(""), ["组件", "按钮"])
  assert_eq(r.resolve("系统/消息框/多余/再多").length(), 2)
}

///|
test "children_at 给的是当前父路径下的候选短名" {
  let r = new_router(t_tree())
  assert_eq(r.children_at(0), ["组件", "系统"])
  assert_eq(r.children_at(1), ["按钮", "消息框"])
  r.goto("系统")
  assert_eq(r.children_at(1), ["托盘", "消息框"])
  assert_eq(r.children_at(2), [])
  assert_eq(r.children_at(-1), [])
}

///|
test "同值整条路径不重复唤醒" {
  let r = new_router(t_tree())
  let mut hits = 0
  r.store_at(0).subscribe(fn(_v : String) -> Unit { hits += 1 })
  r.goto("组件/按钮")
  assert_eq(hits, 0)
  r.goto("组件/消息框")
  assert_eq(hits, 0)
  r.goto("系统")
  assert_eq(hits, 1)
}

///|
test "订阅里再 goto 不成环" {
  let r = new_router(t_tree())
  let mut hits = 0
  r.store_at(0).subscribe(fn(_v : String) -> Unit {
    hits += 1
    r.goto("系统/托盘")
  })
  r.goto("系统/托盘")
  assert_eq(hits, 1)
  assert_eq(r.path(), "系统/托盘")
}

///|
test "route_at 取当前路径上的节点" {
  let r = new_router(t_tree())
  r.goto("系统/消息框")
  assert_eq(
    match r.route_at(0) {
      Some(x) => x.key
      None => "取空"
    },
    "系统",
  )
  assert_eq(
    match r.route_at(1) {
      Some(x) => x.key
      None => "取空"
    },
    "消息框",
  )
  assert_true(r.route_at(2) is None)
  assert_true(r.route_at(-1) is None)
}
