# 平台适配经验

各平台实测坑与结论,每条只记「坑 + 修复」;协议互操作结论均来自真总线、真面板验证,单测自洽不算数。Linux 按发行版 → 桌面环境组织,Windows / macOS 按版本;新增结论写进对应小节。条目只收代码读不出的四类——平台反直觉行为、实测读数与容差、被否掉的路及其原因、环境与版本约束,一句根因 + 一句判据;实测坑与适配经验同代码改动回写本目录对应文件,不留提交说明或会话记忆。

## 文件导航

本目录收平台适配实测坑与口径，由原 `experience/adaptation.md` 拆分而来，条目逐字保留。

- common.md —— 跨平台通用：构建链 / 工具链 / FFI、组件 / 布局 / 渲染 / 字体 / 图表、三平台通用真机反馈与维护约定。
- mac.md —— macOS 专有：平台批 / 对齐批、通知 / Dock / NSAccessibility 桥、拖放、DMG / 自更新。
- windows.md —— Windows 专有：Win32 / 托盘 / OLE 拖放 / WebView2 / MSVC / UIA 与 W 系列批次。
- linux.md —— Linux 专有：G 系列批次、GTK / Pango / D-Bus / SNI / 桌面集成 / webview、Wayland / X11 / AT-SPI。
- linux-distros.md —— 发行版：deepin 20 构建链自救、Ubuntu 24.04 主链路依赖、其他发行版移植起点。

查询入口：

- 查 D-Bus / SNI / Wayland / AT-SPI → linux.md
- 查构建链与工具链 → common.md
- 查 deepin / 发行版版本坑 → linux-distros.md
- 查 mac / win 专有 → mac.md / windows.md
