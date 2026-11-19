# 热更与编辑器

`mng dev` 的循环与编辑器支持。文法见[单文件组件（.mng）](./sfc)，命令与 `mng.toml` 见 [mng 命令与配置](./mng)。

## mng dev 循环

```sh
cd my_app && mng dev
```

- **watch 面**：全工程模板（按 `mng.toml [dev].templates`）+ 工程源文件（`.mbt`（排 `*.gen.mbt`）/`moon.pkg`/`moon.mod`/`moon.work`）+ 主题文件（配了 `theme` 键时）。
- **首轮**：生成 dev 形态 `<stem>.gen.mbt` 到模板同包（热更面在库包 `@mngdev`）→ `moon build` → 起应用。`run` 留空时从 Artifacts 输出抓可执行路径。
- dev 临时产物都在 `.mng/` 下：应用日志、source map（`.mng/map/`）、IR 补丁、LSP hover 临时文件——文件浏览器不再裸露生成垃圾。

## 改动分类：HOT / COLD

每次保存按契约分类，日志如实告知走了哪条路：

| 改动 | 通路 | 观感 |
|---|---|---|
| 结构加减挪、`:attr` 绑定换目标、类与 `<style>` 值 | **HOT**（IR 补丁经单实例通道推送，原位重挂） | 亚秒 |
| 表达式文本（受限文法内：字面量 / Store / 算术比较 / if / `@shared.tx`·`tr` / 插值） | **HOT**（dev 注册表登记新表达式） | 亚秒 |
| script 段、`v-for` 行模板、新符号 / 新函数、自定义组件、表外参数 | **COLD**（构建 → 杀旧 → 重启） | 秒级 |
| 文法外表达式 | COLD，日志 `[HOT→COLD]` 带原因 | 秒级 |

- **COLD 自动回到改动页**（按模板 stem 唤醒），不用手动导航。
- **状态保活**：script 段外层建的 Store 原地存活（改结构热更后计数还在）；页内状态随补丁重置；控件内部态（焦点/滚动/输入法组合）随子树重建重置。
- **握手防假应用**：补丁带 `rev` + 键集摘要，应用侧判 stale 整批不重挂、回执 `.ack`——工具读到 stale 本拍转 COLD，不会出现「补丁失败但界面停在旧树」。
- 修复型保存后可能闪一次旧状态，随即自纠，属已知观感。

## 文件增删

- 运行中**新增** `.mng` → 日志 `[NEW]`，自动生成并入构建重启。
- **删除** → `[GONE]`，清登记与生成码（生成头不匹配时只报路径不删，防误删手写文件）。
- 改 `main.mbt` 等工程源文件 → `[SRC]`，COLD 重启。

## 主题热重载

`mng.toml` 配 `theme = "assets/theme.json"` 后，主题 JSON **存盘即重载**（`@theme.from_json` 重新应用，不走重启）。调色循环直接改文件保存看效果。

## 应用侧接入（@mngdev）

模板所在包的 `moon.pkg` 加一行（`mng new` 生成时已写好，手工接模板的工程才需要）：

```
"NoahLiu/native-gui/mngdev" @mngdev
```

应用零复制 dev 面代码；生产构建换生产形态生成码后 dev 面整体不在包里。

## VS Code 扩展（tools/vscode-mng）

装法：`cd tools/vscode-mng && npx @vscode/vsce package` 打 vsix 安装（覆盖加 `--force`），或按其 README。能力：

- **着色**：TextMate（script 段 MoonBit / `<style>` 段样式子集 / 模板标签与插值）+ **语义着色**（LSP `semanticTokens`：类型/变量/参数/函数/方法/命名空间分档；任何开语义高亮的主题都区分；LSP 不在退回纯 TextMate）。
- **补全**：标签 = 内置 `ui-*` 表 + 页内/跨包组件；属性 = 组件参数 + `v-*` / `@事件`；表达式 = props/槽/函数名 + 常用模块前缀；类名 = 本文件 `<style>`。
- **hover**：组件参数表；真实类型 hover 经 source map 正投生成码桥 `moon ide` 取编译器答案，任何一步失败回落静态 hover（体验不退化）。
- **跳转**：页内声明、组件源码文件、`@别名.成员`。
- **诊断**：保存即跑 `mng lsp` didSave → 就地重生成 + `moon check`，类型错误经 source map **回投到模板行列**进 Problems（不再对着生成码读报错）。
- **命令面板**：`MNG: dev`（拉起 `mng dev` 到集成终端）、`MNG: 新建页面`（调 `mng new page` 生成并打开）。
- 生成码文件嵌套显示：`*.gen.mbt` 折进模板条目默认收起（只改视图不改磁盘）。

LSP 降级：插件启动对 `mng --version` 握手 `mng-schema` 位，对不上则补全/诊断降级为空，高亮与 snippets 照用。

## 已知观感

- 修复型保存后闪一次旧状态自纠（握手重入窗口）。
- dev 形态与生产形态生成码互相覆盖——提交前选一种（见 [mng 命令与配置](./mng#生成码纪律)）。
