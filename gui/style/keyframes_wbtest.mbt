// 关键帧时间轴回归：分段插值、三种循环形态、Once 落定、与 style_for 的接线。

///|
///|
/// "#rrggbb" 的红通道 ≥ 0xf0（近白判定）。
fn hex_first_ge_f0(h : String) -> Bool {
  let a = h.to_array()
  if a.length() < 3 {
    return false
  }
  let hi = a[1]
  let lo = a[2]
  hi >= 'f' && (hi > 'f' || lo >= '0')
}

///|
fn tl_of(frames : Array[(Double, Style)], mode : KfLoop) -> Timeline {
  let fs : Array[Keyframe] = []
  for f in frames {
    fs.push({ at_ms: f.0, style: f.1 })
  }
  { frames: fs, dur: fs[fs.length() - 1].at_ms, mode, start: 1000, finished: false }
}

///|
test "kf_progress：分段线性插值，段外取端帧" {
  let tl = tl_of(
    [
      (0.0, style(background_color="#ffffff")),
      (100.0, style(background_color="#000000")),
    ],
    Once,
  )
  assert_eq(hex_of(kf_progress(tl, 1000).background_color), "#ffffff")
  assert_eq(hex_of(kf_progress(tl, 1050).background_color), "#808080")
  assert_eq(hex_of(kf_progress(tl, 1100).background_color), "#000000")
  assert_eq(hex_of(kf_progress(tl, 1200).background_color), "#000000")
}

///|
test "kf_progress：三帧两段，中段各自插值" {
  let tl = tl_of(
    [
      (0.0, style(background_color="#000000")),
      (100.0, style(background_color="#808080")),
      (200.0, style(background_color="#ffffff")),
    ],
    Once,
  )
  // 第一段中点：黑→灰 的一半
  assert_eq(hex_of(kf_progress(tl, 1050).background_color), "#404040")
  // 第二段中点：灰→白 的一半
  assert_eq(hex_of(kf_progress(tl, 1150).background_color), "#c0c0c0")
}

///|
test "kf_progress：Loop 取模回卷，PingPong 折返" {
  let frames = [
    (0.0, style(background_color="#000000")),
    (100.0, style(background_color="#ffffff")),
  ]
  let lp = tl_of(frames, Loop)
  assert_eq(hex_of(kf_progress(lp, 1150).background_color), "#808080")
  assert_eq(hex_of(kf_progress(lp, 1200).background_color), "#000000")
  let pp = tl_of(frames, PingPong)
  // 150ms 折返到 t=50，180ms 折返到 t=20
  assert_eq(hex_of(kf_progress(pp, 1150).background_color), "#808080")
  let back = kf_progress(pp, 1180).background_color
  assert_true(hex_of(back) != "#ffffff" && hex_of(back) != "#000000")
  let fwd = kf_progress(pp, 1020).background_color
  assert_eq(hex_of(back), hex_of(fwd))
}

///|
test "kf_step：Once 到点落定（末帧仍盖），kf_running 翻假" {
  let w = @widget.Widget::new()
  apply(w, style(background_color="#ff0000"))
  animate(
    w,
    [
      { at_ms: 0.0, style: style(background_color="#ffffff") },
      { at_ms: 100.0, style: style(background_color="#000000") },
    ],
  )
  assert_true(kf_running(w.id))
  // 刚起轴：e≈0 取首帧附近的近白（真实时钟下起轴到断言间会走几毫秒）
  let near0 = hex_of(style_for(w).background_color)
  assert_true(near0 != "#ff0000" && hex_first_ge_f0(near0))
  stop_animating(w)
  assert_true(!kf_running(w.id))
  // 清轴后回落基块
  assert_eq(hex_of(style_for(w).background_color), "#ff0000")
}

///|
test "animate：少于两帧或零时长不立轴" {
  let w = @widget.Widget::new()
  animate(w, [{ at_ms: 0.0, style: style(background_color="#ffffff") }])
  assert_true(!kf_running(w.id))
  animate(
    w,
    [
      { at_ms: 0.0, style: style(background_color="#ffffff") },
      { at_ms: 0.0, style: style(background_color="#000000") },
    ],
  )
  assert_true(!kf_running(w.id))
}
