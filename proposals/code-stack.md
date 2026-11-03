# 代码栈：分词地基、代码编辑器与终端控件

「代码高亮（升级）」「代码编辑器」「终端控件」三件合一份规划：**三个消费者、一条公共地基**——等宽文本栈、着色流（分词 + 配色）、偏移映射（TextLayout）、编辑内核（Editor）。目标形态：库供积木（`code_editor`、`terminal` 控件），轻量级编辑器应用在库之上自建（示例或独立模块，不进 `gui/`）。

2026-11-03 立项。选型口径：分词层**自研带状态扫描器**、不引注册表依赖；终端**控件先行**、PTY 另立项。状态流转见 [roadmap.md](../docs/zh/roadmap.md)「代码栈」节，拆分待办动工时进 TODO。

## 定位

- **为什么合一份**：三件各自都要「等宽字体逐段着色 + 偏移映射 + 编辑内核」，分开做等于各修一遍地基；合起来地基只修一次，三件逐个拼装。
- **依赖链**（自底向上，编号即排期序）：

| 层 | 内容 | 状态 |
|---|---|---|
| ① 等宽文本栈 | `@text.Font` 度量（`text_width` / `line_height_font`）、`draw_box_at` 逐段绘制 | ✅ 已建成 |
| ② 着色流 | `tokenize_lang`（文本→Token 流）+ `CodeTheme`（主题派生配色） | ✅ 已建成，本批升级（跨行状态 + 增量 + 字节偏移） |
| ③ 偏移映射 | `TextLayout`（字符偏移↔屏幕几何） | 🚧 [text-selection-a11y.md](text-selection-a11y.md) 一期抽取中 |
| ④ 编辑内核 | `Editor`（caret/选区/撤销/剪贴板，UTF-8 字节下标） | ✅ 已建成（gui/input/editor.mbt） |

| 消费者 | 吃的地基 | 缺口 |
|---|---|---|
| `code_view`（代码块/高亮，已成） | ①+② | 无跨行状态、无增量、token 无字节偏移 |
| `code_editor`（代码编辑器） | ②升级版+③+④ | 未开工 |
| `terminal`（终端控件） | ①+网格模型（新）+ANSI 状态机（新）+④ 行编辑 | 未开工 |

## 现状盘点

- **分词**：`tokenize_lang` / `tokenize_moonbit`（gui/ui/codeview.mbt:197-392）——手写逐行扫描器，词级分类（9 语言关键字表大小写不敏感、大写开头=类型、`@` 限定名取尾段、后随 `(` =调用、字符串/数字/行注释）。**逐行独立分词、无跨行状态**：块注释 `/* */`、多行字符串、heredoc 劈不准。
- **组件**：`code_view`（gui/ui/codeview.mbt:407）——构造期一次分词+测宽成预排版表（codeview.mbt:429-454），on_draw 按 `CodeTheme` 现取色；静态内容重绘零分词开销，但**编辑态每敲一键都要整体重建**，无「只重排受影响行」的增量模型；自带横向滚动视口。mdview 围栏/缩进/数学代码块全部复用（gui/mdview/markdown.mbt:586-591）。
- **编辑内核**：`@input.Editor`（gui/input/editor.mbt）——caret/选区/撤销重做/剪贴板，坐标一律 UTF-8 字节下标、caret 落码点边界；只挂在 entry/textarea，没有高亮消费方。
- **偏移映射**：`TextLayout` 待 [text-selection-a11y.md](text-selection-a11y.md) 一期从 textarea 抽出（落 gui/input，与 Editor 同包）。
- **终端**：未开工（roadmap 原「终端模拟」⏳）。`sys/procrun` 只有管道进程 spawn/wait/signal/kill，**没有 PTY**。

## 定案一：分词层——自研带跨行状态的行级增量扫描器

### 要补什么

- **跨行状态机**：每行携带「行首状态」（是否在块注释 / 多行字符串 / heredoc 中），开闭记号按语言参数表（沿用现有关键字表同处扩展）；逐行扫描时状态顺着行传播，块注释、多行字符串从此劈得准。
- **行级增量**：每行缓存 `(行首状态, tokens)`；编辑发生后从变更行向上复用最近一个未变行的行首状态，向下重扫，重扫到某行的行首状态与缓存一致即提前停（状态收敛）——典型编辑只碰几行，重扫就此打住。
- **token 带 UTF-8 字节偏移**：现预排版表只有 token 级 x/宽（codeview.mbt:429-454），补字节区间列——code_view 选中（text-selection-a11y 一期首批）与编辑器复制都吃这一列；与 Editor/TextLayout 的字节下标口径贯穿。
- **兼容**：`code_view` 静态路径零回归——构造期一次预排版、重绘零分词的现状保留（静态内容最优），增量模型是新入口供编辑器消费；静态调用方（mdview、showcase）无感。

### 不引什么（moon search 社区备选留档，2026-11-03 实搜）

| 包 | 是什么 | 不进 gui 的理由 |
|---|---|---|
| bobzhang/pygments@0.2.5 | Pygments 全移植：带状态 lexer、`guess_lexer`、多语言、styles/formatters（HTML/终端/Pango 等） | 整篇重排模型非增量；多语言广覆盖本仓用不上（自研表已盖常用语言）；留作未来增强备选 |
| moonbitlang/parser@0.4.7 + lexer@0.4.4 | 官方 MoonBit 解析器（AST 级，纯 MoonBit 无 FFI） | 语义级着色归 tools/lsp 与 VSIX 线（roadmap「编辑器支持」），库内只做词法 |
| tonyfettes/tree-sitter@0.1.1 + tree_sitter_moonbit | tree-sitter 绑定 + MoonBit 语法（编辑器级增量解析事实标准） | C 运行时 + 每语言 C 语法，重 FFI，与「MoonBit 全栈原生自绘」定位冲突；真要做走 `modules/` 子模块另立项 |
| bobzhang/lexer@0.3.1 | 手写词法器基元库（位置追踪/Unicode） | 现扫描器已自成一体且量小（约 200 行核心），引依赖换不来等量收益 |
| mizchi/tui-terminal-buffer@0.1.4 | 终端字符缓冲基元（CharBuffer/cell/宽度量） | 方向相反（往终端画，非解析 pty 输出）；cell 网格模型思路可参考，不引依赖 |
| SongYZZZ/ansi-guard@0.1.0 | ANSI 转义清洗/审计（安全向） | 终端控件期参考其危险序列清单（OSC 8 超链、剪贴板写、标题改写），实现自置 |

## 定案二：代码编辑器控件 `code_editor`（落 gui/ui）

- **组成**：扫描器（增量着色）+ `Editor` 内核（编辑操作）+ `TextLayout`（命中/选区）三积木拼装；等宽字体、行号列沿用 code_view 管线。
- **与 textarea 分工**：textarea=纯文本编辑（比例字体、无高亮）；code_editor=等宽+高亮+行号的编辑件；两者共用 `TextLayout` 与 `Editor`，不各造一套选区/命中。
- **前置**：text-selection-a11y 一期落地（`TextLayout` 抽取 + code_view 选中先行验证字节偏移列）。
- **批次**：
  - P1：编辑 / 光标 / 选区 / 高亮 / 行号 / 撤销重做（`Editor` 已有 undo/redo，直接吃）；
  - P2：查找、自动缩进、括号匹配、当前行高亮。
- **性能口径**：万行级文件构造期预排版若不可接受（见未核项），code_editor 走纯增量路径不预排版——首屏只排可视行附近，滚动现排。

## 定案三：终端控件 `terminal`——控件先行，PTY 另立项

- **范围**：等宽网格 cell（字符 + 前景/背景 + 属性）+ ANSI CSI/SGR 子集（SGR 着色 / 光标移动 / 清屏 / 滚动区）+ 光标（实心块/竖线、闪烁）+ 纵横滚动；**喂文本即可用**——日志面板、REPL 输出、构建输出着色，不需要进程就能消费。
- **配色口径**：ANSI 16/256 色是**直接色值**，不走 `CodeTheme` 语义角色（角色是语义映射，ANSI 是设备色表，两回事）；缺省前景/背景取主题，深浅基底各校一档可辨性。
- **共用**：等宽字体度量、逐段绘制、横滚视口与 code_view 同管线；网格模型自研（cell 缓冲 + 脏行标记），参考社区 CharBuffer 思路不引依赖。
- **安全口径**：不可信输出先清洗高危序列（参考 ansi-guard 清单：OSC 8 超链、剪贴板写、窗口标题改写），控件期不消费。
- **PTY 不在本批**：`sys` 层 forkpty/openpty + Windows ConPTY 是独立平台工程（新 FFI、三平台适配面），单独立项；控件不卡这一条。

## 排期与依赖链

1. **前置（已在走，不在本提案排期）**：text-selection-a11y 一期——`TextLayout` 抽取 + code_view 选中。
2. **扫描器升级**：跨行状态 + 行级增量 + 字节偏移；code_view 静态路径 wbtest 钉零回归。
3. **code_editor 控件**（P1）。
4. **terminal 控件**。
- 每步走流转：动工进 TODO → 实现 → roadmap 移「已实现」按平台标状态 → `测试文档/测试用例.md` 补条。
- 门禁：`cd gui && moon check --deny-warn` 零错误零警告；`moon test ui input widget text` 全绿；真机视觉项（高亮可辨性、光标闪烁、ANSI 色）交用户验。

## 不做

- tree-sitter 进 `gui/`（重 FFI；真要走是 `modules/` 子模块另立项）。
- pygments / bobzhang/lexer 进依赖（留档备选）。
- PTY 与 shell 会话管理（另立项）。
- 语义级着色（AST 级）——归 tools/lsp 与 VSIX 线，库内只做词法。
- 终端复用器（多标签/会话快照）——控件之上应用层的事。

## 未核项清单（开工前先回证）

- 行级增量的收敛停条件在「未闭合多行字符串 / 未闭合块注释」下的行为——用例钉死（脏段一路重扫到文末是正确退化，不许死循环）。
- `line_height_font` 各平台等宽行高实测（code_view 现用，增量路径沿用同一来源）。
- ANSI 256 色与 truecolor 取色档；主题深浅两基底可辨性——真机人工项。
- 万行级文件构造期预排版时长探针（experiment/ 微基准）——决定 code_editor 首屏走预排版还是纯增量。
