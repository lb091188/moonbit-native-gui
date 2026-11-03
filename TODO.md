# TODO — 当前进行中的工作

> 只记「已实现、待复验 / 待收尾」的现行事项；规划与未来批次见 [docs/zh/roadmap.md](docs/zh/roadmap.md)「已规划」，实测坑与口径见 [experience/adaptation.md](experience/adaptation.md)。完成一项删一项，并同步路线图状态。


## 模板预编译（2026-11-01 启动，方案见 [proposals/native-template.md](proposals/native-template.md) 与 [proposals/mng-project-dev.md](proposals/mng-project-dev.md)；已完成叙事归 roadmap「开发体验」，此处只留未完成项）

### 真机复验（用户执行）

- [ ] **热更真机复验**：①`cd examples/showcase`（`mng.toml` 已提交：templates=「.」、build=`moon build .`、app-id 对齐应用；`run` 留空由 build 的 Artifacts 推导）②`moon run ../../tools/native-gui-tools/mng_cli -- dev` 起应用；③应用进「模板 Dev」页 ④改结构/字面量/`class`/`<style>` 值保存 → HOT（日志 `[HOT] 补丁已推送`、应用内 toast「模板补丁已应用」；样式章视觉——类槽覆盖/令牌/枚举值/交互态——随本步一并看）⑤改表达式文本（`@shared.tx("…")`、`{{ qty + 1 }}`、`v-if="qty > 5"`）→ 受限文法内 HOT；新函数/新符号 → `[HOT→COLD]` 带原因 ⑥改 script / v-for / 自定义组件 / 表外参数 → COLD，重启后自动回到改动页（`[COLD] 已请求回到模板页`）⑦把 stepper 调到 7 再走 HOT，值仍为 7（状态保活）；COLD 后回 3
- [ ] **编辑器真机复验**：`cd tools/vscode-mng && npx @vscode/vsce package` 打 0.2.4 vsix 安装（覆盖加 `--force`）→ Reload Window，按 `tools/vscode-mng/README.md` 清单一走——语义着色（类型/变量/参数/函数/方法/命名空间分档；主题未开语义高亮需设 `editor.semanticHighlighting.enabled: true`）、TextMate 着色、snippets、补全、Problems 诊断、hover、跳转

### 工具后续批次

- [ ] **Windows LSP 跳转落点收口**：`mng` 的 LSP 定义跳转在 Windows 上的路径分隔符与行号口径未验，用例 `lsp_wbtest` 现按盘符分流跳过（POSIX 形态断言照跑）——真机验一遍后把 Windows 支也钉上
- [ ] **握手与折层真机复验**（用户执行）：①`mng dev` 跑起来后进「模板 Dev」，改 script 加一个新 Store 并保存 → 该改本应 COLD，若工具侧先推了 HOT 补丁，日志应出现 `[HOT→COLD] 握手不符：注册表键集落后…` 随后 `[COLD] … 应用已重启`、应用回到改动页（**不再出现「补丁失败」toast 后界面停在旧树**）；②正常 HOT（只改结构/字面量）日志 `[HOT] 补丁已应用`，应用内 toast 同步；③样式全序：给 `hover_group` 挂 `class=[style(padding=14.0)]` 的条目看内缩真的按 class 走（散参数 `<` class）

## 主题与样式批次真机复验（用户执行；落地项已在 roadmap「已实现·主题与样式」标 🚧，过了逐条翻 ✅）

- [ ] **样式补全观感**：showcase「过渡与效果」页与「画布与富文本」页看四件——渐变背景（线性/径向、stop 用主题 token 时随主色变；半透明 stop 在 Windows/mac 的插值口径与 Linux 是否一致）、每角圆角与每边边框（不等半径四角、四边独立宽色；带圆角时 per-side 回落统一描边是否诚实）、`mix_blend_mode` 混排（改档看有没有漏到同帧兄弟）、删除线与上划线（折行段落落在最后一行）；令牌间距看整板留白是否仍与改前一致
- [ ] **主题批次观感**：`examples/theme-playground` 按 TP-1.1..5.1 走完（深色系统起窗即深色=默认一次性探测生效）；主题 JSON 落盘改色（dev 档 `mng.toml` `theme` 键存盘即重载）；深浅变体看 tooltip 反色与滚动条/分隔线深档提亮；code_view 在浅色与深色主题下底色跟不跟 `theme_current()`，显式 `code_theme` 是否钉死
- [ ] **窗口族探测口径**：`shell_caps()` 八位在无合成器的 Linux 会话上 `opacity`/`transparent_bg` 位应为 false，`set_transparent_bg` 应回 `Unsupported` 而非静默无效；`native_handle()` 三平台返回值非 0 且能喂给平台 API

## 文本选择与屏读语义（2026-11-03 拍板，方案与坑清单见 [proposals/text-selection-a11y.md](proposals/text-selection-a11y.md)；两个消费者一块地基，做完一项删一项并同步路线图）

- [ ] **二期阶段1·macOS NSAccessibility 桥**：实现已收口（2026-11-03 二批：WMA11yElement 子类带 press 动作压跨平台动作队列、accessibilityFocusedUIElement 按焦点 id 还元素、accessibilityHitTest 按屏幕点还最深元素、快照内容变/焦点换发 AX LayoutChanged/FocusedUIElementChanged 通知、MoonBit 每帧报焦点 id）；剩 VoiceOver 真机清单（朗读 / 状态翻转 / 逐字输入 / press 触发不双触）待用户执行，见测试用例附录 F
- [ ] **二期阶段2·Linux AT-SPI 桥**：实现已落（2026-11-04，`gui/shell/atspi.mbt`：第三总线连接 + Socket.Embed 注册 + 对象树四接口 Accessible/Component/Text/Value + Action 动作 + 事件上行；协议面按 at-spi2-core 2.52 本机实证，详见 adaptation.md）。剩 Orca 真机清单（Tab 遍历朗读 / flat-review 逐行读 / 对按钮按读屏 press 触发不双触 / 中文名与逐字偏移）待用户执行，见测试用例附录 F

## 核查收口批（2026-11-03 核查：浮层原生档与 mac GIF 代码已在树——两件文档追平、三件真机复验；dock/任务栏进度这类单平台条目不做，已从待办与路线图撤下）

- [ ] **Windows UIA 真机复验**（用户执行）：NVDA + Accessibility Insights for Windows 过一遍——①Tab + 方向键遍历同一页，朗读 role/name/状态（勾选态/百分比值/只读/密码保护态）；②Accessibility Insights 树里可见完整控件层级，选中滑杆看 RangeValue 随拖动更新；③对按钮/勾选/下拉用读屏的 Invoke/Toggle/Expand，动作应真的触发（桥合成点击，不与应用自己的点击双触发）；④中文名不乱码（BSTR 走 UTF-8→UTF-16 转换）；⑤快照表是进程级单表，只验单窗应用（多窗边界见 uia_provider.c 头注）
- [ ] **浮层原生档真机复验**（用户执行）：browser 示例按 BR-1.4 过 Windows 与 mac——弹层无边框贴按钮、条目完整不裁、点外/失焦/Esc 都收、反复开关不叠窗；过了把 roadmap「浮层原生档」翻 ✅
- [ ] **mac GIF 真机复验**（用户执行）：showcase「GIF 动图」段（SC-14.4）自转/暂停/继续/缩放档，透明底 GIF 看有没有底色块（有=透明索引缺口另立）；过了 roadmap 翻 ✅、测试用例.md 附录 B「GIF 在 macOS 只显示首帧」行删，顺带修正 stub.c/adaptation「DisposalMethod 不在 Apple 公开清单」旧注（该键实为公开常量，ImageRectangle 才不在）
- [ ] **通知 urgent 二档真机复验**（用户执行，mac）：同一应用分别发 `urgent=true`（缺省）与 `urgent=false`，应用正在前台跑事件循环时前者出横幅、后者只进通知中心不出条；系统设置里关掉「时间敏感」授权后再发 `urgent=true` 应回落到静默。状态行 `backend=` 应报 `un-user-notification`（Linux 报 `dbus`、Windows 报 `win-balloon`）
- [ ] **frame_cost_probe 三平台读数**（用户执行，Windows / macOS 各一遍）：`moon run experiment/frame_cost_probe`，贴全部 `FRAME-COST` 行——重点看 `paint_full` vs `paint_clip` 的 `skip`（纯光栅腿才判交，那条腿的差值才是「图表/整页增量重绘」的立项依据）。Linux 腿已跑：树不变 relayout 20 帧 `ms=0`、`measure=0`（yoga 布局缓存不立项），整页 240 行 ≈3.5ms/帧（判据进测试用例附录 D）

## Wayland 原生路径（2026-11-03 立项，能力出路总表、DE 支持矩阵与坑清单见 [proposals/wayland-native.md](proposals/wayland-native.md)；先 spike 后分期，做完一项删一项并同步路线图）

- [ ] **Spike S1/S2（本体行为 + XWayland 假数据实测，用户执行）**（P0 探针已先行落地：`@sys.session_type()`，夜灯/窗口管理按它降级，预期表进测试用例附录 E）：Ubuntu 24.04 GNOME Wayland + deepin 25 Treeland 跑 hello/showcase 相邻条目；xrandr 输出形态 / redshift 退出码与实际效果 / wmctrl 可见窗口集合——产出「返回成功但无效」清单，定 P0 探针写法（判据见方案 §五）
- [ ] **Spike S3–S8（用户执行）**：GlobalShortcuts 全流程（KDE+GNOME 各一台）、空闲双档误差、Treeland 协议面探测矩阵、夜灯配置口生效与复位、显示器字段对照、弹层定位
- [ ] **P1 portal 骨架 + 全局快捷键 + 空闲检测**：实现已落（2026-11-04：`gui/dbus/portal.mbt` Request/Response 通用层（token 生成 / request 路径派生 / Response 一次性订阅）、`gui/shell/global_shortcuts.mbt` 绑定 + Activated 信号回调门面、`gui/shell/idle.mbt` GNOME IdleMonitor 精确读数 + 集成门面；`dbus` 包补退订与 a11y 之外的第三条总线之外本条用到的会话总线一次性订阅）；剩 GlobalShortcuts 授权框真机清单（KDE 5.27+/GNOME 48+ 各一台）与 ext-idle-notify 近似档（KDE/wlroots，待 Wayland 协议客户端地基）归用户/后续批
- [ ] **P2 夜灯逐 DE + 显示器枚举**：实现已落（2026-11-04：`gui/shell/nightlight.mbt`——GNOME 写 gsd-color 配置键（gsettings CLI，本机 schema 实证）、KDE 走 ColorCorrect 读侧（Plasma 5.27 实物属性全 read-only，写侧 Unsupported；Plasma 6 NightLight 写入口径未核）、wlroots 裸 gamma 待协议客户端；`gui/shell/monitor_dbus.mbt`——KScreen getConfig 解析（本机实证 9 输出/2 已连/30 模式、refreshRate 是 int64 赫兹）、mutter DisplayConfig 只探存在（字段序未核不产读数）、wlroots 待协议客户端）。剩 S6/S7 真机（KDE/GNOME 各一台）与 wlroots 档归后续（含首个 Wayland 协议客户端地基 libwayland vs 自写 wire 的评估）
- [ ] **P3 剪贴板监视协议化 + wlroots 窗口管理**：wlr-data-control + ext-data-control-v1 双协议（Plasma 6.5 迁移坑）；窗口管理仅 wlroots 系（wlr-foreign-toplevel）；GNOME/KDE 窗口管理与层级族按「无通道」出文档；同批更新 roadmap 会话表与 DE 实测矩阵

## GPU 与媒体硬解（2026-11-03 定案，模块形态/融合模型/分批见 [proposals/gpu-architecture.md](proposals/gpu-architecture.md)；硬解独立先行与 GPU 线并行、互不绑定，做完一项删一项并同步路线图）

- [ ] **第一步·X11 wgpu 三角形验收**（真机肉眼，方案既定第一步；验收判据落本批提交）
- [ ] **L1-Linux present 纹理合成**：wm_present GTK X11 臂走「Bitmap 上传纹理 → 全屏 quad → swapchain」；fallback 探测粒度与 Wayland 会话臂随后
- [ ] **L1-Win / L1-mac**：D3D12 swapchain 挂 HWND / CAMetalLayer 挂 NSView，与现有 blit 的切换与回退（回退后逐像素一致）
- [ ] **首消费者**：视频直纹理接口位（仅接口不实现导入）；GPU 内容画布 demo 页（赛季验收面）
- [ ] **硬解探针**（Linux 腿已跑通到「真解一帧」：`open_video_decoder(hw=true)` 走 VAAPI + transfer，首帧与软解逐字节一致，`hw_status=1`；`experiment/hwdecode_probe` 逐设备 open/frames/transfer 读数进方案 §四，设备建得起来≠能用、transfer 全空两条坑已记；Win/mac 两腿待跑）：三平台 hw_device_ctx 能建（VideoToolbox / D3D11VA / VAAPI）+ 归档实物核验（Linux 发行版 ffmpeg 的 `ffmpeg -hwaccels`、Windows BtbN lgpl 归档已命中 `av_d3d11va_alloc_context`、mac 归档脚本从初立就带 `--enable-videotoolbox`——旧判「重做评估」已过期，只剩 `otool -L` 验实物与 LICENSE.txt 口径修正）；未决见 proposals/media-hwdecode.md §六 spike
