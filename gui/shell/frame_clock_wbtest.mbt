// 帧时钟回归：登记、跑一帧、回调里再登记下一帧、无头档不接刷新源。

///|
test "帧时钟：登记与跑帧，回调可续登记下一帧" {
  let prev = session_is_headless()
  session_set_headless(true)
  let log : Array[Int64] = []
  frame_clock_request(fn(t) { log.push(t) })
  assert_true(frame_clock_pending())
  frame_clock_fire(1000L)
  assert_eq(log.length(), 1)
  assert_eq(log[0], 1000L)
  assert_eq(frame_clock_now_ms(), 1000L)
  // 取走即清空：本帧回调只跑一次
  assert_false(frame_clock_pending())
  frame_clock_request(fn(t) { log.push(t + 1L) })
  frame_clock_fire(1017L)
  assert_eq(log.length(), 2)
  assert_eq(log[1], 1018L)
  // 无头档：帧时钟不可用，同步源是无操作
  assert_false(frame_clock_ready())
  frame_clock_sync_source()
  assert_false(frame_clock_pending())
  session_set_headless(prev)
}
