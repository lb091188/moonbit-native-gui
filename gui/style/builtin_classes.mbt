// 内置命名类（带 `dark:`/`light:` 变体档）：变体前缀写法的内置消费者注册表。
// 基档数值来自 tokens.mbt 现状口径；变体档只收「深色下确实要分档」的属性
// ——浅底浮层的描边、深底下提亮的细线细件（`border` 色在深底页面对比不足）。
// `install_builtin_classes` 幂等；组件消费口（`apply_variant_named` /
// `@ui.fold_style_variant`）先装再解析。

///|
let builtin_installed : Ref[Bool] = Ref(false)

///|
/// 注册内置命名类（幂等）。类名与变体档：
/// - `tooltip`：深底气泡（`tooltip_base` 口径，字色取 `bg_page`——深浅两档
///   自动反转：浅档深底白字、深档浅底深字）；`tooltip-dark:dark` 深色档
///   另加 1px `border` 描边（浅底浮层与浅色内容分离）；
/// - `scroll-thumb`：滚动条拇指（`border` 色，现状口径）；
///   `scroll-thumb-dark:dark` 深色档提亮为 `text_secondary`；
/// - `divider-line`：分隔线（`border` 色）；`divider-line-dark:dark`
///   深色档提亮为 `text_secondary`。
pub fn install_builtin_classes() -> Unit {
  if builtin_installed.val {
    return
  }
  builtin_installed.val = true
  define_class("tooltip", merge(tooltip_base, style(color="bg_page")))
  define_class(
    "tooltip-dark",
    style(
      background_color="text_primary",
      color="bg_page",
      border_width=1.0,
      border_color="border",
    ),
  )
  define_class("scroll-thumb", style(background_color="border"))
  define_class("scroll-thumb-dark", style(background_color="text_secondary"))
  define_class("divider-line", style(background_color="border"))
  define_class("divider-line-dark", style(background_color="text_secondary"))
}

///|
/// 变体类的组件消费口（整槽拥有者）：装内置类 → 按**当前深浅档**解析
/// （`dark:`/`light:` 前缀选枚）落到控件，并订阅主题变更——切深浅后重解析
/// 重挂（变体生效），重绘走控件既有的主题订阅通路。适合样式槽全归默认层
/// 的裸控件（滚动条拇指这类）；组件 fold 链用 `@ui.fold_style_variant`，
/// 瞬态浮层用 `resolve_with_variant` 构造期解析一次即可。
pub fn apply_variant_named(w : @widget.Widget, names : Array[String]) -> Unit {
  install_builtin_classes()
  let reapply = fn() -> Unit {
    apply(w, resolve_with_variant(names, @theme.theme_is_dark()))
  }
  reapply()
  let _ = @theme.on_theme_change(reapply)
}
