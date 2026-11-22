// airtype 主入口：async main + 外部事件循环（loop.mbt 的 GuiExternalLoop）。
// GUI 页面来自 airtype.mng（mng build 产 airtype.gen.mbt，生成码入库）：
// 状态单例住 ui_state.mbt，服务侧写入、模板只读。GUI 退出 → done 条件变量
// 唤醒 → 任务组收口、服务自动关停。

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
  let mounted = @ui.mount_window(
    [airtype()],
    title="airtype",
    width=420,
    height=560,
    handle=
      fn(a : @widget.WindowHost) {
        ignore(a.follow_system_theme())
        // 授权重探：用户去系统设置勾选后回来，这里两秒内刷回「已授权」
        let perm_tick : Ref[() -> Unit] = Ref(fn() { () })
        perm_tick.val = fn() -> Unit {
          s_perm.set(perm_text())
          let _ = a.timer(2000, perm_tick.val)
        }
        (perm_tick.val)()
        // 窗口级纵滚：任一页内容超高时整页滚动
        a.enable_root_scroll()
      },
  )
  match mounted {
    None => println("airtype: skip（本平台没有窗口后端或没有显示服务）")
    Some(a) => {
      g_gui_loop.host = Some(a)
      @async.with_task_group(
        group => {
          group.spawn_bg(no_wait=true, allow_failure=true) <| () => {
            service_run(token) catch {
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
