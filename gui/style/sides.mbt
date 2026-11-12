// 每角圆角 / 每边边框的绘制期解析（style-css-expansion S3）。
// 口径：per-corner 缺省回落统一 `border_radius`；每边缺省回落统一
// `border_width`/`border_color`。带圆角的逐边边框（角部接缝）诚实降级为
// 统一描边——降级判据 [has_per_side_border] + 调用方自查四角是否全 0。

///|
/// 四角有效半径（左上/右上/右下/左下）：per-corner ?? `unified`（统一值，
/// 一般传样式槽的 `border_radius`，缺省 0）。
pub fn corner_radii_of(
  s : Style,
  unified : Double,
) -> (Double, Double, Double, Double) {
  (
    number_of(s.border_top_left_radius, unified),
    number_of(s.border_top_right_radius, unified),
    number_of(s.border_bottom_right_radius, unified),
    number_of(s.border_bottom_left_radius, unified),
  )
}

///|
/// 每边边框的绘制期读数：宽度（0 = 本边不画）与颜色（回落统一色）。
pub(all) struct SideBorder {
  width : Double
  color : String
}

///|
/// 四边有效读数（上/右/下/左）：per-side width ?? 统一 `border_width` ?? 0，
/// per-side color ?? 统一 `border_color` ?? 空串。颜色在绘制期按 token 现取。
pub fn side_borders_of(
  s : Style,
) -> (SideBorder, SideBorder, SideBorder, SideBorder) {
  let uw = number_of(s.border_width, 0.0)
  let uc = color_of(s.border_color, "")
  (
    {
      width: number_of(s.border_top_width, uw),
      color: color_of(s.border_top_color, uc),
    },
    {
      width: number_of(s.border_right_width, uw),
      color: color_of(s.border_right_color, uc),
    },
    {
      width: number_of(s.border_bottom_width, uw),
      color: color_of(s.border_bottom_color, uc),
    },
    {
      width: number_of(s.border_left_width, uw),
      color: color_of(s.border_left_color, uc),
    },
  )
}

///|
/// 是否给了任一 per-side 边框（显式覆盖统一描边的判据）。
pub fn has_per_side_border(s : Style) -> Bool {
  s.border_top_width is Some(_) ||
  s.border_top_color is Some(_) ||
  s.border_right_width is Some(_) ||
  s.border_right_color is Some(_) ||
  s.border_bottom_width is Some(_) ||
  s.border_bottom_color is Some(_) ||
  s.border_left_width is Some(_) ||
  s.border_left_color is Some(_)
}

///|
/// 是否给了任一 per-corner 圆角。
pub fn has_per_corner_radius(s : Style) -> Bool {
  s.border_top_left_radius is Some(_) ||
  s.border_top_right_radius is Some(_) ||
  s.border_bottom_right_radius is Some(_) ||
  s.border_bottom_left_radius is Some(_)
}
