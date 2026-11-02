# gui-shell（`NoahLiu/gui-shell`）

native-gui 的集成层单件（能力模块拆分之一，见 `proposals/module-split.md`）：**全仓唯一同时 import 三个能力模块的层**——上承组件层（widget/ui/chart/router/style 都吃它的通道与事件词汇），下接三个能力模块，吸收全部平台差异。它不认识 widget——依赖方向是组件层依赖 shell，不是反过来。

## 能力清单

六条与控件树零耦合的通道 + 事件泵：

| 通道 | 说明 |
|---|---|
| 菜单 | 菜单栏 / 右键菜单（mac NSMenu / Win32 / Linux GTK） |
| 全局热键 | 门面统一注册（后端 gui-window） |
| 托盘 | SNI 在线走 SNI（gui-dbus），否则 Win32（gui-window），否则 `Err(Unsupported)`——运行期选边 |
| 通知 | 平台后端分派（Win32 toast / macOS 通知中心 / Linux org.freedesktop.Notifications） |
| 外部打开 | URL / 文件交系统默认程序（gui-sys NSWorkspace/ShellExecuteW/xdg-open 族） |
| 单实例 | 互斥 + 唤起（POSIX 套接字臂 `shell_stub.c`） |
| 事件泵 | Loop 等待预算 / 唤醒位（负数即无限等） |

另含 `i18n` 包（随迁）：零依赖纯包——读 locales TOML 文本、查译/插值/复数；与 tools/i18nkit 共享格式不共享代码，文件读取归应用层。留在 facade 会成环（gui-shell→facade→gui-shell），故随迁。

## 用法

```json
// moon.mod
{
  "import": ["NoahLiu/gui-shell@0.1.0"]
}
```

```moonbit
// 包名末段即别名：@shell / @i18n
@shell.tray_set_title("demo")
```

## 构建

`shell/shell_stub.c` 只用标准头（POSIX 套接字臂），走 moon native-stub；无 prebuild、无额外链接参数。依赖 `gui-window` / `gui-sys` / `gui-dbus` 三个模块（各家的系统库由它们自己的 prebuild 下发）。
