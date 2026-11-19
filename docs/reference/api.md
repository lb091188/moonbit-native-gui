# 包结构与 API 参考

`moon add NoahLiu/native-gui` 引入整个模块，MoonBit 只编译和链接你 import 的包，没用到的包不占二进制体积。

完整 API 参考在 mooncakes.io，由源码 doc 注释自动生成：每个包的类型与函数签名、注释说明、源码行链接，页面可切换历史版本。下表别名直通对应包：

**[打开 native-gui API 参考 ↗](https://mooncakes.io/docs/NoahLiu/native-gui)**

| 别名 | 内容 |
|---|---|
| [@base](https://mooncakes.io/docs/NoahLiu/native-gui/base) | 平台无关基元：`Store` / `Signal` / `ListStore` 响应式内核、焦点栈、键码常量、帧末合并与账本 |
| [@shell](https://mooncakes.io/docs/NoahLiu/native-gui/shell) | 系统能力壳层：菜单栏 / 右键菜单、全局热键门面、托盘、通知、外部打开，加上事件循环调度器与只读平台探针 |
| [@widget](https://mooncakes.io/docs/NoahLiu/native-gui/widget) | 控件宿主：布局树映射、命中与事件路由、绘制遍历、声明式 `Node`、浮层（图层/原生两档）、拖放、输入映射、`WindowHost` 泵 |
| [@ui](https://mooncakes.io/docs/NoahLiu/native-gui/ui) | 控件与组件库：窗口挂载、标签 / 按钮、表单、显示、导航、日期、表格与虚拟列表、输入框、滚动、浮层、代码视图、声明式层（见[组件总览](../components/index.md)） |
| [@render](https://mooncakes.io/docs/NoahLiu/native-gui/render) | 画布与图像：画布、位图、图像与 PNG（见[画布](../components/canvas.md)） |
| [@text](https://mooncakes.io/docs/NoahLiu/native-gui/text) | 文本层：字体族、字体、富文本与区间属性（Pango / DirectWrite） |
| [@theme](https://mooncakes.io/docs/NoahLiu/native-gui/theme) | 主题系统：色板派生与变更订阅 |
| [@icons](https://mooncakes.io/docs/NoahLiu/native-gui/icons) | 矢量图标系统 |
| [@sys](https://mooncakes.io/docs/NoahLiu/native-gui/sys) | 系统能力：自启动、空闲、子进程、环境、文件、JSON、对话框、浏览器历史 / 书签、最近文件、壁纸、音量、电源、打印机、显示器、窗口控制、应用查找（见[系统能力总览](../capability/sys.md)） |
| [@input](https://mooncakes.io/docs/NoahLiu/native-gui/input) | 编辑内核与键码 |
| [@win](https://mooncakes.io/docs/NoahLiu/native-gui/win) | 平台窗口层：窗口、快捷键、图标、输入法、消息框、通知、托盘 |
| [@dbus](https://mooncakes.io/docs/NoahLiu/native-gui/dbus) | Linux D-Bus 调用：托盘 SNI、通知、logind / upower、媒体、网络、屏保等系统服务 |
| [@chart](https://mooncakes.io/docs/NoahLiu/native-gui/chart) | 图表与横切交互层 |
| [@mdview](https://mooncakes.io/docs/NoahLiu/native-gui/mdview) | Markdown 渲染视图 |
| [@style](https://mooncakes.io/docs/NoahLiu/native-gui/style) | 样式层：样式表写成 MoonBit 值，含状态类与过渡（见[布局样式](../guide/layout.md)） |
| [@i18n](https://mooncakes.io/docs/NoahLiu/native-gui/i18n) | 界面文案多语言：TOML 词表查译 / 插值 / 复数，可订阅语言切换；内置控件文案可本地化（随包中英两套） |
| [@router](https://mooncakes.io/docs/NoahLiu/native-gui/router) | 单窗口页面路由：路由树 + 每层选中键 + link 绑定，任意组件接 `on_link` 导航 |

较重能力放在**独立模块**，可选：

| 模块 | 内容 |
|---|---|
| [NoahLiu/gui-media](https://mooncakes.io/docs/NoahLiu/gui-media) | 音视频引擎与播放器组件 |
| [NoahLiu/gui-webview](https://mooncakes.io/docs/NoahLiu/gui-webview) | 内嵌 WebView（WebKitGTK / WebView2 / WKWebKit） |

用法与场景见左侧指南各页；本站只教使用，逐签名以 API 参考为准。
