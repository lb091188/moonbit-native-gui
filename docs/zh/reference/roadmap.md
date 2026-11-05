# 路线图

MoonBit 的**跨平台桌面 GUI 框架**——一套代码直出 Windows / Linux / macOS 原生窗口，系统能力开箱即用。

## 怎么读

每个功能点一行，行首是状态。

- ✅ 已完成：开发完成，且真机测试通过
- 🚧 施工中：部分开发或部分测试（括号中写明平台差异）
- ⏳ 未开始：未开发
- 「明确不做」：确定的边界不会修改
- 远期规划：无法抽象成跨平台的功能会开发各系统独立的包，规划为：windows-mbt、*DE-mbt（linux发行版本差异大，所以会以桌面环境的方式进行发布，底层会封装 linux-mbt）、mac-mbt

## 平台与当前版本

- **Linux** · X11 完整 wayland 有限支持（协议限制），规划测试发行版：deepin 23、25；Ubuntu 24、26（XFCE、KDE、GNOME、Cinnamon），基于 GTK3
  - deepin 20（2026-10-28 首测后**移出支持目标**）：本库的 prebuild 链已降到 Python 3.7 口径并跑通到编译，墙在 MoonBit 工具链自带 runtime 用的 `SYS_pidfd_open`（该机内核头已 5.18，缺的是 glibc 冻结表里的宏，升内核头补不上）；坑与自救记在 [构建与运行](../guide/build.md) §2「低版本发行版」，不再占测试承诺
- **Windows** · 10 / 11
- **macOS** · Apple Silicon

**当前版本 `0.3.1`**（2026-10 已发 mooncakes），见文末「承诺与版本」。

## 已实现

已经开发的功能。

### 窗口

- ✅ **创建窗口**：`mount_window` 起窗：标题、宽高、handle 回调；无窗口后端或无显示服务时返回 `None`
- ✅ **改标题**：运行期改窗口标题；`set_window_title_localized` 可让它随语言重写
- ✅ **改尺寸**：1280×720 ↔ 960×540 两档切换，切完布局照常重排
- ✅ **全屏**：切全屏与还原；全屏态下内容区跟着变大
- ✅ **最大化 / 还原（接口）**：`set_maximized` / `is_maximized`（三平台真机通过）
- ✅ **无边框**：切无边框窗口；标题栏与边框消失，内容区不变形
- ✅ **显隐驻留**：`hide` / `show` 一对；`show` 唤回 hide 前的屏幕原点，不是居中重开。位置口径：`move_to` / `origin` **按客户区原点、物理像素互逆**（带边框的窗内部补偿标题栏与边框厚度，无边框时两者重合）——Win32 臂 2026-10-28 本机实测：`move(160,160)`→`origin=(160,160)` 且整窗矩形补偿到 (152,129)，带边框窗连做三轮 hide/show 客户区与整窗双零漂移（此前该臂是空桩，读数恒 (0,0) 且 `move_to` 静默不生效）
- ✅ **透视窗默认底让位**：宿主给每个 App 根铺的 `bg_page` 默认底曾把透视窗铺满整窗（实测不透明）——新增 `WindowHost::set_transparent_bg`（转窗口层 + 默认底让位，关透视恢复），showcase 透明测试窗改走它
- ✅ **显隐事件与组合串清理**：`Hidden` / `Shown` 事件（`hide` / `show` 真实转换时发，首次显示不发）；隐藏拍清在途输入法组合串、焦点栈不动；整窗失焦同一条交接链（macOS 补 `windowDidResignKey`、Windows 补 `WM_KILLFOCUS` 上报）；`WindowHost::on_hidden` / `WindowHost::on_shown` 暴露给应用
- ✅ **多窗口**：`open_window` / `close_window` / `window_count` / `active_window` 四个门面
- ✅ **窗口句柄与主窗判定**：`wid` 取句柄、`is_primary` 判主窗
- ✅ **消息泵与每帧调度**：宿主事件循环：投递、命中、重排重绘都在这一拍里
- ✅ **窗口透明**：`set_opacity` 0–255，整窗连字一起淡；无合成器时静默无效（三平台真机通过）
- ✅ **背景穿透**：`set_transparent_bg` 打开后控件没铺到的像素留透明，桌面从洞里透出；Windows 需无边框（三平台真机通过；Windows 2026-10-28 验通，**根因是 `UpdateLayeredWindow` 的 `psize` 传 NULL 时提交不落地**——API 返回 TRUE、`GetLastError()=0`，但一个像素都不画，调用方没有任何错误可捕获；四组合实测「只要 `psize` 非空就上屏，`pptDst` 传不传无所谓」，补丁显式给 SIZE、位置仍不动。200% DPI 物理/逻辑像素场景真机已验）
- ✅ **层级：普通档**：`WindowLayer::Normal`，与系统普通窗同档（三平台真机通过）
- ✅ **层级：图标下**：`Desktop`，压在桌面图标之下（Linux 过；Windows 2026-10-28 验通——挂进壁纸 WorkerW，撤档/隐藏/关闭、以及档内移动与改尺寸时让宿主整层重建一次以清掉 GDI 残影，代价是壁纸层闪 30–80ms；档内无交互，键鼠归桌面图标层，故挪动只由程序驱动）
- ✅ **层级：图标上**：`DesktopWidget`，桌面小部件位，本窗照收键鼠（三平台真机通过）
- ✅ **层级：始终置顶**：`AlwaysOnTop`（三平台真机通过）
- ✅ **层级：面板档**：不进任务栏、不进窗口循环、所有工作区显示、普通窗口上全屏窗口下（即 dock 位，三平台真机通过）
- 🚧 **平台原生句柄透出**：`Window::native_handle() -> Int64`——Windows 给 `HWND`、macOS 给 `NSWindow*`、Linux/GTK 给 `GtkWidget*`（口径钉在桩注释），无效槽或无后端回 0；契约「裸句柄、平台语义、仅逃生用，跨平台代码不得依赖」写在方法文档，第三方原生内容挂窗与平台 API 直调不必再复制库的窗口槽表（接口已落地，三平台真机句柄有效性待复验）
- 🚧 **窗口族能力可探测**：`Window::shell_caps()` 八位探测（`opacity` / `transparent_bg` 在 GTK 臂实时探合成器）+ `set_transparent_bg` 返回 `Result`（`Unsupported` / `Failed` 带原因，前置不满足如 Windows 需先无边框进 `Failed` 档）；窗口方法族契约注释逐平台钉死读回值含义（同签名悄悄无效清零，与系统能力族同一套诚实降级口径）

### 渲染与绘制

- ✅ **渲染内建**：控件绘制全部内建，不依赖 Skia 等外部图形引擎
- ✅ **Cairo 后端**：Linux 走 Cairo；与软件光栅同一份 Painter 契约
- ✅ **基础图元**：`fill_rect` / `stroke_rect` / `arc` / `fill` / `stroke` / `draw_text`
- ✅ **路径与曲线**：`move_to` / `line_to` / 二次与三次贝塞尔；`draw_path(Path)` 对象直通
- ✅ **渐变**：线性渐变与径向渐变填充
- ✅ **裁剪与变换**：push / pop clip，平移缩放旋转
- ✅ **圆角与抗锯齿**：真圆弧 + 1px 抗锯齿；圆角关闭时退直角
- ✅ **线型端点与拐角**：LineCap：Butt / Round / Square；LineJoin：Miter / Round / Bevel
- ✅ **虚线**：`set_dashes(图案, 相位)`，on/off 交替、逻辑像素，空数组回实线（三平台真机通过）
- ✅ **位图与图像解码**：PNG / JPEG / GIF（首帧静图）；缩放到目标矩形
- ✅ **全局 alpha**：`opacity` 整层透明度，绘制期生效
- ✅ **矢量图标**：19 类图标包，不依赖字体文件
- ✅ **过渡动画**：状态桶插值：三条颜色 + 边框宽 + 圆角 + 字号 + 行高，按真实时间推进
- 🚧 **macOS GIF 分帧合成**：ImageIO 自建画布逐帧合成，disposal 全档（0/1 保留、2 清帧矩形、3 还原快照）+ ImageRectangle 子矩形 + 索引色调色板兜底，帧号/时长/换帧口径与 Linux / Windows 一致（mac 本机 moon test gui/render 61/61；真机 showcase 复验待，透明底 GIF 出底色块=透明索引缺口另补）

### 文字排印

- ✅ **字体枚举**：系统字体列表与 `Font` 结构（族名、字号、字重、斜体）
- ✅ **字体回退**：CSS 列表口径：族名不存在就按列表往后退，全不中给兜底族
- ✅ **混排行高**：行盒高取 max ascent + max descent，混排不压字
- ✅ **富文本区间属性**：`AttributedText`：按字节区间设字体与颜色，后设覆盖先设
- ✅ **CJK 与 RTL 行首方向**：对齐给 `align`（Start/Center/End），方向给 `direction`，两者分开
- ✅ **样式槽文本字段**：`text_align` / `white_space` / `line_height` / `text_decoration` 写入 class 即生效
- ✅ **字距**：`letter_spacing` 生效到测量与绘制，字间按设定值加宽（三平台真机通过）
- ✅ **行数钳制**：`measure_font` / `draw_box_at` 加 `max_lines`——折行文本超过行数上限时截断、第 N 行末尾出 …（MoonBit 侧二分前缀截断，三平台一实现，不碰平台 C 代码）；`TextSource` 与 `text` / `text_dyn` 透传 `max_lines`。无示例入口，判定走测试文档附录 D 库级用例
- ✅ **文本件口径定案**：`TextRole` 退役——角色收编为 `@style` 字阶预设（`class` 挂 `text_heading` / `text_title` / `text_secondary` / `text_accent`，字号读 `@theme` 字阶令牌，正文 13 为缺省档）；`text` / `text_dyn` 缺省折行（块级段落语义），单行标签显式 `wrap=false`（下限归 0，行内挤不过兄弟件时收缩、末端出 …）；折行档撤 percent(100)，flex 全线 `0 1 auto`；showcase 100 处与其他示例 26 处 `role=` 全量迁 `class`（三平台真机通过）

### 布局

- ✅ **固定尺寸**：宽高给像素值，按值排
- ✅ **百分比尺寸**：`width_percent` / `height_percent`，随容器变
- ✅ **flex 撑满**：`grow` 分配剩余空间；0 = 按内容
- ✅ **嵌套与对齐**：主轴 justify、交叉轴 align、换行 flex_wrap
- ✅ **分栏把手**：8px 把手可拖，首栏 ≥120、次栏 ≥80；拖动期靠按下捕获不丢事件
- ✅ **间距体系**：`padding` / `margin` / `gap` / `row_gap` / `column_gap`，逐边参数可覆写

### 输入

- ✅ **指针事件**：Down / Up / Move / Leave 四类进同一 `on_pointer`，坐标为本地坐标
- ✅ **按下捕获**：按下即捕获，指针移出矩形也不丢 Move / Up；松手归还
- ✅ **悬停父链**：组内任意子件悬停，整组算悬停；宿主维护，不写 enter/leave
- ✅ **光标形状**：默认 / 手型 / 文本 / 横向调整 / 纵向调整 / 隐藏，取最深非零请求
- ✅ **键盘事件**：只投当前焦点控件，只投按下；Tab / Shift+Tab 走焦点链
- ✅ **组合键**：`bind_combo`，`CmdOrCtrl` 按平台落 Ctrl / Cmd，与全局热键同源词表
- ✅ **多击检测**：`on_double_click` / `on_triple_click`，400ms + 4px 阈值
- ✅ **编辑内核**：选区、双击选词、Shift+箭头、undo/redo、只读、密码遮罩；UTF-8 码点边界对齐
- ✅ **输入法通道**：组合串内联、候选窗贴光标、切框清空；Linux ibus/fcitx、Windows TSF、macOS NSTextInputClient
- ✅ **输入法焦点门**：焦点控件绑定 + filter 门 + focus_in/out 同步（三平台真机通过）
- ✅ **静态文本选中与复制**：`text`/`text_dyn` 的 `selectable` 档（单击定位、双击选词、拖选、Shift+点击扩选、`Ctrl/Cmd+C` 走宿主「谁持有选区」支、右键菜单 `can_edit=false`·`can_copy=true`、I 梁光标、窗口级单 owner 互斥、文本变化清选区；只读、不进 Tab 链）；`code_view` 跨行拖选、双击选词、Shift+点击、复制按 `\n` 拼、行号列不进选区；`markdown_view(selectable=true)` 逐字前缀实测量（`measure_font(前缀)` 与 entry/textarea 光标同口径，消除按比例分摊的 shaping 误差），文档级跨段选中按视觉序拼块、拖选/复制跨块连续，围栏/缩进/数学代码块随 `selectable` 透传；`rich_text(at, selectable)` 接 `AttributedText` 行盒与 `TextSel` 选中链，高亮按行盒铺、复制得全文。段内选中真机验收通过（2026-11-05）
- 🚧 **浮层原生档**：所在窗挂有原生子件（网页区）时，六件浮层组件（气泡/下拉/提示/对话框/Toast/右键菜单）自动改开真窗口——无边框、不进任务栏、transient 到 owner、恒在 owner 之上，档位只看 `has_child_surfaces()`；无网页区维持同窗图层档。三平台接口全真，经 2026-10-28/29 多轮真机迭代收口（白板/窄条/收框量尺/KDE 死边/点外不收，见 adaptation.md）（Linux 真机多轮已过；Windows/mac 末轮清单待复验）

### 组件

- ✅ **按钮**：五变体 Solid / Soft / Border / Text / Danger，图标槽与禁用态
- ✅ **文字与链接**：五级排版角色；Link 主题色 + 悬停下划线
- ✅ **输入框**：单行、多行、密码；placeholder、只读、清空
- ✅ **输入框编辑套件**：系统剪贴板默认接通（Ctrl/Cmd+C/X/V 开箱互通，探测不可用自动降级内部槽，测试可 `use_system_clipboard(false)` 显式关）；单行/多行右键内置编辑菜单（剪切/复制/粘贴/全选；密码框不给复制，只读框只读档），文案走 `gui.ui.edit.*`
- ✅ **步进器**：0..10 钳制；点 +/− 后中间格接焦点，可直接键盘改
- ✅ **步进器聚焦全选**：中间格聚焦（点击 / Tab / 点加减 / ↑↓）即全选，打字整体替换
- ✅ **步进器到界禁用样式**：触界侧按钮呈禁用档（fill_hover 灰底 + 次级字，光标回箭头）
- ✅ **滑杆**：轨道 + 拇指，按 step 量化
- ✅ **评分**：五角星悬停预亮、点击定值
- ✅ **下拉选择**：点字段弹候选、悬停高亮、选中打勾、可清空
- ✅ **取色器**：预设色板点选，hex 值住 Store
- ✅ **勾选与开关**：Checkbox / Radio / Switch；单选组互斥、可整组禁用
- ✅ **日期与时间**：月历、区间、日期时间；时间弹层列式步进，可开秒列
- ✅ **表单与校验**：标签右对齐 + 控件列；`validate` 规则串起来，错误文案随语言
- ✅ **标签 / 头像 / 徽标**：五种语义 Tag、四尺寸头像、数字角标（99+ 封顶）与圆点
- ✅ **统计与进度**：静态数值快照、主题色进度条
- ✅ **卡片与折叠**：标题栏 + 分隔线；折叠面板各自开合
- ✅ **描述与时间线**：键值网格；色点 + 竖线，末项无连线
- ✅ **表格**：斑马纹、列宽拖动、表头排序、单选与多选
- ✅ **虚拟滚动**：只画可见行，万行流畅；排序与列宽同表格
- ✅ **树形**：缩进层级 + ▸/▾ 展开折叠
- ✅ **穿梭框与轮播**：穿梭 ›/‹ 移对侧；轮播箭头 / 圆点 / 自动切 / 悬停暂停
- ✅ **空状态**：占位图 + 说明文字
- ✅ **吸顶列表**：滚动时组标题吸顶，跨边界换文字
- ✅ **侧栏**：分组可折叠、选中浅底 + 主题色强调条
- ✅ **菜单**：右键菜单、下拉菜单、原生菜单栏三种形态
- ✅ **分段控制器**：白底选中 + 主题色文字，与侧栏共享导航状态
- ✅ **页签**：选中下划线 + 内容区显隐切换，不重建
- ✅ **面包屑**：点非当前项直达；分隔符不可点
- ✅ **分页**：当前页实底白字，点页码切换
- ✅ **步骤条**：完成 / 当前 / 待办三态，可进可退
- ✅ **横幅与结果页**：Alert 四语义 + 可关闭；Result 四语义
- ✅ **气泡与轻提示**：Popover 点开点收；Toast 顶部居中、2.6s 自动消失、可堆叠
- ✅ **对话框**：遮罩 + 居中面板，确认/取消后自动收起；随语言重建
- ✅ **拖放**：应用内 4px 起拖 + 落点描边；系统级拖入文件与文本
- ✅ **拖出文件存在性校验与路径归一化**：三平台跳过不存在的拖出路径（死条目会被访达/资源管理器整趟拒收）、全空则本机拖出失败回落应用内；演示载荷改指仓库根真实文件（原相对路径在标准启动 CWD 下不存在，实测拖不出去）；mac 侧路径归一化 `..`/`~` 对齐 GTK/Win32（带 `..` 段的文件 URL 在访达实测拷出整个文件夹）（三平台真机通过：mac 拖出到访达为复制、落成两个文件）
- ✅ **拖拽反馈光标**：新增 `CURSOR_GRAB` / `CURSOR_GRABBING` 两档（Win32 落 IDC_HAND、GTK grab/grabbing、macOS open/closedHand）；拖源悬停张手、按下与拖拽全程握拳（会话期间宿主统一给）
- ✅ **光标组语义补齐**：radio 行、月历格与翻月箭头悬停手型，禁用组与跨月格回默认箭头

### 图表

- ✅ **折线图**：定长滚动窗口、多序列、面积形态、右端最新值标注
- ✅ **柱状图**：纵向柱以 0 为基线支持正负值；横向条适配长类目
- ✅ **环形图**：12 点起顺时针、中心汇总、图例联动
- ✅ **仪表盘**：阈值分段着色，内置插值平滑；可外部驱动
- ✅ **散点图**：2000 点 + 双轴刻度 + 最小二乘趋势线
- ✅ **雷达图**：多维指标的多边形对比，轴网格 + 顶点标注
- ✅ **热力图**：矩阵按值着色，配色阶与坐标标签
- ✅ **K 线图**：开高低收四价柱 + 均线叠加
- ✅ **漏斗图**：分层转化率，宽度随占比收窄
- ✅ **箱线图**：五数概括与离群点
- ✅ **桑基图**：流量分叉与汇合，带宽按流量
- ✅ **关系图**：节点与连线布局，带力导向排布
- ✅ **平行坐标**：多维指标折线对比，轴间连线
- ✅ **象形柱图**：柱体用图形填充，按值重复或缩放
- ✅ **旭日图**：层级占比同心环，内圈为父层级
- ✅ **主题河流**：堆叠序列随时间流动，宽度即分量
- ✅ **树图**：层级节点纵向排布，连线表示从属
- ✅ **矩形树图**：面积占比的嵌套矩形，按层级切分
- ✅ **特效散点**：动画自驱动的散点，位置随时间插值
- ✅ **图表交互**：滚轮锚点缩放、拖拽平移、tooltip、图例点击
- ✅ **图表导出**：画布导出 PNG

### 文档视图

- ✅ **Markdown 渲染**：表格列对齐、脚注、任务列表、围栏代码，行距 1.6 倍
- ✅ **代码高亮**：九种语言关键字集 + 行号 + 一键复制

### 代码栈（编辑器与终端）

- ✅ **分词层跨行状态与字节偏移**：`scan_line(line, lang, state)` 逐行吃行首状态并吐出下一行状态——块注释（C 系不嵌套、rust 按深度嵌套）、python 三引号串、bash heredoc（正文整段按字符串着色、标记行吃完回正常）从此劈得准；Token 带 `byte_start`/`byte_len`（UTF-8 字节，与 Editor/TextLayout 同口径），`tokenize_lang` 降为无状态门面，`code_view` 预排版改吃 `scan_line` 顺行走状态（mdview 围栏代码块同享；静态路径零回归）

### 状态与路由

- ✅ **响应式数据**：`Store` / `Signal` / `computed`；多源合成与条件派生同一写法
- ✅ **绑定与重建**：`bind_node` 原位重建子树、`bind_label` 与各 `*_dyn` 入口
- ✅ **页面路由**：路由树、每层选中键、link 绑定、Eager / Prefetch / Lazy 三档预建
- ✅ **路由每层淘汰**：`Lru(n)` 摘树 + 整代退订，重进按 thunk 重建；只数已挂载子树，`Keep` 不参与淘汰——长会话缓存不无限长
- ✅ **样式与主题**：样式槽 + 状态桶 + 命名类；20 个颜色 token；跟随系统明暗与强调色
- ✅ **声明式层**：`Node{mount:(Widget)->Widget}` 地基（`node_of`/`mount_children`/`WindowHost::mount`/`invalidate` 回路）+ **L1 构造器全集**（`ui/declarative.mbt`：`vbox`/`hbox`/`text_edit`/`picker`/`scroll`/`tab`/`date_picker`/`mount_window`/`bind`/`bind_label`/`hover_group`/`cursor_group`/`overlay_scroll`/`combo`/`gif`；与组件同名的 12 个直接复用组件、不包第二层）。旧链 24 构造器除 `mount`（即 `WindowHost::mount`）与同名件外全部到位**到此收口**。`cursor_group` 配套窗口层光标通道（`wm_set_cursor` + `Widget.cursor` 请求 + 宿主按悬停路径取「最深非零」下发）；`combo` 走按键沿祖先链冒泡（↑↓/回车/Esc）；`gif` 走 `@render.Animation` 逐帧迭代 + 进程级延时通道

### 主题与样式

方案与就绪度档案见 [proposals/style-css-expansion.md](proposals/style-css-expansion.md)（CSS 属性补全）与 [proposals/principles-gap.md](proposals/principles-gap.md)（三条产品原则落差）；本节只列落地项与平台状态。图形后端实为两条：Linux=Cairo，Windows / macOS 共用 Pure Raster，故 Tier A 各件零 C 桩。

- 🚧 **设计令牌四阶**：间距阶 / 半径阶 / 字阶 / 时长阶进 `Theme`（`space_scale` / `radius_scale` / `type_scale` / `duration_scale`）+ 基准常量与静态间距令牌 + 运行时 getter（越界按首末夹取）；`tokens.mbt` 刻度间距字面量换令牌单源（2026-11-02 落地）
- 🚧 **背景渐变**：`background_gradient` 线性 / 径向 + stops（stop 颜色可用主题 token，绘制期现取）；view 盒子（`view` / `col` / `row` / `panel` / `card`）渐变优先、不足两 stop 回落纯色；半透明 stop 的 Cairo / 纯光栅插值口径差记 [adaptation.md](experience/adaptation.md)，不透明主链像素钉死，半透明 golden 待 Windows / mac 批
- 🚧 **每角圆角 + 每边边框**：四角独立半径（CSS over-constraint 归一：相邻角和超边长时全体等比缩小）、四边独立宽与色；不等半径走 4R 路径，纯光栅解析快路加「四值全等」guard；per-side 在四角全 0 时逐边内缘条，带圆角回落统一描边（角部接缝诚实降级）
- 🚧 **混合模式 / overflow / 文本装饰三线**：`mix_blend_mode` 25 式接 `Painter::set_blend_mode`，对 on_draw 与子树同帧生效；`overflow` 的 Visible 档是「跳过控件矩形裁切」的逃生口（Hidden 即现状默认）；`text-decoration` 补 line-through 与 overline，与下划线同一条测量自绘线法（零 C）
- 🚧 **主题 JSON 加载**：`@theme.from_json(src, base?)`——字段白名单 = `Theme` 字段（20 颜色 + 图表色板 + 四阶令牌），未知字段 / 类型不符 / 颜色非法报错，缺省项回落基底；主题随应用分发为数据文件，换肤不碰编译；dev 档 `mng.toml` 的 `theme` 键支持存盘即重载
- 🚧 **跟随系统默认接线**：`@widget.theme_apply_system_once`——进程内首个窗口挂载前探测一次并应用，显式 `theme_apply` 过的应用跳过，持续轮询仍 opt-in；深色系统首次启动不再白闪
- 🚧 **深浅变体接入消费**：`theme_is_dark()`（按页面底亮度判档）+ 内置变体类注册表（tooltip 深浅反转与深档描边、scroll-thumb 与 divider-line 深档提亮）+ 两个消费口（`apply_variant_named` 整槽拥有者、`fold_style_variant` 默认层重折）；`dark:` / `light:` 前缀从「实现了没人用」变有真实消费者
- 🚧 **代码视图主题化**：`Token.color` 角色化为 `Token.role`（0.x 破坏），新增 `CodeTheme` 与 `code_theme_of(Theme)`（按面板底色亮度分深浅两套映射，色值全走语义 token）；缺省绘制期跟 `theme_current()`，显式传 `code_theme` 可钉死
- 🚧 **主题定制示例**：`examples/theme-playground/` 独立模块（换主色 / 全量覆盖 / 持续跟随 / 类槽单组件覆盖四张卡），用例 TP-1.1..5.1 已进测试文档，真机清单待跑
- ✅ **样式全序四层**：一条链 **继承 < 默认（组件内置观感）< 属性（构造散参数）< class < `style(...)`（组件收的显式规则块）**，`fold_style` 的 `style` 位与 `text_dyn` 的 `anon` 落到最高层；对外可配的布局散参数（`hover_group` 的 `padding`/`row_gap`/`width`、`message_box` 面板宽、日期选择器字段宽）从直写 Yoga 折进属性层，组件函数体里的固定行高与轨道宽属内部布局、保持直写不对外样式化；四层同给后者赢由 wbtest 逐条钉住（布局与文字各一条）

### 系统能力

- ✅ **全局快捷键键名随平台**：门面回查/回显给平台规范名（mac `Cmd+…`、其余 `Ctrl+…`，`CmdOrCtrl` 等别名不外泄）；showcase 演示注册 `CmdOrCtrl+Alt+C`
- ✅ **文件对话框**：打开 / 保存 / 选目录；返回所选路径，取消返回 None
- ✅ **打开与定位**：URL 交浏览器、文件交默认程序、路径交文件管理器；不存在给 NotFound 不崩
- ✅ **剪贴板**：读写系统剪贴板文本
- ✅ **音量与静音**：读音量、设百分比、切静音
- 🚧 **任务栏进度（Windows）**：`Window::set_taskbar_progress` / `set_taskbar_state` / `clear_taskbar_progress`，ITaskbarList3 进程级单例、五态写入口；只写不读（Win32 无 getter，非 Windows `taskbar_supported` 恒 false 语义化降级）（W20g 合入；真机观感未复验。dock 徽标（macOS）与 LauncherEntry（Linux）这类单平台专属条目已撤出规划，本条不再拼跨平台门面）
- ✅ **显示器枚举**：在线屏、分辨率、刷新率、物理尺寸、模式列表（三平台各一条官方通道：Linux 解析 `xrandr`、macOS 直调 CoreGraphics、Windows 走 GDI 的 `EnumDisplayDevicesW` + `EnumDisplaySettingsExW`，2026-10-28 接上并真机验通——此前 Windows 掉进 mac 臂恒 `Unsupported`。读数边界：`connected` 恒真（三平台都没有「接了但断电」的公开清单）、`name` Windows 取 `DISPLAY1` 这种设备名去前缀、`mm_width`/`mm_height` 仅 Linux 有（Windows 的 GDI 不报物理尺寸）、`preferred` 三平台恒 false（没有公开信号，不拿「当前档」冒充））
- ✅ **系统托盘**：通知区图标 + 右键/左键菜单（Linux 走 SNI，Windows 走 `Shell_NotifyIcon`）。**退出前必须逐个 `NIM_DELETE`**——Win32 的通知区项不随进程回收，宿主窗口没了会留僵尸图标（右键它既不出菜单也不出 tooltip，得等 Shell 下次鼠标扫过才清）；2026-10-28 修：`remove_all_trays()` 原先只有 SNI 兜底，改为取槽位快照逐个摘除再兜底。**仍是边界**：`taskkill` / 崩溃 / 断电这类非正常退出拦不住，Win32 通病
- ✅ **空闲检测**：读系统空闲秒数（Linux X11、Windows；macOS 走 HID 系统态）
- ✅ **开机自启**：写 autostart / Run 键 / LaunchAgents；开关即真实状态
- ✅ **mac 通知迁移 UNUserNotificationCenter**：老 NSUserNotification 在新 macOS（26.x 实测）被降级成「只进中心不弹条」——通知后端整体迁到 UN：bundle 探测、首次使用请求 alert/sound/timeSensitive 授权（老授权自动补齐）、同 identifier 覆盖即更新、按标识摘除、授权异步裁决前投递排队、声音默认有声（对齐 Win32）、delegate 答复带 Banner|List|Sound、`NATIVEGUI_NOTIFY_LOG` 门控诊断。**前台横幅的钥匙是时间敏感档**：缺档时前台 delegate 询问派发不可靠（忙时静默），标记+授权后忙循环也正常（真机日志 + 探针定案，见 `experience/adaptation.md`）；mac 真机已验（横幅+声音），Linux 走 D-Bus、Windows 走托盘气泡不受影响
- 🚧 **通知打扰档开放给应用**：`notify_send` 加 `urgent?`（缺省 `true`，mac 臂映射 `interruptionLevel` 二档：`true`=TimeSensitive 前台忙时也直接出横幅、`false`=Active 前台忙时静默只进通知中心；用户在系统设置里关掉时间敏感授权后传 `true` 同样回到静默）；Linux 不映射 freedesktop 的 urgency hint（`critical` 是「常驻不消失」语义，与这一档不是一回事）、Win32 无对应物，两臂收下忽略；`wm_notify_send` / `wm_notify_update` 四臂签名同步加 `urgent`；后端名读数 mac 档改报 `un-user-notification`（UN 迁移后名实对齐，枚举 `WinBalloon` 名不动），注释清单补第三档、wbtest 按平台分期望（mac 真机二档观感待复验）
- ✅ **浏览器与编辑器历史**：Chromium 系历史与书签、Firefox 历史、VS Code 最近工作区
- ✅ **窗口管理**：枚举窗口、按 id 或标题激活与关闭（仅 Linux，走 `wmctrl`）
- ✅ **电源计划**：读可用计划集、读当前、切计划（Linux 走 `powerprofilesctl`；Windows 走 PowerGet / SetActiveScheme）
- ✅ **夜间色温**：按百分比设色温与复位（仅 Linux，`redshift` 优先、否则 `xrandr --gamma`）
- ✅ **剪贴板监视**：变更回调（仅 Linux X11，轮询 `xclip` / `xsel` 路线）
- ✅ **子进程与文件原语**：`pr_run` 带超时与输出捕获；`fsx` / `envx` / JSON 读写
- ✅ **传感器 / 蓝牙 / 磁盘**：Linux 侧硬件族只读读数
- ✅ **系统信息**：发行版、机器、内存、开机时长、桌面环境（三平台真机通过；Windows 的机器与内存已接并真机验通——机器走「注册表 `HARDWARE\DESCRIPTION\System\BIOS` → 空则 WMI `Win32_ComputerSystem`」两级，序列号 `Win32_BIOS` → `Win32_ComputerSystemProduct` → `MachineGuid` 依次兜底，**虚拟机（QEMU/SeaBIOS）上那个注册表键存在但一个值都没有**，用户态只剩 WMI 一条路；macOS 走 ioreg 厂商/序列号 + `sysctl hw.model/hw.memsize` + `host_statistics64`）
- ✅ **应用枚举**：已装应用清单与分类（三平台真机通过——Linux `.desktop`、Windows 开始菜单 `.lnk` 递归、macOS `/Applications` plist）
- ✅ **最近文件**：系统最近文件列表（Linux / Windows 实现；macOS 无公开面，属平台边界不是缺口）
- ✅ **壁纸与默认应用**：读写壁纸、查默认应用（三平台分派已接、真机通过——Linux XFCE xfconf、macOS、Windows）
- ✅ **单实例**：进程级唯一 + 唤起已有实例（三平台各一条原生通道已接：Linux dbus 知名名、Windows 命名互斥体 + WM_COPYDATA、macOS AF_UNIX 套接字；Linux 无会话总线回落套接字。三平台真机通过，含双进程防多开）

- ✅ **滚动视口横向滚动档**：`scroll_view(hscroll=true)`——内容自然宽撑开可超视口（align-start 退 stretch + 不收缩），底缘横条（thumb/拖动/点条与纵条同口径），滚轮 dx/触控板横滑消费横向余量；mdview 三处代码块与 showcase section 代码块接入（长行横滚不再裁字）。**布局语义定案补全**：可折内容「收缩 + 折行」（跟随容器），不可折内容（代码/表格）「内容宽 + 横滚」——code_view 恢复内容宽（特例记 adaptation）
- ✅ **组件缺省跟随容器宽（mdview/code_view）**：`markdown_view` 的 width 改语义——0（缺省）= 跟随容器，段落折行走 yoga measure（布局时按可用宽重折，宽变即重排，无任何 resize 监听）；>0 = 构造期定宽（旧口径保留，wbtest 显式 width 用例零回归）。`code_view` 宽改 percent 100（背景条满容器，超宽行交滚动视口）。**库级语义定案：块级组件不显式设宽 = 跟随容器**——yoga 的「不设宽」在主轴是内容宽，必须显式 percent（记 adaptation）。showcase「代码文档」页 markdown 已去定宽。框架 resize→relayout 链路健康由探针三段 + LAYOUT-FRAME 读数证明，此类「resize 后不重排」均为内容侧定宽形态
- ✅ **定宽折行文本按定宽落地（yoga 子项基准三档取法）**：子项交叉轴尺寸确定时，主轴基准取「按该定宽量得的内容尺寸」，不再取 max-content 内在值——此前定宽折行文本的高按「单行不折」落地（measure 已答两行、节点仍是一行高）。交叉轴不确定时仍走 max-content（YG3d 定案不变，反向守卫用例钉住）。yoga 105/105
- ✅ **横滚内容宽 = max(自然宽, 视口宽)**：`scroll_view(hscroll=true)` 的内容补 `min_width percent 100` 下限。缺下限时内容只有自然宽，内部 percent 子项（表格等分列）没有确定参照、还常被内在探询的兜底常量撑大，resize 后列宽纹丝不动、溢出部分滚不回来；补下限后 percent 有确定参照，窄内容铺满视口、宽内容才溢出可滚。mdview 富文本的 max-content 探询同步改为答自身最长行自然宽（去掉 560 兜底常量）。markdown 表格列宽 resize 跟随由无头探针实证（900→列 300、500→列 166.7）
- ✅ **code_view 自带横向滚动 + 宽跟随容器**：代码行不可折，与表格同口径由组件自带 hscroll 视口（视口高即内容高，纵向不滚），调用方不再外包 `scroll_view`——此前每个调用点都要记得包，漏了就裁字。视口与画布宽都取 percent 100（flex 1，摆进任何容器都占满行宽），画布另钉 `min_width=最长行`：窄代码深底条铺满整行、长代码撑出视口横滚。mdview 的 `md_code_scroll` 助手随之撤除，表格横滚折进 `md_table` 本体
- ✅ **换行容器的 min:auto 按定住的交叉宽算**：列内可换行子项的主轴下限，此前按「无定宽时全堆叠」算（18 项图标网格下限 676、真值 30），调用方补 `min_height=0` 又把它钉死成一行、折到第二行被裁（「段不换行」）。现按 css-sizing 以**定住的交叉宽**为参照量：一行放得下就是一行高，放不下自动长到两行，showcase 的 `min_height=0` 全部撤除。只在父主轴为列时启用（父为行时可用宽是限制不是定宽）；实现上复用已算过的那趟测量，不新调容器测量（会就地改写兄弟项 layout）。图标库页/段条流式换行由无头探针实证（900→1 行、500→2 行）
- ✅ **定宽沿测量链下传 + 滚动视口纵向档**：上一条的定宽口径补齐「隔着自身无宽的拉伸列层」形态——父级按 stretch 钦定的交叉宽现随 `measure_content(pinned_w)` 逐层下传，段条不再被包层按全堆叠顶高（实测 236→66）。`scroll_view` 新增 `vscroll=false`（内容高钉视口、只横滚），showcase 右侧改用该档 + 页列自带 percent 宽 + 段条 margin 化：段正文视口重新拿回「窗口 − 段条」的确定高（无头 1100×700 → 634）
- ✅ **样式层 `border_style`（CSS 三档虚线框）**：`Style` 补 `border_style` 槽（`Solid`/`Dashed`/`Dotted`），虚线周期按 `border_width` 派生（dashed = 实 3 空 2、dotted = 圆头点），与 CSS「线形定档、粗细定周期」同口径；通用容器（`view`/`col`/`row`/`panel`/`card`）与滚动视口描边即吃这条，画完复位不漏同帧兄弟。自由图案/相位仍在 Painter 层 `set_dashes`（画布页演示），两者分工记进 showcase 文案。2026-10-27 补纯光栅档（mac/Windows）两处接线：`line_cap` Round 端帽真实落墨（dotted 点全靠它）、直角 `stroke_rect` 虚线档退通用路径（旧档画成实线一圈）

- ✅ **showcase 右侧宽度形态 + 横滚下限档**：右侧内容区 = 窗口宽 − 侧栏宽，`min-width=400`（< 400 钉在 400 并可滚，> 400 用分配宽），窗口窄过「侧栏 + 400」时整块横向滚动。为此 `scroll_view` 的横向档拆成两档：自然宽档 `max(子项自然宽, 视口)`（代码/表格用）与**下限档** `min_content_width` = `max(该值, 视口)`，后者不看子项自然宽——此前子项（自带横滚的宽代码块）的自然宽会一路上浮把外层 min-width 顶掉（探针：设 400 实得 806）。段描述去掉 `max_width=900` 常量，与段标题/正文/代码同一条右缘、随窗口折行
- ✅ **滚动视口跟随底部**：`ScrollState::set_follow_bottom(true)` 开启后内容变高自动贴底，判断点在视口 `on_draw`（几何抄完之后，首帧布局完成即生效），宿主追加内容不必每次调 `scroll_to_bottom`；用户手动滚轮/拖条/点条离开底部自动暂停、回到底部恢复，内部暂停位与宿主开关分离——未开启的滚动容器行为不变。无头用例钉住首帧贴底、内容变高继续跟随、上滚暂停/回落恢复与未开启零影响
- ✅ **权限基础设施（@sys permission）**：系统权限一次性授权的横切族——`permission_probe(kind)` 探测（`AXIsProcessTrusted`/`CGPreflightScreenCaptureAccess` 公开口）、`permission_request(kind)` 弹**系统自带引导框**（不替用户点弹窗）；两态语义（TCC 的未请求与拒绝公开层不可区分，应用侧按「未授→请求→引导→回来再探」走）；Win/Linux 恒 NotNeeded。**操作提权**（每次一弹：macOS 管理员 `osascript`、将来 Windows UAC）随各自能力批处理，首批消费者电源计划 mac 写档已用。showcase「系统集成」页有演示
- ✅ **窗口管理 macOS 档**：win_list 走 `CGWindowList`（窗口 id / 标题——标题需屏幕录制权限，无权限时无标题窗被跳过、列表变短即权限信号）、win_activate 走归属应用激活（免授权）、win_close 走 `AXUIElement` 关闭按钮（辅助功能，缺失报 `Denied` 引导用 permission_request）；行格式对齐 Windows 桩（`0x<winid>\t-1\t<title>`），sys 桩按平台转发到 win 桩（ObjC）
- ✅ **夜间色温 Windows 档**：`SetDeviceGammaRamp` 直调（gdi32，全虚拟屏 DC 一把设齐所有输出）；ramp 构造是 MoonBit 纯函数（pow 曲线，gamma 千分比与 xrandr 路径同源——红提亮/蓝衰减/绿恒 1.00），恒等斜坡即复位；撤掉「无公开 API」的旧判（gamma 桌面斜坡就是公开口）
- ✅ **夜间色温 macOS 档**：全屏点击穿透覆盖层（每屏一扇置顶窗，`CGShieldingWindowLevel` + 跨空间常驻 + `ignoresMouseEvents`，暖色 alpha = 暖度×0.22，percent 100 即摘除）；Night Shift 私有口做不了，f.lux 同款替代机制；实现落 win 桩 `wm_screen_tint_apply`
- ✅ **电源计划 macOS 档（降级映射）**：档集合退化 [Balanced, PowerSaver]（低电量开关映射，性能档不做——High Power 机型限定）；读走 `pmset -g`（免权限），写走 `osascript` 管理员授权弹框（每次一弹的操作提权，用户取消按失败出声）；实现全走 CLI（pr_run），解析纯函数白盒钉住
- ✅ **mac autostart 查询读系统侧禁用位**：`autostart_is_enabled` 在 plist 存在基础上再读 `launchctl print-disabled gui/<uid>`——用户在系统设置「App 后台活动」关掉的条目不再误报已开启（Linux 档认 Hidden 位，mac 认 launchd disabled，两平台口径对齐）；launchctl 读不到时按 plist 宽松放行

### WebView

- ✅ **内嵌 webview**：作为原生子件嵌进界面，矩形由布局给
- ✅ **JS 求值与绑定**：`execute_javascript` 求值回包、`on_invoke` 接网页调用
- ✅ **DOM 抓取**：正文 / 链接 / meta / 结构四项，走脚本求值取 JSON
- ✅ **自定义协议**：`register_protocol` 注册文件根，页面与样式都走协议供给
- ✅ **策略面**：新窗、权限、下载三项可切；拦截与放行即时生效
- ✅ **下载落点归应用层**：库只上报 `Download` 事件（id/uri/建议名）并按档位扣住待决，落判走 `respond_download(id, allow, path)`——保存框从三平台桩移进应用（browser 示例演示）；自动档（默认）交引擎默认落点，库内零弹框（三平台真机通过）
- ✅ **崩溃恢复**：`is_crashed` 探到后重载恢复，不拖死应用
- ✅ **cookie 共享与隔离**：引擎默认共享；隔离走 pane 级 profile，库层不做同步

### 媒体

- ✅ **音频输出**：miniaudio 设备层；Linux / Windows / macOS 三端出声
- ✅ **视频解码与出帧**：ffmpeg 解码 + 帧回传（三平台；mac 免 brew 双路 brew/vendor 归档 LGPL 链接，本机真解码 6/6，video 示例随 release-bin 三平台发布包分发）
- ✅ **播放器控制条**：播放暂停、进度 seek、音量、时间读数
- ✅ **控制条重排**：照成熟播放器排法——静音键并入音量组（进度+时间 → 静音+音量 → 全屏收尾），倍速/缩放档位键钉宽切档不横跳；演示默认开循环、演示资产入各示例模块目录（三平台真机通过）
- ✅ **无头播放**：`HeadlessAudio` / `HeadlessVideo`，注入 schedule 通道自 pump
- ✅ **字幕**：内嵌轨自动读 + 外挂 SRT（纯 MoonBit 实现无平台门，随视频出帧走，三平台）
- ✅ **歌词**：同名 .lrc 配对（纯 MoonBit 实现无平台门，三平台真机通过）
- ✅ **实时频谱**：`pcm_tap` 旁路取 PCM 画柱（随音频输出走，三平台真机通过）
- ✅ **倍速与逐帧**：倍速档位与单帧步进（`AudioPlayer::set_speed` / `VideoPlayer::set_speed` + `step`，三平台真机通过）
- ✅ **全屏三件**：双击切换 / 2.5s 收条藏指针 / 活动即恢复（三平台真机通过）

### 工程与交付

- ✅ **三平台 CI**：检查 + 库测试 + 构建 + 启动冒烟，push 与 PR 都跑
- ✅ **文档站**：中英双语 VitePress 站，含教程、组件、布局、系统能力、路线图
- ✅ **场景教程**：四域 19 个「我想做 X」场景（布局：居中/三段式/分栏/滚动/换行；交互：输入/列表增删/弹窗/toast/定时/显隐/表单/多窗口；样式主题；系统能力），每场景说明、可抄代码与注意事项，落 `docs/zh/howto.md`（英文镜像同路径 `docs/`），与上手教程、布局、组件文档互链

- ✅ **体验文档**：预构建包下载、三平台运行要求、体验点与示例页映射，落 `docs/zh/experience.md`（英文镜像同路径 `docs/`）
- ✅ **预打包扩到三平台五示例**：`release-bin` 工作流补 macOS 腿、收编 browser / audio / video（Windows 随包 FFmpeg DLL、mac 随包 dylib + `.app` 与 `@executable_path` rpath）；2026-10-30 已发布固定 Release「Binaries」（tag `bin`，三平台 zip 覆盖更新，体验点见体验文档）

- ✅ **真机用例与记录台**：按「应用 → 页面 → 段落」组织（现 159 条）；记录台与用例文档同住 `测试文档/`，记录台加载 md 现算清单与计数，用例唯一事实源是 `测试用例.md`（经本地 HTTP 服务打开，Live Server 等）
- 🚧 **组件文档与教程**：每个组件一页配图；教程给可运行最小工程
- ✅ **上手门槛**：首页最短路径；缺依赖时构建报错自带修复提示
- ✅ **贡献入口**：`.github/ISSUE_TEMPLATE` 两份 issue form（bug 带平台 / 会话 / 版本 / 复现步骤 / 退出读数行 / 门禁自查；feature 带真实用例 / 期望接口形态 / 三平台通道情况）+ `config.yml`（关空白 issue，导向体验包、文档站、构建指南与贡献指南）、`PULL_REQUEST_TEMPLATE.md`（门禁读数 + 三平台验证表 + 文档同步清单 + 破坏性改动声明）、`CONTRIBUTING_ZH.md` / `CONTRIBUTING.md` 双语指南（目录落位、设计口径、无头与真机分工、提交与 PR 约定；环境与失败处置指回 build.md，不双源）
- ✅ **无头测试门面 uitest**：公开包 `gui/uitest`（`test-import` 消费、name 定位不靠下标、显式 `frame()` 并行安全、`Capabilities` 显式守卫）；`Window::virtual_` id<0 哨兵 + `WindowHost::test_headless` 假窗与无头泵 wait(0)，定时器经 step 驱动可断言，C 桩零改动；`test_headless` 升为对外门面、`WindowHost::test_headless` 降为底座（签名不承诺 1.0），「虚窗 ≠ 真窗」语义边界写进包首；硬判据 `Tester::finish()`——找/动/看三类观察点一次都没跑即红（跳过计数不进 CI 门禁），form_wbtest 示范迁移完成

## 已规划

规划内容，开发之后会移到上一栏。

### 窗口

- ⏳ **窗口内按键路由补齐**：跨页切换后的按键兜底路由，避免失焦后按键进不了页

### 渲染

- 🚧 **GPU 合成（可选后端）**（2026-11-03 定案排期，模块形态与融合模型见 [proposals/gpu-architecture.md](proposals/gpu-architecture.md)）：`modules/gui-gpu` 独立模块（主包不依赖——包级不引不背、构建级 prebuild 下载失败降级、运行级 dlopen + adapter 探测回退 Cairo/Pure），present 走纹理上传 + 全屏 quad；三级 fallback。✅ **模块骨架已落（2026-11-03）**；✅ **wgpu v29 本机预实证（2026-11-04）**：lavapipe 下 dlopen→instance→adapter→离屏纹理/上传/拷贝管线全通、可无头回读（CI 二档之外的本机判据）；v29 为 future 风格 API（设备经回调取），L1 的 wm_present 臂按此形态实现：pin `wgpu-native v29.0.1.1`（四个平台归档的 sha256 写进 `prebuild.py`，双镜像、总预算 180s/镜像、sha 过了才落盘、`vendor/` 不入库）；`gpu/probe.c` 运行期 dlopen 取 `wgpuCreateInstance`，`probe()` 给 `loaded/not-found` 与可打印详情；**本模块不占链接面**（link_configs 恒空，下载失败即「没装 GPU 扩展」，应用照常走纯光栅）；Linux 本机实测 `loaded(vendor/lib/libwgpu_native.so)`，2/2 用例通过；✅ **第一步 X11 wgpu 三角形已落（2026-11-04）**：`gpu/triangle.c` dlopen wgpu+libX11（零链接面不变）自开 Xlib 窗，v29 future 回调拿 adapter/device + ProcessEvents 泵、surface 走 `WGPUSurfaceSourceXlibWindow`、BGRA8Unorm+Fifo 上屏三色三角形；`run_triangle` 门面 + `experiment/gpu_triangle` 可执行（仓库布局候选：任意 cwd 逐级向上找 vendor，dlopen 试错）；缺 vendor/缺 Xlib 头的平台编译期桩不破构建；无显示实跑验过加载链（错误停在 XOpenDisplay），真机肉眼归用户
- 🚧 **控件级 GPU 绘制**（同一方案定案）：✅ **L1-Linux present 纹理合成已落（2026-11-04）**：`wm_present` GTK X11 臂分派「Bitmap 上传纹理（BGRA8Unorm 与 ARGB32 位图同字节序零转换、行距 256 对齐 CPU 垫行）→ 全屏 textured quad → swapchain present」；GPU 挂上后 cairo 停手 + area 设 app_paintable/关双缓；探测进程级一次（.so 缺/驱动无后端/非 X11 会话永久回退，未 realize 可重试，真失败该窗永久回退），instance/device/管线跨窗复用、每窗只持 surface/纹理/暂存；回退路径逐像素一致（门禁 1296/1296 零变化），真机肉眼归用户；🚧 **首消费者已落（2026-11-04，像素效果待真机）**：gui-gpu 包内加载/探测骨架上收 `wgpu_core`（triangle/canvas 共用，消包内第二份拷贝）；`GpuCanvas` 实现 `@render.GpuSink`（draw_texture_rgba 上传纹理 + fill_rect 纯色 quad，clip 走 scissor、opacity 折顶点，离屏目标 BGRA8Unorm 与位图同字节序零转换，finish 读回解垫）+ `install` 便捷接线 + 无头用例；**进程内 queue 写→GPU 执行链不落地**（standalone C 原型同口径可用，根因待查，见 adaptation.md），像素断言在全零时跳过、真机应用进程复验归用户；✅ **demo 页与 transfer setter 已落（2026-11-05）**：showcase「GPU 画布」页 16（on_render 派发 fill_rect/draw_texture_rgba 进离屏 GpuCanvas、同帧 finish 读回 BGRA 直拷上屏、检查读回按钮给非零率与四角采样、无画布降级 notice）；`Demuxer::set_transfer_mode` 接线（0/1 可设可读、未知档 Err、直纹理档如实不出帧，解码端零改动）；✅ **mac 腿五处修复（2026-11-05）**：库名按平台（.dylib）、adapter 后端自选（Undefined）、上传纹理 RGBA8Unorm、fill shader 去调试写死白、alpha 直通口径——无头用例像素断言首次真正执行并全过；probe 补仓库布局祖先扫描（应用从 examples/仓库根跑都能装库）；✅ **首消费者 mac 真机已过（2026-11-05：图案上屏、检查读回非零；Linux 腿取数与 Win 腿随各自真机条目）**；✅ **L1-Win / L1-mac 已落（2026-11-04）**：核心上收实现 TU 段三臂共享（恰好是三平台真臂的编译条件），Win32 臂 surface 源 WindowsHWND（hinstance=GetModuleHandle(NULL)）、macOS 臂 MetalLayer（首次绑定时 setWantsLayer+挂 CAMetalLayer）；各臂贴像素路径（GTK draw / Win32 WM_PAINT / mac drawRect）按 l1.on 停手，Win32 逐像素透明档不走 GPU；Linux 腿全量可编可测，Win/mac 编译归 CI、真机肉眼归用户（mac 腿已过：2026-11-05 真机界面与纯光栅一致、layer-backing 后交互正常；Win 待验）；✅ **L1 真机两批修复与可观测性（2026-11-04，mac 实测）**：编译错（QuartzCore 引入 + `__bridge` 桥接）与 wgpu v29 校验 abort 两处（sampler `lodMaxClamp`/`maxAnisotropy` 零值、暂存 buffer 缺 `CopyDst`——C 桩 memset 清零吃不到头文件默认值）已修，mac 真机进程取证（dylib 装载 + Metal.framework + present 栈）通过；`NATIVEGUI_GPU_LOG=1` 诊断行（探测结论/逐级失败原因/首窗挂上）+ mac `.dylib` 装载候选 + `@win.gpu_present_status()` 读数上 showcase 探测页；✅ **L2 协议已落**（2026-11-03）——`RenderCtx::Gpu(GpuCtx)` + `pub(open) trait GpuSink`（draw_texture_rgba 视频 quad + fill_rect 简单图形，clip/opacity 随合成传）、`@widget.gpu_set_sink` 探测派发（没设 sink 全 Cpu 档，现有控件零变化）、混排合成序=控件树序（paint_at 的 clip? 可选参把父链裁剪当数据传）；实现仍住可选模块 `@guigpu`（主包只定协议不养猪）。GPU 控件渲到各自纹理、与 CPU 控件纹理按控件树叠合成（融合模型见方案）；首批消费者=视频直纹理接口位 + GPU 内容画布
- 🚧 **性能治理（量化已落地，按数据定后续）**：已落地零散件——局部置脏（按窗标脏区）、分段帧账本（LAYOUT-FRAME 读数 + `paint_profile_summary` 的 layout/paint/present 三段）、组件级布局缓存（textarea 折行 / 图表布局 / 文字 C 侧）；系统性观测面 `experiment/frame_cost_probe`（无头，一个场景一行 `FRAME-COST`）三组读数——帧耗时分段、每帧重绘范围（画到/剔除的控件数）、布局重算次数（yoga 被问测量与缓存命中）。**首批 Linux 读数给的判据**：树不变的连续 20 帧 relayout `ms=0`、`measure=0`（yoga 只在内容真变时才测）——**「再加一层 yoga 布局缓存」不立项**；单段动态文本每帧改一次，240 行树仍 ≤0.5ms/帧；整页绘制成本随规模线性（15/60/240 行 ≈ 0.5/1.2/3.5 ms/帧），而脏矩形裁剪在 cairo 腿几乎不省（不判交），**增量重绘的收益要等 Windows/macOS 两条腿的同款读数**（纯光栅腿才走视口剔除）
- ⏳ **GPU 内容画布**（2026-11-03 由「WebGL 画布」改写归并——桌面原生语境无 WebGL，不按 Web 语境平移）：GPU 上下文嵌进界面，走 gpu-architecture 的 `RenderCtx::Gpu`（Layer 2 第三步），3D/场景图归未来 gui-3d 独立模块

### 代码栈（编辑器与终端）

三件合一份总纲（2026-11-03 立项，依赖链、选型定案与社区备选留档见 [proposals/code-stack.md](proposals/code-stack.md)）：公共地基 = 等宽文本栈 + 着色流 + TextLayout 偏移映射 + Editor 编辑内核；排期 ②扫描器升级（跨行状态/字节偏移已落，剩行级增量随 `code_editor`） → ③`code_editor` → ④`terminal`；前置 text-selection-a11y 一期已落。

- ⏳ **分词层升级·行级增量重扫**：每行缓存 `(行首状态, tokens)`，编辑后从变更行向上复用最近未变行的行首状态、向下重扫，某行行首状态与缓存一致即收敛停；未闭合构造下退化为「脏段一路重扫到文末」（用例钉死不许死循环）。等首个编辑态消费者 `code_editor` 开工同批落，避免先行留无消费者的缓存层。
- ⏳ **代码编辑器控件 `code_editor`**：等宽 + 高亮 + 行号 + 编辑合体——扫描器增量着色 + Editor 内核（caret/选区/撤销重做）+ TextLayout 命中映射；与 textarea 分工（纯文本 vs 高亮编辑），共用 TextLayout/Editor；P1 编辑/光标/选区/高亮/行号/撤销重做，P2 查找/缩进/括号匹配
- ⏳ **终端控件 `terminal`（控件先行，PTY 另立项）**（原「终端模拟」并入本提案）：等宽网格 cell（字符+前背景+属性）+ ANSI CSI/SGR 子集（着色/光标/清屏）+ 滚动，喂文本即可用（日志面板/REPL 输出）；ANSI 直接色值不走 CodeTheme 语义角色，缺省前景/背景跟主题；PTY（forkpty/openpty/ConPTY）独立立项不绑定

### 输入与浮层

- ⏳ **浮层「点外收起」判据**：统一点外收起判定并补回归

### 系统能力

- 🚧 **Wayland 原生路径**（2026-11-03 立项调研，能力出路总表、DE 支持矩阵与 spike 清单见 [proposals/wayland-native.md](proposals/wayland-native.md)）：GUI 本体 Wayland 会话已能跑，缺口在系统能力族与层级/弹层——✅P0 会话探针堵 XWayland 静默假数据（`@sys.session_type()`；夜灯与窗口管理在 Wayland 会话显式 `Unsupported`，显示器枚举按 XWayland 虚拟屏口径声明，预期表进测试文档附录 E）→ ✅ **P1 已落**（2026-11-04）：`gui/dbus/portal.mbt` Request/Response 异步握手通用层（handle_token → request 路径 `/org/freedesktop/portal/desktop/request/<sender 去冒号点换杠>/<token>` → Response 信号一次性订阅，路径派生规则本机 frontend 1.18.4 抓包定案）；`gui/shell/global_shortcuts.mbt` GlobalShortcuts「绑定 + Activated 信号回调」门面（CreateSession→BindShortcuts 两段握手，用户取消/后端不支持如实报错不假成功）；`gui/shell/idle.mbt` GNOME IdleMonitor 精确读数（GetIdletime）+ 集成门面（D-Bus 优先、回落 @sys C 平台读数）；本机实测：frontend 接受请求并按桌面路由到 KDE 后端（5.27.11 实现了 GlobalShortcuts，GTK 后端 1.15.1 没实现——当前会话跑的是 GTK 后端故握手报错，KDE 48+/GNOME 48+ 真机归用户）→ ✅ **P2 已落**（2026-11-04）：夜灯三档——GNOME 写 `org.gnome.settings-daemon.plugins.color` 配置键（gsettings CLI，驱动 DE 自带夜灯）、KDE 读侧全量（Plasma 5.27 ColorCorrect 实物属性全 read-only，写侧 Unsupported；Plasma 6 NightLight 写入口径未核）、wlroots 裸 gamma 待 Wayland 协议客户端；显示器两档——KDE 接 KScreen `getConfig`（本机实证 9 输出/2 已连/30 模式，refreshRate 实测 int64 赫兹、size/pos 是 variant(a{sv})）、GNOME mutter DisplayConfig 字段序未核只探存在（S7 真机定，不许猜字段序产假读数）、wlroots 待协议客户端 → 🚧 P3 进行中（2026-11-04）：协议客户端地基已落——`gui/wayland` 自写 wire（connect/registry/enumerate/bind，headless weston 实测 19 global 与 wayland-info 吻合，选型「自写不链 libwayland」），剪贴板监视/窗口管理/wlroots 各协议客户与 fd 传递待落；layer-shell 不进（KDE/GNOME 双双不支持）；GNOME 侧窗口管理无通道记平台边界；先 spike S1–S8 后动工
- ⏳ **KDE / GNOME / DDE 实测**：托盘、通知、深浅色、壁纸、默认应用的桌面环境矩阵
- ⏳ **显示器「首选档」**：`CGDisplayModeIsPreferred` 已不在 SDK，需找公开替代信号

### 媒体

- 🚧 **硬解与 GPU 合成**（2026-11-03 定案拆两线，互不绑定；两份方案细节已补齐）：**硬解独立先行**——ffmpeg hwaccel 三平台（mac VideoToolbox / Windows D3D11VA / Linux VAAPI），输出仍走现有 CPU 帧链路（改造量收在一个 C 文件 + 两字段），三层回落（驱动缺 / 格式不支持 / 运行期失败）各自在 `vf_open_video_decoder_hw` 与 `vf_decode_next` 判；✅ **Linux VAAPI 本机真跑通**（2026-11-03）：`open_video_decoder(hw=true)` 走 `hw_device_ctx` + `av_hwframe_transfer_data` 下行到 CPU 帧链，首帧 RGBA 与软解**逐字节一致**，状态如实报 `1`；驱动只给软件帧时自动降 `2` 并带原因（绝不把回落报成硬解），对外语义三档「软解 / 硬解 / 已回落」；**三条定案（2026-11-03）**：默认关、显式 `set_hw_decode(true)` 才建 hw ctx；本进程内该 codec+分辨率一次失败即永久回落（重开不带 hw ctx，不逐素材重试）；10bit 首版不做、写进边界；方案、链路与验收口径见 [proposals/media-hwdecode.md](proposals/media-hwdecode.md)。**归档实测更正旧判**：mac 自编脚本从初立就带 `--enable-videotoolbox`（`git log -S` 唯一命中），Windows BtbN lgpl 归档已含 `av_d3d11va_alloc_context`，Linux 走发行版 ffmpeg——「mac 归档重做评估」前提过期，只剩 `otool -L` 验实物与 LICENSE.txt 口径修正。**直纹理零拷贝**归 GPU 线 `GpuContext` 接口位（只留口不排期）；✅ **帧输出抽象（H2）已落**（2026-11-03）：解码帧→RGBA 收敛到单一点 `vf_frame_output`，`VfDec.transfer` 策略位（0=SwScale 唯一已落地档）+ `Demuxer::transfer_mode()` 读数面，GPU 线切直纹理只动输出端一行、解码端零改动（setter 随 GPU 首消费者同批落，不预先留无消费者的 API）；GPU 侧逐平台 surface 挂载、fallback 探测粒度、窗与 surface 生命周期、CI 三档与 wgpu-mbt pin 已落 [proposals/gpu-architecture.md](proposals/gpu-architecture.md)「落地细节」
- ⏳ **解码白名单自建归档（发布形态）**（2026-11-03 立项，方案与分期见 [proposals/media-decode-vendor.md](proposals/media-decode-vendor.md)）：播放档 ffmpeg 从 BtbN 全量共享库换「自编解码白名单」——Windows 运行期 dll 149.2 MB 降白名单量级（推断 15~30 MB，D0 探针定档）、mac 自建脚本 configure 收白名单（顺带修 LICENSE.txt 口径）、Linux 照走发行版不动；swscale 与 hwaccel 保留（与硬解线共存），编码器整档不做（编辑/导出归未来「ffmpeg CLI 独立进程」档，未立项），解码链路代码零改动；D0 探针（体积 + 解码对照）→ D1 Windows workflow 换自编 → D2 mac 收白名单

### 模块化

- ⏳ **能力模块拆分（2026-11-02 定案回退、留档待动机）**：`sys` → `NoahLiu/gui-sys`（纯读写系统工具，无事件循环依赖）、`win` → `NoahLiu/gui-window`（窗口层与 GUI 辅助族：窗口、事件循环、IME、托盘、通知、热键、单实例、对话框，模块内按包细分）、`dbus` → `NoahLiu/gui-dbus`（D-Bus/SNI，依赖 gui-sys）、`shell` + `i18n` → `NoahLiu/gui-shell`（集成层：六通道统一门面、事件泵、平台分派，依赖上述三模块）；`native-gui` 收窄为「组件工具包 + 聚合 facade」、开箱即用不变；顺序 sys → win → dbus → shell → 包级细化，每个模块独立发版，与 gui-webview / gui-media 同形态。2026-11-02 曾完整落地四模块后回退：不对外发行则单件检索面动机不成立，维护成本大于架构收益；方案与回退注记见 `proposals/module-split.md`，四个落地提交在历史里可 cherry-pick 复活

### 开发体验

- 🚧 **模板预编译编译器**：单文件组件（Vue 风模板 + MoonBit script）经工具预编译生成 `.mbt` 再走 `moon build`；表达式原样拼接、`moon check` 唯一类型门禁；v1 指令集：插值、动态属性、事件、双向绑定、条件、keyed 列表、默认 slot；组件带参（props 走签名头：必填位置参、可选具名默认值），跨包组件路径与参数顺序从源码签名自动解析、同包组件零声明；spike 先于编译器（showcase 选页对照钉死语法与产物契约）；CLI 错误回映射模板行列（source map）为 DX 生死线
- 🚧 **模板热更新（IR 热应用）**：编译器旁路产出模板 IR（结构数据 + 类定义数据 + 新表达式 AST）；dev 档注册表由 codegen 生成（状态保活：script 外层建状态、模板树进 build 闭包）+ 应用内 applier 经单实例通道原位重挂；**项目级 dev**（`mng.toml` + 一条命令盯整个工作区）已落地；结构 / class / 样式值 / 受限表达式（字面量、Store、运算、if、`@shared.tx`·`tr`、插值）亚秒；script / v-for / 自定义组件 / children 形 / 文法外表达式回退重启并自动回到改动页
- 🚧 **样式类热更新**：`<style>` 规则随补丁以数据重注册命名类（类名与样式值都可热）；主题 token 的定义改动仍走重启，编译器侧「样式进槽」强制已落——模板属性里的样式字面量一律编译报错，必须进 `<style>` 或 `class`
- 🚧 **模板样式章**：`<style>` 段编译期摊平进命名类注册表（类选择器、`var(--令牌)`、`#rrggbb`、枚举关键字、`flex` 简写、`width`/`height` 的 `%`、`.名:dark` 深浅两档、`:hover/:active/:focus` 交互态、文字属性向下继承；运行时级联 / 元素与后代选择器不做（布局枚举经 `@yoga` 支持））；元素 `class="a b"` → `class_of`；布局属性样式化口径——一条全序 继承 < 默认 < 属性 < class < `style(...)`，对外可配的布局散参数折进属性层、组件内部布局不对外样式化，children / 事件 / 键 / 行列选型留结构侧（Linux 真机待验）
- 🚧 **dev 工具二进制**：本路线的 Vite 位次，`moon install` 分发；子命令 `dev`（watch + 改动分类 + IR 通道推送 + 回退编排）/ `build`（纯生产产物零 dev 痕迹）/ `new`（新 `.mng` 页样板脚手架）/ `lsp`（stdio JSON-RPC：诊断、补全、hover、跳转）/ `--version`（插件握手）就位；工具不依赖 GUI 库（只链 libc/libgcc）；Windows 侧 dev 唤醒的 Win32 单实例客户端（WM_COPYDATA，FindWindowW+SendMessageTimeout）已合入（2026-11-02），HOT 推送真机未验
- 🚧 **编辑器支持**：语义进工具 `lsp` 子命令（stdio JSON-RPC：诊断、补全、hover、跳转；补全目录取 script 段槽名与 props、源码签名解析的组件参数、样式章的类与令牌、`moon.pkg` 别名与包内 `.mbti` 成员；hover 按令牌类型分档并随编辑器语言中英切换（✅2026-11-03 真实类型：script/表达式段经 source map 正投到 `.gen.mbt`，桥 `moon ide hover --json` 取编译器答案，任何一步失败回落静态 hover）；跳转覆盖页内声明、组件源码、`@别名.成员` 与包入口），VSIX（`tools/vscode-mng/`，零依赖 JS）只做语言注册 + TextMate 着色（属性值与脚本段共用表达式文法，类型/变量/函数/常量分色）+ 语义着色（LSP `semanticTokens/full`：类型/变量/参数/函数/方法/命名空间按符号表分档，任何开语义高亮的主题都区分；LSP 降级退回纯 TextMate）+ snippets + LSP 客户端与工具定位引导；不引入原生 HTML/CSS 语义（Linux 待真机装 VSIX 验）；✅2026-11-04 跳转/hover 的 URI 归一收口（`uri_to_path`/`path_to_uri`：盘符前导岔斜、反斜杠、`file:///c%3A/…` 解岔斜，规范 `file:///c:/…` 输出；纯函数用例三平台同跑，集成用例去盘符分流，Windows 真机验归用户）
- ⏳ **模板工具后续批次**（2026-11-02 拆分入待办，进度见 TODO「模板预编译·工具后续批次」）：✅ dev 临时产物目录 `.mng/`（app 日志 / source map / IR 补丁迁出源码目录，文件浏览器不再裸露；2026-11-04 LSP `moon ide hover` 的临时输出也归位——从模板目录向上找项目根落 `.mng/hover.json`，`parent_dir_of` 的根目录语义同批修：给 "." 会让向上走防线踩进 cwd 顶掉已记住的模块根）、✅命令改名 `mng`（目录/包路径/文档/VSIX 默认 cliPath 同批），🚧Windows dev 唤醒（Win32 单实例客户端 WM_COPYDATA 通路已合入待真机：服务端本就吃 GUI 第二实例同款消息，工具侧补 FindWindowW+SendMessageTimeout 客户端）、✅VS Code「MNG: dev」入口（命令面板拉起 `mng dev` 到集成终端）、✅reload-theme 通道（mng.toml `theme` 键 + `--mng-theme` 推送：主题 JSON 存盘即 from_json 重载，不走重启）、真实类型 hover（桥 `moon ide` + source map 正向索引）、✅生成物新鲜度 CI 校验（mng gen dev 形态重编译与提交版 diff）、~~开放问题三项~~ 已定并落地（app 注入=应用自持上下文单例 + 窗口级 `host` 句柄、库零改动；布局属性样式化=一条全序 继承<默认<属性<class<`style(...)`；IR rev 握手=补丁带 `rev`+`keys_digest`、applier 判 stale 回 `.ack`、工具据此转 COLD）
- ⏳ **上游诉求**：moonbitlang native 目标 hot reload / 运行时多模块 + native 增量链接；落地当天 IR 通道升格真代码热换、状态迁移层（快照设计）复活、回退路径消失

### 工程与交付

- ⏳ **稳定面清单与 1.0 时点**：逐包划分承诺面 / 实验面，公告破坏性改动截止线
- ⏳ **无头像素快照基线**（PNG + 容差）：自带基线目录与比对器、三平台各一份基线，`moon test` 无快照机制故全部自建；判据（容差怎么定、基线漂了谁批）待立项时定，工作量大于门面本体，故从 P1 拆出（2026-11-03 定案：单独立项，不进 P1）

### 可访问性

- 🚧 **屏读语义**（2026-11-03 拍板做、自建桥不借原生控件白拿——gui/README.md non-goals 旧口径随批修正；方案、语义槽表桥架构与坑清单见 [proposals/text-selection-a11y.md](proposals/text-selection-a11y.md)）：控件挂 role / name / state，接 macOS NSAccessibility、Linux AT-SPI、Windows UIA provider（MSAA 不做）；阶段排序 mac → Linux → Windows；与静态文本选中共用地基，uitest「name/role 复用同一对字段」开放问题就此收口（另加 enabled 字段与值回调面）。✅ 阶段0 语义字段面已落（2026-11-03）：`Widget` 补 `enabled`（缺省 true）、`a11y_state`（首参控件本身的状态/值回调）、`a11y_text`（现算正文，空则回落 `label`）三个字段，与既有 `name`/`role` 一次加齐（0.x 破坏性变更，构造点只有 `Widget::new()`）；`@widget.ARole` + `arole_of`/`arole_name` 作桥的解析视图（**事实源仍是字符串**，测试与桥同源不双轨）；`Node::a11y(state?, text?)` 包装器按需挂两个回调；✅ **帧尾语义快照已落**（2026-11-03）：`paint_frame` 在上屏前重扫整树，产出 `A11yNode` 快照（id/父/角色/名/状态/值/正文/启用/窗口矩形），`a11y_last_frame()` 就是三平台臂的读数面——重扫不增量，**幽灵控件在这条路上不存在**（用例钉：删控件后快照少一条、不可见子树整棵不进）。C 侧「应答式」槽表等某条桥真需要查询风暴再下移（推送式桥不需要它）。首批组件语义挂载已落：`button`（角色 + 启用态 + 按钮文字）、`checkbox`／`switch`（`checked`/`unchecked` 现读 Store）、`slider`／`progress`（百分比值，改 Store 即变）、`input`（读当前文本；密码框只报 `password` 保护态、明文绝不出语义面；只读报 `read_only`）、`textarea`（读全文）、`select`（当前值）、`text`／`text_dyn`（角色 `text`，正文走 `label`）；✅ **macOS NSAccessibility 桥已落**（2026-11-03，`gui/win/stub.c` 的 WM_STUB_MAC 臂）：WMView 挂协议 + accessibilityChildren 把快照摊成轻量 AX 元素（角色映射、物理像素→点、非翻转 y 换算、屏幕坐标、启用态/值/状态）；二批收口——元素改 `WMA11yElement` 子类带 press 动作（与 Windows UIA 的 Invoke 同压跨平台动作队列、MoonBit 合成点击）、`accessibilityFocusedUIElement`（焦点 id 通道）与 `accessibilityHitTest:`（屏幕点还最深元素）、事件上行（快照内容变发 AX LayoutChanged、焦点换发 FocusedUIElementChanged，静止界面不扰民）；VoiceOver 真机清单归用户；✅ **Windows UIA provider 已落**（2026-11-03，`gui/win/uia_provider.c`）：WM_GETOBJECT → 窗根 provider → 快照行惰性摊成 COM 对象树（IRawElementProviderSimple/Fragment/FragmentRoot，Navigate 按 parent 关系、RuntimeId、BoundingRectangle、ElementProviderFromPoint），**五 pattern 按角色挂**（Invoke=按钮、Toggle=勾选/开关/单选、Value=输入/下拉、RangeValue=滑杆/进度、ExpandCollapse=下拉）；动作侧不碰组件闭包——只压「点一下」进动作队列，MoonBit 每帧抽走合成指针点击（Down+Up 走与真实点击同一条 `route_pointer`）；Value/RangeValue 的 SetValue 如实回 E_NOTIMPL（文本与值都在组件闭包里，桥不装能写）；GUID 取法定案：SDK 头声明 + 链接期取 `uiautomationcore.lib` 符号（同 WIC/uuid.lib 套路），BSTR 走 UTF-8→UTF-16；NVDA + Accessibility Insights 真机清单归用户。快照表进程级单表是已知边界（多窗应用读到最后绘制那扇窗的树），✅ **Linux AT-SPI 桥已落**（2026-11-04，`gui/shell/atspi.mbt`）：第三总线连接（会话总线 GetAddress 取址）+ Socket.Embed 注册 + 对象树（应用根→窗口根→控件按 id 稳态寻址）四接口 Accessible/Component/Text/Value + Action 点击动作（压跨平台动作队列）+ 事件上行（ChildrenChanged/Focus/StateChanged 广播）；协议签名按 at-spi2-core 2.52 实物 introspection 与 libatspi 解码端源码双核（坑清单三条未核项全部实证回填）；本机真总线端到端验过（注册/遍历/属性/几何/字符口径文本/值/动作/事件全通），Orca 真机清单归用户；断线自愈重连后按唯一名核对重新 Embed（`atspi_tick` 每拍核对 `dbus_a11y_unique_name`/`dbus_a11y_alive`，不符回 Idle 重走注册，重注册后补发一次 ChildrenChanged，纯函数判据进 wbtest）；快照 TSV 往返修两处解析缺陷（小数累积错位、`%.10g` 科学计数法致整行静默丢失）并放大读缓冲至 4096（最坏行 ≈1000B，canary 钉住）；✅ **VoiceOver 真机首测反馈批（2026-11-04）**：mac AX 元素改按 widget id 稳定缓存（每帧现建让属性查询全回 CannotComplete、读屏只剩窗标题可念）；读屏焦点通道补 `focus_id`→`w.id` 换算（两套编号没对齐，Tab 不跟随）；`ui.text` 构造即写 `label`（此前只靠 relabel 信号变化写回，静态文本正文恒空）；mac 桥 label/value 分通道（控件念 description、静态文本念 value、滑杆/进度/步进/下拉念 value 槽——百分比此前从未出桥）；`menu_item`/菜单组标题/`rate` 挂语义面（裸 widget 整批念「group」），rate 补方向键增减；showcase 段容器名进读屏。✅ **mac VoiceOver 真机首轮通过**（2026-11-05 用户实测：菜单项/按钮/勾选/单选/输入框朗读、Tab 焦点跟随；长描述段语义树已验证携带全文，VO 复确认随遗留批）。已知缺口：mdview 富文本段与 code_view 代码行的语义挂载未做（另批）
- ⏳ **键盘可达性**：全量控件的 Tab 顺序与可见焦点环；当前只有输入类与部分容器可达

## Linux 兼容说明

### 会话

只有下表四项随会话类型变；各桌面环境若有自己的实现，会放进起初规划的各系统包里发布。Wayland 侧出路已按 2026-11-03 调研收口（proposals/wayland-native.md）。
- **会话探针已落地**：`@sys.session_type()`（`XDG_SESSION_TYPE` 优先、回落 `WAYLAND_DISPLAY`）+ `in_wayland_session()`。X 工具族按它**显式降级**——夜间色温与窗口管理在 Wayland 会话报 `Unsupported`，不再出现「进程照起、退出码照 0、屏幕上没变化」的假成功。显示器枚举不降级，按 XWayland 虚拟屏口径读（读数确实存在，只是不代表真接的屏）。逐条预期与判错现象见 [测试文档 附录 E](../../../测试文档/测试用例.md)。

| 功能点        | X11 | Wayland | Wayland 侧出路               |
| ---------- | --- | ------- | ------------------------- |
| 全局快捷键      | ✅   | ❌       | GlobalShortcuts portal（KDE 5.27+ / GNOME 48+ 可落；portal-wlr 不做、DDE 未核） |
| 空闲检测       | ✅   | ❌       | GNOME IdleMonitor D-Bus 有精确读数口；KDE / wlroots 走 ext-idle-notify 事件近似 |
| 窗口控制、剪贴板监视 | ✅   | ❌       | 窗口管理仅 wlroots 系有协议（GNOME / KDE 无通道）；剪贴板监视 KDE/wlroots 走 data-control、GNOME 维持轮询；读写本体可用 |
| 显示器与夜灯     | ✅   | ❌       | 显示器走 mutter DisplayConfig / kscreen-doctor / wlr-output-management；夜灯 GNOME/KDE 配置 DE 夜灯、wlroots 裸 gamma；deepin 未核 |

### 桌面环境


| 功能点          | XFCE | KDE | GNOME | Cinnamon | deepin 20 | deepin 23 | deepin 25 |
| ------------ | ---- | --- | ----- | -------- | --------- | --------- | --------- |
| 系统托盘         | ✅    | ？   | ？     | ✅        |           |           | ？         |
| 通知           | ✅    | ？   | ？     | ✅        |           |           | ？         |
| 明暗与主题色读取     | ✅    | ？   | ？     | ？        |           |           | ？         |
| 壁纸读写         | ✅    | ？   | ？     | ？        |           |           | ？         |
| 默认应用 / 应用枚举  | ✅    | ？   | ？     | ？        |           |           | ？         |
| 文件管理器「打开并选中」 | ✅    | ？   | ？     | ✅        |           |           | ？         |

## 明确不做

- **Web 主面壳形态（Tauri 位）**（2026-11-02 定）：不做 webview 壳编排层——「WebView 主面 + 原生退居能力层」与本仓「MoonBit 全栈原生自绘」定位相反；主战略是**让原生 DX 与 web 持平**（模板预编译、IR 热更、dev 工具、编辑器支持四件套落地中）。需要 web 技术栈内容时走兼容方案：**gui-webview 组件填满窗口**（单子件 grow 占满，组件面已实现，browser 示例为雏形），该场景下 web 侧开发循环归前端自己的 Vite、原生能力仍经 facade 通道消费；gui-webview 作为嵌入组件的能力原样保留
- **mac 自启动换 `SMAppService` 登录项形态**：`SMAppService.mainApp` 只能注册主应用自身，而 `autostart_enable(app_id)` 是按 id 参数化的门面语义（任意 app_id、落点透明）——语义对不上，维持 LaunchAgents plist 路线（代价：系统「App 后台活动」里按可执行文件名显示、ad-hoc 签名标「身份不明」，均为本机自测可接受项）

- **macOS 四族**（Linux / Windows 有实现，macOS 明确不做）：窗口管理（要 Accessibility 授权；Linux 走 `wmctrl`）、夜间色温（CoreBrightness 私有；Linux 走 `redshift` / `xrandr`）、电源方案（`pmset` 对不上三值语义；Linux / Windows 都有）、媒体播放器枚举（无 MPRIS 对等物）。
- **Linux 工具包升级**：留守 GTK3—— 低版本兼容的保障。
- **原生控件皮肤**：不作主题化路径；按平台开关的原生兜底例外需逐条登记评审。
- **按参考实现平移接口**：接口由真实用例驱动，不为对齐而补。

## 承诺与版本

- 当前 `0.3.1`：**0.x 阶段接口仍在演进**，破坏性改动在提交信息写明并同步文档。
- 旧包 `NoahLiu/moonbit-libyue`（0.1.0–0.5.12 共 22 个版本）与 `NoahLiu/yue-media@0.1.0` 已在 mooncakes 标记废弃，理由「已更名」。
- **稳定清单与 1.0 时点待定**： 会在 moonbit 1.0 之后评估。
