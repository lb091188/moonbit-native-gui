// 演示页「过渡与效果」transform 段的真结构复刻：col → scroll_view → col →
// [演示 holder(row 含旋转卡), code_view]。旋转卡的溢出角伸进后画 code_view
// 区域，帧尾溢出带顶层重画应把它压回来（web 根级 stacking context 观感）。

///|
test "真结构复刻：scroll 内旋转卡溢出压过后画 code_view" {
  @theme.theme_apply(@theme.default_theme())
  let card_w : Ref[@widget.Widget?] = Ref(None)
  let card = view([text("常驻旋转")], width=150.0, height=64.0, class=[
    @style.style(
      background_color="#00ff00",
      border_width=1.0,
      rotate=30.0,
    ),
  ], handle=fn(w) { card_w.val = Some(w) })
  let holder = col([row([card], column_gap=24.0)], padding=8.0)
  let code = view(
    [text("let a = 1")],
    width=400.0,
    height=60.0,
    class=[@style.style(background_color="#ffffff")],
  )
  // 双层滚动嵌套（main.mbt 外层横向 + section_body 内层纵向，与演示页同构）
  let inner_scroll = scroll_view(
    [col([holder, code], row_gap=6.0, padding=16.0)],
    ScrollState::new(),
  )
  let (_root, page) = mounted(
    view(
      [scroll_view([col([inner_scroll], padding=8.0)], ScrollState::new(), hscroll=true)],
      width=420.0,
      height=300.0,
    ),
    420.0,
    300.0,
  )
  ignore(_root)
  let cw = match card_w.val {
    Some(w) => w
    None => abort("卡没挂上")
  }
  let bm = @render.Bitmap::new(420, 300)
  let p = @render.Painter::new(bm)
  page.paint(p)
  p.end()
  // 旋转 30° 的溢出角：卡中心正下方、超出卡底边的点——落在 code（后画
  // 白块）区域内。压回来 = 读到卡绿；没压回来 = 读到白。
  let rr = cw.rect
  let cx = (rr.x + rr.w * 0.5).to_int()
  let below = (rr.y + rr.h + 4.0).to_int()
  let c = bm.pixel(cx, below)
  assert_true(
    c.g >= 200 && c.r < 80 && c.b < 80,
    msg="溢出角被 code_view 盖住（\\{c.r},\\{c.g},\\{c.b}），顶层重画没生效",
  )
}
