# TODO — 当前进行中的工作

> 只记「已实现、待复验 / 待收尾」的现行事项；规划与未来批次见 [docs/zh/roadmap.md](docs/zh/roadmap.md)「已规划」，实测坑与口径见 [proposals/adaptation.md](proposals/adaptation.md)。完成一项删一项，并同步路线图状态。


## 发布与验收（2026-10-31，基于固定「Binaries」Release 最新包）

- [ ] **os-macos 重截**：i18n 修复（4dc3e96b）CI 新包上，mac 切英文后确认侧栏分组标题为 Components / System 再截 showcase，贴边裁净、无背后窗口残影与指针，覆盖 `docs/public/images/os-macos.png`
- [ ] **Windows 真机复验**（browser 示例两处修复，f840edfa）：①冷启动后首页点「JS 调原生绑定」不再报 demoBinding is not defined；②本地片段页「触发下载请求」弹系统保存框、落盘可打开（blob 换 yuedemo://local/ngui.txt）
