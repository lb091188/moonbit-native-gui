// 四半径圆角矩形回归（S3）：4R 路径出像素、不等半径与全等的快路分派同源、
// 半径归一（over-constraint 等比缩小）闭合。

///|
fn near_px(
  bm : Bitmap,
  x : Int32,
  y : Int32,
  r : Int32,
  g : Int32,
  b : Int32,
  tol : Int32,
) -> Bool {
  let px = bm.pixel(x, y)
  (px.r - r).abs() <= tol &&
  (px.g - g).abs() <= tol &&
  (px.b - b).abs() <= tol &&
  px.a > 0
}

///|
test "fill_round_rect4：不等半径四角各自成形" {
  // 40×40 红底块：左上 0（直角）右上 20（大圆）右下 0 左下 0，白底画布
  let bm = Bitmap::new(60, 60)
  let p = Painter::new(bm)
  p.set_fill_color("#ffffff")
  p.fill_rect(0.0, 0.0, 60.0, 60.0)
  p.set_fill_color("#ff0000")
  p.fill_round_rect4(10.0, 10.0, 40.0, 40.0, 0.0, 20.0, 0.0, 0.0)
  p.end()
  // 左上角是直角：贴近角点仍有红
  assert_true(near_px(bm, 11, 11, 255, 0, 0, 8))
  // 右上大圆角：角点外是白（被裁掉）、圆心内侧是红
  assert_true(near_px(bm, 48, 11, 255, 255, 255, 8))
  assert_true(near_px(bm, 40, 14, 255, 0, 0, 40))
}

///|
test "fill_round_rect4：全等半径与单半径版同像素（快路同源）" {
  let bm1 = Bitmap::new(40, 40)
  let p1 = Painter::new(bm1)
  p1.set_fill_color("#00aa55")
  p1.fill_round_rect(2.0, 2.0, 36.0, 36.0, 8.0)
  p1.end()
  let bm2 = Bitmap::new(40, 40)
  let p2 = Painter::new(bm2)
  p2.set_fill_color("#00aa55")
  p2.fill_round_rect4(2.0, 2.0, 36.0, 36.0, 8.0, 8.0, 8.0, 8.0)
  p2.end()
  for y in [2, 10, 20, 30, 37] {
    for x in [2, 10, 20, 30, 37] {
      let a = bm1.pixel(x, y)
      let b = bm2.pixel(x, y)
      assert_true(a.r == b.r && a.g == b.g && a.b == b.b && a.a == b.a)
    }
  }
}

///|
test "round_rect4_path：不等半径描边闭合（角点都描到）" {
  let bm = Bitmap::new(60, 60)
  let p = Painter::new(bm)
  p.set_stroke_color("#0000ff")
  p.set_line_width(2.0)
  p.round_rect4_path(10.0, 10.0, 40.0, 40.0, 12.0, 0.0, 6.0, 0.0)
  p.stroke()
  p.end()
  // 左上圆弧中点附近有蓝墨，右上直角点附近有蓝墨
  assert_true(near_px(bm, 10, 22, 0, 0, 255, 60))
  assert_true(near_px(bm, 49, 10, 0, 0, 255, 60))
}
