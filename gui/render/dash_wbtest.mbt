// 虚线：段数与首段长度（两后端同一图案的直观判据）。走 Pure 后端（无显示时
// cairo 会话建不出，Painter 自动落纯光栅器），像素读数直接来自自有位图。

///|
fn col_inked(bm : Bitmap, x : Int, h : Int) -> Bool {
  let mut hit = false
  for y = 0; y < h; y = y + 1 {
    if bm.pixel(x, y).a > 0 {
      hit = true
    }
  }
  hit
}

///|
fn dash_runs(bm : Bitmap, w : Int, h : Int) -> Array[(Int, Int)] {
  let runs : Array[(Int, Int)] = []
  let mut start = -1
  for x = 0; x < w; x = x + 1 {
    let on = col_inked(bm, x, h)
    if on && start < 0 {
      start = x
    }
    if !on && start >= 0 {
      runs.push((start, x - 1))
      start = -1
    }
  }
  if start >= 0 {
    runs.push((start, w - 1))
  }
  runs
}

///|
fn dashed_line(
  pattern : Array[Double],
  offset : Double,
) -> Array[(Int, Int)] {
  let bm = Bitmap::new(160, 24)
  let p = Painter::new(bm)
  p.set_line_width(2.0)
  p.set_stroke_color("#000000")
  p.set_dashes(pattern, offset~)
  p.begin_path()
  p.move_to(5.0, 12.0)
  p.line_to(105.0, 12.0)
  p.stroke()
  p.end()
  dash_runs(bm, 160, 24)
}

test "虚线：段数与首段长度按图案切分" {
  let runs = dashed_line([10.0, 10.0], 0.0)
  // 100px 的线、周期 20px ⇒ 5 段；首段从 x=5 起
  assert_eq(runs.length(), 5, msg="段数不符：\{runs.length()}")
  if runs.length() > 0 {
    let (s, e) = runs[0]
    assert_eq(s, 5, msg="首段起点=\{s}")
    // 首段长 10px（AA 边缘可能各占一格，容忍 1px）
    assert_eq((e - s - 9).abs() <= 1, true, msg="首段长=\{e - s + 1}")
  }
  // 段间间隔也是 10px（起点的差 = 周期）
  if runs.length() >= 2 {
    assert_eq(runs[1].0 - runs[0].0, 20, msg="周期不符")
  }
}

test "虚线：相位偏移把图案起点前移" {
  // 图案 [10,10] + 相位 10 ⇒ 先空 10px：首段从 x=15 起
  let runs = dashed_line([10.0, 10.0], 10.0)
  if runs.length() > 0 {
    assert_eq(runs[0].0, 15, msg="相位未生效：首段起点=\{runs[0].0}")
  } else {
    assert_eq(false, true, msg="相位档一段都没画出来")
  }
}

test "虚线：清空图案回到实线" {
  let bm = Bitmap::new(160, 24)
  let p = Painter::new(bm)
  p.set_line_width(2.0)
  p.set_stroke_color("#000000")
  p.set_dashes([10.0, 10.0])
  p.set_dashes([])
  p.begin_path()
  p.move_to(5.0, 12.0)
  p.line_to(105.0, 12.0)
  p.stroke()
  p.end()
  let runs = dash_runs(bm, 160, 24)
  assert_eq(runs.length(), 1, msg="清空虚线后应是整条实线，段数=\{runs.length()}")
}

test "虚线：闭合子路径不崩且按图案断段" {
  let bm = Bitmap::new(120, 120)
  let p = Painter::new(bm)
  p.set_line_width(2.0)
  p.set_stroke_color("#000000")
  p.set_dashes([6.0, 4.0])
  p.begin_path()
  p.move_to(20.0, 20.0)
  p.line_to(100.0, 20.0)
  p.line_to(100.0, 100.0)
  p.line_to(20.0, 100.0)
  p.close_path()
  p.stroke()
  p.end()
  // 顶边至少画出两段（图案 6/4 在 80px 上是 8 段）
  let mut top_runs = 0
  let mut prev = false
  for x = 0; x < 120; x = x + 1 {
    let on = bm.pixel(x, 20).a > 0 || bm.pixel(x, 19).a > 0 || bm.pixel(x, 21).a > 0
    if on && !prev {
      top_runs = top_runs + 1
    }
    prev = on
  }
  assert_eq(top_runs >= 2, true, msg="闭合路径顶边虚线断段数=\{top_runs}")
}

test "虚线状态进 save/restore" {
  let bm = Bitmap::new(40, 40)
  let p = Painter::new(bm)
  p.set_dashes([4.0, 4.0])
  p.save()
  p.set_dashes([])
  p.restore()
  assert_eq(p.state.dashes.length(), 2, msg="restore 没拿回虚线图案")
}
