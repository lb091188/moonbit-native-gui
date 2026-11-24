// 帧时钟：把「这一帧要推进一次」从各动画自己的定时器链收成一处。
//
// 平台有显示器刷新回调（当前只有 mac）时，帧由刷新信号驱动：回调线程只投
// 唤醒位并记下目标上屏时刻，主循环等到唤醒后统一跑本帧回调，滚动弹簧按
// 「目标上屏时刻」取位置——帧与刷新对齐，位移均匀。没有刷新回调的平台与
// 无头测试走定时器回退，行为与旧链路一致。
//
// 登记制：回调里要下一帧就再 `frame_clock_request`；表空即停源，空闲零唤醒。
// 目标时刻是回调时刻加一个刷新周期——这一帧会在下一次刷新上屏。

///|
/// 本帧待跑回调，入参是本帧目标上屏时刻（毫秒，与 `now_ms` 同轴）。
let g_frame_cbs : Array[(Int64) -> Unit] = []

///|
/// 定时器回退档的在飞标记（mac 刷新源起不来时兜底）。
let g_frame_timer_armed : Ref[Bool] = Ref(false)

///|
/// 刷新源起不来：进程级判死，不再每帧重试。
let g_frame_vsync_failed : Ref[Bool] = Ref(false)

///|
/// 本帧目标上屏时刻（毫秒），诊断用。
let g_frame_now_ms : Ref[Int64] = Ref(0L)

///|
/// 帧周期（微秒）：刷新率读不到按 60Hz。
fn frame_period_us() -> Int64 {
  let hz = @win.display_hz()
  let h = if hz > 0 { hz.to_int64() } else { 60L }
  let p = 1000000L / h
  if p < 1L { 1L } else { p }
}

///|
/// 帧时钟是否可用：无头测试与无刷新回调的平台为假。
pub fn frame_clock_ready() -> Bool {
  !session_is_headless() && @win.vsync_supported()
}

///|
/// 登记本帧回调。
pub fn frame_clock_request(f : (Int64) -> Unit) -> Unit {
  g_frame_cbs.push(f)
}

///|
/// 本帧是否已有待跑回调。
pub fn frame_clock_pending() -> Bool {
  g_frame_cbs.length() > 0
}

///|
/// 本帧目标上屏时刻（毫秒）。
pub fn frame_clock_now_ms() -> Int64 {
  g_frame_now_ms.val
}

///|
/// 跑一帧：先取走当前登记再逐个跑，回调里可以安全地再登记下一帧。
pub fn frame_clock_fire(target_ms : Int64) -> Unit {
  g_frame_now_ms.val = target_ms
  let list = g_frame_cbs.copy()
  g_frame_cbs.clear()
  for f in list {
    f(target_ms)
  }
}

///|
/// 定时器回退：一帧一定时器，跑完按需再排。
fn frame_clock_arm_timer() -> Unit {
  if g_frame_timer_armed.val {
    return ()
  }
  g_frame_timer_armed.val = true
  let ms = (frame_period_us() / 1000L).to_int()
  let period = if ms < 1 { 1 } else { ms }
  let _ = set_timeout(period, fn() {
    g_frame_timer_armed.val = false
    frame_clock_fire(now_ms() + period.to_int64())
    frame_clock_sync_source()
  })
}

///|
/// 挂/摘刷新源：有待跑回调就开，没有就关；刷新源起不来退定时器。
/// 泵的等待段前后各调一次即可，幂等。
pub fn frame_clock_sync_source() -> Unit {
  if !frame_clock_ready() {
    return ()
  }
  if !frame_clock_pending() {
    if !g_frame_vsync_failed.val {
      @win.vsync_stop()
    }
    return ()
  }
  if !g_frame_vsync_failed.val && !@win.vsync_start() {
    g_frame_vsync_failed.val = true
  }
  if g_frame_vsync_failed.val {
    frame_clock_arm_timer()
  }
}
