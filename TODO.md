# TODO — 当前进行中的工作

> 只记「已实现、待复验 / 待收尾」的现行事项；规划与未来批次见 [docs/zh/roadmap.md](docs/zh/roadmap.md)「已规划」，实测坑与口径见 [experience/adaptation.md](experience/adaptation.md)。完成一项删一项，并同步路线图状态。


## 模板预编译（2026-11-01 启动，方案见 [proposals/native-template.md](proposals/native-template.md)；总顺序：模板 → VS Code 插件 → 拆包）

- Phase 0 探针已完成（2026-11-01：单次热替换 10.4 ms、泄漏 0、订阅跨代恒定，见 `experiment/ir_probe` 与方案回写）
- 编译器 `build` 子命令已完成（2026-11-02：`tools/mngkit` 内核 + `tools/mng_cli`，golden 6/6、source map 错误回映射端到端验通）
- [ ] **`dev` 子命令**：watch + 改动分类（表达式集合 ⊆ 注册表 → 推 IR 补丁；否则回退）+ 单实例通道推 token/类；回退时 `moon build` → 杀旧 → 带参重启
- [ ] **VS Code 插件 1 档**：`.mng` 语言注册 + MoonBit 表达式着色 injection + snippets；落地即把模板文件切裸 `.mng`
- [ ] **拆包**（[proposals/module-split.md](proposals/module-split.md)）：sys → win → dbus → shell 顺序，等工具二进制独立发布动机集中做

## 发布与验收（2026-10-31，基于固定「Binaries」Release 最新包）

- [ ] **os-macos 重截**：i18n 修复（4dc3e96b）CI 新包上，mac 切英文后确认侧栏分组标题为 Components / System 再截 showcase，贴边裁净、无背后窗口残影与指针，覆盖 `docs/public/images/os-macos.png`
- [ ] **Windows 真机复验**（browser 示例两处修复，f840edfa）：①冷启动后首页点「JS 调原生绑定」不再报 demoBinding is not defined；②本地片段页「触发下载请求」弹系统保存框、落盘可打开（blob 换 yuedemo://local/ngui.txt）
