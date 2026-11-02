# gui-sys（`NoahLiu/gui-sys`）

native-gui 的系统工具单件（能力模块拆分之一，见 `proposals/module-split.md`）：**纯读写**系统面——无窗口、无事件循环，任何进程可调（CLI 可用）。

## 能力清单

| 族 | 内容 |
|---|---|
| 剪贴板 | 读写文本（Linux GTK / macOS NSPasteboard / Windows CF_UNICODETEXT）、变更监视（Linux 轮询 xclip/xsel，存量债） |
| 自启动 | 登录自启写删（Linux 桌面条目 / macOS LSSharedFileList / Windows 注册表 Run 键） |
| 桌面与环境 | 默认应用查找、目录/桌面集成、环境变量写删、文件系统扩展、JSON 工具 |
| 窗口控制 | 枚举/激活/关闭窗口（mac 走 CGWindowList + AX；Windows 桩同口径） |
| 历史与最近 | 浏览器书签/历史（Chrome/Edge/Firefox）、VS Code 最近文件、系统最近文档（moonsqlitefile 读库） |
| 硬件与电源 | 音量、电源方案、显示器枚举、空闲检测、系统信息、夜间色温（mac 覆盖层档） |
| 打印与权限 | 打印机枚举、mac 权限探测/引导（辅助功能、屏幕录制） |
| 进程 | 子进程运行原语（procrun） |
| 对话框 | 文件打开/保存（Linux/mac 经 `wm_file_*` 档、Windows COM IFileDialog） |

## 用法

```json
// moon.mod
{
  "import": ["NoahLiu/gui-sys@0.1.0"]
}
```

```moonbit
// 包名末段即别名：@sys
let text = @sys.clipboard_get_text()
```

## 与 native-gui 的关系

模块拆分后本模块与 `gui-window` 是**平行兄弟**（互相零依赖）；窗口/托盘/通知/热键等事件循环寄生型能力在 `NoahLiu/gui-window`（拆分批次中），集成门面在 `NoahLiu/gui-shell`。本模块可脱离 GUI 独立消费。

## 构建

C 端两笔：`sys/sys_stub.c` 走 moon native-stub（只用标准头）；剪贴板 GTK/NSPasteboard、mac 窗口枚举/权限/色温住 `sys/sys_ext.c`，由本模块 `prebuild.py` 编静态库并下发链接参数（Linux 要 `gtk+-3.0` 开发包；macOS 走系统自带框架；Windows 无额外依赖）。
