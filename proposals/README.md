# 对内方案与经验记录

本目录收**对内**的工程设计、方案与实测经验记录,不发布到文档站(`moonbit-native-gui.pages.dev`)。对外使用文档(教程、组件、声明式、布局、构建、系统能力、路线图等)在 [`docs/`](../docs/)。

本目录全部为中文文档,不设语言子目录,文档直接放在这一层。

| 文档 | 内容 |
|---|---|
| [adaptation.md](adaptation.md) | 平台适配经验:各平台实测坑、根因与验证结论 |
| [tray.md](tray.md) | Linux 托盘:SNI 协议栈设计、架构、后端降级与桌面兼容性 |
| [design.md](design.md) | 前端化设计口径:样式表形态、组件命名映射、响应式补强、视图层 |
| [module-structure.md](module-structure.md) | 模块拆分判据、仓库布局、主模块三层子包与各模块边界 |
| [gpu-architecture.md](gpu-architecture.md) | GPU 合成与 3D 路径架构决策 |
| [i18n-and-iconfont.md](i18n-and-iconfont.md) | i18n 与 iconfont 两条线的方案总览 |
| [i18n-toml-design.md](i18n-toml-design.md) | i18n TOML 词表设计 |
| [iconfont-conversion.md](iconfont-conversion.md) | iconfont 图标转换流程 |
| [iconfont-moonbit-tool.md](iconfont-moonbit-tool.md) | MoonBit 侧图标工具设计 |
| [showcase-lazy-loading-and-router.md](showcase-lazy-loading-and-router.md) | showcase 懒加载与单窗口路由 |
| [style-css-expansion.md](style-css-expansion.md) | 样式层 CSS 属性扩展清单 |

第三方授权与来源登记见仓库根 [THIRD-PARTY-NOTICES.md](../THIRD-PARTY-NOTICES.md)。
