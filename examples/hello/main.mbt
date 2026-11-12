// 你好窗口（.mng 单文件形态入门样例）+ 基本窗口示例（多窗 + 托盘轻演示）
// + 窗口功能八段（pages_window.mbt，迁自 components 窗口页）。
//
// 四条口径：
// ① 页面主体来自 hello.mng（`mng gen` 产 hello.gen.mbt，生成码入库）；
// ② 基本窗口示例是命令式代码：三档预设窗口（备忘 / 调色 / 关于）的按钮
//    按开/关状态切换（同一档只留一扇，关掉才能再开），按钮行走 flexbox wrap
//    按窗宽换行；子窗自带「关闭此窗」（`WindowHost::close_window`），窗口数由
//    轮询表刷新到状态行；
// ③ 托盘是「事件循环依赖类能力」的最小面：单例 + 提示语 + 左键计数，200ms
//    派发泵；Linux 的 D-Bus 排期通道同泵接线；
// ④ 窗口功能八段纵向排在入门页与基本窗口示例之后，整页包一层纵滚——
//    展示形态从简（无 code 展示区、文案直写中文，详见 pages_window.mbt 头注释）。

///|
/// 窗口标题
const HELLO_TITLE : String = "你好，MoonBit"

///|
/// 子窗预设：名称 / 说明 / 宽 / 高。
let child_kinds : Array[(String, String, Int, Int)] = [
  ("备忘窗", "随手记一条备忘（演示窗，不做持久化）。", 360, 240),
  ("调色窗", "三块色卡：随深浅模式实时取主题色。", 380, 260),
  ("关于窗", "native-gui 入门样例：.mng 单文件页 + 命令式多窗 + 托盘。", 440, 320),
]

///|
/// 这扇子窗是否还活着（标题栏关 / 子窗按钮关都走同一判定）。
fn host_alive(h : @widget.WindowHost) -> Bool {
  let wid = h.wid()
  for x in @widget.host_windows() {
    if x.wid() == wid {
      return true
    }
  }
  false
}

///|
/// 开/关一档子窗：已开 → 关掉并清状态；未开 → 开一扇并记住句柄，禁止重复开。
fn toggle_child(
  owner : @widget.WindowHost,
  kind : (String, String, Int, Int),
  win_count : @base.Store[Int],
  open : @base.Store[Bool],
  slot : Ref[@widget.WindowHost?],
) -> Unit {
  let (name, desc, w, h) = kind
  match slot.val {
    Some(old) =>
      if host_alive(old) {
        old.close_window()
        slot.val = None
        open.set(false)
        win_count.set(owner.window_count())
        return
      } else {
        // 已自行关闭（标题栏 / 子窗按钮）：先清状态再按未开处理
        slot.val = None
        open.set(false)
      }
    None => ()
  }
  match owner.open_window(w, h, name) {
    None => println("HELLO-NEWWIN-FAIL: 新窗建不起来（窗口上限/平台拒绝）")
    Some(a2) => {
      slot.val = Some(a2)
      open.set(true)
      // 内容在建壳之后组（关闭按钮要捕获这扇窗自己的句柄）
      let body = @ui.col(
        [
          @ui.text(name, class=[@style.text_title]),
          @ui.text(desc, wrap=true),
          @ui.col([], grow=1.0),
          @ui.button("关闭此窗", on_click=fn() {
            a2.close_window()
            slot.val = None
            open.set(false)
            win_count.set(owner.window_count())
          }),
        ],
        padding=16.0,
        row_gap=8.0,
        grow=1.0,
      )
      a2.mount([body])
      win_count.set(owner.window_count())
    }
  }
}

///|
/// 托盘错误 → 可读串。
fn tray_err(e : @shell.TrayError) -> String {
  match e {
    @shell.TrayError::Unsupported => "本平台没有托盘后端"
    @shell.TrayError::IconLoadFailed => "图标加载失败"
    @shell.TrayError::Backend(msg) => "托盘后端失败：\{msg}"
  }
}

///|
fn main {
  let win_count : @base.Store[Int] = @base.Store::new(1)
  let tray_note : @base.Store[String] = @base.Store::new("托盘：（还没建）")
  let tray_clicks : @base.Store[Int] = @base.Store::new(0)
  // 主窗句柄在挂载后才就绪：按钮回调经 Ref 取用
  let host_ref : Ref[@widget.WindowHost?] = Ref(None)
  // 每档一份开关状态与窗口句柄：同一档只留一扇，按钮在「打开/关闭」间切换
  let child_open : Array[@base.Store[Bool]] = child_kinds.map(fn(_k) {
    @base.Store::new(false)
  })
  let child_hosts : Array[Ref[@widget.WindowHost?]] = child_kinds.map(fn(_k) {
    Ref(None)
  })
  // 基本窗口示例：按钮走 wrap，窗宽不够自动换行（flexbox 按需换行展示）
  let buttons : Array[@widget.Node] = []
  for i, kind in child_kinds {
    let (name, _, _, _) = kind
    let open = child_open[i]
    let slot = child_hosts[i]
    buttons.push(
      @widget.bind_node(open.signal(), fn(is_open) {
        @ui.button(if is_open { "关闭\{name}" } else { "打开\{name}" }, on_click=fn() {
          match host_ref.val {
            Some(a) => toggle_child(a, kind, win_count, open, slot)
            None => ()
          }
        })
      }),
    )
  }
  let playground = @ui.col(
    [
      @ui.text("基本窗口示例", class=[@style.text_title]),
      @ui.row(
        buttons,
        column_gap=8.0,
        class=[@style.style(flex_wrap=@yoga.Wrap, row_gap=8.0, min_width=0.0)],
      ),
      @ui.bind_label(win_count, fn(n) { "窗口数：\{n}（含主窗）" }),
      @ui.bind_label(tray_note, fn(s) { s }),
      @ui.bind_label(tray_clicks, fn(n) { "托盘左键：\{n} 次" }),
    ],
    padding=20.0,
    row_gap=8.0,
  )
  let mounted = @ui.mount_window(
    [
      // 整页纵滚：mng 入门页 + 基本窗口示例 + 窗口功能八段（迁移自
      // components 窗口页），纵向一块块、无左右分栏
      @ui.scroll_view(
        [hello(), playground] + window_sections(host_ref),
        @ui.ScrollState::new(),
        handle=fn(v) {
          v.node.set_width(@yoga.percent(100.0))
          v.node.set_flex_grow(1.0)
        },
      ),
    ],
    title=HELLO_TITLE,
    width=760,
    height=680,
    handle=fn(a : @widget.WindowHost) {
      host_ref.val = Some(a)
      // 界面与内置单色托盘图标随系统明暗实时切换
      ignore(a.follow_system_theme())
      // 托盘轻演示：单例 + 提示语 + 左键计数（不传图标 = 库内置单色图标）
      match @shell.Tray::new("libyue-hello-tray") {
        Ok(t) => {
          t.set_tooltip_localized(
            fn() -> String { HELLO_TITLE },
            fn() -> String { "左键计数" },
          )
          t.on_click(fn() {
            tray_clicks.update(fn(n) { n + 1 })
          })
          tray_note.set("托盘：已建（\{t.backend_name()}）")
        }
        Err(e) => tray_note.set("托盘：" + tray_err(e))
      }
      // 托盘派发 + 窗口数/开窗状态轮询同一条 200ms 表
      let tick : Ref[() -> Unit] = Ref(fn() { () })
      tick.val = fn() -> Unit {
        let _ = @shell.dispatch_tray_event()
        win_count.set(a.window_count())
        // 子窗被标题栏关掉时把开关状态收回（自关按钮已即时清）
        for i, slot in child_hosts {
          match slot.val {
            Some(h) =>
              if !host_alive(h) {
                slot.val = None
                child_open[i].set(false)
              }
            None => ()
          }
        }
        let _ = a.timer(200, tick.val)
      }
      (tick.val)()
      // 单实例 + D-Bus 排期泵：mng dev 的 HOT 补丁经这条通道送达
      match @shell.instance_claim("libyue.hello") {
        Ok(@shell.Primary) => {
          @shell.on_instance_wake(fn(args : Array[String]) -> Unit {
            if args.length() == 2 && args[0] == "--mng-hot" {
              match @mngdev.mng_dev_apply_from_file(args[1]) {
                Ok(_) => println("HELLO-DEV: 模板补丁已应用")
                Err(e) => println("HELLO-DEV: 补丁失败：" + e)
              }
            } else {
              println("HELLO-DEV: 被第二实例唤起（\{args.length()} 参）")
            }
          })
        }
        Ok(@shell.Existing) => {
          let _ = @shell.instance_wake("libyue.hello", [])
          println("HELLO-INST: 已有实例，已唤起并退出")
          return
        }
        Err(e) => println("HELLO-INST: 单实例降级（\{e}）")
      }
      @dbus.dbus_set_post_delayed(fn(ms : Int, f : () -> Unit) -> Unit {
        let _ = a.timer(ms, f)
      })
      let pump : Ref[() -> Unit] = Ref(fn() { () })
      pump.val = fn() -> Unit {
        @dbus.dbus_pump()
        let _ = @shell.dispatch_instance_wake()
        let _ = a.timer(200, pump.val)
      }
      (pump.val)()
    },
  )
  match mounted {
    None => {
      println("HELLO-SKIP: 本平台没有窗口后端或没有显示服务")
    }
    Some(host) => {
      println("HELLO-READY title=\{HELLO_TITLE}")
      host.run()
    }
  }
}
