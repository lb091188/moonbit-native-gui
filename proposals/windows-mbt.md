# windows-mbt：Windows 系统特性独立包（规划）

## 定位

跨平台库 `native-gui` 只收三平台能统一抽象的能力；**Windows 系统特性**（Win32 / COM 专属 API、单平台语义）不进跨平台库。远期随「无法抽象成跨平台的功能独立成包」的规划（见 roadmap 远期规划：`windows-mbt` / `*DE-mbt` / `mac-mbt`）单独立项。

本文件收录暂存在跨平台库里的 Windows 系统特性条目：先记录现状与迁移口径，等 windows-mbt 立项时迁走。

## 条目

### 任务栏进度（Windows）

- **API**：`set_taskbar_progress` / `set_taskbar_state` / `clear_taskbar_progress`——ITaskbarList3 进程级单例，五态写入口。
- **能力口径**：只写不读（Win32 无 getter）；非 Windows 平台静默降级（能力探测语义化报不支持，不假装成功）。
- **现状（过渡形态）**：W20g 已合入，实现挂在跨平台库 `gui/win` 的 `Window` 方法上。按本规划，该门面应从跨平台库移出、随 windows-mbt 独立包提供；迁移前维持现状，不再向跨平台 API 面扩展。
- **状态**：真机观感未复验；迁移随 windows-mbt 立项。
- **同类边界**：dock 徽标（macOS）与 LauncherEntry（Linux）这类单平台专属条目已从跨平台路线图撤出——同理归 `mac-mbt` / `*DE-mbt`，不在跨平台库规划内。
