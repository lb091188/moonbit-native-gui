# TODO — 当前进行中的工作

> 只记「已实现、待复验 / 待收尾」的现行事项；规划与未来批次见 [docs/zh/roadmap.md](docs/zh/roadmap.md)「已规划」，实测坑与口径见 [proposals/adaptation.md](proposals/adaptation.md)。完成一项删一项，并同步路线图状态。

## 发布与验收（2026-10-31，基于固定「Binaries」Release 最新包）

- [ ] **mac 真机验收**：解压 bin-macos-arm64.zip → `xattr -dr com.apple.quarantine <目录>` → ①双击 Showcase.app 直跑无终端、Dock 显示「Showcase」；②双击 Audio.app 直播随包演示曲（Resources 资源解析）；③showcase 系统集成页发通知（bundle 化后预期可用）。通过后把体验文档通知条目的「真机复验中」措辞定稿（docs/{,zh/}experience.md）
- [ ] **Windows 真机复验**（browser 示例两处修复，f840edfa）：①冷启动后首页点「JS 调原生绑定」不再报 demoBinding is not defined；②本地片段页「触发下载请求」弹系统保存框、落盘可打开（blob 换 yuedemo://local/ngui.txt）
- [ ] **README 图集更新**（待真机截图，8 张静态）：5 应用首页 `app-hello/app-showcase/app-browser/app-audio/app-video.png` + 3 系统图 `os-linux/os-windows/os-macos.png`（建议都截 showcase，窗口尺寸一致、默认浅色主题）。到位后：换 README 中英图集引用、删两张动图引用与文件（showcase-anim-*.webp）、清 11 张无引用死图（showcase-browser/canvas/feedback/icons/native/nav、sysmonitor×3、sys、widgets）、docs 教程页 5 张旧页图（showcase-basic/form/data/code/system）同批刷新
