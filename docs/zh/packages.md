# 包结构

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

较重能力放在**独立模块**，可选：

| 模块 | 内容 |
|---|---|
| `NoahLiu/gui-media` | 音视频引擎与播放器组件 |
| `NoahLiu/gui-webview` | 内嵌 WebView（WebKitGTK / WebView2 / WKWebKit） |
