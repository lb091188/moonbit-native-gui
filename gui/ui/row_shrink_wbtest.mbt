// 回归：行容器里「percent 100 + 折行」的文本件必须可收缩——收缩被停用
// （或引擎把 percent 解析值当 min:auto）时，行内后续兄弟件被顶出容器外，
// 真机表现为「链接点击后 bind 回显不出字」（回显件在窗口外，拖窗不回来）。

///|
test "行容器内折行文本可收缩：bind 回显件不被顶出容器" {
  let lang = @base.Store::new("")
  let bind_w : Ref[@widget.Widget?] = Ref(None)
  let link_a : Ref[@widget.Widget?] = Ref(None)
  let row = row(
    [
      link("打开文档", fn() { lang.set("docs") }, handle=fn(w) { link_a.val = Some(w) }),
      link("帮助中心", fn() { lang.set("help") }),
      text("最近点击：", role=Body),
      bind(lang.signal(), fn(s) { s }, handle=fn(w) { bind_w.val = Some(w) }),
    ],
    column_gap=8.0,
  )
  let root = @widget.Widget::new()
  root.set_size(1100.0, 700.0)
  root.set_column()
  let _ = row.mount_into(root)
  root.relayout(1100.0, 700.0)
  // 点击「打开文档」：bind 由空串换成 "docs"
  match link_a.val {
    Some(la) => {
      let cx = la.rect.x + la.rect.w / 2.0
      let cy = la.rect.y + la.rect.h / 2.0
      let _ = root.dispatch_pointer({ kind: @widget.PointerKind::Move, x: cx, y: cy, button: 0, mods: 0 })
      let _ = root.dispatch_pointer({ kind: @widget.PointerKind::Down, x: cx, y: cy, button: 1, mods: 0 })
      let _ = root.dispatch_pointer({ kind: @widget.PointerKind::Up, x: cx, y: cy, button: 1, mods: 0 })
    }
    None => fail("link handle 未拿到")
  }
  root.relayout(1100.0, 700.0)
  assert_eq(lang.get(), "docs")
  match bind_w.val {
    Some(bw) => {
      // 回显件有内容且完整落在容器内（曾被「最近点击：」顶到 x=1228 > 1100）
      assert_true(bw.rect.w > 0.0)
      assert_true(bw.rect.h > 0.0)
      assert_true(bw.rect.x + bw.rect.w <= 1100.0)
      assert_true(bw.rect.x >= 0.0)
    }
    None => fail("bind handle 未拿到")
  }
}

///|
test "纯 view percent(100) 项在行内溢出时被收缩（引擎 min 收口联动）" {
  let root = @widget.Widget::new()
  root.set_size(1100.0, 700.0)
  root.set_column()
  let r = row(
    [
      view([], width=52.0, height=18.0),
      view([], height=18.0, handle=fn(w : @widget.Widget) {
        w.node.set_width(@yoga.percent(100.0))
      }),
    ],
    column_gap=8.0,
  )
  let _ = r.mount_into(root)
  root.relayout(1100.0, 700.0)
  match root.children().get(0) {
    Some(rw) =>
      match rw.children().get(1) {
        Some(pv) => {
          // percent 项收缩到行内剩余宽，不溢出（min 曾被顶成 1100 时溢出 52）
          assert_eq(pv.rect.w, 1040.0)
          assert_eq(pv.rect.x, 60.0)
        }
        None => fail("percent 子项缺失")
      }
    None => fail("行子项缺失")
  }
}
