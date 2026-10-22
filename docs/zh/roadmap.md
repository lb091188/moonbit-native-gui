# 路线图

MoonBit 的**跨平台桌面 GUI 框架**——一套代码直出 Windows / Linux / macOS 原生窗口，系统能力开箱即用，`moon add` 后零配置运行。

本页只回答四件事：**做什么、是什么、什么时候、做到哪了**。

## 怎么读

**验证标准就是三平台**：测试列打勾 = Windows / Linux / macOS 真机都过；只过了一两个平台、或还差子项的，写进行中并注明差在哪。

| 列 | 含义 |
|---|---|
| 功能点 | 一行一个功能点。功能描述的每个要点各占一行，功能点、开发、测试三格纵向合并 |
| 开发 | ✅ 完成　🚧 进行中　⏳ 未开始　❌ 不做 |
| 测试 | ✅ 三平台都过　🚧 部分平台过（注明差哪个）　⏳ 未验　— 不适用（文档类或不做） |

批次看标题：`0.2.0` 是已发布，`0.3.0` 是下一批，往后依次。0.x 阶段按批次发版，不排日历日期。

## 平台与当前版本

| 平台 | 支持面 | 真机验证 |
|---|---|---|
| Linux | X11 主链路，兼容跨度 deepin 20 ~ Ubuntu 26，工具包留守 GTK3 | 已验（XFCE 主；KDE/GNOME/DDE 待排） |
| Windows | 10 / 11，产物是 GUI 子系统 exe，双击不弹控制台 | 已验 |
| macOS | Apple Silicon（Intel 未验） | 已验 |

**当前版本 `0.2.0`**（2026-10-19）：主模块 + 四个扩展包同批首发，见文末「承诺与版本」。

## 已发布 · 0.2.0

<table>
<colgroup><col style="width:14%"><col><col style="width:10%"><col style="width:22%"></colgroup>
<thead><tr><th>功能点</th><th>功能描述</th><th>开发状态</th><th>测试状态</th></tr></thead>
<tbody>
<tr>
<td rowspan="7">窗口能力</td>
<td>开窗、改标题、尺寸切换（1280×720 ↔ 960×540）、全屏、无边框</td>
<td rowspan="7">🚧</td>
<td rowspan="7">🚧 Linux 全过；Windows 差透明与层级；macOS 差透明</td>
</tr>
<tr>
<td>显隐驻留与唤回原位：<code>show</code> 回到 hide 前的屏幕原点</td>
</tr>
<tr>
<td>透明 <code>set_opacity</code> 0–255 与背景穿透 <code>set_transparent_bg</code>，无合成器时静默无效</td>
</tr>
<tr>
<td>层级五档：Normal / 图标下 / 图标上 / AlwaysOnTop / Dock</td>
</tr>
<tr>
<td>面板档承诺不进任务栏与窗口循环、跨工作区常驻；Dock 另带压顶</td>
</tr>
<tr>
<td>边框与标题栏不在承诺内，外观照系统窗口设置</td>
</tr>
<tr>
<td>消息泵与每帧调度</td>
</tr>
<tr>
<td rowspan="4">渲染管线</td>
<td>纯 MoonBit 软件光栅 + Cairo 后端</td>
<td rowspan="4">✅</td>
<td rowspan="4">✅</td>
</tr>
<tr>
<td>Painter 面：路径、曲线、渐变、裁剪、圆角抗锯齿</td>
</tr>
<tr>
<td>线型端点 Butt/Round/Square 与拐角 Miter/Round/Bevel</td>
</tr>
<tr>
<td>场景按控件实际尺寸绘制，拉窗不变形</td>
</tr>
<tr>
<td rowspan="4">文字排印</td>
<td>字体枚举与 CSS 列表式回退（<code>resolve_family</code>）</td>
<td rowspan="4">✅</td>
<td rowspan="4">✅</td>
</tr>
<tr>
<td>混排行高取 max ascent + max descent</td>
</tr>
<tr>
<td>富文本区间字体与颜色（<code>AttributedText</code>）</td>
</tr>
<tr>
<td>CJK 与 RTL 行首方向分开给（对齐给 <code>align</code>，方向给 <code>direction</code>）</td>
</tr>
<tr>
<td rowspan="4">布局系统</td>
<td>yoga 三段式：固定 / 百分比 / flex</td>
<td rowspan="4">✅</td>
<td rowspan="4">✅</td>
</tr>
<tr>
<td>嵌套布局与主轴交叉轴对齐</td>
</tr>
<tr>
<td>8px 分栏把手可拖，首栏 ≥120、次栏 ≥80</td>
</tr>
<tr>
<td>拖动期靠按下捕获，指针出界也不丢事件</td>
</tr>
<tr>
<td rowspan="4">输入与编辑内核</td>
<td>焦点栈与 Tab / Shift+Tab 焦点链</td>
<td rowspan="4">✅</td>
<td rowspan="4">✅</td>
</tr>
<tr>
<td>五类指针事件：Down / Up / Move / Leave</td>
</tr>
<tr>
<td>键鼠映射层（物理键 → 语义键，三平台同源）</td>
</tr>
<tr>
<td>输入框全语义：选区、双击选词、Shift+箭头、undo/redo、只读、密码逐字符遮罩</td>
</tr>
<tr>
<td rowspan="3">输入法通道</td>
<td>组合串内联显示在光标处，候选窗贴光标</td>
<td rowspan="3">✅</td>
<td rowspan="3">✅</td>
</tr>
<tr>
<td>切框与失焦清空组合串</td>
</tr>
<tr>
<td>Linux 走 ibus/fcitx，Windows 走 TSF，macOS 走 NSTextInputClient</td>
</tr>
<tr>
<td rowspan="6">组件库</td>
<td>基础原语与文本族</td>
<td rowspan="6">✅</td>
<td rowspan="6">✅</td>
</tr>
<tr>
<td>表单：输入框、步进器、滑杆、评分、下拉、取色、勾选、单选、开关、日期时间、表单校验</td>
</tr>
<tr>
<td>显示：标签、头像、徽标、统计、进度、卡片、折叠、描述、时间线、表格、虚拟滚动、树、穿梭、轮播、空状态、吸顶列表</td>
</tr>
<tr>
<td>导航：侧栏、菜单（右键 / 下拉 / 原生菜单栏）、分段、页签、面包屑、分页、步骤条</td>
</tr>
<tr>
<td>浮层：Alert、Result、Popover、Toast、Dialog、消息框</td>
</tr>
<tr>
<td>容器与滚动分栏、应用内拖放</td>
</tr>
<tr>
<td rowspan="4">声明式与响应式</td>
<td><code>Store</code> / <code>Signal</code> / <code>computed</code> 三层数据形态</td>
<td rowspan="4">✅</td>
<td rowspan="4">✅</td>
</tr>
<tr>
<td><code>bind_node</code> 原位重建子树，旧代订阅整袋退订</td>
</tr>
<tr>
<td><code>bind_label</code> 与 <code>text_dyn</code> / <code>tag_dyn</code> / <code>badge_count_dyn</code> / <code>statistic_dyn</code> 入口</td>
</tr>
<tr>
<td>展示端不写手动 subscribe</td>
</tr>
<tr>
<td rowspan="4">样式与主题</td>
<td>样式槽 + 状态桶（hover / active / focus）+ 过渡时长</td>
<td rowspan="4">✅</td>
<td rowspan="4">✅</td>
</tr>
<tr>
<td>命名样式类与主题变体（<code>define_class</code> / <code>resolve_with_variant</code>）</td>
</tr>
<tr>
<td>20 个颜色 token：主色、语义色、文字三级、底两级、描边、悬停与斑马</td>
</tr>
<tr>
<td>跟随系统明暗与强调色，读不到回落内置</td>
</tr>
<tr>
<td rowspan="3">过渡动画</td>
<td>插值集合：三条颜色 + 边框宽 + 圆角 + 字号 + 行高</td>
<td rowspan="3">✅</td>
<td rowspan="3">✅</td>
</tr>
<tr>
<td>按真实时间推进，掉帧只少帧不变快慢</td>
</tr>
<tr>
<td>中途移开从当前帧续接，不跳变</td>
</tr>
<tr>
<td rowspan="3">图标库</td>
<td>19 类：表单、编辑、方向、布局、文件、云、设备、图表、通信</td>
<td rowspan="3">✅</td>
<td rowspan="3">✅</td>
</tr>
<tr>
<td>19 类：用户、安全、时间、状态、金融、系统、饮食、媒体、品牌、其他</td>
</tr>
<tr>
<td>全量矢量自绘，不依赖字体文件</td>
</tr>
<tr>
<td rowspan="4">图表</td>
<td>五种基础图：折线、柱状、环形、仪表盘、散点</td>
<td rowspan="4">✅</td>
<td rowspan="4">✅</td>
</tr>
<tr>
<td>交互层：滚轮锚点缩放、拖拽平移、tooltip、图例点击</td>
</tr>
<tr>
<td>九种专项图：雷达、热力、K 线、漏斗、箱线、桑基、树图、矩形树图、旭日</td>
</tr>
<tr>
<td>PNG 导出；系列色随主色旋转</td>
</tr>
<tr>
<td rowspan="3">Markdown 视图</td>
<td>mdast 解析 + 富文本行自绘</td>
<td rowspan="3">✅</td>
<td rowspan="3">✅</td>
</tr>
<tr>
<td>表格列对齐、脚注上下标、任务列表真复选框、围栏代码块</td>
</tr>
<tr>
<td>行距按字号 1.6 倍起排，块间留 6</td>
</tr>
<tr>
<td rowspan="3">页面路由</td>
<td><code>@router</code> 路由树、每层选中键、link 绑定</td>
<td rowspan="3">✅</td>
<td rowspan="3">✅</td>
</tr>
<tr>
<td>空闲预建与懒建（Eager / Prefetch / Lazy 三档）</td>
</tr>
<tr>
<td>切页只切可见性不重建树，各页滚动位置各自保留</td>
</tr>
<tr>
<td rowspan="3">多窗口与原生子表面</td>
<td><code>open_window</code> / <code>close_window</code> / <code>window_count</code> / <code>active_window</code></td>
<td rowspan="3">✅</td>
<td rowspan="3">✅</td>
</tr>
<tr>
<td><code>wid</code> 与 <code>is_primary</code> 取句柄与主窗判定</td>
</tr>
<tr>
<td>pane 模型：自绘区与 webview 子件各占矩形，矩形由布局给</td>
</tr>
<tr>
<td rowspan="4">系统能力族</td>
<td>原生文件对话框：打开 / 保存 / 选目录</td>
<td rowspan="4">✅</td>
<td rowspan="4">✅</td>
</tr>
<tr>
<td>打开与定位：URL、文件、路径（不存在的路径给 NotFound 不崩）</td>
</tr>
<tr>
<td>剪贴板读写、音量与静音</td>
</tr>
<tr>
<td>显示器枚举、空闲检测、开机自启</td>
</tr>
<tr>
<td rowspan="4">通知 / 托盘 / 全局热键</td>
<td>系统通知：普通与带进度两种</td>
<td rowspan="4">✅</td>
<td rowspan="4">✅</td>
</tr>
<tr>
<td>托盘图标与右键菜单，左键计数、提示语可改</td>
</tr>
<tr>
<td>全局快捷键在应用外也命中；macOS 通知须从 <code>.app</code> 起</td>
</tr>
<tr>
<td>后端不可用时如实报错，不假装成功</td>
</tr>
<tr>
<td rowspan="3">原生菜单栏与消息框</td>
<td>菜单栏模型翻译到原生菜单，点击经命令派发回模型</td>
<td rowspan="3">✅</td>
<td rowspan="3">✅</td>
</tr>
<tr>
<td>原生 MessageBox：信息档是/否，错误档是/否/取消</td>
</tr>
<tr>
<td>三平台同构的自绘消息框，Esc 收起、Enter 走默认钮</td>
</tr>
<tr>
<td rowspan="4">WebView 集成</td>
<td>内嵌 webview 作为原生子件，矩形与自绘区并排</td>
<td rowspan="4">✅</td>
<td rowspan="4">✅</td>
</tr>
<tr>
<td>JS 求值与绑定回包、DOM 抓取（正文 / 链接 / meta / 结构）</td>
</tr>
<tr>
<td>自定义协议（<code>register_protocol</code>）与本地内容通道</td>
</tr>
<tr>
<td>新窗 / 权限 / 下载三项策略可切；崩溃后可重载恢复</td>
</tr>
<tr>
<td rowspan="5">媒体播放</td>
<td>ffmpeg 解码 + miniaudio / CoreAudio 输出</td>
<td rowspan="5">🚧</td>
<td rowspan="5">🚧 Linux 过；Windows 音频过；macOS 音频过、解码未接</td>
</tr>
<tr>
<td>音频与视频播放器：进度、音量、倍速、逐帧、静音循环</td>
</tr>
<tr>
<td>字幕双来源：容器内嵌轨与外挂 SRT</td>
</tr>
<tr>
<td>歌词（同名 .lrc）、实时频谱、全屏三件</td>
</tr>
<tr>
<td>无头播放接口（<code>HeadlessAudio</code> / <code>HeadlessVideo</code>）</td>
</tr>
<tr>
<td rowspan="3">文档站与 CI</td>
<td>中英双语文档站（VitePress）</td>
<td rowspan="3">✅</td>
<td rowspan="3">✅</td>
</tr>
<tr>
<td>三平台 CI：检查 + 库测试 + 构建 + 启动冒烟</td>
</tr>
<tr>
<td>真机用例 143 条，按「应用 → 页面 → 段落」组织</td>
</tr>
</tbody>
</table>

## 0.3.0 · 下一批

主题是**把「已实现但没验到头」的窗口与系统面收口**。

<table>
<colgroup><col style="width:14%"><col><col style="width:10%"><col style="width:22%"></colgroup>
<thead><tr><th>功能点</th><th>功能描述</th><th>开发状态</th><th>测试状态</th></tr></thead>
<tbody>
<tr>
<td rowspan="3">输入法焦点门</td>
<td>焦点控件绑定 + 输入法 filter 门</td>
<td rowspan="3">🚧</td>
<td rowspan="3">🚧 Linux 过；Windows / macOS 待验</td>
</tr>
<tr>
<td>focus_in/out 同步，切框通知输入法</td>
</tr>
<tr>
<td>修点空白后按键被吞、切框不清组合串</td>
</tr>
<tr>
<td rowspan="3">浮层原生档</td>
<td>弹层走原生 popup / transient 通道</td>
<td rowspan="3">🚧</td>
<td rowspan="3">🚧 Linux 过；Windows 待核；macOS 进行中</td>
</tr>
<tr>
<td>Windows 侧有无对应口待核</td>
</tr>
<tr>
<td>原生弹层 Esc 收起，关窗时挪出派发链</td>
</tr>
<tr>
<td rowspan="3">媒体播放器族补口</td>
<td>Windows 与 macOS 补齐字幕、歌词、实时频谱</td>
<td rowspan="3">🚧</td>
<td rowspan="3">🚧 Linux 过；Windows / macOS 待验</td>
</tr>
<tr>
<td>补倍速、静音循环、全屏三件</td>
</tr>
<tr>
<td>macOS ffmpeg 解码后端单独立项</td>
</tr>
<tr>
<td rowspan="3">系统能力补口</td>
<td>系统信息与桌面环境读数</td>
<td rowspan="3">🚧</td>
<td rowspan="3">🚧 Linux 过；Windows / macOS 待验</td>
</tr>
<tr>
<td>应用枚举与最近文件</td>
</tr>
<tr>
<td>壁纸与默认应用、单实例排在「待排」</td>
</tr>
<tr>
<td rowspan="2">全局快捷键媒体键</td>
<td>MediaPlay / Prev / Next / Mute</td>
<td rowspan="2">🚧</td>
<td rowspan="2">🚧 Linux 与 Windows 进行中；macOS 不支持</td>
</tr>
<tr>
<td>macOS 无 Carbon 键位，注册诚实失败</td>
</tr>
<tr>
<td rowspan="2">上屏帧缓冲所有权</td>
<td>明确帧缓冲归属</td>
<td rowspan="2">🚧</td>
<td rowspan="2">🚧 Linux 过；Windows 进行中；macOS 未接</td>
</tr>
<tr>
<td>减少上屏路径上的多余拷贝</td>
</tr>
<tr>
<td rowspan="2">路由每层淘汰</td>
<td><code>Lru(n)</code> 摘树 + 整代退订</td>
<td rowspan="2">⏳</td>
<td rowspan="2">⏳ 未验</td>
</tr>
<tr>
<td>长会话下页面缓存不无限长</td>
</tr>
<tr>
<td rowspan="2">窗口内按键路由补齐</td>
<td>跨页切换后的按键兜底路由</td>
<td rowspan="2">⏳</td>
<td rowspan="2">⏳ 未验</td>
</tr>
<tr>
<td>避免失焦后按键进不了页</td>
</tr>
<tr>
<td rowspan="2">浮层「点外收起」判据</td>
<td>统一点外收起判定</td>
<td rowspan="2">⏳</td>
<td rowspan="2">⏳ 未验</td>
</tr>
<tr>
<td>补回归，替代各处临时补</td>
</tr>
</tbody>
</table>

## 0.4.0 · GPU 与性能

<table>
<colgroup><col style="width:14%"><col><col style="width:10%"><col style="width:22%"></colgroup>
<thead><tr><th>功能点</th><th>功能描述</th><th>开发状态</th><th>测试状态</th></tr></thead>
<tbody>
<tr>
<td rowspan="4">GPU 合成（可选后端）</td>
<td>WebGPU 作独立可选模块</td>
<td rowspan="4">⏳</td>
<td rowspan="4">⏳ 未验</td>
</tr>
<tr>
<td>present 走纹理上传 + quad</td>
</tr>
<tr>
<td>三级 fallback：WebGPU → Cairo → 纯软件</td>
</tr>
<tr>
<td>只扩 <code>RenderCtx</code> 枚举变体，不改 Widget 契约</td>
</tr>
<tr>
<td rowspan="2">控件级 GPU 绘制</td>
<td>shader / vertex buffer 画控件路径</td>
<td rowspan="2">⏳</td>
<td rowspan="2">⏳ 未验</td>
</tr>
<tr>
<td>省掉 CPU 回读</td>
</tr>
<tr>
<td rowspan="3">性能治理</td>
<td>每帧重绘范围收窄</td>
<td rowspan="3">🚧</td>
<td rowspan="3">🚧 Linux 过；Windows / macOS 待测</td>
</tr>
<tr>
<td>布局缓存与图表增量重绘</td>
</tr>
<tr>
<td>把整页重画从「百毫秒量级」压下去</td>
</tr>
<tr>
<td rowspan="2">媒体硬解与 GPU 合成</td>
<td>解码输出直达纹理</td>
<td rowspan="2">⏳</td>
<td rowspan="2">⏳ 未验</td>
</tr>
<tr>
<td>省掉 CPU 回读</td>
</tr>
</tbody>
</table>

> 架构与选型依据见 [gpu-architecture.md](https://github.com/lb091188/moonbit-native-gui/blob/master/proposals/gpu-architecture.md)。

## 1.0 前 · 稳定与内容

<table>
<colgroup><col style="width:14%"><col><col style="width:10%"><col style="width:22%"></colgroup>
<thead><tr><th>功能点</th><th>功能描述</th><th>开发状态</th><th>测试状态</th></tr></thead>
<tbody>
<tr>
<td rowspan="2">稳定面清单与 1.0 时点</td>
<td>逐包划分「承诺面 / 实验面」</td>
<td rowspan="2">⏳</td>
<td rowspan="2">—</td>
</tr>
<tr>
<td>公告 1.0 的破坏性改动截止线</td>
</tr>
<tr>
<td rowspan="2">组件文档与教程</td>
<td>每个组件一页配图</td>
<td rowspan="2">🚧</td>
<td rowspan="2">—</td>
</tr>
<tr>
<td>教程给可运行的最小工程</td>
</tr>
<tr>
<td rowspan="2">上手门槛</td>
<td>首页「装 moon → moon add → 出窗口」最短路径</td>
<td rowspan="2">🚧</td>
<td rowspan="2">—</td>
</tr>
<tr>
<td>缺依赖时构建报错自带修复提示</td>
</tr>
<tr>
<td rowspan="1">issue 模板与贡献指南</td>
<td>对外投放配套</td>
<td rowspan="1">⏳</td>
<td rowspan="1">—</td>
</tr>
</tbody>
</table>

## 待排

<table>
<colgroup><col style="width:14%"><col><col style="width:10%"><col style="width:22%"></colgroup>
<thead><tr><th>功能点</th><th>功能描述</th><th>开发状态</th><th>测试状态</th></tr></thead>
<tbody>
<tr>
<td rowspan="2">壁纸与默认应用</td>
<td>Windows / macOS 侧后端</td>
<td rowspan="2">🚧</td>
<td rowspan="2">🚧 Linux 过（XFCE）；Windows / macOS 未接</td>
</tr>
<tr>
<td>Linux 已有代码分支，仅 XFCE 实测</td>
</tr>
<tr>
<td rowspan="2">单实例</td>
<td>进程级唯一 + 唤起已有实例</td>
<td rowspan="2">🚧</td>
<td rowspan="2">🚧 Linux 过；Windows / macOS 未接</td>
</tr>
<tr>
<td>现仅 Linux 有 dbus 通道</td>
</tr>
<tr>
<td rowspan="2">Wayland 原生能力</td>
<td>portal / 夜灯 / 全局热键在 Wayland 会话的原生路径</td>
<td rowspan="2">🚧</td>
<td rowspan="2">⏳ 未验</td>
</tr>
<tr>
<td>现一律语义化降级</td>
</tr>
<tr>
<td rowspan="2">KDE / GNOME / DDE 实测</td>
<td>托盘、通知、深浅色读取</td>
<td rowspan="2">🚧</td>
<td rowspan="2">⏳ 未验</td>
</tr>
<tr>
<td>壁纸、默认应用在三个桌面环境的真机记录</td>
</tr>
<tr>
<td rowspan="2">任务栏进度与 dock 徽标</td>
<td>Windows 走 <code>ITaskbarList3</code></td>
<td rowspan="2">🚧</td>
<td rowspan="2">🚧 Windows 过；macOS / Linux 未接</td>
</tr>
<tr>
<td>macOS <code>NSDockTile</code>、Linux <code>LauncherEntry</code> 未接</td>
</tr>
<tr>
<td rowspan="1">传感器 / 蓝牙 / 磁盘</td>
<td>Linux 侧硬件族读数</td>
<td rowspan="1">🚧</td>
<td rowspan="1">🚧 Linux 过；另两平台无对应面</td>
</tr>
<tr>
<td rowspan="2">排印与绘制补口</td>
<td><code>letter_spacing</code>、<code>set_dashes</code></td>
<td rowspan="2">❌</td>
<td rowspan="2">—</td>
</tr>
<tr>
<td>代码高亮 / 终端 / WebGL 画布</td>
</tr>
<tr>
<td rowspan="2">macOS GIF 分帧合成</td>
<td>disposal 不在 Apple 公开属性里，需探针先回证可得性</td>
<td rowspan="2">⏳</td>
<td rowspan="2">⏳ 未验</td>
</tr>
<tr>
<td>现退回首帧静图</td>
</tr>
<tr>
<td rowspan="2">macOS ffmpeg 解码后端</td>
<td>要接系统解码器或自带二进制</td>
<td rowspan="2">❌</td>
<td rowspan="2">—</td>
</tr>
<tr>
<td>现仅音频可用，视频走 <code>Unsupported</code></td>
</tr>
<tr>
<td rowspan="2">macOS 显示器「首选档」</td>
<td><code>CGDisplayModeIsPreferred</code> 已不在 SDK 声明</td>
<td rowspan="2">⏳</td>
<td rowspan="2">⏳ 未验</td>
</tr>
<tr>
<td><code>preferred</code> 恒 false</td>
</tr>
<tr>
<td rowspan="2">通知后端第三档</td>
<td>macOS 走的仍是 WinBalloon 后端名</td>
<td rowspan="2">⏳</td>
<td rowspan="2">⏳ 未验</td>
</tr>
<tr>
<td>能力同档但命名失真</td>
</tr>
</tbody>
</table>

## Linux 兼容面

### 会话轴（X11 / Wayland）

只有下表四项随会话类型变；Wayland 档一律是「探测到会话即语义化降级」。

| 功能点 | X11 | Wayland | Wayland 侧出路 |
|---|---|---|---|
| 全局快捷键 | ✅ | 无对应面 | 需走 portal / 桌面守护协议 |
| 空闲检测 | ✅ | ❌ | 退「有焦点才计时」的近似档 |
| 窗口控制、剪贴板监视 | ✅ | ❌ | 剪贴板读写仍可用 |
| 显示器与夜灯 | ✅ | ❌ | 可改走 D-Bus / portal 的夜灯服务 |

### 桌面环境轴

本仓只有 XFCE 一档有实测记录；`？` 就是待核，已列进「待排」。

| 功能点 | XFCE | KDE | GNOME | deepin / DDE |
|---|---|---|---|---|
| 系统托盘 | ✅ | ？ | ？ | ？ |
| 通知 | ✅ | ？ | ？ | ？ |
| 深浅色与强调色读取 | ✅ | ？ | ？ | ？ |
| 壁纸读写 | ✅ | ？ | ？ | ？ |
| 默认应用 / 应用枚举 | ✅ | ？ | ？ | ？ |
| 文件管理器「打开并选中」 | ✅ | ？ | ？ | ？ |

已知缺口：GNOME 默认无 SNI watcher，需装扩展；KDE 取色路径未接；壁纸与默认应用在 KDE / GNOME / DDE 有代码分支但未实测；「打开并选中」未接 `FileManager1`，现恒落「打开父目录」。

## 明确不做

- **无障碍**：自绘文本栈暂不含，只记不办。
- **单平台能力进跨平台门面**：只有单一平台实现的能力不做门面，也不留挂账。
- **Linux 工具包升级**：留守 GTK3——它是 deepin 20 到 Ubuntu 26 的公共交集；不引入 Qt。脱 GTK 的唯一形态是降为可选后端。
- **原生控件皮肤**：不作主题化路径；按平台开关的原生兜底例外需逐条登记评审。
- **按参考实现平移接口**：接口由真实用例驱动，不为对齐而补。
- **macOS 四族**：窗口管理（Accessibility 授权门槛）、夜间色温（CoreBrightness 私有）、电源方案（`pmset` 语义对不上三值）、媒体播放器枚举（无 MPRIS 对等物）。

## 承诺与版本

- 当前 `0.2.0`：**0.x 阶段接口仍在演进**，破坏性改动在提交信息写明并同步文档。
- **`0.2.0` 发布记录（2026-10-19）**：主模块与扩展模块同批发布——`NoahLiu/native-gui@0.2.0`、`NoahLiu/gui-media@0.2.0`、`NoahLiu/gui-webview@0.2.0`（首发）、`NoahLiu/mdparse@0.1.0`（首发）、`NoahLiu/ffmpeg-mbt@0.2.0`；`NoahLiu/yoga-mbt` 维持 `0.1.1`。旧包 `NoahLiu/moonbit-libyue`（0.1.0–0.5.12 共 22 个版本）与 `NoahLiu/yue-media@0.1.0` 同日在 mooncakes 标记废弃，理由「已更名」。
- **稳定面清单与 1.0 时点待定**：落定后本节按「承诺面 / 实验面」逐包列出。

## 待定决策

- **稳定面清单与 1.0 时点**：逐包划分承诺面 / 实验面后，本文与各包文档同步。
- **GPU 后端的默认档**：等 0.4.0 的合成器落地后按实测帧率与兼容性定，不预先承诺。
