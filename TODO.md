# TODO — 当前进行中的工作

> 只记「已实现、待复验 / 待收尾」的现行事项；规划与未来批次见 [docs/zh/roadmap.md](docs/zh/roadmap.md)「已规划」，实测坑与口径见 [experience/adaptation.md](experience/adaptation.md)。完成一项删一项，并同步路线图状态。


## 模板预编译（2026-11-01 启动，方案见 [proposals/native-template.md](proposals/native-template.md) 与 [proposals/mng-project-dev.md](proposals/mng-project-dev.md)；已完成叙事归 roadmap「开发体验」，此处只留未完成项）

### 真机复验（用户执行）

- [ ] **热更真机复验**：①`cd examples/showcase`（`mng.toml` 已提交：templates=「.」、build=`moon build .`、app-id 对齐应用；`run` 留空由 build 的 Artifacts 推导）②`moon run ../../tools/native-gui-tools/mng_cli -- dev` 起应用；③应用进「模板 Dev」页 ④改结构/字面量/`class`/`<style>` 值保存 → HOT（日志 `[HOT] 补丁已推送`、应用内 toast「模板补丁已应用」；样式章视觉——类槽覆盖/令牌/枚举值/交互态——随本步一并看）⑤改表达式文本（`@shared.tx("…")`、`{{ qty + 1 }}`、`v-if="qty > 5"`）→ 受限文法内 HOT；新函数/新符号 → `[HOT→COLD]` 带原因 ⑥改 script / v-for / 自定义组件 / 表外参数 → COLD，重启后自动回到改动页（`[COLD] 已请求回到模板页`）⑦把 stepper 调到 7 再走 HOT，值仍为 7（状态保活）；COLD 后回 3
- [ ] **编辑器真机复验**：`cd tools/vscode-mng && npx @vscode/vsce package` 打 0.2.4 vsix 安装（覆盖加 `--force`）→ Reload Window，按 `tools/vscode-mng/README.md` 清单一走——语义着色（类型/变量/参数/函数/方法/命名空间分档；主题未开语义高亮需设 `editor.semanticHighlighting.enabled: true`）、TextMate 着色、snippets、补全、Problems 诊断、hover、跳转

### 工具后续批次

- [ ] **真实类型 hover**：桥 `moon ide` + source map 正向索引（native-template 开放问题 6，另批）
- [ ] **开放问题三项（待讨论）**：app 注入（页面拿 App 上下文的通路）；布局属性样式化口径收紧（优先级规则落点与存量构造参数迁移）；IR/注册表 rev 握手协议细节（键集上报格式、rev 对不上时的降级口径）

## 设计原则补齐（2026-11-02 拍板，落差清单见 [proposals/principles-gap.md](proposals/principles-gap.md)；按其 §五 优先级排序，做完一项删一项并同步路线图）



## 样式系统补全（2026-11-02 拍板，方案与风险注记见 [proposals/style-css-expansion.md](proposals/style-css-expansion.md)；S0 文档矛盾与 S5 letter_spacing 已完成，余项按 Tier 顺序）



## 无头测试门面（2026-11-02 立项，方案与坑清单见 [proposals/headless-tester.md](proposals/headless-tester.md)；判据：没有显示服务的机器上，用使用者写代码的方式断言「点了按钮，界面变成那样」）

- [ ] **开放问题（随期定）**：Capabilities 跳过计数是否进 CI 门禁（先观察不设阈值）；`test_headless` 对外公开与否（公开即契约，须连同「虚窗 ≠ 真窗」语义边界写文档）；像素快照基线（PNG + 容差，工作量远大于 P1 主体，建议单独立项）；`name`/`role` 将来接无障碍时复用同一对字段（倾向复用，本期不承诺）

## 文本选择与屏读语义（2026-11-03 拍板，方案与坑清单见 [proposals/text-selection-a11y.md](proposals/text-selection-a11y.md)；两个消费者一块地基，做完一项删一项并同步路线图）

- [ ] **一期首批·TextLayout 地基抽取**：`layout_lines`/`byte_at`/`caret_x_y` 从 textarea 闭包升格 gui/input 纯函数集（测宽函数注入，维持零平台依赖）；textarea/entry 等价改用，既有 wbtest 钉住零行为变化
- [ ] **一期首批·静态文本 selectable 档**：`text`/`text_dyn` 加 selectable（只读 Editor + 选区持有者注册表 + 单击/双击选词/拖选/Shift+点击 + Ctrl+C 宿主内建支 + 右键菜单 can_edit=false）；测量面与绘制面同源切 TextLayout（最大坑，缺省档一行不动）
- [ ] **一期首批·code_view 选中**：预排版表加字节偏移列；行号列排除在选区外，复制按行拼 \n，横滚坐标经控件矩形平移
- [ ] **一期次批·markdown 段落选中**：md_rich_label 混排联合量宽逐字命中（joint_w 模式 + wcache 防 O(n²)），首批注册表/菜单/复制在纯文本闭环后再接
- [ ] **一期缓批·AttributedText 逐字选中**：单独立项——需在 @text 开逐字几何接口动三平台 C 桩，违背一期「不碰平台桥」约束
- [ ] **二期阶段0·语义地基**（与 uitest P1 同批落 Widget 字段，破坏性变更一次做掉）：name/role/enabled + a11y_state/a11y_text 值回调 + ARole 枚举解析视图；C 侧语义槽表 + 帧尾对账；gui/README.md non-goals 口径修正随批
- [ ] **二期阶段1·macOS NSAccessibility 桥**：WMView 挂协议 + accessibilityChildren 轻量元素；VoiceOver 真机清单（朗读 / 状态翻转 / 逐字输入）
- [ ] **二期阶段2·Linux AT-SPI 桩**：第三总线连接 + Socket.Embed 握手 + 对象树四接口；spike 三未核项（注册握手版本兼容 / Text 偏移单位字符 vs 字节 / XFCE·deepin a11y bus 启用态）；Orca 真机清单
- [ ] **二期阶段3·Windows UIA provider**：WM_GETOBJECT + IRawElementProviderSimple/Fragment + 五 pattern；GUID 取法探针先行（大概率复刻 WIC 套路待证）；NVDA + Accessibility Insights 真机清单

## 核查收口批（2026-11-03 核查：浮层原生档与 mac GIF 代码已在树、任务栏进度缺登记——三件文档追平、两件小代码、三件真机复验）

- [ ] **浮层原生档真机复验**（用户执行）：browser 示例按 BR-1.4 过 Windows 与 mac——弹层无边框贴按钮、条目完整不裁、点外/失焦/Esc 都收、反复开关不叠窗；过了把 roadmap「浮层原生档」翻 ✅
- [ ] **mac GIF 真机复验**（用户执行）：showcase「GIF 动图」段（SC-14.4）自转/暂停/继续/缩放档，透明底 GIF 看有没有底色块（有=透明索引缺口另立）；过了 roadmap 翻 ✅、测试用例.md 附录 B「GIF 在 macOS 只显示首帧」行删，顺带修正 stub.c/adaptation「DisposalMethod 不在 Apple 公开清单」旧注（该键实为公开常量，ImageRectangle 才不在）
- [ ] **任务栏进度真机复验**（用户执行）：native-app「任务栏进度」区块七写入口的真观感（绿/红/黄条、不确定滚动）；过了 roadmap 翻 ✅、测试用例.md 补专条
- [ ] **通知后端名收口**：mac 档报 ns-user-notification 名不副实（UN 迁移后）改 un-user-notification；notify.mbt:86 注释清单补第三档；notify_wbtest.mbt:59 断言按平台分期望
- [ ] **通知 urgent 参数**：notify_send 加 urgent?=true 可选参（缺省 true，仅 mac 臂映射 interruptionLevel 二档 TimeSensitive/Active）；C 侧 wm_notify_send 四臂签名同步（非 mac 臂收参忽略）；授权补齐逻辑不动；契约注释写死「urgent=false / 系统关掉时间敏感授权 = 前台忙时静默」；Linux freedesktop urgency hint 不映射（critical=常驻语义，串档）
- [ ] **dock 徽标 mac 臂**：stub.c mac 段 wm_dock_badge_set（[NSApp dockTile] setBadgeLabel，nil 清）+ win 包 set_dock_badge(count)->Bool（count<=0 清，app 级非窗级）；裸二进制 Dock 通用图标徽标是否渲染待实测，打包 .app 路径为准
- [ ] **LauncherEntry Linux 臂**：gui/dbus 新 launcher.mbt，dbus_emit_signal_session 发 com.canonical.Unity.LauncherEntry Update（app_uri=application://<desktop-id>.desktop + count/count-visible/progress/progress-visible）；真机前提=装 .desktop；吃口=Ubuntu Dock / KDE 任务栏 / XFCE docklike（Cinnamon/deepin 未核）
- [ ] **dock 门面合流**：shell 层按平台分派（mac→@win、Linux→@dbus、Windows false）；窗级进度与 app 级徽标语义分档如实注释；Windows SetOverlayIcon（状态图标非计数）做不做同批定
- [ ] **贡献入口**：.github ISSUE_TEMPLATE（bug/feature 两表+config，回报格式引用用例文档「编号+现象+截图+退出读数行」约定）+ CONTRIBUTING 骨架（指向 build.md 与门禁命令，不与 AGENTS.md 双源）+ PR 模板简版
- [ ] **性能基线探针**：experiment/ 独立模块——帧耗时分段（扩 LAYOUT-FRAME 账本观测面）+ 每帧重绘范围 + 布局重算次数三组读数；有数据再定 yoga 布局缓存与图表增量重绘立不立项

## Wayland 原生路径（2026-11-03 立项，能力出路总表、DE 支持矩阵与坑清单见 [proposals/wayland-native.md](proposals/wayland-native.md)；先 spike 后分期，做完一项删一项并同步路线图）

- [ ] **Spike S1/S2（本体行为 + XWayland 假数据实测，用户执行）**：Ubuntu 24.04 GNOME Wayland + deepin 25 Treeland 跑 hello/showcase 相邻条目；xrandr 输出形态 / redshift 退出码与实际效果 / wmctrl 可见窗口集合——产出「返回成功但无效」清单，定 P0 探针写法（判据见方案 §五）
- [ ] **P0 会话探测与口径收口**：XDG_SESSION_TYPE + WAYLAND_DISPLAY 探针；nightlight 在 Wayland 会话不得因 redshift 存在报 supported；monitor 的 XWayland 假名在 caps/文档声明；「Wayland 会话能力预期表」进测试文档
- [ ] **Spike S3–S8（用户执行）**：GlobalShortcuts 全流程（KDE+GNOME 各一台）、空闲双档误差、Treeland 协议面探测矩阵、夜灯配置口生效与复位、显示器字段对照、弹层定位
- [ ] **P1 portal 骨架 + 全局快捷键 + 空闲检测**：gui/dbus portal 客户端通用层（Request/Response 异步握手）；GlobalShortcuts「绑定+信号回调」门面形态；空闲 GNOME IdleMonitor 精确档 + ext-idle-notify 近似档
- [ ] **P2 夜灯逐 DE + 显示器枚举**：KDE ColorCorrect/NightLight（S6 定版本分界）、GNOME gsettings 配置口、wlroots wlr-gamma-control 裸 gamma；显示器 mutter DisplayConfig（锁版本）+ wlr-output-management（KDE 通道 S7 定）；首个 Wayland 协议客户端地基（libwayland vs 自写 wire）单独评
- [ ] **P3 剪贴板监视协议化 + wlroots 窗口管理**：wlr-data-control + ext-data-control-v1 双协议（Plasma 6.5 迁移坑）；窗口管理仅 wlroots 系（wlr-foreign-toplevel）；GNOME/KDE 窗口管理与层级族按「无通道」出文档；同批更新 roadmap 会话表与 DE 实测矩阵
