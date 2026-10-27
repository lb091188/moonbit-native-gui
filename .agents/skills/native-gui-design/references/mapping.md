# 表达映射：基准值落在哪个参数上

接口真相在工程内 `.mooncakes/NoahLiu/native-gui/`（各包 `.mbt` 源码 + `pkg.generated.mbti`）。下面是本基准用到的那一层的参数名与取值形态，名字都是当前版本核对过的；升级库后不确定就先读 `.mbti` 再用。

## 颜色字符串

`background_color=` / `color=` / `border_color=` 收 `String`，三选一形态：

| 写法 | 判定 | 什么时候用 |
|---|---|---|
| `"bg_panel"` | 裸名 → theme token | 界面代码里**只用这个** |
| `"#2D68C4"` | `#` 前缀 → 十六进制 | 只在定义主题/自定义皮肤时用 |
| `"white"` | CSS 命名色（大小写不敏感） | 同上 |

token 名写错在构造期就报错，并回显可用清单。

## 20 个颜色 token

| token | 语义 | 默认浅色值 |
|---|---|---|
| `primary` | 主色：主操作、选中、焦点环 | `#2D68C4` |
| `primary_light` | 主色浅底（选中行、软按钮底） | `#E8F0FB` |
| `primary_hover` | 主色悬停加深 | `#2459A8` |
| `danger` | 危险/错误 | `#D64550` |
| `danger_light` | 危险浅底 | `#FBEDED` |
| `danger_hover` | 危险悬停加深 | `#BC3440` |
| `success` | 成功 | `#2E9E5B` |
| `success_light` | 成功浅底 | `#E9F5EE` |
| `warning` | 警告 | `#D9822B` |
| `warning_light` | 警告浅底 | `#FBF3E8` |
| `info` | 次要信息 | `#6B7480` |
| `info_light` | 次要信息浅底 | `#F0F2F4` |
| `text_primary` | 标题文字（最高对比） | `#2A2F36` |
| `text_regular` | 正文文字 | `#4E5560` |
| `text_secondary` | 次要文字 | `#6B7480` |
| `border` | 描边 | `#D8DCE1` |
| `fill_hover` | 悬停铺底 | `#EFF1F3` |
| `fill_zebra` | 斑马纹 | `#F5F7FA` |
| `bg_page` | 页面底（窗口/滚动区最下层） | `#F5F6F7` |
| `bg_panel` | 面板底（卡片/侧栏/输入框/弹层） | `#FFFFFF` |

另有 `@theme.chart_palette : Array[String]`（图表系列色，按序取）与 `@theme.control_height = 32.0`（控件高度契约）。深色模式是同一套 token 的另一组值，界面代码不需要分支。

按 token 名现取颜色用 `@style.theme_token_value("primary")`（在 `@style`，不在 `@theme`）。

## 布局枚举要先声明依赖

`Display` / `FlexDirection` / `JustifyContent` / `AlignItems` / `FlexWrap` / `PositionType` 这些类型名 `@style` 有再导出，但**枚举构造子没有**——写 `@yoga.Row` 必须自己引进 yoga 包，否则 `[4020] Package "yoga" not found`：

```toml
# moon.mod
import {
  "NoahLiu/native-gui@<版本>",
  "NoahLiu/yoga-mbt@<版本>",
}
```

```toml
# 用到布局枚举的那个包的 moon.pkg
import {
  "NoahLiu/native-gui/ui",
  "NoahLiu/yoga-mbt/src" @yoga,
}

supported_targets = "native"
```

`supported_targets` 不写会警告「依赖的包声明了但本包没声明」；不相关的包别引进 `moon.pkg`，未使用的包同样报警。

`@text`（`NoahLiu/native-gui/text`）提供 `FontWeight` 与 `TextAlign` 的构造子，直接引包即可，它是 native-gui 自己模块内的包。写辅助函数时类型要标 `@widget.Node` 的话，同样要在 `moon.pkg` 引 `"NoahLiu/native-gui/widget" @widget`。

## `@style.style(...)` 参数表

全部是 labelled 可选参数，只写要用到的那些。**简写先铺、逐边参数在后覆写**：`padding=12.0, padding_top=4.0` 得到上 4 其余 12。

| 组 | 参数 | 类型 / 形态 |
|---|---|---|
| 文字 | `color` `background_color` `font_family` | `String`（见上表形态） |
| | `font_size` `line_height` `letter_spacing` | `Double`——`line_height` 是**行盒像素**且只在单行生效 |
| | `font_weight` | `@text.Thin` `ExtraLight` `Light` `Normal` `Medium` `SemiBold` `Bold` `ExtraBold` |
| | `text_align` | `@text.Start` `Center` `End`（没有 Left/Right/Justify） |
| | `text_decoration` | `@style.TextDecoration::Underline` / `None` |
| | `white_space` | `@style.WhiteSpace::Normal` / `NoWrap` |
| 尺寸 | `width` `height` `min_width` `min_height` `max_width` `max_height` | `Double`，0/未设 = 按内容 |
| | `width_percent` `height_percent` | `Double` |
| 边距 | `padding` + `padding_left/right/top/bottom` | `Double` |
| | `margin` + `margin_left/right/top/bottom` | `Double` |
| 边框 | `border_width` `border_color` `border_radius` `border_style` | `Double` / `String` / `Double` / `BorderStyle`（`Solid`/`Dashed`/`Dotted`，虚线周期随 border_width） |
| 布局 | `display` | `@yoga.Flex` / `@yoga.Display::None` |
| | `flex_direction` | `@yoga.Row` `RowReverse` `Column` `ColumnReverse` |
| | `flex_wrap` | `@yoga.NoWrap` `Wrap` `WrapReverse` |
| | `justify_content` | `@yoga.FlexStart` `FlexEnd` `Center` `SpaceBetween` `SpaceAround` `SpaceEvenly` |
| | `align_items` `align_self` | `@yoga.Stretch` `FlexStart` `FlexEnd` `Center` `Baseline` |
| | `flex` | `Double`（= grow） |
| 间距 | `gap` `row_gap` `column_gap` | `Double`，`gap` 同时铺两轴 |
| 定位 | `position` `top` `right` `bottom` `left` `z_index` | `@yoga.Relative` / `Absolute`，`Double`，`Int` |
| 表现 | `opacity` | `Double` 0..1，整层透明度。**没有 box_shadow** |
| | `transition_ms` | `Double`，毫秒，状态桶切换的过渡时长 |
| | `visibility` | `@style.Visibility::Visible` / `Hidden`（`Hidden` 仍占位） |
| | `cursor` | `Int`，取 `@widget.CURSOR_DEFAULT` `CURSOR_HAND` `CURSOR_TEXT` `CURSOR_RESIZE_H` `CURSOR_RESIZE_V` `CURSOR_HIDDEN` |
| 状态桶 | `hover` `active` `focus` | 收整块 `Style` |

状态桶有两种写法，等价：

```moonbit
// 一：现场开桶
@style.style(background_color="bg_panel").hover(background_color="fill_hover")
// 二：收整块
@style.style(hover=@style.style(background_color="fill_hover"))
```

链式方法 `.hover(...)` / `.active(...)` / `.focus(...)` 只收绘制期属性（尺寸与布局参数混进去会让「画的时候」和「量的时候」对不上），所以悬停放大一档用 `opacity` / 底色，不要用 `scale` 类思路。

## 具名类：一组取值复用一个名字

同一套皮肤在多处出现时，注册成类，别复制粘贴散参数：

```moonbit
@style.define_class("card", @style.style(
  background_color="bg_panel", border_width=1.0,
  border_color="border", border_radius=6.0, padding=12.0))

// 用法一：构造期传 class（实测可编译）
@ui.card([@ui.text("内容")], title="概览", class=[@style.style(border_radius=6.0)])
// 用法二：按名字挂到已有控件
@style.apply_named(w, ["card"])
```

`class=` 参数的优先级高于同节点的散参数（散参数先铺，`class` 在后覆写）。深色/浅色变体走 `@style.resolve_with_variant(names, dark)`。

## 容器与组件的默认值

这些是库里已有的默认值，**不写就是基准形态**，写覆盖要有理由：

| 构造 | 关键参数与默认 |
|---|---|
| `@ui.view(children, ...)` | `direction=@yoga.Column`、`row_gap=0.0`、`column_gap=0.0`、`padding=0.0`、`grow=0.0`（1.0 撑满）、`align_items=@yoga.Stretch`、`justify_content=@yoga.FlexStart` |
| `@ui.col(children, row_gap, padding, ...)` | 纵向便捷形态，`align_items` 默认 `Stretch` |
| `@ui.row(children, column_gap, padding, ...)` | 横向便捷形态，`align_items` 默认 **`Center`** |
| `@ui.panel(title, children, ...)` | `padding=10.0`、`row_gap=6.0`、底 `bg_panel` + `border` 描边 |
| `@ui.card(children, title, ...)` | `padding=12.0`、`row_gap=6.0`，标题走 14 + `SemiBold` + `text_primary` |
| `@ui.text(content, ...)` | `font_size=13.0`、`role=@ui.Plain`。给了 `role` 后：字号与字重由角色决定（显式 `font_size` / `weight` 被覆盖），颜色默认取角色 token（显式 `color` 优先） |
| `@ui.button(text, ...)` | `variant=@ui.Soft`、`font_size=13.0`、`icon_size=14.0`（图标槽 = `icon_size + 6.0`）、`min_width=0.0` |
| `@ui.divider(...)` | 分隔线，颜色默认取 `border`（`color=` 可覆盖） |
| `@ui.glass(children, ...)` | 玻璃面板：`padding=12.0`、半径固定 6、`blur_on? : () -> Bool = fn() { true }`（绘制期取值）；绘制顺序必须在背景内容之后 |

按钮五个变体按「这一层要多强」选，不要凭手感：`Solid`（页面唯一主操作）、`Soft`（默认，次级操作）、`Border`（成组的次要操作、工具栏）、`Text`（最低权重，行内操作）、`Danger`（破坏性）。

`@ui.row` 的 `align_items` 默认是 `Center`，而 `@ui.view` / `col` 是 `Stretch`——混用时行内子项撑不满高度通常是这个原因。

`class` 可用性不一，改皮肤前先确认：

| 构造 | 收 `class` | 默认圆角 |
|---|---|---|
| `@ui.view` / `col` / `row` | 收 | 无（直角） |
| `@ui.card` | 收 | 无（直角）→ 要 6 必须显式给 |
| `@ui.panel` | 收（旧版本会报 `no parameter with label class~`，升级或改用 `view`） | 无（直角）→ 要 6 必须显式给 |
| `@ui.dialog` | 收 | 按需显式给 8 |

```moonbit
// 卡片 / 面板圆角 6：实测可编译
@ui.card([@ui.text("内容")], title="概览", class=[@style.style(border_radius=6.0)])
@ui.panel("筛选", [@ui.text("内容")], padding=10.0, class=[@style.style(border_radius=6.0)])
```

圆角几何是**真正的圆弧**，与 CSS / WinUI / GTK 同一定义，另带 1px 抗锯齿。角点像素常是低覆盖率（RGB 仍偏底色、alpha 很低），判断是否圆角要按 alpha 看覆盖率，不要按色相看；截图对比时也别把角点的淡色当成"没裁掉"。

## 入口

```moonbit
fn main {
  let app = match @ui.mount_window(
    [@ui.card([@ui.text("Hello", role=@ui.Body)], title="示例")],
    title="示例窗口",
    width=480,
    height=320,
  ) {
    None => return // 无窗口后端或无显示服务
    Some(a) => a
  }
  app.run()
}
```

`mount_window` 收 `Array[@widget.Node]`。要随状态刷新的节点用对应的 `*_dyn` 入口配 `Store` / `Signal`：现有 `@ui.text_dyn`、`@ui.tag_dyn`、`@ui.badge_count_dyn`、`@ui.avatar_dyn`、`@ui.statistic_dyn`（**没有 `button_dyn`**），不要自己抓控件重绘。

## 实测过的写法（可直接照抄的片段）

下面每一条都在 `NoahLiu/native-gui@0.2.0` 上 `moon check --target native` 通过：

```moonbit
// 角色走体系，字号字重颜色都不手写
@ui.text("季度报告", role=@ui.Title)
@ui.text("最后更新 3 天前", role=@ui.Secondary)

// 卡片 + 面板：库默认内边距就是基准档
@ui.card([@ui.text("内容")], title="概览", padding=12.0)
@ui.panel("筛选", [@ui.text("内容")], padding=10.0, row_gap=6.0)

// 行：列间距 4，两端内边距 6（工具栏形态）；align_items 默认已是 Center
@ui.row([@ui.button("新建", variant=@ui.Solid), @ui.button("导出", variant=@ui.Border)],
        column_gap=4.0, padding=6.0)

// 视图容器：横向、两轴间距、撑满剩余空间
@ui.view([@ui.text("a"), @ui.text("b")],
         direction=@yoga.Row, row_gap=6.0, column_gap=6.0, grow=1.0,
         align_items=@yoga.AlignItems::Center,
         justify_content=@yoga.JustifyContent::SpaceBetween)

// 状态桶 + 指针形状 + 过渡（底色交给 variant，只补 hover 与光标）
@ui.button("保存",
           variant=@ui.Solid,
           class=[@style.style(
             border_radius=4.0,
             cursor=@widget.CURSOR_HAND,
             transition_ms=120.0,
             hover=@style.style(background_color="primary_hover"))])

// 具名类复用一组取值
let _ = @style.define_class("card", @style.style(
  background_color="bg_panel", border_width=1.0,
  border_color="border", border_radius=6.0, padding=12.0))
let s = @style.resolve_named(["card"])
```
