# 上手体验

从零建一个桌面应用：一个窗口、一个按钮、一个随点击自动刷新的计数；之后再过一遍工程机制、单文件组件与调试工具。前置只有构建环境——MoonBit 工具链与平台开发依赖，装法见[构建与运行](build.md) §1–§3；只想先看效果不装任何东西，走[跑预构建包](experience.md)。

## 1. 建工程

```sh
moon new my_app
cd my_app
moon add NoahLiu/native-gui
```

当前 `moon new` 模板的结构：根目录是库包（`my_app.mbt`、空的 `moon.pkg`），可执行入口在 `cmd/main/` 子包（`main.mbt` + `moon.pkg`）。两条硬规矩：

- moon 只把名为 `main.mbt` 的文件识别为程序入口——自建入口文件时保持这个文件名，否则报 `Missing main function`。
- 根目录的 `moon.pkg` 保持为空，依赖只在 `cmd/main/moon.pkg` 里声明。

`moon add NoahLiu/native-gui` 只写了**模块级**依赖（`moon.mod` 里的 import），作用是让库的包可被解析；**包级** import 要在用它的包自己的 `moon.pkg` 里另写。这一步不做，代码里的 `@ui` 会报「找不到包」——新手第一卡点，见 §6。`import` 决定代码里能引用哪些别名：`@ui` 提供控件、组件与声明式入口（`mount_window` 与各节点构造器），响应式状态 `@base`、样式类 `@style`、应用宿主 `@widget`、系统能力 `@sys` 等按需再加，17 个包的别名速查见[包结构](../reference/packages.md)。没 import 的包不编译不链接，不占二进制体积；标准库 `moonbitlang/core` 由 moon 自动注入，不需要写进 import；传递依赖由库自己声明，`moon add` 后自动进 `.mooncakes/`。

工程需要两处手工调整：

- **`moon.mod`：把 `preferred_target = "wasm"` 改为 `"native"`**——本库走原生 FFI，只支持 native 后端（不出 wasm）；不改的话构建直接报「包不支持当前目标」。模板默认已是 native 时跳过。

- **`cmd/main/moon.pkg` 整个替换为**——moon 的 DSL 格式，不是 JSON：

  ```
  import {
    "NoahLiu/native-gui/base",
    "NoahLiu/native-gui/widget" @widget,
    "NoahLiu/native-gui/ui",
    "NoahLiu/native-gui/style" @style,
  }

  pkgtype(kind: "executable")

  supported_targets = "native"
  ```

  这里为本页代码一次列全用到的包；实际按需写，最少只需 `ui` 一行。

## 2. 第一个窗口

把 `cmd/main/main.mbt` 整个替换为：

```moonbit
fn main {
  let count : @base.Store[Int] = @base.Store::new(0)
  let app = match @ui.mount_window(
    [
      @ui.col(
        [
          @ui.text("Hello, MoonBit!", class=[@style.text_heading]),
          @ui.button("点我", variant=@ui.Solid, on_click=fn() {
            count.update(fn(n) { n + 1 })
          }),
          @ui.bind_label(count, fn(n : Int) -> String { "已点 \{n} 次" }),
        ],
        padding=24.0,
        row_gap=12.0,
      ),
    ],
    title="教程示例",
    width=360,
    height=220,
  ) {
    None => {
      println("本平台没有窗口后端或没有显示服务")
      return
    }
    Some(a) => a
  }
  app.run()
}
```

```sh
moon run cmd/main
```

窗口出现：一个标题、一个按钮、一行「已点 0 次」；点按钮，数字自动 +1。这是**响应式状态**——`count` 一变，`bind_label` 自动刷新，无需「点击后改文本」的胶水代码。界面用 `@ui.col([...])` / `@ui.text(...)` / `@ui.button(...)` 等**节点构造器**声明成一棵树，交给 `mount_window` 一次挂载；`mount_window` 在没有窗口后端或没有显示服务时返回 `None`，示例据此结构化退出——这是预期行为，不是故障。

## 3. MoonBit 语法速览（只覆盖上面代码用到的）

| 语法 | 含义 |
|---|---|
| `fn main { ... }` | 程序入口 |
| `let count : @base.Store[Int] = ...` | 类型标注：`Store[Int]` 是一个整数状态盒 |
| `match expr { ... }` | 模式匹配，按分支取值（这里是拆 `Option`） |
| `None => ... / Some(a) => a` | 可选值的两态：`None` 缺省、`Some(x)` 有值 |
| `fn(n) { n + 1 }` | 匿名函数（lambda），作回调传入 |
| `on_click=fn() { ... }` | 命名实参：带默认值的参数按名传递 |
| `"已点 \{n} 次"` | 字符串插值，`\{表达式}` 嵌入任意值 |

**系统学 MoonBit**：官方[中文教程](https://docs.moonbitlang.com/zh-cn/latest/tutorial/index.html)（[English tutorial](https://docs.moonbitlang.com/en/latest/tutorial/index.html)）；偏好交互式边玩边学的，官方 [Tour of MoonBit](https://tour.moonbitlang.com) 在浏览器里逐课演练。

## 4. 单文件组件（.mng）

界面用声明式模板写、状态与逻辑用 MoonBit 写，两段合在一个 `.mng` 文件里，由 `mng` 工具预编译成 `.mbt` 再走 `moon build`——`moon check` 仍是唯一类型门禁。可跑的最小示例在 `examples/template-hello`。

### 装

仓库根执行（`moon install` 按**可执行包**逐个装）：

```sh
moon install ./tools/native-gui-tools/mng
moon install ./tools/native-gui-tools/mngui   # GUI 向导（裸 mng 自动拉起）
mng --version   # 应打印 mng 版本与 mng-schema 位
```

裸敲 `mng`：首跑自动做一轮环境体检（moon / Python / 编译器 / GTK，末尾真编译一个 hello 工程探针），全绿写 `~/.mng/ready` 并拉起 GUI 向导；之后裸 mng 直达向导。命令面提示中英随 locale。

### 起与改

- **从零起工程**：`mng new my_app`（或向导里点出来）——`cd my_app && moon run .` 或 `mng dev`。
- **既有工程加一页**：`mng new page pages/about`；**接模板**：`mng init` 写 `mng.toml`。
- **热更循环**：`mng dev` 起应用后改 `.mng` 保存——结构/样式/受限表达式亚秒 HOT，script / v-for 行模板 / 新符号 COLD 重启并自动回到改动页。

页面长这样：

```html
<script>
let count : @base.Store[Int] = @base.Store::new(0)
fn reset() { count.set(0) }
</script>
<template>
  <ui-col class="page">
    <ui-stepper v-model="count" max="10" />
    计数: {{ count }}
    <ui-button text="重置" @click="reset" />
  </ui-col>
</template>
<style>
.page { padding: 24px; row-gap: 8px; align-items: center; }
</style>
```

**深入**：完整文法（指令集 / 组件 props / `<style>` 章 / 生成码纪律）见[单文件组件（.mng）](./sfc)；命令参考与 `mng.toml` 全键表见 [mng 命令与配置](./mng)；热更分类与 VS Code 扩展见[热更与编辑器](./mng-dev)。编辑器体验装 VS Code 扩展 `tools/vscode-mng`（着色/补全/hover/跳转/诊断回投模板行列，见其 README）。


## 5. 内建 Inspector（调试界面）

库包 `NoahLiu/native-gui/inspector`（应用按需 import），挂一块只读面板进任意容器：

```moonbit
// moon.pkg: "NoahLiu/native-gui/inspector"
@inspector.inspector_panel(refresh_ms=500, auto=false, table_h=240.0, width=640.0)
```

三块读数：

- **控件树**：数据源 `@widget.a11y_last_frame()` 帧尾语义快照——与屏读同源，不可见子树整棵不在快照里，面板自己也出现在树里（预期）；按父链缩进，点行选中
- **选中读数**：id / parent / role / name / state / value / text / enabled / 窗口矩形
- **帧耗时**：`@base.paint_profile_summary()`（布局/绘制/上屏分段累计与最大帧），「重置统计」清零重算

刷新读的是「上一帧」快照——先动一动界面再点刷新，或开自动刷新（500ms 自重排延时表）。

**v2 编辑回灌**（「样式类」页签）：列出 `@style` 注册表的命名类（与 mngdev 样式热更同一个口），选中后改背景/文字/边框色/边框宽/圆角（base 与 `:hover` 各一套），「应用」即 `@style.define_class` 回灌——用了该类的控件下一帧换新样式；「还原此类」回本会话首次刷新类列表时的快照。空白输入 = 不改该字段；token 名与 `#hex` 都吃。编辑面收窄为五样，其余字段走模板源码或 `mng dev` 补丁。

## 6. 常见卡点

| 现象 | 原因与处置 |
|---|---|
| `@ui` 报「找不到包」 | `cmd/main/moon.pkg` 没写包级 import——`moon add` 只改 `moon.mod`（模块级），见 §1 |
| 构建报「包不支持 wasm / 目标不可用」 | `moon.mod` 的 `preferred_target` 还是模板默认的 wasm，改成 native，见 §1 |
| `Missing main function` | moon 只把名为 `main.mbt` 的文件当程序入口，见 §1 |
| `Parsing error: unexpected token {`（读 `moon.pkg`） | `moon.pkg` 是 DSL 格式，不是 JSON，别写 `{ ... }`；根目录的 `moon.pkg` 保持为空 |
| `Cannot inject the standard library moonbitlang/core: Cannot load the core file` | 工具链装残了（多为升级中断，`~/.moon/lib` 丢失）——重跑一遍官方安装脚本即可修复，与你的工程无关 |
| Linux 起手就红：缺 GTK 头文件 / `pep-0263` 报错 | 构建依赖没装齐、或 `python` 还指向 2.7——清单见[构建与运行](build.md) §2，处置见其 §6 前两行 |
| 程序直接退出、没有窗口 | `mount_window` 返回 `None`：无窗口后端或无显示服务（如无 X 的 SSH 会话）——结构化退出是预期行为 |
| 改完代码行为没变 | 改了 C 桩不一定触发重链，见[构建与运行](build.md) §9 |

构建期更深一层的失败（prebuild 解释器、workspace 传染、Windows 链接库、vendor 下载）见[构建与运行](build.md) §6，那里按现象给根因与处置。

## 7. 下一步

第一个应用跑起来之后，按目标选路径：

**想做得好看**——起窗默认自动探测一次系统深浅与主色（显式 `theme_apply` 过则不覆盖）；要持续跟随（系统切换界面即时变色），`follow_system_theme` 一行接上：

```moonbit
handle=fn(a : @widget.WindowHost) -> Unit {
  let _ = a.follow_system_theme(interval_ms=2000)
}
```

把 `@ui.text` / `@ui.button` 换成主题化形态（`button` 的 `variant` 四档、`tag` / `alert` / `card` 等）见 [组件总览](../components/index.md)；样式表（`Style` 值 + `hover` / `active` / `focus` 状态、过渡）见 [布局样式](layout.md)。

**想照着抄**——演示板就是素材库：左侧栏选页、右侧对着写，每页源码独立成文件（`examples/showcase/pages/*.mbt`），复制改写即可；下载与跑法见[跑预构建包](experience.md) §二。

**想系统学**——按面选文档：

- [场景总览](../cookbook/index.md)：场景教程——「我想让内容居中」「我要列表增删」「我要定时刷新」这类具体目标，每篇给可抄代码与注意事项
- [声明式与响应式](declarative.md)：节点树（`Node` / `mount_window`）描述界面、`Store` / `Signal` 绑定状态
- [布局样式](layout.md)：布局样式（`Style` 的 flex / padding / margin 字段，`@ui.col` / `@ui.row` 的散参数与 `class` 通道）
- [组件总览](../components/index.md)：全部控件与组件的入参与事件速查
- [系统能力总览](../capability/sys.md)：系统能力（`@sys`）——音量 / 应用查找 / 壁纸 / 显示器 / 剪贴板 / 电源 / 打印机…，统一 `Result` 语义

遇到工程类卡点（找不到包、目标不可用、入口文件名…）回本页 §6；构建期失败（prebuild、链接、依赖包）见[构建与运行](build.md) §6。

## 8. 给库贡献者的留言

这个库的目标是用 MoonBit 写原生桌面应用，现覆盖控件、图表、Markdown、内嵌 WebView 与系统能力，值得做的事还很多：

- **平台兼容**：Windows、Linux（Ubuntu XFCE/GNOME/KDE、Deepin）、macOS（Apple Silicon）三平台均已真机验证，按 `测试文档/测试用例.md` 同一份清单同步维护；新踩到的平台差异欢迎回报。
- **控件与能力**：还没封装的条目、各平台的适配坑，都欢迎从 issue 开始讨论。
- **文档与示例**：教程、组件文档、演示板每一页的例子，都欢迎改进。

参与没有门槛：提 issue 描述问题或想法、直接提 PR 都行。开始前只需记住三条——`moon check` 零错误零警告、`moon test` 全绿再提交，实测踩坑连同修复写进 [adaptation.md](https://github.com/lb091188/moonbit-native-gui/blob/master/experience/adaptation.md)，一个内聚改动一批提交。完整流程（新增示例模块、prebuild 链接托管）见[构建与运行](build.md)；FFI 规范见仓库 `.agents/skills/moonbit-c-binding/`。
