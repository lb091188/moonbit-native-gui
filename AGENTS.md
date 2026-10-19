# AGENTS.md — native-gui AI 协作规则

native-gui(`NoahLiu/native-gui`): MoonBit 的跨平台桌面 GUI 框架——一套代码直出 Windows / Linux / macOS 原生窗口，系统能力开箱即用，`moon add` 后零配置。详见 [README_ZH.md](README_ZH.md)。
当前主链路: **Ubuntu 24.04 + X11 + XFCE**。

## 硬性规则

1. **链接参数由 prebuild 全权托管**——任何 `moon.pkg` 都不写链接参数，勿手改。详见 `gui/scripts/prebuild.py`。
2. **库包不得放 `link` 段**——moon 会生成无 main 的 `.exe` 导致构建失败；链接配置统一走 prebuild。
3. **FFI 改动必须对照 `.agents/skills/moonbit-c-binding/` 规范**——平台 C 按「单一 stub.c 多分支」组织；不做 C→MoonBit 回调；链接参数一律由 prebuild 托管。
4. **extern 蹦床与 C 函数指针原型逐位对齐，含参数个数**——案例与 ABI 坑见 `proposals/adaptation.md`。
5. **协议级互操作(DBus/DBusMenu/SNI)必须上真实总线、真实面板验证**——单测自洽 ≠ 互操作通过。
6. **真机 GUI 测试由用户执行**——助手负责代码修复与 `moon check`/`moon test`/`moon build` 零错误零警告；视觉与交互验证给出操作步骤清单，由用户在真机执行并反馈，助手不得自行远程驱动，不得在反馈前下结论。
7. **封装/适配经验必须回写 `proposals/adaptation.md`**——环境 + 现象 + 根因 + 修复 + 验证方式，与代码改动同批提交；只留在提交说明或会话记忆里视为未完成。
8. **与用户交流全部使用中文**——代码、命令、路径、专有名词除外。
9. **每完成一个功能或修复即提交并推送**——提交信息只写「【标签】做了什么」(如【修复】输入框焦点丢失)，一个功能一次提交；原理、原因、解释一概不写，归专门文档。
10. **代码注释与使用文档只说内容**——只写「是什么/怎么用/怎么做」；原理、根因写进 `proposals/adaptation.md` 等专门文档，不在内容文档与注释里展开。
11. **MoonBit 侧跨平台分派一律运行时探测 + 模式匹配**——禁用 `#cfg(platform=)` 等编译指令，三平台同构优先。
12. **TODO 收口即删**——条目完成立即从 `TODO.md` 删除，不留 `[x]` 堆积；交付面同批写进 `docs/zh/roadmap.md` 对应小节（平台列 ✅=已验证 / 🚧=已合入待真机 / ❌=未做 / ⏳=待定），坑与根因归 `proposals/adaptation.md`。反向同理：roadmap 与 TODO 不允许互相矛盾。
13. **新内容按「目录地图」落位**——示例一律 `examples/<name>/` 独立模块并注册进 `moon.work`，依赖只写在自己的 `moon.mod`；不往既有示例模块里塞第二个示例，不往 `modules/` 里放示例。

## 常用命令

```sh
moon clean                    # 清理缓存
cd gui && moon check           # 库模块门禁:静态检查(要求零错误零警告)
cd gui && moon test ui render text theme icons sys input win dbus chart mdview style base shell widget   # 库测试(按包限定;web 已出模块,门禁在 modules/gui-webview)
moon run examples/hello         # 最小窗口
moon run examples/hello-themed  # 主题控件集
moon run examples/showcase      # 完整演示板
```

门禁口径: 库门禁在 `gui/` 下按包限定跑。裸 `moon test` 会连带 examples / experiment / 媒体模块，其中含平台适配缺口(非库缺陷)，不作库门禁使用。

## 目录地图(放东西的第一判据:找不到路先看这里)

```
gui/                    库模块 NoahLiu/native-gui(14 包)——唯一发布单元之一
examples/<name>/        每个示例 = 一个独立模块 NoahLiu/native-gui-examples-<name>
                        (hello / hello-themed / showcase / browser / sysmonitor /
                         audio / video / headless-audio；assets/ 是共享资产目录，非模块)
experiment/             探针与微基准模块 NoahLiu/native-gui-experiment
modules/yoga-mbt        布局引擎模块
modules/mdparse        通用 Markdown 解析模块(NoahLiu/mdparse，派生自 mizchi/markdown，只出 AST，不依赖 GUI)
modules/gui-media       媒体模块(ffmpeg + miniaudio 播放器组件)
modules/gui-webview     WebView 模块
modules/ffmpeg-mbt      ffmpeg 绑定模块
moon.work               workspace 成员清单:上面这些模块全部注册在此
proposals/              对内设计/方案/实测经验(纯中文，扁平一层，不分语言子目录)
docs/                   对外文档站(VitePress，中英 docs/ 与 docs/zh/)
```

**依赖隔离靠模块，不靠包**:`moon.mod` 的 import 决定整个模块的依赖闭包，`moon.pkg` 只能从模块已解析的依赖里挑包。所以「某个示例不拖累其它示例」必须做成*每示例一个模块*，把多个示例塞进同一份 `moon.mod` 会重新耦合。新增示例的做法:

1. 建目录 `examples/<name>/`(含 `main.mbt` + `moon.pkg`)，写一份**自己的** `moon.mod`:
   `name = "NoahLiu/native-gui-examples-<name>"`，import 只列该示例真用到的模块。
2. 把 `examples/<name>` 追加进 `moon.work` 的 `members`。
3. 需要在 CI 里构建/冒烟就点名追加，别改成一个 `moon build` 扫整个 workspace(失败看不出是谁坏的)。
4. 产物路径按模块名走:`_build/native/<mode>/build/NoahLiu/native-gui-examples-<name>/native-gui-examples-<name>.exe`
   (`scripts/make_app.sh`、`release-bin.yml` 依赖这个口径)。

## 文档地图

- 使用文档索引: `docs/README.md`
- 平台适配经验: `proposals/adaptation.md`(对内方案目录 `proposals/`,文档站只发对外使用文档与路线图)
- FFI 规范: `.agents/skills/moonbit-c-binding/`、`.agents/skills/make-moonbit-c-bindings/`
- MoonBit 语言与工具链: `.agents/skills/moonbit-agent-guide/`
- 路线图: `TODO.md`
- 模块拆分方案与判据: `proposals/module-structure.md`
- 快速开始/架构: `README_ZH.md`(对外英文文档在 `docs/`,仓库根不再留英文 README)
