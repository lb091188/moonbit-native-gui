# 系统能力总览（@sys）

系统能力族 API：系统音量、应用查找、夜间色温、壁纸、显示器配置、系统窗口管理、剪贴板监听、子进程执行、电源计划、系统信息、打印机、环境变量、目录枚举、最近文件、浏览器书签与 Firefox 历史、VS Code 本地历史。全部只读或经系统服务授权写入，统一返回 `Result`，不支持的环境给对应错误值而不是崩溃；`*_supported()` 每次调用真实探测当前环境。

按域分页：[音量与媒体](media.md)、[应用与历史](apps-history.md)、[桌面与显示](desktop.md)、[系统服务](service.md)。

## 平台状态

> 三平台（Windows / Linux / macOS）均已按同一份清单在真机上跑过：**✅ 已回证**，括号里是实现方式，便于排查；**❌ Unsupported** = 该平台不提供，门面如实出声，不等于「坏了」。逐条用例与平台差异见 `测试文档/测试用例.md`。

| 能力 | Windows | Linux | macOS |
|---|---|---|---|
| 剪贴板 / 自启动 / 子进程 / 文件(fsx) / 环境变量(envx) | ✅ 直调 | ✅ | ✅ 已回证（pbpaste/pbcopy + NSPasteboard；LaunchAgents plist + `launchctl load/unload`） |
| 系统信息 / 壁纸 / 启动器（打开与定位） | ✅ 直调 | ✅ | ✅ 已回证（`sw_vers`/`ioreg`/`sysctl`；osascript 桌面图片，只动主屏；`open` / `open -R`） |
| 音量 / 打印机(列表+默认+打印) | ✅ 直调 | ✅ | ✅ 已回证（osascript 的 `volume settings`，sink 名给不到时按契约置空；macOS 自带 CUPS，与 Linux 同走 `lpstat`/`lp`） |
| 用户空闲检测 | ✅ 直调 | ✅ | ✅ 已回证（`CGEventSourceSecondsSinceLastEventType` 的 HID 系统态读数，不需辅助功能授权） |
| 应用查找 | ✅ 直调 | ✅ | ✅ 已回证（`.app` 包扫描 + `Contents/Info.plist` 公开键；`categories` 与本地化名没有公开对等物，按空/回退给） |
| 最近文件 | ✅ 直调 | ✅ | ❌ Unsupported（sharedfilelist 是私有格式，暂不提供） |
| 窗口管理 / 电源计划 | ✅ 直调 | ✅ X11 会话（**Wayland 会话 Unsupported**，XWayland 只列得到 X 兼容层的窗） | ❌ Unsupported（Accessibility 要用户先授权 / `pmset` 对不上三值方案语义） |
| browser/vscode 数据 | ✅（LOCALAPPDATA 路径） | ✅ | ✅（`Library/Application Support/<厂商>/<产品>` 路径） |
| sysmonitor 进程数据 | ✅（示例模块自带探针） | ✅ | ✅ 已回证（示例模块自带，mac 路径待验） |
| 夜间色温 | ✅ 直调（`SetDeviceGammaRamp`） | ✅ X11 会话（**Wayland 会话 Unsupported**：gamma 只落 XWayland，进程照起、退出码照 0 而屏幕没变） | ❌ 无公开 API（CoreBrightness 私有，走 f.lux 同款覆盖层） |
| 显示器枚举（monitor） | ✅ 直调（`EnumDisplayDevicesW` / `EnumDisplaySettingsExW`；真机与 QEMU QXL 虚拟屏均回证，虚拟屏读到 `DISPLAY1: 1920x1080 @64Hz`） | ✅（xrandr；**Wayland 会话读到的是 XWayland 虚拟屏**，名形如 `XWAYLAND0`） | ✅ 已回证（CoreGraphics 直调：`CGGetOnlineDisplayList` / `CGDisplayBounds` / `CGDisplayCopyAllDisplayModes`；只列「在线」屏，输出名给不了按 `Built-in` / `Display-<id>` 给；读数一律物理像素，故 `MonitorInfo` 不需要缩放比字段） |

macOS 的公开口与底层：`open`/`open -R`、`sw_vers`、`ioreg -rd1 -c IOPlatformExpertDevice`、`sysctl hw.model/hw.memsize/kern.boottime`、`osascript`（System Events 的 `volume settings` 与桌面图片）、`launchctl load/unload` + `~/Library/LaunchAgents/*.plist`、`lpstat`/`lp`，以及进程内直调的 `host_statistics64`、`CGEventSourceSecondsSinceLastEventType`、`CGGetOnlineDisplayList`/`CGDisplayBounds`/`CGDisplayCopyDisplayMode`/`CGDisplayCopyAllDisplayModes`/`CGDisplayScreenSize`。

Windows 直调的底层：SystemParametersInfoW（壁纸）、ShellExecuteW（启动/定位/打印）、PowerGet/SetActiveScheme、注册表（产品与 DMI 信息）、GlobalMemoryStatusEx、GetTickCount64、EnumWindows、EnumPrintersW、IAudioEndpointVolume（COM）、GetLastInputInfo。踩坑与头文件/链接要求见 [experience/adaptation/windows.md](https://github.com/lb091188/moonbit-native-gui/blob/master/experience/adaptation/windows.md)。

完整演示见 `examples/system`（`cd examples/system && moon run .`，左侧「系统能力探测」分组）——每段可「重新探测」逐项呈现本机真实结果，不支持的能力显示对应错误文本。

## 共享基建：子进程执行 procrun

命令行类能力（音量、显示器、壁纸、夜间色温、打印机、电源计划、Firefox profile 定位）共用的「spawn → 限时回收 → 临时文件捕获 stdout/stderr」封装：命令名按 PATH 解析；子进程强制 C locale；退出码 0 归一为 `Ok`，非零归一为 `Err` 并携带 stderr。

| 函数 | 说明 |
|---|---|
| `pr_available() -> Bool` | 当前平台是否支持子进程执行（Linux / macOS / Windows 三主平台为真） |
| `pr_run(cmd, args, timeout_ms? = 5000) -> Result[ProcOutput, ProcError]` | 运行命令并归一结果（超时进程会被强制终止） |

`ProcOutput{ stdout, exit_code }`；错误 `ProcError`：`Unsupported`（非 Linux / macOS / Windows 主平台）/ `SpawnFailed(String)`（命令不存在时由子进程以退出码 127 呈现，归入非零退出）/ `Timeout(String)` / `NonZeroExit(Int32, String)` / `Signaled(Int32)`。

命令缺失与「存在但失败」语义不同：前者归一为 `*Supported == false` 或 `Unsupported`（如 `PpUnsupported`、`PrtUnsupported`），后者是 `CommandFailed`。

```moonbit
match @sys.pr_run("wpctl", ["get-volume", "@DEFAULT_SINK@"]) {
  Ok(out) => println(out.stdout)
  Err(@sys.ProcError::NonZeroExit(_, err)) => println("失败：\{err}")
  Err(e) => println(e)
}
```

## 共享基建：通用 D-Bus 调用层（@dbus）

面向任意服务的方法调用与属性读写，是媒体控制（MPRIS）等模块的公共地基。复用进程级的会话 / 系统总线连接；同步调用 1.5 秒超时，应答超时给 `gdbus.timeout`。

| 函数 | 说明 |
|---|---|
| `gdbus_call_session(dest, path, iface, action, args) -> Result[GDBusValue, GDBusError]` | 会话总线方法调用 |
| `gdbus_call_system(dest, path, iface, action, args) -> Result[GDBusValue, GDBusError]` | 系统总线方法调用 |
| `gdbus_get_property_session(dest, path, iface, prop)` / `gdbus_get_property_system(...)` | 读属性（走 `org.freedesktop.DBus.Properties.Get`，返回值已拆掉 variant 包裹） |
| `gdbus_set_property_session(dest, path, iface, prop, value)` / `gdbus_set_property_system(...)` | 写属性（走 `Properties.Set`；value 传裸值，variant 包裹在本层完成） |

值模型 `GDBusValue`：`GVNone`（无返回值，不能作调用参数）/ `GVBool` / `GVInt32` / `GVUInt32` / `GVInt64` / `GVU64`（'t'，udisks 的 Size/Time 等无符号 64 位）/ `GVDouble` / `GVString` / `GVPath`（'o'）/ `GVArray(元素签名, 元素表)` / `GVDict(a{sv}，值已拆掉 variant 包裹，Map 按插入序序列化)` / `GVVariant`（保持包裹）/ `GVStruct`。应答侧 `{sv}` 数组折成 `GVDict`，多返回值折成 `GVStruct`。错误 `GDBusError{ name, message }`：name 为 D-Bus 错误名或本地前缀 `gdbus.io`（连不上 / 已断开）/ `gdbus.timeout` / `gdbus.encode`。

```moonbit
match
  @dbus.gdbus_get_property_system(
    "org.freedesktop.timedate1",
    "/org/freedesktop/timedate1",
    "org.freedesktop.timedate1",
    "NTP",
  ) {
  Ok(@dbus.GVBool(on)) => println("NTP 开启：\{on}")
  Ok(_) => ()
  Err(e) => println("总线失败：\{e.name} \{e.message}")
}
```

## 边界

- 浏览器运行中 History 库不断有新写入，读取结果是读入时刻的快照。
- Firefox 的 places.sqlite 常处于 WAL 模式，本实现只读主库文件，尚未 checkpoint 进主库的最新浏览记录读不到；多 profile 聚合时同一 url 各出现一次（与 Chrome 侧聚合口径一致）。
- `appfind_executable` 的命中判定为目录里有该名字的条目，不读文件内容、不校验执行权限位。
- 音量设置依赖对应系统服务在线（Windows IAudioEndpointVolume / Linux PipeWire-Pulse），服务缺席时写接口返回错误值。
- 打印 / 切电源计划会改变系统真实状态：接口完整实现，但只在用户显式操作时调用，不要在探测或查询路径里代为触发。
- 剪贴板监听与涟漪动画的定时器都由消息循环驱动且无取消 id（`set_timer`）：停止的途径是让回调返回 false，故句柄类 API（`cbw_stop` / `eff_stop`）应在组件销毁前显式调用。
