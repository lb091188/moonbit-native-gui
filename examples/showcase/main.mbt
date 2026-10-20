// 组件库演示板：侧边导航切换分页。目录结构：
//   shared/ 共享层（App 跨页状态、page/section 段装配、复制回显钩子）
//   pages/  各页内容（每页一个文件）
//   assets/ 图片资源
//
// 响应式分层演示：主题页（基础/表单/导航/数据/反馈）与各组件页用
// Store/Signal 直连，展示端不写手动 subscribe。
//
// 形态要点：
//   - 起窗走 `@ui.mount_window` + `App::run`；窗口居中交给 WM（本栈不提供 `center`）。
//   - 主题跟随是「跟随开关 + 每 2 秒读一次系统偏好」：手动选色/切深浅先把开关关掉，
//     否则下一拍就被盖回去。系统偏好读数用 `@win.sys_color_scheme/sys_accent`
//     （与 `App::follow_system_theme` 内部同一来源，示例要能手动覆盖故自己开表）。
//   - 菜单栏是模型翻译（`MenuBar::apply_to` → 原生菜单栏，点击经 `dispatch_menu_command`
//     派发到模型回调，100ms 轮询表挂在宿主）；单实例是 dbus 层的
//     `claim_name` + Wake（无会话总线的环境降级为不做，只打印说明）；
//     D-Bus 的排期通道与 200ms 泵都由宿主给。托盘菜单在系统集成页托盘段。
//   - 浏览器页在独立示例 `examples/browser`（WebView 重控件不随演示板起窗）。

///|
/// 窗口标题
const SHOWCASE_TITLE : String = "组件库演示板"

///|
/// 侧栏底部的版本号。本地留一份，只用于显示；权威值是库模块 `gui/moon.mod`
/// 的 version。
const SHOWCASE_VERSION : String = "0.1.1"

///|
/// 主题应用：主色空串用内置基准盘，非空按 HSL 公式派生；深浅随 `dark`。
fn apply_theme(app : @shared.App) -> Unit {
  let dark = app.dark_mode.get()
  let accent = app.accent.get()
  if accent.length() == 0 {
    @theme.theme_apply(if dark {
      @theme.dark_theme()
    } else {
      @theme.default_theme()
    })
  } else {
    @theme.theme_apply(@theme.theme_from_accent(accent, dark=dark))
  }
}

///|
/// 侧栏里的深/浅切换按钮：手动改即视为「不跟随系统」。
fn theme_toggle_button(app : @shared.App) -> @widget.Node {
  @ui.icon_button(
    @icons.Moon,
    on_click=fn() {
      app.follow.set(false)
      app.dark_mode.update(fn(v) { !v })
    },
  )
}

///|
/// 全局圆角开关（月亮旁）：切换 `@style.set_square_corners` 后整窗重绘。
fn flat_toggle_button(app : @shared.App) -> @widget.Node {
  @ui.icon_button(
    @icons.RadiusSetting,
    on_click=fn() {
      let on = !@style.square_corners()
      @style.set_square_corners(on)
      app.flat.set(on)
      @widget.invalidate()
    },
  )
}

///|
/// 侧栏/菜单半透玻璃开关（月亮旁）：整窗背景透明 + 重绘（侧栏玻璃底由玻璃样式兑现）。
fn translucent_toggle_button(app : @shared.App) -> @widget.Node {
  @ui.icon_button(
    @icons.MagicStick,
    on_click=fn() {
      let on = !app.translucent.get()
      app.translucent.set(on)
      match app.host.val {
        Some(a) => a.window().set_transparent_bg(on)
        None => ()
      }
      @widget.invalidate()
    },
  )
}

///|
/// 页名清单（路由 key 恒为中文，显示名另经 `nav_labels` 本地化）。
fn page_keys() -> Array[String] {
  [
    "基础组件", "表单组件", "导航组件", "数据展示", "图表", "代码文档", "Store",
    "反馈组件", "事件与布局", "窗口", "系统集成", "图标库", "画布与富文本",
    "过渡与效果", "系统能力探测", "图标字体", "国际化", "RTL 排版",
  ]
}

///|
/// 切语言按钮（月亮旁）：换目录 → 清已建页 → 改动 locale 触发整棵内容树重建。
fn language_toggle_button(app : @shared.App, nav : @router.Router) -> @widget.Node {
  @ui.icon_button(
    @icons.Earth,
    on_click=fn() {
      let to_en = app.locale.get() != "en"
      let loc = if to_en { "en" } else { "zh-CN" }
      @shared.set_locale_catalog(loc)
      app.locale.set(loc)
      // 只重建页面子树（router 自管，不经整树 bind，侧栏按钮不受牵连）
      for k in page_keys() {
        nav.purge_built(k)
      }
      nav.ensure_current()
      @widget.host_repaint_all()
      // 原生菜单栏不在树里：重建并重新挂，菜单文案随语言刷
      match app.host.val {
        Some(a) => {
          let bar = build_menu_bar(app, nav)
          let _ = bar.apply_to(a.window())
        }
        None => ()
      }
    },
  )
}

///|
/// 菜单栏模型（第十五批接线）：动作全部真实有效——「导航」切页、「主题」
/// 拨深浅与跟随开关、「帮助」关于冒提示 / 退出角色项走 `App::quit`。
/// 项点击经原生菜单派发链（`dispatch_menu_command`）回到这些回调。
fn build_menu_bar(app : @shared.App, nav : @router.Router) -> @shell.MenuBar {
  let bar = @shell.MenuBar::new()
  let nav_menu = bar.add_menu(@shared.tr("menu.nav", "导航"))
  for name in ["基础组件", "表单组件", "数据展示", "系统集成"] {
    let _ = nav_menu.add_item(@shared.nav_label(name)).set_on_click(nav.on_link(name))
  }
  let theme = bar.add_menu(@shared.tr("menu.theme", "主题"))
  let _ = theme.add_check_item(@shared.tr("menu.follow", "跟随系统")).set_on_click(fn() {
    app.follow.update(fn(v) { !v })
  })
  let _ = theme.add_item(@shared.tr("menu.light", "浅色")).set_on_click(fn() {
    app.follow.set(false)
    app.dark_mode.set(false)
  })
  let _ = theme.add_item(@shared.tr("menu.dark", "深色")).set_on_click(fn() {
    app.follow.set(false)
    app.dark_mode.set(true)
  })
  let help = bar.add_menu(@shared.tr("menu.help", "帮助"))
  let _ = help.add_item(@shared.tr("menu.about", "关于")).set_on_click(fn() {
    app.toast_push("native-gui 组件库演示板 V" + SHOWCASE_VERSION, @ui.Info)
  })
  let _ = help.add_separator()
  let _ = help.add_role_item(@shell.MenuRole::Quit).set_on_click(fn() {
    match app.host.val {
      Some(a) => a.quit()
      None => ()
    }
  })
  bar
}

///|
/// 一页 = 路由表里一个叶：内容在空闲预建或首次选中时才构造，那时 App 早已装好
/// （`box` 的口径与 `App::host` 同——先建表、后装配）。
fn route_of_page(
  box : Ref[@shared.App?],
  name : String,
  build : (@shared.App) -> @widget.Node,
  load : @router.LoadPolicy,
) -> @router.Route {
  @router.route_leaf(name, fn() -> @widget.Node {
    match box.val {
      Some(a) => build(a)
      None => abort("showcase 路由在 App 装配前构造：" + name)
    }
  }, load=load)
}

///|
fn main {
  let t_start = @win.now_ms()
  let box : Ref[@shared.App?] = Ref(None)
  let toast_push = @ui.toast_layer(duration_ms=2600)
  // 代码区「复制」的回显走同一 toast 层
  @shared.code_toast.val = Some(toast_push)
  let counter = @base.Signal::new(0)
  let routes : Array[@router.Route] = [
    route_of_page(box, "基础组件", @pages.page_basic, @router.Prefetch),
    route_of_page(box, "表单组件", @pages.page_form, @router.Prefetch),
    route_of_page(box, "导航组件", @pages.page_nav, @router.Prefetch),
    route_of_page(box, "数据展示", @pages.page_data, @router.Prefetch),
    route_of_page(box, "图表", @pages.page_charts, @router.Prefetch),
    route_of_page(box, "代码文档", @pages.page_code, @router.Prefetch),
    route_of_page(box, "Store", @pages.page_store_demo, @router.Prefetch),
    route_of_page(box, "反馈组件", @pages.page_feedback, @router.Prefetch),
    route_of_page(box, "事件与布局", @pages.page_events, @router.Prefetch),
    route_of_page(box, "窗口", @pages.page_window, @router.Prefetch),
    // 托盘要在启动期就出（构造期建托盘），所以这一页标 Eager，不进空闲队列
    route_of_page(box, "系统集成", @pages.page_system, @router.Eager),
    route_of_page(box, "图标库", @pages.page_icons, @router.Prefetch),
    route_of_page(box, "画布与富文本", @pages.page_canvas, @router.Prefetch),
    route_of_page(box, "过渡与效果", @pages.page_anim, @router.Prefetch),
    // 系统能力探测在构造期跑全量探测（读浏览器 sqlite、进程表），只给点开时才做
    route_of_page(box, "系统能力探测", @pages.page_sysprobe, @router.Lazy),
    route_of_page(box, "图标字体", @pages.page_iconfont, @router.Prefetch),
    route_of_page(box, "国际化", @pages.page_i18n, @router.Prefetch),
    route_of_page(box, "RTL 排版", @pages.page_rtl, @router.Lazy),
  ]
  let nav = @router.new_router(routes)
  let app : @shared.App = {
    selected: nav.store_at(0),
    locale: @base.Store::new("zh-CN"),
    ui_gen: @base.Store::new(0),
    toast: toast_push,
    dark_mode: @base.Store::new(@win.sys_color_scheme() == "dark"),
    // 启动即跟随系统主色调（系统无主色概念时回落内置 primary）
    accent: @base.Store::new(@win.sys_accent()),
    follow: @base.Store::new(true),
    counter,
    // visits/ratio 由 counter 派生（computed 自动收集依赖，不写手动接线）
    visits: @base.Signal::computed(fn() {
      (counter.get() * 1601 + 12804).to_string()
    }),
    ratio: @base.Signal::computed(fn() {
      let r = 0.25 + counter.get().to_double() * 0.1
      if r > 1.0 {
        1.0
      } else {
        r
      }
    }),
    picked_lang: @base.Signal::new(""),
    dlg_basic: @base.Store::new(false),
    dlg_form: @base.Store::new(false),
    dlg_name: @base.Store::new(""),
    dlg_result: @base.Store::new(""),
    flat: @base.Store::new(false),
    translucent: @base.Store::new(false),
    soft: @base.Store::new(false),
    // 宿主句柄：挂载时由下方 handle 回调填入（窗口页/快捷键页取用）
    host: Ref(None),
  }
  box.val = Some(app)
  // 深浅/主色任一变化即整体换主题；subscribe 注册不回调，故先应用一次
  app.dark_mode.subscribe(fn(_v) { apply_theme(app) })
  app.accent.subscribe(fn(_a) { apply_theme(app) })
  apply_theme(app)
  // 单实例（dbus 层）：先声称总线名；已有实例就唤起它并退出。
  // 无会话总线的环境（如 Windows 桌面）Err 降级为不做，只打印说明。
  match @dbus.claim_name("com.moonbitlibyue.showcase") {
    Ok(@dbus.PrimaryOwner) | Ok(@dbus.AlreadyOwner) =>
      // 首实例：注册 Wake 回调——切回首页并冒提示
      @dbus.on_wake(fn(_args : Array[String]) -> Unit {
        nav.goto("基础组件")
        app.toast_push("已被第二实例唤起", @ui.Info)
      })
    Ok(@dbus.AlreadyExists) | Ok(@dbus.InQueue) => {
      let _ = @dbus.wake_existing("com.moonbitlibyue.showcase", [])
      println("SHOWCASE-INST: 已有实例，已唤起并退出")
      return
    }
    Err(e) => println("SHOWCASE-INST: 单实例降级（\{e}）")
  }
  // 启动期就要生效的页（标了 Eager 的）在建窗之前建完，其余交给空闲预建
  nav.build_eager()
  let slot : Ref[@widget.App?] = Ref(None)
  let mounted = @ui.mount_window(
    [
      @ui.row(
        [
          // 侧栏：可滚动的分组菜单（窗口矮时滚到底部项）+ 底部主题切换 + 版本号
          @ui.col(
            [
              @ui.scroll_view(
                [
                  nav.sidebar(
                    [
                      (@shared.tr("nav.g.components", "组件"), ["基础组件", "表单组件", "导航组件", "数据展示", "图表", "代码文档", "Store", "反馈组件", "事件与布局", "窗口", "系统集成", "图标库", "画布与富文本", "过渡与效果"]),
                      (@shared.tr("nav.g.system", "系统"), ["系统能力探测"]),
                      (@shared.tr("nav.g.localization", "本地化"), ["图标字体", "国际化", "RTL 排版"]),
                    ],
                    label_of=fn(k) { @shared.nav_label(k) },
                    icons=[
                      ("基础组件", @icons.Appstore),
                      ("表单组件", @icons.Edit1),
                      ("导航组件", @icons.Compass),
                      ("数据展示", @icons.Chart),
                      ("图表", @icons.DataLine),
                      ("代码文档", @icons.Document),
                      ("Store", @icons.Database),
                      ("反馈组件", @icons.ChatRound),
                      ("事件与布局", @icons.Mouse),
                      ("窗口", @icons.Windows),
                      ("系统集成", @icons.Cpu),
                      ("图标库", @icons.Layout),
                      ("画布与富文本", @icons.Brush),
                      ("过渡与效果", @icons.MagicStick),
                      ("系统能力探测", @icons.Monitor1),
                    ],
                    width=180.0,
                  ),
                ],
                @ui.ScrollState::new(),
                handle=fn(v) { v.node.set_flex_grow(1.0) },
              ),
              @ui.row(
                [
                  @ui.text("V" + SHOWCASE_VERSION, role=@ui.Secondary),
                  theme_toggle_button(app),
                  flat_toggle_button(app),
                  translucent_toggle_button(app),
                  language_toggle_button(app, nav),
                ],
                padding=10.0,
                column_gap=8.0,
              ),
            ],
            background_color=if app.translucent.get() { "#12161FCC" } else { "" },
            width=180.0,
          ),
          // 主区：路由视图——选中哪页挂哪页，没选过的只留空壳；对话框挂在这一列上
          @ui.col(
            [
              nav.view(None),
              // 对话框挂窗口根：锚点自己是 0 尺寸占位，可见性只由 Store 驱动
              @ui.dialog(
                app.dlg_basic,
                "删除确认",
                [
                  @ui.alert(
                    "此操作不可撤销，请确认。",
                    t=@ui.Warning,
                    closable=true,
                  ),
                  @ui.text("确定要删除「示例项目」吗？", role=@ui.Body),
                ],
                confirm_text="删除",
                cancel_text="取消",
                on_confirm=fn() { app.dlg_result.set("已确认删除") },
                close_on_mask=true,
              ),
              @ui.dialog(
                app.dlg_form,
                "新建连接",
                [
                  @ui.text("名称", role=@ui.Body),
                  @ui.input(app.dlg_name, placeholder="例如：开发库", width=320.0),
                  @ui.text("地址", role=@ui.Body),
                  @ui.input(@base.Store::new(""), placeholder="host:port", width=320.0),
                ],
                on_confirm=fn() { app.dlg_result.set(app.dlg_name.get()) },
                width=380.0,
              ),
            ],
            grow=1.0,
          ),
        ],
        grow=1.0,
        align_items=@yoga.AlignItems::Stretch,
      ),
    ],
    title=SHOWCASE_TITLE,
    width=1280,
    height=720,
    handle=fn(a : @widget.App) {
      slot.val = Some(a)
      // 窗口页/快捷键页经 `app.host` 取宿主（页函数体跑完时还没挂载，这里填）
      app.host.val = Some(a)
      // 空闲预建：首屏之后一拍一页，队列建空自动停；切页时把进度报出来
      nav.start_prefetch()
      nav.store_at(0).subscribe(fn(k : String) -> Unit {
        println(
          "SHOWCASE-ROUTE page=\{k} built=\{nav.built_count().to_string()} " +
            "pending=\{nav.pending_count().to_string()} path=\{nav.path()}",
        )
      })
      // 单实例的 D-Bus 接线：排期通道与 200ms 泵都由宿主给（dbus 不引 GUI
      // 核心层）。无总线时 pump 空转，无副作用。
      @dbus.dbus_set_post_delayed(fn(ms : Int, f : () -> Unit) -> Unit {
        let _ = a.timer(ms, f)
      })
      let pump : Ref[() -> Unit] = Ref(fn() { () })
      pump.val = fn() -> Unit {
        @dbus.dbus_pump()
        let _ = a.timer(200, pump.val)
      }
      (pump.val)()
      // 原生菜单栏：模型翻译成原生菜单挂窗口；项点击经 WM_COMMAND 回收，
      // 100ms 轮询表派发到模型回调（托盘菜单项走同一条派发链）
      let bar = build_menu_bar(app, nav)
      if bar.apply_to(a.window()) {
        let menu_tick : Ref[() -> Unit] = Ref(fn() { () })
        menu_tick.val = fn() -> Unit {
          let _ = @shell.dispatch_menu_command()
          let _ = a.timer(100, menu_tick.val)
        }
        (menu_tick.val)()
      } else {
        println("SHOWCASE-MENU: 菜单栏挂载失败（后端不支持或建菜单失败）")
      }
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
      println("SHOWCASE-SKIP: 本平台没有窗口后端或没有显示服务")
      return
    }
    Some(host) => {
      // 输入框的 Ctrl+C/X/V 接系统剪贴板（演示板按真实使用形态开；探测不可用
      // 时内核自动保持内部剪贴板，见 gui/ui/clipboard.mbt）
      @ui.use_system_clipboard(true)
      let t_ready = @win.now_ms()
      println(
        "SHOWCASE-READY title=\{SHOWCASE_TITLE} pages=15 follow=1 " +
          "startup_ms=\{(t_ready - t_start).to_string()} " +
          "built=\{nav.built_count().to_string()} pending=\{nav.pending_count().to_string()}",
      )
      @base.paint_profile_reset()
      host.run()
    }
  }
  println("SHOWCASE-DONE page=\{nav.path()}")
  // 帧耗时分段账本：切页/渲染卡顿归因用（布局 vs 绘制 vs 上屏，见 gui/base/prof.mbt）。
  let prof = @base.paint_profile_summary()
  println("SHOWCASE-PROF " + prof)
}
