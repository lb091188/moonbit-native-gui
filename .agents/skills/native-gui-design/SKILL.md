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
2. **文字用字阶预设，不手写字号**：`@ui.text(..., class=[@style.text_heading])` 之类挂 `@style` 字阶预设（`text_heading` 18 / `text_title` 14 / `text_secondary` 12 / `text_accent` 13 主色；正文 13 是缺省档不挂）。预设自带字号、字重与颜色 token，主题切换跟随；手写的 `font_size=` 会脱离体系。只有预设覆盖不掉时才写显式值。（原 `role=@ui.*` / `TextRole` 已退役。）
3. **圆角小且分层级**：控件沿用库默认 `4`；卡片 `6`、面板 `6`、对话框与浮层 `8`，都要**显式给**（`card` / `panel` 默认是直角，靠 `class=[@style.style(border_radius=6.0)]`）。若某个构造报 `no parameter with label class~`，说明库版本早于该参数加入，先升级；升不了就用 `@ui.view` 自搭同形态。`border_radius` 不超过 8。
4. **层次靠描边和底色分层，不靠投影**：`Style` 不提供 `box_shadow`。层级顺序是 `bg_page`（页面底）→ `bg_panel`（面板/卡片底）→ `border`（1px 描边）→ 强调色。整层明暗用 `opacity=`。模糊只有一种用法：`@ui.glass` 把它下方已画的内容糊掉（固定一档），不进默认基准、不做窗口背后毛玻璃。
5. **颜色一律写 token，不写死十六进制**：`background_color="bg_panel"`、`color="text_secondary"`。十六进制与 CSS 命名色只在自定义主题里出现，界面代码里出现就是暗色模式失效的隐患。20 个 token 见 `references/mapping.md`。

常见界面模式照 `references/recipes.md` 的配方拼：工具栏、表单、卡片网格、列表、空状态、整页骨架。不要在已有界面上另发明一套排法。

## 风格包

用户点名风格、或产品气质明确时，从 `references/styles/` 取整套风格落地，不要自行混搭别家 CSS 风格指南（本库无投影、圆角上限 8、token 走主题——web 风格值不能直译）：

| 风格 | 文件 | 气质一句话 |
|---|---|---|
| 简约 Minimal | `styles/minimal.md` | 大留白中性色，信息即主角 |
| 工业 Industrial | `styles/industrial.md` | 直角粗描边，仪器面板感 |
| 中国风 Chinoiserie | `styles/chinoiserie.md` | 宣纸墨字朱砂点睛，疏可走马 |
| 玻璃拟态 Glass | `styles/glass.md` | 深底磨砂浮层，`@ui.glass` 一等能力 |
| 暗夜科技 Dark Tech | `styles/dark-tech.md` | 近黑荧光青，控制台气质 |
| 编辑杂志风 Editorial | `styles/editorial.md` | 纸白衬线大字阶，版面感 |

每个风格包四件套：**主题 JSON**（存 `theme.json`，`mng.toml` 配 `theme` 键，存盘即热重载；颜色 token 与 `space_scale` / `radius_scale` / `type_scale` / `duration_scale` 四刻度都是主题白名单字段）+ **布局密度口径**（间距档倾向、描边用法）+ **字体候选族**（CSS 族列表语义，`serif` / `sans-serif` / `monospace` 通用族恒可用，全缺回落系统默认）+ **该风格的反模式清单**。基准刻度与 token 语义见 `references/baseline.md`，风格包只换值不改语义。

## 去模板化（别长成 AI 默认脸）

风格选对只是第一步，落法还要躲开生成式界面的默认套路：

- **风格从题材来，不从习惯来**：给儿童玩具做界面与给金融分析做仪表盘，该长得完全不同。先问产品是什么、给谁用、第一屏要传达什么，再取风格包。
- **大胆只花一处**：让一个元素成为记忆点（一块大字阶标题区、一个荧光强调色、一枚朱砂印章），其余全部安静克制；处处强调等于没有强调。
- **结构装置要有信息**：编号（01/02/03）只用于内容真是步骤或时间线时；眉标、分隔线、图标存在的前提是传达信息，不是装饰。
- **动效一次说清**：非用户触发的动效只留一个编排时刻（进场一次、reveal 一次）；hover/active 这类回答操作的反馈是本分，不算特效。
- **文案也是设计**：按钮写「保存更改」不写「提交」；同一动作全流程同名；错误信息说怎么修，不道歉不含糊。
- **截图自审**：交付前用检查器截图自己看一遍（工作流见 native-gui-dev 技能），看不出记忆点就还没做完。

## 交付前自查

- 所有 `padding` / `row_gap` / `column_gap` 的值都在刻度内。
- 没有出现 `border_radius` 大于 8。
- 文本节点没有手写 `font_size=`（数字型强调与自定义标题除外），其余挂 `class` 字阶预设。
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
- `@ui.view` / `col` / `row` 里尺寸给 `0` 表示按内容取尺寸，撑满剩余空间用 `grow=1.0`，不是 `height="100%"`；三者的 `align_items` 都缺省 `Stretch`——列里子项撑满容器宽、行里子项撑满行高，要居中显式传 `Center`；窗根是竖排容器，页面顶层元素缺省撑满窗宽。
- 用到布局的包要在 `moon.pkg` 写 `supported_targets = "native"`，不写报警告；引了不用的包同样报 `unused_package`。
- 观感不按平台分叉：库不提供按平台改样式的路径，三端同一套值。界面里出现的平台判断只该是能力探测（有没有托盘、有没有显示服务），不是给某个平台换一套圆角或配色。
