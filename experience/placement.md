# 落位判据

新东西放进仓库哪里，按下表第一判据落位；表外拿不准的，先想清楚它是什么再动手，默认不建新目录。

| 位置 | 收 | 不收 |
|---|---|---|
| `gui/` | 库模块 NoahLiu/native-gui 本体，唯一发布单元之一 | 示例、探针 |
| `examples/<name>/` | 示例；每个示例一个独立模块 `NoahLiu/native-gui-examples-<name>`，注册进 `moon.work`，依赖只写自己的 `moon.mod` | 往既有示例模块里塞第二个示例 |
| `experiment/` | 探针与微基准模块 | 要长期维护的功能代码 |
| `modules/` | 子模块：yoga-mbt / mdparse / gui-media / gui-webview / ffmpeg-mbt | 示例 |
| `tools/` | DX 工具总目录：`tools/native-gui-tools/` 是 moon 模块与 mooncakes 发布单元——含 mngkit / mng_cli / icon* / i18n*，注册进 `moon.work`；非 moon 工具同层放，如编辑器插件 `tools/vscode-mng/`——纯 TS，不进 `moon.work` | 库本体、示例、探针 |
| `proposals/` | 对内方案/计划——要做或在做的提案，纯中文，扁平一层 | 对外使用文档；已收口的定案——迁 `experience/` |
| `experience/` | 对内经验与定案：实测坑与结论归 adaptation——按系统拆子目录：`adaptation/` 下 index 导航 + common / mac / windows / linux / linux-distros；已收口设计定案归 design、品牌定案归 brand、仓库判据归 placement；纯中文。adaptation 用子目录，其余扁平一层 | 待做的方案计划——进 `proposals/`；对外使用文档 |
| `docs/` | 对外文档站——VitePress 中英双语，只发对外使用文档与路线图 | 对内方案、计划与实测经验 |
| `assets/brand/` | 品牌源资产：应用图标 master SVG、单色变体、资产许可——对外发布单元，定案见 brand.md | 生成物——PNG/icns/ico 各回消费点：示例进 `examples/<name>/assets/`、文档站进 `docs/public/`；示例运行时资产 |
| `测试文档/` | 用例文档与记录台——记录台运行时解析用例 md，编号一一对应，经本地 HTTP 服务打开 | |
| `.agents/skills/` | 领域指导：FFI、界面设计、MoonBit 语言与工具链 | |

**依赖隔离靠模块，不靠包**:`moon.mod` 的 import 决定整个模块的依赖闭包，`moon.pkg` 只能从已解析依赖里挑包。所以「某个示例不拖累其它示例」必须每示例一个模块。
