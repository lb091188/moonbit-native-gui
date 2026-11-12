# 浮层与消息

对话框 / 气泡 / 菜单 / 提示等浮层一律开在整窗的**浮层图层**上，天然压过内容与其它浮层，不需要常驻隐藏树。锚点类浮层（下拉、气泡、日期时间弹层、悬浮提示）按图层边界收位：贴窗口底边放不下翻到锚点上方、贴右边放不下与锚点右缘对齐，翻完仍越界则钳回窗口内——弹层不会被窗口裁切。

### `dialog(visible : Store[Bool], title, children, confirm_text?="确定", cancel_text?="取消", on_confirm?, on_cancel?, close_on_mask?=false, …)`

- 对话框：`visible` 驱动弹出 / 收起；标题栏 + ✕ + 内容 + 底部按钮
- `confirm_text` / `cancel_text`：按钮文案，空串隐藏对应按钮
- `close_on_mask`：点击遮罩关闭
- 三个出口（确认 / 取消 / ✕ 与遮罩）都先收起再回调

### `message_box(visible : Store[Bool], title, content, kind?=Information, informative?, buttons?=[("确定",1)], on_response?, on_dismiss?, close_on_mask?=false, width?)`

- 消息框：`kind` 选图标语义，`informative` 为补充说明文字
- `buttons`：`(文案, 编号)` 清单，第一个是主色默认按钮；响应编号由调用方定
- `on_response` 收按钮编号；Enter 触发第一钮；✕ / Esc / 点遮罩走 `on_dismiss`、不给编号

### `popover(trigger : Node, content : Node, width?, height?, class?, handle?)`

- 气泡弹层：点击 trigger 在其下方弹出任意内容，再次点击收起
- `width` / `height` 传 `0` 按内容定尺寸

### `tooltip(content : Node, tip : String, delay_ms?=500, class?, handle?)`

- 悬浮提示：停留 `delay_ms` 后在下方弹出 `tip` 气泡，离开即收；走宿主 `on_hover_change` 父链语义

### `context_menu_for(content : Node, items : Array[(String, () -> Unit)], width?=150.0, handle?)`

- 右键上下文菜单：`items` 文案为 `"-"` 时绘制分隔线；右键按「祖先优先」派发

### `dropdown(trigger, items : Array[String], on_select? : (Int32) -> Unit, width?=150.0, focus_id?, class?)`

- 菜单按钮：trigger 文字 + 项清单；选中回调收下标（`-1` 为未选）。`on_select` 是 `(Int32) -> Unit`，与 `select` 的 Store 口径不同

### `toast_layer(duration_ms? = 2600) -> (String, SemanticType) -> Unit`

- 建界面时调一次得推送函数；之后任意回调里 `toast("文案", @ui.Success)`，到时自动消失、多条堆叠

### `msgbox_icon_of(kind)` / `msgbox_icon_color_of(kind)` / `msgbox_default_code(buttons)`

- 消息框配套查询：`MsgBoxKind` 对应的图标、图标色，`buttons` 清单里主色默认按钮的编号——自绘标题栏或复刻消息框时取

### `update_dialog(visible : Store[Bool], flow : UpdateFlow, actions : UpdateActions, current_version?, title?="软件更新", width?=400, …)`

- 应用更新对话框：按 `flow.state` 走「检查中 → 有新版 → 下载中 → 就绪 → 安装重启」状态机视图；`visible` 驱动弹 / 收
- 组件只管状态机与视图：按钮先标状态再触发 `actions` 里注入的闭包，动作结果经 `flow.report_check / report_download / report_install` 喂回（网络与磁盘怎么跑由装配方决定，组件不硬塞）
- `make_update_flow()` 建账本（状态 Store + 检查命中清单 + 下载载体路径）；`sys_update_actions(flow, manifest_url, current_version, quit)` 是直连 `@sys.update_*` 的最短装配（动作错一拍再跑，Loading 至少先画出来；sys 子进程同步执行，大文件下载期间界面停摆是 v1 已知取舍）
- 失败态按可重试步给「重试」钮（重检查 / 重下载），安装失败不给重试钮；Installing 无出口（成功路径是 relaunch + 退出）
- 清单格式与发布链路见[发布与更新](/guide/publish.md)

