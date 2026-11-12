// rich_text 可选富文本控件的无头用例：混排文本命中落字符边界、拖选区间
// 就是原文子串、复制串与所见一致。

///|
fn rich_mount(
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
test "rich_text：混排命中落字符边界、拖选区间即原文子串" {
  let src = "富文本ABC混排 selectable"
  let at = @text.AttributedText::new(src, wrap=false)
  at.set_font(@text.Font::new("", 14.0))
  let node = rich_text(at, selectable=true)
  let (root, _w) = rich_mount(node, 400.0, 60.0)
  // 找到挂载后的控件（node.mount_into 返回根，控件在其子树里）
  let target : Ref[@widget.Widget?] = Ref(None)
  fn find(t : @widget.Widget) -> Unit {
    if target.val is None && sel_states.val.get(t.id) is Some(_) {
      target.val = Some(t)
    }
    for k in t.kids {
      find(k)
    }
  }

  find(root)
  let ctl = target.val.unwrap()
  let state = match sel_states.val.get(ctl.id) {
    Some(s) => s
    None => abort("选中态没装起来")
  }
  assert_eq(state.ed.get_text(), src)
  let y = ctl.rect.y + ctl.rect.h / 2.0
  // 字符边界往返：每个字符前缘 x 命中回该边界（字节位只在字符边界有意义）
  let mut cb = 0
  for ch in src {
    let x = at.caret_x(cb, ctl.rect.w, ctl.rect.h)
    assert_true(x is Some(_), msg="caret_x 缺值（b=\{cb}）")
    let back = at.hit(x.unwrap() + 0.5, y, ctl.rect.w, ctl.rect.h)
    assert_eq(
      back,
      Some(cb),
      msg="字符边界 \{cb} 命中没回该边界（回 \{match back { Some(v) => v; None => -1 }}）",
    )
    cb += @utf8.encode(ch.to_string()).length()
  }
  // 拖选：从「富」拖到「ABC」之后——按字符边界坐标驱动指针链
  let b0 = 0
  let b1 = @utf8.encode("富文本ABC").length()
  let x0 = at.caret_x(b0, ctl.rect.w, ctl.rect.h).unwrap()
  let x1 = at.caret_x(b1, ctl.rect.w, ctl.rect.h).unwrap()
  let _ = root.dispatch_pointer({
    kind: @widget.PointerKind::Down,
    x: ctl.rect.x + x0 + 0.5,
    y,
    button: 1,
    mods: 0,
  })
  let _ = root.dispatch_pointer({
    kind: @widget.PointerKind::Move,
    x: ctl.rect.x + x1 + 0.5,
    y,
    button: 0,
    mods: 0,
  })
  let _ = root.dispatch_pointer({
    kind: @widget.PointerKind::Up,
    x: ctl.rect.x + x1 + 0.5,
    y,
    button: 1,
    mods: 0,
  })
  match state.ed.selection() {
    Some((a, b)) => {
      assert_eq(a, b0, msg="拖选起点不在「富」字前缘")
      assert_eq(b, b1, msg="拖选终点不在 C 之后")
      assert_eq(state.ed.get_text_in_range(a, b), "富文本ABC")
    }
    None => abort("拖选没成选区")
  }
  // 非可选档：不装指针、不进登记
  let at2 = @text.AttributedText::new("纯展示", wrap=false)
  at2.set_font(@text.Font::new("", 14.0))
  let (root2, _w2) = rich_mount(rich_text(at2), 400.0, 60.0)
  let none_found = Ref(true)
  fn find2(t : @widget.Widget) -> Unit {
    if sel_states.val.get(t.id) is Some(_) {
      none_found.val = false
    }
    for k in t.kids {
      find2(k)
    }
  }

  find2(root2)
  assert_true(none_found.val, msg="非可选档不该进选中登记")
}
