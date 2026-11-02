# Wayland 原生路径：系统能力族在 Wayland 会话的通道收口

> **状态**：立项稿（2026-11-03 调研定稿）。外部事实均标注来源，没查到/没核实的点显式标「未核」，不编造。
> **范围**：roadmap「系统能力 → Wayland 原生路径」条目与「Linux 兼容说明 · 会话」表四行（全局快捷键、空闲检测、窗口控制+剪贴板监视、显示器与夜灯）的全量调研、原生出路评估与分期。GUI 本体（窗口/渲染/输入/输入法）已确认在 Wayland 会话可跑，不在本方案新增范围，只盘点其既有行为。拆分待办见 TODO「Wayland 原生路径」节。

## 一、定位

**当前状态**：GTK3 自带 Wayland 后端，应用本体在 Wayland 会话已能跑（建窗、渲染、输入、输入法、浮层开窗都有 GTK 通路）；缺口集中在**系统能力族与少量窗口操作**——这些现在要么直接 spawn X11 工具（`xrandr` / `wmctrl` / `xclip` / `redshift`），要么在 GTK 桩里直接开 X 连接（`XGrabKey` / `XWithdrawWindow` / `_NET_WM_STATE` 族）。全仓零 Wayland 协议与 portal 代码：grep `wayland`/`portal` 的命中全是降级注释（`gui/sys/idle.mbt:12-13`、`gui/win/window.mbt:169`、`gui/win/window.mbt:580-581`、`gui/shell/hotkey.mbt:10-11`、`gui/win/stub.c:5409`、`gui/win/stub.c:7868`、`gui/sys/sys_stub.c:1937`、`gui/sys/sys_stub.c:2021`）。

**要走原生路径的原因**：测试发行版里 Wayland 正在从可选变默认——deepin 25 已把 Treeland（Wayland 合成器）作为默认方向、v25 Release 移除了 deepin-kwin 的 X11/Wayland 两档；Ubuntu 26.04 的 GNOME 桌面直接移除 Xorg 会话。X11 路径在这些会话下不是「降级可用」而是「死或给假数据」（§六），四行会话相关能力需要各自的 Wayland 通道。

**判据一句话**：每个系统能力在 Wayland 会话下，要么有一条不依赖 X 的原生通道真实可用，要么探针显式报 `Unsupported`——**不允许「命令返回成功但实际无效」的静默假数据**。与系统能力族既有的「探测 + 语义化降级」家规同一条口径（剪贴板、通知、托盘各族都是这么做的）。

## 二、现状盘点（带 file:line）

### 2.1 GUI 本体：无强制 X11，但 X11 专属分支处处有

- 建窗入口 `wm_init` 只调 `gtk_init_check`（`gui/win/stub.c:5203-5210`），**全仓没有 `GDK_BACKEND` 环境变量注入、没有 `gdk_set_allowed_backends` 调用**（grep 无命中）。GTK3 在 `WAYLAND_DISPLAY` 非空的会话自动选 Wayland 后端，应用本体照跑。
- GTK 桩 include 了 X11 头（`gui/win/stub.c:4806-4808`，`X11/Xlib.h` + `X11/Xatom.h` + `gdk/gdkx.h`），用途集中：全局热键 `XGrabKey`（7860 起）、`XWithdrawWindow` 撤管（5345-5367）、`_NET_WM_WINDOW_TYPE` / `_NET_WM_STATE` 客户端消息（5419-5515）。
- 所有 X11 直接调用点都有 `GDK_IS_X11_DISPLAY` 守卫（5365、5408、5470、6514、7111、7169 等），Wayland 下早退——**不会崩，但对应能力静默不生效**。
- `wm_shell_caps`（`gui/win/stub.c:5779-5792`）在 Wayland 下 `gdk_x11_display_get_xdisplay` 返回 NULL，合成器探测（`_NET_WM_CM_S0`）做不了 → caps 只给 title/borderless/layer 三位，opacity/transparent_bg 位不给。这是诚实口径：窗口透明 `gdk_window_set_opacity`（5379-5387）Wayland 档本就是无操作。
- **窗口层级族**（`wm_set_layer`，`gui/win/stub.c:5451-5515`；`gui/win/window.mbt:159-197`）：`gtk_window_set_keep_above/below`、`skip_taskbar` 在 Wayland 下只是客户端提示（注释明说「Wayland 下这几条只是客户端提示，兑现归 compositor」），`_NET_WM_STATE` 消息被 X11 守卫挡住。**Wayland 会话下五个层级档（Dock/Desktop/DesktopWidget/AlwaysOnTop/Normal）实际都不兑现**。roadmap 中「层级五档三平台真机通过」的 Linux 真机**验的是 X11 会话**——证据：`测试文档/测试用例.md:23`「Linux（Ubuntu 24.04 + X11 + XFCE）」，`experience/adaptation.md:36`「开发机是 Ubuntu 24.04 + X11 + XFCE」。Wayland 会话下层级族未验、预期不兑现。
- hide/show 的 `XWithdrawWindow` 只在 X11 走（5365 守卫），Wayland 走 `gtk_widget_hide` 常规路径；最大化走 `gtk_window_maximize`（Wayland 落 `xdg_toplevel` state，注释 5915-5916）。
- **弹层浮层**（`wm_window_set_popup`，5798-5821）全走 GTK（type_hint/transient/skip_taskbar），窗能开；但**屏幕绝对定位链路**——`gtk_window_move`（5837）/`gdk_window_get_origin`（5842-5866）——在 Wayland 下没有全局坐标系可依，预期失效或退化为 compositor 自摆。未实证，列 spike S8。

### 2.2 系统能力族通道盘点（逐项）

| 能力 | 现通道 | 证据 | Wayland 原生会话现状 |
|---|---|---|---|
| 显示器枚举 | 解析 `xrandr --query` | `gui/sys/monitor.mbt:739-762`（`mon_list` Linux 臂），解析纯函数 560-622 | **降级且带假名**：`pr_run` 保留 `DISPLAY`/`XAUTHORITY`（`gui/sys/procrun.mbt:198-214`），XWayland 下 xrandr 能跑，拿到的是 XWayland 视角（`XWAYLANDn` 输出名、模式列表受限）——具体形态待真机钉（spike S2） |
| 夜间色温 | `redshift -P -O <K>` 优先，否则 `xrandr --gamma` | `gui/sys/nightlight.mbt:197-215`（探测），244-273（设置），278-299（复位） | **死且静默**：redshift 走 X11 后端连 XWayland，gamma 请求不落地；更糟的是 `nl_supported()` 会因命令存在返回 true——「返回成功但无效」的典型 |
| 剪贴板读写 | GtkClipboard 真实现（住 `gui/win/stub.c` GTK 分支，经 `yue_sys_clipboard_gtk_*` 转发），xclip 命令线兜底 | `gui/sys/clipboard.mbt:38-47, 60, 97, 131-135` | **可用**：GtkClipboard 走 GDK Wayland 后端的 Wayland 剪贴板协议，不依赖 X |
| 剪贴板监视 | 纯轮询（默认 800ms）读同一落点 | `gui/sys/clipboard_watch.mbt:200-248` | **可用（轮询语义不变）**：读数走 GtkClipboard；但拿不到「变更事件」，且 Wayland 下源应用退出后剪贴板内容随之消失（Wayland 数据语义，无 clipboard manager 兜底时） |
| 窗口管理（枚举/激活/关闭） | `wmctrl -l` / `-a` / `-c` | `gui/sys/windowctl.mbt:411-422`（探测），445-448（列表），286/296（参数） | **死**：wmctrl 纯 EWMH，Wayland 会话里只能看到 XWayland 客户端窗口，原生窗口一个都看不见 |
| 空闲检测 | dlopen libX11+libXss 读 XScreenSaver 扩展 | `gui/sys/idle.mbt:12-14, 60-64`；`gui/sys/sys_stub.c:1979-2032` | **死且诚实**：`DISPLAY` 为空时 `idle_supported()=false`、`idle_seconds()` 给 `Unsupported` 不给错数（sys_stub.c:2019-2021）；注意 XWayland 下输入不进 X 服务端，XSS 读数虚高，所以连 XWayland 也不能用 |
| 全局热键 | 自开 X 连接 `XGrabKey` + 变体抓取，泵抽 | `gui/win/stub.c:7860-8010`；`gui/shell/hotkey.mbt:74-76, 82-99`；`gui/win/window.mbt:580-584` | **死且诚实**：`WAYLAND_DISPLAY` 非空恒 0（`stub.c:7911-7914`），门面给 `HotkeyError::Unsupported`（`hotkey.mbt:23`）；XWayland 的 grab 拿不到真全局性，不给假成功 |

### 2.3 已走 D-Bus / CLI、与 Wayland 无关的能力（确认不依赖 X）

- **托盘（SNI）**：纯 MoonBit StatusNotifierItem 直连会话总线，判据是 watcher 在线（`gui/shell/tray.mbt:93, 111` → `gui/dbus/sni.mbt:87`），不依赖 AppIndicator 运行库、不依赖 X。Wayland 会话照用；**host 侧要求**在 §4.3。
- **通知**：freedesktop Notifications（`org.freedesktop.Notifications`），`GetCapabilities` 定可用性（`gui/shell/notify.mbt:69`）。纯 D-Bus，Wayland 可用。
- **单实例**：D-Bus 知名名声称（`RequestName`，`gui/dbus/instance.mbt:101-122`），无总线回落 AF_UNIX（`gui/shell/instance.mbt` 头注）。Wayland 可用。
- **锁屏信号 / 休眠抑制 / MPRIS / UPower / 网络监控**：`gui/dbus/screensaver.mbt:7-9`、`gui/dbus/inhibit.mbt:7-9`（org.freedesktop.ScreenSaver / org.xfce.ScreenSaver 的 Inhibit）、`gui/dbus/media.mbt` 等，全会话/系统总线，Wayland 可用。
- **主题跟随 / 壁纸 / 默认应用**：GSettings 直读（`gui/win/stub.c:7502-7546`，org.gnome.desktop.interface）与 xfconf/gsettings CLI（`gui/sys/wallpaper.mbt:1-8, 306-308`）、`XDG_CURRENT_DESKTOP` 识别（`gui/sys/desktop.mbt:1-8`）。dconf/CLI 都不经 X，Wayland 可用。
- **文件对话框 / 消息框 / 音量 / 电源计划 / 自启动**：GTK 对话框（`stub.c:7447` 起）、wpctl/pactl、powerprofilesctl、`$XDG_CONFIG_HOME/autostart`（`gui/sys/autostart.mbt:9-15`）。均不依赖 X。
- **修正一处既有注记**：`experience/adaptation.md:293` 把 `org.freedesktop.ScreenSaver` 列为 Wayland idle 出路之一——该 portal 只有 Inhibit 没有读空闲口（§三），出路应为 GNOME IdleMonitor D-Bus 与 ext-idle-notify 协议。

## 三、能力出路总表

| 能力 | 现状 | 原生出路 | 成熟度 | 边界 |
|---|---|---|---|---|
| **全局快捷键** | 死（诚实报 Unsupported） | xdg-desktop-portal **GlobalShortcuts**：`CreateSession` → `BindShortcuts`（带 description/preferred_trigger）→ 后端弹**系统授权对话框**列快捷键供用户确认/改键 → `Response` 回实际绑定子集；`Activated`/`Deactivated`/`ShortcutsChanged` 信号驱动回调，`Activated` 可带 `activation_token` 拉窗；`ConfigureShortcuts`（v2）重开配置 UI | **可落**。前端随 portal 1.16（2022）发布；后端 KDE 自 **Plasma 5.27**、GNOME 自 **GNOME 48**（xdg-desktop-portal-gnome）支持 | 授权是每次绑定一弹，用户拒给空集；**xdg-desktop-portal-wlr 不实现**（issue #240 长期 open），Hyprland 等走自家协议；DDE 的 xdg-desktop-portal-dde README 未列 GlobalShortcuts——**未核**，deepin 25 待真机；标准化协议 ext-global-shortcuts-v1 截至 2026 中未合入 wayland-protocols mainline |
| **空闲检测** | 死（诚实报 Unsupported） | 三条：① GNOME `org.gnome.Mutter.IdleMonitor`（对象路径 `/org/gnome/Mutter/IdleMonitor/Core`）：`GetIdletime()→ms` **有精确读数**，`AddIdleWatch/AddUserActiveWatch/RemoveWatch` + `WatchFired` 信号；② KDE/wlroots 走 Wayland 协议 **ext-idle-notify-v1**（KWin 2022-09 合入，wlroots 系原生）：watch 事件式，**没有「当前空闲秒数」读数口**，可用「短间隔 watch + 记 last resumed」近似；③ portal **ScreenSaver/Inhibit 只有 Inhibit，没有读口**（官方文档钉死） | GNOME 通路成熟（idlemon/1Password 等在用）；KWin/wlroots 协议成熟但只事件式；KIdleTime 官方确认 Wayland 插件**不支持轮询** | 「读系统空闲秒数」的现语义在非 GNOME 会话只能近似；GNOME 沙盒（Flatpak）下 IdleMonitor 可能被挡（非沙盒无此问题，本仓非沙盒分发）；mutter 对 ext-idle-notify 的支持在 wayland.app 表出现 Mutter 51.x 条目——**未核**，GNOME 走 D-Bus 口即可不依赖它 |
| **夜灯/色温** | 死且静默（§2.2） | 无标准 portal（无 gamma/色温 portal）。三条：① KDE `org.kde.kwin.ColorCorrect`（Plasma 5，`/ColorCorrect`，`setNightColorConfig({Mode:3, NightTemperature:K})`）或 Plasma 6 的 `org.kde.KWin.NightLight`（`/org/kde/KWin/NightLight`，`running`/`toggle` 等）——**写 DE 自带夜灯的配置**；② GNOME 写 `org.gnome.settings-daemon.plugins.color` 的 night-light 键（gsettings，同样驱动 DE 自带夜灯）；③ wlroots 系走 **wlr-gamma-control-unstable-v1** 协议直设 gamma（本仓 gamma 曲线纯函数可直接对位） | wlr 协议成熟；KDE/GNOME 口成熟但都是「配置 DE 夜灯」不是裸 gamma，语义档位（K 值/开关）与现 API 的「percent 0-100 + reset」要对表 | **KWin 与 mutter 都不实现 wlr-gamma-control**（wlsunset 不支持 Plasma 实锤）——GNOME/KDE 下 gamma 直调路线不存在；KWin 两套接口的版本分界（ColorCorrect vs NightLight）未逐版本核，真机定；deepin（DDE）公开色温 D-Bus 口**未查到**；Treeland 是否给 wlr-gamma-control **未核** |
| **窗口管理** | 死（wmctrl 只见 XWayland 窗口） | **wlr-foreign-toplevel-management-unstable-v1**（枚举/激活/关闭/状态，wlroots 系原生支持）；KDE 用自家 **plasma-window-management**（非公开通用接口且有单客户端限制）；标准化枚举协议 ext-foreign-toplevel-list-v1 只有列表没有操作 | wlroots 成熟（labwc/sway 系可用）；**KWin 不实现 wlr-foreign-toplevel**（KDE bug 502647 截至 2025-12 open） | **GNOME 诚实边界：mutter 不实现且不开放**——GNOME Wayland 下「枚举/激活/关闭别的应用的窗口」没有合法通道，portal 也无对位；KDE 侧现也无解。本能力 Wayland 档只能收窄到 wlroots 系会话 |
| **剪贴板监视** | 可用（轮询） | **wlr-data-control-unstable-v1**（事件式变更通知，wlroots 系 + **KWin 支持**，wl-clipboard 即此路）；**Plasma 6.5 起迁 ext-data-control-v1**，旧协议-only 工具已出兼容事故（CopyQ #3228）——实现需双协议 | wlr 侧成熟；GNOME **mutter 明确不实现 wlr-data-control**（mutter issue #524），portal 无剪贴板对位 | GNOME 维持轮询档（可接受，现状本就是轮询）；Wayland 下复制源退出后内容丢失是协议语义，文档要写 |
| **显示器枚举** | 降级（XWayland 视角，待钉） | 三条：① mutter `org.gnome.Mutter.DisplayConfig.GetCurrentState`（会话总线，monitors 数组含厂商/型号/**物理尺寸 mm**/scale/模式列表；**私有/不稳定 API**，跨版本漂移，字段序以接口 XML 为准）；② KDE：kscreen-doctor CLI 或 kde-output-management-v2 协议（wlr-output-management **不被 KWin 支持**，wlr-randr 在 Plasma 不可用实锤）；③ wlroots 系 **wlr-output-management-unstable-v1**：name/description/**physical_size mm**/模式（size + refresh mHz + preferred）——字段与 xrandr 对位最全 | mutter 口成熟但私有（要锁版本探测）；wlr-output-management 成熟；**portal 无显示器枚举对位**（未核到任何提案落地） | xdg-output 协议只有逻辑位置/尺寸/名称，不给模式与物理尺寸；KDE 通道能拿到的字段（尤其物理尺寸）待真机核；「首选档」信号（preferred）wlr 协议有、mutter 有 flags，KDE 待核——与 roadmap「显示器首选档」条目联动 |
| **窗口层级族** | 降级（提示无效，兑现归 compositor） | 无跨 DE 对位。唯一候选 zwlr_layer_shell_v1（panel 档的正解），但 **KWin 不实现 layer-shell**（swaylock 在 Plasma 报缺协议）、**mutter 也不实现**——只覆盖 wlroots 系（labwc/Treeland?） | 低。收益面只有 wlroots 系会话 | **取舍：layer-shell 不进本方案**（不进首批、也不立独立条目）——测试矩阵四个 DE 里 KDE/GNOME 双双不支持，单为 labwc 档引入 Wayland 协议客户端地基不划算；面板档在 Wayland 会话按「由 compositor 决定、不承诺」出声，文档记边界，等 Treeland 矩阵（S5）有结果再议 |
| 托盘/通知/单实例/抑制/MPRIS | 可用（§2.3） | 无需改 | — | host 侧要求见 §4.3 |

## 四、平台与 DE 成熟度

### 4.1 测试发行版默认会话（外部事实，标来源）

| 发行版 | 默认会话 | 事实与来源 |
|---|---|---|
| deepin 23 | **X11**（dde-kwin） | 发布时 DDE 默认 X11；beta3 起弃用 deepin-kwin 的 Wayland 档，Wayland 由 Treeland 以技术预览提供（DDE 移植指南） |
| deepin 25 | **Wayland（Treeland）为默认方向** | v25 正式版推 Treeland；v25 Release 分支已移除 deepin-kwin-x11/-wayland（developer-center issue #12775）；ddm 为显示管理器，可切回 X11 |
| Ubuntu 24.04 LTS（GNOME） | **Wayland**（Intel/AMD；NVIDIA 可能回退 Xorg，登录齿轮可选 Xorg） | 21.04 起的既定策略 |
| Ubuntu 26.04 LTS（GNOME） | **Wayland-only**——默认 GNOME 桌面移除 Xorg 会话 | 携 GNOME 49.2 |
| KDE（Plasma 6） | **Wayland 默认**（Plasma 6.0 起） | Ubuntu 味具体版本未核：Kubuntu 24.04 若带 Plasma 5.27 则默认 X11、26.04 带 Plasma 6 默认 Wayland——**待核**，影响 KDE 档排期 |
| XFCE | X11 为主体；4.20（2024-12）带**实验性** Wayland 会话，默认合成器 **labwc**（wlroots 系） | Xubuntu 24.04（XFCE 4.18）无 Wayland 会话，26.04 是否带 4.20 Wayland **未核** |
| Cinnamon | X11 默认；6.0（Mint 21.3）起实验性 Wayland 会话，默认关 | Ubuntu Cinnamon 味同理，Wayland 非默认 |

结论：**承诺矩阵里 GNOME（24.04/26.04）与 deepin 25（Treeland）是本方案的第一现实**；XFCE/KDE/Cinnamon 的 Wayland 会话在承诺期内是实验/可选档。

### 4.2 DE/合成器支持矩阵（汇总 §三）

| 通道 | GNOME（mutter） | KDE（KWin） | wlroots 系（labwc/sway/Treeland?） | DDE（deepin） |
|---|---|---|---|---|
| GlobalShortcuts portal | ✅ 48+ | ✅ 5.27+ | ❌（portal-wlr 不做） | 未核 |
| IdleMonitor D-Bus（GetIdletime） | ✅ | ❌ | ❌ | 未核 |
| ext-idle-notify-v1 | 未核（表现 51.x） | ✅（2022-09 起） | ✅ | 未核 |
| 夜灯口 | gsettings→gsd-color（配置档） | ColorCorrect / NightLight（配置档） | wlr-gamma-control（裸 gamma） | 未查到公开口 |
| wlr-foreign-toplevel-management | ❌（不开放） | ❌（bug 502647 open） | ✅ | 未核 |
| wlr-data-control（+ext） | ❌（mutter#524） | ✅（6.5 迁 ext-data-control） | ✅ | 未核 |
| DisplayConfig / 输出枚举 | ✅ DisplayConfig D-Bus（私有） | kscreen-doctor / kde-output-management-v2 | wlr-output-management（含物理尺寸 mm） | 未核 |
| zwlr_layer_shell_v1 | ❌ | ❌ | ✅（labwc 等） | 未核 |

### 4.3 与既有规划的咬合

- **托盘/通知（SNI/Notifications）本就走会话总线**，Wayland 会话不受影响（§2.3 证据）。SNI 在 Wayland 的 host 侧要求 = 面板实现 StatusNotifierWatcher：KDE/XFCE/Cinnamon 面板与 deepin dde-shell 均有；**GNOME Shell 裸版没有**，要 AppIndicator 扩展（Ubuntu 预装、Fedora 裸版不带）——这条边界属于 roadmap「KDE / GNOME / DDE 实测」条目的托盘行，与本方案共用真机会话但不重复立项。
- **「KDE / GNOME / DDE 实测」条目验的是 D-Bus 族 host 可用性**（托盘、通知、深浅色、壁纸、默认应用），本方案验的是会话相关四项 + 层级/浮层行为；两者可在同一批真机 spike 里搭车执行（spike S1 的会话环境即它的执行环境），结论各自回填 roadmap 两张表。
- roadmap「Linux 兼容说明 · 会话」表的「Wayland 侧出路」列按本方案更新：全局快捷键 → portal（双端可落）；空闲检测 → GNOME 有精确读数口、KDE/wlroots 走事件近似（比「退有焦点才计时」的现行说法好）；窗口控制 → 仅 wlroots 系有协议通道，GNOME/KDE 记边界；剪贴板监视 → KDE/wlroots 协议化，GNOME 维持轮询；显示器与夜灯 → mutter/KWin/wlr 各有口（夜灯在 GNOME/KDE 是配置 DE 夜灯档）。

## 五、分期与 spike 清单

### 分期

- **P0 会话探测与口径收口**（改动小，全 MoonBit + 少量 C 探针）：加会话类型探针（`XDG_SESSION_TYPE` + `WAYLAND_DISPLAY`），把 idle/hotkey/nightlight/monitor/windowctl 五个能力在 Wayland 会话的行为统一钉住——本就诚实的（idle/hotkey）保持；静默假数据的（§六）在探测处显式降级：nightlight 在 Wayland 会话 `nl_supported()` 不得因 redshift 可执行而报 true，monitor 的 XWayland 假名输出在 caps/文档声明。产出一张「Wayland 会话能力预期表」进测试文档。
- **P1 portal 骨架 + 全局快捷键 + 空闲检测**：`gui/dbus` 加 portal 客户端通用层（Request/Response handle、session_handle 通道，`bus.mbt` 已有 subscribe/call_sync 地基）；接 GlobalShortcuts（门面从「注册+poll」改为「绑定+信号回调」的形态要设计，`hotkey_register`/`hotkey_poll` 语义在 Wayland 档的变化写进接口文档）；空闲检测 GNOME 档走 IdleMonitor（`GetIdletime` 精确读数，`idle_seconds` 语义原样保住）、KDE/wlroots 档走 ext-idle-notify watch 近似（误差语义写文档）。
- **P2 夜灯 + 显示器枚举逐 DE**：夜灯分三档（KDE 配置口 / GNOME gsettings 配置口 / wlroots wlr-gamma-control 裸 gamma）；显示器枚举接 mutter DisplayConfig（锁版本探测）与 wlr-output-management，KDE 通道按 spike S7 结果定（kscreen-doctor CLI vs 协议）。**本批首次出现「直连 Wayland 协议」的组件**（wlr-gamma-control / wlr-output-management），要立架构位：libwayland 客户端 or 仿 `dbus/wire.mbt` 自写 Wayland wire（本仓有 dbus 自写 wire 的先例，工作量另评）。
- **P3 剪贴板监视协议化 + wlroots 窗口管理 + 收尾**：wlr-data-control（+ext-data-control-v1 双协议）替换 KDE/wlroots 下的轮询档，GNOME 维持轮询并记边界；窗口管理 Wayland 档只做 wlroots 系（wlr-foreign-toplevel）；GNOME/KDE 侧的窗口管理与层级族按「无通道」出文档。

### spike 清单

| # | 验证什么 | 在哪验 | 判据 |
|---|---|---|---|
| S1 | GTK3 本体在 Wayland 会话的全量行为：渲染/输入/IME/浮层开窗/拖放/透明 | Ubuntu 24.04 GNOME Wayland + deepin 25 Treeland，跑 hello/showcase 过测试用例相邻条目 | 相邻条目通过；差异逐条记 `experience/adaptation.md` |
| S2 | XWayland 静默降级实测：`xrandr --query` 输出形态（是否 XWAYLANDn 假名/模式列表）、`redshift -P -O` 退出码与实际效果、`wmctrl -l` 可见窗口集合 | 同上两个 Wayland 会话 | 每条给出「返回成功但无效」清单，定 P0 探针写法 |
| S3 | GlobalShortcuts portal 全流程：CreateSession→BindShortcuts 授权框→Activated 回调→拒绝给空集 | KDE Plasma 6 Wayland 一台 + GNOME 48+ 一台 | 授权框出现、回调可达、handle 时序坑记录（Request/Response 的 bus 层适配点） |
| S4 | 空闲检测：GNOME `GetIdletime` 对照手动计时；KDE/wlroots ext-idle-notify 1s-watch 近似档误差 | GNOME 与 KWin Wayland 各一台 | 精确档误差 ±1s；近似档误差写进文档语义 |
| S5 | Treeland 协议面：探测 wlr-foreign-toplevel/data-control/gamma-control/idle-notify/layer-shell/xdg-output 的 global 是否存在（wayland-info 或 bind 试探） | deepin 25 真机（Treeland） | 一张 Treeland 支持矩阵，回填本方案 §4.2 与 roadmap |
| S6 | 夜灯配置口：KWin `setNightColorConfig({Mode:3,NightTemperature})`（或 Plasma 6 NightLight 口）与 GNOME 写 night-light gsettings 的生效与复位 | KDE 与 GNOME Wayland 各一台 | 肉眼色温变化且可复位；两套 KWin 接口的版本分界定案 |
| S7 | 显示器枚举字段对照：DisplayConfig GetCurrentState / kscreen-doctor / wlr-output-management 各拿 name/分辨率/刷新率/物理尺寸/模式列表哪些字段 | GNOME、KDE、labwc 各一台 | 与 xrandr 档字段对照表，定 Wayland 档 `MonitorInfo` 字段缺口与文档口径 |
| S8 | 弹层定位：showcase 浮层在 Wayland 下 `gtk_window_move`/`gdk_window_get_origin` 实际行为 | S1 同场 | 决定「浮层原生档」条目的 Wayland 工作量 |

## 六、风险与坑

- **XWayland 静默假数据是最大的坑**：`pr_run` 保留 `DISPLAY`/`XAUTHORITY`（`procrun.mbt:198-214`）让 xrandr/redshift/wmctrl 在 Wayland 会话照常起进程；monitor 可能解析出假名虚拟屏、nightlight 的 gamma 设置与 wmctrl 动作可能退出 0 而无效。P0 必须先堵，否则上层应用拿着假读数做布局/护眼决策。
- **portal 的 Request/Response 时序**：portal 全族用 `handle_token` 造 Request 对象、结果走 `Response` 信号，`bus.mbt` 现有同步 call + subscribe 形态要适配异步握手；各 backend（尤其 GNOME）对 session_handle 的 s/o 类型兼容 quirk 官方文档明示要容。
- **私有口漂移**：mutter DisplayConfig 是私有/不稳定 API，跨 GNOME 版本字段会变——锁版本探测 + 字段缺失容忍，探测失败显式降级，不猜字段。
- **KWin 接口版本分界未核**：ColorCorrect（Plasma 5）与 NightLight（Plasma 6）的并存区间要 S6 定，否则 KDE 档会在某发行版上打错接口。
- **Plasma 6.5 的 ext-data-control 迁移**：只实现旧 wlr-data-control 的客户端在 Plasma 6.5+ 会失效（CopyQ 事故在先），P3 必须双协议。
- **直连 Wayland 协议是新地基**：首个 wlr 协议客户端（wire 格式、registry 绑定、事件分发）工作量与 dbus-wire 不同量级，P2 立项时单独评；不评估就动手是本方案最大的隐性成本。
- **deepin 25 快速演进**：ddm/Treeland 自身还在 0.5.x，portal 后端（xdg-desktop-portal-dde）接口表长期不维护（README 的 Implemented/TODO 表自相矛盾），S5/S3 结论要带版本号写。
- **GTK3 Wayland 后端的能力边界**：窗口 opacity/透明底探测已在 caps 收口（§2.1），但弹层定位（S8）、`gtk_window_present` 激活是否走 xdg-activation 未核——这两个影响浮层与「唤起已有实例」的观感，都要真机读数。
- **GNOME 侧产品化边界**：GNOME Wayland 下窗口管理无通道、剪贴板监视只能轮询、夜灯只能写 DE 配置——文档与能力探针要把它说成「平台边界」而不是「库缺陷」，与「最近文件 macOS 无公开面」同一条口径。

## 七、验收口径

1. `moon check` / `moon test`（指定包清单）零错误零警告，与家规一致；Wayland 协议客户端（C 桩）过 ASan 套（若走 libwayland/自写 wire，按 moonbit-c-binding 技能的验收形态）。
2. 会话矩阵：`测试文档/测试用例.md` 补 Wayland 会话条目（SC 系，记录台现算），至少覆盖 deepin 25 Treeland 与 Ubuntu GNOME Wayland 两台；X11 全量用例不退（含 SC-10.2 的 Wayland 预期更新为实际能力）。
3. **「返回成功但无效」清零**：P0 后在任一 Wayland 会话，五个会话相关能力的探针输出与文档口径一一对应——不可用的必须 `Unsupported`，可用的必须真有效（以 S2 的实测清单为红线）。
4. 每条 P1/P2 能力的真机验收由用户执行（助手给操作步骤清单），结论回 `experience/adaptation.md` 与 roadmap 表；roadmap「Wayland 原生路径」条目按平台标 ✅/🚧/❌/⏳。
5. roadmap「Linux 兼容说明 · 会话」表、「KDE / GNOME / DDE 实测」矩阵与 `TODO.md` 同批更新，三者不得互相矛盾。

## 八、证据清单

**仓库（file:line）**

- `gui/sys/idle.mbt:12-14,23-29,60-87`（空闲 X11 通路与 Wayland 诚实降级）
- `gui/sys/sys_stub.c:1929-2032`（XSS dlopen、`DISPLAY` 探测）
- `gui/win/stub.c:4806-4808`（X11 头）、`5203-5210`（gtk_init_check 无后端强制）、`5345-5367`（XWithdrawWindow 守卫）、`5379-5387`+`5774-5792`（opacity 与 caps）、`5407-5417`+`5440-5515`（窗口层级/`_NET_WM_STATE`）、`5798-5866`（弹层与定位）、`7860-8010`（XGrabKey 三件套、`WAYLAND_DISPLAY` 探测）
- `gui/win/window.mbt:159-197`（层级档注释「Wayland 兑现归 compositor」）、`580-584`（hotkey_supported）
- `gui/sys/monitor.mbt:739-762`（xrandr 通道）、`gui/sys/nightlight.mbt:197-215,244-299`（redshift/xrandr 通道）
- `gui/sys/clipboard.mbt:38-47,52-70,75-146`（GtkClipboard 转发层 + xclip 兜底）、`gui/sys/clipboard_watch.mbt:200-248`（轮询）
- `gui/sys/windowctl.mbt:286-298,411-448`（wmctrl 通道）
- `gui/sys/procrun.mbt:198-214`（子进程环境保留 DISPLAY/XAUTHORITY/WAYLAND_DISPLAY）
- `gui/dbus/sni.mbt:87`、`gui/shell/tray.mbt:6-7,93,111`（SNI watcher 判据）；`gui/shell/notify.mbt:69`（GetCapabilities）；`gui/dbus/instance.mbt:101-122`（RequestName）；`gui/dbus/screensaver.mbt:7-9`、`gui/dbus/inhibit.mbt:7-9`（锁屏信号与抑制）；`gui/dbus/media.mbt`（MPRIS）；`gui/win/stub.c:7502-7546,7549-7608`（GSettings 深浅/主色）
- `gui/sys/desktop.mbt:1-8`、`gui/sys/wallpaper.mbt:1-8,306-308`、`gui/sys/autostart.mbt:9-15`（DE 识别/壁纸/自启）
- `测试文档/测试用例.md:23`（Linux 真机 = Ubuntu 24.04 + **X11** + XFCE）、`:170`（SC-10.2 Wayland 预期）；`experience/adaptation.md:36`（开发机同）、`:263`（热键 Wayland 口径）、`:293`（idle 出路注记，本方案 §2.3 修正）

**外部（检索于 2026-11-03）**

- GlobalShortcuts portal 规格与授权交互：[xdg-desktop-portal 文档](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.GlobalShortcuts.html)；KDE 5.27 支持：[KDE 公告讨论](https://www.reddit.com/r/linux/comments/xrk9vf/preliminary_support_for_global_keyboard_shortcuts)、[xdg-desktop-portal-kde MR](https://invent.kde.org/plasma/xdg-desktop-portal-kde)；GNOME 48 支持：[GNOME Discourse 诉求](https://discourse.gnome.org/t/feature-request-globalshortcuts-portal/15343)；portal-wlr 不做：[issue #240](https://github.com/emersion/xdg-desktop-portal-wlr/issues/240)
- portal ScreenSaver/Inhibit 无读口：[Inhibit 官方文档](https://flatpak.github.io/xdg-desktop-portal/docs/doc-org.freedesktop.portal.Inhibit.html)
- Mutter IdleMonitor：`GetIdletime`/`AddIdleWatch`/`WatchFired` 与对象路径 [phosh 接口文档](https://phosh-a5dbaf.pages.gitlab.gnome.org/iface.IdleDBusIdleMonitor.html)、[idlemon](https://github.com/k4yt3x/idlemon)、[实测 D-Bus 流量](https://stackoverflow.com/questions/79660658/wake-up-gnome-gdm-from-lockscreen-via-touchscreen)
- KIdleTime Wayland 不支持轮询：[KDE 论坛（Plasma 6 实测）](https://discuss.kde.org/t/is-it-possible-to-detect-idle-time-on-plasma-6-widgets-on-wayland/30434)；ext-idle-notify-v1 KWin 合入 [MR !2959](https://invent.kde.org/plasma/kwin/-/merge_requests/2959)、协议页 [wayland.app](https://wayland.app/protocols/ext-idle-notify-v1)
- KWin 夜灯口：[org.kde.kwin.ColorCorrect 用法（setNightColorConfig/Mode=3）](http://zren.github.io/2020/05/14/nightcolorpy-for-setting-temp-from-terminal)、[KWin NightLight DBus MR](https://invent.kde.org/plasma/kwin/-/merge_requests/4616)、[dbusinterface.h](https://invent.kde.org/plasma/kwin/-/blob/master/src/dbusinterface.h)
- KWin 不实现 wlr-gamma-control：[wlsunset 项目页（受支持的 compositor 清单）](https://sr.ht/~kennylevinsen/wlsunset)、[Debian 包描述](https://packages.debian.org/sid/armhf/wlsunset)；mutter 同：[GNOME Wayland gamma 讨论](https://forum.manjaro.org/t/gamma-support-on-gnome-wayland/50341)
- wlr-foreign-toplevel：KWin 未实现 [KDE bug 502647](https://bugs.kde.org/show_bug.cgi?id=502647)；mutter 拒绝 wlr-data-control [mutter issue #524](https://gitlab.gnome.org/GNOME/mutter/-/issues/524)；GNOME 私有扩展与 toplevel-tag [Phoronix](https://www.phoronix.com/news/Mutter-Merges-Toplevel-Tag)
- wlr-output-management 字段（含 physical_size mm）：[协议页](https://wayland.app/protocols/wlr-output-management-unstable-v1)；KWin 不支持（wlr-randr 失效、用 kde-output-management）：[Plasma Wayland 显示管理讨论](https://www.reddit.com/r/kde/comments/1ddkivh/kde_plasma_wayland_clipboard_not_working_under)（同帖含 wlr-data-control 支持）
- mutter DisplayConfig 接口（物理尺寸字段存在）：[接口 XML](https://gitlab.gnome.org/GNOME/mutter/-/blob/main/data/dbus-interfaces/org.gnome.Mutter.DisplayConfig.xml)（字段序以 XML 为准，未逐字段核）
- Plasma 6.5 迁 ext-data-control-v1：[CopyQ issue #3228](https://github.com/hluk/CopyQ/issues/3228)
- deepin：portal 后端接口表 [xdg-desktop-portal-dde](https://github.com/linuxdeepin/xdg-desktop-portal-dde)；deepin 23 默认 X11/Treeland 预览、deepin 25 默认方向 [DDE 移植指南](https://deepin-community.github.io/sig-dde-porting/posts/deepin-25-beta-dde-porting-guide/)、[v25 移除 deepin-kwin](https://github.com/linuxdeepin/developer-center/issues/12775)；dde-shell/SNI [deepin 动态](https://planet.deepin.org/page/4)
- 发行版会话：Ubuntu 24.04 Wayland 默认（Intel/AMD）与 26.04 Wayland-only [Ubuntu 迁移报道](https://www.omgubuntu.co.uk/2025/10/ubuntu-26-04-drops-xorg-session)（NVIDIA 回退见 [Ubuntu 文档口径](https://discourse.ubuntu.com/t/wayland-default-in-21-04/17986)）；Plasma 6 默认 Wayland [KDE 公告](https://news.ycombinator.com/item?id=38229576)；XFCE 4.20 实验性 Wayland/labwc [Xfce Wayland 路线](https://wiki.xfce.org/releng/wayland_roadmap)；Cinnamon 6.0 实验性 Wayland [Mint 21.3 发布注记](https://www.linuxmint.com/rel/virginia.php)
- GNOME SNI 需 AppIndicator 扩展：[扩展页](https://extensions.gnome.org/extension/615/appindicator-support/)、[Fedora 预装诉求 bug](https://bugzilla.redhat.com/show_bug.cgi?id=1709401)

**未核/不确定点汇总**（均已在正文标注）：Treeland 协议面（S5）；deepin portal 是否接 GlobalShortcuts；mutter DisplayConfig 元组逐字段序；KWin ColorCorrect/NightLight 版本分界（S6）；KDE 输出通道物理尺寸（S7）；mutter 对 ext-idle-notify 的落地版本；Kubuntu/Xubuntu/Ubuntu Cinnamon 各味的 Plasma/XFCE/Cinnamon 版本与默认会话；`gtk_window_present` 在 Wayland 是否走 xdg-activation；XWayland 下 xrandr 输出的确切形态（S2）。
