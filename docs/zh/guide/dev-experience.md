# 应用开发者体验

最短可跑路径见[五分钟上手教程](tutorial.md)；只想先看效果不写代码，见[先跑起来看看](experience.md)。

## 1. 工程长什么样

`moon new my_app` 给出的模板：根目录是库包（`my_app.mbt`、空的 `moon.pkg`），可执行入口在 `cmd/main/` 子包（`main.mbt` + `moon.pkg`）。两条硬规矩：

- moon 只把名为 `main.mbt` 的文件识别为程序入口——自建入口文件时保持这个文件名，否则报 `Missing main function`。
- 根目录的 `moon.pkg` 保持为空，依赖只在 `cmd/main/moon.pkg` 里声明。

## 2. moon add 与 import 是两回事

`moon add NoahLiu/native-gui` 只写了**模块级**依赖（`moon.mod` 里的 import），作用是让库的包可被解析；**包级** import 要在用它的包自己的 `moon.pkg` 里另写。这一步不做，代码里的 `@ui` 会报「找不到包」——新手第一卡点，见下文第 1 条。

`import` 决定代码里能引用哪些别名：`@ui` 提供控件、组件与声明式入口（`mount_window` 与各节点构造器）。按需再加——响应式状态 `@base`、样式类 `@style`、应用宿主 `@widget`、系统能力 `@sys`——17 个包的别名速查见[包结构](../reference/packages.md)。没 import 的包不编译不链接，不占二进制体积。标准库 `moonbitlang/core` 由 moon 自动注入，不需要写进 import。传递依赖不用管：它们由库自己声明，`moon add` 后自动进 `.mooncakes/`。

## 3. 两处手工调整

**① `cmd/main/moon.pkg`**——补上要用的包并声明目标平台（moon 的 DSL 格式，不是 JSON）：

```
import {
  "NoahLiu/native-gui/ui" @ui,
}

pkgtype(kind: "executable")

supported_targets = "native"
```

**② `moon.mod`**——把 `preferred_target = "wasm"` 改为 `"native"`。本库所有包只支持 native 后端（原生 FFI，不出 wasm）；不改的话构建直接报「包不支持当前目标」。

## 4. 第一个窗口

照[五分钟上手教程](tutorial.md) §3 替换 `cmd/main/main.mbt` 并 `moon run cmd/main`。`mount_window` 在没有窗口后端或没有显示服务时返回 `None`，示例据此结构化退出——这是预期行为，不是故障。

## 5. 单文件组件（.mng）

界面用声明式模板写、状态与逻辑用 MoonBit 写，两段合在一个 `.mng` 文件里，由 `mng` 工具预编译成 `.mbt` 再走 `moon build`——`moon check` 仍是唯一类型门禁。完整语义见 `proposals/native-template.md`；可跑的最小示例在 `examples/template-hello`。

### 装

仓库根执行（工具随本仓分发）：

```sh
moon install ./tools/native-gui-tools/mng
mng --version   # 应打印 mng 0.2.8 与 mng-schema 1
```

命令面提示与错误随 `LC_ALL` / `LC_MESSAGES` / `LANG` 中英切换（`zh` 前缀走中文）；环境变量缺席时读系统 UI 语言（Windows），仍未知则缺省中文；`dev` 运行期 watch 日志与编译器诊断恒为中文。

编辑器体验装 VS Code 扩展 `tools/vscode-mng`（着色/补全/hover/跳转/诊断，见其 README）。

### 起

- **从零起工程**：`mng new my_app`（在 native-gui workspace 内生成时依赖版本现读；显式写法 `mng new app my_app`）生成可跑最小工程——`cd my_app && moon run .`。
- **既有工程加一页**：`mng new page pages/about` 生成单页 `.mng` 样板（父目录不存在会现建）。
- **既有工程接模板**：`mng init` 写 `mng.toml`。

### 页面长什么样

```html
<script>
let count : @base.Store[Int] = @base.Store::new(0)
let name : @base.Store[String] = @base.Store::new("")

fn reset() {
  count.set(0)
  name.set("")
}
</script>
<template>
  <ui-col class="page">
    <ui-input v-model="name" placeholder="你的名字" width="220.0" />
    你好, {{ name }}！
    <ui-stepper v-model="count" max="10" />
    计数: {{ count }}
    <ui-button text="重置" @click="reset" />
  </ui-col>
</template>
<style>
  .page { padding: 24px; row-gap: 8px; align-items: center; }
</style>
```

要点：

- 指令集：插值 `{{ }}`、`:attr` 动态属性、`@event` 事件、`v-model`（直传 Store）、`v-if`/`v-else-if`/`v-else`、`v-show`、`v-for`（源须 `@base.ListStore` keyed，建议 `:key="it.id"`）；单根模板。
- 组件标签：`ui-*` 内置表；同包组件写 `fn 组件名` 直接用；跨包 `let 组件名 = @包.函数`。
- 带参组件：script 首个只有签名没有函数体的 `fn` 头就是 props（必填走位置参、可选 `名? : 类型 = 默认值`）。
- 样式进 `<style>` 段（类选择器 + `var(--令牌)` + 交互态/深浅档）；模板属性里写样式字面量会编译报错——必须进 `<style>` 或 `class`。
- 表达式是 MoonBit 原样拼接：字符串拼接用插值 `"\{x}"` 或 `{{ }}`，不要写 `"a" + 1`。

### dev / build

- `mng init` 在模块根写 `mng.toml`（templates / build / run / app-id / theme）；`mng dev` / `mng build` 无参时向上找它，找不到按 `moon.mod`/`moon.work` 推默认。
- `mng dev`：watch 全工程模板 + 工程源文件（`.mbt`/`moon.pkg`/`moon.mod`/`moon.work`）+ 主题文件；首轮生成 dev 形态 `<stem>.gen.mbt` 到模板同包并起应用。改动分类：结构/类/样式值/受限表达式亚秒 HOT；script、v-for 行模板、新符号回 COLD 重启并自动回到改动页；运行中新增 `.mng` 自动生成并入构建，删除会清（或提示）生成码。热更面在库包 `@mngdev`——模板所在包 `moon.pkg` 加一行 `import "NoahLiu/native-gui/mngdev" @mngdev` 即可（`mng new` 生成时已写好），应用不再复制任何 dev 面 `.mbt`。
- `mng build`：无参按 `mng.toml` 生成全工程**生产形态**生成码（零 dev 痕迹）；`mng build <input> -o <out>` 编译单文件。dev 与生产形态共用同一条 `<stem>.gen.mbt`，会互相覆盖——提交前选一种并保持一致（CI 对两形态各比一遍，匹配任一即过）。

### 生成码怎么接

生成码落模板同包：`<stem>.gen.mbt` 提供 `pub fn <stem>() -> @widget.Node`，像普通函数一样接进路由或窗口：

```moonbit
@ui.mount_window([hello()], title="Template Hello", width=420, height=360)
```

生成码建议提交仓库（消费者零工具链依赖）；它带 `// GENERATED … DO NOT EDIT` 头，别手改——改了模板重新生成即可。

### 常见错误

| 现象 | 原因与处置 |
|---|---|
| `v-for 源须是 @base.ListStore` | 源给了 Store/Signal 或普通变量——列表用 `let rows : @base.ListStore[T] = @base.ListStore::new()` |
| `v-for 与 v-if 不写在同一元素` | 用容器隔开（外层 v-if 包 v-for，或行内 v-if） |
| `String + Int` 之类的类型错 | 表达式原样拼接——拼接用 `{{ }}` 插值或 `"\{x}"`，MoonBit 的 `+` 不拼非串 |
| `moon check` 报生成码与重生成不一致 | 生成码与模板不同步——重跑 `mng dev`（dev 形态）或 `mng build`（生产形态）再提交 |
| 同包生成函数冲突 | 两个 `.mng` 撞名（生成函数名取文件 stem）——改文件名 |
| HOT 没生效走了 COLD | v-for 行模板 / script / 新符号本来就走 COLD；日志 `[HOT→COLD]` 带原因 |

## 常见卡点

| 现象 | 原因与处置 |
|---|---|
| `@ui` 报「找不到包」 | `cmd/main/moon.pkg` 没写包级 import——`moon add` 只改 `moon.mod`（模块级），见 §2 |
| 构建报「包不支持 wasm / 目标不可用」 | `moon.mod` 的 `preferred_target` 还是模板默认的 wasm，改成 native，见 §3 ② |
| `Missing main function` | moon 只把名为 `main.mbt` 的文件当程序入口，见 §1 |
| `Parsing error: unexpected token {`（读 `moon.pkg`） | `moon.pkg` 是 DSL 格式，不是 JSON，别写 `{ ... }`；根目录的 `moon.pkg` 保持为空 |
| `Cannot inject the standard library moonbitlang/core: Cannot load the core file` | 工具链装残了（多为升级中断，`~/.moon/lib` 丢失）——重跑一遍官方安装脚本即可修复，与你的工程无关 |
| Linux 起手就红：缺 GTK 头文件 / `pep-0263` 报错 | 构建依赖没装齐、或 `python` 还指向 2.7——清单见[构建与运行](build.md) §2，处置见其 §6 前两行 |
| 程序直接退出、没有窗口 | `mount_window` 返回 `None`：无窗口后端或无显示服务（如无 X 的 SSH 会话）——结构化退出是预期行为 |
| 改完代码行为没变 | 改了 C 桩不一定触发重链，见[构建与运行](build.md) §9 |

构建期更深一层的失败（prebuild 解释器、workspace 传染、Windows 链接库、vendor 下载）见[构建与运行](build.md) §6，那里按现象给根因与处置。

## 下一步

- [五分钟上手教程](tutorial.md)： MoonBit 语法速览 + 点击计数器（`Store` 响应式的最小形态）
- [组件总览](../components/index.md) · [声明式与响应式](declarative.md) · [布局样式](layout.md) · [系统能力总览](../capability/sys.md)
- 想用模板写界面：[单文件组件（.mng）](dev-experience.md#_5-单文件组件-mng)（§5）与 `examples/template-hello`
- 克隆仓库跑示例：`showcase` 每页源码独立成文件、可直接抄改，入口见[先跑起来看看](experience.md) §二
