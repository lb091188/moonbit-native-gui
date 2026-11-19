// 演示页「过渡与效果」transform 段的真结构复刻：col → scroll_view → col →
// [holder(row 内旋转卡), code_view]。默认 overflow:visible：卡的溢出不被
// row/holder 裁；帧尾提升让下带压过后画的 code_view。结构放在深处，
// 重画的坐标口径才会真的被验证（浅层会被「相对父」的错位偶然盖住）。

///|
test "真结构复刻：深层嵌套旋转卡溢出带不被裁、且压过后画 code_view" {
  @theme.theme_apply(@theme.default_theme())
  let card_w : Ref[@widget.Widget?] = Ref(None)
  let card = view([text("常驻旋转")], width=150.0, height=64.0, class=[
    @style.style(
      background_color="#00ff00",
      border_width=1.0,
      rotate=14.0,
    ),
  ], align_items=@yoga.AlignItems::Center, justify_content=@yoga.JustifyContent::Center,
    handle=fn(w) { card_w.val = Some(w) })
  let code = view(
    [text("let a = 1")],
    width=400.0,
    height=60.0,
    corner_radius=0.0,
    class=[@style.style(background_color="#ffffff")],
  )
  // section_body 的 holder：col 紧包 row，无 padding——旧默认裁切下溢出
  // 正好在这里被裁平
  let holder = col([row([card], column_gap=24.0)], row_gap=8.0)
  let inner_scroll = scroll_view(
    [col([view([], height=180.0), holder, code], row_gap=6.0, padding=16.0)],
    ScrollState::new(),
    width=440.0,
    height=420.0,
  )
  let (_root, page) = mounted(
    view([inner_scroll], width=440.0, height=420.0, corner_radius=0.0, class=[
      @style.style(background_color="#ffffff"),
    ]),
    440.0,
    420.0,
  )
  ignore(_root)
  let cw = match card_w.val {
    Some(w) => w
    None => abort("卡没挂上")
  }
  let bm = @render.Bitmap::new(440, 420)
  let p = @render.Painter::new(bm)
  page.paint(p)
  p.end()
  let rr = cw.rect
  // 旋转 14°：上下溢出集中在左右两半、左右溢出集中在上下两半，采样点按
  // 几何取（避开 1px 描边）
  let probes : Array[(Int, Int, String)] = [
    ((rr.x + 30.0).to_int(), (rr.y - 6.0).to_int(), "上带"),
    ((rr.x + 120.0).to_int(), (rr.y + rr.h + 6.0).to_int(), "下带压 code_view"),
    ((rr.x - 2.0).to_int(), (rr.y + rr.h * 0.5 + 8.0).to_int(), "左带"),
    ((rr.x + rr.w + 2.0).to_int(), (rr.y + rr.h * 0.5 - 8.0).to_int(), "右带"),
  ]
  let bad : Array[String] = []
  for pr in probes {
    let (x, y, name) = pr
    let c = bm.pixel(x, y)
    if !(c.g > 200 && c.r < 80) {
      bad.push("\{name}(\{x},\{y})=(\{c.r},\{c.g},\{c.b})")
    }
  }
  let first = if bad.length() > 0 {
    bad[0]
  } else {
    ""
  }
  assert_true(
    bad.length() == 0,
    msg="旋转溢出带被裁（\{first}），卡 rect=\{rr.x},\{rr.y}",
  )
  // 对照：外接矩形之外仍是页面白底，排除「整片都被重画」
  let outside = bm.pixel((rr.x + 30.0).to_int(), (rr.y - 22.0).to_int())
  assert_true(outside.r > 240 && outside.g > 240 && outside.b > 240)
}

///|
test "祖先显式 overflow:Hidden 照裁变换溢出（重画不越裁切）" {
  @theme.theme_apply(@theme.default_theme())
  let card_w : Ref[@widget.Widget?] = Ref(None)
  let card = view([], width=150.0, height=64.0, class=[
    @style.style(
      background_color="#00ff00",
      border_width=1.0,
      rotate=30.0,
    ),
  ], handle=fn(w) { card_w.val = Some(w) })
  // 裁切壳：padding 5，overflow:Hidden——卡的旋转溢出只能在壳内可见
  let clip_box = view([card], padding=5.0, corner_radius=0.0, class=[
    @style.style(background_color="#ffffff", overflow=@style.Hidden),
  ])
  let (_root, page) = mounted(
    view([view([], height=100.0), clip_box], width=400.0, height=300.0, corner_radius=0.0, class=[
      @style.style(background_color="#ffffff"),
    ]),
    400.0,
    300.0,
  )
  ignore(_root)
  let cw = match card_w.val {
    Some(w) => w
    None => abort("卡没挂上")
  }
  let bm = @render.Bitmap::new(400, 300)
  let p = @render.Painter::new(bm)
  page.paint(p)
  p.end()
  let rr = cw.rect
  let x = (rr.x + 30.0).to_int()
  // 壳外（壳顶 = rr.y - 5）虽在旋转外接内，也不该出绿
  let out = bm.pixel(x, (rr.y - 12.0).to_int())
  assert_true(
    out.r > 240 && out.g > 240 && out.b > 240,
    msg="显式 overflow:Hidden 被帧尾重画绕过（\{out.r},\{out.g},\{out.b}）",
  )
  // 壳内（卡顶上方 1px）旋转溢出照常可见
  let inside = bm.pixel(x, (rr.y - 1.0).to_int())
  assert_true(
    inside.g > 200 && inside.r < 80,
    msg="壳内溢出带没画（\{inside.r},\{inside.g},\{inside.b}）",
  )
}
