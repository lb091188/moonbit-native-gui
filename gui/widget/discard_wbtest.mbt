// 控件丢弃回调回归：换树（clear_children / remove_child）时整棵子树里
// 装了 on_discard 的控件逐只触发——播放引擎这类闭包私有资源靠它停摆，
// 漏触发就是「换载后旧音频继续解码播放」那族 bug 的根。

///|
test "clear_children 触发子树逐只丢弃回调（父先于子，含根本身）" {
  let order : Array[String] = []
  let root = Widget::new()
  let child = Widget::new()
  let grand = Widget::new()
  child.append_child(grand)
  child.on_discard = Some(fn(_w) { order.push("child") })
  grand.on_discard = Some(fn(_w) { order.push("grand") })
  root.append_child(child)
  root.clear_children()
  // 递归序：先报父再进子；没装回调的控件静默跳过
  assert_eq(order, ["child", "grand"])
}

///|
test "remove_child 只触发被摘子树的回调，树上兄弟不受牵连" {
  let hits : Array[String] = []
  let root = Widget::new()
  let kept = Widget::new()
  let dropped = Widget::new()
  kept.on_discard = Some(fn(_w) { hits.push("kept") })
  dropped.on_discard = Some(fn(_w) { hits.push("dropped") })
  root.append_child(kept)
  root.append_child(dropped)
  let _ = root.remove_child(dropped)
  assert_eq(hits, ["dropped"])
  // 再清空时才轮到留下的那个
  root.clear_children()
  assert_eq(hits, ["dropped", "kept"])
}

///|
test "丢弃幂等：摘下后再 clear 同一棵引用不会二次触发" {
  let n : Ref[Int] = Ref(0)
  let root = Widget::new()
  let child = Widget::new()
  child.on_discard = Some(fn(_w) { n.val = n.val + 1 })
  root.append_child(child)
  root.clear_children()
  root.clear_children()
  assert_eq(n.val, 1)
}
