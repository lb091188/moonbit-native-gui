# gui-window（`NoahLiu/gui-window`）

native-gui 的窗口层单件（能力模块拆分之一，见 `proposals/module-split.md`）：**事件循环寄生型**窗口能力全集——与控件树零耦合，`@win` 不依赖 gui-sys / gui-dbus（Linux 托盘半边在 `NoahLiu/gui-dbus`，统一门面在 `NoahLiu/gui-shell`）。

## 能力清单

| 族 | 内容 |
|---|---|
| 窗口 | 建窗/贴屏（surface 像素直出）、多窗、最大最小化、隐藏/撤管、DPI |
| 事件循环 | 消息泵原语（等待预算/唤醒位），循环归 MoonBit 宿主 |
| 输入 | 键鼠事件、IME 纯通道（W6） |
| 拖放 | 跨进程拖入（IDropTarget）与拖出（W23a/b） |
| 全局热键 | Win32 RegisterHotKey / X11 XGrabKey（Wayland 如实 Unsupported）/ Carbon |
| 托盘 | Win32 半边（Shell_NotifyIconW）；Linux 半边（SNI）在 gui-dbus |
| 通知 | Win32 toast / macOS UserNotifications 中心 |
| 单实例 | 互斥量检查 + 唤起已有实例（POSIX 套接字臂在 gui-shell 集成层） |
| 对话框 | message_box（模态窗口本体）与文件对话框 `FileDialog`（Windows IFileDialog / GTK FileChooser / macOS NSPanel，可挂父窗口） |
| 任务栏 | 进度（ITaskbarList3）等 |

## 用法

```json
// moon.mod
{
  "import": ["NoahLiu/gui-window@0.1.0"]
}
```

```moonbit
// 包名末段即别名：@win
let win = @win.create("Hello", 800, 600)
```

## 与 native-gui 的关系

模块拆分后的分层：`gui-window`（本模块，零内部依赖）与 `gui-sys`（纯读写）、`gui-dbus`（D-Bus/SNI）平行；集成门面在 `NoahLiu/gui-shell`；组件工具包 facade `NoahLiu/native-gui` 依赖 gui-shell 间接带走本模块。

## 构建

`win/stub.c` 一个文件四条平台分支：Windows 由 moon native-stub 自编（本模块 prebuild 只下发系统库）；Linux 需要 `gtk+-3.0` 与 `x11` 开发包（prebuild 带 `-DWM_STUB_GTK` 编静态库）；macOS 走系统自带框架（`-x objective-c -fobjc-arc` 专编）。`win_gui.c` 是 MSVC GUI 子系统 pragma 载体，随包归档。
