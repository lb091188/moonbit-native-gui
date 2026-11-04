# 表单控件

值类控件的当前值都由 `Store[T]` 持有，外部改值即刷新，交互改值即回写。通用约定见[组件总览](index.md#约定)。

### `button(text, on_click?, variant?=Soft, color?, background_color?, font_size?, min_width?, focus_id?, disabled?, enabled?, class?, handle?)`

- 按钮：`variant : ButtonVariant` = `Solid` / `Soft` / `Border` / `Text` / `Danger`；键盘空格 / 回车激活
- `min_width`：最小宽度

### `input(store : Store[String], placeholder?, password?=false, read_only?=false, font_size?=13.0, family?, width?=0.0, focus_id?, caret_on?, on_enter?, on_change?, clearable?=false, editor?, class?, …)`

- 单行输入框：选区 / 双击选词 / 撤销重做 / Ctrl+A-C-V / IME 内联全语义
- `placeholder`：空值占位文案；`password` 密码遮罩；`read_only` 只读
- `on_enter`：回车回调；`on_change`：内容变化回调
- `clearable`：悬停 / 聚焦出 ✕、点击清空
- `editor`：挂载时交出 `@input.Editor` 编辑内核句柄，组件外改选区 / 读文本等操作用它
- 右键出编辑菜单（剪切 / 复制 / 粘贴 / 全选，密码框无复制 / 剪切）；Ctrl/Cmd+C/X/V 默认接系统剪贴板（`use_system_clipboard(false)` 可关闭）

### `textarea(store : Store[String], placeholder?, rows?=3, width?=260.0, height?=0.0, font_size?=13.0, family?, read_only?, focus_id?, caret_on?, on_change?, class?, handle?)`

- 多行输入：贪心折行（空格 / 拉丁词 / 中日韩逐字）+ 垂直滚动，上下键跨显示行
- `rows`：初始行数；`height` 给正值时以 `height` 为准
- `on_change`：内容变化回调
- 右键出编辑菜单；Ctrl/Cmd+C/X/V 默认接系统剪贴板

### `checkbox(content, state : Store[Bool], disabled?, enabled?, focus_id?, font_size?, class?, handle?)`

- 复选框 + 文本标签，整行点击区；空格 / 回车切换

### `radio_group(options : Array[String], state : Store[Int], disabled?, direction?=Row, gap?=12.0, class?)`

- 单选组：`options` 依次对应值 `0..n-1`；空格 / 回车选中本项、方向键换选、到头环绕
- `direction`：排布方向，默认横向

### `switch(state : Store[Bool], on_text?, off_text?, disabled?, focus_id?, on_change?, class?)`

- 开关：40×20 胶囊 + 16 圆滑珠；空格 / 回车切换
- `on_text` / `off_text`：开 / 关侧文案，可空
- `on_change`：用户拨动后回调 `on_change(Bool)`（外部写值不回调）

### `slider(state : Store[Double], min?=0.0, max?=100.0, step?=0.0, width?=160.0, disabled?, focus_id?, class?, handle?)`

- 滑块：按下即取值、拖动跟随；方向键步进、Home / End 到端点
- `min` / `max`：取值范围；`step`：吸附步长（`>0` 生效）

### `stepper(state : Store[Int], min?=0, max?=999, step?=1, focus_id?, class?)`

- 数值步进器 `[-] 值 [+]`，共框三段；↑ / ↓ 增减，← / → 移光标
- 中间格可直接输入：只收数字，回车或失焦回写并夹取
- 触界侧自动禁用（灰底次级字、光标回箭头）；聚焦（点击 / Tab / 点加减 / ↑↓）即全选，输入整体替换

### `select(options : Array[String], value : Store[String], on_change?, clearable?=false, placeholder?="", width?=200.0, …)`

- 下拉选择，唯一入口；弹层在浮层图层，↑↓ 高亮 + 回车取值 + Esc 收起
- `on_change`：选中回调
- `clearable`：可清空已选
- `placeholder`：空值占位文案
- 可输入形态用 `editable=true`

### `color_picker(value : Store[String], colors?=[内置 15 色], on_change?, width?=200.0, focus_id?, class?, handle?)`

- 取色器：字段 + 色板网格；回车开板、← / → 移一格、↑ / ↓ 移行、回车取色
- `colors`：色板颜色清单
- `on_change`：取色回调

### `rate(value : Store[Int], max?=5, on_change?, size?=22.0, gap?=4.0, focus_id?, …)`

- 评分：矢量五角星 + 悬停预亮；方向键加减星、Home / End 清零 / 打满
- `max`：星级上限；`size` / `gap`：星形尺寸与间距
- `on_change`：评分变化回调

### `form_item(label_text, control : Node, label_width?=90.0, error?=Store[String], handle?)`

- 表单项：左定宽右对齐标签 + 右控件，下方常驻错误行；行高固定预留、不跳动布局
- `error`：错误文案 Store，非空显示错误行

### `form(title, items : Array[Node], row_gap?=8.0, handle?)`

- 表单：分组标题 + 一组纵排表单项

### `link(text, on_click : () -> Unit, font_size?, class?, handle?)`

- 链接文字：主题色、悬停下划线、抬起触发；`on_click` 点击回调

## 校验与禁用

### `validate(store, rule : (T) -> String?) -> Store[String]`

- 把值流接进规则：立即按现值跑一次，之后值一变就重跑；`rule` 返回 `Some(消息)` 即写红字、`None` 清空。返回的错误 Store 接 `form_item(error=)` 显示同一条错误；订阅进回收袋，控件卸载自动退订

### `required()` / `min_len(n)` / `email()` / `int_range(lo, hi)`

- 四条现成规则（返回值就是上面的 `rule`）：必填（去首尾空白）、字符数下限、邮箱粗规则（`x@y.z` 形态）、整数区间。默认消息随语言取译，`msg~` 传自己的串

### `set_disabled(cell, v)` / `is_disabled(cell)`

- 禁用态单元的读写：控件构造器收 `enabled?` 拿到的单元可随时改；`is_disabled` 读当前态

### `use_system_clipboard(enable)`

- 打开/关闭「输入框的 Ctrl+C/X/V 接系统剪贴板」；只影响**此后新建**的输入框

