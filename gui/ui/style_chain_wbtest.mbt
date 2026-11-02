// 样式归一链回归：默认 < 属性（构造参数）< class（后者覆盖）；字号在测量与
// 绘制走同一份 resolved 样式（文本件不留默认层，初始值走文本源 13）。

///|
fn chain_mount(node : @widget.Node) -> @widget.Widget {
  let root = @widget.Widget::new()
  root.set_column()
  root.set_size(600.0, 400.0)
  root.node.set_align_items(@yoga.AlignItems::FlexStart)
  let kid = node.mount_into(root)
  root.relayout(600.0, 400.0)
  kid
}

///|
fn chain_widget(reg : Ref[@widget.Widget?]) -> @widget.Widget {
  match reg.val {
    Some(w) => w
    None => abort("handle 未回调")
  }
}

///|
test "字号三层：默认（文本源 13）< 属性 < class，且 class 改测量高" {
  let a : Ref[@widget.Widget?] = Ref(None)
  let kid0 = chain_mount(text("abc", handle=fn(w) { a.val = Some(w) }))
  assert_eq(@style.style_for(chain_widget(a)).font_size, None)
  let h0 = kid0.rect.h
  let b : Ref[@widget.Widget?] = Ref(None)
  let kid1 = chain_mount(
    text("abc", class=[@style.style(font_size=20.0)], handle=fn(w) { b.val = Some(w) }),
  )
  assert_eq(@style.style_for(chain_widget(b)).font_size, Some(20.0))
  assert_true(kid1.rect.h > h0)
  // 属性层（font_size=16）低于 class（20）——class 赢
  let c : Ref[@widget.Widget?] = Ref(None)
  let kid2 = chain_mount(
    text(
      "abc",
      font_size=16.0,
      class=[@style.style(font_size=20.0)],
      handle=fn(w) { c.val = Some(w) },
    ),
  )
  assert_eq(@style.style_for(chain_widget(c)).font_size, Some(20.0))
  assert_true(kid2.rect.h == kid1.rect.h)
  // 只给属性：16 生效，且高于默认
  let d : Ref[@widget.Widget?] = Ref(None)
  let kid3 = chain_mount(text("abc", font_size=16.0, handle=fn(w) { d.val = Some(w) }))
  assert_eq(@style.style_for(chain_widget(d)).font_size, Some(16.0))
  assert_true(kid3.rect.h > h0 && kid3.rect.h < kid1.rect.h)
}

///|
test "按钮：默认块给 13，属性/class 依次覆盖（绘制与测量同源）" {
  let a : Ref[@widget.Widget?] = Ref(None)
  let kid0 = chain_mount(button("x", handle=fn(w) { a.val = Some(w) }))
  assert_eq(@style.style_for(chain_widget(a)).font_size, Some(13.0))
  let h0 = kid0.rect.h
  let b : Ref[@widget.Widget?] = Ref(None)
  let kid1 = chain_mount(
    button("x", class=[@style.style(font_size=20.0)], handle=fn(w) { b.val = Some(w) }),
  )
  assert_eq(@style.style_for(chain_widget(b)).font_size, Some(20.0))
  // 高度由按钮样式定（control_height），字号变大不改盒高——与旧口径一致
  assert_true(kid1.rect.h == h0)
}
