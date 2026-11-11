# 导航

通用约定见[组件总览](index.md#约定)。

### `menu(items : Array[String], selected : Store[String], icons? : Array[(String, IconKind)], width?=180.0, class?, handle?)`

- 侧边导航菜单：选中项主题浅底 + 左缘强调条
- `icons`：`(项名, 图标)` 对清单，按名匹配
- `selected`：选中项 Store，可共享给主区联动

### `menu_sections(sections : Array[(String, Array[String])], selected, icons?, foldable?=true, width?=180.0, class?, handle?)`

- 分组侧边菜单：组标题行 + 组内项
- `foldable=true` 点击标题收起 / 展开

### `segmented(options : Array[String], selected : Store[String], class?, handle?)`

- 分段控制器：选中段面板底 + 主题色文字；每段进 Tab 链、空格 / 回车选中、方向键换段

### `breadcrumb(items : Array[String], selected : Store[String], class?, handle?)`

- 面包屑：层级间插 `/`；当前项按 `selected` 判定、不按位置

### `pagination(current : Store[Int], pages : Int, class?, handle?)`

- 分页 `‹ 1 2 … ›`：`current` 从 1 起，箭头越界夹到首 / 末页

### `steps(items : Array[String], current : Store[Int], on_select? : (Int) -> Unit, class?, handle?)`

- 步骤条：数字方块（已完成 / 当前 / 待办）+ 文字 + 连线；`current` 为 0 起始下标
- 数字方块可点可聚焦：不传 `on_select` 时点击 / 空格 / 回车切到该步、← / → 换步（越界夹回）；传 `on_select(i)` 则点击与方向键交给调用方（如向导里做只读预览，高亮仍只跟 `current`）

### `collapse(panels : Array[(String, Array[Node])], class?, handle?)`

- 折叠面板：点击标题切换内容显隐，各面板独立，默认只展开第一个

### `tree(root : Array[TreeNode], class?, handle?)`

- 树：逐层缩进，点击有子节点的行展开 / 收起

### `tabs(pages : Array[(String, Node)], selected? : Store[Int], class?, handle?)`

- 页签：头行选中主题色 + 底部指示条，内容区预建、靠显隐切换；`selected` 0 起始，不传时内部创建

### `transfer(left_items : Store[Array[String]], right_items : Store[Array[String]], width?=200.0, height?=160.0, item_height?=24.0, class?, handle?)`

- 穿梭框：左右两列 + 中间 `›` / `‹`；两列各由一个 `Store` 驱动
- `item_height`：单行高，配合 `height` 定可视行数
