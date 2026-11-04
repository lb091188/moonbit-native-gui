# 五分钟上手教程

从零建一个桌面应用：一个窗口、一个按钮、一个随点击自动刷新的计数。

## 1. 准备工具

**MoonBit 工具链**（一行装好）：

```sh
# Linux / macOS
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
# Windows (PowerShell)
irm https://cli.moonbitlang.com/install/powershell.ps1 | iex
```

本库走原生 FFI，构建还需要 C 工具链与若干开发包（Linux 另需 GTK3 一族）——**三平台完整安装清单与环境自检见[构建与运行](build.md) §2**；只想先看效果不装任何东西，走[先跑起来看看](experience.md)。

## 2. 建工程

```sh
moon new my_app
cd my_app
moon add NoahLiu/native-gui
```

当前 `moon new` 模板的结构：根目录是库包（`my_app.mbt`、空的 `moon.pkg`），可执行入口在 `cmd/main/` 子包（`main.mbt` + `moon.pkg`）。工程需要两处手工调整：

- **`moon.mod`：把 `preferred_target = "wasm"` 改为 `"native"`**——本库走原生 FFI，只支持 native 后端；模板默认已是 native 时跳过。

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

  入口在 `cmd/main/main.mbt`——moon 只把名为 `main.mbt` 的文件识别为程序入口，自建入口文件时保持这个文件名。

  两处调整各自的原因、`moon add` 的模块级 / 包级 import 之分，见[应用开发者体验](dev-experience.md)。

## 3. 第一个窗口

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

窗口出现：一个标题、一个按钮、一行「已点 0 次」；点按钮，数字自动 +1。这是**响应式状态**——`count` 一变，`bind_label` 自动刷新，无需「点击后改文本」的胶水代码。界面用 `@ui.col([...])` / `@ui.text(...)` / `@ui.button(...)` 等**节点构造器**声明成一棵树，交给 `mount_window` 一次挂载；`mount_window` 在没有窗口后端或没有显示服务时返回 `None`，示例据此结构化退出。

## 4. MoonBit 语法速览（只覆盖上面代码用到的）

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

## 5. 下一步

第一个应用跑起来之后，按目标选路径：

**想做得好看**——起窗默认自动探测一次系统深浅与主色（显式 `theme_apply` 过则不覆盖）；要持续跟随（系统切换界面即时变色），`follow_system_theme` 一行接上：

```moonbit
handle=fn(a : @widget.WindowHost) -> Unit {
  let _ = a.follow_system_theme(interval_ms=2000)
}
```

把 `@ui.text` / `@ui.button` 换成主题化形态（`button` 的 `variant` 四档、`tag` / `alert` / `card` 等）见 [组件总览](../components/index.md)；样式表（`Style` 值 + `hover` / `active` / `focus` 状态、过渡）见 [布局样式](layout.md)。

**想照着抄**——演示板就是素材库：左侧栏选页、右侧对着写，每页源码独立成文件（`examples/showcase/pages/*.mbt`），复制改写即可；下载与跑法见[先跑起来看看](experience.md)。

**想系统学**——按面选文档：

- [场景总览](../cookbook/index.md)：场景教程——「我想让内容居中」「我要列表增删」「我要定时刷新」这类具体目标，每篇给可抄代码与注意事项
- [声明式与响应式](declarative.md)：节点树（`Node` / `mount_window`）描述界面、`Store` / `Signal` 绑定状态
- [布局样式](layout.md)：布局样式（`Style` 的 flex / padding / margin 字段，`@ui.col` / `@ui.row` 的散参数与 `class` 通道）
- [组件总览](../components/index.md)：全部控件与组件的入参与事件速查
- [系统能力总览](../capability/sys.md)：系统能力（`@sys`）——音量 / 应用查找 / 壁纸 / 显示器 / 剪贴板 / 电源 / 打印机…，统一 `Result` 语义

**遇到问题**——工程类卡点（找不到包、目标不可用、入口文件名…）见[应用开发者体验](dev-experience.md)；构建期失败（prebuild、链接、依赖包）见[构建与运行](build.md) §6。

## 6. 给库贡献者的留言

这个库的目标是用 MoonBit 写原生桌面应用，现覆盖控件、图表、Markdown、内嵌 WebView 与系统能力，值得做的事还很多：

- **平台兼容**：Windows、Linux（Ubuntu XFCE/GNOME/KDE、Deepin）、macOS（Apple Silicon）三平台均已真机验证，按 `测试文档/测试用例.md` 同一份清单同步维护；新踩到的平台差异欢迎回报。
- **控件与能力**：还没封装的条目、各平台的适配坑，都欢迎从 issue 开始讨论。
- **文档与示例**：教程、组件文档、演示板每一页的例子，都欢迎改进。

参与没有门槛：提 issue 描述问题或想法、直接提 PR 都行。开始前只需记住三条——`moon check` 零错误零警告、`moon test` 全绿再提交，实测踩坑连同修复写进 [adaptation.md](https://github.com/lb091188/moonbit-native-gui/blob/master/experience/adaptation.md)，一个内聚改动一批提交。完整流程（新增示例模块、prebuild 链接托管）见[构建与运行](build.md)；FFI 规范见仓库 `.agents/skills/moonbit-c-binding/`。
