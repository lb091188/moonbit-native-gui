// 设计令牌：间距阶 / 半径阶 / 字阶 / 时长阶（style-css-expansion S1）。
// 阶值是「档位数组」，进 `Theme` 随主题分发（JSON 可定制，见 `from_json`
// 白名单）；下面的 base 常量是基准档，也是静态消费源（`@style.tokens` 的
// 组件基调与 `space_*` 静态令牌按此取值）。getter 读**当前主题**的阶，
// 空表回落基准，越界按首末档夹取。

///|
/// 间距阶基准（与 native-gui-design 技能的间距刻度同源：2/4/6/8/12/16/24）。
pub let space_scale_base : Array[Double] = [
  2.0, 4.0, 6.0, 8.0, 12.0, 16.0, 24.0,
]

///|
/// 半径阶基准（控件 4 / 卡片·面板 6 / 对话框·浮层 8，上限 8；圆形态组件
/// 不吃此阶，永远按几何取圆——与圆角开关口径一致）。
pub let radius_scale_base : Array[Double] = [4.0, 6.0, 8.0]

///|
/// 字阶基准（次要小字 12 / 正文 13 / 面板标题 14 / 大标题 18；与
/// `font_size_*` 令牌同源）。
pub let type_scale_base : Array[Double] = [12.0, 13.0, 14.0, 18.0]

///|
/// 时长阶基准（ms：快 80 / 常速 120 / 平滑 200 / 强调 320）。现状库内
/// `transition_ms` 无集中档，此阶供样式与应用按档取用。
pub let duration_scale_base : Array[Double] = [80.0, 120.0, 200.0, 320.0]

// ---- 静态间距令牌（tokens.mbt 组件基调的消费源，单源基准档）----

///|
pub let space_2 : Double = 2.0

///|
pub let space_4 : Double = 4.0

///|
pub let space_6 : Double = 6.0

///|
pub let space_8 : Double = 8.0

///|
pub let space_12 : Double = 12.0

///|
pub let space_16 : Double = 16.0

///|
pub let space_24 : Double = 24.0

///|
/// 阶取值：空表回落基准、越界按首末档夹取。
fn scale_at(scale : Array[Double], base : Array[Double], i : Int32) -> Double {
  let src = if scale.length() > 0 { scale } else { base }
  if i < 0 {
    src[0]
  } else if i >= src.length() {
    src[src.length() - 1]
  } else {
    src[i]
  }
}

///|
/// 间距阶第 `i` 档（当前主题；0=2 … 6=24，越界夹取）。
pub fn theme_space(i : Int32) -> Double {
  scale_at(theme_box.t.space_scale, space_scale_base, i)
}

///|
/// 半径阶第 `i` 档（当前主题；0=控件 4 / 1=卡片 6 / 2=浮层 8）。
pub fn theme_radius(i : Int32) -> Double {
  scale_at(theme_box.t.radius_scale, radius_scale_base, i)
}

///|
/// 字阶第 `i` 档（当前主题；0=12 / 1=13 / 2=14 / 3=18）。
pub fn theme_type_size(i : Int32) -> Double {
  scale_at(theme_box.t.type_scale, type_scale_base, i)
}

///|
/// 时长阶第 `i` 档（当前主题，ms；0=80 / 1=120 / 2=200 / 3=320）。
pub fn theme_duration(i : Int32) -> Double {
  scale_at(theme_box.t.duration_scale, duration_scale_base, i)
}
