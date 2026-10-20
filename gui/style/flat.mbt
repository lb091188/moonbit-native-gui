///|
/// 圆角总开关：打开后所有经样式槽的圆角按 0 解析（控件与布局不变，只去圆角）。
/// 切换由调用方触发重绘——整窗入口是 `@widget.host_repaint_all()`。
let square_corners_flag : Ref[Bool] = Ref(false)

///|
pub fn set_square_corners(on : Bool) -> Unit {
  square_corners_flag.val = on
}

///|
pub fn square_corners() -> Bool {
  square_corners_flag.val
}

///|
/// 绘制出口统一过这道：开关打开时圆角压成 0（造新值，不改侧表里的基块）。
fn square_corners_applied(s : Style) -> Style {
  if !square_corners_flag.val {
    return s
  }
  let c = merge(s, empty_style())
  c.border_radius = Some(0.0)
  c
}
