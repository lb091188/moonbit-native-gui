# AI 协作规则

## 行为要求

- **规划后执行**——接到需求先检查是否完整，不完整先列出缺项向用户补全；动手前先出规划。
- **规划有检查**——规划完成后先检查有无遗漏、是否与既有约束冲突，检查通过再执行。
- **注释与文档只说内容、保持简单**——只写「是什么/怎么用/怎么做」；原理与根因写进专门文档 `experience/adaptation.md` 等。文档行内不用括号补注，术语解释、日期、平台、出处一律展开为缩进子要点。
- **读者非桌面专业**——TODO、roadmap 与各文档里的桌面/GUI 专业名词，首次出现时紧跟一条大白话解释子要点，让非桌面背景的开发者能读懂；文档整体保持言简意赅。
- **对外文档默认中文先行**——改动一律先写 `docs/zh/` 对应文档；推送前把改动意译进 `docs/` 同路径英文文档。
- **不做本地冒烟测试，真机 GUI 测试由用户执行**——助手负责代码与 `moon check`/`moon test`/`moon build` 零错误零警告；视觉与交互给操作步骤清单交用户，不远程驱动，不在反馈前下结论。
- **与用户交流全部使用中文**——代码、命令、路径、专有名词除外。
- **每完成一个功能或修复即提交并推送**——一个功能一次提交，提交信息只写「【标签】做了什么」，原理与原因一概不写。
- **功能按「已规划 → 待办 → 已实现」流转**——确定做的功能先写进 `docs/zh/reference/roadmap.md`「已规划」；要动手时先放进 `TODO.md`；完成后从 `TODO.md` 删除，路线图条目从「已规划」移进「已实现」并按平台标状态，同批补 `测试文档/测试用例.md`；roadmap 与 TODO 不得互相矛盾。
  - 平台状态标记：✅已验 / 🚧已合入待真机 / ❌未做 / ⏳待定。
  - 记录台加载 `测试文档/测试用例.md` 现算清单，不用另改记录台。
- **新内容按落位判据落位**——先读 `experience/placement.md`；示例一律 `examples/<name>/` 独立模块并注册进 `moon.work`。
- **改领域配置先读对应指导文档**——`moon.pkg` / `moon.mod` / 链接与依赖 → [docs/zh/build.md](docs/zh/build.md)；FFI / C 绑定 → `.agents/skills/moonbit-c-binding/`；平台适配 → `experience/adaptation.md`，实测坑与适配经验回写此文件，与代码同批提交。

## 常用命令与门禁

```sh
cd gui && moon check          # 门禁:零错误零警告
cd gui && moon test base shell widget ui render text theme icons sys input win dbus wayland chart mdview style router uitest mngdev inspector
cd tools/native-gui-tools && moon check && moon test mng mngkit proc inst   # mng 工具链检查 + 测试
cd tools/native-gui-tools && moon build mng --target native --release      # release 形态(符号缺库只在此档露头)
cd modules/gui-webview && moon test webview                   # webview 扩展模块(点名包,裸跑会连带全 workspace)
cd gui && moon build base shell widget ui render text theme icons sys input win chart mdview style router --target native
moon build examples/hello examples/audio examples/video --target native   # 示例链接(含媒体桩真链)
cd docs && npm run build && cd .. && node tools/check-docs-index.mjs      # 文档站构建 + 索引守卫
moon run examples/hello       # 最小窗口(另有 showcase 等)
```

编译面必跑 mac 原生桩语法门禁——照 ci.yml macOS 腿对五桩逐个 `clang -fsyntax-only`，见 ci.yml 的 `gate` 函数。门禁范围与 `.github/workflows/ci.yml` 三腿一致——本机视角是 macOS 腿 + Docs，xvfb 冒烟与 Windows 链接本地不做。

**运行/场景类改到对应面时本地加跑**：

- 编辑器场景：`moon build tools/native-gui-tools/mng --target native` 后在 `tools/vscode-mng` 跑 `npm run typecheck` + `npm test`。
- mng 应用侧场景，不在 CI、只本地：`bash scripts/mng_scenario.sh`，起真进程，跑完自动还原 `moon.work`。

裸 `moon test` 会连带 examples / experiment / 媒体模块，其中含平台适配缺口、非库缺陷，不作库门禁。

## 目录

- 放东西的第一判据:`experience/placement.md`
- 库模块 NoahLiu/native-gui，唯一发布单元之一:`gui/`
- 每个示例一个独立模块 NoahLiu/native-gui-examples-<name>:`examples/<name>/`
- 探针与微基准模块:`experiment/`
- 子模块——yoga-mbt / mdparse / gui-media / gui-webview / ffmpeg-mbt:`modules/`
- DX 工具总目录，moon 模块与非 moon 工具同层分放，非 moon 工具即编辑器插件:`tools/`
- workspace 成员清单，上面这些模块全部注册在此:`moon.work`
- 对内方案/计划——要做或在做的提案:`proposals/`
  - 纯中文，扁平一层。
  - 文档站只发对外使用文档与路线图。
- 对内经验与定案——实测坑、已收口设计定案、仓库判据:`experience/`
  - 纯中文。
- 对外文档站——VitePress，中英双语:`docs/`、`docs/zh/`
- 测试用例文档与记录台:`测试文档/`，内含 `测试用例.md` + `index.html`
  - 记录台运行时解析用例文档现算清单。
  - 用例编号 `HL/SC/BR/AU/VD` 一一对应。
  - 经本地 HTTP 服务打开。
- FFI / C 绑定细节:`.agents/skills/moonbit-c-binding/`、`.agents/skills/make-moonbit-c-bindings/`
- DBus / SNI 实现与真总线读数:`gui/dbus/`、`experience/adaptation.md`
  - 查总线读数在 `experience/adaptation.md` 搜 D-Bus / SNI。
- 平台适配经验:`experience/adaptation.md`
- 写或改界面之前:`.agents/skills/native-gui-design/`
  - 里面有间距刻度、字阶、圆角层级、token。
- 无障碍通道现状——已端到端、非占位:
  - 控件语义挂 `name/label/role/a11y_state/a11y_text`，见 `gui/widget/a11y.mbt`。
  - 语义从帧尾 TSV 快照接到 mac NSAccessibility / win UIA / linux AT-SPI 桥。
  - 焦点序是树序一等遍历，见 `gui/base/focus.mbt`;控件声明 `focus_id` 即入 Tab 链，无 tabIndex/focus_scope。
  - 新控件照 `gui/ui/form.mbt` 首批样板接线;覆盖面缺口与真机清单见 `proposals/text-selection-a11y.md`
- MoonBit 语言与工具链:`.agents/skills/moonbit-agent-guide/`
- 模块拆分方案:`proposals/module-split.md`
- 使用文档索引:`docs/README.md`
- 路线图:`docs/zh/reference/roadmap.md`
- 待办:`TODO.md`
