// 帧节奏账回归：间隔入账、分位取值、超预算计数与空闲间隔的排除。

///|
test "帧节奏账：间隔分位、超预算计数与空闲排除" {
  paint_profile_reset()
  prof_set_budget_us(16667L)
  // 首帧不产生间隔；随后 16667 / 16667 / 30000 三个间隔，最后一个过 1.5 倍
  // 预算算丢刷新
  prof_record(0L, 0L, 0L, 1000L, 1000000L)
  prof_record(0L, 0L, 0L, 1000L, 1016667L)
  prof_record(0L, 0L, 0L, 1000L, 1033334L)
  prof_record(0L, 0L, 0L, 1000L, 1063334L)
  let s = paint_pacing_summary()
  assert_true(s.contains("fps=47."), msg=s)
  assert_true(s.contains("interval_p50=16700us"), msg=s)
  assert_true(s.contains("p95=30100us"), msg=s)
  assert_true(s.contains("max=30000us"), msg=s)
  assert_true(s.contains("over=1"), msg=s)
  // 贴预算但没过 1.5 倍的间隔不算丢刷新；空闲间隔（>4 个周期）不入账
  prof_record(0L, 0L, 0L, 1000L, 1080001L)
  let s2 = paint_pacing_summary()
  assert_true(s2.contains("over=1"), msg=s2)
  prof_record(0L, 0L, 0L, 1000L, 1580001L)
  let s3 = paint_pacing_summary()
  assert_true(s3.contains("over=1"), msg=s3)
  assert_true(s3.contains("max=30000us"), msg=s3)
  // 旧汇总口径保持毫秒字段
  let legacy = paint_profile_summary()
  assert_true(legacy.contains("max_frame="), msg=legacy)
  assert_true(legacy.contains("ms paint="), msg=legacy)
  paint_profile_reset()
  prof_set_budget_us(16667L)
}
