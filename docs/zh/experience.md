# 体验文档

两种不写代码的体验：下载预构建包（§一）或克隆仓库跑示例（§二）。自己写应用，从零路径见[应用开发者体验](dev-experience.md)；改库与参与开发直接看[构建与运行](build.md)。

## 一、真体验：预构建包

### 下载与首次运行

到 [GitHub Releases](https://github.com/lb091188/moonbit-native-gui/releases) 的 **Binaries**（固定单一名，始终是最新构建），按平台取一个 zip：

| 包 | 平台 |
|---|---|
| `bin-windows-x64.zip` | Windows 10/11 x64 |
| `bin-macos-arm64.zip` | Apple Silicon macOS |
| `bin-linux-x64.zip` | x64 Linux |

每个包内是同一套五个可执行文件 + 第三方许可（`THIRD-PARTY-NOTICES.md`）：

| 可执行文件 | 内容 |
|---|---|
| `hello` | 最小窗口（框架体积与启动速度的基线样本） |
| `showcase` | 全功能演示板：组件族、14 种交互图表、Markdown / 代码视图、主题跟随、系统集成页、系统能力探测页 |
| `browser` | 内嵌浏览器演示：地址栏导航、本地站点、JS 互操作、策略拦截 |
| `audio` / `video` | 音频 / 视频播放器演示，演示文件已随包；Windows / macOS 包内另带 FFmpeg 动态库 |

**Windows**：解压后双击对应 `.exe` 即可，不弹控制台黑框；`browser` 依赖的 WebView2 Runtime 系统自带。

**macOS**：五个应用是 `.app` bundle，解压后**双击直接运行**，不会开终端。首次启动会被 Gatekeeper 拦一次（包是 adhoc 签名、未经 Apple 公证，浏览器下载还带隔离属性），两个放行办法任选其一：

1. **终端一行清隔离（推荐，五个程序一次放行）**：

   ```sh
   xattr -dr com.apple.quarantine <解压目录>
   ```

2. **图形路径（macOS 15 起，右键「打开」已不再给放行按钮）**：被拦的对话框点「完成」→ 系统设置 → 隐私与安全性 → 「安全性」段 → 被拦条目旁点**「仍要打开」**（拦截后约 1 小时内有效，每个 app 各来一遍）。

`lib/` 里的 `.dylib` 五个 app 共用，与 `.app` 保持同目录，不要拆散拷贝。

**Linux**：解压后 `chmod +x <文件>` 运行。运行库需求（Ubuntu 24.04 自带，其他发行版按名安装）：

```sh
sudo apt install libgtk-3-0 libpango-1.0-0 libx11-6 \
  libwebkit2gtk-4.1-0 libavcodec60 libavformat60 libswscale7
```

### 体验点与操作路径

#### hello —— 最小窗口

启动即出原生窗口，无第三方窗口库——轻量产物、快速启动的直观样本。

#### showcase —— 组件 / 图表 / 系统能力

左侧栏切页，逐页看：

- **基础组件 / 表单组件 / 数据展示**：按钮、输入、表格、树、虚拟滚动等控件族成品
- **图表页**：折线 / 柱状 / 饼 / 仪表 / 散点 / 雷达 / 热力 / K 线 / 漏斗 / 箱线 / 桑基 / 树 / 矩形树 / 旭日共 14 种，带横向交互层（悬停读数等）
- **主题**：深浅色与强调色跟随系统，跟随开关在菜单里（手动选色会自动关掉跟随，属预期行为）
- **系统集成页**：托盘、桌面通知、全局快捷键、开机自启、剪贴板等门面接口的现场演示
- **系统能力探测页**：五段只读探针（系统桌面 / 显示器窗口 / 应用文件 / 浏览器数据 / 剪贴板电源总线），展示「能力探测 + 结构化降级」——某项系统上不可用会给出结构化原因，不静默失败

#### browser —— 内嵌 WebView

- 地址栏导航、前进后退与历史
- 自定义协议打开的本地站点（本地内容通道）
- JS 互操作：页面执行取回、JS↔原生双向绑定演示
- 菜单「策略触发」三项（新窗 / 定位 / 下载）：默认拦截并回报、可在对话框放行——库的策略面闭环就在这里

#### audio / video —— 媒体线

播放 / 进度 / 倍速，外挂与内嵌字幕双来源，倍速下音画同步。Windows / macOS 包内已带 FFmpeg 动态库；Linux 用系统 FFmpeg。

## 二、跑仓库示例

预构建包之外，还可以克隆仓库直接跑示例（需先装 MoonBit 工具链，见[五分钟上手教程](tutorial.md) §1）——`examples/` 下每个目录都是独立模块，进目录 `moon run .` 即可：

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

示例之上深入各面：[组件速查](components.md)、[声明式与响应式](declarative.md)、[布局样式](layout.md)、[系统能力总览](system-capabilities.md)、[内嵌 WebView](webview.md)。

## 三、库开发

改库、加控件、报平台兼容问题：工具链与依赖安装、构建门禁、测试口径与常见失败处置全在[构建与运行](build.md)；包的组成见[包结构](packages.md)；参与方式见 README「参与贡献」。
