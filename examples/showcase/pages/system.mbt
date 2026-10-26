// 系统集成页：文件对话框 / 消息框 / 通知 / 剪贴板 / 定时器 / 托盘 / 自启 /
// 外部打开 / 系统信息 / 音量 / 单实例 / 平台专属能力（子进程、窗口管理、夜灯、
// 电源、剪贴板监视）。
//
// 四条口径：
// ① 未接的能力整段不放（按钮不摆，口径写进本草头与人工清单）：关闭拦截（无
//    should_close 钩子）、无边框透明窗（stub 无分层窗口透明度）、屏幕常亮（无
//    keep_awake）、休眠锁屏事件、电量与网络（无电源事件通道）——后四样待平台批；
// ② 演示位用「系统信息」（si_os/si_machine/si_memory/si_uptime + desktop_name），
//    另带「音量」段（vol_* 三平台门面已在）；
// ③ 通知走 `@shell.notify_send`（探测 + 结构化错误 + 后端名回显）；托盘走
//    `@shell.Tray`，dispatch 由 200ms 轮询表驱动（宿主循环没有每帧钩子）；
//    单实例走 `@shell.instance_*`：声称在 main 的启动路径，回调计数进 App.inst_wakes，
//    抽帧搭同一条 200ms 泵；
// ④ 文件对话框 parent 传宿主窗口 id（`App::wid().to_int64()`）。

///|
/// 自启动用的应用 id（reverse-DNS 形态：autostart_valid_app_id 要求至少一个点、
/// 元素不以数字或 '-' 开头）。
const AUTOSTART_APP_ID : String = "libyue.showcase"

///|
/// 宿主窗口 id → 对话框 parent（0 = 无父窗口；这里恒有父）。
fn dialog_parent(a : @widget.App) -> Int64 {
  a.wid().to_int64()
}

///|
/// 「用指定程序打开」的演示对象：Windows 记事本、Linux gedit、macOS 给
/// TextEdit 的可执行路径（这一档按 argv 直传，`open -a 应用名` 那种形态随
/// mac 平台批再接）。挑不到的平台给空串，按钮直接演示 SpawnFailed。
fn open_probe_app() -> String {
  match @sys.sys_platform() {
    "windows" => "notepad.exe"
    "linux" => "gedit"
    "macos" => "/System/Applications/TextEdit.app/Contents/MacOS/TextEdit"
    _ => ""
  }
}

///|
/// 自绘档演示位图：32×32 实心琥珀圆，SNI 口径的大端 ARGB（每像素 `A R G B`）。
/// 同一份字节交给 Win/mac 时由库内转成 BGRA 小端预乘，三平台拿到同一张脸。
fn amber_pixmap() -> (Int, Int, Bytes) {
  let w = 32
  let h = 32
  let r = 14.0
  (
    w,
    h,
    Bytes::makei(
      w * h * 4,
      fn(i) {
        let px = i / 4
        let x = (px % w).to_double() - 15.5
        let y = (px / w).to_double() - 15.5
        let off = i % 4
        if x * x + y * y > r * r {
          b'\x00'
        } else if off == 0 {
          b'\xff' // A
        } else if off == 1 {
          b'\xe8' // R
        } else if off == 2 {
          b'\xa3' // G
        } else {
          b'\x17' // B
        }
      },
    ),
  )
}

///|
/// 消息框返回值 → 可读串（编号归一的语义枚举，不记数字）。
fn msgbox_result_label(r : @win.MessageBoxResult) -> String {
  match r {
    @win.Ok => @shared.tx("确定")
    @win.Cancel => @shared.tx("取消")
    @win.Abort => @shared.tx("中止")
    @win.Retry => @shared.tx("重试")
    @win.Ignore => @shared.tx("忽略")
    @win.Yes => @shared.tx("是")
    @win.No => @shared.tx("否")
    @win.Failed => @shared.tx("弹框失败")
  }
}

///|
/// 系统集成页。页内私有状态（回显/托盘句柄/周期表句柄）不进共享 App。
pub fn page_system(app : @shared.App) -> @widget.Node {
  let file_out : @base.Store[String] = @base.Store::new(@shared.tx("（还没选过文件）"))
  let mb_out : @base.Store[String] = @base.Store::new(@shared.tx("（还没弹过框）"))
  let nt_out : @base.Store[String] = @base.Store::new(@shared.tx("（还没发过通知）"))
  let cb_out : @base.Store[String] = @base.Store::new(@shared.tx("（还没动过剪贴板）"))
  let timer_out : @base.Store[String] = @base.Store::new(@shared.tx("（表未起）"))
  let ticks : @base.Store[Int] = @base.Store::new(0)
  let auto_state : @base.Store[String] = @base.Store::new(@shared.tx("（未读）"))
  let ext_out : @base.Store[String] = @base.Store::new(@shared.tx("（还没打开过外部）"))
  let si_out : @base.Store[String] = @base.Store::new(@shared.tx("（点「刷新」读一次）"))
  let vol_out : @base.Store[String] = @base.Store::new(@shared.tx("（还没读过音量）"))
  // 平台专属能力：一个回显行管全部，剪贴板监视另带自己的行与句柄
  let plat_out : @base.Store[String] = @base.Store::new(@shared.tx("（还没动过）"))
  let watch_out : @base.Store[String] = @base.Store::new(@shared.tx("（监视未启动）"))
  let watcher : Ref[@sys.ClipboardWatcher?] = Ref(None)
  // 周期表句柄（0 = 没起）；停表用
  let tick_id : Ref[Int] = Ref(0)
  // 自启动开关：Store 是唯一态，subscribe 落进真实系统状态。
  // priming 标志：初值读取不算「用户改动」，不能反向写一遍系统
  let auto_on : @base.Store[Bool] = @base.Store::new(false)
  let auto_primed : Ref[Bool] = Ref(false)
  auto_on.subscribe(fn(v : Bool) -> Unit {
    if !auto_primed.val {
      return
    }
    if !@sys.autostart_supported() {
      auto_state.set(@shared.tx("本平台不支持开机自启"))
      return
    }
    let r = if v {
      @sys.autostart_enable(AUTOSTART_APP_ID)
    } else {
      @sys.autostart_disable(AUTOSTART_APP_ID)
    }
    match r {
      Ok(_) => auto_state.set(if v { @shared.tx("已开启（重新登录后生效）") } else { @shared.tx("已关闭") })
      Err(e) => auto_state.set(@shared.tr_with("dyn.autostart_write_failed", [("e", "\{e}")], "写入失败：\{e}"))
    }
  })
  match @sys.autostart_is_enabled(AUTOSTART_APP_ID) {
    Ok(v) => {
      auto_on.set(v)
      auto_state.set(if v { @shared.tx("已开启（重新登录后生效）") } else { @shared.tx("已关闭") })
    }
    Err(_) => auto_state.set(@shared.tx("读不到当前自启状态"))
  }
  auto_primed.val = true
  @shared.page([
    @shared.section(
      "文件",
      "文件对话框",
      "原生模态文件对话框：打开回显所选路径；保存把一行文本写进你选的文件。对话框挂在本窗口上（parent = 宿主窗口 id）。",
      [
        @ui.row(
          [
            @ui.button(@shared.tx("打开文件…"), on_click=fn() {
              match app.host.val {
                Some(a) => {
                  let dlg = @sys.FileDialog::new_open()
                  dlg.set_filters(@shared.tx("文本文件:txt,md|所有文件:*"))
                  if dlg.run_for_window(dialog_parent(a)) {
                    let p = dlg.get_result()
                    file_out.set(@shared.tr_with("dyn.file_picked", [("p", p)], "已选：\{p}"))
                    match @sys.sys_read_text_file(p) {
                      Some(t) => file_out.set(@shared.tr_with("dyn.file_picked_chars", [("p", p), ("n", t.length().to_string())], "已选：\{p}（读回 \{t.length()} 字符）"))
                      None => file_out.set(@shared.tr_with("dyn.file_picked_unreadable", [("p", p)], "已选：\{p}（读不出内容或不是文本）"))
                    }
                  } else {
                    file_out.set(@shared.tx("已取消"))
                  }
                  dlg.destroy()
                }
                None => ()
              }
            }),
            @ui.button(@shared.tx("保存文件…"), variant=@ui.Soft, on_click=fn() {
              match app.host.val {
                Some(a) => {
                  let dlg = @sys.FileDialog::new_save()
                  dlg.set_filters(@shared.tx("文本文件:txt|所有文件:*"))
                  dlg.set_filename("showcase.txt")
                  if dlg.run_for_window(dialog_parent(a)) {
                    let p = dlg.get_result()
                    file_out.set(
                      if @sys.sys_write_text_file(p, "libyue 演示板写入\n") {
                        "已写入：\{p}"
                      } else {
                        "写入失败：\{p}"
                      },
                    )
                  } else {
                    file_out.set(@shared.tx("已取消"))
                  }
                  dlg.destroy()
                }
                None => ()
              }
            }),
          ],
          column_gap=8.0,
        ),
        @ui.bind_label(file_out, fn(s) { s }),
      ],
      code=[
        "let dlg = @sys.FileDialog::new_open()",
        "dlg.set_filters(\"文本文件:txt,md|所有文件:*\")",
        "let parent = a.wid().to_int64() // 宿主窗口 id",
        "if dlg.run_for_window(parent) {",
        "  let p = dlg.get_result()",
        "  ignore(@sys.sys_read_text_file(p))",
        "}",
        "dlg.destroy()",
      ],
    ),
    @shared.section(
      "消息框",
      "原生消息框",
      "模态消息框（Win32 MessageBoxW / GTK 对话框）：信息档 × 是/否，错误档 × 是/否/取消。返回值归一成语义枚举，不记编号。",
      [
        @ui.row(
          [
            @ui.button(@shared.tx("信息 是/否"), on_click=fn() {
              let r = @win.show_message_box(
                @shared.tx("libyue 演示板"),
                @shared.tx("原生消息框：点「是」或「否」看回显。"),
                @win.Information,
                @win.YesNo,
              )
              mb_out.set(@shared.tr_with("dyn.msgbox_info", [("r", msgbox_result_label(r))], "信息档 → \{msgbox_result_label(r)}"))
            }),
            @ui.button(@shared.tx("错误 是/否/取消"), variant=@ui.Danger, on_click=fn() {
              let r = @win.show_message_box(
                @shared.tx("libyue 演示板"),
                @shared.tx("错误档：三个按钮都能收回语义。"),
                @win.Error,
                @win.YesNoCancel,
              )
              mb_out.set(@shared.tr_with("dyn.msgbox_error", [("r", msgbox_result_label(r))], "错误档 → \{msgbox_result_label(r)}"))
            }),
          ],
          column_gap=8.0,
        ),
        @ui.bind_label(mb_out, fn(s) { s }),
      ],
      code=[
        "let r = @win.show_message_box(",
        "  \"libyue 演示板\",",
        "  \"原生消息框：点「是」或「否」看回显。\",",
        "  Information,",
        "  YesNo,",
        ")",
        "match r { Yes => ... No => ... _ => ... }",
      ],
    ),
    @shared.section(
      "通知",
      "系统通知",
      "系统通知中心：普通通知与带进度条通知。后端不可用（无 dbus 会话等）时明说失败，不假装成功。macOS 只认从 .app bundle 里跑的进程——裸 `moon run` 下会报不可用，打包口 `scripts/make_app.sh showcase`。",
      [
        @ui.row(
          [
            @ui.button(@shared.tx("普通通知"), on_click=fn() {
              match @shell.notify_send(@shared.tx("libyue 演示板"), @shared.tx("构建完成"), @shared.tx("3 个目标已产出")) {
                Ok(id) => nt_out.set(@shared.tr_with("dyn.notif_sent", [("i", id.to_string())], "已发送 #\{id}"))
                Err(e) => nt_out.set(@shared.tr_with("dyn.notif_failed", [("e", "\{e}")], "发送失败：\{e}"))
              }
            }),
            @ui.button(@shared.tx("带进度 60%"), variant=@ui.Soft, on_click=fn() {
              match
                @shell.notify_send(
                  @shared.tx("libyue 演示板"),
                  @shared.tx("同步中"),
                  @shared.tx("已完成 60%"),
                  kind=1,
                  progress=60,
                ) {
                Ok(id) => nt_out.set(@shared.tr_with("dyn.notif_sent_progress", [("i", id.to_string())], "已发送 #\{id}（带进度）"))
                Err(e) => nt_out.set("发送失败：\{e}")
              }
            }),
          ],
          column_gap=8.0,
        ),
        @ui.bind_label(nt_out, fn(s) { s }),
        @ui.text(
          if @shell.notify_supported() {
            @shared.tx("通知后端可用")
          } else {
            @shared.tx("通知后端不可用（按钮会报失败）")
          },
          role=@ui.Secondary,
        ),
      ],
      code=[
        "match @shell.notify_send(",
        "  \"libyue 演示板\", \"构建完成\", \"3 个目标已产出\") {",
        "  Ok(id) => println(\"已发送 #\\{id}\")",
        "  Err(e) => println(\"失败: \\{e}\")",
        "}",
        "// 带进度：progress=60, kind=1",
      ],
    ),
    @shared.section(
      "剪贴板",
      "剪贴板",
      "读写系统剪贴板文本。写入后点「读取」验证（也可以直接粘到别的程序里）。",
      [
        @ui.row(
          [
            @ui.button(@shared.tx("写入文本"), on_click=fn() {
              cb_out.set(
                if @sys.clipboard_set_text(@shared.tx("libyue 演示板 · 剪贴板写入")) {
                  @shared.tx("已写入（去别处粘贴试试）")
                } else {
                  @shared.tx("写入失败（剪贴板不可用）")
                },
              )
            }),
            @ui.button(@shared.tx("读取剪贴板"), variant=@ui.Soft, on_click=fn() {
              match @sys.clipboard_get_text() {
                Some(t) => cb_out.set(@shared.tr_with("dyn.clip_read", [("t", t)], "读到：\{t}"))
                None => cb_out.set(@shared.tx("读不到（空或不可用）"))
              }
            }),
          ],
          column_gap=8.0,
        ),
        @ui.bind_label(cb_out, fn(s) { s }),
      ],
      code=[
        "@sys.clipboard_set_text(\"libyue 演示板 · 剪贴板写入\")",
        "match @sys.clipboard_get_text() {",
        "  Some(t) => println(\"读到: \\{t}\")",
        "  None => println(\"空或不可用\")",
        "}",
      ],
    ),
    @shared.section(
      "定时器",
      "定时器与延时任务",
      "宿主 `timer` 周期表（句柄可停）+ `set_timeout` 进程级单次延时。两族都自重排，不需要外部循环配合。",
      [
        @ui.row(
          [
            @ui.button(@shared.tx("1.5 秒后提示"), on_click=fn() {
              ignore(
                @shell.set_timeout(1500, fn() {
                  app.toast_push(@shared.tx("延时任务触发"), @ui.Success)
                }),
              )
              timer_out.set(@shared.tx("已排 1.5s 单次"))
            }),
            @ui.button(@shared.tx("起周期表(1s)"), variant=@ui.Soft, on_click=fn() {
              if tick_id.val != 0 {
                timer_out.set(@shared.tx("表已经在跑"))
              } else {
                match app.host.val {
                  Some(a) => {
                    let tick : Ref[() -> Unit] = Ref(fn() { () })
                    tick.val = fn() -> Unit {
                      ticks.update(fn(n) { n + 1 })
                      // 自重排的周期表：每次重排都要把**新句柄**记回 tick_id，
                      // 否则「停表」取消的是已经跑掉的那一号，表照旧在响
                      tick_id.val = a.timer(1000, tick.val)
                    }
                    tick_id.val = a.timer(1000, tick.val)
                    timer_out.set(@shared.tx("表已起（1s 一拍）"))
                  }
                  None => ()
                }
              }
            }),
            @ui.button(@shared.tx("停表"), variant=@ui.Text, on_click=fn() {
              match app.host.val {
                Some(a) =>
                  if tick_id.val != 0 {
                    ignore(a.cancel_timer(tick_id.val))
                    tick_id.val = 0
                    timer_out.set(@shared.tx("表已停"))
                  } else {
                    timer_out.set(@shared.tx("表没在跑"))
                  }
                None => ()
              }
            }),
          ],
          column_gap=8.0,
        ),
        @ui.bind_label(timer_out, fn(s) { s }),
        @ui.bind_label(ticks, fn(n) { @shared.tr_with("dyn.timer_ticks", [("n", n.to_string())], "周期表已响 \{n} 次") }),
      ],
      code=[
        "// 单次延时（进程级）",
        "ignore(@shell.set_timeout(1500, fn() {",
        "  app.toast_push(\"延时任务触发\", Success)",
        "}))",
        "// 周期表：回调里自重排，且每次都要记回新句柄才可停",
        "let id = a.timer(1000, tick)",
        "ignore(a.cancel_timer(id))",
      ],
    ),
    @shared.section(
      "托盘",
      "系统托盘",
      "托盘是应用级单例：由 main 在挂载期建好、默认挂上右键菜单并接左键计数，这一页只做「换提示 / 换图标」这类操作。句柄放页里不行——切语言会原地重挂本页，页内 Ref 每挂一次换一个新的，旧图标就成孤儿。提示语与菜单都登记在语言口上，换语言随广播重算；派发表也归 main（200ms 一拍，起表时宿主已就绪）。图标不传就是库内置月牙，三平台同一张脸。",
      [
        @ui.row(
          [
            @ui.button(@shared.tx("改提示"), variant=@ui.Soft, on_click=fn() {
              match app.tray.val {
                Some(t) => {
                  // 重新登记取串口：文案随语言、计数随左键一起走
                  t.set_tooltip_localized(
                    fn() -> String { @shared.tx("libyue 演示板") },
                    fn() -> String { @shared.tr_with("dyn.tray_tooltip", [("n", app.tray_clicks.get().to_string())], "提示已改 · \{app.tray_clicks.get()} 次左键") },
                  )
                  app.tray_note.set(@shared.tx("提示已改（悬停托盘图标可见）"))
                }
                None => app.tray_note.set(@shared.tx("本平台没有托盘后端"))
              }
            }),
            @ui.button(@shared.tx("换自绘图标"), variant=@ui.Soft, on_click=fn() {
              match app.tray.val {
                Some(t) => {
                  let (w, h, px) = amber_pixmap()
                  t.set_icon_pixmap(w, h, px)
                  app.tray_note.set(@shared.tx("图标已换成自绘琥珀圆"))
                }
                None => app.tray_note.set(@shared.tx("本平台没有托盘后端"))
              }
            }),
            @ui.button(@shared.tx("回内置图标"), variant=@ui.Text, on_click=fn() {
              match app.tray.val {
                Some(t) => {
                  t.set_icon_builtin()
                  app.tray_note.set(@shared.tx("图标已回库内置月牙"))
                }
                None => app.tray_note.set(@shared.tx("本平台没有托盘后端"))
              }
            }),
          ],
          column_gap=8.0,
        ),
        @ui.bind_label(app.tray_note, fn(s) { s }),
        @ui.bind_label(app.tray_clicks, fn(n) { @shared.tr_with("dyn.left_clicks", [("n", n.to_string())], "左键 \{n} 次") }),
      ],
      code=[
        "// 建托盘（main 挂载期，应用级单例）：不传 icon = 库内置月牙",
        "match @shell.Tray::new(\"libyue-showcase-tray\") {",
        "  Ok(t) => {",
        "    // 提示语/右键菜单登记进语言口：换语言随广播重算",
        "    t.set_tooltip_localized(",
        "      fn() { \"libyue 演示板\" },",
        "      fn() { \"左键计数 · W 族门面\" },",
        "    )",
        "    t.set_menu_localized(fn() { menu })",
        "    t.on_click(fn() { clicks.update(fn(n) { n + 1 }) })",
        "  }",
        "  Err(e) => ...",
        "}",
        "// 换图标：大端 ARGB 自绘位图（Win/mac 内部转 BGRA 预乘）",
        "t.set_icon_pixmap(32, 32, argb_bytes)",
        "t.set_icon_builtin() // 回库内置月牙",
        "// 派发表：宿主循环没有每帧钩子，200ms 一拍",
        "let _ = @shell.dispatch_tray_event()",
      ],
    ),
    @shared.section(
      "自启",
      "开机自启动",
      "开关直连真实自启动状态（Linux 写 ~/.config/autostart，Windows 写 Run 键）。重新登录后生效；关闭即撤销。",
      [
        @ui.row(
          [
            @ui.switch(auto_on, on_text=@shared.tx("开启自启"), off_text=@shared.tx("关闭自启")),
            @ui.bind_label(auto_state, fn(s) { s }),
          ],
          column_gap=8.0,
          align_items=@yoga.AlignItems::Center,
        ),
      ],
      code=[
        "// 读当前真实状态",
        "match @sys.autostart_is_enabled(\"libyue.showcase\") {",
        "  Ok(v) => on.set(v)",
        "  Err(_) => ...",
        "}",
        "// 开关即写系统",
        "@sys.autostart_enable(\"libyue.showcase\")",
        "@sys.autostart_disable(\"libyue.showcase\")",
      ],
    ),
    @shared.section(
      "外部",
      "打开外部",
      "把 URL 交给默认浏览器、把文件交给默认程序或指定程序、把路径交给文件管理器。文件走 `@sys.open_file` / `@sys.open_file_with`（相对路径按工作目录归一，路径不存在先给 `NotFound`，不把「打不开」说成「已交给系统」）；定位走 `@shell.reveal_in_file_manager`：Linux 先试会话总线的 `FileManager1.ShowItems`（打开并**选中**），不在线才退回 `xdg-open` 打开父目录（选中态丢失），Windows 直调 `explorer /select`（分隔符统一成反斜杠才会选中）。Ok 只表示已交给系统，之后归操作系统。",
      [
        @ui.row(
          [
            @ui.button(@shared.tx("打开 libyue.com"), on_click=fn() {
              match @sys.open_url("https://libyue.com") {
                Ok(_) => ext_out.set(@shared.tx("已交给默认浏览器"))
                Err(e) => ext_out.set(@shared.tr_with("dyn.open_failed", [("e", "\{e}")], "打开失败：\{e}"))
              }
            }),
            @ui.button(@shared.tx("在文件管理器显示 TODO.md"), variant=@ui.Soft, on_click=fn() {
              match @shell.reveal_in_file_manager("TODO.md") {
                Ok(_) => ext_out.set(@shared.tx("已交给文件管理器"))
                Err(e) => ext_out.set(@shared.tr_with("dyn.reveal_failed", [("e", "\{e}")], "显示失败：\{e}"))
              }
            }),
            @ui.button(@shared.tx("用默认程序打开 TODO.md"), variant=@ui.Soft, on_click=fn() {
              match @sys.open_file("TODO.md") {
                Ok(_) => ext_out.set(@shared.tx("已交给默认程序"))
                Err(e) => ext_out.set(@shared.tr_with("dyn.default_open_failed", [("e", "\{e}")], "默认程序打开失败：\{e}"))
              }
            }),
            @ui.button(@shared.tx("用指定程序打开 TODO.md"), variant=@ui.Soft, on_click=fn() {
              let app = open_probe_app()
              match @sys.open_file_with(app, "TODO.md") {
                Ok(_) => ext_out.set(@shared.tr_with("dyn.opened_with", [("a", app)], "已交给 \{app}"))
                Err(e) => ext_out.set(@shared.tr_with("dyn.chosen_open_failed", [("a", app), ("e", "\{e}")], "指定程序（\{app}）打开失败：\{e}"))
              }
            }),
            @ui.button(@shared.tx("用指定程序打开不存在的路径"), variant=@ui.Soft, on_click=fn() {
              match @sys.open_file_with(open_probe_app(), "no-such-file-zzz.md") {
                Ok(_) => ext_out.set(@shared.tx("已交给指定程序"))
                Err(e) => ext_out.set(@shared.tr_with("dyn.blocked_as_expected", [("e", "\{e}")], "按预期被拦下：\{e}"))
              }
            }),
          ],
          column_gap=8.0,
        ),
        @ui.bind_label(ext_out, fn(s) { s }),
      ],
      code=[
        "match @sys.open_url(\"https://libyue.com\") {",
        "  Ok(_) => println(\"已交给默认浏览器\")",
        "  Err(e) => println(\"失败: \\{e}\")",
        "}",
        "// 打开并选中：Linux 走 FileManager1.ShowItems，退回 xdg-open 父目录\n",
        "match @shell.reveal_in_file_manager(\"TODO.md\") { ... }",
        "// 用默认程序打开（相对路径按工作目录归一，路径不存在先给 NotFound）",
        "match @sys.open_file(\"TODO.md\") { ... }",
        "// 用指定程序打开：app 可以是 PATH 里的命令名或完整可执行路径",
        "match @sys.open_file_with(\"notepad.exe\", \"TODO.md\") { ... }",
      ],
    ),
    @shared.section(
      "信息音量",
      "系统信息与音量",
      "信息：发行版 / 机器 / 内存 / 开机时长 + 桌面环境（替代旧页「电量网络」——电源与网络事件本栈未接，随平台批）。音量：读当前音量/静音、设百分比、切静音（Linux pactl / Windows CoreAudio），后端不可用时按钮明说。",
      [
        @ui.row(
          [
            @ui.button(@shared.tx("刷新系统信息"), on_click=fn() {
              si_out.set(read_sysinfo())
            }),
            @ui.button(@shared.tx("读音量"), on_click=fn() {
              match @sys.vol_get() {
                Ok(v) => vol_out.set(@shared.tr_with("dyn.volume_now", [("v", v.volume.to_string()), ("m", v.muted.to_string()), ("s", v.sink)], "音量 \{v.volume}% 静音=\{v.muted}（\{v.sink}）"))
                Err(e) => vol_out.set(@shared.tr_with("dyn.read_failed", [("e", "\{e}")], "读取失败：\{e}"))
              }
            }),
            @ui.button(@shared.tx("设为 50%"), variant=@ui.Soft, on_click=fn() {
              match @sys.vol_set(50) {
                Ok(_) => vol_out.set(@shared.tx("已设为 50%"))
                Err(e) => vol_out.set("设置失败：\{e}")
              }
            }),
            @ui.button(@shared.tx("静音切换"), variant=@ui.Text, on_click=fn() {
              match @sys.vol_get() {
                Ok(v) =>
                  match @sys.vol_set_mute(!v.muted) {
                    Ok(_) => vol_out.set(if v.muted { @shared.tx("已取消静音") } else { @shared.tx("已静音") })
                    Err(e) => vol_out.set("设置失败：\{e}")
                  }
                Err(e) => vol_out.set("读取失败：\{e}")
              }
            }),
          ],
          column_gap=8.0,
        ),
        @ui.bind_label(si_out, fn(s) { s }),
        @ui.bind_label(vol_out, fn(s) { s }),
      ],
      code=[
        "match @sys.si_os() {",
        "  Ok(o) => println(\"\\{o.pretty_name} \\{o.version_id}\")",
        "  Err(_) => ...",
        "}",
        "// 同族：si_machine / si_memory / si_uptime / desktop_name",
        "match @sys.vol_get() {",
        "  Ok(v) => println(\"\\{v.volume}% muted=\\{v.muted}\")",
        "  Err(e) => ...",
        "}",
        "@sys.vol_set(50)",
        "@sys.vol_set_mute(true)",
      ],
    ),

    @shared.section(
      "单实例",
      "防多开与唤起已有实例",
      "三平台各一条原生通道、门面同一个 API：Windows 用 Local\\ 命名互斥体 + 隐藏窗口收 WM_COPYDATA；Linux 先争 D-Bus 知名名，没有会话总线时落 AF_UNIX 套接字；macOS 用 AF_UNIX 套接字。演示板启动时就声称了这个 app_id（见下方回显）。「读本机档」回显用的是哪一档、本进程收到过几条唤起；「自环唤起」由本进程给自己发一条，下一拍派发后切回首页并冒提示——真机双进程的验法：再开一个终端跑同一条 `moon run`，第二个进程打印 SHOWCASE-INST 后退出，已有窗口被唤回。",
      [
        @ui.row(
          [
            @ui.button(@shared.tx("读本机档"), on_click=fn() {
              let arm = match @shell.instance_arm(@shared.SHOWCASE_APP_ID) {
                Some(b) => @shell.instance_backend_name(b)
                None => "-"
              }
              app.inst_note.set(@shared.tr_with(
                "dyn.inst_state",
                [
                  ("a", arm),
                  ("n", app.inst_wakes.get().to_string()),
                  ("i", @shared.SHOWCASE_APP_ID),
                ],
                "app_id \{@shared.SHOWCASE_APP_ID} · 后端 \{arm} · 已收到唤起 \{app.inst_wakes.get()} 次",
              ))
            }),
            @ui.button(@shared.tx("自环唤起"), variant=@ui.Soft, on_click=fn() {
              match @shell.instance_wake(@shared.SHOWCASE_APP_ID, ["系统集成页"]) {
                Ok(_) => app.inst_note.set(@shared.tx("已发出唤起：下一拍切回首页并冒提示"))
                Err(e) => app.inst_note.set(
                  @shared.tr_with(
                    "dyn.inst_wake_failed",
                    [("e", e.to_string())],
                    "唤起失败：\{e}",
                  ),
                )
              }
            }),
            @ui.text(
              @shared.tx("唤起回调由 main 挂：切回首页 + 提示 + 计数"),
              role=@ui.Secondary,
            ),
          ],
          column_gap=8.0,
          align_items=@yoga.AlignItems::Center,
        ),
        @ui.bind_label(app.inst_note, fn(s) { s }),
      ],
      code=[
        "match @shell.instance_claim(\"com.moonbitlibyue.showcase\") {",
        "  Ok(@shell.Primary) => ...   // 首实例：窗口照常开",
        "  Ok(@shell.Existing) => ...  // 已有实例：唤起后自己退出",
        "  Err(e) => println(\"降级：\\{e}\"),",
        "}",
        "@shell.on_instance_wake(fn(args) { show_window() })",
        "// 宿主每拍抽一次（套接字/Win32 臂）；D-Bus 臂在 dbus_pump 里直达",
        "let _ = @shell.dispatch_instance_wake()",
      ],
    ),

    @shared.section(
      "平台专属",
      "子进程与平台专属能力",
      "这一组在路线图上都是「已实现」，但**对位只在部分平台**：按钮全摆出来，本机没有就当场报原因，不藏也不假装能用。`pr_run` 三平台都有（带超时与输出捕获）；窗口管理走 `wmctrl`、夜间色温走 `redshift` 或 `xrandr`、剪贴板监视轮询 `xclip` / `xsel`，这三样只有 Linux X11；电源计划 Linux 走 `powerprofilesctl`、Windows 走 PowerGet / SetActiveScheme。",
      [
        @ui.row(
          [
            @ui.button(@shared.tx("跑子进程"), on_click=fn() {
              let is_win = @sys.sys_platform() == "windows"
              let r = if is_win {
                @sys.pr_run("cmd", ["/c", "echo hello from pr_run"])
              } else {
                @sys.pr_run("sh", ["-c", "echo hello from pr_run"])
              }
              match r {
                Ok(o) =>
                  plat_out.set(
                    @shared.tr_with(
                      "dyn.proc_ok",
                      [("c", o.exit_code.to_string()), ("s", o.stdout.trim().to_owned())],
                      "子进程退出码 \{o.exit_code}，输出：\{o.stdout.trim()}",
                    ),
                  )
                Err(e) => plat_out.set("子进程失败：\{e}")
              }
            }),
            @ui.button(@shared.tx("跑超时档"), variant=@ui.Soft, on_click=fn() {
              let is_win = @sys.sys_platform() == "windows"
              let r = if is_win {
                @sys.pr_run("cmd", ["/c", "ping -n 3 127.0.0.1"], timeout_ms=150)
              } else {
                @sys.pr_run("sh", ["-c", "sleep 2"], timeout_ms=150)
              }
              match r {
                Ok(o) => plat_out.set("超时档竟然跑完了，退出码 \{o.exit_code}")
                Err(e) => plat_out.set("超时档按预期失败：\{e}")
              }
            }),
            @ui.text(@shared.tx("pr_run：命令 + 参数 + 超时，回 stdout 与退出码"), role=@ui.Secondary),
          ],
          column_gap=8.0,
          align_items=@yoga.AlignItems::Center,
        ),
        @ui.row(
          [
            @ui.button(@shared.tx("辅助功能权限"), on_click=fn() {
              match @sys.permission_probe(@sys.PermAccessibility) {
                Ok(@sys.PermGranted) =>
                  plat_out.set(@shared.tx("辅助功能：已授权"))
                Ok(_) => {
                  let _ = @sys.permission_request(@sys.PermAccessibility)
                  plat_out.set(
                    @shared.tx("辅助功能：未授权，已弹系统引导框——授权后回来重探"),
                  )
                }
                Err(e) => plat_out.set("辅助功能权限探测失败：\{e}")
              }
            }),
            @ui.button(@shared.tx("屏幕录制权限"), variant=@ui.Soft, on_click=fn() {
              match @sys.permission_probe(@sys.PermScreenRecording) {
                Ok(@sys.PermGranted) =>
                  plat_out.set(@shared.tx("屏幕录制：已授权"))
                Ok(_) => {
                  let _ = @sys.permission_request(@sys.PermScreenRecording)
                  plat_out.set(
                    @shared.tx("屏幕录制：未授权，已弹系统引导框——授权后回来重探"),
                  )
                }
                Err(e) => plat_out.set("屏幕录制权限探测失败：\{e}")
              }
            }),
            @ui.text(
              @shared.tx("permission_probe / permission_request（mac）"),
              role=@ui.Secondary,
            ),
          ],
          column_gap=8.0,
          align_items=@yoga.AlignItems::Center,
        ),
        @ui.row(
          [
            @ui.button(@shared.tx("列窗口"), on_click=fn() {
              if !@sys.win_supported() {
                plat_out.set(@shared.tx("窗口管理：本平台没有窗口枚举后端"))
              } else {
                match @sys.win_list() {
                  Ok(ws) => {
                    let sb = StringBuilder()
                    sb.write_string("窗口 \{ws.length()} 个（列前 5）：\n")
                    let n = if ws.length() > 5 { 5 } else { ws.length() }
                    for i in 0..<n {
                      sb.write_string("  \{ws[i].id} · \{ws[i].title}\n")
                    }
                    plat_out.set(sb.to_string())
                  }
                  Err(e) => plat_out.set("窗口列表读不到：\{e}")
                }
              }
            }),
            @ui.button(@shared.tx("激活第一扇"), variant=@ui.Soft, on_click=fn() {
              if !@sys.win_supported() {
                plat_out.set(@shared.tx("激活窗口：本平台没有窗口枚举后端"))
              } else {
                match @sys.win_list() {
                  Ok(ws) =>
                    if ws.length() == 0 {
                      plat_out.set(@shared.tx("没有可激活的窗口"))
                    } else {
                      match @sys.win_activate(ws[0].id) {
                        Ok(_) => plat_out.set("已激活：\{ws[0].title}")
                        Err(e) => plat_out.set("激活失败：\{e}")
                      }
                    }
                  Err(e) => plat_out.set("窗口列表读不到：\{e}")
                }
              }
            }),
            @ui.text(@shared.tx("win_list / win_activate / win_close"), role=@ui.Secondary),
          ],
          column_gap=8.0,
          align_items=@yoga.AlignItems::Center,
        ),
        @ui.row(
          [
            @ui.button(@shared.tx("夜间色温 60%"), on_click=fn() {
              match @sys.nl_set_temperature(60) {
                Ok(_) => plat_out.set(@shared.tx("夜间色温已设 60%（redshift 优先，否则 xrandr gamma）"))
                Err(@sys.NightlightError::Unsupported) =>
                  plat_out.set(@shared.tx("夜间色温：本机没有 redshift 也没有可用 xrandr 输出"))
                Err(e) => plat_out.set("夜间色温设置失败：\{e}")
              }
            }),
            @ui.button(@shared.tx("色温复位"), variant=@ui.Text, on_click=fn() {
              match @sys.nl_reset() {
                Ok(_) => plat_out.set(@shared.tx("夜间色温已复位"))
                Err(@sys.NightlightError::Unsupported) =>
                  plat_out.set(@shared.tx("夜间色温复位：本机没有色温后端"))
                Err(e) => plat_out.set("复位失败：\{e}")
              }
            }),
            @ui.button(@shared.tx("读电源计划"), variant=@ui.Soft, on_click=fn() {
              if !@sys.pp_supported() {
                plat_out.set(@shared.tx("电源计划：本机没有 powerprofilesctl（Linux）或 PowerGet（Windows）"))
              } else {
                match @sys.pp_current() {
                  Ok(cur) =>
                    match @sys.pp_profiles() {
                      Ok(ps) => {
                        let names : Array[String] = []
                        for x in ps {
                          names.push(x.to_string())
                        }
                        plat_out.set(
                          @shared.tr_with(
                            "dyn.pp_now",
                            [("c", cur.to_string()), ("a", names.join(" / "))],
                            "当前电源计划：\{cur}；可选：\{names.join(" / ")}",
                          ),
                        )
                      }
                      Err(e) => plat_out.set("电源计划列表读不到：\{e}")
                    }
                  Err(e) => plat_out.set("当前电源计划读不到：\{e}")
                }
              }
            }),
            @ui.button(@shared.tx("切性能档"), variant=@ui.Text, on_click=fn() {
              match @sys.pp_set(@sys.PowerProfile::PPerformance) {
                Ok(_) => plat_out.set(@shared.tx("电源计划已切到性能档"))
                Err(e) => plat_out.set("切换失败：\{e}")
              }
            }),
          ],
          column_gap=8.0,
        ),
        @ui.row(
          [
            @ui.button(@shared.tx("启动剪贴板监视"), on_click=fn() {
              match watcher.val {
                Some(_) => watch_out.set(@shared.tx("监视已经在跑（改一下剪贴板试试）"))
                None => {
                  let w = @sys.cbw_start_watch(
                    fn(ms : Int, f : () -> Unit) -> Unit {
                      match app.host.val {
                        Some(a) => ignore(a.timer(ms, f))
                        None => ()
                      }
                    },
                    interval_ms=800,
                    fn(text : String) -> Unit {
                      let t = if text.length() > 40 {
                        sp_clip_text(text, 40)
                      } else {
                        text
                      }
                      watch_out.set("剪贴板变了：\{t}")
                    },
                  )
                  watcher.val = Some(w)
                  watch_out.set(@shared.tx("剪贴板监视已启动（800ms 轮询，仅 Linux X11）"))
                }
              }
            }),
            @ui.button(@shared.tx("停止监视"), variant=@ui.Text, on_click=fn() {
              match watcher.val {
                Some(w) => {
                  @sys.cbw_stop(w)
                  watcher.val = None
                  watch_out.set(@shared.tx("剪贴板监视已停止"))
                }
                None => watch_out.set(@shared.tx("监视本来就没起"))
              }
            }),
            @ui.text(@shared.tx("cbw_start_watch：宿主 timer 当排期通道"), role=@ui.Secondary),
          ],
          column_gap=8.0,
          align_items=@yoga.AlignItems::Center,
        ),
        @ui.bind_label(plat_out, fn(s) { s }),
        @ui.bind_label(watch_out, fn(s) { s }),
      ],
      code=[
        "// 子进程（三平台）：命令 + 参数 + 超时，回 stdout 与退出码",
        "match @sys.pr_run(\"sh\", [\"-c\", \"echo hello\"], timeout_ms=2000) {",
        "  Ok(o) => println(\"{o.exit_code}: {o.stdout}\")",
        "  Err(e) => println(\"{e}\")",
        "}",
        "// 窗口管理（仅 Linux X11，走 wmctrl）",
        "match @sys.win_list() {",
        "  Ok(ws) => @sys.win_activate(ws[0].id)",
        "  Err(e) => ...",
        "}",
        "// 夜间色温（仅 Linux）",
        "@sys.nl_set_temperature(60)",
        "@sys.nl_reset()",
        "// 电源计划（Linux / Windows）",
        "@sys.pp_set(@sys.PowerProfile::PPerformance)",
        "// 剪贴板监视（仅 Linux X11）：排期通道由宿主 timer 给",
        "let w = @sys.cbw_start_watch(fn(ms, f) { app.timer(ms, f) }, cb=fn(t) { ... })",
        "@sys.cbw_stop(w)",
      ],
    ),
  ])
}

///|
/// 系统信息一次读完拼成一屏（读不到的项标注原因，不静默丢）。
fn read_sysinfo() -> String {
  let sb = StringBuilder()
  match @sys.si_os() {
    Ok(o) => {
      sb.write_string("系统：\{o.pretty_name}")
      if o.version_id.length() > 0 {
        sb.write_string("（\{o.version_id}）")
      }
      sb.write_string("\n")
    }
    Err(_) => sb.write_string("系统：本平台读不到发行版\n")
  }
  match @sys.si_machine() {
    Ok(m) => sb.write_string("机器：\{m.vendor} \{m.product}\n")
    Err(_) => sb.write_string("机器：本平台读不到\n")
  }
  match @sys.si_memory() {
    Ok(mm) =>
      sb.write_string(
        "内存：可用 \{mm.available_kb / 1024} MB / 共 \{mm.total_kb / 1024} MB\n",
      )
    Err(_) => sb.write_string("内存：本平台读不到\n")
  }
  match @sys.si_uptime() {
    Ok(u) => sb.write_string("开机：\{u.to_int()} 秒\n")
    Err(_) => sb.write_string("开机时长：本平台读不到\n")
  }
  sb.write_string("桌面：\{@sys.desktop_name()}")
  sb.to_string()
}

///|
/// 按字符截断到前 n 个（超出补省略号）：剪贴板回显用，避免长文本顶穿一行。
fn sp_clip_text(s : String, n : Int) -> String {
  let buf = StringBuilder()
  let mut i = 0
  for ch in s {
    if i >= n {
      break
    }
    buf.write_char(ch)
    i = i + 1
  }
  if i >= n {
    buf.write_string("…")
  }
  buf.to_string()
}
