// 帧节奏账回归：间隔入账、分位取值、超预算计数与空闲间隔的排除。

///|
test "帧节奏账：间隔分位、超预算计数与空闲排除" {
  paint_profile_reset()
  prof_set_budget_us(16667L)
  // 首帧不产生间隔；随后 16667 / 16667 / 25000 三个间隔
  prof_record(0L, 0L, 0L, 1000L, 1000000L)
  prof_record(0L, 0L, 0L, 1000L, 1016667L)
  prof_record(0L, 0L, 0L, 1000L, 1033334L)
  prof_record(0L, 0L, 0L, 1000L, 1058334L)
  let s = paint_pacing_summary()
  assert_true(s.contains("fps=51."), msg=s)
  assert_true(s.contains("interval_p50=16700us"), msg=s)
  assert_true(s.contains("p95=25100us"), msg=s)
  assert_true(s.contains("max=25000us"), msg=s)
  assert_true(s.contains("over=1"), msg=s)
  // 空闲间隔（>250ms）不入账：再来一帧，间隔 500ms
  prof_record(0L, 0L, 0L, 1000L, 1558334L)
  let s2 = paint_pacing_summary()
  assert_true(s2.contains("fps=51."), msg=s2)
  // 旧汇总口径保持毫秒字段
  let legacy = paint_profile_summary()
  assert_true(legacy.contains("max_frame="), msg=legacy)
  assert_true(legacy.contains("ms paint="), msg=legacy)
  paint_profile_reset()
  prof_set_budget_us(16667L)
}
