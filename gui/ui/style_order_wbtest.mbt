// 样式全序回归：继承 < 默认（组件内置）< 属性（构造散参数）< class < style
// （组件收的显式规则块）。断言读解析后的样式槽与实排宽度，不锁具体色值。

///|
fn mount_box(
  node : @widget.Node,
  w : Double,
  h : Double,
) -> (@widget.Widget, @widget.Widget) {
  let root = @widget.Widget::new()
  root.set_size(w, h)
  root.set_column()
  root.node.set_align_items(@yoga.AlignItems::FlexStart)
  let kid = node.mount_into(root)
  root.relayout(w, h)
  (root, kid)
}

///|
fn color_var(w : @widget.Widget) -> String {
  match @style.style_for(w).color {
    Some(@style.Var(name)) => name
    _ => ""
  }
}

///|
test "文字全序：属性 < class，class < style（显式块）" {
  let sig = @base.Signal::new("hello")
  // 属性层散参数被 class 盖过
  let (_r1, w1) = mount_box(
    text_dyn(sig, color="primary", class=[@style.style(color="danger")]),
    120.0,
    20.0,
  )
  assert_eq(color_var(w1), "danger")
  // 显式规则块（组件的 style/anon 参数）压在 class 之上
  let (_r2, w2) = mount_box(
    text_dyn(
      sig,
      color="primary",
      class=[@style.style(color="danger")],
      anon=@style.style(color="text_secondary"),
    ),
    120.0,
    20.0,
  )
  assert_eq(color_var(w2), "text_secondary")
}

///|
test "布局全序：散参数落进属性层，class 与 style 逐级盖过" {
  // 散参数折进属性层（样式槽读得到，class/style 才盖得住）
  let (_r1, w1) = mount_box(
    hover_group([], width=60.0, padding=6.0),
    200.0,
    40.0,
  )
  assert_eq(@style.style_for(w1).width, Some(60.0))
  assert_eq(@style.style_for(w1).padding_left, Some(6.0))
  assert_eq(w1.rect.w, 60.0)
  // class 盖过散参数
  let (_r2, w2) = mount_box(
    hover_group([], width=60.0, class=[@style.style(width=90.0)]),
    200.0,
    40.0,
  )
  assert_eq(w2.rect.w, 90.0)
  // style 层盖过 class
  let (_r3, w3) = mount_box(
    text_dyn(
      @base.Signal::new("hi"),
      class=[@style.style(width=70.0)],
      anon=@style.style(width=100.0),
    ),
    200.0,
    20.0,
  )
  assert_eq(w3.rect.w, 100.0)
}
