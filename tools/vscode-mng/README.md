# MNG VS Code 扩展（`tools/vscode-mng`）

`.mng` 模板的编辑器支持。**静态贡献包**（语言注册 / TextMate 着色 / snippets）住这里，语义（诊断、补全、hover、跳转）全部来自 `mng_cli lsp`——本扩展只做 LSP 编解码。

## 装

1. **mng_cli**：从仓库根执行 `moon install ./tools/native-gui-tools/mng_cli`（装到 `~/.moon/bin`；`moon install` 要「主包」路径，指模块根会报 `is-main: true required`）。验证：`mng_cli --version` 应打印 `mng_cli 0.1.0` 与 `mng-schema 1`。PATH 里找不到时，在设置 `mng.cliPath` 里填绝对路径。
2. **扩展**：本目录执行
   ```sh
   npx @vscode/vsce package
   ```
   得到 `mng-vscode-0.2.0.vsix`，VS Code → 扩展 → `…` → 从 VSIX 安装；或开发期直接把本目录软链到 `~/.vscode/extensions/`。
3. 设置（可选）：`mng.cliPath` 指向可执行文件（默认 `mng_cli` 走 PATH）；`mng.enableLsp=false` 只要着色与 snippets。

握手失败（`--version` 读不到 `mng-schema 1`）时补全降级为空，**着色与 snippets 照用**；状态栏会给出提示。

## 能做什么

| 能力 | 说明 |
| --- | --- |
| 着色 | `<script setup>` 段委托给已装的 MoonBit 扩展文法（没装时退回内置子集）；`<style>` 段按本仓样式子集（属性名 / 数值与单位 / `var(--令牌)` / `#rrggbb` / 枚举关键字 / 伪类）；模板里标签（内置 `ui-*` 与自定义分开）、属性、指令（`v-*`、`:attr`、`@event`）；属性值按表达式着色（`@包.函数`、字符串、数字） |
| snippets | 页骨架、props 头、单根模板、`v-model`、条件链、样式类、组件调用、跨包绑定 |
| 补全 | 标签 = 内置组件表 + 页内符号；属性 = 内置参数 + `v-*` / `@事件`；表达式与 script 段 = 页内符号 + `moon.pkg` 的 `@别名` 表，`@别名.` 后给该包 `.mbti` 的公开成员（函数 / `类型::方法` / 类型 / 常量）；`class="…"` = 本文件 `<style>` 的类名 |
| 诊断 | 编译错误的模板行列（与 `mng_cli build` 同源），显示在 Problems 面板 |
| hover | 内置组件参数表；`@别名.成员` 显示源码声明行；`@别名` 显示包目录 |
| 跳转 | 组件标签 → 组件源码（内置 `ui-*` 走 `@ui.<名>`）；页内标识符 → 声明行；`@别名.成员` → 该包源码文件与行号；裸 `@别名` → 包入口（`.mbti` / `moon.pkg`） |

**刻意不做**：原生 HTML / CSS 的语义补全（能力子集与原生差距大，原生只作高亮底子）；v1 没有真实类型 hover（需桥 `moon ide` 与 source map 正向索引，另批）。

## 已知边界

- 跨工程索引不做：跳转与补全只按当前文件所在包的 `moon.pkg` 解析导入。
- 外部包成员表优先读 `pkg.generated.mbti`；没有该文件时退扫源码 `pub` 顶层声明（可能少列 trait 实现）。
- `class="…"` 的补全只给**本文件** `<style>` 里的类名；跨文件类名运行时由注册表解析，编辑器侧 v1 不扫描整个工程。
- v-for 语法合法但生成器 v1 收口（编译报错指路 ListStore），snippets 里不放 v-for。
- 语言服务不读 `moon check`；类型错误仍以 `moon check` 为准。
