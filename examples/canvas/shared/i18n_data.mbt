// 画板与富文本示例英文目录（内嵌,零文件 IO）。顶层键=中文标题原文（section()
// 出口取译）;描述键="desc§"+中文标题;正文键=中文原文(tx)。中文态不加载本目录
// 即回落中文;切英文时 i18n_load 本串。一条 TOML 规矩：段头 `[x]` 之后的裸键都
// 归进 `x.` 前缀，所以顶层键必须写在任何段头之前、`[meta] locale` 放最后。

pub const EN_CATALOG : String =
  // —— 段标题 ——
  "\"交互画板：Pointer × Keyboard\" = \"Interactive board: pointer × keyboard\"\n" +
  "\"Painter 自绘\" = \"Painter drawing\"\n" +
  "\"富文本 AttributedText\" = \"AttributedText\"\n" +
  "\"字体回退与混排行高\" = \"Font fallback & mixed line height\"\n" +
  "\"端点/拐角与 Path 对象直通\" = \"Line cap/join & Path object\"\n" +
  "\"set_dashes 图案与相位\" = \"set_dashes pattern and phase\"\n" +
  "\"圆角半径、抗锯齿与整层 alpha\" = \"Radii, anti-aliasing and whole-layer alpha\"\n" +
  "\"PNG / JPEG / GIF 首帧与缩放\" = \"PNG / JPEG / GIF first frame and scaling\"\n" +
  // —— desc§描述 ——
  "\"desc§交互画板：Pointer × Keyboard\" = \"One on_pointer callback handles all five pointer events: hold the left button to freehand-draw (Down starts, Move samples, Up/Leave ends); coordinates arrive already in local space. Keyboard: declaring focus_id puts the board in the Tab chain - arrow keys move the virtual cursor, Enter drops a dot, Shift+arrow draws a straight line (modifier bits from MOD_SHIFT). Strokes are plain data (point list + color + width); on_draw replays them and edits call invalidate() for a frame.\"\n" +
  "\"desc§Painter 自绘\" = \"fill_rect/arc/fill/stroke_rect/draw_text plus linear gradients, drawn at the widget's real size.\"\n" +
  "\"desc§富文本 AttributedText\" = \"Range fonts/colors, wrap & ellipsis toggles, and text rewriting that keeps attributes.\"\n" +
  "\"desc§字体回退与混排行高\" = \"The right box swaps a suffix to 28px; both boxes take mixed line-height. Missing families fall back via resolve_family.\"\n" +
  "\"desc§端点/拐角与 Path 对象直通\" = \"set_line_cap/join map straight to Cairo; draw_path replays a recorded path in one go.\"\n" +
  "\"desc§set_dashes 图案与相位\" = \"set_dashes(pattern, offset) takes alternating on/off segment lengths in logical pixels and a phase offset; an empty array goes back to a solid line. The three rows are [10, 6], the same pattern at offset 8, and a cleared pattern - the second row is shifted 8px with the same segment count. Dashes live in save/restore, so nested drawing does not leak. The pure raster backend only records state (the stroke still lands); Cairo is where the line really breaks.\"\n" +
  "\"desc§clip_rect / translate / rotate / scale\" = \"The left block clips to a 140x140 rect first, then paints circles and lines far past it - everything outside is cut flat at the boundary. The right block translates the origin, rotates 20 degrees and scales 1.6x, one rounded rect each. All three mutate the current transform, so they must be wrapped in save/restore or every later draw inherits them.\"\n" +
  "\"desc§圆角半径、抗锯齿与整层 alpha\" = \"The top row is three identical blocks with radii 0 / 8 / 24: corners are real arcs with 1px anti-aliasing, so no stair-stepping on the curve; turning the corner switch in the sidebar off falls back to square corners. The bottom row is set_global_alpha: the same circles drawn twice, the right pair at 35% - alpha multiplies at draw time rather than lightening a colour, so overlaps darken on their own.\"\n" +
  "\"desc§PNG / JPEG / GIF 首帧与缩放\" = \"Image::new_from_file decodes PNG / JPEG / GIF (animated GIFs give the first frame here; playback is on the transition page) and draw_image scales it into a target rect. The same PNG is drawn at 64 and 128, plus the center of a GIF first frame scaled up: scaling is bilinear and the aspect ratio follows the target rect.\"\n" +
  // —— seg. 段短名 ——
  "\"seg.画板\" = \"Board\"\n" +
  "\"seg.自绘\" = \"Draw\"\n" +
  "\"seg.富文本\" = \"Rich text\"\n" +
  "\"seg.字体\" = \"Fonts\"\n" +
  "\"seg.线型与路径\" = \"Lines & paths\"\n" +
  "\"seg.虚线\" = \"Dashes\"\n" +
  "\"seg.裁剪与变换\" = \"Clip & transform\"\n" +
  "\"seg.圆角与合成\" = \"Corners & alpha\"\n" +
  "\"seg.位图\" = \"Bitmaps\"\n" +
  // —— 页正文 tx 串 ——
  "\"清空画板\" = \"Clear\"\n" +
  "\"换色\" = \"Color\"\n" +
  "\"线宽\" = \"Width\"\n" +
  "\"笔画已清空\" = \"Strokes cleared\"\n" +
  "\"基准 Base 28\" = \"Base 28\"\n" +
  "\"旋转色相\" = \"Rotate hue\"\n" +
  "\"渐变开关\" = \"Gradient toggle\"\n" +
  "\"换行开关\" = \"Wrap toggle\"\n" +
  "\"省略号开关\" = \"Ellipsis toggle\"\n" +
  "\"改写文本\" = \"Rewrite text\"\n" +
  "\"文本已替换 ✓（范围属性保留）\" = \"Text replaced ✓ (range attributes kept)\"\n" +
  "\"系统深浅：深色\" = \"System appearance: dark\"\n" +
  "\"系统深浅：浅色\" = \"System appearance: light\"\n" +
  "\"系统主色：（无，回落内置）\" = \"System accent: (none, built-in fallback)\"\n" +
  "\"字距 0：MoonBit GUI 字距对照\" = \"Spacing 0: MoonBit GUI letter spacing\"\n" +
  "\"字距 4：MoonBit GUI 字距对照\" = \"Spacing 4: MoonBit GUI letter spacing\"\n" +
  "\"圆角 0 / 8 / 24（真圆弧 + 1px 抗锯齿）\" = \"Radii 0 / 8 / 24 (real arcs, 1px anti-aliasing)\"\n" +
  "\"右边两个：set_global_alpha(0.35)\" = \"Right pair: set_global_alpha(0.35)\"\n" +
  "\"PNG 64×64 / 128×128，GIF 首帧取中心 40×40 放大到 80\" = \"PNG 64×64 / 128×128; GIF first frame center 40×40 scaled to 80\"\n" +
  "\"缩放不糊边\" = \"Scaling stays clean\"\n" +
  "\"代码已复制 ✓\" = \"Code copied ✓\"\n" +
  "\"复制失败：剪贴板不可用\" = \"Copy failed: clipboard unavailable\"\n" +
  // —— dyn. 插值串 ——
  "\"dyn.fallback_family\" = \"Fallback family: {f} ({n} usable families)\"\n" +
  // —— 语言标签（段头之后的键带 `meta.` 前缀，故必须放最后）——
  "[meta]\nlocale = \"en\"\n"
