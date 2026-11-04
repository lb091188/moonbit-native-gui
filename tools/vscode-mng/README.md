# MNG VS Code 扩展（`tools/vscode-mng`）

`.mng` 模板的编辑器支持。**静态贡献包**（语言注册 / TextMate 着色 / snippets）住这里，语义（诊断、补全、hover、跳转）全部来自 `mng lsp`——本扩展只做 LSP 编解码。

## 装

1. **mng**：从仓库根执行 `moon install ./tools/native-gui-tools/mng`（装到 `~/.moon/bin`；`moon install` 要「主包」路径，指模块根会报 `is-main: true required`）。验证：`mng --version` 应打印 `mng 0.1.0` 与 `mng-schema 1`。PATH 里找不到时，在设置 `mng.cliPath` 里填绝对路径。
2. **扩展**：本目录执行
   ```sh
   npx @vscode/vsce package
   ```
   得到 `mng-vscode-0.2.5.vsix`，VS Code → 扩展 → `…` → 从 VSIX 安装（覆盖旧版加 `--force`）：
   ```sh
   code --install-extension mng-vscode-0.2.5.vsix --force
   ```
   或开发期直接把本目录软链到 `~/.vscode/extensions/`。**升级后必须 Reload Window**，TextMate 文法随扩展加载，不重载仍是旧着色。
3. 设置（可选）：`mng.cliPath` 指向可执行文件（默认先查 PATH，再查 `~/.moon/bin`）；`mng.enableLsp=false` 只要着色与 snippets。

握手失败（`--version` 读不到 `mng-schema 1`）时补全降级为空，**着色与 snippets 照用**；状态栏会给出提示，失败原因写在 `MNG` 输出通道。

## 能做什么

| 能力 | 说明 |
| --- | --- |
| 着色 | `<script setup>` 段委托给已装的 MoonBit 扩展文法（没装时退回内置子集）；`<style>` 段按本仓样式子集（属性名 / 数值与单位 / `var(--令牌)` / `#rrggbb` / 枚举关键字 / 伪类）；模板里标签（内置 `ui-*` 与自定义分开）、属性、指令（`v-*`、`:attr`、`@event`）；属性值按表达式着色（`@包.函数`、字符串、数字） |
| 语义着色 | LSP semantic tokens：类型 / let 变量（含 readonly 档）/ props 与签名参数 / 函数 / 方法 / 属性 / `@包` 命名空间按符号表分档（`{{ }}`、`:attr`、`v-model`、`@事件` 表达式槽与 script 段同规则），开语义高亮的主题直接给出区分色；见下方「配色」 |
| snippets | 页骨架、props 头、单根模板、`v-model`、条件链、样式类、组件调用、跨包绑定 |
| 补全 | 标签 = 内置组件表 + 页内符号；属性 = 组件签名的全部参数（含可省参数，带类型 detail）+ `v-*` / `@事件`；表达式与 script 段 = 页内符号 + `moon.pkg` 的 `@别名` 表，`@别名.` 后给该包 `.mbti` 的公开成员（函数 / `类型::方法` / 类型 / 常量）；`class="…"` = 本文件 `<style>` 的类名；`<style>` 段 = 属性名（kebab）+ `var(--令牌)` 的主题色/尺度令牌 |
| 诊断 | 编译错误的模板行列（与 `mng build` 同源），显示在 Problems 面板 |
| hover | 组件参数表来自签名（`名? : 类型 = 默认值` 逐行）；属性悬浮首行说用途（取自组件源码的参数级 `///` 文档），第二行给 `名? : 类型 = 默认值` 与所属组件；`v-*` 指令 / `@事件` / `:动态参数` 各给说明；`@别名.成员` 显示源码声明行；`@别名` 显示包目录。文案随编辑器语言（`vscode.env.language`）中英切换；诊断文本来自编译器，暂为中文 |
| 跳转 | 组件标签 → 组件源码（内置 `ui-*` 走 `@ui.<名>`）；页内标识符 → 声明行；`@别名.成员` → 该包源码文件与行号；裸 `@别名` → 包入口（`.mbti` / `moon.pkg`） |

**刻意不做**：原生 HTML / CSS 的语义补全（能力子集与原生差距大，原生只作高亮底子）；v1 没有真实类型 hover（需桥 `moon ide` 与 source map 正向索引，另批）。

## 配色

着色全部走标准 TextMate scope，最终颜色由主题决定（同一个 scope 在不同主题下颜色不同）：

| 片段 | scope |
| --- | --- |
| 内置组件 `ui-*` / 自定义标签 | `support.class.component` / `entity.name.tag` |
| 属性名 / `class` 属性名 | `entity.other.attribute-name` / `.class` |
| `v-*` 指令 / `@事件` | `keyword.control.directive` / `entity.name.function.event` |
| `class="…"` 值 | `entity.name.class` |
| 表达式：类型 / 变量 / 函数 | `entity.name.type.class` / `variable.other` / `entity.name.function` |
| 表达式：数字·布尔 / 字符串 / 包名 | `constant.numeric`·`constant.language` / `string.quoted` / `entity.name.namespace` |
| 表达式：声明类关键字 / 修饰符 / 控制流 | `storage.type` / `storage.modifier` / `keyword.control` |
| `::`、括号、运算符 | `punctuation.accessor` / `punctuation.brackets` / `keyword.operator` |
| CSS 选择器 / 伪类 | `entity.other.attribute-name.class.css` / `.pseudo-class.css` |
| CSS 属性名 / 枚举值 / 数字与单位 | `support.type.property-name.css` / `support.constant.property-value.css` / `constant.numeric.css` + `keyword.other.unit.css` |
| CSS `var(--令牌)` | `variable.other.custom-property.css` + `support.constant.custom-property-name.css` |

如果主题把某类 token 留成正文色（最常见是变量），可以在设置里只对 `source.mng` 补规则，例如：

```json
"editor.tokenColorCustomizations": {
  "textMateRules": [
    { "scope": "source.mng variable.other.moonbit", "settings": { "foreground": "#268BD2" } }
  ]
}
```

### 语义着色（类型 / 变量 / 参数在任何主题下按语义区分）

TextMate 是正则文法，只能按词形近似（大写当类型、其余小写一律变量）。LSP 侧另有 semantic tokens 通道：`mng lsp` 按符号表分档，编辑器按**语义档**取色——主题自带的语义规则（或其回退 scope 映射）让类型 / 变量 / 参数开箱即有区分色，不用逐主题补。

| 语义档 | 分给谁 |
| --- | --- |
| `type` | 大写标识符：`Store`、`String`、`Int`、`@base.Store` 的 `Store` |
| `variable` | `let` 绑定（声明 + 引用）；不可变绑定带 `readonly` 修饰，`let mut` 不带 |
| `parameter` | props 签名参数与 `fn` 参数（声明 + 体内引用） |
| `function` / `method` | 函数名 / `::` 后成员；`.` 后调用（`.set(…)`、`@shared.tx(…)`） |
| `property` | `.` 后非调用成员 |
| `namespace` | `@包` |

规则：

- 只对标识符类发语义令牌；关键字、字面量、标点、注释、CSS、class 值仍走 TextMate（上表），LSP 降级（`mng.enableLsp=false`、握手失败、旧 mng）时整体退回纯 TextMate，无感。
- **主题开关**：`editor.semanticHighlighting.enabled` 默认 `configuredByTheme`——主题没标 `semanticHighlighting: true`（Solarized 类常见主题就没标）时语义着色不生效。要强制开：
  ```json
  "editor.semanticHighlighting.enabled": true
  ```
- 想改某档颜色：`editor.semanticTokenColorCustomizations`，按上表档名给色，例如参数给浅红：
  ```json
  "editor.semanticTokenColorCustomizations": {
    "rules": { "parameter": "#d19a66" }
  }
  ```

真机验证清单（装 0.2.5 后）：打开 `examples/showcase/pages/dev_demo.mng`——①`qty`/`nick` 是变量档（不可变，亮于正文）；②`Store`/`String`/`Int` 是类型档；③`on_reset` 函数档、`qty.set()`/`@shared.tx()` 方法档；④`@shared` 命名空间档；⑤`{{ qty }}`、`v-model="nick"`、`:text="@shared.tx(…)"`、`@click="on_reset"` 与 script 段同档；⑥带 props 签名头的页里，签名参数是 parameter 档（与变量不同色）；⑦关 LSP 后着色退回纯 TextMate 不报错。

## 命令面板

- **MNG: dev — 模板开发循环**：在集成终端里对工作区根执行 `mng dev`（读 `mng.toml` 盯整个工程的 `.mng` 与主题文件）。可执行文件取 `mng.cliPath` 设置（默认 `mng`，装法见「装」）；停 Ctrl-C。

## 已知边界

- 跨工程索引不做：跳转与补全只按当前文件所在包的 `moon.pkg` 解析导入。
- 外部包成员表优先读 `pkg.generated.mbti`；没有该文件时退扫源码 `pub` 顶层声明（可能少列 trait 实现）。
- `class="…"` 的补全只给**本文件** `<style>` 里的类名；跨文件类名运行时由注册表解析，编辑器侧 v1 不扫描整个工程。
- v-for 语法合法但生成器 v1 收口（编译报错指路 ListStore），snippets 里不放 v-for。
- 语言服务不读 `moon check`；类型错误仍以 `moon check` 为准。
