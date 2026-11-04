# 应用开发者体验

本页讲「为什么」：工程长什么样、`moon add` 与 import 的两级、两处手工调整各自的原因，以及新手最常见的卡点。最短可跑路径（照着敲即可）见[五分钟上手教程](tutorial.md)；只想先看效果不写代码，见[先跑起来看看](experience.md)。

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

照[五分钟上手教程](tutorial.md) §3 把 `cmd/main/main.mbt` 替换为计数器程序、`moon run cmd/main` 跑出窗口，路径即打通。`mount_window` 在没有窗口后端或没有显示服务时返回 `None`，示例据此结构化退出——这是预期行为，不是故障。

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
- 克隆仓库跑示例：`showcase` 每页源码独立成文件、可直接抄改，入口见[先跑起来看看](experience.md) §二
