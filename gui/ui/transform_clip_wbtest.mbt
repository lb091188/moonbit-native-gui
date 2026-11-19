// 真组件复刻「过渡与效果」页 transform 段：hover 放大卡的溢出带不被父级
// 默认裁切限制范围（web overflow 默认 visible 观感）。像素级断言。

///|
fn tf_bm(w : @widget.Widget, wpx : Int32, hpx : Int32) -> @render.Bitmap {
  let bm = @render.Bitmap::new(wpx, hpx)
  let p = @render.Painter::new(bm)
  w.paint_at(p, w.rect.x, w.rect.y)
  // paint_at 直画不经 paint 尾收帧：登记的变换溢出带要显式消费，否则残留
  // 到下一次帧收尾被误重画
  @widget.finish_frame_paint(p)
  p.end()
  bm
}

///|
test "hover 放大：溢出带越过 row 矩形仍可见（演示页复刻）" {
  @theme.theme_apply(@theme.default_theme())
  let card_w : Ref[@widget.Widget?] = Ref(None)
  let card = view([text("悬停放大")], width=150.0, height=64.0, class=[
    @style.style(
      background_color="#f0f0f0",
      border_color="#888888",
      border_width=1.0,
      border_radius=8.0,
      transition_ms=0.0,
    ).hover(scale_x=2.0, scale_y=2.0),
  ], handle=fn(w) { card_w.val = Some(w) })
  let (_root, page) = mounted(
    view([row([card], column_gap=24.0, align_items=@yoga.AlignItems::Center)], padding=20.0),
    400.0,
    140.0,
  )
  ignore(_root)
  let cw = match card_w.val {
    Some(w) => w
    None => abort("卡没挂上")
  }
  // 布局先落：卡在 row 内，row 有 20 内边距
  cw.hovered = true
  let bm = tf_bm(page, 400, 140)
  let rr = cw.rect

  // 放大 2× 后的顶边中心：卡顶上方 (cx, cy - h - 2)——row 顶之外
  let cx = (rr.x + rr.w * 0.5).to_int()
  // 放大 2× 后卡顶 = 中心 y - 卡高（rr.y - rr.h*0.5，位图外）；取位图内的
  // 溢出带：row 顶（=卡顶原位）上方、卡外接内的点
  let top = (rr.y - 6.0).to_int()
  let c = bm.pixel(cx, top)
  assert_true(
    c.r > 200 && c.g > 200,
    msg="放大溢出带被裁（\{c.r},\{c.g},\{c.b}），父级裁切没放行变换子件",
  )
}
