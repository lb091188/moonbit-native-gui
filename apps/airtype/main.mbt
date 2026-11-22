// airtype 主入口：async main + 外部事件循环（loop.mbt 的 GuiExternalLoop）。
// GUI 与服务同进程同主线程：poll 里跑 GUI 拍，async 任务组里跑投字服务，
// GUI 退出 → done 条件变量唤醒 → 任务组收口、服务自动关停。

///|
fn init {
  // 官方契约：事件循环启动前挂外部循环（fn init 或 async main 首段均可）
  @async.set_external_event_loop(g_gui_loop)
}

///|
async fn main {
  // GUI 自有退出通道（SIGINT → @shell.quit_requested）保留：关掉 async 的
  // 信号截胡，否则 Ctrl+C 会取消 async main 而不走 GUI 的收口路径
  @signal.set_global_cancellation_signals([])
  let token = gen_token()
  let app = build_app()
  let mounted = @ui.mount_window(
    [page(app)],
    title="airtype",
    width=460,
    height=640,
    handle=
      fn(a : @widget.WindowHost) {
        ignore(a.follow_system_theme())
      },
  )
  match mounted {
    None => println("airtype: skip（本平台没有窗口后端或没有显示服务）")
    Some(a) => {
      g_gui_loop.host = Some(a)
      @async.with_task_group(
        group => {
          group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
            service_run(app, token) catch {
              e => println("airtype: service err \{e}")
            }
          }
          // GUI 退出（poll 里 step_no_wait 返回 false）前一直挂起
          g_gui_loop.done.wait()
        },
      )
      println("airtype: done")
    }
  }
}
