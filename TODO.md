# TODO — 当前进行中的工作

> 只记「已实现、待复验 / 待收尾」的现行事项；规划与未来批次见 [docs/zh/roadmap.md](docs/zh/roadmap.md)「已规划」，实测坑与口径见 [experience/adaptation.md](experience/adaptation.md)。完成一项删一项，并同步路线图状态。


## 模板预编译（2026-11-01 启动，方案见 [proposals/native-template.md](proposals/native-template.md)；总顺序：模板 → VS Code 插件 → 拆包）

- Phase 0 探针已完成（2026-11-01：单次热替换 10.4 ms、泄漏 0、订阅跨代恒定，见 `experiment/ir_probe` 与方案回写）
- 编译器 `build` 子命令已完成（2026-11-02：`tools/native-gui-tools/mngkit` 内核 + `tools/native-gui-tools/mng_cli`，golden 9/9、source map 错误回映射端到端验通；`ir`/`new` 子命令就位）
- [ ] **HOT 补丁真机复验**：dev 循环（watch→HOT 推送→showcase「模板 Dev」页原位重建）已实现，端到端 GUI 验证由用户执行——步骤：①`moon run tools/native-gui-tools/mng_cli -- dev --watch examples/showcase/dev_demo.mng --out-dir examples/showcase/pages --build-cmd "moon build ./examples/showcase" --run-cmd "./target/native/debug/build/NoahLiu/native-gui-examples-showcase/cmd/main/main.exe"`（可执行路径按平台取 `moon build` 产物）②应用进「模板 Dev」页 ③改模板静态结构保存 → 亚秒可见（HOT）④改 `{{ qty }}` 为 `{{ qty + 1 }}` 保存 → COLD 重启（注册表键在 dev 页手写、对齐 `moon run tools/native-gui-tools/mng_cli -- ir examples/showcase/dev_demo.mng` 输出）
- `dev` 子命令已完成（2026-11-02：watch 内容对比 + 契约分类 HOT/COLD + 回退编排 build→杀旧→带参重启，无头自测验通；HOT 的进程内补丁推送待应用侧 dev 监听落地，本版打标不打断；配套 gui/sys 进程原语补 pr_spawn/pr_alive/pr_kill/pr_sleep_ms，僵尸探活收尸已钉测试）
- 编辑器支持已完成（2026-11-02：`mng_cli lsp` + `tools/vscode-mng` 静态贡献包（`.mng` 语言注册 / TextMate 着色 / snippets / 手写零依赖 LSP 客户端，握手 `mng-schema 1`，对不上降级为空）；待真机：VS Code 里装 VSIX 后按 `tools/vscode-mng/README.md` 清单一走——着色、snippets、补全四档、Problems 诊断、hover、跳转）
- 组件带参已完成（2026-11-02：script 段「只有签名无函数体」的 fn 头即 props（必填位置参、可选 `名? : 类型 = 默认值`，探针结论见 `experience/adaptation.md`）；跨包组件路径从 `let` 右值取、参数顺序从源码签名解析（`mngkit.Sigs` 注入文件端口），同包组件按标签名零声明；`// @mng` 降为不规则落点逃生口；未用 prop 出 `let _ =` 垫片、纯组件绑定的 let 不进生成体，保住零警告门禁；mngkit 测试 14/14）
- 样式章已完成（2026-11-02：`<style>` 类选择器摊平成 `define_class`、`class="a b"` → `class_of`、`var(--令牌)`（20 枚主题色 + 尺度令牌）、`#rrggbb`、枚举关键字、`.名:dark` 深浅两档按 `@win.sys_color_scheme()` 选；模板属性里的样式字面量编译报错；IR v1 带 class 转 COLD；mngkit 测试 18/18；真机视觉待用户按清单验）
- 撞名检测与注册表键控已完成（2026-11-02：build/dev 报同包 stem 撞名并点名文件；dev 注册表与 holder 按 IR 的 `page` 键控，多页并存不串表，showcase dev 页与 wbtest 同步）
- 工具与 GUI 解耦已完成（2026-11-02：`mng_cli` 不再依赖 `gui/sys`——`gui/sys` 在 Linux 上链 GTK 剪贴板符号，命令行工具不能带上它；改为 tools 内自给 `proc`（进程原语）与 `inst`（单实例客户端，帧格式与 shell 通道一致），二进制只链 libc/libgcc；proc/inst 无头测试 6/6）
- 工具链收口已完成（2026-11-02：`mng_cli lsp` stdio JSON-RPC（initialize / didOpen·didChange / completion / hover / definition / shutdown，诊断走 compile 错误坐标）；`--version` 报 `mng-cli 0.1.0` + `mng-schema 1` 供插件握手；native-gui-tools 的 moon.mod 描述与发布配置就位；LSP 无头回归 1 条）
- [ ] **拆包**（[proposals/module-split.md](proposals/module-split.md)）：sys → win → dbus → shell 顺序，等工具二进制独立发布动机集中做

## 发布与验收（2026-10-31，基于固定「Binaries」Release 最新包）

- [ ] **os-macos 重截**：i18n 修复（4dc3e96b）CI 新包上，mac 切英文后确认侧栏分组标题为 Components / System 再截 showcase，贴边裁净、无背后窗口残影与指针，覆盖 `docs/public/images/os-macos.png`
- [ ] **Windows 真机复验**（browser 示例两处修复，f840edfa）：①冷启动后首页点「JS 调原生绑定」不再报 demoBinding is not defined；②本地片段页「触发下载请求」弹系统保存框、落盘可打开（blob 换 yuedemo://local/ngui.txt）
