///|
/// 圆角总开关的真实落点在 `@theme`（与 `control_height` 同层：全局几何基准，
/// 绘制期现取）。本包只做两处接线：透出开关别名（历史 API 口径不变），
/// 以及绘制出口 `square_corners_applied`——经样式槽的圆角在关圆角时压 0。
///|
/// 历史 API 口径：参数 `true` = 要方角（关圆角）；`@theme` 落点口径相反，
/// 这里取反转发。语义与旧版逐字一致，调用方无感。
pub fn set_square_corners(on : Bool) -> Unit {
  @theme.corners_round_set(!on)
}

///|
/// 历史 API 读口：`true` = 方角模式（圆角关）。与 `set_square_corners` 同口径取反。
pub fn square_corners() -> Bool {
  !@theme.corners_round()
}

///|
/// 绘制出口统一过这道：圆角关闭时，样式槽里**配了值**的半径压成 0（造新值，
/// 不改侧表里的基块）；没配的槽位保持未设，组件绘制期照样现取 `@theme.radius_*()`
/// 令牌——开关同时管住两条通道。
fn square_corners_applied(s : Style) -> Style {
  if @theme.corners_round() {
    return s
  }
  match s.border_radius {
    Some(_) => ()
    None => return s
  }
  let c = merge(s, empty_style())
  c.border_radius = Some(0.0)
  c
}
