# AI 协作规则

## 行为要求

- **规划后执行**——接到需求先检查是否完整，不完整先列出缺项向用户补全；动手前先出规划。
- **规划有检查**——规划完成后先检查有无遗漏、是否与既有约束冲突，检查通过再执行。
- **注释与文档只说内容、保持简单**——只写「是什么/怎么用/怎么做」；原理与根因写进专门文档(`proposals/adaptation.md` 等)。
- **对外文档默认中文先行**——改动一律先写 `docs/zh/` 对应文档；推送前把改动意译进 `docs/` 同路径英文文档。
- **不做本地冒烟测试，真机 GUI 测试由用户执行**——助手负责代码与 `moon check`/`moon test`/`moon build` 零错误零警告；视觉与交互给操作步骤清单交用户，不远程驱动，不在反馈前下结论。
- **与用户交流全部使用中文**——代码、命令、路径、专有名词除外。
- **每完成一个功能或修复即提交并推送**——一个功能一次提交，提交信息只写「【标签】做了什么」，原理与原因一概不写。
- **功能按「已规划 → 待办 → 已实现」流转**——确定做的功能先写进 `docs/zh/roadmap.md`「已规划」；要动手时先放进 `TODO.md`；完成后从 `TODO.md` 删除，路线图条目从「已规划」移进「已实现」并按平台标状态(✅已验 / 🚧已合入待真机 / ❌未做 / ⏳待定)，同批补 `测试文档/测试用例.md`(记录台加载它现算清单，不用另改记录台)；roadmap 与 TODO 不得互相矛盾。
- **新内容按落位判据落位**——先读 `proposals/placement.md`；示例一律 `examples/<name>/` 独立模块并注册进 `moon.work`。
- **改领域配置先读对应指导文档**——`moon.pkg` / `moon.mod` / 链接与依赖 → [docs/zh/build.md](docs/zh/build.md)；FFI / C 绑定 → `.agents/skills/moonbit-c-binding/`；平台适配 → `proposals/adaptation.md`(实测坑与适配经验回写此文件，与代码同批提交)。

## 常用命令与门禁

```sh
cd gui && moon check          # 门禁:零错误零警告
cd gui && moon test ui render text theme icons sys input win dbus chart mdview style base shell widget router
moon run examples/hello       # 最小窗口(另有 showcase 等)
```

裸 `moon test` 会连带 examples / experiment / 媒体模块(含平台适配缺口，非库缺陷)，不作库门禁。

## 目录

- 放东西的第一判据:`proposals/placement.md`
- 库模块 NoahLiu/native-gui，唯一发布单元之一:`gui/`
- 每个示例一个独立模块 NoahLiu/native-gui-examples-<name>:`examples/<name>/`
- 探针与微基准模块:`experiment/`
- 子模块(yoga-mbt / mdparse / gui-media / gui-webview / ffmpeg-mbt):`modules/`
- workspace 成员清单，上面这些模块全部注册在此:`moon.work`
- 对内设计/方案/实测经验(纯中文，扁平一层；文档站只发对外使用文档与路线图):`proposals/`
- 对外文档站(VitePress，中英双语):`docs/`、`docs/zh/`
- 测试用例文档与记录台(记录台运行时解析用例文档现算清单；用例编号 `HL/SC/BR/AU/VD` 一一对应；经本地 HTTP 服务打开):`测试文档/`(`测试用例.md` + `index.html`)
- FFI / C 绑定细节:`.agents/skills/moonbit-c-binding/`、`.agents/skills/make-moonbit-c-bindings/`
- DBus / SNI 实现与真总线读数:`gui/dbus/`、`proposals/adaptation.md`(搜 D-Bus / SNI)
- 平台适配经验:`proposals/adaptation.md`
- 写或改界面之前(间距刻度、字阶、圆角层级、token 都在里面):`.agents/skills/native-gui-design/`
- MoonBit 语言与工具链:`.agents/skills/moonbit-agent-guide/`
- 模块拆分判据:`proposals/module-structure.md`
- 使用文档索引:`docs/README.md`
- 路线图:`docs/zh/roadmap.md`
- 待办:`TODO.md`
