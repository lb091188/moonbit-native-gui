// 背景渐变回归（S2）：spec 构造与 merge、token stop 绘制期落色、
// 不足两 stop 回落 false。

///|
test "gradient_spec：构造、stop 钳制、merge 传递" {
  let g = gradient_linear(0.0, 0.0, 0.0, 1.0)
  g.add_stop(-0.5, "primary")
  g.add_stop(1.5, "#000000")
  assert_eq(g.stops.length(), 2)
  assert_eq(g.stops[0].0, 0.0)
  assert_eq(g.stops[1].0, 1.0)
  assert_true(g.stops[0].1 is Var("primary"))
  // merge：后者赢、缺省不抹
  let merged = merge(
    style(background_color="bg_panel"),
    style(background_gradient=g),
  )
  assert_true(merged.background_color is Some(_))
  assert_true(merged.background_gradient is Some(_))
  // 径向构造
  let r = gradient_radial(0.5, 0.5, 1.0)
  r.add_stop(0.0, "#ffffff")
  r.add_stop(1.0, "primary")
  assert_eq(r.stops.length(), 2)
}

///|
test "apply_gradient_bg：token stop 落成当前主题色、不足两 stop 回落 false" {
  @theme.theme_apply(@theme.default_theme())
  let g = gradient_linear(0.0, 0.0, 0.0, 1.0)
  g.add_stop(0.0, "primary")
  g.add_stop(1.0, "bg_page")
  let bm = @render.Bitmap::new(40, 60)
  let p = @render.Painter::new(bm)
  assert_true(apply_gradient_bg(p, g, 40.0, 60.0))
  // apply_gradient_bg 只设渐变笔，填充由调用方按盒形走（这里直线矩形）
  p.fill_rect(0.0, 0.0, 40.0, 60.0)
  p.end()
  // 顶部像素 = 当前主题 primary、底部 = bg_page（token 绘制期现取）
  let (pr, pg, pb) = match @theme.parse_hex(@theme.theme_primary()) {
    Some((r, g, b)) => (r, g, b)
    None => abort("primary 解析失败")
  }
  let top = bm.pixel(20, 1)
  // 像素中心采样在端点内侧一小段，插值有 3–5 的偏移，容差给 8
  assert_true(
    (top.r - pr).abs() <= 8 &&
    (top.g - pg).abs() <= 8 &&
    (top.b - pb).abs() <= 8,
  )
  let (br, bg2, bb) = match @theme.parse_hex(@theme.theme_bg_page()) {
    Some((r, g, b)) => (r, g, b)
    None => abort("bg_page 解析失败")
  }
  let bot = bm.pixel(20, 58)
  assert_true(
    (bot.r - br).abs() <= 8 &&
    (bot.g - bg2).abs() <= 8 &&
    (bot.b - bb).abs() <= 8,
  )
  // 单 stop（画不出渐变）回落 false
  let one = gradient_linear(0.0, 0.0, 0.0, 1.0)
  one.add_stop(0.0, "primary")
  let bm2 = @render.Bitmap::new(10, 10)
  let p2 = @render.Painter::new(bm2)
  assert_false(apply_gradient_bg(p2, one, 10.0, 10.0))
  p2.end()
}
