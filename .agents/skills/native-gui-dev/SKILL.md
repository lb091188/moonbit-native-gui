---
name: native-gui-dev
description: Workflow rules for building and verifying NoahLiu/native-gui (MoonBit cross-platform desktop GUI) apps with the mng toolchain. Use when scaffolding a new app (mng new / mng init), writing .mng single-file components, running the mng dev hot-reload loop, verifying a UI without watching the window (mng mcp tools, mng inspect, headless @uitest assertions), or packaging (mng icons / package / publish). Applies to projects whose moon.mod imports NoahLiu/native-gui. For visual baselines (spacing, type, color tokens) use the native-gui-design skill instead.
---

# native-gui 开发工作流（mng）

观感取值照 `native-gui-design` 技能；本技能管工具链：建工程、写页面、热更循环、无头验证、打包。命令细节以 `mng <子命令> -h` 为准，不凭记忆猜参数。

术语先对齐：**热更**指应用不重启就换界面；**无头**指开发者（或 AI）不盯着窗口也能改界面并验证结果——读控件树、读样式、截图代替肉眼。

## 装 mng

mng 随 native-gui 仓库分发，装一次进 `~/.moon/bin`：

```sh
git clone https://github.com/lb091188/moonbit-native-gui
cd moonbit-native-gui
moon install ./tools/native-gui-tools/mng      # CLI 门面
mng --version   # 应打印版本与 mng-schema 位
```

裸敲 `mng` 首跑自动做一轮环境体检，全绿写 `~/.mng/ready` 再进向导；子命令（`mng dev` 等）与 CI 永不受这道门影响。

## 应用初始化

- 从零起工程：`mng new <名>`；给既有工程接模板：`mng init`（模块根写 `mng.toml` 样板，已有不覆盖）；加一页：`mng new page pages/about`（父目录不存在现建）。
- `mng new` 生成七件，全部建议提交仓库：

| 文件 | 作用 |
|---|---|
| `moon.mod` | 已是 `preferred_target = "native"`，已引 `NoahLiu/native-gui` 与 `NoahLiu/yoga-mbt`；不在库 workspace 内生成时版本是兜底值，按你锁定的发布版改 |
| `main.mbt` | 入口三件事：单实例声称（已有实例则唤起后退出）→ `@inspector.inspect_auto_install()` 检查服务接线 → `mount_window` 挂首页 |
| `moon.pkg` | 主包 import：`ui` / `shell` / `inspector` / 本模块 `pages` |
| `pages/home.mng` | 首页模板（script / template / style 三段） |
| `pages/home.gen.mbt` | 由模板生成的代码，带 GENERATED 头，**照常提交** |
| `pages/moon.pkg` | 生成码引用的别名集（@yoga/@ui/@base/@style/@widget/@text/@mngdev） |
| `mng.toml` | `[dev]` + `[package]` 全键样板 |

- `mng.toml` 常用键：`[dev]` 的 `templates`（扫哪些目录的 `*.mng`）、`build`、`run`（留空 = 从 Artifacts 抓可执行）、`app-id`（留空 = 由模块名派生，裸名自动垫 `local.` 命名空间）、`theme`（主题 JSON 路径，存盘即热重载）。

## 代码组织纪律

**界面一律 `.mng`，非界面才是 `.mbt`。** 这是默认分工，不是可选项：

| 内容 | 落点 |
|---|---|
| 页面结构、布局、样式 | `.mng` 的 `<template>` + `<style>` |
| 页面级状态与事件处理 | `.mng` 的 `<script>` 段（MoonBit 原文） |
| 业务逻辑、数据模型、非 UI 工具 | 独立 `.mbt` 包（页面同包或另包） |
| 应用入口 | `main.mbt`：单实例 + 检查服务接线 + 挂窗（`mng new` 已生成，别动） |

- 为什么界面走 `.mng`：只有模板吃亚秒 HOT 热更、LSP 补全与诊断回投、检查器组件视图（一个模板标签一行）；纯构造器写的界面这些全没有。
- **编译器强制**：模板属性里写样式字面量（`color="#f00"`）直接报错——样式必须进 `<style>` 或 `class`。这是架构约束，不是风格建议。
- 例外：高度动态的编程式界面（画布类）或给库本身写组件，才用纯 MoonBit 构造器（`@ui.col([...])`）写 `.mbt`；普通应用页面一律 `.mng`。

## 页面、组件与状态

- **一个页面一个 `.mng`**：生成 `pub fn <stem>() -> Node`，像普通函数接进 `mount_window` 或路由；同包两个 `.mng` 撞 stem 报错。
- **三段结构**：`<script>`（被模板引用的 `let` 绑定即响应槽）/ `<template>` 单根树 / `<style>` 类选择器。指令五件：`{{ expr }}` 插值、`:attr="expr"` 动态属性、`@event="handler"` 事件、`v-model="store"` 双向绑定、`v-for` 行模板。
- **自定义组件**：script 段第一个只有签名、没有函数体的 `fn` 头就是 props 表（必填走位置参数，可选走 `名? : 类型 = 默认值`），同包直接当标签用；跨包 `let 组件名 = @包.函数`。
- **状态三层归属**：页内状态 → script 段绑定；跨页共享 → 应用自持单例（模块里一个 App 结构，模板构建期只读）；控件值 → `Store` 进 `v-model`。
- **值控件统一 Store**：input / checkbox / slider… 的当前值由 `Store[T]` 持有——外部 `set` 即刷新、交互改即回写；展示类取值两条入口 `x`（静态）/ `x_dyn`（Signal）。
- **列表**：`v-for` 源必须是 `ListStore`（`@base.ListStore::new()`），不是 Store 或 Array；keyed 差分走 `for_list`（`key` 必传）。

写页面前先查 `references/components.md`——全部内置组件一行速查（用途 / 状态参数 / 事件），别凭 web 直觉猜组件名与参数。

## 开发循环（mng dev）

```sh
cd my_app && mng dev
```

watch 全工程 `.mng` + 工程源文件 + 主题文件；每次保存按契约自动分类，日志如实告知走了哪条路：

| 改动 | 通路 | 观感 |
|---|---|---|
| 结构加减挪、`:attr` 换目标、类与 `<style>` 值、受限表达式（字面量 / Store / 算术比较 / if / 插值） | **HOT**（补丁推给活着的应用，原位重挂） | 亚秒 |
| script 段、`v-for` 行模板、新符号 / 新函数、自定义组件、表外参数 | **COLD**（重新构建 → 杀旧 → 重启，自动回到改动页） | 秒级 |

- 状态保活：script 段外层建的 `Store` 跨热更存活；页内状态随补丁重置。
- 运行中新增 `.mng` 自动并入构建重启；删除自动清登记与生成码；改 `main.mbt` 走 COLD。
- **生成码纪律**：dev 与生产两种形态共用同一个 `<stem>.gen.mbt` 文件、互相覆盖——提交前选一种并保持（CI 会做新鲜度比对，改了模板忘重生成直接红）。报「生成码不一致」就重跑 `mng dev`（dev 形态）或 `mng build`（生产形态）再提交。

## AI 推动的布局迭代（无头开发闭环）

底座一句话：**`mng dev` 长驻 + `mng mcp` 直连，保存即亚秒热更，mcp 读到的永远是最新帧**——AI「改模板 → 保存 → 读数 → 再改」全自动循环，不需要重启、不需要人碰窗口。

检查服务按注入开关：`MNG_INSPECT=1` 由 `mng dev` / `mng mcp --run` 起应用时自动注入，应用侧 `inspect_auto_install()` 已在模板里接好；未注入零监听。

### 迭代循环（每轮三步）

1. **改**：改 `.mng` 保存——结构/样式/受限表达式亚秒 HOT 生效。
2. **读树**：`inspector_tree` 拿全树几何，按下面的数值判据核。
3. **截图**：`inspector_shot` 截视口自审观感，`full=true` 补整页（含视口外）。

不达标回 1。达标 = 三关全过（见停止条件）。

### 数值判据（树读数比读图准，先数值后截图）

| 现象 | 判据（从 tree 的 x/y/w/h 列） |
|---|---|
| 塌陷 | w/h ≈ 0，或远小于内容合理预期 |
| 溢出 / 裁切 | 子件 x+w 越出父件 x+w；scroll content 高 > 视口高（决定要不要滚或缩） |
| 没对齐 | 同一横排的兄弟件 y 不相等；同一纵排的 x 不相等 |
| 密度失衡 | 同级同类件行距不一致（差出间距刻度一档以上） |

### 停止条件（交用户的门槛）

**树数值零异常 + 截图自审通过 + design 技能交付自查清单全过——三关全过才交用户。** 交给用户的是操作步骤清单（怎么跑、看哪个窗、点什么），用户只做最终验收，不在 UI 层面返工；用户反馈问题回本循环自修，不让用户调样式数值。

### 工具面

**AI 客户端**把 `mng mcp` 配成 MCP server（stdio），三工具：

```sh
mng mcp --run "moon run ."   # 拉起应用并注入检查开关
mng mcp                      # 直连已起的应用（如 mng dev 起的那个）
```

| 工具 | 参数 | 用途 |
|---|---|---|
| `inspector_tree` | 无 | 控件树 TSV（列头 kind/role/name/id/parent/x/y/w/h/state/value/text/enabled），先用它找控件 id |
| `inspector_style` | `id` | 读该控件生效样式（背景/文字/边框/圆角 + 全部已设字段） |
| `inspector_shot` | `path` 可选、`full` 可选 | 截图落盘 PNG 回执路径；`full=true` 整页重画（含视口外） |

**脚本/终端**用 `mng inspect` 一次性取数：`tree [--full]`、`style <id>`、`style set <id> 字段=值 …`（写单件覆写，下一帧生效，`style reset <id>` 撤）、`highlight <id>`、`shot [--full] [路径]`；`--app <id>` 显式指定应用。

**无显示服务环境**（SSH / CI，连 `mount_window` 都返回 `None`）：别硬跑应用，走 `@uitest` 的 `Tester` 直调断言，不经 socket：`t.frame()` 后 `t.dump_tree()` 摊 TSV、`t.shot(路径)` / `t.shot_full(路径)` 落 PNG，断言口径与服务端一致。

树里找不到控件 = 没挂上，先查模板与生成码，别先怀疑样式。

## 打包与发布

- `mng icons <png>`：1024×1024 源图派生全平台图标（ico + icns/iconset）。
- `mng package`：本平台打本平台包（mac .app+DMG+zip；win setup+zip；linux deb+AppImage）；`[package]` 键在 `mng new` 时已生成，**应用版本只改 `mng.toml` 的 `version`**（与 moon.mod 版本无关，工具会同步生成 appmeta 供应用自报）。
- `mng publish`：扫 `.mng/dist/` 生成 update.json 并上传 draft Release。
- release 要产物级剔除检查服务：删 `main.mbt` 的 `inspect_auto_install()` 行并去掉主包 `moon.pkg` 的 `inspector` import。

## 常见卡点

| 现象 | 处置 |
|---|---|
| `@ui` 报找不到包 | `moon add` 只写模块级依赖；用它的包要在自己的 `moon.pkg` 里写包级 import |
| 构建报目标不可用 | `moon.mod` 的 `preferred_target` 必须是 `"native"`，本库不出 wasm |
| `Missing main function` | moon 只把名为 `main.mbt` 的文件当程序入口 |
| 连不上检查通道 | 应用没起，或没经 `mng dev` / `mng mcp --run` 起过（没注入 `MNG_INSPECT`） |
| 检查 socket 不存在但应用活着 | socket 被占用时服务静默降级不监听——重启应用换新 socket |
| 改了模板行为没变 | 生成码形态不一致：重跑 `mng dev` 或 `mng build` 重生成再看 |
| `v-for 源须是 @base.ListStore` | 列表数据用 `let rows : @base.ListStore[T] = @base.ListStore::new()`，不是 Store 或 Array |
| 模板属性 `color="#f00"` 编译报错 | 样式字面量必须进 `<style>` 或 `class`——编译器强制，动态 `:属性="表达式"` 不受限 |
| 编辑器没有补全/诊断 | 装 VS Code 扩展 `tools/vscode-mng`；`mng-schema` 位不匹配时补全/诊断降级为空，高亮照用 |

## 版本基线

按 `mng@0.2.12`（mng-schema 1）与 `NoahLiu/native-gui@0.3.3` 核对：生成物清单经真跑 `mng new` 验证，命令面逐条对照 `mng -h` / `-h` 细目，mcp 三工具经 stdio JSON-RPC 实连验证；`references/components.md` 按 `docs/zh/components/` 全家族压缩，组件签名与 `.mooncakes` 权威面核对。工具升级后需同步复核本文件。
