// 样式层的枚举与对外类型名（design.md §1.1 / §1.5）。
//
// 本工具链没有 `abbrev` 关键字（实测 [3002]，见 design.md §1.6），类型短名一律
// 走 `pub using`：`using @pkg {type X}` 把外部类型引进来当本名用，`pub` 后
// 本包各文件与外部调用点都能直接写 `TextAlign` / `Display` 这类短名。

///|
pub using @text {type TextAlign, type FontWeight}

///|
pub using @yoga {
  type Display,
  type PositionType,
  type FlexDirection,
  type JustifyContent,
  type AlignItems,
  type FlexWrap,
}

///|
/// 书写/布局方向:CSS `direction` 的两档。`Rtl` 让布局镜像——主轴 row 反向、
/// 起终对齐翻转,整窗从右渲染。默认不设等同 `Ltr`(现行为)。
/// 注:这是**布局镜像**,文本 run 内的基方向由引擎 bidi 另行处理。
pub(all) enum Direction {
  Ltr
  Rtl
}

///|
/// 文本装饰线：CSS `text-decoration` 的自绘三档（下划线/删除线/上划线）与无。
/// 折行文本的线落最后一行下方/上方（与 underline 同一降级口径）。
pub(all) enum TextDecoration {
  Underline
  LineThrough
  Overline
  DecoNone
}

///|
/// 溢出形态：`Hidden` 裁到控件矩形（默认，与本栈控件绘制现状一致），
/// `Visible` 跳过裁切（阴影/越界装饰的逃生口）。
pub(all) enum Overflow {
  Visible
  Hidden
}

///|
/// 换行形态：CSS `white-space` 的两档（`nowrap` 即不折行）。
pub(all) enum WhiteSpace {
  Normal
  NoWrap
}

///|
/// 边框线形：CSS `border-style` 的三档。虚线图案不是自由数组——按
/// `border_width` 派生（dashed = 实 3 空 2、dotted = 圆头点、间距 2 倍宽），
/// 与 CSS「线形定档、粗细定周期」同口径。自定义图案仍走 Painter 层
/// `set_dashes`（画布即时绘制）。
pub(all) enum BorderStyle {
  Solid
  Dashed
  Dotted
}

///|
/// 可见性：`visibility` 只两档（折叠占位一类没有对应绘制语义，不设）。
/// `hidden` 落宿主 `Widget::set_visible(false)`（仍参与布局，与 CSS 同义）。
pub(all) enum Visibility {
  Visible
  Hidden
}
