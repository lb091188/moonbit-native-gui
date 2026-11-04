# 文本与基础控件

通用约定（尺寸口径、`class` 覆盖全序、值控件与 `Store`）见[组件总览](index.md#约定)。

### `text(content, font_size?=13.0, color?, weight?, family?, align?, max_width?, wrap?=true, ellipsis?, max_lines?=0, selectable?=false, class?, handle?)`

- 文本，`label` 与 `label_t` 合并：尺寸来自 Pango 测量并进布局引擎，可参与基线对齐
- `wrap`：缺省 `true`（块级段落）；单行标签显式 `wrap=false`——行内挤不过兄弟件时收缩、末端出 …
- `max_width`：折行宽度上限
- `ellipsis`：溢出补省略号
- `max_lines`：`wrap` 时限制行数，超过第 N 行截断、行末补 …（`0` = 不限）
- 排版档走 `class`（`@style.text_heading` 等字阶预设）
- `selectable`：打开后这段静态文本**可用鼠标选中并复制**——单击定位、双击选词、拖选、Shift+点击扩选，`Ctrl/Cmd+C` 或右键菜单复制。它是只读的：不可聚焦、不进 Tab 链（可选中文本海量，全进 Tab 环绕键盘就废了），所以按键由宿主在「当前谁持有选区」上兜住。已知边界：折行块内不逐行对齐（整块随 `align` 偏移）；选中期间文本或盒宽变了就清选区；行数钳制与省略与缺省档同源，选中范围=可见范围

### `text_dyn(sig : Signal[String], font_size?, color?, …, wrap?=true, selectable?=false, class?, handle?)`

- 随信号更新的文本：值变化就地改字、只重算该条链路
- `sig`：字符串信号源；其余参数同 `text`
- `bind_label` 的信号版对应物，展示类 `*_dyn` 的原型

### `bind_label(store : Store[A], f : (A) -> String, font_size?, color?, handle?)`

- 声明式文本绑定：初值 `f(store.get())`，之后每次 `set` 就地更新文本并重测
- `f`：值到文本的转换函数；恒单行

### `bind(sig : Signal[A], f : (A) -> String, font_size?, color?, handle?)`

- 信号版文本绑定：`sig` 接源信号或 `computed` 派生信号，`f` 同 `bind_label`

### `divider(text?, vertical?=false, color?, class?)`

- 分隔线：`text` 空 = 直线，`vertical` 定横 / 竖；给字 = 居中断线

### `image(path, width?, height?, handle?)`

- 图像：按文件解码（PNG / JPEG / GIF 首帧）；尺寸给 `0` 用原始尺寸

### `icon(kind : @icons.IconKind, size?=16.0, color?, class?, handle?)`

- 矢量图标：`kind` 为图标枚举；`size` 是盒子边长
- `color` 空 = 主题正文色，随主题取值

### `code_view(lines : Array[String], lang?="moonbit", font_size?=13.0, line_numbers?=false, selectable?=false, handle?)`

- 代码高亮视图：配色跟主题（深浅各一套角色映射，切深浅/换主色后重绘即随；`code_theme` 显式传参可钉死一套，供截图比对一类刻意场景）；词分类着色
- `lang`：语言选择，支持 `js` / `ts` / `python` / `rust` / `c` / `go` / `bash` / `sql`，缺省 `moonbit`
- `line_numbers`：显示行号列
- 宽度跟随容器（flex 1）：窄代码深底条铺满整行，代码比容器宽时自带横向滚动（调用方不必再包 `scroll_view`），高按行数
- `selectable`：打开后这段代码可鼠标选中复制——拖选跨行、双击选词、Shift+点击扩选、`Ctrl/Cmd+C` 或右键菜单复制；行号列不进选区，跨行复制按 `\n` 拼；只读、不进 Tab 链

### `gif(path, width?, height?, looping?=true, running?=true, state?, handle?)`

- 动图：非 GIF 静图只绘制第一帧
- `looping`：`false` 播完一轮即停
- `running`：初始播放状态
- `state`：`GifHandle` 外部句柄，程序化控制播放

### `icon_button(kind, on_click?, icon_size?=16.0, box_size?=28.0, color?, disabled?)`

- 图标按钮：矢量图标盒 + 点击回调；`box_size` 是点击盒边长，`disabled` 禁用态

### `bg_block(hex)` / `fg_block(hex)` / `border_block(hex)`

- 三个颜色快捷 `Style`：`class` 里直接 `@style.bg_block("#2A303C")` 即设底色（另两个设文字色 / 描边色），等价于写全 `@style.style(...)`

### `watch_theme()`

- 主题变化即请求重绘（进程级只订一次）；自绘块跟随主题切换用

