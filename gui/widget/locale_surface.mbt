// 语言变更下的原生表面接线：文本组件绘制期现取译文自动跟随，这里管
// **控件树之外**的那批——菜单栏。登记构建函数即挂上所有宿主窗，此后每次
// 换目录（`i18n_load`/`i18n_extend`/`i18n_reset`）自动重算重挂，调用方
// 不再手工「切语言时记得刷菜单」。

///|
/// 菜单栏只有一条：重复登记**替换**旧构建器（先退订再挂新的），不叠监听。
let menu_slot : Ref[Int] = Ref(0)

///|
/// 挂「随语言的菜单栏」：立即按 `builder` 给每扇已注册的宿主窗建原生菜单栏，
/// 并订阅语言变更——之后换目录逐窗用新译文重挂。重复调用以最后一次为准。
pub fn set_menu_bar_localized(builder : (@win.Window) -> @shell.MenuBar) -> Unit {
  let apply = fn(_loc : String) -> Unit {
    for a in host_windows() {
      let _ = (builder(a.window())).apply_to(a.window())
    }
  }
  apply(@i18n.i18n_locale())
  if menu_slot.val != 0 {
    @i18n.off_locale_change(menu_slot.val)
  }
  menu_slot.val = @i18n.on_locale_change(apply)
}
