# 终端控件与单文件 DX 后续编码计划

2026-11-06 排定，执行台账。对应 roadmap「代码栈（编辑器与终端）」与「开发体验」两节；动工前按 AGENTS.md 把条目补进 TODO，完成后从 TODO 删除并同步 roadmap / 测试文档。

## 0. 现状与缺口

### 终端

- `gui/` 目前没有任何 `terminal` / `pty` 代码；`proposals/code-stack.md` 定案「控件先行，PTY 另立项」。
- 可复用地基已齐：`gui/text`（等宽度量、`draw_text_at`、字体权重/斜体）、`gui/render.Painter`、`gui/widget`（`on_draw` / `on_key` / `on_scroll` / 焦点 / `invalidate`）、`gui/theme`、`gui/style`、`gui/ui` 的 code_view / code_editor 几何、选区与剪贴板先例。
- `@sys.procrun` 只有管道进程，**没有 PTY**；本批不碰。

### 单文件 DX

已落地：`mng` 的 `build` / `gen` / `map-errors` / `ir` / `dev` / `new` / `lsp` / `init` / `--version`；mngkit 的插值、动态属性、事件、`v-model`、`v-if` 链、`v-show`、组件/props/默认 slot、样式章；dev 的 HOT/COLD、IR 握手、项目级 `mng.toml` 与 `mng dev`；VSIX 的着色、补全、hover、跳转、语义着色。

本批要补的编码缺口：

1. **`v-for` 生成器**：语法已解析（`html.mbt` 的 `For` / `Key`），但 `gen.mbt` 两处仍报「v-for 生成器 v1 收口未开放」，而 roadmap 的 v1 指令集把 keyed 列表算在内——属未完成承诺。
2. **项目级 `mng build`**：现状 `build` 只收「单文件 + `-o`」；没有按 `mng.toml` 一次生成全工程生产形态的入口。
3. **`mng dev` 的 watch 面**：只盯启动时那批 `.mng` 与主题文件；运行中新增/删除 `.mng`、改 `.mbt` / `moon.pkg` / `moon.mod` 都不触发构建。
4. **生成物新鲜度口径**：CI 只按 dev 形态重编译比对（`.github/workflows/ci.yml` 的 `mng gen`），与「`mng build` 产生产形态」的规划冲突——提交生产形态会必红。
5. **用户文档与示例**：`docs/` 没有 `.mng` 工作流；VSIX README 仍写「v1 没有真实类型 hover」但代码已落；`experience/design.md` 仍写「没有模板语言」；没有 v-for 展示页与最小单文件示例。

## 1. 终端控件 `terminal`

### 1.1 范围

**本批做**：网格模型 + ANSI CSI/SGR 子集 + 等宽绘制 + 光标 + 纵向滚动与回看 + 键盘输入回调 + 选区复制 + 主题配色 + 演示页 + 文档 + 无头测试。

**本批不做**：PTY（forkpty/openpty/ConPTY）、shell 会话、多标签/复用器、Sixel/Kitty 图像协议、鼠标上报、OSC 8 可点击超链、a11y 语义桥（无障碍线容后）、本地行编辑（输入只回调 `on_input`，回显由应用决定）。

### 1.2 公开 API 草案

```moonbit
/// 终端色：默认前景/背景、ANSI 索引（0..255）、真彩色。
pub(all) enum TermColor {
  Default
  Indexed(Int)
  Rgb(Int, Int, Int)
}

/// 终端配色：默认前景/背景、光标、选区、16 色 ANSI 盘（0-7 常规，8-15 亮色）。
pub(all) struct TermTheme {
  fg : String
  bg : String
  cursor : String
  selection : String
  ansi : Array[String]
}

pub fn term_theme_of(t : @theme.Theme) -> TermTheme
pub fn term_theme_current() -> TermTheme

/// 终端模型：网格 + 解析器状态 + 回看偏移；可无头使用（不进控件树也能 feed/断言）。
pub struct Terminal

pub fn Terminal::new(
  cols? : Int = 80,
  rows? : Int = 24,
  scrollback? : Int = 1000,
) -> Terminal

/// 喂一段文本（含 ANSI 转义）；跨调用保留解析器状态，半截 CSI/OSC 不会丢。
pub fn Terminal::feed(self : Terminal, text : String) -> Unit
/// 改网格尺寸：保留左上内容、光标钳进新范围；v1 不做重排（reflow）。
pub fn Terminal::resize(self : Terminal, cols : Int, rows : Int) -> Unit
/// 清当前屏（光标回左上，保留回看）；reset 清全部并复位解析器/属性。
pub fn Terminal::clear(self : Terminal) -> Unit
pub fn Terminal::reset(self : Terminal) -> Unit
/// 回看滚动：正数 = 往上看；0 不动；越界钳到回看区首尾。
pub fn Terminal::scroll_lines(self : Terminal, n : Int) -> Unit
pub fn Terminal::scroll_to_bottom(self : Terminal) -> Unit
pub fn Terminal::cursor(self : Terminal) -> (Int, Int)
pub fn Terminal::cols(self : Terminal) -> Int
pub fn Terminal::rows(self : Terminal) -> Int
pub fn Terminal::is_bottom(self : Terminal) -> Bool
/// 回看区 + 当前屏的纯文本（每行去尾随空白；测试/复制用）。
pub fn Terminal::text(self : Terminal) -> String

/// 终端控件：尺寸跟随布局（on_draw 里按控件矩形重算 cols/rows 并 resize）。
pub fn terminal(
  term : Terminal,
  font_size? : Double = 13.0,
  focus_id? : Int = 0,
  /// 光标闪烁开关；缺省内部 530ms 自重排（`@shell.set_timeout`，退订随回收袋）。
  blink? : Bool = true,
  /// 应用接管光标可见性时给谓词；给了就完全按它画，不走内部 blink。
  cursor_on? : (() -> Bool)? = None,
  /// 键盘输入：可打印字符、控制键、方向键、IME commit 都从这里出去；不本地回显。
  on_input? : (String) -> Unit = fn(_s : String) -> Unit { () },
  selectable? : Bool = true,
  theme? : TermTheme,
  class? : Array[@style.Style] = [],
  handle? : (@widget.Widget) -> Unit = default_handle,
) -> @widget.Node
```

模型内部持有 `rev : Store[Int]`：`feed` / `resize` / `clear` / `scroll_*` 都 bump；控件在 `node_of_new` 里订阅它并 `@widget.invalidate()`，退订走 `@base.sub_bag_register`。这样同一模型可被多个控件观察，也不要求调用方记得手动重绘。

### 1.3 文件落点

- `gui/ui/terminal.mbt`：`TermColor` / `TermTheme` / `Terminal` 模型与公开 API。
- `gui/ui/terminal_ansi.mbt`：解析器状态机、CSI/SGR/OSC 清洗、输入键映射（纯函数）。
- `gui/ui/terminal_draw.mbt`：控件构造、绘制、滚动条、光标、选区命中。
- `gui/ui/terminal_wbtest.mbt`：白盒用例（同包可读私有网格）。
- 演示：`examples/showcase/pages/code.mbt` 末尾加「终端」段（不新增路由页，避免测试文档整页重编号）；`examples/showcase/shared/i18n_data.mbt` 补词条。
- 文档：`docs/zh/components/basics.md` + `docs/components/basics.md`（组件用法；DX 另见 §2.4）。

### 1.4 网格模型

- 屏幕 = `rows × cols` 的 `Array[Array[TermCell]]`；回看区 = 定长 ring buffer（容量 `scrollback`），满时覆盖最旧一行。
- `TermCell`：`text : String`（组合字符拼在前一格）、`wide : Bool`（宽字符首格）、`cont : Bool`（宽字符续格）、`fg/bg : TermColor`、`attrs : Int`（bold/dim/italic/underline/inverse/strike 位）。
- 光标：`x/y`、`saved_x/saved_y`、`pending_wrap`、`visible`、`scroll_top/scroll_bottom`（1 基或 0 基统一在实现里钉死）、`autowrap`。
- 字符宽度：复用 mdview 的宽字符判据（CJK/全角/假名/谚文等）抽成 `term_char_width(ch) -> Int`（0/1/2）；组合记号（U+0300–U+036F 等）返回 0 并 append 到前一格。宽字符占两格，第二格是 `cont`；覆盖宽字符任一格时两格一起清。
- 回看：`view_offset` 是「距底部行数」；`scroll_lines` 钳到 `0..scrollback_len`；`is_bottom` 即 offset=0。用户滚上去后新输出不强行拉回底部；`scroll_to_bottom` 复位。
- `resize`：保留左上内容，截断右侧/底部；光标与滚动区钳进新范围；不重排（长行不重新折行），文档写明边界。
- `text()`：回看 + 屏幕按行拼接，去尾随空白、保留空行。

### 1.5 ANSI 解析器

状态机：`Ground / Esc / Csi / Osc / Dcs(含 Pm/Apc)`，状态与参数缓冲跨 `feed` 保留。

- C0：`\n` 下移（滚屏区内滚）、`\r` 回行首、`\b` 左移、`\t` 到下一个 8 列制表位、`\x07` 忽略。
- ESC：`[` 进 CSI、`]` 进 OSC、`P/^/_` 进忽略态（吃到 ST）、`7/8` 存/取光标、`D` 下移、`M` 上移（反向下滚）、`E` 下一行、`c` 全复位。
- CSI：参数按 `;` / `:` 切，认 `?` 私有前缀；final byte `@ A B C D E F G H J K L M P S T X d f h l m r s u` 子集：
  - 光标移动/定位：CUU/CUD/CUF/CUB/CNL/CPL/CHA/VPA/CUP/HVP；
  - 擦除：ED（0/1/2/3）、EL（0/1/2）、ECH；
  - 插入/删除：ICH/DCH/IL/DL；
  - 滚动：SU/SD、DECSTBM（`r`）；
  - 模式：`?25` 光标显隐、`?7` 自动折行；其余模式静默忽略；
  - SGR：0 复位、1 粗、2 暗、3 斜、4 下划线、7 反显、9 删除线、22/23/24/27/29 复位；30–37/39、40–47/49、90–97/100–107；`38;5;n` / `48;5;n` / `38;2;r;g;b` / `48;2;r;g;b`。
- OSC：整段吃到 BEL 或 `ESC \` 后丢弃（标题、剪贴板、超链一律不消费）；DCS/PM/APC 同样丢弃。这是安全口径，测试必须钉住「OSC 52 不会写剪贴板、OSC 0 不会改窗口标题」。
- 自动折行：最后一列打印后置 `pending_wrap`，下一次打印先换行；`\r`/`\n` 清 `pending_wrap`。
- 未闭合的 CSI/OSC 在 `feed` 边界保留，直到下一次补齐或 `reset`。
- `feed` 收 `String`：调用方保证一次喂进来的是完整 UTF-8；PTY 批次再补 `feed_bytes` 的跨块 UTF-8 解码（本批不做）。

### 1.6 绘制与主题

- 字体：`@text.Font::new("Monospace", font_size, weight=Bold/...)`；`cell_w = text_width("M", font)`，`cell_h = max(14, line_height_font + 2)`；宽字符按 `2 * cell_w` 占位。
- 控件尺寸跟随布局：`on_draw` 用 `r.w/r.h` 算可容纳的 `cols/rows`，变了就 `term.resize`；内容区左上留 4px 内边距。
- 绘制顺序：底 → 逐行背景（非默认 bg 的 run 合并）→ 选区底色 → 文本 run（同 fg/attr 连续格合并成一次 `draw_at`）→ 光标 → 右侧滚动条；只画可视行。
- 光标：实心块（反显当前格），`cursor_on()` 为假时不画；失焦也画但不闪。宽字符光标占两格。内部缺省闪烁 530ms 自重排，`@base.sub_bag_register` 退订，`w.is_painted()` 为假时停表。
- 主题：`term_theme_of(theme)` 按 `bg_panel` 亮度选深/浅两套 16 色 ANSI 盘；`Indexed 16..231` 走 6×6×6 立方（0/95/135/175/215/255），`232..255` 走灰度；`Rgb` 直通；`Default` 取 `fg/bg`。ANSI 色是直接色值，不映射 `CodeTheme` 语义角色。
- 滚动条：右缘 8px；有回看内容才画；滑块位置/高度按 `view_offset` 现算；点击/拖动滚动条可选做，v1 至少支持滚轮与 Shift+PageUp/Down。
- 选区：按格坐标线性选（锚点 → 当前，跨回看区）；`selectable=false` 关闭。复制文本按行拼接，宽字符续格不产出字符，行尾去尾随空白。
- 复制/粘贴键：mac `Cmd+C` / `Cmd+V`，其他平台 `Ctrl+Shift+C` / `Ctrl+Shift+V`；**裸 `Ctrl+C` 必须作为 `\x03` 交给 `on_input`**（终端语义，不能吞成复制）。粘贴走 `@sys.clipboard_get_text()` 后 `on_input`。

### 1.7 键盘输入

- 纯函数 `terminal_input_of(ev : @widget.KeyEvent, mac : Bool) -> String?`，可无头测试：
  - Enter `\r`、Backspace `\x7f`、Tab `\t`、Esc `\x1b`；
  - Ctrl+字母 → `0x01..0x1a`；Ctrl+Space `\x00`；Ctrl+[ `\x1b`、Ctrl+\ `\x1c`、Ctrl+] `\x1d`、Ctrl+^ `\x1e`、Ctrl+_ `\x1f`；
  - 方向键 `ESC [ A/B/C/D`、Home/End `ESC [ H/F`、Delete `ESC [ 3 ~`、Insert `ESC [ 2 ~`、PageUp/Down `ESC [ 5 ~ / 6 ~`；
  - Alt/Meta 修饰前缀 `ESC`（mac 的 Cmd 留给复制/粘贴，不进输入）；
  - 可打印 keysym 按 Unicode 码点转字符；IME 走 `w.on_commit` 直接 `on_input`。
- `on_key` 返回是否消费：方向键/控制键消费并发 `on_input`；Shift+PageUp/Down 只滚动回看、不发给应用；复制/粘贴组合消费。
- `focus_id` 走 `auto_focus_id`；点击控件请求焦点；`w.role = "terminal"`，`w.name` 可留给应用。

### 1.8 测试与验收

`gui/ui/terminal_wbtest.mbt` 至少覆盖：

1. SGR：16/256/truecolor、默认色、粗/斜/下划线/反显复位；
2. 光标移动、CUP、保存/恢复、显隐、边界钳制；
3. 擦除 ED/EL/ECH、插入删除 ICH/DCH/IL/DL、滚动区 DECSTBM/SU/SD；
4. 自动折行 + `pending_wrap`、`\r` 覆盖同行、`\t` 制表位；
5. 宽字符/组合字符占格与覆盖清理、CJK 对齐；
6. 回看 ring buffer 容量、滚上后新输出不拽回底部、`text()` 去尾空白；
7. OSC/DCS 丢弃：标题/剪贴板不产生副作用；
8. 半截 CSI/OSC 跨 `feed` 续上；
9. `terminal_input_of` 的 Ctrl/方向键/Alt/IME 映射；
10. 控件绘制冒烟：挂 400×200、喂内容、`paint` 到 Bitmap 不 panic，且非背景像素 > 0；`blink=false` 避免测试定时器。

门禁：`cd gui && moon check`（零错误零警告）+ `moon test ui ...` 全绿。

### 1.9 演示与文档

- `pages/code.mbt` 末尾加「终端」段：
  - 80×14 终端，喂 16 色标题行、256 色/truecolor 行、CJK 对齐行、超长折行、`\r` 进度行；
  - 按钮：`喂一行`（计数 + 颜色轮换）、`长输出`（100 行，验回看）、`清屏`；
  - 键盘：聚焦后打字/方向键 → `on_input` 回显到旁边 `Store[String]` 的状态行；Enter 把输入行喂回终端（本批无 PTY 的替代演示）。
- `docs/zh/components/basics.md` + `docs/components/basics.md` 加 `terminal` / `Terminal` / `TermTheme` 条目与最小示例；`docs/zh/components/index.md` + `docs/components/index.md` 表格加行。
- `测试文档/测试用例.md` 在 2.7「代码文档」加 `SC-6.5 终端控件`（ANSI 色、CJK、折行、回看、选区复制、输入回显、清屏、深浅主题可辨）。
- 真机清单交用户：showcase → 代码文档 → 终端段；滚轮/Shift+PageUp、拖选 Cmd+C、裸 Ctrl+C 不清选区、OSC 注入不改标题/剪贴板。

## 2. 单文件 DX

### 2.1 `v-for` 代码生成

**落点**：`tools/native-gui-tools/mngkit/`。

1. `source.mbt`：
   - `SlotKind` 加 `KList`；`kind_of_ty` 先判 `ListStore[` 再判 `Store[`（否则 `ListStore` 被误判成 KStore，`rewrite_value` 会给它补 `.get()`）。
   - `rewrite_value`：KList 不补 `.get()`（`items.length()` 之类方法调用保持原样）。
   - `sources_of`：KList 不算字符串响应源（但列表数据变化由 `for_list` 自己订阅）。
2. `script.mbt`：`elem_ty_of` 识别 `ListStore[T]` 的元素类型；`slot_tys` 保留 `T` 供 dev/诊断。
3. `gen.mbt`：
   - `gen_blocks` 识别 `For`：解析 `v-for="alias in source"`（可选 `(alias, index) in source`）；源必须是**裸标识符**且槽类型为 `KList`，否则报错并提示「v-for 源须为 @base.ListStore，例如 `let rows : @base.ListStore[@base.Item] = ...`」。
   - 生成（有 `:key`）：
     ```moonbit
     @ui.for_list(rows, fn(r, _i) {
       ...
     }, key=fn(r) { r.id })
     ```
     无 `:key` 用 `@ui.for_list_indexed(rows, fn(r, _i) { ... })`。
   - 行节点生成时剥掉 `For` / `Key` 属性；`alias` 是作用域内局部名，`rewrite_value` / `sources_of` 不把它当槽；行内仍可引用 script 里的 Store（照常补 `.get()`）。
   - 边界（报错不猜）：嵌套 v-for、同一元素 `v-for` + `v-if`、`:key` 不在 v-for 元素上、源不是 ListStore、别名重复。
   - `index` 别名未出现时用 `_i`，避免零警告门禁。
4. `devregs.mbt`：遍历到 `For` 节点时**跳过整棵行子树**（行模板不在 HOT 范围，注册了也是 `fn() { r.name }` 这种作用域外闭包，编不过）。
5. `gen.mbt` 的 `hot_ir`：新模板含 `v-for` 直接回 `Err("v-for 行模板不在热更范围——回 COLD 重启")`；`dev.mbt` 已有 `[HOT→COLD]` 日志，不改成「补丁失败」。
6. LSP/VSIX（P2，可后置）：`semantic.mbt` 把别名当变量档；`lsp_expr_completion` 在 v-for 标签内把别名加入补全；VSIX snippets 加 `v-for` 模板、README 的「v1 收口」改为已支持 + 边界。

**测试**：`mngkit_wbtest.mbt` 新增：

- 有 key、无 key、带 index 三种生成码逐字断言；
- 源不是 ListStore / 嵌套 / v-for+v-if 的报错文本；
- `dev` 形态生成码里行子树表达式不进注册表；
- `hot_ir` 对含 v-for 的模板回 `Err`。

**展示**：新增 `examples/showcase/pages/vfor_demo.mng`（用 `@base.ListStore[@base.Item]`），在 `pages/code.mbt` 加「模板 v-for」段调用生成函数；配增删按钮验证 keyed 行复用。生成码提交；CI 新鲜度对账覆盖它。测试文档加 `SC-6.6 模板 v-for`。

### 2.2 项目级 `mng build`

**落点**：`tools/native-gui-tools/mng/main.mbt`、`project.mbt`。

- `mng build` 无位置参数且无 `-o` → 项目模式：
  - 复用 `load_dev_conf` / `scan_templates` / `collision_msg`（`mng.toml` 向上找；没有就按 `moon.mod` / `moon.work` 推默认）；
  - 逐个 `mng_compile`（生产形态）写回模板同包的 `<stem>.gen.mbt`；source map 落 `.mng/map/<相对路径>/<stem>.gen.mbt.map`；
  - 打印每个文件 OK 与总数；任一失败非零退出；
  - 保留现有 `mng build <input.mng> -o <out.mbt>` 单文件形态不变。
- **生成物形态口径**：`mng dev` 写 dev 形态、`mng build` 写生产形态，两者共用同一个 `<stem>.gen.mbt`，会互相覆盖——文档写明「提交前选一种并保持一致；开发用 dev，发布用 build」。
- **CI 新鲜度**：`.github/workflows/ci.yml` 的模板对账改为「dev 形态与生产形态各生成一份，提交物匹配任一即通过」；否则提交生产形态必红（现存冲突）。
- **测试**：`project_wbtest.mbt` 测无参解析、模板扫描、撞名；`mng` 集成用例在临时目录跑项目 build 两次（幂等、生成函数名正确）；不真跑 GUI。

### 2.3 `mng dev` watch 覆盖面

**落点**：`tools/native-gui-tools/mng/dev.mbt`。

- 每个 poll 拍重扫 `.mng` 列表（尊重 `--watch` 过滤）：
  - 新增：dev 编译 + 写 `<stem>.gen.mbt` + 记 baseline/seen，并触发一次 COLD build/重启；
  - 删除：从列表移除并打印陈旧生成码路径；若 `<stem>.gen.mbt` 以生成头开头则安全删除，否则只警告（绝不删用户文件）。
- 新增源文件监听（项目根 `conf.dir` 下递归）：`*.mbt`（排除 `*.gen.mbt`）、`moon.pkg`、`moon.pkg.json`、`moon.mod`、`moon.work`；内容变 → 一次 COLD build/重启。跳过 `_build` / `.mooncakes` / `.mng` / `target` / `.git`。
  - **不能**监听 `*.gen.mbt`：dev 自己每拍写它，会形成构建自激。
  - `mng.toml` 变更：打印「配置变了，请重启 mng dev」，本批不热加载配置。
- 把「扫描/差分」抽成纯函数（文件列表 → 新增/删除/变更），`dev_wbtest.mbt` 钉住；循环本身交用户真机。
- 验收：`mng dev` 跑着时新建一个 `.mng` 应自动生成并重启；改 `main.mbt` 的路由应重启；删除 `.mng` 应只报陈旧生成码而不崩。

### 2.4 文档、示例与口径校正

- `docs/zh/guide/dev-experience.md` + `docs/guide/dev-experience.md` 新增「单文件组件（.mng）」一章：装 `mng`、`mng init`、`mng new`、`mng dev`、`mng build`、生成码与路由接线、HOT/COLD 边界表、编辑器 VSIX 安装、常见错误（v-for 源、ListStore、mng.toml、生成码覆盖）。
- 最小示例（P2，可后置）：`examples/template-hello/`（`moon.mod` + `mng.toml` + `pages/hello.mng` + `main.mbt`），注册进 `moon.work`；`mng build` 产出生产生成码，`moon run .` 起窗。文档用它做「五分钟单文件」。
- `tools/vscode-mng/README.md`：删「v1 没有真实类型 hover」，补 v-for 支持与边界、snippets 更新。
- `proposals/native-template.md`：`v-for`「v1 收口」改为已支持；工具后续批次状态补「项目级 build / dev watch 覆盖」。
- `experience/design.md` §4「没有模板语言」加一句边界：「模板预编译是作者侧工具，运行时仍是本文的 render 形态」。
- `docs/zh/reference/roadmap.md`：终端条目移「已实现」并按平台标状态；DX 三条（v-for / 项目 build / dev watch）从「已规划」移「已实现」。
- `TODO.md`：动工时建条目，完成一项删一项；`测试文档/测试用例.md` 补 SC 条与附录 D 工具用例数。

## 3. 不做什么（本批）

- 终端 PTY 与 shell 会话（另立项；控件只留 `on_input` 缝）。
- 终端多标签、会话快照、鼠标上报、Sixel/Kitty 图像、可点击 OSC 8。
- v-for 的嵌套、行内结构热更、`v-for` + `v-if` 同元素（v1 明确报错）。
- 自定义组件 / children 形组件的 IR 热更、`v-else-if` 热更（仍 COLD，roadmap 已记边界）。
- 运行时级联/选择器、原生 HTML/CSS 语义补全（原有边界不变）。

## 4. 执行顺序与提交切分

一项一提交、推送后再做下一项；同一项内先 `moon check` 零警告再提交。

1. **落位**：把 §1 / §2 条目补进 roadmap「已规划」与 TODO；本文档入库（可与第 1 个功能同批）。
2. **终端·网格模型**：`terminal.mbt` + 宽字符/回看/resize + 用例（§1.4）。
3. **终端·ANSI**：`terminal_ansi.mbt` + 解析器用例（§1.5）。
4. **终端·绘制/主题/滚动**：`terminal_draw.mbt` + `TermTheme` + 光标/滚动条/选区绘制 + 冒烟（§1.6）。
5. **终端·输入/复制**：键映射 + IME + 选区复制/粘贴 + 用例（§1.7）。
6. **终端·演示/文档/测试用例**：showcase 段 + 中英文档 + SC-6.5 + 真机清单（§1.9）。
7. **SFC·v-for**：mngkit 生成 + dev COLD 边界 + 用例 + vfor_demo + SC-6.6（§2.1）。
8. **SFC·项目级 build**：`mng build` 无参 + CI 双形态对账 + 用例（§2.2）。
9. **SFC·dev watch**：新/删 `.mng` + `.mbt`/`moon.pkg`/`moon.mod` 监听 + 纯函数用例（§2.3）。
10. **SFC·文档/示例/校正**：guide 中英文、最小示例、VSIX/README/design/roadmap 同步（§2.4）。
11. **收口**：全门禁复跑；roadmap 状态、TODO 删除、测试文档计数；给用户真机清单。

依赖：2→3→4→5→6 串行；7 独立；8→9→10；7 与 8 可在 2-6 之后并行。

## 5. 门禁与真机清单

**助手本地必过**：

```sh
cd gui && moon check
cd gui && moon test ui render text theme icons sys input win dbus wayland chart mdview style base shell widget router
cd examples/showcase && moon check
cd tools/native-gui-tools && moon check
cd tools/native-gui-tools && moon test ./mngkit ./mng ./proc ./inst
cd examples/showcase/shared && moon test .
```

`mng dev` 起 GUI 不在助手本地跑（AGENTS.md：真机 GUI 测试由用户执行）；项目级 `mng build`、单文件 `mng gen`、临时目录集成用例可本地跑。

**交用户真机**：

- 终端：showcase → 代码文档 → 终端段，按 SC-6.5 走（16/256/truecolor、CJK、折行、回看、拖选复制、裸 Ctrl+C、OSC 注入、深浅主题）。
- v-for：代码文档页「模板 v-for」增删行，keyed 行复用、无残影；`mng dev` 下改行模板应 `[HOT→COLD]` 重启而不是补丁失败。
- 项目 build / dev watch：按 §2.2 / §2.3 验收步骤；VSIX 按 `tools/vscode-mng/README.md` 清单。

## 6. 规划检查

**与既有约束的冲突（已在计划内消解）**：

1. `v-for` 的「v1 收口」与 roadmap v1 指令集含 keyed 列表冲突 → §2.1 实现并同步所有文档口径。
2. `mng build` 生产形态与 CI 只比 dev 形态冲突 → §2.2 改为双形态任一匹配。
3. VSIX README「v1 没有真实类型 hover」与已落代码冲突 → §2.4 校正。
4. `experience/design.md`「没有模板语言」与 `.mng` 现状冲突 → §2.4 加作者侧工具边界一句话。
5. 终端提案「纵横滚动」与 v1 只做纵向回看：横向在自动折行下无内容可滚，v1 明确不做，写进边界（§1.1 / 文档）。

**遗漏检查**：

- 终端：主题两套盘、宽字符、半截转义、OSC 安全、复制键歧义（Ctrl+C）、测试定时器、演示不新增路由页——均已列。
- SFC：v-for 作用域改写、devregs 作用域外闭包、hot_ir COLD、ListStore 误判 KStore、生成码形态覆盖、CI 双形态、watch 自激、删除生成码安全——均已列。
- 台账：roadmap / TODO / 测试文档 / 中英文文档 / VSIX README / design.md 已列。
- 门禁：库测试清单、工具测试清单、showcase check、无 GUI 本地冒烟边界已列。

**结论**：计划与现有架构（运行时零新机制、PTY 另立项、v1 热更边界、真机测试归用户）不冲突；可按 §4 执行。
