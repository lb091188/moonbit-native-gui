# 界面检查器

应用内建的只读检查通道：看控件树、读生效样式、截最近一帧。给人用的是内嵌面板，给 AI 与脚本用的是 socket 服务——两边走同一份数据。

## 组件类型名 kind

每个控件构造时自带一个组件类型名（如 `Button`、`Table`、`CodeEditor`），inspector 的树表、详情与 `tree` 命令都显示它。`kind` 与读屏的 `role` 分工：

- `role`：读屏封闭枚举（`button`、`text_input` 这类小写语义名），面向读屏器。
- `kind`：开放字符串组件类型名，面向人与 AI 的「这是什么控件」。

包装层与动态建树可用 `with_kind("名字")` 覆盖。

## 内嵌面板

`gui/inspector` 包按需 import，`inspector_panel()` 挂进任意页面即可：

- 控件树表：按父链缩进，行文本是「类型名·角色「名」 #id」，点行看详情读数（id/父/类型名/角色/名/状态/值/正文/启用/矩形）。
- 样式类页签：列注册类，改五字段（背景/文字/边框色/边框宽/圆角）应用后下一帧生效，「还原此类」回原样。
- 刷新手动或自动（默认 500ms），树数据吃帧尾语义快照，与读屏同一份。

## 服务（MNG_INSPECT 注入式）

应用进程内可起一个只读检查服务，`mng` 经 socket 取数：

- **开关纯注入**：`MNG_INSPECT=1` 由 `mng dev` / `mng mcp --run` 起应用时注入环境变量，未注入不启动、零监听；应用侧在 `main` 里调一行 `@inspector.inspect_auto_install()` 接线（`mng new` 生成的模板已带）。
- **socket 位置**：`$XDG_RUNTIME_DIR` → `$TMPDIR` → `/tmp` 目录下 `moonbit-inspect-<应用名>.<uid>.sock`，与单实例通道互不干扰；被占用即静默降级不监听。
- **应用名**：取 `MNG_INSPECT_APP`（工具注入时自动带上），缺省 `app`。

三命令，请求一行文本、响应 TSV 行文本（上限 256KB，超限截到最近完整行并尾行标 `truncated`）：

| 命令 | 响应 |
|---|---|
| `tree` | 整树 dump，一行一控件；首行列头，列序 kind/role/name/id/parent/x/y/w/h/state/value/text/enabled |
| `style <id>` | 按 id 读生效样式五字段（background/color/border_color/border_width/border_radius），与样式编辑器同口径 |
| `shot [路径]` | 最近一帧落盘 PNG；不带路径写系统临时目录 `mng-shot-<窗题>-<时间戳>.png`，回执带实际路径 |

## mng inspect

一次性取数打印：

```sh
mng inspect tree              # 整树 TSV
mng inspect style 42          # id=42 的样式读数
mng inspect shot              # 截帧到临时目录，回执打印路径
mng inspect --app libyue.hello tree   # 显式指定应用名
```

应用没起或没注入时报「连不上检查通道」。

## mng mcp（AI 客户端接入）

stdio 传输的 MCP server，把三个能力包装成 tools：

```sh
mng mcp --run "moon run examples/hello"   # 拉起应用并注入 MNG_INSPECT=1
mng mcp                                    # 直连已起的应用（不拉起）
```

AI 客户端把 `mng mcp` 配成 MCP server 即可，三工具：

| 工具 | 参数 | 作用 |
|---|---|---|
| `inspector_tree` | 无 | 读控件树（同 `tree`） |
| `inspector_style` | `id` 整数 | 读样式五字段 |
| `inspector_shot` | `path` 可选 | 截帧落盘，回执带路径（二进制不进对话） |

典型用法：AI 先 `inspector_tree` 看树找控件 id，再 `inspector_style` 读样式、`inspector_shot` 看界面长什么样。

## 无头测试直调

`@uitest` 的 `Tester` 有两个不经 socket 的直调方法，断言口径与服务端一致：

- `dump_tree()`：先做帧尾对账再摊 TSV，列头与 `tree` 命令相同。
- `shot(路径)`：整帧位图落盘 PNG（`frame()` 之后才有内容）。

```moonbit
t.frame()
let out = t.dump_tree()
assert_true(out.contains("Button\tbutton\t"))
```
