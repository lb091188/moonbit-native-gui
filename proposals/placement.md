# 落位判据

新东西放进仓库哪里，按下表第一判据落位；表外拿不准的，先想清楚它是什么再动手，默认不建新目录。

| 位置 | 收 | 不收 |
|---|---|---|
| `gui/` | 库模块 NoahLiu/native-gui 本体，唯一发布单元之一 | 示例、探针 |
| `examples/<name>/` | 示例；每个示例一个独立模块 `NoahLiu/native-gui-examples-<name>`，注册进 `moon.work`，依赖只写自己的 `moon.mod` | 往既有示例模块里塞第二个示例 |
| `experiment/` | 探针与微基准模块 | 要长期维护的功能代码 |
| `modules/` | 子模块：yoga-mbt / mdparse / gui-media / gui-webview / ffmpeg-mbt | 示例 |
| `proposals/` | 对内设计/方案/实测经验，纯中文，扁平一层 | 对外使用文档 |
| `docs/` | 对外文档站（VitePress，中英双语），只发对外使用文档与路线图 | 对内方案与实测经验 |
| `测试文档/` `测试记录/` | 用例文档与记录台（单文件网页，编号一一对应） | |
| `.agents/skills/` | 领域指导：FFI、界面设计、MoonBit 语言与工具链 | |

**依赖隔离靠模块，不靠包**:`moon.mod` 的 import 决定整个模块的依赖闭包，`moon.pkg` 只能从已解析依赖里挑包。所以「某个示例不拖累其它示例」必须每示例一个模块。
