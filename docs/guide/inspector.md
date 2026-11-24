# 界面检查器

应用内建的只读检查通道：看控件树、读生效样式、截最近一帧。给人用的是内嵌面板，给 AI 与脚本用的是 socket 服务——两边走同一份数据。

## 组件类型名 kind

每个控件构造时自带一个组件类型名，与 .mng 模板标签统一（kebab-case，如 `ui-input`、`ui-table`；无模板标签的控件同风格补 `ui-` 前缀）。inspector 的树表、详情与 `tree` 命令都显示它。`kind` 与读屏的 `role` 分工：

- `role`：读屏封闭枚举（`button`、`text_input` 这类小写语义名），面向读屏器。
- `kind`：开放字符串组件类型名，面向人与 AI 的「这是什么控件」，名字就是模板里写的标签。

包装层与动态建树可用 `with_kind("名字")` 覆盖；mngkit 在每个模板标签调用点注入 `with_comp("标签")`——它同时定类型名并留组件标记，检查器组件视图与读屏组件组节点认这个标记。会占检查器树一行的裸容器也要报类型名：滚动视口内容容器是 `ui-scroll-content`、虚拟列表内容容器是 `ui-virt-list-content`。

## 组件视图

树默认按「一个组件就是一个组件」组织：

- 模板里写出的每个标签一行（内置组件与自定义组件同口径，自定义组件也是一行，内部实现件不占行）。
- 纯 MoonBit 应用没有组件标记，树保持全量。
- 要看组件内部实现：图形检查器开「内部实现」开关，或 `tree --full`。

读屏同口径：无语义面（无角色、无名、无组件标记、无正文、无状态值、不可点、不可聚焦）的纯布局壳不进语义树，子件挂回最近语义祖先；组件根做组节点（角色 `group`、名字报组件标签），内部可交互控件与文本全部可达。

## 内嵌面板

`gui/inspector` 包按需 import，`inspector_panel()` 挂进任意页面即可：

- 控件树表：按父链缩进，行文本是「类型名·角色「名」 #id」，kind 与 role 双空的裸容器行显示 `(无)`；点行看详情读数（id/父/类型名/角色/名/状态/值/正文/启用/矩形）。
- 样式类页签：列注册类，改五字段（背景/文字/边框色/边框宽/圆角）应用后下一帧生效，「还原此类」回原样。
- 刷新手动或自动（默认 500ms），树数据走最近上屏帧的控件树，组件视图口径。

## 服务（MNG_INSPECT 注入式）

应用进程内可起一个只读检查服务，`mng` 经 socket 取数：

- **开关纯注入**：`MNG_INSPECT=1` 由 `mng dev` / `mng mcp --run` 起应用时注入环境变量，未注入不启动、零监听；应用侧在 `main` 里调一行 `@inspector.inspect_auto_install()` 接线（`mng new` 生成的模板已带）。
- **socket 位置**：`$XDG_RUNTIME_DIR` → `$TMPDIR` → `/tmp` 目录下 `moonbit-inspect-<应用名>.<uid>.sock`，与单实例通道互不干扰；被占用即静默降级不监听。
- **应用名**：取 `MNG_INSPECT_APP`（工具注入时自动带上），缺省 `app`。

五命令，请求一行文本、响应 TSV 行文本（上限 256KB，超限截到最近完整行并尾行标 `truncated`）：

| 命令 | 响应 |
|---|---|
| `tree [--full]` | 整树 dump，一行一控件；缺省组件视图（每个模板标签一行，组件内部实现件不占行，其子件挂回最近已收祖先），`--full` 全量；首行列头，列序 kind/role/name/id/parent/x/y/w/h/state/value/text/enabled |
| `style <id>` | 按 id 读生效样式（含单件覆写后的值）：前五行是样式编辑器口径的五字段（background/color/border_color/border_width/border_radius），随后是**全部已设字段**（字段名即 @style.Style 字段本名，与模板 CSS 属性同口径，如 `font_size`、`flex_direction`） |
| `style set <id> 字段=值 …` | 把列出的字段写进该件的**单件覆写**（只存列出的字段，值非法整条拒绝）：字段名同五字段，值颜色给 `#rrggbb` 或 token 名、数值直写。下一帧生效，`style reset <id>` 撤全部覆写 |
| `select <id>` | `style <id>` 的读数 + 同时在目标应用上高亮该控件（GUI 检查器点行专用，一次往返完成两件事） |
| `highlight <id>` | 在目标应用上高亮该控件（淡蓝半透明填充 + 描边，Chrome DevTools 同款观感）；`highlight 0` 取消。高亮框命中穿透、不进语义树 |
| `shot [--full] [路径]` | 截图落盘 PNG。缺省档截最近上屏帧（视口所见）；`--full` 档对页面滚动容器的内容按全内容高重画（滚动截图语义，含视口外内容；虚拟列表只含已挂载行；超 20000px 截断并注明）。不带路径写系统临时目录 `mng-shot-<窗题>-<时间戳>.png`，回执带实际路径 |

## mng inspect

一次性取数打印：

```sh
mng inspect tree              # 整树 TSV
mng inspect style 42          # id=42 的样式读数
mng inspect shot              # 截帧到临时目录，回执打印路径
mng inspect --app libyue.hello tree   # 显式指定应用名
```

应用没起或没注入时报「连不上检查通道」。

## 检查器附窗与 F12（应用内）

`inspect_auto_install()` 接线的应用（`mng new` 模板已带）顺带装快捷键钩子：焦点在应用窗上按检查器快捷键开附窗，再按关闭（关时取消目标高亮；标题栏叉掉后再按也能重开）。快捷键平台分档——**mac 是 ⌘⌥I**（Cmd+Option+I，浏览器检查器同款；F12 也收，兼容外接键盘），**Windows/Linux 是 F12**。附窗数据直调应用内检查服务（同进程零 socket），布局与交互和图形检查器窗一致：左右分栏可拖、组件视图 + 「内部实现」开关、详情描述列表、样式五字段表单直改选中件。未注入 `MNG_INSPECT` 的应用按了无反应。

附窗检查的是按快捷键的那扇窗——活动窗优先，没有活动窗退第一扇；多窗应用关掉触发窗时附窗跟着关。附窗自己不进检查器的取数面（树、样式、高亮、截图都锚定触发窗），检查器窗不会查到自己头上。

键钩子是窗口级按键兜底之后的进程级通道（`@widget.add_app_key_hook`），服务组件拿不到窗句柄也能装应用级快捷键。

## mng inspect --gui（图形检查器）

仿 Chrome DevTools 的独立检查器窗，经 mngui 出（mng 本体不链 GUI 库，只做参数透传）——适合连**别的进程**的应用；看自己用 F12 附窗即可：

```sh
mng inspect --gui              # 按工程推导应用 id 后开窗
mng inspect --gui --app libyue.hello
mngui --inspect --app libyue.hello   # 裸跑 mngui 亦可
```

- 左右分栏：左树右详情，中间手柄可拖宽度（表格默认两份、详情一份，树表跟栏宽伸缩）。
- 左栏：缩进控件树（类型名·角色「名」 #id），组件视图口径，头部「内部实现」开关切换全量档，点击选中，恒开自动刷新约 1s（异步取数，界面线程不阻塞；树没变不重建表）。
- 右栏：详情用描述列表展示（id/parent/kind/role/name/state/value/text/rect/enabled），最高占右栏一半、不足按实际高；余下全部给样式区，超出滚动。
- 样式区是表单：编辑器五字段（背景/文字/边框色/边框宽/圆角）直接可编辑，选中即预填当前值，「应用」按差量写进该件的单件覆写（改的就是选中的那件，下一帧生效），「还原」撤覆写；表单下方列全部已设字段只读读数。
- 选中即高亮：目标应用窗口上同步画出高亮框，位置随布局实时跟随；关窗自动取消高亮。
- 应用没起或没注入时状态栏报「未连接」，起好后自动接上（轮询重试）。

## mng mcp（AI 客户端接入）

stdio 传输的 MCP server，把三个能力包装成 tools：

```sh
mng mcp --run "moon run examples/hello"   # 拉起应用并注入 MNG_INSPECT=1
mng mcp                                    # 直连已起的应用（不拉起）
```

AI 客户端把 `mng mcp` 配成 MCP server 即可，三工具：

| 工具 | 参数 | 作用 |
|---|---|---|
| `inspector_tree` | 无 | 读控件树（组件视图，同 `tree` 缺省档） |
| `inspector_style` | `id` 整数 | 读样式五字段 |
| `inspector_shot` | `path` 可选、`full` 可选 | 截图落盘，回执带路径（二进制不进对话）；`full=true` 整页内容重画 |

典型用法：AI 先 `inspector_tree` 看树找控件 id，再 `inspector_style` 读样式、`inspector_shot` 看界面长什么样。

## 无头测试直调

`@uitest` 的 `Tester` 有两个不经 socket 的直调方法，断言口径与服务端一致：

- `dump_tree()`：先做帧尾对账再摊 TSV，列头与 `tree` 命令相同。
- `shot(路径)`：整帧位图落盘 PNG（视口所见，`frame()` 之后才有内容）。
- `shot_full(路径)`：整页内容重画落盘 PNG（与服务端 `shot --full` 同口径）。

```moonbit
t.frame()
let out = t.dump_tree()
assert_true(out.contains("Button\tbutton\t"))
```
