# AI 协作规则

## 行为要求

- **规划后执行**——接到需求先检查是否完整，不完整先列出缺项向用户补全；动手前先出规划。
- **规划有检查**——规划完成后先检查有无遗漏、是否与既有约束冲突，检查通过再执行。
- **注释与文档只说内容、保持简单**——只写「是什么/怎么用/怎么做」；原理与根因写进专门文档(`proposals/adaptation.md` 等)。
- **不做本地冒烟测试，真机 GUI 测试由用户执行**——助手负责代码与 `moon check`/`moon test`/`moon build` 零错误零警告；视觉与交互给操作步骤清单交用户，不远程驱动，不在反馈前下结论。
- **与用户交流全部使用中文**——代码、命令、路径、专有名词除外。
- **每完成一个功能或修复即提交并推送**——一个功能一次提交，提交信息只写「【标签】做了什么」，原理与原因一概不写。
- **TODO 收口即删，交付面同批写进路线图**——完成即从 `TODO.md` 删除；状态进 `docs/zh/roadmap.md`(✅已验 / 🚧已合入待真机 / ❌未做 / ⏳待定)，两者不得互相矛盾。
- **新内容按「目录」落位**——示例一律 `examples/<name>/` 独立模块并注册进 `moon.work`，依赖只写自己的 `moon.mod`；不往既有示例模块里塞第二个示例，不往 `modules/` 里放示例。
- **改领域配置先读对应指导文档**——`moon.pkg` / `moon.mod` / 链接与依赖 → [docs/zh/build.md](docs/zh/build.md)；FFI / C 绑定 → `.agents/skills/moonbit-c-binding/`；平台适配 → `proposals/adaptation.md`(实测坑与适配经验回写此文件，与代码同批提交)。

## 常用命令与门禁

```sh
cd gui && moon check          # 门禁:零错误零警告
cd gui && moon test ui render text theme icons sys input win dbus chart mdview style base shell widget router
moon run examples/hello       # 最小窗口(另有 hello-themed / showcase 等)
```

裸 `moon test` 会连带 examples / experiment / 媒体模块(含平台适配缺口，非库缺陷)，不作库门禁。

## 目录(放东西的第一判据，文档与资料用到再读)

- 库模块 NoahLiu/native-gui，唯一发布单元之一:`gui/`
- 每个示例一个独立模块 NoahLiu/native-gui-examples-<name>:`examples/<name>/`
- 探针与微基准模块:`experiment/`
- 子模块(yoga-mbt / mdparse / gui-media / gui-webview / ffmpeg-mbt):`modules/`
- workspace 成员清单，上面这些模块全部注册在此:`moon.work`
- 对内设计/方案/实测经验(纯中文，扁平一层；文档站只发对外使用文档与路线图):`proposals/`
- 对外文档站(VitePress，中英双语):`docs/`、`docs/zh/`
- 测试用例文档与记录台(单文件网页；用例编号 `HL/SC/BR/AU/VD` 与记录台一一对应):`测试文档/测试用例.md`、`测试记录/index.html`
- FFI / C 绑定细节:`.agents/skills/moonbit-c-binding/`、`.agents/skills/make-moonbit-c-bindings/`
- DBus / SNI 实现与真总线读数:`gui/dbus/`、`proposals/adaptation.md`(搜 D-Bus / SNI)
- 平台适配经验:`proposals/adaptation.md`
- 写或改界面之前(间距刻度、字阶、圆角层级、token 都在里面):`.agents/skills/native-gui-design/`
- MoonBit 语言与工具链:`.agents/skills/moonbit-agent-guide/`
- 模块拆分判据:`proposals/module-structure.md`
- 使用文档索引:`docs/README.md`
- 路线图:`docs/zh/roadmap.md`
- 待办:`TODO.md`

**依赖隔离靠模块，不靠包**:`moon.mod` 的 import 决定整个模块的依赖闭包，`moon.pkg` 只能从已解析依赖里挑包。所以「某个示例不拖累其它示例」必须每示例一个模块。
