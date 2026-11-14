# 样式系统 CSS 属性完善与跨平台统一方案

## 〇、代码核实的关键事实，先纠偏

`gui/style/` 单一 `Style` 结构体，字段全 `Option`，合并=非 None 覆盖。
  - 取证：`style.mbt:5-69`。
对照三后端实况后，纠正几处易误判的点：

1. **图形后端其实是 2 个，不是 3 个。**
   Linux=Cairo；**Windows 和 macOS 共用同一套 Pure Raster**。
   DirectWrite / CoreText / Pango 只是**文本**引擎。所以"图形属性跨平台统一"= 让 Cairo + Raster 两条实现都接上，工作量按 2 算。
   - 取证：`painter.mbt:1-24`。
   - Cairo：Linux 常用的 2D 矢量绘图库，本库 Linux 腿的绘图后端。
   - Pure Raster：本仓自写的纯软件绘图器，Windows 与 macOS 共用。
   - DirectWrite：Windows 的文本渲染引擎，缩写 DWrite。
   - CoreText：macOS 的文本渲染引擎。
   - Pango：Linux GTK 侧的文本排版引擎。

2. **box-shadow / blur 不提供，别天真重提。**
   重做的前置是「有真 Gaussian blur」。两后端都无卷积模糊。
   - 依据：`design.md` §1.1「效果」行。
   - 取证：stub.c 无 `cairo_push_group`/filter，raster 无 convolution。
   - Gaussian blur：高斯模糊，按高斯分布加权平均像素的标准模糊算法。

3. **`letter_spacing` 是死字段：存了、能合并、状态桶也接受，但从未被画。**
   `gui/ui/` `gui/text/` 全无消费者。roadmap.md:159 标 ❌❌❌。
   - 补充：全仓无 kern/tracking/letter_spacing 代码。
   - kern：相邻两个字偶对之间的微调间距。
   - tracking / letter_spacing：整段文字的统一字间距。
   - 状态桶：样式系统按 hover/active/focus 等状态嵌套存放样式值的结构。

4. **gradient 渲染层已完备，但 Style 层没字段。**
   `Gradient` 线性+径向、`Painter::set_fill_gradient/stroke_gradient` 在 **Cairo 与 Raster 双后端均已测试**。缺的只是把它接到 `Style`。
   - 取证：`render/gradient.mbt`、`painter.mbt:549`。
   - 取证：`painter_wbtest.mbt:243`、`blend_wbtest.mbt:117`。

5. **文档矛盾需修**：roadmap.md:162 仍写"全局 alpha 与**硬阴影** ✅/✅/🚧"，但硬阴影已删——roadmap 与代码互相矛盾，应先对齐。

## 一、当前属性覆盖盘点

| CSS 组 | 已有 | 缺失 |
|---|---|---|
| 颜色 | `color` / `background_color`，含 `#RRGGBBAA` alpha | 渐变字段，渲染层有、Style 无 |
| 字体 | `font_size/family/weight/text_align/line_height/white_space` | `letter_spacing` 死字段、多行 line-height 仅单行覆盖 `base.mbt:204` |
| 装饰 | `text_decoration` 仅 Underline，自绘线见 `base.mbt:250` | line-through / overline，可同法自绘 |
| 盒模型 | width/height/min/max 含 %、padding/margin **四边独立** | — |
| 边框 | `border_width`/`border_color`/`border_radius`，**均四边/四角同值** | 每边独立宽/色、每角独立半径、`border-style` dashed 档 |
| 布局 | display/flex_direction/wrap/justify/align/self/gap/position/z_index | — |
| 效果 | `opacity` 两路，全局 alpha `alpha_paint` + 色 alpha | box-shadow、backdrop-blur、mix-blend-mode，渲染层有 BlendMode、Style 无字段 |
| 过渡 | `transition_ms`，模板面写 `transition-duration: 120ms`，实现见 `transition.mbt`，不插值 opacity，macOS 🚧 | — |
| 状态 | `hover`/`active`/`focus` 嵌套桶 | — |

应用路径 `apply.mbt:36-194` 三分：布局→Yoga；opacity/visibility/cursor→Widget 宿主字段；其余→进程级 side table `resolved_table`，paint 期读 `style_for`。
- Yoga：Meta 开源的 flexbox 布局引擎，本库布局计算的后端。
- side table：挂在主结构旁的辅助查值表，不改主结构本身。

## 二、可跨平台统一的简单 CSS 属性：按成本分层

### Tier A — 纯 MoonBit，双后端图元已存在·最该先做·零 C

| 属性 | 后端就绪 | 落地要点 |
|---|---|---|
| **background-gradient**，线性/径向+stops | ✅ 双后端已测 | 加 Style 字段+factory kwargs+merge/setter；box 绘制处把 `set_fill_color`→`set_fill_gradient`，照 `basic.mbt:83-94` 型：83 填色 / 85 `fill_round_rect` / 94 `round_rect_path`+stroke。注意半透明 stop 在 raster/cairo 的非预乘口径差，取证 `experience/adaptation/common.md`「与 cairo 的已知口径差」 |
| **每角 border-radius** 4 值 | ✅ 接近 | `trace_round_rect` 见 `painter.mbt:307`，四等弧推广到四半径，走 path 回退；仅 `Raster::fill_round_rect` 解析快路见 `raster.mbt:264`，需加不等半径 guard 退回 path |
| **每边 border 宽/色** | ✅ 可行 | 用 `clip_rect`+`fill_rect` 叠四边条；难点只在"有半径时角部接缝" |
| **mix-blend-mode** | ✅ 25 个 BlendMode 双后端 | 加 Style 字段接 `Painter::set_blend_mode`，见 `painter.mbt:638` |
| **overflow: hidden/clip** | ✅ `clip_rect` 双后端 + widget 已裁 | 语义化暴露即可 |
| **text-decoration line-through/overline** | ✅ 文本层无需求，ui 自绘同法 | 扩 `base.mbt:250` 自绘线，零 C |
| **spacing/radius/duration 设计令牌** | ✅ 纯 Style 层 | 见 §三，最大统一收益 |

- mix-blend-mode：CSS 的混合模式，让元素颜色与底下已画内容按指定公式混合。
- 预乘 alpha：把透明度预先乘进 RGB 分量的存色方式；两种口径混用，半透明色会算错。

### Tier C — 需新渲染能力·勿排便宜工期
- **box-shadow**：要真 Gaussian blur，两后端皆无 → 已试过两次并撤回，重做须先建 blur 基建。
  - box-shadow：CSS 的盒子投影效果，在元素边框外画一层带模糊的阴影。
- **backdrop-blur**：目标读回+分组+模糊，比 box-shadow 更大。
  - backdrop-blur：把元素背后已画好的内容读回来模糊后再垫底的效果。
- **border-style: dashed**：`cr_set_dash` 仅 Linux 分支真实现且**未绑定 MoonBit**，raster 无 dash → 要新写 raster 功，且 cap/join 先例正是这种"平台不对称"的教训，别重蹈。
  - 取证：stub.c:291。
  - 取证：`painter.mbt:605` raster 处 no-op。

## 三、设计令牌缺口·性价比最高的统一

`theme` 目前只有 20 个颜色令牌 + 一个 `control_height=32.0`。
**没有间距阶 / 半径阶 / 字阶 / 时长阶**——所有长度都是散字面量。
`style/tokens.mbt` 是 ~80 个按组件的 Style 常量，**不是**设计令牌。
  - 取证：`theme.mbt:13`、`theme.mbt:339`。
  - 设计令牌：把间距、圆角、字号、时长这类设计值集中命名成一套常量，全库统一取用。

补：`space-scale`、`radius-scale`、`type-scale`、`duration-scale` 进 theme，`style(...)` factory 与 `tokens.mbt` 消费之。纯 Style 层，零后端，收益最大。

## 四、分期实施·按 Tier A 优先

- [ ] **S0 修文档矛盾**：roadmap.md:162 硬阴影条目与代码对齐。
- [x] **S1 设计令牌**：四阶进 `Theme`，即 `space_scale`/`radius_scale`/`type_scale`/`duration_scale`，pub(all) 破坏记提交信息；加基准常量与静态间距令牌 `space_2..24`；加运行时 getter `theme_space/radius/type_size/duration`，越界首末夹取；`from_json` 白名单同步扩四字段；`tokens.mbt` 35 处刻度间距字面量换令牌单源，非刻度组件现状值保留并自注释。时长阶基准 80/120/200/320 为初值，库内 transition 无集中档，供样式与应用按档取用。
  - 状态：2026-11-02 落地。
- [x] **S2 background-gradient**：`GradientSpec` + `style(background_gradient=)` kwargs + merge/setter；`apply_gradient_bg` 落色助手，view 盒子渐变优先、不足两 stop 回落纯色。半透明 stop 双后端插值口径差已在 `experience/adaptation/common.md`「与 cairo 的已知口径差」记档，不透明 stop 主链 wbtest 像素钉死，半透明 golden 归 Windows/mac 批。
  - 状态：2026-11-02 落地。
  - `GradientSpec`：归一化几何 Linear/Radial + stops 复用 style `Color`，token 名绘制期现取。
  - view 盒子：view/col/row/panel/card 全走 `apply_gradient_bg`。
  - wbtest：MoonBit 的白盒测试，写在包内、能直接访问包内部状态的测试。
  - golden：golden 测试，把输出与事先存好的基准结果逐位比对的测试。
- [x] **S3 每角 radius + 每边 border**：`Painter::fill_round_rect4` / `round_rect4_path` + `trace_round_rect4`；raster 快路 guard = 四值全等走单半径解析快路、不等退路径，同像素回归钉快路同源。Style 12 字段 + factory kwargs + `corner_radii_of`/`side_borders_of`/`has_per_*` 解析助手；view 盒子接线——不等半径走 4R 填充/描边，per-side 在四角全 0 时逐边内缘条 fill_rect 不带线形，带圆角回落统一描边。
  - 状态：2026-11-02 落地。
  - `trace_round_rect4`：CSS over-constraint 归一，相邻角和超边长全体等比缩小。
  - Style 12 字段：per-corner radius ×4 / per-side width·color ×8。
  - 补充：角部接缝诚实降级，后续要真接缝再立项。
- [x] **S4 mix-blend-mode / overflow / 删除线**：`blend_mode`、`overflow`、`TextDecoration` 扩 `LineThrough`/`Overline`。
  - 状态：2026-11-02 落地。
  - `blend_mode`：25 式 BlendMode 进 Style → `Widget::blend_paint`，paint_at 对 on_draw+子树生效、restore 快照自动恢复。
  - `overflow`：Visible 档跳过控件矩形裁切=逃生口，Hidden 即现状默认。
  - `TextDecoration` 扩 `LineThrough`/`Overline`：与 underline 同一测量自绘线法，折行档落最后一行，零 C。
- [ ] **S5 letter_spacing·选做·贵**：三引擎 stub + measure/paint 一致性；先确认 DWrite 逐字形方案再排期。
  - stub：C 桩文件，MoonBit 外部函数调到平台 C API 的胶水层。

> 每项按仓库约定：代码改动同批把「环境+现象+根因+修复+验证」回写 `experience/adaptation/`；交付面写进 `docs/zh/roadmap.md` 对应小节。真机视觉由用户验证。
>
> - 补充：平台列用 ✅/🚧/❌/⏳。

## 五、风险 / 不对称陷阱
- **raster 快路 vs path 回退**：每角不等半径若漏 guard，raster 解析快路会画错，应退回 path。
- **半透明渐变口径差**：raster stop 非预乘插值，与 Cairo 仅在半透明 stop 处有差，要钉 golden 测试。
  - 取证：`experience/adaptation/common.md`「与 cairo 的已知口径差」。
- **量画一致**：任何进文本度量的属性，即 letter-spacing/多行 line-height，必须同步 `resolved_for_measure`，否则布局盒与绘制不符 + 整窗重算。
- **勿引入平台不对称**：cap/join 在 raster 处 no-op 是反面教材；新属性优先两后端同时落。
- **性能**：Raster 圆角/描边/blit 慢路每次分配 per-row `cov` 数组；扩每角半径会走更多 path，注意。
  - 取证：TODO.md:137。
