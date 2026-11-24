// WindowHost：一扇窗的运行时宿主——把「窗口 + 事件循环 + 控件树 + 输入法通道 + 上屏」收成一处，
// 分层依据：WindowHost/Window、脏区重绘、命中测试、组件宿主同在 `widget`。
//
// 一条重要的分层约束：`input` 只依赖 `base`、与本包互不引用，所以编辑器与
// 宿主的接缝做成控件回调形态——`on_key` /
// `on_commit` / `on_preedit` / `im_context` / `im_cursor` 五者由持有 Editor 的
// 控件自己实现，宿主只负责按焦点投递与喂系统输入法通道。这正是 G5b 记档的
// `TextEditorHost` 收口形态（四签名 process_key/commit/preedit/set_cursor_rect
// 逐一对应，只是从「一个 host 对象」换成「焦点控件的回调表」）。
//
// 三条既有纪律在这里继续成立（见 experience/adaptation.md）：时基必须先
// `Loop::start`；置脏必须 `@win.wake()` 否则睡在 `wait` 里的循环不会醒；
// 输入法每拍只喂**已提交**文本，`im_reset` 只在逻辑焦点换控件那一瞬调一次
// （每拍调会一直打断组合，见 `Window::im_reset` 注释）。

///|
pub(all) struct WindowHost {
  /// 壳层窗：平台窗口、共用的 `Loop`、窗号与退出位、
  /// 悬停/捕获/光标/输入法去重缓存与帧脏标志。webview / 3D 路线只吃这一半。
  mut session : @shell.Session
  root : Widget
  focus : FocusStack
  /// 本窗的浮层宿主（图层挂在 root 上；多窗时浮层开在当前窗的那层）
  host : OverlayHost
  /// 已拆过窗（close_window/shutdown 幂等）
  mut closed : Bool
  /// 脏区（窗口坐标，None = 整窗）：事件路由只并涉事控件的小矩形，浮层
  /// 打开与结构性变更走 `schedule_paint` 整窗兜底；paint_frame 消费后清空
  mut dirty_rect : Rect?
  /// 「本批已请求整窗重绘」标志：`dirty_rect=None` 同时表示「整窗」与「还没有脏区」,
  /// 区分不开,故整窗请求单独占一位。置位后同批内的局部置脏不收窄脏区,
  /// `paint_frame` 取走这一帧的裁剪框后复位。
  mut dirty_full : Bool
  /// 本批的滚动位移（视口 id、内容位移、条带修复余量）：本帧唯一脏区就是
  /// 该视口且位移为整数时才走条带快路径，否则按普通视口重绘
  mut scroll_pending : (Int32, Double, Double)?
  /// 本次滚轮已被动画中的滚动视口接住：只更新了弹簧目标、不需要立刻重绘。
  /// 滚动路由据此跳过整窗兜底，等节拍下一拍自己局部置脏。
  mut scroll_touch : Bool
  /// 按窗复用的帧位图：尺寸没变就不重新分配（每帧 new 是 MB 级分配+清零；
  /// 平台桩在 present 时同步拷贝像素，MoonBit 侧缓冲无延迟读，复用安全）
  mut canvas : @render.Bitmap?
  /// 窗口级按键兜底通道（见 `WindowHost::add_key_fallthrough`）
  key_fallthrough : Array[(KeyEvent) -> Bool]
  /// macOS 系统档默认加速键的开关（见 `WindowHost::set_system_keys`）
  mut system_keys : Bool
  /// 本窗隐藏驻留回调（见 `WindowHost::on_hidden`）
  hidden_cbs : Array[() -> Unit]
  /// 本窗从隐藏驻留唤回的回调（见 `WindowHost::on_shown`）
  shown_cbs : Array[() -> Unit]
  /// 本窗关闭回调（见 `WindowHost::on_close`）：F12 关与标题栏关闭都触发
  close_cbs : Array[() -> Unit]
  /// 宿主默认页面底是否在画（`WindowHost::set_transparent_bg` 按透视开关）
  mut page_fill : Bool
  /// 窗口状态记忆的应用 id（`WindowHost::remember_geometry` 置位；空 = 不记）。
  /// 记着的窗在关闭/宿主退出时把位置/尺寸/最大化档写回状态文件
  mut remember_id : String
  /// 本窗是否已成功上屏过至少一帧。新窗首帧可能早于平台映射被丢掉，
  /// 之后没有输入事件就不会再入泵（真机：新开窗白屏、动鼠标才出内容），
  /// 故首帧前由 `mount` 排几次兜底重绘。
  mut painted_once : Bool
  /// 首帧兜底重绘剩余排期（>0 表示已排过，防止每次 mount 重复排）。
  mut first_retry_left : Int32
  /// 这扇窗不进「最近帧」登记（检查器附窗这类取数工具窗：自己是查别人的
  /// 工具，不是被查对象，上屏不该顶掉最近帧）。
  mut frame_untracked : Bool
}

///|
/// 宿主要不要把这枚无修饰 Tab 吃掉驱动焦点栈：焦点控件声明 `wants_tab`
/// （Tab 是输入的控件，如代码编辑器）时不吃、放行给焦点链派发；无焦点或
/// 焦点控件不在树上时照旧吃（纯 Tab 语义）。Shift+Tab 走不到这里。
fn tab_consumed_by_host(root : Widget, current : Int32?) -> Bool {
  match current {
    Some(id) =>
      match root.find_by_focus_id(id) {
        Some(w) => !w.wants_tab
        None => true
      }
    None => true
  }
}

///|
/// 注册一个**窗口级**按键兜底处理器：焦点链（焦点控件及其带 `on_key` 的祖先）
/// 没消费、或压根没有焦点控件时，按注册序逐个问过去，第一个返回 `true` 的截断。
/// 给「不点也能用键盘」的组件（播放器快捷键一类）用。三条口径：
/// ① 焦点在输入框里时按键被编辑器消费，兜底不会抢字——不需要额外判据；
/// ② 只在本窗事件循环里生效，不是系统级热键（那是 `sys`/`win` 的 hotkey 线）；
/// ③ 注册没有反注册通道（本层还没有控件卸载钩子），所以处理器**自己负责活体
/// 判断**——用 `Widget::is_painted()` 问「我这棵子树还在被画吗」，不在就返回
/// `false` 放行，别让摘掉的组件继续吃键。
pub fn WindowHost::add_key_fallthrough(
  self : WindowHost,
  f : (KeyEvent) -> Bool,
) -> Unit {
  let _ = self.key_fallthrough.push(f)
}

///|
/// W32 便捷：把组合键字符串（"Ctrl+S" / "Alt+Shift+Tab" / "CmdOrCtrl+S" 等）
/// 绑到回调上。走的是同一条 `key_fallthrough` 通道，只在解析命中时调用 `cb`。
/// `CmdOrCtrl` 按平台落地（macOS 是 Cmd、其余是 Ctrl），词表与全局热键、菜单
/// 加速键同一套。解析失败的 spec 会被静默忽略（回调永不触发），不阻断注册流程。
pub fn WindowHost::bind_combo(
  self : WindowHost,
  spec : String,
  cb : () -> Unit,
) -> Unit {
  match parse_combo(spec, mac=@shell.platform_is_macos()) {
    Some((mods, keysym)) =>
      self.add_key_fallthrough(fn(ev : KeyEvent) -> Bool {
        if match_combo(ev, mods, keysym) {
          cb()
          true
        } else {
          false
        }
      })
    None => ()
  }
}

///|
/// W32 便捷：把「同一个键连按两次」绑到回调上（键多击的窗口级通道）。
/// 同一键在 60–400ms 内再次按下才触发，系统自动重复（约 25–40ms 一拍）不计；
/// 走 `key_fallthrough`，焦点链已消费的按键（例如输入框里打进字符）不会到这里。
pub fn WindowHost::bind_key_double(
  self : WindowHost,
  spec : String,
  cb : () -> Unit,
) -> Unit {
  match parse_combo(spec, mac=@shell.platform_is_macos()) {
    Some((mods, keysym)) => {
      let tracker = KeyTracker::new()
      self.add_key_fallthrough(fn(ev : KeyEvent) -> Bool {
        if match_combo(ev, mods, keysym) {
          let _ = tracker.feed(ev.keysym, ev.mods)
          if tracker.is_double() {
            cb()
            return true
          }
        }
        false
      })
    }
    None => ()
  }
}

///|
/// 系统档默认加速键的开关（默认开）。宿主内置这三条**只在 macOS**：本栈没有
/// 原生应用菜单，而 Cmd+Q / Cmd+W / Ctrl+Cmd+F 在别的 mac 软件里都由菜单给，
/// 缺了就是「连 Cmd+Q 都退不出去」。Linux 的 Super、Windows 的 Win 键各有桌面
/// 归属，不抢——那两档上本函数什么都不做。应用要自己接管这些组合时关掉。
pub fn WindowHost::set_system_keys(self : WindowHost, on : Bool) -> Unit {
  self.system_keys = on
}

///|
/// 系统档加速键的**动作号**（纯函数，平台读数由参数给）：0 无 / 1 退出 /
/// 2 关本窗 / 3 翻全屏。mods 按全等比——多按一个 Shift 不算命中。非 macOS
/// 一律 0：Linux 的 Super、Windows 的 Win 各有桌面归属，不该被应用抢。
fn system_key_action(
  mods : Int32,
  keysym : Int32,
  press : Bool,
  is_mac : Bool,
) -> Int32 {
  if !press || !is_mac {
    return 0
  }
  let cmd = @base.MOD_META
  let cmd_ctrl = @base.MOD_META | @base.MOD_CTRL
  if mods == cmd && keysym == keysym_of_name("q") {
    1
  } else if mods == cmd && keysym == keysym_of_name("w") {
    2
  } else if mods == cmd_ctrl && keysym == keysym_of_name("f") {
    3
  } else {
    0
  }
}

///|
/// 系统档加速键派发：在焦点链与兜底通道**之前**问一次（系统级动作不该被
/// 页面控件抢走）。
fn WindowHost::fire_system_keys(self : WindowHost, kev : KeyEvent) -> Bool {
  if !self.system_keys {
    return false
  }
  let act = system_key_action(
    kev.mods,
    kev.keysym,
    kev.press,
    @shell.platform_is_macos(),
  )
  match act {
    1 => {
      self.quit()
      true
    }
    2 => {
      self.close_window()
      true
    }
    3 => {
      self.session.window.toggle_fullscreen()
      true
    }
    _ => false
  }
}

///|
/// 装进程级挂钩（多窗形态只有一套）：重绘请求广播给所有在窗、浮层按当前窗取
/// 宿主、延时定时器走共用的 `Loop`。每建一扇窗都装一遍，装的是同一组闭包，
/// 重复安装没有副作用（无头测试自装的静态宿主会在下一扇窗建好时被接管）。
fn install_host_hooks() -> Unit {
  set_repaint_hook(fn() { host_repaint_all() })
  @shell.set_repaint_sink(fn() { host_repaint_all() })
  set_scroll_hook(fn(id : Int32, dy : Double, ext : Double) {
    host_scroll_repaint(id, dy, ext)
  })
  set_scroll_touch_hook(fn(id : Int32) { host_scroll_touch(id) })
  set_overlay_provider(fn() -> OverlayHost? {
    match host_active() {
      Some(a) => Some(a.host)
      None => None
    }
  })
  // 拖拽落点在**当前窗**的控件树里找（多窗各自一棵树，投错窗就白投）
  set_drag_root_provider(fn() -> Widget? {
    match host_active() {
      Some(a) => Some(a.root)
      None => None
    }
  })
  let l = host_loop()
  set_timer_hooks(fn(ms : Int32, f : () -> Unit) -> Int32 { l.timer(ms, f) }, fn(
    id : Int32,
  ) -> Unit {
    // 到期项已移除时 cancel 返回 false，不必上抛
    let _ = l.cancel(id)
  })
}

///|
/// 建一扇窗并挂上根控件：先开壳层窗（`@shell.session_open`——后端/平台窗
/// 建不起来给 None），再铺缺省底色、装进程级挂钩，并登记进两半本账。
/// 注册表还空即主窗，否则是附窗（共用同一个 `Loop` 与平台泵）。
fn app_window(
  width : Int32,
  height : Int32,
  title : String,
  popup_of : @win.Window?,
  place : (Int32, Int32)?,
  popup_focus~ : Bool = false,
) -> WindowHost? {
  match
    @shell.session_open(width, height, title, popup_of, place, popup_focus~) {
    None => None
    Some(session) => {
      let root = Widget::new()
      root.kind = "Window"
      // 窗根是读屏的窗锚点：报 window 角色、名字是窗题
      root.role = "window"
      root.name = title
      // 窗根是竖排容器：页面顶层元素缺省撑满窗宽、高度按内容，要占满剩余
      // 高度给 grow=1.0——与 web 块级布局同口径
      root.node.set_flex_direction(@yoga.Column)
      let app : WindowHost = {
        session,
        root,
        focus: FocusStack::new(),
        host: make_overlay_host(root),
        closed: false,
        canvas: None,
        key_fallthrough: [],
        dirty_rect: None,
        dirty_full: false,
        scroll_pending: None,
        scroll_touch: false,
        system_keys: true,
        hidden_cbs: [],
        shown_cbs: [],
        close_cbs: [],
        page_fill: true,
        remember_id: "",
        painted_once: false,
        first_retry_left: 0,
        frame_untracked: false,
      }
      // 缺省底色：宿主先铺一层主题页面色，最小示例不必自己写 on_draw 才有背景
      // （要别的底色/图案照常覆盖 root.on_draw 即可）；背景透视开着时本底让位——
      // 铺满整窗的默认底会把「没铺到的像素」吃光，透视形同虚设（透明测试窗实测）
      root.on_draw = Some(fn(
        _w : Widget,
        p : @render.Painter,
        r : Rect,
      ) -> Unit {
        if app.page_fill {
          p.set_fill_color(@theme.theme_bg_page())
          p.fill_rect(0.0, 0.0, r.w, r.h)
        }
      })
      host_add_app(app)
      install_host_hooks()
      Some(app)
    }
  }
}

///|
/// 跨模块测试通道：给一扇（假）壳层窗挂上空的根控件与浮层宿主。
pub fn test_app(s : @shell.Session) -> WindowHost {
  let root = Widget::new()
  root.kind = "Window"
  root.role = "window"
  root.node.set_flex_direction(@yoga.Column)
  {
    session: s,
    root,
    focus: FocusStack::new(),
    host: make_overlay_host(root),
    closed: false,
    canvas: None,
    key_fallthrough: [],
    dirty_rect: None,
    dirty_full: false,
    scroll_pending: None,
    scroll_touch: false,
    system_keys: true,
    hidden_cbs: [],
    shown_cbs: [],
    close_cbs: [],
    remember_id: "",
    painted_once: false,
    first_retry_left: 0,
    page_fill: true,
    frame_untracked: false,
  }
}

///|
/// 无头测试宿主（headless-tester P2）：进程内假窗（哨兵句柄，平台桩对
/// 越界 id 全部早退）+ 无头泵（`step` 不真睡）。应用泵行为由此可断言：
/// 定时器到期、脏区合并、`follow_system_theme` 轮询、`overlay_fit_pass`
/// 三帧收框。用例驱动形态：改状态 → `step()` 若干拍 → 断言。
/// **虚窗 ≠ 真窗**：平台窗口映射 / FFI / 输入法 / Retina 观感仍归真机人工验。
/// 对外契约是 `@uitest.test_headless`（「虚窗 ≠ 真窗」全清单在 uitest 包首），
/// 本方法作为它的底座，签名不承诺 1.0 稳定。
pub fn WindowHost::test_headless(width : Int32, height : Int32) -> WindowHost {
  @shell.session_set_headless(true)
  let a = test_app(
    @shell.fake_session(-1, @shell.host_new_wid(), true, width, height),
  )
  host_add_app(a)
  install_host_hooks()
  a
}

///|
/// 首个宿主入口（主窗）。再要一扇窗用 `WindowHost::open_window`，或在本表已空时
/// 再调一次本函数（那扇又成主窗）。
pub fn WindowHost::new(
  width : Int32,
  height : Int32,
  title : String,
) -> WindowHost? {
  app_window(width, height, title, None, None)
}

///|
/// 再开一扇窗：每窗一棵控件树、一套焦点栈与输入法状态，**共用**宿主的循环与泵。
/// 关掉它不影响宿主存活（只有主窗或最后一扇被关才整体退出）；内容照挂
/// `win.mount([...])`，事件路由与上屏在 `WindowHost::step` 里逐窗走。
pub fn WindowHost::open_window(
  self : WindowHost,
  width : Int32,
  height : Int32,
  title : String,
) -> WindowHost? {
  let _ = self
  app_window(width, height, title, None, None)
}

///|
/// 在窗数与当前窗（诊断与测试用）。注册表是进程级的，`self` 只作调用点锚。
pub fn WindowHost::window_count(self : WindowHost) -> Int32 {
  let _ = self
  host_window_count()
}

///|
pub fn WindowHost::active_window(self : WindowHost) -> WindowHost? {
  let _ = self
  host_active()
}

///|
/// 本窗窗号与是否主窗。
pub fn WindowHost::wid(self : WindowHost) -> Int32 {
  self.session.wid
}

///|
pub fn WindowHost::is_primary(self : WindowHost) -> Bool {
  self.session.primary
}

///|
/// 本窗的窗口层门面。控件层本来就拿不到窗口（`set_fullscreen` 因此收在宿主）；
/// 标题/尺寸/无边框/最小尺寸这类**窗口级**动作，上层（示例、应用代码）经这里
/// 取 `@win.Window` 自己调——`@win` 是公开包，方法即公开 API。关窗后的调用
/// 由 win 层自消化（no-op），不需调用方判空。
pub fn WindowHost::window(self : WindowHost) -> @win.Window {
  self.session.window
}

///|
/// 本窗全屏开关（播放器「铺满整屏」这类窗口级动作）。控件层拿不到窗口，
/// 所以由宿主把请求转到这里；尺寸变化照常走 allocate，调用方不用自己重算。

///|
/// 背景透视开关（转给本窗平台层），并让宿主默认页面底随之让位——铺满整窗的
/// `bg_page` 会把「没铺到的像素」吃光，透视开着时它必须退场；关透视时恢复。
/// 想要的观感是「控件没铺到的像素透出桌面」时，本窗的内容就别再整片铺底。
/// 失败档（平台无此能力 / 前置不满足）在这里收平为空操作；要分辨就直调
/// `Window::set_transparent_bg`（`Result` 带原因）或先探 `Window::shell_caps`。
pub fn WindowHost::set_transparent_bg(self : WindowHost, on : Bool) -> Unit {
  self.page_fill = !on
  let _ = self.session.window.set_transparent_bg(on)
}

///|
pub fn WindowHost::set_fullscreen(self : WindowHost, on : Bool) -> Unit {
  if self.closed {
    return
  }
  self.session.window.set_fullscreen(on)
}

///|
/// 跟随系统深浅/主色：每 `interval_ms` 读一次系统偏好，变了就 `theme_apply`
/// （订阅了主题变更的组件即时重着色，不重建界面）。返回停表函数。
///
/// 放在窗口层而不是 `theme`：主题包不该反过来依赖平台后端与事件循环。
/// 桌面环境没有对应通道（非 GNOME、或 schema 缺键）时读出来是空串，
/// 于是按亮色预设走，且此后每拍都不变、不会反复重刷。
pub fn WindowHost::follow_system_theme(
  self : WindowHost,
  interval_ms~ : Int32 = 1000,
) -> () -> Unit {
  let running : Ref[Bool] = Ref(true)
  let tick : Ref[() -> Unit] = Ref(fn() { () })
  tick.val = fn() -> Unit {
    if !running.val || !self.is_running() {
      running.val = false
      return
    }
    let t = @theme.theme_from_system(
      fn() -> String { @win.sys_color_scheme() },
      fn() -> String { @win.sys_accent() },
    )
    if @theme.theme_fingerprint_of(t) !=
      @theme.theme_fingerprint_of(@theme.theme_current()) {
      @theme.theme_apply(t)
    }
    let _ = self.timer(interval_ms, tick.val)
  }
  (tick.val)()
  fn() -> Unit { running.val = false }
}

///|
/// 一次性系统主题默认接线：进程内首个窗口挂载前做一次 `theme_from_system`
/// 探测并应用（单次探测、无轮询；深浅与主色读不出的桌面回落亮色基准）。
/// 应用此前已显式 `theme_apply`（含已接 `follow_system_theme`）时跳过，
/// 显式选择不被默认覆盖；持续跟随仍走 opt-in 的 `follow_system_theme`。
/// 返回是否实际应用。
let theme_auto_done : Ref[Bool] = Ref(false)

///|
pub fn theme_apply_system_once() -> Bool {
  if theme_auto_done.val || @theme.theme_explicitly_applied() {
    return false
  }
  theme_auto_done.val = true
  let _ = @theme.theme_apply_system(
    fn() -> String { @win.sys_color_scheme() },
    fn() -> String { @win.sys_accent() },
  )
  true
}

///|
/// 首帧兜底：新窗第一帧可能落在平台映射之前被丢掉，而排期当时那次
/// `@win.wake()` 已经消费掉，之后没有输入事件就再也不入泵。这里在新窗
/// 首次挂内容时排三拍延时重绘（30/120/400ms），保证「开窗即出内容」
/// 不依赖鼠标移动。三拍**不看 `painted_once` 照补**：present 成功只说明
/// 位图提交了，窗还没映射完时那一帧照样被丢——同拍首帧恰好在映射前
/// 「画过」时，看 painted_once 早退会把兜底提前缴械（真机复现：预设
/// 子窗白屏到鼠标动为止）。代价是每扇新窗至多三次冗余补绘（内容相同
/// 不闪）。`first_retry_left` 三态：0=未排（可排）、>0=飞行中（挡重复
/// 排）、-1=已收口（永不再排）。
fn arm_first_paint_retries(host : WindowHost) -> Unit {
  if host.first_retry_left != 0 {
    return
  }
  host.first_retry_left = 3
  fn retry(host : WindowHost, last : Bool) -> Unit {
    if host.first_retry_left > 0 {
      host.schedule_paint()
      host.first_retry_left = if last { -1 } else { host.first_retry_left - 1 }
    }
  }
  let _ = host.session.sched.timer(30, fn() { retry(host, false) })
  let _ = host.session.sched.timer(120, fn() { retry(host, false) })
  let _ = host.session.sched.timer(400, fn() { retry(host, true) })
}

///|
/// 把声明式节点树挂进根控件（内容入口）。挂载即建控件，之后信号驱动的
/// 重挂走 `bind_node` 的原位替换；挂完标一次脏，下一帧就有内容。
/// 多窗时每窗挂自己那棵，浮层图层升回自己那层的最后。
pub fn WindowHost::mount(self : WindowHost, children : Array[Node]) -> Unit {
  mount_children(self.root, children)
  // 新挂的内容会排在浮层图层之后，把**本窗**的图层挪回最后
  self.host.raise_layer()
  self.schedule_paint()
  arm_first_paint_retries(self)
}

///|
/// 把「除浮层图层外」的已挂内容整体搬进一个滚动视口（滚轮平移、视口裁剪）。
/// 用途：累积验证页把十几页叠成一根数千像素高的长柱，屏幕低于内容高时下面的
/// 页根本够不着（人工验收无从下手）——**全部页面挂完**之后调一次本函数即可。
/// 搬运保持内容顺序与绝对坐标（视口在顶、内容相对顶对齐），读几何的读数行不
/// 受影响；浮层宿主留在视口外（它是覆盖层，不该跟着内容滚）。滚轮先经内容里
/// 的子级滚动容器（虚拟列表/粘性列表等）消费，没人要才落到本视口。
pub fn WindowHost::enable_root_scroll(self : WindowHost) -> Unit {
  let root = self.root
  let vp = Widget::new()
  vp.node.set_flex_direction(@yoga.Column)
  vp.node.set_width(@yoga.percent(100.0))
  vp.node.set_height(@yoga.percent(100.0))
  let content = Widget::new()
  content.node.set_flex_direction(@yoga.Column)
  content.node.set_width(@yoga.percent(100.0))
  content.node.set_position(@yoga.Relative)
  let kept : Array[Widget] = []
  for kid in root.children() {
    if kid.id != self.host.layer.id {
      kept.push(kid)
    }
  }
  for kid in kept {
    let _ = root.remove_child(kid)
    content.append_child(kid)
  }
  vp.append_child(content)
  root.insert_child(0, vp)
  let off : Ref[Double] = Ref(0.0)
  vp.on_scroll = Some(fn(ev : ScrollEvent) -> Bool {
    let maxoff = (content.rect.h - vp.rect.h).max(0.0)
    let next = (off.val - ev.dy * 48.0).max(0.0).min(maxoff)
    if next != off.val {
      off.val = next
      content.node.set_top(@yoga.fixed(-next))
      self.schedule_paint()
    }
    true
  })
  self.schedule_paint()
}

///|
/// 标脏并唤醒等待中的平台泵（供控件回调与定时器使用）。整窗语义：浮层
/// 打开、结构性变更（重挂/换页/主题）与一切拿不准的回退都走这里。
pub fn WindowHost::schedule_paint(self : WindowHost) -> Unit {
  self.session.dirty = true
  self.dirty_full = true
  self.dirty_rect = None
  @win.wake()
}

///|
/// 局部置脏的累积规则：`full` 为真表示本批已请求整窗重绘，此时局部矩形不改脏区。
fn accept_widget_rect(full : Bool, cur : Rect?, r : Rect) -> Rect? {
  if full {
    cur
  } else {
    Some(
      match cur {
        None => r
        Some(x) => x.union(r)
      },
    )
  }
}

///|
/// 一帧的裁剪框：整窗请求时无裁剪（None），否则用累积的脏区。
fn dirty_clip(full : Bool, rect : Rect?) -> Rect? {
  if full {
    None
  } else {
    rect
  }
}

///|
/// 矩形与毛玻璃控件相交吗（backdrop_blur 开着、可见、矩形相交）。
fn blur_rect_hit(w : Widget, rect : Rect) -> Bool {
  w.backdrop_blur_paint >= 1.0 &&
  w.visible &&
  w.rect.w > 0.0 &&
  w.rect.h > 0.0 &&
  w.rect.x < rect.x + rect.w &&
  w.rect.x + w.rect.w > rect.x &&
  w.rect.y < rect.y + rect.h &&
  w.rect.y + w.rect.h > rect.y
}

///|
/// 局部置脏：把一个控件的绝对矩形并入脏区并唤醒。带绘制期变换的控件取
/// **变换外接矩形**——旋转/缩放的内容越出布局矩形，按原矩形标脏会留残影。
/// 脏区与**毛玻璃控件**相交时把玻璃矩形整块并入——blur 的糊窗在糊区域边界
/// 上取边缘样本，糊区域随脏区变则玻璃区像素帧间漂移（真机表现为圆角边缘
/// 「模糊位置闪烁」）；全块并入后下层重画范围与糊窗每帧恒定，输出稳定。
fn WindowHost::mark_widget_rect(self : WindowHost, w : Widget) -> Unit {
  self.session.dirty = true
  let r = w.transform_expanded_rect(w.rect)
  self.dirty_rect = accept_widget_rect(
    self.dirty_full,
    self.dirty_rect,
    r,
  )
  if !self.dirty_full {
    let hits : Array[Rect] = []
    fn walk(w : Widget) -> Unit {
      if !w.visible {
        return
      }
      if blur_rect_hit(w, r) {
        hits.push(w.transform_expanded_rect(w.rect))
      }
      for k in w.kids {
        walk(k)
      }
    }

    walk(self.root)
    for br in hits {
      self.dirty_rect = accept_widget_rect(false, self.dirty_rect, br)
    }
  }
  @win.wake()
}

///|
/// 动画中的滚动视口接住了本次滚轮：只记「本批不用整窗兜底」，不标脏、不唤醒。
/// 下一拍弹簧自己置脏时再走条带。
fn host_scroll_touch(viewport_id : Int32) -> Unit {
  for a in host_windows() {
    match a.root.by_id(viewport_id) {
      Some(_) => a.scroll_touch = true
      None => ()
    }
  }
}

///|
/// 滚动重绘：按视口控件局部置脏，并记下位移供条带快路径判定（未安装滚动
/// 钩子时由 `@widget.scroll_repaint` 回退整窗）。
fn host_scroll_repaint(viewport_id : Int32, dy : Double, extent : Double) -> Unit {
  for a in host_windows() {
    match a.root.by_id(viewport_id) {
      Some(w) => a.mark_scroll(w, dy, extent)
      None => ()
    }
  }
  @win.wake()
}

///|
fn WindowHost::mark_scroll(
  self : WindowHost,
  w : Widget,
  dy : Double,
  extent : Double,
) -> Unit {
  self.session.dirty = true
  self.dirty_rect = accept_widget_rect(self.dirty_full, self.dirty_rect, w.rect)
  self.scroll_pending = match self.scroll_pending {
    Some((_, pdy, pext)) =>
      Some((w.id, pdy + dy, if extent > pext { extent } else { pext }))
    None => Some((w.id, dy, extent))
  }
}

///|
/// 子树里有没有与矩形相交的毛玻璃控件（条带快路径的禁用条件之一）。
fn tree_blur_hit(w : Widget, rect : Rect) -> Bool {
  if !w.visible {
    return false
  }
  if blur_rect_hit(w, rect) {
    return true
  }
  for k in w.kids {
    if tree_blur_hit(k, rect) {
      return true
    }
  }
  false
}

///|
/// 条带快路径的滚动视口结构白名单：第一颗子件是内容容器，其余只允许**纵向**
/// 滚动条。粘性标题、横向条、调用方额外挂的浮层都说明视口里还有「不随内容
/// 平移」的东西，整块平移会画错，一律退回普通重绘。
fn strip_scrollable(v : Widget) -> Bool {
  let content_kind = match v.kind {
    "ui-virt-list" => "ui-virt-list-content"
    "ui-scroll-view" => "ui-scroll-content"
    _ => return false
  }
  if v.kids.length() == 0 || v.kids[0].kind != content_kind {
    return false
  }
  for i = 1; i < v.kids.length(); i = i + 1 {
    if v.kids[i].kind != "ui-scroll-bar" {
      return false
    }
  }
  true
}

///|
/// 裁剪到矩形画一次整树（条带修复用；裁剪外的控件被视口剔除跳过）。
fn paint_clipped(root : Widget, p : @render.Painter, r : Rect) -> Unit {
  if r.w <= 0.0 || r.h <= 0.0 {
    return
  }
  p.save()
  p.clip_rect(r.x, r.y, r.w, r.h)
  root.paint(p)
  p.restore()
}

///|
/// 悬停/按下变化的标脏范围：指针底下那颗控件，**加上悬停链上每个自绘状态的祖先**。
/// 只标最深那颗会漏——表格行的整行悬停底色由行控件画，脏区却只有鼠标那一格，
/// 真机表现就是「悬停不是整行」。链上没有状态祖先时，代价仍只是一颗控件的矩形。
fn WindowHost::mark_state_chain(self : WindowHost, id : Int32) -> Unit {
  if id <= 0 {
    return
  }
  let path = path_to_widget(self.root, id, [])
  if path.length() == 0 {
    self.schedule_paint()
    return
  }
  for w in path {
    if w.id == id || w.paints_state {
      self.mark_widget_rect(w)
    }
  }
}

///|
/// 焦点 id 版（焦点栈存的是 Int?）：None 表示本就无焦点，无事可做。
/// 焦点栈记的是**焦点 id**（使用者给控件的序号），不是控件实例 id——拿它去
/// `by_id` 查树会把脏区标到「实例 id 恰好等于那个序号」的另一个控件上，
/// 新焦点的焦点环与光标因此可能整片不重画。
fn WindowHost::mark_focus_rect(self : WindowHost, id : Int32?) -> Unit {
  match id {
    Some(i) => self.mark_focus_id_rect(i)
    None => ()
  }
}

///|
/// 按焦点 id 局部置脏；树里没有这个焦点 id（未挂载/已隐藏）回退整窗。
fn WindowHost::mark_focus_id_rect(self : WindowHost, focus_id : Int32) -> Unit {
  if focus_id <= 0 {
    return
  }
  match self.root.find_by_focus_id(focus_id) {
    Some(w) => self.mark_widget_rect(w)
    None => self.schedule_paint()
  }
}

///|
/// 相对延时定时器（转派 `Loop::timer`，返回可取消的句柄）。
pub fn WindowHost::timer(
  self : WindowHost,
  delay_ms : Int32,
  work : () -> Unit,
) -> Int32 {
  self.session.timer(delay_ms, work)
}

///|
/// 停掉一个周期/延时表（`timer` 返回的句柄）。幂等：没这个句柄（已响完 /
/// 已停 / 号不存在）都算成功。`timer` 的语义是「句柄可停」，没有取消口子
/// 的话上层只能让回调自己判flag——那留着一个每拍空转的表，故这里补上。
pub fn WindowHost::cancel_timer(self : WindowHost, id : Int32) -> Bool {
  if self.closed {
    return false
  }
  self.session.sched.cancel(id)
}

///|
/// 推迟一拍执行：回调里不做重活。
pub fn WindowHost::task(self : WindowHost, work : () -> Unit) -> Unit {
  self.session.task(work)
}

///|
/// 退出：只停派发，不拆对象（拆除由调用方在 `run` 返回后做）。`Loop` 是各窗
/// 共用的，所以任一窗调它即整体退出。
pub fn WindowHost::quit(self : WindowHost) -> Unit {
  @shell.remove_all_trays()
  self.session.quit()
}

///|
pub fn WindowHost::is_running(self : WindowHost) -> Bool {
  !self.closed && self.session.is_running()
}

///|
/// 注册本窗「被隐藏驻留」（`hide` 的真实转换）回调：可注册多个，按注册序触发。
/// 典型用途是托盘/单实例唤起前记状态、隐藏驻留时暂停动画。回调时机在事件
/// 拍内（`hide()` 调用后的下一拍），此时窗口已撤出屏幕。
pub fn WindowHost::on_hidden(self : WindowHost, f : () -> Unit) -> Unit {
  let _ = self.hidden_cbs.push(f)
}

///|
/// 注册本窗「从隐藏驻留唤回」（`show` 的真实转换）回调：可注册多个，按注册序
/// 触发。首次显示不发——只有隐藏过的窗才有「唤回」。
pub fn WindowHost::on_shown(self : WindowHost, f : () -> Unit) -> Unit {
  let _ = self.shown_cbs.push(f)
}

///|
/// 注册本窗关闭回调（F12 关、内容里 `close_window`、标题栏关闭都触发）：
/// 可注册多个，按注册序触发；幂等关闭只触发一次。时机在拆平台窗之前，
/// 收尾还能碰窗里的对象。
pub fn WindowHost::on_close(self : WindowHost, f : () -> Unit) -> Unit {
  let _ = self.close_cbs.push(f)
}

///|
/// 隐藏驻留的宿主侧收口：与「整窗失焦」同一套输入法交接（在途 commit 归当前
/// 控件、清掉组合串显示、打断引擎侧未完成的组合、复位去重缓存），再触发应用
/// 回调。隐藏不产生平台失焦事件，少了这条组合串会一直挂着、唤回后原样还在
/// （真机实测）。焦点栈不动：唤回时控件焦点照旧。
fn WindowHost::handle_hidden(self : WindowHost) -> Unit {
  self.flush_ime_for_switch(self.focus.current())
  for f in self.hidden_cbs {
    f()
  }
}

///|
/// 唤回的宿主侧收口：只触发应用回调（输入法会话在隐藏时已清，重挂的焦点
/// 会由 `pump_ime` 重新对齐）。
fn WindowHost::handle_shown(self : WindowHost) -> Unit {
  for f in self.shown_cbs {
    f()
  }
}

///|
/// 焦点真要换控件时的**前置**动作（必须在改焦点栈之前调）：
/// - 把输入法已经排队的提交文本交还**旧**控件——这些提交是旧控件的按键产生的，
///   晚一拍排空就会落进新控件（真机实测：在 A 框打的字 commit 进了 B 框）；
/// - 清掉旧控件画着的组合串；
/// - `im_reset` 打断输入法侧未完成的组合串（一个窗口只有一个 IM 上下文）。
fn WindowHost::flush_ime_for_switch(self : WindowHost, prev : Int32?) -> Unit {
  match prev {
    Some(id) => {
      let mut more = true
      while more {
        match self.session.window.take_commit() {
          Some(t) =>
            if self.root.dispatch_commit(id, t) {
              self.schedule_paint()
            }
          None => more = false
        }
      }
      if self.session.last_preedit.0.length() > 0 {
        self.root.dispatch_preedit(id, "", 0)
        self.session.last_preedit = ("", 0)
      }
    }
    None => ()
  }
  self.session.window.im_reset()
  // 置「未同步」哨兵而不是 0：pump_ime 按「焦点变了才同步 IM 门」工作，
  // 0 与「无焦点」同值会让丢焦后的那拍跳过同步——上一个焦点是输入框时
  // 门停在开，字符键从此全被 IM 吃掉（真机：Linux 点空白丢焦后播放器
  // M/L 快捷键失效）。哨兵让下一拍必同步到真实档位。
  self.session.ime_focus = -1
}

///|
/// 焦点栈对齐控件树：树里且未隐藏的 `focus_id` 全部进栈（树序即 Tab 序），
/// 掉出树的自动注销。宿主在「按下要改焦点」与「Tab 要走栈」之前各对齐一次，
/// 所以声明了 `focus_id` 的控件天然可聚焦——调用方不需要把号逐个交给
/// `focus.register`（那仍是画布类自绘宿主与浮层临时焦点的口子）。
fn WindowHost::sync_focus(self : WindowHost) -> Unit {
  self.focus.sync(
    match self.host.focus_root() {
      // 铺满遮罩的模态层（对话框/消息框）开着：Tab 只在这一层里转
      Some(w) => w.focus_ids()
      None => self.root.focus_ids()
    },
  )
}

///|
/// 焦点栈移动 + 把键盘焦点重新要到窗口上 + 重绘。
pub fn WindowHost::move_focus(self : WindowHost, backward : Bool) -> Unit {
  self.sync_focus()
  let prev = self.focus.current()
  let next = self.focus.move_focus(backward)
  if next != prev {
    self.flush_ime_for_switch(prev)
  }
  self.session.window.request_focus()
  // 焦点环只在旧/新两控件上走，局部置脏；flush 里若整窗置脏则并集即整窗
  self.mark_focus_rect(prev)
  self.mark_focus_rect(next)
}

///|
/// 把焦点交给焦点栈里的某个 id（控件自己请焦点走这条：步进器点 +/- 要把焦点落到
/// 中间那格）。先把焦点栈与控件树对齐一次，id 不在册就不改焦点并给 false。
pub fn WindowHost::focus_by_id(self : WindowHost, id : Int32) -> Bool {
  self.sync_focus()
  if self.focus.is_focused(id) {
    return true
  }
  let prev = self.focus.current()
  let ok = self.focus.focus(id)
  if ok {
    self.flush_ime_for_switch(prev)
    self.mark_focus_rect(prev)
    self.mark_focus_id_rect(id)
    let _ = self.session.window.request_focus()
    // 当场对齐一次焦点标志：请焦点的控件这一拍就能读到 `focused`
    self.root.set_focused_by_focus(id)
    self.schedule_paint()
  }
  ok
}

///|
/// 原始事件的归类型。`win` 的 code 语义：0 键按下 1 键抬起 2 按钮按下
/// 3 按钮抬起 4 指针移动 5 滚轮；两个数据槽按 C 侧 `WmEv.dx/dy` 命名，
/// 到 MoonBit 是 `button`（dx：按钮号或滚轮横向）与 `axis`（dy：滚轮纵向，
/// 正=上滚）。
pub(all) enum RawEvent {
  Key(KeyEvent)
  Pointer(PointerEvent)
  Scroll(ScrollEvent)
  Ignored
}

///|
/// 原始事件 → 本层事件形态。独立成函数是为了无头可测（宿主其余部分要窗口）。
pub fn raw_to_event(
  code : Int32,
  keysym : Int32,
  mods : Int32,
  x : Int32,
  y : Int32,
  button : Int32,
  axis : Int32,
  dx_f~ : Double = 0.0,
  dy_f~ : Double = 0.0,
) -> RawEvent {
  let xf = x.to_double()
  let yf = y.to_double()
  if code == 0 || code == 1 {
    Key({ press: code == 0, keysym, mods, })
  } else if code == 2 || code == 3 || code == 4 {
    Pointer({
      kind: if code == 2 {
        Down
      } else if code == 3 {
        Up
      } else {
        Move
      },
      x: xf,
      y: yf,
      button,
      mods,
    })
  } else if code == 5 {
    Scroll({
      x: xf,
      y: yf,
      // 精确滚量优先（Windows delta/120、GTK smooth、mac 触控板），零则回退方向刻度
      dx: if dx_f != 0.0 { dx_f } else { button.to_double() },
      dy: if dy_f != 0.0 { dy_f } else { axis.to_double() },
      mods,
    })
  } else {
    Ignored
  }
}

///|

///|
/// 宿主路由诊断门：`LIBYUE_ROUTE_LOG` / `NATIVEGUI_ROUTE_LOG` 任一设了就往
/// stdout 打按键与点击聚焦的关键拍（焦点栈当前值、命中可聚焦结果）——真机
/// 取证「按键没反应」时先看这条：焦点对不对，一眼定层。
fn route_diag(msg : String) -> Unit {
  let on = match @env.get_env_var("LIBYUE_ROUTE_LOG") {
    Some(_) => true
    None => @env.get_env_var("NATIVEGUI_ROUTE_LOG") is Some(_)
  }
  if on {
    println("[route] \{msg}")
  }
}

///|
/// 测试泵（无头用例专用）：把一条**原始事件**灌进真宿主管线——与真机同一
/// 条 route（命中、点击聚焦、捕获、系统键、Tab 分支、焦点链派发、兜底通道
/// 全在里面）。uitest 的 `dispatch_*` 直达控件绕过这些宿主分支，测不出
/// 「真机上按键没反应」这类问题；无头复现一律走这两个口。
pub fn WindowHost::test_pump_pointer(
  self : WindowHost,
  code : Int32,
  x : Int32,
  y : Int32,
  button : Int32,
) -> Unit {
  self.route({ code, keysym: 0, mods: 0, x, y, button, axis: 0, dx_f: 0.0, dy_f: 0.0, })
}

///|
/// 测试泵（无头用例专用）：灌一条按键（`press=false` 走抬起声明制通道）。
pub fn WindowHost::test_pump_key(
  self : WindowHost,
  keysym : Int32,
  mods : Int32,
  press~ : Bool = true,
) -> Unit {
  self.route({
    code: if press {
      0
    } else {
      1
    },
    keysym,
    mods,
    x: 0,
    y: 0,
    button: 0,
    axis: 0,
    dx_f: 0.0,
    dy_f: 0.0,
  })
}

///|
fn WindowHost::route(self : WindowHost, ev : @win.InputEvent) -> Unit {
  // 谁被操作谁就是当前窗（浮层与工具提示跟着它，见 host.mbt）
  host_mark_active(self.session)
  match
    raw_to_event(
      ev.code,
      ev.keysym,
      ev.mods,
      ev.x,
      ev.y,
      ev.button,
      ev.axis,
      dx_f=ev.dx_f,
      dy_f=ev.dy_f,
    ) {
    Ignored => ()
    Pointer(pev) => {
      // 原生档浮层的点外收起：owner 上任何按下都是点外（弹层是独立窗），
      // 收起最上层并把整段手势吞掉，不再派发给内容
      if overlay_pointer_prelude(self, pev) {
        return
      }
      let old_hover = self.session.hover_id
      let old_cap = self.session.capture
      let r = route_pointer(
        self.root,
        pev,
        self.session.hover_id,
        self.session.capture,
      )
      self.session.hover_id = r.0
      self.session.capture = r.1
      // 光标形状随悬停路径走（拖动期间被捕获，形状停在起手那档）
      let wants_cursor = match pev.kind {
        Move => true
        _ => false
      }
      if wants_cursor {
        // 应用内拖拽会话进行中：全程握拳（悬停路径此刻被捕获，落点命中与否
        // 由落点自己的描边高亮表达，光标不再随点下的控件改形）
        let want = if drag_active() {
          CURSOR_GRABBING
        } else {
          self.root.cursor_at(pev.x, pev.y)
        }
        if want != self.session.cursor_kind {
          self.session.cursor_kind = want
          self.session.window.set_cursor(want)
        }
      }
      match pev.kind {
        Down => {
          // 焦点栈先跟上这一回合的树（重挂/换页可能在上一拍改过控件）
          self.sync_focus()
          // 本窗自绘区被点，键盘焦点必须回到本窗：GTK 不会替 GtkDrawingArea
          // 做这件事，而焦点一旦被网页子件拿走就再也不回来——真机实测症状是
          // 「点进网页再点回输入框，打字毫无反应」（键全被 webview 收走，
          // 连 Ctrl+Z 这类快捷键也进网页）。无条件要一次，代价只是重复 grab 同一个控件。
          self.session.window.request_focus()
          // 命中可聚焦控件时切焦点栈（栈里没有该 id 时不改焦点栈）
          let hit_focus = self.root.focusable_at(pev.x, pev.y)
          route_diag(
            "pointer-down focusable_at(\{pev.x},\{pev.y})=\{Repr(hit_focus)} current=\{Repr(self.focus.current())}",
          )
          match hit_focus {
            Some(id) =>
              if !self.focus.is_focused(id) {
                let prev = self.focus.current()
                if self.focus.focus(id) {
                  self.flush_ime_for_switch(prev)
                  self.mark_focus_rect(prev)
                }
                self.mark_focus_id_rect(id)
              }
            None =>
              // 点在不可聚焦的自绘区：焦点让位（Web 的点空白 blur 语义）——
              // 否则焦点滞留在远处那个按钮上，空格/回车还在驱动它，而用户
              // 以为在操作眼前这块。注册表保留（点回来 focus(id) 找得到）。
              // 例外：命中链上声明了 `keep_focus_on_click` 的附属小件（步进器
              // +/- 这类「只是操作、不是换焦点对象」的格）不让位。
              if self.root.keep_focus_at(pev.x, pev.y) {
                ()
              } else {
                match self.focus.current() {
                  Some(prev) => {
                    self.flush_ime_for_switch(Some(prev))
                    self.focus.drop_current()
                    self.mark_focus_id_rect(prev)
                  }
                  None => ()
                }
              }
          }
        }
        _ => ()
      }
      // 抬起（点击成交）必有跨控件涟漪：on_click 改的 Store 常影响悬停/捕获
      // 链之外的兄弟控件（显示端不订阅、绘制期现取的多），局部置脏盖不住，
      // 整窗兜底一帧。点击是低频交互，整帧代价可接受。
      if pev.kind is Up {
        self.schedule_paint()
      }
      if r.2 || r.3 {
        // 局部置脏：变化范围 = 旧/新悬停 + 旧/新捕获（悬停高亮、按下态、
        // 事件消费者的自绘都在这些控件上）；浮层开着（菜单/提示可能盖到
        // 任何位置）回退整窗。
        if self.host.layer.visible {
          self.schedule_paint()
        } else {
          self.mark_state_chain(old_hover)
          self.mark_state_chain(self.session.hover_id)
          self.mark_state_chain(old_cap)
          self.mark_state_chain(self.session.capture)
        }
      }
    }
    Scroll(sev) => {
      let handled = self.root.dispatch_scroll(sev)
      // 动画中的滚动视口只更新弹簧目标、下一拍自己置脏；本次不再整窗兜底
      let touched = self.scroll_touch
      self.scroll_touch = false
      // 滚动容器消费时已按视口局部置脏（ScrollState::set_offset）；消费者
      // 改了别的状态却没标脏才整窗兜底
      if handled && !touched && !self.session.dirty {
        self.schedule_paint()
      }
    }
    Key(kev) => {
      route_diag(
        "key keysym=\{kev.keysym} mods=\{kev.mods} press=\{kev.press} focus=\{Repr(self.focus.current())}",
      )
      // 抬起事件走**声明制**通道：只投给挂了 on_key_release 的控件（焦点链
      // 最深优先）。on_key 与兜底通道都不收抬起——编辑内核的 handle_key 只吃
      // keysym、不区分按下/抬起，放行抬起等于「松手再插一个字符」（实测：Tab
      // 抬起被当可打印字符插成 '\t'）；兜底消费者按按下语义写，放行等于空格
      // 切两次。没人声明就整条丢弃。
      if !kev.press {
        let consumed = match self.focus.current() {
          Some(id) => self.root.dispatch_key_release(id, kev)
          None => false
        }
        if consumed {
          if self.host.layer.visible {
            self.schedule_paint()
          } else {
            match self.focus.current() {
              Some(id) =>
                for w in self.root.key_release_targets(id) {
                  self.mark_widget_rect(w)
                }
              None => self.schedule_paint()
            }
          }
        }
        return ()
      }
      // 系统档加速键（mac 的 Cmd+Q/W、Ctrl+Cmd+F）排在焦点链与兜底之前
      if self.fire_system_keys(kev) {
        return ()
      }
      // Tab / Shift+Tab 由宿主消费并驱动焦点栈（GTK 可能给 ISO_Left_Tab）；
      // 焦点控件声明 `wants_tab`（Tab 是输入的控件，如代码编辑器）时，无修饰
      // Tab 放行给焦点链——Shift+Tab 仍归宿主（编辑器的反缩进日后再接）。
      if kev.keysym == KS_TAB || kev.keysym == KS_ISO_LEFT_TAB {
        if kev.keysym == KS_ISO_LEFT_TAB ||
          (kev.mods & MOD_SHIFT) != 0 ||
          tab_consumed_by_host(self.root, self.focus.current()) {
          self.move_focus(
            kev.keysym == KS_ISO_LEFT_TAB || (kev.mods & MOD_SHIFT) != 0,
          )
          return ()
        }
      }
      let consumed = match self.focus.current() {
        Some(id) => self.root.dispatch_key(id, kev)
        None => false
      }
      if consumed {
        // 键处理只落在焦点控件与其带 on_key 的祖先链上，标记这条链；
        // 浮层开着回退整窗
        if self.host.layer.visible {
          self.schedule_paint()
        } else {
          match self.focus.current() {
            Some(id) =>
              for w in self.root.key_targets(id) {
                self.mark_widget_rect(w)
              }
            None => self.schedule_paint()
          }
        }
      } else if self.fire_selection_copy(kev) {
        // 静态文本的选区复制：受影响的是那件自己（它自己置脏）
        self.schedule_paint()
      } else if self.fire_key_fallthrough(kev) {
        // 兜底通道吃掉了这条键：受影响的是处理器自己的子树（组件自己置脏），
        // 宿主不知道范围，整窗兜一帧
        self.schedule_paint()
      } else if fire_app_key_hooks(kev) {
        // 进程级钩子吃掉了这条键：范围未知，整窗兜一帧
        self.schedule_paint()
      }
    }
  }
}

///|
/// 静态文本选区的复制支：展示件不可聚焦（`focus_id=0`，不进 Tab 链），按键到不了
/// 它们，所以宿主在兜底通道之前问一句「这一刻有没有谁正持有选区」，有且是按下的
/// primary+C 就让它执行复制。焦点在输入框且它自己有选区时，上一条 `consumed`
/// 已经吃掉这条键（既定口径：那时行为=复制焦点件）。
fn WindowHost::fire_selection_copy(_self : WindowHost, kev : KeyEvent) -> Bool {
  let primary = if @shell.platform_is_macos() {
    (kev.mods & MOD_META) != 0
  } else {
    (kev.mods & MOD_CTRL) != 0
  }
  if !primary || kev.keysym != 'c'.to_int() {
    return false
  }
  text_sel_copy()
}

///|
/// 兜底通道派发：按注册序问，第一个吃掉的返回 true（`WindowHost::add_key_fallthrough`）。
fn WindowHost::fire_key_fallthrough(self : WindowHost, kev : KeyEvent) -> Bool {
  for f in self.key_fallthrough {
    if f(kev) {
      return true
    }
  }
  false
}

///|
/// 进程级键兜底钩子（所有窗共用，排在窗级兜底之后）：给拿不到窗句柄的
/// 服务组件装应用级快捷键用（检查器 F12 开关附窗这类）。回调自己负责
/// 活体判断（注册没有反注册，与窗级兜底同口径）。
let g_app_key_hooks : Array[(KeyEvent) -> Bool] = []

///|
pub fn add_app_key_hook(f : (KeyEvent) -> Bool) -> Unit {
  g_app_key_hooks.push(f)
}

///|
fn fire_app_key_hooks(kev : KeyEvent) -> Bool {
  for f in g_app_key_hooks {
    if f(kev) {
      return true
    }
  }
  false
}

///|
/// 进程里第一扇还在的窗：服务组件（检查器附窗开关这类）开窗拿句柄用。
pub fn primary_host() -> WindowHost? {
  match host_windows().get(0) {
    Some(h) => Some(h)
    None => None
  }
}

///|
/// 输入法四条件里的后两条在此收口：每拍喂 surrounding + 插入符矩形，
/// 取走 commit 与组合串投给焦点控件（只喂已提交文本，不调 reset）。
pub fn WindowHost::pump_ime(self : WindowHost) -> Unit {
  let cur = match self.focus.current() {
    Some(id) => id
    None => 0
  }
  if cur != self.session.ime_focus {
    // 兜底：上层直接改了焦点栈（没走 move_focus / 点击接管）时，旧控件画着的
    // 组合串要清掉，去重缓存一并复位。真正的前置清理见 flush_ime_for_switch。
    // （-1 是「未同步」哨兵：见 Session 字段注——它只逼出下面的门同步，
    // 不是控件 id，不走组合串清理。）
    if self.session.ime_focus > 0 && self.session.last_preedit.0.length() > 0 {
      self.root.dispatch_preedit(self.session.ime_focus, "", 0)
    }
    self.session.ime_focus = cur
    self.session.last_preedit = ("", 0)
    // 输入法焦点门同步给后端：焦点控件是输入框才让 IM 过滤按键——ibus 一类
    // 会话里 IM 会把字符键全吃进 commit 通道，非输入框焦点时按键事件就只剩
    // 修饰键（真机症状：键盘回显恒 65507 = Control_L）
    self.session.window.set_im_active(self.root.im_context_of(cur) is Some(_))
  }
  if cur == 0 {
    return ()
  }
  match self.root.im_context_of(cur) {
    None => ()
    Some((text, caret)) => {
      self.session.window.set_im_surrounding(text, caret)
      match self.root.im_cursor_of(cur) {
        Some(r) =>
          self.session.window.set_im_cursor(
            r.x.floor().to_int(),
            r.y.floor().to_int(),
            r.w.ceil().to_int(),
            r.h.ceil().to_int(),
          )
        None => ()
      }
      let mut more = true
      while more {
        match self.session.window.take_commit() {
          Some(t) =>
            // 提交文本画在焦点控件自己的盒内，局部置脏（entry 这类提交后
            // 有跨控件反应的组件自己会 invalidate 整窗兜底）
            if self.root.dispatch_commit(cur, t) {
              match self.root.by_id(cur) {
                Some(w) => self.mark_widget_rect(w)
                None => self.schedule_paint()
              }
            }
          None => more = false
        }
      }
      let st = self.session.window.preedit()
      if st.text != self.session.last_preedit.0 ||
        st.caret != self.session.last_preedit.1 {
        self.session.last_preedit = (st.text, st.caret)
        self.root.dispatch_preedit(cur, st.text, st.caret)
        match self.root.by_id(cur) {
          Some(w) => self.mark_widget_rect(w)
          None => self.schedule_paint()
        }
      }
    }
  }
}

///|
let text_batch_done : Ref[Bool] = Ref(false)

///|
/// 文本帧级批的一次性接线：①注册光栅前置闸——任何写像素操作前按裁剪矩形
/// 冲掉相交的待批文本（保「后画的盖住先画的」；不相交则继续攒批，卡片墙
/// 这类「填充-文本-填充-文本」交错序列也能攒出长批）；②打开 C 侧批开关。
/// 测试与探针不经过这里，文本批保持关闭、像素行为与旧路径逐位一致。
fn text_batch_init() -> Unit {
  if !text_batch_done.val {
    text_batch_done.val = true
    @render.set_raster_gate(fn(x0, y0, x1, y1) {
      @text.flush_before_raster(x0, y0, x1, y1)
    })
    @text.enable_batching()
  }
}

///|
/// 一帧的绘制：根控件恒等尺寸取窗口内容尺寸，布局→绘制→上屏。
/// 脏区非整窗时把绘制器裁到脏区——控件遍历的视口剔除按当前裁剪框判交，
/// 裁剪外整块跳过；位图按窗复用保留上一帧内容，裁剪外像素即上一帧。
// 布局诊断读数的上一帧宽（见 paint_frame 的 NATIVEGUI_LAYOUT_LOG）。
let layout_log_last_w : Ref[Int32] = Ref(0)

///|
/// 条带快路径命中次数：白盒用例据此确认本帧真的走了快路径（生产只多一次自增）。
let strip_hits : Ref[Int32] = Ref(0)

///|
/// NATIVEGUI_PROF=1 的周期读数：上次打印的时刻与 a11y 对账的上次时刻。
let prof_log_last : Ref[Int64] = Ref(0)
let a11y_sync_last : Ref[Int64] = Ref(0)

///|
/// 条带快路径的上一帧快照缓冲（进程级复用）：只给分数缩放/亚像素视口的分支
/// 兜底——那一档的设备位移不是整行，只能整幅贴回；每帧 new 一张 MB 级
/// FixedArray 会走大块 malloc/free，同尺寸直接 blit 覆盖。
let g_strip_snapshot : Ref[@render.Bitmap?] = Ref(None)

///|
/// 设备像素对齐判据：值离最近的整数不到百分之一像素。
fn dev_int_ok(v : Double) -> Bool {
  let r = v.round()
  (v - r) > -0.01 && (v - r) < 0.01
}

///|
fn strip_snapshot(bm : @render.Bitmap) -> @render.Bitmap {
  match g_strip_snapshot.val {
    Some(s) if s.width == bm.width && s.height == bm.height => {
      bm.data.blit_to(s.data, len=bm.data.length())
      s
    }
    _ => {
      let s = @render.Bitmap::copy(bm)
      g_strip_snapshot.val = Some(s)
      s
    }
  }
}

///|
pub fn WindowHost::paint_frame(self : WindowHost) -> Unit {
  text_batch_init()
  // 帧号先进一格：被画到的控件在这一格里记账，自转组件据此判断「这帧有没有我」
  let _ = bump_paint_epoch()
  self.session.dirty = false
  let clip = dirty_clip(self.dirty_full, self.dirty_rect)
  self.dirty_full = false
  self.dirty_rect = None
  let scroll = self.scroll_pending
  self.scroll_pending = None
  let (w, h) = self.session.window.size()
  // 诊断读数：NATIVEGUI_LAYOUT_LOG 非空时，宽度变化的绘制帧打一行——
  // 定位「resize 后内容不重排」类问题的断点（事件 / 账本 / 布局哪层没跟上）。
  // 关闭时零开销（每帧一次字符串比较之外只有一次 env 读……env 读也在门里）。
  if w != layout_log_last_w.val &&
    @env.get_env_var("NATIVEGUI_LAYOUT_LOG") is Some(_) {
    layout_log_last_w.val = w
    println("LAYOUT-FRAME w=\{w} h=\{h}")
  }
  if w < 1 || h < 1 {
    // 盒还没成好，这一帧画不了——但**别把脏标记吃掉**：画不了就没布局，收框也就
    // 永远量不到内容尺寸，两者互相等就成了「窗在、点位对、整块空白」的死局
    // （真机 mac 弹层）。C 侧在贴不出帧时本来就会再请一次重绘，这里跟着它留脏；
    // 同时排首帧兜底，防止平台重绘请求也被吞掉。
    self.session.dirty = true
    arm_first_paint_retries(self)
    return ()
  }
  // 绘制前同步一次焦点标志：焦点栈、控件树、重挂都可能在上一拍改过
  match self.focus.current() {
    Some(id) => self.root.set_focused_by_focus(id)
    None => self.root.set_focused_by_focus(0)
  }
  // 读屏焦点通道：焦点换了通知平台臂（mac AX FocusedUIElementChanged）。
  // 焦点栈的 id 是控件声明的 focus_id，快照行存的是 widget id——报之前换算。
  a11y_set_focus(
    match self.focus.current() {
      Some(fid) => a11y_focus_widget_id(self.root, fid)
      None => 0
    },
  )
  // 分段账本从帧起算：位图分配（仅变尺寸时发生）计入 total 不计入单段，
  // 避免把「分配」混进「布局」
  let t0 = @win.now_ms()
  // 设备缩放：1 逻辑单位折合的物理像素数（虚窗 / 无缩放档恒 1）。窗口账本
  // 是逻辑单位，位图按 逻辑 × 因子 开物理像素，Painter 全局 CTM 放大后整树
  // 仍按逻辑坐标画——100% 档各值相等，与旧路径逐位一致。因子每帧现读：
  // 跨缩放档拖动后位图复用判据自动失配重建、CTM 自动取新值，无需事件。
  let sc = self.session.window.scale()
  let pw = (w.to_double() * sc + 0.5).to_int()
  let ph = (h.to_double() * sc + 0.5).to_int()
  // 位图按窗复用（比物理尺寸）：尺寸不变直接续用上一帧的缓冲，只有变尺寸
  // 才重建
  let bm = match self.canvas {
    Some(b) if b.width == pw && b.height == ph => b
    _ => {
      let b = @render.Bitmap::new(pw, ph)
      self.canvas = Some(b)
      b
    }
  }
  let p = @render.Painter::new(bm)
  p.scale(sc, sc)
  // 本帧脏区（窗口逻辑坐标，已与窗口边界求交）：随 present 下传，平台把贴帧
  // 裁到脏区——滚动帧只贴视口条带，GTK/Win32 各省一整窗重贴
  let dmg_x = Ref(-1)
  let dmg_y = Ref(-1)
  let dmg_w = Ref(-1)
  let dmg_h = Ref(-1)
  match clip {
    None => ()
    Some(r) => {
      // 与窗口边界求交后裁剪；空矩形整帧无事可做
      let x0 = if r.x < 0.0 { 0.0 } else { r.x }
      let y0 = if r.y < 0.0 { 0.0 } else { r.y }
      let wd = w.to_double()
      let hd = h.to_double()
      let x1 = if r.x + r.w > wd { wd } else { r.x + r.w }
      let y1 = if r.y + r.h > hd { hd } else { r.y + r.h }
      if x1 > x0 && y1 > y0 {
        p.clip_rect(x0, y0, x1 - x0, y1 - y0)
        dmg_x.val = x0.round().to_int()
        dmg_y.val = y0.round().to_int()
        dmg_w.val = (x1 - x0).round().to_int()
        dmg_h.val = (y1 - y0).round().to_int()
      } else {
        return
      }
    }
  }
  self.root.set_size(w.to_double(), h.to_double())
  self.root.relayout(w.to_double(), h.to_double())
  let t1 = @win.now_ms()
  // 条带快路径：本帧唯一脏区就是滚动视口、位移为整数、无毛玻璃与原生子件；
  // 任一不满足就走普通视口整块重绘（正确性优先）
  let strip_plan = match (clip, scroll) {
    (Some(cr), Some((vid, sdy, ext))) =>
      match self.root.by_id(vid) {
        Some(v) => {
          let vr = v.rect
          let dyi = sdy.round()
          let int_ok = (sdy - dyi) > -0.01 && (sdy - dyi) < 0.01
          let same = cr.x == vr.x &&
            cr.y == vr.y &&
            cr.w == vr.w &&
            cr.h == vr.h
          if strip_scrollable(v) &&
            int_ok &&
            dyi != 0.0 &&
            same &&
            vr.w > 16.0 &&
            vr.h > 16.0 &&
            !self.session.window.has_child_surfaces() &&
            !tree_blur_hit(self.root, vr) {
            // 设备像素对齐：缩放为整倍、视口四边与位移都落在设备像素上才走
            // 就地整行搬移；分数缩放/亚像素视口退回快照贴回
            let dy_dev_f = dyi * sc
            let dev_ok = dev_int_ok(dy_dev_f) &&
              dev_int_ok(vr.x * sc) &&
              dev_int_ok(vr.y * sc) &&
              dev_int_ok((vr.x + vr.w) * sc) &&
              dev_int_ok((vr.y + vr.h) * sc)
            Some((vr, dyi, ext, v.strip_ink, dy_dev_f.round().to_int(), dev_ok))
          } else {
            None
          }
        }
        None => None
      }
    _ => None
  }
  match strip_plan {
    Some((vr, sdy, ext, ink, dy_dev, dev_ok)) => {
      strip_hits.val = strip_hits.val + 1
      // ① 视口内整块按整数位移平移
      if dev_ok {
        // 就地逐行搬移：不分配、不逐像素，2 倍屏与 1 倍屏同一条路
        bm.shift_rows(
          (vr.x * sc).round().to_int(),
          ((vr.x + vr.w) * sc).round().to_int(),
          (vr.y * sc).round().to_int(),
          ((vr.y + vr.h) * sc).round().to_int(),
          dy_dev,
        )
      } else {
        // 分数缩放/亚像素视口：快照上一帧再整幅贴回，通用平移兜底
        let snap = @render.Canvas::from_bitmap(strip_snapshot(bm))
        p.save()
        p.clip_rect(vr.x, vr.y, vr.w, vr.h)
        p.draw_canvas_from_rect(
          snap,
          0.0,
          0.0,
          bm.width.to_double(),
          bm.height.to_double(),
          0.0,
          sdy,
          w.to_double(),
          h.to_double(),
        )
        p.restore()
      }
      // ② 修复新露条带（|位移| + 最高行余量 + 视口固定墨迹）与滚动条列。
      // 固定墨迹是视口自己画的、不随内容滚动的那圈描边：平移会把旧帧的边框行
      // 搬进视口内部（新露条带的近侧一行），不把它盖进重画范围就留成横纹。
      let ad = if sdy > 0.0 { sdy } else { 0.0 - sdy }
      let band_h = ad + ext + ink
      let band : Rect = if sdy > 0.0 {
        { x: vr.x, y: vr.y, w: vr.w, h: band_h }
      } else {
        { x: vr.x, y: vr.y + vr.h - band_h, w: vr.w, h: band_h }
      }
      let sb : Rect = { x: vr.x + vr.w - 12.0, y: vr.y, w: 12.0, h: vr.h }
      // 视口描边/底色随整块平移：新露条带在另一端，对侧的边线被移出后要补画；
      // 补线高度取 2 行与墨迹宽度的较大值
      let edge_h = if ink > 2.0 { ink } else { 2.0 }
      let edge : Rect = if sdy > 0.0 {
        { x: vr.x, y: vr.y + vr.h - edge_h, w: vr.w, h: edge_h }
      } else {
        { x: vr.x, y: vr.y, w: vr.w, h: edge_h }
      }
      paint_clipped(self.root, p, band)
      paint_clipped(self.root, p, sb)
      paint_clipped(self.root, p, edge)
    }
    None => self.root.paint(p)
  }
  // 帧级文本批：整树画完先把待批段落位（C 侧一次 BeginDraw/EndDraw 提交 +
  // 并集读回混合），present 读到的才是完整帧
  @text.flush_pending()
  p.end()
  // 帧尾语义对账：重扫整树快照，排在上屏前（读屏拿到的矩形必须是这一帧的）。
  // 滚动帧降频：惯性/回弹的每拍只是条带位移，读屏不需要逐帧的矩形刷新——
  // 150ms 对账一次，滚动停下后由随后的非滚动帧把终态补齐
  let scroll_frame = scroll is Some(_)
  if !scroll_frame || @win.now_ms() - a11y_sync_last.val >= 150 {
    let _ = a11y_frame_sync(self.root)
    a11y_sync_last.val = @win.now_ms()
  }
  // 读屏动作通道（UIA Invoke/Toggle/Expand / AT-SPI DoAction / AX press）：
  // 抽干并合成点击，会话状态接回去
  let act = a11y_pump_actions(
    self.root,
    self.session.hover_id,
    self.session.capture,
  )
  self.session.hover_id = act.0
  self.session.capture = act.1
  // AT-SPI 桥（Linux）：窗口原点报给平台侧（Component 的屏幕坐标 = 原点 +
  // 快照矩形），再抽干读屏查询、比对新旧快照发事件。无 a11y 总线时
  // atspi_tick 内部按背间隔重试，不开读屏的会话零开销（一次状态判断）。
  let (wox, woy) = self.session.window.origin()
  @win.a11y_set_window_origin(wox.to_double(), woy.to_double())
  @shell.atspi_tick()
  let t2 = @win.now_ms()
  self.session.window.present(
    bm.data,
    bm.width,
    bm.height,
    dmg_x.val,
    dmg_y.val,
    dmg_w.val,
    dmg_h.val,
  )
  // 最近一帧位图登记（inspector shot 用）：canvas 是按窗复用的缓冲，present
  // 后内容就是本帧完整体，进程级记引用即可（只读，不改写）
  self.frame_register(bm)
  // present 成功只计「提交过一帧」（诊断用）：帧是否真落屏要等平台映射，
  // 首帧兜底的收口在三拍计时器里，不在这里提前缴械。
  self.painted_once = true
  let t3 = @win.now_ms()
  // 分段账本：位图分配计入 total 不计入单段，避免把「分配」混进「布局」
  prof_record(t1 - t0, t2 - t1, t3 - t2, t3 - t0)
  // 诊断读数（NATIVEGUI_PROF=1）：每 2s 打一行窗口帧账本并清账——布局/绘制/
  // 上屏三段占比、条带命中数，滚动卡顿归因用
  if @env.get_env_var("NATIVEGUI_PROF") is Some(_) && t3 - prof_log_last.val >= 2000 {
    println(
      "PROF " +
      @base.paint_profile_summary() +
      " strip=" +
      strip_hits.val.to_string(),
    )
    @base.paint_profile_reset()
    strip_hits.val = 0
    prof_log_last.val = t3
  }
}

///|
/// 最近上屏一帧的位图（进程级一份，多窗应用记最后 present 的那扇）：
/// inspector 的 shot 命令从这里取图。位图是按窗复用的绘制缓冲，读侧只读。
let g_last_frame_bitmap : Ref[@render.Bitmap?] = Ref(None)

///|
/// 最近上屏一帧所属窗口的标题（shot 落盘文件名用）。
let g_last_frame_title : Ref[String] = Ref("")

///|
/// 最近上屏一帧的窗口根控件（整页重画找滚动容器用）。
let g_last_frame_root : Ref[Widget?] = Ref(None)

///|
/// 取数指定窗（检查器附窗登记的触发窗）：设了之后 last_frame_* 读这扇的
/// 现役帧，不再看「最后 present 的那扇」——附窗与目标窗同进程，附窗自己
/// 上屏会把最近帧顶掉。目标窗关了或置 None 回落最近帧登记。
let g_inspect_target : Ref[WindowHost?] = Ref(None)

///|
/// 登记取数指定窗：检查器附窗开着时锁触发窗，关附窗置 None 还原。
pub fn inspect_target_set(h : WindowHost?) -> Unit {
  g_inspect_target.val = h
}

///|
/// 取数窗裁决：指定窗还活着回指定窗，否则 None（调用方回落最近帧登记）。
fn inspect_target_alive() -> WindowHost? {
  match g_inspect_target.val {
    Some(h) => if h.is_running() {
      Some(h)
    } else {
      None
    }
    None => None
  }
}

///|
/// 帧尾登记：本帧位图/窗题/根控件记进「最近帧」（inspector 取数用）。
/// `frame_untracked` 的窗跳过——附窗这类取数工具窗上屏不顶掉最近帧。
fn WindowHost::frame_register(self : WindowHost, bm : @render.Bitmap) -> Unit {
  if self.frame_untracked {
    return
  }
  g_last_frame_bitmap.val = Some(bm)
  g_last_frame_title.val = self.session.window.title()
  g_last_frame_root.val = Some(self.root)
}

///|
/// 最近一帧的位图与窗口标题：指定窗活着取指定窗的现役帧（canvas 与标题
/// 现读，变尺寸后的新缓冲也照拿），否则回落最近帧登记。没上过帧给 None。
/// 返回的是复用缓冲的引用，只读——要落盘请走 `@render.png_write_bitmap`。
pub fn last_frame_bitmap() -> (@render.Bitmap?, String) {
  match inspect_target_alive() {
    Some(h) => (h.canvas, h.session.window.title())
    None => (g_last_frame_bitmap.val, g_last_frame_title.val)
  }
}

///|
/// 最近一帧的窗口根控件：指定窗活着取指定窗根（整页重画用），否则回落
/// 最近帧登记；都没上过帧给 None。
pub fn last_frame_root() -> Widget? {
  match inspect_target_alive() {
    Some(h) => Some(h.root)
    None => g_last_frame_root.val
  }
}

///|
/// 整页重画尺寸上限：宽/高各自 clamp（超长页截到上限内，防异常内存占用）。
const FULL_PAGE_CAP : Int32 = 20000

///|
/// 深度优先找第一个 `ScrollView`（页面级滚动容器通常在浅层先命中）。
fn find_first_scroll_view(w : Widget) -> Widget? {
  if w.kind == "ui-scroll-view" {
    return Some(w)
  }
  for k in w.kids {
    match find_first_scroll_view(k) {
      Some(x) => return Some(x)
      None => ()
    }
  }
  None
}

///|
/// 整页内容重画：根下第一个 `ScrollView` 的内容子树按**全内容高**画到独立
/// 位图（滚动截图语义），返回位图与「是否因尺寸上限截断」。页内没有滚动
/// 容器时给 None（调用方回退视口帧或报错）。
///
/// 边界：虚拟列表只有视口窗口内的行真实挂载，整页图不含未挂载行；
/// GPU 档控件在独立绘制器上按 CPU 回退（`on_render` 的 Cpu 档），与主帧
/// 混排路径同语义。绘制先铺主题页面底色，内容子树原点归零到大图左上。
pub fn paint_full_page(w : Widget) -> (@render.Bitmap?, Bool) {
  let sv = match find_first_scroll_view(w) {
    Some(v) => v
    None => return (None, false)
  }
  // scroll_view 的构造序恒定：首个子件是内容容器（自然高撑开、不裁切），
  // 第二个起是滚动条
  if sv.kids.length() == 0 {
    return (None, false)
  }
  let content = sv.kids[0]
  let cw = content.rect.w.round().to_int()
  let ch = content.rect.h.round().to_int()
  if cw <= 0 || ch <= 0 {
    return (None, false)
  }
  let wpx = cw.min(FULL_PAGE_CAP)
  let hpx = ch.min(FULL_PAGE_CAP)
  let clipped = wpx < cw || hpx < ch
  let bm = @render.Bitmap::new(wpx, hpx)
  let p = @render.Painter::new(bm)
  p.set_fill_color(@theme.theme_bg_page())
  p.fill_rect(0.0, 0.0, wpx.to_double(), hpx.to_double())
  // 内容子树原点归零：paint_at 的 ox/oy 传内容绝对矩形原点，绘制期平移掉
  content.paint_at(p, content.rect.x, content.rect.y)
  p.end()
  (Some(bm), clipped)
}

///|
/// 走一圈：等事件 → 跑到期任务 → **逐窗**排空事件 → 抽外部拖入 → 逐窗喂输入法 →
/// 脏窗上屏。
/// 返回是否继续（false = 已退出）。一扇窗被关（用户点关闭、或内容里调
/// `WindowHost::close_window`）只摘掉它自己，主窗或最后一扇被关才整体退出。
pub fn WindowHost::step(self : WindowHost) -> Bool {
  if !self.is_running() {
    return false
  }
  // 泵的「等 + 到期任务」段归壳层（webview/3D 路线只吃这一半就能跑起来）
  @shell.session_pump_advance()
  self.step_tail()
}

///|
/// 外部事件循环模式的一拍：与 [WindowHost::step] 同体，差异只在「等平台
/// 事件」段——这里不等，等待由外部循环的 poll 自己做（先 `@win.wait` 再调
/// 本函数）。给 core/async 的 `ExternalEventLoop` 集成用：GUI 代码全部留在
/// 主线程，等待与派发交替进行。
pub fn WindowHost::step_no_wait(self : WindowHost) -> Bool {
  if !self.is_running() {
    return false
  }
  @shell.session_pump_advance_nowait()
  self.step_tail()
}

///|
/// 一拍的「等待之后」段：退出信号 → 逐窗排空 → 抽外部拖入 → 冲刷
/// next_tick → 逐窗输入法与脏窗上屏。
fn WindowHost::step_tail(self : WindowHost) -> Bool {
  // 退出信号（SIGINT/SIGTERM）到这一拍被取走：等事件的 poll 会被信号打断，
  // 所以这里必能在下一拍读到。走 shutdown 收口，托盘注销先于进程结束。
  if @shell.quit_requested() {
    self.shutdown()
    return false
  }
  // 遍历一律走快照：排空途中关窗会改注册表
  for a in host_windows() {
    a.drain_events()
  }
  // 外部拖入（W23a）：OLE 的 `IDropTarget` 回调打在消息派发里，这里每拍抽干队列
  // 喂进与宿主内拖放同一条会话——落点命中、`accept` 判据、松手投递全部复用。
  let _ = drag_external_pump()
  // 事件批尾冲刷 next_tick（§3 第 3 项:回调尾同步 flush,反馈不晚一帧），
  // 排在绘制之前——这批回调改的 Store 仍在本帧生效。
  tick_flush()
  if !self.is_running() {
    return false
  }
  for a in host_windows() {
    a.pump_ime()
    if a.session.dirty {
      a.paint_frame()
    }
    // 原生档浮层：首帧后按内容实测尺寸收框（最多三帧，见 overlay_native.mbt）
    overlay_fit_pass(a)
  }
  self.is_running()
}

///|
/// 排空本窗的平台事件。
fn WindowHost::drain_events(self : WindowHost) -> Unit {
  let mut keep = true
  while keep && self.is_running() {
    match self.session.window.poll_event() {
      @win.Closing => {
        self.close_window()
        keep = false
      }
      @win.NeedsDraw => self.schedule_paint()
      @win.Resized => self.schedule_paint()
      @win.Hidden => self.handle_hidden()
      @win.Shown => self.handle_shown()
      @win.LostFocus => {
        // 键盘焦点被拿走（点进网页子件、浮层或别的窗口接管）：把输入法这一会话
        // 交还给系统——在途 commit 归当前控件、清掉组合串显示、打断引擎侧未完成的
        // 组合、复位去重缓存。焦点栈不动（回到本窗时控件焦点照旧）。
        // 少了这一步，网页里打字期间旧框还挂着半截组合串，回来后的第一键也可能
        // 落进那个旧组合。
        self.flush_ime_for_switch(self.focus.current())
        overlay_on_lost_focus(self)
        // 但「让位给本窗内的原生子件」不属于上面那种情况，那是用户点了别处：
        // 必须把自绘控件的焦点清掉，否则输入框继续亮边框、闪光标，看着像还能
        // 往里打字，而键其实全进了网页。整窗失焦（切到别的应用/别的窗）不清，
        // 回到本窗时焦点照旧——这一档是使用者认过的行为。
        match self.session.window.focus_owner() {
          @win.ChildSurface => {
            self.focus.drop_current()
            self.schedule_paint()
          }
          _ => ()
        }
      }
      @win.Input =>
        match self.session.window.take_input() {
          Some(ev) => self.route(ev)
          None => ()
        }
      @win.NoEvent => keep = false
    }
  }
}

///|
/// 关一扇窗：停派发 → 摘表 → 拆平台窗口（顺序是「先停派发、再拆对象」），
/// 再按 `host_close_action` 决定整体退出还是继续跑剩下的窗。
/// 幂等：重复调用（用户点关闭 + 内容里自己调）只生效一次。
pub fn WindowHost::close_window(self : WindowHost) -> Unit {
  if self.closed {
    return
  }
  // 记窗的先落盘再拆窗（拆完 origin/size 就读不到了）
  self.save_geometry()
  self.closed = true
  self.session.running = false
  // 关闭回调先于拆平台窗：内容里的收尾（取消高亮、清引用）还能跑
  for f in self.close_cbs {
    f()
  }
  let session = self.session
  let remaining = host_window_count() - 1
  host_remove_app(self.wid())
  host_deregister(session)
  session.window.close()
  if host_close_action(session.primary, remaining) {
    @shell.remove_all_trays()
    self.session.sched.quit()
    @win.wake()
  }
}

///|
/// 阻塞式主循环。返回后由调用方拆对象（先停派发、再拆对象）。
pub fn WindowHost::run(self : WindowHost) -> Unit {
  while self.step() {

  }
}

///|
/// 关闭窗口并释放平台资源：把**所有**还在的窗一起拆掉（附窗可能还开着），
/// 注册表随之复位。已拆过的窗句柄是 -1，`wm_close` 幂等，重复调无害。
pub fn WindowHost::shutdown(self : WindowHost) -> Unit {
  @shell.remove_all_trays()
  for a in host_windows() {
    a.save_geometry()
    a.session.running = false
    a.closed = true
    a.session.window.close()
  }
  overlay_close_all_native()
  self.session.running = false
  if !self.closed {
    self.closed = true
    self.session.window.close()
  }
  host_reset()
}
