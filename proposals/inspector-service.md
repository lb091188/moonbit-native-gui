# inspector 服务化：进程内检查服务、组件类型名与门面改造

> **状态**：已规划（2026-11-16 拍板），未动工。
> **起因**：AI 开发界面缺两条输出通道——整棵组件树的可读 dump 与帧截图落盘；现状 inspector 是嵌入式面板组件，自读自消费、人眼专用，外部进程与 AI 无法取数。
> **决策**（2026-11-16 用户拍板三项）：
> - 载荷格式：TSV 行文本，与 a11y 快照、平台桥口径一致。
> - 服务能力：树 dump + 节点样式 + 帧截图 PNG，第一版全做。
> - 开关策略：debug 构建默认开，release 不监听；环境变量可显式覆盖。

## 1. 现状核账

| 面 | 现状 | 证据 |
| --- | --- | --- |
| inspector 形态 | 嵌入式 GUI 面板，读进程内全局快照自展示 | gui/inspector/inspector.mbt `inspector_panel` |
| 快照字段 | id/parent/role/name/state/value/text/enabled/矩形九件套，无样式面、无组件类型名 | gui/widget/a11y.mbt `A11yNode` |
| 组件类型名 | Widget 无 kind 字段；role 是读屏封闭枚举 22 种，复合组件全落 group/unknown | gui/widget/a11y.mbt `ARole` |
| IPC 基建 | unix socket / Windows 命名管道服务端 FFI 已有，非阻塞轮询、帧泵驱动 | gui/shell/instance.mbt `yi_inst_listen/poll/take` |
| 客户端基建 | socket 路径规则与唤醒客户端已有，mng dev 在用 | tools/native-gui-tools/inst `socket_path/wake` |
| PNG 落盘 | 纯 MoonBit 编码器已有，Canvas/Image 可导出 | gui/render/png.mbt `png_write_bitmap` |
| 无头渲染 | uitest Tester 可 mount + frame + 取位图 | gui/uitest/tester.mbt |

- inspector：开发期检查器，看界面里每个控件的结构、状态与样式。
- unix socket：同机进程间的本地通信管道，Linux 与 macOS 走文件路径寻址。
- 命名管道：Windows 上等价的进程间通信通道。
- 非阻塞轮询：服务端不阻塞等连接，每帧泵顺路查一次有没有人来取数。
- 帧泵：界面应用的事件循环，每帧顺路处理排队事务。

## 2. 设计定案

### 2.1 Widget.kind 组件类型名

- Widget 增 `kind` 字段：组件构造时自带类型名，如 `"Button"`、`"Table"`、`"CodeEditor"`。
- `Node` 包装器提供覆盖入口，形态与 `named` / `with_role` 一致。
- `A11yNode` 快照同步扩列 kind，TSV 输出与 inspector 面板跟着显示。
- 与 role 分工：role 服务读屏语义、封闭枚举；kind 服务 AI 与调试认知、开放字符串，二者独立演化互不挤占。

### 2.2 inspector 拆两层

- 服务核：快照采集 + TSV 序列化 + socket/管道服务端，跑在应用进程内，帧尾顺路更新。
- 门面：现有 `inspector_panel` 改为消费服务数据的展示端，面板自身不再直读全局快照。
- 服务端 FFI 新开 `yi_insp_*` 符号族：listen / poll / take / respond 四符号。
  - 单实例 `yi_inst_*` 原语是单通道槽设计，`yi_listen_fd` 全局唯一、二次 listen 覆盖旧通道，不能复用（已核 shell_stub.c 源码）。
  - POSIX 臂住 inspector 包新 stub 文件，照 shell_stub.c 单实例族结构；Windows 管道臂进 win/stub.c 的 WM_STUB_WIN 分支，照单实例同族模式。
  - ci.yml gate 清单加 `gate inspector/stub.c "" c`，与 sys 桩同口径；win 臂属 CI Windows 腿验证面。
- 帧泵挂点：shell 新增帧泵钩子表，`gui/ui/declarative.mbt` 泵 `dispatch_instance_wake` 的同位无条件调钩子遍历；inspector 服务启动时向钩子表注册自己的泵。
  - ui 与 inspector 互相依赖成环，钩子表放 shell 层，两侧都已依赖 shell。
  - 命令式应用不经 declarative 泵，手动调 inspector 公开的泵入口即可接入。

### 2.3 服务协议

- socket 路径规则沿用 inst 口径：目录 `$XDG_RUNTIME_DIR` → `$TMPDIR` → `/tmp`，文件名 `moonbit-inspect-<slug>.<uid>.sock`，与单实例通道文件名不同互不干扰。
- 请求单行命令，响应 TSV 行文本：
  - `tree`——整树 dump，一行一控件，列含 kind/role/name/id/parent/矩形/状态/值/正文。
  - `style <id>`——指定控件生效样式读数，起步五字段与样式编辑器对齐：背景/文字/边框色/边框宽/圆角。
  - `shot [路径]`——当前帧渲染落盘 PNG；不带路径写默认临时路径，回执一行带实际路径。
- 响应帧上限 256KB，超限截断并在尾行标注 truncated。

### 2.4 开关实现

- 纯注入式定案：`MNG_INSPECT=1` 由 mng dev / mng mcp 起应用时自动注入，未注入不启动服务、零监听。
- 不做构建档位探测：MoonBit 无按档位条件编译机制，档位方案整体放弃。
- tools proc 包 spawn 扩 env 参数，mng dev 的应用拉起点注入。
- 监听 socket 被占用即静默降级为不监听，防御并发场景。

### 2.5 无头直调面

- uitest Tester 同批加 `dump_tree` 与 `shot` 直调方法，不经 socket 直接产出 TSV 与 PNG。
- AI 无头闭环改代码 → 无头跑 → 读树 + 看图，全程不依赖前台进程与真窗口。

### 2.6 kind 快照契约三同步点

- 快照摊平 blob 尾加 kind 字段：gui/widget/a11y.mbt。
- C 桥结构体、publish 解析与 row_tsv 格式串同步扩：gui/win/stub.c `WmA11yRow`。
- AT-SPI 解析侧 `atspi_row_parse` 是列数下限校验，列尾加列自动兼容，按需读。
- 已核读屏消费面：C 桥按结构体字段不吃 TSV 列号，AT-SPI 按列下标取前十二列，kind 列尾追加安全。

### 2.7 mng 消费端

- `mng inspect`：一次性 CLI，`mng inspect tree / style <id> / shot [路径]`，连 socket 取数打印。
- `mng mcp`：stdio 传输 MCP server，三能力包装成 tools；纯 MoonBit 手写 initialize / tools/list / tools/call 三方法，换行分隔 JSON-RPC，stdio 循环照抄 mng lsp 的 read_stdin 通道。
  - MCP：Model Context Protocol，AI 客户端连接外部工具服务的标准协议。
  - 双连接形态：`--run <命令>` 拉起应用并注入 MNG_INSPECT=1；或直连已起应用，直连不拉起。

## 3. 分批施工

- 批 1 组件类型名：Widget.kind + A11yNode 扩列 + inspector 面板显示，全库控件补 kind。
- 批 2 服务核：TSV dump + style 读数 + shot 落盘 + socket 服务端 + 档位开关。
- 批 3 门面与消费端：inspector_panel 改服务消费者、mng 侧消费子命令、中英使用文档。

## 4. 风险与开放点

- 样式采样口径：帧尾对账从 Widget 现取生效样式，起步五字段；级联全量展开不在第一版。
- 截图二进制不走管道：回执只带路径，消费方自读文件，保持载荷纯文本。
- 无显示环境下的 shot：走既有无头渲染链路出图，依赖 headless-closeout 已定的三档分工。
