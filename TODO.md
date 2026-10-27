# 路线图 — MoonBit 原生 GUI 栈

记号：`[~]` 部分（缺口写在子条目）· `[ ]` 未开始。完成项不驻留——删除并同批写进 [docs/zh/roadmap.md](docs/zh/roadmap.md)。

- **唯一主线**：自绘栈（新栈拥有窗口/像素/事件循环/布局，控件全部基于 Painter 自绘 + 自定义主题，不提供独立原生控件）。
- **更名与目录定案（2026-10-12）**：主模块 `NoahLiu/moonbit-libyue` → **`NoahLiu/native-gui`**（mooncakes 新包名，首版 0.1.0 占位；`NoahLiu/moonbit-libyue` 与 `NoahLiu/yue-media` 已于 2026-10-19 在 mooncakes 标记废弃，理由「已更名」）；子模块 `NoahLiu/yue-media` → `NoahLiu/gui-media`、`NoahLiu/yue-examples` → `NoahLiu/gui-examples`；**库模块根落在 `gui/`**：15 个库包（`gui/base` … `gui/style`；原 `gui/web` 于 2026-10-16 G9 Batch 1 出成独立模块 `modules/gui-webview`；原 `gui/core` 于 2026-10-17 G9 Batch 2 import 迁移后整包退场）与 `moon.mod` 都在其下，模块名不变故 mooncakes 包路径 `NoahLiu/native-gui/<包>` 与既有 import 全部不变；`examples/`、`experiment/` 拆为**独立模块**（`NoahLiu/native-gui-examples` / `NoahLiu/native-gui-experiment`），经 `moon.work` 本地解析依赖库模块，构建/测试不再牵连库门禁；旧链 `yue/` 已删除。GitHub 仓库名 2026-10-13 已改为 **`moonbit-native-gui`**（旧名 301 重定向）；项目显示名（README 首行、文档站 title/hero、许可行）2026-10-15 随 0.1.1 重发统一为 **native-gui**，旧名只留更名注。
- **本分支不保留老 libyue 绑定**：`shim/`、`lib/` 预构建库、`scripts/prepare.py` 已删除；libyue 只作**老师**（行为参考、可平移资产来源、`patches/` 的真实 bug 语料）。
- **路径搬家注（2026-10-16）**：本文件历史条目里的 `gui/web/…`、`NoahLiu/native-gui/web`、`moon test ./gui/web` 均指已出模块的 webview 线，现落位 `modules/gui-webview/webview/`（包 `NoahLiu/gui-webview/webview`），不逐处改写。
- **示例目录定案（2026-10-19）**：历史条目里的 `NoahLiu/native-gui-examples/<示例>`、`modules/gui-examples`、包名 `NoahLiu/gui-examples/…` 均指已合并的旧示例模块，现落位 `examples/<示例>/`（各自独立模块 `NoahLiu/native-gui-examples-<示例>`），不逐处改写。
- **旧链路的完成项与实测结论不在本文件重述**：代码在 `master`（`shim + libyue`，0.5.x 与 `bin-*`/`vendor-*` 发布照旧），踩坑与验收细节在 [proposals/adaptation.md](proposals/adaptation.md) 与 `git log`。**凡旧栈做过、新栈尚未重做的能力，本文件一律记为未完成。**
- **门禁口径**：全仓 `moon check --deny-warn` 零错误零警告（2026-10-15 复核；2026-10-11 起曾为红基线 287 errors / 68 warnings，逐批清零）；库门禁在 `gui/` 下按包限定跑 `moon check` + 分包 `moon test`，`examples/`、`experiment/`、`modules/*` 各模块 `--deny-warn` 复核。
- **验证示例归口（2026-10-16 收口）[历史，模块名见上方 2026-10-19 定案]**：native-* 累积验证板已全部删除（`examples/native-app`、`examples/native-window`、`examples/systemprobe`、`examples/native-web`、`examples/systemprobe`），职能归正式示例——GUI 能力与系统能力只读探测归 `examples/showcase`（含第 15 页「系统能力探测」与任务栏进度/粘性列表/GIF/自绘消息框/字体回退/bind_node 各段）、浏览器归 `examples/browser`、媒体归 `examples/audio` / `video`、扩展图表归 showcase「图表」页的扩展/新图表/交互三段（2026-10-16 由独立示例 `examples/charts` 并回后删除）。后续新能力的演示一律直接进对应正式示例（或库测试），不再新开 native-* 验证板。
- **跟踪口径（2026-10-12 定）**：本文件**只跟踪跨平台能力**（三平台同构的 API 面、或「一个门面 + 各平台后端」的形态）。**纯 Linux 依赖的实现细节不再列为待办**——xrandr / wmctrl / xclip / sysfs / wpctl / pactl / CUPS / redshift / xfconf / gsettings / xdg-* / D-Bus 等命令线与总线面的适配，属「Linux 后端内部事务」，随各自能力批处理时按需实现，不进路线图。判据：一个条目若只在一个平台有意义（换个平台没有对应 API 可做）→ 不进 TODO；若换个平台有对应 API（tray/hotkey/通知/剪贴板/文件对话框/菜单栏…）→ 进 TODO，且**以「门面定形态 + 各平台后端」记账**。

## 1. 地基（新栈自身进度）

> 已完成的功能点全部收进 [docs/zh/roadmap.md](docs/zh/roadmap.md)「功能面全景」；本节只留未完成项。

- [ ] [~] **G5b** 输入通道补齐
  - ibus 一套复验（探针侧归因 libpinyin display-style，待确认）
  - macOS：`NSTextInputClient` 通道已随 mac 合并落地（2026-10-18 d3020b9 补功能键闸，修导航键被输入法吞），三平台真机已复验
  - 肉眼确认项：preedit 下划线观感、候选窗是否贴组合串末尾、caret 闪烁观感（点击定位已用 xdotool 客观验通：点控件最左端 caret 归 0、原位插字符）
- [ ] [~] **G7** 声明式层与组件宿主接线（`mount` 目标从 `View` 换 yoga-mbt 节点；恢复全仓门禁。宿主与声明式地基已就位：`@widget.App` + `@widget.Widget` 树 + `@widget.Node`/`bind_node`/`swap_node` + `@base.Store`/`@base.Signal`，验证归 `examples/showcase`；剩组件与图表挂新 Painter）
- [ ] **G8** 原生子表面通道与其消费者（见 §4「浏览器」「视频」）
- [ ] **G10 窗口内按键路由补齐**（2026-10-16 播放器快捷键一批暴露的面）
  - [ ] **焦点链会抢走窗口级兜底**：`ui.button` 的键盘口径是「空格/回车激活」。于是用户 Tab 过任何一个按钮之后，空格就不再是播放器的「播放/暂停」而是「按下那个按钮」——与 Web 一致，但播放器用户预期相反。待定口径：播放器快捷键是否要**优先于**焦点链（给 `add_key_fallthrough` 加「抢占档」），还是把按钮激活键收成只 `Enter`（改 ui 公共行为，波及所有表单）。先立判据再动：同一窗内「Tab 到按钮 + 按空格」的期望行为写进契约与 wbtest。
  - [ ] **方向键与滚动/焦点导航的归属**：`←/→/↑/↓` 在 `ui.slider`、`ui.input`（光标移动）、滚动容器与本批的播放器音量键之间目前**没有优先级记录**——同一条键谁先吃，靠的是「焦点链先问、兜底后问」这条隐式规则。要把可达路径写成表（哪个控件在焦点上时四个方向键分别归谁）。

## 2. 框架能力域 — 全部待在新栈重做

> 清单已按 master 线参考副本逐包核对（2026-10-11，`/home/lkyh/ownCode/moonbit-libyue` 的 master，比本仓 origin/master 新）；条目里的文件/函数名均指 master 现行资产。

### 前端化批次（design.md §5 的 P1–P5，2026-10-13 起）

（P1 样式层、P3 响应式补强、P4 绘制能力、P5 动画 `transition` 与逐组件样式通道已交付，见 roadmap「组件层与前端化」；真机反馈修复集迁入 adaptation。）

- [~] **P2 组件层**收尾：
  - [ ] 观感逐页比对不回退（真机由用户复验，`examples/hello`、`showcase`、`sysmonitor`）。

### 控件（一律自绘，不再引入原生控件皮肤；家族名对应 master `yue/components/` 九个源文件）

（九族件数与清单见 roadmap「控件与组件清单」。）

- [~] 基础原语：`group`/`separator`/标签/图像/图标/按钮已落新包 **`ui`**（首批 7 件，另附 `container`；文本 measure/baseline 首次回灌布局引擎，`on_pointer`/`on_draw` 首参为控件本身以免自捕获引用环；`type=` 因是保留字改 `kind : ButtonKind`；`yue/components` 属旧链路红点，按批替换）；表单族 15 件已全部落 `ui/form.mbt` + `ui/entry.mbt` + `ui/textarea.mbt`；`tab` 已由 `ui/nav.mbt` 的 `tabs_t` 承担（页签头行 + 预建页区显隐），`scroll` 已落 `ui/scroll.mbt`（垂直滚动容器 + 自绘滚动条，平移用 yoga 新补的相对定位偏移），`splitter` 已落 `ui/split.mbt`（`hsplit`/`vsplit`）、`combo` 已落 `ui/form.mbt`

### 主题、声明式与应用层

- [ ] [~] 主题系统
  - 新栈刻意不做：原生控件 CSS 下发（全自绘后色板是唯一来源）
- [ ] [~] 声明式层（`declarative/` 612 行、24 构造器）：地基已落（`Node{mount:(Widget)->Widget}`、`node_of`/`node_of_new`/`mount_children`/`App::mount`、`invalidate` 回路）；**L1 构造器全集落 `ui/declarative.mbt`**——`vbox`/`hbox`/`text_edit`/`picker`/`scroll`/`tab`/`date_picker`（改名者，旧调用点原样跑在新栈上）+ `mount_window`（建宿主并挂载）+ `bind`/`bind_label`（Store/信号驱动的文本绑定），与组件**同名**的（`label`/`button`/`entry`/`checkbox`/`container`/`group`/`separator`/`image`/`icon`/`radio_group`/`slider`/`progress`）直接用组件、不再包第二层；`hover_group` 已落（本栈宿主悬停态是父链语义，旧链路那套全局指针轮询不需要）；`overlay_scroll` 即 `scroll_v`（滚动条一直是视口的绝对定位子控件）。`cursor_group` 已落（配套新增窗口层光标通道：`wm_set_cursor` FFI + `Widget.cursor` 请求 + 宿主按悬停路径取「最深非零」下发）；`combo`（可编辑下拉：`entry` + 随输入过滤的候选浮层，↑↓/回车/Esc 走按键沿祖先链冒泡）已落 `ui/form.mbt`；`gif`（动图组件，走 `@render.Animation` 的逐帧迭代 + 进程级延时通道）已落 `ui/gif.mbt`。**L1 构造器全集到此收口**（旧 24 个里除 `mount`（即 `App::mount`）与同名组件外都已到位）。
- [ ] 富文本编辑（远期 WYSIWYG 块编辑器）
- [ ] 代码高亮、终端模拟器、WebGL 画布（旧栈即无，列为待评估）

### 系统集成（master 参考面：`yue/system` 31 源文件 + `yue/traybus` 16 源文件，属可平移资产）

- [ ] [~] A 类平移 · 环境/文件原语
- [ ] [~] A 类平移 · 硬件族（六进 sys；sensor/bluetooth 走 @traybus、disk 走 UDisks+@traybus，随 DBus 线）：
  - [ ] `sensor`（iio-sensor-proxy）/ `bluetooth`（org.bluez）/ `disk`（UDisks2）随 DBus 线（**仅 Linux 有对应面，按新口径不进路线图**；如需启用另立 Linux 侧文档）
- [ ] [~] A 类平移 · 会话与状态：`power`/`session`/`powerctl`/`online`/`idle`/`keepawake`/`clipboard_watch`/`locale_sys`/`sysinfo`/`windowctl`（monitor 已随硬件族提前）
  - [~] `power`/`session`/`online`/`keepawake`/`powerctl` 的**总线能力已在 `dbus`**（`upower.mbt`/`logind.mbt`/`netmon.mbt`/`inhibit.mbt`，真总线回证）；`sys` 侧与旧链同名的语义化包装（电量读数、挂起/休眠动作、在线判定、抑制睡眠）待随各能力线补——**总线面为 Linux-only，按新口径不进路线图**；如需在非 Linux 提供同类能力，走 §6 的跨平台门面（如 W21a 通知）
- [ ] [~] DBus 系在新事件循环下**重写/重验**：SNI 托盘（`traybus/sni.mbt`）、通知（新栈须重写 `org.freedesktop.Notifications`，含 `Notification::set_progress` 进度文本）、logind（`SetBrightness`/inhibit）、UPower、NetworkManager（`netmon`/`online`）、屏保 `screensaver`、媒体键 MPRIS（`media` 含状态监视轮询）
  - **非 Linux 后端**：D-Bus 线本身是 Linux-only（`dbus_stub.c` 在 `_WIN32`/`__APPLE__` 为失败桩），但 **SNI 托盘 / 通知 / MPRIS 的跨平台面**已按新口径收进 §6（W20c 托盘、W21a 通知）；其余（logind/UPower/NetworkManager/屏保/inhibit）**无跨平台对应面，不再跟踪**
- [ ] 新建项（master 全仓无资产，属新做）：**任务栏进度 / dock 徽标** 已收进 §6.3（W20 批，三平台各有原生面）；**勿扰** 随 W21a 通知门面
- [ ] 平台分派：**跨平台能力的各平台后端按 §6 批次推进**（Win 基础能力 W20 / MBT 通用门面 W21）；master 有 Win32 直连族与 mac ObjC++ 族可参照

### webview 与媒体（角色区 pane 模型；已锁决策与批次验收见方案 §4）

窗口内容 = 1..N 个互不重叠的矩形区（pane），每区声明 owner（自绘 = Painter / webview = 原生子件），矩形由 yoga 布局给；Tauri-like、爬虫内容获取页、原生多窗口三种形态同源。**本轮只做 Linux 闭环**，Windows/macOS 后端归输入通道另线与平台批。

- [~] **批 C JS 桥 + DOM 抓取 + 导航面**（已完成面见 roadmap「webview 与原生子表面」；剩余见子条目）
  - [ ] 评估项（不立项，等真实调用方）：cookie 变更监听——三平台都有引擎事件可挂（WebKitGTK cookie manager 的 changed 信号 / `WKHTTPCookieStore` observer / WebView2 CookieManager 事件），只有「多 pane 实时联动 UI」（如任意 pane 登出、所有 pane 徽标即时刷新）这类需求用得上；共享与隔离本体已定案＝浏览器默认策略，见 roadmap「cookie 共享与隔离」行。
  - [ ] 一条待查观测（不影响本批结论，且**不是每次都出现**）：协议页首屏在事件区偶发出现**两次** `导航开始 yuedemo://local/bridge.html`（出现时 `navs` 比真实导航数多 1）。同一份示例复跑四次的 `navs` 读数依次为 4、1、1、1，所以这条不是协议页的固定行为，更像引擎侧偶发的一次额外 `load-changed::STARTED`。已排除本栈双路径（`load_url` 在未挂载时只记 `self.url`，`wb_create` 建视图时才 `load_uri` 一次）。要定案就在 `wb_on_load_changed` 里带上 `load_event` 原值与 `webkit_web_view_get_uri` 的读数对照多轮，判据先立再改，不改行为
- [~] **批 D 媒体播放器**（可与 B/C 并行）：复用 `modules/ffmpeg-mbt`（零 libyue 依赖，已有 `decode_rgba`/`decode_pcm`/`seek`/`duration_s`/`video_fps`）+ `modules/gui-media` 内嵌的 miniaudio 设备层；**CPU 回灌 + 软解**（RGBA → `render` 的 `Bitmap` → Painter 合成，本档位不做硬解与 GPU 合成）；新写播放器 UI（悬浮控制条/进度与音量/倍速/字幕叠加/seek 防抖）+ 音频时钟与同步；旧链坑照 adaptation.md 逐条验收（音画不同轴、seek 后进度从零重涨、换载崩溃）
  - [ ] 批 D2c 再余项（不假装完成）：ASS 样式渲染（颜色/定位，目前只按文本叠加）、多字幕轨列表与切换（现在只取 `av_find_best_stream` 选中的那条）、倍速听感复验（是否仍同步；音高随动已定案不做——时间拉伸要相位声码器，口径见 media/audio.mbt 注释）
- [~] **批 E 原生弹层窗口**（已完成面见 roadmap 同节；剩余见子条目）
  - [~] **批 E 余项**：「点外收起」的可用判据仍欠——失焦自收在映射期会误触发（对照实验：开=约两秒自关且 `hides=0`；关=常驻），故 `overlay_set_dismiss_on_blur` **默认关**，等「拿到过焦点才算」的判据；另欠弹层锚点跟随 owner 滚动/移动、六件各自的尺寸提示
- 积木原则：一个能力一个接口、可单独不用；能力之间不互相依赖（webview 不依赖媒体层，反之亦然，两者只依赖窗口/布局/事件层）；框架只给原语不给产品（爬虫框架、站点适配、内容解析、开发者面板、页面脚本库不进库）；每项能力给探测 + 语义化降级；新 API 一律走 `Painter`/`Bitmap` 门面
- 明确不做（避免反复讨论）：网络拦截/改写、代理配置、一窗多 webview 并排、Linux 上把 webview 变纹理、首批硬解、首批 GPU 合成、网页内 `<video>` 与自绘播放器统一、macOS 13 及以下的持久化隔离（根因是 Apple API 边界：持久化 profile 需 macOS 14+ 且有 bundle id）
- 平台后端（随各自真机）：Windows WebView2——**2026-10-13 平台批已接**（两级异步 COM 创建 Environment→Controller、失败走 dead 语义降级、就绪前 load 排队、13 事件 push 队列同构 WebKit 分支、自定义 scheme 经 `EnvironmentOptions4::SetCustomSchemeRegistrations` 预注册 + `WebResourceRequested` 回包（`CreateWebResourceResponse`，404 给明确空响应）；vendor 口径：NuGet Microsoft.Web.WebView2 1.0.4258.31 的 `WebView2LoaderStatic.lib` + 头 vendor 进 `gui/web/`，prebuild 下发链接参数；**真机验证**：web wbtest 17/17、一次性探针 load_html/标题事件/JS 求值/协议页导航/DOM 求值全通、`native-web` 冒烟 `supported=1` + GEO 真矩形 + 8 组统计；坑见 `adaptation.md`——未预注册 scheme 导航直接失败、COM propput 少 self 参数在 x64 上静默写坏 vtable、`GetCustomSchemeRegistrations` 数组必须 `CoTaskMemAlloc`（静态数组会被引擎 free 触发堆损坏 0xC0000374））。**未接**：跨 HWND 焦点与滚轮转发。macOS WKWebView（自定义协议走**公开**的 `WKURLSchemeHandler`（macOS 10.13+），libyue 当年那条 `WKBrowsingContextController registerSchemeForCustomProtocol:` 是更老的私有路线；要验的是公开入口够不够用：自定义 scheme 默认非标准、origin/localStorage 行为要另配；**另需真机验一条**：`loadHTMLString:baseURL:` 是否入前进/后退历史——Apple 无文档承诺，而 Linux 实测 `load_html` 不入历史、WebView2 文档明写 `NavigateToString` 不改历史，若 mac 相反就要在 `web` 里抹平或写进契约）

### 交付面（webview 批 A/B 落地后接上）

- [ ] 文档：中英使用文档按新栈重写（`components`/`components-ui`/`declarative`/`layout`/`relink`/`system-capabilities`/`tutorial`），README 挂新截图
- [ ] 文档：中英使用文档按新栈重写（`components`/`components-ui`/`declarative`/`layout`/`relink`/`system-capabilities`/`tutorial`），README 挂新截图
- [ ] 发布：旧 `bin-*`/`vendor-*` 预构建发布链退役（mooncakes 侧 0.2.0 已于 2026-10-19 发布，见 roadmap「承诺与版本」）
- [ ] 真机验证矩阵：macOS 已按 `测试文档/测试用例.md` 跑完；Windows 10 / 11 本机冒烟已通；Ubuntu GNOME / KDE / XFCE 待排
- [ ] [~] **平台批：WebView2 桩真实现 + ffmpeg Windows 真链接**（已完成面见 roadmap；剩余见子条目）
  - **win 子 HWND 容器**（P1）：`gui/win/stub.c` 补 `wm_surface_new/set_rect/close/container` Windows 真实现（`WS_CHILD` 面板 HWND，父=宿主窗，DefWindowProc + 背景刷 NULL 免闪白），`wm_init` 注册窗口类、`wm_close` 清 surface 槽——web 桩经 `wm_surface_container(surface_id)` 拿 parentHWND。
  - **WebView2 桩真实现**（P2/P3）：`gui/web/webview2_stub.c`（仅 `_WIN32` 有内容，~1450 行）——静态 Loader 链接形态（`WebView2LoaderStatic.lib` vendor 进 `gui/web/lib/`、头 vendor 进 `gui/web/include/`，NuGet Microsoft.Web.WebView2 1.0.4258.31，MIT）；事件模型与 WebKit 分支同构（COM 回调 push 队列、MoonBit 每帧消费式取）；`webview_predeclare_schemes` 名单经新 extern `wb_predeclare_scheme` 流到 C 桩、Environment 创建时经 `EnvironmentOptions4::SetCustomSchemeRegistrations` 注册（`WbReg`/`WbOptions` 手写 COM，secure=TRUE/authority=TRUE）；`webkit_stub.c` 两分支加 no-op 对齐。**验证**：`moon test ./gui/web` 17/17、`core` 118/118、examples `--deny-warn` 零警告；一次性探针 `examples/webprobe`（验证后已删）——load_html+标题事件+JS 求值、协议预注册+本地文件服务+导航（`PROBE-TITLE ScmPage`/`PROBE-DONE title=ScmPage url=probescm://local/index.html`/`PROBE-JS scheme-ok`）全链路真机通；`native-web` 冒烟 `supported=1` + GEO 真矩形 + 8 组统计。
  - **ffmpeg Windows 真链接**（P4）：`ffmpeg_stub.c` 删 `_WIN32` 全错误降级分支，三平台实现同源；dev 内容 vendor 进 `modules/ffmpeg-mbt/vendor/`（BtbN `ffmpeg-n9.0-latest-win64-lgpl-shared-9.0` 的 include 头 + 导入库 + LGPLv3 LICENSE，共 2.5MB；**运行期 dll 不进仓库**——本地放 PATH 或与 exe 同目录）；`prebuild.py` Windows 分支输出 `vars.FFMPEG_INC` + 导入库 `link_configs`（官方 prebuild `vars` + moon.pkg `${build.VAR}` 替换机制）；`src/moon.pkg` 加 `stub-cc-flags: "/utf-8 -I${build.FFMPEG_INC}"`——**`/utf-8` 是必须项**：MSVC 默认按系统代码页（GBK）读无 BOM 源文件，中文注释与 ffmpeg 头的 UTF-8 字节序列被误读吞行（C4819 → 级联语法错误）。`gui-media/prebuild.py` 注释更新：Windows 实测 miniaudio WASAPI/COM 全走运行期加载，零额外链接库。**验证**：`moon test ./modules/ffmpeg-mbt/src` **6/6**（ogg/m4a/wav 音频真解码 + 视频真解码 96x64 12 帧）、`moon test ./modules/gui-media/media` **24/24**（AudioPlayer 冒烟 pump 33 拍播完 1 秒素材——WASAPI 设备链真出声）；`native-web`（依赖 media→ffmpeg-mbt）Windows 链接成功。
  - **门禁**：库 `moon check` 归零 + 分包测试 **837/837**；各模块 check 全绿。**已知遗留**：`experiment/ime_probe` Windows 链接 `ip_set_surrounding` LNK2019（Windows 上 prebuild 不编 IME 探针桩，既有问题、与平台批无关）；`release-bin.yml` 等 CI 未覆盖 ffmpeg dll 分发口径。


## 3. 里程碑

- **M3** macOS 地基：mac 平台批①-⑤ 已落（窗口/渲染/文本/webview/sys 各族），真机目视已回证，遗留缺口见 §7

## 6. 跨平台能力面（Win 基础能力 + MBT 通用能力）

> **本节口径**（2026-10-12 定）：只记跨平台能力——即「换个平台有对应原生 API 可做」的能力，一律记&#x6210;**「MBT 门面定形态 + 各平台后端」**；纯 Linux 依赖的实现细节（xrandr/wmctrl/xclip/sysfs/wpctl/CUPS/D-Bus…）不再列为待办。清单来源＝旧栈资产面（`yue/tray.mbt`/`menu.mbt`/`misc.mbt`/`widgets.mbt` 的 `Notification`/`register_global_shortcut`/`Tray`/`MenuBar`/`MessageBox`，见本仓实验区 vendored 副本 `experiment/async_coexist/lab/.mooncakes/NoahLiu/native-gui/yue/`）逐文件比对，剔除 Linux-only 后重排。
>
> **执行顺序（口径留档，W22 已全数交付移出本文件）**：W20 批（Win 基础能力，桩层 `win/stub.c` 的 `_WIN32` 分支 + `win/window.mbt` FFI）→ W21 批（MBT 通用门面，跨平台同构）→ 托盘/通知/热键三族门面统一（原 W22，2026-10-18 前全部交付）。每批独立可交付、独立提交。

### 6.1 W20 · Win 基础能力（Windows 桩层，按现有范式）

> 范式：`win/stub.c` 的 `_WIN32` 分支加真实现 → `include` 或 `ffi.mbt` 声明 extern → `win/window.mbt` 加 `Window::*` 方法 → 纯函数/探针可测的抽成纯函数 → `examples/native-app` 累积验证页加一节 → 真机项进人工清单。

### 6.2 W21 · MBT 通用能力（跨平台同构，不依赖平台）

#### W23 · 窗口显隐：`Window::hide`（与既有 `show` / `request_focus` 对称）

- [~] **`Window::hide` 门面已落，Linux 后端已接**（2026-10-16）：`win/stub.c` 三分支 + `Window::hide`/`Window::is_hidden`，`show` 唤回 hide 前的屏幕原点（GTK 分支 `gtk_widget_hide` + `XWithdrawWindow` 撤管，语义区别于 `XIconifyWindow` 最小化；Windows 分支 `SW_HIDE` 记客户区原点供 `SetWindowPos` 复位，**Linux 侧本机 wbtest 真开窗通过、Windows 分支未上机**）。macOS 臂 2026-10-18 已随对齐批落地（86644a4：`orderOut:`/`makeKeyAndOrderFront:` + hidden 驻留标志，show 唤回清零）——三平台真机已复验，剩 mooncakes 发版（启动器「Esc 隐藏驻留」待发版接入）。
  - 动机：旗舰应用 moon-launcher（`lb091188/moon-launcher`）已把「Esc 隐藏驻留托盘」挂为其 README「已知边界」——发布包 0.1.1 只有 `show` 无 `hide`，启动器现在只能「Esc 清空→退出」。
  - 验收判据（本机判据已过：幂等、hide 后 `request_focus` 不异常；真机肉眼项已随三平台清单复验）：启动器 Esc 后窗口隐藏且托盘/DBus 单实例存活，Wake 或托盘点击唤回**原位置**并自动聚焦输入框。

### 6.3 与既有 §1/§2 的接缝（不改口径，仅指向）

- **§2「系统集成」里已有的跨平台能力**（剪贴板、文件对话框、`open_url`/`reveal`、浏览器历史/书签、`sysinfo`、主题跟随系统）**Windows 后端已落**（W14/W14e/W16），无需重开；**只差真机观感复验**（见 6.4）。
- **§2「新建项」**（任务栏进度、dock 徽标、勿扰）与本节的「Win 基础能力」有重叠面——**任务栏进度**（Win32 `ITaskbarList3::SetProgressValue`）与 **dock 徽标**（macOS `NSDockTile`）建议**收进 W20 批一并做**（三平台各有原生面，符合跨平台口径）。
- **`monitor`/`brightness`/`wallpaper`/`nightlight`/`volume`/`printer`/`powerprofile`/`windowctl`/`locale_sys` 等**——按新口径**不再在 TODO 逐条跟踪**（Linux 实现已是既有事实、非 Linux 无对应面或属各自平台批内部事务）；如后续启用平台批，按「各自能力批的内部事务」处理，不占路线图。
- **能力删除定案（2026-10-14，用户拍板）**：`brightness`（屏幕/键盘背光，Linux logind+sysfs 线）、`defaultapps`（xdg-mime/mimeapps 线）、`volume` 的 `volx_` 增强组（pactl 设备枚举/逐应用流）、`printer` 的 `prt_queue`（lpstat 队列枚举）四族**从代码与文档整体删除**——它们只有单平台实现、不满足跨平台口径，也不再留「待补另一平台」的挂账；`dbus` 的 logind 亮度接线（`bridge.mbt`/`brightness.mbt`）随之删除。此前文档里的对应「Windows 待补」条目一并摘除，不作为计划保留。

### 6.4 真机验证（用户执行，助手只给步骤）

- [ ] **W7 真实注入验证**：微软拼音端到端（preedit 下划线/候选窗位置/commit 落框）、两窗互相遮挡与拖动重绘、跨程序剪贴板（复制→记事本→粘回）、文件对话框模态 run 与真选文件、主题跟随系统深浅/强调色——归 `测试文档/测试用例.md`
- [ ] **W20 批观感复验**：原生菜单栏（下拉/快捷键提示/勾选项）、全局快捷键（切到别的程序仍能触发）、托盘（图标出现/右键菜单/左键计数）、MessageBox（图标/按钮/返回值）、窗口标题与图标
- [ ] **三平台真机矩阵**：Windows 10/11 本机冒烟已通（退出码 0）；macOS 已按 `测试文档/测试用例.md` 跑完；Ubuntu GNOME / KDE / XFCE 待排

### 6.6 性能批（2026-10-13 真机反馈立项）

真机反馈原文：「native-app 整体感觉卡顿，滚动、点击、悬浮都有 300–500ms 的延迟，点线分布图推点按钮没用，表格排序不生效，虚拟表格滚动失效」。前三条是**一个根因**、第四条是**示例漏接线**，见下。

- [ ] **文本布局缓存的 1024 超限整表清空策略待 Windows 实测**（`323b537` 引入）：本机 Pango 路径 cold(1680 条不同文本) 与 warm 持平（3.35 vs 3.25 ms/帧），说明这条路径不吃亏；**Windows/DWrite 侧没量过**，而 showcase 这种上千条不同文本的页面正好踩在上限之上——若真机账本 `paint` 占比高且 `frames` 正常，就把整表清空换成按键淘汰（注意现役三处缓存上限不一：DWrite `g_layout_cache` 1024、MoonBit `StrCache` 8192、stub.c 像素缓存 768，统一口径一并定）。对照判据已留：`moon run experiment/showcase_cost_bench`（同树换版本），真机读数 `SHOWCASE-PROF` / `showcase-prof.txt`。
- [ ] **悬停/点击反馈的帧成本量化**（脏矩形已落地后的收益项，未量；P5 已按小脏区读数开工）：局部脏区一帧要花多少钱，由 `SHOWCASE-PROF` / `anim_cost_bench` 的小脏区档读数定档（滚动仍要全视口重画，收益在悬停与点击）。
- [ ] **光栅微优化**（部分已做）：`fill_rect` 不透明实心 + SrcOver 已走 `fill_device_rect` 直写快路径（`composite_solid_span`，无 cov 分配），根背景全窗填充已复用它（仍逐像素写字节）；剩：`Raster::fill/stroke` 通用路径与圆角/stroke/blit 慢路径仍每次新分配一条 width 长的 `cov` 数组（每帧数百次），待末条「量出来再优化」分档后动。
- [ ] **文本布局缓存**（部分已做，仍是单帧成本里最重的一块）：纯文本度量已建 C 侧跨帧缓存 `g_layout_cache`（3c744db，Pango/DirectWrite 同批，键=字体四要素+宽约束等，上限 1024 整清）；剩：富文本 `rt_measure`/`rt_draw` 仍每次经 `ptw_session_layout` 现建 `IDWriteTextFormat` + `IDWriteTextLayout` 用完即 Release（`AttributedText::rt()` 每个文本节点每帧开两个会话），`ui` 的富文本节点一律走这条路；布局（yoga）每帧还会为**全树**文本节点各测一次，屏外的也照测。
- [ ] **量出来再优化**：上面三条都还没在真机上分档计时（`experiment/text_bench` 已有先例可扩展）。建议先做一个「单帧成本分解」探针（根背景填充 / 控件绘制 / 文本 / memcpy+StretchDIBits 各占多少），再决定动哪一块。

### 6.7 面板档收口（2026-10-22 立项）

> 定义见 [docs/zh/roadmap.md](docs/zh/roadmap.md)「已实现 · 窗口 · 层级：面板档」：**不进任务栏、不进窗口循环、所有工作区显示、普通窗口上全屏窗口下**。四条逐平台现状——Linux 四条齐（「全屏窗口下」依赖 WM 层序，XFCE 过、其余 DE 待验）；macOS 循环 / 所有工作区 / 普通窗口上三条齐，**全屏那条相反**；Windows 任务栏 / 循环 / 普通窗口上三条齐，**所有工作区没做**、**全屏关系未定**。

- [ ] **Windows · 所有工作区显示（跟随式，帧调度驱动）**
  - 做法：`wm_set_layer` 进面板档时登记面板窗，宿主每帧调度里按节流问一次 `IVirtualDesktopManager::IsWindowOnCurrentVirtualDesktop`（约 500ms 一档，别逐帧问）；返回 FALSE 时取当前桌面 GUID 并 `MoveWindowToDesktop`，搬完重设 `HWND_TOPMOST`——搬窗会改 z 序。
  - 当前桌面 GUID：`GetWindowDesktopId` 读一扇「当前桌面上的」顶层窗（前台窗优先），缓存最近一次搬入的 GUID 兜底。
  - 退出面板档 / 关窗：注销登记，停止询问。
  - 只走公开 API；**不碰** `IVirtualDesktopPinnedApps`（未公开，IID 与 vtable 随 build 变，系统升级即碎），私有 pin 只允许待在 `experiment/`。
  - 口径：这是「跟随」不是「钉住」——切桌面瞬间窗口从旧桌面消失、在新桌面出现，观感等价但语义弱一档，文档不写成「同时存在于所有桌面」。
  - 验收：Win10 / Win11 各切一次桌面——面板随当前桌面出现且仍在普通窗口之上；切回原桌面不残留第二扇；回 Normal 档后行为与普通窗一致；`SHOWCASE-PROF` 对照无可见帧掉。
- [ ] **全屏窗口下（三平台对齐定义）**
  - **macOS 现在是反的**：`wm_set_layer` 的 Dock 档带 `NSWindowCollectionBehaviorFullScreenAuxiliary`，效果是压在全屏 App 之上。按定义要去掉这一位，改为全屏时不可见（退出全屏回来）。验收：全屏 App 打开时面板消失、退出后原位复现、切 Space 行为不变。
  - **Windows 无「普通窗口上、全屏之下」这个档**：`HWND_TOPMOST` 是唯一能稳定压住普通窗口的手段，而独占全屏（DX）会盖掉 topmost 窗口、DWM 无边框全屏不一定。候选做法：用 `SHQueryUserNotificationState` 判 `QUNS_RUNNING_D3D_FULL_SCREEN` / `QUNS_PRESENTATION_MODE`，进入时临时 `HWND_NOTOPMOST` + `HWND_TOP`，退出回 `HWND_TOPMOST`。先真机分别测「独占全屏」与「F11 / 视频全屏」两路，再决定要不要这条降档逻辑；若两路表现已符合定义则不做。
  - **Linux 待验层序**：`_NET_WM_STATE_ABOVE` 与 `_NET_WM_STATE_FULLSCREEN` 的先后由 WM 决定，XFCE 已过，需在 KDE / GNOME / Cinnamon 各验一次全屏 App 打开时面板是否被盖住；若某 DE 相反，登记为平台差异而不是改实现。

## 4. 已知边界与风险

- 自绘文本的**无障碍**（ATK / UIA / NSAccessibility）本栈暂不含，只记不办。
- 例外扩散警戒：可见原生控件覆盖只作**按平台开关的兜底**，默认关；子表面（浏览器/视频）属能力型例外，需逐条登记评审。
- **过渡期已收口（2026-10-15）**：`examples/*`、`examples`、`modules/gui-media` 全量编译通过、各模块 `--deny-warn` 零警告；分支仍不宜积压——一批完成即提交推送。
- 回归基线：旧栈约 660 条测试随绑定文件消失，属净覆盖损失；补法是新栈每包自建 wbtest 并随资产平移测试。

## 5. 随手可查

- 平台实测坑：[proposals/adaptation.md](proposals/adaptation.md)
- 布局引擎交接与决策：[modules/yoga-mbt/HANDOFF.md](modules/yoga-mbt/HANDOFF.md)
- libyue 源码（只读老师）：`/home/lkyh/ownCode/yue`，含 `patches/` bug 语料
- master 线参考副本（代码权威）：`/home/lkyh/ownCode/moonbit-libyue`（比本仓 origin/master 新，Windows/mac 批次在此；本仓文档落后量见「交付面」）
- FFI 规范与坑：`.agents/skills/moonbit-c-binding/`（同步自 [moonbitlang/skills](https://github.com/moonbitlang/skills)，`~/.agents/skills/` 同版）
- **跨平台能力批次表（Win 基础能力 + MBT 通用门面）：本文件 §6**（2026-10-12 定；只跟踪跨平台能力，Linux-only 细节不再入表）
- 旧栈 API 参照面（可平移资产）：`experiment/async_coexist/lab/.mooncakes/NoahLiu/native-gui/yue/`（`tray.mbt`/`menu.mbt`/`misc.mbt`/`widgets.mbt`，本机离线可用）
- 人工复验清单：`测试文档/测试用例.md`（跑 `moon run examples/native-app`）

## 7. mac 平台批（已落地，遗留缺口）

> 口径同 §6：**门面定形态 + 各平台后端**。形态与坑记在 [proposals/adaptation.md](proposals/adaptation.md) 的「macOS 后端首批」节；真机用例在 `测试文档/测试用例.md`（原 T 节已并入，三平台同一份）；编译/链接门禁是 `ci.yml` 的 macOS job。

- [ ] **macOS GIF 动图分帧合成**：要逐帧读「帧矩形 + disposal」，disposal 不在 Apple 的 GIF 公开属性清单里——先真机用 experiment 探针把可得性回证，再补（当前 `img_anim_decode_file` 给 0，组件退回首帧静图，尺寸已按首帧给对）
- [ ] **macOS 显示器「首选档」标记**：`CGDisplayModeIsPreferred` 在当前 SDK 已不声明（同族的 `CGDisplayCopyAllDisplayModes`/`GetPixelWidth`/`GetRefreshRate` 都还在），`preferred` 一律给 false。要做要先找到公开信号（ScreenCaptureKit 那侧的模式清单能否对上 `CGDirectDisplayID`），不拿私有形态或「当前档」冒充
- [ ] **macOS 通知的后端名仍叫 WinBalloon**：mac 的通知实现在 win 桩的 `wm_notify_*`（NSUserNotification），而 `shell/notify.mbt` 的 `NotifyBackend` 只有 `Dbus`/`WinBalloon` 两档，于是 mac 上 `notify_backend_name()` 报 "win-balloon"。能力本身（标题+正文，无动作/持久化）与气泡同档，先不改门面；通知已真机验通（须从 `.app` bundle 起，裸跑报不可用是系统约束），是否加第三档 `Cocoa` 待定
- [ ] **macOS 安装自启动的生效回证**：plist 写落点已通（纯函数有测试钉住），`launchctl load` 在新写入文件上的实际生效已真机回证；若要换 `bootstrap gui/<uid>`，得先给 sys 补一个取 uid 的口子
- [x] **真机复验 T1-T6 全部目视项**（清单已并入 `测试文档/测试用例.md`）：Retina 观感、输入法内联、拖窗期间的循环、通知弹出——已按清单跑完；通知须从 `.app` bundle 起

## 8. Windows 平台批（2026-10-28 交接：mac 侧编不到也跑不到的项）

背景：本轮在 mac 读码定位。win32 那条 C 臂本地编不到（无 mingw），**编译以 CI 的 windows job 为准**，行为确认全在那台 Windows 真机。

### 8.1 已改待验（本批已提交，pull 后即可验）

- [ ] **`wm_window_move` / `wm_window_origin` 补实**（win32 臂此前是空桩，输出从不写）
  - 判据：窗口页「开驻留探针窗」→ 窗应落在 (160,160)；点「读窗位置」应回 `(160, 160)`、`is_hidden=false`。此前无论窗在哪都回 `(0,0)`，且 `move_to` 静默不生效。
  - 口径：move 与 origin **互逆**，都按**客户区原点**、物理像素（本臂进程已声明 Per-Monitor V2）；带边框的窗内部补偿标题栏厚度。
  - 顺带修：`hide`→`show` 每轮偏一个标题栏厚度（原桩记客户区原点、`show` 却按整窗原点写回 `SetWindowPos`）。验法：带边框窗连做三轮 hide/show，位置读数不动。
- [ ] **「图标下」档撤档/隐藏/关闭时请 WorkerW 重画**（真机「壁纸层残影」）
  - 判据：把某扇窗设到「图标下」，随后四条路径各验一次——切回主窗、撤回普通档、`hide`、`close`；壁纸上都不应留下该窗的最后一帧。
  - 若仍有残影：记下**哪条路径**留下的、当时那扇窗是否还挂着（决定要不要把失效点从桩侧挪到宿主侧）。

### 8.2 待诊断（没动手，先要读数）

- [ ] **透明测试窗整片空白**（`set_borderless(true)` + `App::set_transparent_bg(true)` 的子窗看不到内容）
  - 已排除：present 链在逐像素档是通的（`wm_present` 拷帧后直接 `wm_layered_submit`，不走 WM_PAINT，避免 GDI 把不透明像素糊回去）。
  - 三个候选，按可能性排：① `UpdateLayeredWindow` 走 `pptDst=NULL, psize=NULL`「沿用当前窗口尺寸」，而子窗刚建好时窗口矩形与客户帧尺寸可能不一致（200% DPI 下帧是物理像素、窗是逻辑尺寸），提交的面与窗框对不上；② `w->borderless` 没被 `set_borderless` 更新 → `want=0` 不进逐像素档（但那时应显示不透明内容，与读数不符）；③ 子宿主（`App::open_window` 开的子窗）根本没跑 present 循环。
  - 不改代码就能收的两条读数：① 那扇窗**在不在**（Alt+Tab / 任务栏里有没有它；按 8.1 的 `origin` 读数推位置，看能不能点中「关掉本窗」）；② 同段把「透明度」滑到 128，看**主窗**是否变淡（那是 `wm_apply_alpha` 普通档，另一条路）。窗在且能点中 → 候选 ①；窗根本不在 → 候选 ③。
  - 定了再补：必要时加 `wm_trans_state(id, out4)` 只读探针（打 `trans_want` / `borderless` / `trans_mode` / `pending_w×pending_h` 与 `GetWindowRect` 的差），一轮读数收口。

### 8.3 未实现（win32 臂空桩，不在本批范围）

- [ ] **`wm_window_set_popup` 空桩**：原生弹层（无边框 + 不进任务栏 + transient 到 owner + 恒在 owner 之上）在 Windows 上完全没接——任何要盖住 webview 子表面的浮层在那边就是普通窗。mac 臂的实现可对照（`WM_STUB_MAC` 段）。
- [ ] `wm_permission_request` 空桩属有意占位（见 adaptation「extern 直连 `wm_*` 须各平台分支留占位」）。

### 8.4 验通后的收尾

8.1 两条移进 `docs/zh/roadmap.md` 对应能力行并按平台标 ✅；`测试文档/测试用例.md` 窗口组补「读窗位置」「图标下撤档无残影」两条；8.2 的诊断结论回写 `proposals/adaptation.md`。
