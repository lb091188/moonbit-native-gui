# native-gui 完整产品与开发体验建议

> 审查对象：`lb091188/moonbit-native-gui` 的 `dev` 分支，以及 `lb091188/native-gui-skills` 的 `master` 分支。  
> 审查日期：2026-11-26。  
> 代码快照：`moonbit-native-gui/dev` = `1be8de2afe4d08194c386d8799c71e36a0adf1f2`；`native-gui-skills/master` = `7ce4c3d90cd4920f08a0745932cce57872e431dd`。  
> 目标：在渲染路线已经确定的前提下，规划 native-gui 的功能成熟度、开发者体验（DX）和 AI 协作能力。
>
> 审查方式：通过 GitHub 读取上述分支的 README、Skill、关键 MoonBit 源码、GPU 提案、Inspector/uitest 文档、路线图和 CI 配置；本报告是代码与文档审查，不代表本轮在 Windows/Linux/macOS 真机上重新执行了构建、驱动和交互验收。路线图标为“已合入待真机”的项目仍按待验处理。

---

## 0. 执行摘要

我建议把 native-gui 下一阶段的目标定义为：

**让开发者能够用 MoonBit 快速构建完整的桌面应用，并且让 AI 能够理解、修改、运行、检查和验证这些应用。**

这不是再做一个控件集合，也不只是给 GUI 库补一套 AI 提示词。你现在已经有三块互相连接的基础设施：

1. **GUI 运行时**：控件树、布局、样式、输入、绘制、窗口和系统能力。
2. **mng 工具链**：项目创建、`.mng` 编译、热更新、LSP、检查器、MCP、无头测试、打包发布。
3. **native-gui-skills**：让 AI 按 native-gui 的真实 API、设计规范和工具链工作。

这三者应该作为一个整体规划。真正的差异化不只是“能画 UI”，而是：

**AI 写出的界面能编译、能热更新、能被检查器观察、能被自动测试，并且能按同一套规则在多个桌面平台交付。**

### 最值得优先做的五件事

| 优先级 | 建议 | 原因 |
|---|---|---|
| P0 | 修正 Skills 与主仓库的版本和内容漂移 | 当前已经发现明确不一致，会让 AI 读取到过期规则 |
| P0 | 把 MCP 从“只读观察”补成“受控交互验证” | 当前 AI 能读树、读样式、截图，但不能经 MCP 模拟用户操作 |
| P0 | 完成高 DPI、键盘可达性、屏幕阅读器的跨平台收口 | 这些决定 GUI 能否成为成熟桌面应用框架 |
| P0 | 把无头测试、实时 Inspector、真机验收串成一条验证链 | 现有零件已经有了，重点是形成可信闭环 |
| P1 | 建立统一 Command / Action 模型和成熟业务组件能力 | 让真实大型应用更容易组织和维护 |

**不建议再从零建设 Inspector、UI 自动化测试、项目模板或热更新。** 这些能力已经存在。下一步应当补齐它们之间的接口、验证与维护机制。

---

## 1. 本次仓库审查结论

### 1.1 两个仓库当前分别承担什么角色

`native-gui-skills` 的设计很清晰：把 AI 使用 native-gui 时最重要的两种知识拆成两个技能。

| Skill | 责任 | 主要内容 |
|---|---|---|
| `native-gui-design` | 解决“界面应该怎样设计、怎样使用库的真实 API” | 视觉基准、参数映射、组件配方、六套风格包、去模板化纪律、交付自查 |
| `native-gui-dev` | 解决“怎样创建、开发、调试、验证和发布应用” | `mng`、`.mng`、HOT/COLD、状态归属、组件索引、MCP、Inspector、`@uitest`、打包发布 |

这是一种正确的分工。**设计技能不应该承担工具链操作，开发技能也不应该重复制定视觉体系。**

来源：
- [native-gui-skills README](https://github.com/lb091188/native-gui-skills/blob/master/README.md)
- [native-gui-design/SKILL.md](https://github.com/lb091188/native-gui-skills/blob/master/.agents/skills/native-gui-design/SKILL.md)
- [native-gui-dev/SKILL.md](https://github.com/lb091188/native-gui-skills/blob/master/.agents/skills/native-gui-dev/SKILL.md)

### 1.2 `native-gui-design` 已经不只是视觉提示词

我认为它最有价值的部分不是六种风格，而是它把设计判断变成了可执行约束：

- 间距、字号、圆角和颜色都定义了统一基准。
- `mapping.md` 把这些规则映射到 `@style` / `@ui` 的真实 MoonBit 参数。
- `recipes.md` 给出工具栏、表单、卡片网格、列表、空状态和页面骨架等常用结构。
- 六套风格包不仅包含主题 JSON，还包含布局密度、字体候选和反模式。
- 去模板化章节要求 AI 先理解产品题材、用户和首屏信息，不允许所有界面都变成同一种 AI 默认风格。
- 布局纪律和已知陷阱针对 Yoga / native-gui 的真实行为，而不是照搬 CSS 常识。

这已经是一个小型设计系统的 AI 入口。建议继续保留这种“规则 + 参数映射 + 配方 + 风格包”的结构，不要退化成单份很长的 prompt。

来源：[design Skill](https://github.com/lb091188/native-gui-skills/tree/master/.agents/skills/native-gui-design)

### 1.3 `native-gui-dev` 已经覆盖完整开发主流程

技能文件已经覆盖：

- `mng new` / `mng init` 项目初始化。
- `.mng` 页面结构、`<script>` / `<template>` / `<style>` 分工。
- 页面状态、跨页状态、控件值的归属。
- `mng dev` 的 HOT / COLD 更新契约。
- 生成码纪律和工程目录约定。
- AI 迭代的“修改 → 保存 → 读取控件树 → 截图自审”循环。
- `mng mcp`、`mng inspect` 和 `@uitest` 的使用方式。
- 打包、发布和常见构建卡点。

这比只教 AI 生成 MoonBit 代码成熟得多。它在教 AI 按项目已有工作流完成任务。

来源：[dev Skill](https://github.com/lb091188/native-gui-skills/blob/master/.agents/skills/native-gui-dev/SKILL.md)

### 1.4 主仓库已经具备很多之前建议“新增”的 DX 能力

我对照 `dev` 分支代码后，以下能力应当视为**已有基础**，不能再以“从头建设”列为新项目：

| 能力 | 当前已有内容 | 仍值得做的工作 |
|---|---|---|
| 项目模板 | `mng new`、`mng init`、`mngui` 向导 | 减少首次配置卡点，完善模板变体和升级迁移 |
| 热更新 | `mng dev`、HOT/COLD 分类、模板与源文件监听 | 跨平台真机验收、失败恢复与诊断完善 |
| 编辑器 | `mng lsp`、VS Code 扩展、补全/诊断/Hover/跳转 | 继续增加真实编辑器场景和兼容性测试 |
| Inspector | 控件树、样式读数、样式覆盖、截图、独立检查器窗口 | 统一人与 AI 的检查入口，缩短交互验证链 |
| 快捷检查器 | F12；macOS 的 ⌘⌥I，也接受 F12 | 完成三平台真实环境验收 |
| UI 自动化 | `@uitest` 的定位、点击、输入、按键、滚动、拖拽、帧绘制和像素读取 | 补高层断言、应用级测试组织和更多平台边界测试 |
| AI 接入 | `mng mcp`，提供控件树、样式、截图三个工具 | 增加受控交互能力和更丰富的结构化读数 |
| CI | 编译、测试、构建、冒烟、LSP、VS Code、生成码新鲜度等 | 将 Skills 自身也纳入一致性验证 |
| 文档与示例 | 双语文档、组件示例、系统示例、主题试验场、预构建体验包 | 文档 API 自动核对和组件交互状态覆盖 |

相关源码：
- [mng MCP 实现](https://github.com/lb091188/moonbit-native-gui/blob/dev/tools/native-gui-tools/mng/mcp.mbt)
- [Inspector 文档](https://github.com/lb091188/moonbit-native-gui/blob/dev/docs/guide/inspector.md)
- [无头 Tester](https://github.com/lb091188/moonbit-native-gui/blob/dev/gui/uitest/tester.mbt)
- [CI 工作流](https://github.com/lb091188/moonbit-native-gui/blob/dev/.github/workflows/ci.yml)

---

## 2. 本次审查发现的具体问题

这部分是我认为最应该立即处理的内容，因为它们不是长期设想，而是已经能从代码和文档中确认的差异。

### 2.1 Skills 的 mng 版本基线已经落后

`native-gui-skills` 的 README 和 `native-gui-dev/SKILL.md` 都写着：

- `NoahLiu/native-gui@0.3.3`
- `mng@0.2.12`
- `mng-schema 1`

我查看的 `native-gui` `dev` 分支中：

- `gui/moon.mod` 的 native-gui 版本仍是 `0.3.3`。
- `tools/native-gui-tools/mng/main.mbt` 中的 `MNG_VERSION` 已经是 `0.2.15`。
- `mng-schema` 仍是 `1`。

所以 GUI 库版本对齐，但 mng 文档基线已经落后三个补丁版本。即使命令面恰好未变化，技能文件也不应该继续声称按 `0.2.12` 完整验证过当前工具链。

**建议：**

1. 先把 Skills 的基线更新到实际复核过的 mng 版本；如果还没有对 `0.2.15` 做完整实测，就标记为“待复核”，不要直接把版本号改成已验证。
2. README 和 SKILL 文件只引用一个版本清单，避免同一版本号在多个地方重复维护。
3. 版本基线同时记录 `native-gui`、`mng`、`mng-schema`、`yoga-mbt` 和组件速查来源。
4. 每次 mng 命令面、模板生成物或 Inspector 协议变化时，必须触发对应 Skill 的复核。

来源：[mng 当前版本定义](https://github.com/lb091188/moonbit-native-gui/blob/dev/tools/native-gui-tools/mng/main.mbt)、[GUI 模块版本](https://github.com/lb091188/moonbit-native-gui/blob/dev/gui/moon.mod)、[Skills 版本声明](https://github.com/lb091188/native-gui-skills/blob/master/README.md)

### 2.2 主仓库内有一份同名但较旧的 design Skill

我发现 `moonbit-native-gui/dev` 自己也包含：

`.agents/skills/native-gui-design/SKILL.md`

它和 `native-gui-skills` 仓库中的 Skill 有相同名称与类似 description，但主仓库这一份内容更短：没有“风格包”索引，也没有“去模板化”章节；主仓库对应的 `references` 目录也没有六个 `styles/*.md` 文件。

这会产生一个实际问题：开发者在主仓库里工作时，Agent 可能发现仓库内的同名 Skill，而不是外部仓库的较新版本。不同 AI 客户端对同名技能的加载优先级可能不同，因此会造成行为差异。

**建议明确唯一事实源：**

- 以 `native-gui-skills` 作为面向应用开发者的 Skills 主仓库。
- 主仓库不再手工维护一份容易过期的同名副本；要么移除重复副本，要么通过固定版本/提交的同步脚本生成镜像。
- 如果主仓库确实需要内置版，就把它标注为“仓库开发者本地版”，并确保它与外部版本自动对账。
- 同步时必须同步整个 Skill 目录，而不只是 `SKILL.md`，否则引用的 `references/styles/` 会缺文件。

来源：[主仓库内的 design Skill](https://github.com/lb091188/moonbit-native-gui/blob/dev/.agents/skills/native-gui-design/SKILL.md)、[Skills 仓库的完整目录](https://github.com/lb091188/native-gui-skills/tree/master/.agents/skills/native-gui-design)

### 2.3 MCP 目前是“只读观察工具”，还不是完整的 UI Agent 工具面

当前 `mng mcp` 对外注册三个工具：

- `inspector_tree`
- `inspector_style`
- `inspector_shot`

它们足够让 AI 看当前控件树、样式和截图。但 Inspector 服务本身已经有更丰富的操作命令，例如：

- `select <id>`
- `highlight <id>`
- `style set <id> ...`
- `style reset <id>`

这些能力并没有完整映射到 MCP 工具面。更重要的是，MCP 目前没有点击、输入、按键、滚动等用户交互工具。

所以当前 AI 可以通过修改 `.mng` 让界面热更新，然后观察结果；但对于“按钮点击后页面是否正确变化”“键盘导航是否正确”“输入后校验是否工作”这类运行时行为，AI 还不能仅靠现有 MCP 工具完成完整验证。

**建议：不要一次性暴露几十个低层工具，而是分两批补齐。**

第一批（低风险、以观察和定位为主）：

| 工具 | 用途 |
|---|---|
| `inspector_highlight` | 高亮指定控件，便于截图和确认定位对象 |
| `inspector_style_set` | 在调试会话内临时覆盖指定控件样式 |
| `inspector_style_reset` | 撤销单控件样式覆盖 |
| `inspector_subtree` | 读取指定节点及其子树，避免每次传整个控件树 |
| `inspector_diagnostics` | 返回布局异常、不可见原因、后端状态和最近错误 |

第二批（交互验证）：

| 工具 | 用途 |
|---|---|
| `ui_click` | 按稳定语义名或节点 id 点击控件 |
| `ui_type_text` | 向当前焦点控件注入文本 |
| `ui_key` | 注入按键和修饰键 |
| `ui_scroll` | 在指定区域滚动 |
| `ui_wait` | 等待状态条件满足，而不是固定 sleep |

交互工具必须有边界：

- 只允许作用于由 `mng mcp --run` 或显式选中的调试应用。
- 控件树快照要带 frame/revision，避免 AI 用旧 id 操作新树。
- `ui_wait` 应按可观察条件等待（文本、状态、节点存在、尺寸变化），并有超时。
- 操作返回结构化结果：执行是否成功、目标是否找到、事件是否消费、操作后 frame id。
- 不把任意进程执行、任意文件读写或通用 shell 能力混进 Inspector MCP。

如果用户只需要自动化测试，而不是在运行中的应用上探索交互，优先使用 `@uitest`；MCP 更适合 AI 实时检查正在运行的应用。

来源：[MCP 工具注册](https://github.com/lb091188/moonbit-native-gui/blob/dev/tools/native-gui-tools/mng/mcp.mbt)、[Inspector 服务命令](https://github.com/lb091188/moonbit-native-gui/blob/dev/gui/inspector/service.mbt)、[Inspector 用户文档](https://github.com/lb091188/moonbit-native-gui/blob/dev/docs/guide/inspector.md)

### 2.4 Design Skill 内部有一处规则冲突

`baseline.md` 将 1px 描边描述为唯一描边宽度；但 `styles/industrial.md` 明确要求 `border_width: 2.0`，并且把粗描边当作工业风的核心语言。

这不是不能允许，而是需要定义清楚：

- 1px 是默认设计系统基准；
- 2px 是 Industrial 风格包的显式例外；
- 例外必须由用户选定该风格包触发，不能变成任意页面随意加粗边框的理由。

另外，间距刻度规则也应该限定为“设计系统间距值”，不能把所有尺寸、图表几何、控件内部尺寸和数据驱动的尺寸都强制压到七个数值上。

**建议把设计约束拆成三类：**

1. **全局不变量**：颜色 token、主题跟随、交互状态、语义完整、平台不分叉。
2. **默认视觉基准**：间距刻度、常规 1px 边框、字号等级、常规圆角。
3. **风格包特例**：明确声明可覆盖哪些基准，例如 Industrial 的 2px 边框、Editorial 的字阶变化。

这样 AI 才能既有一致性，又不被自己的规则互相限制。

来源：[设计基准](https://github.com/lb091188/native-gui-skills/blob/master/.agents/skills/native-gui-design/references/baseline.md)、[工业风格包](https://github.com/lb091188/native-gui-skills/blob/master/.agents/skills/native-gui-design/references/styles/industrial.md)

### 2.5 Skills 仓库还缺少自己的自动化质量门禁

我查看了 `native-gui-skills` 的仓库树：当前内容主要是 README、两个 Skill 和 references，没有看到专门的 `.github/workflows` 测试工作流。

这意味着 Skills 的版本声明、引用文件、代码片段、主题 JSON 和组件参数映射，主要靠人工维护和人工复核。对于一个专门指导 AI 生成代码的仓库，这个风险不应长期存在。

建议增加 Skills CI，至少检查：

- 所有 `SKILL.md` 引用的 reference 路径真实存在。
- README 提及的 Skill 名称、安装路径和目录结构一致。
- 所有主题 JSON 都能通过 native-gui 的主题解析器。
- 文档中列出的组件名和参数能从对应版本的公开 API / `.mbti` 中核对。
- 可复制的关键代码片段能在最小 native 工程中 `moon check`。
- 技能基线版本与实际复核版本一致。
- `native-gui` 内置镜像（如保留）与 Skills 主仓库版本一致。

不要把所有自然语言规则都硬编码成 lint。优先自动验证能机械判断的事实：文件路径、版本号、JSON、API 符号、构建片段和工具列表。

---

## 3. 产品定位：从 GUI 库发展为 AI 友好的桌面应用开发平台

建议明确产品由三层组成：

```text
应用开发者 / AI Agent
        │
        ▼
native-gui-skills
设计规范、组件配方、项目工作流、AI 操作纪律
        │
        ▼
mng 开发工具链
new / dev / LSP / inspect / MCP / uitest / package / publish
        │
        ▼
native-gui Runtime
Widget / Layout / State / Theme / Input / Render / Window / System
```

这三个层次需要各自有稳定边界：

- **Runtime** 提供可靠、可组合的 UI 能力。
- **mng** 提供开发、调试、测试、打包和发布的可重复流程。
- **Skills** 教 AI 正确使用前两者，但不应成为 API 的唯一说明来源，也不应该绕过类型系统和测试。

把 AI 能力当作正式产品能力，不意味着把 AI 绑定进运行时。native-gui 不需要依赖某个模型或 Agent 平台；它只需要提供稳定、可探测、受控、结构化的工具接口。

---

## 4. 功能体验建议

以下按“应用开发者实际能否完成工作”排序，而不是按控件数量排序。

### 4.1 P0：完成桌面基本体验的关键缺口

#### A. 无障碍与键盘可达性

路线图已经有 `role / name / state`、帧尾语义快照和三平台桥接基础；macOS VoiceOver 已有首轮真机通过记录，但 Windows NVDA / Linux Orca 仍待跑，富文本和代码视图的语义也有缺口；全量控件键盘可达性仍是规划项。

建议把它作为 P0，而不是等到最后。

**具体工作：**

- 完成 Windows UI Automation、Linux AT-SPI、macOS Accessibility 的真实屏读验证。
- 为所有可交互组件统一 Tab 顺序、可见焦点环、方向键行为和禁用态语义。
- 补齐 dialog、popover、菜单、表格、树、图表、富文本、代码视图的语义。
- 定义焦点进入/退出复合控件时的规则。
- 提供无障碍树调试和自动化断言。

**验收：**

- 三平台至少一套主流屏幕阅读器完成关键流程验收。
- 组件展示应用可用键盘完成核心交互，不需要鼠标。
- 自动化测试能断言 role、name、value、state、focus 和 enabled。

#### B. 高 DPI 与跨屏动态缩放

路线图已把 125% / 150% 混合 DPI、窗口跨屏后重排与重采样列为规划工作。这会直接影响界面尺寸、字体、命中测试和截图质量。

**具体工作：**

- 统一逻辑像素、物理像素、窗口客户区和位图像素的换算。
- 窗口跨显示器后更新 scale factor，并触发布局、字体、光栅缓存和 GPU 资源更新。
- 处理 100%、125%、150%、200% 等常见倍率。
- 明确截图尺寸与坐标读数使用逻辑还是物理像素。

**验收：**

- 同一窗口在不同缩放倍率下控件大小、文本、命中区域保持一致。
- 跨屏移动不出现文字突然变小、模糊、错位或鼠标命中偏差。
- UI 自动化测试明确标注坐标单位，不靠猜测。

#### C. 虚拟滚动与大数据组件成熟度

现在已有表格、列宽拖动、排序、单选/多选和万行虚拟滚动；下一项真正有价值的工作，是路线图里已经规划的“可变高度任意元素虚拟滚动”，而不是重新做一个普通 Table。

**具体工作：**

- 完成可变高度列表的估高、实测、前缀和与二分定位。
- 处理插入、删除、过滤、排序时滚动锚点稳定。
- 明确异步数据加载、占位行、空状态、错误状态。
- 对滚动时的重绘、命中、焦点和无障碍节点进行统一处理。

后续可以再评估 DataGrid 的单元格编辑、固定列、复制粘贴和异步数据源；先不要同时开多个复杂表格版本。

**验收：**

- 固定行高仍保留原有快速路径。
- 可变高度滚动时不出现大跳动和明显白屏。
- 插入/删除数据后，用户当前查看的内容尽量保持锚定。
- 万行数据、复杂卡片列表和分组列表有固定性能基准。

#### D. 文字输入与编辑器体验

对桌面应用而言，TextField 不只是能输入字符。中文输入法、组合文本、选区、撤销重做、剪贴板、光标候选框位置，都是成熟度的重要指标。

建议把现有 `input`、`textarea`、`code_editor` 的行为定义成统一文本编辑契约，并用真实输入法和自动化测试分别验证。

**验收：**

- 中文拼音组合输入、中途取消、候选选择、光标移动和选区替换正常。
- 输入法候选窗位置跟随插入符。
- Ctrl/Cmd+C/X/V、全选、撤销、重做行为一致。
- 焦点切换、窗口隐藏/显示和窗口关闭时，不残留旧组合串。

### 4.2 P1：让大型业务应用更好组织

#### A. 统一 Command / Action 模型

建议增加一个与具体 UI 解耦的命令模型：命令有稳定 id、标题、本地化文案、快捷键、启用条件、执行函数和可选图标。

菜单、工具栏、右键菜单、快捷键和命令面板共享同一个 Command，而不是分别写回调。

**建议概念：**

```moonbit
// 概念 API，名称与签名以实际实现为准
let save_command = Command::new(
  id="file.save",
  title="保存",
  shortcut="Ctrl+S",
  enabled=can_save,
  execute=fn() { document.save() },
)
```

价值：降低复杂应用的重复代码，让快捷键、本地化、禁用态、菜单状态保持一致，也方便 AI 理解用户操作入口。

#### B. 异步任务与加载状态规范

建议提供统一的异步任务呈现模式：Loading、Success、Empty、Error、Cancelled。不要让每个应用各自发明加载动画、错误提示和重试逻辑。

重点考虑：

- 任务取消与页面卸载。
- 进度、重试、错误详情。
- 后台任务结果回传 UI 的线程边界。
- 多个异步任务并发时的状态归属。

#### C. 窗口与应用状态持久化

已有多窗口、几何记忆、路由等基础。建议继续收口：窗口状态、页面状态、用户偏好、最近文件和工作区布局应有清晰分层。

不要把所有内容都放进单一全局 Store。需要明确哪些状态跨页面、跨窗口、跨应用重启保留。

#### D. 设计系统与组件 Playground

`examples/components` 已经是丰富的组件展示库，`examples/theme-playground` 也已经存在。下一步不应再只做“展示更多控件”。

建议把现有示例升级成可调试的组件 Playground：

- 选择组件后可改变 props、主题和交互状态。
- 展示默认态、hover、pressed、focused、disabled、selected、error。
- 自动显示对应 MoonBit / `.mng` 代码。
- 每个演示案例可单独运行并可被测试。
- 生成截图作为版本对比样本。

#### E. 系统能力的诚实降级

你在贡献规范里已经强调“能力缺失就明确报 Unsupported，不要假成功”。建议把这一原则产品化：每个系统能力都提供 capability 查询、可用状态、降级原因和对应文档。

这对 Windows / macOS / Linux 的桌面差异尤其重要，也能让 AI 在生成应用时先检查能力，而不是假设每个平台都能做到一样。

### 4.3 P2：扩展生态

等 P0/P1 稳定之后，再考虑：

- 第三方组件包规范与兼容矩阵。
- 图标、字体、主题、组件配方的可复用资源包。
- 插件扩展机制。
- 更多官方完整应用示例。
- 移动端宿主与输入/无障碍适配实验。

移动端建议继续独立作为产品路线，不要为了追求“跨端”把桌面系统 API 的语义稀释掉。

---

## 5. 开发体验（DX）建议

### 5.1 把现有 Inspector / MCP / @uitest 连接成一个闭环

当前已有三种观察与验证路径：

| 方式 | 最适合的场景 | 特点 |
|---|---|---|
| `mng inspect --gui` / F12 | 人类开发者实时观察 | 图形检查器、树、详情、样式编辑、高亮 |
| `mng mcp` | AI 实时观察正在运行的应用 | 当前 MCP 暴露树、样式、截图三工具 |
| `@uitest` | CI 和无头确定性验证 | 可构建虚窗、注入输入、推进虚拟时间、读取几何和像素 |

不要做三套互不相关的控件定位和快照格式。建议建立统一的语义数据契约：

- `kind`：组件类型。
- `role`：无障碍语义角色。
- `name`：稳定测试名称。
- `label` / `text`：可见内容。
- `state` / `value` / `enabled`：交互状态。
- `id` / `parent`：运行时定位。
- `rect`：几何信息，必须标注坐标空间与单位。
- `frame_revision`：当前快照的版本号。

这样 Inspector、MCP、UI Test 和无障碍系统都可以复用一套核心语义，而不是每个工具各自解析 UI。

### 5.2 MCP 应该返回结构化数据，而不是让 AI 主要解析自由文本

当前 MCP 的设计很轻量，三工具足够启动；但长期不建议将 TSV 文本作为唯一机器接口。

建议逐步引入稳定 JSON 对象：

```json
{
  "frame_revision": 128,
  "nodes": [
    {
      "id": 42,
      "parent": 7,
      "kind": "ui-button",
      "role": "button",
      "name": "save-button",
      "text": "保存",
      "enabled": true,
      "rect": { "x": 16, "y": 24, "width": 96, "height": 32 },
      "coordinate_space": "window-logical"
    }
  ]
}
```

保留 CLI TSV 输出以便人类和脚本使用；MCP 使用结构化结果，减少 AI 对列顺序、转义和截断的依赖。

建议先补 `frame_revision`、`coordinate_space`、`truncated`、`errors` 等元数据，不必一次性重写整个服务协议。

### 5.3 让 `@uitest` 成为正式的应用级测试 API

`Tester` 已经支持定位、点击、文本注入、按键、滚动、拖拽、布局刷新、矩形读取、文本读取、角色读取和像素读取，也有能力守卫和 `finish()` 防止测试空跑。

建议补的是更高层的断言与失败产物，而不是再造一套测试引擎：

- `expect_exists(name)` / `expect_visible(name)`。
- `expect_text(name, expected)`。
- `expect_enabled(name)` / `expect_state(name, state)`。
- `expect_rect(name, expected, tolerance)`。
- `expect_focus(name)`。
- 失败时自动输出控件树、关键样式、截图和最近日志。
- 提供测试用例的应用级 fixture，减少每条测试重复 mount / 初始化。

同时明确无头测试边界：虚拟窗口不等于真实窗口。当前无头路径无法替代真实 IME、系统对话框、托盘、通知、真实屏幕 DPI、原生窗口合成器、屏幕阅读器和真实 GPU present 的验收。

推荐分层：

1. 白盒单元测试：纯逻辑、布局状态机、绘制几何。
2. 无头 UI 测试：事件、控件状态、布局、像素、虚拟时间。
3. Inspector/MCP 实时测试：开发时验证正在运行的应用。
4. 真机验收：平台输入法、无障碍、DPI、窗口合成、GPU、系统能力。

### 5.4 增加可解释的运行时诊断

不要只给 AI 一张截图。建议 `inspector_diagnostics` 汇总：

- 当前实际 Renderer / Surface / present 路径。
- GPU 初始化状态、设备丢失原因、当前 fallback 档位。
- 帧耗时（布局 / 绘制 / 合成 / present）。
- 最近布局异常：零尺寸、溢出、裁剪、不可见。
- 资源加载失败和图片/字体错误。
- 最近一次输入/焦点路由情况。

这会比继续增加一个“自动修 UI”按钮更有价值，因为它让 AI 和开发者都能知道为什么出现问题。

### 5.5 将 `mng` 命令面和 Skills 绑定验证

建议增加一个概念上的命令：

```sh
mng skill check
```

检查当前工程使用的 Skill 与实际 `native-gui` / `mng` 版本是否兼容，引用文件是否缺失，组件 API 速查是否过期，主题 JSON 是否可解析。

它不需要负责安装所有 AI 客户端，也不需要绑定某家模型平台。只负责给出明确检查报告：

```text
native-gui-skills
  design skill: compatible
  dev skill: stale (expects mng 0.2.12, found 0.2.15)
  references: 1 missing file
  theme JSON: 6/6 valid
  component API index: needs refresh
```

这会把“技能版本漂移”从人工记忆问题变成可自动发现的问题。

### 5.6 做好项目模板，但不要重新造模板系统

`mng new`、`mng init` 和向导已经存在。不要再另开一个平行 CLI。

更有价值的是提供受控模板档位：

- `minimal`：最少文件，适合学习和简单工具。
- `app`：标准应用结构，页面、业务逻辑、资源、测试目录。
- `data-app`：带导航、表格、筛选、异步加载和错误状态。
- `canvas`：自绘 / GPU 内容画布项目。

模板要做到：每一个模板生成后都能直接 `mng dev`、测试和打包；每个模板都由 CI 真正构建，而不是只检查文本存在。

---

## 6. AI Skills 仓库的具体改进方案

### 6.1 保留两个核心 Skill，不要过度拆分

目前 `native-gui-design` 与 `native-gui-dev` 两分法是好的。暂时不需要拆成十个细小技能，否则 Agent 可能难以判断何时加载、也会增加版本同步成本。

建议未来只增加一个第三类：

**`native-gui-maintainer`：专门服务于 native-gui 仓库本身的贡献者。**

它和 `native-gui-dev` 的适用范围不同：

- `native-gui-dev`：在一个应用项目里使用 native-gui。
- `native-gui-maintainer`：修改 native-gui Runtime、mng、平台 C 桩、渲染后端和测试。

maintainer Skill 可以引用仓库已有的 MoonBit、C binding、refactoring、proof、spec-test 技能，不要复制这些通用知识。它只补 native-gui 自身的架构地图、包边界、平台适配纪律、CI 门禁、真实硬件验收与版本发布规则。

### 6.2 建一个唯一版本清单

建议在 Skills 仓库加一个简单 manifest，例如：

```toml
[native_gui]
version = "0.3.3"

[mng]
version = "0.2.15"
schema = 1

[validation]
status = "verified"
verified_at = "2026-11-26"
```

这个文件只是示意。关键是 README、Skill、组件索引和脚本都从同一事实源读版本，不能复制粘贴多个版本号。

如果某个版本还没有跑完验证，应允许状态为 `stale` / `needs_review`，不要仅仅改数字就标成 verified。

### 6.3 把 Skills 的验证做成 CI

建议最小 CI 拆成四类：

| 检查 | 自动化方式 | 失败条件 |
|---|---|---|
| 结构检查 | 检查 README / Skill / references 路径 | 文件缺失、链接失效 |
| 版本检查 | 对照 `gui/moon.mod` 和 mng `MNG_VERSION` | manifest 与源码版本不一致 |
| 内容检查 | JSON 主题解析、公开 API 符号对照、示例构建 | 非法主题、API 不存在、示例编译失败 |
| 镜像检查 | 对照主仓库内嵌 Skill 或生成副本 | 内容漂移、漏同步文件 |

在 `native-gui` 的 CI 中增加一个轻量 job：主仓库相关 API、mng 命令面或模板生成器发生变化时，触发 Skills 兼容性检查。

### 6.4 让 Skill 规则有可追溯的来源

每一条容易过期的规则，建议标注来源：

- API 参数：对应模块 `.mbti` 或源码路径。
- 视觉基准：对应 theme token 和默认样式实现。
- 布局陷阱：对应白盒测试或真实适配记录。
- mng 行为：对应 CLI 命令、工具测试或文档。
- 平台差异：对应测试用例编号和验证日期。

这样 AI 或维护者发现行为变化时，能找到真正的事实来源，而不是只改提示词。

### 6.5 明确默认规则和例外规则

Design Skill 建议增加一个简明约定：

> 先使用全局设计基准；用户明确选择风格包后，风格包可以覆盖其明确声明的视觉变量；风格包没有声明的变量继续沿用全局基准。风格包不能覆盖功能、可访问性、响应式和跨平台行为要求。

这会解决当前 Industrial 2px 边框和 baseline 1px 唯一边框之间的冲突，也能防止未来风格包互相叠加导致规则不清。

---

## 7. 渲染架构对功能和 DX 的影响

渲染方案确定后，不建议把所有普通控件改写成 GPU 专用实现。应继续坚持：

- 一套 Widget Tree、Layout、State、Theme、Input。
- CPU 和 GPU 是后端实现，不是两套 UI 框架。
- 普通控件使用统一绘制语义。
- 视频、3D、自定义 GPU 内容通过专用 GPU 接口接入。
- 无 GPU 时能诚实回退到软件绘制。

先把当前代码中的两条 GPU 路径区分清楚。这一点很重要，不能把“窗口上屏已经用 GPU”误说成“所有控件已经在 GPU 上绘制”：

- **Layer 1：普通 UI 的 GPU 合成 / Present。**普通 Widget 仍由现有 `Painter` 在 CPU 上画进 `Bitmap`；窗口呈现时把 Bitmap 上传为纹理，再由 GPU 画全屏 quad 并 present 到 swapchain。GPU 不可用时回退原来的平台位图上屏。这已经能让 GPU 参与窗口最终合成，但控件的逐像素光栅工作仍在 CPU。
- **Layer 2：GPU 专用控件 / `GpuCanvas`。**视频纹理、简单 GPU 图形或应用自定义 3D 内容可以走 `RenderCtx::Gpu` / `GpuSink` / `GpuCanvas`。目前 `GpuCanvas.finish()` 会把离屏目标读回 CPU 字节，再接回既有上屏路径；这属于过渡接法，不等同于最终的 GPU render-target 直接参与窗口合成。

所以当前更准确的描述是：**普通控件 CPU 光栅 + GPU 最终合成；少量 GPU 专用内容有独立绘制入口，但其离屏画布读回路径仍需继续演进。** 这比简单说“GPU 与软件光栅两条路”更接近当前架构状态。

从用户和开发者体验看，建议增加三个可观察能力：

1. **渲染策略配置**：Auto / Software / Hardware（最终命名按代码设计）。应由窗口宿主管理；Software 应能强制走 CPU 上屏，Hardware 应明确报出不可用原因，Auto 才自动回退。配置是否支持运行中无损切换，需要单独定义切换时资源重建和帧边界。
2. **当前后端诊断**：显示实际使用的 renderer、present 路径、回退原因和设备状态。建议区分 `widget_raster_backend`、`window_present_backend`、`gpu_content_backend`，否则“GPU 已开启”会让人误以为所有控件都由 GPU 绘制。
3. **渲染测试矩阵**：同一 UI 场景至少覆盖软件光栅 + CPU Present、软件光栅 + GPU 合成、GPU 专用控件混排、GPU 不可用回退、设备丢失/窗口 resize 等档位。

不要把像素完全相同作为 CPU/GPU 成功的唯一标准。应分别检查布局几何、控件语义、绘制结果和性能，并允许字体抗锯齿等合理差异。

对 `GpuCanvas.finish()` 这种 GPU → CPU 读回路径，应明确标记为过渡路径；Layer 1 的 Bitmap → GPU 纹理上传是另一条方向相反的路径，不能把两者混为一谈。最终目标应是 GPU 专用内容的 render target 能直接进入窗口 compositor，避免每帧读回 CPU；这需要与普通控件 CPU 光栅路径并存，而不是强迫普通控件全部重写成 GPU 控件。

来源：[GPU 架构提案](https://github.com/lb091188/moonbit-native-gui/blob/dev/proposals/gpu-architecture.md)、[渲染路线图](https://github.com/lb091188/moonbit-native-gui/blob/dev/docs/reference/roadmap.md)

---

## 8. 建议的实施顺序

建议分四个批次推进，每个批次都有明确交付物和验收标准。

### 批次 0：先治理现有资产和规则漂移

**目标：让 AI 当前拿到的规则就是正确规则。**

任务：

1. 更新 `native-gui-skills` 中 mng 的版本基线，并重新执行版本对应的命令、模板和 MCP 验证。
2. 解决主仓库内嵌 `native-gui-design` 与外部同名 Skill 的重复维护问题。
3. 修正文档基准与 Industrial 风格包的边框规则冲突。
4. 给 Skills 仓库增加结构检查和版本一致性 CI。
5. 为 Skills 添加一个短的变更日志，说明每次同步了哪些 API、命令或设计规范。

**验收标准：**

- 主仓库和 Skills 仓库不会同时提供两个不同内容的同名 Skill。
- manifest、README、Skill 和源码版本能够自动对账。
- 六套风格主题 JSON 全部通过真实解析。
- 所有 reference 文件路径存在。

### 批次 1：打通 AI 的运行时交互验证

**目标：AI 不只是能看界面，还能验证关键交互。**

任务：

1. MCP 增加高亮与样式临时覆盖工具。
2. MCP 增加受控点击、文本输入、按键、滚动和条件等待。
3. 控件树加入 frame revision 和明确的坐标空间。
4. MCP 返回结构化 JSON，避免依赖不稳定文本列解析。
5. `@uitest` 增加高层断言和失败截图/树快照归档。

**验收标准：**

- AI 能自动完成“定位按钮 → 点击 → 等待结果 → 读取状态 → 截图”的完整流程。
- 目标失效或控件树变更时，工具能识别旧 revision，不会点错控件。
- 无头测试失败时能输出足够的诊断信息。
- MCP 不开放任意命令执行，只能操作指定的调试应用。

### 批次 2：完成桌面应用质量底座

**目标：把最影响真实应用的跨平台缺口收口。**

建议顺序：

1. 高 DPI / 混合 DPI 动态缩放。
2. 键盘可达性和焦点环。
3. Windows NVDA、Linux Orca、macOS VoiceOver 验证和缺口修复。
4. 可变高度虚拟列表与滚动性能。
5. 文本输入法和编辑操作完整性。
6. GPU / CPU 后端切换和诊断。

**验收标准：**

- 三个平台有对应的真机验收记录。
- 每个新行为都有无头测试或可重复的真机用例。
- 任何能力缺失都能明确显示 Unsupported 或降级原因。

### 批次 3：提高应用开发效率和生态复用

**目标：让开发者用 native-gui 构建复杂应用更省力。**

任务：

1. Command / Action 系统。
2. 异步加载、错误、重试、取消的统一状态模式。
3. 组件 Playground 的 props、状态和代码联动。
4. 多窗口、工作区、最近文件和应用偏好的状态管理规范。
5. `native-gui-maintainer` Skill。
6. 第三方组件包和主题资源的版本兼容规范。

**验收标准：**

- 至少一个完整业务应用使用统一 Command / Action，而非应用自行拼回调。
- Playground 里的案例可运行、可测试、可导出代码。
- 第三方组件包有明确的 API 版本和平台支持声明。

---

## 9. 不建议现在投入的方向

| 暂不建议 | 原因 |
|---|---|
| 从零重做 Inspector | 已有 Inspector UI、服务、mng inspect、MCP 和 F12 入口；应补接口和验收 |
| 从零重做 UI 自动化 | `@uitest` 已具备虚窗、输入注入、几何和像素读取；先提高断言和测试组织 |
| 再做一个项目创建 CLI | `mng new` / `mng init` / `mngui` 已存在；应完善模板，而不是平行造轮子 |
| 继续堆大量风格包 | 六套风格已经覆盖常见方向；优先把规则和例外验证做好 |
| 让 AI 直接生成并提交所有运行时行为 | AI 应通过类型检查、测试和受控 Inspector 迭代；不能绕开质量门禁 |
| 立即把所有普通控件迁成 GPU 专用控件 | 会造成两套控件维护成本；统一绘制语义和多后端更稳妥 |
| 用截图像素相同证明三平台完全一致 | 字体、抗锯齿、DPI 和 GPU 算法有合理差异；应分层验收 |

---

## 10. 建议的度量指标

避免只用“增加多少 API / 组件 / Skills”衡量进展。建议记录这些指标：

| 维度 | 指标 | 想回答的问题 |
|---|---|---|
| 上手体验 | 从 `mng new` 到窗口运行所需步骤/时间 | 新用户能否快速开始 |
| 开发循环 | `.mng` 保存到应用看到更新的耗时；HOT/COLD 成功率 | 修改是否高效、稳定 |
| AI 迭代 | AI 能独立完成的“修改-观察-交互验证”任务比例 | AI 是否真的理解工具链 |
| 定位能力 | 失败时是否能提供树、样式、截图和原因 | 问题能否快速定位 |
| 组件质量 | 关键组件的自动化交互覆盖 | 组件能否用于真实业务 |
| 跨平台 | Windows / Linux / macOS 真机用例通过率 | 平台承诺是否可信 |
| 无障碍 | 屏读和键盘流程完成率 | 应用是否对不同用户可用 |
| 渲染 | CPU/GPU 各阶段耗时、回退次数、设备丢失恢复 | 硬件加速是否有实际收益 |
| 兼容性 | Skills 基线漂移数量、过期 API 数量 | AI 规则是否跟得上库变化 |

---

## 11. 最终建议

我的总体判断是：**native-gui 的基础设施比单看 GUI 组件数量所呈现的成熟度更高。** 你已经有项目生成、模板热更、编辑器集成、Inspector、MCP、无头 UI 测试、三平台 CI 和发布链路；`native-gui-skills` 则把这些能力进一步变成 AI 可执行的工作规则。

接下来最重要的工作不应是继续增加工具数量，而是解决三个核心问题：

1. **事实一致：** API、mng 命令、Skills、主仓库内置规则和文档必须来自同一事实源。
2. **验证闭环：** AI 应能修改代码、观察运行时、执行交互、读取诊断，并用自动化测试证明结果；真机专属能力仍需真实平台验收。
3. **平台成熟度：** 高 DPI、键盘可达性、屏幕阅读器、输入法、虚拟滚动和 GPU present 等功能必须有明确的跨平台验收结果。

如果只能先做一件事，我建议先做**批次 0：治理 Skills 与主仓库之间的同步和版本漂移**。因为 Skills 是 AI 对框架的“操作手册”；如果操作手册和真实代码不一致，后续所有 AI 自动化都会建立在不可靠的信息上。

紧接着做**批次 1：给 MCP 增加受控交互验证**。这会让你已有的 `mng dev`、Inspector、MCP、`@uitest` 形成真正的 AI 开发闭环。

---

## 附录 A：本次核对的主要文件

### `native-gui-skills`（master）

- [README.md](https://github.com/lb091188/native-gui-skills/blob/master/README.md)
- [native-gui-design/SKILL.md](https://github.com/lb091188/native-gui-skills/blob/master/.agents/skills/native-gui-design/SKILL.md)
- [baseline.md](https://github.com/lb091188/native-gui-skills/blob/master/.agents/skills/native-gui-design/references/baseline.md)
- [mapping.md](https://github.com/lb091188/native-gui-skills/blob/master/.agents/skills/native-gui-design/references/mapping.md)
- [recipes.md](https://github.com/lb091188/native-gui-skills/blob/master/.agents/skills/native-gui-design/references/recipes.md)
- [styles/](https://github.com/lb091188/native-gui-skills/tree/master/.agents/skills/native-gui-design/references/styles)
- [native-gui-dev/SKILL.md](https://github.com/lb091188/native-gui-skills/blob/master/.agents/skills/native-gui-dev/SKILL.md)
- [components.md](https://github.com/lb091188/native-gui-skills/blob/master/.agents/skills/native-gui-dev/references/components.md)

### `moonbit-native-gui`（dev）

- [GUI 模块版本](https://github.com/lb091188/moonbit-native-gui/blob/dev/gui/moon.mod)
- [mng 版本与命令入口](https://github.com/lb091188/moonbit-native-gui/blob/dev/tools/native-gui-tools/mng/main.mbt)
- [mng MCP](https://github.com/lb091188/moonbit-native-gui/blob/dev/tools/native-gui-tools/mng/mcp.mbt)
- [Inspector 服务](https://github.com/lb091188/moonbit-native-gui/blob/dev/gui/inspector/service.mbt)
- [无头 UI Tester](https://github.com/lb091188/moonbit-native-gui/blob/dev/gui/uitest/tester.mbt)
- [Inspector 文档](https://github.com/lb091188/moonbit-native-gui/blob/dev/docs/guide/inspector.md)
- [路线图](https://github.com/lb091188/moonbit-native-gui/blob/dev/docs/reference/roadmap.md)
- [CI 工作流](https://github.com/lb091188/moonbit-native-gui/blob/dev/.github/workflows/ci.yml)
- [GPU 架构提案](https://github.com/lb091188/moonbit-native-gui/blob/dev/proposals/gpu-architecture.md)

