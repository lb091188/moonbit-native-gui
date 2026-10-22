# Markdown 解析层：依赖面盘点与自研范围

> **状态**：调研完成（2026-10-19）；方案 A 已落地（`modules/mdparse`，同日）
> **跟踪**：`modules/mdparse`（模块）；`gui/mdview` 现状见 §1；落地细节见 §8

## 1. 结论先说

1. **仓库确实只需要「解析」**。`gui/mdview` 对 `mizchi/markdown` 的全部依赖是 1 个函数调用 `@mdast.parse(source)` 加它的 AST 类型；上游的 `serialize` / `md_to_html` / `md_to_html_with_options` / 增量解析（`md_parse_incremental`）一条没用。渲染（块级 17 变体、行内 16 变体、折行、区间计量、删除线自绘、链接命中）全部是我们自己的 1106 行。
2. **社区没有「单一且覆盖齐全」的可直替库**。最接近的是 `moonbit-community/cmark@0.4.12`（62 689 下载，Apache-2.0，`Doc::from_string` 出 AST + Mapper/Folder 遍历），但它缺 5 项我们现在就在用的能力（见 §3），直接换会掉功能、掉测试。
3. **推荐路线：把解析内核 vendor 进仓库（方案 A）**，而不是换库或从零写。理由见 §5。

## 2. 现状依赖面（`gui/mdview`）

| 项 | 实测 |
| --- | --- |
| 上游 import | `gui/moon.mod` 一条：`mizchi/markdown@0.8.3`；`gui/mdview/moon.pkg` 一条：`"mizchi/markdown" @mdast` |
| 调用点 | `markdown.mbt:1066` `@mdast.parse(source)`；`markdown_wbtest.mbt` 9 处 `@mdast.parse` |
| 用到的返回字段 | `document.children`、`definitions`（label/url） |
| 渲染侧自研 | `markdown.mbt` 1106 行 + `markdown_wbtest.mbt` 733 行 |
| 上游未被使用的能力 | `serialize`、`md_to_html`、`render_html_with_options`、`md_parse_incremental`、frontmatter、toc、slug、highlight 全部未用 |

上游根包 `src/` 实测 **15 874 行**（含 bench、增量解析、HTML renderer、serializer）；MoonBit 按包编译、包内不树摇，这 15 874 行会整体进二进制——和我们「只解析」的用法严重不匹配。这一条本身就是换/自研的现实动机，与上游是否修 issue 无关。

## 3. 能力对照（渲染层已实现的语法面）

`markdown.mbt` 的 `md_render_blocks` / `md_flatten_inline` 两个 match 就是需求清单，逐项对照：

| 语法 | mizchi 0.8.3（现用） | cmark 0.4.12 | 我们有实测源文 |
| --- | --- | --- | --- |
| 标题 ATX/Setext、围栏+info、缩进代码 | ✅ | ✅ | ✅ |
| 引用、分隔线、HTML 块 | ✅ | ✅ | ✅ |
| 无序/有序（start）、任务列表 | ✅ | ✅（`ListItem.ext_task_marker`） | ✅ |
| 表格 + 列对齐 | ✅ | ✅（`TableRow` Header/Sep/Data + `TableCellLayout`） | ✅ |
| 脚注**定义** | ✅ | ✅（`ExtFootnoteDefinition`） | ✅ |
| 数学块 / 行内数学 | ✅ | ✅（`ExtMathBlock` / `ExtMathSpan`） | ❌ 未用 |
| 粗/斜/删除线、行内代码、链接、引用式链接、自动链接、图片 | ✅ | ✅（`ReferenceKind::Inline/Ref` 覆盖引用式） | ✅ |
| 软/硬换行、行内 HTML | ✅ | ✅（`Inline::Break` / `RawHtml`） | ✅ |
| **脚注引用 `[^n]`** | ✅ `FootnoteReference` | ❌ 只有定义块，行内无此变体 | ✅ 测试与 paint_probe 都在用 |
| **定义列表**（术语 / `: 定义`） | ✅ `DefinitionList` | ❌ | ✅ GFM 全要素用例 + paint_probe |
| GFM 提示块 `> [!NOTE]` | ✅ `Alert(AlertKind)` | ❌ | ❌ 仅渲染层支持 |
| `:::note` 块级/行内指令 | ✅ `Directive` | ❌ | ❌ 仅渲染层支持 |
| `[[WikiLink]]` | ✅ `WikiLink` | ❌ | ❌ 仅渲染层支持 |

**结论：cmark 缺 5 项，其中 2 项（脚注引用、定义列表）是我们的回归用例直接覆盖的**，换库当天就会红。

## 4. `moon search markdown` 实测候选（按下载量）

| 模块 | 版本 | 下载 | 形态 | 判断 |
| --- | --- | --- | --- | --- |
| `moonbit-community/cmark` | 0.4.12 | 62 689 | cmarkit 移植，纯 AST + Mapper/Folder + HTML renderer | 最接近「单一解析」，但缺 5 项；依赖 `moonbitlang/async` |
| `mizchi/markdown` | 0.8.4 | 20 530 | CST/增量解析 + mdast + HTML + serializer 同包 | 现用；能力最全，但按包编译全量进二进制 |
| `hustcer/html2md` | 0.1.3 | 11 190 | HTML → Markdown，反向 | 不适用 |
| `shiguri-01/markdown` | 0.1.1 | 26 | 事件驱动 + mdast sink | 形态对，太早期（26 下载、0.1.x） |
| `kokic/cmark` | 0.1.1 | 22 | pulldown-cmark 端口，事件流 | 形态对，太早期 |
| `tonyfettes/tree_sitter_markdown` | 0.1.26 | 255 | tree-sitter 语法定义 | 只给语法，AST 与遍历要自己接 |
| `oilleelssq-wq/moonmarkdown`、`lexchb/moonbit-texteditor` | — | <30 | Markdown → HTML | 目标是 HTML，不是 AST |

> 数据来自本机 `moon search markdown -l 30 --json`（2026-10-19，registry 已更新）。

## 5. 方案比较

### 方案 A：vendor 解析内核（推荐）

把 `mizchi/markdown` 的 parse 链路拷进仓库（新建 `gui/mdparse`，或 `modules/mdparse` 独立模块），只留解析：

- **留**：`block_parser_*`、`inline_parser_*`、`scanner`/`syntax`、`mdast` 定义、`entity`、`attributes`。
- **删**：`incremental`、`html_renderer`、`serializer`、`bench_*`、`highlight_*`、`frontmatter`、`toc`、`slug`、`cmd`。
- **改成自己的契约**：对外只出 `parse(String) -> Document` + AST；`position`/增量相关字段可去掉，减少一半结构噪声。
- **许可**：上游 MIT，保留 `LICENSE` 与 `THIRD-PARTY-NOTICES.md` 条目即可。

收益：解析器进仓库，issue 自己修；体积从 15 874 行降到估 6~8k 行（需实测）；渲染层面对的是稳定自控的 AST。
代价：一次性移植 + 后续跟着 CommonMark 规范自己维护；需要保留上游 652 条 spec 用例做回归基线。

### 方案 B：换 `moonbit-community/cmark`

收益：官方社区维护（62k 下载）、结构干净（cmarkit 风格 `Node[T]` + `Meta` 定位 + `Mapper`/`Folder`）、Apache-2.0。
代价：缺 §3 那 5 项，且 cmark 的 `Mapper/Folder` 只能变换已有 AST、**不能注册新语法**——补脚注引用、定义列表要在解析前做预扫描改写、解析后做后处理，容易和原文位置（`layout`/`locs`）打架；另外模块级依赖 `moonbitlang/async`，会被整个拖进 GUI 依赖闭包。
判断：只在「愿意砍掉定义列表/脚注引用」时可选，不推荐。

### 方案 C：从零自研

CommonMark 0.31.2 有 652 条规范用例，加 GFM 扩展与我们要的 4 项私货，估 4~6k 行，且要靠用例逐条磨。除非只做子集（只支持我们文档里出现的语法），否则不建议——上游 bug 的修复成本远低于重写成本。

### 方案 D：维持现状

不动。上游不修的问题继续存在，15 874 行进二进制。只在「当前没有任何解析层 bug」时成立。

## 6. 推荐执行顺序（方案 A 落地）

1. **先锁契约**：`gui/mdview` 不再直接 `import "mizchi/markdown"`，所有 `@mdast.*` 收口到 `gui/mdparse` 的再导出；渲染层只认 `mdparse` 的类型。此步不换实现、零行为变化，可独立提交、可单独回滚。
2. **再 vendor**：把 parse 链路拷进 `mdparse`，删非解析文件，跑 `moon test mdview` 全绿（31 条）+ 补上游 652 条 spec 用例子集做基线。
3. **最后自修**：按 issue 清单改解析行为；渲染层不动。

第 1 步是纯机械收口，风险最低，且无论最终选 A 还是 B 都必须做（换后端只改一个文件）。

## 7. 待确认

- 上游不响应的那几个 issue **具体是什么语法/行为**？（决定第 3 步改哪里；目前只能确认缺能力清单，无法确认具体 bug 面）
- 是否接受把上游解析代码 vendor 进仓库（MIT 署名）？若坚持「一行上游代码都不留」，则只剩方案 C。
- `Alert` / `Directive` / `WikiLink` 三项渲染层支持但无实际源文，是否保留？砍掉可进一步缩小解析面。

> 2026-10-19 补：已确认上游真正的问题不是语法 bug，而是**依赖链编译不过**——`mizchi/markdown@0.8.3 → mizchi/signals → mizchi/brotli@0.1.0`，`brotli` 仍用已废弃的 `moon.mod.json`，新工具链在构建计划阶段就失败；作者不响应。因此「fork + 只留解析」直接定案，第 1、2 项随之关闭。

## 8. 落地记录（方案 A）

产物：`modules/mdparse`，模块名 `NoahLiu/mdparse`（通用解析库，命名不绑定 GUI，可独立发布/复用），单包，`supported_targets = "js+wasm+wasm-gc+native"`（与上游一致，不裁平台）。

| 项 | 结果 |
| --- | --- |
| 源码 | 上游 0.8.3 的解析链路，6 117 行（上游根包 15 874 行） |
| 模块级依赖 | 0（只用 `moonbitlang/core`；上游的 async/parser/x/syntree/moomaid 全部不需要） |
| 删除 | renderer / serializer / incremental / bench / highlight / frontmatter / toc / slug / cmd |
| 修掉的上游问题 | 依赖链里 `mizchi/brotli` 旧清单导致 `moon check` 失败（根因已不存在：不再依赖它） |
| 规则对齐 | 去掉 `#cfg(target=...)` 与 `@v128` SIMD 分支，`find_line_end` 统一标量实现 |
| 测试 | 上游解析测试 147 条随源带入（删 6 条依赖序列化/HTML 的用例，改写 3 条为 AST 断言） |
| 接入 | `gui/moon.mod` + `gui/mdview/moon.pkg` 改指新模块，别名仍是 `@mdast`，渲染层零改动 |
| 门禁 | `mdparse` 147/147、`mdview` 32/32、两处 `moon check --deny-warn` 零错误零警告 |
| 许可 | MIT；`LICENSE` 保留上游版权，`NOTICE.md` 列来源/删改/分发义务，`THIRD-PARTY-NOTICES.md` 登记 |
