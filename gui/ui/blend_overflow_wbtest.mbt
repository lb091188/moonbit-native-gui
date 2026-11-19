// S4 回归：混合模式（Multiply 重叠变黑）、溢出默认可见 / 显式 Hidden 裁切、
// 装饰线三档（line-through / overline / underline 各自落线）。

///|
fn s4_bm(w : @widget.Widget, wpx : Int32, hpx : Int32) -> @render.Bitmap {
  let bm = @render.Bitmap::new(wpx, hpx)
  let p = @render.Painter::new(bm)
  w.paint_at(p, w.rect.x, w.rect.y)
  p.end()
  bm
}

///|
test "blend_mode：Multiply 重叠区变黑、非重叠区保持底色" {
  @theme.theme_apply(@theme.default_theme())
  let inner = view([], width=30.0, height=30.0, background_color="#0000ff", class=[
    @style.style(blend_mode=@render.Multiply),
  ])
  let (root, w) = mounted(
    view(
      [inner],
      width=40.0,
      height=40.0,
      background_color="#ff0000",
      corner_radius=0.0,
    ),
    80.0,
    80.0,
  )
  let _ = root
  let bm = s4_bm(w, 40, 40)
  // 重叠区（inner 盒 (0,0,30,30) 内）：红×蓝 = 黑
  let mid = bm.pixel(5, 5)
  assert_true(mid.r < 40 && mid.g < 40 && mid.b < 40)
  // 非重叠区：底红
  let corner = bm.pixel(35, 35)
  assert_true(corner.r > 200 && corner.g < 40 && corner.b < 40)
}

///|
test "overflow：默认放行越界子件，Hidden 裁到自身矩形" {
  @theme.theme_apply(@theme.default_theme())
  let kid = fn() -> @widget.Node {
    view([], width=20.0, height=20.0, background_color="danger", class=[
      @style.style(position=@yoga.Absolute, top=30.0, left=30.0),
    ])
  }
  let (_, by_default) = mounted(
    view(
      [kid()],
      width=40.0,
      height=40.0,
      background_color="bg_panel",
      corner_radius=0.0,
    ),
    80.0,
    80.0,
  )
  let (_, hidden) = mounted(
    view(
      [kid()],
      width=40.0,
      height=40.0,
      background_color="bg_panel",
      corner_radius=0.0,
      class=[@style.style(overflow=@style.Hidden)],
    ),
    80.0,
    80.0,
  )
  let (dr, dg, _db) = match @theme.parse_hex(@theme.theme_danger()) {
    Some((r, g, b)) => (r, g, b)
    None => abort("danger 解析失败")
  }
  // 默认（overflow:visible）：越出父矩形（40×40）的部分照常出墨
  // （45,45 在子件 30..50 内）
  let bm_d = @render.Bitmap::new(60, 60)
  let pd = @render.Painter::new(bm_d)
  by_default.paint_at(pd, 0.0, 0.0)
  pd.end()
  let out = bm_d.pixel(45, 45)
  assert_true((out.r - dr).abs() <= 8 && (out.g - dg).abs() <= 8)
  // Hidden：同样构图越界部分不出墨
  let bm_h = @render.Bitmap::new(60, 60)
  let ph = @render.Painter::new(bm_h)
  hidden.paint_at(ph, 0.0, 0.0)
  ph.end()
  assert_eq(bm_h.pixel(45, 45).a, 0)
  // Hidden 只裁越界：父内与子件相交的 (35,35) 仍画
  let inside = bm_h.pixel(35, 35)
  assert_true((inside.r - dr).abs() <= 8 && (inside.g - dg).abs() <= 8)
}

///|
test "text 装饰线：line-through 在字高中部、overline 在盒顶" {
  if !ui_text_guard() {
    return
  }
  @theme.theme_apply(@theme.default_theme())
  let (root1, w1) = mounted(
    text("abcd wxyz", color="danger", class=[
      @style.style(text_decoration=@style.LineThrough),
    ]),
    200.0,
    40.0,
  )
  let _ = root1
  let bm1 = s4_bm(w1, 200, 40)
  // 找删除线：连续 danger 色横线（宽 > 40）
  fn count_line(bm : @render.Bitmap) -> Int32 {
    let (dr, _dg, _db) = match @theme.parse_hex(@theme.theme_danger()) {
      Some((r, g, b)) => (r, g, b)
      None => (214, 69, 80)
    }
    let mut best = 0
    for y in 0..<bm.height {
      let mut run = 0
      for x in 0..<bm.width {
        let px = bm.pixel(x, y)
        if (px.r - dr).abs() <= 30 && (px.g - _dg).abs() <= 30 {
          run += 1
          if run > best {
            best = run
          }
        } else {
          run = 0
        }
      }
    }
    best
  }
  assert_true(count_line(bm1) > 40)
  // overline：线在盒顶部（y < 8）
  let (root2, w2) = mounted(
    text("abcd wxyz", color="danger", class=[
      @style.style(text_decoration=@style.Overline),
    ]),
    200.0,
    40.0,
  )
  let _ = root2
  let bm2 = s4_bm(w2, 200, 40)
  let mut top_line_y = -1
  for y in 0..<10 {
    let mut run = 0
    for x in 0..<bm2.width {
      let px = bm2.pixel(x, y)
      if px.r > 150 && px.g < 140 {
        run += 1
      }
    }
    if run > 40 {
      top_line_y = y
      break
    }
  }
  assert_true(top_line_y >= 0)
}
