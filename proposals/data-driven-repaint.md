# 数据驱动局部重绘：整窗广播收窄为按控件或子树标脏

> **状态**：已规划（2026-11-21），未动工。
> **起因**：TODO.md「数据驱动局部重绘」——Store / Signal 数据回调仍走 `host_repaint_all` 整窗广播；TODO 旧数 122 处已陈旧，当前实测 185 处。
> **决策**（本批定案方向）：
> - 主路线收窄标脏：数据回调把「所有在窗整窗置脏」改为「涉事控件矩形置脏」，复用现有脏区裁剪与控件剔除。
> - 不做组件内增量绘制：标脏收窄后，绘制端按脏区裁剪自动只画涉事矩形，图表改一个点只画图表矩形由现有管线直接达成。
> - mdview 不立项：滚动呈现已由条带快路径解决，内容变化即重建树、无常驻更新场景。
> - 前置读数：mac 腿已采齐，Windows 腿待用户补跑。

## 1. 现状核账

### 1.1 已有局部置脏的环节

| 环节 | 机制 | 证据 |
| --- | --- | --- |
| 指针悬停 / 捕获链 | `mark_state_chain` 并涉事控件矩形 | gui/widget/app.mbt |
| 按键目标链 | 消费后按链逐控件标矩形 | gui/widget/app.mbt |
| 焦点切换 | 前后两件各标矩形 | gui/widget/app.mbt |
| 滚动 | 视口局部置脏 + 整数位移条带快路径 | gui/ui/scroll.mbt、app.mbt |
| style 过渡与关键帧动画 | 每拍 `invalidate_id` 按控件标脏，收敛停表 | gui/style/transition.mbt、keyframes.mbt |
| 绘制端消费 | 单矩形裁剪 + 控件整棵剔除（纯光栅臂） | gui/render/raster.mbt `clip_bounds`、gui/widget/widget.mbt `widget_cull_skip` |

### 1.2 仍是整窗广播的环节

| 环节 | 规模 | 说明 |
| --- | --- | --- |
| Store / Signal 订阅回调 | 主体——`follow_store`、`bind_node` / `swap_node`、`when`、`watch_theme`、`text_dyn` | 订阅只为重绘，回调一律 `@widget.invalidate()` |
| chart | 21 处 | 数据改一点、悬停、图例切换全整窗 |
| gui-media | 24 处 | 播放器进度与状态 |
| 点击成交 Up | 兜底 | on_click 改的 Store 常影响悬停链外兄弟，刻意整窗一帧 |
| GIF 换帧、拖放、浮层开着 | 少量 | 现状整窗 |

- `@widget.invalidate()` 全库 185 处：gui/ui 99、gui-media 24、gui/chart 21、examples 27、其余 14。

## 2. 收益读数

`frame_cost_probe` 的 `paint_full` 与 `paint_clip` 差值就是收窄收益依据（mac 腿本批采集，2026-11-21，release，1400×900）：

| rows | paint_full | paint_clip | 差值倍数 | skip |
| --- | --- | --- | --- | --- |
| 15 | 3.55 ms/帧 | 0.35 ms/帧 | 10.1 | 260 |
| 60 | 5.2 ms/帧 | 0.35 ms/帧 | 14.9 | 1160 |
| 240 | 5.5 ms/帧 | 0.45 ms/帧 | 12.2 | 4760 |

- 裁剪框外的控件整棵跳过遍历，visit 从 1940 降到 180——收益来自「不跑 on_draw」，不是绘制本身变快。
- Linux cairo 腿量不到剔除收益，skip 恒 0 属预期；Windows 腿读数待补跑后补表。

## 3. 收窄路线分期

- 批 1 订阅回调带控件 id：`bind_node` / `when` / `text_dyn` / `relabel` / `watch_theme` / `follow_store` 的回调从 `@widget.invalidate()` 改按控件标脏。
  - 机制：复用 `invalidate_id`（跨窗按控件 id 标矩形，未命中回退整窗）——gui/widget/host.mbt 已有。
  - 难点：订阅发生在组件构造期，回调闭包要拿到控件实例 id；构造后 id 才定，需要「订阅先挂、id 后补」的槽位或回调时现查。
  - 收窄后同批处理回收：控件销毁时退订，防悬空 id 反复回退整窗。
- 批 2 chart：悬停、图例、数据变更改按图表控件标脏；数据变更随批 1 的 follow_store 通道自动收窄，本批只补悬停与图例。
- 批 3 兜底收窄：点击成交 Up、GIF 换帧、拖放——点击兜底依赖「控件 → 订阅面」反向索引，是全案最难一块，放最后单独评估，收益不够可以维持整窗兜底现状。

## 4. 判据与验证

- `frame_cost_probe` Windows 腿补跑，贴 `paint_full` / `paint_clip` 的 visit / skip 与差值——与 mac 腿合并成收益基线。
- 库测试全绿；`gui/widget` 现有脏区 wbtest 不回退。
- 真机：改一个 Store 数值，检查器确认脏区只落图表矩形；mac 本机可验，Windows 待用户。

## 5. 风险与开放点

- 一个 Signal 多控件订阅：标脏按订阅者逐个并矩形，跨窗各自落账，语义不变。
- 布局侧：脏区只省绘制不省布局，relayout 每帧全量跑——布局增量重排是另一批事，本提案不碰。
- present 恒整帧上屏，无平台局部上屏通道——收窄收益止步于绘制段，上屏段不动。
