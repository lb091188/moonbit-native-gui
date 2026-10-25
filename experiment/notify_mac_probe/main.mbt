// mac 通知栈探针（与 showcase 同一条栈：MoonBit 主循环 + win 桩 + UN）。
// 起一扇小窗（保持前台激活），2 秒后自动发两条通知（kind 0 无声 / kind 2 带
// 默认声），再跑 10 秒退出。发通知前后的时间点都打读数。
//
// 跑法（mac 必须从 .app bundle 起——非 bundle 连 UN currentNotificationCenter
// 都会 abort）：
//   moon build experiment/notify_mac_probe --target native
//   scripts/make_app.sh notify-mac-probe "通知栈探针"
//   open _build/apps/NotifyMacProbe.app
// 日志：NATIVEGUI_NOTIFY_LOG 指到文件可带出桩侧 auth/post/willPresent 读数：
//   NATIVEGUI_NOTIFY_LOG=/tmp/ngui-probe.log open _build/apps/NotifyMacProbe.app
// 期望：窗口在前台时点 open 起来 → 两条都弹横幅（探针 J 档已证 UN 路径本身
// 是通的）；不弹则 MoonBit 栈与纯 ObjC 探针存在真实差异，读数即证据。
fn main {
  let host = match @widget.App::new(280, 120, "通知栈探针") {
    Some(a) => a
    None => {
      println("NOTIFY-MAC-PROBE FAIL (窗建不出)")
      return
    }
  }
  host.mount([])
  println("NOTIFY-MAC-PROBE start supported=\{@win.notify_supported()}")
  // 忙循环档:16ms 一拍持续 schedule_paint,复现 showcase 的高频重绘
  // (SHOWCASE-PROF 实测 ~126fps)——验证「忙到 runloop 转不进 → UN 回调超时」
  let busy = Ref(true)
  fn tick_paint() -> Unit {
    if busy.val {
      host.schedule_paint()
      let _ = host.timer(16, tick_paint)
    }
  }

  let _ = host.timer(300, tick_paint)
  // 2 秒后发:此刻正处于忙循环中,模拟 showcase 点按钮时的主循环形态
  let _ = host.timer(2000, fn() {
    println("NOTIFY-MAC-PROBE sending kind=0 (busy)")
    let id0 = @win.notify_send(0, "栈探针 忙循环", "忙循环中发的 kind=2(带声)", 2)
    println("NOTIFY-MAC-PROBE sent kind=0 id=\{id0}")
    let id2 = @win.notify_send(0, "栈探针 忙循环2", "第二条 kind=2(带声)", 2)
    println("NOTIFY-MAC-PROBE sent kind=2 id=\{id2}")
  })
  // 停忙,让主循环回到空闲长等待,看迟到的 delegate 会不会补进来
  let _ = host.timer(6000, fn() {
    busy.val = false
    println("NOTIFY-MAC-PROBE busy off")
  })
  // 14 秒后自动退出
  let _ = host.timer(14000, fn() {
    println("NOTIFY-MAC-PROBE done")
    host.shutdown()
  })
  host.run()
}
