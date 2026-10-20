# 文本排版方案：RTL

## 一、目标
RTL(从右渲染):阿拉伯语/希伯来语等,以及整窗从右的镜像布局。分两层:
- **布局镜像**:UI 主轴反向、起终对齐翻转。
- **文本 run 基方向**:段落内文字(bidi 顺序、混排括号)真正右起。

## 二、现状(代码核实)
文本经三后端:Linux=Pango+Cairo(`gui/text/stub.c`)、Windows=DirectWrite(`gui/text/dwrite_text.cpp`)、macOS=CoreText(`gui/text/stub.c` CT 分支)。MoonBit 入口 `gui/text/text.mbt`(`measure`/`draw_*`,`align/valign : TextAlign`)。此前只有盒内对齐(左/中/右),无基方向、无方向标志:`stub.c` 仅 `pango_layout_set_alignment`;`dwrite_text.cpp` 仅 `SetTextAlignment(LEADING/CENTER/TRAILING)`。

## 三、可行性(逐后端,仅 RTL)
| 后端 | 原生支持 | 成本 |
|---|---|---|
| DWrite | ✅ `SetReadingDirection(RIGHT_TO_LEFT)` | 低——现只用了 SetTextAlignment,补一调用 |
| Pango | ✅ 真·RTL 文本靠内容 bidi 天然正确;强制拉丁段落右起需注入段落方向 | 低-中 |
| CoreText | ◐ attributed-string 段落方向属性 | 中 |
| 布局镜像(整窗从右) | yoga `FlexDirection::RowReverse` + 起终对齐翻转 | 低,纯 MoonBit |

## 四、已落:布局镜像层(纯 MoonBit、可无头验证、零回归)
- `gui/style` 加 `Direction{Ltr,Rtl}` + `Style.direction` 字段(None/Ltr 逐字同现状)。
- `apply.mbt` 在 `Rtl` 时:`flex_direction` row↔rowReverse(列不动)、`justify_content`/`align_items`/`align_self` 的 `FlexStart↔FlexEnd`。
- 镜像纯函数 `mirror_flex/mirror_justify/mirror_align` + `style_rtl_wbtest.mbt` 单测。
- 验证:`gui check` 干净、style 35/35。

## 五、待做(T17):文本 run 基方向(C 后端)
把 `dir : TextDirection` 贯穿 `gui/text` 的 measure/draw/cache(三者口径必须一致,否则量画分叉),后端各自接原生基方向(DWrite `SetReadingDirection`、Pango 段落方向、CoreText 段落属性)。
- **性质**:改文本地基 + 只能真机逐平台回视觉(AGENTS 规则 6),故与镜像层分列、不盲进。
- 默认 LTR 保证零回归;先接 DWrite(原生最干净),再 Pango、CoreText。

## 六、验证边界
- 无头可测:布局镜像映射(纯函数)、默认 LTR 零回归、RTL 段 measure 宽度一致性。
- 必须真机视觉:文本 run 的实际基方向/括号镜像/基线——由用户跑,给复验清单。
