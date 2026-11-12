// 系统能力示例：系统集成（文件对话框 / 消息框 / 通知 / 剪贴板 / 定时器 / 托盘 /
// 自启 / 外部打开 / 系统信息与音量 / 单实例 / 平台专属 / 应用自更新）+ 只读探测
// （系统与桌面 / 显示器 / 应用与文件 / 浏览器数据 / 剪贴板与桌面状态）。
// 布局是左侧分组菜单 + 右侧滚动正文（`@shared.menu_page`），不再是段条形式。
//
// main 负责应用级设施（句柄类单例不进段，段随页面装配重建会另造句柄）：
//   - 单实例声称：main 启动即 claim，已有实例唤起它并退出；wake 回调计数 + 冒提示
//   - 托盘单例：main 挂载期建、默认提示语 + 左键计数，200ms 派发泵也在 main
//   - D-Bus 排期通道 + 200ms 泵（Linux 托盘/通知的到件路径）

///|
/// 窗口标题
const SYS_TITLE : String = "系统能力"

///|
/// 托盘错误 → 可读串（没后端 / 图标没建成 / 后端具体失败）。
fn tray_err_text(e : @shell.TrayError) -> String {
  match e {
    @shell.TrayError::Unsupported => @shared.tx("本平台没有托盘后端")
    @shell.TrayError::IconLoadFailed => @shared.tx("图标加载失败")
    @shell.TrayError::Backend(msg) =>
      @shared.tr_with(
        "dyn.tray_backend_failed",
        [("m", msg)],
        "托盘后端失败：\{msg}",
      )
  }
}

///|
fn main {
  // 剪贴板段与代码区「复制」都要写系统剪贴板；在建 UI 之前打开
  @ui.use_system_clipboard(true)
  let toast_push = @ui.toast_layer(duration_ms=2600)
  @shared.code_toast.val = Some(toast_push)
  let app : @shared.App = {
    toast: toast_push,
    host: Ref(None),
    tray: Ref(None),
    tray_clicks: @base.Store::new(0),
    tray_note: @base.Store::new(@shared.tx("（还没建托盘）")),
    inst_wakes: @base.Store::new(0),
    inst_note: @base.Store::new(@shared.tx("（还没声称过）")),
  }
  // 单实例（@shell 门面，三平台各自的臂）：先声称；已有实例就唤起它并退出
  match @shell.instance_claim(@shared.sys_app_id) {
    Ok(@shell.Primary) => {
      let arm = match @shell.instance_arm(@shared.sys_app_id) {
        Some(b) => @shell.instance_backend_name(b)
        None => "?"
      }
      app.inst_note.set(
        @shared.tr_with(
          "dyn.inst_primary",
          [("a", arm)],
          "本进程是首实例（后端 \{arm}）",
        ),
      )
      @shell.on_instance_wake(fn(_args : Array[String]) -> Unit {
        app.inst_wakes.set(app.inst_wakes.get() + 1)
        app.toast_push(@shared.tx("已被第二实例唤起"), @ui.Info)
      })
    }
    Ok(@shell.Existing) => {
      let _ = @shell.instance_wake(@shared.sys_app_id, [])
      println("SYS-INST: 已有实例，已唤起并退出")
      return
    }
    Err(e) => println("SYS-INST: 单实例降级（\{e}）")
  }
  let mounted = @ui.mount_window(
    [
      @ui.col(
        [
          @shared.menu_page([
            ("系统集成", @pages.system_sections(app)),
            ("系统能力探测", @pages.sysprobe_sections(app)),
          ]),
        ],
        grow=1.0,
      ),
    ],
    title=SYS_TITLE,
    width=1180,
    height=780,
    handle=fn(a : @widget.WindowHost) {
      app.host.val = Some(a)
      // 单实例的 D-Bus 接线：排期通道与 200ms 泵都由宿主给（无总线时空转）
      @dbus.dbus_set_post_delayed(fn(ms : Int32, f : () -> Unit) -> Unit {
        let _ = a.timer(ms, f)
      })
      let pump : Ref[() -> Unit] = Ref(fn() { () })
      pump.val = fn() -> Unit {
        @dbus.dbus_pump()
        // 单实例抽帧：套接字/Win32 臂在这拍落地，D-Bus 臂上面那泵已直达
        let _ = @shell.dispatch_instance_wake()
        let _ = a.timer(200, pump.val)
      }
      (pump.val)()
      // 托盘：应用级单例，main 挂载期建（不进段：页面装配重建会另造托盘句柄，
      // 旧图标成孤儿）。不传图标 = 库内置月牙，三平台同一张脸。
      match @shell.Tray::new("libyue-sysdemo-tray") {
        Ok(t) => {
          t.set_tooltip_localized(
            fn() -> String { @shared.tx("系统能力演示") },
            fn() -> String { @shared.tx("左键计数") },
          )
          t.on_click(fn() {
            app.tray_clicks.update(fn(n) { n + 1 })
            app.toast_push(@shared.tx("托盘左键被点了"), @ui.Info)
          })
          app.tray.val = Some(t)
          app.tray_note.set(
            @shared.tr_with(
              "dyn.tray_created",
              [("b", t.backend_name())],
              "已建（\{t.backend_name()}）",
            ),
          )
        }
        Err(e) => app.tray_note.set(tray_err_text(e))
      }
      // 托盘事件派发：200ms 轮询表（宿主循环没有每帧钩子）
      let tray_tick : Ref[() -> Unit] = Ref(fn() { () })
      tray_tick.val = fn() -> Unit {
        let _ = @shell.dispatch_tray_event()
        let _ = a.timer(200, tray_tick.val)
      }
      (tray_tick.val)()
    },
  )
  match mounted {
    None =>
      println("SYS-SKIP: 本平台没有窗口后端或没有显示服务")
    Some(host) => {
      println("SYS-READY title=\{SYS_TITLE}")
      host.run()
    }
  }
}
