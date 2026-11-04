# 文档索引

native-gui 是什么见[首页](/zh/)。站内结构与顶部导航一致，按目标找文档：

## 指南（从零到应用）

| 文档 | 内容 |
|---|---|
| [五分钟上手](guide/tutorial.md) | 装工具链、建工程、做出第一扇带点击计数的窗口 |
| [先跑起来看看](guide/experience.md) | 真体验——预构建包直接跑、克隆仓库跑示例 |
| [应用开发者体验](guide/dev-experience.md) | 工程机制与新手卡点：模板结构、`moon add` 与 import 的两级、两处调整的原因、常见卡点表 |
| [构建与运行](guide/build.md) | 三平台依赖清单、构建命令与产物落点、预构建二进制现状、常见失败处置 |
| [布局样式](guide/layout.md) | Flexbox 布局口径与 `@style` 的 `Style` 字段集、`class` 通道 |
| [声明式与响应式](guide/declarative.md) | 节点树与 `mount_window`、`Store` / `Signal`、`for_list` / `when`、原位替换 |
| [画布](guide/canvas.md) | 挂自绘区域、`Painter` 常用画法、请求重绘、离屏导出 PNG |
| [自绘与键鼠](guide/custom-draw.md) | 自绘块接指针 / 悬停 / 焦点 / 滚轮，迷你画板骨架 |

## 场景速查

| 文档 | 内容 |
|---|---|
| [场景总览](cookbook/index.md) | 「我想做 X」检索表 + 公共 import 前提 |
| [布局场景](cookbook/layout.md) | 居中、三段式、分栏、滚动、折行、按钮右对齐 |
| [交互场景](cookbook/interaction.md) | 输入框、列表增删、弹窗、轻提示、定时、显隐、表单校验、多窗口 |
| [样式与主题场景](cookbook/theme.md) | 换主色、跟随系统深浅、hover / active / focus 样式槽 |
| [系统能力场景](cookbook/system.md) | 打开链接与定位文件、剪贴板、桌面通知 |

## 组件（@ui）

| 文档 | 内容 |
|---|---|
| [组件总览](components/index.md) | 约定、`mount_window`、家族分页一览 |
| 家族分页 | [布局与容器](components/containers.md) / [文本与基础](components/basics.md) / [表单](components/form.md) / [日期与时间](components/date.md) / [数据展示](components/display.md) / [表格与虚拟列表](components/table.md) / [导航](components/navigation.md) / [浮层与消息](components/overlay.md) / [拖放悬停与窗口事件](components/interaction.md) / [响应式控制](components/reactive.md) |

## 能力

| 文档 | 内容 |
|---|---|
| [系统能力总览](capability/sys.md) | 平台状态矩阵、子进程与 D-Bus 两块共享基建、能力分页入口 |
| [音量与媒体](capability/media.md) | 系统音量、MPRIS 媒体控制与监视、gui-media 音视频播放 |
| [应用与历史](capability/apps-history.md) | 应用查找、VS Code 历史、浏览器历史 / 下载 / 书签、Firefox 历史、最近文件 |
| [桌面与显示](capability/desktop.md) | 会话类型、夜间色温、壁纸、显示器配置、窗口管理 |
| [系统服务](capability/service.md) | macOS 权限、电源计划、系统信息、打印机、环境变量、剪贴板监听、开机自启 |
| [内嵌 WebView](capability/webview.md) | `gui-webview` 模块的使用与平台说明 |
| [图表](capability/chart.md) | `@chart` 二十种图型、交互版、PNG 导出 |
| [Markdown 视图](capability/mdview.md) | `@mdview` 一个入口渲染 Markdown，选中复制 |
| [页面路由](capability/router.md) | `@router` 路由树、link 绑定、加载与淘汰策略 |
| [多语言](capability/i18n.md) | `@i18n` TOML 词表、插值复数、语言切换订阅 |

## 参考

| 文档 | 内容 |
|---|---|
| [包结构](reference/packages.md) | 17 个包别名与两个独立模块的内容一览 |
| [API 参考](reference/api.md) | mooncakes.io 自动生成的逐签名 API 参考（十七包直达链接） |
| [对外路线图](reference/roadmap.md) | 功能点、计划版本、开发与测试状态、平台兼容面、明确不做 |
| [第三方授权](../THIRD-PARTY-NOTICES.md) | 随源码入库的资产、Release 上的自编二进制、随之而来的分发义务 |

对内的工程记录——平台适配经验、Linux 托盘设计、前端化设计、GPU 架构决策——在仓库的 [`proposals/`](https://github.com/lb091188/moonbit-native-gui/tree/master/proposals) 目录，不在本站发布。

项目总览与快速开始入口见仓库根 [README_ZH.md](https://github.com/lb091188/moonbit-native-gui/blob/master/README_ZH.md)。
