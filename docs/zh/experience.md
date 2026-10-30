# 体验文档

不装任何开发环境，用 GitHub Releases 上的**预构建演示包**把 native-gui 在三个平台跑起来；每个演示给出一眼可验的体验点与操作路径。想直接从源码跑，见 §5。

## 1. 下载预构建包

到 [GitHub Releases](https://github.com/lb091188/moonbit-native-gui/releases) 找 **Binaries** 版（`bin-*` 标签产出），按平台取一个 zip：

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
| `audio` / `video` | 音频 / 视频播放器演示（Windows / macOS 包内自带 FFmpeg 动态库） |

## 2. 首次运行

**Windows**：解压后双击对应 `.exe` 即可，不弹控制台黑框；`browser` 依赖的 WebView2 Runtime 系统自带。

**macOS**：包内 `.dylib` 必须与可执行文件同目录，不要拆开拷贝。首次启动会被 Gatekeeper 拦一次（包是 adhoc 签名、未经 Apple 公证，浏览器下载还带隔离属性），两个放行办法任选其一：

1. **终端一行清隔离（推荐，五个程序一次放行）**：

   ```sh
   xattr -dr com.apple.quarantine <解压目录>
   ```

2. **图形路径（macOS 15 起，右键「打开」已不再给放行按钮）**：被拦的对话框点「完成」→ 系统设置 → 隐私与安全性 → 「安全性」段 → 被拦条目旁点**「仍要打开」**（拦截后约 1 小时内有效，每个可执行文件各来一遍）。

**Linux**：解压后 `chmod +x <文件>` 运行。运行库需求（Ubuntu 24.04 自带，其他发行版按名安装）：

```sh
sudo apt install libgtk-3-0 libpango-1.0-0 libx11-6 \
  libwebkit2gtk-4.1-0 libavcodec60 libavformat60 libswscale7
```

## 3. 体验点与操作路径

### hello —— 最小窗口

启动即出原生窗口，无第三方窗口库——轻量产物、快速启动的直观样本。

### showcase —— 组件 / 图表 / 系统能力

左侧栏切页，逐页看：

- **基础组件 / 表单组件 / 数据展示**：按钮、输入、表格、树、虚拟滚动等控件族成品
- **图表页**：折线 / 柱状 / 饼 / 仪表 / 散点 / 雷达 / 热力 / K 线 / 漏斗 / 箱线 / 桑基 / 树 / 矩形树 / 旭日共 14 种，带横向交互层（悬停读数等）
- **主题**：深浅色与强调色跟随系统，跟随开关在菜单里（手动选色会自动关掉跟随，属预期行为）
- **系统集成页**：托盘、桌面通知、全局快捷键、开机自启、剪贴板等门面接口的现场演示
- **系统能力探测页**：五段只读探针（系统桌面 / 显示器窗口 / 应用文件 / 浏览器数据 / 剪贴板电源总线），展示「能力探测 + 结构化降级」——某项系统上不可用会给出结构化原因，不静默失败

### browser —— 内嵌 WebView

- 地址栏导航、前进后退与历史
- 自定义协议打开的本地站点（本地内容通道）
- JS 互操作：页面执行取回、JS↔原生双向绑定演示
- 菜单「策略触发」三项（新窗 / 定位 / 下载）：默认拦截并回报、可在对话框放行——库的策略面闭环就在这里

### audio / video —— 媒体线

播放 / 进度 / 倍速，外挂与内嵌字幕双来源，倍速下音画同步。Windows / macOS 包内已带 FFmpeg 动态库；Linux 用系统 FFmpeg。

## 4. 已知平台差异（诚实口径）

- **macOS 通知**：需从 `.app` bundle 启动才可用，直接跑二进制会报不可用——系统约束，非库缺陷；其余托盘 / 热键等能力裸跑可用。
- **Linux**：音视频与 `browser` 分别依赖系统 FFmpeg 与 WebKit2gtk，见 §2 的安装清单。
- 平台状态以 [README 平台表](https://github.com/lb091188/moonbit-native-gui) 与 [路线图](roadmap.md) 为准：三平台均已真机验证。

## 5. 源码方式运行

装 [MoonBit 工具链](https://www.moonbitlang.com) 后：

```sh
git clone https://github.com/lb091188/moonbit-native-gui
cd moonbit-native-gui
moon run examples/showcase --target native   # 或 examples/<其他示例>
```

依赖安装、失败处置见[构建与运行](build.md)；五分钟上手见[教程](tutorial.md)。
