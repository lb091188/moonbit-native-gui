# 能力模块拆分方案

记录 2026-10 竞品调研后定下的模块拆分决策：为什么拆、拆成什么、依赖怎么分层、按什么顺序执行。对外进度见 [roadmap](../docs/zh/roadmap.md)「模块化」小节；本文是对内方案。

## 背景与动机

- 2026-10-31 调研（moon search + gh）：MoonBit GUI 赛道头部是 Proton（web 前端壳，主模块 2.7 万下载、`proton_*` 单件各 2 万+）与 MoUI（Skia 自绘多平台）；本库 89 下载、4★。
- justjavac 单件套件（clipboard / auto_launch / global_hotkey / notification / tray，各 6k+ 下载）证明：系统能力按单件独立发布有独立检索曝光与独立消费场景；聚合包拿不到这波检索。
- 本库的真实空位：**带全套桌面能力的窗口层**（winit 位 + Electron desktop API 位）生态里无人占据（orby 仅 Win32/GTK3，无托盘/IME/macOS；Milky2018/window 是 winit 范式且 macOS 先行）。
- 拆分是发行策略不是定位转向：每个能力获得独立检索面与单件消费路径；facade 不变保「开箱即用」。

## 目标形态

| 模块 | 来源 | 定位 | 内部依赖 |
|---|---|---|---|
| `NoahLiu/gui-sys` | gui/sys | 纯读写系统工具：剪贴板、自启、壁纸、打印机、音量、电源、历史等 | 无（core + moonsqlitefile） |
| `NoahLiu/gui-window` | gui/win | 窗口层 + GUI 辅助族：窗口、事件循环、surface、拖放、IME、任务栏、托盘、通知、热键、单实例、对话框 | 无 |
| `NoahLiu/gui-dbus` | gui/dbus | D-Bus/SNI：托盘 Linux 半边、通知、MPRIS、UPower、NetworkManager、logind、单实例 | gui-sys |
| `NoahLiu/native-gui` | — | 聚合 facade：base/render/text/theme/widget/ui/shell 等 + 统一 API（平台分派） | 上述三模块 + gui-webview / gui-media |

三模块与 gui-webview / gui-media 同形态：独立模块、独立发版、prebuild 自管、钉版。

## 依赖规则

能力按「消费方式」分三类，模块归属由此决定：

1. **纯读写型** → gui-sys。无窗口、无事件循环、任何进程可调（CLI 可用）。
2. **事件循环寄生型** → gui-window。tray / hotkey / notify 挂在隐藏消息窗与消息泵上，产出回调进应用循环——是 GUI 的辅助，不是读写接口。
3. **窗口本体** → gui-window。message_box 字面就是模态窗口。

边界原则：

- 事件型能力从此不进 gui-sys。存量例外：sys 的 clipboard_watch 半只脚踩事件型（Linux 轮询 xclip/xsel 路线），不动，记为存量债。
- 纯读写能力不进 gui-window。
- instance 归 gui-window：「是否首实例」是互斥量检查（纯读写），但收益动作「唤起已有实例」是窗口行为。
- **tray 双半边各住各模块**：Win32 半边 `win/tray.mbt`（gui-window），Linux 半边 `dbus/sni.mbt`（gui-dbus）；统一 API 与后端选择在 facade 层（双后端图见 [tray.md](tray.md)）。**gui-window 不依赖 gui-dbus**——两者是平行兄弟：win 包只依赖 core/utf8，dbus 包只依赖 sys，互相零 import；facade 运行期选边（SNI watcher 在线走 SNI，否则 Win32，否则 `Err(Unsupported)`）。这样 gui-window 在 Windows/macOS 上零 D-Bus 包袱，gui-dbus 独立可消费。

## 拆分顺序（23 步，每步一提交，步间保持全绿可发布）

1. roadmap 落「已规划」条目（已完成，见「模块化」小节）；TODO 待动手再进。
2. 基线固化：全量 check/test 绿；快照 win/sys/dbus 三包 `pkg.generated.mbti`；记录三方依赖版本（moonsqlitefile 等）。
3. 建 `modules/gui-sys`：整体迁移 gui/sys（.mbt + sys_stub.c + moon.pkg）+ LICENSE/NOTICE/README，keywords 铺长尾（clipboard/autostart/wallpaper/printer/volume/power/history…）。
4. prebuild 切割：gui 的 prebuild.py 摘 sys 分支；gui-sys 自管（sys 基本纯 native-stub，预计零成本）。
5. 全仓 import 改写（约 25 处 moon.pkg）：chart/dbus/shell/ui 四包 + gui-webview + examples（audio/browser/headless-audio/hello/showcase 各子包/sysmonitor/video）+ experiment 各 probe；显式 `@sys` 别名保 .mbt 代码零改动。
6. 注册与文档：moon.work、facade 钉版依赖、AGENTS.md 门禁命令、build.md、测试文档同步。
7. 门禁 → 提交 → `gui-sys@0.1.0` 发版 + 钉版清单同步。
8. 建 `modules/gui-window`：整体迁移 gui/win（stub.c 四平台分支 + win_gui.c + 全部 mbt/wbtest）+ 文档关键词（window/tray/notification/global hotkey/IME/single instance/taskbar）。
9. prebuild 迁移（全计划最重）：Windows 系统库链接、GTK `libyue_win_stub.a`、macOS `libyue_win_stub_mac.a`、GUI 子系统 pragma 下发各分支整体搬至 gui-window 自管，gui 侧删净。
10. 全仓 import 改写：shell/widget、gui-webview、showcase 各处、experiment win 系 probe；注册与文档同步。
11. 门禁 → 提交。
12. 真机验证（用户执行，助手出操作清单）：三平台窗口/拖放/IME/托盘/热键/单实例 + 链接三件事（Windows 无控制台窗口、GTK 静态库、macOS 框架）与迁前一致。
13. `gui-window@0.1.0` 发版 + 钉版同步。
14. 建 `modules/gui-dbus`：迁移 gui/dbus 全部文件（dbus_stub.c + wire/bus/sni/notify/upower/logind/netmon/inhibit/instance…），依赖改指 gui-sys。
15. import 改写：shell、showcase、tray_zombie_probe；注册与文档同步。
16. 门禁 → 提交 → Linux 真机清单（SNI 托盘/通知/MPRIS/单实例/logind）交用户。
17. `gui-dbus@0.1.0` 发版 + 钉版同步。
18. gui-window 模块内分包：`window` 核心 + `tray`/`hotkey`/`notify`/`instance`/`dialog` 平级包，测试随迁；同模块 import，无需新原语。
19. 核验 facade 对外 mbti 与第 2 步快照一致。
20. 托盘/热键真机复验 → 提交 → `gui-window@0.2.0`。
21. （可选）gui-sys 工具族按消费场景分包，有独立检索价值的才拆。
22. facade 定型：README/落地页「模块菜单」一节（每模块一行定位与单用场景）；中英文档同步；facade 标记版本另行决定。
23. webview 壳编排层单独立项（见「后续」）。

## 修订记录

- 2026-10-31 初版：tray/notify/hotkey/instance/message_box 计划迁入 gui-sys（gui-sys 依赖 gui-window 的隐藏消息窗原语）。
- 2026-10-31 修订：五件留在 gui-window、模块内分包（tray/hotkey/notify/instance/dialog）。理由：①事件循环寄生，与消息泵同模块，免掉「gui-window 暴露隐藏消息窗原语」的额外设计；②托盘两半边（window + dbus）比（sys + dbus）语义齐整；③不设独立 tray 模块——那会对 gui-window（Win32 半边）与 gui-dbus（Linux 半边）形成双向扇入，比现状差。

## 不变量与验收

- facade 对外 API 零变化：第 2 步的 mbti 快照是每步验收对照物。
- 每步 `moon check` 零错误零警告 + 相关包 `moon test`。
- prebuild 迁移的验收在真机（用户执行）：GUI 行为一律出操作清单，不远程驱动、不在反馈前下结论。
- 发版节奏：每模块 0.1.0 起发；facade 钉版清单全仓同步。

## 后续

- **webview 壳编排层**：基于 gui-window + gui-webview 的薄编排——IPC 命令契约（`register_protocol`/JS 求值往返上定义字符串协议 + MoonBit 端 CommandRegistry + 注入 `window.__*__.invoke` 运行时）、前端资产装载约定、dev 加载约定（加载 Vite dev URL）。打包器与 CLI 无限期后置。拆分完成后单独立项。
