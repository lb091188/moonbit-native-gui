// 画板与富文本示例：交互画板（Pointer 手绘 × Keyboard 画线）+ Painter 自绘 +
// AttributedText 富文本 + 字体/线型/虚线/裁剪变换/位图各段。
//
// 形态要点：
//   - 起窗走 `@ui.mount_window` + `WindowHost::run`；主题深浅与主色跟随系统
//     （2s tick 读偏好，变了写 App，subscribe 落成 theme_apply）。
//   - 代码区「复制」回显走全局钩子 `@shared.code_toast`（main 注入 toast 层）。

///|
/// 窗口标题
const CANVAS_TITLE : String = "画板"

///|
/// 主题应用：跟随系统深浅，主色读系统（无主色概念的平台回落内置基准盘）。
fn apply_theme(app : @shared.App) -> Unit {
  let dark = app.dark_mode.get()
  @theme.theme_apply(
    if dark {
      @theme.dark_theme()
    } else {
      @theme.default_theme()
    },
  )
}

///|
fn main {
  // 代码区「复制」要写系统剪贴板；在建 UI 之前打开
  @ui.use_system_clipboard(true)
  let toast_push = @ui.toast_layer(duration_ms=2600)
  @shared.code_toast.val = Some(toast_push)
  let app : @shared.App = {
    toast: toast_push,
    dark_mode: @base.Store::new(@win.sys_color_scheme() == "dark"),
    accent: @base.Store::new(@win.sys_accent()),
    follow: @base.Store::new(true),
  }
  // 深浅任一变化即整体换主题；subscribe 注册不回调，故先应用一次
  app.dark_mode.subscribe(fn(_v) { apply_theme(app) })
  app.accent.subscribe(fn(_a) { apply_theme(app) })
  apply_theme(app)
  let mounted = @ui.mount_window(
    [
      @ui.col([@pages.page_canvas(app)], grow=1.0),
    ],
    title=CANVAS_TITLE,
    width=1100,
    height=800,
    handle=fn(a : @widget.WindowHost) {
      // 「跟随系统」轮询：开关打开时每 2 秒读一次系统深浅与主色，
      // 变了就写进 App（App 的 subscribe 再落成 theme_apply）
      let tick : Ref[() -> Unit] = Ref(fn() { () })
      tick.val = fn() -> Unit {
        if app.follow.get() {
          app.dark_mode.set(@win.sys_color_scheme() == "dark")
          app.accent.set(@win.sys_accent())
        }
        let _ = a.timer(2000, tick.val)
      }
      (tick.val)()
    },
  )
  match mounted {
    None => {
      println("CANVAS-SKIP: 本平台没有窗口后端或没有显示服务")
    }
    Some(host) => {
      println("CANVAS-READY title=\{CANVAS_TITLE}")
      host.run()
    }
  }
}
