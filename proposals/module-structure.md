# 模块结构：按路线拆模块、按层级切子包

> **状态**：拆分已落地——主模块 `gui/` 里 `base` / `shell` / `widget` 三层子包就位，`core` 门面包退场；可选重资产在 `modules/`；示例每例一模块。

## 1. 背景与目标

native-gui 计划支持三条渲染路线：**原生自绘 / WebView / 纯 3D**。单模块 + 扁平子包下 `core` 同时依赖 render / theme / win / sys / text / dbus，构成「引力井」：只走 XFCE 自绘的用户也要承担 WebView2 SDK 的代价——vendor 下载加 WebKitGTK 的 pkg-config 探测；未来的 3D 路线更不可能复用整套 widget 树。

| 目标 | 痛点 |
| --- | --- |
| 各路线按需组装 | 一个把控件树、泵、系统能力捆在一起的根对象，使一条 import 就拉进全部后端桩 |
| 减少构建负担 | prebuild 无条件编译全部平台桩、无条件拉 vendor 文件，每个消费者都要等一次完整预构建 |
| 允许路线独立演进 | 每开一个新模块都要重复一份 prebuild 与版本 lockstep |

## 2. 判据一句话

> **外部重资产 + 必须强制下发链接参数 → 开模块；纯内部层 → 留子包。**

## 3. 仓库布局

```
moonbit-native-gui/                          # 根 workspace
├── gui/                                       # [主模块] NoahLiu/native-gui
│   ├── base/                                  # 响应式内核、焦点栈、键码、帧账本
│   ├── shell/                                 # 窗 + 泵 + 子件槽 + resize + 系统能力壳层
│   ├── widget/                                # 布局树映射 + 命中 + Painter 绘制 + App 主体
│   └── ...                                    # style/theme/icons/input/text/chart/mdview/sys/dbus/win/render
├── modules/
│   ├── gui-webview/                           # [模块] WebView2 + WebKitGTK + WKWebView
│   ├── gui-media/                             # [模块] ffmpeg 解码 + miniaudio 播放
│   ├── ffmpeg-mbt/                            # [模块] ffmpeg 绑定
│   └── yoga-mbt/                              # [模块] 布局引擎
├── examples/<name>/                           # [每示例一模块] NoahLiu/native-gui-examples-<目录名>
└── experiment/                                # [独立模块]
```

### 3.1 主模块的三个分层子包

| 子包 | 内容 | 下游 |
| --- | --- | --- |
| `base` | signal、store、effect、keys、focus、list_store、prof、tick、rect | 无 |
| `shell` | loop、session、menu、hotkey、tray、notify、reveal、probes | win / sys / dbus |
| `widget` | widget、node、overlay、overlay_native、popup、drag、input_map、click_tracker、combo、app、host | base + shell + render/text/theme/yoga |

边界规则：

- `shell` 的 `Session` 是泵 + 平台窗 + 窗号/主窗/退出位 + 悬停/捕获/光标/输入法去重缓存 + 整窗脏标志；`widget` 的 `App = { session, root, focus, host, dirty_*, … }`。WebView / 3D 路线只吃 `Session` 这一半，不碰控件树。
- `widget` 能调 `@shell`，`@shell` 不能反调；Painter 契约只在 `widget` 出现。
- 事件词汇（`PointerKind` 等）留在 `widget`；壳层需要回到控件层时走进程级注入单槽（`set_repaint_hook` / `set_repaint_sink` / `set_timer_hooks`），壳层不认识控件树。
- 输入法整块留 `widget`——它服务的就是编辑控件；`shell` 只在 `step` 里调注入的 `on_frame`。
- `input` 只依赖 `base`、与 `widget` 互不引用，编辑器与宿主的接缝做成控件回调（`on_key` / `on_commit` / `on_preedit` / `im_context` / `im_cursor`），宿主按焦点投递。

### 3.2 `NoahLiu/gui-webview` 模块

本包只依赖窗口 / 布局 / 事件层，不依赖媒体层，也不被媒体层依赖，所以两条路线可以并行推进。入口：`webview_new(app, url)` / `webview_open(app, opts)` 开整页壳，`Webview::node(self, …)` 作混排形态。

- **一个能力一个接口**：`webview_supported()` 说清这台机器有没有引擎，不可用时 `webview_new` 给 `None`，由调用方决定摆什么替代品，不静默降级。
- **子件不被 Painter 绘制、不吃 `clip_rect`**：所以不做圆角 / 透明 / 被覆盖的承诺，pane 之间也不重叠。
- **prebuild 自管 WebView2 资产**：vendor 的 lib + 头文件在本模块；Linux 分支探 WebKitGTK 时缺开发包返回空 link_configs 而不报错，MoonBit 侧以 `webview_supported()` 探测降级。主仓 prebuild 不再有 web 相关分发。
- **版本独立**：对外发布独立 version，消费者经 `moon.work` 本地解析或指定版本号。

### 3.3 模块化的代价

每新增一个模块 = 一份 platform 探测 + 静态库编译 + vendor 下载 + prebuild 脚本 + CI 矩阵条目 + 版本 lockstep。现存参照：`gui/scripts/prebuild.py`（主仓，分平台 stub 分支）、`modules/gui-media/prebuild.py`（媒体线）、`modules/ffmpeg-mbt/prebuild.py`（libav* flags）。

**因此只有真正踩线的才开模块。**

### 3.3.1 示例侧反着来：每示例一个模块

上一条的代价全在**库模块**（platform 探测、vendor、prebuild、CI 矩阵、版本 lockstep）。示例模块一条都不吃：不 prebuild、不 vendor、不进发布链，代价只是「一份 `moon.mod` + 一行 `moon.work` 成员 + 构建命令逐示例点名」。所以示例的判据反过来——**默认每示例独立成模块**：`examples/<name>/moon.mod`（`NoahLiu/native-gui-examples-<name>`），import 只列自己用到的包。合并成一份 `moon.mod` 会把重资产（ffmpeg / gui-media）拉进整个示例集的依赖闭包，而 moon 的依赖解析单位就是模块，包级 `moon.pkg` 救不回来。产物随模块名落目录：`_build/native/<mode>/build/NoahLiu/native-gui-examples-<name>/native-gui-examples-<name>.exe`。纯资产目录（`examples/assets/`）不放 `moon.mod`，就不算模块。

### 3.4 `gui-media` 的依赖面

- 引擎在 `media/`，只有引擎没有 UI：帧以 RGBA 字节交出，由调用方灌进 `@render` 的 `Bitmap` 再走 Painter 合成。
- 播放器组件用 `ui` 的现成控件（`icon_button`、`button`）。方向是 media → ui——ui 不认媒体，无环；ui 是纯内部层，不拉外部重资产，判据不变。
- 依赖面：`base` + `shell` + `widget` + `render`/`text`/`theme`/`icons` + `ui`，加 `ffmpeg-mbt` 与 `yoga-mbt`。

## 4. 约束与红线

- **模块外消费者进迁移清单**：跨包改名/import 迁移必须覆盖 `modules/*`、`examples/`、`experiment/`——它们经 `moon.work` 本地解析，不在主模块门禁的视野里，漏一个就是「已推送的树断链」。每批改完逐模块重跑 `--deny-warn`。
- **工具链没有再导出**：无 `pub use`，`moon.pkg` 的对象式 `import-all` 解析器不认；类型别名转不出枚举构造子，跨包消费方要写全限定变体（`@widget.PointerKind::Down`、`@shell.MenuRole::Copy`），这也是终态写法。
- **未用 import 会判红**：`--deny-warn` 下删文件必须同步删 `moon.pkg` 的 import。
- **版本 lockstep**：`modules/*` 发布前同批递增版本号，CI 测试清单同步扩展到新模块。
- **prebuild 复制劳动**：考虑抽 `scripts/shared_prebuild.py`；先解决功能再抽象。

## 5. 待定问题

- `gui-3d` 的初步范围：GLFW 窗口创建 + OpenGL ES/Vulkan 上下文，还是复用 `win` 的子件槽挂 canvas？这决定 `shell` 是否需要额外抽象。
