# 平台适配·Windows专有

收 Windows 专有的实测坑与口径：Win32 窗口 / 托盘 / 任务栏、OLE 拖放、WebView2、MSVC 链接与 manifest、UIA 无障碍、W 系列批次与 Windows 真机反馈。

### MoonBit 原生 GUI 栈 · 系统能力桩的 Windows 分支（W14：文件 / 环境变量 / 子进程 / 文件对话框）

- **第三方 `chensuiyi/subproc` 只能弃用,且主分支早就弃了**:该包自述就是「Synchronous **Linux** process management」,靠 pidfd/procfs/poll 这些 Linux 专有机制——本机 `.mooncakes/chensuiyi/subproc/src/native.c:7` 在 MSVC 下 `fatal error C1083: 无法打开包括文件 poll.h`,于是 `sys` 连同下游(chart/ui/examples/native-app)整条链在 Windows 连编译都进不去。注册表另一候选 `trkbt10/subprocess` 只覆盖 Unix/macOS 子进程(Windows 侧仅 IPC socket),同样不够。**改法:平移 master 已验的三平台实现**(master 的实现走自有 C 桩 `proc_spawn/proc_wait/proc_getpid`,零第三方依赖),移植进 `sys/sys_stub.c` 的 C 形态,符号名 `yue_sys_proc_*`,语义逐位对齐:POSIX 分支 Linux/macOS 共用(`fork`→`setsid`/macOS `setpgid`→`dup2` 临时文件→Linux `execvpe`/macOS `execvp`+`*_NSGetEnviron`,失败 `_exit(127)`、`chdir` 失败 `_exit(126)`);Windows 走 `CreateProcessW`+`CREATE_NO_WINDOW`、`STARTF_USESTDHANDLES` 挂可继承句柄、环境块按名排序双宽 NUL 收尾、空块＝继承父环境。**关键设计差别:只回 pid 不回句柄**,Windows 侧 `wait` 用 `OpenProcess(SYNCHRONIZE|TERMINATE|QUERY_LIMITED)` 按 pid 取,句柄用完即关——省掉一张跨调用句柄表和它的泄漏风险(原计划「返 hProcess + `proc_drop`」作废)。
- **`__uuidof` 在 MSVC 的 C 模式里不存在**:`CoCreateInstance(&CLSID_FileOpenDialog, ...)` 若写成 `__uuidof(FileOpenDialog)` 直接 `error C4233: 使用了非标准扩展: 此关键字只在 C++ 中支持`(SDK 头里的 coclass 声明是 C++ 专属)。C 侧只能取头文件里的 `extern const GUID` 常量(`CLSID_FileOpenDialog`/`IID_IFileDialog`/`IID_IShellItem`),这些符号由 **uuid.lib** 提供,故 `scripts/prebuild.py` 的 Windows 分支给 `sys` 下发 `ole32.lib shell32.lib uuid.lib`(MSVC 位置参数口径,`-l` 会报 D9002)。
- **UCRT 没有 `_getwcwd`**:看着像宽字符版 getcwd,实则 SDK 全无声明——MSVC 只给 `warning C4013: 未定义; 默认外部返回 int`,把返回的 `wchar_t*` 截断成 int 再当指针用,是「能编过但必崩」的形态。取工作目录改 Win32 的 `GetCurrentDirectoryW`(两趟:长度 0 问大小,再取串)。
- **环境变量必须宽字符,且 Windows 没有「存在但值为空」这一档**:`getenv`/`_putenv_s` 是 ANSI 版,按进程 ANSI 代码页(本机 936)来回转,UTF-8 中文值写进去读出来是「鍊糀」——`sys/envx_wbtest.mbt` 当场抓到。改 `GetEnvironmentVariableW`/`_wputenv_s`(长度 0 先问大小)。顺带一条语义差:Windows 里 `_wputenv_s(name, L"")` **就是删除**,所以 `envx_get(name)` 空值写入后为 `None` 而非 `Some("")`,测试按平台分档断言。文件同理:路径一律 UTF-8 进、宽字符 API 出(`FindFirstFileW`/`_wfopen`/`_wremove`),A 版在中文用户名目录下直接错位。
- **`ShellExecuteW` 的成功判据是返回值 >32**:它返回 HINSTANCE 语义的旧式状态码(≤32 是 `SE_ERR_*`),`>32 ? 0 : -1` 才对;`open` 动词自带系统关联(URL 走默认浏览器、文档走关联程序),正对应 POSIX 分支 `xdg-open` 的角色。
- **占位分支里「与图形无关」的落盘必须真实现**:`render/stub.c` 的非 Linux 分支原把 `fsw_write_file` 写成 `return 0`(占位保链接),而 PNG 编码本体在纯 MoonBit 的 `png.mbt`,只差这一次写盘——结果 Windows 上图表导出 `ci_save` 恒 `WriteFailed`。判据:占位只该覆盖「该平台还没实装的后端能力」,标准 I/O 这类无后端依赖的不该跟着占位。
- **测试的平台分流(三条)**:①`/tmp` 在 Windows CRT 里是「当前盘根目录下的 tmp」,目录不存在就写失败,临时文件路径要按平台取 `%TEMP%`/`$TMPDIR`(且分隔符随平台);②cmd 系输出行尾是 `\r\n`,断言 `echo` 结果不能写死 `\n`;③**从 Git Bash 起测试时 PATH 里有 `/usr/bin/*.exe`(`echo`/`cat`/`sleep`/`true`),POSIX 命令名「看着能跑」掩盖了实现差异**——从 cmd 起就全灭,故回环一律经平台分流(POSIX `sh -c`,Windows `cmd /c`)。Unix 惯例专属的断言(命令不存在退 127、子进程自发 SIGTERM、固定 `LC_ALL=C`、`/etc/hostname`)只在 POSIX 侧跑,Windows 侧给等价断言(`CreateProcessW` 找不到可执行文件直接 `SpawnFailed`)或打印跳过。
- **没有文字层时自绘控件塌成 0 尺寸**:纯光栅器平台上 `@text.measure` 给 `None`,`attach_text_measure` 的退化值是 `(0.0, 0.0)`,于是「宽度随文本」的按钮/标签/链接既测不出宽也点不中——`ui` 有 20 条断言是这一类。处理口径:测试层加**运行时探针**(`ui_text_guard()` 试测 `"Ag"`、`ui_decode_guard()` 试解一张 GIF),探不到就打印跳过、其余断言照跑,等 W5(DirectWrite)/W9(WIC)落地自动复绿;`theme` 的「控件高度基准」同一处理。不在库里塞估算宽度:那是静默假数据,与「探测 + 语义化降级」的定案相悖。
- **验证方式**(Windows 10 19045 + MSVC 14.44 + SDK 10.0.26100,moon 0.1.20260920):`moon test -p sys` **163/163**(subproc 摘除后该包在 Windows 首次可编可跑)、chart 189/189、ui 110/110(20 条按探针跳过)、theme 8/8、core 70、render 43、input 10、mdview 26、icons 4 全绿;逐包 `moon check --deny-warn` 零警告、`moon check ./examples/native-app --deny-warn` 通过(此前被 subproc 挡在依赖阶段)、全仓红点 287 errors/68 warnings 与基线持平;`text` 在 Windows 仍红,属 W5 范围(断言分「结构性共用/数值平台基线」两档改造随那一批做)。真窗口下的文件对话框观感(IFileDialog 的过滤项/多选/初始目录)留使用者复验。

### MoonBit 原生 GUI 栈 · 批 A 多窗宿主的 Windows 跟进（W15：槽位复用 + wm_init 幂等）

- **批 A 只修了 GTK 分支,同一条缺陷在 Windows 还在**:d1fb1e8 把 `win/stub.c` 的 GTK 分支 `wm_window_new` 改成扫 `area == NULL` 复用槽位,`_WIN32` 分支(同一函数的另一条路)仍是 `wm_next_id++`——附窗反复开合会吃光 32 槽并让 `open_window` 静默返回 `None`。修法照 GTK 逐字对齐,判据换成 `hwnd == NULL`(建窗成功必设、`wm_close` 里 memset 清零,拆过的槽与没用过的槽同样可取)。
- **真正拦住多窗的是 `wm_init` 不幂等**:`app_window()` 每开一扇窗都调一次 `@win.init_backend()`,而 Win32 的 `RegisterClassExW` **同名类重复注册返回 0**(`ERROR_CLASS_ALREADY_EXISTS`)——于是第一次成功、第二次起就返回「后端不可用」,`App::open_window` 在 Windows 上永远给 `None`(主窗反而是第一次调用,所以单窗示例一直正常)。修成「waker 窗口已在则整段直接返回 1」并把 `ERROR_CLASS_ALREADY_EXISTS` 视为成功。GTK 分支用 `gtk_init_check`,它本来就幂等,所以这条只在 Windows 露出来——**「一条路径两次调用」是批 A 引入的新形状,单窗时代的所有冒烟都测不到它**。
- **回证方式(探针包 `experiment/multiwin_probe`)**:①建-拆 40 轮(> 桩的 `WM_MAX_WINDOWS=32` 上限)仍建得出,`opened=40 failed=0`;探针**只建不 show**,于是 40 次建拆不在桌面闪窗。②两轮「开附窗→泵 60ms→关掉它」,打印 `sub_wid/primary/active_is_sub/count` 与 `before/after/main_running`,证明多窗宿主在真有两个 HWND 时派发仍然成立:新窗即当前窗(`active_is_sub=true`)、`primary=false`、关附窗后主窗 `running=true` 且在窗数回落。③收尾 `MULTIWIN-DONE` 行 + 退出码 0。跑法 `moon run experiment/multiwin_probe`;无显示服务打印 `MULTIWIN SKIP`。真窗观感(两窗互相遮挡/拖动重绘、附窗里的 preedit)仍留使用者复验;`examples/native-app` 在 Windows 的启动冒烟回证 `NATIVE-APP-MW wins=1 ... ` 与退出码 0(按钮点击需要注入,归 W7)。
- **顺带补的口径**:`_WIN32` 分支调用 `snprintf` 却没引 `<stdio.h>`,MSVC 只给 `C4013 隐式声明;假定外部返回 int`——与「UCRT 无 `_getwcwd`」同形的静默坑,补头后本桩单编零警告。

### MoonBit 原生 GUI 栈 · 历史族的三平台数据根（W14e，平移 master 现成分支）

- **不新写,从 master 平移**:浏览器历史/书签/SQLite 侧的 Windows 数据根分支在 `origin/master` 是现成的(`bh_browser_defs_win`/`bh_mac_root`/`bh_root_win`),本分支当年平移时只带了 Linux 的那一份,于是 `bh_supported`/`bm_supported` 被写成「仅 Linux」。做法与 W14b 同:先查主分支有没有,有就搬。
- **三平台只差数据根与目录名,逻辑共用**:Linux=`XDG_CONFIG_HOME` 否则 `$HOME/.config`;Windows=`%LOCALAPPDATA%`,且 Chromium 系的 profile 在其下 `<厂商>/<产品>/User Data` 再下一层(比 Linux 多 `User Data` 这一层,目录名大小写随安装器,如 `Google/Chrome/User Data`、`Microsoft/Edge/User Data`);macOS=`$HOME/Library/Application Support/<厂商>/<产品>`(没有 Windows 那层 User Data)。profile 候选名(`Default` 与 `Profile 1..24`)、目录枚举查 `History`/`Bookmarks` 条目、SQLite/JSON 解析三平台同一条路径,所以只有定义表 `bh_defs()` 与根定位按平台分流。
- **回证方式(Windows 真机,本机装有 Chrome/Edge)**:`bh: profiles=2 items=5` 与 `bh: downloads=3` 是**真读到本机浏览器库**的读数(此前这条在 Windows 上被平台门恒跳过),`bm_bookmarks` 端到端解析同样从「skip」转真跑;`moon test -p sys` 163/163、`moon check ./gui/sys --deny-warn` 与 `./examples/native-sys --deny-warn` 零警告。测试侧一条旧断言 `bm_supported() == (platform=="linux")` 随之改成三平台口径。
- **口径提醒**:`fsx_list_dir`/`sys_read_text_file` 走的是本批刚补的宽字符路由,所以中文用户名目录(`C:\Users\张三\…`)下的浏览器库同样读得到——这条是 W14a「路径一律 UTF-8 进、宽字符 API 出」的直接后果。

### MoonBit 原生 GUI 栈 · DirectWrite 文本层（W5，Windows 文字落地）

- **`dwrite.h` 在 C 里编不了，换 C++ TU 解**：`DWRITE_MAKE_OPENTYPE_TAG`/`DWRITE_MAKE_FONT_FEATURE_TAG` 用 `static_cast` 展开进枚举初值，C 模式直接一串 C2275/C2065（实测）；两条路——手工声明 COM 接口（vtable 顺序错一处就崩，弃）或换 C++ 编译单元。**moon 的 native-stub 认 `.cpp`**（探针实测：extern "C" 函数往返成功），于是平台分工定型：`stub.c` 的 Pango 分支（prebuild 带 `-DWM_STUB_PANGO`）+ `stub.c` 的占位分支（macOS 等）+ `dwrite_text.cpp`（Windows，native-stub 编，dwrite.h 直接可见）。链接输入由 prebuild 给 text 包下发 `dwrite.lib d2d1.lib ole32.lib uuid.lib gdi32.lib`。**非 Windows 侧这份 `.cpp` 编出空翻译单元**，故 Linux/mac 的构建链要有 C++ 前端（老链路 shim 就是 C++，本仓环境具备）。
- **行盒取「单字布局的行度量」，不取字体设计度量**：实测 14px 缺省族 DWrite 的布局行高是 19（= 字体 ascent+descent+lineGap 按整像素），按设计度量自己算是 17；更坑的是族名空串时若从集合里取**首族**（不是系统缺省族）会差出两 px——而「行盒要盖得住绘制高度」的混排行高断言吃的就是这个数。修法：`pt_font_line_height` 现搭一份 `"M"` 的布局、读 `DWRITE_LINE_METRICS`（height/baseline），与 `measure()`、绘制三条路自洽（LH14=19 与 M14.h=19、基线 15 对齐）。
- **族名表排序用字节序**：MoonBit 侧断言严格递增走 `lexical_compare`（字节序），而 DWrite 的集合顺序随装载变化——C 侧 qsort 用 `strcmp`（与 Pango 侧 `g_strcmp0` 同口径），相邻**完全相同**才去重；族名取 0 号 locale（en-us），故主题里钉的 Windows 族名用英文（"Microsoft YaHei"）。
- **`GetLineMetrics` 两段式在 Win11 26100 失效 → 行盒全空**：先 `GetLineMetrics(nullptr, 0, &count)` 取行数、再按该行数 `GetLineMetrics(lms, count, &count)` 复取，行数能查到（3）但第二段拿不到数组，`rt_line_box` 全失败、富文本行盒 0 行（`attributed_sel_wbtest` 在 Windows CI 报「盒宽 200 没折出多行（行盒 0 行；rt h=1 count=3；测量宽 196 高 56）」——同平台的 `measure_font` 折行正常，说明只是这条查询姿势坏了）。修法：一次给足栈容量（64 行）调 `GetLineMetrics`，超过再按实际条数扩容；顺带修掉原实现 `free(lms)` 之后再读 `lms[line].height` 的 use-after-free。

- **`HitTestTextPosition` 的 metrics 出参必须给真指针**：第 5 参（`DWRITE_HIT_TEST_METRICS*`）在旧版 DWrite 上给 `nullptr` 能过，Win11 26100 起改成无条件写这份结构——`movups [r10],xmm0` 且 `r10=0`，直接 0xc0000005（2026-11-11 Windows CI 白盒测试崩溃，cdb 转储栈顶就是 `DWrite!DWriteTextLayout::HitTestTextPosition+0x21`；moon 报的「active test」是下一条用例开始前，别被标签带偏）。`rt_line_box`/`rt_caret_x` 两处原先传 `nullptr`，改为栈上 `DWRITE_HIT_TEST_METRICS hitm = {}` 并忽略内容。**排查代价记档**：带调试器单跑那条用例复现不出来（cdb 下干净退出），必须用 procdump 守候整套 `moon test ui` 抓转储才能看到真栈。

- **区间下标要换 UTF-16 码元**：MoonBit（与 Pango 分支）的区间口径是 **UTF-8 字节下标**，DWrite 的 `DWRITE_TEXT_RANGE` 吃宽字符下标——不换的话多字节文本的区间落到界外被静默吞掉（「字节下标：切在字节上」那条断言就是红的）。换算 = `MultiByteToWideChar` 数前缀长度。
- **绘制 = D2D 的 DC 渲染目标 + 32bpp DIB + 预乘 over**：同一份 `IDWriteTextLayout` 先画进 DIB（`Clear` 成透明底、反锯齿固定灰度档——ClearType 是次像素渲染，落在透明底会出彩边），再按 `out = src + dst·(1−srcA)` 逐分量合进 MoonBit 缓冲（ARGB32 小端与 DIB 同布局，无需换序）。区间颜色必须在渲染目标上建画笔（D2D 画笔是设备相关对象）再 `SetDrawingEffect`，所以颜色只在绘制那一趟快照；盒内对齐照 Pango 的 `pt_render_box` 规则：有宽约束时宽与对齐交给布局，单行不省略时自己算 slack 偏移，垂直同理。
- **纯后端没有 cairo 会话：文本走「离屏 + blit」**：`draw_box_at`/`AttributedText::draw_at` 在 `cairo_id()==None` 时把文本先画进自有离屏位图（`pt_draw_box`/`rt_draw` 的缓冲版），再经 `Raster::blit` 落位——平移/裁剪/混合模式都由 blit 现算。
- **顺手修掉 `Raster::blit` 的一个真 bug**：它把 `rect_device` 给的「已是设备坐标」的矩形再乘进 `mt` 又复合 CTM → CTM 被计两次，带 `translate` 的会话里源采样落到源矩形界外，**一个像素都落不下来**（实测 ink=0，且无 transform 时正常所以一直没暴露）。修法：`mt` 建在用户空间（`e/f` 取用户 `dx/dy`），设备矩形只用于扫描窗。修后 render 43/ui 110/chart 189 全绿。
- **行高 K 地板定案落地**：`line_height = max(引擎自然, ceil(size×K))`，**K=1.36** 实测自本机雅黑 12..32px 的自然比上界（1.29..1.36，最肥一档 14px→19）；混排行盒用行内最大字号取地板；升距（基线）不动，地板顶起的余量由绘制的盒内垂直居中吸收（观感即半行距）。两条按「纯自然行高」写的白盒断言（family_wbtest）随口径更新。
- **缺省字族按平台探进主题**：`@theme.default_font_family()` 探到 "Microsoft YaHei" 就用（进程级缓存），探不到交回引擎缺省（Linux fontconfig / macOS CoreText）；`ui` 的 `role_font` 统一走它。
- **验证**（Windows 本机）：text **29/29**（此前 8/29）、render 43、ui 110（20 条文字/解码探针自动转真跑）、chart 189、theme 8、mdview 26、core 70 全绿；native-app 启动冒烟读数行齐、退出码 0；逐包 `--deny-warn` 零警告；全仓红点 287/68 持平。**计划里「text 断言分结构性/数值两档」实测不必要**：29 条都是「与同平台自己的测量比」的自洽断言，两平台各自全绿（记档以免后人再改一遍）。

### MoonBit 原生 GUI 栈 · Windows IME 纯通道（W6）

- **协议面与 GTK 分支逐条对齐**：commit/preedit 都是 UTF-8 字节流（容量 255，超了截断）、`preedit_caret` 也是字节偏移、读完 commit 要 `commit_done` 清零；`WM_IME_COMPOSITION` 里 `GCS_RESULTSTR` → commit（进文本状态），`GCS_COMPSTR` → preedit（只供自绘，绝不进文本状态）。
- **三条平台差异（都是实测/接口事实）**：① `WM_IME_SETCONTEXT` 必须滤掉 `ISC_SHOWUICOMPOSITIONWINDOW`——本栈 preedit 是自绘的，不滤掉系统会在窗口上再叠一份自己的组合窗（重影）；② 组合串光标 `GCS_CURSORPOS` 是**字符偏移**，而 MoonBit 侧口径（与 GTK 一致）是 UTF-8 **字节偏移**，要按前缀 `WideCharToMultiByte` 换算，不换则中文组合串的光标位置全错；③ legacy IMM32 **没有 surrounding-text 接口**（那是 TSF 的），`wm_im_set_surrounding` 只能空操作——GTK 侧喂「已提交文本」是为了让 IM context 推断上下文，Windows 的 IME 从自身组合状态取上下文，两平台语义在此分叉（记档，不在 MoonBit 层做假接口）。
- **光标与候选窗**：`wm_im_set_cursor` 存矩形并在 `WM_IME_STARTCOMPOSITION` 时复喂一次（有些 IME 只在这时读位置）；`ImmSetCompositionWindow(CFS_POINT)` 与 `ImmSetCandidateWindow(CFS_CANDIDATEPOS)` 都贴光标**底边**（`y + h`），候选窗贴组合串末尾的惯例由此成立。`wm_im_reset` 走 `ImmNotifyIME(NI_COMPOSITIONSTR, CPS_CANCEL)` **并清本侧 preedit 缓存**——reset 后 IME 不一定再推组合消息，旧串留在缓存里会被继续画出来（GTK 侧同一条教训）。
- **回证**：探针 `experiment/ime_win_probe`（建窗 → 报插入符矩形 → reset → 读 commit/preedit → 泵 30 轮消息 → 干净退出）读数如预期（commit=none、preedit 空）且零崩溃；`experiment/multiwin_probe` 与 `examples/native-app` 冒烟在 WndProc 加消息分支后仍全绿（退出码 0）。**真实拼音的端到端**（preedit 下划线观感、候选窗位置、commit 落进焦点框）需要注入键入，归 W7 的 SendInput 探针与使用者真机复验——本机已装微软拼音（zh-Hans-CN，唯一 IME），路径可行。

### MoonBit 原生 GUI 栈 · 系统剪贴板（W16）

- **能力落 `sys`（新 `clipboard.mbt` + `sys_stub.c` 的 `_WIN32` 分支）**：Windows 走 `CF_UNICODETEXT`（`OpenClipboard`/`GetClipboardData`/`GlobalLock` 读，`GlobalAlloc(GMEM_MOVEABLE)`+`SetClipboardData` 写——**成功后所有权归系统，绝不能 `GlobalFree`**，这是 Win32 剪贴板的经典坑）；Linux/mac 走命令线（`xclip -selection clipboard` / `pbcopy`·`pbpaste`）。中文内容必须走宽串（`win_utf8_wide`）+ 宽→UTF-8，A 版 API 按 ANSI 代码页会把内容搅乱（同 W14 的环境变量一条）。
- **命令线传文本要绕开引号地狱**：`pr_run` 不做 shell 解析，所以显式 `sh -c 'printf %s "$1" | xclip -selection clipboard' sh <文本>`——文本走 **argv 的第 4 个位置**（脚本里的 `$1`），不拼进脚本体，引号、换行、中文都无需转义。
- **链接面漏过一处**：剪贴板 API 在 **user32.lib**，而 sys 包原先的 Windows 链接参数只有 `ole32.lib shell32.lib uuid.lib`——漏了就是 `LNK2019: __imp_SetClipboardData` 一串，已补（记档：Windows 侧每引一组新 API 都要核对它在哪个 .lib 里）。
- **接线走「内核槽」而不是内核直连平台**：`input` 的 `Editor::set_clipboard(get, set)` 给内核留外部剪贴板槽——`copy`/`cut` 顺手写出去、`Ctrl+V` 现取（取不到回退内置 `clip`），内核本身仍不依赖任何平台层（无头可测）。**默认不装**：`ui` 的 `use_system_clipboard(true)` 由应用显式打开（`examples/native-app` 与 `examples/showcase` 各一行）——测试里的 Ctrl+X 不该动使用者的剪贴板；探测不可用时自动保持内部剪贴板，属语义化降级（Linux 的探测口径见「Linux 剪贴板」那条：GtkClipboard 优先，没跑过 gtk_init 的进程才退回 xclip）。
- **测试**：sys 新增回环用例（中文 + 换行的 `set → get`），**写入前把原内容存档、断言完还原**（探针不在使用者的剪贴板里留痕）；Windows 本机 `moon test -p sys` **165/165**（新增 2 条），ui 110/110、input 10/10 无回归。真跨程序粘贴（复制出去、粘到记事本再粘回来）留使用者复验。

### MoonBit 原生 GUI 栈 · Windows 窗口「黑屏 + 未响应」复盘（W17a，五处根因与性能批）

- **根因一：`wm_wait` 等完不派发**。Win32 分支 `MsgWaitForMultipleObjectsEx` 之后**没调 `wm_pump`**（GTK 分支 poll 完会调）——没人派发消息 → WndProc 永不执行 → 输入、WM_CLOSE、WM_PAINT 全部收不到。判据：窗口被系统标「未响应」、优雅关窗要等自杀计时器（实测 15.9s；修后 **0.9s**）、发 SendKeys 完全没反应。修法：等完即 `wm_pump()`。
- **根因二：`wm_present` 只存指针**。它把 MoonBit 的像素指针记账，等 WM_PAINT 时才去贴——而那是 `paint_frame` 里的**局部** Bitmap，函数一返回就是 GC 的猎物，贴出来是悬垂内存（整窗纯黑）。判据：截图整片黑、而绘制读数与几何行一切正常。修法：桩持帧拷贝（`WmWindow.frame`，按尺寸增长的缓冲），`wm_close` 释放。
- **根因三：键码口径不一致**。Win32 桩把控制字符按 GDK 约定给 `0x01000000|u`，而内核的 `KS_*` 是 X11 口径（Tab=0xFF09、回车=0xFF0D、退格=0xFF08、Esc=0xFF1B、Del=0xFFFF）→ 宿主认不出 Tab/回车（实测 Tab 被当可打印字符插进输入框、回车提交失灵）。修法：控制字符按 X11 keysym 出，可打印（含中文）直接用 Unicode 码点。
- **根因四：抬起事件投给控件**。内核 `Editor::handle_key` 只有 `(keysym, mods)`、分不出按下/抬起，宿主若放行抬起就等于「松手再插一个字符」（现象与根因三叠加）。修法：`App::route` 只把按下投给控件（Tab/焦点栈的宿主处理同样只看按下）。
- **根因五（同批回归自查抓到）**：视口剔除用**绝对矩形**去过 CTM，父原点被计两次 → `oy≠0` 的子树整片误剔（判据：ui 掉到 102/110、控件场景探针「下半屏 0 墨」）。修法：判交用相对当前原点的**本地矩形**（`rect - (ox,oy)`）——CTM 的原点就在父内容原点。
- **根因六（输入真正接通后才暴露的潜伏越界）**：`dispatch_on_path` 的「右键祖先优先」分支写成**取下标前自增**——走完路径末项时 `i` 恰好等于长度，`path[i]` 越界，真机表现为「右键点任何控件即 `PanicError`」。Linux 侧之所以没见过，是那些用例的右键都在更深的层被消费、提前 `handled` 出循环。修法：祖先优先改成「先取后进」（自增挪到循环体末尾）；补回归用例 `widget_wbtest` 的「右键祖先优先：走完路径不越界，顺序根→叶」（含只有根一层的路径）。判据：真机注入左键+右键各两次，进程存活、`clicks=1` 落数、日志无 Panic。
- **根因七（中文输入法打不出字）：消息泵缺 `TranslateMessage`**。Win32 的 `wm_pump` 只做 `PeekMessage + DispatchMessage`——而 legacy IME（IMM32）的组合处理就挂在 `TranslateMessage` 这条路上：缺了它只会收到裸键（字母的按下被 IME 吃掉、只余抬起），`WM_IME_STARTCOMPOSITION`/`WM_IME_COMPOSITION` 一条都收不到，拼音永远组合不起来（实测：只来 `WM_IME_SETCONTEXT`）。补上之后探针立刻拿到 `preedit=[ni'h'ao …]` 与 `commit=[你还奥]` ✓。判据：`experiment/key_probe` 打字看 preedit/commit 行。
- **根因八（Markdown 序号掉到基线下方）：标记格是零高度节点**。`md_marker` 只设了宽度、没有子件也不注册测量 → 高 0；而 `hbox` 默认 `align_items=Center`，0 高的格子被摆到行的中点（实测 `rect=(0,111,18,0)` 而正文在 102..120），序号整体低半个行高、中心正好压在正文基线上。修法：给标记格注册文本测量（行盒高与正文同源），并把它贴首行顶对齐（`valign=Start`）；回归用例 `markdown_wbtest`「有序列表：序号与正文落在同一条基线上」。
- **性能（同批）**：文字路径 **9.4ms → 0.35ms/段**（三件：①D2D 渲染目标从 DC 换 **WIC 位图**——DC 目标逐调用 `BindDC` 就要 0.4ms，总账 1.8ms/段；②画布/画笔进程级缓存，尺寸只增不减；③`Raster::blit` 加「整数平移 + 1:1 全幅 + Normal」快路径，源字节先过 256×256 查表复刻通用路的「解除预乘→乘回」，**逐位一致**才没把像素断言打红）。整树重画 550ms → ~300ms（视口剔除）；示例节拍 100ms → 500ms（真机每个重绘周期阻塞消息泵的时间随之落回安全区）。整窗重绘仍是数百毫秒级（图表页最重），列为后续性能批。
- **WIC 画布两条陷阱**：①**不能**用 `CreateBitmapFromMemory` 包外部缓冲再让 D2D 画——那走 WIC 内部缓存，读不回你的缓冲（现象：ink=0 而返回值成功），要自持位图 + 绘制后 `Lock(WICBitmapLockRead)` 读回；②用「全透明笔 `FillRectangle`」清画布是**空操作**（源覆盖语义），必须 `Clear`——它吃轴对齐裁剪，所以能只清本次区域（缓存画布比本次大时正好用上）。
- **回证方式**：`experiment/key_probe`（建窗→泵→打印键码，配 PowerShell `AppActivate`+`SendKeys`）验键盘通路；`experiment/text_bench` 守文字路径性能；截图核对窗口内容（本机用 PowerShell 抓屏 PNG 看图判色）；`App::step`/`paint_frame` 的临时分段计时（PAINT-PROF/STEP-PROF）定位过瓶颈，已撤。全绿复核：core 70 / input 10 / ui 110 / render 43 / text 29 / chart 189 / theme 8 / mdview 26 / sys 165，全仓红点 287/68 持平。

### MoonBit 原生 GUI 栈 · Windows 基础能力首批（W20a 菜单栏 / W20b 全局快捷键 / W20d 消息框）

- **环境与绕开工具链的验证路径**：Windows 10 19045 + VS BuildTools 2022（MSVC **14.44.35207**，在 `C:\Program Files (x86)\Microsoft Visual Studio\...`；`C:\Program Files\...` 是空目录、会白找）+ SDK 10.0.26100。`vcvars64.bat` 被 reg.exe 策略挡住，手工编纯 C 探针要自己设 `INCLUDE`/`LIB`，且必须用 Windows 风格路径（`/c/...` 会被 cl 当源文件）：
  ```bash
  MSVC='C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Tools\MSVC\14.44.35207'
  SDK='C:\Program Files (x86)\Windows Kits\10'
  export INCLUDE="$MSVC\include;$SDK\Include\10.0.26100.0\ucrt;$SDK\Include\10.0.26100.0\shared;$SDK\Include\10.0.26100.0\um;$SDK\Include\10.0.26100.0\winrt"
  export LIB="$MSVC\lib\x64;$SDK\Lib\10.0.26100.0\ucrt\x64;$SDK\Lib\10.0.26100.0\um\x64"
  MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' "$MSVC/bin/Hostx64/x64/cl.exe" \
    /nologo /W4 /utf-8 /O2 /DWIN32 /D_WINDOWS /DUNICODE /D_UNICODE <探针>.c \
    /Fe:<探针>.exe user32.lib gdi32.lib imm32.lib advapi32.lib
  ```
  纯 C 探针 `experiment/menu_probe/menu_backend_probe.c` 直接 `#include "../../gui/win/stub.c"`——因为 `wm_menu_bar_new` 返回的是**句柄表下标**（1..31）而非真 `HMENU`，反读菜单结构必须同 TU 拿静态表 `wm_menus[]`（第一版拿下标当 `HMENU` 传给 `GetMenuItemCount`，满屏 `-1`）。
- **纯 C 探针的 include 编译必须显式 `-DUNICODE`/`-D_UNICODE`**：不带时 `IDC_ARROW` 等是 `MAKEINTRESOURCEA` 形态（`LPSTR`），传给 `...W` 形参报 **C4133**（`stub.c:388-396`、`646`）；带上后零新增告警（`stub.c` 自身 `wcsncpy`/`wcsncat` 的 C4996 是既有告警）。`moon` 的 native-stub 本就定义 UNICODE（W2 小节已记），故生产链吃不到这两条 C4133。
- **`AppendMenuW` 单菜单项数上限实测 ≈1168**（本机 bulk 循环第 1169 项起返回 0），**远低于命令 id 池 2048**。由此定两条：①**命令 id 必须「挂载成功后才推进游标」**——原实现先 `cmd = next++` 再 `AppendMenuW`，失败照样吃掉一个 id；反复失败（菜单超限）会让配额提前耗尽，进而与其他菜单在用的 id 相撞（`WM_COMMAND` 只带 id，撞了就把点击派给错项）。修正为 `cmd = next`，`AppendMenuW` 成功后再 `next = cmd + 1`（到池尾归位 `BASE`）。②`WM_MENU_CMD_MAX=2048` 要**刻意大于单菜单上限**：池 ≥ 单菜单上限才保证「只填一个菜单绝不回绕」、菜单自身 id 不自相撞；把池收紧到「实测上限」反而让满菜单撞上回绕。探针据此重写回绕用例——跨菜单填满 2048 个 id 后再在**有空间的新菜单**上加一项，验证它拿到归位后的 1000（单菜单永远耗不尽池子，第一版断言不可达）。
- **`\t` 拼进标签即加速键提示**：`AppendMenuW` 会把 `\t` 之后的部分右对齐显示（探针用 `GetMenuItemInfoW` 读回，校验中文 UTF-8→UTF-16 往返 + `\tCtrl+Alt+Q` 提示串存在）。真正的加速键表（`TranslateAccelerator`）未接，菜单打开后的键盘导航/快捷键暂靠 W20b 全局热键。
- **消息框（W20d）是栈内第二种 FFI 形态——「阻塞式」**：`MessageBoxW` 一次调用即显示并**模态阻塞**到用户点按钮、返回按钮编号，没有回调也没有窗口槽；`uType` 的四段位组合（图标 + 按钮）由 MoonBit 侧纯函数算好传进来（探针真机跑出 `icon=64 btn=0 raw=327744`）。与菜单/热键那种「寄存 + 泵里抽」的异步形态正交。
- **全局快捷键（W20b）挂在**线程**消息队列而非窗口**：`RegisterHotKey` 的 `WM_HOTKEY` 进的是注册线程队列，WndProc 收不到——与菜单同制，桩侧 `wm_hotkey_poll` 在 MoonBit 泵里主动抽。加速键串解析（`"CmdOrCtrl+Shift+M"` → 修饰位 + 虚拟键码）抽成三平台同源纯函数（`CmdOrCtrl` 在 Win 映射 Ctrl、mac 映射 Cmd），10/10。
- **回证**：`experiment/menu_probe/menu_backend_probe.c` 纯 C 探针 `MENU-BACKEND-OK`（菜单条/子菜单/命令 id/分隔线/勾选/嵌套/中文标签/非法父句柄/句柄表用尽/id 回绕全过）；`experiment/menu_probe` 的 MoonBit 侧验模型树 `MENU-OK`；`core/menu_wbtest.mbt` 10/10、`win/hotkey_wbtest.mbt` 10/10、`win/message_box_wbtest.mbt` 8/8 真跑通过。

### MoonBit 原生 GUI 栈 · Windows 图标加载（W20f：.ico 原生 + PNG 走 WIC）

- **三条来源各有各的入口**：`.ico`/`.bmp` 走 `LoadImageW(LR_LOADFROMFILE)`（Win32 原生图标格式，不必解码）；PNG/JPEG/GIF **没有原生入口**，只能 WIC 从内存解码（`CreateStream`→`InitializeFromMemory`→`CreateDecoderFromStream`→`CreateFormatConverter` 到 `GUID_WICPixelFormat32bppBGRA`→`CopyPixels`）；已是像素的走 32bpp 自顶向下 DIB + `CreateIconIndirect`。`wm_icon_load_file` 按扩展名分派，两条都失败给 0。
- **32bpp HICON 的 alpha 必须预乘，而 `render` 的 Bitmap 正是这个口径**（小端 B,G,R,A 预乘）——`CreateIconIndirect` 的颜色位图用 alpha 做混合，预乘才不出光环；两者天然对齐，像素可逐字节 `memcpy` 进 DIB。验证法：`GetObject` 对 DIB section 的 `bmBits` **不保证可读**（实测拿到不可用指针、memcmp 必挂），要反读像素得用 `GetDIBits`（`biHeight` 给负数＝请求自顶向下，与输入行序一致）。
- **`CLSID_WICImagingFactory` 是宏、会指向 Win8 才有的 Factory2**：`wincodec.h` 在 `_WIN32_WINNT >= 0x0602` 时 `#define CLSID_WICImagingFactory CLSID_WICImagingFactory2`；要兼容旧系统就显式取 **`CLSID_WICImagingFactory1`**（vtable 前缀一致，`IID_IWICImagingFactory` 仍用 v1）。
- **GUID 常量全在 `windowscodecs.lib` 里导出**（`dumpbin /linkermember` 实测：`CLSID_WICImagingFactory1`、`IID_IWICImagingFactory`、`GUID_WICPixelFormat32bppBGRA` 都有），故 win 的 Windows 链接行只加 `windowscodecs.lib ole32.lib`，不必再链 `uuid.lib`（C 模式仍用不了 `__uuidof`，与 W14 文件对话框同条坑）。
- **C4013 隐式声明同样会在这条路上出现**：`wm_icon_load_file` 的 WIC 回退要调定义在其后的 `wm_icon_from_png`，独立编 stub.c 时 MSVC 给 `C4013: 未定义；假定外部返回 int`——**能编过但口径不可信**（与主色那节的坑同族），加前置声明即消。教训：内部互相调用的静态/全局函数，先想清定义次序或直接前置声明，别靠隐式声明兜。
- **回证**：纯 C 探针 `experiment/icon_probe/icon_backend_probe.c`（`#include stub.c` 直喂 `wm_icon_*`，再用 `GetIconInfo`/`GetDIBits` 反读）末行 `ICON-BACKEND-OK`：BGRA→HICON 的尺寸/位深/像素往返、`.ico` 磁盘加载、PNG 走 WIC（8×8 RGBA 半透明红解出 32bpp）、句柄表 31 槽用尽归 0、释放幂等全过。PNG 素材由 `experiment/icon_probe/make_png.py` 用标准库 zlib 手写生成（不依赖 Pillow）。`moon test ./gui/win` 24/24（新增 6 条纯函数：扩展名判定/格式分派/句柄 0 语义/尺寸校验）。

### MoonBit 原生 GUI 栈 · Windows 窗口增强（W20e：改标题 / 窗口图标 / 最小尺寸 / 无边框拖拽区）

- **`WM_GETMINMAXINFO` 的 `ptMinTrackSize` 要的是整窗尺寸，不是客户区**：MoonBit 侧传的是**最小客户区**（`set_min_size(w,h)`），C 侧按当前样式 `AdjustWindowRectEx(&r, st, FALSE, ex)` 把非客户区（边框 + 标题栏）外扩后再填 `ptMinTrackSize`。探针实测：客户区最小宽 400、WS_OVERLAPPEDWINDOW 下外框 416（左右各 8px），`AdjustWindowRectEx` 口径与 `WM_GETMINMAXINFO` 一致。
- **某轴为 0 必须显式归零**：`set_min_size` 允许单轴不限（`0` = 该轴不限制）。但**不能**把 `0` 直接塞进 `AdjustWindowRectEx` 的矩形——那会算出「零客户区也占 2×边框宽」的假最小宽。实现写成 `mmi->ptMinTrackSize.x = w->min_w > 0 ? (r.right - r.left) : 0;`，两轴都判一次；`wm_set_min_size` 入口也先把负数夹成 `0`。只设一轴时另一轴必须回落到 0，否则窗口在该轴被卡住。
- **`WM_NCHITTEST` 用 `break` 而非 `return 0`**：自绘标题栏拖拽区命中时 `return HTCAPTION`（把拖窗交给系统），**不在区内必须 `break` 落回默认处理**——`WM_NCHITTEST` 的默认返回值含客户区 `HTCLIENT` / 边框缩放角 `HTBOTTOMRIGHT` 等语义，`return 0` 会把它们一并吞掉：实测表现为边框再也拽不动、客户区鼠标行为异常。命中判定用 `ScreenToClient` 把 `lParam` 的**屏幕坐标**转客户区坐标再比矩形（`lParam` 打包的是屏幕坐标，不是客户区，容易看走眼）；区间取左下闭右上开（`>= x && < x+w`）。注意 `lParam` 的坐标是 **16 位有符号**（`(int16_t)LOWORD/HIWORD`），多显示器负坐标也能还原。
- **`WM_GETICON` 反读校验窗口图标**：`wm_set_icon(id, icon_slot, which)` 的 `which` 0/1/2 分别对应 `ICON_BIG` / `ICON_SMALL` / 两者，直接 `SendMessageW(hwnd, WM_SETICON, …)`。探针用 `WM_GETICON(ICON_BIG)` 反读，拿到同一个 `HICON` 句柄即证明写入生效。**图标句柄表归调用方**（W20f 的槽表），窗口只是「用」这个 `HICON`：C 侧注释与门面文档都写明「调用方须保证图标在窗口显示期间不被 `free`」，否则窗口引用悬空句柄。传入 `icon_slot=0` 即清空图标。
- **无边框 = 改样式后按客户区重算外框 + `SWP_FRAMECHANGED`**：ON 时去掉 `WS_CAPTION|WS_THICKFRAME|WS_MINIMIZEBOX|WS_MAXIMIZEBOX|WS_SYSMENU|WS_BORDER|WS_DLGFRAME`、换 `WS_POPUP`（保留 `WS_MINIMIZEBOX` 以便仍能最小化），OFF 时还原 `WS_OVERLAPPEDWINDOW`。**关键两步**：①先 `GetClientRect` 拿当前客户区尺寸，改完样式后用新样式 `AdjustWindowRectEx` 重算外框，再 `SetWindowPos(..., SWP_NOMOVE|SWP_NOZORDER|SWP_FRAMECHANGED)`——少了 `SWP_FRAMECHANGED` 非客户区不重算，窗口尺寸会跳；②幂等判据用 `w->borderless`，重复设同值直接返回（否则每次调用都 `SetWindowPos`，无谓重排）。探针验：无边框后 `GWL_STYLE` 里没有 `WS_CAPTION`、客户区宽度仍是 640（不变）。
- **运行中改标题走 `SetWindowTextW`**：`wm_set_title` 把 UTF-8 转 UTF-16 后 `SetWindowTextW`；探针用 `GetWindowTextW` 反读中文标题校验 UTF-8→UTF-16 往返。
- **回证**：纯 C 探针 `experiment/window_probe/window_enhance_probe.c`（`#include` stub.c，建真窗口后 `SendMessageW(WM_GETMINMAXINFO/WM_NCHITTEST)` 直读、`GetWindowTextW`/`WM_GETICON`/`GWL_STYLE` 反读）末行 `WIN-ENHANCE-OK`（40 条断言全过）：`SetWindowTextW` 生效（中文）、`ptMinTrackSize.x == 416`（客户区 400 + 边框）、多显示器负坐标命中/边界开区间、区内回 `HTCAPTION` 区外回 `HTCLIENT`、`WM_GETICON(ICON_BIG)` 等于传入图标、无边框后无 `WS_CAPTION` 且客户区宽不变、越界 id 不崩且不写缓冲。示例接线：`examples/native-app` 新增窗口增强区（改标题 / 自绘图标 / 无边框开关 / 拖拽带开关）与退出状态行 `NATIVE-APP-WIN title='…' min=… drag=… bl=… icon=…`，`moon build` 产出 `native-app.exe`。`moon test ./gui/win` 24/24、`moon check ./gui/win ./examples/native-app --deny-warn` 零警告、C 后端 MSVC `/W4` 干净。

### MoonBit 原生 GUI 栈 · Windows 系统托盘（W20c：Shell_NotifyIconW + 复用 W20a 菜单做右键）

- **托盘 = 「一个 HWND + 一个 uID」的 Shell 通知图标**：`Shell_NotifyIconW` 的回调消息投给 `NOTIFYICONDATAW.hWnd` 那扇窗，`wParam` 是 `uID`、`lParam` 是鼠标消息。本侧因此自建一扇**隐藏消息窗**（`yue_wm_tray` 类 + `HWND_MESSAGE`，惰性建、幂等），槽号即 `uID`（1 起，槽 0 不用；`WM_MAX_TRAYS=8`）。
- **`WIN32_LEAN_AND_MEAN` 会把 `shellapi.h` 一并裁掉**：`Shell_NotifyIconW` / `NOTIFYICONDATAW` / `NIM_*` / `NIF_*` 全在它里面，必须显式 `#include <shellapi.h>`（与 `imm.h` 同待遇）。链接面补 **`shell32.lib`**（`user32`/`gdi32` 里没有）——漏了就是 `LNK2019 __imp_Shell_NotifyIconW`。
- **回调消息用 `WM_APP+2`，且同样「C 不回调 MoonBit」**：`WM_APP+1` 已被 `wm_wakeup` 的 waker 窗占用（`stub.c` 里那条 `case WM_APP + 1:`），托盘另取 `WM_APP+2`。命中（`WM_LBUTTONUP`/`WM_LBUTTONDBLCLK` → 左键、`WM_RBUTTONUP` → 右键）压进程级环形队列，宿主每拍 `wm_tray_poll` 抽——与菜单/热键同制，避开蹦床形参错位那一类坑。非点击消息（如 `WM_MOUSEMOVE`）不入队。
- **右键菜单复用 W20a 的 HMENU 句柄表，于是「托盘菜单」与「窗口菜单」共用同一条派发链**：`wm_menu_popup_new()` 建弹出根（与 `wm_menu_bar_new` 只差 `CreatePopupMenu` vs `CreateMenu`），core 的 `menu_translate_into` 照常往里填项；弹出用 `TrackPopupMenuEx(menu, TPM_RIGHTBUTTON|TPM_RETURNCMD|TPM_NONOTIFY, x, y, tray_hwnd, NULL)`——**`TPM_RETURNCMD` 把选中项直接作返回值给出**，压进 `wm_menu_push` 即回到 `dispatch_menu_command()` 的回调表，不必依赖托盘窗的 `WM_COMMAND` 路由。两条微软约定照做：弹前 `SetForegroundWindow(tray_hwnd)`、弹后 `PostMessage(hwnd, WM_NULL, 0, 0)`，否则菜单可能不消失（焦点不还回去）。
- **`szTip` 是 128 宽字符的定长数组，超长必须截断**：写 tooltip 用 `wcsncpy_s(nid.szTip, 128, wtip, _TRUNCATE)`——裸 `wcsncpy` 会吃 **C4996**（与 W20a 菜单标签那两处同族告警）。本次刻意用 `_s` 变体，托盘整段在 MSVC `/W4` 下**零新增告警**。
- **后端选择：Linux SNI 优先，Windows 走本批桩，皆无给 `Err(Unsupported)`**。SNI 可用性判据是**新增**的 `@dbus.sni_watcher_present()`（连得上总线 **且** `NameHasOwner(org.kde.StatusNotifierWatcher)`），比既有的 `@dbus.sni_available()`（只看「连得上总线」这个候选条件）更强——纯净 GNOME 未装 AppIndicator 扩展时总线通但 watcher 不在线，托盘实际不可用。**GTK 分支刻意返回 0**：Linux 的托盘走 SNI 协议栈，不走 GTK3 的 `GtkStatusIcon`（已弃用且面板不认），与 W20f 图标加载在 GTK 分支返回 0 同一个理由。
- **门面住 `core/tray.mbt`，core 因此新增 `sys` 与 `dbus` 两个依赖**（前者供 `desktop_environment()` 读 `XDG_CURRENT_DESKTOP`，后者供 SNI）。这与 W20a 把菜单模型放 core 同一条分层口径：core 是「跨平台能力门面」层，平台后端只做「模型 → 原生」翻译。旧栈同名 `TrayError` 在待退役的 `yue/error.mbt`，新栈口径住本文件。
- **退出读数的坑（本批顺带修）**：示例的退出状态行在**窗口关闭之后**才打印，那时后端槽已被 `memset` 清空——`NATIVE-APP-WIN title='' min=0x0 …` 一片 0（现场读数读的是一扇已销毁的窗）。改成每拍把现场读数快照进一个 `Ref[String]`、退出时打印最后一份「活着时的」读数，读数才有意义（实测由 `title='' min=0x0` 变为 `title='MoonBit App 宿主 (批次1)' min=900x600`）。口径：**退出时想报「运行中的现场状态」，就得在运行中取样，别指望销毁后还能读到。**
- **回证**：纯 C 探针 `experiment/tray_probe/tray_backend_probe.c`（`#include` stub.c，直喂 `wm_tray_*`）末行 **`TRAY-BACKEND-OK`**，28 条断言全过：`wm_tray_supported()==1`、**真实 `Shell_NotifyIconW(NIM_ADD)` 建成**、tooltip 中文 UTF-8→UTF-16 往返与 299 字符截断在 127 内、不越界、`wm_menu_popup_new` 拿到真 `HMENU` 且挂进托盘、**主动给托盘消息窗投 `WM_TRAY_CB` 验左键 kind=0 / 右键 kind=1 / 槽号一致 / 非点击消息不入队**、`wm_tray_popup` 的守卫路径（非法槽、无菜单）立刻返回 0 不阻塞（`TrackPopupMenuEx` 是阻塞调用，真弹出需真人点选，故只验守卫）、槽表用尽（7 槽后给 0）、移除幂等且计数归 0。`moon test ./gui/core` **99/99**（新增 6 条纯函数：`basename_no_ext` 各类路径/空串/尾点/多重点、桌面环境名非空、`TrayError` 三种 Show；**1 条生命周期**：建 → `tray_count()==1` → tooltip 回读一致 → 挂菜单（弹出句柄回填）→ 移除 → `tray_count()==0`，无托盘后端的机器自动跳过而非造假）。示例 `examples/native-app` 新增托盘区块（建/改提示/挂菜单/弹菜单/移除五键 + 状态计数）与退出状态行 `NATIVE-APP-TRAY supported=… backend=… count=… clicks=… note=…`，并在主循环每拍加 `dispatch_tray_event()`。真机冒烟：`exit 0`，`NATIVE-APP-TRAY supported=1 backend=- count=0 clicks=0 note=-`（未点按钮故未建项，supported=1 即 Win32 托盘后端可用）。`moon check` 全仓红点 **287/68** 持平，gui/{core,win,dbus,ui,render,text,theme,icons,input,mdview,chart} 全绿。

### MoonBit 原生 GUI 栈 · Windows 桌面通知（W21a：托盘气泡 NIF_INFO + freedesktop 跨平台门面）

- **Win32 的「通知」没有独立 API，它就是挂在托盘图标上的一张气泡**：先 `NIM_ADD` 建托盘项，再 `NIM_MODIFY` 带 `NIF_INFO` 与 `szInfoTitle`/`szInfo` 弹气泡（Vista 起系统把这类气泡转成 Action Center 的 toast）。因此本段**复用 W20c 的托盘槽表与消息窗**，用新增的 `WmTray.kind` 区分：`kind == 0` = 托盘图标（收点击）、`kind == 1` = 通知气泡（只弹、不收点击）。通知 id 于是天然等于所属托盘槽号（>=1）。
- **通知槽必须显式排除在点击队列外**：`wm_tray_wndproc` 收 `WM_TRAY_CB` 时加了 `wm_trays[slot].kind == 0` 守卫，`kind == 1` 的槽收到点击直接丢弃——气泡的点击语义未定义（Windows 的 toast 点击由系统处理，不经 `uCallbackMessage`），若照旧入队会派发到一个「不是托盘图标」的槽上。探针主动给通知槽投 `WM_LBUTTONUP`/`WM_RBUTTONUP`，验队列仍空。
- **「收气泡」没有独立 API，只能照官方约定再发一次 `NIF_INFO` 且 `szInfo` 置空**：`wm_notify_close` 先发这条空正文的 `NIM_MODIFY`（系统据此撤下气泡），再 `NIM_DELETE` 摘掉托盘项——两步都要，只 `NIM_DELETE` 不保证气泡立刻消失。幂等：重复关闭走「槽已空」的守卫直接返回。
- **两条平台差异显式降级、不假装对齐**（写进 `core/notify.mbt` 的文档头与本节）：① **`uTimeout` 自 Vista 起被系统忽略**，气泡驻留时长由系统的辅助功能设置定，故 `timeout_ms` 只用于与 Linux 侧同签名、本侧不生效；② **Win32 气泡没有「进度 hint」**，Linux 的 freedesktop `value` hint 能让桌面端画进度条，Win32 无对应物，门面把百分比拼进正文（`notify_body_with_progress`，可见降级而非静默丢弃）。
- **`kind` 三态映射 `NIIF_*`**：0 信息 / 1 警告 / 2 错误 → `NIIF_ERROR` / `NIIF_WARNING` / `NIIF_INFO`（气泡左侧的系统状态图标）。这是写死的一行三元式，**Win32 没有读回 `dwInfoFlags` 的接口**，故探针只能验三个 kind 下发都返回成功，映射本身由代码评审兜底（探针头注释如实写明这一限制）。
- **`szInfoTitle` 是 64 宽字符、`szInfo` 是 256 宽字符的定长数组**：写入一律 `wcsncpy_s(..., _TRUNCATE)`（裸 `wcsncpy` 吃 C4996，与 W20a/W20c 同族）。`WmTray.ntitle[64]` 存一份标题副本供反读（`wm_notify_title`，UTF-8 输出）。
- **托盘图标槽与通知槽共用同一张 `WM_MAX_TRAYS=8` 表，但计数完全解耦**：`wm_tray_count()` 只数 `kind == 0`、`wm_notify_count()` 只数 `kind == 1`。探针验「托盘 1 + 通知 3 = 占用 4 槽」「表满后再发只成 3 张」「摘掉托盘图标不影响通知数」。分配入口统一走 `wm_tray_alloc(kind, icon_slot, tip)`，`wm_tray_new` 转调 `kind=0`。
- **门面分层**：`win/notify.mbt` 是 Windows 侧薄封装（`notify_supported`/`notify_send`/`notify_update`/`notify_close`/`notify_count`/`notify_title` + `NOTIFY_INFO/WARNING/ERROR` 三常量）；`core/notify.mbt` 是**跨平台门面**——后端选择 Linux freedesktop D-Bus（`dbus/notify.mbt`）优先 → Win32 托盘气泡 → 皆无给 `Err(NotifyError::Unsupported)`。跨平台 API 形如 `notify_send(app_name, summary, body, icon?, timeout_ms?, replaces_id?, progress?, kind?, icon_handle?)`，其中 `icon` 是 Linux 主题图标名、`icon_handle` 是 Win32 的 W20f 图标句柄（0 = 用系统状态图标）。`replaces_id > 0` 时 Win32 侧先试 `notify_update`（同槽重发即替换）。
- **回证**：纯 C 探针 `experiment/notify_probe/notify_backend_probe.c`（`#include` stub.c，直喂 `wm_notify_*`）末行 **`NOTIFY-BACKEND-OK`**，**37 条断言全过**：`wm_notify_supported()==1`、**真实 `Shell_NotifyIconW(NIM_MODIFY)` 弹气泡**、标题中文 UTF-8→UTF-16 往返与 399 字符截断在 63 内、不越界、**通知槽点击不入托盘队列**、三个 kind 下发皆成功、**托盘 1 + 通知 3 共表且计数解耦**、表满（7 槽）后新发给 0、关闭减一且幂等、非法槽/托盘槽调用通知 API 全给 0 或无效。`moon test ./gui/core` **108/108**（新增 9 条：`notify_clamp_kind` 夹 0..2、`notify_clamp_pct` 夹 0..100、`notify_body_with_progress` 负值不改/拼进正文/百分比夹取、`NotifyError` 两种 Show、后端名与枚举一致、`notify_caps` 有/无后端两态；**1 条生命周期**：发 → 改进度 → 关 → 幂等重关，无通知后端的机器自动跳过）。示例 `examples/native-app` 新增通知区块（发信息/发警告/发错误/进度 60%/关闭五键 + 状态计数）与退出状态行 `NATIVE-APP-NOTIFY supported=… backend=… sends=… id=… count=… note=…`（`count=` 同样每拍快照，理由同 W20c 的退出读数坑）。真机冒烟：`exit 0`，`NATIVE-APP-NOTIFY supported=1 backend=win-balloon sends=0 id=0 count=0 note=-`（未点按钮故未发，`backend=win-balloon` 即后端选择正确）。`moon check` 全仓红点 **287/68** 持平，gui/{core,win,dbus,ui,render,text,theme,icons,input,mdview,chart} 全绿。

### MoonBit 原生 GUI 栈 · 开机自启动（W21d：`sys/autostart.mbt`，面在 MoonBit、只有 Windows 要 C）

- **分工**：**跨平台的面在 MoonBit**——Linux（及各 XDG 桌面）拼 `$XDG_CONFIG_HOME/autostart/<app_id>.desktop` 并写盘（纯字符串 + `fsx.mbt` 既有的文本文件读写入口，不需要任何平台接口）；**只有 Windows 需要 C**——HKCU 的 Run 键只能走注册表 API（`RegOpenKeyExW` / `RegQueryValueExW` / `RegSetValueExW` / `RegDeleteValueW`），见 `sys/sys_stub.c` 的自启动节。macOS 本批显式 `Unsupported`（要走 LaunchAgents plist，留待真机）。
- **值的形态是平台惯例，不是随便一个字符串**：Linux 的 `.desktop` Exec 要按桌面项规范**整体双引号包裹**（引号内 `\` 与 `"` 反斜杠转义、`%` 写 `%%`）；Windows 的 REG_SZ 值同样要**整串引号包裹**——路径含空格而未加引号时，登录拉起会被截断成第一个词（等于自启动了一个不存在的程序）。两侧的引号都由 MoonBit 侧拼（`autostart_escape_exec` / `autostart_run_value`），C 桩**原样写、原样读**，不做二次加工。
- **幂等是契约的一部分**：重复 `enable` 是覆盖写（Linux 覆盖 `.desktop` / Windows 覆盖同值名的 Run 值）；`disable` 对「本就不在」也返回成功（Linux 靠 `yue_sys_remove_file` 的「先探存在再删」、Windows 对 `RegDeleteValueW` 的 `ERROR_FILE_NOT_FOUND` 与「键都不在」两档都算成功）。
- **app_id 校验是两个落点的公共前提**：app_id 同时要当 `.desktop` 文件名与 Windows 的 Run 值名，所以沿用 DBus 知名名字符集（≥2 个点分元素、每元素以字母/下划线开头、只含 `[A-Za-z0-9_-]`、总长 ≤255）。**`sys` 不反向依赖 `dbus`**，故这条规则在 `sys/autostart.mbt` 里本地实现了一份（`autostart_valid_app_id`）。**踩到的认知坑**：元素**不能以 `-` 或以数字开头**，但**可以包含**它们——`com.example.my-app2` 合法、`com.2app` 与 `com.-app` 非法。写测试时曾把「含 `-`」当成非法（断言 `com.ap-p` 为 false，而它实际合法），实测纠正。
- **链接面**：`Reg*` 一族在 **advapi32.lib**，而 `sys` 的 Windows 链接行原本只有 `ole32/shell32/uuid/user32`（那些是给文件对话框的 COM 用的）——本批给 sys 条目补上 `advapi32.lib`（`scripts/prebuild.py` 托管，包内仍不写链接参数）。
- **纯 C 探针的两个自带件**（`experiment/autostart_probe/autostart_backend_probe.c`）：①**探针自带 `moonbit_make_bytes`**——纯 C 探针不链 moon 运行时，而 `yue_sys_*` 返回的是 moon 字节串；自带一份只要**布局自洽**即可（长度存数据指针**前 4 字节**，与真 `moonbit_object` 头同构），真 ABI 交互由白盒测试覆盖。②**`stub.c` 的 include 顺序会让 `_CRT_SECURE_NO_WARNINGS` 失效**——探针先 `#include <windows.h>`（它已带入 `string.h`），UCRT 在那一刻就定下了弃用名要不要告警，于是桩里那两处 `wcscpy`/`wcscat` 在探针编译里出 2 条 C4996。这是**探针 include 顺序的产物，不是代码问题**：真构建由 moon 的 native-stub 先含 `sys_stub.c`，宏先生效，无此告警。
- **回证**：纯 C 探针末行 **`AUTOSTART-BACKEND-OK`**，**36 条断言全过**：`yue_sys_exe_path` 与独立调用 `GetModuleFileNameW` 逐字符一致（含 `.exe` 后缀与反斜杠）、未写时 ok=0、写入后**探针自己直读** `RegQueryValueExW` 确认落在 `Software\Microsoft\Windows\CurrentVersion\Run` 且类型 `REG_SZ`、值与写入逐字符一致、覆盖写/中文路径往返/空值（长度 0 但存在）/1207 字符长值往返、`NULL` 参数三入口回 -1、删除后独立直读 `ERROR_FILE_NOT_FOUND`、幂等再删仍成功。**探针会真写用户注册表**（这正是它的意义），起手与收尾都删自己的专属值 `com.moonbit.native-gui.autostart_cprobe`，无论成败都清场（跑完 `reg query` 复核无残留）。`sys/autostart_wbtest.mbt` **8 条**：6 条纯函数（目录解析三态 / Exec 转义 / `.desktop` 内容与解析两态 / Run 值形态与反解 / app_id 校验 / 错误 `Show`）+ 1 条「非法 app_id 在任何平台先被拒」+ **1 条真实生命周期**（清场 → 未启用 → enable → 启用 → 落点可读回（Linux 读 `.desktop` 正文、Windows 读 Run 值并反解比对 exe）→ 重复 enable 幂等 → disable → 未启用 → 幂等再 disable），`autostart_supported()` 为假时跳过而非造假。`moon test ./gui/sys` **174 条、173 过、1 红**——那 1 条是**既有**的 `fsx_wbtest.mbt:109`（`sys_make_dirs` 用例当时在 Windows 上本就红：`pr_available()` 在 Windows 为真，但用例走的是 POSIX 的 `/tmp` + `pr_run("rm"/"mkdir")`；已用 `git stash` 在纯净态复核同一条红，与本批无关）。**现已修复**——`sys_make_dirs` 改为 C 薄 FFI `yue_sys_make_dirs`、用例本身也做成平台可移植，`sys` 178/178。示例 `examples/native-sys` 新增「启用自启 / 取消自启」两键与状态行，退出读数行 `NATIVE-SYS-AUTOSTART supported=1 enabled=0 id=… exe=… on_hits=0 note=…`（`is_enabled` 是即时读盘/读注册表，关窗后照读，与窗口读数不同）；真机冒烟 `exit 0`（未点按钮故 `enabled=0`、注册表无残留）。`moon check ./gui/sys ./examples/native-sys --deny-warn` 零警告；C 侧 MSVC `/W4` 仅剩 2 条 C4996（探针 include 顺序所致，见上）；全仓红点 **287/68** 持平。
- **本批未做且不假装完成**：macOS（LaunchAgents plist，留 Unsupported）、「启动参数」与「延迟启动」（Windows 可写 `**` 前缀/`schtasks` 延时，Linux 可加 `X-GNOME-Autostart-Delay`——本批不写）、`is_supported` 之外的能力探测、自启动真机观感（归 `测试文档/测试用例.md`）。

### MoonBit 原生 GUI 栈 · 用户空闲检测（W21e：`sys/idle.mbt`，只给读数不给二值）

- **接口只给「秒数」，不设 active/idle 二值**：`idle_seconds() -> Result[Double, IdleError]` 返回**自最后一次输入起的秒数**，阈值判定交给调用方自己比较——屏幕常亮/锁屏/省电各自的阈值差别很大，库替调用方拍一个数只会被绕开。换算与夹取（负数归零）在 MoonBit 纯函数 `idle_clamp_ms` / `idle_ms_to_seconds` 里，桩只回毫秒原始值。
- **平台取数分三档（都在 `sys/sys_stub.c` 的空闲节）**：Windows `GetLastInputInfo` + `GetTickCount`；Linux 走 X11 的 **XScreenSaver 扩展（XSS）**；macOS 本批不做（恒 false / `Unsupported`）。
- **Windows：差值必须用无符号模减，不能用 int64 相减**（本批的关键口径）。`GetTickCount()` 是 32 位、约 **49.7 天**回绕一次。正确的写法是 `DWORD elapsed = GetTickCount() - li.dwTime;`——无符号减法天然按模 2³² 求值，跨回绕点结果仍对；若先各转 int64 再相减，回绕点会得到一个巨大的负数（换算成秒是负的时间）。纯 C 探针用合成值（`0x10 - 0xFFFFFFF0 == 0x20`）把这条语义钉死。
- **Linux：运行期 dlopen，不引入 X 链接依赖**。`sys` 的 Linux 链接行只有 pthread/dl/m/stdc++——**headless 消费者不该被 X 库绑住**，所以 XSS 一律走 `dlopen("libX11.so.6"/".so")` + `dlopen("libXss.so.1"/".so")`，`dlsym` 取 `XOpenDisplay` / `XDefaultRootWindow` / `XScreenSaverAllocInfo` / `XScreenSaverQueryInfo` / `XFree` / `XCloseDisplay`。`XScreenSaverInfo` 结构体**在桩里本地声明**（不引 `X11/extensions/scrnsaver.h`，避免链进 X 头）；取符号经 `void*` 中转（`memcpy`）避开 `-Wcast-function-type`。结果缓存在静态 `g_idle_x11`（`tried` 位防重复探测）。
- **Wayland 会话给「不支持」而不是给错数**：没有 X 服务端（`DISPLAY` 为空）时 `idle_supported()` 直接 false。XWayland 下输入事件不进 X 服务端，XSS 读数只会**虚高**——宁可不报，也不给会误导调用方误判的错值（这正是「只给读数」要配 `Result` 的原因：失败当 0 秒会被误读成「刚动过」）。
- **支持性与这次成败分两档**：`idle_supported()` 是运行期能力探测（Windows 恒真；Linux 要 `DISPLAY` 非空且两个库都 dlopen 成功；macOS false）；`idle_seconds()` 里 `ok=1` 给 `Ok`，否则**看 `idle_supported()`**：真则 `Err(Failed("空闲查询失败"))`（如 X 连接中途断），假则 `Err(Unsupported)`。二者分开，调用方才能区别「这台机器没这能力」和「这次查询挂了」。
- **回证**：纯 C 探针 `experiment/idle_probe/idle_backend_probe.c` 末行 **`IDLE-BACKEND-OK`**、**13 条断言全过**——支持性恒 1、读数非负且在 int32 区间（无误截断）、与**独立重算**的 `GetTickCount() - li.dwTime` 一致（±2000ms，容忍调用间隙与 GetTickCount 粒度）、连续读单调不减、模减语义合成值（含回绕）、连续 5 次读全成功、`ok` 出参每次被写。探针只读系统状态、不写任何东西（较 W21d 少一处自带件：空闲接口不返回 moon 字节串，故不需要自带 `moonbit_make_bytes`）。编法见探针头注释（补 `user32.lib`——`GetLastInputInfo` 在 user32；同时因 `#include sys_stub.c` 带进注册表函数，需一并链 `advapi32.lib`）。`sys/idle_wbtest.mbt` **4 条**：3 条纯函数（毫秒夹取 / 毫秒换秒 / 错误 `Show`）+ 1 条「支持性探测」（Windows 断言真、余平台只打印）+ 1 条「读数非负 + 连续两次单调（变小只可能是期间有输入把它清零，此时新值必然 <0.05s）」。`moon test ./gui/sys` **178 条、177 过、1 红**——那 1 条是**既有**的 `fsx_wbtest.mbt:109`（与本批无关，已在前批用纯净态复核）。**现已修复**，见上面「C 桩按需且 minimal」那条的回访。示例 `examples/native-sys` 新增「读空闲」键与状态行，退出读数行 `NATIVE-SYS-IDLE supported=1 seconds=2486.141 hits=0 note=…`；真机冒烟 `exit 0`、`NATIVE-SYS-GEO` 含 `idle=1786,368,110x32`（按钮已排版）。`moon check ./examples/native-sys` 零警告；全仓红点 **287/68** 持平。

### MoonBit 原生 GUI 栈 · 任务栏进度（W20g：`win/taskbar.mbt`，§6.3 接缝项「任务栏进度 / dock 徽标」的 Windows 半边）

- **只写不读**：Win32 的 `ITaskbarList3` **没有 getter**，`TBPF_*` 进度状态不可反读（与 W21a 通知的 kind→`NIIF_*` 映射同款「映射不可反读，由代码评审兜底」）。所以对外只有写入口（`set_taskbar_progress` / `set_taskbar_state` / `clear_taskbar_progress`），探测（`taskbar_supported`）只报「COM 实例起没起来」，不回任何当前进度值。调用方要显示当前进度，自己持有那份数（与 `notify_title` 反读是刻意不同的两档：那个有 `NIF_INFO` 的 szInfoTitle 可反读，这个没有）。
- **COM 实例进程级单例，目标窗口按 hwnd 区分**：`ITaskbarList3` 接口本身与窗口无关（`SetProgressValue(hwnd, …)` 的 hwnd 才是目标），所以桩侧一个静态单例（`wm_taskbar` + `wm_taskbar_tried` 防重复探测），窗口句柄从窗口槽拿（`id` 越界或 `hwnd` 为空一律返回 0，与其它 `wm_*` 入口同口径）。初始化细节：`CoInitializeEx(COINIT_APARTMENTTHREADED)` 遇 `RPC_E_CHANGED_MODE` 退回 `CoInitialize` 再试一次；`S_FALSE`（本线程已初始化过）当成功；`HrInit` 失败要 `Release` 再报不可用；退出时不 `CoUninitialize`——COM 对象随进程收尾，而应用退出路径上还有别的 COM 用户（W14 文件对话框、W20f WIC）。
- **GUID 符号走 `uuid.lib`，不是 ole32**：C 模式用不了 `__uuidof`，`CLSID_TaskbarList` / `IID_ITaskbarList3` 两个常量要在链接期取符号——**ole32.lib 只导 COM 基础 GUID，这两个在 uuid.lib**（与 W20f 图标加载的 `CLSID_WICImagingFactory` 一族在 windowscodecs.lib 是同一条坑：GUID 常量落在哪个库要逐个确认）。故 `gui/scripts/prebuild.py` 的 Windows 分支 win 条目补 `uuid.lib`（探针手工编法同）。
- **进度值走 `Int64`**：下载字节数一类的进度值会超 32 位，MoonBit 侧 `value`/`total` 用 `Int64`、C 侧透传 `ULONGLONG`；`total <= 0` 时 `SetProgressValue` 语义无意义，文档口径是「不确定进度改用 `Indeterminate` 状态」。
- **回证**：纯 C 探针 `experiment/taskbar_probe/taskbar_backend_probe.c` 末行 **`TASKBAR-BACKEND-OK`**、**20 条断言全过**——`wm_init` 成功、`supported == 1` 且单例非空（这两条同时验证 uuid.lib 的 GUID 符号解析与 `CoCreateInstance` + `HrInit` 两步）、建真窗口（`wm_window_new` + `wm_show`，测完 `wm_close`）、五种 state 编号与 `value/total` 写路径全成功、`4GB-1 / 8GB` 大值成功、守卫路径（越界 `id=0` / `id=9999`、槽在但 `hwnd` 空的未建窗口、非法 `state=5` / `state=-1`）全给 0 不崩不写、收尾清回 `NoProgress` 后关窗、关窗后同 id 给 0（`hwnd` 已置空）。`gui/win/taskbar_wbtest.mbt` **4 条**：编号与 `TBPF_*` 对齐、编号往返、未知编号归 `NoProgress`（与 C 侧 default 分支一致）、「连上了才硬断言」——后端可用时不存在的窗口句柄必须给 `false` 而非静默成功（其余平台只打印 skip）。`moon test ./gui/win` **28/28**（原 24 + 新增 4）。
- **示例接线**：`examples/native-app` 加「任务栏进度（§6.3）」区块——七个写入口按钮（10% / 50% / 100% / 错误 / 暂停 / 不确定 / 清除）+ `live_counter` 每帧现读最近一次操作的结果标签（写失败会写进标签，不静默）；退出状态行 `NATIVE-APP-TASKBAR supported=… last=…`。`moon check ./examples/native-app --deny-warn` 零警告；冒烟进程存活（110 秒无 panic、无 CRITICAL——注意 native-app 的自杀点是 **10 分钟**，无人值守跑法一律带超时）。
- **本批未做且不假装完成**：Linux 的任务栏进度另有 Unity LauncherEntry（DBus `com.canonical.Unity.LauncherEntry`）路径、macOS 是 dock 徽标（`NSDockTile`），当时留作后续跨平台门面批（**2026-11-03 定：这类只有单平台形态、语义不对等的条目不做门面合流，已撤出路线图**）——GTK 分支与占位分支只给「supported 恒 0」的可编译失败桩；任务栏按钮的**真观感**（绿条 / 红条 / 黄条、 indeterminate 滚动）只能人看，归 `测试文档/测试用例.md`。
- **探针侧两条 C4996 是既有现象**：`wm_im_*` 段的 `wcsncpy` / `wcsncat`——探针自己 `#include <windows.h>` 会让桩内的 `_CRT_SECURE_NO_WARNINGS` 失效（W21d 记过同一条），真构建（moon 的 native-stub）无此告警。

### MoonBit 原生 GUI 栈 · 原生档弹层的「点外收起」武装与 Win32 弹层落地（2026-10-28 真机反馈）

- **Win32 的 `wm_window_set_popup` 原本是空桩**：弹层于是按 `WS_OVERLAPPEDWINDOW` 的普通窗（标题栏 + 初始 320x200 白底）上屏，Windows 真机看到的就是「一片白板」。落地后三件事：`GWL_STYLE=WS_POPUP` 去框、`WS_EX_TOOLWINDOW` 不进任务栏/Alt+Tab、`GWLP_HWNDPARENT=owner` 让 owned 窗恒压 owner 之上并随其移动。无边框后客户区==整窗，`wm_client_offset` 自然为 0，move 与 origin 互逆不用另补。
- **macOS 无边框窗默认拒绝成为 key**：`canBecomeKeyWindow` 对 borderless 返回 NO，`wm_show` 的 `makeKeyAndOrderFront` 与 `request_focus` 全部空转——弹层既收不到键盘（Esc/↑↓ 失效），也等不到 `resignKey`，「失焦即收起」这条通道整个不存在（真机反馈「菜单点开就关不掉」的 mac 侧根因）。修法：`WMPopupWindow : NSWindow` 只覆写 `canBecomeKeyWindow` 返回 YES、**不加 ivar**，set_popup 里对既有窗 `object_setClass` 换 isa（只换弹层，普通窗不受影响）。
- **「拿到过焦点才算」判据补上，失焦收起默认开**：三平台窗状态各加 `focus_gained` 位（Win `WM_SETFOCUS` / GTK `focus-in-event` / mac `windowDidBecomeKey:`），经 `wm_window_had_focus` 查询；`overlay_on_lost_focus` 要求该弹层窗**当过 key** 才收——批 E 记过的「映射期 focus-out 噪声两秒自关」被这条判据直接挡掉，`g_dismiss_on_blur` 从默认关翻成默认开（开关保留）。
- **验证**：`cd gui && moon check` 零错误零警告、`moon test widget win ui` 370/370、mac 桩重编（`win_stub_mac.o`）通过。真机清单（用户执行）：浏览器示例「演示」菜单——点浮层外收起、Esc/↑↓ 键盘、Windows 侧弹层应无边框贴按钮且不再白板。

### MoonBit 原生 GUI 栈 · Windows 浮层「窄条」的真根因：`wm_window_surface_count` 恒 0 桩（2026-10-28 同线续）

- **上一条修完白板后 Windows 菜单仍只剩贴按钮的一条窄白**，且探针（只挂在原生档路径上）**一行读数都没出**——这条「没有读数」本身就是读数：Windows 上根本没进原生档。判据链：`overlay_native_tier()` 读 `Window::has_child_surfaces()` 读 `wm_window_surface_count`，而 Win32 段那条是**恒 0 的桩**（GTK/mac 段都是真实现，唯独 Windows 漏了）——于是有网页区的窗也走图层档，弹层画在自绘底上被 WebView2 子件整个盖住，只有浮在工具栏与网页区交界之上的几像素露出来，看着像「弹层被压住/收框收坏」，其实是档位判错。
- **判据**：跨平台桩补齐时，**读源函数比消费函数更容易漏**——`wm_surface_new`（写侧）有真实现、`wm_window_surface_count`（读侧）是桩，写读不对称不会编译报错，只在依赖读数的那条分支上静默降级。排查时「探针没出声」优先于「探针读数异常」去怀疑：**先确认代码路径进没进**。
- **修法**：Windows 段按 `wm_surfaces[]` 槽表（hwnd 非空且 window_id 匹配）计数，与 mac 段同口径。修后 Windows 应进原生档：弹层走上一批落地的真窗口（无边框+owner），窄条症状与白板一并消失；待 Windows 真机复验。
- **验证**：`cd gui && moon check --deny-warn` 全绿、`moon test widget win ui` 370/370（本机 mac 段不受影响；Win32 段随用户机 MSVC 编译验证）。

### MoonBit 原生 GUI 栈 · 原生档弹层的收框假量尺与摆位框宽补偿（2026-10-28 探针第三轮读数）

- **读数**（Windows，探针 `POPUP-FIT`）：`meas=(208,200) cur=(208,200) kids=[208x200 0x0(h)]`——16 项菜单应有约 448 高，面板在布局里被**弹性收缩压成视口高**，于是「量内容→长窗」的收框循环量到的永远是当前窗自己，锁死在初框 200。修法是量尺那一拍把根重排成「高度未定」再量。**第一版只把可用高度传了 None 没收效**（真机第二轮仍 `[208x200]`）——因为 `paint_frame` 每帧 `root.set_size(窗宽,窗高)` 把根钉成 fixed，根自己的固定高就是天花板；要连 `set_height(undefined)` 一起解掉、量完钉回。paint 每帧照常按窗尺寸重排，量完即弃不残留。
- **同轮第二读数**：`pos=(1158,176)` vs `at=(1150,145)`，差 (8,31) 恰是标题栏+边框——`set_popup` 改了 `GWL_STYLE` 但框尺寸没立刻重算，随后 `wm_window_move` 的 `wm_client_offset` 读到旧框值，弹层朝左上偏一个框宽。修法：样式改完补一次 `SetWindowPos(SWP_FRAMECHANGED)` 强制重算，move 的补偿自然归零。
- **判据**：「先开框、量完再收」这条链上，**量尺必须在与视口解耦的条件下做**，否则视口就是内容的天花板，收缩档永远自证达标；改窗口样式（有框↔无边框）后任何读框几何前都要 `SWP_FRAMECHANGED` 刷一次，`GetWindowRect` 不会替你即时反映 `GWL_STYLE` 的改动。
- **验证**：`cd gui && moon check --deny-warn` 全绿、`moon test widget ui` 338/338；Windows 真机复验清单交用户（菜单应完整 16 项、贴按钮下沿）。

## Windows 10 / 11 ✅

首次本机全链路验证环境:Windows 10 19045 + VS BuildTools 2022(v17.14)+ SDK 10.0.26100,prepare.py 构建 → moon check / test / build → hello 启动冒烟全通过(此前 Windows 侧仅有 CI 验证,部分分支从未在真 Windows SDK 下编译过)。

### 工具链

- 需 VS Build Tools(VCTools 工作负载 + ATL 组件,`base/win/atl_throw.h` 依赖),在 x64 Native Tools Command Prompt 或 vcvars64 环境执行 moon / cmake;安装器 quiet / passive 模式须提权,否则 Exit 5007。
- 发行包资产名是 `libyue_{v}_win.zip` / `_mac.zip`(非 windows / darwin)。
- 大小写敏感卷上编译报 C1083 找不到 `webview2.h`:SDK 只给 `WebView2.h`(大写 W),prepare.py 解压后补小写别名;同一卷上 `shutil.copyfile` 的 samefile 判定不可靠,复制前先删目标。
- 平台专属代码的 include 与实现必须同批进平台分支:裸 `gtk/gtk.h`、或有使用守卫无定义守卫的函数,都会在另一平台编译端炸出 C1083 / C2065。
- 电源/会话消息(B6)首个真机编译撞出三处 SDK 事实:`PBT_APMRESUME` 宏不存在(唤醒只有必发的 `PBT_APMRESUMEAUTOMATIC` 与其后仅在用户输入唤醒时追加的 `PBT_APMRESUMESUSPEND`,后者是前者子集、两个都认会一次唤醒两次回调);SDK 10.0.26100 已把 `PBT_*` 常量收编进 winuser.h,根本没有独立 `pbt.h`,显式 include 它反而 C1083;`WTSRegisterSessionNotification` / `NOTIFY_FOR_THIS_SESSION` 声明在 `wtsapi32.h`,而 `WTS_SESSION_LOCK` 等消息码在 winuser.h——只缺 include 时报函数未声明、消息码不报错,易误判成「头文件没问题」。
- shim 平台差异:`dlfcn.h` 按 `__linux__` 守卫;MSVC 的 `M_PI` 需 `_USE_MATH_DEFINES`;`base::FilePath` 在 UNICODE 构建下是 `std::wstring`,统一经 `FromUTF8Unsafe / AsUTF8Unsafe` 进出;Windows 无 Popover、无 `SetOverlayScrollbar` / `Clipboard::Selection` / `Tray::SetTitle` 等,shim 降级空操作;`operator new/delete` 重定向 `malloc/free`(moon 运行时以 MOONBIT_ALLOCATOR=SYSTEM 编译);控件 HWND 须经 `dynamic_cast<nu::SubwinView*>(GetNative())->hwnd()` 取,`GetNative()` 本身不是 HWND。
- 原生子控件滚动后 HWND 不随容器移动(悬浮遮挡):`View::Layout()` 强制重摆,scroll 封装已挂 on_scroll,回调经 0ms 定时器推迟到布局完成后执行;输入框内阴影是 `WS_EX_CLIENTEDGE`,borderless 须清 STATICEDGE / CLIENTEDGE / WS_BORDER 三者;DatePicker 不显式给宽只显示年份;字形小图标跨平台不一致,组件内一律 Painter 矢量自绘。

### 链接参数(moon → cl / link)

- `cc-link-flags` 被原样拼进 cl 命令行,GNU 风格 `-L/-l` 报 D9002;正确做法是写链接输入(`build/yue_mbt.lib setupapi.lib …`),cl 把 .lib 位置参数转交 link,系统库由 LIB 环境变量解析。
- 路径分隔符必须正斜杠:反斜杠被 moon 参数解析吃掉,报 LNK1104。
- 官方 CMakeLists 系统库清单缺项,照抄报 144+ LNK2019;prepare.py 清单已补齐。
- CRT 必须与 moon 一致为静态 /MT:CMake 多配置生成器忽略 `CMAKE_BUILD_TYPE`,`cmake --build` 必须带 `--config Release`(prepare.py 已自动化),否则 LNK4098 + `__imp__*` 未解析。
- **exe 控制台黑框已由库内链接机制根治(新栈，2026-10-12 Windows 实测)**：`gui/win/win_gui.c` 里放 `#pragma comment(linker, "/SUBSYSTEM:WINDOWS")` 与 `/ENTRY:mainCRTStartup`，整体在 `#if defined(_WIN32) && defined(_MSC_VER)` 内；该文件与 `stub.c` 一起列在 `gui/win/moon.pkg` 的 `native-stub` 里。pragma 落进目标文件的 `.drectve` 段；moon 会把 native-stub 的 C 源直接编进 exe 构建（cl 命令行里能看到 `win_gui.c`），但链接器只认**实际被抽取**的归档成员的 `.drectve`——所以文件里另留 `wm_win_gui_marker`，由 `win/window.mbt` 的 `init_backend()` 以 `ignore(wm_win_gui_marker())` 引用：这个引用就是抽取锚点，而 `core/app.mbt` 的应用路径会调 `init_backend()`，故依赖方零配置拿到 GUI(2)。`/ENTRY:mainCRTStartup` 不能省：换子系统后默认入口点变成 `WinMainCRTStartup`，而 moon 产出的是控制台形态的 `main()`，不钉回去就报未解析的 `WinMain`。追加参数那条路走不通——用户 `link_flags` 拼在 `/link` 之前，cl 把 `/SUBSYSTEM` 类链接选项当编译选项直接丢弃（D9002）。因此 `release-bin.yml` 从「改写 PE 头兜底」改成**校验**：任一发布 exe 的 OptionalHeader.Subsystem 不是 2 就让 CI 红。实测：`moon build examples/{hello,hello-themed,showcase} --target native --release --strip` 三件套读回 Subsystem 全为 2、无需任何后处理；测试 exe 基本不受影响，只有代码路径走到 `init_backend()` 的那些变成 GUI(2)（实测 `core.whitebox_test.exe`、`ui.whitebox_test.exe`，其余仍 CONSOLE(3)），库门禁仍为 830 条 / 825 过（5 条红是既有的 dbus 会话总线与 `fsx_wbtest.mbt:109`）。GUI 子系统下 stdout 仅管道 / 重定向可见——测试框架正是用管道抓的。
- 换 `yue_mbt.lib` 后 `moon build` 报 no work to do:删 `_build` 下产物 exe 强制重链。
- prepare.py 模式切换坑(prebuilt↔source):`cmake -D` 只在显式传时覆盖 CMakeCache,不传则沿用残留值——旧 build 目录按 prebuilt 配置过(YUE_MBT_PREBUILT=ON)后切源码模式,configure 沿用 ON 导致 GLOB 到的源码一个不编,`yue_mbt.lib` 里只有 shim 一个 obj,最终链接 360 个符号全库缺失。修复:两种模式都显式传 ON/OFF。判定法:`lib /list build\yue_mbt.lib` 数 obj,全量源码构建应有 27 个(Windows)。
- prebuild 的 link_configs Windows 分支曾漏为 `yue/traybus` 单列一份:traybus 不依赖 yue(反向),按「依赖该包的目标」传播拿不到链接配置,`moon test` 链 traybus 测试 exe 时 12 个 `yue_mbt_sys_*` 符号 LNK2019;Linux/macOS 分支本就单列,Windows 补齐后三平台一致。

### manifest

- moon 的链接参数拼接行为(Windows 实测):按 main 包的依赖闭包把每个带 link_configs 的包的 flags 各拼一遍,并对 blackbox 测试目标把「被测包」的 flags 额外再拼一遍(被测包份 ×2)。`.lib` 重复列出无害,`manifest.res` 重复列出则同名 MANIFEST 资源进两次 → CVT1100 链接失败。早期「moon 新版给 exe 自带 MANIFEST 与我们的 res 冲突」的结论有误:mt 实测 moon 链的 exe 不含任何清单资源,冲突的「另一份」始终是重复传入的 res 自己(为 traybus 补 Windows 链接配置后,凡同时拼两份 flags 的目标即触发)。
- 通道探索结论:`/MANIFEST:EMBED` `/MANIFESTINPUT:` 等链接选项放进 link_flags 会被 cl 当编译选项丢弃(D9002,`/link` 之前的链接选项不传递);`#pragma comment(linker,"/manifestdependency")` 依赖链接器开 /MANIFEST,moon 的链接不开(moon 链的 exe 旁也无外部 .manifest 文件);prebuild 的 stdin 只有环境变量快照与 module_root,无目标/包信息,无法按目标输出差异化配置。
- 最终方案:manifest.res 不进默认 link_flags——开发 / 测试 / moon run 零配置。无清单的运行代价不止视觉退化:真机 Win10 19045 实测消息框点击按钮进程即崩——`TaskDialogIndirect` 只有 comctl32 v6 才按序号 345 导出,无清单加载的是 v5.82,其导出表序号 345 指向无关函数,libyue 按序号取址拿到非空垃圾指针直接调用即 UB(python ctypes 探针证实解析出非空地址;MoonBit 探针复刻同用法三连跑全干净退出,UB 非确定性,单次不复现不能下结论)。fork 修复(mbt.13):MessageBox 解析序号前先读 comctl32 的 DllGetVersion,主版本 ≥6 才调用;低于 v6 走经典 `MessageBoxW` 降级(图标按 TD_*_ICON 映射 MB_ICON*,≥2 个自定义按钮时 MB_OKCANCEL 且确定返回首个按钮响应,否则 MB_OK、响应为取消语义),弹窗可用性不受清单影响;OnClose 统一 PostTask 回 UI 线程(原空解析路径在后台线程直接回调也是跨线程隐患)。降级初版是「解析为空即直接关闭」,真机反馈表现为「点消息框没反应」,故补 MessageBoxW 降级;再版真机反馈「有图标按钮没文字」——TaskDialog 的主文字在 `pszMainInstruction`、仅补充文字在 `pszContent`,而 `SetText` 只写前者,降级须把两个字段拼接进 MessageBoxW 的单行文本。分发型构建设 `YUE_MBT_KEEP_MANIFEST=1`:res 随 yue 份传入,moon build 的 main 包对每份 flags 只拼一遍,恰好嵌入一份清单(Common-Controls v6 + supportedOS,mt 实读验证),v6 下有真 TaskDialog;全仓 `moon test` 勿设此开关(blackbox 被测包双拼必炸)。release-bin.yml 已按此配置。
- 环境变量改变 link_flags 后 moon 偶发沿用旧配置不重链:设 / 去变量后行为不变时,`moon clean`(或删 `_build` 下产物 exe)兜底。

### 运行期差异

- **2026-09-25 整树回退至 09-23 晚 f3ba8bf 版本(用户拍板)**:09-24 起为「表单页滚动原生子控件跟随/切页横线/tooltip 不显示」做的整条修复链(第一代 0ms 重摆 → fork 递归下钻 → 去 WS_CLIPCHILDREN → 平移传导 → 像素搬运 → 补画次序 → 切页性能合并,30+ 笔,含 fork ba479418/e373e60a/f4528cb8/cf308737 与浏览器包拆分、tooltip 自绘三代)经真机多轮复验为**净负担**——每轮在旧病未根治的同时引入新病(卡顿/蓝影/横线复发/重影/悬浮/撕裂),应用户要求整树回退,native 钉回 v0.15.6-mbt.12。核心教训:**原生 HWND 与自绘内容混排的「同步层」修复在真机连续失败——任何此类修复必须真机单点验证通过后才可叠加下一层,禁止多修复捆绑推进**;被回退各方案的全过程根因分析见 git 历史 09-24~09-25 各提交说明与 fork 仓库同期提交。回退后接受的已知状态:Windows 原生 tooltip 不显示(原生路径依赖 comctl32 v6 清单)、滚动中原生输入框靠 update_layout 兜底跟随、切页/滚动可见横线(WS_CLIPCHILDREN 固有)。**回退后按用户逐项挑选捡回**(同日):浏览器包拆分(含按库形态分化的链接修)、result 符号矢量自绘、cursor_group 光标组、网络状态 label() 与 Linux 初值派发两修、Windows live-resize 位图占位(纯 shim subclass)、Entry 滚轮放行(fork 7f57e87f,经 v0.15.6-mbt.18 预构建带入;fork 侧未选的 ba479418 已在 3f8e8935 撤除后再出包);未捡回:tooltip 自绘气泡、prepare 追打补丁机制与全部滚动/切页系修复。**悬浮滚动条 Windows 形态后续经真机验收捡回**(同日单独一批):只移植形态本体(host 包装+自绘 thumb+host 分支内 flex/basis 0),9-23 晚基线的 update_layout 跟随兜底原样保留、非 Windows 分支不动;原提交捆带的「删兜底+无条件 basis 0」(aab1a74 所治的塌陷病根)未随入。
- MoonBit 泛型方法的具体类型误传(FFI 句柄类参数):`MessageBox::run_for_window` 曾把 `Window` 结构体直接传给期望 `View` 句柄的 extern(C 侧 `void*` 收到 MoonBit 堆地址而非注册表 id),`CastTo<nu::Window>` 静默失败 → 消息框无父窗口 + 同步路径假死;判定法:MoonBit 生成的 C 原型第二个参数是 `struct ...Window*` 而非 `void*`。凡 FFI 声明带句柄参数,一律用 `View`(external)类型,具体控件 struct 在 MoonBit 侧 `.view()` 解出句柄再传;异步 `show_for_window` 与同步 `run_for_window` 必须同口径。另注:moon 的增量判断不可靠,改 shim/库后 `moon build` 可能报 up to date 不重链,须删 `_build` 下产物 exe 强制重链(否则探到的是旧库行为)。
- 显隐页切换后内容消失(tabs_t 等 set_visible 切换场景,真机实测):libyue win 的 `View::Layout()` 只向 `IsContainer()` 的父传播(`if (GetParent() && GetParent()->IsContainer())`),Scroll 不是 Container——挂在 Scroll 内容里的子树做显隐切换(set_visible → yoga display 切换)后,传播链在 Scroll 处中断,yoga 根永不重算,恢复显示的页拿 0 高尺寸;页内容无显式高度时被压成 padding 之和(实测页高 50→16,内容整块消失)。GTK 端由 gtk size-allocate 全量重排掩掉,Windows 独有。修复:shim 的 `yue_mbt_view_layout`(即 update_layout)改为沿父链遍历到根容器再 `Layout()`,tabs_t 的 `sel.subscribe` 在显隐翻转后补一次 `update_layout(outer)`;探针(页内容 on_draw 自证 + bounds 打印)验证每次切换绘制到位、页高稳定。注意:只对 root 的直接 flex 子场景不触发(根重算一直有),必须经 Scroll 的内容树才断。
- 显隐页切换消失·三层嵌套残余场景(showcase 结构:页容器 set_visible 切页 + scroll + section + tabs_t,真机仍复现):页签切换时,`Container::Layout` 的 dirty 自愈分支(view.cc 里自带 TODO 注释的那条)会用 display 切换中间态的 yoga 值分配外层容器——并列 flex:1 的页容器被按「scroll 内容测量中间态」分配成压缩高度(实测 210→56),且此后无法自救:自愈传播链断在 Scroll(非 Container),根级重算的 SetBounds 链又断在「尺寸未变的中间容器」(hbox 等尺寸相同 → ViewImpl::SizeAllocate 早退 → 不向下触发子级 UpdateChildBounds)。后果:WM_PAINT 的 dirty 被压缩的页容器裁成 24 高碎片,与页区域(74,278,512,50)不相交,`DrawChild` 的 `child_dirty.IsEmpty()` 整块跳过——on_draw 不触发、bounds 却正常。已试无效(均实测):根级重算 ×N、反转显隐顺序(先 true 后 false)、set_visible 内联根重算(shim 侧)、叶子层显隐(显隐只切页内容)、page_c 的 flexbasis 置 0(CSS flex:1 1 0 语义)。结论:根因在 libyue win 的 yoga 集成本身(dirty 自愈用过期布局 + Scroll 断链的双重断裂),yue/shim 层外部修补打不穿,需 fork 侧根治(备选方向:UpdateChildBounds 的分配前强制 YGNodeCalculateLayout,或 Scroll 内容测量避开中间态)。当前 20babb5 修复对「tabs_t 直接位于 scroll 内容」场景(无页容器层)完全有效,showcase 场景待 fork 侧方案。
- 滚动条形态:libyue 在 Windows 的滚动条是自绘经典样式(Scrollbar 类:轨道 + 箭头按钮 + 常驻占布局),`Scroll::SetOverlayScrollbar` 对 Windows 是空操作(头文件里 API 就被 `#if !defined(OS_WIN)` 排除)——GTK 的悬浮形态在 Windows 没有对应物。统一方案是 yue 层 `attach_overlay_thumb`:policy 置 Never 隐藏平台条,自绘 thumb 用 yoga absolute(right/top/bottom 静态样式)占满右缘全高,可见段在 on_draw 按 Ref 状态绘制——滚动更新只 schedule_paint 零 yoga 重排;浮现/渐隐用 clear_timeout 可取消的两级定时器(d9→73→隐藏),拖拽依赖按下后的隐式鼠标捕获(拖出仍收 move,见 splitter 条目的 WM_CAPTURECHANGED 适配),thumb 窄条上的滚轮经 on_wheel 手动转发给 Scroll。收口点:declarative `scroll()` 默认形态(Windows 且 overlay=true、未显式 policy)即套 host 容器走它(style 参数挪给 host,Scroll 在内撑满——thumb 的 absolute 定位以 host 为基准,直接挂页面容器会被 padding/margin 带偏);overlay_scroll 组件与 Windows 侧页面滚动同走此路径。Windows 分支保留 on_scroll→0ms 定时器强制重摆原生 HWND 的兜底。
- 系统强调色:`DwmGetColorizationColor` 取的是「窗口颜色化色」——强调色与系统基色的混合,默认配置下与设置页强调色有明显色偏(参照机 Win10 19045 实测返回黄绿 0xFFB7AC00,而设置页强调色为青 0xFF00B7C3);先读注册表 `HKCU\Software\Microsoft\Windows\DWM\AccentColor`(0xAABBGGRR,Win10 1803+ 写入),缺失 / 0 / 0xFFFFFFFF 才回退颜色化色,修复后探针实测 0xFF00B7C3 与设置页逐位一致。回退值的 alpha 位是「强度」非透明度,只取 RGB。
- GetSystemPowerStatus 语义损失(电量查询):ACLineStatus 255(未知)按非在线;BatteryFlag 128(无电池)/ 255(未知)均按无电池;BatteryLifeTime 语义随交直流漂移且常为 -1,统一不给剩余时间(Linux UPower 侧 State 1/4/5 都归"接着电源",两平台口径对齐)。另:满电接着电源时 BatteryFlag=High 不带 Charging 位(实测 percent=100 charging=false),「已充满仍接着电源」在 Windows 上表现为非充电态;电量本身无变化事件(仅电源插拔有),缓慢放充电要靠轮询兜底(showcase 系统页 30s set_timer + 插拔事件即时刷新,同一查询口径)。
- `AttributedText` 区间字体 / 颜色:上游 Windows 只支持全文(区间 CHECK 崩,GDI+ 无富文本),fork mbt.9 自建分段布局器(run 存储 / 流式折行 / 测量绘制同源),MoonBit 层降级守卫已删,三平台语义一致。坑:`Gdiplus::Font::GetHeight` 重载是 `(const Graphics*)`,传引用编不过。
- `Color::Get(Border)` 触发 NOTREACHED 返回垃圾色:shim 对 Border 用 `GetSysColor(COLOR_WINDOWFRAME)`。
- 自绘字体发虚:libyue GDI+ 画笔写死灰度抗锯齿,prepare.py 幂等补丁换 `TextRenderingHintClearTypeGridFit`。
- 系统通知:WinRT toast 按 AUMID 查 notifier,未设 AppUserModelID 时静默失败;shim 首次通知前自动设 AUMID 并写注册表 DisplayName。
- 浏览器优先 WebView2(loader / 运行时缺失自动回退 IE);WebView2 跟随系统代理,代理失效机器设 `LIBYUE_WEBVIEW2_ARGS=--no-proxy-server` 直连(prepare.py 补丁经环境变量注入 AdditionalBrowserArguments);demo:// 自定义协议在 WebView2 下无效(IE 路径可用)。
- win32 的 Group / Scroll 不按内容自增长:须显式高度;ScrollImpl 滚动范围只认 SetContentSize,prepare.py 补丁在未显式设置时向内容 yoga 树查自然尺寸。
- 键码与修饰键:Windows KeyboardCode 是 Win32 VK 值,events.mbt 入口已归一化到常量表;修饰键位 Windows 原生 Shift=2 / Ctrl=4 / Alt=8,shim `NormalizeModifiers` 补 OS_WIN 分支映射统一 1/2/4/8。
- 幽灵托盘:异常退出不跑 CRT 静态析构,图标残留;shim 装 atexit / SetConsoleCtrlHandler / SetUnhandledExceptionFilter / SIGABRT 四道钩子,按「属主窗口 + 图标 ID 区间」补发 NIM_DELETE;taskkill /F 式硬杀无法进程侧根除。托盘图标显示为空白先查资产(曾用 1×1 占位图)。
- Popover 替代实现(无边框 / 不抢焦点 / 置顶小窗):弹窗须补 `WS_EX_NOACTIVATE`(防点击弹层时抢焦点);嵌套滚动下 `GetBoundsInScreen` 有垃圾偏移,锚点坐标改取原生子控件 HWND 的 `GetWindowRect`;close 在 Windows 是销毁语义,复用弹层改 `SetVisible(false)`;点外收起挂 `WH_MOUSE_LL` 钩子,按下不在弹层矩形即 PostTask 收层;弹层背景不随主题,新增 `Popover::set_background_color` 全链路接入。libyue 的 SetVisible / IsVisible 在无 Activate 置顶窗场景不可靠,直接 Win32 `SetWindowPos` + `SW_SHOWNOACTIVATE`。
- autocomplete 键盘导航:Windows 分支在 Entry 挂 on_key_down(↑↓ 高亮 / 回车选中 / Esc 收起);单行 EDIT 无垂直居中样式,`entry_vcenter` 按字体行高收窄控件高度均分 margin;RichEdit 恒黑字不随主题,`Entry::set_colors`(EM_SETBKCOLOR + CHARFORMAT2)接入主题链路。
- 原生控件暗色:真 Win32 通用控件(RICHEDIT50W / SysListView32 / SysDateTimePick32 等)均不跟系统暗色;RichEdit 可经消息通道暗色化;Table 不可行(custom draw 自绘白底覆盖外部消息);正式方案 = 组件库全自绘,原生暗色列为已知边界。
- 命中测试与绘制层级方向相反:上游 `FindChildFromPoint` 正序遍历,后挂的全屏遮罩视觉在上、事件却穿透到先挂的容器(dialog 关不掉、点击穿遮罩)——fork mbt.6 改倒序遍历对齐绘制层级。凡「视觉在上层收不到事件」先查命中遍历方向。
- 滚轮被最外层 Scroll 直接消费不下发,嵌套滚动与自绘 canvas 收不到:prepare.py 补丁(`patch_win_wheel_dispatch`)按 FindChildFromPoint 下发光标下子视图;shim `yue_mbt_view_on_wheel` 补 Windows 分支,换算 WM_MOUSEWHEEL delta。
- 文字测宽与绘制不一致:`GetBoundsFor` 用 GenericDefault(带 overhang)、`DrawString` 用 GenericTypographic,手动 `x=(宽-测量宽)/2` 摆位必左偏;摆位一律用 `align=Center/End` 交给平台,测宽仅用于算容器宽度。
- splitter 两坑:Windows 端显式 `SetCapture` 会触发 `WM_CAPTURECHANGED` 拆掉隐式捕获(已持捕获须跳过);`flexbasis:"50%"` 百分比字符串仅 GTK 端解析,跨平台统一写像素。
- Entry 无限递归案例:非 Linux 分支两函数互调栈溢出,MSVC C4717 早已告警——「逻辑必死」类警告应按错误对待。GUI「无窗口」用 `Get-Process <name> | Select MainWindowHandle` 判定;MoonBit println 管道下全缓冲,进程被杀即丢,插桩用 stderr。
- mount_window 在 handle 回调执行后自动激活显示,消费方无需手动 activate。
- 平台信息 / 区域 / 缩放 / 剪贴板 / 定时器 / 全局快捷键 / 全局鼠标轮询 / 画布(GDI+)实测正常。
- 离屏 Canvas 在 Windows 不能早于 initialize 创建:`Canvas::new` 一句即 0xc0000005 访问违例(最小复现不含任何绘制调用)。根因:Canvas / DoubleBuffer / Painter 构造依赖 `nu::State`——GDI+(`GdiplusHolder`)、默认字体、NativeTheme 都随 State 建立,而 State 由 initialize() 创建;曾试在 canvas_new 里裸 `GdiplusStartup` 兜底仍崩(State 还有别的空解引用),正解是 `g_state` 为空时先走与 initialize 相同的 `yue_mbt_app_init()`。对照 Linux:cairo image surface 无 State 依赖,离屏几何无需 initialize 可跑(仅文本路径要 GTK 栈,见「自绘画布与图表渲染」);Windows 连几何都起不来,shim 兜底后三平台「离屏 Canvas 随处可用」语义一致。charts_wbtest 的离屏几何基准据此在 Windows 通过(17/17)。
- 平台无关函数误入平台分支的桩:wire 的 `'d'` 编解码走 `yue_mbt_sys_f64_to_bits/from_bits`(纯位重解释,memcpy 实现),实现却放在 OS_LINUX 分支、非 Linux 桩恒返回 0——Windows 上 3 个纯内存 wire 测试解码全 0 失败(wire 编解码测试不依赖总线,非 Linux 也跑)。移到平台分支外修复。判定法:桩清单逐个过「是否真平台专属」,纯计算 / 纯内存逻辑不进桩(与 macOS 小节「`#else` 兜底误吞 macOS」同族)。
- 单实例消息窗口是仓内首例自有 WNDPROC/窗口类代码(此前 grep 0 命中):类名由 app_id 派生(`moonbit_libyue_instance_<app_id 点换下划线>`),必须建在运行 libyue 主循环的主线程;WM_COPYDATA 由 SendMessage 同步派发到 WNDPROC(不走消息队列),收端 MessageLoop::PostTask 抛回主循环再触发 MoonBit 回调,避免在对方进程的 SendMessage 栈里执行应用代码。互斥体用 Local\ 会话命名空间免提升;同进程对同名二次 CreateMutexW 会命中 ERROR_ALREADY_EXISTS,以 static 句柄守卫做幂等。【待真机验证】消息窗口在 libyue 主循环下的实际派发、SetForegroundWindow 在前台互斥下的置前成功率、旧构建混跑时标题查找兜底路径。
- UI 线程 COM 套间必须按 STA 建立,否则文件对话框卡死/崩:公共文件对话框 `IFileDialog::Show` 要求 STA——UI 线程 COM 从未初始化时 `CoCreateInstance(CLSID_FileOpenDialog)` 直接失败(库内空指针解引用),被应用侧后置调用抢先初始化成 MTA(典型:旧版在 UI 线程调 `CoInitializeEx(MTA)` 的网络查询)时 `Show` 永久挂死,现象即「点打开/保存文件应用直接卡死」。修复:shim `yue_mbt_app_init` 建 State 后立即 `State::InitializeCOM()`(ScopedCOMInitializer STA + OleInitialize,幂等);此后 UI 线程上的 `CoInitializeEx(MTA)` 只会得到 `RPC_E_CHANGED_MODE`,本地 COM 对象不受影响。与「NLM 查询挪后台 MTA 线程」互补:后台线程的 COM 初始化是线程局部的,不替代 UI 线程自己的 STA。验证:真机点开/保存文件对话框正常弹出、选完路径回传。
- Windows 切主题无全局重绘,残留旧像素成"重影":GTK 端 `theme_apply` 有 CSS 重建 + 逐窗口同步重绘兜底,Windows 端原本只通知订阅主题的自绘视图,漏订阅区域(以及被隐藏/移走的原生子窗口背后的区域)留旧像素,鼠标划过触发局部失效才消失。修复:shim `yue_mbt_repaint_all` 补 Windows 分支——`EnumWindows` 过滤本进程可见、无属主的顶层窗口,`RedrawWindow(RDW_INVALIDATE|RDW_ERASE|RDW_ALLCHILDREN)` 整体失效连带原生子窗口,只失效不同步绘制(WM_PAINT 交回消息循环);`theme_apply` 的 windows 分支调用它。验证:真机来回切深浅,头部/页面无残影。
- 零高度自绘视图整段静默不渲染(table_t 文字列消失):`ViewImpl::Invalidate` 对空尺寸提前返回,childless 且无高度样式的 on_draw 容器被 yoga 测高为 0 后永不绘制——table_t 的 CellText 单元格正是这种容器(文字经 on_draw 自绘、无子节点),现象为整列文字不可见而表头/斑马纹/复选框正常;GTK 端裁剪行为不同故未暴露(同函数族此前已踩过「GTK 小单元格路径填充不渲染」的反向坑)。修复:`cell_view` 给 CellText 容器补 `minHeight=row_height`。教训:自绘 on_draw 容器必须有非零尺寸来源(显式高或子内容),「无子节点 + 自动高」在 Windows 等于不画;离屏 Canvas 像素探针可先排除绘制链本身(AttributedText 带色在 Windows 画布上逐位正常)。
- GDI+ 混合模式仅 Normal/Copy 生效:`PainterWin::SetBlendMode` 只把 Copy 映射为 `CompositingModeSourceCopy`,其余全部落 `SourceOver`——GDI+ `Graphics` 只有这两种合成模式,Multiply/Screen/Difference/Xor 等静默无效。离屏像素探针实测:Multiply 交叉区 (128,128,255) 与 SourceOver 逐位一致(数学期望 #8028FF)。平台能力缺口,不修库(换 D2D 才有完整混合);showcase 画布演示在 Windows 回显「此平台仅 Normal 生效」,`docs` 中 `Image::write_to_file` 平台口径同步修正(Windows GDI+ 编码器 png/jpeg 可用、mac 发行包未编译恒失败)。
- 原生 Tab 添加首页即回调 `on_selected_page_change`(内部初始选中,非用户切换):回调登记先于加页时,挂载期会空触发(declarative `tab()` 曾因此让切换计数演示凭空起跳);登记挪到加页循环之后即避开。

### MoonBit 原生 GUI 栈 · Windows 构建基线(W0/W1,新栈 Windows 化首批)

- **环境**:Windows 10 19045 + VS BuildTools 2022(MSVC 14.44)+ SDK 10.0.26100,moon 0.1.20260920;新栈特性分支 `feature/yoga-mbt`。目的:新栈完成项(TODO.md 全部 `[x]`)逐项在 Windows 验证,Windows 地基(Win32 后端)先行。
- **moon native 在 Windows 开箱即用,不需要 vcvars**:普通 shell(Git Bash / CMD)直接 `moon test`,moon 自行定位 MSVC 工具链并编译链接(报错码是 cl/link 的 C2059/C1083、lib.exe 中文输出可佐证),与老栈时代「须在 Native Tools Command Prompt 执行」的记录不同——那条管的是老栈 prepare.py/cmake 链,新栈构建不适用。
- **workspace 任一成员的 prebuild 硬失败会挡死全部 moon 命令**:`modules/ffmpeg-mbt/prebuild.py` 缺 pkg-config 即非零退出,`moon.work` 五成员里任何包跑 check/test 都先过它;而主 `scripts/prebuild.py` 非 Linux 本就优雅降级(空 link_configs)。修复:ffmpeg prebuild 补「非 Linux 输出空 link_configs 且 exit 0」分支(Linux 行为不变),与主脚本同口径;ffmpeg 消费方(gui-media)本就是过渡期红点,不在新栈验证路径上。
- **非 Linux 占位桩的 GLib 类型在 MSVC 下语法错误**:`win/gtk_stub_portable.c` 用 `gint32` 作占位函数返回类型——该文件整体包在 `#if !defined(__linux__)` 里,Linux 上从不编译故从未暴露;MSVC 下 6 处 C2059(无 glib.h,`gint32` 未定义)。改 `int32_t`(ABI 同为 32 位整型,extern 原型不变)。教训:占位桩也要按「能在 Windows 真编译」的标准写,MSVC 是占位桩的第一位真实读者。
- **`chensuiyi/subproc` 的 C 桩用 POSIX `poll.h`,Windows 编译必炸**:`sys` 的 `procrun.mbt` 基于 @subproc(自己注释就写着「仅 Linux」),sys 与依赖它的 chart 包全被连坐编译失败。Windows 子进程层(spawn→限时回收→输出捕获)归 W14 用 CreateProcess 重做,替换 MoonBit 侧的 @subproc 依赖;在此之前 sys/chart 在 Windows 不可验证。
- **分包测试的连带编译问题 Windows 与 Linux 同款**:workspace 内 cd 进成员目录裸跑 `moon test` 会把主包红点一并编进来,须 `-p` 限定包/模块名(Linux 侧早已记录,此处确认 Windows 同款)。
- **验证**(2026-10-11,本机):`moon check` 287 errors / 68 warnings 与 Linux 基线**逐字持平**;纯 MoonBit 包全绿——yoga-mbt 96/96、core 62/62、input 10/10、mdview 26/26、theme 7/8(挂的「控件高度基准」一条依赖 Pango 字体实测,占位文本后端必挂,归文本后端批)、icons 2/4(挂的两条是「真画出像素」绘制断言,归渲染后端批);ui 因 `TextMetrics::unwrap` 空值 panic(同归文本批)、sys/chart 因 subproc 编译失败(归 W14)。

### MoonBit 原生 GUI 栈 · Windows 窗口地基(W2,stub 合一 + Win32 后端)

- **架构定案:平台桩合并为单一 `win/stub.c` 三分支**——`_WIN32` 真 Win32 实现、`WM_STUB_GTK` 真 GTK 实现(prebuild 在 Linux 带 `-DWM_STUB_GTK` + pkg-config 头编进 `libyue_win_stub.a`)、其余平台占位;原先的 `gtk_stub.c`/`gtk_stub_portable.c` 两文件删除。合并的物理约束:moon 的 native-stub 会把 moon.pkg 里列的每个 .c 在**所有平台**各编一遍,而 GTK 头路径只有 prebuild 拿得到,所以装 GTK 的分支必须挂在「prebuild 独有的宏」下——Linux 上 native-stub 的那次编译(无宏)落不进任何分支,编出空 TU,避免与 .a 双定义;这正是原两文件结构的等价形态,只是收敛进一个文件。空 TU 在本链已验证可行(原 portable 文件在 Linux 就是空编)。
- **moon native-stub 在 Windows 直接可见 `windows.h`**(探针包实编译链接验证):moon 自行定位 MSVC 工具链并设好 SDK 包含路径,Win32 桩可以直接走 native-stub,无需 prebuild 代编;prebuild 的 Windows 分支只下发系统库链接参数(`user32.lib gdi32.lib imm32.lib advapi32.lib`,MSVC 位置参数口径)。
- **MSVC 的 `IDC_*` 光标宏默认走 ANSI 变体**:不定义 UNICODE 时 `IDC_ARROW` 是 `MAKEINTRESOURCEA` 形态(LPSTR),传给 `LoadCursorW` 的 `LPCWSTR` 形参报 C4133;桩文件顶部强制 `#define UNICODE`/`_UNICODE` 即全 W 化。
- **按键映射口径与 GDK 对齐**:字符面在 `WM_KEYDOWN` 里用 `ToUnicode` 直取(ASCII/Latin-1 原值、其余 `0x01000000|unicode`,与 `gdk_unicode_to_keyval` 一致,`keysym_to_text` 两条 Latin-1/UCS 路都能吃);**Ctrl 组合键要把 `VK_CONTROL` 从 `GetKeyboardState` 的状态副本里摘掉再换算**——带控制位会吐控制字符(`\x01`),内核的 Ctrl+A(判 `keysym=='a'`)就失效了,摘掉后与 GDK 的「keyval 取基准字符、修饰走 mods」同语义;AltGr(Ctrl+Alt)因此拿不到特殊字符,留 IME/后续批次。死键(`ToUnicode` 返回负)不推事件,组合由布局状态自然发生在下一个键上。Alt+F4 放回 `DefWindowProc` 生成 `WM_CLOSE`(与「窗口管理器请求关闭」同语义),其余系统键(F10 菜单/Alt+空格)自己吃掉。
- **贴屏无需换序**:`render` 的 Bitmap 就是 cairo ARGB32(小端字节 B,G,R,A 预乘),GDI 的 32bpp `BI_RGB` 顶底 DIB(负 biHeight)字节口径完全一致,`StretchDIBits` 直贴;present 只记地址 + `InvalidateRect`,真贴在 `WM_PAINT` 里(与 GTK 桩「draw 回调才贴」同口径,避开死窗口期)。`WM_ERASEBKGND` 返回 1 防闪。
- **循环配方**:等待用 `MsgWaitForMultipleObjectsEx(0,NULL,timeout,QS_ALLINPUT,MWMO_INPUTAVAILABLE)`(有未派发消息立即返回,负超时即 INFINITE);跨线程唤醒是 `HWND_MESSAGE` 仅消息窗口 + `PostMessageW(WM_APP+1)`;泵是 `PeekMessageW` 排空 + `DispatchMessageW`,**不做 TranslateMessage**(WM_CHAR 不消费,字符面在 WM_KEYDOWN 直取)。
- **槽位与创建时序**:`WM_SIZE` 在 `CreateWindowW` 期间就会到达,槽号必须经 `CREATESTRUCT.lpCreateParams` 在 `WM_CREATE` 里先行落位(`GWLP_USERDATA` 建完再设会丢掉首条 WM_SIZE);客户区口径用 `AdjustWindowRect` 把外框撑到客户区恰为 width×height。DPI 用 `SetProcessDpiAwarenessContext` per-monitor v2(经 GetProcAddress 取,老系统缺导出不断链),整栈物理像素,`WM_DPICHANGED` 按建议矩形重摆、WM_SIZE 记账。
- **验证**(2026-10-11,本机):`moon build examples/native-window` 全链链接成功;冒烟 `NATIVE-WINDOW-OK frames=45`(5s 定时退出,exit 0,45 帧上屏即 present→WM_PAINT→StretchDIBits 通);core.App 宿主形态用用完即删探针验 `WIN-SMOKE-OK`(App::new + 声明式挂载 + timer + 干净退出);core 62/62 复绿(测试不调 App::new,不会弹真窗),全仓 check 287/68 持平。band_h=0/0/0/0 属文本后端占位(W5)。

### WebView2 webview 桩与 ffmpeg Windows 真链接(平台批,2026-10-13)

- **WebView2 自定义 scheme 必须在 Environment 创建时预注册**:没经 `ICoreWebView2EnvironmentOptions4::SetCustomSchemeRegistrations` 注册的自定义 scheme,导航直接失败(真机实测失败码 9,换 8)。MoonBit 层 `webview_predeclare_schemes` 名单经新 extern 流到 C 桩全局名单,`wb_create` 传手写 `WbOptions`(四子接口嵌套 COM)由引擎在 Environment 创建时取名单。
- **COM propget/propput 手写实现少写 `self` 参数会在 x64 上静默写坏 vtable**:`get_bool(BOOL *value)` 按单参声明,引擎按 COM 约定传 `(self, &value)` 两参——x64 下第一参数 RCX=self 被当成 value,`*value = FALSE` 实际把对象首 8 字节(lpVtbl!)写成 0,之后任何对该接口的调用 = 调 NULL vtable = segfault。put_str/put_bool 同病(少读 this,x64 恰好不炸)。**C 无函数签名检查,vtable 指针赋值只有 C4113 警告**——每个手写 COM 方法的参数表都要逐个对着头文件数。
- **`GetCustomSchemeRegistrations` 返回的数组必须 `CoTaskMemAlloc`**:契约是调用方(loader)用 `CoTaskMemFree` 释放——把静态数组指针交出去,loader 对它 free 直接触发 `0xC0000374`(堆损坏),且崩溃点在引擎内部、get_regs 返回之后,栈上完全看不出与 registration 有关。排查用了 AddVectoredExceptionHandler(打印异常码/地址/所属模块)+ HeapWalk 全遍历堆校验(stderr 无缓冲,segfault 下 stdout 缓冲会丢)。
- **MSVC 默认按系统代码页(GBK)读无 BOM 的 UTF-8 源文件**(C4819):中文注释与 ffmpeg 头的 UTF-8 字节序列被 GBK 误读吞行——注释行末字节恰与换行组成 GBK 双字节时,下一行被并进注释,级联出几百条「非法存储类/未定义标识符」。修法:`stub-cc-flags` 加 `/utf-8`(ffmpeg-mbt 的 vendor 头同样中招,rational.h 也报 C4819)。
- **moon prebuild 的 `vars` + moon.pkg `${build.VAR}` 替换可用**(0.1.20260920 实测):prebuild 输出 `{"vars": {"FFMPEG_INC": "..."}, "link_configs": [...]}`,moon.pkg 写 `link: { "native": { "stub-cc-flags": "/utf-8 -I${build.FFMPEG_INC}" } }`——vendor 头路径不经静态写死即可注入 stub 编译;`stub-cc-flags` 只对 native-stub 编译生效。未下发变量的平台给占位值(`/usr/include` 或 `.`)避免 `${...}` 落空。
- **ffmpeg dev 内容 vendor 口径**:BtbN `ffmpeg-n9.0-latest-win64-lgpl-shared-9.0` 的 include 头 + 7 个导入库 + LGPLv3 LICENSE 共 2.5MB 进 `modules/ffmpeg-mbt/vendor/`(**选 lgpl-shared 不选 gpl-shared**——动态链接场景 LGPL 义务最小);运行期 dll(150MB)不进仓库,与 exe 同目录或放 PATH。`ffmpeg_stub.c` 删 `_WIN32` 全错误降级分支,三平台实现同源(ffmpeg API 本身跨平台,原 Linux 分支无 POSIX 特有调用,原样可移)。
- **miniaudio 在 Windows 零额外链接库**:WASAPI/COM/dsound/winmm 全走运行期 LoadLibrary,`gui-media/prebuild.py` 空 link_configs 即正确形态(非降级)。gui-media 24/24 全过含 AudioPlayer 冒烟(pump 33 拍播完 1 秒素材,WASAPI 设备链真出声);ffmpeg-mbt 6/6(ogg/m4a/wav + 视频真解码)。
- **GUI 子系统示例的无人值守收尾**:`native-web` 不设自杀点(人工验收要逐项点过去),自动化跑法须 `taskkill /IM`(发 WM_CLOSE,app.run() 正常返回后统计才 flush)——`kill -9` 会连 stdout 缓冲一起丢。

### WebView2 跨 HWND 焦点与滚轮转发(焦点批,2026-10-13)

- **GotFocus/LostFocus 挂在 Controller 上,不在 ICoreWebView2 上**:`add_GotFocus/add_LostFocus` 是 `ICoreWebView2Controller` 的方法;且这对事件的 `Invoke` sender 参数是 `ICoreWebView2Controller*`(事件 handler 宏写死 sender 为 `ICoreWebView2*`,x64 下 C4113 之外会真崩)——这对 handler 手写、不走宏。
- **滚轮投递规则是「发给焦点窗口」,与鼠标位置无关**,WebView2 拿焦点后宿主滚动区断轮。修法双向各一半:① 本桩 subclass 引擎输入窗(`Chrome_WidgetWin_1`,controller 创建同步完成后在面板 HWND 下按类名 FindWindowEx 找;找不到只少一半转发、不算错)——焦点在网页、鼠标不在其上时把滚轮 SendMessage 回宿主主窗;② 宿主 `WM_MOUSEWHEEL` 分支先经 wheel probe(web 桩 create 时经 `wm_set_wheel_probe` 函数指针槽注册,避免 win→web 反向符号依赖)问「该屏幕坐标是否落在网页上」,在则原样转给 Chrome 窗。两半合起来等价 GTK「悬停即滚」观感。subclass 用 SetProp 存原 proc 与自身 HWND,destroy 时还原+RemoveProp。
- **宿主主动给网页焦点**:`MoveFocus(COREWEBVIEW2_MOVE_FOCUS_REASON_PROGRAMMATIC)`(WebKit 分支是 `gtk_widget_grab_focus`),随后 GotFocus 事件照发,宿主可做状态联动。
- **焦点事件透出为 kind 16/17(WebView2 独有)**:WebKitGTK 是同树 widget、宿主天然可感知,不发。
- **调试插曲(教训)**:`python -c` 单行脚本对已存在大文件 `io.open(p,'w')` 传错 newline 值,ValueError 在 TextIOWrapper 初始化时抛出——但文件已按 'w' 截空,几百行改动全丢(git checkout 恢复后用 Edit 工具重做)。改大文件永远用 Edit 工具或先写脚本文件再跑,不用内联 python 单行写整文件。

### MoonBit 原生 GUI 栈 · 图片解码后端(W9:Windows 走 WIC)

- **为什么这条是「平台矩阵」的唯一例外**:Windows 的渲染是**纯 MoonBit 光栅器**(零第三方依赖,plan 矩阵定案),但光栅器不负责解码——图片解码只能借系统能力,**WIC**(`windowscodecs.lib`,系统组件,不是第三方包)。此前非 Linux 分支把 `img_*` 整组写成占位 no-op,于是 Windows 上 `Image::new_from_file` 恒返回空图、动图组件退成 0 尺寸;测试侧靠 `decode_available()` / `ui_decode_guard()` 探针跳过(不算红)。本批把 `gui/render/stub.c` 的 `_WIN32` 分支实装。
- **三条 WIC 实测事实**(`experiment/img_probe` 纯 C 探针回证,与 MoonBit 运行时无关):
  1. **WIC 的 GIF 解码器给的是「原始子矩形帧」,不替调用方合成**——`IWICBitmapFrameDecode::GetSize` 报的是**帧矩形**(探针实测 12×12),偏移在 `/imgdesc/Left|Top`(实测 14/14)。Linux 侧 GdkPixbuf 的 `GdkPixbufAnimationIter` 是替我们做了合成的,所以这条差异是本批新踩:整幅合成必须本层做——画布取 `/logscrdesc/Width|Height` 的逻辑屏幕,逐帧按 disposal 收尾(0/1 保留、2 清帧矩形、3 还原到「画本帧之前」的快照)。
  2. **透明索引已由 WIC 应用**(帧像素 alpha 实测只有 0 与 255 两档)。GIF 的透明语义是「此处保留前帧」而非混合,所以合成规则就是「alpha==0 跳过、其余整像素覆盖」,不需要 alpha 混合。
  3. **`/grctlext/Delay` 单位是厘秒**(GIF 规格),×10 才是毫秒;缺省/0 统一成 100ms,与 Linux 分支同口径。
- **预乘口径与 Linux 逐字同式**:WIC 转 `GUID_WICPixelFormat32bppBGRA`(straight)后,本层按 `(c*a+127)/255` 预乘再交给 MoonBit——与 Linux 分支同一公式,保证「编码→解码→再编码」字节稳定(`image_wbtest` 的半透明往返断言就吃这条)。静态首帧的尺寸口径也向 Linux 对齐:**GIF 按逻辑屏幕尺寸合成**,首帧是子矩形时不会被裁成帧矩形大小。
- **动图的内存策略**:像素**按需现解**(不把 N 帧全缓存),合成结果缓在 canvas 上——同一帧被反复取(每拍重绘)时不重复解码;逐帧前进走增量(只收尾上一帧的 disposal),回绕/跳帧才从 0 重放。帧数上限 4096 只防病态文件(内存与帧数无关,但回绕那一拍是 O(n))。
- **帧号语义沿用 Linux 的单调口径**:`img_anim_frame()` 只增不减(显示帧 = 帧号 % 帧数)。因此组件侧 `gif(looping=false)` 的「帧号回到 0 就停」判据**在两个平台都不触发**——这是既有行为,`image_wbtest` 的「帧号等于成功次数」断言正依赖它,本批不改。顺带一条资产事实:showcase 用的 `examples/showcase/assets/dot.gif` 四帧的压缩数据**逐字节相同**、只有局部调色板不同(所以看起来是「同一个点变色」而非移动)。
- **链接面**:`gui/scripts/prebuild.py` 的 Windows 分支新增 **RENDER_PACKAGE** 条目(`windowscodecs.lib ole32.lib user32.lib`)——此前 render 包在 Windows 一条 link_configs 都没有(桩全是 no-op,不需要外部符号),`render.whitebox_test.exe` 一旦调 WIC 就会缺符号。GUID 常量(`CLSID_WICImagingFactory1` / `IID_IWICImagingFactory` / `GUID_WICPixelFormat32bppBGRA`)与 W20f 图标加载同源,C 模式用不了 `__uuidof` 故链接期取。
- **`/utf-8` 不必补**:render 桩的中文注释在 MSVC 按 GBK 误读下只出 2 条 C4819(与改动前逐字持平;`win/stub.c` 是 6 条),无吞行、无语法错——故不引入 `stub-cc-flags`(ffmpeg-mbt 那条是 vendor 头真中招才要)。
- **验证**:纯 C 探针 `experiment/img_probe/img_backend_probe.c`(独立于 moon 工具链,`cl /W4 /utf-8` 直编,include 进 `render/stub.c` 直喂 `img_*` 入口)末行 **`IMG-BACKEND-OK`**,60 条断言全过:PNG 文件/内存两入口尺寸一致且预乘不越界、坏图/NULL/零长/越界句柄/不存在文件全给 0、`dot.gif` 静态首帧 120×120、动图 4 帧 + 延时 400ms + 逐帧前进帧号单调 + 不同帧像素确实不同 + 回绕后显示帧与首帧逐字节一致、释放幂等且释放后全空操作、PNG 经动图入口 `is_static=1` 且 `advance` 恒 0、**子矩形帧合成**(`experiment/img_probe/assets/subrect.gif` 第二帧 12×12@(14,14):画布仍是 40×40、(0,0) 保留第 0 帧的黑、框内偏红)。跑法:先 `cl` 编出 exe 再在仓库根执行 `experiment/img_probe/img_backend_probe.exe .`(资产重建脚本 `make_asset.py` 用 ffmpeg 现场生成 subrect.gif)。`moon check` 库模块零警告。
- **本批未做且不假装完成**:macOS 后端(仍是占位);`looping=false` 的「帧号归零」语义(跨平台既有行为,要改得同时动 `ui/gif.mbt` 与 `image_wbtest` 断言);JPEG/BMP/TIFF 未逐格式单独验(走同一条 `CreateDecoderFromFilename` 嗅探路径,PNG/GIF 已实证);真机观感(showcase 卡片/媒体页的图片区、动图是否在动)归 `测试文档/测试用例.md`。

### 自维持重绘环:present 与 expose 互相点火(2026-10-13 真机反馈)

- **现象**:`examples/native-app` 真机「整体卡顿,滚动/点击/悬浮都有 300–500ms 延迟」,同时「图表推点按钮点了没反应、表格点表头不排序、虚拟表格滚不动」。看代码像三个不相干的 bug,实际是**一个根因 + 一处示例漏接线**。
- **根因(两分支同形)**:`wm_present` 每帧都请系统重画(`_WIN32` 侧 `InvalidateRect(NULL,FALSE)`、GTK 侧 `gtk_widget_queue_draw`),而系统的重画回调(`WM_PAINT` / `wm_on_draw`)又置 `need_draw = 1` → MoonBit 侧 `poll_event` 收到 `NeedsDraw` → `dirty = true` → 全帧重画 → `present` → ……**永动环**。于是:(1) 应用**永不空闲**,`wm_wait` 永远立刻返回(队列里总有 paint 消息),每一拍都在画 1400×3520 ≈ 490 万像素,输入只能排在一整帧之后——这就是 300–500ms 延迟;(2) 一帧里攒下的鼠标移动(高回报率鼠标轻松上百条)把 64 槽事件队列塞满,`wm_push` 的「满了丢弃」把**随后的抬起与滚轮整批丢掉**——这就是「点了没反应/不排序/滚不动」。注意这三条症状在**同一帧里同时成立**:点击的 `Down` 进了队列、`Up` 被丢了,控件停在按下态,看着就是「按钮坏了」。
- **修法(两分支同批改,保持对称)**:重画回调只**贴缓存帧**、不再请求重绘(`WM_PAINT` 只在还没有任何帧可贴时置一次 `need_draw`;`wm_on_draw` 同理)。重绘请求的唯一来源回到 MoonBit 侧的 `schedule_paint`(`@core.invalidate` / `App::schedule_paint`),这也正是本栈既定的契约——**「内容变了才画」**。首帧不受影响:`wm_show` 本来就置 `need_draw = 1`(`wm_mark_draw`)。
- **另一半:队列里合并连续移动**。`wm_push` 里若队列最后一条也是**未消费**的移动,直接替换成新的(位置是状态不是流水)。只在「最后一条也是移动」时替换,中间夹着按下/抬起就不动它,FIFO 语义不破。这一条即使修好永动环也要留着:任何一帧(现在仍有百毫秒量级)期间移动都能攒下几十上百条。
- **窗口高 3520 → 900(示例侧)**:视口剔除(`widget_cull_skip`)只画屏内那部分,**窗口高直接决定每帧像素量**;`enable_root_scroll` 落地后「一屏装下整页」的长柱只剩代价。改成 `APP_WIN_H` 常量,要「一屏看全」改回 3520 即可。
- **表格排序不生效是示例漏接线,不是组件 bug**:表头点击只切 `TableSort` Store(组件**不替使用方排序**,口径早写在 `TableSort` 注释里),示例没订阅它把行序写回 `rows`。补一个 `@ui.sort_rows` 作参考口径(**前导数字优先比数值**——演示数据是「12 处/6 处」这种混排,纯字典序会把 12 排在 6 前面、看着像没排;加**稳定排序**,同键成片时不会乱跳),示例两三行订阅即可。
- **教训**:「永不空闲」类 bug 在真机上表现为**一堆互不相干的功能失效**,而不像性能问题。下次见到「点了没反应 + 卡 + 滚不动」同时出现,先看事件队列的**入队速率与消费速率**,再看有没有自维持的重绘环——两者都会造成「事件被静默丢弃」,而丢弃是没有任何日志的。
- **验证**:`moon check --deny-warn` 库模块与 `examples` 模块零警告(两处注入式探针确认门禁确实覆盖这两个模块);`gui/win/stub.c` 用 MSVC(`cl /c /W4 /utf-8`)单编通过、警告数与改动前逐字持平(仅 2 条既有 C4996);新增 `table_wbtest.mbt` 2 条(排序口径 + 稳定性)。**真机行为(延迟是否真的降到「一帧」、点击是否不再丢)归 `_Windows真机测试清单.md` 复验**。

### Windows 本机库测试三红收口(2026-10-13,W9/排序批跟进)

W9 与表格排序批落库后,Windows 本机库测试长期 3 条红(`moon test` 合并跑在本机还会偶发超时,**分包跑**才稳定)。逐条根因与修法:

- **`moon test` 的测试进程 cwd 是模块根(`gui/`),与调用目录无关**(探针 `yue_sys_getcwd` 实证:从仓根调 `moon test gui/sys` 与从 `gui/` 调 `moon test sys`,进程 cwd 都是 `gui/`)。于是 wbtest 里按仓根写的相对路径 `examples/showcase/assets/dot.gif` 在测试里**永远不存在**,动图解码用例 `None => assert_true(false)` 恒红;`ui_decode_guard()` 也因此探不到图,ui 的动图组件断言一直在静默跳过。修法:测试侧路径改「两候选探测」(`examples/...` 与 `../examples/...` 哪个解得出图用哪个,`image_wbtest` 的 `test_asset` 与 `basic_wbtest` 的 `gif_asset` 同口径),守卫与组件测试从此在 Windows 真跑。
- **`Image::resize` 只开 Cairo 会话,Windows 无 Cairo 后端整帧空图**——放大后取像素得 `(0,0,0,0)`。`Cairo::over` 在无后端平台返回 `None`,原实现直接放弃填充。修法:改走 `Painter::draw_image`(Cairo / 纯光栅两后端都实装的拉伸 blit),平台无关。
- **`compare_cells` 只摘串首数字,不是自然序**——`"虚拟行 3"` 首字符非数字即回落字典序,`"虚拟行 12"` 反而排前面(平台无关的真 bug,Linux 同样该红,只是该用例落库后没赶上过一次绿 CI)。修法:重写为**自然序**(逐字符走,两侧同处数字段时整段按数值比,数值相等视同相等继续,先耗尽者排前),`leading_int` 删除。
- **动图换帧节奏的平台差异(测试口径)**:Windows(WIC)的 `img_anim_advance` 是**一拍一帧**(组件按 `delay_ms` 节奏问一次进一帧,无内部时钟);Linux(io-gif)按虚拟时钟锚定,每拍推进的帧数不同。`basic_wbtest` 的「12 拍 2..6 帧」上限是按 Linux 标定的,改成平台无关不变量「12 拍至少走 2 帧、至多 12 帧(一拍至多一帧的失控护栏)」。
- **验证**:Windows 本机分包全绿——core 132、ui 125、render 43、text/theme/icons 41、sys/input/win/dbus 280、chart/mdview/web 233,**854/854**;`moon check` 零警告。合并跑偶发 SIGTERM 超时为本机现象,CI(Linux)与分包口径不受影响。

## Windows-only 的 `GUID` helper 漏在守卫外:非 Windows 侧整个库编不过(2026-10-14)

- **现象**:`moon run examples/showcase` / `moon test ui` 起不来,报 `sys/sys_stub.c:2023:45: error: unknown type name 'GUID'`(电源方案那批代码)。
- **根因**:`yue_sys_pp_current_guid` / `yue_sys_pp_set` 两个导出函数体内都写了 `#if defined(_WIN32)` 分支 ✓,但它们共用的两条 `static` helper(`sys_pp_guid_string` / `sys_pp_parse_guid`)签名里带 `GUID`,却写在所有守卫之外——`static` 且未被调用也要过类型检查,Linux/mac 上 `windows.h` 没进来了就当场炸。
- **修复**:两条 helper 一起圈进 `#if defined(_WIN32) ... #endif`(它们只在 Windows 分支里被调用,Windows 侧行为零变化)。
- **通用口径**:平台桩里**只要类型来自平台头**(GUID / HINSTANCE / PangoLayout…),函数本体就得整段进守卫,不能只守函数体而把签名露在外面;`static` helper 同样算。加完 C 代码后至少跑一次**非目标平台**的编译(`cd gui && moon check`),这条守卫漏没漏一眼就知道。
- **验证**:`moon check sys ui --deny-warn` 过、`moon build showcase --target native` 链接过、库全包 924/924。
- **同类复发(2026-10-14 windowctl 批)**:同一口径第二次踩——`sys_win_find_ctx_t`/`sys_win_find`/`sys_win_find_cb`/`sys_mon_find_t`/`sys_mon_find_cb`/`sys_monitor_index`/`sys_win_enum_cb`/`sys_wcs_icontains` 这批 `static` helper(签名带 `HWND`/`HMONITOR`/`BOOL CALLBACK`)照旧写在守卫外,Linux 侧 `moon test sys` 报 `sys_stub.c:2338: error: expected ‘=’, … before ‘sys_win_find_cb’`。修复仍是整块圈进 `#if defined(_WIN32)`(两块:枚举 helper、find+标题匹配 helper;`sys_win_blob_t`/`sys_win_blob_append`/`sys_win_enum_ctx_t` 只用 stdlib,留守卫外)。
- **收口动作(不复发的前提)**:凡给单平台加过 C,**当批必须在对侧平台跑一次 `cd gui && moon test <该平台包> --target native`**——导出函数体有 `#else` 分支不会炸,只有守卫外的 helper 才炸,而这只有对侧编译器看得到;Windows-only 的 `sys` 批在 Linux 上跑,`win`/`dbus` 那类反向同理。本批 Linux 读数:`moon test sys` 182/182、库全包 928/928、`cd gui && moon check --deny-warn` 与 `cd examples && moon check --deny-warn` 零警告、`moon build showcase --target native` 链接通过。
- **第三种踩法(2026-10-14 平台批④音量段)**:守卫范围**划过头**——整段(含 `yue_sys_vol_get` / `yue_sys_vol_write` 两个导出函数)一起被 `#if defined(_WIN32)` 圈住,而这两个函数体内已经各自写了 `#else` 退路。Linux 侧不是类型报错而是**链接报 undefined reference**(`sys.whitebox_test.o: undefined reference to yue_sys_vol_write`),因为 MoonBit 侧声明照写、C 侧整个符号没了。口径补一条:**导出函数本体恒留在守卫外**(它自带两分支),守卫只圈平台专属的 helper/常量/GUID 表;`#endif` 要收在 helper 段尾,不能盖到导出函数上。本批 Linux 读数:sys 185/185、库全包 932/932、`moon build showcase --target native` 链接通过。


## Windows 全屏与尺寸切换无效:win 分支两符号是空壳桩,GTK 一直有真实现(2026-10-15,真机反馈 Windows)

- **现象**:showcase「窗口」页的「全屏切换」「尺寸切换」按钮(以及一切经 `App::set_fullscreen` / `Window::set_size_pixels` 的调用)在 Windows 全部无效——点击不报错,窗口纹丝不动。
- **根因**:`gui/win/stub.c` 的 Windows 分支里 `wm_window_set_size` / `wm_window_set_fullscreen` 是带符号的空壳桩(参数全 `(void)` 丢弃),GTK 分支早就接了 `gtk_window_resize` / `gtk_window_fullscreen`。符号存在所以链接不断、调用静默无效——「两后端方法面同形、真实现只落了一边」这条坑在 win 桩上又漏了一处(与此前 Raster 纯光栅器不清路径、圆角描边直段不落墨同型)。
- **修复**(`gui/win/stub.c` Windows 分支):
  - `wm_window_set_size`:参数是客户区物理像素(整栈物理像素口径),按当前样式 `AdjustWindowRectEx` 外扩成整窗尺寸再 `SetWindowPos(SWP_NOMOVE|SWP_NOZORDER|SWP_NOACTIVATE)`;宽高 <1 钳到 1(MoonBit 侧 `set_size_pixels` 已先拦 <1,这里是 C 侧兜底;实测有标题栏的窗口会被系统最小宽顶住,宽度钳制只对无边框形态可见)。WM_SIZE 的既有记账把 `resized` 置 1,MoonBit 侧照常收 `Resized` 事件,宿主不用自己算新矩形。
  - `wm_window_set_fullscreen`:进屏先记现场(样式 + `WINDOWPLACEMENT`),样式剥掉 `WS_OVERLAPPEDWINDOW` 换 `WS_POPUP`,`SetWindowPos` 摆到最近显示器(`MonitorFromWindow` + `GetMonitorInfoW`)整屏;退屏原样还原样式与位置。同值重复调用直接返回(幂等)。
- **验证方式**:`experiment/window_probe/window_enhance_probe.c` 新增两节——`set_size` 后 `GetClientRect` 读回目标尺寸、`wm_windows[].resized` 置位、`wm_size` 读回一致;全屏进屏窗口矩形 == 显示器矩形且客户区记账同步、退屏位置与样式逐值还原、重复进出幂等、越界 id 不崩。全量 `WIN-ENHANCE-OK`(本机 Windows 1920×1080)。探针编译顺带补了两条缺件:`shell32.lib`(托盘 `Shell_NotifyIconW` 已进符号面)与 `moonbit_make_bytes` 的 malloc 兜底(剪贴板空壳引用运行时分配符号),编法更新在探针头注释与 `build.bat`。`moon test win` 28/28、`cd gui && moon check --deny-warn` 零警告、`cd examples && moon build hello --target native` 链接通过。真机复验归 `测试文档/测试用例.md`。

## 全局快捷键按了没反应:轮询表挂在构造期钩子里,宿主就绪前跑完第一拍就死了(2026-10-15,真机反馈 Windows)

- **现象**:showcase「窗口」页点「注册 Ctrl+Alt+C」状态显示已注册成功,切到别的程序按组合键,「命中 N 次」永远不动。
- **根因**:库侧链路(注册 → 泵截 WM_HOTKEY → poll 抽取)都是好的——`experiment/window_probe` 用 `PostThreadMessageW` 打真实 WM_HOTKEY 的同一条路全绿;坏在 showcase 的轮询表挂错了时机:「零尺寸挂载钩子」写在 `node_of_new` 的 finish 里,而 finish 是**构造期**执行(`core/node.mbt` 记档),页面函数又是 `mount_window` 的实参、求值早于建窗——第一拍 `hotkey_poll()` 跑在空 timer 通道上,`app.host.val` 还是 None,**循环不再重排,当场死掉**,之后泵里截获的 WM_HOTKEY 没人来抽。与图表页推点(52119a4)同一条坑的第 2 处,页面里那句「零尺寸挂载钩子」注释承诺的是挂载期、用的却是构造期 API。
- **修复**(`examples/showcase/pages/window.mbt`):钩子改挂 `Node::on_mount`——段正文惰性挂载、首次选中本段时才跑,那时宿主已就绪;200ms 自重排表照旧。轮询表「宿主未就绪即永久死掉」的脆弱形态(尾拍 `app.host` 为 None 就不再重排)是示例侧现状,属可加固点(另批)。
- **验证方式**:`experiment/window_probe` 新增热键节——注册 → `PostThreadMessageW` 投 WM_HOTKEY → `wm_pump` 截获 → `wm_hotkey_poll` 取出、同批重复投递只记一次、同组合重复注册被系统拒绝、注销后同 id 不再置位,全量 `WIN-ENHANCE-OK`。`cd examples && moon check --deny-warn` 零警告、`moon build showcase --target native` 链接通过。真机复验归 `测试文档/测试用例.md`(真实按键触发只能人来)。

## 托盘挂菜单与左右键点击全失效:同一构造期坑的第 3 处——派发表起表也写在 finish 里(2026-10-15,真机反馈 Windows)

- **现象**:showcase「系统集成」页的托盘图标建出来了(图标可见、tooltip 能悬停出来),但左键点不动(计数恒 0、不冒提示)、「挂菜单」后右键也弹不出菜单。
- **根因**:与上一节快捷键完全同形。库侧链路完好——`experiment/tray_probe/tray_backend_probe.c` 直喂 `wm_tray_*`,左/右键回调消息入队与 `wm_tray_poll` 抽取、`wm_menu_popup_new` + `wm_menu_add_item` 的挂菜单、非法槽与无菜单不阻塞,全绿。坏在示例侧:`tray_poll_loop()` 的**起表**写在 `node_of_new` 的 finish 里(构造期跑),首拍 `@core.host_active()` 还是 None ⇒ 200ms 表不再重排、当场死掉。于是 `dispatch_tray_event()` 从此没人调:左键回调抽不到,而 Win32 上「右键无 `on_context` 回调时自动弹已挂的菜单」这条也住在 `dispatch_tray_event` 里 ⇒ 用户看到的就是「菜单挂不上 + 点了没反应」。同一页的菜单项派发(`dispatch_menu_command`)反而没事,因为它的表起在宿主 `handle`(真·挂载期)。
- **修复**(`examples/showcase/pages/system.mbt`):起表挪到 `Node::on_mount`(段正文惰性挂载、首次选中才跑,那时宿主已就绪),建托盘仍留在构造期(启动即出图标的既有形态不变)。页面注释按实情重写——原来那句「段首次选中时建托盘 + 起派发表」承诺的是挂载期、用的却是构造期 API,是这条坑连续第 3 次踩中的原因。
- **验证方式**:`moon check --deny-warn`(examples)零警告、`moon build showcase --target native` 链接通过。库侧本批零改动,其托盘语义用 `experiment/tray_probe/tray_backend_probe.c`(纯 C,直接 `#include stub.c`)在本机重跑坐实:左键/右键回调消息入队与 `wm_tray_poll` 逐条抽出、`kind` 0/1 正确、非点击消息不入队、`wm_menu_popup_new` 的弹出根是真 HMENU 且挂上后 `wm_menu_add_item` 拿到命令 id、无菜单/非法槽的 `wm_tray_popup` 立刻返回 0 不阻塞、移除幂等——末行 `TRAY-BACKEND-OK`。探针编法同 window_probe 并补了 `build.bat`;整份 stub.c 编进来会带上剪贴板空壳引用的 `moonbit_make_bytes`,探针里用 malloc 兜底(头注释已记)。真机复验归 `测试文档/测试用例.md`:进「系统集成」页 → 左键计数递增并冒提示 → 点「挂菜单」→ 右键弹出三项 → 点项走 `dispatch_menu_command` 回回调。
- **可加固点(另批)**:「宿主每拍抽一次」这条契约现在全靠调用方自觉,已连带踩中 3 处(图表推点 / 快捷键 / 托盘);把 `dispatch_menu_command` + `dispatch_tray_event` + `hotkey_poll` 统一收进宿主每拍(`App::step`)才是终结这条坑的做法,消费式队列允许多个抽取者并存(native-app 的显式调用不会与之抢事件)。

## Windows 系统级拖入:OLE 回调住在消息派发里,效果要靠「两段式」回写(2026-10-15,用户提需求)

- **环境**:Windows 10 19044 开发机,MSVC `/W4`,纯 C 探针直接 `#include ../../gui/win/stub.c`(不链 moon 运行时)。
- **现象/动机**:用户提「拖放应该还有与外部的交互,拖入、拖出,内部也应该能支持多次拖放吧」。W21c 只落了应用内拖放,系统级(从资源管理器拖文件进窗口)当时明确记为「随平台批」。内部多次拖放经核实是**既有能力**(`route_pointer` 抬起即释放捕获,会话在 `drag_drop`/`drag_cancel` 里复位,不是一次性对象),本批补回归钉住;系统级**拖入**在本批落地,**拖出**(`DoDragDrop` + `IDropSource` + `IDataObject`)另批。
- **根因/设计口径**(为什么长这样):
  - OLE 的 `IDropTarget` 回调打在**本线程的消息派发**里,与托盘/菜单/热键同一条约束(不做 C→MoonBit 回调)⇒ C 侧把 `DragEnter`/`DragOver`/`DragLeave`/`Drop` 压进进程级环形队列(64 槽),宿主每拍 `wm_dragdnd_poll` 抽。载荷不进队列,单独放一块 64KB 缓冲,`wm_dragdnd_payload` 按「进入/投递」时读回的最近一份取。
  - **效果两段式**:`DragEnter` 时 MoonBit 还没机会判「这个落点收不收」(回调必须立刻给 `pdweffect`),所以 C 侧按「这份格式认不认得」先给承诺值(CF_HDROP/CF_UNICODETEXT 给 COPY,认不出给 NONE);之后每次 `DragOver`/`Drop` 读 MoonBit 上一拍 `wm_dragdnd_set_effect` 写回的 per-window 标志。于是应用侧的 `accept` 判断能反映到系统光标,而回调侧不需要同步问 MoonBit。
  - **`accept` 必须另开一条钩子**:`on_drop` 一调就是真投递(有副作用),悬停期问「收不收」不能复用它 ⇒ `Widget::drag_accept` + `drag_wants`(没装钩子时按「收」),`@ui.drop_target(accept=)` 同时挂 `on_drop` 与 `drag_accept` 两处。
  - **会话复用,不另建一套**:`core/drag.mbt` 的进程级单例 `drag_current` 是 App 内拖放已有的,外部事件按 ENTER→`drag_begin(data,0,x,y)`、OVER→`drag_move`、LEAVE→`drag_cancel`、DROP→`drag_drop` 喂进同一条,落点命中(`drop_target_at`)与高亮(`drag_hover`)全部复用;落点树按**事件所属窗**找(`drag_window_root_of` 遍历 `host_windows()` 比 `a.window.id`),`drag_root()` 在外部会话期间优先返回那张树。
  - **双向不劫持**:`drag_ext_window` 记当前外部会话归属哪扇窗,LEAVE/DROP 只处理同窗事件;App 内已有内部会话在跑时,外部 ENTER 直接忽略(不抢正在拖的那次)。
- **载荷线形状**:CF_HDROP **优先**(资源管理器拖文件给的就是它),`DragQueryFileW` 逐条宽字符、`\n` 连接 → `Paths`(kind 4);没有 HDROP 才取 CF_UNICODETEXT → `Text`(kind 1);两者都认不出 → 载荷空串、效果 NONE。文本一律 `WideCharToMultiByte(CP_UTF8)`,编成 `[kind:i32 LE][payload]`,与 `drag_encode` 同制,MoonBit 侧 `drag_decode` 直接吃。坐标 `ScreenToClient` 换成客户区像素(整栈物理像素口径)。
- **坑(C 侧,逐条实测)**:
  1. `IDataObjectVtbl::QueryGetData` **只有一个 `FORMATETC *` 参数**——按 `GetData` 的形状多写一位 `NULL` 直接 C2197「参数太多」(SDK `objidl.h` 实证)。
  2. C 模式下 `GetCanonicalFormatEtc` 的第二参是 `FORMATETC *`,不是 C++ 别名 `DFORMATETC`(后者在 `#ifdef __cplusplus` 里),写了编译不过(C2143/C2081)。
  3. `DROPFILES` 定义在 `um/ShlObj_core.h`,**不在 `shellapi.h`**——`#include <shlobj.h>` 才拿得到;`pFiles = sizeof(DROPFILES)` + `fWide = TRUE` + 双空结尾宽字符表,`DragQueryFileW` 才认。
  4. COM 接口用 C 的「首成员放 iface + 静态 vtbl」实现;vtbl 定义**不能带 `const`**(`lpVtbl` 字段是非 const 指针,带 const 会 C2038 类赋值警告)。IID_*/CLSID_* 在 `uuid.lib`,拖放函数在 `shell32.lib`,`OleInitialize` 在 `ole32.lib`——这三个前批(图标/托盘/任务栏)就已在 prebuild 的 Windows 链接行里,本批零改动。
  5. OLE 起来与否要**探测一次并缓存**:`OleInitialize` 返回 `S_OK`/`S_FALSE` 与 `RPC_E_CHANGED_MODE`(有人先 `CoInitialize` 过)都算「已起来」;`dragdnd_supported()` 恒 false 时上层静默跳过挂接,应用内拖放不受影响。
- **坑(探针侧)**:OLE 送进 `DragEnter`/`DragOver` 的坐标是**屏幕**坐标,想在客户区 (20,30) 那一点验落点,要用 `ClientToScreen` **反推**屏幕点;拿屏幕原点 (0,0) 加偏移会把窗口自身位置算进去,落点整体偏一个窗口距离(实测差 -48/-84),看着像库错、实际探针用法错。
- **验证方式**:`experiment/drag_probe/dragdnd_probe.c` 末行 **`DRAGDND-OK`**(40 条:挂/撤/幂等/越界 id/在用计数/效果初值;HDROP→Paths(4) 且两条路径逐字符一致;`set_effect` 被下一次 `DragOver`/`Drop` 读回;投递后载荷复位;HDROP 优先于文本;纯文本→Text(1);认不出的格式给 NONE 且载荷空;`DragLeave` 清载荷并入队 LEAVE;`disable` 后计数 0、效果 -1)。`core/drag_wbtest.mbt` 新增 1 条(喂事件驱动会话、COPY/NONE 按落点 `drag_wants` 答、`data=None` 不动现有会话、DROP 投递并复位、LEAVE 取消不投递、跨窗不抢、内部会话不被劫持);`ui/drag_wbtest.mbt` 新增 2 条(同一拖源连拖两次都成立且载荷每次现取、`accept` 同时挂成悬停查询)。`moon test core ui win` **351/351**、库全包 **937/938**(1 条红是 `si_machine` 读注册表 `SystemManufacturer` 失败,本机环境基线,与本批无关)、`cd gui && moon check --deny-warn` 与 examples 模块零警告、`moon build showcase --target native` 链接通过、本机起窗冒烟后正常终止。跨进程真拖(资源管理器 → 窗口)只能人来,归 `测试文档/测试用例.md`。

## Windows 系统级拖出:只读 IDataObject + `SHDoDragDrop` 免掉一整支 IDropSource,而 `GetFullPathNameW` 不许就地写回(2026-10-15,用户提需求)

- **环境**:Windows 10 19044 开发机,MSVC `/W4`;库构建走 moon 的 native-stub(cl 由工具链自己拼),探针走 `experiment/drag_probe/build.bat`(vcvars64 + 全参数 cl),两条编译命令的**宏与 include 路径不同**——这一点在下面第 2 条坑上要命。
- **现象/动机**:承上一节,用户那句「拖放应该还有与外部的交互,拖入、拖出」里的「拖出」半句。目标是从本窗拖出去,对方程序(桌面、资源管理器、编辑器)拿到的是标准的复制/移动/链接语义,而不是只能在自己窗口里玩。
- **根因/设计口径**(为什么长这样):
  - **不做 `IDropSource`**:造一只只读 `IDataObject`(12 槽)+ 交给 `SHDoDragDrop(hwnd, pdata, NULL, dwEffect, &effect)`——第三参给 NULL 时系统用**默认 IDropSource**(自己轮询真实鼠标键与 Esc),于是省掉 `QueryContinueDrag`/`GiveFeedback` 那一整支 vtbl,还白得资源管理器那圈「复制到 X」拖放说明气泡。`SHDoDragDrop` 声明在 `um/ShlObj_core.h`,实现在 `shell32.lib`(前批已在 prebuild 的 Windows 链接行里)。
  - **只读对象的取数据两条都要给**:拖入侧的 `wm_dnd_fetch` 走的是 `GetDataHere`(在调用方给定的 HGLOBAL 里就地写),而对方程序也常问 `GetData`;两条都实做,`EnumFormatEtc` 只给当前那一条格式(`DATADIR_GET`),`SetData`/`DAdvise`/`EnumDAdvise` 明确 `E_NOTIMPL`,`QueryGetData` 只认 `cfFormat` 相符的一条。
  - **阻塞语义**:这一支**阻塞**到松手或取消才返回(OLE 在里面代跑消息循环),期间本窗的拖入回调照常打进 C 队列、返回后的下一拍由宿主抽取 ⇒ 「拖出去又拖回自己窗口」是通的,但**拖拽途中没有应用内实时高亮**(那是应用内会话的待遇,两条会话同一时刻只能跑一条)。而且**必须在鼠标键仍按下时调用**(过阈值那一刻),按钮抬起后再调系统不认——`@ui.drag_source` 正好发在 `Move` 分支里。
  - **回落口径(重要)**:`@ui.drag_source(external=true)` 先试系统那一趟,`Err`(后端没接 / 种类没有系统级形态 / 这趟起不来)才**回落到应用内会话**,`Ok`(成交或用户取消)**绝不回落**——那时用户已经松手,再开一条会话会凭空拖出一段。于是同一份示例代码三平台都能跑,Linux/mac 的后端桩恒给 `Unsupported` 自然落回应用内。
  - **效果编号**:`DragEffect`(Rejected/Copy/Move/Link)与 Win32 `DROPEFFECT_*` 逐值同制(0/1/2/4);`drag_effect_of_flag` 只认这四个值,多位的组合(3、7)与越界值一律按「没成交」,不猜成复制。起拖时给系统的 `dwEffect` 是 COPY|MOVE|LINK 全开,具体按 Ctrl/Shift/Alt 由系统定夺。
  - **种类判据在起拖前**:`Text`→`CF_UNICODETEXT`、`Paths`→`CF_HDROP` 有系统级形态;`Html`(要 CF_HTML 的 `StartFragment`/`EndFragment` 源标记格式)与 `Img`(要位图/`METAFILEPICT`)本批不给,`drag_data_has_system_form` 直接拦下,不会误碰系统。
- **坑(C 侧,逐条实测)**:
  1. **`GetFullPathNameW` 不许就地写回同一块缓冲**。CF_HDROP 里要给绝对路径,原先写 `GetFullPathNameW(buf, size, buf, NULL)`,实测把「`rel\乙.txt`」这种相对串写成「`<cwd>\<被截断的串>`」这类拼接垃圾——就地写回会覆盖还没读完的输入,而对方程序拿到的正是这个。改成**输入/输出分两块**(`wm_dsrc_one` 转码、`wm_dsrc_abs` 绝对化),解析失败或超长就原样给(不吞掉整条路径)。
  2. 更要命的是**探针当初用同一个就地调用算期望值**,于是「`DragQueryFileW` 逐条解析回原路径」这一条判据在坏实现下**照样绿**。修探针:转码与期望分缓冲(`srcw`/`want`),期望串自己拼,且**`\n` 分隔符必须在转换之前写进表里**(先写反过一次)。教训口径:合成探针里「用被测函数算期望」等于没测。
  3. **`DROPFILES` 与 `SHDoDragDrop` 在库构建下取不到**:`gui/win/stub.c` 原先只引 `<shobjidl.h>`,探针自己额外引了 `<shlobj.h>` 所以一直是绿的;而 moon 的 cl 调用一编译 stub.c 就报 17 条 `C2065: "DROPFILES" 未声明`(`SHDoDragDrop` 反而只当隐式声明,不报硬错,最容易看漏)。补 `#include <shlobj.h>` 后两边同时通过——同一条「SDK 头文件按包含顺序/版本宏裁剪,探针绿不等于库绿」的坑,这次是**两条编译命令不一致**造成的。
- **验证方式**:`experiment/drag_probe/dragdnd_probe.c` 末行 **`DRAGDND-OK`**(**84 条**,原拖入 40 条 + 拖出 44 条):`wm_dsrc_fill` 之后 `QueryGetData` 正/负;`GetData` 出来的 CF_HDROP 被 `DragQueryFileW` 逐条解析回**独立算出的**期望串、三条都在、相对路径已绝对化(断言 `第 2、3 字符 == L':' L'\\'`);`GetDataHere` 与 `GetData` 首条逐字符一致;枚举器 `Next`/`Reset`/`Skip` 到位、`Clone` 明确 `E_NOTIMPL`、`SetData` 失败;再把同一只对象喂回本窗 `IDropTarget`,抽出的载荷与原始编码逐字符一致(往返闭合)。文本档:宽字符逐字符一致 + `GlobalSize == (wlen+1)*2` + 往返 `Text`(1)。负面:kind 2/3 无系统级形态、空正文、失败后不留缓冲、`wm_dragdnd_send` 的越界 id/NULL 载荷/`len<4`/NULL `out_effect` 全部返回 0 且不写效果。探针源文件 `/W4` 零告警(修掉 C4389 有/无符号比较与两处 C4456 遮蔽),`stub.c` 只剩既有 2 条 C4996。MoonBit 侧:`core/drag_wbtest.mbt` +2(效果编号与 `DragEffect::flag` 往返、未知标志按 Rejected;只 Text/Paths 有系统级形态,无头起拖必然 `Err` 且不留半截会话)、`ui/drag_wbtest.mbt` +2(`external=true` 在后端起不来时回落应用内会话且仍完成投递、`on_external` 确实回报;`Html` 数据判为 `Unsupported` 后回落)。`moon test core ui win` **355/355**、库全包 **941/942**(唯一红是 `si_machine` 读注册表 `HARDWARE\DESCRIPTION\System\BIOS:SystemManufacturer` 失败,本机虚拟化环境的基线红,与本批无关),`cd gui && moon check --deny-warn` 与 examples 模块零警告,`moon build showcase --target native` 链接通过,本机起窗冒烟 4 秒存活后正常终止。真拖到桌面/记事本只能人来,归 `测试文档/测试用例.md`。

## 真机复验 S26:从资源管理器拖文件进来显示「禁止」——只走 `GetDataHere` 取不到 shell 的载荷(2026-10-15,用户真机反馈)

- **环境**:Windows 10 19044 真机,showcase「窗口」页拖放段,源是**资源管理器**(跨进程真 COM 对象)。
- **现象**:文件拖进窗口时鼠标是**禁止符**、松手不收(= S26 第①项失败)。同一份代码在探针里是全绿的。
- **根因**:`wm_dnd_fetch` 只走 `GetDataHere` 一条腿(当时的注释理由是「省掉 IMalloc 释放这条腿」)。**资源管理器的数据对象对 CF_HDROP 常只实现 `GetData`**,`GetDataHere` 直接给 `E_NOTIMPL`/`MK_E_UNAVAILABLE` ⇒ `QueryGetData` 明明认得出格式、载荷却取不回来 ⇒ `wm_dnd_extract` 判「这份东西我不认识」⇒ `DragEnter` 承诺 NONE,于是**一进来就是禁止符**,后面 MoonBit 再怎么写回都救不回来(效果初值就是 NONE)。
- **修复**:取数据改**两条腿**——先 `GetDataHere`(我们递空 `GMEM_MOVEABLE`,取回的归我们 `GlobalFree`),**失败再退 `GetData`**(对方自己分配 medium,所有权在 medium,必须 `ReleaseStgMedium` 放、不能再 `GlobalFree`)。释放口径随取法走,故把返回从裸 `HGLOBAL` 换成 `WmDndBlob{h, via_medium, medium}` + `wm_dnd_blob_free`,`wm_dnd_extract` 的两个分支都改用它。
- **为什么探针照绿**:探针那只合成数据对象**两条都实现**,所以「只走一条腿」这种错在合成对象上永远看不出来——正是「单测自洽 ≠ 互操作通过」那类问题。现给 `ProbeDo` 加 `no_get_data_here`/`no_get_data` 两个开关,新增 9 条判据钉住「只实现 `GetData` 的对象也要认得出 Paths(4)/Text(1) 并承诺 COPY」,以及「两条都不给时才老实答 NONE、载荷为空」。
- **顺带加的诊断落盘**(跨进程真拖只能真人跑,出问题要有读数):设环境变量 `NATIVEGUI_DND_LOG=<绝对路径>` 后,`gui/win/stub.c` 把拖放链关键节点逐条追加写进那个文件——`ole_init ready=…`、`enable slot=… hwnd=… ok/FAILED hr=…`、`enter slot=… recognized=… payload=… promised=… pt=…`、`over slot=… answered=…`(只在答的效果变了时落一行,不刷屏)、`set_effect slot=… effect=…`、`drop slot=… recognized=… eff=…`。没设变量时一个字节都不写。据此一眼分得清是「OLE 没起来」「没注册上」「载荷取不回」「MoonBit 答了 NONE」哪一环。
- **验证方式**:探针 `experiment/drag_probe/dragdnd_probe.c` 末行 **`DRAGDND-OK`**,判据 **93 条**(84 → 93);`moon test core ui win` **355/355**、库全包 **941/942**(唯一红仍是 `si_machine` 的 BIOS 注册表读数,本机环境基线)、`cd gui && moon check --deny-warn` 零警告、`moon build showcase --target native` 链接通过。真机复验仍归 `测试文档/测试用例.md`(建议带 `NATIVEGUI_DND_LOG` 跑一次并把日志贴回)。

## 「在文件管理器显示 TODO.md」不生效：绝对判据只认前导 `/`，Windows 路径被拼成 `<cwd>/C:\…`（2026-10-15，真机反馈）

- **环境**：Windows 10 19044 真机，showcase「系统集成」页「外部打开」段（按钮传的是相对路径 `TODO.md`）。
- **现象**：点「在文件管理器显示 TODO.md」定位不出来（要么开个别处、要么什么也没发生）；同时用户指出面还缺两条——**用默认软件打开指定文件**、**用指定软件打开指定文件**。
- **根因**（三条叠在一起）：
  1. `launcher_abs_path` 只用「前导 `/`」判绝对，Windows 的 `C:\…`、UNC `\\srv\…` 全被当相对路径拼到 cwd 后面，产出 `<cwd>/C:\a\b.txt` 这种垃圾串。
  2. 拼接一律用 `/`，而 `explorer /select,"…"` 对**混合分隔符**的路径**不选中**（往往只开一个文件夹，甚至开「文档」）——交出去之前要把 `/` 统一成 `\`。
  3. `ShellExecuteW` 返回 >32 只说明「explorer 起来了」，所以 `Ok` 成了假承诺：路径不存在时系统侧**默默成功**。补一条 `yue_sys_path_exists`（Windows `GetFileAttributesW`、其余 `stat(2)`），交出去之前先判一次，不存在给新增的 `NotFound` 档（`FileManagerError` 与新的 `OpenFileError` 都有）。
- **另炸出的一条工具链坑**：本工具链里 `String` 的下标返回的是 **UTF-16 码位（UInt16）**，按 `Char` 逐位重建字符串会把中文路径**写坏**（一个 UTF-8 三字节序列被重编码成三个 Char）。`launcher_win_path` 因此走 `@utf8.encode` 成 `Bytes` 逐字节替换，再解回串。
- **为什么之前没暴露**：`sys/launcher_wbtest.mbt` 的归一判据全用 POSIX 形状（`/a/b`、`/cwd`），Windows 形状一条都没写；`reveal` 的真机动作只归示例回证。教训口径：**路径归一的白盒判据要按平台形状各来一组**，否则「只认 `/`」这种错在测试里是隐形的。
- **新增两条面**：`@sys.open_file(path)`（默认程序：Windows `ShellExecuteW "open"`、Linux `xdg-open`、macOS `open`）与 `@sys.open_file_with(app, path)`（指定程序：Windows 走新入口 `yue_sys_shell_open_with`，`lpFile`=程序、`lpParameters`=**带引号**的路径——路径含空格时对方 `argv[1]` 才是一整条；Linux/macOS 用 argv 直传的分离式启动，空格天然安全）。两条都是**平台门在前**（不支持的平台先给 `Unsupported`，再判路径），`app` 可以是 PATH 里的命令名（`notepad.exe`）也可以是完整可执行路径。macOS 那种「按应用名 `open -a TextEdit`」的形态未接（要给可执行文件路径），随 mac 平台批。
- **验证方式**：`sys/launcher_wbtest.mbt` 新增 4 组判据——绝对三写法（`/`、盘符 + 冒号、`\\` 与 `\` 开头）且 `C:` 盘符相对不算绝对、Windows 绝对路径不被拼进 cwd、`launcher_win_path` 对中文/已正确串不变形（含 `launcher_abs_path` 与归一函数串起来用的混合输入）、`sys_path_exists` 真实读数（工作目录必在、拼个不存在的名字必不在、空串 false）、打开面三条**无系统副作用**的负例（空路径/不存在路径/空程序名）。`moon test sys core` **333/334**（唯一红仍是 `si_machine` 读 `HARDWARE\DESCRIPTION\System\BIOS:SystemManufacturer`，本机环境基线）、`cd gui && moon check --deny-warn` 与 examples 模块零警告、`moon build showcase --target native` 链接通过、本机冒烟 4 秒存活后按 Windows pid 正常终止。真机复验归 `测试文档/测试用例.md`。
- **同批自检补漏（Linux，2026-10-15）**：上段判据里的「win_path 回读仍存在」（`sys_path_exists(launcher_win_path(cwd))`）按 Windows 文件系统行为写死——Windows 的 stat 两种分隔符都认，Linux 上 POSIX 路径换成反斜杠串后 stat 必不存在，CI Linux 必红。已改按 `sys_platform()` 运行时分派：Windows 断 win_path 回读，其余平台断 `launcher_abs_path` 归一回读（存在的路径不被归一写坏）；本节「白盒判据按平台形状各来一组」教训的第一处落地。

## 库测试每跑一次就弹一次「需要使用新应用以打开 …」：ShellExecuteW 对未注册协议不返错（2026-10-15,用户报）

- **环境**：Windows 10 19044 开发机，跑 `cd gui && moon test sys`（或全包测试）时反复弹系统对话框。
- **现象**：用户反馈「你测试的时候总是提示『需要使用新应用以打开 libyue-invalid-probe 链接』」。
- **根因**：`sys/launcher_wbtest.mbt` 里有一条 Windows 探针 `open_url("libyue-invalid-probe://no-such-scheme")`，注释写着「用无效目标的 SpawnFailed 语义做探针（**不弹窗**）」——这句是错的。`ShellExecuteW` 走的是系统关联/协议分发：**未注册的协议不返回 `SE_ERR_*`**，而是把「你要用哪个应用打开」的选择器交给用户（等价于成功），所以既拿不到期望的 `SpawnFailed`，又每次跑测试都在开发者桌面上弹窗。测试有真实系统副作用，还违反「真机动作归用户复验」的分工。
- **修复**：新增纯判据 `open_supported()`（Windows/Linux/macOS 为真，运行时探测、不碰系统），测试改成只断它 + **在交出去之前就返回**的负例（`open_file("")`→`NotFound`、`open_file_with("", …)`→`SpawnFailed`、`reveal_in_file_manager("")`→`NotFound`/macOS 的 `Unsupported`），真开动作只留在示例按钮里（S28 由用户复验）。顺带把 `open_url` 的 macOS 分支补上（`open` 一条，与 `open_file` 同口径），`open_supported` 与三条面的分派表因此一致。
- **口径**：库测试里**不许**出现 `ShellExecute*` / `xdg-open` / `open` 的真实目标调用；要验「后端接没接上」用纯判据，要验「真开出来是什么」写进 `测试文档/测试用例.md` 让人跑。以后再有「拿无效目标探错误档」的想法，先确认该无效性能在**不启动系统 UI** 的前提下返错——协议的无效性恰恰不满足这条。
- **验证方式**：`moon test sys` **186/187**（唯一红仍是 `si_machine` 读 BIOS 注册表的本机环境基线），跑测试期间桌面不再出现任何对话框；`cd gui && moon check --deny-warn` 与 examples 零警告。
### Windows 媒体示例的 ffmpeg 运行期 dll 分发(工具批,2026-10-20)

- **环境**:Windows 10/11 x64,`moon run examples/audio`(video 同构)。
- **现象**:两个示例启动即退,系统报缺少 `avcodec-63.dll` 等一批 dll;示例自身无任何输出,窗口从不出现。
- **根因**:`ffmpeg-mbt` 的 Windows 侧走**导入库动态链接**(`vendor/*.lib` 指向 BtbN win64-lgpl-shared 9.0),导入库进链接 = exe 在**加载期**硬依赖 `avcodec-63.dll` / `avformat-63.dll` / `avutil-61.dll` / `swscale-10.dll` / `swresample-7.dll`。加载器在 `main` 之前解析导入表,缺任一个就拒绝加载——所以现象是「进程起不来」而非「示例内报错」(控制台一闪即退,Git Bash 退出码 127)。dll 共约 150MB 不入库,此前只在 README 写「放 exe 同目录或加进 PATH」,没有一步替使用者把文件搬到那儿,于是每条 Windows 新机器都要重踩一遍。
- **构建期补下载(`ffmpeg-mbt/prebuild.py` 的 Windows 分支)**:此前 Windows 分支只下发 5 个导入库的绝对路径,`ensure_win_runtime_dlls()` 是新加的对称件——运行期 dll 落到 `vendor/win/bin/`(与 macOS 的 `vendor/mac` 同一口径:不入库、缺失即取、离线可覆盖),来源是同一份 BtbN `win64-lgpl-shared 9.0` 归档的 `bin/`。BtbN 的 `latest` 是滚动资产、没有可固定的 sha256(与自建的 mac 归档不同),所以判据落在「7 个带大版本号的文件名齐 + 单个 >100KB」上;下载失败只提示不中断构建(导入库链接照旧可用)。`NATIVE_GUI_FFMPEG_ZIP` 指本地 zip 或镜像 URL,`NATIVE_GUI_SKIP_VENDOR=1` 跳过这 150MB(CI 已自备 dll 放 PATH,已在 `.github/workflows/ci.yml` 的 Windows 构建 step 设上)。
- **归档与预算(2026-10-20 实测)**:运行期 dll 归档 `ffmpeg-windows-x64-9.0-lgpl-shared.zip`(67.5MB,解出 149.2MB/7 个 dll)由新增 workflow `win-ffmpeg-vendor` 在 windows runner 上取 BtbN → 抽 `bin/*.dll` + LGPL 文本 → 打包算 sha256 → 直接 `gh release upload vendor-v1`,与 mac 归档同处一档;prebuild 优先取它(双镜像竞速 + sha256 校验),拿不到才退 BtbN 上游。**总预算必须按体积给**:沿用 mac 的 60 秒预算,本机实测要 123.5 秒才下完,会「数据还在流、预算先到」被判死;故 `fetch_vendor_file` 加 `budget` 参数,Windows 路给 360 秒(mac 仍 60)。端到端实测:清空 `vendor/win` 后跑 Windows 分支 → 命中 GitHub 镜像、sha256 通过、7 个 dll 就位(123.5s);当时 gitee 侧还没有该附件,竞速里它失败即跳过、不影响结论。gitee 镜像靠 workflow 末尾的「同步到 gitee 镜像」步骤(gitee 附件接口没有覆盖语义,先按名删旧再 `curl -F` 上传),需 repo secret `GITEE_TOKEN`,没配则跳过不挡构建。
- **搬运(`scripts/win_ffmpeg_dll.py`)**:来源链 `--dll-dir` → exe 同目录 → prebuild 落点 → PATH → winget → scoop → 旧缓存,把 av*/sw* dll 复制到 exe 同目录(app-local,加载器第一顺位搜索);缺 exe 时先自动 `moon build examples/<name>`;`--run` 补完直接启动,`--dry-run` 只打计划。
- **prebuild 为什么不干脆把 dll 直接放到 exe 旁**:实测 moon 传给 prebuild 的 stdin 只有 `{"env": ..., "paths": {"module_root": ..., "out_dir": "_build/native/<mode>/build/prebuild/<hash>"}}`——没有最终 exe 目录;而且 prebuild 跑在模块构建**之前**,exe 那时还不存在。所以「构建期备好」与「放到 exe 旁」必须拆成两步:prebuild 负责下载,脚本负责搬运(moon 侧没有 post-build 钩子)。
- **为什么不换链接方式**:静态链与 `vendor/*.lib`(导入库)不兼容,且 LGPL 静态链接还要额外满足「可重链接」义务;把 dll 放进仓库会永久占用 git 历史体积。app-local 复制是 Windows 惯例,也是发布时的正确形态。
- **验证**(本机 macOS,代码级):`--dry-run` 对「来源齐全 / 来源版本错配 / 缺 exe」三条路径的输出与退出码逐一核对;复制幂等(第二次报「已就位」),七个 dll 落位与 exe 同目录清单一致;prebuild 的 Windows 分支用 `platform.system` 打桩跑过三条路(跳过开关 / vendor/win 已就位 / 正常 emit JSON),stdout 只出 JSON。**Windows 真机复跑归使用者**——构建日志先看到「运行期 dll 已就位」,再按 `examples/README.md` 跑脚本,窗口出现即通过。

## Windows「图标下」压不住桌面图标：挂进 Explorer 的壁纸 WorkerW（2026-10-21，Windows 真机反馈）

- **报障**：win 上点「图标下」还是遮住图标。
- **根因**：Win32 分支此前只有 `SetWindowPos(HWND_BOTTOM)`，注释写的判断是「Shell 桌面窗归 Explorer 所有，客户窗压不进它下面」——这条只对了一半：`HWND_BOTTOM` 只到「所有普通顶层窗之下」，而桌面图标由 Explorer 的 `SHELLDLL_DefView` 画，那一层还在更下面。但**壁纸那扇 `WorkerW` 恰好在图标之下**，把窗挂进去就是这一档要的位置。
- **机制**：`wm_wallpaper_host()` = `FindWindowW("Progman")` → 发 `0x052C`（Win10 2004 起 Progman 默认不派生壁纸 WorkerW，这条内部消息让它派生；用 `SendMessageTimeoutW` 卡 500ms，桌面卡住时不拖死我们）→ `EnumWindows` 找带 `SHELLDLL_DefView` 的那扇，取它**后一个** `WorkerW` 兄弟。挂前记下原样式与原父窗（本栈建窗都是顶层、父窗 NULL），加 `WS_CHILD` 后 `SetParent`，屏幕位置经 `ScreenToClient(host)` 换算过去（宿主客户区原点=主屏 (0,0)，主屏上看着不跳位），再 `HWND_BOTTOM` 排到兄弟序最低——壁纸之上、图标之下。切别的档时 `wm_leave_desktop` 原样还原并 `SWP_FRAMECHANGED` 重报框架（不重报标题栏要等下一次窗口变动才回来）。探不到宿主（非 Explorer 桌面、第三方壳）退回原来的 `HWND_BOTTOM`，不比现状坏。
- **代价写进承诺**：`WS_CHILD` 摘掉非客户区（装饰不见），跨进程挂进 Explorer 后本窗拿不到键盘焦点——`Desktop` 档的语义本就是「壁纸场景、事件归桌面」，鼠标点击照旧落到图标上，这两条与承诺一致；`DesktopWidget`（图标上、要可交互）**不嵌入**，仍走 `HWND_BOTTOM`。多屏时挂的是主屏那扇 WorkerW，副屏位置会被宿主裁掉。以上都写进 `WindowLayer` 注释与演示段说明。
- **验证**：**本机没有 Windows SDK 头文件，C 侧编译由 CI 的 Windows 作业兜**（MSVC `moon check`+build）；MoonBit 侧只改了注释与演示文案，`cd gui && moon check` 零错误零警告、`moon test ui` 208/208、`examples/showcase` `moon build` 零警告、i18n 覆盖门禁全绿（desc§ 那条中英文说明同步改写）。**待真机（Windows）**：①点「图标下」→ 窗沉到桌面图标之下、壁纸之上，任务栏与 Alt+Tab 里没有它；②点「图标上」→ 回到图标之上且仍可交互；③点「普通」/「置顶」→ 装饰与位置原样回来（重点看还原后没跑位、标题栏回来了）；④拖到副屏再点「图标下」，确认与「主屏宿主」这条说明一致。

## Windows 运行期 dll 不再要求贴着 exe：延迟加载 + 构建期目录（2026-10-21，第三方 `moon add` 追询）

- **问题**：媒体示例在 Windows 上一直靠「构建后把 7 个 dll 搬到 exe 旁」才能跑（`scripts/win_ffmpeg_dll.py`）。第三方 `moon add` 后没有这个脚本，等于把搬运工作丢给使用者；而本仓的承诺是「`moon add` 后零配置」。
- **先确认的事实**：依赖模块的 prebuild 会执行（在 `/tmp` 建探针工程 `import "NoahLiu/ffmpeg-mbt@0.2.0"`，`moon build` 日志里出现 `ffmpeg(prebuild): macOS 走 brew 的 ffmpeg`），dll 也确实会被取到 `<工程>/.mooncakes/NoahLiu/ffmpeg-mbt/vendor/win/bin`。所以缺的不是「下载」，是**没人把目录告诉加载器**。
- **为什么 prebuild 不能自己投放**：prebuild 拿到的 JSON 只有 `paths.module_root` 与 `paths.out_dir`（`build/prebuild/<hash>`），没有最终 exe 目录，而 exe 在那之后才生成；moon 也没有 post-build 钩子（`moon build --help` 无此项）。投放这一步在 prebuild 里做不到。
- **修**：新增 `src/ffmpeg_win_dll.c`——`#pragma comment(linker, "/DELAYLOAD:<5 个 dll>")` + `#pragma comment(lib, "delayimp.lib")` 让这 5 个 dll 延迟到首次调用才解析；`vf_rt_ready()` 在 `ffmpeg_supported()` 首次调用时显式加载它们，顺序是**系统默认（exe 同目录 / 系统目录 / PATH）→ 构建期目录**（`SetDllDirectoryA` 只在回落那一次临时设、随即清掉，免得盖过用户放在 exe 旁的 dll）。prebuild 的 Windows 分支下发 `-DNG_FFMPEG_DELAYLOAD -DNG_FFMPEG_BIN="<vendor/win/bin>"`（走既有的 `vars.FFMPEG_STUB_CC` → `stub-cc-flags` 通道，与 `-I${FFMPEG_INC}` 同一条路）。
- **为什么用 pragma 而不是把 `/DELAYLOAD` 塞进 link_flags**：`link_flags` 在 Windows 上承载的是 `.lib` 路径，是否直达 `link.exe`（而不是被 `cl` 当未知开关忽略）取决于 moon 内部实现，我们无从验证；`#pragma comment(linker, …)` 写在 `.o` 里，只要这个 `.o` 进了链接就必然生效。为了让 `.o` 不被静态库裁掉，`vf_rt_ready()` 由 MoonBit 侧真实调用（`ffmpeg_supported()`）。
- **等价关系**：Windows 的「延迟加载 + 构建期目录」就是 macOS 那条 `-Wl,-rpath,<vendor/mac/lib>` 的等价物——两边都是「把构建机上的库目录记进 exe，运行期就地加载」。
- **行为变化（写进文档）**：缺 dll 从「加载器在 `main` 之前拒绝、窗口不出现」变成「exe 正常启动、`ffmpeg_supported()` 返回 false」，媒体后端判为不可用。这比原来好在可诊断，也比原来好在不再把「库缺失」伪装成「程序秒退」。
- **退路**：`NATIVE_GUI_FFMPEG_NO_DELAYLOAD=1` 时不发这两个宏，退回「dll 必须在 exe 旁」的老行为（发布打包若遇怪问题可一键回落）。
- **验证（macOS，代码级）**：`moon check`（ffmpeg-mbt）、`moon test`（ffmpeg-mbt 全绿）、`moon build examples/audio` 全部零错误；新增的 C 文件在非 Windows 上只编译出 `vf_rt_ready(){return 1;}`（`nm` 确认导出 `_vf_rt_ready`），链接期**没有新增告警**（构建里那条 `libtool: warning: 'stub.o' has no symbols` 来自既有的 `win/text/webview` 空 stub，与本次无关）。模拟 `platform.system()=="Windows"` 跑 prebuild，`vars.FFMPEG_STUB_CC` 确为 `/utf-8 -DNG_FFMPEG_DELAYLOAD -DNG_FFMPEG_BIN="…/vendor/win/bin"`。**待 Windows 真机**：①不搬 dll 直接 `moon run examples/audio`，窗口出现且能播；②把 `vendor/win/bin` 改名后重跑，应得到 `ffmpeg_supported()==false` 而不是崩溃；③把 7 个 dll 复制到 exe 旁、同时删掉构建期目录，仍能跑（app-local 优先）；④`dumpbin /dependents <exe>.exe` 里 av*/sw* 应落在 delay-load 段。


## Windows 文字颜色错位：FFI 参数顺序在 x64 Windows 上按位置共享槽位（2026-10-22，Windows 真机）

- **现象**：Windows 上 hello 的标题发灰、次级文字发青（用户口述「褐色显示成灰色、浅灰显示成蓝绿色」），mac 正常。
- **根因**：MoonBit `extern pt_draw_box / pt_draw_box_cr` 把 `spacing : Double` 放在 `r,g,b,a` **之前**，而 C 侧（stub.c 与 dwrite_text.cpp）都把 `spacing` 放在**最后**。SysV（mac/Linux）整数走 GP 寄存器序列、浮点走 XMM 序列，**各自按类别顺序对齐**，顺序错位碰巧无害；**Windows x64 按位置分配**（前 4 个位置 RCX/RDX/R8/R9 与 XMM0-3 共享编号，第 5 位起按位置落栈），于是 C 的 `r` 读到 spacing 的位模式（0.0 → 0），`g/b/a` 依次错一位——颜色变 RGB(0,R,G)、alpha=B：text_primary #2A2F36 → RGB(0,42,47)@21% 淡青灰、text_secondary #6B7480 → RGB(0,107,116)@50% 青绿、primary #2D68C4 → 深藏蓝，与真机观感逐条吻合。
- **修**：MoonBit extern 与两处调用点把 `spacing` 挪到最后（与 C 一致）；C 侧不动。
- **判据**：所有含浮点的 `extern "c"` 签名，MoonBit 与三份 C 实现（stub.c 的 Pango/CoreText 分支、dwrite_text.cpp）的参数顺序必须**逐位一致**，不能依赖 SysV 的类别分序列兜底——它会在 mac 上全绿、只在 Windows 上爆。本轮顺手核过 gui 全部混排 Int/Double 的 extern（cr_blit / cr_grad_stop / rt_new / rt_add_font / rt_draw / rt_measure / pt_measure / pt_measure_font / pt_draw），除 box 两处外均一致。

## win32 臂的 `wm_window_move`/`wm_window_origin` 是链接空桩：位置读数恒 (0,0)、摆位静默不生效（2026-10-28,真机「Windows 读窗口位置无论在哪儿都回 0,0」）

**症状**：`Window::origin()` 在 Windows 上恒给 `(0, 0)`；同一段里「驻留探针窗」用 `move_to(160,160)` 定死位置那一步也没生效（静默）。
**根因**：门面声明与另两臂都是实的（GTK 走 `gdk_window_get_origin`、mac 走 `convertRectToScreen` × scale），只有 win32 臂留着一行 `{ (void)id; (void)out_x; (void)out_y; }` —— 输出指针从不写，MoonBit 侧 `Ref(0)` 保持 0。`wm_window_move` 同一条空桩。这类占位是**为了让 showcase 在三平台都链接得过**而留的（同一批还有 `wm_window_set_popup`、`wm_permission_request`），代价是能力面「有 API、无实现」，调用方拿到的不是错误而是一个像样的假值。
**修复**：win32 臂补两条实现，语义钉在**客户区原点、物理像素**（本臂进程声明 Per-Monitor V2，Win32 坐标即物理像素，与整栈一致）：`origin` 走 `ClientToScreen(0,0)`；`move` 先用 `GetWindowRect` 与 `ClientToScreen` 量出「客户区原点相对整窗原点的偏移」（标题栏 + 边框），按它补偿后 `SetWindowPos`，两函数互逆；挂进 WorkerW 的「图标下」档是 `WS_CHILD`，`SetWindowPos` 收的是宿主客户区坐标，故那条路径上先 `ScreenToClient(host)` 换算。
**同批修掉的两条同源错位**：① `wm_hide` 记的是客户区原点（`ClientToScreen`），`wm_show` 却把它当整窗原点写回 `SetWindowPos` —— 带边框的窗每走一轮 hide/show 就往下左偏一个标题栏厚度，现统一记 `GetWindowRect` 的整窗原点；② 「图标下」撤档/隐藏/关闭时没人请 WorkerW 重画本窗占过的那块（WorkerW 不自绘暴露区），壁纸上留着最后一帧 = 真机「残影」，现记 `desk_host` 并在三条路径上 `InvalidateRect` + `UpdateWindow`。
**教训**：跨平台桩的**空实现必须让调用方拿得到「没做」这个事实**——`{ (void)… }` 让 `origin` 返回一个合法的 (0,0)，比返回错误更难查（读数看着像「贴左边贴上了」）。要么在门面侧写明「本平台不支持」并给 `*_supported()`，要么让桩写出哨兵值由门面翻译成错误；顺手一条判据：新补一个平台臂时，把同臂所有 `{ (void)` 一行桩列成清单（本批剩余的两条空桩——`wm_window_set_popup` 与有意占位的 `wm_permission_request`——跟踪项已收进 `TODO.md` §2「批 E 原生弹层窗口」）。
**验证**：mac 侧只能做括号/符号自查（本机无 mingw，win32 臂编不到），**编译以 CI windows job 为准**；行为判据与读数清单见下文三节专题（本文件「`UpdateLayeredWindow` 的 `psize`…」「WorkerW 不自绘暴露区…」「托盘僵尸图标…」）与 `测试文档/测试用例.md` SC-10.9 / 10.10 / 10.11。

## `UpdateLayeredWindow` 的 `psize` 传 NULL 时「返回成功但一个像素都不画」（2026-10-28，Windows 真机「透明测试窗整片空白」的根因）

**症状**：`set_borderless(true)` + `App::set_transparent_bg(true)` 的子窗整片空白——窗在、能点、`trans_mode=1`、帧也确实进了 `layer_bits`，屏上就是什么都没有。主窗「透明度」滑到 128 那条路（`wm_apply_alpha` 走 `SetLayeredWindowAttributes(LWA_ALPHA)`）是好的，所以不是整条 layered 通道死。
**定位**：交接时列的三个候选（提交面与窗框尺寸对不上 / `borderless` 没更新 / 子宿主没跑 present）**一个都不是**——探针把字段全打出来：`trans_want=1 / borderless=1 / trans_mode=1 / IsWindowVisible=1 / WS_EX_LAYERED=1`，`pending=380×280`、`winrect=380×280`、`client=380×280`、`delta=(0,0)`。真因是桩在 `wm_layered_submit` 里把 `pptDst` 与 `psize` **都**传了 NULL。
**四组合实测**（240×150 逐像素档窗、每组合独立开一扇、GDI `BitBlt|CAPTUREBLT` 抓屏数上屏像素）：`dst=NULL,psize=NULL` → `ok=1,err=0`、屏上 **0/36000**；`dst=有,psize=NULL` → `ok=1,err=0`、**0/36000**；`dst=NULL,psize=有` → **36000/36000**；`dst=有,psize=有` → **36000/36000**。结论：**`psize` 非空就上屏，`pptDst` 无所谓**。`psize` 为空时 API 返回 TRUE、`GetLastError()` 为 0——调用方没有任何错误可捕获，只能靠看屏。
**修复**：`wm_layered_submit` 显式给 `SIZE ps = {pending_w, pending_h}`，`pptDst` 仍 NULL（位置不动）。文档写的是「尺寸不变可传 NULL」，与实测不符；按实测走。非空 `psize` 会让 ULW 顺带把窗口设成这个尺寸——本档只在无边框形态生效，那形态下窗口尺寸本就该等于客户区，无可见变化。
**验证**：补丁后同一探针只走 `wm_present`：卡片 17629–18000/18000 上屏、透明区角落纯黑像素 2/1600（桌面真透出来）、`opacity=128` 时纯色像素掉到 0、边框回来后 `winrect` 仍 380×280；`moon test gui/win` 32/32、`moon check --deny-warn` 零输出。真机目视同批留档（`C:/ProgramData/wmprobe/v9_card.bmp`）。
**教训**：① 「API 返回成功」不等于「效果发生了」——这类**成功但无副作用**的调用（ULW、`SetWindowPos` 的某些组合、`InvalidateRect` 遇上不自绘的窗）只能靠像素判据兜；② 跨平台桩里凡是把平台 API 的默认语义（「不传就沿用当前值」）当契约用，都要在**目标机器**上量一次，文档与实现不一致时以实测为准；③ 定位这类「什么都不显示」的问题，先把**状态字段**（谁在管这个档位）与**像素**（到底有没有画）分开收，二者一对就能排除掉一半候选。

## WorkerW 不自绘暴露区：撤掉挂在它下面的子窗后，壁纸层留着最后一帧，且**没有任何重画通道能清**（2026-10-28，Windows 真机「壁纸层残影」）

**症状**：窗切到「图标下」（`SetParent` 进壁纸 WorkerW、`WS_CHILD`）后，撤档 / `hide` / `close`，壁纸上留下该窗最后一帧。量化：320×180 纯色块撤掉后原地仍占 57394–57600/57600 像素（另一色 56399/57600），**跨进程退出仍在**、持续数分钟不自愈。与透明测试窗无关（残影那几轮没开任何逐像素窗）。
**根因**：`wm_desk_repaint_host` 的时机是「子窗还挂着」时 `InvalidateRect(host) + UpdateWindow(host)`——宿主的 `WM_PAINT` 裁剪区扣掉了子窗那块，等于什么都没画；摘钩之后又没人再请求重画。但**顺序不是唯一问题**：把重画挪到摘钩之后仍然无效。
**实测无效的通道**（逐条单独试、每条都抓屏数像素）：`RedrawWindow(host, rect, RDW_INVALIDATE|RDW_ERASE|RDW_UPDATENOW)`、`RedrawWindow(host, NULL, NULL, …|RDW_ALLCHILDREN)`、`SendMessage(host, WM_PAINT)`、`SendMessage(host, WM_SETREDRAW, FALSE/TRUE)` + 整窗失效、`Progman` 的 `WM_COMMAND 0x7402`（老「刷新桌面」口子）、`Progman` 的 `RedrawWindow`、宿主 `SetWindowPos(… SWP_FRAMECHANGED)`——一条都没动那 5.7 万像素。
**实测有效的两条**（都得让壁纸层整体重建，代价是桌面闪一下）：① `SystemParametersInfoW(SPI_SETDESKWALLPAPER, 0, 当前路径, SPIF_SENDCHANGE)`——**不带** `SPIF_UPDATEINIFILE` 就不写注册表，实测同样清干净（57600/56399 → 0/0）；② `ShowWindow(host, SW_HIDE)` → `ShowWindow(host, SW_SHOW)`（57392 → 0）。
**另一条设计路已堵死**：想让「图标下」档走逐像素提交（像素由 DWM 合成、不落宿主 GDI 面）——实测**逐像素子窗挂进 WorkerW 后根本不显示**（`trans_mode=1`、`embedded=1`、重提交后屏上 0/57600），这一档只能用 GDI 画进宿主面，残影必须靠清屏通道解决。
**修复（2026-10-28 次日定案并落地）**：`wm_desk_repaint_host` 改成 `wm_desk_purge`——`ShowWindow(host, SW_HIDE)` 紧接 `ShowWindow(host, SW_SHOW)`，隐藏时长 **0ms**（实测 0/30/60ms 三种结果一致，重建发生在隐藏那一刻，不必留可见空白期，也不阻塞 UI）。不选另一条同样能清的 `SPI_SETDESKWALLPAPER`：实测 `SPI_SETDESKWALLPAPER(0, NULL, SPIF_SENDCHANGE)` 会把**纯色桌面重画成注册表里留存的壁纸图**（本机注册表 `WallPaper=img0.jpg` 而实际桌面是纯色，调用后宿主客户区 1920×1080 逐像素全变），那是改用户外观。宿主 hide/show 前后整张宿主客户区逐像素比对 `diff=0`、宿主句柄不变、注册表不动。
**同时改了三处调用顺序**：残影产生于「窗不可见」那一刻，所以 `wm_hide` 要先 `ShowWindow(SW_HIDE)` 再 purge；`wm_close` 要在 `DestroyWindow` 之后 purge；`wm_leave_desktop` 要在摘钩 + 复位之后 purge（原来三处都排在窗还可见时）。
**最终读数**：门面直调四条路径（撤档回普通 / 撤档到置顶 / `hide` / `close`），挂进去时 `embedded_visible=57600`，撤掉后**全部 `leftover=0`**；同一探针把补丁 `git stash` 掉重跑，四条**全部 `leftover=57600`**，对照成立。`moon test gui/win` 32/32、`moon check --deny-warn` 全仓零输出。
**已知代价**：整个壁纸层（连桌面图标、以及别的挂在同一 WorkerW 下的「图标下」窗）会闪一下，约 30–80ms。这条路绑宿主身份，Explorer 重建后 `desk_host` 会失效——`IsWindow(host)` 检查让它安全跳过（跳过即退回已知边界，不崩）。
**另两条路已实测堵死**：① 预防——摘钩前先把子窗 `ShowWindow(SW_HIDE)` 等 250ms 再摘，`after_hide` 与 `after_detach` 都是 57600，隐藏子窗同样不触发宿主擦除；② 绕开——让这一档走逐像素提交，逐像素子窗挂进 WorkerW 根本不显示。
**教训**：① 「请对方重画」的前提是**对方会重画**——WorkerW 是 Explorer 用来承载壁纸的壳，它本身不处理 `WM_PAINT`，`InvalidateRect` 这类请求全部落空；② 判断「谁该负责清屏」要看**像素到底落在谁的面上**，而不是看谁在代码里父子上更近；③ 这类不可自愈的视觉脏数据必须用「跨进程复测」确认持久性——同一个进程里看到的「还在」可能是帧缓存没刷，跨进程还在才是真烙进去了。

**补记（同日，档内移动/改尺寸也一并收口）**：撤档之后还剩一个口子——窗**还挂在**「图标下」档里时调 `move_to` / 改尺寸，旧位置同样没人擦（同一条根因：宿主不自绘暴露区）。当时判成「本批不处理，得先定节流方案，否则每帧重建宿主会让拖动卡顿」，**这个判断的前提是错的**：这一档根本没有交互。子窗挂在 `WorkerW` 里，桌面图标层（`SHELLDLL_DefView`）在它上面，鼠标与键盘事件被图标层截走，本窗连 `WM_LBUTTONDOWN` / `WM_LBUTTONUP` 都收不到（Linux 侧的 `Desktop` 档也是同一语义，见本文「图标下档不可交互是这一档的语义，不是缺陷」那条）；档内的位置/尺寸变化只可能来自程序自己驱动，所以不存在「跟随拖动逐帧一清会卡顿」，直接每步清即可。改法：`wm_window_move` 与 `wm_window_set_size` 末尾各调一次 `wm_desk_repaint_host`（未挂载时 no-op）。**读数**：挂进档内连移 3 次，原位 `old_spot=57600 RESIDUE`（修前）→ `0 CLEAN`（修后）；档内缩窄 120px 后原本被窗盖住、现在露出的那条带子 `exposed_band=0 CLEAN`。代价与撤档同源：每次挪动整张壁纸层闪一下，因此**别在档内做逐帧动画**（真要做，得另找不重建宿主的通道，实测那九条全部无效）。

## Win32 通知区图标不随进程回收：只做 SNI 兜底的 `remove_all_trays()` 会留僵尸图标（2026-10-28 真机）

**症状**：程序退出后托盘图标还留在通知区，**右键它既不出菜单也不出 tooltip**——看起来像「托盘右键菜单没实现」，实际上菜单本身好好的。
**定位**：先排除菜单——showcase 右键实测弹出 `#32768` 窗 `rect=(1713,959) 150×101`，四项齐全（冒个提示 / 回首页 / 报左键计数 / 退出），选中项也回得去。问题在**图标没人管**：进程走了，通知区项还在，没有窗口接 `WM_TRAY_CB`，点它自然什么都不发生；鼠标悬停一下图标会自己消失，那是 Shell 发现宿主窗口没了才顺手删的。
**根因**：`gui/shell/tray.mbt` 的 `remove_all_trays()` 只有一行 `@dbus.sni_unregister_all()`，注释把它写成设计假设：「Win32 的通知区项由 shell 随进程回收，不需要注销」。**这条假设是错的**（回收时机是「下次鼠标交互」而不是「进程退出」，中间这段时间就是僵尸）。`gui/win` 侧也没有批量注销门面，只有单个 `wm_tray_remove(slot)`。
**修复**：`remove_all_trays()` 先取 `tray_by_slot.to_array()` 快照，逐个 `Tray::remove()`（内含 `wm_tray_remove` + 摘表 + 清语言口），再走 SNI 兜底。快照是必须的——`remove` 会改 `tray_by_slot`，边遍历边删不安全。
**验证**：重建后走菜单「退出」→ 图标**立即消失**（抓屏时先把光标移离托盘区，避免 Shell 顺手清理干扰判断）；`moon test gui/shell` 55/55，新增用例量 `@win.tray_count()` 由 1 到 0（旧实现下恒为 1）。
**遗留边界**：`taskkill` / 崩溃 / 断电仍留僵尸图标，Win32 通病——没有 `SetConsoleCtrlHandler` 或 Job Object 兜底时拦不住，只能靠用户悬停让 Shell 回收。
**教训**：① 「系统会自动回收」这类**默认行为**必须验证**时机**——进程退出与资源释放不是同一件事，中间窗口期正是用户能看到的缺陷；② 跨平台抽象里「另一端不需要做 X」的注释最容易掩盖漏实现，写这种断言时该顺手在目标平台量一次；③ 用户报「菜单弹不出来」时，要先分清是**菜单没画出来**还是**根本没人处理这次点击**——前者查 `TrackPopupMenuEx`，后者查图标宿主进程还在不在。

## 虚拟机里的「机器」与「显示器」都读不到：一条是虚拟机固件不给表，一条是 Windows 臂压根没接（2026-10-28，QEMU/SeaBIOS 虚拟机截图）

**症状**：演示板「系统能力探测 → 系统桌面 → 系统与机器」里 `机器: 读不到：SysInfoError::SiReadFailed(HARDWARE\DESCRIPTION\System\BIOS:SystemManufacturer)`；同一个探针页的「显示器」分段也是空的。用户判断：虚拟机的虚拟显示器应该读得到。

**显示器（真缺口）**：`mon_list()` 当时只有 Linux（xrandr）与 macOS（CoreGraphics）两臂，**Windows 直接掉进 mac 臂**，桩体恒回 `ok=0` → `Unsupported`。也就是说 Windows 上从来没接过显示器枚举，与虚拟机无关。
**修法**：`yue_sys_mon_win`（`EnumDisplayDevicesW` 列贴桌面的适配器 + `EnumDisplaySettingsExW` 取当前档与模式表），输出与 mac 臂同一份 `MON`/`MODE` 行式文本，MoonBit 侧复用同一个解析函数（`mon_parse_mac` 因此改名 `mon_parse_blob`）。实测 QXL 虚拟显卡读到 `DISPLAY1: 1920x1080 @64.0Hz 位置 +0+0，支持模式 30 种`。
**回马枪（mac 链接断，同日）**：这一段当时写成 `#if __APPLE__ / #elif _WIN32 / #else` 三臂，但只有最后的 `#else` 同时给了两个符号的桩——mac 臂里 `yue_sys_mon_win` 压根没定义，而 MoonBit 侧 `extern "c" fn ffi_mon_win` 是无条件的（三平台同一套链接），于是 mac 上 `moon run examples/showcase` 报 `Undefined symbols: _yue_sys_mon_win`。**修法**：mac 臂末尾补一个恒回 `ok=0` 的 `yue_sys_mon_win` 桩，与 `_WIN32` 臂里那个 `yue_sys_mon_mac` 桩对称。**教训**：加平台臂时，「另外几臂的符号桩」属于同一批改动；而且 `moon check` 只编不链可执行体，抓不到这类缺口——必须 `moon build --target native` 把带 `extern` 的示例真链一次。

**机器（虚拟机固件的坑）**：`si_machine()` 的 Windows 臂一直只读注册表 `HKLM\HARDWARE\DESCRIPTION\System\BIOS`——那是内核从 SMBIOS 抄的镜像。这台 QEMU/SeaBIOS 机器上这个键**存在但 `ValueCount=0`**（一个值都没有，`GetSubKeyNames` 也空）。继续往下查：
- `GetSystemFirmwareTable('RSMB', 0, …)` → 返回 0，`GetLastError()=ERROR_INVALID_FUNCTION(1)`；`EnumSystemFirmwareTables` 连一个 provider 都不给 → **用户态没有固件表可读**；
- `HKLM\SYSTEM\CurrentControlSet\Services\mssmbios\Data` 只有 `AcpiData`/`BiosData`/`RegistersData`，逐字节找 `_SM_`/`_SM3_`/`BOCHS` 全无 → 原始 SMBIOS 表**不在注册表里**；
- 而 WMI 读得到：`Win32_ComputerSystem` 给 `Manufacturer="BOCHS_"`、`Model="BXPC____"`（`Win32_BIOS`/`Win32_ComputerSystemProduct` 的序列号则全 null）。

**结论**：SMBIOS 表只留在 mssmbios 驱动那边，WMI 提供方走 IOCTL 取，**用户态唯一的路就是 WMI**。
**修法**：`si_machine()` 的 Windows 臂改成两级——注册表镜像（真机常态）→ 空则 `yue_sys_wmi_machine`（`Win32_ComputerSystem` 的 `Manufacturer`/`Model`，序列号再依次试 `Win32_BIOS.SerialNumber`、`Win32_ComputerSystemProduct.IdentifyingNumber`，最后落 `MachineGuid`）。实测页面显示 `机器: BOCHS_ BXPC____（序列号 a2d70bed-…）`。
**C 侧三个坑**：① `wbemidl.h` 的 `CLSID_WbemLocator`/`IID_IWbemLocator` 是 `extern` 常量，C 模式用不了 `__uuidof`，必须链 **wbemuuid.lib**（同 `IFileDialog` 那批的坑）；`SysAllocString`/`VariantClear` 在 **oleaut32.lib**——于是 `gui/scripts/prebuild.py` 的 sys 包链接串多了这两个库。② `ConnectServer` 之后要 `CoSetProxyBlanket(…RPC_C_AUTHN_WINNT…RPC_C_IMP_LEVEL_IMPERSONATE…)`，不设的话 `ExecQuery` 在部分机器上回 `E_ACCESSDENIED`。③ 每条查询自建连接、自释放，**不缓存 `IWbemServices`**：`si_machine` 可能从任意线程进，COM 代理跨套间复用不安全；这条路径只在注册表为空时才走到，慢一点无妨。

**教训**：① 「读不到」先分清是**没实现**还是**环境不给**——显示器是前者（Windows 臂从来没接），机器是后者（固件不交表），两者的修法完全不同；② 「注册表里有这个键」不等于「键里有值」——`Test-Path` 为真、`ValueCount=0` 这种情况必须量到值层面；③ 平台的固件表接口（`GetSystemFirmwareTable`）在虚拟机上可能是 `ERROR_INVALID_FUNCTION`，而 WMI 仍读得到——把 WMI 当**兜底**而不是主路径，真机上就不必为它付 COM 的那份开销。

## Windows 链接串漏了 `gdi32.lib`：夜间色温的桩能编，每个用到 sys 的 exe 都断在 `LNK2019 __imp_SetDeviceGammaRamp`（2026-10-28，用户 Windows 真机 `moon build` 日志）

**症状**：桩全部编过，链接期第一条硬错 `libsys.lib(sys_stub.obj) : error LNK2019: 无法解析的外部符号 __imp_SetDeviceGammaRamp，函数 yue_sys_nl_set_ramp 中引用了该符号`，紧跟 `fatal error LNK1120` 落在 `dialog_probe.exe`，整次构建 `failed when building project`。
**根因**：夜间色温 Windows 档那批只改了 C 桩（`yue_sys_nl_set_ramp` 直调 `SetDeviceGammaRamp`）与 MoonBit 侧，**没同批改 `gui/scripts/prebuild.py` 的 sys 包 Windows 链接串**，里面没有 `gdi32.lib`。同一段注释当时还写着「平台批③显示器枚举要 gdi32（…故保持原样）」——把「用到 DC 一族」和「要链 gdi32」混成一句，flags 里既没有 gdi32，这句话也就从没被对着核过。
**判据**：① `__imp_` 打头的是 Win32 **导入函数**，符号在哪个 `.lib` 就该链哪个：`SetDeviceGammaRamp` 在 `gdi32.lib`（同一函数里的 `GetDC`/`ReleaseDC` 在 `user32`，两个都得在）；② 报错行的 `lib<归档>(<对象>.obj)` 直接点名包，去 prebuild 找那个包 Windows 分支的 `link_flags` 一行即可，不必翻桩源码；③ `sys_stub.obj` 是一个整体，进了链接就全体生效——**每个用到 sys 的 main 包都断在同一条**，首个失败者是哪个示例不说明问题。
**修法**：sys 包 Windows 链接串补 `gdi32.lib`，注释按 API 归属逐条重写（枚举显示器在 user32、不需要额外库；gamma 斜坡在 gdi32）。对外口径进 `docs/zh|en build.md`：§6 两行（`__imp_*` 缺库、MSVC COM 告警）、§8 一条须知（Windows 分支每用一个新的 Win32 API，同批把库补进链接串）。
**验证**：本机只能验「没碰坏别的」——`moon test sys` 215/215、`py_compile` 过；改动全在 Windows 分支，mac 走不到。真机复验（用户 Windows）：`moon build --target native` 起手的 `LNK2019/LNK1120` 消失，`experiment/dialog_probe` 与其余 exe 全部链过。
**教训**：① Windows 上「桩编得过」不等于「库链得上」，`moon check` 与非 Windows 门禁都抓不到缺库——链接串是平台分支代码，改桩就要同批改；② 注释里的「要 X 库」与 flags 里的实际清单是一对可核对读数，二者不符本身就是缺陷，写注释时逐条对着 flags 核；③ 巡检不止报错那一处：本轮把全仓 C/C++ 源按 gdi32/dwmapi/shcore/uxtheme/msimg32/winmm/iphlpapi/psapi 一族符号扫了一遍，只有 sys 缺（`win/stub.c` 的 `CreateDIBSection`/`StretchDIBits` 早就带着 gdi32；`experiment/icon_probe` 是手工编译的探针，注释里已列明库）。

## WebView2 桩 31 条 MSVC 告警的三类根因：`Vtbl` 不许加 `const`、`self` 形参类型逐接口各写一份（2026-10-28，同轮 Windows 真机日志）

**症状**：`modules/gui-webview/webview/webview2_stub.c` 刷一片 `C4090 不同的 const 限定符`（约 25 条，落在 766/1141/1330×4/1399-1412/1442/1679/1726/1978）、`C4113 参数列表不同`（4 条，1281/1285 两对）、`C4133 类型不兼容`（1 条，1296）。都不挡构建，但把上面那条真错误埋进噪声里。
**三类根因与修法**：① **`const` 的 Vtbl**——SDK 的 COM 结构里 `lpVtbl` 字段是**非 const 指针**，`static const IXVtbl vt = {...}` 再 `x->lpVtbl = &vt` 每处赋值吃一条 C4090；本文件 13 处显式声明加 `WB_EVT_HANDLER` 宏模板（展开覆盖 12 个事件 handler）一律去掉 `const`，一条规则清掉绝大多数告警。② **一个实现塞两个接口的 vtable**——`WbOpt_get_bool`/`WbOpt_put_bool` 按基类 `ICoreWebView2EnvironmentOptions *self` 写，装进 `EnvironmentOptions2/3` 的表里就是 C4113；补 `WbOpt2_*`/`WbOpt3_*` 各按自己 `self` 类型的四份小桩。这条不是风格问题：`WbOptions` 是四个子接口**顺序嵌套**的结构，QI 交出的是 `&o->opt2` 这样的子槽指针、`rel/ref` 靠 `offsetof` 反推对象，拿基类签名去解引用 `self` 会读到错位内存——正好处处 `(void)self` 才一直没出事。③ **`LPCWSTR` 与 `LPWSTR` 之差**——SDK 的 `SetAllowedOrigins` 收 `LPCWSTR *`，桩写成 `LPWSTR *`；同族 `GetAllowedOrigins` 的出参却是 `LPWSTR **`，一对属性上下不对称，只能逐个查头。顺带把 `wb_regs_build()` 的返回类型从接口指针改成实现类型 `WbReg **`，调用点少一次强转，C4133 随之消失。
**判据**：MSVC 的行号指着 **vtable 初始化列表里的那一项**（不是函数定义行）——顺着它看数组下标是 SDK 声明的第几个槽，再去 `include/WebView2.h` 抄那一槽的原签名，比猜快。
**验证**：告警只有 MSVC 编得出来，本机 clang 复现不了；改动全在 `#ifdef _WIN32` 分支内，mac/Linux 编的是空翻译单元。真机复验口径：同一份 `moon build --target native` 日志里 `webview2_stub.c` 应一行不出。
**教训**：① C 模式手写 COM，`Vtbl` 实例加 `const` 是「看着更安全、实际每处赋值都报警」的写法，按 SDK 字段类型来；② 编译器不替你查「同一个函数塞进不同接口的 vtable」（只给 C4113），`self` 类型关乎内存布局；③ 告警清零的收益是可读数——31 行噪声里埋着一条 LNK2019，Windows 排查先清噪声。

## MSVC 链路上 `-D` 值的引号到不了宏：`NG_FFMPEG_BIN` 展开成裸路径记号，`ffmpeg_win_dll.c` 一片语法错（2026-10-29，用户 Windows 真机 `moon build` 日志）

**症状**：延迟加载首上 Windows 真机即炸：`ffmpeg_win_dll.c(50)` 起 `error C2065: "C": 未声明的标识符`、`C2143 缺少")"(在":"前面)`、`C2059 ")"`，57/61/65 行级联报 `mod 未声明`/`return`/`}`；同批其余 C 桩全部编过。cl 命令行里是 `-DNG_FFMPEG_BIN=C:/…/vendor/win/bin`——prebuild.py 明明写的是 `-DNG_FFMPEG_BIN="<目录>"`，引号在路上没了。
**根因**：Windows 上这条 flags 从 moon 到 cl 走的是「拼命令行字符串 → MSVC argv 解析」，`"` 被当参数分组符剥掉，宏值成了裸记号序列；`NG_FFMPEG_BIN[0]` 展开成 `C:/Users/…[0]`，`C` 被当标识符、`:` 打断 if 语句，后面全是级联。同一条 `-I"C:/…"` 也被剥了引号但侥幸活着——路径无空格，引号本来就可有可无；宏要当字符串字面量用就必炸。这个 -D 只在 Windows 分支下发、使用点只在 `#ifdef _WIN32` 里，mac/Linux 门禁永远编不到，写下的引号写法从没在真机成立过。
**判据**：① 指纹对号：`“C”: 未声明的标识符` + `: 前缺 ")"` 正是裸路径被当代码解析的形状，对着第 50 行一读即中；② 打印出来的 cl 命令行就是直接证据——源头写了引号、落点收到裸值；③ 排环境：windows.h 包含成功（49 行 `HMODULE`/`LoadLibraryA` 零错），缺 INCLUDE 变量会死在 C1083，不会走进语法分析。
**修法**：不在 `-D` 上传引号，改 C 侧两级宏记号字符串化：`NG_FFMPEG_STR(NG_FFMPEG_BIN)`（`#x` 套一层）把裸记号还原成字符串字面量，使用点统一走 `vf_bin_dir`；默认值不能参与串化（`#` 作用到 `""` 得到的是含两个引号字符的串，不是空串），用 `#ifdef` 分支直写空串。prebuild 去掉值上的引号，路径含空白时打警告（空白在 argv 层就拆断记号，串化救不了）。cl/gcc/clang 通用。
**验证**：本机 clang 以与 cl 同形的裸记号 `-DNG_FFMPEG_BIN=C:/…` 编样例，串化读数与路径逐字一致（len=98）；无 `-D` 档 len=0。`moon check`（gui、ffmpeg-mbt）零输出、`moon test`（ffmpeg-mbt）1599/1599、`moon build examples/audio` 通过。mac 编不到 Windows 分支，C 侧待真机：`moon build` 该文件一行错误不出；`moon run examples/audio` dll 不搬家能播（回落目录生效）。
**教训**：① 跨平台下发的 `-D` 值别带引号，也别指望宏值直接当字符串用——Windows 这条链引号进不了宏，字符串字面量在 C 源里用 `#` 串化还原才是正位；② 宏默认值与串化宏要分开处理，`#` 作用到 `""` 串进去的是引号字符不是空串；③ 只在单平台分支生效的代码，「写完」的判定在该平台真机过门禁——上一条目挂着的「待 Windows 真机」清单就是为此留的窗口。

## WebView2 就绪窗口竞态与 blob 下载不起步：绑定 shim 丢失、探针改走真实 URL（2026-10-30，Windows 真机打包测试）

- **现象一（绑定丢失）**：bin 包里的 browser 在冷启动后，页面点「JS 调原生绑定」报 `demoBinding is not defined`；热缓存下又能好。现象二（下载不起步）：load_html 片段页的下载探针（blob + `<a download>`）点了毫无反应——保存框不弹、状态无变化。
- **根因一**：WebView2 的环境/控制器创建是异步的，`WbView` 句柄在 `wb_create` 即登记、`ready` 要等创建回调——中间是就绪窗口。`wb_add_user_script` 在窗口内**静默丢弃**注入（`AddScriptToExecuteOnDocumentCreated` 要 web 在位），而 `wb_add_binding` **不看丢弃与否，句柄在就返回 1**——示例的重试 tick 首拍（80ms）落进窗口就停止重试，shim 永远没注上。冷启动创建慢必现、热缓存快则偶过。WebKit 两臂同步注册无此窗口。
- **修一**：注入拆 `wb_add_user_script_checked` 返回真假，`wb_add_binding` 只在 shim 真注上时返回 1——重试 tick 自然续拍到就绪为止（上限 60 拍）。教训：**「调用了注入口」不等于「注入成功」**，异步就绪的引擎，注入口的返回值必须反映真伪，调用方的重试语义才成立。
- **根因二**：blob 下载不引发导航，WebView2 的 `DownloadStarting` 对它不起步（引擎缺口，上游 WebView2Feedback #4562/#2180 同类）；WebKitGTK 上 ba26ab18 挂协议 base 后能走通，属引擎差异不是桩缺陷。
- **修二**：browser 示例的下载探针从 blob 换成协议真实 URL（`yuedemo://local/ngui.txt` + `download` 属性强制落盘不渲染），三引擎同走常规下载管线进「上报-扣住-落判」闭环；blob 路径的引擎差异记档于此，库侧不做 blob 特判。
- **验证**：gui-webview `moon check` 零警、`moon test` 1599 全绿（Linux/webkit 臂不受影响）；webview2 桩 MSVC 编译与真机行为由 CI Windows job + 用户真机复验（demoBinding 点按、下载探针弹保存框落盘）。

## Windows 专有 C 在本机的语法级校验：最小头桩 + gcc -fsyntax-only（2026-11-03，UIA provider 二批）

`gui/win` 的 Win32 分支只有 CI 的 windows-latest 腿（`moon test ... win ...` 走 native-stub + MSVC）才编，本机 Linux 上一次都没编过。UIA provider 二批（五 pattern + FragmentRoot，纯 COM vtable 手写）在本机先搭一套**最小 Windows 头桩**（`/tmp/winhdr`：windows.h / oleauto.h / uiautomationcore.h，只声明用到的接口面，vtable 项数按 SDK 口径写）再 `gcc -fsyntax-only -std=c11 -Wall -Wextra -D_WIN32 -I/tmp/winhdr gui/win/uia_provider.c`——**校验的正是「vtable 初始化项数/顺序」这件手写 COM 最容易错、且 MSVC 才会报的事**。本批实测抓到两处真问题：①`snprintf` 缺 `<stdio.h>`（首批蒙对是 MSVC  transitive include 赏的，不赏的编译器直接隐式声明）；②**COM 对象布局坑**——pattern 对象的 vtable 指针必须是结构体首成员，QI 对 `IUnknown` 与主接口同回主接口指针；若把 IUnknown 与 pattern 接口拆成两个成员，方法收到的 `self` 指向第二个成员，`(WmX *)self` 强转整体偏移错位，读到的是垃圾（不崩也只是运气）。头桩不进仓库（按环境搭），判据：Win32 分支 C 改完先在桩下过一遍 `-fsyntax-only` 再提交，MSVC 腿只当二验。

## UIA provider 二批（五 pattern + FragmentRoot）：快照只读、动作走「点一下」（2026-11-03）

pattern 的值读侧全部从帧尾语义快照现取（Toggle 态读 state 串、Value 读 value/text、RangeValue 按百分比口径 0–100 解析 `50%`、IsPassword/IsReadOnly 读 state）；**动作侧不碰组件**——Store 与 Editor 都锁在组件闭包里，C 侧够不着也不该够着，Invoke/Toggle/Expand 只把「(快照行号, 点击)」压进动作队列（`stub.c` 实现 TU 段的环形队列，GTK/mac 无 provider 恒空但符号要在），MoonBit 每帧抽走、按 id 找控件、在控件中心合成 Down+Up 走与真实点击同一条 `route_pointer`——组件的点击链路自己驱动业务，桥不双触发。Value/RangeValue 的 SetValue 如实回 `E_NOTIMPL`（读屏改值走键盘），不装能写。BSTR 是 UTF-16、快照是 UTF-8：`SysAllocStringByteLen` 直拷会让中文名乱码，统一 `MultiByteToWideChar(CP_UTF8, …)`（首批的属性映射同批修）。GUID 取法定案：C 模式用不了 `__uuidof`，IID/PATTERNID 常量 SDK 头声明 + 链接期取 `uiautomationcore.lib` 符号，与 WIC 的 windowscodecs.lib、任务栏的 uuid.lib 同一条套路。已知边界：快照表是**进程级单表**（`wm_a11y_publish` 整体替换），多窗应用读屏看到的是最后绘制那扇窗的树——单窗（绝对多数）完全正确，多窗要修得把快照表按窗口键分份。

## Windows 全链首编五处缺口：UIA 头、POSIX 头、DWrite 结构档（2026-11-06，SDK 10.0.26100 真机日志）

Windows 真机 `moon run` 首次全量编译暴露——**全是 Windows-only 编译路径，Linux 门禁（prebuild 只编 GTK 臂 + gui-gpu）覆盖不到**：

- **`uiautomationcore.h` 不能裸 include**：它假设调用者已含 COM 基础头；`WIN32_LEAN_AND_MEAN` 下 `windows.h` 不带 ole 系，`interface` 宏（C 模式下 combaseapi.h 的 `#define interface struct`）未定义 → 头内全部 `interface IXxx;` 前向声明语法错（一屏 C2061/C2059 连锁）。**UIA 符号归属是拆的**（微软文档 Requirements 为准）：provider 接口本体与枚举（`ToggleState`/`ExpandCollapseState`/`ProviderOptions`/`NavigateDirection`、`UiaRect`、各 `IRawElementProvider*` vtable）在 **uiautomationcore.h**；`UIA_*PropertyId` 属性常量在 **uiautomationclient.h**；`UIA_*ControlTypeId/PatternId` 聚合头 uiautomation.h 就供；`UiaReturnRawElementProvider`/`UiaHostProviderFromHwnd`/`UiaRootObjectId` 在 **uiautomationcoreapi.h**。定案（2026-11-06 链接期修正）：**`uiautomationclient.h` 谁都不引**——SDK 把 `UIA_*` 常量写成文件域 `const long` 定义（16299 头实物 377 条），C 下带外部链接，两个 TU 各含一次就在链接期 LNK4006/LNK2005 互撞全表；用到的常量反正都由自给层给。uia_provider.c：`ole2.h` + `objbase.h` + `uiautomationcore.h` + `uiautomationcoreapi.h`；stub.c 只用 `UiaRootObjectId`，改成本地 `#define UiaRootObjectId (-25)`（coreapi.h 里本就是宏），**两个 UIA 头都不引**——接口头只留 uia_provider.c 一个 TU，聚合头 `<uiautomation.h>` 同样禁用。**C 模式还要一层自给**（SDK 头实物实证，16299/26100 皆然）：UIA_\* 常量在头里是 **`const long` 变量定义**、不是宏——纯 C 下 `const` 不是编译期常量，`case UIA_Xxx:` 直接 C2051；26100 连 provider 枚举类型也走 const 形态，类型名当形参报 C2081。修法：include 之后把用到的 31 个 `UIA_*` 按 ABI 数值（30005 等，跨版本恒定）`#define`，枚举/几何给自有 `Wm` 前缀形态（vtable 初始化全 `(void*)` 强转，签名与 SDK 声明二进制同形即可）。另两个小坑：**没有 `SysAllocStringW`**（BSTR 本身就是宽字符，只有 `SysAllocString`），写了会报假定返回 int 的 C4047；**没有 `UIA_IsReadOnlyPropertyId` 这个常量**——真名 `UIA_ValueIsReadOnlyPropertyId`（30046，Value pattern 的只读属性；RangeValue 版 30048）。**vtable 槽数**：`IRawElementProviderFragment`（9 槽 = IUnknown 3 + Navigate/GetRuntimeId/get_BoundingRectangle/GetEmbeddedFragmentRoots/SetFocus/get_FragmentRoot）与 `FragmentRoot`（5 槽 = IUnknown 3 + ElementProviderFromPoint/GetFocus）都是**独立接口**，不是 Simple 的顺延——把 Simple 的 4 槽铺进去就是 C2078「初始值设定项太多」。**多接口 COM 的容器换算**：一个 C 对象挂多个接口时，fragment/root 入口的 this 是内嵌结构地址，直接 `(WmProv*)self` 会错位（运行期字段全乱）；QI/AddRef/Release 与各方法都要 `offsetof` 回容器（simple 是首成员偏移 0 才可直接转）。
- **`wgpu_core.c` Win 分支缺 `windows.h`**：`HMODULE`/`LoadLibraryA` 落隐式声明（int 返回 → C4312 int→void* 警告只是表象）。
- **`canvas.c` 无条件含 `unistd.h`/`dlfcn.h`**：MSVC 无 POSIX 头（C1083）。shim 宏 `MNG_CV_DLSYM`/`MNG_CV_SLEEP_1MS`（Win32 = GetProcAddress/Sleep）。
- **wgpu 库 Windows 产物名/候选**：`wgpu_native.dll`（无 lib 前缀）——`MNG_WGPU_LIB_BASE` 加 `_WIN32` 档；候选补 `vendor/lib/`、`vendor/` 相对路径在前（裸名走 DLL 搜索序，从仓库跑的应用找不到 vendor 下的库 → L1 永远回退 cairo，复验会白跑）。
- **`DWRITE_LINE_METRICS`（v1）没有 `textPosition`**（那是 `LINE_METRICS1`/`IDWriteTextLayout1` 的字段）；行首 UTF-16 位用**前行长度累加**得到（DWrite 保证行区间连续），不必为这一个字段 QI Layout1。`HitTestPoint` 第 5 参是 `DWRITE_HIT_TEST_METRICS*`，不能传 `UINT32*`（结构体首字段恰好是 textPosition 也不能靠布局侥幸）。
- 关联环境态：`shell/monitor_dbus_wbtest` 的「KScreen 真总线集成」对会话状态敏感（KScreen 服务在但 `/backend` 对象不在 → 枚举失败报 FAIL 而非跳过），与代码无关时按环境波动处理（stash 对照复跑同败可证）。
- **多 TU 重复定义（C 模式）**：SDK 头里 `const long UIA_X = n;` 在 C 下是**外部链接的定义**、不是声明；两个 TU 包含同一份 client 头，链接器先报 LNK4006「已定义，忽略第二个」，同一库内成员再被拉入就升级成 LNK2005（必须全表清掉）。这与「C 下 const 不是编译期常量」是同一个头形态的两面：前者卡编译（C2051），后者卡链接（LNK2005）。判据：Windows-only 头里凡是文件域 const 变量，要么只在单 TU 引入，要么干脆不引、数值自给。**`uiautomationcore.h` 自己也带一个**：`const double UIA_ScrollPatternNoScroll = -1;`（26100 头 957 行，MIDL 的 `UIA_OtherConstants` module），不在上表那 377 条里。11-06 更新把 `uia_provider.c` 并入 `native-stub` 后，gui/win 两个 TU 都含接口头，`libwin.lib` 里先 LNK4006 再 LNK2005 `UIA_ScrollPatternNoScroll`、末了 LNK1169，所有 GUI 示例链不上（首个报错是 showcase）。定案：stub.c 不引 UIA 头、数值自给，接口头单 TU 化。**mingw 头把它们复刻成宏，本地语法闭环抓不到这一类**（宏不产生符号），只能靠 MSVC 链接日志。
- **幻影函数**：`UiaCreateRuntimeId` 在 SDK 里不存在（16299 头实物核过，只有 `UiaGetRuntimeId`）——凭记忆写过，MSVC 只报隐式声明警告、链接期才 LNK2019。RuntimeId 用 `SafeArrayCreateVector(VT_I4, …)` 自建。电源 API 的归属头同理：`PowerGetActiveScheme`/`PowerSetActiveScheme` 在 **powersetting.h**（不在 powrprof.h），C 模式漏了它也是隐式声明带过。
- **空串测量三平台不等价（2026-11-06 Windows 门禁）**：Pango 量空布局给「0 宽 + 单行行高/基线」，DWrite 侧 `ptw_wide(s, 0)` 经 `MultiByteToWideChar` 回 0、`ptw_layout` 建不出 0 长布局，`pt_measure_font` 于是返回 0 → `measure_font("")` 为 `None`。逐字边缘用例对 0 位前缀量宽直接 `abort("本平台没有文本测量")`。修法：`dwrite_text.cpp` 的 `pt_measure_font` 对 `len <= 0` 取 `pt_font_line_height` 的行度量、宽直接给 0；Pango/mac 分支不动。判据：`moon test mdview` 41/41。
- **本地验证闭环（Linux 上验 Windows 编译）**：`apt-get download mingw-w64-x86-64-dev mingw-w64-common`（免 root）+ `dpkg -x` 解到临时 root，`clang --target=x86_64-w64-mingw32 -fsyntax-only -std=c11 -I <root>/usr/x86_64-w64-mingw32/include [-I ~/.moon/include]` 即可把 Windows-only 的 C 文件全部语法验过（uia_provider.c/stub.c/sys_stub.c/wgpu_core.c/canvas.c 实测零错零警告）。注意事项：mingw 头把 UIA 常量复刻成**宏**（微软 SDK 是 `const long` 变量）——两边形态都要覆盖（自给层带 `#ifndef` 守卫即通吃）；mingw 缺 `_mingw.h` 生成头类文件时补 `mingw-w64-common`；`<string>`/`<unordered_map>` 走 libstdc++ 的 C++ 文件（如 dwrite_text.cpp）本机验不了（glibc 头与 mingw 目标不兼容），那类文件以真机 MSVC 日志为准。

## Windows wgpu 装载器缺仓库布局扫描：showcase GPU 页从仓库根启动降级（2026-11-06）

**现象**：showcase 第 16 页 GPU 画布区域没有内容，页面落进「GPU 画布建不出」降级文案。同一个 `gpu_triangle.exe` 从仓库根跑是 `probe loaded=false detail=not-found: LoadLibrary failed`，从 `modules/gui-gpu` 跑是 `loaded=true loaded(vendor/lib/wgpu_native.dll)`。vendor 归档不是没下载（`modules/gui-gpu/vendor/lib/wgpu_native.dll` 在），缺的是**找它的路径**。

**根因**：`probe.c` 与 `wgpu_core.c` 把「从 cwd 逐级上溯 `<anc>/vendor/lib/<lib>` 与 `<anc>/modules/gui-gpu/vendor/lib/<lib>`」整段圈在 `#if !defined(_WIN32)` 里，Windows 分支只剩 cwd 相对的 `vendor/lib/`、`vendor/` 与裸名 `wgpu_native.dll`；归档实际在 `modules/gui-gpu/vendor/lib/`，故从仓库根 / `examples/<name>` / `_build` 产物目录起的应用一律装载失败。`GpuCanvas::new` 又以**另一套独立的** `probe()` 作前置门槛（`probe()` 只查 `wgpuCreateInstance`，core 才真正建 instance/adapter/device），候选表一分叉就把「core 明明建得出设备」误判成降级。

**修法**：三平台统一祖先扫描——Windows 用 `GetCurrentDirectoryA` 取 cwd，`LoadLibraryA` 接受正斜杠作分隔符，故候选串与 POSIX 同形；上溯时取正斜杠与反斜杠里更靠右者截断，`(slash - anc) <= 2` 停在盘符根（`D:`），不把盘符截成空串。`GpuCanvas::new` 去掉 `probe()` 前置，只由 `mng_gpu_canvas_new` 内的 `mng_wgpu_ready()` 判定，失败原因走 C 侧 `canvas_detail()`（带 core detail）——画布只信自己实际用的那条装载链。

**判据**：从仓库根实跑探针得 `probe loaded=true detail=loaded(D:/code/moonbit-native-gui/modules/gui-gpu/vendor/lib/wgpu_native.dll)` → `canvas: Ok 64x48` → `finish: sample B,G,R,A=0,0,255,255, nonzero=1536`（32×24 红矩形，R+A 两槽非零）；`cd modules/gui-gpu && moon test gpu` 3/3 且像素断言真执行；全仓 `moon check`、库 `moon check`、全仓 `moon build --target native` 零错误零警告。

**边界（2026-11-07 已收）**：`gui/win/stub.c` 的 L1 呈现核心原先**刻意未动**——Windows 分支只试裸名 `wgpu_native.dll`，且 `L1_LIB_BASE` 仍是 `.so`，从仓库布局跑一律装载失败（Win 腿首验只能「dll 放 exe 旁 / 设 `MNG_WGPU_LIB`」）。现补齐同一套口径：库名加 `_WIN32` 档，候选序与 `probe.c`、`wgpu_core.c` 一字不差（`MNG_WGPU_LIB` → `vendor/lib/`、`vendor/` 相对路径 → cwd 逐级上溯 `<anc>/vendor/lib` 与 `<anc>/modules/gui-gpu/vendor/lib` → 裸名走平台搜索序），`GetCurrentDirectoryA` 取 cwd、正反斜杠取更靠右者截断、`<= 2` 停在盘符根（`D:`）。发行形态（cwd 在仓库外）仍走 `MNG_WGPU_LIB` 或把 dll 放 exe 同目录。Win 呈现档本身已于 2026-11-06 真机通过（界面与纯光栅一致、无闪烁、resize 不花），回归口径见 `测试文档/测试用例.md` SC-16.6。

## Windows 任务栏最小化必崩：swapchain 在 0×0 客户区上 acquire，wgpu 直接 panic（2026-11-07，真机复现并修复）

**现象**：Windows 上 showcase 窗口在任务栏点一下（收起）就**静默消失**——没有错误框、`Application Error` 事件日志里没有记录、终端只有 prebuild 行；而且每次必崩。时间点很关键：这是 `gui-gpu` 装载链补齐之后 Windows 第一次真正挂上 L1 present 档，所以是新暴露的路径，不是老 bug。

**定位（三条独立证据）**：① 进程退出码 `0xE06D7363`——MSVC 的 C++ 异常码，而 Rust 的 panic 在 MSVC 目标上正是用它抛出（wgpu-native 是 Rust）；② 栈帧除 `RaiseException` 外全落在 `wgpu_native.dll` 里；③ 取证档的面包屑末尾是 `present → l1.try → l1.present → l1.frame`，**偏偏没有 `l1.tex`**——而 `l1.tex` 是 `wgpuSurfaceGetCurrentTexture` **返回之后**才记的，说明就死在那次调用内部。

**根因**：`WM_SIZE` 对 `SIZE_MINIMIZED` 是刻意跳过的（客户区 0×0 不该把 GUI 逻辑尺寸归零），于是 `w->width/height` 仍是 1280×700；present 照旧带着这个旧尺寸去 acquire 一个真实尺寸已归零的 swapchain，wgpu-core 在 DX12 后端上直接 panic。**它不是走 uncaptured error 通道**：给 `WGPUDeviceDescriptor.uncapturedErrorCallbackInfo` 装上自己的回调后（A/B 实测）**照样 panic**，属内部断言型 `panic!`，用户侧没有钩子可拦——只能在进 wgpu 之前就不调用。

**修法**：`wm_l1_try` 在碰任何 wgpu 对象之前判 `IsIconic(hwnd)` 或 `GetClientRect` 归零 → 当「本帧已处理」直接返回（既不 acquire 也不回退 CPU 路径：最小化时确实没有可上屏的像素），同时置 `w->l1.stale`；`WM_SIZE` 的 `SIZE_MINIMIZED` 分支同样置 `stale` 且不动尺寸。还原时即便尺寸没变也主动 `need_draw = 1` 要一帧（遮挡期间内容不保证有效，而 GPU 档下 `WM_PAINT` 是不画东西的）；present 侧见到 `stale` 先把已配尺寸打回 0 逼一次重配（`l1_release_frame` + `l1_bind_frame`）再上屏。`stale` 放进共享核心的 `WmL1`，三臂同位，Linux/mac 需要时直接置位即可。

**验证（脚本化，不靠手点）**：本机写了 `toggle.exe`（`ShowWindow(SW_MINIMIZE)` → `SW_RESTORE` 循环，每轮用 `PrintWindow(PW_RENDERFULLCONTENT)` 抓客户区算 FNV 与非黑像素数）跑 6 轮——进程 6/6 存活；还原后 `nonblack=890748/896000`、hash 与最小化前**逐位相同**（既不是黑屏，也不是残留旧帧）；配合取证档能读到「窗口呈现挂上 GPU 档（surface 1280x700…）」，证明这一轮确实走 GPU 档而非悄悄回退 CPU。反向 A/B：把守卫关掉，第 1 轮最小化就 `0xE06D7363` 死——确认修的就是这条路径。

**顺带落地的崩溃取证档（默认关）**：`gui/win/crash_log.c`，`NATIVEGUI_CRASH_LOG=1` 打开。内容是 64 项环形面包屑（present / WM_PAINT / 尺寸变化 / show·hide / 弹层上屏 / L1 各阶段）加一个向量化异常处理器（VEH）：异常时把「异常码 + 各栈帧的模块与 RVA + 面包屑」写进 `NATIVEGUI_CRASH_FILE`（默认 `mng_crash.log`，已进 `.gitignore`）。踩过的四个坑：① **过滤清单里绝不能有 `0xE06D7363`**（Rust panic 走它，滤掉等于把 GPU 侧现场全漏光——本轮就栽在这，第一次抓到的其实是启动期噪声）；② 要滤的是 `0x40010006` / `0x4001000A`（OutputDebugString A/W）、`0x40010005`、`0x80000003`、`0x406D1388`；③ 落盘要允许多次覆盖（文件是 `CREATE_ALWAYS`），只许一次的话首发噪声会把致命现场挤掉；④ GUI 子系统进程没有终端，PowerShell 的 `-RedirectStandardError` 还会因环境里 `HTTPS_PROXY`/`https_proxy` 大小写重名直接抛异常，所以 `l1_log` 每条也镜像写入同一文件（`note t=<tick> …`）。另外 Intel 显卡驱动 `igvk64.dll` 在启动期会抛被它自己接住的 C++ 异常，按噪声看待，不必追。

## macOS / Linux 测试与示例链接失败：win 桩归档只编了 stub.c，缺 wm_crash_* 定义方（2026-11-07）

**症状**：`moon test`（gui 下任一含 sys/web 的包）链接期报 `_wm_crash_mark` / `_wm_crash_note` symbol(s) not found，arm64；Linux 同病：`moon build examples/hello` 报 `libyue_win_stub.a(stub.o): undefined reference to wm_crash_note / wm_crash_mark`（GTK 分支在 `wm_present` / L1 路径同样有调用点，此前记「GTK 零调用」是误判）。**根因**：`crash_log.c` 与 `stub.c` 是「同编」关系（调用点不落平台宏），Windows 下两者都在 native-stub 归档里所以没事；mac/Linux 的真实现分支由 `gui/scripts/prebuild.py` 单独编 `stub.c` 成 `libyue_win_stub_mac.a` / `libyue_win_stub.a`，crash_log.c 没跟上，分支内调用即成悬空引用（dbus/sys 等不引 win 包的测试目标不会链进 win 归档，符号无处可取）。**修法**：`compile_mac_stub` 支持多源文件（对齐 `compile_stub` 的多源口径），mac 与 Linux 分支的 win 桩都改传 `[stub.c, crash_log.c]`；同符号两处定义（native-stub 空分支 + 桩归档空实现）不冲突——ar 成员惰性拉取，先到先得，另一份无其他符号永不被拉。**判据修**：旧「源 mtime 新于归档才重编」漏掉「源清单变了」——新增的 crash_log.c mtime 比旧归档还旧，直接跳过、归档里缺成员（本次实证）；`stub_current` 补「`ar t` 成员清单必须齐全」一条，mac/GTK 两处共用。改 prebuild 后旧 `.a` 若仍判新，手动删一次 `gui/build/libyue_win_stub*.a`。
## tools 模块 release 链接断 Win32 符号：debug 的链接行多一串系统库把缺口盖住了（2026-11-08）

**现象**：`moon install ./tools/native-gui-tools/mng` 报 `libinst.lib(inst_stub.obj) : error LNK2019: 无法解析的外部符号 __imp_SendMessageTimeoutW / __imp_FindWindowW` + `LNK1120: 2 个无法解析的外部命令`；而 `moon build tools/native-gui-tools/mng --target native`（debug 画像）是绿的——「本机能构建」因此不成立。

**根因（`moon build … --dry-run` 抓到两份链接行，这是本轮唯一的定位手段）**：debug 画像 moon 在 `/link` 后追加 `libcmt.lib oldnames.lib kernel32.lib shell32.lib user32.lib dbghelp.lib uuid.lib`；release 画像只有 `/link /LIBPATH:$MOON_HOME/lib`，系统库全靠各对象自带的 `/DEFAULTLIB`。`tools/native-gui-tools` 没挂 `--moonbit-unstable-prebuild`（独立模块、要 `moon install` 发给用户，不该在用户机器上拉 Python 依赖），因此没有 `link_configs` 可下发，`inst_stub.c` 里 `FindWindowW`/`SendMessageTimeoutW` 的 user32 无人补——release 断链、debug 被 moon 那串系统库顺手救下。

**修法**：`inst_stub.c` 的 `_WIN32` 分支加 `#pragma comment(lib, "user32.lib")`，与 `gui/win/win_gui.c` 的 `#pragma comment(linker, "/SUBSYSTEM:WINDOWS")`、`modules/ffmpeg-mbt/src/ffmpeg_win_dll.c` 的 `#pragma comment(lib, "delayimp.lib")` 同机制：MSVC 把 `/DEFAULTLIB` 写进该 TU 的 `.drectve` 段，链接器抽到这份 `.obj`（符号被引用即抽）时自动带库，`mng` 与任何依赖方零配置，也不用在 tools 里造一份只为一行 flag 的 prebuild。

**验证**：`moon build … --release` 与 `moon install ./tools/native-gui-tools/mng` 均成功（`Success: Installed mng to C:/Users/…/.moon/bin/mng.exe`）；`dumpbin -dependents mng.exe` 的导入表出现 `USER32.dll`；`mng --help` 正常；`moon test ./tools/native-gui-tools/inst ./tools/native-gui-tools/proc` 7/7。

**判据**：① `LNK2019 __imp_*` 先看「谁的链接行」——挂了 prebuild 的库模块补 `gui/scripts/prebuild.py` 对应包的 Windows 链接串；没挂 prebuild 的独立模块（tools）用 `#pragma comment(lib, …)`，别为了一个 flag 引入构建期 Python 依赖；② **「debug 能过」不能当通**：两画像的链接行不同，而 `moon install` 走的是 release，CI 的 tools 门禁原来只有 `moon test`（debug），已在 Windows job 补 `moon build mng --target native --release`——这道缺口原本在 CI 上全绿。
## Windows stub.c C2371：前置调用的隐式声明与 void 定义冲突（2026-11-13，win 腿编译红）

- `wm_tray_set_icon_template` 定义在 `wm_tray_set_icon` 之前，体内前置调用产生隐式声明（默认 `int` 返回），随后遇到 `void` 定义报 C2371 重定义冲突——同一编译单元里委托包装必须放在被调函数定义之后（或先给前置声明）；移到定义之后即绿。

