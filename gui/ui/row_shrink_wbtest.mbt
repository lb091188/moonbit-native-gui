// 回归：行容器里的文本件走 flex 0 1 auto（文本件口径定案，折行档不再钉
// percent 100）——定案前两代坑：① percent+停收缩把回显件顶出容器外；
// ② percent 收缩到「行内剩余宽」后留下空盒，回显被推到行尾（真机
// 「最近点击：help」中间隔一整段占位）。两代症状都由本条钉死。

///|
test "行容器内文本件紧贴排布：bind 回显贴着标签，不顶出也不留占位" {
  let lang = @base.Store::new("")
  let bind_w : Ref[@widget.Widget?] = Ref(None)
  let link_a : Ref[@widget.Widget?] = Ref(None)
  let label_w : Ref[@widget.Widget?] = Ref(None)
  let row = row(
    [
      link("打开文档", fn() { lang.set("docs") }, handle=fn(w) { link_a.val = Some(w) }),
      link("帮助中心", fn() { lang.set("help") }),
      text("最近点击：", handle=fn(w) { label_w.val = Some(w) }),
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
      // 紧贴标签：回显左缘 = 标签右缘 + 行间隙（±1px），不留 flex 占位
      match label_w.val {
        Some(lw) => {
          assert_true(lw.rect.w < 120.0)
          assert_true(bw.rect.x - (lw.rect.x + lw.rect.w) <= 9.0)
          assert_true(bw.rect.x - (lw.rect.x + lw.rect.w) >= 7.0)
        }
        None => fail("标签 handle 未拿到")
      }
    }
    None => fail("bind handle 未拿到")
  }
}

///|
test "文本件口径：缺省折行按可用宽排，单行档收缩让宽不溢出" {
  if !ui_text_guard() {
    return
  }
  let long =
    "这段文字足够长，在窄容器里应当折行或收缩让位，而不是撑破容器，也不再留整行的 flex 占位。"
  // 缺省即折行：真实列（缺省 stretch 给确定宽）里 200 宽排成多行。
  // 不用 `mounted` 助手——它把 align_items 定成 FlexStart，列自己缩到
  // max-content，量不到块级跟随这条真语境（CSS shrink-to-fit 同口径）。
  let root = @widget.Widget::new()
  root.set_size(200.0, 300.0)
  root.set_column()
  let tv = text(long).mount_into(root)
  root.relayout(200.0, 300.0)
  assert_true(tv.rect.w <= 200.0)
  assert_true(tv.rect.h > 40.0)
  // 单行档：自然宽远超行内剩余，收缩让位（曾被顶出容器或整段占位）。
  // 行同样直挂确定宽根，避开 shrink-to-fit 让行自己长到内容宽。
  let root2 = @widget.Widget::new()
  root2.set_size(200.0, 60.0)
  root2.set_column()
  let rw = row([view([], width=180.0, height=18.0), text(long, wrap=false)])
         .mount_into(root2)
  root2.relayout(200.0, 60.0)
  match rw.children().get(1) {
    Some(t) => {
      assert_true(t.rect.w < 200.0)
      assert_true(t.rect.x + t.rect.w <= 200.0)
    }
    None => fail("行内单行文本缺失")
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
