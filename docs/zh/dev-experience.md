# 应用开发者体验

从零到第一个窗口的完整路径：一台新机器，五分钟内用 MoonBit 和 native-gui 写出一个原生桌面应用。面向没用过 MoonBit 的应用开发者；只想先看效果、不写代码的，看[体验文档](experience.md)的预构建包。

## 1. 装工具链

MoonBit 工具链一行装好：

```sh
# Linux / macOS
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
# Windows (PowerShell)
irm https://cli.moonbitlang.com/install/powershell.ps1 | iex
```

本库走原生 FFI，构建还需要 C 工具链，外加 Python 3（Linux 另需 GTK3 一族开发包）：三平台安装清单与环境自检见[构建与运行](build.md) §2；Windows 上 moon 自动定位 MSVC，普通 shell 直接可用。

## 2. 建工程

```sh
moon new my_app
cd my_app
moon add NoahLiu/native-gui
```

当前 `moon new` 模板的结构：根目录是库包（`my_app.mbt`、空的 `moon.pkg`），可执行入口在 `cmd/main/` 子包（`main.mbt` + `moon.pkg`）。

`moon add` 只写了**模块级**依赖（`moon.mod` 里的 import），作用是让库的包可被解析；**包级** import 要在用它的包自己的 `moon.pkg` 里另写。这一步不做，代码里的 `@ui` 会报「找不到包」——这是新手第一卡点，见 §3 ①。

## 3. 两处手工调整

**① `cmd/main/moon.pkg`**——补上要用的包并声明目标平台（moon 的 DSL 格式，不是 JSON）：

```
import {
  "NoahLiu/native-gui/ui" @ui,
}

pkgtype(kind: "executable")

supported_targets = "native"
```

`import` 决定代码里能引用哪些别名：`@ui` 提供控件、组件与声明式入口（`mount_window` 与各节点构造器）。按需再加——响应式状态 `@base`、样式类 `@style`、应用宿主 `@widget`、系统能力 `@sys`——17 个包的别名速查见[包结构](packages.md)。没 import 的包不编译不链接，不占二进制体积。标准库 `moonbitlang/core` 由 moon 自动注入，不需要写进 import。

**② `moon.mod`**——把 `preferred_target = "wasm"` 改为 `"native"`。本库所有包只支持 native 后端；不改的话构建直接报「包不支持当前目标」。

传递依赖不用管：它们由库自己声明，`moon add` 后自动进 `.mooncakes/`，无需手动添加。

## 4. 第一个窗口

把 `cmd/main/main.mbt` 替换为：

```moonbit
fn main {
  let app = match @ui.mount_window(
    [@ui.text("Hello, MoonBit!", font_size=18.0)],
    title="Hello, MoonBit!",
    width=400,
    height=300,
  ) {
    None => {
      // 本平台没有窗口后端或没有显示服务
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

窗口出现，路径打通。

## 常见卡点

| 现象 | 原因与处置 |
|---|---|
| `@ui` 报「找不到包」 | `cmd/main/moon.pkg` 没写包级 import——`moon add` 只改 `moon.mod`（模块级），见 §3 ① |
| 构建报「包不支持 wasm / 目标不可用」 | `moon.mod` 的 `preferred_target` 还是模板默认的 wasm，改成 native，见 §3 ② |
| `Missing main function` | moon 只把名为 `main.mbt` 的文件当程序入口——模板已放在 `cmd/main/`，自建入口文件时保持这个文件名 |
| `Parsing error: unexpected token {`（读 `moon.pkg`） | `moon.pkg` 是 DSL 格式，不是 JSON，别写 `{ ... }`；根目录的 `moon.pkg` 保持为空，依赖只在 `cmd/main/moon.pkg` 里声明 |
| `Cannot inject the standard library moonbitlang/core: Cannot load the core file` | 工具链装残了（多为升级中断，`~/.moon/lib` 丢失）——重跑一遍官方安装脚本即可修复，与你的工程无关 |
| Linux 起手就红：缺 GTK 头文件 / `pep-0263` 报错 | 构建依赖没装齐，或 `python` 还指向 2.7——对照[构建与运行](build.md) §2 与 §6 |
| 程序直接退出、没有窗口 | `mount_window` 返回 `None`：无窗口后端或无显示服务（如无 X 的 SSH 会话）——结构化退出是预期行为 |

## 下一步

- [五分钟上手教程](tutorial.md)：MoonBit 语法速览 + 点击计数器（`Store` 响应式的最小形态）
- [组件速查](components.md) · [声明式与响应式](declarative.md) · [布局样式](layout.md) · [系统能力总览](system-capabilities.md)
- 克隆仓库跑示例：`showcase` 每页源码独立成文件、可直接抄改，入口见[体验文档](experience.md) §二
