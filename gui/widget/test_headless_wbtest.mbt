// 无头测试宿主回归（headless-tester P2）：test_headless 的应用泵可断言
// （定时器到期由 step 逐步结算、不真睡）、虚窗哨兵的窗口级动作全空转。

///|
test "test_headless：定时器经 step 驱动到期（wait(0) 不真睡）" {
  let fired : Ref[Int] = Ref(0)
  let a = WindowHost::test_headless(200, 120)
  assert_true(a.is_primary())
  assert_true(@shell.session_is_headless())
  let _ = a.timer(20, fn() { fired.val += 1 })
  // 2s 预算内经 step 逐步结算（每拍 wait(0) 不额外睡，真实时钟过 20ms 即到期）
  let deadline = @win.now_ms() + 2000L
  let mut steps = 0
  while fired.val == 0 && @win.now_ms() < deadline && steps < 100000 {
    let _ = a.step()
    steps += 1
  }
  assert_true(fired.val > 0)
}

///|
test "test_headless：挂内容、置脏、step 一拍结算不崩" {
  let a = WindowHost::test_headless(240, 160)
  a.mount([
    node_of_new(fn(_p : Widget) -> Widget {
      let w = Widget::new()
      w.set_size(40.0, 20.0)
      w.on_draw = Some(fn(_s : Widget, p : @render.Painter, r : Rect) -> Unit {
        p.set_fill_color("#336699")
        p.fill_rect(0.0, 0.0, r.w, r.h)
      })
      w
    }),
  ])
  assert_true(a.step())
  // 首帧已上屏、脏标记已清；兜底仍在排——present 成功不提前缴械
  //（窗未映射完时的首帧会被平台丢掉，必须由计时拍补上）
  assert_true(a.painted_once)
  assert_eq(a.session.dirty, false)
  assert_eq(a.first_retry_left, 3)
  // 飞行中再 mount 不重复排
  a.mount([node_of_new(fn(_p : Widget) -> Widget { Widget::new() })])
  assert_eq(a.first_retry_left, 3)
  assert_true(a.step())
  assert_true(a.painted_once)
  // 推进到三拍（30/120/400ms）全部到期：收口为 -1，此后 mount 也不再排
  let deadline = @win.now_ms() + 2000L
  while a.first_retry_left != -1 && @win.now_ms() < deadline {
    let _ = a.step()
  }
  assert_eq(a.first_retry_left, -1)
  a.mount([node_of_new(fn(_p : Widget) -> Widget { Widget::new() })])
  assert_eq(a.first_retry_left, -1)
}

///|
test "Window::virtual_：size 回字段、窗口级动作空转、句柄 0" {
  let w = @win.Window::virtual_(320, 200)
  assert_eq(w.size(), (320, 200))
  // 全部桩级动作对 id=-1 早退：不崩、读回安全值
  w.show()
  w.hide()
  w.set_title("ghost")
  assert_eq(w.native_handle(), 0L)
}
