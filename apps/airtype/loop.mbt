// GUI 外部事件循环适配层：把 native-gui 的「等平台事件 + 跑一拍」接进
// core/async 的 ExternalEventLoop。async 只把内核等待放专用线程，全部
// MoonBit 代码（含服务回调与 GUI 拍）都留主线程——服务收到手机文本后直接
// 调注入门面，无跨线程队列。

///|
/// 直链平台唤醒原语：wakeup 回调在 async 的专用等待线程被调，官方契约只许
/// 纯 C 调用——wm_wakeup 投平台唤醒事件，不做任何 MoonBit 引用计数操作。
extern "c" fn ffi_platform_wakeup() -> Unit = "wm_wakeup"

///|
/// GUI 循环适配器。host 在挂窗后注入；GUI 退出经 done 通知 async main 收口。
struct GuiExternalLoop {
  mut host : @widget.WindowHost?
  done : @async.Cond
}

///|
/// 进程级单例：fn init 挂给 async（须在事件循环启动前），async main 里填 host。
let g_gui_loop : GuiExternalLoop = { host: None, done: @async.Cond() }

///|
/// poll 超时与 GUI 定时预算取小；双方都无限等时封顶 250ms——状态刷新类
/// 定时器最迟 250ms 一拍，不无限睡。
fn poll_budget(timeout? : Int32) -> Int32 {
  let a = timeout.unwrap_or(-1)
  let g = match @shell.host_loop().wait_budget(@win.now_ms()) {
    Some(ms) => ms
    None => -1
  }
  let mut ms = if a < 0 {
    g
  } else if g < 0 {
    a
  } else if a < g {
    a
  } else {
    g
  }
  if ms < 0 || ms > 250 {
    ms = 250
  }
  ms
}

///|
pub impl @external_loop_integration.ExternalEventLoop for GuiExternalLoop with fn poll(
  self,
  timeout?,
) {
  let _ = @win.wait(poll_budget(timeout?))
  match self.host {
    Some(h) =>
      if !h.step_no_wait() {
        self.done.signal()
      }
    None => ()
  }
}

///|
pub impl @external_loop_integration.ExternalEventLoop for GuiExternalLoop with fn get_wakeup_callback_for_foreign_thread(
  _self,
) {
  () => ffi_platform_wakeup()
}

///|
pub impl @external_loop_integration.ExternalEventLoop for GuiExternalLoop with fn terminate(
  _self,
) {
  // GUI 资源拆解已随退出拍里的 shutdown 走完，这里无额外收口
  ()
}
