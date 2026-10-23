# 样式系统 CSS 属性完善与跨平台统一方案

## 〇、代码核实的关键事实（先纠偏）

`gui/style/` 单一 `Style` 结构体（`style.mbt:5-69`），字段全 `Option`，合并=非 None 覆盖。
对照三后端实况后，纠正几处易误判的点：

1. **图形后端其实是 2 个，不是 3 个。**
   Linux=Cairo；**Windows 和 macOS 共用同一套 Pure Raster**（`painter.mbt:1-24`）。
   DirectWrite / CoreText / Pango 只是**文本**引擎。所以"图形属性跨平台统一"= 让 Cairo + Raster 两条实现都接上，工作量按 2 算。

2. **box-shadow / blur 不提供，别天真重提。**
   重做的前置是「有真 Gaussian blur」（`design.md` §1.1「效果」行）。两后端都无卷积模糊（stub.c 无 `cairo_push_group`/filter，raster 无 convolution）。

3. **`letter_spacing` 是死字段：存了、能合并、状态桶也接受，但从未被画。**
   `gui/ui/` `gui/text/` 全无消费者（无 kern/tracking/letter_spacing）。roadmap.md:159 标 ❌❌❌。

4. **gradient 渲染层已完备，但 Style 层没字段。**
   `Gradient` 线性+径向（`render/gradient.mbt`）、`Painter::set_fill_gradient/stroke_gradient`（`painter.mbt:549`）在 **Cairo 与 Raster 双后端均已测试**（`painter_wbtest.mbt:243`、`blend_wbtest.mbt:117`）。缺的只是把它接到 `Style`。

5. **文档矛盾需修**：roadmap.md:162 仍写"全局 alpha 与**硬阴影** ✅/✅/🚧"，但硬阴影已删——roadmap 与代码互相矛盾，应先对齐。

## 一、当前属性覆盖盘点

| CSS 组 | 已有 | 缺失 |
|---|---|---|
| 颜色 | `color` / `background_color`（含 `#RRGGBBAA` alpha） | 渐变字段（渲染层有，Style 无） |
| 字体 | `font_size/family/weight/text_align/line_height/white_space` | `letter_spacing`（死字段）、多行 line-height（仅单行覆盖 `base.mbt:204`） |
| 装饰 | `text_decoration`（仅 Underline，自绘线 `base.mbt:250`） | line-through / overline（可同法自绘） |
| 盒模型 | width/height/min/max（含 %）、padding/margin **四边独立** | — |
| 边框 | `border_width`/`border_color`/`border_radius`（**均四边/四角同值**） | 每边独立宽/色、每角独立半径、`border-style`（dashed） |
| 布局 | display/flex_direction/wrap/justify/align/self/gap/position/z_index | — |
| 效果 | `opacity`（两路：全局 alpha `alpha_paint` + 色 alpha） | box-shadow、backdrop-blur、mix-blend-mode（渲染层有 BlendMode，Style 无字段） |
| 过渡 | `transition_ms`（`transition.mbt`，不插值 opacity，macOS 🚧） | — |
| 状态 | `hover`/`active`/`focus` 嵌套桶 | — |

应用路径 `apply.mbt:36-194` 三分：布局→Yoga；opacity/visibility/cursor→Widget 宿主字段；其余→进程级 side table `resolved_table`（paint 期读 `style_for`）。

## 二、可跨平台统一的简单 CSS 属性：按成本分层

### Tier A — 纯 MoonBit，双后端图元已存在（最该先做，零 C）

| 属性 | 后端就绪 | 落地要点 |
|---|---|---|
| **background-gradient**（线性/径向+stops） | ✅ 双后端已测 | 加 Style 字段+factory kwargs+merge/setter；box 绘制处把 `set_fill_color`→`set_fill_gradient`（照 `basic.mbt:83-94` 型：83 填色 / 85 `fill_round_rect` / 94 `round_rect_path`+stroke）。注意半透明 stop 在 raster/cairo 的非预乘口径差（adaptation.md:57） |
| **每角 border-radius**（4 值） | ✅ 接近 | `trace_round_rect`（`painter.mbt:307`）四等弧推广到四半径，走 path 回退；仅 `Raster::fill_round_rect` 解析快路（`raster.mbt:264`）需加不等半径 guard 退回 path |
| **每边 border 宽/色** | ✅ 可行 | 用 `clip_rect`+`fill_rect` 叠四边条；难点只在"有半径时角部接缝" |
| **mix-blend-mode** | ✅ 25 个 BlendMode 双后端 | 加 Style 字段接 `Painter::set_blend_mode`（`painter.mbt:638`） |
| **overflow: hidden/clip** | ✅ `clip_rect` 双后端 + widget 已裁 | 语义化暴露即可 |
| **text-decoration line-through/overline** | ✅ 文本层无需求，ui 自绘同法 | 扩 `base.mbt:250` 自绘线，零 C |
| **spacing/radius/duration 设计令牌** | ✅ 纯 Style 层 | 见 §三，最大统一收益 |

### Tier B — 需新文本层 API（3 引擎各改一次 stub）
- **letter_spacing**：Pango `pango_attr_letter_spacing_new`、CoreText `kCTKernAttributeName`；**DirectWrite 无一等字距**，要做逐字形偏移。且必须同时穿透 `measure_font`/`line_ascent_font`/`draw_box_at`，否则量画不一致。**最贵**，design.md「Pango/DWrite 都有该能力」对 DWrite 偏乐观。
- **多行 line-height（真 leading）**：Pango line attr / `DWRITE_LINE_METRICS` / `kCTLineSpacingAttributeName`；中等，且与框增大触发的整窗重算（`transition.mbt:127`）相互作用。

### Tier C — 需新渲染能力（勿排便宜工期）
- **box-shadow**：要真 Gaussian blur，两后端皆无 → 已试过两次并撤回，重做须先建 blur 基建。
- **backdrop-blur**：目标读回+分组+模糊，比 box-shadow 更大。
- **border-style: dashed**：`cr_set_dash` 仅 Linux 分支真实现（stub.c:291）且**未绑定 MoonBit**，raster 无 dash → 要新写 raster 功，且 cap/join 先例（`painter.mbt:605` raster 处 no-op）正是这种"平台不对称"的教训，别重蹈。

## 三、设计令牌缺口（性价比最高的统一）

`theme` 目前只有 20 个颜色令牌（`theme.mbt:13`）+ 一个 `control_height=32.0`（`theme.mbt:339`）。
**没有间距阶 / 半径阶 / 字阶 / 时长阶**——所有长度都是散字面量。
`style/tokens.mbt` 是 ~80 个按组件的 Style 常量，**不是**设计令牌。

补：`space-scale`、`radius-scale`、`type-scale`、`duration-scale` 进 theme，`style(...)` factory 与 `tokens.mbt` 消费之。纯 Style 层，零后端，收益最大。

## 四、分期实施（按 Tier A 优先）

- [ ] **S0 修文档矛盾**：roadmap.md:162 硬阴影条目与代码对齐。
- [ ] **S1 设计令牌**：space/radius/type/duration scale 进 theme + factory 消费。
- [ ] **S2 background-gradient**：Style 字段 + 双后端接入 + 半透明 stop 口径钉测试。
- [ ] **S3 每角 radius + 每边 border**：扩 `trace_round_rect` 四半径 + raster 快路 guard；四边条合成 + 角接缝。
- [ ] **S4 mix-blend-mode / overflow / line-through**：语义暴露 + 自绘线扩展。
- [ ] **S5（选做，贵）letter_spacing**：三引擎 stub + measure/paint 一致性；先确认 DWrite 逐字形方案再排期。

> 每项按仓库约定：代码改动同批把「环境+现象+根因+修复+验证」回写 `proposals/adaptation.md`；交付面写进 `docs/zh/roadmap.md` 对应小节（平台列 ✅/🚧/❌/⏳）。真机视觉由用户验证。

## 五、风险 / 不对称陷阱
- **raster 快路 vs path 回退**：每角不等半径若漏 guard，raster 解析快路会画错（应退回 path）。
- **半透明渐变口径差**：raster stop 非预乘插值，与 Cairo 仅在半透明 stop 处有差（adaptation.md:57），要钉 golden 测试。
- **量画一致**：任何进文本度量的属性（letter-spacing/多行 line-height）必须同步 `resolved_for_measure`，否则布局盒与绘制不符 + 整窗重算。
- **勿引入平台不对称**：cap/join 在 raster 处 no-op 是反面教材；新属性优先两后端同时落。
- **性能**：Raster 圆角/描边/blit 慢路每次分配 per-row `cov` 数组（TODO.md:137）；扩每角半径会走更多 path，注意。
