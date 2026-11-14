# 路线图

MoonBit 的**跨平台桌面 GUI 框架**——一套代码直出 Windows / Linux / macOS 原生窗口，系统能力开箱即用。

## 当前状态

- **当前版本 `0.3.3`**；0.x 阶段接口仍在演进，见文末「承诺与版本」。
  - 时间：2026-11 已发 mooncakes。
  - mooncakes：MoonBit 官方的包发布仓库，`moon install` 从这里装包。
- 组件库、图表、文档视图、系统能力、媒体播放、WebView、打包与自动更新主链均已落地，三平台 CI 全绿。
- **进行中的重点**：
  - 真机验证批：新窗首帧补绘、托盘品牌图标、通知打扰档、inspector、模板工具链一批条目已合入待真机
  - 媒体硬解与解码白名单自建归档
    - 硬解：由显卡等专用硬件解码视频，比软件解码省 CPU。
    - 进度：Linux VAAPI 已通，mac / Windows 待接。
    - VAAPI：Linux 的视频硬件加速解码接口。
  - 屏读语义收尾与键盘可达性
    - 屏读：屏幕阅读器，把界面念给视障用户听的软件。
    - 进度：三平台桥已通，mdview / code_view 语义挂载待补。
  - 模板工具链「mng 全入口」
    - mng：本仓的开发者工具命令行，管新建工程、dev 热更、体检与打包发布。
    - 内容：向导壳、工程中心化、三通道分发。
  - GPU 合成后续：性能治理读数、GPU 内容画布
- 平台覆盖与 Linux 桌面环境支持面见文末「Linux 兼容说明」。

## 怎么读

每个功能点一条，行首是状态；条目只写「是什么 + 状态」，方案细节与踩坑记录在对内的方案 / 经验文档里，不在本页展开。

状态：

- ✅ **已验**：真机测试通过
- 🚧 **已合入待真机**：代码已合入，真机验证进行中；待验面写成子要点
- ⏳ **未开始**：已规划、未动工
- 「明确不做」：确定的边界，不会修改

条目格式：

- 一条只写一个功能，不合并；状态只在行首出现一次，正文不再写状态
- 需要保留的细节写成缩进子要点，一行一个事实
  - 细节包括：平台差异、边界、依赖、待验面。
- 不用括号补注；放不进子要点的细节进对内文档 proposals / experience
- 专业名词首次出现时补一条大白话解释子要点

「已实现」章收代码已完成的功能，即 ✅ 与 🚧；「已规划」章收未完成的，即 🚧 与 ⏳。

远期方向：无法抽象成跨平台的能力会按系统独立发包——windows-mbt、*DE-mbt、mac-mbt；其中 *DE-mbt 按桌面环境发布、底层封装 linux-mbt，因为 Linux 发行版差异大。

## 平台覆盖

- **Windows** · 10 / 11
- **macOS** · Apple Silicon
- **Linux** · X11 完整，Wayland 有限支持；规划测试发行版：deepin 23、25，Ubuntu 24、26，基于 GTK3
  - X11：Linux 的传统窗口显示协议。
  - Wayland：Linux 的新一代窗口显示协议，正逐步取代 X11。
  - Wayland 有限支持的原因：协议限制，详见「Linux 兼容说明」。
  - 发行版：一套打包好的完整 Linux 系统，如 deepin、Ubuntu。
  - Ubuntu 桌面环境：XFCE / KDE / GNOME / Cinnamon，四款常见 Linux 桌面环境。
  - GTK3：Linux 常用的界面工具库，本仓 Linux 侧基于它。
  - deepin 20：构建链已跑通到编译，墙在 MoonBit 工具链 runtime 的系统调用兼容性；坑与自救见[构建与运行](../guide/build.md)「低版本发行版」一节，不再占测试承诺
    - 时间：2026-10-28 首测后**移出支持目标**。

## 已实现

已经开发的功能。

### 窗口

- ✅ **创建窗口**：`mount_window` 起窗：标题、宽高、handle 回调；无窗口后端或无显示服务时返回 `None`
- ✅ **改标题**：运行期改窗口标题；`set_window_title_localized` 可让它随语言重写
- ✅ **改尺寸**：1280×720 ↔ 960×540 两档切换，切完布局照常重排
- ✅ **全屏**：切全屏与还原；全屏态下内容区跟着变大
- ✅ **最大化 / 还原**：`set_maximized` / `is_maximized`
- ✅ **无边框**：切无边框窗口；标题栏与边框消失，内容区不变形
- ✅ **显隐驻留**：`hide` / `show` 一对
  - `show` 唤回隐藏前的位置而非居中重开
  - `move_to` / `origin` 按客户区原点、物理像素互逆
  - 客户区：窗口去掉标题栏与边框后真正放内容的部分。
  - 带边框窗内部补偿标题栏与边框厚度
- ✅ **透视窗默认底让位**：`WindowHost::set_transparent_bg` 让宿主默认底给透视窗让位，关透视恢复
- ✅ **显隐事件与组合串清理**
  - `Hidden` / `Shown` 事件：真实显隐转换时发，首次显示不发
  - 隐藏拍清在途输入法组合串
  - `WindowHost::on_hidden` / `on_shown` 暴露给应用
- ✅ **多窗口**：`open_window` / `close_window` / `window_count` / `active_window` 四个门面
- ✅ **窗口句柄与主窗判定**：`wid` 取句柄、`is_primary` 判主窗
- ✅ **消息泵与每帧调度**：宿主事件循环：投递、命中、重排重绘都在这一拍里
- ✅ **窗口透明**：`set_opacity` 0–255，整窗连字一起淡
  - 无合成器时静默无效
  - 合成器：Linux 图形会话里把各窗口画面合成上屏的系统服务。
- ✅ **背景穿透**：`set_transparent_bg` 打开后控件没铺到的像素留透明，桌面从洞里透出
  - Windows 需无边框
  - mac 透明档与 GPU 档互斥已拦
  - 待验：mac 透明档真机
- ✅ **层级：普通档**：`WindowLayer::Normal`，与系统普通窗同档
- ✅ **层级：图标下**：`Desktop`，压在桌面图标之下，档内无交互
- ✅ **层级：图标上**：`DesktopWidget`，桌面小部件位，本窗照收键鼠
- ✅ **层级：始终置顶**：`AlwaysOnTop`
- ✅ **层级：面板档**：不进任务栏、不进窗口循环、所有工作区显示、普通窗口上全屏窗口下，即 dock 位
  - 工作区：Linux 桌面里可切换的多个虚拟桌面。
- 🚧 **平台原生句柄透出**：`Window::native_handle()` 返回平台裸句柄
  - 句柄是各平台窗口对象的原始指针，拿到它才能调系统原生 API。
  - Windows 返回 `HWND`，macOS 返回 `NSWindow*`，Linux 返回 `GtkWidget*`。
  - 仅逃生用，跨平台代码不得依赖
  - 待验：句柄有效性复验
- 🚧 **窗口族能力可探测**：`Window::shell_caps()` 能力探测
  - `opacity` / `transparent_bg` 等位可查
  - `set_transparent_bg` 返回 `Result` 诚实降级：前置不满足给 `Unsupported` / `Failed` 带原因
- 🚧 **新窗首帧自动补绘**：建窗后自动三拍兜底重绘，应用零接线
  - 背景：新开窗首帧落在平台映射前被丢弃导致白屏
- ✅ **窗口状态记忆**：`WindowHost::remember_geometry(app_id)` 一行接上
  - 开窗恢复上次位置 / 尺寸 / 最大化档，关窗与 `shutdown` 自动写回
  - 状态文件按平台落应用目录
  - 边界：恢复不做屏幕钳位、多窗对同一 id 只记一份
  - 待验：真机清单

### 渲染与绘制

- ✅ **渲染内建**：控件绘制全部内建，不依赖 Skia 等外部图形引擎
  - Skia：Google 的开源 2D 绘图引擎，Chrome 用的就是它。
- ✅ **Cairo 后端**：Linux 走 Cairo；与软件光栅同一份 Painter 契约
  - Cairo：Linux 常用的 2D 绘图库。
  - 软件光栅：不走 GPU、由 CPU 逐像素画图的绘制方式。
- ✅ **基础图元**：`fill_rect` / `stroke_rect` / `arc` / `fill` / `stroke` / `draw_text`
- ✅ **路径与曲线**：`move_to` / `line_to`、二次与三次贝塞尔；`draw_path(Path)` 对象直通
- ✅ **渐变**：线性渐变与径向渐变填充
- ✅ **裁剪与变换**：push / pop clip，平移缩放旋转
- ✅ **圆角与抗锯齿**：真圆弧 + 1px 抗锯齿；圆角关闭时退直角
- ✅ **线型端点与拐角**：LineCap：Butt / Round / Square；LineJoin：Miter / Round / Bevel
- ✅ **虚线**：`set_dashes(图案, 相位)`，on/off 交替、逻辑像素，空数组回实线
- ✅ **位图与图像解码**：PNG / JPEG / GIF；缩放到目标矩形
  - GIF 解码范围：首帧静图。
- ✅ **全局 alpha**：`opacity` 整层透明度，绘制期生效
- ✅ **矢量图标**：19 类图标包，不依赖字体文件
- ✅ **过渡动画**：状态桶插值：三条颜色 + 边框宽 + 圆角 + 字号 + 行高，按真实时间推进
- ✅ **macOS GIF 分帧合成**：ImageIO 逐帧合成，disposal 全档；帧号 / 时长 / 换帧口径与 Linux / Windows 一致
  - ImageIO：macOS 系统自带的图像读取框架。
- ✅ **GPU 合成**：独立模块 `modules/gui-gpu`，主包零依赖
  - 定位：可选后端。
  - 构建级下载失败即降级；运行级 dlopen 探测回退 Cairo / 纯光栅
  - dlopen：运行时按名字加载动态库的系统接口，用它探测 GPU 库在不在。
  - 整窗 present 纹理合成
  - 逐像素透明档不走 GPU
  - 方案：对内 proposals/gpu-architecture.md
- ✅ **控件级 GPU 绘制**：`RenderCtx::Gpu` 协议 + `GpuSink` 接口
  - 用途：视频 quad / 简单图形。
  - quad：GPU 绘图用的矩形面片，画面纹理贴在它上面。
  - GPU 画布控件与视频直纹理 setter 已落

### 文字排印

- ✅ **字体枚举**：系统字体列表与 `Font` 结构
  - Font 字段：族名、字号、字重、斜体。
- ✅ **字体回退**：CSS 列表口径：族名不存在就按列表往后退，全不中给兜底族
- ✅ **混排行高**：行盒高取 max ascent + max descent，混排不压字
  - ascent / descent：字符向上伸出与向下延伸的高度，行高由两者最大值决定。
- ✅ **富文本区间属性**：`AttributedText`：按字节区间设字体与颜色，后设覆盖先设
- ✅ **CJK 与 RTL 行首方向**：对齐给 `align`，方向给 `direction`，两者分开
  - CJK：中日韩文字的统称。
  - RTL：从右到左的书写方向，如阿拉伯文。
  - align 取值：Start / Center / End。
- ✅ **样式槽文本字段**：`text_align` / `white_space` / `line_height` / `text_decoration` 写入 class 即生效
- ✅ **字距**：`letter_spacing` 生效到测量与绘制，字间按设定值加宽
- ✅ **行数钳制**：`max_lines` 折行文本超行数上限时截断、末尾出 …
- ✅ **文本件口径定案**：`TextRole` 退役，角色收编为 `@style` 字阶预设
  - `class` 挂 `text_heading` 等，字号读主题字阶令牌
  - `text` / `text_dyn` 缺省折行，单行标签显式 `wrap=false`
  - 全部调用点已迁移

### 布局

- ✅ **固定尺寸**：宽高给像素值，按值排
- ✅ **百分比尺寸**：`width_percent` / `height_percent`，随容器变
- ✅ **flex 撑满**：`grow` 分配剩余空间；0 = 按内容
- ✅ **嵌套与对齐**：主轴 justify、交叉轴 align、换行 flex_wrap
- ✅ **分栏把手**：8px 把手可拖，首栏 ≥120、次栏 ≥80；拖动期靠按下捕获不丢事件
- ✅ **间距体系**：`padding` / `margin` / `gap` / `row_gap` / `column_gap`，逐边参数可覆写
- ✅ **横向滚动视口**：`scroll_view(hscroll=true)`，长代码 / 表格横滚不裁字
  - 内容宽 = max(自然宽, 视口宽)，另有 `min_content_width` 下限档
- ✅ **纵向档与跟随底部**：`vscroll=false` 只横滚不纵滚
  - `set_follow_bottom(true)` 内容变高自动贴底，手动上滚暂停、回到底部恢复
- ✅ **块级组件跟随容器宽**：`markdown_view` / `code_view` 缺省宽跟随容器、布局期重折，显式宽保留定宽口径
- ✅ **定宽折行文本按定宽落地**：高按「折行后量得」落；交叉轴不确定时仍走 max-content
  - 取法：yoga 子项基准三档。
  - yoga：本仓用的 flex 布局引擎，代码在 modules/yoga-mbt。
- ✅ **定宽沿测量链下传**：父级 stretch 钦定的交叉宽随测量逐层下传，折行文本不再被包层按「全堆叠」顶高
- ✅ **换行容器 min:auto 按定住交叉宽算**：列内可换行子项的下限按定住的交叉宽参照——一行放得下就是一行高、放不下自动长高
- ✅ **code_view 自带横向滚动**：代码行不可折，组件自带横滚视口与最长行下限，调用方不再外包 `scroll_view`
- 🚧 **web 缺省布局行为**：窗根竖排、容器交叉轴缺省拉满，与 web flexbox 同口径
  - 窗根从 Row 改 Column：页面顶层元素缺省撑满窗宽、高度按内容，占满剩余高度给 `grow=1.0`
  - `row` 缺省 `align_items` 从 Center 改 Stretch：行内子项撑满行高，与 `col` 一致；要居中显式传 `Center`
  - Stretch：flexbox 交叉轴拉齐——子项沿垂直于排列方向的轴撑满容器
  - 待验面：工具行 / 面包屑 / markdown 列表序号与表格纵向对齐观感；新建页面顶层宽度自动占满

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
  - ibus / fcitx：Linux 的两大输入法框架。
  - TSF：Windows 的输入法接入框架。
  - NSTextInputClient：macOS 的输入法接入协议。
- ✅ **输入法焦点门**：焦点控件绑定 + filter 门 + focus_in/out 同步
- ✅ **静态文本选中与复制**：`text` / `text_dyn` 的 `selectable` 档
  - 单击定位、双击选词、拖选、Shift 扩选、复制走宿主选区通道
  - `code_view` 跨行拖选与复制；`markdown_view(selectable)` 文档级跨段选中；`rich_text` 接富文本选中链
- ✅ **浮层原生档**：所在窗挂有原生子件时，六件浮层组件自动改开真窗口
  - 浮层：气泡、下拉、菜单这类浮在页面内容上方的弹出组件。
  - 原生子件：指网页区。
  - 六件浮层组件：气泡 / 下拉 / 提示 / 对话框 / Toast / 右键菜单。
  - 无边框、不进任务栏、恒在 owner 之上
  - 菜单类弹层三端不抢激活、键盘全程归 owner 触发件
  - 平台：win / mac 真机过；Linux 待复验

### 组件

- ✅ **按钮**：五变体 Solid / Soft / Border / Text / Danger，图标槽与禁用态
- ✅ **文字与链接**：五级排版角色；Link 主题色 + 悬停下划线
- ✅ **输入框**：单行、多行、密码；placeholder、只读、清空
- ✅ **输入框编辑套件**：
  - 系统剪贴板默认接通：Ctrl/Cmd+C/X/V 开箱互通，探测不可用自动降级内部槽，测试可 `use_system_clipboard(false)` 显式关
  - 单行 / 多行右键内置编辑菜单：剪切 / 复制 / 粘贴 / 全选；密码框不给复制，只读框只读档
  - 文案走 `gui.ui.edit.*`
- ✅ **步进器**：0..10 钳制；点 +/− 后中间格接焦点，可直接键盘改
- ✅ **步进器聚焦全选**：中间格聚焦即全选，打字整体替换
  - 聚焦途径：点击 / Tab / 点加减 / ↑↓。
- ✅ **步进器到界禁用样式**：触界侧按钮呈禁用档
  - 禁用档样式：fill_hover 灰底 + 次级字，光标回箭头。
- ✅ **滑杆**：轨道 + 拇指，按 step 量化
- ✅ **评分**：五角星悬停预亮、点击定值
- ✅ **下拉选择**：点字段弹候选、悬停高亮、选中打勾、可清空
- ✅ **取色器**：预设色板点选，hex 值住 Store
- ✅ **勾选与开关**：Checkbox / Radio / Switch；单选组互斥、可整组禁用
- ✅ **日期与时间**：月历、区间、日期时间；时间弹层列式步进，可开秒列
- ✅ **表单与校验**：标签右对齐 + 控件列；`validate` 规则串起来，错误文案随语言
- ✅ **标签 / 头像 / 徽标**：五种语义 Tag、四尺寸头像、数字角标与圆点
  - 角标上限：99+ 封顶。
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
- ✅ **拖出文件校验与路径归一**：
  - 三平台跳过不存在的拖出路径；全空则本机拖出失败回落应用内
  - 理由：死条目会被访达 / 资源管理器整趟拒收。
  - mac 侧路径归一化 `..` / `~` 对齐 GTK / Win32
  - Win32：Windows 的原生 C 风格系统 API 家族。
  - 原因：带 `..` 段的文件 URL 访达可拷出整个文件夹。
  - 演示载荷指仓库根真实文件
- ✅ **拖拽反馈光标**：`CURSOR_GRAB` / `CURSOR_GRABBING` 两档
  - 平台映射：Win32 IDC_HAND、GTK grab/grabbing、macOS open/closedHand
  - 拖源悬停张手、按下与拖拽全程握拳
  - 握拳来源：会话期间宿主统一给。
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

### 代码栈·编辑器与终端

- 🚧 **终端控件 `terminal`**：等宽网格 + ANSI 子集，`feed` 喂文本即可用
  - 着色 16/256/truecolor；OSC/DCS 清洗
  - OSC / DCS：终端转义序列里的两类扩展控制串，显示前要洗掉。
  - 回看缓冲、滚动条与拖选；输入全走 `on_input` 出口
  - 模型 / ANSI / 绘制 / 输入全部可无头断言
  - 待验：真机；未上 showcase
  - 另立项：PTY / 鼠标上报 / 图像协议
  - PTY：伪终端，给程序模拟一个真终端的虚拟通道。
- ✅ **分词层跨行状态与字节偏移**：`scan_line` 逐行吃行首状态、吐下一行状态
  - 块注释、三引号串、heredoc 从此劈得准
  - Token 带 UTF-8 字节偏移与编辑器同口径；mdview 围栏代码块同享
- ✅ **分词层行级增量重扫**：每行缓存状态与 token 宽，编辑后只重扫变更区间
  - 首屏只扫可视行、跳转补扫
- ✅ **代码编辑器控件 `code_editor`**：等宽 + 高亮 + 行号 + 编辑合体
  - 选区 / undo / IME / 系统剪贴板 / 纵横滚动 / 光标跟随
  - 外加查找、回车自动缩进、括号匹配高亮、当前行高亮
- ✅ **code_view 内建复制**：`copyable` 代码块右上悬浮「复制」按钮，全文写系统剪贴板；与 `code_editor` 一套几何口径并排不错位
- ✅ **文本测量宽全链浮点**：测量出参不取整、盒宽统一 ceil；win / mac 光标与字符不再错位半格

### 状态与路由

- ✅ **响应式数据**：`Store` / `Signal` / `computed`；多源合成与条件派生同一写法
- ✅ **绑定与重建**：`bind_node` 原位重建子树、`bind_label` 与各 `*_dyn` 入口
- ✅ **页面路由**：路由树、每层选中键、link 绑定、Eager / Prefetch / Lazy 三档预建
- ✅ **路由每层淘汰**：`Lru(n)` 摘树 + 整代退订，重进按 thunk 重建；只数已挂载子树，`Keep` 不参与淘汰——长会话缓存不无限长
- ✅ **样式与主题**：样式槽 + 状态桶 + 命名类；20 个颜色 token；跟随系统明暗与强调色
- ✅ **声明式层**：`Node{mount}` 地基 + L1 构造器全集
  - 位置：`ui/declarative.mbt`。
  - 旧链构造器全部到位收口
  - `cursor_group` 窗口层光标通道
  - `combo` 按键祖先链冒泡
  - `gif` 逐帧迭代

### 主题与样式

CSS 属性补全与产品原则落差的就绪度档案在对内方案 proposals/style-css-expansion.md、principles-gap.md；本节只列落地项与平台状态。

- 🚧 **设计令牌四阶**：间距阶 / 半径阶 / 字阶 / 时长阶进 `Theme`
  - 基准常量与静态间距令牌 + 运行时 getter，越界按首末夹取
  - 刻度字面量已换令牌单源
- 🚧 **背景渐变**：`background_gradient` 线性 / 径向 + stops
  - stop 颜色可用主题 token
  - view 盒子渐变优先、不足两 stop 回落纯色
  - 待收尾：半透明 stop 的后端插值口径差，待 golden 对拍
- 🚧 **每角圆角**：四角独立半径；相邻角和超边长时等比缩小
- 🚧 **每边边框**：四边独立宽与色；带圆角的 per-side 边框角部接缝诚实降级
- 🚧 **混合模式**：`mix_blend_mode` 25 式对控件与子树同帧生效
- 🚧 **overflow 裁切逃生口**：`overflow` Visible 档跳过裁切
- 🚧 **文本装饰补全**：`text-decoration` 补 line-through 与 overline
  - 零 C：不新增 C 代码，纯 MoonBit 改动。
- 🚧 **主题 JSON 加载**：`@theme.from_json(src, base?)`
  - 字段白名单校验、非法报错、缺省回落基底
  - 主题随应用分发为数据文件，换肤不碰编译
  - dev 档 `mng.toml` 支持 `theme` 键存盘即重载
- 🚧 **跟随系统默认接线**：`theme_apply_system_once`——首个窗口挂载前探测一次并应用，深色系统首次启动不再白闪
  - 持续轮询仍 opt-in
- 🚧 **深浅变体接入消费**：`theme_is_dark()` 判档 + 内置变体类注册表 + 两个消费口
  - 内置变体类：tooltip / scroll-thumb / divider-line 深档
  - `dark:` / `light:` 前缀有了真实消费者
- 🚧 **代码视图主题化**：`Token.role` 角色化 + `CodeTheme`
  - 按面板底色分深浅两套映射，色值全走语义 token
  - 缺省跟当前主题，可显式钉死
- 🚧 **主题定制示例**：`examples/theme-playground/` 独立模块
  - 覆盖：换主色 / 全量覆盖 / 持续跟随 / 类槽覆盖
  - 用例已进测试文档；待验：真机清单
- ✅ **样式全序四层**：一条链 **继承 < 默认 < 属性 < class < `style(...)`**；对外可配的布局散参数折进属性层，组件内部布局不对外样式化
- ✅ **样式层 `border_style`**：`Solid` / `Dashed` / `Dotted` 三档虚线框，线形定档、粗细定周期；通用容器与滚动视口描边即吃

### 系统能力

- ✅ **全局快捷键键名随平台**：门面回查 / 回显给平台规范名
  - mac `Cmd+…`、其余 `Ctrl+…`；`CmdOrCtrl` 别名不外泄
- ✅ **文件对话框**：打开 / 保存 / 选目录；取消返回 None
- ✅ **打开与定位**：URL 交浏览器、文件交默认程序、路径交文件管理器；不存在给 NotFound 不崩
- ✅ **剪贴板**：读写系统剪贴板文本
- ✅ **音量与静音**：读音量、设百分比、切静音
- ✅ **显示器枚举**：在线屏、分辨率、刷新率、模式列表
  - 平台实现：Linux `xrandr`、macOS CoreGraphics、Windows GDI
  - xrandr：Linux X11 的显示器配置命令行工具。
  - CoreGraphics：macOS 的底层图形框架。
  - GDI：Windows 的经典图形绘制接口。
  - 读数边界如实：`connected` 恒真、物理尺寸仅 Linux 有、`preferred` 恒 false
  - preferred 缘由：无公开信号，不拿当前档冒充。
- ✅ **系统托盘**：通知区图标 + 右键 / 左键菜单
  - 托盘：系统桌面上通知区域的小图标，点它弹菜单。
  - 平台实现：Linux SNI、Windows `Shell_NotifyIcon`
  - SNI：Linux 桌面的托盘图标协议 StatusNotifierItem。
  - 退出前逐个摘除不留僵尸图标；非正常退出仍拦不住，属 Win32 通病
  - 内置品牌单色图标随主题明暗，mac 走系统模板图自动反色
  - 待验：图标部分真机
- ✅ **空闲检测**：读系统空闲秒数
  - 平台实现：Linux X11、Windows；macOS 走 HID
  - HID：macOS 的人机接口设备框架，空闲读数走它。
- ✅ **开机自启**：写 autostart / Run 键 / LaunchAgents；查询读系统侧禁用位，系统设置里关掉的不误报
  - autostart / Run 键 / LaunchAgents：Linux、Windows、macOS 各自的开机自启登记处。
- ✅ **通知**：授权请求、同 id 覆盖即更新、按标识摘除；前台横幅走时间敏感档
  - 平台实现：macOS UNUserNotificationCenter、Linux D-Bus、Windows 托盘气泡
  - D-Bus：Linux 桌面的进程间通信总线，托盘、通知等桌面功能靠它互调。
- 🚧 **通知打扰档开放给应用**：`notify_send` 加 `urgent` 档
  - mac 映射 TimeSensitive / Active 二档；Linux / Windows 收下忽略
  - 待验：mac 观感复验
- ✅ **浏览器与编辑器历史**：Chromium 系历史与书签、Firefox 历史、VS Code 最近工作区
- ✅ **窗口管理**：枚举窗口、激活与关闭
  - 平台实现：Linux `wmctrl`；macOS CGWindowList 枚举 + AX 关闭
  - AX：macOS 辅助功能接口的简称。
  - 边界：关闭需辅助功能授权、缺失报 Denied 引导授权。
- ✅ **电源计划**：读可用计划集、读当前、切计划
  - 平台实现：Linux `powerprofilesctl`、Windows Power Scheme API、macOS 低电量开关映射降级档
  - 边界：mac 写走管理员授权。
- ✅ **夜间色温**：按百分比设色温与复位
  - 平台实现：Linux `redshift` / `xrandr`、Windows gamma ramp 直调、macOS 全屏点击穿透覆盖层
  - gamma ramp：显卡的逐通道色彩查找表，改它能让屏幕整体偏暖。
- ✅ **剪贴板监视**：变更回调
  - 平台：仅 Linux X11。
- ✅ **子进程与文件原语**：`pr_run` 带超时与输出捕获；`fsx` / `envx` / JSON 读写
- ✅ **传感器 / 蓝牙 / 磁盘**：Linux 侧硬件族只读读数
- ✅ **系统信息**：发行版、机器、内存、开机时长、桌面环境
- ✅ **应用枚举**：已装应用清单与分类
  - 平台实现：Linux `.desktop`、Windows 开始菜单、macOS `/Applications`
  - .desktop：Linux 的应用入口描述文件，桌面据此列出应用。
- ✅ **最近文件**：系统最近文件列表
  - 平台实现：Linux / Windows
  - macOS 无公开面，属平台边界不是缺口
- ✅ **壁纸与默认应用**：读写壁纸、查默认应用
- ✅ **单实例**：进程级唯一 + 唤起已有实例
  - 平台实现：Linux D-Bus 知名名、Windows 命名互斥体、macOS AF_UNIX
  - 知名名 / 命名互斥体 / AF_UNIX：分别是 Linux 总线上的注册名、Windows 的系统级命名锁、macOS 的本机套接字，都用来保证进程唯一。
- ✅ **权限基础设施**：`permission_probe` 探测 + `permission_request` 弹系统自带引导框
  - 覆盖：macOS 辅助功能 / 屏幕录制等 TCC 权限；Windows / Linux 恒 NotNeeded
  - TCC：macOS 的隐私授权机制，管辅助功能、屏幕录制这类授权。
  - 每次一弹的操作提权随各自能力批处理
  - 提权：即管理员授权。

### WebView

- ✅ **内嵌 webview**：作为原生子件嵌进界面，矩形由布局给
  - webview：嵌在原生窗口里渲染网页的浏览器组件。
- ✅ **JS 求值与绑定**：`execute_javascript` 求值回包、`on_invoke` 接网页调用
- ✅ **DOM 抓取**：正文 / 链接 / meta / 结构四项，走脚本求值取 JSON
- ✅ **自定义协议**：`register_protocol` 注册文件根，页面与样式都走协议供给
- ✅ **策略面**：新窗、权限、下载三项可切；拦截与放行即时生效
- ✅ **下载落点归应用层**：库只上报 `Download` 事件并按档位扣住待决，落判走 `respond_download(id, allow, path)`
  - Download 事件字段：id / uri / 建议名。
  - 保存框从三平台桩移进应用，browser 示例演示
  - 自动档为默认，交引擎默认落点，库内零弹框
- ✅ **崩溃恢复**：`is_crashed` 探到后重载恢复，不拖死应用
- ✅ **cookie 共享与隔离**：引擎默认共享；隔离走 pane 级 profile，库层不做同步

### 媒体

- ✅ **音频输出**：miniaudio 设备层；三端出声
  - miniaudio：单文件式的跨平台音频输出库。
- ✅ **视频解码与出帧**：ffmpeg 解码 + 帧回传；video 示例随发布包分发
- ✅ **播放器控制条**：播放暂停、进度 seek、音量、时间读数
- ✅ **控制条重排**：照成熟播放器排法——静音键并入音量组、倍速 / 缩放档位键钉宽切档不横跳
- ✅ **无头播放**：`HeadlessAudio` / `HeadlessVideo`，注入 schedule 通道自 pump
  - 无头：不开窗口、纯后台跑，供自动化测试用。
- ✅ **字幕**：内嵌轨自动读 + 外挂 SRT
  - 实现：纯 MoonBit 实现无平台门，随视频出帧走。
- ✅ **歌词**：同名 .lrc 配对
  - 实现：纯 MoonBit，无平台门。
- ✅ **实时频谱**：`pcm_tap` 旁路取 PCM 画柱
  - PCM：未压缩的原始音频采样数据。
- ✅ **倍速与逐帧**：倍速档位与单帧步进
  - 接口：`AudioPlayer::set_speed` / `VideoPlayer::set_speed` + `step`。
- ✅ **全屏三件**：双击切换 / 2.5s 收条藏指针 / 活动即恢复

### 开发体验

- 🚧 **模板 DX 补全批**：`v-for` keyed 生成器、项目级 `mng build`、`mng dev` watch 覆盖面
  - v-for 生成器：嵌套 / 缺 key 报错。
  - 项目级 `mng build`：按 `mng.toml` 一次生成全工程生产形态。
  - watch 覆盖面：模板与工程源文件增删改均并入本拍。
  - 待验：v-for 复用、新增 / 删模板重启、双形态提交
- ✅ **mngdev 库包与工具链联动**：dev 热更面进库，`mng new` 工程脚手架，`mng lsp` 保存即 regen + 类型错误回投 Problems
  - dev 热更面进库的效果：应用一行 import 替代千行复制。
  - lsp：语言服务器协议，编辑器靠它拿补全、跳转、诊断。
  - 待验：脚手架真机
- ✅ **`mng new` 面改版**：裸 `new <名字>` 即建工程、`new page` 出单页样板
  - VS Code 插件「新建页面」命令与生成码文件嵌套折叠
  - 待验：真机 / 编辑器
- 🚧 **内建 inspector v1 只读 + v2 样式回灌**：
  - inspector：内建的界面检查器面板，看控件树、读数与帧耗时。
  - v1：控件树浏览、选中行看读数与帧耗时账本
    - 数据源：吃帧尾语义快照，与屏读同源。
  - v2：样式类编辑回灌下一帧生效
  - 库包按需 import；待验：面板观感与回灌真机

### 工程与交付

- ✅ **三平台 CI**：检查 + 库测试 + 构建 + 启动冒烟，push 与 PR 都跑
- ✅ **文档站**：中英双语 VitePress 站，含教程、组件、布局、系统能力、路线图
- ✅ **文档 llms.txt**：构建时把中英文档源各聚成一份纯文本全集，给 LLM 离线消费，不跑 JS 不解析侧边栏
- ✅ **示例体积门禁**：size-gate 工作流三平台量 release+strip 可执行字节数，增量超 max(基线 5%, 128KB) 拦红；基线人工随批提交
- ✅ **场景教程**：四域 19 个「我想做 X」场景，每场景说明、可抄代码与注意事项，落 `docs/zh/howto.md`
  - 英文镜像同路径。
- ✅ **体验文档**：预构建包下载、三平台运行要求、体验点与示例页映射，落 `docs/zh/experience.md`
  - 英文镜像同路径。
- ✅ **预打包三平台五示例**：固定 Release「Binaries」
  - tag：`bin`，三平台 zip 覆盖更新。
  - Windows 随包 FFmpeg DLL；mac 随包 dylib 与 `.app`
- ✅ **真机用例与记录台**：按「应用 → 页面 → 段落」组织；用例唯一事实源是 `测试用例.md`，记录台加载 md 现算清单与计数
  - 规模：现 191 条，八个示例。
- 🚧 **示例矩阵收拢**：showcase 改名 `examples/components` 收为纯组件展示库
  - 构成：11 组件页 + GPU 画布。
  - 新增 `examples/system` 与 `examples/canvas`；`examples/hello` 改 mng 单文件入门样例
  - 文档站示例表、测试用例与 CI 路径同步
  - 待验：真机冒烟
- 🚧 **hello 交互收口与 sysmonitor 改版**：
  - hello 预设窗改开 / 关单例、接入系统主题跟随
  - sysmonitor 重排为固定六项资源菜单 + 右侧横向滚动、CPU 各核小图换行、磁盘剔虚拟设备
  - 待验：真机
- ✅ **整数类型口径 Int→Int32**：全仓公开 API 的 `Int` 收敛为 `Int32`——订阅 id、焦点 id、列表下标、组件回调参数、进程退出码等签名随之；`moon check` 零警告、库测试 1418 全绿
  - 时间：2026-11-13。
- 🚧 **组件文档与教程**：每个组件一页配图；教程给可运行最小工程
- ✅ **上手门槛**：首页最短路径；缺依赖时构建报错自带修复提示
- ✅ **贡献入口**：bug / feature 两份 issue form + PR 模板 + 双语 CONTRIBUTING
  - PR 模板含：门禁读数 + 三平台验证表。
  - CONTRIBUTING 含：目录落位、设计口径、无头与真机分工、提交与 PR 约定。
- ✅ **无头测试门面 uitest**：公开包 `gui/uitest`
  - name 定位、显式 `frame()` 并行安全、假窗无头泵、定时器可驱动可断言
  - 硬判据 `Tester::finish()`：观察点一次没跑即红
- ✅ **确定性测试时钟**：无头档专用虚拟时基 + `advance` / `settle` 门面，两会话同推程同读数，可复现
- ✅ **无头化收尾**：缺 Linux 开发包降级占位桩、探针诚实化、无字体回退、三档分工定档
  - 降级占位桩：prebuild 探不到 GTK 开发包时编 `_ph` 占位归档，纯光栅渲染可跑可测，stderr 有「已降级占位桩」提示；CI 加无 GTK 裸容器腿固化。
  - 探针诚实化：文本测量判据收紧为「真后端有值且宽大于 0」（`measure_real` 一族），没字体从假绿变真跳过。
  - 内建回退测量器：真后端不可用时按字符宽表估算尺寸的纯 MoonBit 兜底，`measure` 复合入口自动接管。
  - 内嵌字体子集：Noto Sans SC 裁剪子集随库发布，系统零字体的机器注册进 fontconfig 真量真画。
  - dragdnd 探测失败缓存：无头档每帧空探 `gtk_init_check` 归零。
  - 三档分工：无头断言归 CI、真窗冒烟归 xvfb、真机清单不变，进中英 build.md 与测试文档附录 D。
  - 方案：proposals/headless-closeout.md。
  - 平台：mac 本机 19 包全绿；Linux 既有腿真实现路径与 bare 腿占位路径待 CI 首跑，内嵌字体注册待无字体 Linux 真机复验；Windows 待链接复验。
- ✅ **mng 场景测试自动化**：编辑器类型门禁、TextMate 离线分词、真 `mng lsp` 协议会话、真 VS Code 集成、进程级应用侧五档门禁进 CI 三腿
  - TextMate：编辑器语法高亮用的词法规则格式，VS Code 原生支持。
- ✅ **应用打包 `mng package`**
  - mac：`.app` + DMG + 可选签名公证；DMG 是 macOS 的磁盘映像安装包，拖进应用目录即装。
  - Windows：NSIS setup + 签名档；NSIS 是 Windows 的安装包制作工具。
  - Linux：AppImage + deb；AppImage 是单文件免安装格式，deb 是 Debian 系软件包格式。
  - 公证：签名后交 Apple 线上核验，通过后用户打开不被拦。
- ✅ **发布与自动更新链**：
  - CI：`release-app` 现算 SHA256 生成 update.json 发 Release
  - 库侧：HTTPS 拉清单 + semver 比较 + SHA256 校验 + 平台原子替换 + relaunch
  - 组件：`update_dialog` 全态视图
  - 工具：`mng publish` 本地发布器与本地更新测试服务，mac 真机过全链
  - v1 边界：同步下载无进度与取消；Ed25519 清单签名随 v1.5
- ✅ **应用元信息单源**：`mng dev` / `build` / `package` 从 mng.toml `[package]` 生成 appmeta，版本与 id 不再手抄；使用文档见[打包与自动更新](../guide/publish.md)

## 已规划

规划内容，开发之后会移到上一章。

### 窗口

- ⏳ **窗口内按键路由补齐**：跨页切换后的按键兜底路由，避免失焦后按键进不了页
- ⏳ **窗口状态记忆·剩余面**：库侧已落，见「已实现 · 窗口」；剩 `mng new` 脚手架把可选会话恢复接进模板

### 渲染

- 🚧 **性能治理**：帧耗时分段账本与帧成本探针已落地
  - 已落地内容：局部置脏、组件级布局缓存。
  - Linux 读数判据：树不变零重排、绘制成本随规模线性
  - 增量重绘收益等 Windows / macOS 同款读数再定
- ⏳ **GPU 内容画布**：GPU 上下文嵌进界面，走 `RenderCtx::Gpu`
  - 3D / 场景图归未来 gui-3d 独立模块

### 输入与浮层

- ⏳ **浮层「点外收起」判据**：统一点外收起判定并补回归

### 系统能力

- ⏳ **显示器「首选档」**：`CGDisplayModeIsPreferred` 已不在 SDK，需找公开替代信号

### 媒体

- 🚧 **硬解**：ffmpeg hwaccel 三平台，三层回落，对外语义三档「软解 / 硬解 / 已回落」
  - 平台通道：mac VideoToolbox / Windows D3D11VA / Linux VAAPI
  - VideoToolbox：macOS 的硬件编解码框架。
  - D3D11VA：Windows 的显卡视频解码接口。
  - 默认关、显式开启；10bit 首版不做
  - 进度：Linux VAAPI 本机已跑通，首帧与软解逐字节一致；mac / Windows 待接
- ⏳ **解码白名单自建归档**：播放档 ffmpeg 从全量共享库换自编解码白名单
  - Windows 运行期 dll 从 149 MB 降到白名单量级；mac 自建脚本收白名单；Linux 走发行版不动
  - 编码器整档不做

### 模块化

- ⏳ **能力模块拆分**：sys / win / dbus / shell 拆独立模块、`native-gui` 收窄为「组件工具包 + 聚合 facade」
  - 状态：留档待动机。
  - 2026-11 曾完整落地后回退——不对外发行则单件检索面动机不成立
  - 方案与落地提交留档，动机出现即可复活

### 开发体验

- 🚧 **模板预编译编译器**：单文件组件预编译生成 `.mbt` 再走 `moon build`
  - 单文件组件：Vue 风模板 + MoonBit script 合写在一个文件。
  - v1 指令集：插值、动态属性、事件、双向绑定、条件、keyed 列表、默认 slot
  - 组件带参：props 走签名头
  - CLI 错误回映射模板行列，靠 source map，此为 DX 生死线
- 🚧 **模板热更新**：编译器旁路产出模板 IR，应用内 applier 经单实例通道原位重挂
  - IR：中间表示，编译器内部的半成品结构，热更补丁以它下发。
  - 结构 / class / 样式值 / 受限表达式亚秒
  - script / v-for / 自定义组件 / children 形回退重启并自动回到改动页
  - 项目级 dev 已落地，一条命令盯整个工作区
- 🚧 **样式类热更新**：`<style>` 规则随补丁以数据重注册命名类，类名与样式值都可热
  - 主题 token 定义改动仍走重启
  - 模板属性里的样式字面量一律编译报错；「样式进槽」编译器强制已落
- 🚧 **模板样式章**：`<style>` 段编译期摊平进命名类注册表
  - 支持：类选择器、`var(--令牌)`、`#rrggbb`、枚举关键字、flex 简写、`%` 宽高、深浅两档、`:hover/:active/:focus` 交互态、文字属性继承
  - 不做：运行时级联 / 元素与后代选择器
  - 布局属性样式化按四层全序口径；待验：Linux 真机
- 🚧 **dev 工具二进制**：本路线的 Vite 位次，`moon install` 分发
  - 子命令 `dev` / `build` / `new` / `lsp` / `--version` 就位；工具不依赖 GUI 库
  - 待验：Windows dev 唤醒真机
- 🚧 **编辑器支持**：`lsp` 子命令——诊断、补全、hover、跳转
  - hover 真实类型：经 source map 桥 `moon ide` 取编译器答案，失败回落静态
  - 跳转：页内声明 / 组件源码 / 包入口
  - VSIX 语言注册 + TextMate 着色 + 语义着色 + snippets
  - VSIX：VS Code 插件安装包格式。
  - 待验：Linux 装 VSIX 真机
- ⏳ **上游诉求**：moonbitlang native 目标 hot reload / 运行时多模块 + native 增量链接
  - 落地当天 IR 通道升格真代码热换、状态迁移层复活、回退路径消失
- 🚧 **mng 全入口：doctor 体检 + GUI 向导 + 三通道分发**：mng 从模板工具升格为项目唯一入口
  - 时间：2026-11-11 立项。
  - 裸 `mng` 状态机：环境未体检先跑 doctor，全绿写 ready 并继续，ready 有效起向导；ready 只门交互入口，子命令与 CI 永不被拦
  - **P0 doctor 体检** ✅ 三平台真机全过
  - **P1 mngui 向导壳** 🚧 已合入待真机 + 工具链文档区建区
    - 五步壳：欢迎 → 体检 → 新建 → 起 dev → 完成页；图标步未做
  - **P2 工程中心化** 🚧 已合入待真机
    - 工程面板、`mng run/check/test` 包装、`mng icons` / `mng ffmpeg-dll` 内建化
  - **prebuild 去 Python** ✅ 2026-11-13 全部切 `.mbtx`，构建不再依赖 Python；mac 本机无 python 全链构建验证过，win / linux 腿随 CI 回证
    - 切换模块：gui / gui-media / gui-gpu / gui-webview / ffmpeg-mbt / experiment
    - mbtx：MoonBit 的新式 prebuild 载体，脚本由构建工具原生执行，不再依赖外部 python。
    - prebuild：构建前自动跑的准备脚本，比如生成代码。
  - **P3 三通道分发** ⏳ 方案已定
    - 版本两轴独立、install 脚本、Gitee 镜像；修复动作第一版只给可复制命令

### 工程与交付

- ⏳ **品牌与应用图标 v1**：master 图标「月兔从应用窗口探头」+ 品牌四色落 `assets/brand/`
  - 定案：见对内 experience/brand.md。
  - 导出矩阵脚本化：macOS icns / Windows ico / Linux png / favicon / 文档站 logo。
  - 待验：应用图标替换真机
- ⏳ **应用打包管线·剩余面**：安装卸载观感真机清单、签名公证真机复验
  - 自定义证书入口已留 `[package.sign]`
- ⏳ **自动更新·剩余面**：异步下载执行器、Ed25519 清单签名、增量更新
  - 异步下载执行器：进度 / 取消，随平台线程批。
  - Ed25519 清单签名随 v1.5。
  - 增量更新随 v2。
- ⏳ **桌面登记面·剩余面**：
  - 基础键已随打包落：`StartupWMClass` / `CFBundleDisplayName` / Maintainer 可配
    - `StartupWMClass` 与 `CFBundleDisplayName`：分别让 Linux 按窗口认回应用、macOS 显示应用名。
  - 剩：深链 scheme、文件关联、最近文档写侧——登记声明进 `mng.toml`、打包器落各平台清单、唤起事件经单实例通道回投
    - 深链：点 `myapp://路径` 这类链接直接唤起应用。
- ⏳ **稳定面清单与 1.0 时点**：逐包划分承诺面 / 实验面，公告破坏性改动截止线；在 moonbit 1.0 之后评估
- ⏳ **CPU/GPU 像素对拍与无头像素快照基线**：同一套比对器两用——快照基线管「跨版本不漂」、对拍管「GPU 路径与纯光栅逐像素一致」
  - 容差与基线治理判据立项时定
  - 工作量大于门面本体，单独立项

### 示例与文档

- ⏳ **dev 工具独立示例**：模板 Dev 对照页与检查器演示页随示例收拢出清，库包仍在 `gui/inspector`、`mngdev`，待建独立 dev 工具示例承载
  - 前提：验收后。
- ⏳ **示例第二批拆分**：components 的「GPU 画布」页拆出独立示例，components 只留纯组件页
  - 前提：验收后。
- ⏳ **mng 逐示例迁移**：hello 已转 mng 单文件形态；其余示例按「演示价值 ÷ 迁移成本」逐个评估
  - 优先：system 与 canvas。
- ⏳ **browser / audio / video 去留终裁**：三示例依赖 gui-webview / gui-media，当前保留在仓与预编译发布面；去留与打包面在验收后定

### 可访问性

- 🚧 **屏读语义**：控件挂 role / name / state，接 macOS NSAccessibility、Linux AT-SPI、Windows UIA provider
  - NSAccessibility：macOS 的无障碍接口，屏幕阅读器靠它读界面。
  - AT-SPI：Linux 的无障碍接口协议。
  - UIA：Windows 的无障碍接口框架，全名 UI Automation。
  - MSAA：Windows 老一代无障碍接口，本仓不做。
  - 帧尾语义快照与三平台桥已落，首批组件语义挂载完成
  - mac VoiceOver 真机首轮通过
  - VoiceOver：macOS 自带的屏幕阅读器。
  - 待跑：Windows NVDA / Linux Orca 真机清单
  - NVDA：Windows 的免费屏幕阅读器。
  - Orca：Linux 的屏幕阅读器。
  - 已知缺口：mdview 富文本段与 code_view 代码行的语义挂载，另批
- ⏳ **键盘可达性**：全量控件的 Tab 顺序与可见焦点环；当前只有输入类与部分容器可达

## Linux 兼容说明

### 会话

只有下表四项随会话类型变；各桌面环境若有自己的实现，会放进起初规划的各系统包里发布。Wayland 侧出路已按调研收口，对内方案 proposals/wayland-native.md。

- **会话探针已落地**：`@sys.session_type()` + `in_wayland_session()`
  - X 工具族按会话类型显式降级——夜间色温与窗口管理在 Wayland 会话如实报 `Unsupported`，不再出现「进程照起、屏幕没变化」的假成功
  - 显示器枚举不降级，按 XWayland 虚拟屏口径读
  - XWayland：在 Wayland 会话里兼容跑 X11 应用的转译层。
  - 逐条预期与判错现象见测试用例文档附录 E

| 功能点        | X11 | Wayland | Wayland 侧出路               |
| ---------- | --- | ------- | ------------------------- |
| 全局快捷键      | ✅   | ❌       | GlobalShortcuts portal，KDE 5.27+ 与 GNOME 48+ 可落，portal-wlr 不做、DDE 未核 |
| 空闲检测       | ✅   | ❌       | GNOME IdleMonitor D-Bus 有精确读数口；KDE / wlroots 走 ext-idle-notify 事件近似 |
| 窗口控制、剪贴板监视 | ✅   | ❌       | 窗口管理仅 wlroots 系有协议，GNOME / KDE 无通道；剪贴板监视 KDE/wlroots 走 data-control、GNOME 维持轮询；读写本体可用 |
| 显示器与夜灯     | ✅   | ❌       | 显示器走 mutter DisplayConfig / kscreen-doctor / wlr-output-management；夜灯 GNOME/KDE 配置 DE 夜灯、wlroots 裸 gamma；deepin 未核 |

- portal：Linux 桌面的统一能力代理服务，应用经它申请全局快捷键、屏幕截图这类受限能力。
- wlroots：构建 Wayland 合成器的常用底层库，泛指基于它的那系桌面。
- DDE：deepin 自带的深度桌面环境。
- mutter：GNOME 的窗口合成器。
- kscreen-doctor：KDE 的显示器配置命令行。

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

- **Web 主面壳形态·Tauri 位**：不做 webview 壳编排层
  - Tauri：用系统 webview 装网页前端的桌面应用框架。
  - 「WebView 主面 + 原生退居能力层」与本仓「MoonBit 全栈原生自绘」定位相反；主战略是**让原生 DX 与 web 持平**
  - 需要 web 技术栈内容时走兼容方案：gui-webview 组件填满窗口，web 侧开发循环归前端自己的 Vite、原生能力仍经 facade 通道消费
  - gui-webview 作为嵌入组件的能力原样保留
- **mac 自启动换 `SMAppService` 登录项形态**：只能注册主应用自身，与按 id 参数化的门面语义对不上，维持 LaunchAgents plist 路线
  - SMAppService：macOS 新式的登录项注册接口。
  - 代价：系统设置按可执行文件名显示、ad-hoc 签名标「身份不明」，本机自测可接受
  - ad-hoc 签名：没有开发者证书的临时签名。
- **macOS 四族**：Linux / Windows 有实现，macOS 明确不做
  - 窗口管理：要 Accessibility 授权；Linux 走 `wmctrl`
  - 夜间色温：CoreBrightness 私有；Linux 走 `redshift` / `xrandr`
  - 电源方案：`pmset` 对不上三值语义；Linux / Windows 都有
  - 媒体播放器枚举：无 MPRIS 对等物
  - CoreBrightness：macOS 管屏幕色温的私有框架。
  - MPRIS：Linux 桌面的媒体播放器控制标准接口。
- **Linux 工具包升级**：留守 GTK3——低版本兼容的保障
- **原生控件皮肤**：不作主题化路径；按平台开关的原生兜底例外需逐条登记评审
- **按参考实现平移接口**：接口由真实用例驱动，不为对齐而补

## 承诺与版本

- 当前 `0.3.3`：**0.x 阶段接口仍在演进**，破坏性改动在提交信息写明并同步文档
- 旧包 `NoahLiu/moonbit-libyue` 与 `NoahLiu/yue-media@0.1.0` 已在 mooncakes 标记废弃，理由「已更名」
  - 版本范围：0.1.0–0.5.12 共 22 个版本。
- **稳定清单与 1.0 时点待定**：在 moonbit 1.0 之后评估
  - 见「已规划 · 稳定面清单与 1.0 时点」。
