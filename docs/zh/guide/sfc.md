# 单文件组件（.mng）

界面用声明式模板写、状态与逻辑用 MoonBit 写，两段合在一个 `.mng` 文件里，由 `mng` 工具预编译成 `.mbt` 再走 `moon build`——`moon check` 仍是唯一类型门禁。命令与工程配置见 [mng 命令与配置](./mng)；热更循环与编辑器见 [热更与编辑器](./mng-dev)。

## 文件结构

```html
<script>
// 页状态与逻辑：MoonBit 原文。被模板引用的 let 绑定即响应槽。
let count : @base.Store[Int32] = @base.Store::new(0)

fn reset() {
  count.set(0)
}
</script>
<template>
  <!-- 单根树 -->
  <ui-col class="page">
    <ui-stepper v-model="count" max="10" />
    计数: {{ count }}
    <ui-button text="重置" @click="reset" />
  </ui-col>
</template>
<style>
.page { padding: 24px; row-gap: 8px; align-items: center; }
</style>
```

- `<script>`：MoonBit 原文，进生成函数体前段；裸 `<script>` 标签（旧写法 `setup`/`lang` 属性仍兼容）。
- `<template>`：单根树（多根 fragment 不支持）。
- `<style>`：类选择器样式，见下[样式章](#样式style-段)。

## 指令集

| 指令 | 作用 | 备注 |
|---|---|---|
| `{{ expr }}` | 文本插值 | 表达式是 MoonBit 原样拼接 |
| `:attr="expr"` | 动态属性 | 落对应 `*_dyn` 入口；引号三式都认（见下） |
| `@event="handler"` | 事件 | 接 script 段的函数；未知事件名编译报错 |
| `v-model="store"` | 双向绑定 | 直传 `@base.Store`，落受控组件的值槽 |
| `v-if` / `v-else-if` / `v-else` | 结构条件 | 表达式任意；不与 `v-for` 同元素（用容器隔开） |
| `v-show="expr"` | 显隐 | 不重建子树 |
| `v-for="it in items" :key="it.id"` | keyed 列表 | 源须 `@base.ListStore`；`(别名, 下标)` 形式可用 |

属性引号三式：① 外层单引号包 MoonBit 双引号串 `:text='@shared.tx("开")'`；② 外层双引号内 `\"` 转义；③ 外层双引号里按 JS 习惯写 `'多字符'`（编译期自动换双引号串；单字符 `'a'` 仍是 Char 字面量，含转义或内嵌双引号的单引号串不自动换）。

静态属性按 MoonBit 字面量规则解析透传（`0` / `0.0` / `true` / 串）。

**表达式是 MoonBit 原样拼接**：字符串拼接用插值 `"\{x}"` 或 `{{ }}`，不要写 `"a" + 1`（MoonBit 的 `+` 不拼非串）；上限 = MoonBit 表达式能写什么，类型安全由 `moon check` 全量保住。

## 组件标签

- **`ui-*` 内置表**：`<ui-button>` → `@ui.button`（`-`→`_`），全集见[组件文档](/zh/components/)。
- **同包组件**：script 段的 `let` 绑定 / 同包 `fn 组件名` 直接当标签用，零声明。
- **跨包组件**：`let 组件名 = @包.函数`——路径取自右值、参数顺序与类型取自源码签名。
- **不规则落点**：子元素参数不是 `Array[@widget.Node]` 之类时用一行覆盖（逃生口，不是日常）：
  `// @mng sh-page = @shared.page positional(children)`

### 带参组件（props）

script 段第一个**只有签名、没有函数体**的 `fn` 头就是本组件的参数表：

```html
<script>
fn user_card(name : String, qty : @base.Store[Int32], on_reset : () -> Unit, wide? : Bool = false) -> @widget.Node {
  ...
}
</script>
<template>
  <user_card name="张三" :qty="count" @reset="reset" />
</template>
```

- 必填走位置参数，可选走 `名? : 类型 = 默认值`。
- 模板里按参数名写属性；回调 prop 用 `@事件名`（按 `名` / `on_名` 在参数表里查）。
- 不写 props 头则生成 `fn <文件 stem>() -> @widget.Node`。
- 未被引用的 prop 自动垫片，保住 `moon check` 零警告。

## 样式（`<style>` 段）

```css
.page { padding: 24px; row-gap: 8px; }
.title { font-size: 18px; font-weight: bold; color: var(--primary); }
.title:hover { color: var(--text_secondary); }
.card:dark { background_color: var(--bg_panel); }
```

- **类选择器**：元素 `class="a b"` 挂多类（后者覆盖前者）；类只作用于挂它的控件——运行时级联 / 元素与后代选择器 / `@media` 不做，遇到即编译报错。
- **值形态**：长度要 `px`（零可省略）；`width`/`height` 另收 `%`；`var(--令牌)` 查主题色 / 尺度令牌；`#rrggbb` 颜色字面量；枚举关键字按 CSS 原味（`space-between`、`flex-end`…）；`flex: g [s [b]]` 按 CSS 简写展开；`transition-duration` 收毫秒；`opacity` / `flex-shrink` 无单位数。
- **交互态**：`.名:hover` / `:active` / `:focus` 编译进状态桶（只收绘制期属性，布局属性进桶编译报错）。
- **深浅两份**：颜色走 `var(--令牌)` 自带深浅两份；字面量分化写 `.名:dark { … }`。
- **文字属性继承**：`font_size` / `color` / `text_align` / `line_height` 等可继承属性随控件树向下推，子声明优先；布局字段不下推。
- **硬约定**：模板属性里的样式字面量（`color=` / `font_size=` 等）**编译报错**——必须进 `<style>` 或 `class`；动态 `:属性="表达式"` 不受限。
- **优先级全序**：继承 < 组件默认 < 构造属性 < class < `style(...)` 规则块。

## 生成码与接线

生成码落模板同包：`<stem>.gen.mbt` 提供 `pub fn <stem>() -> @widget.Node`，像普通函数一样接进路由或窗口：

```moonbit
@ui.mount_window([hello()], title="Template Hello", width=420, height=360)
```

- 生成码带 `// GENERATED … DO NOT EDIT` 头，别手改——改模板重新生成。
- **建议提交仓库**（消费者零工具链依赖）；CI 对 dev / 生产两形态各比一遍新鲜度（重生成后 diff 非空即红）。
- dev 与生产形态共用同一条 `<stem>.gen.mbt`，会互相覆盖——提交前选一种并保持一致。
- 同包两个 `.mng` 撞名（生成函数名取文件 stem）build 期报错并点名文件。

## 页面上下文

库不注入上下文，两条约定：

- **应用级**：应用自持一份上下文单例（模块里一个 `App` 结构 + `@shared.app()` 读）。模板页构建期只读这一层——插值与 `:attr` 表达式在挂载期求值，那时窗口句柄还没填。
- **窗口级**：枚举/切换窗口走 `@widget.host_windows()` / `@widget.active_window()`；窗口级 API（标题、尺寸、无边框…）在**回调里**读上下文里的 `host : Ref[@widget.WindowHost?]`——挂载回调之后才有值。

## 常见错误

| 现象 | 原因与处置 |
|---|---|
| `v-for 源须是 @base.ListStore` | 源给了 Store/Signal 或普通变量——列表用 `let rows : @base.ListStore[T] = @base.ListStore::new()` |
| `v-for 与 v-if 不写在同一元素` | 用容器隔开（外层 v-if 包 v-for，或行内 v-if） |
| `String + Int` 之类的类型错 | 表达式原样拼接——拼接用 `{{ }}` 插值或 `"\{x}"` |
| `moon check` 报生成码与重生成不一致 | 生成码与模板不同步——重跑 `mng dev`（dev 形态）或 `mng build`（生产形态）再提交 |
| 同包生成函数冲突 | 两个 `.mng` 撞名（生成函数名取文件 stem）——改文件名 |
| 模板属性里写 `color="#f00"` 编译报错 | 样式字面量必须进 `<style>` 或 `class`——这是编译器强制，不是建议 |
| HOT 没生效走了 COLD | v-for 行模板 / script / 新符号本来就走 COLD；日志 `[HOT→COLD]` 带原因 |
