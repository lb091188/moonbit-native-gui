// 字距（letter_spacing）的验收：宽增量 = 字符数 × spacing，测量与绘制同源。
// 不断言绝对宽度（随字体配置变），只断言差值与「绘制也吃到字距」。

///|
fn inked_right(bm : @render.Bitmap, w : Int, h : Int) -> Int {
  let mut right = -1
  for y = 0; y < h; y = y + 1 {
    for x = 0; x < w; x = x + 1 {
      if bm.pixel(x, y).a > 0 && x > right {
        right = x
      }
    }
  }
  right
}

test "字距：量宽差 = 字符数 × spacing" {
  let base = Font::new("", 14.0)
  let cases : Array[(String, Int)] = [("a", 1), ("abc", 3), ("中文测", 3), ("hello world", 11)]
  for pair in cases {
    let text = pair.0
    let n = pair.1
    let w0 = match measure_font(text, base) {
      Some(m) => m.width
      None => -1
    }
    if w0 < 0 {
      println("字距: skip (文本后端不可用)")
      continue
    }
    for s in [1.0, 2.0, 4.0] {
      let w = match measure_font(text, Font::new("", 14.0, spacing=s)) {
        Some(m) => m.width
        None => -1
      }
      // 宽是整像素（上取整），差值允许 1px 的累计取整误差
      let want = (n.to_double() * s).to_int()
      let d = w - w0
      assert_eq(
        (d - want).abs() <= 1,
        true,
        msg="字距宽度差不符：\{text} spacing=\{s} 实测差=\{d} 期望=\{want}",
      )
    }
  }
}

test "字距：绘制与测量同源（墨迹右界随字距外扩）" {
  let plain = Font::new("", 14.0)
  let wide = Font::new("", 14.0, spacing=8.0)
  let bm0 = @render.Bitmap::new(200, 40)
  let bm1 = @render.Bitmap::new(200, 40)
  let ok0 = draw_in_box(bm0, 0.0, 0.0, 0.0, 0.0, "iii", plain, "#000000", wrap=false)
  let ok1 = draw_in_box(bm1, 0.0, 0.0, 0.0, 0.0, "iii", wide, "#000000", wrap=false)
  assert_eq(ok0 && ok1, true)
  let r0 = inked_right(bm0, 200, 40)
  let r1 = inked_right(bm1, 200, 40)
  assert_eq(r1 > r0, true, msg="字距没进绘制：右界 \{r1} 未超出 \{r0}")
}

test "字距参与缓存键：同串不同字距不串味" {
  let a = measure_font("abc", Font::new("", 14.0))
  let b = measure_font("abc", Font::new("", 14.0, spacing=3.0))
  match (a, b) {
    (Some(a), Some(b)) => assert_eq(b.width > a.width, true)
    _ => assert_eq(true, true)
  }
}
