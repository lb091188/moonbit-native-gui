# 桌面与显示

桌面外观（色温 / 壁纸）与显示设备（显示器 / 窗口管理）。统一 `Result` 语义与支持矩阵见[系统能力总览](sys.md)。

## 桌面会话类型

Linux 上「跑在 X11 还是 Wayland」决定一整个工具族能不能信。Wayland 会话里 X 工具照常起进程、照常退出码 0（XWayland 在底下接着），读数却是兼容层的假数——所以本库把它们在探测处显式降级，不拿假数冒充成功。

| 函数 | 说明 |
|---|---|
| `session_type() -> SessionType` | 读本机环境给会话类型：`X11` / `Wayland` / `Unknown` |
| `session_type_of(xdg_session_type, wayland_display) -> SessionType` | 纯解析，便于按自有的环境值判定：`XDG_SESSION_TYPE` 说话在先（认 `wayland` / `x11`，大小写与空白不敏感），没写时回落 `WAYLAND_DISPLAY` 非空即 Wayland |
| `in_wayland_session() -> Bool` | 能力族用的门 |

按此降级的能力：**夜间色温**（`nl_supported()` 恒 false，设/复位给 `Unsupported`）、**窗口管理**（`win_supported()` false，列表/激活/关闭给 `Unsupported`）、**空闲检测与全局快捷键**（Linux 走 X11 服务端与 X 抓键，Wayland 原生会话本就不支持——见[路线图](../reference/roadmap.md)「Linux 兼容说明」的会话表）。**显示器枚举**不降级：XWayland 那块虚拟屏确实存在，但按「不是真接的屏」这个口径读，字段别拿去做布局或采购判断；Wayland 侧的真通道在规划里（`proposals/wayland-native.md` P2）。

## 夜间色温

以百分比 0-100 表示色温（0 = 最暖、100 = 6500K 中性即不改动）。两条后端自动探测：`redshift` 存在时优先（`-P -O <K>` 一次性设色温），否则 `xrandr --output <首选输出> --gamma R:G:B`（蓝通道衰减越多越暖；绿通道恒 1.00）。

| 函数 | 说明 |
|---|---|
| `nl_supported() -> Bool` | redshift 或 xrandr 任一可用，且不在 Wayland 会话（探测均为只读调用，无副作用） |
| `nl_set_temperature(percent) -> Result[Unit, NightlightError]` | 设色温（0-100，出界钳制；redshift 路径 0→2500K / 100→6500K） |
| `nl_reset() -> Result[Unit, NightlightError]` | 复位（redshift `-x` / `xrandr --gamma 1.00:1.00:1.00`，不带 `--output` 作用于全部输出） |

错误 `NightlightError`：`Unsupported`（非 Linux、Wayland 会话，或 redshift 与 xrandr 均不可用、xrandr 无已连接输出）/ `CommandFailed(String)`。Wayland 会话下 `nl_supported()` 恒 false：redshift / xrandr 的 gamma 只作用在 XWayland 兼容层，进程起得来、退出码 0、屏幕上没变化——按不支持报，不给假生效。xrandr 路径从当前主输出取，无主输出取首个已连接输出。

```moonbit
let _ = @sys.nl_set_temperature(30) // 偏暖
let _ = @sys.nl_reset()
```

## 壁纸

Windows 走 `SystemParametersInfoW`（SPI_SETDESKWALLPAPER）直调。Linux 按 `XDG_CURRENT_DESKTOP` 分派，DE 识别用 sys 包内自带的纯函数。**XFCE** 走 `xfconf-query` 读写 xfce4-desktop 频道的 `/backdrop/<screen>/monitor<输出>/<workspace>/last-image` 属性（多个显示器时取已连接输出）；**KDE** 走 `qdbus6`/`qdbus` 调 plasmashell 的 `evaluateScript`；本仓库未在 KDE 真机验证。其余 gsettings 系桌面由一张落点表统一驱动（读写同一表）：**GNOME** 与同 schema 的衍生桌面 **Budgie/Unity** 取 `org.gnome.desktop.background` 的 `picture-uri`（未设置回退 `picture-uri-dark`）、**Cinnamon** 取自家 fork 的 `org.cinnamon.desktop.background picture-uri`、**MATE** 取 `org.mate.background picture-filename`（存的是裸路径，写值不套 `file://`）。

| 函数 | 说明 |
|---|---|
| `wp_get() -> Result[String, WallpaperError]` | 读当前壁纸路径 |
| `wp_set(path) -> Result[Unit, WallpaperError]` | 设置壁纸（会改变桌面外观） |

错误 `WallpaperError`：`Unsupported`（Linux 上子进程不可用、KDE 的 qdbus 不在）/ `UnknownDesktop(String)`（既不在 XFCE/KDE 分支、也不在 gsettings 落点表内，如 LXQt/Deepin/Wayland 合成器，带 `XDG_CURRENT_DESKTOP` 原文）/ `CommandFailed(String)` / `ParseFailed(String)` / `InvalidParam(String)`。XFCE 写入时属性不存在会创建。

```moonbit
match @sys.wp_get() {
  Ok(p) => println("当前壁纸：\{p}")
  Err(e) => println("读不到：\{e}")
}
let _ = @sys.wp_set("/home/me/Pictures/wall.png")
```

## 显示器配置

Linux 解析 `xrandr --query` 输出，macOS 直调 CoreGraphics（`CGGetOnlineDisplayList` 一家），Windows 直调 GDI 的显示设备口（`EnumDisplayDevicesW` + `EnumDisplaySettingsExW`），三处都给出每个输出的名称 / 连接状态 / 当前分辨率 × 刷新率 / 位置 / 物理尺寸 / 支持的模式列表；分辨率与位置都是**物理像素**。刷新率以厘赫兹整数表示（×100，如 5995 = 59.95Hz），避免浮点解析与比较。

| 函数 | 说明 |
|---|---|
| `mon_list() -> Result[Array[MonitorInfo], MonitorError]` | 枚举显示器输出，含未接通的，保持 xrandr 顺序（Linux）；macOS / Windows 只列在线屏 |
| `mon_current() -> Result[Array[CurrentOutput], MonitorError]` | 当前输出简化快照（已连接且有当前模式），不含模式列表 |

`MonitorInfo{ name, connected, primary, width, height, refresh_centi, pos_x, pos_y, mm_width, mm_height, modes }`；`MonitorMode{ width, height, refresh_centi, preferred, current }`；`CurrentOutput{ name, width, height, refresh_centi, pos_x, pos_y }`。错误 `MonitorError`：`Unsupported`（macOS 上探不到在线显示器 / Windows 上枚举不到显示设备 / 非三平台）/ `CommandFailed(String)`（Linux 的 xrandr 起不来或退出码非零）/ `ParseFailed(String)`（一条输出都没有）。

Windows 侧三条读数差异：`connected` 恒真——GDI 的这份清单是「贴合桌面的适配器」，没有「接了但断电」那一档；`name` 取 `DeviceName` 去掉 `\\.\` 前缀（`DISPLAY1`），驱动描述（`Red Hat QXL controller` 这种）会随驱动语言变，不作稳定标识；`mm_width`/`mm_height` 恒 0——GDI 不报物理尺寸，真要拿得解 `DeviceKey` 下的 EDID 二进制，本批不做；`preferred` 同样恒 false。模式表按 `(宽, 高, 厘赫兹)` 去重且只取 32bpp，同一分辨率的多份时序配置不会重复计入。

macOS 侧四条读数差异：`connected` 恒真（macOS 没有「接了但关掉」的公开清单，离线屏不出现在表里）；`name` 是 `Built-in`（内建屏）或 `Display-<CGDirectDisplayID>`（其余）——公开的 CG 接口没有显示器名，`NSScreen.localizedName` 属于 ObjC 侧；`refresh_centi` 在内建面板的部分模式上给 0（后端报「未知」，不冒充数值），`mm_width`/`mm_height` 同档缺省时给 0；`MonitorMode.preferred` 恒 false——当前 SDK 没有公开的「首选/原生模式」信号，不拿「当前档」冒充它。

```moonbit
match @sys.mon_current() {
  Ok(outs) => for o in outs {
      println("\{o.name}  \{o.width}x\{o.height}@\{o.refresh_centi / 100}Hz")
    }
  Err(e) => println("读不到：\{e}")
}
```

## 系统窗口管理

窗口列表（id / 桌面 / 主机 / 标题）、按 id 或标题激活、按标题关闭。Windows 走 `EnumWindows` / `SetForegroundWindow` / `WM_CLOSE` 直调；Linux 解析 `wmctrl -l` 并走其激活 / 关闭动作。Wayland 会话下 Linux 这支给 `Unsupported`：`wmctrl` 只看得到 X 兼容层的窗口，动作退出码 0 也不动真窗口。普通 MoonBit 进程即可调用，不需 GUI 宿主。

| 函数 | 说明 |
|---|---|
| `win_supported() -> Bool` | Windows 恒真；macOS 走 CGWindowList/AX；Linux 且 wmctrl 可用（wmctrl 缺失时 Unix 以退出码 127 呈现），Wayland 会话恒 false |
| `win_list() -> Result[Array[WindowInfo], WinError]` | 窗口列表 |
| `win_activate(id_or_title) -> Result[Unit, WinError]` | 按窗口 id（wmctrl 的 `0x...` 十六进制）或标题激活 |
| `win_close(title) -> Result[Unit, WinError]` | 按标题关闭窗口 |

`WindowInfo{ id, desktop, host, title }`：id 可直接回传 `win_activate`；desktop 为窗口所在桌面，-1 表示 sticky（跨全部桌面）。错误 `WinError`：`Unsupported` / `CommandFailed(String)` / `ParseFailed(String)` / `InvalidParam(String)`。

激活与关闭会改变真实窗口状态：接口完整实现，应用层只在用户操作时调用。

```moonbit
match @sys.win_list() {
  Ok(wins) => for w in wins { println("\{w.id}  \{w.title}") }
  Err(e) => println("不可用：\{e}")
}
let _ = @sys.win_activate("ZCode")   // 按标题
let _ = @sys.win_close("ZCode")
```
