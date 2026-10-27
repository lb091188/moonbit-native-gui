// W35 收尾：Painter.line_cap/join + draw_path 无头回归。
// Cairo 后端在纯 CI 无显示时不可用；本 wbtest 走 Pure 后端。
// line_cap 的 Round 档两后端都真实生效（dotted 边框的圆头点靠它落墨）。

test "Painter.set_line_cap/join 在 Pure 后端不抛错" {
  let bmp = Bitmap::new(4, 4)
  let p = Painter::new(bmp)
  p.set_line_cap(Round)
  p.set_line_join(Bevel)
  p.set_line_cap(Butt)
  p.set_line_join(Miter)
}

test "draw_path 回放 Path 序列不抛错" {
  let bmp = Bitmap::new(8, 8)
  let p = Painter::new(bmp)
  let path = Path::new()
  path.move_to(1.0, 1.0)
  path.line_to(5.0, 1.0)
  path.line_to(5.0, 5.0)
  path.close()
  p.draw_path(path)
  // 只是不抛；具体像素覆盖由 Cairo 真机验收承担
}

test "LineCap/LineJoin 枚举变体齐全" {
  let a : LineCap = Butt
  let b : LineCap = Round
  let c : LineCap = Square
  let d : LineJoin = Miter
  let e : LineJoin = Round
  let f : LineJoin = Bevel
  assert_true(line_cap_to_int(a) == 0)
  assert_true(line_cap_to_int(b) == 1)
  assert_true(line_cap_to_int(c) == 2)
  assert_true(line_join_to_int(d) == 0)
  assert_true(line_join_to_int(e) == 1)
  assert_true(line_join_to_int(f) == 2)
}

///|
test "Round 端帽真实落墨：dotted 点段横向 ±1px 有墨、butt 档没有" {
  // dotted 边框的画法 = 0.1px 段 + Round 端帽（ui/base.mbt set_border_pen）。
  // 端帽空操作的档上，点段只剩 0.1px 宽的一条缝——真机表现为「mac 看不见
  // 点边框」。判据取点中心左右 ±1px：圆帽（半径=线宽一半=1.5）必墨，butt 必空。
  let draw = fn(cap : LineCap) -> Bitmap {
    let bmp = Bitmap::new(40, 20)
    let p = Painter::new(bmp)
    p.set_stroke_color("#ffffff")
    p.set_line_width(4.0)
    p.set_dashes([0.1, 9.9])
    p.set_line_cap(cap)
    p.begin_path()
    p.move_to(5.0, 10.0)
    p.line_to(35.5, 10.0)
    p.stroke()
    p.end()
    bmp
  }
  let round_bmp = draw(Round)
  // 点心在 x=5/15/25/35、y=10：±1px 与上下 ±1px 都该有墨
  for cx in [5, 15, 25, 35] {
    assert_true(round_bmp.pixel(cx - 1, 10).a > 128, msg="圆帽左侧没墨 x=\{cx}")
    assert_true(round_bmp.pixel(cx + 1, 10).a > 128, msg="圆帽右侧没墨 x=\{cx}")
    assert_true(round_bmp.pixel(cx, 9).a > 128, msg="圆帽上侧没墨 x=\{cx}")
  }
  // 点间空隙（周期 10 的半相）必须留白——点糊成线也算红
  assert_eq(round_bmp.pixel(10, 10).a, 0)
  assert_eq(round_bmp.pixel(20, 10).a, 0)
  // butt 对照：同参数下 ±1px 无墨（旧实现全档如此，证明判据钉的是端帽本身）
  let butt_bmp = draw(Butt)
  assert_true(butt_bmp.pixel(6, 10).a <= 128)
  assert_true(butt_bmp.pixel(14, 10).a <= 128)
}

///|
test "stroke_rect 虚线档两后端退通用路径：直角点边框四点有墨、点间留白" {
  // 两家的 stroke_rect 都是「四带填充」内侧复现，不吃虚线——门面在虚线档
  // 一律换成内缩半线宽的居中路径走 stroke()。旧实现下这里是一圈实线。
  let bmp = Bitmap::new(30, 30)
  let p = Painter::new(bmp)
  p.set_stroke_color("#ffffff")
  p.set_line_width(3.0)
  p.set_dashes([0.1, 3.9])
  p.set_line_cap(Round)
  p.stroke_rect(0.0, 0.0, 30.0, 30.0)
  p.end()
  // 居中路径内缩 lw/2=1.5：顶边点心 (1.5,1.5)、(5.5,1.5)…，帽半径 1.5
  assert_true(bmp.pixel(1, 1).a > 128, msg="直角点边框第一点没墨")
  assert_true(bmp.pixel(2, 1).a > 128, msg="直角点边框点帽右侧没墨")
  assert_true(bmp.pixel(3, 1).a < 32)
  assert_true(bmp.pixel(5, 1).a > 128, msg="顶边第二个点没墨")
  // 左边对称：点心 (1.5,5.5)
  assert_true(bmp.pixel(1, 5).a > 128, msg="左边点没墨")
}
