# linux-mbt：Linux 桌面系统特性独立包（规划）

## 定位

跨平台库 `native-gui` 只收三平台能统一抽象的能力；**Linux 桌面系统特性**（Wayland 协议客户端、portal 族、DE 专属通道）不进跨平台库。按 roadmap 远期规划（`windows-mbt` / `*DE-mbt` / `mac-mbt`），Linux 发行版差异大、以桌面环境方式发布，底层封装 `linux-mbt`。

本文件承接原先挂在跨平台任务里的 Wayland / DE 专属条目：已落代码记为过渡现状，剩余工作与 spike 清单收在这里，等 linux-mbt 立项迁走。技术方案细节仍在 [wayland-native.md](wayland-native.md)（能力出路总表、DE 支持矩阵、坑清单、spike 判据 §五），本文件不复制。

## 过渡现状（代码已在跨平台库）

- `gui/wayland`：自写 wire 协议客户端地基（connect/registry/enumerate/bind，headless weston 实测 19 global 与 wayland-info 吻合；选型「自写不链 libwayland」）。
- `gui/dbus/portal.mbt`：portal Request/Response 异步握手通用层（token → request 路径派生 → Response 一次性订阅）。
- `gui/shell/global_shortcuts.mbt`：GlobalShortcuts 绑定 + Activated 回调门面。
- `gui/shell/idle.mbt`：GNOME IdleMonitor 精确读数 + 集成门面（D-Bus 优先、回落 `@sys`）。
- `gui/shell/nightlight.mbt`：夜灯 GNOME 写配置键 / KDE ColorCorrect 读侧。
- `gui/shell/monitor_dbus.mbt`：KScreen `getConfig` 解析；mutter DisplayConfig 只探存在。
- `@sys.session_type()`：Wayland 会话探针（夜灯/窗口管理显式 `Unsupported`，显示器枚举按 XWayland 虚拟屏口径声明，预期表见测试文档附录 E）。

迁移口径：随 linux-mbt 立项迁出；迁移前维持现状，不再向跨平台 API 面扩展。

## 剩余工作

### Spike

- **S1/S2（本体行为 + XWayland 假数据实测）**：Ubuntu 24.04 GNOME Wayland + deepin 25 Treeland 跑 hello/showcase 相邻条目；xrandr 输出形态 / redshift 退出码与实际效果 / wmctrl 可见窗口集合——产出「返回成功但无效」清单，定 P0 探针写法（判据见 wayland-native.md §五）。
- **S3–S8**：GlobalShortcuts 全流程（KDE+GNOME 各一台）、空闲双档误差、Treeland 协议面探测矩阵、夜灯配置口生效与复位、显示器字段对照、弹层定位。

### 已落部分的真机清单

- **P1 GlobalShortcuts 授权框**：KDE 5.27+/GNOME 48+ 各一台（本机会话走 GTK 后端，握手报错属预期）；ext-idle-notify 近似档（KDE/wlroots）待协议客户端地基。
- **P2 剩余**：wlroots 裸 gamma（待协议客户端）；mutter DisplayConfig 字段序（S7 真机定，不许猜字段序产假读数）；Plasma 6 NightLight 写入口径（未核）。

### P3 协议客户（待写）

- 剪贴板监视：`wlr-data-control` + `ext-data-control`。
- 窗口管理：`wlr-foreign-toplevel`。
- 显示器 / 色温：`wlr-output-management`、`wlr-gamma-control`。
- 空闲近似档：`ext-idle-notify`。
- **fd 传递（SCM_RIGHTS）**——data-control 的 receive 需要。
- GNOME/KDE 窗口管理与层级族按「无通道」出文档（layer-shell 不进：KDE/GNOME 双双不支持）。

### DE 实测矩阵

托盘、通知、深浅色、壁纸、默认应用的桌面环境矩阵（KDE / GNOME / DDE 各一）。
