# native-gui [![CI](https://github.com/lb091188/moonbit-native-gui/actions/workflows/ci.yml/badge.svg)](https://github.com/lb091188/moonbit-native-gui/actions/workflows/ci.yml)

> **来时的路**：本库最初是 [赵成(zcbenz)](https://github.com/zcbenz) 的 [Yue / libyue](https://github.com/yue/yue) 的 MoonBit 封装，如今`libyue`、`yoga`不再是运行时依赖，只作行为参考。感谢 libyue、yoga、[MoonBit](https://github.com/moonbitlang)。

[MoonBit](https://github.com/moonbitlang) 的**跨平台桌面 GUI 框架** —— 一套 MoonBit 代码直出 Windows 🟩 / Linux 🟩 / macOS 🟩 原生窗口，托盘、通知、快捷键、文件对话框等系统能力开箱即用，`moon add` 后零配置直接运行。

[English](README.md) | 简体中文

📚 [**在线文档**](https://moonbit-native-gui.pages.dev/zh/)

📦 **零环境体验**：三平台预构建演示包（hello / showcase / browser / audio / video）在 [GitHub Releases](https://github.com/lb091188/moonbit-native-gui/releases)，解压即跑；每个演示的体验点与操作路径见[体验文档](https://moonbit-native-gui.pages.dev/zh/experience)。

![组件库演示板](./docs/public/images/showcase-main.png)
![Linux(XFCE)实机演示](./docs/public/images/showcase-anim-linux.webp) 
![Windows 实机演示](./docs/public/images/showcase-anim-windows.webp)

## 核心特色

**🖥 系统接口完备** —— 托盘、通知、全局快捷键、剪贴板、原生菜单、文件对话框、拖放、开机自启等桌面常用能力开箱即用，另有音量 / 电源 / 壁纸 / 显示器 / 打印机等系统查询能力

**🎨 渲染管线自绘** —— 不依赖 Skia 等重型图形引擎，控件观感跨平台一致，默认跟随系统强调色与明暗模式，主题可按需定制。

**📊 界面组件齐全** —— 基础布局组件、表单组件、可交互图表、Markdown 渲染；另有独立的 gui-media 音视频播放和展示能力、gui-webview 基于系统 webview 的 web 渲染能力。

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

MoonBit 生态的 GUI 能力各有分工：[MoUI](https://github.com/wzzc-dev/MoUI) 基于 Skia 渲染引擎，面向多端共享界面逻辑；而 native-gui 基于系统渲染，定位**桌面应用的一站式交付**，力求让系统能力开箱即用，常用组件跨平台统一，日常应用一站式完成。

## 快速开始

三条路，与[体验文档](https://moonbit-native-gui.pages.dev/zh/experience)同一套分法：

**① 真体验：预构建包** —— [GitHub Releases](https://github.com/lb091188/moonbit-native-gui/releases) 的「Binaries」按平台取一个 zip，解压即跑；体验点与操作路径见[体验文档](https://moonbit-native-gui.pages.dev/zh/experience)。

**② 基于库做应用** —— ②③ 需要开发环境：MoonBit 原生工具链 + C 工具链 + Python 3 + pkg-config（Linux 再加 GTK3 一族开发包），安装清单见[构建与运行](https://moonbit-native-gui.pages.dev/zh/build)。自己的工程里引入：

```sh
moon add NoahLiu/native-gui
```

想看效果就克隆仓库跑示例——`examples/` 下每个目录都是独立模块，进目录 `moon run .` 即可：

```sh
git clone https://github.com/lb091188/moonbit-native-gui.git
cd moonbit-native-gui/examples/hello   # 换成下表任一目录
MOON_WORK=off moon run .               # 按注册表已发布的库版本解析；连着库改动跑就去掉它
```

| 目录 | 内容 |
|---|---|
| `examples/hello` | 最小窗口：一个原生窗口 + 基本控件 |
| `examples/showcase` | 全功能演示板：组件库、交互图标、图表、系统接口 |
| `examples/browser` | 内嵌 WebView 浏览器（额外依赖 `gui-webview`）|
| `examples/audio` · `video` | 音视频播放器（额外依赖 `gui-media`，需 ffmpeg）|
| `examples/headless-audio` | 无窗口、纯代码驱动播放 |

`moon run` 起手就报错——多半是构建依赖没装齐，对照[构建与运行](https://moonbit-native-gui.pages.dev/zh/build)处置。

**③ 改库 / 参与开发** —— 工具链与依赖安装、构建门禁、测试口径与常见失败处置全在[构建与运行](https://moonbit-native-gui.pages.dev/zh/build)；包的组成见[包结构](https://moonbit-native-gui.pages.dev/zh/packages)。

## 平台支持

| 平台 | 状态 | 说明 |
|---|---|---|
| Ubuntu 24.04 | ✅ | XFCE / GNOME / KDE / Cinnamon |
| Deepin 23 / 25 | ✅ | |
| Deepin 20 / Debian 10 基线 | ❌ | **不作为支持目标**：本库侧已按 Python 3.7 口径跑通到编译，墙在 MoonBit 工具链自带 runtime 用的 `SYS_pidfd_open`（老 glibc 的冻结 syscall 表，升内核头补不上），坑与自救见[构建与运行](https://moonbit-native-gui.pages.dev/zh/build) |
| Windows 10 / 11 | ✅ |  |
| macOS | ✅ | Apple Silicon  |

## 参与贡献

报平台兼容问题、补控件、补文档都欢迎。基本要求：

- **提交门禁**：库模块在 `gui/` 下 `moon check` + `moon test ui render text theme icons sys input win dbus chart mdview style base shell widget` 零错误零警告
- **经验留档**：实测坑与修复随代码记录，不要只留在提交信息里
- **小批次**：一个提交一个内聚改动，提交信息简短
- **进度与计划**：功能面全景与后续待做见[路线图](https://moonbit-native-gui.pages.dev/zh/roadmap)

[构建与运行](https://moonbit-native-gui.pages.dev/zh/build)：从零装环境、构建与产物落点、预构建二进制、常见失败处置，以及链接参数托管与新增示例模块的机制。

## 许可

`native-gui` 以 [MIT 许可](LICENSE) 发布。第三方资产的授权与来源见 [THIRD-PARTY-NOTICES.md](docs/THIRD-PARTY-NOTICES.md)。

## 参考

- [MoonBit 文档](https://docs.moonbitlang.cn/)
- 本库从中学习过思路的项目：[Yue / libyue](https://github.com/yue/yue) · [Yoga](https://github.com/facebook/yoga)
