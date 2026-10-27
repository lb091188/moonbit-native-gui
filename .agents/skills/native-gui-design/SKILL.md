---
name: native-gui-design
description: Design rules for building user interfaces with NoahLiu/native-gui (MoonBit cross-platform desktop GUI). Use when creating or restyling any native-gui screen, window, widget tree, theme, layout, or example app, and when the result looks plain or inconsistent. Applies to projects whose moon.mod imports NoahLiu/native-gui. Gives a single compact aesthetic baseline shared by Windows, Linux and macOS, the numbers to use, and how they map onto the library's Style and builder parameters.
---

# native-gui 界面设计

三端同一套观感，不写平台方言。取值一律落在 `@style` 与 `@ui` 的真实参数上，不引入库外的概念。

## 动手前

1. 看项目里已有的界面文件，新界面沿用同一套容器与角色，不要另起风格。
2. 需要接口真相时读工程内 `.mooncakes/NoahLiu/native-gui/`：各包源码与 `pkg.generated.mbti` 就是当前版本的权威面。目录要跑过一次 `moon check` 才会生成。不要凭 CSS / web 的常识猜参数。
3. 判据先行：界面写完能说出「哪里按 8 的档、哪一层用哪个 token」，说不出就是没照表。

## 五条硬规则

1. **间距只从刻度取值**：`2 / 4 / 6 / 8 / 12 / 16 / 24`。不用 5、7、10、15、13 这类档位外的数——一次一档对齐，整套界面才齐。见 `references/baseline.md`。
2. **文字用角色，不手写字号**：`@ui.text(..., role=@ui.Title)` 之类走 `TextRole`。角色自带字号、字重与颜色 token，主题切换跟随；手写的 `font_size=` 会脱离体系。只有角色覆盖不掉时才写显式值。
3. **圆角小且分层级**：控件沿用库默认 `4`；卡片 `6`、面板 `6`、对话框与浮层 `8`，都要**显式给**（`card` / `panel` 默认是直角，靠 `class=[@style.style(border_radius=6.0)]`）。若某个构造报 `no parameter with label class~`，说明库版本早于该参数加入，先升级；升不了就用 `@ui.view` 自搭同形态。`border_radius` 不超过 8。
4. **层次靠描边和底色分层，不靠投影**：`Style` 不提供 `box_shadow`。层级顺序是 `bg_page`（页面底）→ `bg_panel`（面板/卡片底）→ `border`（1px 描边）→ 强调色。整层明暗用 `opacity=`。模糊只有一种用法：`@ui.glass` 把它下方已画的内容糊掉（固定一档），不进默认基准、不做窗口背后毛玻璃。
5. **颜色一律写 token，不写死十六进制**：`background_color="bg_panel"`、`color="text_secondary"`。十六进制与 CSS 命名色只在自定义主题里出现，界面代码里出现就是暗色模式失效的隐患。20 个 token 见 `references/mapping.md`。

常见界面模式照 `references/recipes.md` 的配方拼：工具栏、表单、卡片网格、列表、空状态、整页骨架。不要在已有界面上另发明一套排法。

## 交付前自查

- 所有 `padding` / `row_gap` / `column_gap` 的值都在刻度内。
- 没有出现 `border_radius` 大于 8。
- 文本节点没有手写 `font_size=`（数字型强调与自定义标题除外），其余走 `role`。
- 颜色字符串全是 token；没写死 `#` 值或 CSS 色名。
- 一个界面里主色（`primary`）只用在主操作、选中项、焦点环上；正文与结构用 `text_primary` / `text_regular` / `text_secondary`，底用 `bg_page` / `bg_panel`。
- 可点的东西有 `hover` / `active` 反馈，输入类有 `focus`；用 `Style::hover(...)` 之类的状态桶，不是自己另画一层。

## 布局纪律（防空白带 / 防塌陷 / 防裁切）

1. **确定高度要层层给**：`grow=1.0` 只在祖先链高度确定的前提下有得可分。内容自带滚动时，外层再套一个纵向 `scroll_view` 会掐断链条（滚动容器的内容高 = 自然高），带 `grow` 的子项直接塌成 0。外层只需要横滚时用 `scroll_view(hscroll=true, vscroll=false)`（内容高钉视口）；库版本没有 `vscroll` 参数时，外层干脆别包纵滚。
2. **折行容器别包「自身无宽的列」**：只想加外边距就直接给容器 `class=[@style.style(margin=16.0)]`，不要套一层不设宽的 padding 列——旧库版本里这层会把折行子项的纵向下限按「无约束全堆叠」顶起来（段条下凭空多一大片空白，实测 236 vs 真值 66）。确需包裹列时给它 `width_percent=100.0`。
3. **别用 `min_height=0` 躲折行撑高**：下限归零会同时把容器钉死在一行高，真折到第二行就被裁。正确参照是「定住的宽」：自身显式宽，或父列有确定内宽时被拉伸（见第 2 条）。
4. **min-width 两档**：`scroll_view` 横滚默认是自然宽档 `max(子项自然宽, 视口)`；想要「至少这么宽，窄了可滚、宽了跟随」给 `min_content_width=`（下限档不看子项自然宽）。用错档时内容自然宽会静默顶掉你设的值。

## 已知陷阱（web 直觉会写错的地方）

- **布局枚举不在 `@style` 里**：`Display` / `FlexDirection` / `JustifyContent` / `AlignItems` / `FlexWrap` / `PositionType` 的类型名有再导出，枚举构造子没有。写 `@yoga.Row` 要在自己的 `moon.mod` 与 `moon.pkg` 各引一次 `NoahLiu/yoga-mbt`（包路径 `src`），否则 `[4020] Package "yoga" not found`。
- `line_height` 是**行盒高的像素数**，不是 1.4 那种倍数；且只在单行文本生效，折行时被忽略。
- 文本对齐只有 `@text.Start` / `Center` / `End`，没有 `Left` / `Right` / `Justify`。
- 现取 token 颜色用 `@style.theme_token_value(name)`，不在 `@theme` 包里。
- `padding=` 是四边简写，`padding_top=` 等逐边参数写在它**之后**才覆写；`gap=` 同时铺 `row_gap` 与 `column_gap`，逐轴参数同样在后。
- `@ui.view` / `col` / `row` 里尺寸给 `0` 表示按内容取尺寸，撑满剩余空间用 `grow=1.0`，不是 `height="100%"`；`@ui.row` 的 `align_items` 默认是 `Center`，而 `view` / `col` 是 `Stretch`。
- 用到布局的包要在 `moon.pkg` 写 `supported_targets = "native"`，不写报警告；引了不用的包同样报 `unused_package`。
- 观感不按平台分叉：库不提供按平台改样式的路径，三端同一套值。界面里出现的平台判断只该是能力探测（有没有托盘、有没有显示服务），不是给某个平台换一套圆角或配色。
