// 外部事件循环一拍回归：step_no_wait 与 step 在无头档行为一致——定时器
// 同样到期结算、脏窗同样上屏、返回值同语义；差异只在等待段归调用方。

///|
test "step_no_wait：定时器经推进结算（等待段由调用方自理）" {
  let fired : Ref[Int32] = Ref(0)
  let a = WindowHost::test_headless(200, 120)
  let _ = a.timer(20, fn() { fired.val += 1 })
  // 外部循环形态：每拍先 wait(0)（无头预算口径），再 step_no_wait 推进
  let deadline = @win.now_ms() + 2000L
  let mut beats = 0
  while fired.val == 0 && @win.now_ms() < deadline && beats < 100000 {
    let _ = @win.wait(0)
    let _ = a.step_no_wait()
    beats += 1
  }
  assert_true(fired.val > 0)
}

///|
test "step_no_wait：挂内容置脏一拍上屏，返回继续" {
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
  let _ = @win.wait(0)
  assert_true(a.step_no_wait())
  assert_true(a.painted_once)
  assert_eq(a.session.dirty, false)
}
