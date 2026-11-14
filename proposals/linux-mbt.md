# linux-mbt：Linux 桌面系统特性独立包·规划

## 定位

跨平台库 `native-gui` 只收三平台能统一抽象的能力；**Linux 桌面系统特性**不进跨平台库。按 roadmap 远期规划 `windows-mbt` / `*DE-mbt` / `mac-mbt`，Linux 发行版差异大、以桌面环境方式发布，底层封装 `linux-mbt`。
  - 范围：Wayland 协议客户端、portal 族、DE 专属通道。
  - DE：桌面环境，如 XFCE、KDE、GNOME。
  - Wayland：Linux 的新一代窗口显示协议，应用与合成器经它通信。
  - portal：Linux 桌面给应用提供的统一能力门户，如文件选择、打开链接。

本文件承接原先挂在跨平台任务里的 Wayland / DE 专属条目：已落代码记为过渡现状，剩余工作与 spike 清单收在这里，等 linux-mbt 立项迁走。技术方案细节仍在 [wayland-native.md](wayland-native.md)，本文件不复制。
  - spike：为验证一个技术问题专门做的探索性小实验，结论落档、代码可弃。
  - 范围：能力出路总表、DE 支持矩阵、坑清单、spike 判据 §五。

## 过渡现状·代码已在跨平台库

- `gui/wayland`：自写 wire 协议客户端地基。
  - 范围：connect/registry/enumerate/bind。
  - 取证：headless weston 实测 19 global，与 wayland-info 吻合。
  - 选型：自写不链 libwayland。
  - wire 协议：Wayland 客户端与服务端之间的底层二进制通信协议。
  - headless：不开真实屏幕、在无显示环境里跑。
  - weston：Wayland 的官方参考合成器，即管理窗口与画面的服务端程序。
- `gui/dbus/portal.mbt`：portal Request/Response 异步握手通用层。
  - 流程：token → request 路径派生 → Response 一次性订阅。
  - D-Bus：Linux 桌面的进程间通信总线，portal 就架在它上面。
- `gui/shell/global_shortcuts.mbt`：GlobalShortcuts 绑定 + Activated 回调门面。
  - 门面：把一组底层调用包成一个简单入口的封装层。
- `gui/shell/idle.mbt`：GNOME IdleMonitor 精确读数 + 集成门面。
  - 策略：D-Bus 优先、回落 `@sys`。
- `gui/shell/nightlight.mbt`：夜灯 GNOME 写配置键 / KDE ColorCorrect 读侧。
- `gui/shell/monitor_dbus.mbt`：KScreen `getConfig` 解析；mutter DisplayConfig 只探存在。
  - KScreen：KDE 的显示器配置服务。
  - mutter：GNOME 的窗口合成器与显示配置服务。
- `@sys.session_type()`：Wayland 会话探针。
  - 范围：夜灯/窗口管理显式 `Unsupported`。
  - 显示器枚举按 XWayland 虚拟屏口径声明，预期表见测试文档附录 E。
  - XWayland：在 Wayland 里兼容跑老 X11 应用的桥接层。

迁移口径：随 linux-mbt 立项迁出；迁移前维持现状，不再向跨平台 API 面扩展。

## 剩余工作

### Spike

- **S1/S2**：Ubuntu 24.04 GNOME Wayland + deepin 25 Treeland 跑 hello/showcase 相邻条目；xrandr 输出形态 / redshift 退出码与实际效果 / wmctrl 可见窗口集合——产出「返回成功但无效」清单，定 P0 探针写法。
  - 范围：本体行为 + XWayland 假数据实测。
  - 依据：判据见 wayland-native.md §五。
  - deepin：国产 Linux 发行版。
  - Treeland：deepin 25 的 Wayland 合成器。
  - xrandr：X11 的显示器设置命令行工具。
  - redshift：按时间调屏幕色温的命令行工具。
  - wmctrl：列出与管理窗口的命令行工具。
- **S3–S8**：GlobalShortcuts 全流程、空闲双档误差、Treeland 协议面探测矩阵、夜灯配置口生效与复位、显示器字段对照、弹层定位。
  - 范围：KDE+GNOME 各一台。
  - 弹层：临时弹出的小窗口或浮层。

### 已落部分的真机清单

- **P1 GlobalShortcuts 授权框**：KDE 5.27+/GNOME 48+ 各一台；ext-idle-notify 近似档待协议客户端地基。
  - 环境：本机会话走 GTK 后端，握手报错属预期。
  - 适用：ext-idle-notify 近似档适用 KDE/wlroots。
  - GTK：GNOME 生态的界面工具库。
  - wlroots：常用的一套 Wayland 合成器构建库。
- **P2 剩余**：wlroots 裸 gamma；mutter DisplayConfig 字段序；Plasma 6 NightLight 写入口径。
  - wlroots 裸 gamma：待协议客户端。
  - mutter DisplayConfig 字段序：S7 真机定，不许猜字段序产假读数。
  - Plasma 6 NightLight 写入口径：未核。
  - gamma：屏幕的伽马曲线，调色温靠改它。
  - Plasma：KDE 的桌面环境实现。

### P3 协议客户·待写

- 剪贴板监视：`wlr-data-control` + `ext-data-control`。
- 窗口管理：`wlr-foreign-toplevel`。
- 显示器 / 色温：`wlr-output-management`、`wlr-gamma-control`。
- 空闲近似档：`ext-idle-notify`。
- **fd 传递**——data-control 的 receive 需要。
  - SCM_RIGHTS：Linux 进程间经套接字传文件描述符的机制。
- GNOME/KDE 窗口管理与层级族按「无通道」出文档。
  - layer-shell 不进：KDE/GNOME 双双不支持。
  - layer-shell：在壁纸、面板这类层上放窗口的 Wayland 协议。

### DE 实测矩阵

托盘、通知、深浅色、壁纸、默认应用的桌面环境矩阵。
  - 范围：KDE / GNOME / DDE 各一。
  - 托盘：任务栏旁的常驻小图标区，后台应用的图标放这里。
  - DDE：deepin 的桌面环境。
