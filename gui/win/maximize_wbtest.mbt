// 最大化 / 还原：程序化切换与「现问平台」的读回。无显示服务环境跳过；
// 还原后「客户区尺寸与位置回到最大化前」是肉眼项，走人工清单。
// WM 的态与几何都是异步回写（set 返回时 _NET_WM_STATE 还没落定，XFCE 系
// 实机必现）：对每次切换在预算内轮询读数，验「最终跟随」，不吃竞态。

///|
// 等 is_maximized 落定：预算内读到 want 即真；预算耗尽按最后读数判定
fn wait_maximized(w : Window, want : Bool, budget_ms : Int) -> Bool {
  let deadline = now_ms() + budget_ms.to_int64()
  let mut ok = w.is_maximized() == want
  while !ok && now_ms() < deadline {
    ignore(wait(20))
    ok = w.is_maximized() == want
  }
  ok
}

// 等几何落定：pred 对当前尺寸成立即真（「撑大」「回原尺寸」两处共用）
fn wait_size(w : Window, pred : ((Int, Int)) -> Bool, budget_ms : Int) -> Bool {
  let deadline = now_ms() + budget_ms.to_int64()
  let mut ok = pred(w.size())
  while !ok && now_ms() < deadline {
    ignore(wait(20))
    ok = pred(w.size())
  }
  ok
}

///|
test "最大化：切换后读回跟随，幂等不重做" {
  if !init_backend() {
    println("maximize: skip (无显示服务)")
  } else {
    let win = Window::new(320, 200, "wbtest-maximize")
    match win {
      None => println("maximize: skip (建窗失败)")
      Some(w) => {
        w.show()
        inspect(w.is_maximized(), content="false")
        w.set_maximized(true)
        inspect(wait_maximized(w, true, 2000), content="true")
        // 最大化后客户区比初始大（系统标题栏之外没有别的来源能撑大它）
        inspect(
          wait_size(w, fn(s) { s.0 > 320 || s.1 > 200 }, 2000),
          content="true",
        )
        // 幂等：已最大化再设不重做（态与尺寸读数不变）
        let (mw, mh) = w.size()
        w.set_maximized(true)
        inspect(wait_maximized(w, true, 2000), content="true")
        let (mw2, mh2) = w.size()
        inspect(mw2 == mw && mh2 == mh, content="true")
        w.set_maximized(false)
        inspect(wait_maximized(w, false, 2000), content="true")
        // 还原后回到建窗尺寸（三平台都由系统记着进最大化前的几何）
        inspect(
          wait_size(w, fn(s) { s.0 == 320 && s.1 == 200 }, 2000),
          content="true",
        )
        w.close()
      }
    }
  }
}
