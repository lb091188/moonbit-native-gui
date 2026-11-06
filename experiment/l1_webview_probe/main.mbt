///|
/// L1 呈现档 × webview 共存探针。
///
/// 窗口里放一个铺满的 webview pane，页面底色给「洋红」(#ff00ff)：屏幕窗口
/// 中心取到洋红 = 网页出像素；取到主题底色 = 网页被 L1 承载子窗口盖住。
/// 读数在窗口外做（XGetImage 取根窗对应像素），探针只负责把窗口摆好并保持。
fn main {
  let magenta = "<html><body style='margin:0;background:#ff00ff'>probe</body></html>"
  let holder : Ref[@widget.Widget?] = Ref(None)
  let body : @widget.Node = @ui.col(
    [
      @ui.col([], grow=1.0, handle=fn(c) { holder.val = Some(c) }),
    ],
    grow=1.0,
  )
  let setup = fn(a : @widget.WindowHost) -> Unit {
    // 与示例同序：首帧之后才建 webview（L1 承载子窗口此时已存在）
    let _ = a.timer(0, fn() -> Unit {
      match @web.webview_new(a, "about:blank") {
        Some(v) => {
          v.load_html(magenta)
          match holder.val {
            Some(c) => {
              let _ = v.node(grow=1.0).mount_into(c)
              println("L1WV-MOUNTED")
            }
            None => println("L1WV-HOLDER-NONE")
          }
        }
        None => println("L1WV-NOENGINE")
      }
    })
  }
  println("L1WV-GPU: \{@win.gpu_present_status()}")
  match @ui.mount_window([body], title="L1WV-PROBE", width=520, height=360, handle=setup) {
    None => println("L1WV-SKIP")
    Some(host) => {
      println("L1WV-READY")
      host.run()
    }
  }
}
