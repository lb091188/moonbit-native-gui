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
        // 首启主动引导：未授权直接弹系统引导框并直达设置页（已授权/无需授权
        // 的启动保持静默，不反复打扰）
        match @sys.permission_probe(@sys.PermAccessibility) {
          Ok(@sys.PermGranted) | Ok(@sys.PermNotNeeded) => ()
          _ => go_perm()
        }
        // 单实例：mng dev 的 HOT 补丁经这条通道送达
        match @shell.instance_claim("libyue.airtype") {
          Ok(@shell.Primary) => {
            @shell.on_instance_wake(fn(args : Array[String]) -> Unit {
              if args.length() == 2 && args[0] == "--mng-hot" {
                match @mngdev.mng_dev_apply_from_file(args[1]) {
                  Ok(_) => println("AIRTYPE-DEV: 模板补丁已应用")
                  Err(e) => println("AIRTYPE-DEV: 补丁失败：" + e)
                }
              } else {
                println("AIRTYPE-DEV: 被第二实例唤起（\{args.length()} 参）")
              }
            })
          }
          Ok(@shell.Existing) => {
            let _ = @shell.instance_wake("libyue.airtype", [])
            println("AIRTYPE-INST: 已有实例，已唤起并退出")
            return
          }
          Err(e) => println("AIRTYPE-INST: 单实例降级（\{e}）")
        }
        // 唤醒派发泵：单实例通道的事件 200ms 一拍抽掉
        let pump : Ref[() -> Unit] = Ref(fn() { () })
        pump.val = fn() -> Unit {
          let _ = @shell.dispatch_instance_wake()
          let _ = a.timer(200, pump.val)
        }
        (pump.val)()
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
