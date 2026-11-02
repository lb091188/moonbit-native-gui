// 背景渐变组件级回归（S2）：view 盒子的渐变底铺满、渐变优先于纯色。

///|
fn grad_bm(w : @widget.Widget, wpx : Int, hpx : Int) -> @render.Bitmap {
  let bm = @render.Bitmap::new(wpx, hpx)
  let p = @render.Painter::new(bm)
  w.paint_at(p, w.rect.x, w.rect.y)
  p.end()
  bm
}

///|
/// 上主色下页面底的竖向线性渐变块（40×60）。
fn grad_view() -> @widget.Node {
  let g = @style.gradient_linear(0.0, 0.0, 0.0, 1.0)
  g.add_stop(0.0, "primary")
  g.add_stop(1.0, "bg_page")
  view([], width=40.0, height=60.0, background_color="bg_panel", class=[
    @style.style(background_gradient=g),
  ])
}

///|
test "view 渐变底：上主色下页面底，线性随盒子铺满" {
  @theme.theme_apply(@theme.default_theme())
  let (root, w) = mounted(grad_view(), 80.0, 100.0)
  let _ = root
  let bm = grad_bm(w, 40, 60)
  let (pr, pg, pb) = match @theme.parse_hex(@theme.theme_primary()) {
    Some((r, g, b)) => (r, g, b)
    None => abort("primary 解析失败")
  }
  let top = bm.pixel(20, 1)
  // 像素中心采样在端点内侧一小段，插值有 3–5 的偏移，容差给 8
  assert_true((top.r - pr).abs() <= 8 && (top.g - pg).abs() <= 8 && (top.b - pb).abs() <= 8)
  let (br, bg2, bb) = match @theme.parse_hex(@theme.theme_bg_page()) {
    Some((r, g, b)) => (r, g, b)
    None => abort("bg_page 解析失败")
  }
  let bot = bm.pixel(20, 58)
  assert_true((bot.r - br).abs() <= 8 && (bot.g - bg2).abs() <= 8 && (bot.b - bb).abs() <= 8)
  // 中点在两端插值之间（渐变确实在过渡，不是分段纯色）
  let mid = bm.pixel(20, 30)
  assert_true(mid.g > (pg + bg2) / 2 - 24 && mid.g < (pg + bg2) / 2 + 24)
}

///|
test "view 渐变优先于纯色：给渐变时不再铺 background_color" {
  @theme.theme_apply(@theme.default_theme())
  let g = @style.gradient_linear(0.0, 0.0, 0.0, 1.0)
  g.add_stop(0.0, "primary")
  g.add_stop(1.0, "primary")
  let (root, w) = mounted(
    view([], width=30.0, height=30.0, background_color="danger", class=[
      @style.style(background_gradient=g),
    ]),
    60.0,
    60.0,
  )
  let _ = root
  let bm = grad_bm(w, 30, 30)
  // 全屏都是 primary（渐变两 stop 同色），不是 danger
  let (pr, pg, pb) = match @theme.parse_hex(@theme.theme_primary()) {
    Some((r, gg, b)) => (r, gg, b)
    None => abort("primary 解析失败")
  }
  let (dr, dg, db) = match @theme.parse_hex(@theme.theme_danger()) {
    Some((r, gg, b)) => (r, gg, b)
    None => abort("danger 解析失败")
  }
  let mid = bm.pixel(15, 15)
  assert_true((mid.r - pr).abs() <= 8 && (mid.g - pg).abs() <= 8 && (mid.b - pb).abs() <= 8)
  assert_true(!((mid.r - dr).abs() <= 8 && (mid.g - dg).abs() <= 8 && (mid.b - db).abs() <= 8))
}
