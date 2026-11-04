# 系统服务

权限、电源、信息、打印、剪贴板、自启动等系统级服务。统一 `Result` 语义与支持矩阵见[系统能力总览](sys.md)。

## 系统权限（macOS）

躲不开的系统授权做成横切族。macOS 走 TCC：探测走公开口（`AXIsProcessTrusted` / `CGPreflightScreenCaptureAccess`），请求弹**系统自带引导框**（「打开系统设置」对话框），不替用户点任何东西。Windows / Linux 无此概念，恒 `PermNotNeeded`。状态只有「已授 / 未授」两态——「未请求」与「拒绝」在公开 API 层不可区分，应用侧统一按「未授 → 请求 → 引导 → 用户回来再探」的节奏走。

| 函数 | 说明 |
|---|---|
| `permission_supported() -> Bool` | 当前平台是否有权限族（macOS） |
| `permission_probe(kind) -> Result[PermissionStatus, PermissionError]` | 探测当前状态：`PermGranted` / `PermNotGranted` / `PermNotNeeded` |
| `permission_request(kind) -> Result[Unit, PermissionError]` | 弹系统引导框；**不阻塞等待**，引导后由调用方在合适时机重新探测 |

`PermissionKind`：`PermAccessibility`（辅助功能——激活/操作其他应用窗口要）、`PermScreenRecording`（屏幕录制——读到其他应用窗口标题要）。

```moonbit
match @sys.permission_probe(@sys.PermAccessibility) {
  Ok(@sys.PermGranted) => () // 直接干活
  Ok(_) => {
    let _ = @sys.permission_request(@sys.PermAccessibility)
    // 引导框已弹，等用户回来再探
  }
  Err(e) => println(e)
}
```

另一档「操作提权」（每次一弹：macOS 管理员密码框、将来 Windows UAC）不落本族，随各自能力批处理（如电源计划 macOS 档的写操作走 `osascript` 管理员授权）。

## 电源计划

经 `powerprofilesctl` 三条命令读可用计划集、读当前计划、切换计划（`power-profiles-daemon` 未安装时 shell 以退出码 127 呈现 → `PpUnsupported`）。

| 函数 | 说明 |
|---|---|
| `pp_supported() -> Bool` | powerprofilesctl 存在且可查询 |
| `pp_profiles() -> Result[Array[PowerProfile], PowerProfileError]` | 可用计划列表（按后端输出序，推荐序在前时即推荐序） |
| `pp_current() -> Result[PowerProfile, PowerProfileError]` | 当前计划 |
| `pp_set(profile) -> Result[Unit, PowerProfileError]` | 切换计划（有副作用、需要认证，调用方自行走授权流程） |

`PowerProfile`：`PPerformance` / `PBalanced` / `PPowerSaver`。错误 `PowerProfileError`：`PpUnsupported` / `PpCommandFailed(String)` / `PpParseFailed(String)`。

```moonbit
match @sys.pp_profiles() {
  Ok(profiles) if profiles.contains(@sys.PBalanced) => {
    let _ = @sys.pp_set(@sys.PBalanced)
  }
  _ => ()
}
```

## 系统信息

Linux 只读 `/proc` 与 `/sys` 文本：发行版标识（`/etc/os-release`）、机器 DMI 标识（`/sys/class/dmi/id/`）、物理内存（`/proc/meminfo`）、开机时长（`/proc/uptime`）。Windows 走注册表（`Windows NT\CurrentVersion` 的 `ProductName`/`DisplayVersion`、`HARDWARE\DESCRIPTION\System\BIOS` 的 DMI 镜像）+ `GlobalMemoryStatusEx`/`GetTickCount64`，机器标识在注册表镜像为空时退 WMI（`Win32_ComputerSystem` 的 `Manufacturer`/`Model`）。macOS 走 `sw_vers` / `ioreg -rd1 -c IOPlatformExpertDevice` + `sysctl -n hw.model`，内存与开机时长走桩内直调。读不到一律给 `Err` 并带路径/接口名，不以空串代替。

| 函数 | 说明 |
|---|---|
| `si_os() -> Result[OsInfo, SysInfoError]` | 发行版：`OsInfo{ pretty_name, id, version_id }`（Windows 是 `ProductName + DisplayVersion`） |
| `si_machine() -> Result[MachineInfo, SysInfoError]` | 机器：`MachineInfo{ vendor, product, serial }`（序列号多数发行版仅 root 可读、虚拟机常空，读不到给 `Err` 或兜底机器唯一标识） |
| `si_memory() -> Result[MemoryInfo, SysInfoError]` | 内存：`MemoryInfo{ total_kb, available_kb }`（单位 kB，available_kb 即 MemAvailable） |
| `si_uptime() -> Result[Double, SysInfoError]` | 开机时长（秒） |

错误 `SysInfoError`：`SiUnsupported`（非三平台）/ `SiReadFailed(String)`（带路径或接口名）/ `SiParseFailed(String)`。

Windows 侧 `si_machine()` 的两级取数（真机与虚拟机都要能读到）：先读注册表 `HKLM\HARDWARE\DESCRIPTION\System\BIOS`（内核从 SMBIOS 抄的镜像，真机常态可用）；这张镜像是空的（QEMU/SeaBIOS 实测一个值都没有——固件不把 SMBIOS 表交给用户态，连 `GetSystemFirmwareTable('RSMB')` 都返回 `ERROR_INVALID_FUNCTION`）时退 WMI 的 `Win32_ComputerSystem`，本机回证读到 `BOCHS_ / BXPC____`；序列号 `BIOS SerialNumber` → WMI `Win32_BIOS.SerialNumber` / `Win32_ComputerSystemProduct.IdentifyingNumber` → `HKLM\SOFTWARE\Microsoft\Cryptography\MachineGuid` 依次兜底。

```moonbit
let os = @sys.si_os() // Ok({ pretty_name: "Ubuntu 24.04.5 LTS", id: "ubuntu", .. })
let mem = @sys.si_memory()
let up = @sys.si_uptime() // Ok(84088.08)
```

## 打印机

Windows 走 winspool 直调（`EnumPrintersW` 列表 + `GetDefaultPrinterW` 默认名）与 `ShellExecuteW`「print」动词打印；Linux 经 `lpstat` 读打印机列表（`-p`）与默认打印机（`-d`）、`lp` 提交打印任务。未装 CUPS（lpstat 以退出码 127 呈现）→ `PrtUnsupported`。

| 函数 | 说明 |
|---|---|
| `prt_supported() -> Bool` | Windows 看 winspool 列表可取；Linux 看 lpstat 可用 |
| `prt_list() -> Result[Array[PrinterInfo], PrinterError]` | 打印机列表（名称 + 可用状态） |
| `prt_default() -> Result[String, PrinterError]` | 默认打印机名 |
| `prt_print(printer? = "", path, copies? = 1) -> Result[Unit, PrinterError]` | 提交打印任务（Linux 用系统默认打印机当 printer 缺省；Windows 走「print」动词、不支持份数参数；有副作用，真实排队打印） |

`PrinterStatus`：`Idle` / `Printing` / `Paused`（暂停接新任务）/ `Disabled`；`prt_status_available(status)` 判是否可用接任务。`PrinterInfo{ name, status }`。错误 `PrinterError`：`PrtUnsupported` / `PrtCommandFailed(String)` / `PrtParseFailed(String)` / `PrtInvalidParam(String)`（文件路径为空、份数 < 1）。

```moonbit
match @sys.prt_default() {
  Ok(name) => {
    let _ = @sys.prt_print(printer=name, path="/tmp/doc.pdf")
  }
  Err(e) => println("无默认打印机：\{e}")
}
```

## 环境变量与目录枚举

两块小原语：进程内环境变量读写与删除（`envx`，读走标准库 `core/env`、写删走 C 层 setenv/unsetenv），目录枚举（`fsx`，C 层 opendir/readdir 或 Win32 FindFirstFileW）。

| 函数 | 用途 |
|---|---|
| `envx_get(name) -> String?` | 读（当前进程环境，取不到 None） |
| `envx_set(name, value) -> Result[Unit, EnvxError]` | 写（仅当前进程环境，之后 spawn 的子进程可见） |
| `envx_unset(name) -> Result[Unit, EnvxError]` | 删（本就不存在也视为成功，幂等） |
| `envx_common() -> Map[String, String]` | 常用集合：PATH / HOME / LANG / SHELL / USER 固定读取 + `XDG_*` 前缀扫描（环境里存在才收入） |
| `fsx_list_dir(path) -> Result[Array[String], FsError]` | 枚举目录子项名（不含 `.` `..`、不递归、含隐藏项） |
| `fsx_set_env(name, value, overwrite) -> Result[Unit, FsError]` | 写环境变量（overwrite=false 且已存在时保持原值，仍为 Ok） |
| `fsx_unset_env(name) -> Result[Unit, FsError]` | 删环境变量（envx_unset 的底层） |

语义为「进程内生效」——写只改当前进程环境，不触碰系统持久配置，也不影响父进程。错误：`EnvxError::ExInvalidParam(String)`（变量名空串）/ `ExFailed(String)`（C 层拒绝，如名含 '='）；`FsError::InvalidParam(String)` / `OpenFailed(String)`（目录打不开，带路径）/ `EnvFailed(String)`。`fsx_list_dir` 已知边界：子项名含 '\n' 的极端文件名会被拆开。

```moonbit
let path = @sys.envx_get("PATH")
let _ = @sys.envx_set("MY_FLAG", "1")
let _ = @sys.envx_unset("MY_FLAG")
match @sys.fsx_list_dir("/usr/share/applications") {
  Ok(names) => for n in names if n.ends_with(".desktop") { println(n) }
  Err(e) => println("打不开：\{e}")
}
```

## 剪贴板监听

文本读写与变化监听。Windows 走 Win32 `CF_UNICODETEXT` 直调；Linux 优先 GtkClipboard（需宿主跑过 gtk_init，探测给 0 时退回命令线 `xclip`），文本内容变化时回调派发新文本。本模块为纯轮询实现，任意 MoonBit 进程可用，回调落在调用方上下文。

| 函数 | 说明 |
|---|---|
| `cbw_get_text() -> Result[String, ClipboardError]` | 读一次剪贴板文本（不可用 / 选区无文本为对应 Err） |
| `cbw_start_watch(interval_ms? = 800, cb) -> ClipboardWatcher` | 启动监听（轮询间隔钳 100..60000；基线取启动瞬间内容，初始内容不触发回调） |
| `cbw_stop(watcher)` | 停止监听（置停靠标志，至多再跑一拍自行终止；幂等） |

错误 `ClipboardError`：`Unsupported`（平台/后端都不可用）/ `CommandFailed(String)`。读失败静默跳过该拍，不触发回调。轮询挂在 GUI 定时器上，需在消息循环运行后才实际派发。

```moonbit
let w = @sys.cbw_start_watch(interval_ms=500, fn(text) {
  println("剪贴板新内容：\{text}")
})
// ……需要时
@sys.cbw_stop(w)
```

## 开机自启动

跨平台的开机自启动查询、设置与取消，语义在 MoonBit 层归一，使用方不需感知平台。

| 平台 | 机制 | 条目位置 |
|---|---|---|
| Linux | XDG 自启动目录写 `<app_id>.desktop` | `$XDG_CONFIG_HOME/autostart/`，未设回退 `$HOME/.config/autostart/` |
| Windows | HKCU `Software\Microsoft\Windows\CurrentVersion\Run` 写值 | 值名是 app_id，值是引号包裹的可执行文件路径 |
| macOS | LaunchAgents plist + `launchctl load` / `unload`（真机已回证） | `~/Library/LaunchAgents/<app_id>.plist`——Label 为 app_id，ProgramArguments 为可执行文件，RunAtLoad true |

| 函数 | 说明 |
|---|---|
| `autostart_supported() -> Bool` | 运行时探测；三平台均为 true |
| `autostart_is_enabled(app_id) -> Result[Bool, AutostartError]` | 查询当前状态；Linux 认 `Hidden` 与 `X-GNOME-Autostart-enabled` 两个系统侧禁用位；macOS 以 plist 是否存在为启用状态 |
| `autostart_enable(app_id)` / `autostart_disable(app_id) -> Result[Unit, AutostartError]` | 设置与取消；两者幂等：重复 enable 覆盖，disable 对本就不存在的条目也算成功 |
| `autostart_path(app_id) -> Result[String, AutostartError]` | 落点描述，排查用：Linux 是 `.desktop` 全路径，Windows 是 `HKCU\…\Run\<app_id>`，macOS 是 `~/Library/LaunchAgents/<app_id>.plist` |
| `autostart_exe_path() -> String?` | 当前进程可执行文件全路径，enable 写入的就是它 |
| `autostart_valid_app_id(app_id) -> Bool` | 按 DBus 知名名规则校验 app_id：至少两个点分元素，元素以字母或下划线开头 |
| `autostart_dir_of` / `autostart_escape_exec` / `autostart_desktop_entry` / `autostart_desktop_enabled` / `autostart_run_value` / `autostart_run_value_exe` | 纯函数：自启动目录解析、Exec 转义、`.desktop` 内容与解析、Windows Run 值形态与反解 |

```moonbit
match @sys.autostart_enable("com.example.MyApp") {
  Ok(_) => ()      // 重新登录 / 重启即拉起（落点见 autostart_path）
  Err(e) => println(e.to_string())
}
match @sys.autostart_is_enabled("com.example.MyApp") { ... }
match @sys.autostart_disable("com.example.MyApp") { ... }   // 幂等
```

错误类型 `AutostartError{Unsupported, InvalidAppId, NoExecutablePath, IoFailed(String)}` 把不支持与失败分开，不静默。exec 路径的引号按平台惯例由库加——`.desktop` 的 Exec 与 Windows REG_SZ 都是整串双引号包裹，调用方不要再拼一层。

边界：自启动目标取本进程可执行文件的绝对路径，AppImage 或便携解压目录等临时位置下，应用挪动目录后旧条目失效需重新 enable；Linux 的自启动目录可能被清理工具清空，Windows 的 Run 键可被组策略禁用（条目在但不执行），两类都是环境侧行为，库不做探测；macOS 的 enable/disable 走已废弃但仍在的 `launchctl load` / `unload`（新写法 `bootstrap` 要用户 uid，本 API 族没有取 uid 的口子），load 失败不撤销已写入的 plist（下次登录仍生效），但会如实报错。
