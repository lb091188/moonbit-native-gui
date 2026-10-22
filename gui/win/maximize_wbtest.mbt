// 最大化 / 还原：程序化切换与「现问平台」的读回。无显示服务环境跳过；
// 还原后「客户区尺寸与位置回到最大化前」是肉眼项，走人工清单。

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
        inspect(w.is_maximized(), content="true")
        // 幂等：已最大化再设不重做（态与尺寸读数不变）
        let (mw, mh) = w.size()
        w.set_maximized(true)
        inspect(w.is_maximized(), content="true")
        let (mw2, mh2) = w.size()
        inspect(mw2 == mw && mh2 == mh, content="true")
        // 最大化后客户区比初始大（系统标题栏之外没有别的来源能撑大它）
        inspect(mw > 320 || mh > 200, content="true")
        w.set_maximized(false)
        inspect(w.is_maximized(), content="false")
        let (rw, rh) = w.size()
        // 还原后回到建窗尺寸（三平台都由系统记着进最大化前的几何）
        inspect(rw == 320 && rh == 200, content="true")
        w.close()
      }
    }
  }
}
