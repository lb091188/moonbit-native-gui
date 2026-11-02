# TODO — 当前进行中的工作

> 只记「已实现、待复验 / 待收尾」的现行事项；规划与未来批次见 [docs/zh/roadmap.md](docs/zh/roadmap.md)「已规划」，实测坑与口径见 [experience/adaptation.md](experience/adaptation.md)。完成一项删一项，并同步路线图状态。


## 模板预编译（2026-11-01 启动，方案见 [proposals/native-template.md](proposals/native-template.md)；总顺序：模板 → VS Code 插件 → 拆包）

- Phase 0 探针已完成（2026-11-01：单次热替换 10.4 ms、泄漏 0、订阅跨代恒定，见 `experiment/ir_probe` 与方案回写）
- 编译器 `build` 子命令已完成（2026-11-02：`tools/native-gui-tools/mngkit` 内核 + `tools/native-gui-tools/mng_cli`，golden 9/9、source map 错误回映射端到端验通；`ir`/`new` 子命令就位）
- [ ] **热更真机复验**：端到端 GUI 验证由用户执行——步骤：①`cd examples/showcase`（`mng.toml` 已提交：templates=「.」、build=`moon build .`、app-id 对齐应用；`run` 留空由 build 的 Artifacts 推导）②`moon run ../../tools/native-gui-tools/mng_cli -- dev` 起应用；③应用进「模板 Dev」页 ④改结构/字面量/`class`/`<style>` 值保存 → HOT（日志 `[HOT] 补丁已推送`、应用内 toast「模板补丁已应用」）⑤改表达式文本（`@shared.tx("…")`、`{{ qty + 1 }}`、`v-if="qty > 5"`）→ 受限文法内 HOT；新函数/新符号 → `[HOT→COLD]` 带原因 ⑥改 script / v-for / 自定义组件 / 表外参数 → COLD，重启后自动回到改动页（`[COLD] 已请求回到模板页`）⑦把 stepper 调到 7 再走 HOT，值仍为 7（状态保活）；COLD 后回 3
- `dev` 子命令已完成（2026-11-02：watch 内容对比 + 回退编排 build→杀旧→带参重启；HOT 分支产 IR 经单实例通道 `--mng-hot` 推送，应用侧按 `page` 取 holder 原位重挂（script 段状态保活）；动态槽键按表达式内容哈希；class 名与 `<style>` 规则随补丁重注册；新表达式按受限 AST 在应用侧求值（v2a-1：字面量/Store/运算/比较/逻辑/if/`@shared.tx`·`tr`/字符串插值）；COLD 重启后按改动页 stem 唤醒回页；D-Bus 臂补套接字旁路供 dev 工具送达；配套 gui/sys 进程原语补 pr_spawn/pr_alive/pr_kill/pr_sleep_ms）
- 模板 dev 档已完成（2026-11-02，批次 A：`mngkit.compile_dev` 产页面注册表与 holder 落点（expr/cond/handler/state 四类，键沿用 IR）、app 侧 `mng_dev_page` 通用件、showcase 演示页改调生成页并删手写注册表、`mng dev` 产 dev 形态；生成码提交的仍是生产形态）
- 项目级 dev 已完成（2026-11-02，批次 B：`mng.toml` 解析（`[dev] templates / build / run / app-id / poll-ms`，极小 key=value 子集）、`mng dev` 无参向上找配置/按 moon.mod 推默认、递归扫模板（跳过 `_build`/`.mooncakes`/点目录）、生成码落模板所在包、一拍多改动合并成一次 build/重启、app-id 由 moon.mod name 派生、`run` 留空时从 build 的 `Artifacts` 抓可执行、撞名按包聚合、`mng_cli init` 样板；方案见 [proposals/mng-project-dev.md](proposals/mng-project-dev.md)）
- 编辑器支持已完成（2026-11-02：`mng_cli lsp` + `tools/vscode-mng` 静态贡献包（`.mng` 语言注册 / TextMate 着色 / snippets / 手写零依赖 LSP 客户端，握手 `mng-schema 1`，对不上降级为空）；着色补齐属性值表达式、CSS 数值单位与枚举值，脚本段与属性值共用一套表达式着色（类型/变量/函数/常量分色，class 引用用类名 scope，关键字分声明/修饰/控制三档，命名空间与 `::`/括号单列）；语义着色已加 LSP semantic tokens 通道（0.2.4）——`mng_cli lsp` 的 `semanticTokens/full` 按符号表分档（类型/let 变量+readonly/props 与 fn 参数/函数/方法/属性/`@包` 命名空间，只发标识符类，`:attr`/`@事件`/`v-model`/`{{ }}` 槽与 script 段同规则），VSIX 注册语义 provider 转发，TextMate 文法不动，LSP 降级退回纯 TextMate（主题未标语义高亮需设 `editor.semanticHighlighting.enabled: true`，见 README）；样式编译错误坐标回到模板真实行，`<style>` 段补全属性名与 `var(--令牌)`；hover 按令牌类型给说明（`v-*`/`@事件`/`:动态参数`，不再把指令当组件），组件参数表与属性补全从签名取全量（含可省参数、默认值与参数级 `///` 说明），内置组件已逐个补参数文档，文案按编辑器语言中英切换；跳转与补全打通外部包——`@别名.成员`（含 `类型::方法`）按 `moon.pkg` 别名解析到源码文件与行号、`.mbti` 供成员表，裸 `@别名` 到包入口，内置 `ui-*` 标签到 `@ui.<名>` 源码；待真机：重打包安装 0.2.4 vsix 后按 `tools/vscode-mng/README.md` 清单一走——语义着色、着色、snippets、补全、Problems 诊断、hover、跳转）
- 组件带参已完成（2026-11-02：script 段「只有签名无函数体」的 fn 头即 props（必填位置参、可选 `名? : 类型 = 默认值`，探针结论见 `experience/adaptation.md`）；跨包组件路径从 `let` 右值取、参数顺序从源码签名解析（`mngkit.Sigs` 注入文件端口），同包组件按标签名零声明；`// @mng` 降为不规则落点逃生口；未用 prop 出 `let _ =` 垫片、纯组件绑定的 let 不进生成体，保住零警告门禁；mngkit 测试 14/14）
- 样式章已完成（2026-11-02：`<style>` 类选择器摊平成 `define_class`、`class="a b"` → `class_of`、`var(--令牌)`（20 枚主题色 + 尺度令牌）、`#rrggbb`、枚举关键字、`.名:dark` 深浅两档按 `@win.sys_color_scheme()` 选；模板属性里的样式字面量编译报错；IR 带 class 名与类定义数据（属性名 + 编译期值），补丁可重注册命名类；mngkit 测试 29/29；真机视觉待用户按清单验）
- 撞名检测与注册表键控已完成（2026-11-02：build/dev 报同包 stem 撞名并点名文件；dev 注册表与 holder 按 IR 的 `page` 键控，多页并存不串表，showcase dev 页与 wbtest 同步）
- 工具与 GUI 解耦已完成（2026-11-02：`mng_cli` 不再依赖 `gui/sys`——`gui/sys` 在 Linux 上链 GTK 剪贴板符号，命令行工具不能带上它；改为 tools 内自给 `proc`（进程原语）与 `inst`（单实例客户端，帧格式与 shell 通道一致），二进制只链 libc/libgcc；proc/inst 无头测试 6/6）
- 工具链收口已完成（2026-11-02：`mng_cli lsp` stdio JSON-RPC（initialize / didOpen·didChange / completion / hover / definition / shutdown，诊断走 compile 错误坐标）；`--version` 报 `mng-cli 0.1.0` + `mng-schema 1` 供插件握手；native-gui-tools 的 moon.mod 描述与发布配置就位；LSP 无头回归 1 条）
- [x] **拆包已回退**（2026-11-02 定案）：四模块曾按 [proposals/module-split.md](proposals/module-split.md) 完整落地并全绿，随即回退——不对外发行则单件检索面动机不成立；方案留档、四个落地提交在历史可复活。重启条件：决定对外发版单件

## 设计原则补齐（2026-11-02 拍板，落差清单见 [proposals/principles-gap.md](proposals/principles-gap.md)；按其 §五 优先级排序，做完一项删一项并同步路线图）

- [ ] **os-macos 重截**：i18n 修复（4dc3e96b）CI 新包上，mac 切英文后确认侧栏分组标题为 Components / System 再截 showcase，贴边裁净、无背后窗口残影与指针，覆盖 `docs/public/images/os-macos.png`
- [ ] **Windows 真机复验**（browser 示例两处修复，f840edfa）：①冷启动后首页点「JS 调原生绑定」不再报 demoBinding is not defined；②本地片段页「触发下载请求」弹系统保存框、落盘可打开（blob 换 yuedemo://local/ngui.txt）
