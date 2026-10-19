// 路由表构造期契约回归：同父重名、跨父重名合法、叶/分支的 build 归属、空键、
// 同父深度不齐、层数读法。

fn dummy_node() -> @widget.Node {
  @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget { w })
}

fn lf(k : String) -> Route {
  route_leaf(k, dummy_node)
}

fn br(k : String, kids : Array[Route]) -> Route {
  route_branch(k, kids)
}

///|
test "同父重名被拒，跨父重名合法" {
  let cross_parent_ok = [
    br("组件", [lf("消息框"), lf("横幅")]),
    br("系统", [lf("消息框")]),
  ]
  assert_eq(tree_errors(cross_parent_ok).length(), 0)
  let same_parent_dup = [br("组件", [lf("消息框"), lf("消息框")])]
  let errs = tree_errors(same_parent_dup)
  assert_eq(errs.length(), 1)
  assert_true(errs[0].has_prefix("同父重名"))
}

///|
test "叶必须有 build，分支不得带 build" {
  let leaf_no_build : Array[Route] = [
    { key: "空手叶", children: [], build: None, load: None, evict: None },
  ]
  let errs = tree_errors(leaf_no_build)
  assert_eq(errs.length(), 1)
  assert_true(errs[0].has_prefix("空节点"))
  let branch_with_build : Array[Route] = [
    {
      key: "多手分支",
      children: [lf("子")],
      build: Some(dummy_node),
      load: None,
      evict: None,
    },
  ]
  let errs2 = tree_errors(branch_with_build)
  assert_eq(errs2.length(), 1)
  assert_true(errs2[0].has_prefix("分支节点不该带 build"))
}

///|
test "空键与分隔符键被拒" {
  let errs = tree_errors([lf(""), lf("/")])
  assert_eq(errs.length(), 2)
  assert_true(errs[0].has_prefix("键为空"))
  assert_true(errs[1].has_prefix("键不能是分隔符"))
}

///|
test "同层叶与分支混排算不齐" {
  let errs = tree_errors([lf("单页"), br("有子页", [lf("段")])])
  assert_eq(errs.length(), 1)
  assert_true(errs[0].has_prefix("同父深度不齐"))
}

///|
test "路由表为空被拒" {
  assert_eq(tree_errors([]).length(), 1)
}

///|
test "同父深度不齐被拒" {
  let unbalanced = [
    br("甲", [lf("一段")]),
    br("乙", [br("下层", [lf("三段")])]),
  ]
  let errs = tree_errors(unbalanced)
  assert_eq(errs.length(), 1)
  assert_true(errs[0].has_prefix("同父深度不齐"))
}

///|
test "层数 = 树深，叶为 1 层" {
  let two_levels = [br("页", [lf("段一"), lf("段二")]), br("另一页", [lf("段")])]
  assert_eq(two_levels[0].depth(), 2)
  assert_eq(two_levels[1].depth(), 2)
  assert_eq(tree_depth(two_levels), 2)
  assert_eq(tree_depth([lf("只有页"), lf("另一页")]), 1)
  assert_true(lf("叶").is_leaf())
  assert_true(!br("分支", [lf("叶")]).is_leaf())
}

///|
test "违规一次报全，不短路" {
  let errs = tree_errors([br("甲", [lf("重"), lf("重")]), br("乙", [lf("消息框")])])
  // 「乙/消息框」跨父合法，只有「甲」下同父重名一条
  assert_eq(errs.length(), 1)
}
