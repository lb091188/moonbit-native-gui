# 代码栈：分词地基、代码编辑器与终端控件

「代码高亮」升级、「代码编辑器」、「终端控件」三件合一份规划：**三个消费者、一条公共地基**——等宽文本栈、着色流、偏移映射 `TextLayout`、编辑内核 `Editor`。目标形态：库供积木，即 `code_editor`、`terminal` 控件；轻量级编辑器应用在库之上自建。
  - 着色流：分词 + 配色，把代码切成一个个词再逐词定颜色。
  - 分词：把连续文本切成有类型的最小词单元，即 Token。
  - 等宽字体：每个字符宽度相同的字体，代码对齐与逐段着色的前提。
  - TextLayout：字符偏移与屏幕几何互查的映射层。
  - Editor：管光标、选区、撤销、剪贴板的编辑内核。
  - 边界：编辑器应用以示例或独立模块形态自建，不进 `gui/`。

2026-11-03 立项。选型口径：分词层**自研带状态扫描器**、不引注册表依赖；终端**控件先行**、PTY 另立项。状态流转见 [roadmap.md](../docs/zh/roadmap.md)「代码栈」节，拆分待办动工时进 TODO。
  - PTY：伪终端，给程序模拟一个真实终端的通道，终端接 shell 必需。

## 定位

- **为什么合一份**：三件各自都要「等宽字体逐段着色 + 偏移映射 + 编辑内核」，分开做等于各修一遍地基；合起来地基只修一次，三件逐个拼装。
- **依赖链**：
  - 排期：自底向上，编号即排期序。

| 层 | 内容 | 状态 |
|---|---|---|
| ① 等宽文本栈 | `@text.Font` 度量接口 `text_width` / `line_height_font`、`draw_box_at` 逐段绘制 | ✅ 已建成 |
| ② 着色流 | `tokenize_lang` 文本转 Token 流 + `CodeTheme` 主题派生配色 | ✅ 已全部落地：跨行状态 + 字节偏移，2026-11-03 随 `scan_line` 落；行级增量，2026-11-05 随 `code_editor` 落 |
| ③ 偏移映射 | `TextLayout` 字符偏移与屏幕几何互查 | ✅ 已建成，gui/input/text_layout.mbt，2026-11-03 |
| ④ 编辑内核 | `Editor` 管 caret/选区/撤销/剪贴板，坐标用 UTF-8 字节下标 | ✅ 已建成，gui/input/editor.mbt |

| 消费者 | 吃的地基 | 缺口 |
|---|---|---|
| `code_view` 代码块/高亮，已成 | ①+② | 跨行状态与字节偏移已接，预排版吃 `scan_line`；仍无编辑态增量 |
| `code_editor` 代码编辑器 | ②升级版+③+④ | ✅ P1+P2 已落，2026-11-05，🚧 真机待验，演示 SC-6.4 |
| `terminal` 终端控件 | ①+网格模型新件+ANSI 状态机新件+④ 行编辑 | 未开工 |

## 现状盘点

- **分词**：`tokenize_lang` / `tokenize_moonbit`——手写逐行扫描器，词级分类。
  - 取证：gui/ui/codeview.mbt。
  - 词级分类规则：9 语言关键字表大小写不敏感、大写开头=类型、`@` 限定名取尾段、后随 `(` =调用、字符串/数字/行注释。
  - 跨行状态已由 `scan_line` 补齐，覆盖块注释 / 三引号串 / heredoc。
  - heredoc：从起始标记到结束标记之间整段算字符串的多行写法。
  - 静态预排版与行级增量均已接入，增量在 `gui/ui/code_editor_scan.mbt`，随 `code_editor` 消费。
- **组件**：`code_view`——构造期一次分词+测宽成预排版表，on_draw 按 `CodeTheme` 现取色；静态内容重绘零分词开销，但**编辑态每敲一键都要整体重建**，无「只重排受影响行」的增量模型；自带横向滚动视口。mdview 围栏/缩进/数学代码块全部复用。
  - 取证：gui/ui/codeview.mbt:407、codeview.mbt:429-454、gui/mdview/markdown.mbt:586-591。
  - mdview：本库的 Markdown 文档渲染控件。
  - 视口：控件内可见并可滚动的区域。
- **编辑内核**：`@input.Editor`——caret/选区/撤销重做/剪贴板，坐标一律 UTF-8 字节下标、caret 落码点边界；只挂在 entry/textarea，没有高亮消费方。
  - 取证：gui/input/editor.mbt。
  - caret：文本插入光标，即当前输入位置。
- **偏移映射**：`TextLayout` 已落 `gui/input/text_layout.mbt`，textarea / code_view / markdown / rich_text 共用。
  - 接口：`build`/`hit`/`caret_x`/`caret_y`/`line_of`/`rects`。
- **终端**：未开工，roadmap 原「终端模拟」条目标 ⏳ 待定。`sys/procrun` 只有管道进程 spawn/wait/signal/kill，**没有 PTY**。

## 定案一：分词层——自研带跨行状态的行级增量扫描器

### 要补什么

- **跨行状态机**：每行携带「行首状态」，开闭记号按语言参数表；逐行扫描时状态顺着行传播，块注释、多行字符串从此劈得准。
  - 行首状态：该行开始时是否在块注释 / 多行字符串 / heredoc 中。
  - 语言参数表：沿用现有关键字表同处扩展。
- **行级增量**：每行缓存 `(行首状态, tokens)`；编辑发生后从变更行向上复用最近一个未变行的行首状态，向下重扫，重扫到某行的行首状态与缓存一致即提前停——典型编辑只碰几行，重扫就此打住。
  - 状态收敛：重扫行的行首状态与缓存一致，增量扫描据此提前停。
- **token 带 UTF-8 字节偏移**：现预排版表只有 token 级 x/宽，补字节区间列——code_view 选中与编辑器复制都吃这一列；与 Editor/TextLayout 的字节下标口径贯穿。
  - 取证：codeview.mbt:429-454。
  - 范围：code_view 选中属 text-selection-a11y 一期首批。
- **兼容**：`code_view` 静态路径零回归——构造期一次预排版、重绘零分词的现状保留，增量模型是新入口供编辑器消费；静态调用方无感。
  - 理由：静态内容最优，现状保留。
  - 范围：静态调用方指 mdview、showcase。

### 不引什么·moon search 社区备选留档·2026-11-03 实搜

| 包 | 是什么 | 不进 gui 的理由 |
|---|---|---|
| bobzhang/pygments@0.2.5 | Pygments 全移植：带状态 lexer、`guess_lexer`、多语言、styles/formatters，输出面向 HTML/终端/Pango 等 | 整篇重排模型非增量；多语言广覆盖本仓用不上，自研表已盖常用语言；留作未来增强备选 |
| moonbitlang/parser@0.4.7 + lexer@0.4.4 | 官方 MoonBit 解析器，AST 级，纯 MoonBit 无 FFI | 语义级着色归 tools/lsp 与 VSIX 线，见 roadmap「编辑器支持」；库内只做词法 |
| tonyfettes/tree-sitter@0.1.1 + tree_sitter_moonbit | tree-sitter 绑定 + MoonBit 语法，属编辑器级增量解析的事实标准 | C 运行时 + 每语言 C 语法，重 FFI，与「MoonBit 全栈原生自绘」定位冲突；真要做走 `modules/` 子模块另立项 |
| bobzhang/lexer@0.3.1 | 手写词法器基元库，提供位置追踪/Unicode | 现扫描器已自成一体且量小，核心约 200 行，引依赖换不来等量收益 |
| mizchi/tui-terminal-buffer@0.1.4 | 终端字符缓冲基元，含 CharBuffer/cell/宽度量 | 方向相反，往终端画而非解析 pty 输出；cell 网格模型思路可参考，不引依赖 |
| SongYZZZ/ansi-guard@0.1.0 | ANSI 转义清洗/审计，安全向 | 终端控件期参考其危险序列清单，含 OSC 8 超链、剪贴板写、标题改写；实现自置 |

- Pygments：Python 生态的老牌语法高亮库。
- ANSI 转义序列：终端里用特殊字符序列控制颜色、光标、标题等的标准写法。
- OSC 8：ANSI 转义序列里表示超链接的标准。
- Pango：Linux 图形生态常用的文本排版库。
- VSIX：VS Code 扩展的打包格式。
- tree-sitter：编辑器领域常用的增量语法解析库，C 实现，每种语言一份语法表。

## 定案二：代码编辑器控件 `code_editor`·落 gui/ui

- **组成**：扫描器 + `Editor` 内核 + `TextLayout` 三积木拼装；等宽字体、行号列沿用 code_view 管线。
  - 扫描器：管增量着色。
  - `Editor` 内核：管编辑操作。
  - `TextLayout`：管命中/选区。
- **与 textarea 分工**：textarea=纯文本编辑；code_editor=等宽+高亮+行号的编辑件；两者共用 `TextLayout` 与 `Editor`，不各造一套选区/命中。
  - textarea：比例字体、无高亮。
- **前置**：text-selection-a11y 一期落地。
  - 范围：`TextLayout` 抽取 + code_view 选中先行验证字节偏移列。
- **批次**：
  - P1：编辑 / 光标 / 选区 / 高亮 / 行号 / 撤销重做；
    - 补充：`Editor` 已有 undo/redo，直接吃。
  - P2：查找、自动缩进、括号匹配、当前行高亮。
- **性能口径**：万行级文件构造期预排版若不可接受，code_editor 走纯增量路径不预排版——首屏只排可视行附近，滚动现排。
  - 依据：见「未核项清单」。

## 定案三：终端控件 `terminal`——控件先行，PTY 另立项

- **范围**：等宽网格 cell + ANSI CSI/SGR 子集 + 光标 + 纵横滚动；**喂文本即可用**——日志面板、REPL 输出、构建输出着色，不需要进程就能消费。
  - 等宽网格 cell：把终端画面划成等宽字符格子，每格存字符 + 前景/背景 + 属性。
  - ANSI CSI/SGR 子集：SGR 着色 / 光标移动 / 清屏 / 滚动区。
  - CSI：ANSI 转义序列里控制光标移动、清屏等动作的一类。
  - SGR：ANSI 转义序列里设置颜色与样式的一类。
  - 光标：实心块/竖线、闪烁。
  - REPL：逐行输入代码、立即看结果的交互式环境。
- **配色口径**：ANSI 16/256 色是**直接色值**，不走 `CodeTheme` 语义角色；缺省前景/背景取主题，深浅基底各校一档可辨性。
  - 区分：`CodeTheme` 角色是语义映射，ANSI 是设备色表，两回事。
- **共用**：等宽字体度量、逐段绘制、横滚视口与 code_view 同管线；网格模型自研，参考社区 CharBuffer 思路不引依赖。
  - 网格模型：cell 缓冲 + 脏行标记。
  - 脏行标记：只重画内容变过的行。
- **安全口径**：不可信输出先清洗高危序列，控件期不消费。
  - 高危序列：OSC 8 超链、剪贴板写、窗口标题改写，参考 ansi-guard 清单。
- **PTY 不在本批**：`sys` 层 forkpty/openpty + Windows ConPTY 是独立平台工程，单独立项；控件不卡这一条。
  - 范围：新 FFI、三平台适配面。
  - ConPTY：Windows 的伪终端 API，PTY 的 Windows 版。

## 排期与依赖链

1. **前置**：text-selection-a11y 一期——`TextLayout` 抽取 + code_view 选中。
   - 状态：已在走，不在本提案排期。
2. ~~扫描器升级~~：**已全部落地**——跨行状态 + 字节偏移；**行级增量**随 `code_editor` 同批落。
   - 跨行状态 + 字节偏移：`scan_line` / `ScanState`，code_view 预排版同批改吃它，289 项 ui+mdview 全绿。
   - 行级增量：2026-11-05，前缀/后缀行对齐 + 渐进扫描，见「已实现」。
3. ~~code_editor 控件~~：**P1+P2 已落**。
   - 状态：2026-11-05，🚧 真机待验。
4. **terminal 控件**。
- 每步走流转：动工进 TODO → 实现 → roadmap 移「已实现」按平台标状态 → `测试文档/测试用例.md` 补条。
- 门禁：`cd gui && moon check --deny-warn` 零错误零警告；`moon test ui input widget text` 全绿；真机视觉项交用户验。
  - 范围：高亮可辨性、光标闪烁、ANSI 色。

## 不做

- tree-sitter 进 `gui/`。
  - 理由：重 FFI。
  - 边界：真要走是 `modules/` 子模块另立项。
- pygments / bobzhang/lexer 进依赖。
  - 处置：留档备选。
- PTY 与 shell 会话管理。
  - 状态：另立项。
- 语义级着色——归 tools/lsp 与 VSIX 线，库内只做词法。
  - 边界：AST 级。
- 终端复用器——控件之上应用层的事。
  - 范围：多标签/会话快照。
  - 终端复用器：在一个终端里管理多个会话的工具，如 tmux。

## 未核项清单·开工前先回证

- ~~万行级文件构造期预排版时长探针~~ **已回证**：万行 × ~80 列 scan+measure = **169ms**，其中纯扫描 113ms；debug 档 326/267ms——构造期整篇预排版不可接受，首屏冻 0.2–0.3s，Windows 纯光栅腿更慢。
  - 取证：2026-11-05，mac release，`experiment/code_editor_bench`。
  - **定案：code_editor 走纯增量路径**——前缀/后缀行对齐 + 渐进扫描 + 逐行测宽按需惰性缓存。
    - delta 映射：前缀/后缀行对齐的实现方式。
    - 渐进扫描：扫到哪缓存哪，首屏只扫可视行附近。
  - 跳到未扫区域的首屏一次扫描成本顺延到跳转时刻，万行 ≈ 0.1s 一跳一次，记边界。
  - 同批读数：单行编辑重扫 **1 行**，收敛判据成立；未闭合块注释退化到文末 **5000 行**，正确退化。
  - `line_height_font` Monospace 13 实测 = **18**。
    - 平台：mac。
- 行级增量的收敛停条件在「未闭合多行字符串 / 未闭合块注释」下的行为——用例钉死。
  - 边界：脏段一路重扫到文末是正确退化，不许死循环。
- `line_height_font` 其余平台等宽行高实测——P1 无头用例不钉具体像素，真机走查行距即可。
  - 平台：Windows/Linux。
  - 补充：P1 无头用例按 `line_height_font` 现算，不钉具体像素。
  - 无头：不开真实窗口、在纯命令行环境跑测试的方式。
- ANSI 256 色与 truecolor 取色档；主题深浅两基底可辨性——真机人工项。
  - 范围：终端控件批。
  - truecolor：直接用 24bit 值表示颜色，比 256 色更细。
