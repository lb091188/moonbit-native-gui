# 文档索引

**native-gui**：MoonBit 的跨平台桌面 GUI 框架。一套代码直出 Windows 🟩 / Linux 🟩 / macOS 🟩 原生窗口，系统能力开箱即用，`moon add` 后零配置；三平台同一份真机清单同步维护，mooncakes 包名 `NoahLiu/native-gui`。

## 包结构

`moon add NoahLiu/native-gui` 一次引入整个模块，MoonBit 只编译和链接你 import 的包，没 import 的不进二进制：

| `moon.pkg` 里的导入 | 别名 | 内容 |
|---|---|---|
| `NoahLiu/native-gui/base` | `@base` | 平台无关基元：`Store` / `Signal` / `ListStore`、焦点栈、键码、帧末合并与账本 |
| `NoahLiu/native-gui/shell` | `@shell` | 系统能力壳层：菜单、全局热键门面、托盘、通知、外部打开、事件循环调度器与只读平台探针 |
| `NoahLiu/native-gui/widget` | `@widget` | 自绘控件宿主：布局树映射、命中与事件路由、绘制遍历、声明式 `Node`、浮层两档、拖放、输入映射、`App` 泵 |
| `.../native-gui/ui` | `@ui` | 自绘控件与组件库：窗口挂载、标签 / 按钮、表单、显示、导航、日期、表格与虚拟列表、输入框、滚动、浮层、代码视图、声明式层 |
| `.../native-gui/render` | `@render` | 画布与图像：自绘画布、位图、图像与 PNG |
| `.../native-gui/text` | `@text` | 文本层：字体族、字体、富文本与区间属性（Pango / DirectWrite） |
| `.../native-gui/theme` | `@theme` | 主题系统：色板派生与变更订阅 |
| `.../native-gui/icons` | `@icons` | 矢量图标系统 |
| `.../native-gui/sys` | `@sys` | 系统能力：自启动、空闲、子进程、环境、文件、JSON、对话框、浏览器历史 / 书签、最近文件、壁纸、音量、电源、打印机、显示器、窗口控制、应用查找 |
| `.../native-gui/input` | `@input` | 编辑内核与键码 |
| `.../native-gui/win` | `@win` | 平台窗口层：窗口、快捷键、图标、输入法、消息框、通知、托盘 |
| `.../native-gui/dbus` | `@dbus` | Linux D-Bus 调用：托盘 SNI、通知、logind / upower、媒体、网络、屏保等系统服务 |
| `.../native-gui/chart` | `@chart` | 图表与横切交互层 |
| `.../native-gui/mdview` | `@mdview` | Markdown 渲染视图 |
| `.../native-gui/style` | `@style` | 样式层：样式表写成 MoonBit 值，含状态类与过渡 |
| `.../native-gui/i18n` | `@i18n` | 界面文案多语言：TOML 词表查译 / 插值 / 复数，可订阅语言切换；内置控件文案可本地化（随包中英两套） |
| `.../native-gui/router` | `@router` | 单窗口页面路由：路由树 + 每层选中键 + link 绑定，任意组件接 `on_link` 导航 |

较重的可选能力放在独立模块，`moon add NoahLiu/native-gui` 不会把它们拉进来：

| 模块 | 内容 |
|---|---|
| `NoahLiu/gui-media` | 音视频引擎与播放器组件。 |
| `NoahLiu/gui-webview` | 内嵌 WebView（WebKitGTK / WebView2 / WKWebView），定位是「浏览器表现力 + 原生能力配合」，见 [webview.md](webview.md)。 |

一句话记住边界：没 import 的包不进你的二进制；WebView 与媒体引擎住在独立模块里，默认依赖根本没有它们。

## 演示

示例由浅入深——`examples/` 下每个目录都是独立模块，进目录 `moon run .` 即可：

```sh
cd examples/hello && MOON_WORK=off moon run .
```

`MOON_WORK=off` 只解析该示例自己的依赖，不必装齐全仓的开发包；留在 workspace 里跑则要按 [build.md](build.md) §2 装齐全部开发包——缺 GTK3 一族，或 `python` 仍指向 2.7，都会让 native 构建起手就红（处置见同页 §6）。

- `examples/hello` —— 最小窗口
- `examples/showcase` —— 完整演示板
- `examples/browser` —— 内嵌 WebView 浏览器

`examples/showcase` 覆盖组件库全部家族、图表、代码与文档视图、系统集成与过渡效果，并带一页只读的系统能力探测。每页源码独立成文件（`examples/showcase/pages/*.mbt`），可直接复制改用。各组件截图：

![基础组件](/images/showcase-basic.png)

![表单组件](/images/showcase-form.png)

![数据展示](/images/showcase-data.png)

![代码与文档](/images/showcase-code.png)

![系统集成](/images/showcase-system.png)

## 分流

| 文档 | 内容 |
|---|---|
| [dev-experience.md](dev-experience.md) | 应用开发者体验：从零到第一个窗口——装工具链、建工程（`moon new` 模板的两处调整）、运行与常见卡点 |
| [tutorial.md](tutorial.md) | 五分钟上手：装工具链、建工程、做出第一扇带点击计数的窗口 |
| [components.md](components.md) | 组件速查（`@ui`）：各控件构造器的入口签名与用途，按家族分组 |
| [declarative.md](declarative.md) | 声明式层与响应式：节点树与 `mount_window`、`Store` / `Signal`、`for_list` / `when`、原位替换 |
| [layout.md](layout.md) | 布局：Flexbox 布局口径与 `@style` 的 `Style` 字段集、`class` 通道 |
| [build.md](build.md) | 构建与运行：从零装依赖（三平台清单 + 环境自检）、构建命令与产物落点、预构建二进制现状、常见失败处置；面向库开发的机制细节在后半段 |
| [packages.md](packages.md) | 包结构：17 个包别名与两个独立模块的内容一览 |
| [roadmap.md](roadmap.md) | 对外路线图：功能点、功能描述、计划版本、开发与测试状态；附平台兼容面、承诺与版本、明确不做 |
| [autostart.md](autostart.md) | 开机自启：Linux 写 XDG .desktop、Windows 写 HKCU Run 键，统一 `is_enabled` / `enable` / `disable` |
| [experience.md](experience.md) | 体验文档：真体验——预构建包直接跑、克隆仓库跑示例；写应用与改库分别引导到应用开发者体验与构建与运行 |
| [system-capabilities.md](system-capabilities.md) | 系统能力总览（`@sys`）：音量、应用查找、色温、壁纸、显示器、窗口管理、剪贴板监听、系统信息、打印机、最近文件、浏览器历史等，统一 `Result` 语义；含子进程与 D-Bus 调用层两块共享基建 |
| [THIRD-PARTY-NOTICES.md](../THIRD-PARTY-NOTICES.md) | 第三方授权与来源：随源码入库的资产、我们自编或重打包挂在 Release 上的二进制、以及随之而来的分发义务 |

对内的工程记录——平台适配经验、Linux 托盘设计、前端化设计、GPU 架构决策——在仓库的 [`proposals/`](https://github.com/lb091188/moonbit-native-gui/tree/master/proposals) 目录，不在本站发布。

项目总览与快速开始入口见仓库根 [README_ZH.md](https://github.com/lb091188/moonbit-native-gui/blob/master/README_ZH.md)。
