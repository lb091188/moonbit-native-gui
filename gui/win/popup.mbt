// 原生弹层窗口：把一扇窗配成「弹层」——无边框、不进任务栏、transient 到
// owner、恒在 owner 之上。存在的理由是一条物理事实：自绘像素永远画在原生子件
// （webview 区）之下，所以浮层要能盖住网页，就必须是真的顶层窗口（方案 §4.5）。

///|
/// 在 `show` 之前调用才生效（类型提示与 transient 关系在映射时定）。
/// owner 给 None 时只去装饰与置顶（例如独立的全屏遮罩）。
///
/// `want_focus`：菜单/下拉/提示类传 false——弹层窗不激活、不抢键盘焦点，
/// ↑↓/回车/Esc 走 owner 触发件的按键处理，点外收起由宿主侧手势判定；
/// 对话框这类要键盘输入的传 true。
pub fn Window::set_popup(
  self : Window,
  owner : Window?,
  want_focus~ : Bool = false,
) -> Unit {
  let oid = match owner {
    None => 0L
    Some(o) => o.id
  }
  wm_window_set_popup(self.id, oid, if want_focus { 1 } else { 0 })
}

///|
/// 请该窗下一帧重画：原生弹层 mount 内容后调（show 时内容还没挂上，
/// 首帧画的是空框；不补这一下，弹层重开要等鼠标移动才出内容）。
pub fn Window::request_redraw(self : Window) -> Unit {
  wm_window_request_redraw(self.id)
}

///|
/// 摆到屏幕坐标（弹层按「owner 原点 + 锚点的窗口内矩形」算）。
pub fn Window::move_to(self : Window, x : Int32, y : Int32) -> Unit {
  wm_window_move(self.id, x, y)
}

///|
/// 这扇窗拿到过键盘焦点没有：原生浮层「失焦即收起」的武装判据——映射期的
/// 焦点来回只发送焦，没当过 key 的窗失焦不算「用户点了别处」。
pub fn Window::had_focus(self : Window) -> Bool {
  wm_window_had_focus(self.id) != 0
}

///|
/// 客户区在屏幕上的原点（拿不到时给 (0,0)，调用方按它摆位不会崩，只会贴边）。
pub fn Window::origin(self : Window) -> (Int32, Int32) {
  let ox = Ref(0)
  let oy = Ref(0)
  wm_window_origin(self.id, ox, oy)
  (ox.val, oy.val)
}
