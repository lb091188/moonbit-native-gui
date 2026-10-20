# 文本排版方案：RTL 与竖排/古汉语

## 一、目标
两类排版能力:
- **RTL(从右渲染)**:阿拉伯语/希伯来语,以及"整窗从右"的镜像布局。
- **竖排/古汉语**:字从上到下、列从右到左(竖排 CJK / 古籍版式)。

## 二、现状(代码核实)
文本经三后端:Linux=Pango+Cairo(`gui/text/stub.c`)、Windows=DirectWrite(`gui/text/dwrite_text.cpp`)、macOS=CoreText(`gui/text/stub.c` CT 分支)。MoonBit 侧入口 `gui/text/text.mbt`(`measure`/`draw_*`,`align/valign : TextAlign`)。

现在只有盒内对齐(左/中/右),**无基方向、无 writing-mode**:`stub.c` 仅 `pango_layout_set_alignment`;`dwrite_text.cpp` 仅 `SetTextAlignment(LEADING/CENTER/TRAILING)`。

## 三、可行性(逐后端)

### RTL
| 后端 | 原生支持 | 落地成本 |
|---|---|---|
| DWrite | ✅ `SetReadingDirection(RIGHT_TO_LEFT)` + `SetFlowDirection` | 低——现只用了 SetTextAlignment,补两调用 |
| Pango | ◐ `pango_layout_set_alignment` 右对齐;基方向靠内容 bidi,非 RTL 文本需手动注入 U+202B/U+202D 段落控制符 | 中 |
| CoreText | ◐ RTL 靠 attributed-string 段落方向属性,手工 | 中 |
| 布局镜像(整窗从右) | yoga `FlexDirection::RowReverse` + 对齐翻转 | 与文本方向**分离**,在 `style/apply.mbt` 侧 |

### 竖排 / 古汉语(列右到左)
| 后端 | 原生支持 | 落地成本 |
|---|---|---|
| DWrite | ✅ `SetFlowDirection(BOTTOM_TO_TOP)`(竖排 CJK) | 中 |
| CoreText | ◐ CTFrame/竖排字形属性 | 中高(手工) |
| Pango | ❌ 无原生竖排 | **高**:逐字 `cairo_rotate` + 手工分列,shaping 会碎;Linux 主线是硬缺口 |

**结论:RTL 三后端都能做到不同程度(以对齐 + DWrite 基方向最稳);竖排只有 Windows 便宜,macOS 手工,Linux(Pango)几乎要从零自研逐字排版。**

## 四、API 设计(贯穿,默认零回归)
```
// gui/text/text.mbt
pub(all) enum TextDirection { LTR  RTL }
pub(all) enum WritingMode   { Horizontal  VerticalRTL /* 竖排,列右到左 */ }

// 在 measure/draw 入口加 dir/writing(默认 LTR/Horizontal = 现行为)
pub fn draw_in_box(..., align?, valign?, dir?=LTR, writing?=Horizontal)
```
后端映射:
- `dir=RTL`:DWrite `SetReadingDirection(RTL)`;Pango 注入段落方向 + 右对齐;CT 段落方向属性。
- `writing=VerticalRTL`:DWrite `SetFlowDirection(BOTTOM_TO_TOP)`;CT 竖排;Pango **v1 明确报"该后端不支持竖排"并退化为横排右对齐**(不假装支持)。
- 布局镜像另做:`style` 增 `direction`,`apply.mbt` 对 row/justify/align 在 RTL 时翻转(独立于文本)。

## 五、分期(按可行性排序)
- **P1 RTL(可无头验证部分)**:API 线程 + DWrite `SetReadingDirection/FlowDirection`(原生、稳)+ Pango 段落方向注入 + 对齐。measure 宽度对 RTL 串可在 wbtest 断言"与 LTR 同内容宽度一致"。视觉基线归真机。
- **P2 布局镜像**:style `direction` + `apply.mbt` row-reverse/align 翻转;wbtest 可断言盒坐标镜像(无头)。
- **P3 竖排/古汉语**:DWrite + CoreText 分支;Linux(Pango)需自研逐字排版——**建议单列,可能推到 icon 独立文件那批一起下月做**,且必须真机逐平台验。

## 六、验证边界(AGENTS 规则 6)
- 无头可测:API 默认零回归、RTL 串的 measure 宽度一致性、布局镜像坐标(纯函数/盒账)。
- **必须真机视觉**:任何 C 后端的实际 shaping/基线/竖排字形——由用户跑,我给复验清单(如 "阿语段落右起、括号镜像"、"竖排 CJK 列序右到左、Linux 退化提示")。
- C 后端改动属地基,错误会让全框架文本崩——不盲改、分步、每步留 LTR/Horizontal 默认兜底。

## 七、风险
- Pango 竖排无原生:要么接受 Linux 不支持(诚实降级),要么自研逐字排版(大工程、shaping 质量风险)。
- 混排(竖排里嵌拉丁字母旋转 90°)三后端口径各异,先不支持。
- RTL 数字/括号 bidi 依赖引擎,内容驱动,Pango 注入控制符需谨慎避免影响 measure 缓存键。
