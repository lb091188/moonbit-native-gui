# AGENTS.md — native-gui AI 协作规则

MoonBit 跨平台桌面 GUI 框架(包 `NoahLiu/native-gui`)，一套代码直出 Windows / Linux / macOS 原生窗口。主链路 **Ubuntu 24.04 + X11 + XFCE**。
定位与上手见 [README_ZH.md](README_ZH.md)；构建、链接、新增示例模块的完整流程见 [docs/zh/build.md](docs/zh/build.md)。本文件只放**每轮都必须遵守的约束**，其余按需查(见文末)。

## 硬性规则

> 编号被 `proposals/`、`.github/workflows/`、`README_ZH.md` 等按号引用（如「规则 6」）。只可改措辞，**不可重排、不可删号复用**；新增规则一律追加在末尾。

1. **链接参数由 prebuild 全权托管**——任何 `moon.pkg` 都不写链接参数，勿手改(`gui/scripts/prebuild.py` 是唯一出口)。
2. **库包不得放 `link` 段**——moon 会生成无 main 的 `.exe` 导致构建失败；链接配置统一走 prebuild。
3. **FFI 改动必须对照 `.agents/skills/moonbit-c-binding/`**——平台 C 按「单一 stub.c 多分支」组织；不做 C→MoonBit 回调。
4. **extern 蹦床与 C 函数指针原型逐位对齐，含参数个数**——ABI 坑见 `proposals/adaptation.md`。
5. **协议级互操作(DBus/DBusMenu/SNI)必须上真实总线、真实面板验证**——单测自洽 ≠ 互操作通过。
6. **真机 GUI 测试由用户执行**——助手负责代码修复与 `moon check`/`moon test`/`moon build` 零错误零警告；视觉与交互给操作步骤清单交用户执行，不远程驱动，不在反馈前下结论。
7. **封装/适配经验必须回写 `proposals/adaptation.md`**——与代码改动同批提交，只留在提交说明或会话记忆里视为未完成(写法见规则 14)。
8. **与用户交流全部使用中文**——代码、命令、路径、专有名词除外。
9. **每完成一个功能或修复即提交并推送**——一个功能一次提交，提交信息只写「【标签】做了什么」(如【修复】输入框焦点丢失)，原理与原因一概不写。
10. **代码注释与使用文档只说内容**——只写「是什么/怎么用/怎么做」；原理、根因写进 `proposals/adaptation.md` 等专门文档。
11. **MoonBit 侧跨平台分派一律运行时探测 + 模式匹配**——禁用 `#cfg(platform=)` 等编译指令，三平台同构优先。
12. **TODO 收口即删，交付面同批写进路线图**——完成即从 `TODO.md` 删除，不留 `[x]` 堆积；状态进 `docs/zh/roadmap.md`(✅已验 / 🚧已合入待真机 / ❌未做 / ⏳待定)；roadmap 与 TODO 不得互相矛盾。
13. **新内容按「目录地图」落位**——示例一律 `examples/<name>/` 独立模块并注册进 `moon.work`，依赖只写自己的 `moon.mod`；不往既有示例模块里塞第二个示例，不往 `modules/` 里放示例。
14. **经验条目只收「代码读不出的四类」**——判据：删掉这条，未来是否会有人因它做出错误决定？**收**：平台反直觉行为、实测读数与容差、被否掉的路及其原因、环境与版本约束。**不收**：能由 diff 复述的实现步骤、「是什么/怎么用」、过程叙事。一条一事，一句根因 + 一句判据。

## 常用命令与门禁

```sh
cd gui && moon check          # 门禁:零错误零警告
cd gui && moon test ui render text theme icons sys input win dbus chart mdview style base shell widget router
moon run examples/hello       # 最小窗口(另有 hello-themed / showcase 等)
```

裸 `moon test` 会连带 examples / experiment / 媒体模块(含平台适配缺口，非库缺陷)，不作库门禁。其余命令、产物路径与「改了 C 桩不重链」的处理见 [docs/zh/build.md](docs/zh/build.md)。

## 目录地图(放东西的第一判据)

```
gui/                    库模块 NoahLiu/native-gui——唯一发布单元之一
examples/<name>/        每个示例 = 一个独立模块 NoahLiu/native-gui-examples-<name>
experiment/             探针与微基准模块
modules/                yoga-mbt / mdparse / gui-media / gui-webview / ffmpeg-mbt
moon.work               workspace 成员清单:上面这些模块全部注册在此
proposals/              对内设计/方案/实测经验(纯中文，扁平一层)
docs/                   对外文档站(VitePress，中英 docs/ 与 docs/zh/)
测试文档/ 测试记录/      用例文档与记录台(单文件网页，编号一一对应)
```

**依赖隔离靠模块，不靠包**:`moon.mod` 的 import 决定整个模块的依赖闭包，`moon.pkg` 只能从已解析依赖里挑包。所以「某个示例不拖累其它示例」必须每示例一个模块。

## 按需查阅(不常驻，用到再读)

- **FFI / C 绑定细节**:`.agents/skills/moonbit-c-binding/`、`.agents/skills/make-moonbit-c-bindings/`
- **DBus / SNI 实现与真总线读数**:`proposals/adaptation.md`(搜 D-Bus / SNI)、`gui/dbus/`
- **写或改界面之前**:`.agents/skills/native-gui-design/`(间距刻度、字阶、圆角层级、token 都在里面)
- **平台适配经验**:`proposals/adaptation.md`(对内方案目录 `proposals/`；文档站只发对外使用文档与路线图)
- **MoonBit 语言与工具链**:`.agents/skills/moonbit-agent-guide/`
- **使用文档索引**:`docs/README.md` · **路线图**:`docs/zh/roadmap.md` · **待办**:`TODO.md`
- **测试用例**:`测试文档/测试用例.md`(编号 `HL/SC/BR/AU/VD`，与 `测试记录/index.html` 一一对应)
- **模块拆分判据**:`proposals/module-structure.md`
