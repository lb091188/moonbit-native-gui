# 文档索引

native-gui 是什么见[首页](/zh/)。按目标找文档：

## 文档分流

| 文档 | 内容 |
|---|---|
| [dev-experience.md](dev-experience.md) | 应用开发者体验：从零到第一个窗口——装工具链、建工程（`moon new` 模板的两处调整）、运行与常见卡点 |
| [tutorial.md](tutorial.md) | 五分钟上手：装工具链、建工程、做出第一扇带点击计数的窗口 |
| [components.md](components.md) | 组件速查（`@ui`）：各控件构造器的入口签名与用途，按家族分组 |
| [declarative.md](declarative.md) | 声明式层与响应式：节点树与 `mount_window`、`Store` / `Signal`、`for_list` / `when`、原位替换 |
| [layout.md](layout.md) | 布局：Flexbox 布局口径与 `@style` 的 `Style` 字段集、`class` 通道 |
| [build.md](build.md) | 构建与运行：从零装依赖（三平台清单 + 环境自检）、构建命令与产物落点、预构建二进制现状、常见失败处置；面向库开发的机制细节在后半段 |
| [packages.md](packages.md) | 包结构：17 个包别名与两个独立模块的内容一览 |
| [system-capabilities.md](system-capabilities.md) | 系统能力总览（`@sys`）：音量、应用查找、色温、壁纸、显示器、窗口管理、剪贴板监听、开机自启、系统信息、打印机、最近文件、浏览器历史等，统一 `Result` 语义；含子进程与 D-Bus 调用层两块共享基建 |
| [webview.md](webview.md) | 内嵌 WebView：`gui-webview` 模块的使用与平台说明 |
| [roadmap.md](roadmap.md) | 对外路线图：功能点、功能描述、计划版本、开发与测试状态；附平台兼容面、承诺与版本、明确不做 |
| [experience.md](experience.md) | 体验文档：真体验——预构建包直接跑、克隆仓库跑示例；写应用与改库分别引导到应用开发者体验与构建与运行 |
| [THIRD-PARTY-NOTICES.md](../THIRD-PARTY-NOTICES.md) | 第三方授权与来源：随源码入库的资产、我们自编或重打包挂在 Release 上的二进制、以及随之而来的分发义务 |

对内的工程记录——平台适配经验、Linux 托盘设计、前端化设计、GPU 架构决策——在仓库的 [`proposals/`](https://github.com/lb091188/moonbit-native-gui/tree/master/proposals) 目录，不在本站发布。

项目总览与快速开始入口见仓库根 [README_ZH.md](https://github.com/lb091188/moonbit-native-gui/blob/master/README_ZH.md)。
