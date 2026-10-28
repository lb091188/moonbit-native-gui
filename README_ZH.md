# native-gui [![CI](https://github.com/lb091188/moonbit-native-gui/actions/workflows/ci.yml/badge.svg)](https://github.com/lb091188/moonbit-native-gui/actions/workflows/ci.yml)

> **来时的路**：本库最初是 [赵成(zcbenz)](https://github.com/zcbenz) 的 [Yue / libyue](https://github.com/yue/yue) 的 MoonBit 封装，布局沿用 [Yoga](https://github.com/facebook/yoga) 的 flexbox。如今两者都不再是运行时依赖，只作行为参考与语料来源。也感谢 [MoonBit](https://github.com/moonbitlang)。

[MoonBit](https://github.com/moonbitlang) 的**跨平台桌面 GUI 框架**——一套 MoonBit 代码直出 Windows 🟩 / Linux 🟩 / macOS 🟩 原生窗口，托盘、通知、快捷键、文件对话框等系统能力开箱即用，`moon add` 后零配置直接运行。三平台（Windows / Linux / macOS）同一套代码、同一份真机清单同步维护。

[English](README.md) | 简体中文

📚 **在线文档**：<https://moonbit-native-gui.pages.dev/>

![组件库演示板](./docs/public/images/showcase-main.png)
![Linux(XFCE)实机演示](./docs/public/images/showcase-anim-linux.webp) 
![Windows 实机演示](./docs/public/images/showcase-anim-windows.webp)

## 核心特色

**🖥 系统接口完备** —— 托盘、通知、全局快捷键、剪贴板、原生菜单、文件对话框、拖放、开机自启等桌面常用能力开箱即用，另有音量 / 电源 / 壁纸 / 显示器 / 打印机等系统查询能力

**🎨 渲染管线自绘** —— 不依赖 Skia 等重型图形引擎，控件观感跨平台一致，默认跟随系统强调色与明暗模式，主题可按需定制。

**📊 界面组件齐全** —— 基础布局组件、表单组件、可交互图表、Markdown 渲染；另有独立的 gui-media 音视频播放和展示能力、gui-web 基于系统 webview 的 web 渲染能力。

**📝 声明式 UI 与响应式状态** —— 界面以树描述，`mount_window` 一步挂载；状态放 `Store` / `Signal`，绑定点随数据自动刷新：

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

> `cd examples/showcase && moon run .` —— 演示板：基础组件、交互图标、系统接口。

## 生态坐标

MoonBit 生态的 GUI 能力各有分工：[MoUI](https://github.com/wzzc-dev/MoUI) 基于 Skia 渲染引擎，面向多端共享界面逻辑；而 native-gui 基于系统渲染，定位**桌面应用的一站式交付**，励志让系统能力开箱即用，常用组件跨平台统一，日常应用一站式完成。

## 包结构

`moon add NoahLiu/native-gui` 引入整个模块，MoonBit 只编译和链接你 import 的包，没用到的包不占二进制体积：

| 别名 | 内容 |
|---|---|
| `@base` | 平台无关基元：`Store` / `Signal` / `ListStore` 响应式内核、焦点栈、键码常量、帧末合并与账本 |
| `@shell` | 系统能力壳层：菜单栏 / 右键菜单、全局热键门面、托盘、通知、外部打开，加上事件循环调度器与只读平台探针 |
| `@widget` | 自绘控件宿主：布局树映射、命中与事件路由、绘制遍历、声明式 `Node`、浮层（图层/原生两档）、拖放、输入映射、`App` 泵 |
| `@ui` | 自绘控件与组件库：窗口挂载、标签 / 按钮、表单、显示、导航、日期、表格与虚拟列表、输入框、滚动、浮层、代码视图、声明式层 |
| `@render` | 光栅器：纯 MoonBit 软件光栅 + Cairo 后端；位图、画布、图像、PNG |
| `@text` | 文本层：字体族、字体、富文本与区间属性（Pango / DirectWrite） |
| `@theme` | 主题系统：色板派生与变更订阅 |
| `@icons` | 矢量图标系统 |
| `@sys` | 系统能力：自启动、空闲、子进程、环境、文件、JSON、对话框、浏览器历史 / 书签、最近文件、壁纸、音量、电源、打印机、显示器、窗口控制、应用查找 |
| `@input` | 编辑内核与键码 |
| `@win` | 平台窗口后端（Win32 / GTK3 的 C 桩）：快捷键、图标、输入法、消息框、通知、托盘、surface |
| `@dbus` | Linux D-Bus 桥：托盘 SNI、通知、logind / upower、媒体、网络、屏保 |
| `@chart` | 图表与横切交互层 |
| `@mdview` | Markdown 渲染视图 |
| `@style` | 样式层：样式表写成 MoonBit 值，含状态类与过渡 |

较重能力放在**独立模块**，可选

| 模块 | 内容 |
|---|---|
| `NoahLiu/gui-media` | 音视频引擎与播放器组件。 |
| `NoahLiu/gui-webview` | 内嵌 WebView（WebKitGTK / WebView2 / WKWebKit）。 |

## 快速开始

前置是 MoonBit 原生工具链，外加构建期的四样：C 工具链、Python 3、pkg-config，Linux 上再要 GTK3 一族开发包。三平台的安装清单、环境自检与「起手就红」的处置都在 **[docs/zh/build.md](docs/zh/build.md)「构建与运行」**——刚接触 MoonBit 的话，[在线文档](https://moonbit-native-gui.pages.dev/) 的五分钟上手教程覆盖工具链与第一个窗口。

在自己的工程里引入：

```sh
moon add NoahLiu/native-gui
```

想看效果就克隆仓库跑示例——`examples/` 下每个目录都是独立模块，**进目录 `moon run .`** 即可：

```sh
git clone https://github.com/lb091188/moonbit-native-gui.git
cd moonbit-native-gui/examples/hello   # 换成下表任一目录
MOON_WORK=off moon run .               # 绕开 workspace：只解析本示例的依赖闭包
```

`MOON_WORK=off` 让示例按注册表里已发布的库版本解析，媒体 / 探针 / ffmpeg 那几个成员的 prebuild 一概不跑，装齐 §2 那份最小依赖就能看效果；要连着库的改动一起跑就去掉它，代价是整套开发包（含 `libav*-dev`）都得在位。

| 目录 | 内容 |
|---|---|
| `examples/hello` | 最小窗口：一个原生窗口 + 基本控件 |
| `examples/showcase` | 全功能演示板：组件库、交互图标、图表、系统接口 |
| `examples/browser` | 浏览器演示 |
| `examples/audio` · `video` | 音视频播放器|
| `examples/headless-audio` | 无窗口、纯代码驱动播放 |

`moon run` 起手就报错——多半是构建依赖没装齐（Linux 的 GTK3 开发包、或 `python` 还指向 2.7）——对照 [docs/zh/build.md](docs/zh/build.md) §2 与 §6 处置。

## 平台支持

| 平台 | 状态 | 说明 |
|---|---|---|
| Ubuntu 24.04 | ✅ | XFCE / GNOME / KDE / Cinnamon |
| Deepin 23 / 25 | ✅ | |
| Deepin 20 / Debian 10 基线 | ❌ | **不作为支持目标**：本库侧已按 Python 3.7 口径跑通到编译，墙在 MoonBit 工具链自带 runtime 用的 `SYS_pidfd_open`（老 glibc 的冻结 syscall 表，升内核头补不上），坑与自救见 [docs/zh/build.md](docs/zh/build.md) §2 |
| Windows 10 / 11 | ✅ |  |
| macOS | ✅ | Apple Silicon  |

## 参与贡献

报平台兼容问题、补控件、补文档都欢迎。基本要求：

- **提交门禁**：库模块在 `gui/` 下 `moon check` + `moon test ui render text theme icons sys input win dbus chart mdview style base shell widget` 零错误零警告
- **经验留档**：实测坑与修复随代码记录，不要只留在提交信息里
- **小批次**：一个提交一个内聚改动，提交信息简短
- **进度与计划**：功能面全景与后续待做见[路线图](https://moonbit-native-gui.pages.dev/zh/roadmap)

[docs/zh/build.md](docs/zh/build.md)：从零装环境、构建与产物落点、预构建二进制、常见失败处置，以及链接参数托管与新增示例模块的机制。

## 许可

`native-gui` 以 [MIT 许可](LICENSE) 发布。第三方资产的授权与来源见 [THIRD-PARTY-NOTICES.md](docs/THIRD-PARTY-NOTICES.md)。

## 参考

- [MoonBit 文档](https://docs.moonbitlang.cn/)
- 本库从中学习过思路的项目：[Yue / libyue](https://github.com/yue/yue) · [Yoga](https://github.com/facebook/yoga)
