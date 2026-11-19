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
/// 子窗预设：名称 / 宽 / 高（内容按档在 `child_content` 分造）。
let child_kinds : Array[(String, Int, Int)] = [
  ("备忘窗", 360, 240),
  ("调色窗", 380, 260),
  ("关于窗", 440, 320),
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
/// 色卡行：token 取色的小色块 + 标签，随主题深浅实时换色。
fn swatch_row(token : String, label : String) -> @widget.Node {
  @ui.row(
    [
      @ui.view(
        [],
        background_color=token,
        width=44.0,
        height=22.0,
        class=[@style.style(border_radius=4.0)],
      ),
      @ui.text(label),
    ],
    column_gap=8.0,
  )
}

///|
/// 子窗内容按档分造：文案说有的东西（输入框、色卡）窗里就真得有。
/// 内容均为演示态：随开随建、关窗即弃。
fn child_content(name : String) -> Array[@widget.Node] {
  if name == "备忘窗" {
    let note : @base.Store[String] = @base.Store::new("")
    [
      @ui.text("备忘", class=[@style.text_title]),
      @ui.textarea(note, placeholder="想到什么记什么…", rows=5),
    ]
  } else if name == "调色窗" {
    [
      @ui.text("调色", class=[@style.text_title]),
      @ui.text("色卡随系统深浅变色", class=[@style.text_secondary]),
      swatch_row("primary", "主色"),
      swatch_row("success", "成功"),
      swatch_row("warning", "警告"),
    ]
  } else {
    [
      @ui.text("你好，MoonBit", class=[@style.text_heading]),
      @ui.text("native-gui 入门样例", class=[@style.text_secondary]),
      @ui.divider(),
      @ui.text(
        "单文件组件页面、命令式多窗与托盘，三平台同一套代码。",
        wrap=true,
      ),
    ]
  }
}

///|
/// 开/关一档子窗：已开 → 关掉并清状态；未开 → 开一扇并记住句柄，禁止重复开。
fn toggle_child(
  owner : @widget.WindowHost,
  kind : (String, Int, Int),
  win_count : @base.Store[Int],
  open : @base.Store[Bool],
  slot : Ref[@widget.WindowHost?],
) -> Unit {
  let (name, w, h) = kind
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
      // 内容在建壳之后组（关闭按钮要捕获这扇窗自己的句柄）；
      // 关窗不是破坏性动作，按钮用 Soft——Danger 留给删除类
      let body = @ui.col(
        child_content(name) +
        [
          @ui.col([], grow=1.0),
          @ui.row(
            [
              @ui.col([], grow=1.0),
              @ui.button("关闭", variant=@ui.Soft, on_click=fn() {
                a2.close_window()
                slot.val = None
                open.set(false)
                win_count.set(owner.window_count())
              }),
            ],
          ),
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
  // inspector 检查服务接线：MNG_INSPECT=1 注入时应用内起只读检查通道
  @inspector.inspect_auto_install()
  let win_count : @base.Store[Int] = @base.Store::new(1)
  let tray_note : @base.Store[String] = @base.Store::new("托盘：未创建")
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
    let (name, _, _) = kind
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
      @ui.bind_label(win_count, fn(n) { "窗口数：\{n}" }),
      @ui.bind_label(tray_note, fn(s) { s }),
      @ui.bind_label(tray_clicks, fn(n) { "托盘点击：\{n} 次" }),
    ],
    padding=24.0,
    row_gap=8.0,
    // 与 pages_window 的段容器同观感：bg_panel 卡片 + 1px 描边 + 圆角 6
    class=[
      @style.style(
        margin=16.0,
        background_color="bg_panel",
        border_color="border",
        border_width=1.0,
        border_radius=6.0,
      ),
    ],
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
          // 右键菜单：关于窗开关 + 分隔线 + 退出（右键无回调时自动弹已挂菜单）
          let menu = @shell.Menu::new()
          let about = menu.add_item("关于窗")
          about.on_click = Some(fn() {
            match host_ref.val {
              Some(a) =>
                for i, k in child_kinds {
                  if k.0 == "关于窗" {
                    toggle_child(a, k, win_count, child_open[i], child_hosts[i])
                  }
                }
              None => ()
            }
          })
          let _ = menu.add_separator()
          let quit = menu.add_role_item(@shell.MenuRole::Quit)
          quit.on_click = Some(fn() {
            match host_ref.val {
              Some(a) => a.quit()
              None => ()
            }
          })
          t.set_menu(menu)
          tray_note.set("托盘：已建（\{t.backend_name()}）")
        }
        Err(e) => tray_note.set("托盘：" + tray_err(e))
      }
      // 托盘派发 + 窗口数/开窗状态轮询同一条 200ms 表
      let tick : Ref[() -> Unit] = Ref(fn() { () })
      tick.val = fn() -> Unit {
        let _ = @shell.dispatch_tray_event()
        // 托盘菜单选中项经菜单队列回来，同一拍抽掉
        let _ = @shell.dispatch_menu_command()
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
