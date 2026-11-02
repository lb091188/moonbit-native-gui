# TODO — 当前进行中的工作

> 只记「已实现、待复验 / 待收尾」的现行事项；规划与未来批次见 [docs/zh/roadmap.md](docs/zh/roadmap.md)「已规划」，实测坑与口径见 [experience/adaptation.md](experience/adaptation.md)。完成一项删一项，并同步路线图状态。


## 模板预编译（2026-11-01 启动，方案见 [proposals/native-template.md](proposals/native-template.md) 与 [proposals/mng-project-dev.md](proposals/mng-project-dev.md)；已完成叙事归 roadmap「开发体验」，此处只留未完成项）

### 真机复验（用户执行）

- [ ] **热更真机复验**：①`cd examples/showcase`（`mng.toml` 已提交：templates=「.」、build=`moon build .`、app-id 对齐应用；`run` 留空由 build 的 Artifacts 推导）②`moon run ../../tools/native-gui-tools/mng_cli -- dev` 起应用；③应用进「模板 Dev」页 ④改结构/字面量/`class`/`<style>` 值保存 → HOT（日志 `[HOT] 补丁已推送`、应用内 toast「模板补丁已应用」；样式章视觉——类槽覆盖/令牌/枚举值/交互态——随本步一并看）⑤改表达式文本（`@shared.tx("…")`、`{{ qty + 1 }}`、`v-if="qty > 5"`）→ 受限文法内 HOT；新函数/新符号 → `[HOT→COLD]` 带原因 ⑥改 script / v-for / 自定义组件 / 表外参数 → COLD，重启后自动回到改动页（`[COLD] 已请求回到模板页`）⑦把 stepper 调到 7 再走 HOT，值仍为 7（状态保活）；COLD 后回 3
- [ ] **编辑器真机复验**：`cd tools/vscode-mng && npx @vscode/vsce package` 打 0.2.4 vsix 安装（覆盖加 `--force`）→ Reload Window，按 `tools/vscode-mng/README.md` 清单一走——语义着色（类型/变量/参数/函数/方法/命名空间分档；主题未开语义高亮需设 `editor.semanticHighlighting.enabled: true`）、TextMate 着色、snippets、补全、Problems 诊断、hover、跳转

### 工具后续批次

- [ ] **preview 子命令**：独立预览窗（同一 applier + mock 状态），工具终态 dev/build/new/preview/lsp 的缺角
- [ ] **命令改名 `mng`**：`mng_cli` → `mng`（对外 DX 第一入口的命名，native-template 开放问题 5 + mng-project-dev 后续；改名同批核对 README/教程/编辑器插件 `mng.cliPath` 默认值与安装引导）
- [ ] **Windows dev 唤醒**：工具侧 Win32 单实例客户端——现仅 D-Bus 臂有套接字旁路，Windows HOT 推送未验
- [ ] **VS Code「MNG: dev」入口**：命令面板拉起 `mng dev` 并复用现有 lsp 诊断/补全（mng-project-dev 后续）
- [ ] **reload-theme 通道**：主题 token 定义改动热更（现走重启；native-template 热更节）
- [ ] **真实类型 hover**：桥 `moon ide` + source map 正向索引（native-template 开放问题 6，另批）
- [ ] **v2 热更方向**：子树对账状态保活（控件内部态焦点/滚动/IME 随重建重置的收窄）、列表行模板热编辑（v1 行内结构编辑回退）
- [ ] **生成物新鲜度 CI 校验**：生成物提交已定（开放问题 3 前半），CI 校验 `.gen.mbt` 与 `.mng` 的新鲜度未做——防手改生成码或忘重新生成
- [ ] **开放问题三项（待讨论）**：app 注入（页面拿 App 上下文的通路）；布局属性样式化口径收紧（优先级规则落点与存量构造参数迁移）；IR/注册表 rev 握手协议细节（键集上报格式、rev 对不上时的降级口径）

## 设计原则补齐（2026-11-02 拍板，落差清单见 [proposals/principles-gap.md](proposals/principles-gap.md)；按其 §五 优先级排序，做完一项删一项并同步路线图）



## 样式系统补全（2026-11-02 拍板，方案与风险注记见 [proposals/style-css-expansion.md](proposals/style-css-expansion.md)；S0 文档矛盾与 S5 letter_spacing 已完成，余项按 Tier 顺序）

- [ ] **Tier B 多行 line-height（真 leading，贵）**：三引擎各改一次 stub（Pango line attr / DWRITE_LINE_METRICS / kCTLineSpacingAttributeName），必须同时穿透 measure/paint（`resolved_for_measure` 同步，否则量画不一致）；注意与框增大触发的整窗重算（transition.mbt）相互作用


## 无头测试门面（2026-11-02 立项，方案与坑清单见 [proposals/headless-tester.md](proposals/headless-tester.md)；判据：没有显示服务的机器上，用使用者写代码的方式断言「点了按钮，界面变成那样」）

- [ ] **P1 公开包 `gui/uitest`（控件层，纯 MoonBit 可落地）**：`mount`/`mount_all` 建树；定位靠 name 不靠下标——`Node::named` 包装器落 `gui/widget/node.mbt`（Widget 加 `name`/`role` 两字段，pub(all) struct 属破坏性变更记发版说明；`bind_label` 动态文本要在绑定更新路径写回 `w.name`，否则 `text()` 永远读到初值）；动：click（Down+Up 成对封死，坐标按 rect 中心换算成窗口口径）/pointer/type_text/key/scroll/drag；看：`frame()` 无条件重算布局+重画（**不碰** `set_repaint_hook` 进程级单例，并行安全）/rect/text/pixel/bitmap；`Capabilities` 显式守卫（text_measure/image_decode/raster；依赖缺失的用例名带 `[需文本]`/`[需解码]` 前缀并计数打印，不静默通过）；不依赖 `ui`（防 test-import 自引用成环）；uitest 自身用黑盒 `uitest_test.mbt` 证「包外可用」；`form_wbtest.mbt` 示范迁移（私有 click 删除、断言条数不变），其余 37 个 wbtest 文件不动
- [ ] **P2 虚窗哨兵（应用泵层，单独立项）**：`Window::virtual_(width, height)`（id = -1 运行时哨兵；`size` 回字段、`present` 拷进程内快照缓冲、`poll_event` 从内存队列取、show/hide/request_focus 空操作；**哨兵分支只放 MoonBit 侧，C 桩一行不改**）；`App::test_headless` 造虚窗 Session 走 host_add_app；`session_pump_advance` 虚窗模式 `wait(0)` 不真睡；拿到定时器到期 / 脏区合并 / `follow_system_theme` 轮询 / `overlay_fit_pass` 三帧收框的可断言驱动（这些现在只能真机人工看）；真机人工验分工不变（平台窗口映射 / FFI / 输入法 / Retina 观感仍归人工）
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
