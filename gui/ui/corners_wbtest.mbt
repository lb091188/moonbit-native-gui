// 每角圆角 / 每边边框组件级回归（S3）：view 盒子四角不等半径裁切、
// 每边内缘条（无圆角）、带圆角时 per-side 回落统一描边。

///|
fn corners_bm(w : @widget.Widget, wpx : Int, hpx : Int) -> @render.Bitmap {
  let bm = @render.Bitmap::new(wpx, hpx)
  let p = @render.Painter::new(bm)
  w.paint_at(p, w.rect.x, w.rect.y)
  p.end()
  bm
}

///|
test "view 每角圆角：左上直角右上大圆角，角落像素分档" {
  @theme.theme_apply(@theme.default_theme())
  let (root, w) = mounted(
    view([], width=40.0, height=40.0, background_color="danger", class=[
      @style.style(
        border_top_left_radius=0.0,
        border_top_right_radius=20.0,
      ),
    ]),
    80.0,
    80.0,
  )
  let _ = root
  let bm = corners_bm(w, 40, 40)
  let (dr, _dg, _db) = match @theme.parse_hex(@theme.theme_danger()) {
    Some((r, g, b)) => (r, g, b)
    None => abort("danger 解析失败")
  }
  // 左上直角：角点内侧仍是 danger
  assert_true(
    (bm.pixel(1, 1).r - dr).abs() <= 8 &&
    (bm.pixel(1, 1).g - _dg).abs() <= 8,
  )
  // 右上大圆角：角点被裁掉（透明），圆心内侧在
  assert_eq(bm.pixel(38, 1).a, 0)
  assert_true((bm.pixel(30, 6).r - dr).abs() <= 40)
}

///|
test "view 每边边框：无圆角逐边内缘条，颜色各异" {
  @theme.theme_apply(@theme.default_theme())
  let (root, w) = mounted(
    view(
      [],
      width=40.0,
      height=40.0,
      background_color="bg_panel",
      // per-side 逐边只在无圆角时生效（诚实降级口径），显式关掉
      corner_radius=0.0,
      class=[
        @style.style(
          border_top_width=4.0,
          border_top_color="danger",
          border_left_width=2.0,
          border_left_color="success",
        ),
      ],
    ),
    80.0,
    80.0,
  )
  let _ = root
  let bm = corners_bm(w, 40, 40)
  let (dr, _dg, _db) = match @theme.parse_hex(@theme.theme_danger()) {
    Some((r, g, b)) => (r, g, b)
    None => abort("danger 解析失败")
  }
  let (sr, _sg, _sb) = match @theme.parse_hex(@theme.theme_success()) {
    Some((r, g, b)) => (r, g, b)
    None => abort("success 解析失败")
  }
  // 顶条 4px danger、左条 2px success、右缘无框露面板底（bg_panel 白，不透明）
  assert_true((bm.pixel(20, 1).r - dr).abs() <= 8)
  assert_true((bm.pixel(1, 20).r - sr).abs() <= 8)
  let rx = bm.pixel(39, 20)
  assert_true(rx.r > 240 && rx.g > 240 && rx.b > 240)
}

///|
test "side_borders_of / corner_radii_of：缺省回落统一值" {
  let s = @style.style(border_width=2.0, border_color="primary", border_radius=6.0)
  let (bt, br, _bb, _bl) = @style.side_borders_of(s)
  assert_eq(bt.width, 2.0)
  assert_true(br.color == @theme.theme_primary())
  assert_true(!@style.has_per_side_border(s))
  let (tl, tr, brr, _bl) = @style.corner_radii_of(s, 6.0)
  assert_true(tl == 6.0 && tr == 6.0 && brr == 6.0 && _bl == 6.0)
  assert_true(!@style.has_per_corner_radius(s))
  let s2 = @style.style(border_top_left_radius=12.0)
  assert_true(@style.has_per_corner_radius(s2))
  assert_eq(@style.corner_radii_of(s2, 6.0).0, 12.0)
  assert_eq(@style.corner_radii_of(s2, 6.0).1, 6.0)
}
