# TODO — 当前进行中的工作

> 只记「已实现、待复验 / 待收尾」的现行事项；规划与未来批次见 [docs/zh/roadmap.md](docs/zh/roadmap.md)「已规划」，实测坑与口径见 [experience/adaptation.md](experience/adaptation.md)。完成一项删一项，并同步路线图状态。


## 模板预编译（2026-11-01 启动，方案见 [proposals/native-template.md](proposals/native-template.md) 与 [proposals/mng-project-dev.md](proposals/mng-project-dev.md)；已完成叙事归 roadmap「开发体验」，此处只留未完成项）

### 真机复验（用户执行）

- [ ] **热更真机复验**：①`cd examples/showcase`（`mng.toml` 已提交：templates=「.」、build=`moon build .`、app-id 对齐应用；`run` 留空由 build 的 Artifacts 推导）②`moon run ../../tools/native-gui-tools/mng_cli -- dev` 起应用；③应用进「模板 Dev」页 ④改结构/字面量/`class`/`<style>` 值保存 → HOT（日志 `[HOT] 补丁已推送`、应用内 toast「模板补丁已应用」；样式章视觉——类槽覆盖/令牌/枚举值/交互态——随本步一并看）⑤改表达式文本（`@shared.tx("…")`、`{{ qty + 1 }}`、`v-if="qty > 5"`）→ 受限文法内 HOT；新函数/新符号 → `[HOT→COLD]` 带原因 ⑥改 script / v-for / 自定义组件 / 表外参数 → COLD，重启后自动回到改动页（`[COLD] 已请求回到模板页`）⑦把 stepper 调到 7 再走 HOT，值仍为 7（状态保活）；COLD 后回 3
- [ ] **编辑器真机复验**：`cd tools/vscode-mng && npx @vscode/vsce package` 打 0.2.4 vsix 安装（覆盖加 `--force`）→ Reload Window，按 `tools/vscode-mng/README.md` 清单一走——语义着色（类型/变量/参数/函数/方法/命名空间分档；主题未开语义高亮需设 `editor.semanticHighlighting.enabled: true`）、TextMate 着色、snippets、补全、Problems 诊断、hover、跳转

### 工具后续批次

- [ ] **dev 临时产物目录 `.mng/`**：现在 app 日志（`examples/showcase/.mng-dev-app.log`）、source map（`pages/dev_demo.gen.mbt.map`）、IR 补丁（`pages/dev_demo.ir.json`）全散在源码目录（已 gitignore 但文件浏览器里裸露，污染源码树）。改法——dev 循环的产物统一落 `<项目根>/.mng/`：`logs/<app-id>.log`、`map/<相对包路径>/<stem>.gen.mbt.map`、`ir/<相对包路径>/<stem>.ir.json`；`.gitignore` 加 `**/.mng/`；`map-errors --map` 显式传参不受影响（dev 循环内部自管路径、文档同步）；`build` 子命令的显式 `-o` 语义不变；顺手清掉现有散落文件。改动点：`mng_cli/dev.mbt`（app_log、irpath、dev 编译 map 路径三处）
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

- [ ] **1.1 平台原生句柄透出**：三平台桩各加 `wm_native_handle(slot) -> int64_t`（Windows 取槽表 hwnd / GTK 复用 `wm_surface_container` 取法、口径在契约注释钉死 / mac 取桩内 NSWindow*，无窗口后端回 0），MoonBit 侧 `Window::native_handle() -> Int64`，文档标注「裸句柄、平台语义、仅逃生用，跨平台代码不得依赖」；白盒测试覆盖
- [ ] **2.1 主题 JSON 加载**：`@theme.from_json(String) -> Result[Theme, String]`——字段名白名单 = `Theme` 字段、未知字段报错、允许部分缺省（回落 `default_theme()`/`dark_theme()` 基底）；复用 `@sys` JSON 原语，不引属性名解析器；wbtest 覆盖（合法 / 未知字段 / 缺省回落）
- [ ] **2.2 跟随系统默认接线 + 表述对齐**：`mount_window` 默认做一次 `theme_from_system` 探测并应用（单次探测无轮询成本；显式 `theme_apply` 的应用不受影响；轮询跟随器保持 opt-in）；docs/zh/index.md「默认跟随系统深浅色」与 tutorial.md「默认已整套跟随」两处表述落实后核对为真
- [ ] **3.1 窗口族诚实降级（分两步）**：①文档步——`Window::set_title/set_icon/set_min_size/set_opacity/set_transparent_bg` 等契约注释逐平台钉死读回值含义（非 Windows 空实现读回 0/false、无合成器静默无效、Windows 透明底前置无边框，全部写明）；②签名步（0.x 破坏性改动）——补 `*_supported()` 探测或 setter 返回 `Result`/`Bool`，前置不满足进 `Failed` 档带原因文案（对齐系统能力族口径）
- [ ] **1.4 `@ui` 公共面收窄**：`button_skin` / `button_skin_token` / `paint_subset` / `fold_color` / `mask_of` 逐个判断去向——纯实现细节去 pub（0.x 破坏记提交信息），确有外部价值的（如 `fold_style`）保留并写文档；同批核对 examples 与测试文档无引用
- [ ] **2.3 `dark:`/`light:` 变体接入组件消费**：从 `gui/style/tokens.mbt` 挑 2–3 个确需深浅分档的内置样式（阴影深浅 / 边框强度 / 代码视图底色）改变体前缀写法；补「切深浅后变体生效 + 重绘」回归测试
- [ ] **2.4 code_view 主题化**：One Dark 硬编码色板（gui/ui/codeview.mbt）抽成按 `Theme` 派生的代码配色（深浅基底各一套：背景/前景/关键字/字符串/注释映射 theme token 或派生），默认跟 `theme_current()`；保留显式 `code_theme` 参数给刻意场景
- [ ] **1.2 原生子件登记流程成文**：gui/win/surface.mbt 头注写死登记清单——①三平台桩各实现挂载/移除/矩形同步 ②能力缺失平台的兜底行为（`None`）③探针 + 真机用例；第一个按流程演练的候选是 gui-media 视频直出（另批）
- [ ] **2.5 主题定制示例恢复**：按落位判据建 `examples/theme-playground/` 独立模块注册 moon.work，四个最小页——`theme_from_accent` 换主色 / `theme_apply` 全量覆盖 / `follow_system_theme` 接线 / `class` 单组件覆盖；同批补 `测试文档/测试用例.md` 对应用例
