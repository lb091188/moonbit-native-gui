// 字体：族名 + 逻辑像素字号 + 字重/样式。字重数值与 CSS 同口径（100..900），
// 直传 Pango（PangoWeight 就是该数值域），枚举名与旧契约 `yue/painter.mbt`
// 一致。主题层落地后由 `theme_font_body()` 之类给出默认值，本层默认字体是
// 「空族名 + 13px 常规」——空族名让 Pango 走系统默认族。

///|
pub(all) enum FontWeight {
  Thin
  ExtraLight
  Light
  Normal
  Medium
  SemiBold
  Bold
  ExtraBold
  Black
}

///|
fn weight_value(w : FontWeight) -> Int {
  match w {
    Thin => 100
    ExtraLight => 200
    Light => 300
    Normal => 400
    Medium => 500
    SemiBold => 600
    Bold => 700
    ExtraBold => 800
    Black => 900
  }
}

///|
pub(all) enum FontStyle {
  Roman
  Italic
}

///|
pub(all) struct Font {
  name : String
  size : Double
  weight : FontWeight
  style : FontStyle
  /// 字距（逻辑像素）：每个字符后追加的额外前进量，0 = 不调整。
  /// 测量与绘制同源，宽度差恰为「字符数 × spacing」（三平台同口径）。
  spacing : Double
}

///|
/// 创建字体（size 为逻辑像素，不是磅；spacing 为字距，逻辑像素）。
pub fn Font::new(
  name : String,
  size : Double,
  weight? : FontWeight = Normal,
  style? : FontStyle = Roman,
  spacing? : Double = 0.0,
) -> Font {
  { name, size, weight, style, spacing }
}

///|
/// 默认正文字体：空族名（Pango 用系统默认）+ 13px 常规。
pub fn font_body() -> Font {
  Font::new("", 13.0)
}

///|
fn style_id(s : FontStyle) -> Int {
  match s {
    Roman => 0
    Italic => 1
  }
}
