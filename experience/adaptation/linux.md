# 平台适配·Linux专有

收 Linux 专有的实测坑与口径：G 系列批次、GTK / Pango / Cairo、D-Bus / SNI / 桌面集成、webview GTK 桩、Wayland / X11 / AT-SPI 与 Linux 真机反馈修复集。

### 无头化收尾：缺开发包占位降级与无字体回退 · 2026-11-14

- **占位归档的三方互斥**：缺 GTK 开发包时 prebuild 用新宏 `WM_STUB_LINUX_PLACEHOLDER` 把三个 stub.c 编成 `_ph.a` 占位归档（只保链接符号、`cr_*`/`pt_*`/`wm_*` 返 0），与「真实现 `.a`（`WM_STUB_GTK` 等宏）」「native-stub 无宏空 TU」三方永不同场。占位臂条件是「平台闸**追加**宏」——`(!defined(__linux__) && !defined(__APPLE__)) || defined(WM_STUB_LINUX_PLACEHOLDER)`；**不能放宽成 `!defined(__linux__) || …`**：那会把 mac 无宏的 native-stub 编译也带进占位臂，与 prebuild 的 mac 归档 126 个符号双定义（本批实测踩到后改回）。
- **`_ph` 独立命名不是美观**：`modules/gui-webview/scripts/prebuild.mbtx` 的 `find_win_stub_archive` 按真归档名 `libyue_win_stub.a` 查找，占位归档沿用重名会在「有 webkit 开发包、缺 GTK」的组合下把真 webkit 实现链到占位 win 桩上（`wm_surface_container` undefined）。
- **占位臂此前是死代码**：`win/stub.c` 的「其余平台」臂从没被任何编译触达过，藏着 `wm_hotkey_register` 重复定义与缺标准头（`snprintf`/`va_list`）两处旧账；开启占位编译首跑即暴露，属预期内的「低频路径不固化必烂」，CI 的 Linux bare 腿就是为固化它加的。
- **文本回退两层各治一段**：内建回退测量器（`gui/text/fallback.mbt`，纯 MoonBit）治「量不出」——占位档/无后端下 `measure` 复合入口按字符宽表估算，探针与守卫走 `measure_real` 不吃回退；内嵌字体子集（`text/assets/fallback-cjk.ttf`，Noto Sans SC 裁剪 965KB）治「有 Pango 无字体」——`pt_ensure_fallback_font` 探到 font family 数为 0 时 `FcConfigAppFontAddFile` 注册并 `pango_cairo_font_map_set_default(NULL)` 重置默认 fontmap（探测那趟可能已缓存了不含应用字体的配置快照），有系统字体绝不干预。注册代码挂三个入口：`pt_make_layout` / `pt_font_line_height` / `pt_fam_build`，once 开销为零。
- **字体路径编译期注入**：prebuild 用 `-DNGUI_FALLBACK_FONT_PATH="<module_root>/text/assets/fallback-cjk.ttf"` 下发——构建机器的绝对路径，发布场景使用者侧重跑 prebuild 重新解析；文件缺失只影响运行时注册（`AddFile` 自弃），不影响编译。
- **验证**：mac 本机 19 包 1422 测试全绿 + 五桩 mac gate 过 + mac 无宏空 TU 口径保持（符号数 0）；占位宏形态三桩 `clang -fsyntax-only` 过。Linux 占位真链与 bare 腿判定、无字体真机的内嵌字体注册，见 TODO「无头化收尾真机复验」。

### MoonBit 原生 GUI 栈 · Linux 全局热键后端 · W22 Linux 档 X11 `XGrabKey` · 2026-10-16

- **范围**：`win/stub.c` GTK 分支的 `wm_hotkey_*` 三件套从占位桩换真实现，新增 `wm_hotkey_supported`；门面 `core/hotkey.mbt` 与解析 `win/hotkey.mbt` 零语义变化——「两套码」约定本批生效：C ABI 的 register 加了第三个参数，`vk` 与 `keysym` 都传、各平台桩自己挑——Windows 取 vk、X11 取 keysym；MoonBit 侧 `register_global_shortcut` 改收 `Hotkey` 整体。
- **自开 X 连接而不是挂 GTK 泵**：`XOpenDisplay` 一条进程级连接，`XGrabKey` 落在它的根窗上；被抓的 KeyPress 只进本连接队列，`wm_hotkey_poll` 用 `XPending` 非阻塞抽——TODO 原设想的 `gdk_window_add_filter` / 周期 `XCheckIfEvent` 都不需要，泵完全不进 GTK 主循环。
- **变体抓取是刚需不是防御**：注册时对 `base`、`base|Lock`、`base|Mod2`、`base|Lock|Mod2` 四个变体各 `XGrabKey` 一遍。TODO 原设想「grab 时 `& ~(Mod2|Lock)`」行不通——掩码清位只是不匹配修饰，NumLock 亮时事件 state 含 Mod2、对不上就整键丢失；真机注入事件 `state=28`，即 Control|Mod1|**Mod2**，直接证明这台机器 NumLock 常开，无变体抓取则恒不触发。ScrollLock 即 Mod5，不抓变体、匹配时屏蔽。
- **BadAccess 是异步的**：组合被别的客户端占用时 `XGrabKey` 不当场报错——临时 `XSetErrorHandler` 陷阱 + `XSync` 后才知道；任一变体失败整体 `XUngrabKey` 撤回、按注册失败回报——门面落 `Err(Failed)`、不静默。无修饰的裸键拒绝，与 Windows `RegisterHotKey` 口径一致。
- **VT 切换保留域的坑，现象→根因**：探针沿用 W20b 的 `Ctrl+Alt+F9`，注册成功但注入恒不触发；最小 C 复现——裸 `XGrabKey` 加 XTEST 注入——同样不触发；换 `Ctrl+Alt+H` 一发命中——**`Ctrl+Alt+Fn` 是 VT 切换组合，事件在被动抓取之前就被服务器消费**，grab 注册得上但永远等不到。Linux 档选默认/演示组合避开 Fn 系，Windows 无此约束；这条也解释了 W20b 的 F9/F10 组合为什么在 Windows 侧无恙。
- **Wayland 口径**：`WAYLAND_DISPLAY` 非空时 `wm_hotkey_supported` 恒 0——XWayland 的 grab 只在 X11 窗口持焦点时生效，拿不到真全局性，按「没做」回报不装成功；出路见 roadmap「会话轴」，即 portal 或桌面守护协议。
- **验证**：`moon run experiment/hotkey_probe`——① 解析七组对照 ② 注册/幂等注销/槽位复用，`Some(1)`、`Some(2)`、再注册 `Some(1)` ③ 新增门面轮询段：`xdotool key ctrl+alt+h`——XTEST 走真实投递路径——收到 `HOTKEY-CORE-FIRE id=1 spec=Ctrl+Alt+H`，全链路 = 注入 → X server → 被动抓取 → 泵抽取 → 门面回查；`moon check` 零警告、库测试 982/982。顺手：`HotkeyError` 补 `Show`/`extend`——与另两族错误同构，探针才能 `\{e}` 插值。
  - 环境：Ubuntu 24.04 + X11 + XFCE

### 示例临时文件的落点选型：TEMP 之外的世界 · 2026-10-16 · 浏览器示例改版批

- **现象**：`examples/browser` 的 `scheme_root()` 只认 `TEMP` 环境变量、拿不到就回落**相对路径** `libyue-browser-scheme/`。Linux 桌面没有 `TEMP`——那是 Windows 惯例——于是每次跑示例都在**当前工作目录**落一个临时目录——从仓库根起跑时就是仓库根本身，留下一坨不入库的脏目录，本仓根下的 `libyue-browser-scheme/` 即其遗留。
- **根因**：临时目录选型按 Windows 单平台口径写死；「拿不到就回落当前目录」在 Windows 上近乎无害——`TEMP` 基本恒在；在 Linux 上却把「最不该写的地方」当了兜底。
- **修复**，改 `examples/browser/main.mbt` 的 `scheme_root`：按平台分流——Windows 走 `TEMP`，回落 `TMP`，再回落 `C:/Windows/Temp`，绝不回落相对路径；Linux/macOS 走 `XDG_RUNTIME_DIR`——用户级运行时目录，登出即清——再回落 `/tmp`。目录名同步更名 `native-gui-browser-scheme`，随仓更名，旧遗留目录直接删。
- **验证**：Ubuntu 24.04 冒烟后 `/run/user/<uid>/native-gui-browser-scheme/` 出现三份协议页文件——index.html、page2.html、style.css；仓库根无新增目录；`git status` 干净。
- **口径**：示例要往盘上写中间产物时，落点必须「系统临时区三选一」：`XDG_RUNTIME_DIR` → `/tmp`，或 Windows `TEMP` → `TMP`；**禁止回落当前目录**——`moon run` 的工作目录是使用者的事，示例不能假设。

- **引子**：`TODO.md` 里「旧链 `modules/gui-media` 下线」那句话被读成「不要 ffmpeg 了」。查证后确认 ffmpeg 一点没退场——新栈 `yue/media` 照旧 import `NoahLiu/ffmpeg-mbt/src`，是**解码后端**；但**带出一个真问题**：`yue/media` 住在主模块里，为让它 import 得动 ffmpeg-mbt，根 `moon.mod` 必须声明 `NoahLiu/ffmpeg-mbt@0.1.0`——于是**所有消费主模块的人都把 ffmpeg 拉进依赖闭包**，当初「媒体拆成独立模块＝可选依赖」的设计被抵消了。
- **机制，moon 的硬约束**：`moon.pkg` 的 import 必须先由 `moon.mod` 声明模块依赖，否则报 `containing module is not imported`。因此「媒体包住在主模块内」与「模块级可选」**互斥**：想要可选，媒体只能整个挪出主模块。**要把两层分开**——**包级可选**这一层，即 `moon.pkg` 的 import 决定编译/链接边界，一直在，不 import `yue/media` 就不会链 `-lav*`；丢的是**依赖闭包/构建期**那一层，两者不是同一件事。
- **一处实测纠偏**：本仓是 moon workspace，`moon.work` 成员含 `modules/ffmpeg-mbt`，所以**仓内构建任何包都会跑 ffmpeg-mbt 的 prebuild**——实测 `moon build ./gui/core`、`moon build ./modules/yoga-mbt/src` 都打印 `ffmpeg(prebuild):` 那行，而这两者与媒体毫无关系。这条**不是**根 `moon.mod` 造成的，workspace 成员身份单独就能触发——`moon.work` 改不改都跑；`.mooncakes` 里没有 `NoahLiu/`，说明 `NoahLiu/*` 全从 workspace 本地成员解析。**本批收益因此限定在「外部消费者」**：消费者不在这个 workspace 里，只按 `moon.mod` 解析依赖，摘掉那行后 ffmpeg-mbt 不再进他们的闭包。仓内/CI 仍会跑，CI 本就安装 ffmpeg 开发包，无新增负担。
- **做法**：①`git mv yue/media modules/gui-media/media`——媒体包迁进既有独立模块 `NoahLiu/gui-media`，该模块本就是为可选媒体而拆的；②媒体包要的 miniaudio 系统库链接参数 `-lpthread -ldl -lm -lstdc++ -latomic` 从主仓 `scripts/prebuild.py` 搬到**新模块自己的** `modules/gui-media/prebuild.py`，按包名 `NoahLiu/gui-media/media` 下发，非 Linux 优雅降级为空 link_configs，与 ffmpeg-mbt／主 prebuild 同口径；③`modules/gui-media/moon.mod` 补 `NoahLiu/yoga-mbt@0.1.0`——媒体包经 `@yoga` 取节点——与 prebuild 选项；④根 `moon.mod` 摘掉 `NoahLiu/ffmpeg-mbt@0.1.0`。
- **示例必须跟着走，`b01d1dd` 的教训**：`examples/native-web` 是主模块里**唯一** import `yue/media` 的包。它若留在主模块，主模块就得反向依赖媒体模块 → 重现「主 ↔ 媒体」的发布环——当年正是这个环让两边都发不了版，才把示例拆去 `examples`。故整包迁到 `examples/native-web`，该模块本就是「需要媒体的独立示例模块」；其 `moon.pkg` 的 `NoahLiu/native-gui/yue/media` 改为 `NoahLiu/gui-media/media`——别名仍派生为 `@media`，**源码零改**——`examples/moon.mod` 补 `NoahLiu/yoga-mbt@0.1.0`。**不拆页**：`native-web` 头部写明它「webview 与媒体的累积验证示例，同族不另开页」，拆出去另开页违背该口径。
- **归口政策随之更新**：`TODO.md` 的「验证示例归口」把 webview + 媒体侧的落点从 `examples/native-web` 改为 `examples/native-web`——历史回证行的原文保留，那是当年的记录。
- **回证**：①`moon tree` 根模块闭包**不再列 `NoahLiu/ffmpeg-mbt`**——改前明确列着，改后首行只剩 yoga-mbt / subproc / markdown 三支；②全仓 `moon check` 红点 **287/68 未变**，错误仍全在旧链包，即 `events.mbt`、`splitter.mbt`、`types.mbt`、`props.mbt`、`video_view.mbt` 等，证明搬迁没碰那批；③两个迁出的包强制重查——`touch` 源码后 `moon check`——全绿；④新模块 prebuild 直跑 `echo '{}' | python modules/gui-media/prebuild.py` → `{"link_configs": []}`，即非 Linux 降级；⑤主模块 `grep` 无任何包引用 `yue/media`、主 prebuild 无 `MEDIA_PACKAGE` 残留。**一条 Windows 侧收获，改前就是坏的**：根模块在 Windows 上根本构建不了——`native-web` → `yue/media` 的 C 桩要 `libavformat/avformat.h`、`audio_stub.c` 又用了 `CLOCK_MONOTONIC`，实测 `moon build ./examples/native-web` 直接失败；改后根模块不再含任何「在 Windows 编不过的包」。
- **本批未做且不假装完成**：miniaudio 单头文件**仍是两份拷贝**——`modules/gui-media/src/miniaudio.h` 与 `modules/gui-media/media/miniaudio.h`，同 md5 `8d5bf2a0b46efa835bde4d0eac5a0cd8`——归一仍卡在旧链 `modules/gui-media/src` 下线，前置是 `systemprobe` 媒体页迁移；媒体包在 Windows/macOS 仍不可用，POSIX 时钟 + ffmpeg 后端未接；媒体在 Linux 的真机行为——是否真出声、seek 手感——本机无法回证，归人工清单。
- **本批未做且不假装完成**：macOS 要走 `CGEventSourceSecondsSinceLastEventType` / IOKit HID，留 Unsupported；Wayland 原生会话的 idle 要走 `org.gnome.Mutter.IdleMonitor` GNOME 精确档或 `ext-idle-notify-v1` KDE/wlroots 近似档，本批只给「不支持」；「屏幕常亮」的置位侧——`XScreenSaverSuspend` / `SetThreadExecutionState`——本批只做**读**空闲，不拦休眠；空闲阈值变化的通知机制；真机观感归 `测试文档/测试用例.md`。
  - wlroots：多数轻量 Wayland 桌面底层共用的合成器库，Sway 等即用它搭的会话
  - ext-idle-notify-v1：Wayland 的空闲通知协议，用户一段时间不操作时给客户端发事件，只有近似档读数
  - 调研修正，2026-11-03：ScreenSaver portal 只有 Inhibit 无读空闲口，见 proposals/wayland-native.md §2.3

### MoonBit 原生 GUI 栈(G0 输入法探针)

- **环境**:Ubuntu 24.04 + X11(XDG_SESSION_TYPE=x11)+ XFCE,moon 0.1.20260920;系统库 gtk+-3.0 3.24.41 / pangocairo 1.52.1 / cairo 1.18.0 / x11 1.8.7;fcitx5 与 ibus 的守护进程均已安装,`GTK_IM_MODULE=fcitx`。探针在 `experiment/ime_probe`,两形态同二进制:模式 B = `GtkIMContext` 纯通道(文本状态只在 MoonBit 一份)、模式 C = 可见 `GtkEntry` + CSS 主题化。**构建链四条坑**:①**moon 的 `link_configs` 只有链接期字段**——给条目加 `c_flags` 被静默忽略,`native-stub` 编译不带系统头文件搜索路径,`#include <gtk/gtk.h>` 直接 fatal error;修复是与 shim 同构,由 `scripts/prebuild.py` 的 `build_ime_probe_stub()` 用 `pkg-config --cflags` 编成 `build/libime_probe_stub.a`,再仅经 `link_flags` 传入。②该库必须按 ld 命名叫 `libime_probe_stub.a`,`-lime_probe_stub` 才找得到。③**moon 不重链改过的原生库**:改 stub 后 `moon run` 仍跑旧 exe(SIGSEGV 现场一模一样),与「改 shim 后须删 `_build` 下产物强制重链」是同一条坑,此处复现于 `-l` 静态库路径——删 `build/libime_probe_stub.a` 与该包 exe 后再跑。④CI 三平台都跑 `moon build --target native` 的**全包链接**,Linux 专属探针会让 Windows/macOS 断 `ip_*` 符号;修复:加 `ime_probe_stub_portable.c`,在 `#if !defined(__linux__)` 下把所有入口给空实现(`ip_init` 返回 0,MoonBit 侧据此打印"本平台无探针"后退出),该文件走 moon 自己的 native-stub,Linux 上整体为空。**自己的一个坑**:`ip_report_im_module` 在模式 C 对 `pr.im == NULL` 调 `G_OBJECT_TYPE_NAME` → SIGSEGV(退出码 139);模式 C 本就没有自建上下文(输入法挂在 GtkEntry 上)——冒烟只跑模式 B 完全看不出来,再次印证「每条分支真实触发过才算验证」。**已实测到的三条**(供 G5 取舍):①`g_main_context_iteration(NULL, TRUE)` 单步就能驱动 GTK 窗口与信号,**不需要 `gtk_main`**,主循环全在 MoonBit 手里,Esc 与 1500ms 自动退出都干净、无退出期崩溃;②**GtkEntry 的尺寸协商确实顶回去**——给它 22px 的盒子,主题默认把控件撑到 32~33px(`requested_h=22 allocated_h=33`),CSS 加 `min-height: 0px` 后落到 24px(22 + 上下各 1px 边框),即"能压但压不回请求值";③Pango 口径可直接用——14px 字面行高量得 17px,前缀宽度量出 59px,插入点矩形 `83,22 1x17` 已推给输入法通道(候选窗定位的输入口)。**待真机项**:commit / preedit 内联 / 候选窗贴合 / 快捷键穿透 / 中文实际可打性,按 `experiment/ime_probe/README.md` 清单在 fcitx5 与 ibus 两种 `GTK_IM_MODULE` 下执行,结论回填本节。验证:`moon check` 零警告 + 全仓 `moon test` 740/740 + `moon build --target native` 68 任务全过 + 本机两模式冒烟进程存活并干净退出。

### MoonBit 原生 GUI 栈 G2 · GTK3 窗口地基 · 循环泵与上屏的五条实测坑

环境：Ubuntu 24.04 + X11 + XFCE，moon 0.1.20260920 / moonc v0.10.14，GTK3 3.24.x。新增 `win`——GTK3 后端——与 `examples/native-window`。

- **坑 ①，窗口不画、frames=0**：`gtk_widget_show_all` 之后 GDK 的 map 请求还压在输出缓冲里，X 服务端收不到 map，poll 等的是一个永远不会来的事件。**修复**：show 后 `gdk_display_flush(...)` 并跑一轮 `gtk_main_iteration_do(FALSE)`，不要用已弃用的 `gdk_flush`。
- **坑 ②，忙轮询占满 CPU，dt=0**：在 `poll` 之前调 `g_main_context_wakeup` 会把 GLib 内部唤醒管道置为可读，poll 立刻返回，外层退化成空转。**修复**：等待内部绝不调 wakeup，跨线程唤醒只由外部 `wm_wakeup()` 触发，效果正是让本次 poll 提前返回。
- **坑 ③，GLib 加固签名**：本机 `g_main_context_query/check` 比网上示例多一个 `n_fds` 参数——query 第 5 位传缓冲容量；check 第 4 位是 n_fds，不是 n_ready。**做法**：按 `/usr/include/glib-2.0/glib/gmain.h` 核对，不照抄文档示例。
- **坑 ④，相对延时的时基**：`CLOCK_MONOTONIC` 是开机起算的大数，本机实测 21405569ms。`Loop` 的 last_now 若从 0 起算，首次 advance 前排的定时器会**全部立刻到期**——骨架动画只跑一拍、5 秒退出定时器当拍就停循环。**修复**：`Loop::start(now_ms)` 显式建立时基，未 start 时基准取 0，已入单测。
- **坑 ⑤，已知坑复现，moon 不因原生静态库变化重链**：改 `win/gtk_stub.c` 后 `moon build` 报 `no work to do`，跑的还是旧 exe，与「改 shim 后须删产物」同一条。**修复**：删 `build/libyue_win_stub.a` 与该示例的 `_build` 输出再来。
- **另记，口径**：上屏路径把调用方的 RGBA 缓冲拷进后端暂存再换序为 BGRx，**绝不就地改调用方缓冲**——离屏快照与窗口同源，就地换序会让下一次快照通道错位、重复上屏还会来回颠倒。
- **验证**：`moon check gui/{core,win,render}` 零警告；`moon test -p NoahLiu/native-gui/core` 9/9；`examples/native-window` 本机冒烟 52 帧、退出码 0、无退出期崩溃；yoga-mbt 79/79 未掉。

### MoonBit 原生 GUI 栈 G3 首批 · Cairo 光栅器 · 位图格式与两侧口径对齐

- **格式定案，关键**：`render` 的 Bitmap 内部布局改为与 `CAIRO_FORMAT_ARGB32` 一致——小端 = B,G,R,A 且**预乘** alpha。收益：Cairo 可以直接画进我们自己的缓冲，即 `cairo_image_surface_create_for_data`，上屏直拷，全链路单一格式零转换。代价与对策：自写的 `Bitmap::paint` 改在预乘域做 source-over，与 Cairo 同一套算术；`Bitmap::pixel` 负责**反预乘**，所以对外语义——独立 RGBA 分量——与 G1 的断言完全不变。
- **上屏简化**：`wm_present` 去掉 RGBA→BGRx 换序与暂存拷贝，直接用调用方缓冲建 ARGB32 surface 贴上——会话期间由 `#borrow` 持有，缓冲不会动。
- **`stroke_rect` 两侧同口径**：Cairo 的 `stroke` 是**居中**描边，与布局层 border-box 口径不符，故 C 端用「四条内边带填充」复现内侧语义；界面上要与 Cairo 居中描边区分时另开方法，不改本契约。
- **不变量，已入单测**：同一矩形、同一颜色——含 alpha——经「纯 MoonBit 矩形绘制器」与「Cairo」两条路径**逐像素完全相等**，含 `#00000080` 叠白底 = 127,127,127,255 的情形；斜边填充出现中间 alpha，证明确实走了抗锯齿。
- **验证**：`moon test -p NoahLiu/native-gui/render` 14/14——新增 6 条 Cairo 断言：逐像素一致、三角形填充、抗锯齿中间 alpha、clip+translate、内侧描边两侧同语义、半透明混合一致；`moon check gui/{core,win,render}` 零警告；`examples/native-window` 冒烟 52 帧、退出码 0——示例已加 Cairo 画的圆与贝塞尔弧，整条链路过一遍。

### MoonBit 原生 GUI 栈 G3 次批 · Pango 文本层 · FFI 出参与跨包字段可见性

- **坑：SIGSEGV，无测试输出**：把 `Array[Int]` 当 C 的出参数组用——C 侧 `int32_t *out` 写 `out[0..2]`——会段错误，MoonBit 传给 C 的是**数组对象**，按 `out[0]` 写会踩坏它的长度头，之后任何一次使用都崩。仓库既有形态是逐个 `Ref[Int]` 出参，见 `yue/ffi.mbt:452` 的 `ok : Ref[Int]`；改成三个 `Ref[Int]` 后 7/7 通过。**规则**：C 回传多值一律用多个 `Ref[Int]`，不要用 `Array[Int]` 借指针。
- **坑**：跨包构造/读取结构体字段要 `pub(all) struct`，`yue/geometry.mbt:20` 的 `RectF` 即该形态。只写 `pub struct` 时报 `Cannot create values of the read-only type`，同一条也适用于 `pub(all) enum`。
- **坑**：带默认值的参数必须是标签参数，如 `family? : String = ""`；写成 `family : String = ""` 报 `Only labelled arguments can have default value`。
- **口径**：字号按**逻辑像素**取绝对尺寸——`pango_font_description_set_absolute_size(desc, px * PANGO_SCALE)`，不是磅；`baseline` 是首行基线到布局盒顶部，与 yoga-mbt `set_baseline` 的定义一致，接线时不需要换算；ellipsize/wrap 语义照老师 `attributed_text_gtk.cc:82/128-132`。
- **测试取向**：不断言具体像素宽/高——随机器字体配置变，G0 探针记的「14px 行高 17px」是本机值；只断单调性——文本更长更宽、字号更大更高，约束性——`max_width` 下宽受钳、换行后高增长——与「确实落像素」的计数，保证换机不假红。
- **验证**：`moon test -p NoahLiu/native-gui/text` 7/7；`moon check gui/{core,win,render,text}` 零警告；`examples/native-window` 冒烟 52 帧退出码 0，窗口内画中英混排文本；全仓红点仍 290 errors 未增。

### MoonBit 原生 GUI 栈 G3b 补充 · 行高口径定案与「测试可执行文件不重链」

- **口径定案**：`line_height` 取**字体 metrics 的 ascent+descent**，经 `pango_context_get_metrics`；`line_ascent` 取 ascent，即首行基线。不能用样例文本的盒高当行高——那会把「有无下伸部」当成行高差，布局盒高随内容抖。
- **与 G0 探针对账**：探针记的「14px 字面行高量得 17」是**首行基线**，本层 `line_ascent(14) = 17` 与之一致；本层 `line_height(14) = 22`，即 ascent+descent。两个数都对，名字用错了；G5 定文本盒高时按 22 这一路走。
- **坑**：`PangoFontMetrics` 不是 GObject，必须 `pango_font_metrics_unref`；误用 `g_object_unref` 直接 SIGSEGV——且崩在测试驱动里、无任何测试输出，极易误判成 FFI 参数问题。
- **坑，既有坑的新面**：改原生静态库后 `moon test` 的可执行文件**同样不重链**——此前记录只针对 `moon build` 的 exe，本次复现于 `_build/native/debug/test/<pkg>`：修好 SIGSEGV 之后测试仍崩，因为跑的是旧链接产物。排查时先用一个普通 main 目标复现——它是新目标、必然新链接——一致地「main 正常、测试崩」即指向产物过期；修复要连 `_build/native/debug/test/<pkg>` 一起删。
- **验证**：删产物后 `moon test -p NoahLiu/native-gui/text` 7/7；`moon check gui/{core,win,render,text}` 零警告；render 14/14、core 9/9、yoga-mbt 79/79 未掉。

### MoonBit 原生 GUI 栈 G4 次批 · 键/指针事件与焦点接入 · GTK 侧四条口径

- **坑**：`gdk_keyval_to_lower(ev->keyval)` 会把 Shift 后的大写抹成小写——X11 的 keyval **本身已含 shift 语义**，'a' 与 'A' 是不同 keysym；内核的 `keysym_to_text` 因此能直接得到正确字符。事件里保留原 keyval，不做小写化。
- **坑**：修饰位不能直接透传 GDK 的位值——Shift=1、Control=4、Mod1=8、Mod2=64、Meta=16——必须显式重映射到本栈的 `MOD_SHIFT=1 / MOD_CTRL=2 / MOD_ALT=4 / MOD_META=8`，否则 `Ctrl+Left`、`Shift+Tab` 一类组合全判错。
- **收键前提**：`gtk_widget_set_can_focus(area, TRUE)` + `gtk_widget_add_events(area, GDK_KEY_PRESS_MASK | ... | GDK_SCROLL_MASK)`，并在 `show_all` 之后 `gtk_widget_grab_focus`；少任一步窗口存在但一个键事件都不回，与 G2 的「不 flush 就等空事件」同类——现象是「没反应」而不是「报错」。
- **口径**：事件队列是每窗口 64 槽 FIFO，满了**丢弃而不是覆盖**，宁可丢一个事件也不能把顺序打乱；取事件用「`wm_take_event` 返回 code + `wm_ev_*` 逐字段读最后一条」而不是多个出参——MoonBit 不能给 C 传可写数组，见 G3b 那条 SIGSEGV。
- **焦点栈在 MoonBit 侧**：`core/focus.mbt` 只管次序与环绕——Tab 到末尾回第一个、Shift+Tab 到首位回最后一个、注销当前项焦点交给后继；平台侧只有一个动作 `Window::request_focus`。逻辑焦点归 MoonBit，与 libyue 的 `FocusManager` 同构——容器不持有系统焦点。
- **caret 定位口径**：点击定位逐码点量前缀宽，取「不超过点击点的最右边界」；`Editor::boundary_after` 由私有提升为公开，供上层做同一种推进。
- **验证**：逐包 `moon check` 零警告；测试 core 14/14、input 10/10、render 14/14、text 7/7、yoga-mbt 79/79；`examples/native-window` 本机冒烟 49 帧、退出码 0、两个框文本状态完好。**真机项待协作方**：英文/数字可打字、退格与方向键、Tab/Shift+Tab 在两框间环绕、点击定位光标、caret 500ms 闪烁、中文标点与组合键——IME 属 G5。

### MoonBit 原生 GUI 栈 G0 · 真机回证：`im_focus` 是纯通道成立的前提，preedit 缺口定位在探针挂法

环境：Ubuntu 24.04 + X11 + XFCE，`GTK_IM_MODULE=fcitx` 即 fcitx5。执行人：协作方真机。

- **现象**：探针模式 B 下每按一键都直接落成一次 commit、preedit 恒 0，输入法像根本没接管——不是 fcitx5 不工作，而是 `GtkIMMulticontext` 在上下文**未激活**时落回内建的 `GtkIMContextSimple`——只处理 Latin-1，组合串与候选都不走。
- **根因**：只调了 `gtk_im_context_set_client_window` 就够了让上下文可用，但**没调 `gtk_im_context_focus_in`**，它一直处于失活态，`filter_keypress` 因此从不消费按键。
- **修复**：realize 时 `gtk_im_context_focus_in(pr.im)`；顶层窗口 focus-in/out 事件里同步 in/out——失焦必须 `focus_out`，否则输入法侧残留未完成的组合串，即清单第 5 项。补上后**中文 commit 路径真机可用**。
- **闭环，同日追加**：preedit 内联已达成，纯通道**四条件**齐备——①`focus_in`/`focus_out` 随焦点同步；②按键处理挂**焦点控件**层——挂窗口层时事件顺序与消费都不对，这正是与 `GtkEntry` 行为的差别所在；③每拍 `gtk_im_context_set_surrounding`，只喂已提交文本、光标按 UTF-8 字节；④`use_preedit=TRUE`——它的语义是「用 preedit 串做内联反馈」，不是「输入法自绘」，一度读反，代价是两轮假阴性。
- **另一处真机坑，与输入法无关**：组合串**只能在一处拼接**。探针原先 MoonBit 侧把 preedit 拼进显示串、C 侧绘制时又拼一次，同一段文字显示两份；修法是把拼接与下划线统一收到绘制侧——正文不带线、组合串带线，与 `GtkEntry` 同观感——MoonBit 只推已提交文本。
- **一处误判要记**：曾按「前端版本错配」怀疑依赖，被模式 C 对照否证——同环境下 `GtkEntry` 预览正常；真机症状先用参照实现对照，再谈归因。
- **ibus 未装**：清单中 ibus 两轮标「环境未装 ibus daemon，未测」。
- **验证方式**：`moon build experiment/ime_probe` + 两模式冒烟退出码 0，助手侧；真机 fcitx5 由协作方回证：preedit 内联一份带下划线、流水有 `[preedit] changed`、`[commit] 中文` 正常、候选窗贴组合串末尾。

### MoonBit 原生 GUI 栈 G4 · 真机反馈「无法输入/点击与 Tab 不切焦点」的第一处根因：事件码 4 未映射

- **现象**，协作方真机：自绘框打不进字、点击不切焦点、Tab/Shift+Tab 无反应，但窗口动画与重绘正常。
- **根因**：后端 `wm_event` 用返回值 **4** 表示「有输入事件待取」，而 MoonBit 侧 `Window::poll_event` 的映射只写了 1/2/3，4 落进 `_ => NoEvent` 分支——于是主循环认为「没有事件」直接退出排空，`take_input` 永不被调用。渲染走定时器所以照常动，症状正是「只有输入全失灵」，且**没有任何报错**。
- **教训，口径级**：事件码是两端之间的隐式契约，新增一类事件必须同时改 C 端返回值与 MoonBit 端映射，且**默认分支不能吞掉未知码**——今后新增事件类型时，先把未识别码打出来或断言，别让 `_ =>` 静默吸收。
- **仍未闭环**：修完映射后示例的 5 秒自动退出没触发，进程 0% CPU 阻塞在等待里。已排除 `Loop::advance`「只看队首就 break」饿死后序定时器这一猜想——新增无头用例「自重排的短周期节拍不应饿死长周期定时器」通过，core 15/15。下一步用 `xdotool` 向示例窗口注入按键与点击做客观验证——这条路本机已跑通，可替代肉眼来回。
- **验证**：`moon check win` 零警告；逐包测试 core 15/15、input 10/10、render 14/14、text 7/7 全绿。

### MoonBit 原生 GUI 栈 G4 · 「完全打不进字」的两处真因：按键挂错层 与 NumLock 被当成 Meta

现象：G4 接入后自绘框一个字符都进不去，但 Tab 看着"像在动"，其实是焦点切了；窗口动画与重绘正常、全程无报错。用 `xdotool key` 向示例窗口注入按键做客观验证——本机宿主、不依赖肉眼——逐条打印 `code/keysym/mods/focus/len` 后定位到两处：

- **① 按键挂到了顶层窗口而不是焦点控件**：原 `g_signal_connect(w->window, "key-press-event", ...)`。G0 探针 `ec2849d` 已用真机定下挂法——按键处理要挂在**焦点控件**上，挂窗口层会让事件顺序与"消费后能否真正吃掉"都不对，接 IME 后尤其致命。改为挂 `w->area` 即 drawing area，与 GtkEntry 的挂法同构。
- **② `GDK_MOD2_MASK` 被当成 Meta 用，致命且极易误判**：`wm_mods()` 里写了 `state & (GDK_META_MASK | GDK_MOD2_MASK)` 就置 MOD_META。MOD2 在 X11 上是 **NumLock**，正常桌面恒为亮，于是**每个**按键事件都带 mods=8；内核 `handle_key` 见 `alt/meta` 非零即判定为组合键、不插字符，于是所有可打印键被静默丢弃。修法：Meta 只认 `GDK_META_MASK | GDK_SUPER_MASK`，NumLock/CapsLock 这类锁定位不参与本栈修饰位。
- **定位手法，值得复用**：「事件到没到 C」在 C 回调里 `fprintf(stderr, "[c] key ...")`；「到了 MoonBit 之后丢在哪」在派发点打印 `code/keysym/mods/focus/编辑器字节数`。这次就是靠 `mods=8` 一个字段直接锁定第 ② 条的——只看现象会一路往"事件没送到"方向猜。
- **反证的一条**：修完映射后示例一度不自动退出，我先怀疑 `Loop::advance`「只看队首就 break」会饿死后序定时器，写成无头用例后**通过**，core 15/15，猜想去掉；实际卡住是第 ③ 条——draw 之外画 GdkWindow 撞死窗口，见 G2/G4 时序条——与测试等待时长不够叠加造成，不是调度器问题。
- **验证，客观**：注入 `a b c Tab d e f` 后 `NATIVE-WINDOW-OK ... a='helloabc' b='第二个框def'`——前三键进第一框、Tab 切焦点、后三键进第二框；`mods=0`。逐包 `moon check` 零警告，core 15/15、input 10/10、render 14/14、text 7/7、yoga-mbt 79/79，全仓红点仍 290 errors。**仍需肉眼确认**：点击定位光标与 caret 500ms 闪烁的观感——xdotool 能注入点击、但看不到画出来的 caret。

### MoonBit 原生 GUI 栈 G5 首批 · Linux 纯通道输入法接入 · 四条件落到 win 上的四条坑

配方来自 G0 探针的 `ec2849d` 四条件，本批把它实现进新栈自己的窗口层：`win` 建 `GtkIMMulticontext`，`use_preedit=TRUE`；收键先 `filter_keypress`——消费即吃掉、不推给内核；提交文本与组合串以「取一条 + 逐字段读」回 MoonBit、每拍喂 surrounding 与插入符矩形；`input` 增加 `set_preedit`/`preedit_text`——组合串只作显示，**绝不并入文本状态**，文本仍只有一份；示例把组合串画在已提交文本之后并加下划线，候选窗矩形算上组合串宽。

- **坑①：拼音原样进文本、输入法像没工作**：`set_client_window` 在 `show` 之前调，那时 drawing area 还没 realize、`gtk_widget_get_window` 返回 NULL，multicontext 于是没挂上任何输入法模块，`filter_keypress` 恒返回不消费。**必须挂在 `realize` 信号里**，探针同此，并配 `focus-in/out-event` 做 `focus_in`/`focus_out`。
- **坑②：core dump `free(): double free detected in tcache 2`**：`commit` 信号给的 UTF-8 串所有权在 GTK，回调返回后它自己释放，处理器里 `g_free(text)` 即双释放。探针的处理函数也确实不 free。
- **坑③：永远出不来中文**：每拍喂 surrounding 时顺手调 `gtk_im_context_reset` 会**打断组合**——reset 的语义是「当前组合串作废」。喂 surrounding 只调 `gtk_im_context_set_surrounding(im, text, len, caret_bytes)`——四参旧接口，探针同此，不走带 SelectionData 的新接口。
- **坑④**：`preedit-changed` 的信号签名是 `(GtkIMContext*, gpointer)`，串要用 `gtk_im_context_get_preedit_string(ctx, &str, &attrs, &caret)` 取，按 `(ctx, text, data)` 接会拿到错的指针；`caret` 是组合串内的**字节**偏移，与我们 UTF-8 字节光标同口径。
- **工具链补充**：`FixedArray[Byte]` → `String` 的现行路子是 `@utf8.decode_lossy(FixedArray::unsafe_reinterpret_as_bytes(buf))`，本版本没有 `@utf8.decode_utf8` 与 `buf.to_bytes()`；`Double → Int` 用 `x.floor().to_int()`——无 `Int.floor_of_double`，也没有 `+.` 运算符，且**续行运算符必须收在上一行行尾**。
- **验证**，客观，`xdotool` 注入、`GTK_IM_MODULE=fcitx`：输入 `nihao` + 空格 → 退出行 `a='hello你哈哦'`，拼音字母零残留、`seen=6` 只剩未被消费的键，说明过滤与「消费即吃掉」都按预期工作；进程干净退出。逐包 `moon check` 零警告，core 15/15、input 10/10、render 14/14、text 7/7、yoga-mbt 79/79，全仓红点仍 290 errors。
- **待肉眼/待补**：preedit 下划线的观感、候选窗是否贴组合串末尾——本机只能证明矩形已推送；ibus 一套，探针侧结论是 ibus 无内联预览疑为 libpinyin display-style 设置，与本层无关，另记；Windows `ImmAssociateContext` 与 macOS。

### MoonBit 原生 GUI 栈 · 富文本区间属性 `rt_*` 会话 · Pango 属性侧三条实测

- **实现形态**：`AttributedText` 只存数据——文本 + 格式 + 基准字体/颜色 + `Array[TextRange]`；每次测量或绘制把会话建到 C 端的 `rt_*` 槽表，槽上限 `RT_MAX 16`，用完立刻 `rt_free`——不留长驻句柄，也就不存在「MoonBit 对象被回收而 C 侧还握着指针」。文本与字体名在入口处拷进自有内存，MoonBit 交来的 `Bytes` 指针只在调用期内有效。
- **区间口径**：**UTF-8 字节下标** `[start, end)`，与编辑内核同源；libyue 的区间是字符区间，属记档的分岔。越界在建树时钳掉、起点不小于终点的空区间直接跳过、非法 hex 不入表；`set_text` 按旧语义保留区间表。公共面加 `range_count()`，组件层判断「要不要走富文本路径」用。
- **Pango 侧三条实测**：① `pango_layout_insert_attr` 要 Pango 1.52+，本机头文件里没有它的声明——C 侧按**隐式声明返回 int** 编译通过、把指针截断，症状会是莫名其妙的段错误，改用 `PangoAttrList` + `pango_layout_set_attributes`，1.44 起可用；② 前景色与前景 alpha 是**两条属性**——`pango_attr_foreground_alpha_new` 只收一个 `guint16`，不是 RGBA 四参，半透明区间要 `foreground_new` + `foreground_alpha_new` 一起插；③ `pango_attr_font_desc_new` 会自己复制描述，本地那份建完即 `pango_font_description_free`。
- **覆盖顺序**：同类型属性按插入顺序生效，后设覆盖先设；用「整段染红 + 首字符改回黑」的像素包围盒验，而不是靠读 Pango 文档。
- **验证**：`moon test -p NoahLiu/native-gui/text` 20/20——新增 6 条：颜色区间落在正确的字形上且其余保持基准色、多字节文本证明切的是**字节**不是字符、字号区间抬高包围盒、后设覆盖先设、越界/空区间/非法色不落像素也不炸、空文本与 `set_text` 后的区间保留；`moon check text --deny-warn` 零警告；示例标题把开头 `MoonBit` 7 字节换色上屏，冒烟 49 帧、退出码 0；全仓红点仍 287 errors / 68 warnings、yoga-mbt 81/81。

### MoonBit 原生 GUI 栈 · 窗口层光标通道：`wm_set_cursor` + `Widget.cursor` + `cursor_group`

- **全自绘栈里光标是「窗口级的一层」**：没有原生控件就没有「每个控件自带光标」这回事，形状只能设在绘图区的 `GdkWindow` 上。所以链路是：组件在控件上声明**请求**，即 `Widget.cursor`，编号 `@core.CURSOR_*`：0 默认 / 1 手型 / 2 文本 I 形 / 3 横向调整 / 4 纵向调整 → 宿主在 `Move` 时取「悬停路径上**最深的那个非零请求**」→ 与已下发的形状不同才走一次 FFI，即 `Window::set_cursor`。取「最深非零」而不是「最深」，是为了让包住一整组的 `cursor_group` 自然回退：组内子件没提请求时用组的，提了则以子件为准。
- **与 master 的一条机制差**：旧链路的 `cursor_group` 必须把光标**递归设进组根与全部子孙**——GTK 的光标按原生事件窗口生效，只设容器盖不住有独立窗口的子件。本栈只设组自己一处即可，代价是「组内某个子件想保留自己的形状」要靠它自己提请求，提了就赢。
- **C 侧两道守卫**：`gtk_widget_get_window(area)` 在未 realize 时是 NULL，此时设了也没窗口可挂，直接跳过，下一次悬停会再试；`WmWindow.cursor_kind` 记着当前形状，同形状重复请求不再新建 `GdkCursor`——`gdk_cursor_new_from_name` 每次都要分配，悬停抖动会白烧。名字取不到，主题缺字形，时退回 `default`。
- **两条工具链写法**：① `pub(all) enum PointerKind` **不自动带 `Eq`**，`pev.kind == Move` 编译不过，报 `Type PointerKind does not implement trait Eq`，要写 `match pev.kind { Move => true _ => false }`；② `pub(all) struct Rect` 的字段同样是公开的，测试里 `w.rect.x` 直接可读，不必另开 getter。
- **验证**：`moon test -p NoahLiu/native-gui/core` **62/62**——新增 1 条 `cursor_at`：组内回退到组、子件自己提了以子件为准、组外与空白无命中都回默认；`moon test -p NoahLiu/native-gui/ui` **104/104**——新增 1 条：按钮/主题化按钮/悬停组手型、`entry`/`textarea` 文本形、`hsplit`/`vsplit` 把手横向/纵向、`cursor_group` 可覆盖形状且子件保持默认。逐包 `--deny-warn` 全零警告、全仓红点仍 287 errors / 68 warnings 未增。真窗口回证——`examples/native-app` 每拍采一次宿主已下发形状，状态行补 `cur=手/文本/横向/纵向`：注入「依次停在实心按钮 → 多行框 → 分隔把手 → 空白处」得 `cur=8/8/8/0`，前三档各被采到 8 拍，纵向那档示例里没有 `vsplit` 故为 0，退出码 0。**光标的实际形状观感——手型是不是常见的指针、文本形是否为 I 形——由用户在真机复验**：注入只能证明宿主确实按区域下发了不同编号。
- **禁用态的光标请求必须「命中时现算」，建树时定死必错，真机反馈禁用按钮悬停仍是手型**：`Widget.cursor` 是建树时写入的**一次性 `Int`**，而禁用态在本栈是**单元**，即 `Enabled`、`state.mbt` 的既定口径——禁用态若用布尔在建树时固化，后续每次 `set_disabled` 都改不动已定死的字段；`button()`/`icon_button_t()` 无条件写 `CURSOR_HAND`，于是禁用与可用在光标面上完全没有区分度。修法不是给每个组件补一个「重新算光标」的入口，而是把请求本身变成可现算的：`Widget` 新增 `cursor_fn : Option[(Widget) -> Int]`，**存在时压过静态 `cursor`**；`cursor_at` 改走新增的公开方法 `Widget::cursor_request()` 逐节点求值——返回 0 仍表示「本控件不请求」，查询继续往祖先走，`cursor_group` 的组请求语义不受影响。`ui/state.mbt` 加私有助手 `enabled_cursor(cell, on)`：禁用时回 `CURSOR_DEFAULT`、可用时给 `on`。改动点：`ui/basic.mbt` 的 `button`/`icon_button_t`、`ui/form.mbt` 的 `checkbox`/`switch_t`/`slider`/`button_t`，步进器两侧走 `button()` 已自动覆盖。
- **教训：改字段语义要全仓搜该字段的「断言」，不只搜实现侧调用点**——`ui/declarative_wbtest.mbt:151` 是直接读按钮**静态** `cursor` 的断言，改造后当场红，`0 != 1`，是用户跑 `moon test core ui` 抓出来的；它只查实现侧 grep 是搜不到的——断言写的是 `.cursor`，与组件构造点无关。同类改造的检查清单：实现写入点 → 读该字段的断言 → 该字段的公开访问器，此处补 `cursor_request()` 正是为了给断言一个语义正确的入口。
- **验证**：`moon test core ui` **243/243**——新增 core 1 条「带 `cursor_fn` 时以现算结果为准，压过静态 `cursor`；同一棵树改状态下一次查询立刻生效」、ui 1 条「按钮光标跟着禁用单元走：禁用不请求手型、改回可用立刻恢复」；修正 `declarative_wbtest` 既有断言 1 条。真机复验：禁用按钮悬停为普通箭头、恢复可用立刻变手型。

### MoonBit 原生 GUI 栈 · sys 批 2 · `sys/dialog.mbt` 文件对话框

- **GTK 端归 win 桩、语义层归 sys 包**：`GtkFileChooserDialog` 的封装写进 `win/gtk_stub.c`，前缀 `wm_file_*`，槽表与窗口桩同制——对话框要挂 GTK 父窗口、且该文件已由 prebuild 编进 GTK 链接单元；`sys/dialog.mbt` 只做语义薄封装——filters 字符串透传、选项位、run/取结果/销毁。sys 包 **不 import win**——`run_for_window` 的 parent 是纯句柄 id 即 Int64，MoonBit 层无符号依赖，但链接需要 `-lyue_win_stub`，由 `scripts/prebuild.py` 给 sys 包**单独下发** link_configs，GTK 库清单同 win 一套。
- **未 run 的 chooser 查结果会段错误，本机实测**：`gtk_file_chooser_get_uri` 在内部文件系统模型未初始化时直接 SIGSEGV——桩加 `wm_dlg_accepted` 标记，只在 `gtk_dialog_run` 返回 ACCEPT 后放行查询，其余一律空串。同因 GTK 断言：`set_current_name` 即 set_filename 只对 SAVE 动作合法，OPEN 对话框上调用打 Gtk-CRITICAL。
- **无显示环境的退化路径**：`wm_file_dialog_new` 先 `gtk_init_check`，失败返回 0 句柄——wbtest 无 X 连接、CI 场景——全接口对 0 句柄 no-op 不崩；有显示的环境，本机即有，则真建对象，测试走双路径断言。
- **「改桩不重链」的第三处案发现场**：改 gtk_stub.c 后 `moon test` 报 undefined reference——`build/libyue_win_stub.a` 的 mtime 比源码新，同批测试产物也没重链；判据是比对 `build/*.a` 与测试 exe 的 mtime，双删 `_build/native/debug/test/.../gui/sys` 与桩库强制重编。与 G 批次的桩教训同源，moon 的增量对「C 源码改动」不可靠是常态了。
- **`get_uri` 回的是百分号编码串，中文目录必翻车，2026-10-16 用户真机反馈**：`wm_file_dialog_get_result` 原先取 `gtk_file_chooser_get_uri` 再手工剥 `file://` 前缀，选「下载」目录回给 `/home/lkyh/%E4%B8%8B%E8%BD%BD`，示例拿它去 `fsx_list_dir` 直接 `FsError::OpenFailed`——含空格 / `#` / `%` 的路径同理，且保存对话框回填初始目录也会踩。改取 `gtk_file_chooser_get_filename`——GTK 已解好码的本地 UTF-8 路径；回收站/远端 URI 拿不到本地文件名时返回空串，与 Windows 侧 `SIGDN_FILESYSPATH` 同口径。上一条的 `wm_dlg_accepted` 守卫保留，未 run 就查结果仍会段错误。**验证**：`moon test ./sys` **187/187**，并按「改桩不重链」那条核过 mtime——`gui/build/libyue_win_stub.a` 新于 `gui/win/stub.c`、sys 测试 exe 又新于该 `.a`；真机复验=选中文目录与含空格目录 → 播放列表出条目。
- **验证**：`moon test -p NoahLiu/native-gui/sys` **30/30**——新增 1：对话框建/配/释放双路径，有显示真建对象配置后销毁、无显示全接口 no-op；模态 run 与真选文件留真机复验；`moon check sys --deny-warn` 零警告、全仓红点仍 287/68。**真机复验清单**：应用内触发打开对话框 → 选文件 → 结果路径正确；保存对话框初始名生效；filters 下拉分组正确。

### MoonBit 原生 GUI 栈 · 浮层的原生档 · 批 E 余项 `core/overlay_native.mbt`

- **档位只看一件事**：所在窗有没有已挂载的原生子件，即 `Window::has_child_surfaces()`，读 C 侧槽表 `wm_window_surface_count`。有网页区就整层改走真窗口，没有就继续走图层——判据放在 C 侧的槽表而不是 MoonBit 记账，省掉一套会漏销的计数器。六件浮层——tooltip/下拉/右键菜单/对话框/轻提示/悬浮卡——都经 `overlay_show_at`/`overlay_show_full`，所以档位切换在一处生效。
- **原生表不放进 `OverlayHost`**：宿主归 `App`，宿主再持 `App` 就是引用环；弹层表放进程级 `Map[句柄, App]`，`overlay_hide`/`overlay_clear`/退出清理都走它。
- **「先开框、量完内容再收框」踩到两条 GTK 事实**：① 绘制区的 `gtk_widget_set_size_request` 是窗口的**最小内容尺寸**，建窗时按初始大小设的，不改它直接 `gtk_window_resize` 就缩不回初始以下——浮层量完内容会留一圈死边；② `set_resizable(FALSE)` 会让程序化 `gtk_window_resize` 被整个忽略——无边框窗用户本来就拖不动，所以设 TRUE 没有副作用。两条都在 `wm_window_set_size` 里一起处理。
- **「失焦即收起」在映射期会误触发，默认关，对照实验**：开着时弹层约两秒自关，而内容里的「收起」从没被点过，`hides=0` 证明不是我们主动收的；把开关关掉后同一序列弹层常驻。根因是 transient + keep-above 的窗口在映射期会连着来 focus-out。在没有「拿到过焦点才算」的判据之前，宁可让浮层常驻由内容自己收——「开一下就自己消失」比「点外不收起」更坏。开关 `overlay_set_dismiss_on_blur(on)` 留着，判据补上就能开。
- **新增事件构造体会打到「冻结」的基准页**：`@win.Event` 加 `LostFocus` 之后全仓红点从 287 变 288——`examples/native-window` 是 G2–G5 基准、不再加特性，对事件做穷尽 match。判据是先看红点数变化再找是谁变多，加一条空分支即回到基线；**「冻结」不等于可以不跟着改口径**。
- **验证**：`moon test -p NoahLiu/native-gui/core` **81/81**——新增 3 条：无子件时走图层档且 `overlay_show_at`/`hide`/`count` 照常、量尺只算可见子项的右/下边界、没有原生档浮层时失焦与收框两条路径都是空操作；`moon check core`/`win`/四个示例 `--deny-warn` 零警告；ui 110/110、web 11/11、media 18/18 未掉；全仓红点回到 287 errors / 68 warnings。真窗口回证——在**带网页区的桥接窗**里点「浮层盖网页」：`NATIVE-WEB-OVL opens=1 tier=1 native=1 layer=0`，截图见自绘内容，标题 + 「收起」按钮，压在 WebKit 渲染的正文之上——这条正是图层档做不到的。
- **本批未做，不假装完成**：点外收起的可用判据，即上一条的开关默认关；Esc 收起、弹层锚点跟随 owner 滚动/移动、六件组件各自的尺寸提示——现在靠三帧收框。

### MoonBit 原生 GUI 栈 · 原生弹层窗口 · 批 E `win/popup.mbt` + `core/popup.mbt`

- **为什么非要是真窗口**：自绘像素永远画在原生子件即 webview 区**之下**——z 序在原生侧，Painter 无法把它盖住。所以「下拉/右键菜单/tooltip/toast/对话框要能压住网页」这一条只有一条路：走窗口系统，即方案 §4.5 的浮层纪律。本批给的就是这条通道，而不是又一层自绘图层。
- **GTK 侧五条配置必须一次配齐，且必须在 `show` 之前**：`set_decorated(FALSE)` + `set_type_hint(GDK_WINDOW_TYPE_HINT_POPUP_MENU)` + `set_transient_for(owner)` + `set_skip_taskbar_hint/skip_pager_hint(TRUE)` + `set_keep_above(TRUE)`，外加 `set_resizable(FALSE)`。类型提示与 transient 关系在**映射时**才生效，show 之后再设就晚了。
- **一条实测硬坑：`gtk_window_get_position` 在窗口管理器的 reparent 下恒返回 (0,0)**。它给的是「相对父窗」的坐标，而顶层窗会被 WM 包进装饰框架里，相对框架当然是 0,0。要**屏幕原点**必须问 GdkWindow：`gdk_window_get_origin(gtk_widget_get_window(w), &x, &y)`。判据不是「报错」而是**弹层落点等于请求的局部坐标、与 owner 在哪无关**——多窗形态下所有窗的菜单都会落在同一屏坐标，看起来像「弹层没跟着按钮」。修后实测 `owner_origin=2,34`、请求局部 (420,300) → 落点 (422,334)，与 xwininfo 逐位一致。
- **摆位做成纯函数**：`popup_place(owner_x, owner_y, x, y, w, h, screen_w, screen_h)`——越过屏幕右/下边时翻到锚点另一侧——贴边的菜单向反方向展开——翻完仍为负则钳回 0，屏幕尺寸给 0 表示「只钳不翻」。三条边界都进了断言，含「翻到另一侧仍在屏内就用翻转位而不是钳 0」这条容易写错的。
- **弹层就是附窗，不需要第二套生命周期**：`App::open_popup` 走批 A 的注册表，因此它天然共享循环与泵、`close_window()` 只摘自己不影响宿主、`App::shutdown` 一起拆。示例回证：选完菜单项后 `xdotool search --name '^popup$'` 归 0 而主窗仍在，`NATIVE-WEB-POP opens=1 closed=1 choice='乙' wins=1 owner_origin=2,34 win_size=1100x700`，截图清楚看到无边框弹层压在 WebKit 渲染的网页文字之上。
- **本批只给通道 + 一份自绘弹层示例**：`core/overlay.mbt` 那六件——tooltip/下拉/右键菜单/对话框/轻提示/悬浮卡——目前仍走自绘图层，把它们接成「有 webview 时用原生档」是下一步，判据：所在窗存在已挂载的 pane 时才切原生窗口，否则保持图层——没有网页时没必要多开一扇窗。
- **验证**：`moon test -p NoahLiu/native-gui/core` **71/71**——新增 1 条摆位回归，含七种边界；`moon check win`/`core`/三个示例 `--deny-warn` 零警告；ui 110/110、web 11/11、media 18/18 未掉；全仓红点仍 287 errors / 68 warnings。真窗口回证见上：弹层 240x150 落在 (422,334)、IsViewable、选项即自关、主窗不受影响。**待使用者目视**：弹层的无边框观感与 keep-above 在多显示器/切窗后的表现。

### MoonBit 原生 GUI 栈 · Linux 弹层「灰边与残影」= 旧弹层没关在叠窗 · 2026-10-28 真机反馈

- **现象判读先别信「背景」**：菜单右侧多出的灰柱不是窗口背景也不是 size_request 死边，GTK 建窗全树已无 size_request、先排除了这条旧坑；是**上一扇 320 宽的旧弹层没关掉**，被 208 宽的新窗压住只剩右边一条；「残影」= 逐次点击叠出来的真窗口。判据：灰柱宽度恰等于新旧窗宽差、高度与窗同、关一个就少一条。
- **叠窗的两环成因**：① GTK 下 `gtk_widget_grab_focus` 只管应用内焦点，WM 不给弹层窗输入焦点 → focus-in 永不到来 → 「拿到过焦点才算」的失焦收起永不触发；修法：弹层窗 show 后补 `gtk_window_present` + `gdk_window_focus(GDK_CURRENT_TIME)` 向 WM 主动要焦点。② ui 层 `overlay_alive` 只查图层栈、不认原生档 → dropdown 以为「没开着」又开一扇；修法：widget 开 `overlay_native_opened(id)` 查询口，`overlay_alive` 两栈都认。两环各自独立成灾，只修一条仍会叠。
- **验证**：`cd gui && moon check --deny-warn` 全绿、`moon test widget ui` 338/338，GTK 段随用户机编译验证；Linux 真机清单：反复开关菜单不再叠窗、点外/再点触发件都能收、灰柱与残影消失。

### MoonBit 原生 GUI 栈 · KDE X11 弹层右侧死边的又一成因：收框放大分支拿慢拍窗读当地板 · 2026-10-29 真机截图

- **现象**：弹层窗左侧 208px 是菜单面板，右侧恒多一条 112px 的 #F5F6F7 竖条——弹层根的 `bg_page` 底——高度却是贴合的。与上一条「灰柱=旧窗没关」不同形：这次窗自身就是 320 宽——初框宽原样留在了屏上。
  - 环境：Ubuntu 24 KDE X11，browser 演示菜单
- **读数推演**：收框前三拍每拍申请 `set_size_pixels(208,430)`；KDE 合成器对新映射窗的 Configure 回包慢，三拍内 `wm_size` 读回的 `cur` 仍是初框 (320,200)；第四拍起进「只放行放大」分支，旧代码算 `max(内容, cur)` = `(320,430)`——**把宽度反向钉回初框 320**，高度照常贴合。此后内容宽 208 永远不再大于 320，该分支不再触发，死边锁死。XFCE/Win32/mac 的 resize 回包赶在三拍内应用，故只有 KDE 踩中；112px 恰为 320−208，与截图逐像素吻合。
- **判据**：「先开框、量完再收」链上的任何「以当前窗读数为地板/上限」的逻辑，在 WM 异步应用几何时都不可信——**读数是上一拍的事实，申请才是本拍的意图**。放大分支的地板改用记账的「最近一次申请尺寸」`g_native_req`——开框记初值、每次申请即更新——慢拍时窄申请不再被陈旧宽读数顶回。
- **修法**：`overlay_fit_pass` 放大分支比较与取 max 都对 `g_native_req` 做；探针 `POPUP-FIT` 行补 `req=` 读数便于真机分辨「申请了没收下」与「没申请」。前三拍内的收窄申请照旧，幂等。
- **验证**：`cd gui && moon check --deny-warn` 全绿、`moon test widget ui` 338/338；KDE 真机清单交用户——`NGUI_POPUP_PROBE=1` 看 `req=` 链：应从 (320,200) 收到 (208,430) 后停；屏上弹层宽应贴合菜单面板、右侧无死边。

### MoonBit 原生 GUI 栈 · Linux 下载「事件报了、保存框没弹」= 放行档没设落点 · 2026-10-29 真机反馈

- **现象**：browser 示例「策略触发·下载(当前页)」放行档下事件区报了下载事件，保存框从未弹出，盘上也没有文件。拦下档与 mac 同形，都是取消；缺的只是放行档后半段。
  - 环境：Ubuntu 24 KDE X11
- **根因**：GTK 段 `wb_on_download` 放行档只调了 `webkit_download_set_allow_overwrite`，**从头到尾没设 destination**——WebKitGTK 的下载没有落点不会写盘，同接口 mac 在 `decideDestination` 回调里 `runModal` 弹 NSSavePanel 定落点，Linux 漏了对应的「弹框定落点」一步。kind=10 在落点决策前就上报，于是「事件有、框没有」。
- **修法**：`wb_on_download` 放行档补 `GtkFileChooserNative` + `gtk_native_dialog_run`——信号处理器内同步定落点，与 mac `runModal` 同形态；标题/按钮传 NULL 跟系统 locale——确定即 `g_filename_to_uri` 后 `webkit_download_set_destination`；拦下档 / 对话框取消一律 `webkit_download_cancel`。建议文件名取 `webkit_uri_response_get_suggested_filename`，即 Content-Disposition / URL 末段，blob 下载以引擎给的实际值为准。
- **判据**：三平台下载放行档的落点都要在引擎回调里**同步**给死——mac `completionHandler(nil)`、WebKitGTK 不设 destination，都是「不给落点即取消」的同一条引擎事实；新接一个引擎先问「落点不给会怎样」。
- **验证**：`cd gui && moon check --deny-warn` 全绿、`moon test widget ui` 338/338；本机无 WebKitGTK，GTK 段随用户机编译验证；真机清单：演示菜单 → 策略触发·下载(当前页) → 保存框弹出且预填建议名 → 选落点后文件落盘、内容为 probe 文本；点取消则无文件、事件区无异常增长。

### MoonBit 原生 GUI 栈 · 点进网页后原生输入框打不进字 · 两处根因：GTK 焦点拿不回来 + 空框不画组合串

- **症状**：使用者真机，点进 webview 页面之后再点回原生输入框，打字毫无反应。
- 用 xdotool 注入复现 + C 侧临时探针定位，查出**两处互相独立的缺陷**：
- **① 我们的绘制区从来没把 GTK 键盘焦点要回来**：窗口显示时 `gtk_widget_grab_focus` 过一次，之后 WebKit 子件在点击时拿走焦点；而 `GtkDrawingArea` 不会因为被点击就把焦点还给自己，GTK 不替它做这件事。探针实证：点回输入框后 `[focus] in` 一条都没有、`[key]` 也一条都没有——键全进了网页，连 Ctrl+Z 都进网页，所以「某些操作看着还有效」是错觉。修法：宿主在指针按下时**无条件** `request_focus()`——原来只在「焦点栈真的换人」时才要，而换人恰恰不会发生，栈里还是那个输入框。
- **② 空输入框显示 placeholder 时组合串根本不画**：`ui/entry.mbt` 的绘制把「画占位符」与「画文本 + 组合串」写成一个 if/else，空框无文本时走占位符分支，**组合串那条分支被整个跳过**。于是拼音在正常走——探针 `[preedit] '爱'` 一直在到——屏幕上什么都不出现，看起来就是「打不进字」。修法：占位符只在「没文本**且**没组合串」时画，组合串独立成一支。这条与网页无关，空框单独也能复现，多行 `textarea` 没这个问题——它的组合串画在占位符循环之外。
- **顺带收紧一条**：键盘焦点被拿走，即 `Event::LostFocus`，时把输入法这一会话交还系统——在途 commit 归当前控件、清组合串显示、`im_reset` 打断引擎侧未完成的组合、复位去重缓存；焦点栈不动，回到本窗时控件焦点照旧。
- **探针方法论，踩了再记**：应用侧 `println` 在 stdout 重定向到文件时是**块缓冲**，进程被 kill 就全丢——我第一次据此误判「应用侧一条日志都没有」，加 `stdbuf -oL` 才看到真数据；C 侧 stderr 无缓冲，所以两边日志看起来不对称时先怀疑缓冲，别急着下结论。
- **验证**：`[focus] in` 在点回后出现、`[key]` 跟进——修复前两者都没有；空框打字截图见组合串「爱」带下划线；完整往返流程——清空 → 点进网页 → 点回 → 打字——截图见组合串「阿宝」。`core` 82/82、`ui` 110/110、`input` 10/10、`web` 15/15 全绿，分包 `--deny-warn` 零警告，全仓红点仍 287 errors / 68 warnings。**待使用者复验**：原报场景，网页里点跳转后回原生框打字，是否恢复正常。

### MoonBit 原生 GUI 栈 · 上屏缓冲的所有权 · 修复多开大窗花屏与自绘区闪烁

- **症状**：使用者真机报——开「桥接窗」或「本地视频窗」这类第二扇窗时花屏、自绘区域闪烁；主窗单开时看不出来。
- **根因**：`wm_present` 把 `w->pending` **直接指向 MoonBit 侧的 `Bitmap` 缓冲**，而真正的贴像素在**下一次** draw 回调里做，GTK 只能在 draw 回调里拿 GdkWindow 的 cairo，绕不开。回调排上之后，那块 Bitmap 在 MoonBit 侧已经没人引用了——`App::paint_frame` 里它是局部量，下一帧就换一个——GC 什么时候收全看压力。收掉之后 expose 再读那个地址就是**已释放内存**，于是花屏；每次 expose 重读一次，看起来就像「一闪一闪」。
- **为什么偏偏是多开大窗**：单窗小画面时那块缓冲往往还没被回收就又被贴一次；多一扇 1000x620 的动画窗，每秒多几十次分配，GC 压力上来了，窗口就落在「已回收但还要被 expose」的窗口期里。覆盖再移开，即强制 expose 旧区域，最容易复现。
- **修复**：后端**自己拥有**帧缓冲——`WmWindow` 加 `backing/backing_cap`，`wm_present` 走 `wm_store_frame`——按需 realloc + 一次 memcpy——`pending` 指向自己的缓冲；`wm_close` 释放，槽位会被下一扇窗复用，只 memset 就是既漏又错。GTK 与 Win32 两条分支同形改，避免两套语义；Windows 侧本机跑不了，只经代码审查，随 W 线真机复验。
- **一条口径**：跨 FFI 边界「留到下一次回调」的缓冲必须由**被回调的一侧**拥有。只写注释，原先就写着「所有权在 MoonBit」，不解决问题——所有权写清楚了，可没人负责让它活到那一刻。同类形态在 `web` 的 JS 回包、`yue/media` 的帧回灌里都检查过一遍：那两处都是 C 侧自己 `malloc`/`g_free`，没有这条隐患。
- **验证**：改后 `moon build ./examples/native-web` 重链，`build/libyue_win_stub.a` 重编，真窗口跑「开本地视频窗 → 截图 → 用主窗盖住再移开逼一次 expose → 再截图」：23 分钟真片连解 `NATIVE-WEB-LOCAL present=1 frames=1369 pos_ms=56397 speed=1.25x err=''`——一扇 1000x620 的动画窗每秒几十次分配，正是原先最容易落进「已回收但仍要 expose」的形态——日志里 X 错误 0 条，两帧截图内容与视频一致、无条纹脏区；**使用者已在真机复验：桥接窗与本地视频窗不再花屏、自绘区不再闪**。全仓红点仍 287 errors / 68 warnings。

### MoonBit 原生 GUI 栈 · 跨 FFI 句柄的活期 · 修复关窗后日志刷满 GTK/WebKit 断言

- **症状**：对照实验定位，不是猜——同一份示例，**只关桥接窗**日志干净，**关主窗**，即网页区挂着的那个，退出时固定 5 行 CRITICAL——`webkit_web_view_get_title/get_uri` 报 `WEBKIT_IS_WEB_VIEW(webView)` 断言失败，紧跟 `gtk_widget_get_parent`/`gtk_widget_destroy` 报 `GTK_IS_WIDGET` 失败。断言不崩进程，所以之前一直没被当回事。
- **根因**：窗口拆除走的是窗口层的 `wm_close`，它把归属本窗的原生子件槽整格清零并销毁那棵 GtkWidget 树，WebKitWebView 是它的孙子，一起没了——但**没人通知能力层**。于是 `Webview` 的 `handle` 仍是旧槽号、`pumping` 仍为真：排期泵与示例的状态轮询继续拿这个句柄调 `wb_get_title/wb_is_loading`，而桩里 `wb_get(id)` 只看「槽位有没有 view」，看不出「那个 view 已经随窗口销毁」，就把悬垂指针交出去。最后 `wb_destroy` 在退出时 `close` 再拿它 `gtk_widget_get_parent`/`destroy` 一次，就是那两行 `GTK_IS_WIDGET`。
- **修复，一处收口，两条分支同形**：把「活期」的判据放到**知道拆除时刻的那一侧**——桩里 `wb_view_alive(v)` = 槽位有 view **且** `wm_surface_container(v->surface_id) != NULL`，容器是 win 的槽表给的，窗口一拆就是 NULL，这是唯一可靠的存活信号。`wb_get` 一律过这道闸，于是**所有**引擎查询与动作在视图死后自动变空操作，不必逐个函数补判据；`wb_destroy` 也走同一条判据——容器没了就只 `g_free` + `memset` 还资源，不再碰那个指针。MoonBit 侧加公开口 `Webview::is_alive()`，泵的那一拍发现视图不在就 `pumping=false`、`handle=0L`、丢掉 `eval_waiters`，停掉排期而不是继续空转。
- **一条口径，与「上屏缓冲的所有权」同族**：跨 FFI 的**句柄**和跨 FFI 的**缓冲**是同一类问题——「什么时候没了」只有拆除的那一侧知道，所以作废判据必须由它给出。MoonBit 侧看 `handle != 0L` 只能说明「建过」，永远说明不了「还在」；把存活判据写进桩里的统一取回函数 `wb_get`，比在 20 个方法前各写一遍可靠得多。同类形态自查，按「是不是又造了一张按 id 查的 C 槽表」筛：`win` 的 `wm_windows[]` 拆窗后整格 memset，逐个数过取槽点——凡碰 `w->window`/`w->area` 的都已判空返回，其余只读 `ev_count`/`commit_len` 这类计数，memset 后是 0，天然安全，没有这条缝；`yue/media` 的 FFI 面传的是不透明指针 `MbtAdev` 而不是槽号，生命周期由 MoonBit 自己 `close`，形态不同、不在此列。
- **验证**：`moon test -p NoahLiu/native-gui/web` **17/17**——新增 1 条：句柄非零但视图不在时 `is_alive()` 给假、`retire_if_dead` 收口后 `handle=0`/`pumping=false`/`eval_waiters` 清空；`web` 与示例 `--deny-warn` 零警告；全仓红点仍 287 errors / 68 warnings。真窗口判据，同一条对照实验重跑：开桥接窗 → 关桥接窗 → 关主窗，日志 **CRITICAL 0 条**——修复前 5 条——进程自退，`alive=0`，退出行读数照常，`last='标题 本地桥接页'`；**使用者已真机复验，2026-10-12，手动逐扇关窗，点标题栏 X，到只剩主窗再关，日志同样零 CRITICAL**。回归两条确认存活判据没把活视图一起挡掉：桥接页照常从协议装载并读出中文标题；主窗协议行 `reg=1 loads=1 files=2 unreg=1 fails=1 fail='WebKitNetworkError/399 yuedemo://local/index.html'`，与修复前逐字段一致。

### MoonBit 原生 GUI 栈 · 内嵌字幕轨 · 批 D2c ffmpeg-mbt 暴露字幕流与一条时长谎报

- **字幕流此前根本不存在**：`modules/ffmpeg-mbt` 只定位视频与音频两条流——`vf_open` 里两次 `av_find_best_stream`——字幕包在解码循环里被当作「不是我要的流」直接 `av_packet_unref` 丢掉。本批补第三条：`VfFmt.sstream` + 一个独立的 `VfSDec`，即 `vf_sub_open`/`vf_sub_next`/`vf_sub_pts_s`/`vf_sub_end_s`/`vf_sub_close`，MoonBit 侧 `subtitle_cues(path)` 一次读完整条轨给 `Array[SubCue]`。
- **必须另开一份容器读**：字幕解码器若与视频/音频共用 `AVFormatContext`，两边都在推进同一个 `av_read_frame` 游标——读完字幕后视频就从中间开始、或直接 EOF。所以 `subtitle_cues` 内部自己 open 一份、读完就关，代价是一次额外的容器打开，字幕是稀疏的、一次读完，比逐帧查便宜，换来的是**播放中途调用也不搅动主时间轴**——这条写成了无头断言：读完字幕后再开一份继续解，帧 pts 照常推进。
- **一条时长谎报，真数据抓到，不是猜**：mov_text 解出来的 `AVSubtitle.end_display_time` **恒为 2000ms**——解码器不填条目时长时的默认值——照它读，第一条字幕会压住第二条、并在应该消失之后还挂着一秒。判据是打印出来的表：`0.2..2.2 / 0.6..2.6` 是错，`0.2..0.6 / 0.6..1.0` 是素材本意。修法取**「包时长」与「end_display_time」里较短的那个**——包时长要在 `av_packet_unref` 之前取，之后会被清零——mp4 的 sample duration 是权威的，实测落回素材本意。
- **ASS 整行前缀在 FFI 层剥**：部分文本字幕解码器，mov_text 即其一，不填 `rect->text`、只给整行 ASS 对话 `ReadOrder,Layer,Style,Name,MarL,MarR,MarV,Effect,文本`——那是解码器输出的**形状**不是内容，所以归一化属于搬运，即 `subtitle_ass_text`。判据保守：至少八个逗号、`ReadOrder` 是非空数字、三个边距字段是数字或空才剥；样式名/人名/特效是自由文本，不能当判据，否则正文里恰好带八个逗号的字幕会被切掉半句——这条有正反用例钉着。排版标记，`{\an8}`、`<c.xxx>`，仍归 `yue/media` 的 `strip_cue_tags`，与外部字幕同一条清洗路——两种来源在渲染侧完全同形。
- **播放器两条来源 + 一个观测口**：`video` 的 `subtitle` 传了就用，明确意图优先，留空才试容器内嵌轨；`on_subtitle(条数, 是否内嵌)` 与既有 `on_tick`/`on_speed` 同构，示例把两个值写进退出行——`NATIVE-WEB-MEDIA ... subs=2 emb=1`、`NATIVE-WEB-LOCAL ... subs=0`——「这条片没字幕轨」与「字幕轨解不开」在回证里分得开——后者会经 `on_error` 报出原因而不是静默给空表。
- **验证**：`moon test -p NoahLiu/ffmpeg-mbt/src` **6/6**——新增 2 条：`subtitle_ass_text` 的剥前缀与三种「不该剥」的反例、真容器 `av_1s_subs.mp4` 整条读出 + 起止秒 + 中文文本 + 不搅动主时间轴 + 「无轨=Ok([])」与「打不开=Err」分开；`moon test -p NoahLiu/native-gui/yue/media` **24/24**——新增 2 条：内嵌轨转 `Cue` 的搬运与清洗口径对齐、端到端按位置命中；`yue/media`/`web`/`core`/`ui`/`ffmpeg-mbt` 与 `examples/native-web` `--deny-warn` 零警告，全仓红点仍 287 errors / 68 warnings。测试素材是仓库内自带的 13KB 三流片——`av_1s.mp4` 流拷贝 + 两条 mov_text，`ffmpeg -map 0:v -map 0:a? -map 1:0 -c copy -c:s mov_text`。**使用者已真机复验，2026-10-12**：内嵌字幕窗两条字幕按 0.2~0.6 / 0.6~1.0 出现与消失、外挂那条窗行为不变、长素材窗 `subs=0` 不报错。
- **本批未做，不假装完成**：ASS 的样式渲染——颜色/定位/多轨选择，目前只按文本叠加；字幕轨列表与切换，多轨容器只取 `av_find_best_stream` 选中的那条；倍速下的听感复验。

### MoonBit 原生 GUI 栈 · 本地内容通道与导航细粒度原因 · 批 C 余项 `web/scheme.mbt`

- **协议按 context 注册，不按视图**：`webkit_web_context_register_uri_scheme` 的回调签名是 `(WebKitURISchemeRequest*, gpointer)`——**没有 view 参数**，所以协议归属天然是 context 级；旧链那种进程级静态注册在多 profile——profile 挂 pane 级——之后语义就不清了。本批的槽表按 `(context, scheme)` 去重：同一 context 下同名协议只向引擎注册一次，再注册只换根目录。
- **「注销」是顶替而不是撤销**：WebKit 没有 unregister-uri-scheme。注销 = 把这条 scheme 的根目录清空，回调从此一律走 `webkit_uri_scheme_request_finish_error`，页面拿到「协议在、内容取不到」。这比留着旧目录安全——切了 profile 还能读到上一个 profile 的文件——也比「假装能撤销注册」诚实——返回值只表示顶替成功。
- **只做根目录下的静态文件，路径穿越在桩侧拦**：请求 path 含 `..` 直接回错误，不做绝对化、不跟符号链接逃逸；MIME 按扩展名查表：html/htm/css/js/mjs/json/svg/png/jpg/jpeg/gif/woff2/txt，其余 `application/octet-stream`。
- **一条口径，2026-10-12 定案**：C 桩**按需且 minimal**——只在 MoonBit 够不着的地方写，即 GTK3 窗口层、Cairo、Pango、WebKitGTK、miniaudio/ffmpeg、dirent/getenv/spawn、socket；C 里只做 ABI 翻译与槽表，判断/解析/降级语义一律留在 MoonBit；加函数前先查「已有的 MoonBit 通道能不能组合出来」。本批就是一次实际取舍：目录创建没有新增 C，`sys_make_dirs` 用既有的子进程通道组合 `pr_run("mkdir", ["-p", path])`，仓库里 `defaultapps_wbtest` 已有同样先例，代价是它只在 `pr_available()` 为真的平台上成立，所以函数文档写明「探测即口径」，而不是让调用方以为处处可用。
- **当天晚些回访并修正——口径管的是能力，不是「`sys` 不许有 C」**：两条路**真等价**时才组合，**不等价就加 C**。目录创建按组合写法落地后，代价一实测就兑现：它实际只在 POSIX 成立，因为 Windows 的 PATH 上没有 `mkdir`，`fsx_wbtest.mbt:109` 从上线那天起在 Windows 上就是红的。现改为薄 FFI `yue_sys_make_dirs`——Windows 逐级 `CreateDirectoryW`、POSIX 逐级 `mkdir(2)`——与本来就是 C 的 `sys_read_text_file` / `sys_remove_file` / `fsx_list_dir` 归为同族——这不是给口径开了新例外，而是把唯一那个不合群的成员抹平，顺带丢掉一个子进程依赖——不再要求 `pr_available()`，也不必每次 fork + 落两个临时文件。
- **`CreateDirectoryW` 对盘符前缀给的不是「已存在」**，本批真机实测：逐级建目录时把 `"C:"` 当一段去建，它返回 **`ERROR_ACCESS_DENIED(5)`** 而不是 `ERROR_ALREADY_EXISTS(183)`——只认 183 会把盘根读成失败、整个调用返回 0。判法是**先探再建**：`GetFileAttributesW` 有效说明这一级已在，直接跳过；创建期竞态再容 183。POSIX 没这坑——`mkdir` 对已存在目录就是 `EEXIST`。
- **写文件不会顺手建父目录，而症状出现在别处**，本批真窗口踩到：页面区只显示一句 `not found`，看着像协议没通，实际是根目录 `/tmp/native-web-scheme` 压根不存在、两份 `sys_write_text_file` 全失败。修法是 `sys_make_dirs`，但**判据要先拆开**：示例的退出行加了 `files=` 计数——注册成功 / 加载发出 / 文件真在不在——少了这一段就得靠猜是哪条链断的。
- **导航细粒度原因两条**：① `WEBKIT_LOAD_REDIRECTED` 出 kind 15——调用方要能区分「换了地址」与「重新加载」；② load-failed 的载荷结构化成 `uri|domain|code|message`，`domain` 用 `g_quark_to_string` 给名字，MoonBit 侧 `nav_error_parse` 拆成 `NavError`；错误文本里可能有 `|`，所以前三段按位置取、剩下的全归 message，段数不足给 `None` 而不是猜字段。
- **一条只有真窗口能抓到的接缝缺陷**：`WebEvent` 里**有** `LoadFailed`，而 `Webview::dispatch` 的 kind 表里**没写 14**，于是每次失败都落成 `Unknown(14, raw)`，调用方永远读不到原因。无头套件当时号称「kind→事件逐条映射」却漏了它——因为被走查的那张表本身就跳过了 14：**两半各自有测试，中间那道映射没有**。现在 2/3/4/14/15 全钉进那条测试，另加一条端到端：dispatch 14 → `LoadFailed` → `nav_error_parse` 拆出四段。
- **`load_html` 装入的页面不进前进/后退历史**，真窗口实测，别当成回退坏了：桥接页是 `load_html` 装的，随后点一个不存在的域名，示例里的 `a.example`——`.example` 是 RFC 2606 保留域，DNS 必然失败——当时读到 `can_back=0 can_fwd=0`、`go_back()` 空操作。**但根因不是「失败导航清了历史」**——把四步分开测就清楚了：
  ```
  after-load_html  url=https://local.test/  can_back=0   ← load_html 不入历史
  after-ok-nav     url=https://example.com/ can_back=1   ← 成功导航入历史
  after-fail-nav   url=https://a.example/1  can_back=1   ← 失败导航不清历史
  after-go_back    url=https://example.com/ can_fwd=1    ← 真的退回去了
  ```
  失败导航照常留下可回退状态；那次之所以是 0，是因为桥接页历史里除了 `load_html` 那一项本来就没别的条目。**跨平台一致**：WebView2 文档对 `NavigateToString` 明写「the back or forward history will not be modified」，与 Linux 实测同形；macOS 的 `loadHTMLString:baseURL:` Apple 未作承诺，随 mac 真机验，已记 TODO。**口径两条**：① 引擎语义决定的空操作必须在 UI 上说实话——示例的按钮现在要么记「后退 → url」要么记「后退：无处可退（can_go_back=0；load_html 不入历史）」——否则看着就是 bug；② 要给本地页一条真历史，就用上一条的自定义协议给它一个真 URL 再 `load_url`，别用 `load_html`。
- **自定义协议的公开面收成「名字先预声明」**，2026-10-12 定，三平台取严：Linux 允许随时按 context 注册新 scheme，但 WebView2 的名单挂在**环境选项**上——建 environment 之前，一进程一次；WKWebView 挂在**建视图之前**的 configuration 上——把「运行时新增名字」当公开语义，就是在写一份在 Windows/mac 上会失效的代码。现在：`webview_predeclare_schemes([...])`，在第一扇 webview 之前，→ `register_protocol(scheme, root)` 只认已声明的名字——根目录随时可换、`unregister_protocol` 照旧顶替成错误 handler；名单在建视图时由 `webview_seal_schemes()` 封版，空名单补缺省名 `app`，零配置可用。Linux 那份动态能力留在桩里不对外。**验证**：`web` 16/16——新增一条：建视图即封版、未声明的名字注册被挡、封版后再声明返回 false 且名单不变——真窗口 `NATIVE-WEB-SCHEME reg=1 loads=1 files=2`，示例先 `webview_predeclare_schemes(["yuedemo"])` 再建视图，协议页照常生效。
- **协议登记也要能吃「挂载前」**，2026-10-12，把桥接窗改成协议页时抓到：pane 的视图是「第一次拿到真实矩形」那一帧才建的，`register_protocol` 原先照 `handle != 0L` 判，于是挂载前一律 false——调用方得自己排期等挂载，而 `load_html` 早就有 `pending_html` 了，同一件事两套规矩。现补 `pending_protos`：挂载前排的 `(scheme, root)` 记下来，`mount_at` 建完视图即应用；`unregister_protocol` 先撤这份待应用的登记——撤到过算 true，本来没登记过仍 false，「未挂载」不等于「随便成功」。**判据**：示例第一次跑落在了 `load_html` 退回分支并打出「协议未就绪」，就是这条接缝。
- **协议通道只回 MIME，文本类不钉 charset 就是乱码**，同批真机截图：`wb_mime_of` 对 `.html` 返回裸 `text/html`，WebKit 没有别的口径可猜编码，按 ISO-8859-1 解，中文页整屏花——`桥接页大标题` 成串乱码。修法两处：桩里文本类扩展名一律带回 `charset=utf-8`，即 html/css/js/json/txt；页面自身也补 `<meta charset="utf-8">`——两道各自都够用，但走协议时**只有 HTTP 头这一道是可靠的**——`<meta>` 要在解码到那一个字节之后才起作用，而首屏字节已经按错码表解过了。**验证**：`web` 16/16、`web` 与 `examples/native-web` `--deny-warn` 零警告；真窗口截图见协议页中文正常，事件区 `后退 → yuedemo://local/bridge.html` 证明协议页**在历史里**且退得回去——对照：同一页用 `load_html` 装入时后退是空操作——退出行 `navs=5 … dom_ok=1 text_bytes=68 … last='标题 本地桥接页'`。
- **协议通道只给 MIME，所以文本类必须自己带上 `charset=utf-8`**，真窗口抓到的乱码：同一份桥接页 HTML 走 `load_html` 中文正常、走 `yuedemo://` 装入就整页成 `æ¡¥æŽ¥é¡µ`。根因是两条通道的编码口径不同——`webkit_web_view_load_html` 的入参本身就是 UTF-8 文本，引擎按 UTF-8 解；协议回灌只递一个 content type，裸 `text/html` 没有编码声明时 WebKit 按 ISO-8859-1 解——页面里的 `<meta charset>` 要等解出标签才看得见，而标签已经先被解坏了。修法在桩侧一次性收口：`wb_mime_of` 对 html/css/js/mjs/json/txt 一律返回 `...; charset=utf-8`，二进制与图片不动。**口径**：走协议发文本时 MIME 是唯一编码口径，别指望页内的 `<meta>`；页内声明照写——存成文件用别的浏览器打开时还要靠它。
- **挂载前排的登记要受理，不然「先注册再加载」这条自然写法只能调用方自己等**：视图在第一次拿到真实矩形那一帧才建，`register_protocol` 原先在未挂载时一律 false，示例里桥接窗就是这条路径——`win.mount` 之后立刻注册 → false → 退回 `load_html`，页面上「后退」于是永远空操作。现在与 `pending_html` 同源：未挂载即记入 `pending_protos`，`mount_at` 建完视图逐条应用，`unregister_protocol` 能把还没应用的登记撤掉——撤到过返回 true，没得撤才 false——「未挂载」不等于「随便成功」。**示例随之改判据**：桥接页改走协议——真 URL 才有真历史——注册失败时不再静默降级，事件区明写「协议未就绪，退回 load_html（此页不入历史）」。
- **验证**：`moon test -p NoahLiu/native-gui/web` **16/16**——新增 4 条无头：`nav_error_parse` 的四段与「message 里带 `|`」与段数不足、`nav_parse_int` 的负号与非数字即停、未挂载时注册受理/注销可撤/双重注销 false、上面那条 kind 14 接缝；`moon test -p NoahLiu/native-gui/sys` **164/164**——新增 1 条 `sys_make_dirs`：逐级建目录→写→读回、幂等、空串拒绝、父目录缺失时写失败；`moon check sys`/`web`/`./examples/native-web` `--deny-warn` 零警告。真窗口回证，`examples/native-web` 的「批 C 余项」一行，两段判据分开跑：① 加载协议页 `NATIVE-WEB-SCHEME reg=1 loads=1 files=2 unreg=0 title='本地协议页'` + `NATIVE-WEB-STAT ... title='本地协议页' url='yuedemo://local/index.html'`，截图两条硬证据——页面标题是协议页的 `<title>`、正文段落带蓝底，`style.css` 也是走 `yuedemo://` 取到的，不是内联；② 注销后重载同一 URL `unreg=1 fails=1 raw=0 fail='WebKitNetworkError/399 yuedemo://local/index.html' title=''`，页面区把 `finish_error` 里给的文本原样画出来，屏幕上就是 `scheme unregistered` 一行，证明「注销=顶替成错误 handler」真的生效、且失败原因是**结构**而不是字符串。顺带一条枚举事实：`WEBKIT_NETWORK_ERROR_FAILED = 399`，不是直觉的 -1。③ 桥接页改走协议后的四条一起回证，注入点击、截图读事件区：`导航开始 yuedemo://local/bridge.html` → 点链接甲 `加载失败 g-resolver-error-quark/0 https://a.example/1` → 点「后退」`后退 → yuedemo://local/bridge.html`——**这次真退得回去**，之前 `load_html` 那条永远空操作——→ 页面区中文标题/正文/链接全部正常、`抓正文 ok=1 title=本地桥接页 链接=0`，DOM 抓取走的是协议页，标题按 UTF-8 读回。**使用者已真机复验，2026-10-12**：协议页中文正常、点保留域链接报出结构化原因、「后退」真回到桥接页。留一条口径给后来人：两扇窗没各给数据目录时共用同一个 context，主窗的「注销该协议」会把桥接窗的根目录一并清空——重新注册即恢复，示例注释里已写明。

### MoonBit 原生 GUI 栈 · JS 桥 / DOM 抓取 / 导航面 · 批 C `web` 的 webkit 桩与契约面

- **异步事件一律「C 排队 + MoonBit 消费式取」，不写 C→MoonBit 蹦床**：WebKit 的导航、标题、JS 回包、页面 `invoke`、权限、下载、进程终止都是引擎侧异步信号，若每个都做闭包蹦床，就要替 12 个回调各自管生命周期与线程归属。本批的形态是 per-view 一条 32 格环形队列——`wb_next_event` 取 kind、`wb_event_num`/`wb_event_text` 读载荷——队列满**丢最旧**——事件是提示不是账本，堵死会把主循环拖住。
- **泵不挂在绘制里**：回包回调可能装载/卸载控件，例如抓到链接后要重画列表；而绘制遍历中途改树是本栈一直避免的形态，`Widget::paint_at` 正在逐层 translate+clip。于是挂载时起一条 `@core.set_timeout(30, ...)` 自续的排期泵，`close` 即停。
- **`load_html` 在未挂载时不能丢**，本批真窗口踩到：pane 的挂载发生在「第一次拿到真实矩形」那一帧，`win.mount(...)` 之后立刻 `load_html` 时句柄还是 0，页面区就只剩 `about:blank`。判据是 `navs=1` 且事件里只有 about:blank、抓取全空。修法与 `load_url` 同构：记下 `pending_html`，`mount_at` 建完视图立刻应用。
- **抓取脚本的括号配平要钉住**：四档各自拼 `}})` 时多写了一个右括号，页面侧回包是 `SyntaxError: Unexpected token '}'`。解析层把它判成 `ok=false` 是对的，不静默，但生成器得钉：改成统一包裹 `dom_wrap(fields)`，四档只写自己的字段，并加一条断言 `{`/`}`、`(`/`)` 数量相等且以 `})` 收尾。
- **2.52 的权限入口只有一个**：`decide-policy` 的枚举里**没有** `WEBKIT_POLICY_DECISION_TYPE_PERMISSION_REQUEST`，只有 NAVIGATION_ACTION / NEW_WINDOW_ACTION / RESPONSE，权限只能连 `"permission-request"` 信号；而且 `webkit_permission_request_allow(request)` **只有一个参数**，不是旧文档里的 `(request, gboolean)`——回调返回 TRUE 表示「我们自己处理了」，所以默认拒绝就是「报事件 + 返回 TRUE」，放行则是「显式 allow 之后仍返回 TRUE」。
- **可选信号先 `g_signal_lookup` 再连**，并把在位情况做成掩码报出去，即 `wb_signal_mask()`：1 下载 / 2 进程终止 / 4 权限 / 8 新窗。缺哪条就少哪条回证，不让「回调没触发」和「没实现」混成一个现象。
- **两个 API 形态与直觉相反**：① `webkit_cookie_manager_get_cookies_finish` 在 webkit2gtk-4.1，这一支链的是 libsoup-3.0，头与库随 `pkg-config --cflags/--libs webkit2gtk-4.1` 一起给，返回的是 **`GList` 而不是 `GSList`**，元素是 `SoupCookie`；② 2.40+ 的 `webkit_web_view_evaluate_javascript_finish` 直接给 **`JSCValue*`**，旧的 `run_javascript_finish` 才给 `WebKitJavascriptResult*`，而 `jsc_value_to_string` 对 JS 字符串返回**不带引号**的内容——所以「结构化载荷」就是 JSON 文本本身，不需要再脱一层引号。
- **profile 挂 pane 级**：`wb_create` 的 `data_dir` 非空时走 `webkit_website_data_manager_new(base-data-directory, base-cache-directory)` + `webkit_web_context_new_with_website_data_manager` + `webkit_web_view_new_with_context`；空则用默认 context + 自带 user content manager。`browser_profile_persistence()` 在 Linux 恒 `Persistent`——macOS 才有「14+ 且要有 bundle id」那道 API 边界——探测口留着，调用方不必为平台写分支。
- **两条示例侧计数坑**：① 四档抓取共用一组计数器时，最后一档即结构档没有正文与链接，直接赋值会把前面几档的回证冲掉——取峰值；② 顶层窗带 WebKit 子 X 窗时，用 `import -window <id>` 截出来是条纹状脏区，必须 `import -window root -crop WxH+X+Y` 截合成后的屏幕。
- **契约名沿用旧链**：`load_url`/`get_url`/`get_title`/`reload`/`stop`/`go_back`/`go_forward`/`can_go_back`/`can_go_forward`/`is_loading`/`load_html`/`set_user_agent`/`execute_javascript`/`execute_javascript_with_result`/`add_user_script`/`add_raw_binding`/`remove_binding`/`has_bindings`/`get_cookies_for_url`，`current_url` 作 `get_url` 别名。`remove_binding`/`remove_all_user_scripts` 恒返回 false 并写明原因：WebKit 没有注销口，别让它看起来像本栈的实现缺陷。新窗，即 `window.open`，默认拦下并回报事件，可选「在当前 pane 里导航过去」——本栈不做一窗多 webview。
- **验证**：`moon test -p NoahLiu/native-gui/web` **11/11**——新增 9 条无头：抓取脚本形态与括号配平、四档 JSON 的结构化解析、解析失败 `ok=false` 且 raw 留着、未挂载时全部调用安全且 `capture_dom`/`add_raw_binding`/带结果的求柄给 false/-1、kind→`WebEvent` 逐条映射、JS 回包按序号配对且只回调一次、invoke 双路，即 `on_invoke` 加旁路 `on_event`、持久化探测与引擎在位一致；`moon check web`/`./examples/native-web` `--deny-warn` 零警告；core 70/70、ui 110/110 未掉；全仓红点仍 287 errors / 68 warnings。真窗口回证，`examples/native-web` 的「开一扇桥接窗」= 第二扇窗装一份 `load_html` 的本地页，不依赖网络：`NATIVE-WEB-JS binding=1 evals=1 dom_ok=4 dom_bad=0 links=3 text_bytes=68 meta=1 headings=2 elements=14 invokes=1 navs=2 perms=1 wins=1 crashes=0 cookie_bytes=2 last='invoke {"msg":"来自页面","n":7}'`；合成截图三条硬证据——页内正文显示「已被原生改过」，原生→网页 `execute_javascript` 真改了 DOM；原生事件区逐条列出「页面回话 {...} / 权限请求（默认拒绝）WebKitGeolocationPermissionRequest / 新窗请求已拦下 https://b.example/2」；且桥接窗数量仍为 1——新窗被拦下而不是开出第二个 webview。**使用者已真机复验，2026-10-12**：网页内滚动与点链接正常；webview 聚焦时本栈输入法让位、点回原生框后恢复可打字。

### MoonBit 原生 GUI 栈 · 角色区 pane 与 webview 通道 · 批 B `win/surface.mbt` + 新包 `web`

- **窗口内容改成「绘制区 + 可定位子件」的 `GtkFixed`**，而不是 `GtkOverlay`：Overlay 要靠 `pass_through` 让事件穿过容器，而带子件的容器在 Overlay 下事件归属不可靠，容器自身透明不等于它的子件也正确；`GtkFixed` 是普通容器，指针落在子件上归子件、落在别处归绘制区，**零额外机制**。代价是要自己跟尺寸：`fixed` 的 `size-allocate` 里给绘制区 `set_size_request`，且必须加「尺寸没变就不设」的闸门——`set_size_request` 会再触发一轮分配，无条件设就自激。
- **子件槽表要记归属窗口**：`WmSurface{container, window_id, kind, x,y,w,h}`，`wm_close(window)` 里把属于该窗的槽一并清掉。否则窗口先拆、能力层即 webkit 桩还拿着悬垂的 `GtkWidget*` 去 `gtk_fixed_put` 就是段错误。槽位同样复用，扫 `container == NULL`，与批 A 的窗口槽一个判据。
- **C 之间传指针、MoonBit 只搬整数**：`wm_surface_container(int64) -> GtkWidget*` 由 win 导出，`web/webkit_stub.c` 里 `extern` 声明后使用，同一个可执行文件内链接。这样 `web` 的 MoonBit 层不引 `win` 的 MoonBit 层，包依赖保持「webview 只依赖窗口/布局/事件层」。
- **缺 webkit 开发包不是错误，是降级**：`scripts/prebuild.py` 探 `webkit2gtk-4.1`，探到就带 `-DWB_HAVE_WEBKIT` 编真实现并把 `-lwebkit2gtk-4.1` 下发给 `web`；探不到就编**无宏**那份占位分支，`wb_available()` 返回 0。两条都要保证 `wb_*` 符号存在——否则是链接期断，不是运行期降级。桩文件的分支形态照 win：`#if defined(WB_HAVE_WEBKIT)` / `#elif !defined(__linux__)` / 其余为空翻译单元，避免与 prebuild 的 `.a` 双定义。链接顺序 `-lyue_web` 在 `-lyue_win_stub` 之前，前者引用后者的符号。
- **亚像素必须四舍五入，不能截断**：pane 矩形来自 yoga 的 Double，每帧同步给子件。若按截断，0.4px 的漂移会让「矩形变了」恒真，于是每帧多走一遍 FFI + 一次原生重排。规则钉在纯函数 `webview_rect_key`——`round()`，负坐标同口径——里，去重按取整后的键比。
- **`ChildKind` 是登记制**：目前只有 `Webview = 1`。子表面只保留「原生控件嵌入」这一条语义，见方案 §4.5，不开放自定义值——否则又变成「通用子表面」那句空话。
- **验证**：新包 `web` 无头 2/2——取整与去重键、探测与构造一致且未挂载时零句柄、没挂过就 `close` 安全；`moon check win`/`web`/`./examples/native-web` `--deny-warn` 零警告；core 70/70、ui 110/110 未掉；全仓红点仍 287 errors / 68 warnings。真窗口回证——`examples/native-web`，本机 X11/XFCE + WebKitGTK 2.52.6：分栏形态 `NATIVE-WEB-STAT supported=1 loading=0 title='Example Domain' url='https://example.com/'` + `NATIVE-WEB-GEO pane=262,71,848x605 sidebar=12,71,240x605`，两区不重叠；xdotool 注入「整页/分栏切换 + 载入 + 在页面区点一下」得 `loads=1 toggles=1 mode=full pane=12,71,1098x605`，截图复核页面真的由 WebKit 渲染且切整页后按新宽度重排——**同一条 pane 机制出两种形态**。**待使用者肉眼复验**：网页内滚动与点链接、webview 聚焦时我们侧纯通道 IME 是否让位，离开后恢复。

### MoonBit 原生 GUI 栈 · 单实例与 logind 亮度接线 · `dbus` instance 收口 + `bridge.mbt`

- **单实例走「总线名字声称 + Wake 入站调用」**：首实例 `RequestName(app_id, DO_NOT_QUEUE)` 拿 `PrimaryOwner`——重复声称得 `AlreadyOwner`，幂等；第二实例 `RequestName` 拿到 `AlreadyExists`/`InQueue` 时改调首实例 `org.moonbitlibyue.Instance.Wake('as' 命令行)` 然后自己退出；首实例收到 Wake 先应答再触发回调，`is_wake_call` 在 `bus.mbt` 的入站分支里优先判——第二实例的 `call_sync` 有时限，回调里做恢复窗口这种耗时活不能让对端干等。示例回证：首实例跑着时再启一次，第二实例打印「已有实例，已唤起并退出」并 `exit=0`，首实例打印「收到第二实例的唤起」。
- **亮度写路径的接线方向是单向的**：`dbus` 依赖 `sys`，即环境变量、子进程、sysfs 读，反过来不行；所以 `bridge.mbt` 在调用方启动时把 logind 能力**注进** sys 的两个槽——`brightness_set_logind_probe` 给探针、`brightness_set_action` 给 `(subsystem, name, value) -> 错误串` 的动作——sys 自己不引 D-Bus。本机实测注入后 `@sys.brightness_supported()` 由假变真，`logind_available=true`，而 `brightness_devices()` 仍只读 sysfs，本机无背光设备给 0 个——读写两条路的依赖被这条注入线彻底分开。
- **验证**：`moon test -p NoahLiu/native-gui/dbus` **64/64**——新增 2：注入后 sys 的亮度门与 logind 在线与否一致、同进程重复声称名字得 `AlreadyOwner`；`moon check ./examples/native-sys --deny-warn` 零警告；真窗口回证见上——`pool=:1.483`、第二实例 `exit=0`。**待使用者真机复验**：`brightness_set_percent` 真要改屏幕亮度需带背光的机器，本机是台式机，无 `/sys/class/backlight` 设备。

### MoonBit 原生 GUI 栈 · SNI 托盘与 DBusMenu · `dbus` sni + icon + instance + filemanager

- **平移面**：旧链 `traybus` 的 `sni.mbt`(731 行，StatusNotifierItem 对象面 + DBusMenu 服务端)、`icon.mbt`(75 行，程序生成的默认图标位图)、`instance.mbt`(221 行，单实例名字声称/唤醒)、`filemanager.mbt`(98 行，FileManager1 `ShowItems`) 逐行平移进 `dbus`；**之前从 `bus.mbt` 剥掉的托盘挂钩在同批接回**：`Conn.items`/`menus` 两张注册表、`NameOwnerChanged(arg0=watcher)` 重启后逐项重注册、断线迁移时把托盘项一起带回、入站调用三路分派——单实例 `Wake` 先应答后触发 → 路径命中 `items`/`menus` 走 SNI 的 `handle_call` → 最后才是 `CallReq` 兜底。这正是「基建包先剥语义、能力包回来再接」的收口方式。
- **测试同批平移并把 `inspect` 换成 `assert`**：`sni_wbtest`(212)/`instance_wbtest`(93)/`filemanager_wbtest`(24)，本轮实测这三份里 40 余处旧 `inspect(x, content=…)`。
- **真总线回证，协议侧**：本机 XFCE 面板 `xfce4-panel` 就是 StatusNotifierWatcher。示例里点「托盘图标」后，watcher 的 `RegisteredStatusNotifierItems` 从 **9 条变成 10 条**——多出来的就是本进程的项——退出前对称注销；`sni_wbtest` 的真总线用例创建多托盘项、验路径与菜单对象互不覆盖、注销后两张表都干净。
- **一条注入/测试环境的坑，判据先行**：连跑多轮「创建-注销托盘项」的测试时，偶发 `托盘注册失败: org.freedesktop.DBus.Error.NoReply` 或 `NameHasOwner` 拿到非 true。根因不是代码：**测试进程没有主循环，面板对托盘项的同步属性查询只能在 `call_sync` 的泵里被顺带服务**，积压多轮后 xfce4-panel 的一次查询会卡住，后续注册就超时。判据是「重跑即好、且 `dbus-send` 查 `RegisteredStatusNotifierItems` 仍然在线」；修法是让测试进程别长时间不泵——示例里宿主每 200 ms `dbus_pump()` 就不存在这个问题。当时顺手加过一段 debug 打印定位，确认分支后就撤了。
- **验证**：`moon test -p NoahLiu/native-gui/dbus` **62/62**——新增 12：sni 6 / 单实例 4 / 文件管理器 2，三连跑零 skip；`moon check ./examples/native-sys --deny-warn` 零警告、`moon build` 通过；真窗口回证 `pool=:1.479`、五键几何行 `tray=747,391,110x32`、退出码 0。**待使用者肉眼复验**：点示例里的「托盘图标」后 XFCE 通知区是否出现图标、右键是否弹出「刷新探测 / 退出」菜单、点图标后窗口里的「托盘点击」计数是否 +1。

### MoonBit 原生 GUI 栈 · D-Bus 能力模块首批 · `dbus` UPower/logind/网络/屏保/inhibit/MPRIS + 通知

- **平移面**：旧链 `traybus` 的 `upower`(197 行)/`logind`(105)/`netmon`(191)/`screensaver`(94)/`inhibit`(146) 五件，与 `yue/system/media.mbt`(707 行，MPRIS) 逐行平移进 `dbus`，只换包前缀，media 里的 `pr_run`/`pr_available` 改指 `@sys`。**测试同批平移，并且把旧 wbtest 的 `inspect(x, content=…)` 全换成 `assert_eq/assert_true`**——那批 inspect 在 native 后端本来不断言，此前记过两次，平移过来若不换就是「全绿但零覆盖」；本轮实测这一批里就有 54 处。
- **MPRIS 轮询监视改「排期通道注入」**：master 的 `media_watch_status` 直接挂 `@yue.set_timer`，回调返回 Bool 决定是否续拍；新栈给它加 `schedule : (Int, () -> Unit) -> Unit` 参数——GUI 层给 `@core.set_timeout`，无头测试给把回调收进表里的假通道——内部 `arm()` 自续——与 `clipboard_watch`、主题探针同一个分层理由：能力包不认识事件循环。
- **通知是新做**，master 的通知实现在 C++ libyue 里，MoonBit 侧只有一层包装，属「新栈须重写」项：`notify_caps` 走 `GetCapabilities`——**无副作用**，能力清单不翻译成枚举、raw 原样留给调用方；`notify_send`/`notify_close` 走 `Notify`/`CloseNotification`。**进度不是独立方法**——按 freedesktop 规范用 `Notify` + `replaces_id` 重发同一张通知，并在标准 hint `value` 里带百分比——INT32、0..100，本层把 >100 钳到 100、负数视为不带进度——桌面端据此画进度条；`notify_progress` 就是这个形状，参数顺序与 hint 形态由纯函数 `nf_notify_args` 钉住。
- **设置类纪律**：发通知会真的在桌面弹气泡，测试只跑到能力探测、参数构造与错误归一——未知方法、服务不在线——真发送留给示例里的按钮由使用者点，与 open_url/reveal 同一条纪律。
- **示例接线与真窗口回证**：`examples/native-sys` 加「窗口 / 剪贴板 / D-Bus」面板——会话唯一名 / 通知能力条数 / 系统总线「未连接（首次调用时按需连接）」——+「发通知(带进度)」按钮 + 宿主泵：`dbus_set_post_delayed` 包 `app.timer`、每 200 ms `dbus_pump()`。整轮跑完 `pool=:1.434`，连接全程存活、证明注入的泵真的在喂总线，通知能力 7 条、退出码 0，截图复核五行读数。
- **验证**：`moon test -p NoahLiu/native-gui/dbus` **50/50**——新增 27：UPower 4 / logind 2 / 网络 3 / 屏保 2 / MPRIS 12 / 通知 4，`moon check ./examples/native-sys --deny-warn` 零警告。**待使用者真机复验**：点「发通知(带进度)」是否弹气泡且进度随点击递增——本机 xfce4-notifyd 能力清单 7 条已真读到；UPower/logind/网络/屏保这四件的「事件真的来了才触发」需在插拔电源、锁屏、断网等真动作下观察。

### MoonBit 原生 GUI 栈 · D-Bus 通用基建 · 新包 `dbus` wire + dbus + bus + socket 桩

- **平移面**：旧链 `yue/traybus/` 的 `wire.mbt`，833 行线协议编解码，与 `dbus.mbt`，419 行 `GDBusValue` 通用调用层，**逐行平移**，只把 `sys_f64_to_bits/from_bits` 换成新包的 FFI 名；`bus.mbt`，784 行，按新栈改：连接/握手/收发/分发/断线自愈全保留，**剥掉嵌在通用层里的 SNI 与单实例语义**，即 `items`/`menus` 字段、watcher 特判、入站 `Wake` 分支——那些随各自能力模块回来。
- **最大的分层差：不挂 glib fd 监视**。旧链靠 `g_unix_fd_add` 把总线 fd 挂进 GTK 主循环、靠 libyue 的 `PostDelayedTask` 做重连退避；新栈禁 glib 也不依赖 GUI 层，改成两个注入点：宿主周期调 `dbus_pump()`——缺省 `timeout_ms=0`，poll 看一眼就走，适合挂每帧/每拍——断线自愈的延迟重连走 `dbus_set_post_delayed(fn(ms, f){...})`。**两者都不注入时同步调用照样可用**——`call_sync` 与 `gdbus_call_*` 自带 `pump_until` 泵，握手、Hello、注册都走它，纯 CLI 场景因此不需要事件循环；代价是「没人泵就收不到异步信号」，这条写进了包注释。
- **socket 桩只用标准头**，`dbus_stub.c`，走 native-stub 不写链接参数：`socket(AF_UNIX, SOCK_STREAM|SOCK_NONBLOCK|SOCK_CLOEXEC)` + `connect`，容 `EINPROGRESS`，/ `read` / `write` / 单 fd `poll` / `close` / `getuid` / Double 位模式，`memcpy` 重解释、`static_assert` 钉住 8 字节。错误码约定与旧 shim **逐位一致**——read：>0 字节 / 0 对端关 / -1 EAGAIN·EINTR / -2 其它；write：>=0 已写 / -1 暂不可写 / -2 其它；poll：revents 位 1=IN 4=OUT 8=ERR 16=HUP——这样上层分流代码一行不用改。
- **SASL EXTERNAL 不需要客户端显式传凭据**：连接时内核自动带上 `SCM_CREDENTIALS`、服务端读 `SO_PEERCRED`，客户端只发 `AUTH EXTERNAL <hex(uid)>` 即可——旧链 shim 里也没有 `sendmsg`，这一点是查证过的而不是猜的。
- **对外面比旧链干净一处**：旧链的入站方法调用要求处理者拿到同包的 priv `Conn`/`Msg` 才能应答；新包给出 `CallReq{bus, sender, path, iface, action, args, reply, reply_error}`，`reply` 的签名**由参数值推导**，即 `gdbus_args_wire`，信号订阅回调也只拿到已解码的 `GDBusValue` 数组——线协议值类型不外泄，能力模块与外部调用方看到的是同一份。
- **三条工具链写法，本批实测**：① 结构体字面量的字段用 `字段: 值`，写成 `=` 直接报 `Unexpected '=' in struct expression`；② **函数类型的结构体字段不是方法**——`req.reply_error(...)` 报 `Type CallReq has no method reply_error`，要先 `let f = req.reply_error` 再调；③ `;` 不是注释，`;;` 也不是，拿它当行内注释会连锁解析失败。
- **真总线回证，总线侧**：`moon test -p NoahLiu/native-gui/dbus` **23/23**——会话总线握手成功，本端唯一名 `:1.392`；`ListNames` 真返回并含 `org.freedesktop.DBus`、不存在方法的错误名/错误文本真拿到、信号 `AddMatch` 真登记、`dbus_pump` 空转不阻塞不判死、系统总线 `ListNames` 返回 96 个名字。**面板侧，托盘图标真出现在 XFCE 通知区，与通知弹窗仍待使用者真机复验**，随 SNI/通知模块批次。
- **后续批次**：SNI 托盘 + DBusMenu，含真实面板复验；通知，即 `org.freedesktop.Notifications` 与 `set_progress`；UPower/logind/NetworkManager/屏保/MPRIS 监视、单实例、以及 `brightness` 的 logind `SetBrightness` 注入实做。

### MoonBit 原生 GUI 栈 · 系统集成状态族可脱总线三件 · `sys` sysinfo + windowctl + clipboard_watch

- **桩读文件不能只按 `ftell` 定长**，本批修掉的真 bug，覆盖此前所有走这条桩的读盘：`/proc/meminfo`、`/proc/uptime`、`/sys/class/dmi/id/*` 这类伪文件的 `lseek(END)` 报 **0 字节**，内容只有真正去读时才出现。旧写法 `fseek(END)` → `ftell` → 按该长度分配再 `fread` 正好命中这个坑：伪文件返回 `Ok("")`——**不是报错**——调用方解析失败还被当成「数据格式不对」。`yue_sys_read_text_file` 改成以 ftell 作提示、按块 `fread` 循环到 EOF——普通文件与数十 MB 的 SQLite 库同一条路径——两条本机断言，MemTotal/MemAvailable 与 uptime 秒数，当场从红转绿。**判据**：读伪文件得到「成功但空串」先怀疑取长方式，别怀疑权限。
- **窗口/剪贴板/时间日期类走命令路线**：`windowctl` 解析 `wmctrl -l -p` 列窗口、`-i -a` 按 id 激活、`-c` 按标题关闭；`clipboard_watch` 走 `xclip -selection clipboard -o` 只读轮询——本机未装 xclip 时以退出码 127 呈现，归一成 `Unsupported`，与「命令缺失」语义一致而不是报错；`sysinfo` 纯读 `/etc/os-release`、`/proc/meminfo`、`/proc/uptime`、`/sys/class/dmi/id/`。激活/关闭/挂监听都是设置类：白盒只验命令构造与输出解析，动作留给调用方。
- **剪贴板监听的定时器改「由调用方注入」**：master 的 `cbw_start_watch` 直接挂 libyue 的 `set_timer`，无取消 id，靠停靠标志自然终止；新栈 `sys` 不引 GUI 核心层，于是把排期能力做成参数 `schedule : (Int, () -> Unit) -> Unit`，GUI 层传 `fn(ms, f) { let _ = @core.set_timeout(ms, f) }`，无头测试传一个把每拍回调收进表里的假通道——于是**续拍与 stop 后不再续拍都能在测试里逐拍手动派**，这条与主题批「探针作参数」是同一个分层理由。
- **总线依赖的六件留 DBus 线**：`power` 即 UPower、`session` 即 logind/屏保、`online` 即 NetworkManager、`keepawake` 即 logind inhibit、`powerctl` 即 `gdbus_call_system`、`locale_sys` 的 localed 部分——`timedatectl` 那半可脱总线。
- **验证**：`moon test -p NoahLiu/native-gui/sys` **163/163**——新增 36：sysinfo 14——含本机 `/proc` 两条活断言；windowctl 14——`wmctrl -l -p` 真实列表读到 8 个窗口；clipboard_watch 8——假定时器通道逐拍派发、stop 不再续拍、xclip 缺失归一 Unsupported 等。`sys` `--deny-warn` 零警告、全仓红点仍 287 errors / 68 warnings 未增。

### MoonBit 原生 GUI 栈 · 桌面集成族后半 · `sys` 最近文件 recently-used.xbel

- **数据面**：GTK 系应用，即 Thunar / Nautilus / GIO、xdg-desktop-portal-gtk，都往 `$XDG_DATA_HOME/recently-used.xbel`——缺省 `~/.local/share/`——追加，本层**只读不写**。解析是手写薄扫描器，只取 `bookmark` 与 `bookmark:application` / `mime:mime-type` 的属性，把易错面全交给三块纯函数：XML 实体解码——命名实体 + `&#NN;`/`&#xHH;`，坏码点与代理值按字面保留；URI 百分号解码——连续 `%XX` 按 UTF-8 组合，`100%` / `%E` / `%zz` 原样留；ISO 8601 → Unix 毫秒——小数秒取前三位、无时区按 UTC、闰日校验。本机实读 **156 条**。
- **旧 wbtest 的 `inspect(x, content="…")` 在 native 后端不断言**，此前记过一次，本批是第二个现场：整批平移过来会「全绿但零覆盖」。转换口径：布尔→`assert_true`/`assert_false`；数字→`assert_eq`，**Int64 的字面量要补 `L`**——XBEL 的毫秒时间戳超出 Int 位宽，写 `assert_eq(items[0].added, 1776757238510)` 会类型不匹配；数组的 debug 文本 `[1, 2, 3]` 直接改写成数组字面量；`content="<应解析成功>"` 这类不是断言而是错误分支里的说明文字，落成 `println` 并补一条显式失败断言。
- **冒烟用例的报错分支不能静默跳过**：`rf_recent` / `rf_by_app` 的旧写法是 `Err(_) => ()`，即「本机没记录就算跳过」，它把「有文件却读不出」这类真回归一起掩盖掉。改成 `Err(e) => { assert_false(rf_supported()); println(...) }`——只有本机确实没有这份文件时才允许走到 Err 分支。
- **两条 XBEL 容错语义，用例钉住**：注释里藏的假 `<bookmark>` 不收，`skip_declaration` 走 `-->`；同一 bookmark 出现两个 `mime:mime-type` 时**首个生效**；写到一半截断的 XBEL 只收已闭合的条目。
- **验证**：`moon test -p NoahLiu/native-gui/sys` **86/86**——新增 13：实体解码/ISO 换算与闰日/历法天数/百分号解码/URI 还原/完整 XBEL 样例六态/非 XBEL 与截断/映射与并列排序/按应用精确过滤/`rf_take` 边界/`rf_data_dir` 三态/两份本机真实冒烟。`sys` `--deny-warn` 零警告、全仓红点仍 287 errors / 68 warnings 未增。

### MoonBit 原生 GUI 栈 · 桌面集成族中半 · `sys` 壁纸 + 默认应用 · 附子进程环境补漏

- **`pr_env_blob` 少透传 DISPLAY / DBus 两条，桌面侧命令在子进程里必失败**，上一批 monitor 只能 skip 的根因就在这一行：[pr_run] 给子进程的环境是白名单构造的，原先只有 `PATH` / `XDG_RUNTIME_DIR` / `HOME` + `LC_ALL=C`，`xrandr --query` 拿不到 `DISPLAY` 就退出 1，`xfconf-query`、`gsettings` 拿不到 `DBUS_SESSION_BUS_ADDRESS` 也起不来。本批补 `DISPLAY` / `XAUTHORITY` / `WAYLAND_DISPLAY` / `DBUS_SESSION_BUS_ADDRESS` 四项透传后，**同一个宿主上** monitor 的用例真读出 DP-0..5 与 HDMI-0——主输出 1920x1080——与 HDMI-2，壁纸的只读冒烟读出 `/usr/share/xfce4/backdrops/Dolomites_by_Felix_Hartlieb.jpg`。**判据**：同一命令在 shell 里跑得通、在 `pr_run` 里非零退出，就是白名单少了变量，别先怀疑工具版本。
- **壁纸的属性选择与已连接输出联动**：XFCE 的 `last-image` 按「workspace0 且输出已连接 → 首个 workspace0 → 首个可解析项」三轮挑，第一轮用 [mon_list] 的 connected 集合排掉拔掉显示器留下的陈旧项；xrandr 不可用时退化为「首个 workspace0」。写路径按同一规则选目标属性，这是「绘制与命中同源」那条纪律在这里的对应物，一条都没有时创建 `monitorNone-1` 的兜底项。第三轮**不再看已连接**，只按清单顺序取首个可解析项。
- **默认应用的写路径在测试里真写、真读回**：`da_set_default` 的落点是 `$XDG_CONFIG_HOME/mimeapps.list`，测试把 `XDG_CONFIG_HOME` 指到 `/tmp/da_wbtest_config`，存—改—断—复，断三态——文件不存在→新建段；同 mime 再设→原行替换不留第二行；另一 mime→段内追加——既不碰用户真实配置又走完整条读写链。
- **工具链两条，本批实测**：① **同包多枚举的同名构造器要消歧**——`Unsupported`/`CommandFailed`/`ParseFailed` 在 `WallpaperError`/`MonitorError`/`VolumeError`/`FileManagerError`/`AppFindError` 之间撞名，测试里裸写报 4124，报文 `The constructor ... is ambiguous`，得写 `WallpaperError::ParseFailed(...)`；实现文件里 `match self { Unsupported => ... }` 上下文能定类型，不用改。② **无载荷的 enum 同样不自动带 `Show`**：`println("\{de}")` 编译不过，报 `Type DesktopEnv does not implement trait Show`，诊断面走专门的 `desktop_name()`。
- **验证**：`moon test -p NoahLiu/native-gui/sys` **73/73**——新增 14：壁纸 9——真实 xfconf 属性清单的三轮选择、`monitorNone-1` 兜底、gsettings/KDE 输出解析与参数构造、JS 单引号转义、文本工具、参数防御与 Show 文案、真机只读冒烟；默认应用 5——mimeapps 段解析与同名键不去重、合并改写四态、关联合并去重排序、临时 `XDG_CONFIG_HOME` 真写读回、xdg-mime 本机探测。`sys` `--deny-warn` 零警告、全仓红点仍 287 errors / 68 warnings 未增。**`wp_set` 属设置类**：本批只验参数构造、不真改桌面外观，与 master 同纪律，换壁纸由用户按需在真机执行。

## Linux

### 桌面环境(托盘 / 菜单行为差异)

#### XFCE ✅

- 自启动 .desktop 实测:Exec 经 /proc/self/exe readlink 取绝对路径(开发期指向 _build 构建产物,产物位置一变条目即失效——发布版固定安装路径才可靠,AppImage 指向挂载点同理);整文件 desktop-file-validate 零警告;启用位解析兼容系统侧 Hidden=true 与 X-GNOME-Autostart-enabled=false 两种禁用开关,disable 幂等(条目不存在视为成功)。

- 右键菜单由面板自镜像 DBusMenu 渲染,不走 SNI ContextMenu 让应用自绘。
- xfce4-panel 4.18 只发批量版 `EventGroup` / `AboutToShowGroup`,不发单条版:只实现单条版会被 UnknownMethod 静默拒绝,表现为菜单能弹、点击全部无效。
- 桌面通知必须走 `Notification::Show()`;`NotificationCenter::AddNotification` 在 Linux 从不发 DBus Notify,静默失败。
- 全局快捷键是 XGrabKey 排他注册,键位被占用 Register 返回 -1(不崩,静默失败),使用方须检查并提示换键。
- 焦点落在桌面时 xfwm4 抢占键盘,全局快捷键不触发(焦点在应用窗口时正常)。

#### GNOME ✅(X11 与 Wayland 双会话)

- AppIndicator 扩展在注册瞬间读 Menu 属性建代理:空菜单返回 `/` 会让菜单客户端永久坏死(点击图标全程无反应)。traybus 恒返回真实 `/MenuBar`,空菜单也导出,靠 LayoutUpdated 填充。
- `ItemIsMenu=false`:左 / 右键均发 Activate。
- 全局快捷键在 Wayland 会话段错误(上游用 GDK X11 宏强转根窗口):已加 `GDK_IS_X11_DISPLAY` 守卫,非 X11 会话 Register 返回 -1。
- 鼠标键位是 yue 统一语义 1=左 2=右 3=中,GDK 原始的 2/3 已被交换,组件按 yue 语义判断。
- SSH 起 GUI 的环境变量:X11 会话 `XAUTHORITY=/run/user/1000/gdm/Xauthority`;Wayland 会话 `XAUTHORITY=/run/user/1000/.mutter-Xwaylandauth.*` 与 `WAYLAND_DISPLAY=wayland-0`;均需 `DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus`。

#### KDE ✅(Plasma 5.27)

- 面板直收 SNI,新图标直接进可见托盘区;托盘 / 菜单 / 退出全链路通过。
- 协议行为与 XFCE 相反:只发单条 `Event` / `AboutToShow`,不发批量版;traybus 两种都实现。

#### Deepin ✅(23 / 25,DDE)

- dde-dock 实现 StatusNotifierWatcher,SNI 直连可用;新图标默认进折叠区,可拖出常驻。
- libyue 的 Popover(透明窗 + 指针抓取)在 DDE 不渲染且拖慢鼠标:shim 按 `XDG_CURRENT_DESKTOP`(23=DDE,25=Deepin)回退无边框普通窗口。
- 宿主机(Ubuntu 24.04)构建的二进制可直接跑:glibc 符号上限 2.38 且 deepin 带 webkit2gtk-4.1 运行库;跨发行版分发先查 glibc 符号需求(`objdump -T | grep GLIBC_`)。
- `TextEdit::Delete()` 是删选区不是清空;清空用 `set_text("")`。
- DDE 剪贴板管理器交互偶发 CHECK / CRITICAL 日志噪音,不影响功能。

#### KDE / MATE / Cinnamon / Budgie / LXQt ❓ 未实测

- 协议层均支持 SNI,traybus 已按协议实现,待真实环境逐一验证。

### DBus 线路协议(traybus)

- DBus 数组长度前缀不含首元素前的对齐填充;算进去会被 dbus-daemon 判违规断连。
- 头部 SIGNATURE 字段的 variant 签名是 "g"(u8 长度编码),按 "s" 编过不了真实总线。
- SNI Menu 属性恒返回真实菜单对象路径,空菜单也不能回 `/`。
- 单测自洽 ≠ 互操作通过:协议问题用 dbus-monitor 抓真总线定位,GNOME 面板侧异常看 journalctl。
- 单实例 RequestName 必须带 flags=4(DO_NOT_QUEUE):默认 0 会排队,第二实例的防多开判定挂到首实例退出为止,语义全错。真总线实测(Ubuntu 24.04 XFCE):回复 3=他连接持有(已有实例→唤醒后退出);首实例 SIGKILL 后总线自动回收名字,新连接回复 1 即 claim 成为首实例;回复 4=本连接已持有(幂等)。完整链路(RequestName flags=4 → EXISTS → Wake('as') → RETURN)经 dbus-monitor 真总线抓包验证:Wake 到 RETURN 39µs;SIGKILL 首实例后第三实例可正常 claim。
- 二次唤起的 Wake 分发必须插在 bus.mbt 的 Conn::handle kind==1 分支、先于 sni.mbt 的 handle_call:所有入站调用都汇进 handle_call,不拦截就落 UnknownMethod 兜底,首实例永远收不到。Wake 命名约定:接口 org.moonbitlibyue.Instance、对象路径 /org/moonbitlibyue/Instance、成员 Wake('as'=第二实例命令行,经 moonbitlang/core/env args() 透传,含 argv[0] 程序路径,使用方自行取舍)。
- FileManager1(打开并选中文件)实测(XFCE):NameHasOwner 在线探测可用;ShowItems 线格式 "ass"(file URI 数组 + startup_id 空串);file URI 的百分号 hex 用大写(RFC 3986 大小写均可,大写为通行惯例),unreserved(A-Za-z0-9-._~)与 '/' 不编码,其余按 UTF-8 字节 %XX,单测锁定。服务不在线或调用失败的回退是 xdg-open 打开父目录——选中态丢失,属语义降级,使用文档须写明。
- 外部打开类的 spawn 走 g_spawn_async(G_SPAWN_SEARCH_PATH + 输出重定向 DEV_NULL),glib 自动回收子进程无僵尸;不经 shell,argv 直传。xdg-open 对不存在路径/不可打开 URL 的行为因桌面而异,库层 Ok 只表示「已交给系统」,系统侧成败不回传。
- 屏幕抑制(Inhibit/UnInhibit)服务名以 NameHasOwner 真实在线为准,不按环境名猜:候选表 [org.freedesktop.ScreenSaver, org.xfce.ScreenSaver],实测 Ubuntu 24.04 XFCE 仅 org.xfce.ScreenSaver 在线(xfce4-screensaver 持有),org.freedesktop.ScreenSaver 无人持有。两家接口同构:对象路径与接口名由服务名点换斜杠派生,Inhibit("ss" = 应用名 + 原因)-> u cookie,UnInhibit("u" = 原 cookie)须逐位一致(真总线抓包:Inhibit 得 cookie 1516211641,2 秒后 UnInhibit 带同值,空应答成功)。GNOME / KDE 的服务持有情况待真机补记。
- 系统总线(Ubuntu 24.04 实测):socket 为 /run/dbus/system_bus_socket,未设 DBUS_SYSTEM_BUS_ADDRESS 时按此默认直连成功;地址显式设置时按逗号分隔取第一个 unix:path=,取不到(如 tcp: 地址)必须显式 Err 带原文——静默回退默认 socket 会连回真有 UPower 的总线,降级验收变假失败。系统总线 BecomeMonitor 被拒(dbus-monitor 与 busctl monitor 同),抓包不可用,验证走探针自身往返 + busctl call 对照应答形状。
- 多总线连接并存(B5 基建):shim 的 fd 监视从进程级单槽(每次 watch 覆盖上一条)改为 fd→回调分发表 + unwatch;MoonBit 侧 fd→Conn 注册表按 fd 路由。双连接(会话 SNI + 系统 UPower)并存实测互不覆盖。glib source 回调返回 0 时 glib 自毁 source,shim 表项同步 erase(否则后续 unwatch 对已亡 id 再 g_source_remove 触发告警)。
- wire 层 'd'(DOUBLE)与 't'(UINT64)必须成套支持:真总线 UPower GetAll 应答里 UpdateTime 是 't'、Percentage/Energy 是 'd',缺 't' 时 variant 未知签名走「返回空串但读位不动」的旧防御分支,后续元素整体错位、read_string 切片越界直接 abort(单测自洽测不出——自造的形状恰好没踩到)。防御已改两层:variant 未知签名把 pos 推到消息尾(解析化为垃圾值而非错位)、read_string/read_sig 加边界检查。新增类型是全链路八处联动:DVal/Sig/sig_align/parse_one_sig/sig_of/sig_char/encode/decode_in。
- Double↔IEEE 754 位转换放 shim(moonbitlang/core 无 Double::to_bits/from_bits,实测确认):yue_mbt_sys_f64_to_bits/from_bits 纯位重解释(static_assert sizeof(double)==8),wire 层 'd' 借道 Int64 的 8 字节小端读写。注意:traybus 的 whitebox 测试目标一旦引用此类 extern,链接就吃 -lyue_mbt——而 link_configs 按「依赖该包的目标」传播,traybus 不依赖 yue(反向),prebuild.py 须为 NoahLiu/native-gui/yue/traybus 单列一份同值配置(静态库单成员引用 gtk 全套,不能给精简 flags)。
- UPower 读数路径(实测 Ubuntu 24.04,台式机):DisplayDevice(/org/freedesktop/UPower/devices/DisplayDevice,接口 org.freedesktop.UPower.Device)聚合主电池,IsPresent=false → Ok(None);属性接口名注意区分——设备是 …UPower.Device、顶层是 …UPower,PropertiesChanged 的 arg0 过滤天然把设备级信号挡在顶层订阅外。OnBattery 在顶层对象,交直流事件订阅顶层 PropertiesChanged、回调内直解 changed 字典(信号分发在 drain 栈上,回调内 call_sync 会重入收包路径,严禁)。
- 断线自愈(B5,未经真机断线演练):mark_dead 幂等(以 fd 注册表为准),经 shim 的 post_delayed_task(符号直 extern,绕开 traybus→yue 反向依赖)延迟 500ms 重连、最多 3 次;成功后重放 AddMatch 规则、迁移订阅表与托盘项并重新注册(断线期间 watcher 已按唯一名消失清掉旧注册)。纯 CLI 场景(主循环未跑)重连回调不触发,自然放弃。
- logind 事件订阅(B6):PrepareForSleep(b) 在 Manager 接口、Lock/Unlock 在各会话对象的 Session 接口(空体信号,按成员各一条 AddMatch,不限定 path——所有会话都收,多用户登录时别人的会话锁屏也会触发,归属限制调用方自查 sender)。降级实测(私有总线无 logind):suspend_resume_supported()==false、session_lock_watch 返回 Err(SystemError::Unsupported),不静默。快速挂起唤醒可能连收两条 Resuming(库内不去抖);唤醒后网络/DBus 可能未就绪,回调里的重试逻辑应延迟。
- 锁屏事件必须双信号源(真机踩坑修正):XFCE 的 xfce4-screensaver 锁屏**不调 logind**(logind Lock/Unlock 无信号;busctl 直接调 Session.Lock 方法可正常触发信号,证明订阅链路无恙、是锁屏器不通知),它锁屏时在自己持有的 org.xfce.ScreenSaver 上发 ActiveChanged(b)。修复:session_lock_watch 双源订阅——logind Lock/Unlock(系统总线,GNOME/KDE 走此)+ 屏保服务 ActiveChanged(会话总线,候选 [org.xfce.ScreenSaver, org.freedesktop.ScreenSaver] 按真实在线选定),多源同报经状态机去重(同态重复不派发,翻转才派发)。ActiveChanged 订阅 key 带服务名前缀,与 logind 订阅不冲突。
- XFCE「黑屏设置不生效」与常亮验证口径(真机诊断):电源管理器 GUI 的「黑屏 1 分钟」依赖 DPMS 或屏保空白屏,实测宿主机三条息屏链路全关(xfce4-screensaver /saver/enabled=false、X DPMS Disabled、xfce4-power-manager 无任何 dpms/blank 键)——设置界面有值但没人执行黑屏,常亮开关自然无从观测。验证常亮前须先开一路执行器(推荐屏保空白屏:锁屏器同源,抑制与锁屏事件都能配套);org.xfce.PowerManagement 抑制接口在本机不在线(NameHasOwner=false),XFCE 下 DPMS 黑屏不可经 DBus 抑制,避开该路径。
- Windows 电源/会话事件窗口(B6,代码落地真机待验):一个 message-only 窗口同时收 WM_POWERBROADCAST(PBT_APMSUSPEND;PBT_APMRESUME 与 PBT_APMRESUMEAUTOMATIC 都归已唤醒)与 WM_WTSSESSION_CHANGE(WTS_SESSION_LOCK/UNLOCK,NOTIFY_FOR_THIS_SESSION),WNDPROC 内 PostTask 抛回主循环(B1 消息窗口模式复用)。C 侧单窗口单回调,休眠/锁屏共用——MoonBit 侧全局单点登记按 event 码派发,后注册不得覆盖前者。WTSRegisterSessionNotification 失败只影响锁屏事件不视为整体失败。wtsapi32.lib 是全计划唯一链接清单改动,prebuild.py 的 WINDOWS_LINK_LIBS 与 shim/CMakeLists.txt 必须同提交(双清单无一致性注释背书)。
- NetworkManager 在线状态(B7):State 与 Connectivity 都是顶层属性,Properties.Get 的应答体是单 "v"(内为 u32),与 GetAll 的 a{sv} 不同形状。变化信号两条都订——老式 StateChanged(i) 直带新值,新式 PropertiesChanged(a{sv}) 的 changed 里可能带任一属性;订阅回调在 drain 栈上,只更新缓存与归并通知,严禁 call_sync 重查(首次缓存建在注册动作里,主线程非 drain 栈合法,最坏阻塞 1.5s)。归一口径:State 70/50 且 Connectivity 4/3 为 Online,门户劫持(Connectivity=2)按 Offline(「在线」= 可达互联网)。实测 Ubuntu 24.04:State=70/Connectivity=4 → Online,与 busctl 逐位一致;私有总线降级 Err(NetworkError::Unsupported)。Windows NLM GetConnectivity 位掩码:含 IPV4_INTERNET(0x40)/IPV6_INTERNET(0x400)为 Online,轮询 5s(监听式后置);netlistmgr.h 无需额外链接库。
- NM StateChanged 信号参数是 Int32(i) 不是 u32(真机踩坑修正):D-Bus 规范里属性 State 是 u、信号 StateChanged 的 state 参数是 i,两者类型不同源;wire 层 i 解码为 VI32,旧实现只匹配 VU32 被静默丢弃——信号照发、回调不触发,面板断开连接/关「启用网络」(State 70→20/10)后 UI 恒显示初始 Online(单测自洽测不出:自造信号体恰好写成 u)。修复:statechanged_of 对 VI32/VU32 双匹配,bool 等其余类型照旧丢弃;Properties.Get 与 PropertiesChanged 里的 State 仍是 u,不动。分发链路本身用无害属性写实测存活(NM 1.46 WwanEnabled 开关,无 WWAN 硬件机器零网络影响,PropertiesChanged 实时到达);信号触发后的 UI 翻转由真机断网/恢复验证。
- 网络回调登记必须平台分支外统一(真机两级观测定位):on_network_status_change 的派发统一走 net_dispatch 遍历 g_net_cbs,但登记 g_net_cbs.push(cb) 原本只在 Windows 分支——Linux 信号全数到达、缓存逐值更新(State 70→10→20→40→60→70 与 nmcli monitor 逐条一致)而回调零执行,UI 恒显初值;两级探针(traybus nm_on_change 层 + online 派发层)一对比即锁定。修复:push 提到平台分支外,两平台统一登记。同类事件注册(on_suspend_resume/on_power_source_change)是回调闭包直接内嵌、不经全局数组,无此问题;net_dispatch 的去重以注册时回填的 network_status() 为基线,注册后首条同态信号不派发属预期。
- 通用 D-Bus 调用层(yue/traybus/dbus.mbt,横切地基,媒体/磁盘/蓝牙/传感器/时区五模块共用):在 wire.mbt 的线协议与 bus.mbt 的进程级双连接之上加薄薄一层「任意服务的方法调用 + 属性读写」,六个公开入口 gdbus_call_session / gdbus_call_system / gdbus_get_property_session / gdbus_get_property_system / gdbus_set_property_session / gdbus_set_property_system(连接取进程级单例,没有则现连;同步调用 1.5 秒超时,与总线既有约定一致,应答超时给 gdbus.timeout)。**a{sv} 支持是这层的立项理由**:MPRIS 的 Metadata、udisks 的 GetAll 属性字典都是 a{sv},只支持基本类型的话每个模块都要各自解一遍字典,重复且易错。值模型 GDBusValue 覆盖 GVArray(元素签名, 元素表) / GVDict(a{sv},Map 按插入序序列化) / GVVariant(保持包裹) / GVStruct 四种容器:编码侧 GVArray 的元素签名由调用方给全("s"/"{sv}"/"(ii)" 等完整类型),套 GVStruct 时逐字段拼签名后整体过 parse_signature 预检**不带超时代价**(坏签名在本地就报 gdbus.encode,不用等 1.5s 总线超时);解码侧 `VArray("{sv}")` 折成 GVDict 并拆掉 variant 包裹(终端数据是取值,类别细分无后续编码影响),Byte/16 位整数并入 GVInt32、'g' 签名并入 GVString。参数树递归禁 GVNone(类型签名无从推导),入口先过 gdbus_args_ok 全树扫描。属性读路径的返回值已拆变体包裹(Properties.Get 的应答体恒为单 "v",解开直取内层),写路径的 value 传裸值、variant 包裹在本层完成。错误模型 GDBusError{ name, message }:name 取 D-Bus 错误名原样(UnknownMethod / ServiceUnknown 等),本地错误用 gdbus.io(连不上/已断开)/ gdbus.timeout / gdbus.encode 前缀,调用方按 name 前缀即可分流「服务不在线」与「应答超时」。
- udisks2(org.freedesktop.UDisks2,系统总线)接口要点:对象枚举走 `/org/freedesktop/UDisks2/Manager` 的 GetBlocks 返回 a{oa{sv}}(设备路径 → 该 block 对象的全部属性字典),每块再按需 Properties.GetAll 补 Filesystem 接口;**挂载点属性(MountPoints)的类型是 aay(字节数组数组)**,不是 as——按字符串数组解析会直接把全部条目变成空串,挂载态永远读不出来,须逐字节数组按 UTF-8 解码。挂载/卸载走 Filesystem 接口的 Mount(options : a{sv})/Unmount(options : a{sv}),第一参 options 可传空 GVDict;应答带挂载点字符串(多挂载点设备可能多个)。udisks2 不在线时 lsblk --json 只做枚举回退(char-typed 字段需 ansi 剔除)。
- bluez(org.bluez,系统总线)接口要点:对象枚举用 ObjectManager.GetManagedObjects,应答形状 a{oa{sa{sv}}}(路径 → 接口名 → 该接口的属性字典),按接口名 filter 出 Adapter1 / Device1 两摊;Adapter1 的 Powered / Discovering 与 Device1 的 Name / Alias / Paired / Connected / Trusted 都从字典里取。开扫描用 Adapter1.StartDiscovery(空参),配对用 Device1.Pair(空参),连接用 Device1.Connect——三者都是空参方法,应答为空。**无蓝牙适配器是合法状态**:org.bluez 不在线或枚举不到 Adapter1,bt_supported() 给 false、查询类 API 给 Unsupported,不当异常处理。
- iio-sensor-proxy(net.hadess.SensorProxy,系统总线)接口要点:属性 HasAccelerometer / HasAmbientLight / LightLevel / AccelerometerOrientation 全在同一对象 `/net/hadess/SensorProxy` 的单一接口上(与 udisks / bluez 的多接口多对象不同)。**取值前必须 ClaimLight/ReleaseLight(或 ClaimAccelerometer/ReleaseAccelerometer)**:传感器不点灯时读数停在旧值,取完必须释放,否则别人(如自动亮度)读不到新值。AccelerometerOrientation 的类型是**字符串**(不是枚举整数),取值如 "normal"/"left-up"/"bottom-down"。
- Windows NLM GetConnectivity 在 UI 线程调用可秒级冻结并连带原生布局断言崩溃(实测 Win10 19045 宿主机,网络环境差时必现):showcase 启动 3.7~4.7s 稳定 abort(0xC0000409 = fast-fail),崩前 stderr 打出 yoga 顶层断言「availableHeight is indefinite so heightMeasureMode must be YGMeasureModeUndefined」;崩率随网络环境 0%~100% 漂移(网络健康时查询毫秒级,与提交时冒烟存活一致,极易误判为代码回归)。定位路径:同一 exe 二分页面(仅系统集成页消失即 0 崩)→ 只禁网络初值查询+回调注册即 10/10 稳 → 预热/延迟查询均无效(查询存在即冻结,与时机无关)。根因:GetConnectivity 慢路径单次可达秒级,注册时的同步初值查询冻结 UI 线程数秒,返回瞬间 yoga 在积压布局上走 ScrollView 内容测量的 GetPreferred* 路径(该路径以 NaN 高度调 YGNodeCalculateLayout,对 height 样式已定义的容器是 fatal)。修复:shim 新增 yue_mbt_netwin_start/netwin_cached——后台 MTA 线程独占 COM 与轮询(interval 默认 5s),结果写进程级缓存,UI 线程只读缓存(network_status 缓存未就绪返回 QueryFailed,on_network_status_change 不再同步回填初值,g_net_last 改 None=未知态、首值必派发)。跨线程 COM 的 apartment 问题因接口指针创建与使用都在同一线程自然消解。验证:moon check 零警告、128 测全过、showcase 冒烟 12/12 存活(修复前同环境 7/10 崩)。
- **多托盘项的 DBusMenu 对象路径必须随项路径派生(CORE2,白盒 + 真总线回归)**:SNI 的 Menu 属性旧实现恒返回 `/MenuBar`,menus 注册表(菜单对象路径 → Item)同键互覆——建第二个托盘项时 `c.menus.set("/MenuBar", item2)` 直接顶掉第一项的路由,面板从此只认最后注册那项的菜单(第一项的布局查询/点名落到第二项上或 UnknownObject);注销时按新键也清不掉旧键,注册表永久脏。修复:`menu_path_of(项路径)` 派生(`/StatusNotifierItem`→`/MenuBar`、`/StatusNotifierItem_N`→`/MenuBar_N`,首项沿用 ksni 约定),unregister 与 create 失败路径对称清理 items + menus 两张表;`Conn::next_item_path` 改为扫首个空闲路径(旧实现按 items.length()+1 编号,注销中间项后新项复用已占用路径,与菜单路由一起撞车)。真总线回归(sni_wbtest,无面板 watcher 自动跳过):建两项断言路径/菜单路径互异,经 `gdbus_call_session(自身唯一名, 各菜单路径, GetLayout)` 分别拿到各自菜单标签(互不含对方标签),注销后两表清零且新项从头拿路径;暂存修复前代码(menu_path_of 恒 /MenuBar)相关用例精确失败。**面板侧双图标与各自菜单的实际弹出行为需真机目视复核**。
- **断线自愈重连不得无条件新建连接(CORE2,白盒 + 真总线回归)**:`try_reconnect` 旧实现拿到 g_saved 就直接 connect_session/connect_system 并覆盖 g_conn/g_sys_conn——若断线后按需路径(sni_available / Item::create / system_conn)已重建过一条活连接,这条连同它的 fd 与 glib fd 监视一起被泄漏(g_conns 注册表按 fd 路由,覆盖后再无引用能 unwatch/close),订阅与托盘项也分裂在两条连接上,信号只到达被 orphan 的那条。修复:迁移逻辑收敛为 `Conn::adopt_saved(bus)`,由 connect_session/connect_system 在任一新连接建立时立即调用(按需重建与自愈重连同路),`try_reconnect` 先看 g_conn/g_sys_conn 是否已是活连接——是则只补一次迁移(幂等),不再新建。附带修了两个老问题:迁移时本连接已占用的路径不重复注册(防同连接重复 RegisterStatusNotifierItem 出双图标);`Item::unregister` 在连接已断时也清暂存旧连接里的项(旧实现只清当前表,项会随重连复活)。托盘项的重新注册经 `sys_post_delayed(0, …)` 投回主循环:register_item_path 内部 call_sync 要泵总线,同步执行会让 sni_available / Tray::is_supported 这类谓词在 GUI 回调里被调用时阻塞至 1.5s,并让泵期间到达的入站调用重入派发(与 netmon/UPower 回调严禁 call_sync 同一条纪律)。真总线回归:mark_dead 模拟断线 → 按需重建 → try_reconnect 后 g_conn 仍是同一条(唯一名不变)、g_conns 不新增;暂存修复前行为(无条件新建)精确失败。

- sysmonitor 实测(Ubuntu 24.04 XFCE X11,口径同篇首性能基准:启动中位、稳态 Rss、release 二进制):启动(exec → 窗口 map)5 轮 77/78/81/82/88ms,中位 81ms(hello 基线 70ms 是空载系统,本次系统载有 1042 进程);稳态进程页前台 1Hz 刷新 CPU 2-3%(采样 + 派生数据 + 千行表格重建 + 重绘合计约 25ms/秒),Rss 84.9MB → 100s 后 85.8MB 走平;二进制 7.72MB(hello 对照 7.03MB)。千行进程页验收达标:1053 进程全量采样 14.94ms/次(release,≈14µs/进程,每进程两次 /proc 读取),1Hz 下采样占空 1.5%。
- 千行表格用 table_v_t 虚拟滚动(只画可见行):刷新走「数据层全量采样 → 过滤/排序派生 → rows Store set → 表格 load + schedule_paint」,不重建视图树;选择按 pid 重映射(排序每秒变化时选中不漂)。无 C++ 对照副本,「封装层 + 数据层」合计开销以上述数值直接归因,UI 绘制部分与 hello 基线同口径(持平量级)。
- **空 pixmap 形态下 IconPixmap 属性回调 panic(2026-10 用户真机栈 + 修复前后对照实证)**:showcase 托盘 demo 点「切主题图标(Linux)」后,`set_icon_name` 按既定策略清空位图(XFCE 面板 IconPixmap 优先于 IconName,不清则换名后仍画旧图),形态为 w=0/h=0/空 buf;面板收到 NewIcon 回查 IconPixmap,`Item::property` 对空 pixmap 调 `downscale_pixmap(0, 0, …)` 生成 16×16 附档——旧实现的钳位守卫 `if y*h/nh > h-1 { h-1 }` 在 h=0 时条件 `0 > -1` 成立,钳出 **sy=-1**,`px[src+c]` 负索引,DBus 回调里直接 PanicError(exit 134)。用户真机栈:`traybus.downscale_pixmap(icon.mbt:63) ← Item::property(sni.mbt:539) ← Conn::handle_call(sni.mbt:660) ← drain ← on_bus_ready`。修复:`downscale_pixmap` 对退化尺寸(w/h/nw/nh ≤ 0 或缓冲区短于 w*h*4)**早退返 (0,0,空)**,删掉两处合法输入下永不命中的死钳位(y*h/nh 恒 < h);主档 `pixmap_value` 本就容忍空态,面板回落 IconName 走主题图标,SNI 语义不变。修复前后对照(同探针同路径,建托盘→set_icon_name→面板/手动回查 IconPixmap):修复前 exit 134 崩、栈与用户报告逐帧一致;修复后属性返回 `[(0,0,[]), (0,0,[])]`、进程稳定存活(手动 gdbus Properties.Get 复核亦然)。回归:icon_test 补 3 条(0×0 空 pixmap、退化目标尺寸、短缓冲区均返空),moon test 659 全绿。教训:**DBus 属性回调栈上的纯函数同样要防退化输入——回调里 panic 直接杀消息泵;「钳到 h-1」这类尺寸守卫在尺寸为 0 时会把 -1 当合法值,早退比钳位可靠;清空态(0×0)是合法业务状态,所有消费者都要容忍**。
### 系统监控数据层(/proc、/sys,sysmonitor 示例)

- /proc、/sys 伪文件 stat 尺寸恒为 0(fseek/ftell 拿不到长度):整文件读取必须循环增量 `fread` + 倍增缓冲(上限 16MB);读目录时 `fopen` 成功但 `fread` 报 EISDIR,靠 `ferror` 判失败。实现在应用 native-stub `examples/sysmonitor/stub/sysmon.c`,MoonBit 侧统一走 `read_text_file`。
- 应用自有 native-stub 可放子目录:`"native-stub": ["stub/sysmon.c"]` 相对 moon.pkg 所在目录解析;符号全在 libc 默认链接范围,零 shim / fork / vendored / 链接参数改动。测试目标自动链入该 stub,wbtest 可直接读真实 /proc 文件。
- /proc/stat 列序 `user nice system idle iowait irq softirq steal guest guest_nice`:第 9 列 guest 已由内核计入 user/nice,再累加即重复计数;占用率 = (Δ总 − Δidle − Δiowait) / Δ总,iowait 不算 CPU 忙。采样间隔短于一个 tick(USER_HZ 通常 10ms)时 Δ总 ≤ 0,返回 0;首帧前样本取全零,首屏值为开机至今均值。
- /proc/cpuinfo 型号字段平台分歧:x86 是 `model name`,ARM 开发板只有 `Processor` / `Hardware`,三级回退;核数取 `processor` 行数(逻辑 CPU 含超线程,与 nproc 一致)。
- Windows 侧 /proc/cpuinfo 的核数修正(超 64 核,终审发现):GetSystemInfo 的 dwNumberOfProcessors 只覆盖调用线程所在组(单组 ≤64),多组机器须按 GetLogicalProcessorInformationEx(RelationGroup) 的活动组内 ActiveProcessorCount 求和。原实现的守卫与偏移全部不对:关系常量写成 3(RelationProcessorPackage,真实 RelationGroup=4),ActiveGroupCount 读 it+8(真实为 it+10:记录头 8 字节 + MaximumGroupCount 2 字节),GroupInfo 基址与步长按 32+64g(真实为 it+32 起、每组 48 字节),守卫按 32+64g(真实 32+48g)——单组时 API 返回 Size=8+24+48=80 < 96,total 恒 0,修正永不触发,>64 核机器核数停留在当前组值。权威布局(Microsoft Learn winnt.h 文档):GROUP_RELATIONSHIP{WORD MaximumGroupCount; WORD ActiveGroupCount; BYTE Reserved[20]; PROCESSOR_GROUP_INFO GroupInfo[]}(头 24 字节,联合体自记录 +8 起),PROCESSOR_GROUP_INFO{BYTE MaximumProcessorCount; BYTE ActiveProcessorCount; BYTE Reserved[38]; KAFFINITY ActiveProcessorMask}(体 48 字节),SYSTEM_LOGICAL_PROCESSOR_INFORMATION_EX 的 Size 是整条记录长度(含 Relationship+Size 头),用作走到下一条记录的步长。验证:harness 以真实结构体填充 2 组(64+32)缓冲区,断言求和得 96;单组与 Size 被裁两种退化各断言回退 64。**多组真机数值须 Windows 真机核实**。
- /proc/meminfo 单位恒为 kB;`MemAvailable` 内核 ≥3.14 才有,缺失回退 `MemFree`;已用口径 = 总 − 可用(含可回收缓存)。
- `moon run` 包装进程不向子进程传播信号:冒烟验证退出行为要杀构建产物 exe 子进程,只杀包装 PID 会留下孤儿窗口。
- 全量进程采样实测(release,Ubuntu 24.04):580 进程 × 2 文件读取(stat + cmdline)共 9.57ms/次,1Hz 刷新约占 1% CPU;RSS 取 stat 的页数 × 页大小(与 status 的 VmRSS 等值),省掉每进程第三次读取。
- /proc/[pid]/stat 的 comm 可含空格与嵌套括号(进程名 "(foo (bar))"),只能按行内最后一个 ')' 切分;comm 截断到 15 字符,完整命令行另读 cmdline(NUL 分隔,空则内核线程回退 [comm])。
- getpriority 的 nice = -1 是合法值,与出错返回值歧义:成败经 `Ref[Int]` 出参报告(kill / setpriority 仍用 errno 返回值)。
- Windows 无 /proc 与 nice 语义:stub 编译期保留同一 ABI、运行期返回「不支持」哨兵(-1000),MoonBit 层语义化为中文提示,进程页整体降级;CI 三平台构建不受影响(macOS 走 POSIX 分支天然可用)。
- NVIDIA 专有驱动的 GPU 占用 / 显存 / 温度不可走进程内 NVML:dlopen `libnvidia-ml.so.1` 后 `nvmlInit_v2` 与宿主运行时偶发堆冲突(本机 RTX 3070 + Ubuntu 24.04 实测启动段错误约 5/6,gdb 下不复现、时序敏感;仅 dlopen+dlsym 不 init 则干净),已改 popen `nvidia-smi` 批量查询(`--query-gpu=pci.bus_id,utilization.gpu,memory.used,memory.total,temperature.gpu,name --format=csv,noheader,nounits`,每卡一行),pci 总线地址按「取冒号后最后一段去前导零」与 sysfs 枚举对位(nvidia-smi 的 00000000:01:00.0 vs sysfs 的 0000:01:00.0);代价是每次采样一个子进程(实测几十毫秒,1Hz 可接受)。nvidia-smi 不存在(无 N 卡 / 未装驱动)时自然回退 sysfs 通用节点(amdgpu / nouveau 的 `gpu_busy_percent`、`mem_info_vram_*`),hwmon 温度两者通用;N 卡专有驱动无 hwmon,温度只能来自 nvidia-smi。
- diskstats 同时含整盘与分区条目(nvme0n1 与 nvme0n1p1/p2/p3);LVM 挂载设备名(/dev/mapper/ubuntu--vg-ubuntu--lv)与 diskstats 名(dm-N)对不上,须经 `/sys/block/dm-*/dm/name` 反查 dm-N 再取 slaves 首项(实测 dm-0 → nvme0n1p3)才能把 IO 速率归属到挂载行。
- hwmon 温度编号跳号(coretemp 只暴露部分核的 tempN_input),label 可缺(acpitz 无 label,回退 chip 名);毫摄氏度可为负(电池传感器);NVIDIA 独显普遍不暴露 hwmon 温度(实测 0x2488 无 temp),GPU 温度按 hwmon 口径显示「—」。
- statvfs 容量取 f_bavail(可用,含保留块扣除)而非 f_bfree,与 df 的 Use% 口径一致;结构体跨 ABI 拆成 total/free/avail 三个 int64 出参。
- /proc/mounts 的伪文件系统(proc/sysfs/cgroup2/devtmpfs/efivarfs 等约 20 种)statvfs 无容量意义,容量表按 fstype 黑名单跳过,只留 /dev/ 真实设备行;同一设备多挂载点(btrfs 子卷 / LVM 快照)按设备去重取首个。
- 目录枚举(/sys/class/hwmon、/sys/class/net、/sys/bus/pci/devices、/sys/block/*/slaves)经 stub 的 opendir/readdir 通用化(换行分隔条目名),与 read_text_file 同为数据层唯一两类 IO 原语。
- /dev/fuse 控制挂载(文件管理器拉起 gvfsd-fuse 后出现,挂载点 /tmp/fuse)statvfs 合法返回但 f_blocks=0:只按 fstype 黑名单过滤伪文件系统不够,须再按 total<=0 过滤,否则磁盘页出现 "0 MB / 0 MB" 噪音行(实测 S5 白盒断言 total>0 也因此挂)。
- **Windows 数据层(SYS1):Win32 数据源在 stub 读取入口虚拟出与 Linux 同构的 /proc、/sys 文本,MoonBit 数据层与解析纯函数零改动**。设计定案:与其在 MoonBit 层开平台分支(每个采样器×2 套实现、纯函数测试无法覆盖 Win32 路径),不如让 C 侧把 `read_text_file`/`list_dir`/`statvfs`/`list_pids` 请求的 Linux 路径现场生成同构文本——Linux 路径即跨层契约,单测照常喂字面量全绿。七路映射与偏差清单:
  - CPU:/proc/stat = GetSystemTimes(全局;kernel 含 idle,须相减)+ ntdll `NtQuerySystemInformation(SystemProcessorPerformanceInformation)` 每逻辑核(未公开信息类但 ABI 数十年稳定,任务管理器同源;查询失败只输出总行,各核柱为空);单位统一换算成 10ms tick(100ns ÷ 1e5)与 clk_tck=100 对齐;/proc/cpuinfo 型号与主频取注册表 `CentralProcessor\0` 的 ProcessorNameString/~MHz(编译器无关,比 CPUID intrinsic 免 x86 条件编译),核数 GetSystemInfo(≤64)+ GetLogicalProcessorInformationEx(RelationGroup)组内活动处理器求和修正(>64 核系统 GetSystemInfo 封顶 64)。
  - 内存:GlobalMemoryStatusEx → MemTotal/Free/Available 与 SwapTotal/Free;ullAvailPhys 即 Windows 口径可用(直接充当 MemAvailable 与 MemFree),页面文件额度(ullTotalPageFile=commit limit)充当 swap,与任务管理器「提交」一致而非「页面文件池」。
  - 磁盘:/proc/mounts = GetLogicalDrives 逐盘(GetDriveType 只收 FIXED/REMOVABLE,光驱读盘噪音与网络映射盘跳过),行约定 `dev/C: C:\ ntfs ...`——设备列强制 /dev/ 前缀进 parse_mounts,挂载点直接放真实 Windows 路径(MoonBit 层 statvfs_info 原样传回,stub 侧 GetDiskFreeSpaceExW 直收,UI 显示 "C:\" 自然);/proc/diskstats = PDH `\PhysicalDisk(*)\Disk {Read,Write} Bytes`(PdhAddEnglishCounterW 英文名注册,规避本地化计数器名——中文 Windows 的对象/计数器名不同,硬编码本地化路径必失败;**路径有效性须真机核实**),取原始累计计数器(非 per-sec 变体)单次 Collect 即有效,值÷512 成扇区喂 MoonBit 现有 sector_rate 差值,实例名(如 "0 C: D:")按空格分词、只收形如 "C:" 的盘符 token(磁盘序号与 "_Total" 自然跳过),盘上每个盘符各出一行同名同值——PDH PhysicalDisk 计数按物理盘计, mounts 侧按盘符逐行产出,两个盘符都要能归属到所属物理盘(曾取最后一个 token,多分区盘只记最后一个盘符、其余分区速率恒 None)。**多分区盘实例名形态须真机核实**。
  - 网络:GetIfTable2 全表,InterfaceAlias 做网卡名,Software Loopback 归一为 "lo"(main.mbt 的速率汇总排除逻辑自动生效);InOctets/OutOctets 充当 rx/tx 累计字节。表带 200ms 静态缓存——每块网卡 rx/tx 各读一次路径,1Hz 下无缓存会全表拉取 2×N 次。
  - 进程:K32EnumProcesses(kernel32 导出名带 K32 前缀,须 GetProcAddress)枚举 pid;pid→ppid/线程数/镜像名单次 CreateToolhelp32Snapshot 快照(250ms TTL),每 pid 再 OpenProcess+GetProcessTimes(100ns÷1e5=10ms tick,clk_tck=100 同一单位)+K32GetProcessMemoryInfo(WorkingSetSize÷4096=页数,与 page_size=4096 对位);cmdline = QueryFullProcessImageNameA 全路径,系统进程 OpenProcess 被拒时时间/内存为 0、命令行回退 [comm]。nice 恒 0:Windows 优先级类不映射 Linux nice 语义(映射值会误导),priority 归一是 SYS2 范围(SYS2 已落地:nice 字段改为优先级类反查的档位代表值)。
  - GPU:DXGI CreateDXGIFactory1 枚举适配器,虚拟 pci 地址 `0000:00:NN.0`(MoonBit norm_pci 取尾段去前导零后唯一);vendor/device 出 "0x%04x" 小写喂现有 vendor_name 表;WARP 软件适配器(Flags bit0)跳过;显存 total=DedicatedVideoMemory(为 0 的集显不虚拟 mem_info_vram_total,UI 不出显存曲线),used=IDXGIAdapter3::QueryVideoMemoryInfo(Local 段).CurrentUsage;COM 头不 include dxgi.h——vtable 槽位按接口继承序手工声明(COM 二进制 ABI 稳定),IID 用 SDK 公开常量值自定义,规避 MinGW 头版本差异与 dxgi.lib 链接面。利用率 = PDH `\GPU Engine(*)\Utilization Percentage`,实例名 `pid_*_luid_0xHEX_0xHEX_*` 按适配器 LUID 低 32 位过滤求和(多引擎多进程聚合);**该计数器类型需两次采样才出格式化值,查询句柄静态跨拍保持,首拍恒 0;实例名格式与聚合口径须真机核实**。
  - **手工 COM 声明三处 SDK 事实修正(SYS1 终审修正)**:①三个 IID 全部写错——IDXGIFactory1 写成 770AAE78-F26F-4DBA-83A9-50BC11D9EE9B(真实 770AAE78-F26F-4DBA-A829-253C83D1B387),CreateDXGIFactory1 不被接受、E_NOINTERFACE 返回 → factory==NULL → GPU 一块都枚举不到;IDXGIAdapter3 写成 645967A4-1392-4316-9CEC-9CAF7113F420(真实 645967A4-1392-4310-A798-8053CE3E93FD),QueryInterface 恒失败 → 显存 used 永远拿不到;IDXGIAdapter1(当前无调用点)写成 290462F0-AC1E-4212-AA25-4F95B4968B12(真实 29038F61-3839-4626-91FD-086879011A05)。②IDXGIFactory1 vtable 漏 CreateSoftwareAdapter 且 Make/GetWindowAssociation 顺序颠倒:SDK 顺序(win32metadata dxgi.h 的 IDXGIFactory 块 + IDXGIFactory1 追加块)为 EnumAdapters、MakeWindowAssociation、GetWindowAssociation、CreateSwapChain、CreateSoftwareAdapter,再由 IDXGIFactory1 追加 EnumAdapters1、IsCurrent——原声明下标 11 的「EnumAdapters1」实为 CreateSoftwareAdapter,调用即以 Module=(HMODULE)i 走 CreateSoftwareAdapter(对模块句柄加引用计数),循环 16 次拿不到硬件适配器。③IDXGIAdapter vtable 槽位名同样照 SDK 更正(EnumOutputs;RegisterHardwareContentProtectionTeardownStatusEvent / UnregisterHardwareContentProtectionTeardownStatus,非 RegisterVideoMemoryBudget*)。教训:**手工 COM 声明的 IID 与槽位必须逐项对权威源核(win32metadata generation/WinSDK/RecompiledIdlHeaders 的 dxgi.h/dxgi1_4.h、Microsoft Learn 结构体文档),「自定义常量」不等于「凭印象写」**。验证方式:本机无 Windows 宿主,以「SDK 头文件导出期望 IID/槽位表 + gcc 编译期 _Static_assert(offsetof(槽)==序号)+ 运行期 memcmp」自校验(harness 不进仓库),并对照修复前代码精确失败;语义仍须 Windows 真机验收(GPU 页卡片 / 显存曲线)。
  - 温度:仅 NVIDIA 经 nvidia-smi 子进程,虚拟成 `/sys/class/hwmon/hwmonN/{name,temp1_input,temp1_label}`(每卡一条,输入毫摄氏度),传感器页照常解析;AMD/Intel 温度不可用不硬造(不引 WinRing0 类内核驱动),机器上 hwmon 目录返回 NULL、传感器页为空属合法状态。nvidia-smi 首列总线地址与 DXGI 虚拟地址不同源,按第 6 列型号名与 desc.Description 匹配后重写首列完成对位(型号名是两者共同字符串来源;驱动改名的极端情形对位失败,该卡占用/显存/温度缺失,退化为 DXGI 静态信息)。
  - 子进程原语:CreateProcess+CREATE_NO_WINDOW+匿名管道读输出(hStdOutput/hStdError 同管),不用 _popen——GUI 进程下 _popen 的控制台子进程会闪黑窗;WaitForSingleObject 3s 超时兜底 TerminateProcess。nvidia-smi 结果 500ms 静态缓存(1Hz 下 hwmon 与 gpu_list 各消费一次,避免每秒两次子进程)。
  - 链接纪律:pdh/dxgi/iphlpapi/psapi/ntdll 一律 LoadLibrary+GetProcAddress,kernel32/advapi32 是 MinGW/MSVC 默认链接库直接调用——零链接参数改动,prebuild 托管不破。
  - monotonic 必须真实现(QueryPerformanceCounter):速率类指标全靠墙钟差值,原占位恒 0 会让差值分母恒 0。
  - 验证方式:本机无 mingw/MSVC 无法真编译 Windows 分支,以「最小 Win32 桩头 + gcc -fsyntax-only -Wall -Wextra」验语法与符号面零告警(桩头不进仓库),语义正确性由 CI Windows runner 真实编译 + Windows 真机五页验收(见 TODO.md SYS1 真机清单):重点核实 PDH PhysicalDisk/GPU Engine 计数器路径在中文 Windows 的行为、GPU Engine 的 LUID 聚合数值、nvidia-smi 与 DXGI 型号名匹配、无 N 卡机器传感器页空态。
- **Windows 进程管理语义归一(SYS2):kill / 优先级 / 错误码在 stub 内统一为 Linux errno 语义形态,MoonBit 层 errno_text 与 Result 零改动**。定案:①kill 首版映射 TerminateProcess 一档(SIGTERM/SIGKILL 同映射,UI 收敛为单按钮;TerminateProcess 发起后退出是异步的,短等 WaitForSingleObject 3s 让「已结束 N 个」的报告为真;温和结束 WM_CLOSE 方案后置)。②优先级映射 IDLE/NORMAL/HIGH/REALTIME 四档:set 就近钳制(≥10 IDLE / -9..9 NORMAL / -16..-10 HIGH / ≤-17 REALTIME),get 反查档位代表值(19/10/0/-10/-13/-20;BELOW/ABOVE_NORMAL 钳邻档),虚拟 /proc/[pid]/stat 的 nice 字段从恒 0 改为 GetPriorityClass 反查代表值(进程页 nice 列/排序随之真实)。③Win32 错误码在 stub 内译成 errno 编号:ERROR_ACCESS_DENIED→1(EPERM)、ERROR_INVALID_PARAMETER→22(EINVAL)、ERROR_PRIVILEGE_NOT_HELD/ERROR_SHARING_VIOLATION→13(EACCES)、ERROR_FILE_NOT_FOUND/PATH_NOT_FOUND→2(ENOENT)、NOT_ENOUGH_MEMORY/OUTOFMEMORY→12(ENOMEM)、INVALID_HANDLE→9(EBADF)、ALREADY_EXISTS→17(EEXIST)、BROKEN_PIPE→32(EPIPE),未列出归 EIO=5。④**OpenProcess 对已退出 pid 恒报 ERROR_INVALID_PARAMETER(87)**:不特判会把「进程不存在」显示成「参数非法」,kill/get/set 三入口统一特判 →ESRCH(3),与 Linux kill 不存在进程同语义。⑤REALTIME 档需 SeIncreaseBasePriorityPrivilege,普通用户 SetPriorityClass 报 ERROR_PRIVILEGE_NOT_HELD→EACCES,与 Linux setpriority 负值非属主报 EACCES 对齐。⑥UI 文案平台化(kill_button_labels / priority_ui / priority_result / priority_col_header 纯函数,platform 显式带参便于单测):Windows 单「结束进程(立即终止)」按钮、renice 消息显示档位名 + set 后回读代表值(离散档钳制后的实际值)、优先级列头标「优先级」;Linux 维持两档 kill 与连续 nice。⑦温度等不可用来源按位显示「—」:处理器卡「12% · —」、显卡卡「35% · —」/「— · 55℃」(原为省略对应位,用户分不清「没数据」与「还没刷新」),传感器页无来源时给「暂无可用温度来源」空态行。⑧平台探测新增 yue_sysmon_is_windows(编译期定,两分支各一份),不引 @yue.platform() 保持数据层自足。
  - **踩坑:桩头按代码形状定义会掩盖真实 SDK 的结构成员错误(SYS2 修正 SYS1 遗留)**:SYS1 的 PDH 原始值读取写成 `RawValue.FirstValue.largeValue`,而真实 pdh.h 的 `PDH_RAW_COUNTER.FirstValue` 是 LONGLONG(无 `.largeValue` 后缀,匿名 union 形态的是 `PDH_FMT_COUNTERVALUE` 的 FmtValue)——SYS1 的最小桩头按代码形状定义,`-fsyntax-only` 自然通过,CI Windows runner 真实编译必红。SYS2 修正为 `RawValue.FirstValue`,并把桩头按真实 SDK 形状写(FirstValue 为 LONGLONG、FmtValue 才是匿名 union);结论:桩头只验「符号面与语法」,结构体成员名/布局仍须逐成员对照真实 SDK,`-fsyntax-only` 零告警不等于能真编译。
  - SYS2 验证方式:本机无 Windows 宿主,Windows 分支以最小 Win32 桩头(按真实 SDK 形状定义,不进仓库)过 `gcc -fsyntax-only -Wall -Wextra` 零告警;touch stub 后 `moon build examples/sysmonitor` 零警告(sysmon.o 真实重编);`moon check` 零警告 + `moon test` 608 全绿(sysproc_wbtest 新增 8 条:errno_text 翻译目标值、四档档界、kill/优先级按钮与结果文案、列头、with_temp「—」占位、不存在 pid 的 get/set 归一 ESRCH);**实际终止 / REALTIME 提权行为必须 Windows 真机验证**(清单见 TODO.md SYS2)。
- **macOS 数据层(SYS3):Mach / libproc / getfsstat / getifaddrs / system_profiler 数据源在 stub 读取入口虚拟出与 Linux 同构的 /proc、/sys 文本,MoonBit 解析层与解析纯函数零改动(同 SYS1「Linux 路径即跨层契约」的定案);GPU 走 system_profiler -json 子进程、JSON 解析在 MoonBit 纯函数;磁盘 IO 速率与温度无来源,UI 按「—」边界显示**。七路映射与平台分流:
  - 平台分流:stub 三平台结构(`_WIN32` / `__APPLE__` / Linux),kill / 优先级 / statvfs / monotonic / page_size 走 POSIX 共享实现(macOS 与 Linux 同语义,进程管理 UI 两按钮与连续 nice 口径原样适用);CPU / 内存 / 进程 / 网络 / 挂载五路由到虚拟文本;MoonBit 层只开两处分支(`on_macos() = @yue.platform() == "macos"`):gpu_list 走 system_profiler 解析、DiskMonitor 容忍 /proc/diskstats 缺失。Mach / proc_info / statfs / if_data64 一律按 xnu 源码布局自声明(符号在 libSystem 默认链接范围),免 SDK 头版本差异——同 Windows 分支手工 vtable 与自定义 PROCESS_MEMORY_COUNTERS 的思路。
  - CPU:`host_processor_info(PROCESSOR_CPU_LOAD_INFO)` 每逻辑核 user/system/idle/nice 累计 tick,总行取各核求和,列序与 /proc/stat 对齐(iowait/irq/softirq/steal 无对应恒 0);tick 单位由 mach 自定,只用于差值比率,与 clk_tck 无关;返回缓冲必须 `vm_deallocate(mach_task_self_())`(1Hz 采样每拍一块,泄漏可积少成多)。型号 `machdep.cpu.brand_string`(Apple Silicon 亦实现)→ 回退 `hw.model`;主频 `hw.cpufrequency_max` 档(Hz→MHz,无该键回退当前档 `hw.cpufrequency`,再无键为 0,2026-11-13 真机补);核数 `hw.ncpu`。
  - 内存:`hw.memsize` 总量;`host_statistics64(HOST_VM_INFO64)` 取 free / inactive,可用 = free + inactive(活动监视器口径);swap 走 sysctl `vm.swapusage`(`xsw_usage` 布局 SDK 未公开,按通用定义自声明:total/avail/used 三 uint64 + pagesize + encrypted)。
  - 磁盘:`getfsstat(MNT_WAIT)` 全量挂载转写成 /proc/mounts 同构文本,过滤口径全部留在 MoonBit 侧——`is_pseudo_fs` 补 BSD 伪文件系统(devfs / fdesc / nullfs / volfs / union / synth,autofs 两平台同名),`is_system_mount` 补 macOS 系统宗卷(/private 即 swap 后备卷、/System/Volumes/{Preboot,Update,VM,Hardware,iSCPreboot,Recovery,xarts,Cryptexes};用户数据卷 /System/Volumes/Data 与 / 是同一块 APFS 容器(读数一致)并入黑名单,只留 / 一行,2026-11-13 真机补);挂载点可含空格(用户卷名),stub 按内核惯例 `\040` 转义、MoonBit 侧 `unescape_mount` 还原(不还原会按空白切错列、statvfs 失败后整行从容量表消失);容量复用 POSIX 共享 statvfs。**IO 速率无来源(IOKit 列远期)**:`/proc/diskstats` 读失败不再让整次 tick 失败(旧实现直接 return None 会让磁盘页整页空白),`DiskInfo.read_bps/write_bps` 由 Double 改 `Double?`,None 时 UI 显示「—」、IO 曲线不推点(不画一条假的 0 线);归属不到 diskstats 的挂载(NFS 等)同样 None,比旧实现恒显 0 B/s 更诚实。
  - 网络:`getifaddrs`(表带 200ms TTL 缓存——每块网卡 rx/tx 各读一次路径,1Hz 下无缓存会每拍两次全表拉取),`ifa_data` 指向 `struct if_data64`,`ifi_ibytes/ifi_obytes` 充当累计字节;每地址族一条按名字去重;loopback "lo0" 归一为 "lo"(main.mbt 的速率汇总排除按 "lo" 口径,同 Windows 分支对 Software Loopback 的处理)。
  - 进程:`proc_listpids(PROC_ALL_PIDS)` 枚举(NULL/0 探所需字节数 + 8KB 余量吸收两次调用间的新进程),pid 0(kernel_task)无命令行与计时,枚举时跳过;`proc_pidinfo(PROC_PIDTBSDINFO)` 取 ppid / nice / 状态 / comm,`PROC_PIDTASKINFO` 取线程数与纳秒计时(÷1e7 → 10ms tick,`yue_sysmon_clk_tck` 在 macOS 分支硬编码 100,与换算口径自洽);RSS 字节 ÷ 页数;`proc_pidpath` 全路径充当 cmdline(权限不足 / kernel_task 返回 NULL,MoonBit 层回退 [comm]);状态按 BSD p_stat 映射(SIDL→I / SRUN→R / SZOMB→Z / SSLEEP→S / SSTOP→T)。选 PROC_PIDTASKINFO 而非 proc_pid_rusage:一次调用同时拿线程数 / 双计时 / RSS,少一次系统调用。
  - GPU:`system_profiler SPDisplaysDataType -json` 子进程——fork + 匿名管道 + poll 超时(8s)后 SIGKILL,不用 popen(GUI 进程下 shell 子进程会闪窗,同 Windows CREATE_NO_WINDOW 的考虑),execv 绝对路径 `/usr/sbin/system_profiler` 免 PATH 搜索分配;首跑秒级,成功后进程内常驻缓存(型号 / 显存总量静态,同 Windows DXGI 枚举一次的思路),失败按 5s 退避重试;JSON 原样回传,MoonBit 侧 `parse_system_profiler_gpu` 纯函数解析(数组定位双形态——旧版顶层 `{"SPDisplaysDataType": {"_items": [...]}}`、新版 macOS 26 顶层键直挂数组无 `_items` 键,按锚点序试命中哪个用哪个,2026-11-13 真机补;对象切分按花括号深度、跳过字符串内括号,型号取 `sppci_model` 回退 `_name`,显存 `spdisplays_vram`,厂商按名字嗅探)。利用率与温度无来源(GPU 利用率无公开接口、SMC / IOReport 私有键列远期),busy / celsius 留 None,UI 按位显示「—」。
  - 温度:首版不显示(SMC / IOReport 私有键列远期),`/sys/class/hwmon` 在 macOS 自然返回 None,传感器页空态行与处理器卡温度位「· —」沿用 SYS2 既有口径。
  - 链接纪律:新增符号全部在 libSystem 默认链接范围,零链接参数;extern 声明须三平台都可链接——非 macOS 用同 ABI 占位返回 NULL(MoonBit 层 `gpu_list` 的 macOS 分支只在 `on_macos()` 为真时调用,运行期不会到占位),否则 Linux / Windows 的测试构建链接期直接失败(本次即因此补占位)。
  - **踩坑:Mach 常量与结构布局自声明前必须对照 xnu 源码核实**:`PROCESSOR_CPU_LOAD_INFO` 是 2 不是 1、`MNT_WAIT` 是 1 不是 2、`MAXCOMLEN` 是 16、64 位 `statfs` 的 `f_mntonname` 在 `f_mntfromname` 之前、`if_data64` 的字节计数叫 `ifi_ibytes/ifi_obytes`(无 `ifi_oobytes`)——这些凭记忆写错编译器不会报(自声明即真相),`-fsyntax-only` 只验语法与符号面,结构体偏移仍须逐成员对照真实 SDK(同 SYS2 教训);`host_statistics64` 的 count 语义是「小于 REV0 count 返回 KERN_FAILURE、大于则按低版本填」,故按当前 xnu 全字段布局传 40 个整数、多带字段安全。
  - **踩坑:`String::unsafe_get` 返回 UInt16(UTF-16 code unit)而不是 Char**:逐字符扫描 JSON / 转义串时 `c == '\\'` 直接类型不匹配,要么 `to_int()` 比较、要么对未处理区间成段拷贝(`write_stringview` + 切片,代理对安全),混用会踩「has type UInt16, wanted Char」。
  - 踩坑:宿主机时钟回跳会让 moon 增量构建把未来 mtime 的 `.o` 当最新,`touch` 源码不触发重编——验证 stub 改动时若 `moon build` 报 up to date,先删 `_build` 下对应 `.o` 再构建。
  - SYS3 验证方式:本环境无 macOS 实机。Linux 宿主 `moon check` 零警告 + `moon test` 614 全绿(syshw_wbtest 新增 6 条:unescape_mount 转义还原与非法序列、parse_mounts 的 macOS getfsstat 形态(含空格卷名 / BSD 伪文件系统)、is_system_mount 系统宗卷、parse_vram、json_string_value / json_items_objects 切分与嵌套、parse_system_profiler_gpu 双卡解析与宽容口径;DiskInfo 速率字段改 Option 后 S5 / S6 真实采样断言同步放宽为双形态);macOS 分支以 `gcc -fsyntax-only -Wall -Wextra -D__APPLE__` 零告警(只验语法与符号面,结构体布局按 xnu 源码逐字段核对,语义由真机把关);touch stub 后 `moon build examples/sysmonitor` 零警告;非 macOS 占位符号已核在 Linux 构建产物中导出。**七路数据与进程管理必须 mac 真机验证**(清单见 TODO.md SYS3):重点核实 host_processor_info 各核占用数值(顺序错会把 idle 当 user)、system_profiler -json 的键名与解析对位(sppci_model / spdisplays_vram / spdisplays_vendor,Apple Silicon 与 Intel / AMD 卡各测)、getfsstat 挂载表与 df 对照(含含空格卷名与 /System/Volumes/Data)、proc_listpids 进程数与 ps 对照、kill / setpriority 实际生效。
- **Linux GPU 利用率补全(SYS4):DRM fdinfo 聚合采样免 root 得全卡利用率(i915 / xe / amdgpu);点名域原表述「请求超管权限读显卡」经本机实证改为「免 root 数据源补全 + 提权边界显式化」**。定案:①**权限实证**(Ubuntu 24.04 uid 1000 本机实测):`/sys/class/hwmon/hwmon*/temp*_input` 与 amdgpu `gpu_busy_percent` 均 0444,DRM fdinfo 走 /proc 标准接口(本用户进程的 fdinfo 文件 r--r--r--),面板所需常规数据本就免 root;唯一受限的 `/sys/kernel/debug/dri`(debugfs,drwx------ root)是 i915 调试视图(per-engine / per-client 细分),并不含面板所需指标——「请求超管权限读显卡」没有数据支撑,polkit / pkexec 集成暂不做(若用户坚持提权路线再单独排批)。②占用来源优先级:nvidia-smi(N 卡)> sysfs `gpu_busy_percent`(amdgpu,驱动侧全卡均值、覆盖全部客户端)> DRM fdinfo 聚合(i915 / xe / amdgpu 兜底);显存 / 温度口径不变。③fdinfo 聚合口径:枚举 `/proc/<pid>/fdinfo`,解析 `drm-driver` / `drm-pdev` / `drm-client-id` / `drm-engine-*`(全部引擎求和),按 (设备键, client-id) 归并(dup 的 fd、fd 经 unix socket 跨进程传递是同一个 drm_file、累计值相同,只取最大一次),两次采样差值 / 墙钟折算全卡利用率(0..100 钳制)——与 intel_gpu_top / nvtop 同源。④归属:`drm-pdev`(内核 ≥6.5,PCI 槽位地址与 sysfs 设备目录名同形)优先;老内核无该键,按 `/sys/bus/pci/devices/<addr>/uevent` 的 `DRIVER=` 驱动名回退(双同驱动卡会合并成同一值,已知边界)。⑤扫描只在「有显卡既无 sysfs 占用也无 nvidia-smi 覆盖」时才做:AMD / NVIDIA 机器整拍免扫,Intel 机每拍扫(nvtop / intel_gpu_top 同款成本)。⑥首帧无前样本不出数(次帧起),新客户端首现那帧不计;数据层入口由 `gpu_list()` 改为 `GpuMonitor::tick()`(前样本状态随 App 常驻,macOS 分支不变)。
  - **版本边界(对照 torvalds/linux 源码逐版核实)**:`drm-engine-*` / `drm-driver` / `drm-client-id` 自 v5.19 起(amdgpu / i915 "Convert to common fdinfo format v5",2022-05-26,v5.18 无 / v5.19 有);`drm-pdev` 自 v6.5 起(`drm_file.c` 的 `drm_show_fdinfo` 里 `dev_is_pci` 分支,v6.4 无 / v6.5 有,格式 `%04x:%02x:%02x.%d`);cycles / maxfreq 类 6.2 起(本轮不消费)。Ubuntu 22.04 的 5.15 内核无引擎统计键 → busy None 显示「—」;24.04 的 6.8 三者全有。
  - **已知边界(诚实口径,来源不可用即显示「—」)**:①fdinfo 只覆盖本用户进程——他人进程(root 服务 / 其他登录用户)的 `/proc/<pid>/fdinfo/<fd>` 读返回 EACCES(实测 `/proc/1/fdinfo/1` 权限不够),整卡利用率是「本用户可见口径」,会低估;全量统计需 root(polkit 暂不集成)。②扫描成本实测:全 /proc fdinfo 扫描 9123 个文件、4.2MB,约 56ms/拍(与 stub 同款读取循环的 C 程序实测,554 进程桌面;Python 同口径 78ms)。③短命客户端在两次扫描间开闭,其忙时间随客户端消失而丢失( fdinfo 计数器挂在客户端上)。④多引擎并行(gfx + compute 同时跑)合计可超墙钟,钳到 100。⑤计数器非单调更新(内核规范允许)按 0 增量。
  - **踩坑:解析必须排除 `drm-engine-capacity-<name>`**:i915 多视频引擎时打印并行引擎数(如 `drm-engine-capacity-video: 2`),按 `has_prefix("drm-engine-")` 收集会把引擎数(2)当成 ns 累加进忙时间;值侧同理要取首个空白分隔字段再 parse_u64——引擎值带 ` ns` 后缀、旁支键值带 ` KiB` 单位(`drm-memory-vram: 1024 KiB`)、`drm-memory-gtt: ` 冒号后还多带一个空格(amdgpu 源码原样),不取首字段直接 parse 必失败。
  - 踩坑:/proc 目录枚举条目含 `cpuinfo` / `self` / `irq` 等非进程条目,须纯数字过滤后再进 fdinfo;amdgpu 零用量引擎不打印(源码 `if (!usage[hw_ip]) continue;`),条目里只有非零引擎,求和口径不受影响;i915 gen<8 早退不打引擎键 → 解析为 None,busy 显示「—」。
  - SYS4 验证方式:stub 零改动(纯 MoonBit 侧,复用 read_text_file / list_dir 两类原语)。Linux 宿主 `moon check` 零警告 + `moon test` 623 全绿(syshw_wbtest 新增 9 条:parse_drm_fdinfo 的 amdgpu / i915 / None 三形态、is_drm_engine_key 与 drm_device_key、drm_clients_total 归并(dup fd / 跨进程 / 双设备 / 缺 client-id)、drm_busy_percent(首帧 / 回落 / 钳 100)、is_pid_entry、parse_uevent_driver、fdinfo 真实采样两拍);删 `_build` 下 sysmonitor `.o` 后 `moon build examples/sysmonitor` 零警告。**i915 / xe / amdgpu 真机验证由用户执行**(本机为 NVIDIA 专有驱动机,无 fdinfo 用量统计、无法实测此路):①Intel 集显占用与 `intel_gpu_top` 同窗口对照②AMD 独显 sysfs `gpu_busy_percent` 与 fdinfo 双源对照(应优先 sysfs)③双卡机(iGPU + dGPU)归属正确性(drm-pdev 优先)④老内核(<6.5)驱动名回退归属⑤短命 GPU 客户端(反复起停的跑分程序)利用率是否漏计⑥本用户口径与 `sudo intel_gpu_top` 的差异量级⑦扫描耗时对 1Hz 采样占空的影响。
- **Linux GPU 型号名解析(SYS5):AMD / Intel 卡经 pci.ids 显示商业型号名——sysfs 只有数字 id(vendor / device 节点)与驱动绑定名,商业型号名不在任何 /sys 节点中,免 root 纯文本数据库是唯一来源;查不到回退 device id 原文显示**。定案:①来源优先级:nvidia-smi 命中(N 卡,型号名比 pci.ids 更具体,如 smi 的 "NVIDIA GeForce RTX 3070" vs pci.ids 的 "GA104 [GeForce RTX 3070 Lite Hash Rate]")> pci.ids 按 vendor:device 查 > device id 原文(「0x7480」,至少可区分多卡);sysfs 读取失败的占位 id("(未知)")留空,UI 不显示型号位。②路径差异:hwdata 包装 `/usr/share/hwdata/pci.ids`(不少发行版里它是指向 misc 的符号链接)、pciutils 包装 `/usr/share/misc/pci.ids`,依次尝试;两路都不可达(未装数据库 / Flatpak 沙箱 / 非 Linux)按「查不到」兜底。③缓存:pci.ids 全文首次用到时读入常驻(约 1.4MB,在 native-stub 单文件 16MB 上限内),解析结果按 PCI 地址常驻——实测单次全文查找约 14ms(`moon test` debug 构建;Intel vendor 在 27868/38108 行,早退也要扫七成文件),1Hz 每卡每拍重扫不可接受;vendor:device 是静态硬件信息,首拍查一次即可,库不可达时常驻的是回退值、重启后重试。④UI:型号名拼进传感器页小节标题(既有 gpu_label 路径,page_sensors.mbt 零改动),概览页卡片只显示紧凑数值、型号归详情页。
  - **pci.ids 格式实测(2024.03.31 版,38108 行)**:无缩进行 = vendor(4 位十六进制 id + 两空格 + 厂商名),单 Tab 行 = 该 vendor 的 device,双 Tab 行 = subsystem(本面板不消费),'#' 起 = 注释;vendor 2378 个、device 18685 条、subsystem 16258 条;全文无 CRLF、无行尾空白、id 全部恰为 4 位小写十六进制;7 个空行全在文件头注释区与 class 节内(现代版本 vendor 块之间不空行);末尾 class 节("C 00" 起)与 vendor 行同形,但 id 非四位十六进制,自然不匹配;"ffff Illegal Vendor ID" 是最后一个 vendor 且无 device 行、紧接 class 节——查它正好验「出节提前返回」。
  - **踩坑:空 id 归一化不能补零**:`norm_pci_id("")` 按「左补零到 4 位」会补成 "0000" 假有效 id(单测首跑即抓出),空串须保持空串;sysfs 读取失败时 vendor / device 是 "(未知)" 占位串,靠 is_hex4 挡掉后才能走回退。
  - 踩坑:型号名整段保留内部空格与方括号(如 "Navi 33 [Radeon RX 7700S/7600/7600S/7600M XT/PRO W7600]"),不能按空白切 fields 再 join(当前版本名称内含双空格虽为 0 条,按整段切片才是正解);切片按 UTF-16 码元索引(`StringView::exact_view` 的基准),不能用 `iter2` 的码点索引——结构性字符全是 ASCII,代理对只可能出现在名称里;device 行有条目但无名称(真实库不出现)不当命中,继续扫、按查不到回退 id。
  - SYS5 验证方式:stub 零改动(纯 MoonBit 侧,复用 read_text_file 一类原语)。Linux 宿主 `moon check` 零警告 + `moon test` 628 全绿(syshw_wbtest 新增 5 条:norm_pci_id / is_hex4 归一化与判定、pci_ids_device_name 缩进层级解析(subsystem 跳过 / 跨 vendor 不串 / 无 device 行 vendor / class 节 / 出节提前返回 / 非法 id)、gpu_model_name 四形态(smi 优先 / 库命中 / 库不可达与无条目回退 id / 占位 id 留空)、GpuMonitor::gpu_model 常驻缓存与 smi 优先、真实 pci.ids 采样(动态取首对 vendor/device 正向断言 + 无 device 行的 dead vendor 负向));删 `_build` 下 sysmonitor `.o` 后 `moon build examples/sysmonitor` 零警告;本机(Ubuntu 24.04,NVIDIA 专有驱动机)实测三对真实条目解析正确(1002:7480 → Navi 33、8086:3ea0 → WhiskeyLake-U GT2、10de:2488 → GA104)。**AMD / Intel 真机验证由用户执行**:①AMD 独显传感器页小节标题显示商业型号名(与 `lspci -nn` 对照)②Intel 集显同上③双卡机(iGPU + dGPU)两块各显示各的型号④查不到(极新卡 / 数据库缺条目)时回退显示 device id 而非空白⑤最小化安装(无 hwdata / pciutils)与 Flatpak 沙箱下的回退形态⑥其它发行版路径差异(Fedora / Arch 的 hwdata、openSUSE 等)⑦长型号名在小节标题的换行 / 溢出观感。
- sysmonitor 界面文案纪律(整批界面打磨实测):界面文字只说「是什么 / 怎么用」,不写数据口径与实现路径(如 /proc 路径、两次差值、毫摄氏度换算、"nvidia-smi 后置"这类计划说明);速率 / 容量 / 坐标轴一律多级单位动态换挡(B→K→M→G),数值保持短,大号数值卡(24px)尤其忌换行溢出卡片。
- sysmonitor 概览页卡片范式对标 Mission Center(资源管理器式):图标 + 标题、规格副标题(CPU 型号 / 总容量 / 挂载点等硬件规格放卡片副标题,不在窗口顶层占副标题行)、当前值行(占用% · 温度、已用 / 总量 · swap 等组合)、卡内迷你曲线(序列末窗 + 末端圆点;值域固定 0-100 或峰值自适应,双序列同窗叠加如网络 rx/tx)。卡片 flex 均分、同排 stretch 等高,随窗口伸缩;单卡自包含,不看窗口其他部分也能读懂。
- xrandr 输出格式随版本变化(显示器枚举实测):1.5.2 起把刷新率标记('*' 当前 / '+' 首选 / 'i' 隔行)中的 '+' 打成独立 token 且位于被标记刷新率之后(`59.95 +  75.00`,经 xrandr --verbose 证实 59.95 为该 +preferred 模式),旧版直接附着在刷新率尾部(`59.95+`)。mon_fold_marker_tokens 把独立标记 token 回贴到前一 token 尾部统一为附着形态后再解析。
- **进程数据两处正确性缺陷(EX2,高危):负 nice 全显 0、新出现 pid 当拍 CPU% 钉满格**。①`/proc/[pid]/stat` 的 nice 是**有符号**字段(-20..19),而解析用的 `parse_u64` 遇负号整字段返回 None → `unwrap_or(0)` 把负 nice 静默变 0:进程页 nice 列显示失真,ByNice 排序也失真(本机 142 个负 nice 进程,kworker 系全部 -20,是日常就存在的量而非边角)。修法:同一处解析内按字段符号选解析器——无符号字段(utime/stime/starttime/rss_pages)走 `parse_u64`,有符号字段(nice/ppid/threads)走现成的 `parse_i64`,字段序号与取值口径零改动。②`ProcMonitor::tick` 的差值前样本用 `self.prev.get(pid).unwrap_or(0)`:**采样间隙新出现的 pid**(启动新进程、`moon test` 自身起的子进程)本拍没有前样本,却按「前样本 tick = 0」参与差值,把该进程开机以来的全部累计 tick 当成本拍增量 → CPU% 直接顶到 cores×100 钳制值(白盒对照实测 `400 != 0`,即单拍假满格),下一拍才回落真值。修法:差值前样本改为可空,抽成纯函数 `proc_tick_cpu_pct(prev : Int64?, cur, clk_tck, wall_s, cores)`,prev 缺失时本拍直接给 0(与「首帧无前样本给 0」同一口径),`tick` 只传 `self.prev.get(pid)`;有前样本时分派到既有 `proc_cpu_pct`,行为不变。
  - 踩坑:`parse_u64` / `parse_i64` 的失败都收敛成 `unwrap_or(0)`,`None` 与「真的是 0」在调用侧不可区分——有符号字段用错解析器不会报错、只会静默给出错值,是这类缺陷能长期潜伏的原因;按字段符号显式选解析器比「一个 num() 通用」更稳。
  - 踩坑:CPU% 差值类指标的「无前样本」必须与「前样本为 0」区分开。前者是「不知道」,后者是「确实从 0 开始」;用 `unwrap_or(0)` 把前者混成后者,对**单调累计计数器**(tick/字节/扇区)必然产出「开机至今全量」的假增量,且被钳制逻辑掩盖成「满格」而非明显异常,肉眼难以归因。
  - 验证方式:stub 零改动(纯 MoonBit 侧)。`moon check --deny-warn` 零警告 + `moon test` 644 全绿(sysproc_wbtest 新增 3 条:parse_proc_pid_stat 负 nice 真实样本(取本机 /proc/4/stat 的 kworker/R-rcu_gp nice=-20 逐字段断言,外加 nice=-1 / 19 / 裸负号兜底)、sort_procs 的 ByNice 负值升降序(-20/0/19 三档不再混档)、proc_tick_cpu_pct 无前样本当拍置 0(与有前样本满负荷/半负荷/钳制/墙钟无效/负增量各形态对照));删 `_build` 下 sysmonitor `.o` 后 `moon build examples/sysmonitor` 零警告;白盒对照——暂存修复前代码跑 `moon test -p sysmonitor`,负 nice 用例精确失败(`0 != -20`)、把 `proc_tick_cpu_pct` 改回旧语义后 tick 用例精确失败(`400 != 0`),恢复修复后 24/24 通过;真实 /proc 端到端用例(强制起短命进程填满 2s 窗口)实测新出现 pid 的当拍 CPU% 恒 0。

### 系统能力数据层(音量 / 亮度 / 浏览器历史 / VS Code 历史 / 应用查找)

本批新增五模块(yue/volume、brightness、browser_history、vscode_history、appfind),实测环境 Ubuntu 24.04 + XFCE + X11、PipeWire 音频栈、Chrome 多 profile、VS Code(OSS 官方发行版)。以下为本批真机实测沉淀:

- 音量双后端实测(wpctl 优先、pactl 回退):wpctl `get-volume @DEFAULT_SINK@` 输出形如 `Volume: 0.42 [MUTED]`,sink 显示名取 `wpctl status`(层级文本,取 Audio 段 Sinks 首个);pactl 路径三次查询(get-default-sink + get-sink-volume + get-sink-mute)。**pactl 的可读输出按 locale 本地化**(中文环境输出「音量:」而非 "Volume:"),按英文文案写的解析在本地化环境必挂——子进程环境必须固定 `LC_ALL=C`(vol_env_blob 同时传 PATH、XDG_RUNTIME_DIR、HOME:PipeWire/Pulse 套接字定位靠 XDG_RUNTIME_DIR,缺了工具连不上服务、退出码非 0)。样例断言用实机采集文本(volume_wbtest,pactl 样例即 LC_ALL=C 下输出;出现本地化文案即视为解析失败)。
- 浏览器历史直读 Chrome 系 SQLite 库(moonsqlitefile 纯解析,无 SQLite FFI、不开锁、不复制原库):①时间基准是 1601-01-01 UTC 起微秒(Windows FILETIME 同源),Unix 毫秒 = µs/1000 − 11644473600000,实测样本 13435769563030519 → 2026-10-06T14:12:43.030Z;②urls 表 id 列虽是 INTEGER PRIMARY KEY,磁盘记录里存 **Null**(rowid 别名不落盘),按列序取值不能假设类型;③hidden 列非 0 是重定向等隐藏条目须滤除;④Chrome 运行中的新写入落库的 -wal 文件,当前实现只传主库文件给 open_database(未做 WAL 合并,moonsqlitefile 另有 open_wal_database 可接);⑤探测读入的库字节直接作打开输入,同一库不读第二遍(History 库常达数十 MB)。
- VS Code 本地历史:①`User/History/<hash>/entries.json` 的目录名哈希是 31 进制滚动哈希(种子 149417,Int32 回绕),输出**有符号**小写十六进制——负值目录名真实存在(实测 `-10b5e510`),按资源 URI 复算三例(正数/负数/vscode-userdata 方案)全部命中;②entries.json 部分条目**无 source 字段**(实测),解析不能假设必有;③storage.json 的 windowsState:lastActiveWindow 在前 + openedWindows 数组,窗口对象有 folder(普通文件夹)与 workspaceUri(.code-workspace)两种形态,URI 百分号编码(空格 `%20`、中文 `%E4%B8%AD`)须解码;④端到端仅在存在 VS Code 用户数据的环境执行(vsc_supported 门控),纯逻辑层全部在内存样例上白盒断言。
- 亮度:设置走 logind 的 SetBrightness(系统总线 session/auto 对象,@traybus 层),枚举与当前值走 /sys/class/backlight sysfs 只读——logind 不在线时 set 报 Unsupported 而 devices/get 仍可用;键盘背光在 leds 子系统(设备名形如 `inputN::kbd_backlight`)。sysfs 值文本解析容忍首尾空白与尾换行。
- 应用查找(appfind):desktop entries 无目录枚举原语,`appfind_installed_with` 由调用方注入列举函数,默认便捷入口因恒空已裁撤(名不副实);`appfind_executable` 命中判定为整文件可读(read_binary_file),大体积可执行文件全量读入仅判存在是已知取舍(修需新增原生 stat 原语,暂不动 shim)。
- 默认应用查询(defaultapps,补清单遗漏):①查询走 `xdg-mime query filetype/default`,关联枚举直读三层 mimeapps.list(`~/.config` → `~/.local/share/applications` → `/usr/share/applications`,即 XDG mimeapps 规范优先级),不依赖命令的路径全用 read_text_file 薄解析;②**mimeapps.list 的同名键多行是候选列表,与 .desktop INI 的「首键生效」口径相反**——`[Default Applications]` 同一 MIME 写多行是「后写覆盖先写」的多候选登记,da_parse_mimeapps 因此不去重同键,da_default_for 回退路径取该 MIME 最后一个候选的段首值;③`xdg-mime query default` 对未登记类型**返回空串且退出码 0**(不是非零退出),「无默认」只能判空输出,不能靠退出码;④设置为「读-改-写回」~/.config/mimeapps.list 的 `[Default Applications]` 段:已有该行替换、无该行段内追加、无段文末补段,写文件用 write_text_file(同包 FFI,autostart 同款);⑤libyue 原生 Notification 无进度接口(vendor 头 notification.h 仅 title/body/info/silent/image/actions,shim 无对应 FFI),Linux 通知进度标准在 freedesktop hints 的 `value` 字段(走 traybus D-Bus 可实现)——本批确认原生通知能力已够用,未做进度条,后续若需要走 D-Bus Notify + a{sv} hints。
- 浏览器历史 / VS Code 历史的真机验证入口:NoahLiu/gui-examples/systemprobe 示例(图表 + 系统能力一板),`moon run NoahLiu/gui-examples/systemprobe` 点「读取系统能力」按钮逐项呈现五模块真实结果。

#### 影音与桌面控制命令路线(pr_run 统一封装,含 MPRIS 总线回退)

本批命令行类模块全部经 `yue/procrun.mbt` 的 `pr_run`(spawn → 限时回收 → 临时文件捕获 stdout/stderr),不自行 spawn;环境固定 C locale,退出码 0 归一 Ok、非零归一 Err 带 stderr,调用方不再自行判码。**命令缺失的语义**:Unix 下 shell 以退出码 127 呈现,由各模块自己的 `*_supported()` 探测归一为 Unsupported(pp_profiles / prt_default / nl_supported / win_list 各自探测自身命令),调用方按错误值分类,不用文本猜。命令路线与降级链:

| 能力 | 首选路线 | 降级路线 | 探测方式(只读无副作用) |
|---|---|---|---|
| 夜间色温 nightlight | `redshift -P -O <K>`(2500K..6500K,一次性设) | `xrandr --output <输出> --gamma R:G:B`(红 0.85..1.00 微提、蓝 1.00..2.20 衰减,绿恒 1.00) | `redshift -V` 退出 0;否则 `xrandr --query` 可用(无已连接输出 → Unsupported,无头环境) |
| 显示器配置 monitor | `xrandr --query` 全量解析(刷新率厘赫兹整数) | 无(不可用即 Unsupported) | 同上,一条 `--query` 只读探测 |
| 壁纸 wallpaper | XFCE `xfconf-query -c xfce4-desktop -p /backdrop/.../last-image`(读 / 写) | GNOME `gsettings get/set org.gnome.desktop.background picture-uri`;KDE `qdbus6/qdbus org.kde.plasmashell evaluateScript`(未真机验证) | DE 识别复用 @traybus.detect_desktop(XDG_CURRENT_DESKTOP),未知 DE → UnknownDesktop 带原文 |
| 窗口管理 windowctl | `wmctrl -l` 列表 / `-i -a <id>` / `-ic <id>` | 无(非 Linux 或 wmctrl 缺失 → Unsupported) | 命令缺失以 127 呈现 → Unsupported |
| 剪贴板监听 clipboard_watch | `xclip -selection clipboard -o`(只读轮询) | 无 | 同上,读失败(未装 / 选区无文本)静默跳过该拍 |
| 电源计划 powerprofile | `powerprofilesctl list / get / set` | 无 | 命令缺失 → PpUnsupported;list 输出保留后端序(推荐序在前时即推荐序) |
| 打印机 printer | `lpstat -p / -d / -o <打印机>` + `lp [-d 打印机] -n 份数 文件` | 无 | lpstat 缺失(未装 CUPS)→ PrtUnsupported |
| 磁盘卷 disk | udisks2 D-Bus(系统总线) | `lsblk --json`(仅枚举,挂载卸载不可用) | NameHasOwner 或 Manager 调用可达 |

MPRIS(媒体控制)是这族里唯一「总线优先、命令兜底」的倒置路线。接口要点:播放器实例经会话总线 `org.freedesktop.DBus.ListNames` 应答里过滤 `org.mpris.MediaPlayer2.` 前缀(含 playerctld 代理实例,一并收),对象路径恒 `/org/mpris/MediaPlayer2`,接口 `org.mpris.MediaPlayer2.Player`;播放控制 Play/Pause/PlayPause/Next/Previous/Stop 全为空参方法(应答空),状态读 `org.freedesktop.DBus.Properties.PlaybackStatus` + Metadata 字符串字段 title/artist/album。**总线调用失败才回退 playerctl**(`playerctl --version` 退出 0 判定可用),回退路径用 `-p <player>` 指定实例、读取用 `metadata --format <US>title<US>artist<US>album<US>`(US 分隔符界定,标题含分隔符的场景按首段切分,已知取舍)。探测口径:media_supported 以 ListNames 通为准,总线不可达才看 playerctl。播放控制属设置类,不在探测里触发。

#### 音频与视频(FRAME → draw_image 渲染路线)

- 音频:集成 `CorvusCinereus/miniaudio@0.4.0`(miniaudio 的 MoonBit 封装,产物体积小、ABI 面=引擎+剪辑两组)。链接验证:同样本 prebuild.py 托管体系,moon add 后 moon build 全仓通过,与 subproc/moonsqlitefile 的 native stub 共存无冲突;该包自身 moonbuild 无 supported_targets 声明(第三方包的告警,非本项目问题)。headless 真机冒烟(本机 XFCE + PipeWire):引擎可建、`/usr/share/sounds/alsa/Front_Center.wav` 可加载、volume 读写在 0.5 附近成立;播放/停止属设置类未在测试执行。
- 视频画面渲染路线:**libyue 的 Image 没有裸像素构造入口**(查证 vendor/libyue/include/nativeui/gfx/image.h:构造只有 Image(NativeImage, scale_factor) / Image(FilePath) / Image(Buffer, scale_factor),其中 Buffer 只吃 PNG/JPEG 编码),Canvas/Painter 也无像素写接口。故视频帧走「帧源回调 → pngr_encode_rgba 内存 PNG 编码 → Image::new_from_png 解码 → draw_image 铺满」。PNG 编码为纯 MoonBit(签名/IHDR/IDAT/IEND + CRC32 + Adler32 + zlib stored 块,CR 表与累计全程 Int64 运算——MoonBit Int 的 >> 是算术右移,反射表需要逻辑右移,Int64 非负值的 >> 即 32 位逻辑右移)。
- **PTREF**:headless 测试环境(moon test)里 Image::new_from_png / new_from_file 一律返回空图——无 GUI 上下文(GTK 未初始化)时 libyue 解码恒失败,实测本机真实 PNG(`/usr/share/icons/hicolor/48x48/apps/*.png`)同样 is_empty=true。因此 PNG 编码器的 wbtest 全部为字节级自校验(魔数/IHDR 字段/IDAT stored 块数/总长自洽/adler 尾部),Image 真机解码验证改由 systemprobe 示例承担。
- 视频组件与解码器解耦:VideoFrameSource 回调(帧号→RGBA)注入,moonav1(纯 MoonBit AV1 解码器,mooncakes)作为下一批帧源实现接入;H.264 需 ffmpeg,暂无 MoonBit 绑定,留待需要。
- 帧推进用 @yue.set_timer(无取消句柄,句柄持 Ref 开关,停止后回调返回 false 注销,复用 charts_effectscatter 的 EffAnim 模式);set_progress/媒体轮询同款模式。

#### 媒体状态监视(MPRIS 轮询增量)与通知进度(正文字符条)

- 环境:Ubuntu 24.04 + XFCE + PipeWire(pipewire-pulse)。MPRIS 的 org.freedesktop.DBus.PropertiesChanged 信号可订阅,但订阅需要常驻读循环,与本库「同步请求-回复 socket 事务 + set_timer」的调用模型不兼容(通用 D-Bus 层 gdbus_call 是同步往返,无异步读线程)。故 media_watch_status 走轮询增量:默认 1000ms 读一次 PlaybackStatus + Metadata,播放态 / 标题 / 艺术家 / 专辑任一变化即 on_change;首轮只建基线不触发;查询失败(总线错误 / playerctld 掉线)的轮次静默跳过不影响后续。
- 目标解析:player 参数为空时每轮重试解析首个播放器实例(media_players 失败即跳过本轮),实例出现后锁定;播放中切换播放器不会自动跟随,使用文档已写明。
- 停止语义:set_timer 无取消句柄(只能让回调返回 false),句柄持 Ref[Bool],media_watch_stop 置 false 后下一帧注销,不可恢复——复用 charts_effectscatter 的 EffAnim 同一模式。已知取舍:on_change 回调抛异常会中断该定时器(无 try/catch 保护是 MoonBit unused_try 检查的取舍),文档已注明。
- 真机冒烟:本机无 MPRIS 播放器,watch 启动后立即 stop,on_change 触发 0 次且全程无异常(media_wbtest.mbt 冒烟用例,12/12 通过)。
- 通知进度:freedesktop 通知协议无进度字段(Windows / macOS 原生进度呈现也各自为政),跨平台一致做法是正文内字符条 + 百分比。notification_progress_text 把 percent 钳到 [0,100],NaN 经 percent!=percent 检测按 0 处理,width<=0 只给百分比,格数四舍五入(+0.5 后 to_int);Notification::set_progress 正文=原文字 + 换行 + 进度行。

#### Firefox places.sqlite(纯读取,非 WAL 合并)

- places.sqlite 常处 WAL 模式:最新浏览记录还在 places.sqlite-wal / -shm 里,主库文件是旧快照。当前实现只把主库文件字节交给 moonsqlitefile 的 `open_database`,**尚未 WAL 合并,checkpoint 进主库的最新记录读不到**——这是已知边界,文档须写明「读数是读入时刻的主库快照」。补法(未做):moonsqlitefile 另有 `open_wal_database` 可接,需同时把 -wal 文件交给同一 Database。
- 表与列:`moz_places` 是唯一需要的表,取列 `url`(TEXT,主键为 id 但行解析不依赖)、`title`(TEXT,可为 NULL)、`last_visit_date`(INTEGER,**Unix 纪元微秒**——与 Chrome 的 1601 微秒不同源,ffx_time_to_unix_us 换算毫秒 = us/1000)、`hidden`(INTEGER,非 0 的是书签/收藏条目须滤除,口径同 Chrome)。
- 行解析按列序取值但**类型不做假设**:url 可能是 Blob(SQLite 动态类型,title/url 理论上都可能是 BLOB 存储),BhValue 各分支都要有兜底(ffx_parse_places_row 对非文本值返回 None 跳过该行)。
- profile 定位:`~/.mozilla/firefox/profiles.ini` 取 `Path=` 目录名(分节 [Install*]/[Profile*] 都可能有 Path,全部收),缺失时回退固定候选名(default / default-release / default-esr / default-nightly / dev-edition-default)——**随机前缀命名的 profile 目录(如 `a1b2c3d4.default-release`)只有 profiles.ini 收得到**,本包无目录枚举原语时这是硬边界(fsx_list_dir 落地后可扫目录补齐)。
- 条目类型复用 browser_history 的 `HistoryItem`(字段结构与 Chrome 历史完全一致),排序 / 截断 / 取列也复用 bh_sort_history / bh_take / bh_value_text / bh_value_int,不重造一套。
- 多 profile 聚合口径与 Chrome 侧一致:同一 url 在不同 profile 各出现一次,不去重(去重反而掩盖「多账号分别在两个 profile」的事实)。

### 系统信息(si_machine / memory / uptime)与系统级安全边界

- /sys/class/dmi/id/product_serial 多数发行版仅 root 可读,读不到给 `Err` 带路径,不用空串糊弄;/proc/meminfo 单位恒 kB,MemAvailable 内核 ≥3.14 才有,缺失回退 MemFree;uptime 是浮点秒直接返回。
- 传感器(iio-sensor-proxy)取值前必须 ClaimLight/ReleaseLight,不点灯的读数停在旧值;AccelerometerOrientation 的类型是字符串而非枚举整数。

### 显示协议

- X11 ✅ 主链路;Wayland 未支持,验证 GUI 行为用 X11 会话(托盘 / 快捷键已按会话守卫)。
- 用户空闲秒数走 X Screen Saver Extension(XSS)的 XScreenSaverQueryInfo,运行期 dlopen("libXss.so.1"/"libXss.so") 而非构建期链接:规避 libxss-dev 进分发链(预构建静态库随 mooncakes 分发,多一个动态依赖在消费端未必装);XScreenSaverInfo 结构极简,shim 里手写镜像结构体(idle 毫秒字段偏移 24),加载失败与无 X 同路径返回 Unsupported。
- XWayland 会话输入事件不进 X 服务端,XSS idle 读数虚高(用户刚动过也可能读到小时级):显式探测 WAYLAND_DISPLAY 置位即返回 Unsupported,给错数不如不给;env -u DISPLAY(无 X 会话)同样 Unsupported,均不崩。数值对照实测(Ubuntu 24.04 XFCE X11):idle_seconds 与 xprintidle 同刻双读差 17ms(判据 ±2s),xdotool 模拟鼠标移动后 0.317s vs xprintidle 320ms。
- 锁屏不算输入:XSS 的 idle 在锁屏期间持续增长(锁屏器不上报输入),「用户空闲」与「屏幕锁定」是正交维度,勿用 idle 阈值近似锁屏判定(锁屏事件走 logind,另批落地)。
- 空闲读数的演示交互:点击本身是输入事件,会重置 XSS 空闲计数——「点按钮读当前空闲」的演示自相矛盾(读到的恒为 0.x 秒;命令行探针/xdotool 外部读数测不出此交互矛盾)。正确形态是开关开启后定时刷新(每秒读一次),开关关闭定时器下一拍自行停止(libyue 定时器无取消 id,回调查开关状态自杀)。

### GTK 相关

- Table 放进 Notebook 页签会在尺寸测量时段错误(negative allocation):放普通容器或独立窗口。
- 内容型控件(Group / Scroll)继承 View 而非 Container:挂内容用 `SetContentView`,`AddChild` 会被类型校验拒绝。
- 上游 NUContainer 缺陷(补丁 `patch_linux_container_events`):①事件窗口 map 即 raise,截走子原生控件命中(页签点不动、滚轮失效)→ 改 `gdk_window_show_unraised`;②容器 preferred 尺寸硬编码 0、Scroll 的 size_request 为 0×0 → 宽度随视口、高度取内容 yoga 自然高度。不要向 GTK 报告 yoga 动态自然尺寸:allocate 会污染 yoga 状态,requisition 震荡不收敛。
- `UpdateChildBounds` 开头的可见性守卫会错过 GTK 首次 size-allocate(发生在 map 之前):布局计算须无条件执行。
- `Slider::SetValue` 对相同值也置 ignore 标记,吞掉用户首个回调:仅值变化才设标记。
- `ProgressBar::SetValue` 在 Linux 与 Windows 端语义均为 0..100,yue 层统一 0..1,换算分支须覆盖两平台。
- `View::GetBoundsInScreen` 在 Scroll / 嵌套容器下坐标叠错(补丁 `patch_linux_view_bounds_in_screen`):GTK 屏幕坐标必须「客户区原点(`gdk_window_get_origin`)+ 客户区内偏移(`gtk_widget_translate_coordinates`)」;`gtk_window_get_position` 含标题栏装饰,与 translate 混用必差一个装饰尺寸。
- 表格 Checkbox 列指示器随行高缩放(XFCE 主题):对 Checkbox 列显式 `indicator-size=16`,renderer 高度限 20。
- 拖出数据须用 `Data(std::vector<base::FilePath>)` 构造(string 构造会被静默降级为 Text);相对路径先绝对化(`g_filename_to_uri` 不收相对路径)。
- 拖拽预览图 hotspot 上游写死 (0,0),补丁改图片中心对齐光标(`patch_linux_drag_icon_hotspot`)。
- 拖放能否接收由 drag-motion(`handle_drag_update`)决定,`handle_drag_enter` 只是进入通知;注册数据类型须补 Image(从图片查看器 / 浏览器拖入的是图片内容,不是文件路径)。
- libyue 的 `Entry::SetText` 会吞掉 `on_text_change`:GTK 侧用 `is-editing` 对象数据守卫,编程式设置期间 `changed` 信号被过滤(防回环),程序化清空 / 置文本后可见文本变了但使用方拿不到回调——`input_t` 的清空 ✕ 曾因此「文本没了、筛选列表不刷新」。修复:清空处理里显式补调一次 `on_input("")`。凡编程式改 Entry / TextEdit 文本后又依赖回调的路径,都要手动补回调。
- 拖出发起:同步调 `gtk_drag_begin` 会使 GTK 拖拽状态机不一致(嵌套 gtk_main 不退出、只能拖一次),须推迟到事件队列排空、以 press 事件发起并回填 drag_context;drag-failed 须防御性收尾(fork mbt.12)。
- 浏览器页(WebKitGTK)创建即 abort「Could not create GBM EGL display: EGL_NOT_INITIALIZED. Aborting...」:WebKitGTK 2.5x 的 DRMDeviceManager 在创建 WebView 时初始化主 DRM 设备,GBM EGL 拿不到就 RELEASE_ASSERT 直接杀进程。NVIDIA 专有驱动未装 `libnvidia-egl-gbm` 时 GLVND 只有 X11 后端(`10_nvidia.json` 不含 GBM),card1 / renderD128 都拿不到 display(实测 `eglGetPlatformDisplay(GBM)` 返回 NULL;注意进程内独立探测与 WebKit 实际选路不一致——进程内 renderD128 探测竟能初始化成功而 WebKit 仍炸,勿用探测结果做决策)。showcase 首屏挂 Browser,必炸。库层修复:shim 的 app_init(Linux)统一 `setenv("WEBKIT_DISABLE_DMABUF_RENDERER","1",0)`(overwrite=0,用户显式设置优先),WebKit 退传统渲染路径不再崩,浏览器页功能不受影响(仅网页内容少一层 GPU 加速,界面 cairo 自绘无关);实测裸跑 showcase 正常起窗、存活、零 abort。系统层根治:装 `libnvidia-egl-gbm`(NVIDIA GBM EGL 后端),装后可自行设 `WEBKIT_DISABLE_DMABUF_RENDERER=0` 恢复硬件路径。工程注意:改 shim 后 moon 不必然重链(exe 不在其依赖图),须 `moon clean` 或删 exe 强制重链,`nm exe | grep 新符号` 确认。
- **跟进**，2026-10-14 实测，回答「Linux webview 到底集成了没有」：① 集成是在的——本机 `pkg-config --modversion webkit2gtk-4.1 = 2.52.6`，prebuild 编的是**真实现**分支，`nm gui/build/libyue_web.a` 有 46 条未定义 `webkit_*` 引用，占位分支不可能有；2026-10-12 另有一串真机复验读数：协议页中文正常、后退真回得去、网页内滚动与点链接正常、webview 聚焦时输入法让位后恢复。② 但上面那条保护**没跟到新栈**：全仓 `grep WEBKIT_DISABLE_DMABUF_RENDERER` 零命中，它当年写在已删除的 shim `app_init` 里。③ 当前机器**不复现**该 abort：驱动已带 GBM 后端——`/usr/lib/x86_64-linux-gnu/gbm/nvidia-drm_gbm.so` 在位，RTX 3070；一个不建窗口的 C 探针在**不设该环境变量**下 `webkit_web_view_new()` + `load_uri("about:blank")` + 约 2 秒主循环仍然存活，`PROBE ALIVE`、exit 0——所以没有擅自把 `setenv` 加回来，加回去只是白丢网页合成的 GPU 加速。④ 留判据给后来人：换机器/换驱动栈后浏览器页若再出现「创建即退出」，第一嫌疑就是这条丢了的保护，复现**不需要起 GUI**——控制台里 new 一个 WebView 不映射窗口即可判定；系统层根治仍是装 `libnvidia-egl-gbm`。
- overlay 滚动条的默认语义要靠进程环境保底:环境变量 `GTK_OVERLAY_SCROLLING` 在 GtkSettings 里优先级高于 gsettings(发行版脚本/用户全局导出 `=0` 强制经典滚动条是常见做法),GTK 每次创建 ScrolledWindow 都实时读进程环境——仅在主题初始化时写 `gtk-overlay-scrolling` GtkSettings 属性压不过环境变量路径。app_init(Linux)在 gtk_init 前 `setenv("GTK_OVERLAY_SCROLLING","1",1)`(overwrite=1:库默认语义与 set_overlay_scrollbar(true) 压过全局偏好;调用方对单个滚动区显式 false 仍走 per-widget API 生效),对装了同类脚本的最终用户机器免疫;后置的 GtkSettings 写入保留作兜底。
- **惰性挂载后滚动范围停在骨架高度(滚不动页第二根因,探针二分矩阵实证)**:GTK 下 ScrolledWindow 的滚动范围不来自内容测量——nativeui 的 nu_container 对 GTK preferred 恒报 0(不走 GTK 布局系统),viewport 的 adjustment upper 全靠 fork `Scroll::PlatformSetContentView` 在 **set_content 时刻**对内容自然高做的一次性快照(写成 size request);且重挂同内容时该函数先读旧快照(非 -1)即跳过重算、remove 清掉后 add 又写回旧值——内容在 set_content 之后才挂入(惰性挂载)或明显长高时,滚动范围永停在骨架高度,表现为「内容明明超高却滚不动、滚轮无声」。showcase 全部 111 段均为惰性挂载,图标库长段(9 行图标墙)最先暴露,实为全页共性。探针四列二分定案:常驻文本/图标墙 max=428/518(能滚)、惰性后挂文本/图标墙 max=0(holder 实测 1120/1210、GetPreferredSize 1164/1254 均正确)——与内容类型无关,纯挂载时序;重 set_content 无效(旧快照短路),显式 set_content_size 大值立即生效(adjustment 链路通,锁定 size request 快照不更新)。修复:shim 增 `yue_mbt_scroll_refresh_content_size`(Linux 直写 `gtk_widget_set_size_request(宽保持现值, 高=Container::GetPreferredSize() 即时跑 yoga)`,win/mac 空操作——Windows 的 ScrollImpl::Layout 本就每轮重查内容自然尺寸、macOS 由 documentView frame 决定范围,均无快照问题),yue 层 `Scroll::refresh_content_size()`;惰性挂载方在挂载完成后调用(showcase section_body 已接)。端到端探针:切页/切段/二轮显隐/切回后 max_y 恒为 内容高−视口(598=1290−692)精确恢复、视口变化亦动态正确。与「滚动范围跨轴 bug」(读侧)互补,本条是写侧,两修都在 shim 层。回归工具:`moon run examples/probe-iconscroll`(端到端四时序采样,长段 max_y 应恒 >0)。同一快照机制也咬**非惰性**场景:挂载后 `set_text` 长高(systemprobe 系统能力报告,几十行文本)与挂载后 `mount_into` 动态挂入新子树(视频播放器挂进占位容器)同样不更新滚动范围——表现为「读取结果出来后底部被截/滚不动、播放器挂载后滚不到底」。挂载方在内容变化完成后调 `refresh_content_size()` 即恢复;systemprobe 多页化重构的页面壳把刷新闭包注入正文构建函数,报告 set_text、播放器挂载、命令预览文本三处接上(2026-10 实测)。
- **报告标签 set_text 后不长高(裁剪,滚动范围快照之外的第二半,2026-10 用户真机反馈+探针对照实证)**:systemprobe 系统能力页点「读取系统能力」,几十行报告只显示前 1-2 行(用户截图:音量节只剩 sink 行,「音量: 45% 静音: 否」及其后全部不可见)。根因:GTK 标签(nu_label)的 yoga 高度只在挂载时测量一次(占位文本的高度),`Label::SetText` 只改 pango 文本、不标记 yoga 脏——新文本按旧高度裁剪;`refresh_content_size()` 只把容器**现有的**首选高度写给 GTK viewport,救不了标签自身高度(它修的是上一条的滚动范围那半)。探针对照(同页面壳结构 scroll→vbox→长占位 label):仅 set_text+refresh,16 行报告只渲染第 1 行;set_text 后加 `set_visible(false)`→`set_visible(true)` 再 refresh,16 行全文渲染。显隐切换生效是因 shim 的 `yue_mbt_view_set_visible` 内部走根级 `Layout()` 重算(三平台同代码、无平台分支),迫使 yoga 重新测量标签;显隐在同一拍内完成,无可见闪烁。修复:systemprobe 共享层增 `report_set(label, text, refresh)`(set_text + 显隐切换 + refresh),系统能力 / 命令预览 / 视频播放三页的全部报告写入点改走它。验证:真机点击「读取系统能力」,报告全文(音量 45% / 亮度 / 浏览器历史 / 下载 / VS Code / 二进制查找六节)完整渲染,点击前后截图差异 62979 像素;`moon check` 零警告 + `moon test` 657 全绿。教训:**GTK 标签的「长高」与「滚动范围」是两件事——前者要显隐切换(或等价重排)迫使 yoga 重测,后者才归 refresh_content_size**——显隐切换治半截,内容超视口时的另半截见下一条。
- **报告标签自然高的三条路全都不可信(上条「显隐切换即好」的深化,动态内容超视口时才暴露,2026-10 用户反馈+探针+DBus 双旁证)**:上条修复(显隐切换迫使 yoga 重测)只治了半截——内容不超视口时(16 行报告 < 视口)看似全好;内容超视口后仍滚不动、且标签被裁(40 行只显示 19 行),用户反馈「report 更新后调了刷新但没有滚动条」。深挖三层根因:①GTK 标签的自然高由 yoga `MeasureLabel` → `AttributedText::GetBoundsFor` 量,后者 `pango_layout_set_height(text_, size.height() * PANGO_SCALE)` **不防 NaN**——yoga 传未定义高度(GetPreferredSize 的 NaN 测量)时 NaN→int 为垃圾值,pango 把整个布局按**一行**量(shim 临时打印实测 preferred_h=92,即按钮+一行占位);②视口的确定高度(382)沿 holder→vbox 向下传导,MeasureLabel 的 AT_MOST 模式把文本裁到 341(40 行只分 19 行)——内容永不超过视口;③`refresh_content_size` 把 ①的错误值(92)写给 viewport,adjustment upper 不动 → `get_max_scroll_position_y` 恒 0。机制旁证:同探针 `set_content_size(600,1000)` 后下一个 tick `max=618`(=1000−382),证明 adjustment 链路本身是通的、refresh 的写入值才是祸首。修复(纯 MoonBit 侧,不动 shim/fork):yue 新增 `measure_text_height(text, role?, width?)`(同角色字体的 AttributedText 探针 + 大宽高测量,绕开 NaN 与 AT_MOST 两坑);`report_set` 改序为 set_text → 量自然高 → `set_style(label,"height",h+2)` **显式高度** → 显隐切换(根级重排)→ refresh。显式高度后 yoga 不再调用测量函数,两坑同时绕开。验证:探针(同页面壳结构,40 行报告)修复前 label_h=341/max=0,修复后 label_h=699(全文高)、body_h=773、**max=391(=773−382)**、滚轮 5 击 pos=263,截屏确认 40 行全文渲染且滚动到位。边界:显式高度在窗口 resize 后不重算(宽度变→折行变→高度 stale),演示页可接受,后续可在 on_size_changed 重设。教训:**GTK 标签的「自然高」三条路都不可信——yoga 重测遇未定义高度按一行量、遇视口确定高度按裁断量、挂载时量的是占位文本;运行期动态长文本一律「AttributedText 同字体量 + 显式设定高度」,勿把自然高交给任何自动路径**。
- **滚动范围跨轴 bug(滚不动页的根因,探针逐位实证)**:fork 的 Linux ScrollImpl::GetMaximumScrollPosition 把**视口宽度**当垂直 page_size 用——实测 `max_y = 内容自然高 − 视口宽`(窗口 900×600 时:纯自绘行块内容 1064→maxy 164、图表+行块 1088→188、纯标签 1160→260,全部精确命中),水平轴对称错。后果:程序化滚动行程只剩真实量的零头、悬浮 thumb 不浮现(库判定 maxy≤0.5 隐藏)。**初始可见与隐藏后显示同样错**(一度误判为隐藏挂载的测量问题,常驻对照组同值推翻;期间试过的 queue_resize/update_layout 补测均无效——GTK 测量本来就对,错的是 nativeui 的读数)。修复:shim 的 `yue_mbt_scroll_get_max_position_x/y` 在 Linux 改从 `gtk_scrolled_window_get_h/vadjustment` 直读 `upper − page_size`(其余平台仍直通 nativeui),修后 1160−600=560 逐位正确,sysmonitor 右栏滚轮实测生效(前后截图差异 5871 像素)。
- hover 组(hover_group)的判定不能依赖容器 enter/leave:GTK 的指针事件不冒泡,发给最深命中的 GdkWindow 就终结,子容器(NUContainer)/原生控件(Entry 等)的事件窗口会**独占**指针事件,祖先容器收不到 enter(sysmonitor 卡片能收 enter 是因为子件是无窗口的 label;子件一旦是容器/原生控件就断流)——「事件透传」需改 fork 上游(每视图事件广播祖先链)或平台全局钩子(XI2/WH_MOUSE),侵入与维护都重,不走。可行机制=指针位置轮询:**全部组共享一个全局 100ms 定时器(set_timeout 链,无组时完全停转),每 tick 一次指针查询 + 每组一次屏幕矩形比对,均微秒级**;cursor_screen_x/y 与 get_bounds_in_screen 同为屏幕根坐标、多屏拼接含负值一致(探针逐位验证)。enter 仅作命中加速、离场全靠轮询。可见背景必须 on_draw 自绘(set_background_color 与 backgroundColor 样式对无 draw 的容器均不可靠——主题 CSS 与子控件窗口都会压掉;悬停/常态底色直接在组容器 draw 里画,透明子区域自然透出)。实测:子控件(输入框)悬停整卡变 fill_hover(239,241,243)精确命中、移出复原。
- 自绘悬浮滚动条(overlay_scroll)先因跨轴 bug 降级为显式选用组件、后经真机验收捡回 Windows 形态:曾作 declarative `scroll()` 默认形态(为 Windows 经典条统一三平台观感),但 thumb 依赖 maxy/on_size_changed 链,叠加跨轴 bug 后形态不稳,一度回退平台原生滚动条;跨轴修复后经真机验收单独捡回——Windows 上 `scroll()` 在 overlay=true 且未显式 policy 时套 host 容器走 attach_overlay_thumb 自绘细条,非 Windows 与显式 policy 路径仍走平台原生条(overlay=true 请求悬浮样式,Linux 由环境变量保底、Windows 无悬浮对应物);overlay_scroll 组件与 Windows 侧页面滚动同走此路径。
- 系统主色调读取(GTK3 无强调色 API,`yue_mbt_system_accent` 三级递进):①GNOME 47+ 的 GSettings `org.gnome.desktop.interface`/`accent-color`——schema 存在但键不存在时(如 Ubuntu 24.04 的 gsettings-desktop-schemas)`g_settings_get_string` 直接 abort 而非返回空,必须先 `g_settings_schema_has_key` 探测(本机探针实测 abort);②当前主题 CSS 的 `@define-color theme_selected_bg_color`:GTK 各主题把主色统一表达为选中底色,按 `~/.themes` → `$XDG_DATA_HOME/themes` → `$XDG_DATA_DIRS/themes` → `/usr/share/themes` 找 `gtk-3.0/{gtk,gtk-contained,gtk-dark}.css`,深浅偏好决定先解析哪个(Orchis 系 gtk.css 是浅色主色、gtk-dark.css 是深色变体);③都取不到返回空。验证:探针程序(Ubuntu 24.04 + XFCE + Orchis-Teal-Light-Compact)返回 `#009688`,与主题 CSS 定义逐位一致;XFCE 无强调色设置,靠②命中主题主色。
- 容器级 hover 高亮(on_mouse_enter/leave 切底色)遇子控件必闪烁:GTK 的 enter/leave 按**原生窗口边界**派发,进子窗口即视为离开父窗口;libyue 有补偿(responder_gtk.cc `OnMouseEvent`:leave 延迟一拍、子 enter 取消 pending,仅 GTK),但有两洞——①子控件没连任何鼠标 handler 时 `PlatformInstallMouseMoveEvents` 未执行、无 enter 掩码,永远发不出 enter 去取消,pending leave 到点照发(卡片里 label / 图标一带);②空容器(如自绘迷你曲线画布)不满足「Container 且有子节点才延迟 leave」,父 leave 立即触发。实测 sysmonitor 左栏资源卡:鼠标在卡内每跨过一个子控件 hover 底色灭一次。规避:自绘容器的悬停反馈只用 cursor(手型)+ 常驻选中态(描边/浅底),不依赖 enter/leave;确需 hover 类效果须单画布自绘整卡(表格行同款)或改库层事件派发。另:悬停光标也按原生窗口生效,只设在容器上盖不住有独立窗口的子控件(hbox 行 / 自绘画布),须逐子控件 SetCursor(NUSetCursor 对无窗口控件为安全空操作;一个 nu::Cursor 可经 scoped_refptr 被多视图共享,复用同一实例即可)。透传通用化:`cursor_group` 组件与 hover_group 共用同一全局轮询拍——指针落在组 bounds 内时经 shim `yue_mbt_view_set_cursor_deep` 对组根+全部子孙递归 SetCursor,离开恢复 Default;恢复的是默认而非子件原光标(库不提供读回,组内子件需保留自身光标时不要套组)。
- **运行期改布局样式不触发重排(splitter 拖不动的根因,探针 8 场景定性)**:GTK 上挂载后用 `SetStyleProperty` 改任何布局属性(`width` / `flexbasis` 实测)都不落地——`update_layout` 根调用、叶子调用、纯 set_style 等自然布局周期(600ms 后读 bounds)全部无效;初始挂载时的样式值正常(首次全链 size-allocate 会读到)。Windows 上运行期 flexbasis 生效(5f272b4 合成拖拽验证过),平台差异,跨平台组件勿假设样式运行期可写。附带发现:Scroll 内初始 flexbasis 也不落地(首栏掉到 minwidth),width 正常。修复:shim 补 `yue_mbt_view_set_bounds`(直通 `View::SetBounds`)+ MoonBit 侧 `set_view_bounds` 泛型函数;splitter 拖动与初始比例改「set_bounds 直写三件几何 + 首栏 width/height 样式双写」——直写即时生效,样式值供窗口 resize 全链重排时按最后宽度接管。验证:examples/probe-splitter 探针(留仓)两阶段对照——样式路径 8 场景全不生效、set_bounds 6 场景全精确生效(直挂/Scroll 内 × 两档);131 测全过、showcase 冒烟存活,拖动手感真机复验。方法论:机制探针用定时器逐步改参数 + 隔拍 dump bounds,无需模拟鼠标即可定性布局链路。
- **Linux Label 是自绘控件 NULabel,不存在 GtkLabel 的 selectable 通道**:libyue 的 Label 在 GTK 侧是自定义 GtkWidget(nativeui/gtk/nu_label.cc,cairo 自绘文本,preferred 尺寸硬编码 0、无内建文本选择/复制),`gtk_label_set_selectable(GTK_LABEL(GetNative()))` 打在错误对象上静默无效(gtk_label_get_selectable 读回恒 0,运行时探针实证)。文本可选择的能力要走自绘组件方案(自绘命中计算+选中高亮+Ctrl+C 写剪贴板),不走原生通道。曾据 GetNative 是 GtkWidget 的假设加过 set_selectable API,验证失败后整批撤销(experiment/input_probe 为链路探针,留仓)。
- **on_wheel 的 Linux 挂接两处缺陷(0.5.10 修复):Window/View 兄弟类错位强转 + GtkWidget 默认无滚轮 mask**:shim 的 yue_mbt_view_on_wheel 曾用 CastToView(view)——Window 继承 Responder 而非 View,static_cast 错位后 View::GetNative() 读到错误偏移的成员,g_signal_connect 收到垃圾实例报 GLib-CRITICAL「instance of invalid non-instantiatable type」且信号从未挂上(运行时可见两条 CRITICAL 即此症);另 GtkWidget/GtkWindow 默认不含 GDK_SCROLL_MASK,不显式 gtk_widget_add_events 则 scroll-event 永不投递。修复:按 GetClassName 分派(Window 用 Window::GetNative,其余 `dynamic_cast<View*>` 取 GetNative),统一补 GDK_SCROLL_MASK|GDK_SMOOTH_SCROLL_MASK(NUContainer 的事件窗口 mask 走 nu_container_add_event_mask 叠加)。连带教训:**shim 里一切需要 GetNative() 的 view 级接口,对 Window 入参都不能走 CastToView**(Responder 级 Signal 的 Connect 因两类 Responder 头部同布局而碰巧安全,但这不可依赖)。
- **NUContainer(自绘容器)鼠标事件在作为 wgpu 渲染宿主时收不到,Window 级信号可靠(层进探针定案)**:把 wgpu surface present 到 Container 的 GdkWindow 后(甚至仅建 surface 不渲染),该容器的 on_mouse_down/move/wheel 全部收不到;层进实验(render/surface/one-frame 三模式)与无 wgpu 对照、Window 级对照交叉定位——X 层事件未断(Window 的 on_mouse_down 正常触发),断在 NUContainer 的 input-only 事件窗口命中/转发层,且该现象在无 wgpu 的空容器上对合成点击同样出现(XTEST 置顶复现,真机 hello-themed 的原生控件点击不受影响——原生 Button 有独立 GdkWindow)。**规避:渲染宿主场景的鼠标交互一律挂 Window 级信号**(客户区坐标系一致,容器铺满窗口时坐标等价);滚轮建议 window+host 双挂(window 级滚轮对 XTEST 合成事件未收到,真机行为待验,双挂谁通算谁、不同时触发)。诊断工具:three-native examples/input_diag(模式化层进,INPUT_DIAG_MODE=render/surface/frame)。根因(NUContainer 事件窗口与 wgpu surface 的交互)待深挖,列 fork 排查项。
- **主动 quit() 退出段错误(根因链 gdb 实锤,quit 前统一断信号根治)**:程序内 quit()(菜单退出/回调路径,不经 delete-event)时,窗口与控件被 shim 句柄注册表 ViewStore 持有、活到 exit 静态析构期才销毁;析构 ~Window→GTK 同步派发 focus-out,经 OnFocusOut→MoonBit 蹦床→schedule_paint→`Store<Responder>::get` 撞上析构中的 unordered_map→SIGSEGV(复现率约 1/20,窗口内有可聚焦 button_t 时;纯 label 不触发,gdb 下时序敏感不复现)。修复:shim `yue_mbt_quit` 在 MessageLoop::Quit 前遍历 ViewStore 断开全部视图的应用层信号(Responder 级 7 个+View 级 4 个+Window 的 on_focus/on_blur;on_close 故意不断——quit 常在其回调链内,Emit 已持 slots 拷贝不断亦安全),exit 期信号 Emit 空转,跨平台生效。实现注意:Window 继承自 Responder 而非 View(兄弟类),按 GetClassName 分支后各自 static_cast,不能从 View* 直转 Window*(编译期即拒)。验证:主动 quit 探针 ×50 零异常(修前 1/20 段错误)、无焦点探针 ×30 零异常、关窗路径(wmctrl -ic)×12 全 rc=0、135 测全过;复现器与探针留仓 experiment/exit_crash/。根治项(fork 加 is_quitting 标志在 OnFocusOut 入口短路)列 vendor 后续批次可选。
- **运行期 set_text 变长截断(标签宽度不跟随文本,探针 bounds 定量定案)**:bind / bind_label 及任何「订阅信号后 `Label::set_text` 换文本」的路径,文本比挂载时变长即被裁——长度超出挂载瞬间的 allocation 宽度,GTK 按控件 allocation 裁剪绘制,滞后到下一次真实窗口 resize 才恢复。三层根因:①libyue `Label::SetText` 只 `YGNodeMarkDirty` + `queue_draw`(纯重绘,不触发布局);②即便有人调 `Layout()`(yoga 全树重算、深层节点新值已算出),边界**下发**靠每层容器的 `UpdateChildBounds`,而根只对直接子 `SetBounds`;③GTK 对相同 allocation 的 `size_allocate` 短路——自身尺寸未变的中间容器(hbox 等)不下发,其子树里 measure 已变的 label 拿不到新宽度。libyue 的 `Container::Layout()` 非根分支本有「父层没下发就自己补」的自愈(dirty 链回溯逐层 UpdateChildBounds),但其向上传播在非 Container 父(Scroll)处截断,且 shim 的 `yue_mbt_view_layout` 原实现自己走到根调 `root->Layout()`,恰好绕开自愈分支。修复(shim):抽 `layout_root_down`——走根 `Layout()` 后,沿 **root→起点方向**对路径上每个 Container 逐层强制 `UpdateChildBounds()`(幂等下发,非 Linux 平台的可见性守卫照旧);`yue_mbt_view_refresh` 同步换用。**顺序必须外→内**:Scroll 的内容容器是独立 yoga 根(不挂大树,`IsRootYGNode` 以「无 YG 父」判定自成根),它的 `UpdateChildBounds` 才触发局部树重算;逐层下发若按内→外序,内层先执行拿到的是重算前的旧值,新测宽仍到不了目标——showcase 段内滚动架构(页面全在 Scroll 里)下首轮修复(内→外序)探针实测仍滞后一轮,翻序后即时同步。修复(MoonBit):`bind_label` 订阅回调、stat_card 数值(num)、form_item 校验文案(err)三处 `set_text` 后补 `update_layout`。验证:examples/probe-bind 探针(留仓,含 Scroll 包裹形态)定时短/长轮换 + 每轮 dump bounds——修复前长文本 bounds 停在 25px(恒截断)且滞后一轮;修复后 Scroll 内外均长 243 / 短 25 即时精确同步;65 测全过、showcase 冒烟存活。观测教训:①GTK 的 size_allocate 异步于当前回调,同步打印读到的永远是上一帧 allocation,勿据当帧值下结论;②改 shim 后 moon 不必然重链既有 exe(`.a` 不在其依赖图),须删 exe 强制重链,首日修复因此在 showcase 上「看似无效」实为旧 exe。

### 对话框遮罩纯黑(背景色 alpha 被 GTK 钳为不透明,2026-10 用户真机反馈+本机实证)

- 现象(用户真机):dialog_t 遮罩变成纯黑、盖住底下内容——预期 35% 半透明黑(`#59000000`)。
- 根因:遮罩色走 `ViewLike::set_background_color` → shim 裸传 `nu::Color(std::string)` → GTK 后端 `View::SetBackgroundColor` 以 `Color::ToString()` 拼 CSS。libyue(上游与 fork 同)的 `ToString()` 产出 `rgba(r, g, b, a)` 且 **a 是 0-255 整数**,而 GTK CSS 的 rgba alpha 只接受 0..1,超界钳为 1.0——本机 `gdk_rgba_parse` 实测:`rgba(0,0,0,89)`→alpha=1.000、`rgba(0,0,0,128)`→1.000、`rgba(0,0,0,0.35)`→0.350。故任何带 alpha 的 8 位 hex 走背景色路径在 Linux 一律渲染为不透明。`6af827c` 只修对字节序,其「#80000000 50% 黑」探针结论取自 Painter 填充路径,在背景色路径上不成立(深色底上不透明黑与半透明黑肉眼难分,误判来源)。
- 修复:遮罩改 on_draw + Painter `set_fill_color("#59000000")` + `fill_rect`(控制条同款 Cairo 路径,alpha 正常;与 hover_group「可见背景必须自绘」既有结论一致);absolute 容器补显式 `height:"100%"`;删 `set_background_color` 调用;`set_background_color` 文档注释更正为「#AARRGGBB,alpha 不保证生效,半透明底走 Painter」。全仓扫描:带 alpha 的 8 位 hex 走背景色路径仅此一处,`with_alpha` 全走 Painter 无碍。
- 验证:探针示例(白底 + dialog_t 常驻可见)真机截图,遮罩区域三处像素采样均 `srgb(166,166,166)` = `#a6a6a6`,与 `#59000000` 叠 `#ffffff` 理论值(255×(1−0x59/255)=166)逐位一致;`moon check` 零警告 + `moon test` 657 全绿。
- 教训:**半透明底一律 on_draw + Painter 填充,不走 set_background_color**(libyue 的 Color→CSS rgba 把 0-255 alpha 钳成不透明);探针结论必须标明渲染路径——Painter 填充与背景色 CSS 两条路径同一色值行为不同。

### 悬浮控制条对齐统一与背景不渲染终因(absolute 内容撑高 × 宿主 on_draw,2026-10 探针实证)

- 现象(用户真机):控制条上播放/暂停、等比/原始、全屏按钮高度不一、对齐不齐;进度滑杆与循环勾选不与按钮垂直居中;此前半透明黑底修复(6af827c 改 ARGB 序)后背景**仍然**不可见。
- 对齐统一:三按钮统一高 28(播放钮原生内建高度偏大,`Button::make(style=[("height",28)])` 显式钉;等比 44x28、全屏 28x28);**slider_t 内建 marginBottom 10、checkbox_t 内建 6 会把控件顶离行中线**——调用方 style 传 `("marginBottom", 0)` 覆盖(base 先 push 调用方后 push,可覆盖),交还 alignItems=center 真居中;去掉按钮私有 marginLeft 统一走 gap;等比文字测宽水平居中(`get_bounds_for` 测宽 + 居中绘制)。
- **背景不渲染终因**:组件控制条 absolute+bottom/left/right **无显式高度(内容撑高)**,且宿主(画面容器)自身挂 on_draw(画视频)——此组合下条的自身 on_draw 填色整个不渲染(子控件照常画)。隔离矩阵逐因素实证:absolute 定位✓、on_draw 画法✓、宿主 on_draw✓、内容撑高×宿主 bg✓,唯独「内容撑高×宿主 on_draw」组合失效;给条显式 `height: 40`(28 控件+12 padding)立即恢复,像素采样条区=视频色×50% 黑精确成立。机制深层(GTK draw 链与 yoga 内容测量的时序)待源码级确认,经验规则先行:**absolute 无显式尺寸的子容器,其宿主若挂自定义 on_draw,必须给子容器显式宽高**。
- 排查弯路:①stdout 管道缓冲——`timeout` 强杀探针会丢全部 println(READY 没出现≠程序卡死,自然退出才 flush),窗口是否映射要用 `xwininfo -root -tree` 按真实标题查;②探针窗口截图坐标含标题栏偏移,逐点采样前先剖面扫描找边界;③一度误判 get_bounds_for/对齐改动导致卡死——实为缓冲假象。
- 验证:探针像素采样条区半透明黑精确 50% 压暗;特写截图全行垂直居中;576 测全绿;systemprobe 冒烟存活。真机观感由用户复验。

## GTK 后端的窗口增强是空实现:改标题与无边框「按了没反应」(2026-10-14,真机反馈)

- **现象**:窗口页四个按钮只有「全屏切换」有效,「改标题」「无边框切换」按下去毫无变化,「还原尺寸」也看不出作用。
- **根因(三条各不相同)**:① 改标题 / 无边框——`gui/win/stub.c` 的 **GTK 分支是 W20e 留下的空实现**(`wm_set_title` / `wm_set_borderless` 整段 `(void)id;`),当年段首注释写的口径是「属 Linux 后端内部事务、不进路线图」,而 Win32 分支两条都实做了:于是 MoonBit 门面调过去无害、屏幕上什么都没有。② 还原尺寸——`wm_window_set_size` 在 GTK 分支**是真实现**(`gtk_window_resize`),但演示按钮写死 `set_size_pixels(1280, 720)`,而 1280×720 正是 showcase 的启动尺寸:不手动拖过窗口就点不出差别,这是演示缺判据不是后端缺口。③ 全屏——Win32 与 GTK 两分支都实做,所以只有它「有用」。
- **修复**:①GTK 分支补上 `gtk_window_set_title`(id 越界、`win->window == NULL`、`title == NULL` 三道守卫)与 `gtk_window_set_decorated(on ? FALSE : TRUE)`;同段的**图标 / 最小尺寸 / 自绘标题栏拖拽区仍是空实现**,理由写进段首注释(GdkPixbuf 的源与 HICON 不同宗;`geometry_hints` 未接;`begin_move_drag` 要按下时的指针与按钮号,本栈还没把这条请求送到窗口层),不留「看着像没坏」的空白。②演示按钮改成 1280×720 ↔ 960×540 两档切换(按钮名改「尺寸切换」、段文案同步),每次点击都有可见结果。③MoonBit 侧 `set_title` / `set_borderless` 的文档从「非 Windows 后端空实现」改成**逐后端点名**(Win32 改样式位重算外框 / GTK 走 `set_decorated` / macOS 仍空)。
- **验证**:窗口级动作无头判不了(要真窗口 + 窗口管理器),交真机。本批门禁读数:`cd gui && moon check --deny-warn` 零警告、库全包 937/937、`cd examples && moon check --deny-warn` 零警告、`moon build showcase --target native` 链接通过(gtk-3 本就在链接面上)。
- **口径**:后端能力不齐时**演示不许放按钮**(本仓先例:「最大化/还原」「置顶」因 Win32 段没写就不放按钮)。空实现的 API 留在门面里可以(跨平台形状一致),但演示与文档必须点名哪个后端没接。
- **待真机复验**(用户执行):「改标题」→ 标题栏变成「组件库演示板 · 标题已改」(顺带验 UTF-8 中文标题);「无边框切换」→ 标题栏与边框消失、再点回来;「尺寸切换」→ 两档大小来回可见;「全屏切换」照旧。

## 代码「复制」报成功却没写进剪贴板：提示吞掉了返回值，且缺一条跨进程判据 · 2026-10-14 真机反馈

- **现象**：点代码区「复制」，弹「代码已复制 ✓」，到别处 Ctrl+V 什么都没有。
- **根因一，报信**：`examples/showcase/shared/section.mbt` 写的是 `let _ = @sys.clipboard_set_text(...)` —— **返回值 Bool 被丢掉**，成功失败弹同一句话，于是提示与事实毫无关系。写路径本身在上一批已改走 GtkClipboard。
- **根因二，判据缺口**：既有的剪贴板回归是**同进程**写后读回，证明不了「别的程序读得到」——X11 的 CLIPBOARD 选区由主人进程负责应答请求，主人退出且会话里没有剪贴板管理器时外部就读不到。**同进程绿灯可以对应跨进程坏**，这类能力必须有第二个进程当证人。
- **新增判据**：`experiment/clipboard_probe` —— 先 `@win.init_backend()`，与真实图形应用同形态——GTK 分支就是 `gtk_init_check`——再写，写完**保持存活 6 秒**，期间由外部进程读回。本机实测，外部读者是独立的 python-gi 进程：`backend=true / available=true / set_ok=true`，外部读到 100 字符、含中文、弯引号、双反斜杠、制表符与尾部标记，`PROBE-AFTER-HOLD` 与写入完全一致 → **Linux 的 GtkClipboard 写路径跨进程成立**，所以这次坏的不是写、是报信。
- **一条正确行为，别当 bug 查**：没初始化窗口后端的纯命令行进程里 `clipboard_available()` 恒 false 并退回命令线 xclip；本机**没装 xclip** → 那种进程写剪贴板确实会失败，这是语义化降级不是缺陷。要复现「应用内」的行为必须先 `init_backend`，否则探针读数会把人带偏——我第一次跑探针就读到 `available=false`，差点归因错。
- **修复**：复制按钮按真实结果分支——成功才弹「代码已复制 ✓」，失败弹「复制失败：剪贴板不可用」，Danger 档。全仓另一处 `let _ = clipboard_set_text` 在 `gui/ui/clipboard.mbt` 的内核槽里：内核 `copy()` 没有回报通道，且失败时内部剪贴板仍然兜底，按设计保留不动。
- **验证**：`moon check clipboard_probe --deny-warn` 零警告、`cd examples && moon check --deny-warn` 零错误零警告、`moon build showcase --target native` 链接通过、库侧无改动，core+ui+sys 486/486 复跑通过。可见结果——去浏览器粘贴——归真机，清单 S15。
- **待真机复验**，用户执行：代码区点「复制」→ 去浏览器/编辑器 Ctrl+V 应见同一段代码；若弹的是「复制失败：剪贴板不可用」，把这句原文贴我——那说明应用内探测没走到 GtkClipboard，是另一条根因，而现在至少分得清了。

## 「在文件管理器显示」只开目录不选中：两条通道要在 core 会师 · 2026-10-14 真机反馈

- **现象**：XFCE 上点「在文件管理器显示 TODO.md」，Thunar 打开了那个目录，但 `TODO.md` 没有被选中。
- **根因**：`@sys.reveal_in_file_manager` 的 Linux 分支就是 `xdg-open <父目录>`，它自己的文档注释写着「总线通道的『打开并选中』随 DBus 线接入，当前一律落到打开父目录（选中态丢失）」—— 而 `FileManager1.ShowItems` 那一半**早就住在 `@dbus`**——`filemanager_available` / `show_items` / `file_uri` 三条齐全，URI 百分号编码还有测试覆盖——只是**没人把两条接起来**。接不起来是分层决定的：`@dbus` 依赖 `@sys`，sys 不能反向 import dbus，会师点只能是 core。
- **外测，本机**：`gdbus` 问 `NameHasOwner org.freedesktop.FileManager1` → `(true,)`，Thunar 注册了它；`thunar --help` 里**没有** `--select` 这类命令行开关 —— 总线是唯一能带选中的通道，退回 `xdg-open` 必然丢选中。
- **修复**：新增 `gui/core/reveal.mbt`，`@core.reveal_in_file_manager(path)`：Linux 且 FileManager1 在线时走 `show_items([reveal_uri(path, cwd)])`，不在线或这次调用失败才退回 `@sys` 的命令行路径；Windows 仍由 sys 直调 `explorer /select`。纯函数 `reveal_uri(path, cwd)` 单独露出来钉测试——选中态成不成就看这一串：必须绝对化 + 百分号编码。sys 那条的文档改成点名「这是退路，要选中走 `@core`」；演示两处，showcase 外部段与 systemprobe 的 reveal，改调 core 版。
- **验证**：core 新增 1 条 URI 回归，覆盖相对路径绝对化、空格、中文三段 → `moon test core` 138/138、库全包 939/939、`cd gui` 与 `cd examples` 的 `--deny-warn` 零错误零警告、`moon build showcase`/`moon build systemprobe` 链接通过。真机可见结果——Thunar 里高亮那一项——归用户，清单 S14。
- **口径**：**两条通道分住两层时，会师点必须是同时看得见两者的那一层**，并且文档要点名退路会丢什么——这里丢「选中」。否则能力齐备、行为却停在退路上，看起来就像「没做」。
- **待真机复验**，用户执行：showcase 外部段点「在文件管理器显示 TODO.md」→ Thunar 打开仓库根目录且 **TODO.md 处于选中态**；systemprobe 的 reveal，目标 `/tmp`，应把 `/tmp` 本身选中。

## Linux 托盘「没启动」：演示把整段建托盘挂在图标句柄成功之后 · 2026-10-14 真机反馈

- **现象**：showcase / native-app 在 Linux 上托盘图标始终不出，页内回显停在「建图标失败」。
- **根因**：`wm_icon_from_bgra` 在 **GTK 分支是 W20f 留的失败桩**——HICON 是 Win32 概念，恒返回句柄 0——于是 `@win.icon_from_bgra` 给 `None`；而两个演示都把整段建托盘写成 `match icon_from_bgra(...) { Some(ic) => Tray::new(...)  None => 记一句失败 }` —— **Linux 上根本没走到 `Tray::new`**。库侧不是缺口：SNI 后端不读这个句柄——图标走面板的主题图标名或库内置位图，见 `Tray::set_icon_name` 与 `Item::create` 里的 `default_icon_pixmap`。
- **取证链**，三条各自独立：① 会话总线上 `org.kde.StatusNotifierWatcher` 的 `NameHasOwner` 用 `gdbus` 外测为 `(true,)`——XFCE 面板的通知区在挂着；② `moon test dbus` 里既有的四条「真总线」SNI 用例——多托盘项路径/菜单路由/注销对称清理/断线自愈——在本机全过，注册链是通的；③ 读 `Tray::new` 的分支：`sni_watcher_present()` 为真即走 `@dbus.Item::create`，与 `icon` 参数无关。
- **修复，只动演示**：图标句柄**照传而不作门槛**——`let ic = icon_from_bgra(...)` 后直接 `Tray::new(id, icon=ic)`；成功时把句柄留在持有者里——Win32 的 HICON 在托盘存活期不能释放——失败时才 `free`，Linux 下 `ic` 本就是 `None`，两处都按 Option 走。
- **口径**：**平台专属的「可选输入」不能当能力开关**——句柄/句柄型资源在别的后端可能恒空，把它当成建对象的前置条件就把那条平台整条路径堵死了。与「后端没接的能力不放按钮」是同一条纪律的另一面：这里是不该藏的按钮被藏了。
- **验证**：`cd examples && moon check --deny-warn` 零错误零警告、`moon build showcase`/`moon build native-app` 均链接通过；库侧无改动，938/938 复测见提交。Linux 托盘的**可见结果**——面板出图标、左键计数、右键弹菜单——归真机复验，清单 S13。
- **待真机复验**，用户执行：切到系统集成页的「托盘」段 → 回显应为「已建（sni）」、XFCE 面板通知区出现托盘图标；左键点击计数走、`挂菜单` 后右键出菜单、`改提示` 后悬停可见新提示。若仍不出图标，把回显原文贴我——那已经是另一条根因。

## Linux 剪贴板改走 GtkClipboard：顺带炸出 win 桩缺 `moonbit_make_bytes` 声明的指针截断 · 2026-10-14 真机反馈

- **现象**：本机，Ubuntu 24.04 / X11 / XFCE，报「剪贴板不可用」——系统集成页的读写按钮没反应，输入框的 Ctrl+C/X/V 也不接系统。
- **根因一，能力缺口**：Linux 唯一的后端是命令线 `xclip`，而本机**没装 xclip**，`which xclip` 为空，于是 `clipboard_available()` 恒 false，`ui` 的 `attach_system_clipboard` 不装槽、门面读写全部退回失败。
- **修复一**：`win/stub.c` 的 GTK 分支补 `wm_clipboard_available / get_text / set_text`，即 GtkClipboard；sys 侧 extern 直链 win 桩——与文件对话框 `wm_file_*` 是**同一条先例**——MoonBit 层不引 win 包，链接由 prebuild 下发。探测顺序 GTK → xclip；`set_text` 在 `gtk_clipboard_set_text` 后紧跟一次 **`gtk_clipboard_store`**——只登记所有权而不 store，应用退出后别处就读不到了；监听侧 `cbw_get_text` 同口径改走 GTK，顺带省掉每拍一个子进程。Win32 与占位分支给同名符号——Windows 的真路径仍在 `sys_stub.c` 自己的 CF_UNICODETEXT，不动它。演示侧补 `@ui.use_system_clipboard(true)`，此前只有 native-app 开过。
- **根因二，ABI，被第一条炸出来的**：**`win/stub.c` 用 `moonbit_make_bytes` 却没有声明**——本文件的 GTK 分支由 prebuild 直接编，拿不到 moon 的 `moonbit.h` 包含路径——`compile_stub` 只加 pkg-config cflags。隐式声明按「返回 `int`」假定，x86-64 下返回值指针被截成低 32 位。**反汇编实证**：撤掉声明后 `wm_clipboard_get_text` 里出现 `mov %eax,%edi`，即把 32 位返回值当 64 位指针参数往下传，而本机堆地址是 `0x61bc76xxxxx` 量级，截断即垃圾地址。补 `extern void *moonbit_make_bytes(int size, int value);`——与 `sys_stub.c:57` 同一行先例；签名与 `~/.moon/include/moonbit.h` 的 `moonbit_bytes_t moonbit_make_bytes(int32_t, int)` 逐位对齐——后该 TU 零隐式声明警告。
- **顺带修掉一处既有隐患**：`wm_file_dialog_get_result`，即 Linux 文件对话框取回路径，一直在返回截断指针，只是从没被无头测试走到——要真选一次文件才触发。
- **对照实验**：撤声明 + 强制重链 → `moon test sys` SIGSEGV；补回 → 188/188。**踩坑记档**：只改桩里的 C **不会**让 moon 重链测试可执行文件，它按 .mbt 包脏化，第一次对照实验因此「假通过」；必须 `touch` 一个 .mbt 源文件，或删掉归档再脏化包，才作数。
- **读数与口径**：GTK 路径在本机真读到使用者剪贴板，watcher 测试打印 `cbw_get_text: Ok（13 字符）…`。注意 `gdk_display_get_default()` 在**没跑过 gtk_init 的测试进程里也返回非空**，GDK 按 `$DISPLAY` 惰性开，所以 Linux 探测在无头测试里同样是 true——剪贴板回归因此必须写成「可用则做 save→set→get→restore 往返、不锁使用者内容」的形态，`clipboard_wbtest.mbt` 已是这形态，换后端不假红。
- **验证**：`cd gui && moon check --deny-warn` 与 `cd examples && moon check --deny-warn` 零错误零警告、库全包 937/937、`moon build showcase --target native` 链接通过。真机复验清单加 S11——系统集成页读写按钮、输入框 Ctrl+C/V 与外部应用互通。
- **待真机复验**，用户执行：系统集成页「写入剪贴板」→ 到浏览器/终端里 Ctrl+V 应见同一段中文；页内读取按钮应回读到外部复制的内容；输入框内 Ctrl+C/X/V 与系统互通；退出应用后剪贴板内容仍在——靠那次 `store`。

## Linux 系统级拖放接上(W23 平台批):四信号喂同一条会话、press 存档起拖、阻塞语义靠嵌套主循环(2026-10-15,用户提需求)

- **环境**:Ubuntu 24.04(X11/XFCE,GTK3),W23a/b 此前只接了 Windows 半边,GTK 分支是失败桩(`supported` 恒 0);本批补 Linux 侧,门面/事件泵/回落语义/showcase 全部零改动。
- **设计(与 Windows 分支同构的接线)**:拖入 `gtk_drag_dest_set` 挂在 GtkWindow 上(坐标即客户区坐标),四个信号——`drag-motion`(答 `gdk_drag_status` 两段式 + 首次**异步**取载荷)、`drag-leave`(收会话)、`drag-drop`(只置「投递待载荷」,放行 `GTK_DEST_DEFAULT_DROP` 默认 handler 去请求数据)、`drag-data-received`(motion 期缓存载荷并补发 ENTER,drop 期发 DROP + `gtk_drag_finish`)。事件压进程级队列、宿主每拍 `wm_dragdnd_poll` 抽,`core/drag.mbt` 的 `drag_external_pump` 一行不改。
- **坑①(motion 期载荷是异步的)**:X11/XDND 下拖到一半时目标**拿不到 selection 数据**,必须 `gtk_drag_get_data` 请求、数据到达走 `data-received`(GTK 随后会再发一次 motion)。ENTER 事件从 `data-received` 里补发——指针停住不动不会再有 motion,ENTER 不能等;请求失败(源一样都不给)置 `asked` 标志答禁止,不重试。载荷单缓冲进程级一份(同一时刻只有一条会话,与 core 侧 `drag_current` 单例同口径)。
- **坑②(起拖要 GdkEvent,而处置链不在 GTK 派发栈内)**:`gtk_drag_begin_with_coordinates` 要一个按钮事件,但本栈的起拖发生在 MoonBit 处置指针 Move 那一拍——早已离开 GTK 信号派发,`gtk_get_current_event()` 返回 NULL。按下那一刻 `gdk_event_copy` 存档、抬起即释放;没有存档(测试/键盘发起)直接失败——`Err(Failed)` 自动回落应用内,恰好是三平台同一份代码的口径。
- **坑③(阻塞语义)**:Windows 侧 `SHDoDragDrop` 自跑消息循环阻塞到松手;GTK 的 `gtk_drag_begin` 立即返回,本批在 C 侧嵌套跑 `gtk_main_iteration()` 直到 `drag-end` 信号(60 秒 `g_timeout` 兜底,防协议异常丢了 `drag-end` 把调用方永久挂住),效果从 `drag-end` 时的 `gdk_drag_context_get_selected_action` 读回。
- **坑④(效果位值两套)**:`GDK_ACTION_COPY/MOVE/LINK` 是 2/4/8,与门面沿用 Win32 的 `DROPEFFECT_*`(1/2/4)不同套——显式互转,多位同亮按「没成交」(0)不猜,与 core 侧 `drag_effect_of_flag` 只认 1/2/4 同口径。
- **为什么没有合成探针**:Windows 侧 `drag_probe` 能纯 C 合成全链路,是因为 OLE 的 COM 接口可以直接喂对象;XDND 的 motion 由**指针**驱动,合成不了跨进程拖拽——Linux 侧验证层次是「编译 + 真环境读数测试(`win/dragdnd_wbtest`:挂接/幂等/计数/效果写回,无头打印跳过)+ 冒烟 + 真机清单 S26/S27」。
- **顺带两条 C 层小坑**:`GPOINTER_TO_ATOM` 不存在(GDK 的是 `GDK_POINTER_TO_ATOM`);`gtk_target_list_add_text_targets`/`add_uri_targets` 必须带 `info` 参数(C 编译期报错,好抓)。
- **验证方式**:`moon test win` **29/29**(新增 1 条环境读数)、库全量 **975/975** 零红、`cd gui && moon check --deny-warn` 零警告、showcase 构建链接 + 本机 8 秒冒烟存活;跨进程真拖(Thunar/gedit ↔ 窗口)归 `测试文档/测试用例.md` 的 Linux 项。

## 真机反馈四则(点击上屏延迟/键盘恒 65507/空格不激活/radio 圆圈被截):GTK 帧派发要当场跑、IM 要焦点门、点击涟漪要整窗兜底、标记行高不随字体塌陷(2026-10-15,Linux 真机反馈)

- **环境**:Ubuntu 24.04(X11/XFCE,ibus 输入法会话),showcase 真机,用户报四条:①表单段 stepper 连点期间数字不动、停手 ~1s 才跳;②键盘测试段回显恒 65507(= X11 的 Control_L),按什么键都不变;③radio/checkbox 空格不改状态;④radio 圆圈渲染偏上被截。附带轻提示只显示第一次——与①同根。
- **根因①(GTK 的 draw 信号要主循环迭代才派发)**:`wm_present` 存帧后只 `gtk_widget_queue_draw`,而本栈的泵 `wm_wait` 只在 **fd 就绪**时跑 `wm_pump()`——timer 到期/poll 超时那拍 `ready=0` 不迭代,帧一直躺在 GDK 队列里等下一个 X 事件。点击后若无后续事件,上屏就卡到下一个事件源(实测 ~1s)。**修复**:`wm_present` 在 queue_draw 后**当场非阻塞派发一轮**(`while gtk_events_pending() gtk_main_iteration_do(FALSE)`,上限 8 防意外重入;迭代里重入的 button/key 照旧入本窗队列、下一拍抽)。toast 第二条不显示同根:push 的 invalidate 画的帧同样躺在队列里。
- **根因②③(ibus 把字符键吃进 commit 通道)**:`wm_on_key` 无条件 `gtk_im_context_filter_keypress`——挂着 ibus 的会话里 IM 消费全部字符键(经 commit 通道回报,非输入框焦点的 commit 被丢),按键事件只剩 IM 不吃的**修饰键**(65507=Control_L)。空格是字符键,radio/checkbox 的 `KS_SPACE` 激活自然收不到。**修复**:输入法焦点门——C 侧 `wm_im_set_active(id, on)` + `WmWindow.im_active`,仅 MoonBit 侧焦点控件是输入框(`im_context_of` 有值)时才让 IM 过滤;`App::pump_ime` 在焦点切换处同步。Windows 分支 IMM 不过滤普通按键,空桩保链接。
- **根因④(标记行高随字体度量塌陷)**:radio/checkbox 的行高由文本行盒决定,测试宿主(Noto)行高 19 装得下 14px 标记;真机 XFCE 默认字体的行盒可比 14px 还矮,标记撑破行、圆圈顶被上方内容盖住(诊断读数:测试宿主下两组 dot 完全对称 y=2.5/h=14,排除布局结构问题)。**修复**:radio/checkbox 行 `set_min_height(fixed(20.0))`,标记高度不再依赖字体度量(switch 的胶囊 20px 固定、本就不塌,不改)。
- **附带(core 层的点击涟漪缺陷,全平台)**:指针事件后只对悬停/捕获链做**局部置脏**,而 `on_click` 改的 Store 常影响链外兄弟(stepper 数字:显示控件不订阅、绘制期现取),脏区盖不住、上屏保留旧像素。**修复**:指针 **Up(点击成交)一律整窗置脏**兜底——点击是低频交互,整帧代价可接受;Move/Down 的局部脏保留。
- **验证方式**:库全量 **975/975** 零红、`cd gui && moon check --deny-warn` 零警告、examples `--deny-warn` 零警告、showcase 构建链接 + 本机 8 秒冒烟存活;真机复验归 `测试文档/测试用例.md`。
- **待真机读数的一条(本批未动)**:「侧边栏菜单能通过 Tab 获得焦点」——无头诊断显示侧栏 `menu_sections` 树 `focus_ids()` 为**空**(菜单项无 focus_id,本就不在 Tab 链),组件层无缺陷可修;复验时请按 Tab 后截图焦点环落在哪个元素上,按读数再定位。

- **后续，同日，用户拍板撤除**：分层羽化这版做出来自己看读数是对的——十档单调渐隐、角边同浓度、往下多投一个偏移——但**真机观感仍不如人意**——用户复验后说「阴影悬浮还是去掉吧」。于是整条撤除：`Style` 的 `box_shadow`/`shadow_x`/`shadow_y`/`shadow_color` 四字段与 setter、`shadow_of`、`Painter::drop_shadow`、`Widget.shadow_paint`——含裁剪窗口与视口剔除判交的外扩——一并删掉，showcase 的两张投影卡片与 design.md §1.1「效果」行、P4 行同步改口径；不留「写了不生效」的空字段，那等于假装能用。教训记两条：①**数值判据自洽 ≠ 观感通过**——本项目里观感类改动一律以真机复验为准，读数只能帮我定位不能替我签字；②要重做投影，先解决**真高斯 blur**——分层近似在 1× 物理像素、无 HiDPI 放大的渲染里天然带台阶——别在近似上再叠 API。
## 输入法吃字符键有两层，焦点门只挡了第一层：fcitx5 的 GTK 模块嗅探器在 GTK 派发之前就吞掉按下 · 2026-10-18 Linux 真机三相位回证

**现象**：用户真机，两轮——Linux + fcitx5 会话里打开 audio/video 示例播放，没有任何输入框持有焦点，按 `M`/`L` 即静音/循环快捷键无效；空格/方向键正常。第一轮修复，`ime_focus` 哨兵化，后依旧。
**三相位定位**，家机 `ssh home` + `experiment/key_probe` 原始窗口层打印 + xdotool 注入 + `fcitx5-remote` 开关，key_probe 不经任何 MoonBit 门控：
- **相位 A**，fcitx 置非激活：m/l/space/Up 的按下+抬起全部到达；
- **相位 B**，fcitx 激活、中文态：`m`/`l`/空格的**按下**全部消失——`preedit=[m]`、`preedit=[m l]`、空格直接 `commit=[目录]`，fcitx 把拼音 "ml" 选了候选；**抬起**照常到达，`ev code=1 keysym=109/108/32`；
- **相位 C**，`GTK_IM_MODULE`/`XMODIFIERS` 全 unset、fcitx 仍全局激活：全通。
**根因**：吃键的不是我们的 `gtk_im_context_filter_keypress`——那层由 `im_active` 门控着、key_probe 根本没开门也照样被吃——而是 **fcitx5 的 GTK IM 模块在 `gtk_init` 时装的进程级按键嗅探器 key snooper**——它跑在所有控件的 key-press handler 之前，只要本窗的 `GtkIMContext` 处于 `focus_in` 状态就把字符键按下转给 fcitx，进 preedit/commit，抬起放行。而 GTK 臂在 `wm_on_realize`/`wm_on_area_focus_in` 里**无条件 `focus_in`**，G0 条件①要它；`wm_im_set_active` 只拨旗标从不 focus_out——旗标管得住自家 filter，管不住嗅探器。
**修复**，两层一起：`wm_im_set_active` 同步 focus_in/out——开=focus_in，G0 条件①保留、真拼音仍可用；关=focus_out 并清组合串缓存，与失焦路径同口径——`wm_on_realize`/`wm_on_area_focus_in` 的 focus_in 加 `im_active` 门。外加前一轮的 `ime_focus` 哨兵化——那也是真洞：丢焦路径写 0 绕过门同步，修好它门才有机会在「无输入框」时被拨到关。
**验证**：三相位矩阵里的相位 B 即判据——修复后重跑 key_probe + fcitx 激活，m/l 按下应作为 `ev code=0` 到达且不再出现 preedit；真机最终收口见 T 清单，播放器 M/L + 输入框拼音双向。

### Linux 真机反馈修复集 · 2026-10-17 第二批 · 桌面环境已换 Cinnamon/Muffin

- **NoWrap 文本不裁切**：`pt_render_box` 在 `wrap=0 && ellipsize=0` 时不设 Pango 宽度，否则会被折行，文字自然画出声明盒；mac 侧绘制有盒裁切、Linux 侧没有。修：`pt_draw_box_cr` 在 `save` 后按声明盒 `cairo_clip`，宽/高为 0 视为该轴不裁。判据：限宽 300 的 NoWrap 文本右缘齐盒。
- **Desktop 层压在桌面图标之上**：真机读数——`xprop -root _NET_CLIENT_LIST_STACKING` 逐窗回读类型与状态——定的靶子：Cinnamon 的桌面图标窗 `nemo-desktop` 本身就是 `_NET_WM_WINDOW_TYPE_DESKTOP`、Depth 32——ARGB，除图标外全透明——每台显示器一扇铺满工作区、已排在栈底；壁纸由 Cinnamon 自己的合成层画，在全部 X 窗之下。所以「图标下、壁纸上」= 挤到 nemo-desktop 之前，这个位置确实存在。要过两道坎：① **类型只在 map 时读**——Muffin 对已映射窗改 `_NET_WM_WINDOW_TYPE` 不重新分层，`XChangeProperty` + `XLowerWindow` 实测无效；改走「记原位 → `gtk_widget_hide` 即 unmap → `XSync` 让 unmap 进服务端 → 挂类型 → `gtk_window_move` + `gtk_widget_show` remap」。② **画序不吃 X 栈**——合成窗口按 WM 自己的窗口列表排，客户端 `XLowerWindow`/`gdk_window_lower` 只动 X 输入栈；真机症状正是两条栈分叉——图标能拖了，输入到位，但窗口还画在上面，画序没动。补 EWMH 权威路径：map 之后向根窗发 `_NET_WM_STATE` ClientMessage——桌面档 ADD `BELOW`、其余档 REMOVE `BELOW`；置顶/dock 档 ADD `ABOVE`——再补一次 lower 收输入栈。lower 走 `gdk_window_lower` 而非裸 `XLowerWindow`，与 GDK 队列里的 map 请求同序，混用会插到未 flush 的 map 之前。复位 normal/dock 档同走重挂，否则 1→0 切换回不来；窗口已 `w->hidden` 时只挂属性，等 `wm_show` 的 map 生效；非 X11 会话只留 GDK 类型提示。验证，2026-10-19 Cinnamon 真机：窗口页选「桌面层」后用同一条读数命令回读，本窗 `showcase.exe` 落在 index 0、类型 DESKTOP、状态含 `BELOW`，排在两扇 `nemo-desktop` 之前；视觉上图标盖住窗体且仍可点选拖动，切「普通」/「置顶」各自回位。
- **系统级拖出后全局光标卡在「+」**：只在 Cinnamon 复现——XFCE 与 mac 同码正常。根因在桌面端：拖拽期间整屏光标由 shell 画——Muffin `src/compositor/meta-dnd.c` 只处理 `XdndEnter`/`XdndPosition`/`XdndLeave` 三种消息，**没有 `XdndFinished`/`XdndDrop` 分支**；Cinnamon `js/ui/xdndHandler.js` 把 enter/leave 转成 drag-begin/drag-end，`js/ui/dnd.js` 在 drag-begin 里 `global.set_cursor(Cinnamon.Cursor.DND_IN_DRAG)`、**只有 drag-end 才 `unset_cursor()`**。`wm_dragdnd_send` 从 MoonBit 事件栈——非 GTK 派发栈内——手动起拖并自跑嵌套主循环，旧收尾在 `drag-end` 那一刻立即 return，把 GTK 排在后面的收尾事件整批跳过，`XdndLeave` 发不出去 ⇒ shell 光标永久卡住；卡的是 shell 级光标，所以之后连 Nemo 桌面图标拖拽也一并显卡——同一条后果，不是第二条故障。修，三处同批：① 循环退出后先**排空挂起事件**——有界 200 轮 `gtk_main_iteration_do(FALSE)`——让 GTK 把 Leave 与协议尾巴跑完；② 排空后按 `gdk_display_device_is_grabbed` 读数决定要不要补 `gdk_seat_ungrab`，再排空一轮；③ 无论读数如何都把源窗，toplevel 与 area 的 GdkWindow，光标清成 NULL，并把宿主缓存形状置 `-1` 即未知，下一拍按命中路径重装。超时兜底路径先 `gdk_drag_abort` 再走同一条收尾。判据：拖文件到文件管理器、拖文本到编辑器，松手后光标立即复原、可正常点击；真机读数 `end ... ended=1 get_calls=1/4/5 drained=12/1/8`——对方来取过数据、以复制成交，排空的那几条正是旧版跳过的收尾。读数通道：环境变量 `LIBYUE_DND_LOG=<路径>` 才落盘，未设完全静默。注意 `post-ungrab grabbed=1` 也可能出现——seat ungrab 后 GDK 读数要下一轮事件才归 0，此读数只作线索、不作契约。
- **同一条坑的第二处：grab 不还，僵的是本应用**，2026-10-19 复测，`/tmp/dnd.log` 12 条会话全现：上一判据把收尾改成「`ended=1` 就不动 grab」——依据是 `post-ungrab grabbed=1` 显示 seat ungrab 没减读数、又怕打乱 seat 计数——症状就从「全局光标卡住」变成「本窗交互僵住」：每条会话排空 11~24 轮后 `grabbed` 仍为 1，而 GDK 已把 drag-end 当收口、不会再替这条会话 ungrab：服务端 grab 不还，键鼠事件全被它吃掉。修：排空后只要 `grabbed=1` 就走 X 侧 `XUngrabPointer`——`gdk_x11_display_error_trap_push`/`pop_ignored` 兜住 grab 不在本进程时的 BadAccess——再跑一轮派发让 GDK 收到自己的 GrabNotify、把读数跟上来；不再碰 `gdk_seat_ungrab`——它只减 GDK 自己的计数、不动服务端，正是上一条读数码住的那位。判据：拖文件出本窗松手后本窗立即可点，读数多一行 `post-xungrab id=... grabbed=0`；`grabbed` 仍为 1 就说明 grab 不归本进程，得往 shell 侧查。

### Linux 真机反馈修复集 · 2026-10-17 第三批 · Cinnamon

- **机器信息整条报读不到**：`si_machine` 把 `/sys/class/dmi/id/product_serial` 当必需项，而该档权限 `0400`——多数发行版仅 root 可读，本机实测确认——vendor/product 明明读得到也被连累成 `SiReadFailed`。修：序列号回落 `/var/lib/dbus/machine-id` → `/etc/machine-id`，与 Windows 侧 `SerialNumber`→`MachineGuid` 同一兜底形态，两者都缺才报错。教训：DMI 三件套不是同权限档，必需项只能是全局可读的那两件。
- **剪贴板第一次读不到、第二次手动触发才读到**：`gtk_clipboard_wait_for_text` 的首问会输给选区属主握手——Cinnamon 有 `csd-clipboard` 常驻接管属主，首问更容易空转返回 NULL——第二次问时属主缓存已热。修：首问为 NULL 时把主上下文中已就绪的事件跑一轮，`g_main_context_pending` + 非阻塞 `iteration`，再问一次。判据：应用启动后第一次点「读取剪贴板」即应回显内容。

### 拖出跨平台对齐复查 · 2026-10-19 · 由 mac 那条报障回查 Linux/Windows

- **Linux 从不设拖拽图标**：`gtk_drag_begin_*` 之后没跟任何 `gtk_drag_set_icon_*`，而 GTK 的默认拖拽图标是**发起控件的快照**——本栈的发起控件就是整扇窗口，于是拖起来是一整块窗口贴在指针上，落点看着全偏——报障「拖动的位置有问题」的直接来源。修法：两档都显式给 32px 图标并取中心当热点——`Paths` 取第一个文件的系统图标，即 `g_file_query_info(standard::icon)` → `gtk_icon_theme_lookup_by_gicon` → `gtk_icon_info_load_icon`，取不到退回 `text-x-generic`；`Text` 直接取文档图标；主题里取不到就留着不动。`gtk_drag_begin_with_coordinates` 的 `x/y` 给 `-1` 即「用当前指针位」，位置本身不用我们算。GdkPixbuf/GIO 符号在 `gtk+-3.0` 的 pkg-config 库里，prebuild 不用改。
- **两支的返回值契约与门都是干净的**，对照 mac 那两条毛病：Win32 `wm_dragdnd_send` 与 GTK 支都是 5 参 `(id, payload, len, allowed, int32_t *out_effect)`、返回「0=没起来 / 1=走完并写 out_effect」，都**不**以「本窗挂过拖入目标」为起拖前提；Win32 走 `SHDoDragDrop`——OLE 自己按当前指针画拖拽图像，无整窗快照问题。
- **组件层两条判据补齐**，`gui/ui/drag_wbtest.mbt`，无头：① 按下落在拖源内部的**文本节点**上仍要冒泡开拖——普通盒子测不到这条，盒子里没有子节点、命中的就是包装层本身，当时怀疑「文字的干扰」就在这一点，实测路由无误；② `external=true` 时系统级起不来——后端不可用/无活动窗口——必须回落到应用内会话，不能既不拖也不回落。
- **仍待读数的一条**：起拖发生在宿主泵里，比按钮现场晚一拍。若那一拍内键已抬起，`gtk_drag_begin_*` 抓不到指针，会话当场收口——外在表现就是「有时拖不出来」。读数口已就位：设 `LIBYUE_DND_LOG=<路径>` 后看 `begin ... grabbed=` 那一条，`grabbed=0` 即这一类。根治方向是把起拖挪进 GTK 的事件派发栈内——三支同改，会牵动 `drag_external_send` 的阻塞语义与回落时机，属接口级改动，未动。

### 桌面层级拆两档与任务栏撤条 · 2026-10-19 · Cinnamon

- **图标下档不可交互是这一档的语义，不是缺陷**：图标下，即壁纸场景，= DESKTOP 型 + `BELOW`，本窗排在 `nemo-desktop` 之前，鼠标事件全归桌面窗——壁纸背后没有「本窗接事件」这回事。要做**桌面小部件**——图标之上、普通窗口之下，且本窗收键鼠——类型不能再挂 DESKTOP：改走 **NORMAL 型 + `_NET_WM_STATE_BELOW`**，落在普通层栈底，天然压在桌面层之上、其它窗口之下。对外即 `WindowLayer::Desktop` 图标下与 `WindowLayer::DesktopWidget` 图标上两档。
- **另两平台的档位落点**：macOS 有原生对应层，`kCGDesktopWindowLevelKey` 即图标下、`kCGDesktopIconWindowLevelKey` 即图标上，一一对上，待真机。Windows 的桌面窗归 Explorer，即 Progman / SysListView32，客户窗压不进它下面——两档都只能 `SetWindowPos(HWND_BOTTOM)`，即恒在图标之上；「不进任务栏」要 `WS_EX_TOOLWINDOW`，未接，按未做记。
- **桌面档任务栏条目不消失**：`gtk_window_set_skip_taskbar_hint` 只改 `_NET_WM_STATE` 属性，Muffin 对已映射窗不重读属性——与画序那条同一个口径——真机读数：属性里 `SKIP_TASKBAR, SKIP_PAGER` 都在，面板条目照旧。修：桌面两档在 map 之后向根窗发 ClientMessage `ADD SKIP_TASKBAR / SKIP_PAGER / STICKY`，切回 Normal 逐条 `REMOVE`。判据：点「图标上」后——图标被窗体盖住、窗内按钮点得动、任务栏不再有本窗条目、切到任意普通窗口时本窗沉在所有普通窗口之下；「图标下」则窗体被图标盖住且点击穿透到桌面。

### 拖出机制沿革核查 · 2026-10-19

- **没有「旧的可用实现」可以回退**：Linux 拖出自 `94056db`，2026-10-15 W23 平台批，起就是同一机制——`gtk_drag_begin_with_coordinates` 起拖 + 自跑嵌套 `gtk_main_iteration` 阻塞到 `drag-end`，60s 兜底。`git log -S XdndEnter -- gui/win/stub.c` 全史零命中，当前文件里也一个都没有：手写 XDND 源端协议从未存在过；不带 coordinates 的 `gtk_drag_begin`、不起嵌套循环的异步状态机同样没有。`5377445`→`3f9f19c`→`06b2bf9`→`cceb478`→`2ff4c69`→`b91e5f1`→`3c1d19b` 这八次全在**收尾**上打补丁——seat ungrab → 排空事件 → 撤销代收尾 → 改 X 侧 ungrab → 补 ctx 引用——机制一次没换。
- **「以前拖成功过」对的是传输，不是另一套机制**：`fd9f12e` 记的真机读数 `ended=1 get_calls=1/4/5`、以复制成交——跨进程数据传送成过；没成过的只有收尾，即光标「+」与指针 grab 不还，以及 `1ac264b` 补落点读数带进来的野指针崩溃——`3c1d19b` 已治：落点改在 drag-end 回调内取，起拖 `g_object_ref(ctx)`、收尾交回。
- **同一条根因自首发就在**：`94056db` 的提交说明当时就写着「MoonBit 处置链不在 GTK 派发栈内」，所以起拖由我们手动发起、收尾也得我们手动补——上面整串收尾补丁都是这一条的下游。要断根只能把起拖挪进 GTK 事件派发栈、会话改异步收口：三支同改，且 `drag_external_send` 的阻塞语义与回落时机要一起换，属接口级改动。
- **要拖两次才拖得出来**：起拖用的事件由 `wm_on_button` 在按下那一刻存档，而 `wm_dragdnd_send` 要到宿主泵看见「过阈值」那一拍才调用——那一拍距按下已过若干毫秒，`gtk_drag_begin_with_coordinates` 拿**旧时间戳**去抓指针会抓空，头一趟当场死掉；第二趟因为队列里的事件新鲜才成。修：左键仍按着时，每条移动都把存档事件换成当前这条——时间戳与坐标都是新鲜的——门面契约不变，仍要求「键还按着」时调用。读数同时补两处：`begin ... ev_type=`，5=已刷成移动事件、4=还是按下那条，与每趟被拒的原因 `refuse ... why=args/no_window/no_press/kind N/actions N`。**待真机**：若拖不出时读到的是 `why=no_press`，根因就不是时间戳而是「键抬起早于这一拍」，得走上一条「起拖挪进 GTK 派发栈内」的根治方案。
- **在窗外松手会叫起拖现场永远陈旧**：`wm_on_button` 只在 `wm_dnd_press == NULL` 时存按下事件，而 release 只在指针还落在我方窗口时才收得到——在窗外松手，那份存档就永远留着，之后每次按下都不再更新，起拖一直拿最旧那份事件。改：每次左键按下都覆盖存档，先释放旧的。同时组件层补了拖出决策读数，`gui/ui/drag.mbt` 的 `dnd_diag`、与 C 侧同一个 `LIBYUE_DND_LOG` 开关、落 stderr：`按下记牢 / 过阈值 / 系统级走完 / 系统级没起来→回落`，因为 C 侧读数只知道自己的被调没被调——真机上一趟「拖不出」若在读数里连 `begin` 都没有，断点就在组件层以上。

### 拖放真机复查 · 2026-10-19 续

- **指针 grab 收尾：读数要先 sync，还 grab 只能走 GDK 的 XI2 出口**：`gdk_display_device_is_grabbed` 读的是 GDK 自己的 grab 账，`gdk_device_ungrab` 之后要等服务端回执——异步 roundtrip——才销账，不 sync 直接读，会把「账没跟上」误判成「grab 没还」。另一头，GTK3 在 X11 用 `XIGrabDevice` 取指针，`XUngrabPointer` 只动 core 指针 grab，既还不了这条 grab、也改不了 GDK 的账：13:50 读数 `post-xungrab grabbed=1`——此前已 XSync——是 grab 真没还，不是读数滞后。grab 不还，指针事件一路归本进程的拖拽 grab 窗，表现为拖完光标卡「+」、本窗与之后的拖入都僵住。修：drag-end 排空事件后先 `gdk_display_sync` 再读；仍挂着就 `gdk_seat_ungrab`，内部走 `XIUngrabDevice`，再 sync 复核。seat ungrab 只还本进程取下的 grab，不碰别家程序。
- **拖出收口后宿主收不到抬起**：拖拽期间指针归 GTK 的 grab 窗，抬起被它吃掉；宿主 `capture`/`pressed` 停在拖源上，悬停不刷新、下一个控件要重新按下才拖得动。修：`drag_external_send` 成功收口后清捕获、按下态、悬停并重绘。
- **悬停期取数据 + `GTK_DEST_DEFAULT_DROP` = 源被提前收口，拖出秒死 / 拖不进来**：`gtk_drag_selection_received` 收到数据后只要 dest 带 `GTK_DEST_DEFAULT_DROP`，就**无条件 `gtk_drag_finish`**——它不知道这次数据是悬停期主动取的。我们的 motion 处理器在首次进入时就 `gtk_drag_get_data`，数据一到即给源发 XdndFinished：自家窗口做落点时数据是即时回的，起拖约 33ms 就收口——读数 `alive_us≈33ms dest=self get_calls=1`，表现为第一趟拖不动；外部拖入同理在悬停期被结束，拖不进来。修：`gtk_drag_dest_set` 改 flags=0，`drag-drop` 里自己请求数据、`drag-data-received` 的投递分支自己 `gtk_drag_finish`；motion 期取到的数据只缓存。
- **GTK 在 drop 前必发一声 drag-leave**：`_gtk_drag_dest_handle_event` 处理 `GDK_DROP_START` 时先调 `gtk_drag_dest_leave`，给控件反高亮，紧接着才发 `drag-drop`。原来 leave 处理器当场收会话，紧随的 drop 就因 `drag_ext_window == 0` 被丢掉——真机表现=拖入松手没有接受——日志是 `dest leave` 后紧跟 `dest drop`，且 drop 时 `sent=0 have=0`。修：leave 记成待收，用 `g_idle_add`，同一趟里来了 drop 就取消它；drop 之后迟到的数据回包按「会话已收」忽略。
- **无修饰键时系统默认动作是 MOVE，文件被搬走 / 文本被拒**：Windows 的 `SHDoDragDrop(..., pdsrc=NULL)` 用系统默认 drop source，`QueryContinueDrag` 在无修饰键时报 `DROPEFFECT_MOVE`；mac 的 Finder 同卷拖放默认也是移动。演示载荷指向仓库文件，第一次拖出就把 `README.md` / `experience/adaptation.md` **搬出了仓库**，第二趟 `exists=0`，mac 日志实证；Windows 文件拖出读数 `effect=2` 同样印证；而只收 COPY 的文本落点，即记事本，把默认 MOVE 直接判拒——`query cf=13 hit=1` 但 drop 不取数据。修：`drag_external_send` 起拖时按**起拖时的修饰键**定唯一效果——无修饰/Ctrl=COPY、Shift=MOVE、Alt=LINK；不再把三档一起放开，交给系统去猜默认值。
- **RichEdit/Win11 记事本优先认 RTF，纯文本不兜底**：RichEdit 控件注册并优先粘贴 `Rich Text Format`——其次 RTF-noobj / 私有「RichEdit 文本和对象」——只有这些都没有才退回文本。我们只给 `CF_UNICODETEXT`/`CF_TEXT`/`text/plain` 时，记事本悬停期一直向私有富文本槽取数——真机 `GetData cf=<私有注册号> refused` 刷屏——松手判 0。修：文本拖出同时生成最小 RTF 档，UTF-8→UTF-16、`\uN?` 转义中文、`\par` 换行，并加入格式枚举；`GetClipboardFormatName` 反查名保留，便于再遇私有格式对号。
- **Win11 记事本不收文本拖放，目标侧限制、不是源的问题**：本栈文本拖出到浏览器、落回本窗都能成；拖到记事本时它只在悬停期问 `DragContext`/`IsShowingLayered`，Shell 内部格式，与 `CF_UNICODETEXT`，松手不取数。对照实验：**从浏览器选中文本拖进同一个记事本也粘不进去**——该版本记事本不支持文本拖放，只接文件打开。结论：文本拖出以浏览器/编辑器为验证目标；演示页文案不再承诺记事本。RTF 档仍保留，真实 RichEdit 目标按文档优先认 RTF。
- **兜底**：C 侧另有起跑线重起一次——`begin/drag-end` 同秒、未进别家窗、键仍按着 → 用 `event=NULL` 重起，读数 `session-retry/try=`——以及投放侧按 `GdkDragContext` 认新会话，变了就补 LEAVE、清状态、重新取数，读数 `dest new/ask/recv/leave/drop`；外部拖出没起来时组件层先清残留投放会话再回落，应用内会话不再被挡。这些是防御层，根因是上一条。
- **mac 拖入被当场拒，文件拖不进窗口**：`draggingEntered:` 把 MoonBit 上一拍写回的效果位原样当答复返回，而首拍那位还是 0——ENTER 事件刚压进队列、宿主还没抽——于是 AppKit 判「无处可放」，之后 `draggingUpdated:`/`prepareForDragOperation:`/`performDragOperation:` 都不再来问——不是格式问题，是**答复晚了**。改：与 Win32 支 `DragEnter` 的承诺值同一条口径，认出格式，即 `wm_dnd_buf_len >= 4`，就先顶一档——源允许复制给复制，否则给 Move/Link/源掩码；认不出格式才给 None。承诺值同时写回效果位，免得「Drop 比 MoonBit 第一拍快」时 `performDragOperation:` 自己拒收。`draggingUpdated:` 里「源只发 updated 不发 entered」那条补发支路同改。验证归 mac 真机：Finder 拖文件与文本编辑器拖文本进窗口都要能落。

## 托盘僵尸注册项：退出不注销 + 编码 abort 两条同批 · 2026-10-20 · Ubuntu 24.04 + X11 + Cinnamon 6.0.4 · 面板侧 xapp-sn-watcher

- **现象**：showcase 退出后托盘里留一个空白占位图标。注册表读数，`org.kde.StatusNotifierWatcher.RegisteredStatusNotifierItems`，里能看到 `":1.623/StatusNotifierItem"`、`":1.654/StatusNotifierItem_2"` 这类条目，而 `NameHasOwner` 对同一服务名回 `false`——即在册项指向已经没有主人的连接；`~/.xsession-errors` 里 xapp-sn-watcher 反复报 `g_variant_new_string: assertion 'g_utf8_validate (string, -1, NULL)' failed`，紧随一条 `g_variant_ref_sink: assertion 'value != NULL' failed`。`/StatusNotifierItem_N` 这套对象路径是本库的指纹，由 `sni.mbt` 的 `next_item_path` 派生，其它 KDE 系只用 `/StatusNotifierItem`。
- **根因一，在册不清**：注销只挂在 `Tray::remove` 上，而 `examples/showcase/main.mbt` 的收尾只有 `host.run()` 一个调用——关窗、Ctrl+C、崩溃三条路都不经过它，`UnregisterStatusNotifierItem` 从没发出过。SIGINT/SIGTERM 走默认处置是**当场终止**，主循环连一拍都跑不到，任何兜底都无处安放。
- **根因二，崩在这一拍**：MoonBit 的 `String` 按 UTF-16 码元存放——实测 `"a🎉b".length()=4`，迭代给码点：97 / 127881 / 98——`@utf8.encode` 对未配对代理对是 `abort("invalid surrogate pair")`——实测 `String::from_array(['x', (0xD83D).unsafe_to_char(), 'y'])` 一编码，整个测试 exe 以 `PanicError @ moonbitlang/core/abort.abort` 挂掉。所以这条**不会把非法字节送上线**，而是先把进程打死，正好又落回根因一。顺带一条否证：字符串切片切在代理对中间不会留下半截码元，`"a🎉b"[1:2].length()=0`；字面量里的 `\u{D83D}` 编译期即被拒——孤立码元的来路只剩外部拼进来的串。
- **断言失败不能算在库的编码上**：把 showcase 那条真实 `GetAll` 应答——中文标题 + `·` + 🎉 + 32/16 两档 `IconPixmap`，5624 字节——交给 GVariant 的**非 trusted** 解析，即 `g_variant_new_from_bytes`，严格校验填充与 UTF-8，正是 watcher 那两条断言的同一套判据，头 `a{yv}` 与体 `a{sv}` 都过。再对照日志时序：断言成批出现在 watcher 自身启动的那一瞬间，08:18:13.887，同批一起 `Adding` 的 `:1.136` / `:1.533` / `:1.557` 都不是本库的项；`g_variant_new_string` 前一条 `Could not get properties for :1.623` 说明它已经在给已死的服务名补读属性。故断言归因未定，本轮不声称修掉了它——只把「我们这一侧永远交出合法 UTF-8」做成硬保证。
- **修复**：
  1. `gui/dbus/sock.mbt`：线路出口 `utf8()` 前插 `replace_lone_surrogates`——孤立代理对逐个换 U+FFFD 再编码，干净串原样返回、不多分配一次，既不 abort 也保证上总线的字节合法。入向本来就走 `@utf8.decode_lossy`，无需再动。
  2. `gui/dbus/dbus_stub.c` + `bus.mbt`：新增 `yue_dbus_install_quit_signals` / `yue_dbus_quit_signal`。信号上下文里只置一个 `volatile sig_atomic_t`——不分配、不 IO、不调 MoonBit 蹦床，符合「不做 C→MoonBit 回调」——由主循环下一拍取走；第二次同类信号恢复 `SIG_DFL` 再 `raise`，循环卡死时连按仍有效。`_WIN32` 支留空实现，Windows 通知区的项由 shell 随进程回收，不需要注销。`poll` 被信号打断原本就回 0 视作超时，走 `yue_dbus_poll` 的 EINTR 分支，泵不必改。
  3. `gui/dbus/sni.mbt`：加进程级在册表 `live_items`——`Item::create` 注册成功入表，`sni_drop_item` 出表——与 `sni_unregister_all()`，逐项注销、幂等。
  4. `gui/shell/tray.mbt`：`Tray::new` 只在 SNI 注册成功后装信号兜底并置 `quit_watch`，没建过托盘的应用每拍零开销；对外补 `remove_all_trays()` 与 `quit_requested()` 两个门面。
  5. `gui/widget/app.mbt`：`App::step` 在泵之后读 `@shell.quit_requested()` → 走 `shutdown()`；`close_window` 的整体退出支、`App::quit`、`App::shutdown` 三处都先 `@shell.remove_all_trays()`。widget 层只依赖 base/shell，见 `gui/widget/moon.pkg`，所以信号与在册两条口子都从 shell 门面出，不让 widget 直连 dbus。
- **验证**，助手侧无头判据：`moon check` 于 gui 包零错误；`moon test dbus shell widget` 210/210；`moon test` 全库 1079/1079。新增两条库测试：`gui/dbus/wire_wbtest.mbt`「线路字符串恒为合法 UTF-8」——中文+`·`+emoji 编码字节数、🎉 的四字节序列、孤立代理对换成 `EF BF BD` 且 `Buf::string` 的长度前缀按替换后计；`gui/shell/tray_wbtest.mbt`「退出兜底：未收到退出信号时不报退出，批量注销可空跑」。端到端用 `experiment/tray_zombie_probe`——只建托盘项、不开窗，`PROBE_MODE=async|sync|hold`——配注册表差集读数：正常退出、`kill -INT`、`kill -TERM` 三条各跑后 `comm -13` 前后差集为空——读数 `PROBE-SIGNAL ticks=18` / `PROBE-EXIT how=signal`，退出码 0；`kill -9` 那次该条目 4 秒后被 watcher 自己摘掉——**watcher 什么时候清理已断开的在册项不由我们定**，另一条死名在册实测挂了 25 分钟以上。异步「发完就走」与同步「等 watcher 应答」两种注销各 4 趟都不留残留，故没保留同步形态——多一层最坏 1.5s 阻塞、无收益。
- **同批记录的一条测试副作用**：库的 SNI 单测在**真会话总线**上注册——`sni_wbtest.mbt` 的 `Item::create("wbtest-*")`、`tray_wbtest.mbt` 的 `Tray::new("libyue-wbtest")`——跑一次 `moon test dbus` 后注册表实测多出一条 `":1.963/StatusNotifierItem"`，主人已死。面板上就会多一个空白占位——这是开发节奏里看到「僵尸」的另一个来源，具体漏在册的分支未定位。
- **待真机**，使用者判据：`moon run examples/showcase` 后按 ① 点窗口关闭 ② 终端 Ctrl+C ③ `kill -9` 三种方式各退一次，每次退完扫注册表看 `libyue-showcase-tray` 那条的宿主名是否还在；同时 `tail -f ~/.xsession-errors` 看运行期间是否还有 `g_utf8_validate` / `g_variant_new_string` 断言与本库的项同时出现。

## Linux 系统读数两处缺口：壁纸分派表漏 gsettings 系桌面、xclip「无文本」被当命令失败 · 2026-10-28 真机「Cinnamon 壁纸读不到 / 剪贴板报退出码 1」

**症状一**：Cinnamon 真机 `wp_get()` 报 `UnknownDesktop(Cinnamon)`——桌面环境**认得出名字**，`desktop_parse_value` 命中 X-Cinnamon，但 `wp_get_linux` 的分派只有 XFCE/GNOME/KDE 三条，其余一律 UnknownDesktop。**症状二**：`cbw_get_text()` 报 `CommandFailed(xclip: 退出码 1（Error: target STRING not available）)`——这句 xclip 正文的含义是「剪贴板里没有可转成文本的目标」，即空、或装着图片/文件，与 GtkClipboard 档的「读到空串」是同一件事，却走了命令失败那条路。
**修复一，表化分派**：新增落点表 `wp_gsettings_target(env)` → `WpGsettings { schema, keys, uri }`，读写共用一张：GNOME 与同 schema 的衍生桌面 Budgie/Unity 取 `org.gnome.desktop.background` 的 `picture-uri`，回退 `picture-uri-dark`；Cinnamon 取自家 fork 的 `org.cinnamon.desktop.background picture-uri`、MATE 取 `org.mate.background picture-filename`——**MATE 存的是裸路径**，`uri=false` 让写值不再套 `file://`，套了就是给一个路径键塞 URI。`wp_get_gnome`/`wp_gnome_set_args` 退役成表驱动。LXQt，即 pcmanfm-qt 的 conf，与 Deepin，即 dde 自有 schema，不进表：机制不同源，硬套 GNOME 的键只会读出与桌面无关的值，诚实报 UnknownDesktop 更好。
**修复二，错误归位**：`cbw_xclip_no_text` 认 xclip 的 `not available` 正文 → 归 `NoText`；演示侧同步把「当前无文本（空或图片/文件）」与「读不到」分成两句，不再混报。
**教训**：① 「认得出桌面」不等于「会读它的壁纸」——分派表要按**机制**列全，新增一族配置，即 gsettings，时用一个纯函数表把 schema/键/值形态收在一处，比在分派点堆 if 更容易核漏；② 子进程的错误正文里带着语义——xclip 这句就是「没文本」——只按退出码归错会把常态当成故障；③ 值形态是键的属性不是桌面的属性——同为 gsettings，URI 键与路径键的写法不同。
**验证**：`wallpaper_wbtest` 新增落点表用例——Cinnamon/MATE/GNOME 系逐条 + 不在表内的六个环境给 None——与写参数表用例，MATE 裸路径、GNOME file://；`clipboard_watch_wbtest` 新增 `cbw_xclip_no_text` 判据。库门禁 1171/1171、`moon check` 零警告、showcase 构建过。**待真机**：Cinnamon 上壁纸读出当前图、设置生效；Linux 剪贴板空/图片时显示「当前无文本」。

## 子进程环境钉 `LC_ALL=C` 把中文路径吃成问号：字符集与消息语言要分开设 · 2026-10-28 真机 Cinnamon「壁纸: /home/lkyh/??/?????.jpg」

**症状**：gsettings 系桌面的壁纸读数里，非 ASCII 段逐字变成 `?`——命令行同一条 `gsettings get` 给的是 `'file:///home/lkyh/图片/哈巴雪山.jpg'`。同一行文本里应用自己的中文，即「打印机: 1 台」，显示正常。
**定位**：丢字不在本仓的读取链——mac 无头跑同一条链，`pr_run` 捕获 → `@utf8.decode_lossy` → `wp_parse_gsettings_uri` 剥引号与 `file://`，字节级等值，`图片`→22270/29255 原样回来，中文完好；显示字体也没问题，同一行别处的中文正常。剩下的唯一差异是**我们给子进程的环境**：`pr_env_posix` 一条 `LC_ALL=C` 打天下。`LC_ALL` 覆盖所有 locale 类别，把 **`LC_CTYPE` 字符集也钉成 ASCII**——`locale charmap` 在 `LC_ALL=C` 下给 `US-ASCII`/`ANSI_X3.4-1968`——于是按 locale 字符集转一遍再输出的那一段把不可表示的字符逐个换成 `?`。
**当初为什么钉 C**：解析依赖英文文案——pactl 中文环境输出「音量:」而非 `Volume:`，见本文件「音量双后端」条；xrandr 的 `connected` 同理。但那件事归 **`LC_MESSAGES`** 一类管，与字符集无关。
**修复**：`pr_locale_vars(ctype, lang)` 出一对变量——`LC_CTYPE` 随会话，取父进程 `LC_CTYPE`、其次 `LANG`，空/`C`/`POSIX` 都算没挑到、退 `C.UTF-8`；`LC_MESSAGES=C` 固定英文；**不再设 `LC_ALL`**。`LANGUAGE` 不透传——GLib 的消息翻译优先看它，透传会把文案带回本地化；`LC_NUMERIC`/`LC_TIME`/`LC_COLLATE` 一律不设＝保持 C，数字与时间格式不因转发 LANG 而变。
**教训**：① 「让输出语言恒定」和「让输出字符集恒定」是两件事，用一条 `LC_ALL` 同时钉死，代价是**所有非 ASCII 数据**——路径、文件名、书签标题、打印机名——静默变问号，数据坏掉不像解析失败那样会报错，只以「看着像乱码」的形式在真机暴露；② 子进程白名单环境里，凡是**值可能非 ASCII** 的读数，字符集必须显式随会话；③ 判据要能自动跑：`locale charmap` 一条命令就把「子进程字符集＝会话字符集」钉成用例——会话本身无 UTF-8 locale 时打印跳过，不误伤纯 ASCII 主机。
**验证**：`procrun_wbtest` 新增 `pr_locale_vars` 纯函数用例——优先级、`C`/`POSIX`/空串退化、表内无 `LC_ALL`——与子进程实测两条，`LC_MESSAGES=C`、`LC_CTYPE` 非 ASCII、`LC_ALL` 未设，及 `locale charmap` 非 ASCII；旧「环境固定 C locale」用例改钉新契约；`monitor/envx/windowctl` 三处提到 LC_ALL 的注释同步改口径。库门禁 1173/1173、`moon check` 零警告。**待真机**：Linux Cinnamon 重开「系统探针 → 系统与桌面」，壁纸行应显出 `/home/lkyh/图片/哈巴雪山.jpg`；音量、显示器、窗口列表三处解析不因换 locale 对而退化。

## RTL 行不贴右缘：Pango 把 LEFT/RIGHT 对齐档按段落自检方向解释 · 2026-10-28 用户 Linux 真机截图「字体排版」页

**症状**：演示板「基础组件 → 字体排版 → 各语言的行首方向」：四行以阿拉伯/波斯/希伯来/乌尔都字母起头的串——`align=End` + `direction=Rtl`——全部贴**左**缘，而同一批里以拉丁字母起头的「RTL 行里的 1234 / ABC…」同款配置正确贴右缘。截图逐行量墨迹：四行 left=197..198 贴左，末行 left=1013 / right=1262 贴右。
**定位与本机复现**：五行走的是同一条路径——`ui.text` 缺省 `wrap=true` → Linux 侧「设 Pango 宽度 + `pango_layout_set_alignment`」档——配置逐位相同、唯一差异是内容。纯 C 探针，本机 Pango 1.52.1、渲染进位图再扫墨迹、与库同口径，直接复现：同一段含 RTL 字符的内容，`PANGO_ALIGN_RIGHT` 渲染后墨迹落在左缘 1..206、`PANGO_ALIGN_LEFT` 反而落在右缘 793..998；纯 LTR 内容各档全部正常。
**根因**：Pango 新版布局把 `PANGO_ALIGN_LEFT/RIGHT` 当**相对段落方向**的 start/end 解释，而段落方向缺省 `auto_dir=TRUE` 按「首强字符」逐段自检——首字是 RTL 字符的段被整段判成 RTL 基方向，对齐档跟着翻转；末行首字是拉丁字母，判 LTR，所以是对的。mac 臂自算 dx 偏移、Windows 臂 DWrite `TRAILING`——基方向 LTR——都是**绝对**左右档，只有 Linux 踩这一档，所以只有 Linux 错。
**修复**：`gui/text/stub.c` 的 `pt_make_layout` 加一行 `pango_layout_set_auto_dir(layout, FALSE)`——段落方向钉死在 `pango_context_set_base_dir` 设的全局档上，缺省 LTR、与文本层契约「默认 Ltr 即现状」一致，应用调 `set_base_dir(Rtl)` 后整窗按 RTL。这同时修掉一个暗差异：此前 auto_dir 让 Linux 逐段自检基方向，Win/mac 固定 LTR，同一段混排串在 Linux 的段内排序本就与另两平台不同；钉住后三平台同口径。纯文本与富文本，`rt_build`，全走 `pt_make_layout`，一处覆盖。
**验证**：新增 wbtest「RTL 起头的串盒内对齐仍是绝对左右缘」——修前红，End 档墨迹贴左；修后绿，回证测试确实守着这个回归；本机探针 pin 后四组读数：无论内容 LTR/RTL、上下文基方向 LTR/RTL，`ALIGN_LEFT` 一律落左缘、`ALIGN_RIGHT` 一律落右缘。库门禁 1177 条，除两条既有红，`text/spacing_wbtest` 字距与 `win/maximize_wbtest` 最大化，前批已记录、与本批无关，全绿；`moon check --deny-warn` 零输出、`moon build examples/showcase` 通过。
**教训**：①「对齐参数」在各排版引擎并不天然同义——Pango 的 LEFT/RIGHT 是相对段落方向的，拿到手先量落位再当绝对值用；② 排版引擎的「自动」行为，auto_dir 首强字符自检，会连坐看似无关的属性，对齐，不想让它自作主张就显式钉死；③ 跨平台库的平台缺陷，先看「另两个平台为什么对」再动刀——mac 自算 dx、Win 绝对 TRAILING 反证了 Linux 该给绝对档。

## WebKitGTK 下载直链死在 `WebKitPolicyError/102`：decide-policy 连着信号时 `return FALSE` 是 use，不是「交回引擎默认」 · 2026-10-29 用户 Linux 真机 `examples/browser` 截图

**症状**：示例地址栏直接输 http 下载直链 .dmg，事件区只有「加载失败（结构化原因）WebKitPolicyError/102 http://…」，`download` 信号与下载事件从未出现；本地页 blob 锚点下载同样无声。`8db2a3f6` 的保存对话框代码从未被走到。2026-10-30 更正：view 级 `download` 信号在现代 WebKitGTK 根本不存在，「转进 download 信号」的前提不成立——见文末对应条目。
**根因**：`wb_on_decide_policy` 只答 NEW_WINDOW_ACTION 即 ignore，其余 `return FALSE`，注释当作「交回默认处理」——但 decide-policy 一旦连了处理器，返回 FALSE 的语义是「不拦」= 引擎按 use 走「试着展示」；`application/octet-stream` 展示不了，落到 PolicyError/102 即 CAN_NOT_SHOW_URI。正确的路是 `webkit_policy_decision_download()` 把响应决策转成下载、进 "download" 信号；「不可展示 MIME 自动下载」的引擎默认只在**没连处理器**时存在，连了信号与要引擎默认不可兼得。
**判据**：① `WebKitPolicyError/102` 就是「决策被答成 use 但展示不了」的指纹，看到它先查 decide-policy 处理器答了什么；② 「事件区有没有下载事件」分两层——一条下载事件都没有是信号层断，本条；有事件没弹框是处理层断，弹框实现；先分层再动刀。
**修法**：`wb_on_decide_policy` 补 RESPONSE 分支：`webkit_response_policy_decision_is_mime_type_supported()` 为假 → `webkit_policy_decision_download(d)` + return TRUE——转进 "download" 信号，落点/取消在 `wb_on_download`；可展示响应与导航决策仍 return FALSE。同批示例层删掉两处 `set_new_window_policy(pol_newwin.val)`：库契约 `in_place=true` 是「当前 pane 导航过去」，示例的放行=自开独立窗，两层各干一件事曾把主窗也带到目标站——`window.open` 测试一开新窗主窗跟着跳。
**验证**：改动全在 `#ifdef WB_HAVE_WEBKIT` 分支，mac 编不到；门禁 `moon check` 零输出、`moon test` 1599/1599、`examples/browser` 构建通过。真机复验，用户 Linux：①先 `rm -rf modules/gui-webview/build && moon clean && moon build`，见 build.md §9 归档缓存；②地址栏直链 .dmg → 弹保存框、确定落盘、取消无文件；③本地页「发起 blob 下载」→ 放行档弹框、拦下档落地取消；④`window.open` → 另起一扇独立窗，主窗不再跟跳。
**教训**：① WebKitGTK 的 decide-policy 是「连了就得答」的信号——只处理关心的分支、其余 return FALSE，等于把不关心的分支强行答成 use；② mac 门禁编不到 Linux 分支 + 桩走预编归档缓存，两层都会吞掉「改动进没进」的验证，真机先清缓存再判行为；③ 引擎「默认行为」与「有处理器时的 FALSE」不是一个东西，接引擎信号前先量好这两层的分界。

## WebKitGTK 下载链路整条是死代码：view 级 `download` 信号在现代 WebKitGTK 根本不存在 · 2026-10-30 本机 webkit2gtk-4.1 2.52.6 源码核对 + 信号表探针

**更正**：上两条——8db2a3f6 弹框、921e6ab3 转下载——都在给一条**不存在的信号**铺路：`WebKitWebView` 没有 `"download"` 信号，`g_signal_lookup("download", WEBKIT_TYPE_WEB_VIEW)` 在 WebKitGTK 恒 0，`wb_on_download` 从未被连接过。所谓「Linux 事件区报了下载事件」其实是示例自己 `ev("已发起 blob 下载…")` 的固定文案，不是引擎回证；探针，NG_WEBVIEW_DL_LOG，一行不打也是同一根因——处理器压根没挂。
**证据**：① WebKit 源码 2.34/2.36/2.38/2.40/2.44 的 `WebKitWebView.cpp` 信号枚举都没有 DOWNLOAD——view 级下载信号是 WebKit1/远古 WebKit2 时代的口；② 本机装上 webkit2gtk-4.1 2.52.6 后信号表探针实测：`view/download=0`、`view/decide-policy=84`、`download/decide-destination=107`。注意 `g_signal_lookup` 前必须先 `g_type_class_ref`，否则类未实例化查表恒 0，会得出假阴性。
**现代钩子**，webkit2gtk-4.1 老 GLib API：入口是 **context 级 `WebKitWebContext::download-started`**——2.40 标记 deprecated 但 4.1 仍发射；`webkit_download_get_web_view()` 可归属回发起视图。落点是**每个下载的 `WebKitDownload::decide-destination`**，带建议文件名——不接它引擎默认**悄悄写进 `~/下载`**，老 API 的 class handler 就是这个默认，文件可能有、对话框与事件全没有；接了 `return TRUE` 即扣住落点自己定，2.40+ 契约=落点没定或没 cancel 前引擎不写盘，`webkit_download_cancel()` 会顺手释放挂起的落点回调——析构 `g_critical` 那条 bug 口由此收掉。`<a download>`/blob 锚点不用 decide-policy 表态：非 Cocoa 平台 UI 进程把「Use + shouldPerformDownload」强转 Download，见 `WebPageProxy.cpp` 的 `forceDownloadFromDownloadAttribute`；直链下载走 RESPONSE 决策转下载，两条路都汇进 download-started。
**修法**：`wb_on_download_started`——kind=10 上报源 URL + 拦下档就地 cancel + 给该下载挂 decide-destination——→ `wb_on_decide_destination`——放行档：`gtk_native_dialog_show` 异步弹保存框，modal + transient parent，响应回调里 `webkit_download_set_destination`/cancel——→ `wb_on_dl_response`——落点=绝对路径；本地路径拿不到按取消收口；**对话框的 unref 挪 idle**，响应回调还在对话框自己的 response 发射链里，当场释放可能析构正在发射的对象。挂起槽 8 个 ref 住下载与对话框，`wb_destroy` 按 `p->v==v` 收口。掩码位 1 改探两条现代钩子同时在位；`download-started` 按 context 挂一次，没给 data_dir 的视图共享默认 context，回调里按发起视图归属。
**判据**：① 新接一个引擎信号前先跑 `g_signal_lookup` 探针，先 `g_type_class_ref`；信号不存在就查「这个引擎的现代钩子叫什么」，别按另一平台的同名信号望文生义；② 「上层有没有收到事件」必须用引擎回证，kind=10，判断，示例自己打的文案不算；③ 事件分层照旧：连一条 kind=10 都没有=入口断，本条；有事件没框=落点处理断。
**验证**：`gcc -fsyntax-only -DWB_HAVE_WEBKIT`，本机 2.52.6 头；`moon check` 零警、`moon test` 1177 中 1175，2 红为本机无 WM/字体度量环境固有，stash 改动复跑同红；`examples/browser` 构建过且归档新指纹在链参里，`libgui_webview-30fa9c57.a`。真机复验，用户 Linux、`NG_WEBVIEW_DL_LOG=1` 跑：①掩码位 1 在位；②演示菜单「策略触发·下载(当前页)」→ WB-DL started/放行 逐拍有日志、保存框弹出且预填建议名 → 确定落盘、取消无文件；③地址栏直链 .dmg 同上；④拦下档 → started 有日志、无框无文件；⑤下 8+ 个下载连发不崩，挂起槽满交引擎默认。
**二排**，同日真机取证，钩子仍没挂的第二层坑：推上去后真机「还是一样」，但 `~/下载` 里躺着当次测试的 `ngui.txt`，内容=probe 文本，与 `.dmg`，时间戳 07:34、exe 07:28 新构建、新符号在二进制里——下载**走通了引擎**，只是落进默认 `~/下载`，即 download-started 处理器依旧没被调用。根因是上一条验证自己埋的：**`g_signal_lookup` 只认「类已实例化」的类型**——探针里先 `g_type_class_ref` 了三个类所以全查得到；真机 app 里 `WebKitDownload` 从未有实例、类从未实例化，wb_create 守卫里 `g_signal_lookup("decide-destination", WEBKIT_TYPE_DOWNLOAD)` **恒 0 → 守卫判假 → 钩子整个没装**——WebContext 有默认实例、lookup 正常，恰使误判只落在半边，更难一眼看穿。本机探针实钉：同一进程里 `webkit_download_get_type()` 后直接 lookup=0，`g_type_class_ref` 后 lookup=5。修法：`wb_ensure_signal_classes()`——class_ref WebContext/Download 两个类，GObject 永久缓存——在 `wb_signal_mask` 与 wb_create 的守卫前各调一次；**判据升级：`g_signal_lookup` 当守卫前必须先保证类已实例化，否则「信号在位」的判断本身就是假的**；取证判据补一条——`~/下载` 出现测试产物 = 引擎默认落点路径在走 = 事件层钩子没挂上，这比「没弹框」精确得多。
**三排**，下载通了之后的伴生噪音：钩子挂上、保存框弹出落盘成功后，事件区每次下载仍伴一行「加载失败（结构化原因）WebKitPolicyError/102 …」。这不是故障：102 = `WEBKIT_POLICY_ERROR_FRAME_LOAD_INTERRUPTED_BY_POLICY_CHANGE`，WebKitError.h 对枚举，是引擎对「这次导航被策略决定打断」的例行口令——响应/锚点被转成下载的当下，主帧加载按「失败」收尾，下载事件，kind=10，与保存框是同一件事的另一面。修法：`wb_on_load_failed` 对 `domain == WEBKIT_POLICY_ERROR && code == 102` 直接 return——本栈唯一来源就是转下载，不再当加载失败上报；mac 侧下载转换不产生等价失败事件，无需对齐。**判据：下载链路接好后，看「事件区有没有 102」别再当信号层断的指纹——它已经反转为「转下载成功」的伴生回证。**

## 命令行工具与 GUI 库的链接边界：`gui/sys` 在 Linux 上自带 GTK · 2026-11-02 mng 解耦实测

- **现象**：`mng` 只用到进程原语与单实例唤起，却把 `@shell`/`@win` 带进闭包；改走 `@sys` 后 `ldd` 里依旧一片 `libgtk-3`。
- **根因，两层**：① 单实例门面在 `shell`，依赖 `win`；② 更隐蔽的是 `gui/sys` 自身在 Linux 上就嵌 GTK——`sys_stub.c` 的剪贴板实现调 `wm_clipboard_*`，`scripts/prebuild.py` 因此把 `libyue_win_stub.a` + `pkg-config gtk+-3.0` 的链接参数挂在 **sys 包** 上，即 `link_configs` 的 `package` 字段。只要闭包里出现 `gui/sys`，GTK 开发包就是构建期硬依赖。
- **判定方法**：`ldd <exe>` 看有没有 `libgtk-3`；`link_configs` 是按包下发的，包名在哪、flags 就跟到哪。
- **处置**：工具侧不复用 GUI 库——`tools/native-gui-tools/proc`，fork/execvp 成组 + 超时 + 探活/杀/节拍，标准头；`inst`，套接字唤起客户端，帧格式与 shell 通道逐字一致；两者在 tools 内自给。成组 kill、`argv[0]` 必须是程序名、exec 失败要在父进程用 `access()` 先判——子进程退出码 127 与真实退出码不可区分——三条坑已在实现里钉住。
- **判据**：任何「要装才能用」的命令行工具，先 `ldd` 检查闭包链接物；库的包边界不等于依赖边界——C 桩里的跨包符号引用会把整条依赖链带进来。

## Wayland 会话的「返回成功但无效」：X 工具族按会话探针降级 · 2026-11-03 · P0

**判据**：`XDG_SESSION_TYPE`，loginctl/DE 都写，认 `wayland` / `x11`，没写时回落 `WAYLAND_DISPLAY` 非空即 Wayland；其余值，`tty` / `display-manager`，归 Unknown——**不猜 X11**，否则又拿假数据当真实会话。实现在 `gui/sys/session.mbt`，纯解析 `session_type_of` + 读环境 `session_type`；Windows/macOS 走各自平台支，不经过这道门。
**降级的三条**：夜间色温——`nl_supported()` false，设/复位给 `Unsupported`；窗口管理——`win_supported()` false，`win_list`/`win_activate`/`win_close` 给 `Unsupported`——`wmctrl -l` 在 Wayland 下只列 X 兼容层那部分，给残缺集合比给错误更坏，因为它看着像真列表。**不降级的**：显示器枚举——XWayland 那块虚拟屏确实存在，返回 `Unsupported` 等于撒谎；改为在文档与函数注释钉死「名形如 `XWAYLAND0`、不代表真接的屏」的读数口径。
**为什么不能靠工具探测**：`pr_run` 保留 `DISPLAY`/`XAUTHORITY`，见 `procrun.mbt:198-214`，Wayland 会话里 redshift / xrandr / wmctrl 都起得来、退出码都是 0——「命令存在 + 退出码 0」这条探测线在 Wayland 下**系统性失真**，能力探测必须先问会话再问工具。空闲与全局快捷键早就按同一形态降级——sys 桩 `DISPLAY` 空即 unsupported，win 桩热键支 `WAYLAND_DISPLAY` 非空即 unsupported——本批把剩下的族补齐同一口径。
**测试口径**：`session_type_of` 纯函数钉九档；`session_type()` 用 `envx_set` 在进程内改环境再断言——跑完还原本机值，原本没有的删掉——因此 Linux/Windows/macOS 同一份用例都能跑；夜灯与窗口管理的降级支只在 `sys_platform()=="linux"` 断言，非 Linux 打印 skip，它们各自的真通道在前。
**待复验**：Wayland 真机，Ubuntu GNOME Wayland / deepin Treeland，的会话读数与「夜灯不再空转」归用户，判据见 `测试文档/测试用例.md` 附录 E 与 spike S1/S2。

## Linux AT-SPI 桥 · 无障碍阶段 2 · 协议面全部本机实证，不留「推测能吃」 · 2026-11-04

at-spi2-core 2.52 装在开发机上——包为 `at-spi2-core`/`gir1.2-atspi-2.0`/`libatk-adaptor`；a11y 总线，registryd，本机就在跑——**方案里标「未核」的协议面全部实测定案**，实现零猜测：
- **总线地址**：会话总线 `org.a11y.Bus.GetAddress`，路径 `/org/a11y/bus`，返回 `unix:path=/run/user/1000/at-spi/bus_0,guid=…`；回落 `AT_SPI_BUS_ADDRESS`、再回落 `$XDG_RUNTIME_DIR/at-spi/bus`。
- **注册**：连上 a11y 总线后调 `/org/a11y/atspi/accessible/root` 上 `org.a11y.atspi.Socket.Embed`，**入参是 `(so)`，不是旧文献的 `(s,o)`——传本端唯一名 + 自己的根路径**；registry 随即将本端挂上它的根、广播 `ChildrenChanged`，并给本端发 `Properties.Set(org.a11y.atspi.Application, Id, v i)`。**没有 `RegisterApplication`**——2.52 的 Registry 接口只有 RegisterEvent/DeregisterEvent/GetRegisteredEvents，旧文献的注册流程已废。
- **路径方案**：应用根 `/org/a11y/atspi/accessible/root`，子对象 `/org/a11y/atspi/accessible/<n>`——参考实现是递增编号；本桥按 widget id 稳态寻址 `…/win/<id>`——编号每帧重排会让客户端缓存的身份抖动。
- **接口签名**，registryd 与活应用双路 introspection 核对：Accessible 的 Name/Description/Parent/ChildCount/Locale/AccessibleId/HelpText 是**属性**，走 org.freedesktop.DBus.Properties.Get；方法是 GetChildAtIndex(i)→(so)、GetChildren()→a(so)、GetIndexInParent()→i、GetRelationSet()→a(ua(so))、GetRole()→u、GetRoleName()→s、GetState()→au、GetAttributes()→a{ss}、GetApplication()→(so)、GetInterfaces()→as；Component 的 GetExtents(u)→(iiii)，coord_type 0=screen 1=window 2=parent；**Text 与 Value 在 2.52 全是属性/方法混合且没有 Get* 形式的旧方法**——Text 是 GetText(i,i)→s、GetStringAtOffset(i,u)→(s,i,i,s)、GetCharacterAtOffset(i)→i 等，Value 的 CurrentValue/MaximumValue/MinimumValue/MinimumIncrement/Text **全是属性**，调 GetCurrentValue 直接 UnknownMethod；Action 是 NActions 属性 + GetActions()→a(sss) + DoAction(i)→b。
- **事件**，libatspi 解码端源码定案，信号体只收 `siiv(so)` 或 `siiva{sv}` 两种：ChildrenChanged=(s "add", i 数量, i 0, v (so) 子引用, a{sv} {})；Focus/StateChanged=(s detail1, i, i, v (so) 源元素, (so) 应用根)。应用侧**广播**，无 destination，监听方按 match 规则收；registry 不中转，它只管 Listener 注册表。
- **角色/状态枚举值**取自 Atspi-2.0.gir：push_button=43、check_box=7、radio_button=44、slider=51、spin_button=52、text=61、combo_box=11、progress_bar=42、heading=83、link=88、frame=23、application=75、grouping=99、panel=39…；状态 enabled=8/focused=12/checked=4/read_only=43/multi_line=17/editable=7/has_popup=42/showing=25/visible=30/sensitive=24。
- **Text 偏移单位是字符**，方案坑清单那条：本桥按码点切片——`String::to_array()` 是 UTF-16 码元，BMP 汉字一元一字符；代理对暂不特殊处理，等 @text 逐字几何批一起收口。
- **不实现的与为什么**：GetMDIZOrder 返回 'n' 即 int16，本仓 GDBusValue 无 int16 变体，如实回 UnknownMethod 不硬编；Introspectable 不服务——libatspi/pyatspi 直调方法不 introspect，python-dbus 的懒代理会报 Introspect error 属噪音；逐字几何，即 GetCharacterExtents/GetOffsetAtPoint，等 @text 逐字几何接口；GrabFocus 回 false——焦点栈在 widget 层，桥不直改。
- **落位**：协议实现住 `gui/shell/atspi.mbt`——shell 同时看得见 dbus 与 win，快照读 `@win.a11y_row_tsv`、动作压 `@win.a11y_action_push`，不依赖 widget 包；dbus 包只加第三条任意地址连接——bus=2 + 记住路径供自愈。端到端在本机真总线验过：注册→树遍历→属性/几何/文本/值/动作查询→事件三连，ChildrenChanged/Focus/StateChanged，全通；无 a11y 总线的环境，即 CI/Windows/macOS，启动即失败并按背间隔重试，不崩不假成功。

## AT-SPI 断线自愈后的重新 Embed：唯一名核对 · 2026-11-04

dbus 包对 bus=2 断线自愈重建连接后，本端唯一名会变——新连接新 Hello——而 registry 里挂的还是 Embed 时的旧名，读屏从此看不到本应用，`atspi_alive()` 还报 true——状态说谎比重启更糟：重启至少用户知道出了问题。修法在 `atspi_tick` 的 Live 分支：Embed 成功时记下唯一名 `g_atspi_name`，每拍核对 `dbus_a11y_unique_name()` 与 `dbus_a11y_alive()`，不符即回 Idle 走既有背间隔重试——重走 `atspi_start` 时 `dbus_connect_a11y` 对已自愈的连接幂等，Embed 用新名重新注册，handler 安装幂等不动。判据抽纯函数 `atspi_needs_reembed(stored, now, alive)` 进 wbtest：名一致且活着才不动，名变了/连接没了/空名都该重注册。重新 Embed 后把 digest 置空，下一拍补发一次 ChildrenChanged 保证客户端刷新——registry 自身也会因 Embed 广播，双保险。

## AT-SPI 快照 TSV 往返的两处解析缺陷 + 读缓冲余量 · 2026-11-04 · 最坏行 canary 抓出

给 `a11y_row_tsv` 的读缓冲，1024B，做「最坏行」canary 时连带抓出 `atspi_parse_double` 两个真缺陷——**发布侧是 C 的 `%.10g`、解析侧是手写 MoonBit，两边口径没对过**：
- **小数累积错位**：原实现小数点后仍在给整数位 `v` 乘 10，`"1.5"` 算出 15.6、`"10.5"` 算出 105.6——HiDPI 下快照坐标全是小数，AT-SPI Component 几何自桥落地起就是错的——既有用例坐标全是整数，没抓到。修法：`in_frac` 标志把整数位与小数位分开累积。
- **不认科学计数法**：`%.10g` 对 ≥1e10 / <1e-4 的值就产出 `1e+300` / `1e-05` 形态，原解析器遇 `e` 直接 None——**整行从读屏树里静默消失**，解析失败的行 `atspi_rows_now` 跳过不报。修法：尾数后认 `e/E` + 带符号指数，按位乘除 10——指数范围内不引数学依赖；极值的浮点累积用区间断言钉，坐标口径用不到。
- **缓冲余量**：C 侧字段有界——name≤255 / text≤511 / role≤31 / state≤31 / value≤63 + 4 个 `%.10g` double——最坏行 ≈1000B，1024 只剩 ~3%，任何字段加宽都会静默丢行。`a11y_row_tsv` 缓冲放大到 4096，4 倍余量；canary 用例——各字段顶格 + 指数 double 经 publish→readback 全链往返——钉住；注意测试数据别越界——`1.797693135e+308` 超 DBL_MAX，C 侧 strtod 溢出成 `inf`，`%.10g` 印出 `inf` 照样整行丢，坐标不可能是 inf，解析器如实不认。
- **已知边界，不修**：`dbus_set_call_handler` 是单槽，AT-SPI 占用后其他模块再注册会把它顶掉，反之亦然；当前无冲突——SNI 的 items/menus 与单实例 Wake 在 `Conn::handle` 里先于 `g_on_call` 被接走。要多路复用等真有第二个消费者再说。

## xdg-desktop-portal 客户端 · Wayland P1 · request 路径派生与后端路由本机实证 · 2026-11-04

- **Request 路径**：调用方自造 `handle_token` 塞进 options 末位；portal frontend 建 Request 对象于 `/org/freedesktop/portal/desktop/request/<sender>/<token>`，**sender 段 = 本端唯一名去掉冒号、点换下杠**，`:1.850` → `1_850`，frontend 1.18.4 AddMatch 规则抓包定案、不是文档猜的；结果走 `org.freedesktop.portal.Request.Response(u code, a{sv} results)` 信号，0=成功 1=用户取消 2=失败。同步调用仍走普通 method call，拿 handle 那种；异步握手才建 Request。
- **后端按桌面路由、按需激活**：frontend 读 `XDG_CURRENT_DESKTOP` 选 impl 后端。本机，KDE 会话，`org.freedesktop.portal.GlobalShortcuts.CreateSession` 一发过去，frontend 就给 `org.freedesktop.impl.portal.desktop.kde` 加了 match 规则并 **D-Bus 按需激活了 KDE 后端**——`xdg-desktop-portal-kde` 5.27.11；它的 `kde.portal` Interfaces 清单里确实有 GlobalShortcuts。**GTK 后端 1.15.1 没实现**——`gtk.portal` 清单无此项，且 `UseIn=gnome`——本机会话当时实际跑着 GTK 后端，故调用报错。结论：GlobalShortcuts 能不能用取决于当前会话跑的 impl 后端，不取决于 frontend 接口在不在。
- **门面形态差**，方案 §五 定的：X11/Win/mac 是「注册 + 每帧 poll」；Wayland portal 是「绑定 + 信号回调」——授权每次绑定一弹。壳层按会话类型分派，应用侧一个入口。
- **退订是新增能力**：portal 的 Response 是一次性信号，`bus.mbt` 原有订阅只增不删，回调会攒；本批补 `Conn::unsubscribe` + `dbus_unsubscribe_session`——按 key 整键摘除 + RemoveMatch——`match_rules` 字段随之改 `mut`。
- **空闲双通道**：`@sys.idle_seconds`——C 平台：Win GetLastInputInfo / mac HID / Linux X11 XSS——不动；GNOME 档新增 `org.gnome.Mutter.IdleMonitor.GetIdletime`，D-Bus，Wayland 原生与 GNOME X11 都准，探测结果进程级缓存。KDE/wlroots 的 ext-idle-notify 只有事件没有「当前空闲秒」读数口，要 Wayland 协议客户端地基——归 P3 之后。
- **跨平台通知节流矩阵**，2026-11-04 逐家核对，回答「其他 DE/mac/Win 限不服」：freedesktop 通知规范**没有限流条款**——原文无 reject/throttle 措辞——限流全是各家实现自加：
  - **KDE，Plasma**：唯一**错误拒绝 + 连累同发送者后续调用**的实现——`ExcessNotificationGeneration`，本案；实测同内容快速连发触发、触发后探测也翻转。`nf_call` 的超时重试 + 测试内容可区分就是为它设计。
  - **GNOME Shell**：**不拒绝调用**，Notify 照常返回 id；但连发同 app 的气泡会**静默丢弃/合并**——Launchpad #2116717 burst bug；「Notification Configurator」扩展把限流当卖点反证了原生态位。调用方无感，无错误面，影响只在观感——测试断言不查气泡可见性，不受影响。
  - **dunst**：`notification_limit` 是**显示队列**上限，超出排队不拒绝，D-Bus 调用即时返回；无超时面。
  - **macOS，UN 框架，本仓 mac 臂**：`addNotificationRequest` 是**异步提交**——completion handler 回来才算结果——本桩不阻塞、无超时面；立即型通知无 64 pending 上限——那是计划触发型的队列上限；系统可能视觉合并同内容，但调用层面无拒绝。mac 腿的 wbtest 不吃 nf_call 的重试/超时逻辑，走 win 桩另一路。
  - **Windows，Shell_NotifyIconW 气泡，本仓 Win 臂**：同步调用进 Explorer 托盘窗；**全系统同时只显示一个气泡**，新气泡替换或排队——10/11 转 toast 后堆叠上限 3 个、其余进通知中心；无「限流拒绝」错误，失败面是调用返回 FALSE——托盘不存在等——返回值本仓已查。Vista 起 `uTimeout` 无效，显示时长系统钳在 10~30s。
  - **库侧结论**：`nf_call` 的重试只服务「D-Bus 应答长尾」这一种失败面，KDE 实测 2~3s；mac/Win 的调用面不阻塞不拒绝，无需同款处理。测试侧的限流/超时容错只在 Linux 腿生效。多包 `moon test` 时 notify 用例三成概率失败。`dbus-monitor --profile` 抓线配对定案两条根因：① **plasmashell 通知服务的应答长尾**——服务跑在 GUI 进程里，桌面忙时，气泡渲染/历史面板，应答 2~3s——235 次往返 16 次 >1.5s、最慢 3.1s；空闲时 2ms——单次 1.5s 超时必撞；② **KDE 的发送方限流**，`ExcessNotificationGeneration: Created too many similar notifications in quick succession`——同内容快速连发触发，触发后连累同发送者的后续调用，即探测翻转的来源。修复：通知族调用 `nf_call` 对 `gdbus.timeout` **重试 3 次**——4.5s 覆盖实测长尾；「服务不在线」是 `ServiceUnknown` 立即回、不吃重试，探测口径反而更诚实——+ 测试内容全部带时间戳可区分 + 用例对限流/超时按环境跳过、断言改「单次探测自洽」——跨探测一致性属环境性，不作断言。验证：满载全量门禁 16 连绿，此前 3/10 失败率。诊断通道 `NATIVEGUI_DBUS_DEBUG=1`——mark_dead / 连接级失败 / notify_caps 错误名打点——参照 `NATIVEGUI_LAYOUT_LOG` 先例保留。

## Wayland P2 夜灯/显示器：KDE 两口的本机实证 · 2026-11-04

- **KDE 夜灯，Plasma 5.27 实物**：接口在 `org.kde.NightColor`，不是 `org.kde.kwin.ColorCorrect` 那个名——后者无主；对象 `/ColorCorrect`、接口 `org.kde.kwin.ColorCorrect`；属性 `available/currentTemperature/enabled/inhibited/mode/running/targetTemperature/…` **全是 access="read"**，逐个核过 XML；方法只有 `nightColorAutoLocationUpdate/inhibit/uninhibit/preview/stopPreview`——**5.x 没有公开写入口**，KCM 写 kwinrc，不走 D-Bus。Plasma 6 的 `org.kde.KWin.NightLight` 本机不存在，写入口径未核，S6 真机定。故 KDE 档读侧全量、写侧一律 Unsupported——读得到不装扮写得进。
- **KDE 显示器，KScreen 实物**：`org.kde.KScreen` 的 `/backend` 上 `org.kde.kscreen.Backend.getConfig` 返回顶层 `a{sv}`；`outputs` 是 `av`，每个 v 是 a{sv}；mode 也是 `av`，每个 mode 的 `size` 与 output 的 `pos` 都是 **variant(a{sv})**，不是数组——按数组解析会全落空。**`refreshRate` 是 int64 赫兹**——本机 25/50/60/75；dbus-send dump 里看到的 double 59.9506 是别家/别版字段，两种形态都吃。mode 无 preferred 标志位，XML 核过，`current` 由 output 的 `currentModeId` 对回。KScreen 不报物理尺寸 mm。本机实测：9 个输出、2 个已连——HDMI-0/HDMI-2 均 1920x1080@60、pos 左右排布、各 30 模式——与 xrandr 一致。
- **GNOME 夜灯**：`org.gnome.settings-daemon.plugins.color` 的 `night-light-enabled`/`night-light-temperature` 键本机 schema 在——KDE 会话也装了——写键驱动 gsd-color 自己的夜灯，不是裸 gamma；gsettings 走 `@sys.pr_run` CLI，与壁纸通道同路数、不引新依赖。gsd-color 服务不在时写键也落得下去，不拿「服务在不在」当门槛。
- **mutter DisplayConfig**：字段序以接口 XML 为准且本机拉不到源码核——GNOME 下载源被挡、GitLab raw 404——按「不许假数据」只做存在性探测，读一率 Unsupported，S7 真机定字段序后再接。
- **wlroots 两件**，即 wlr-gamma-control / wlr-output-management，都要 Wayland 协议客户端地基，与 ext-idle-notify 一拨归 P3 之后。

## Wayland 自写 wire 客户端 · P3 地基 · 两个 empirisch 坑与 headless weston 实证 · 2026-11-04

- **选型定案**：自写 wire 不链 libwayland-client——与 dbus/wire.mbt 同构、零新增链接期依赖、按包可选——`gui/wayland` 独立包，Windows 桩函数恒 -2。协议面——8 字节固定头 + 对象 id + new_id——确实够简单。
- **坑①，opcode 序**：`wl_display` 的请求序是 **sync=0 / get_registry=1**，见 wayland.xml。搞反时的现象很误导：服务端把 get_registry 当 sync 建出一个 callback——对象 2 上收到 12 字节 done、随后 delete_id(2)——registry 永远收不到 global，而 sync 的 done 照样回来，往返屏障看着是通的。
- **坑②，string 长度**：wayland 的 string 长度字段**含结尾 NUL**——实物核过：`wl_subcompositor` 16 字符 → 长度 17。按「不含 NUL」解接口名会带个尾 NUL；下一个字段偏移两种算法在这批数据上巧合一致，pad 吸收，但名字是脏的。
- **实证**：本机 weston 13 headless，`XDG_RUNTIME_DIR` 指到临时目录 + `--backend=headless-backend.so --socket=…`，起合成器，`wl_globals` 枚举出 19 个 global，与 `wayland-info` 输出逐一吻合。无 Wayland 会话的机器，即 X11/Windows/macOS/CI，探测即不可用，用例走跳过支。
- **未落地**：fd 传递——SCM_RIGHTS，data-control 的 receive 要用，需 C 助手；wlr-data-control / ext-data-control、wlr-foreign-toplevel、wlr-output-management / wlr-gamma-control、ext-idle-notify 的协议客户。
  - SCM_RIGHTS：Unix 域套接字上随消息附带传文件描述符的机制，Wayland 剪贴板类协议靠它把数据管道的 fd 交给对端
  - data-control：wlroots 系的剪贴板协议族，wlr-data-control 与 ext-data-control 都属它，对应 X11 下剪贴板选区那一套

## GPU 第一步 X11 wgpu 三角形：moon native-stub 的 C 编译面相与 v29 future API · 2026-11-04

`modules/gui-gpu/gpu/triangle.c`——dlopen wgpu + libX11，自开 Xlib 窗上屏三色三角形——落地时踩平的编译/装载面：
- **moon native-stub 支持包目录相对的 quoted include**，webview 的 `#include "include/WebView2.h"` 是先例，但**相对层级要数对**：vendor 是 `gpu/` 包的兄弟，即 `modules/gui-gpu/vendor`，路径是 `../vendor/include/webgpu/webgpu.h`——按仓库根的直觉写 `../../vendor/…` 会静默走空——`__has_include` 假 + 编译期桩分支，构建照旧绿，现象是「运行期报 unsupported」而不是编译错。
- **`__has_include` 守卫让缺 vendor/缺 Xlib 头的平台退化成编译期桩**——prebuild 没下载/非 Linux 都不破构建；PFN typedef 全部取自 vendor 头的 `WGPUProc*`，204 个，不手抄签名；函数指针表用宏声明时**声明名与调用名要一套**——`p_wgpu##name` vs 写歪的 `p_##name` 的教训：moon 的 C 编译对未声明标识符竟走到链接期才报，别指望编译期拦。
- **dlopen 候选原是相对 cwd 的**——probe.c 的 `vendor/lib/…` 只在模块根 cwd 下中——experiment 从仓库根跑会误报 not-found。triangle.c 的加载器加**仓库布局候选**：从 cwd 逐级向上，每级试 `<anc>/vendor/lib/…` 模块根形态，与 `<anc>/modules/gui-gpu/vendor/lib/…` 仓库根形态，dlopen 试错不需要 stat；发行的应用走不到这两级，落环境变量/系统名。`probe()` 的候选不动，库契约保持简单，experiment 的失败诊断会附带打印 probe 详情，别被它的 not-found 误导。
- **v29 future 风格 API 实跑口径**：adapter/device 都经回调拿——`WGPUCallbackMode_AllowSpontaneous` + `wgpuInstanceProcessEvents` 轮询泵，1ms 步进带超时——不能当同步函数；surface 走 `WGPUSurfaceSourceXlibWindow{display, window}`；v29 没有 `wgpuSurfaceGetPreferredFormat`，格式直接 BGRA8Unorm，即 Linux/Vulkan 地表形态；`WGPURequestAdapterOptions.backendType` 还在，留 Undefined 让 wgpu 自选 primary。
- **无显示实跑验证**，不开窗、只走加载链：仓库根 `env -u DISPLAY ./gpu_triangle.exe`，错误停在 `XOpenDisplay 失败`——证明仓库布局候选找到库、19 个 wgpu 符号 + 12 个 Xlib 符号加载、MoonBit↔C ABI 与缓冲读回全链通。三色三角形的肉眼验收归用户——`moon run experiment/gpu_triangle`，关窗/Esc 退出。

## L1-Linux present 纹理合成：stub.c GTK 臂的 GPU 档与双编译形态 · 2026-11-04

`gui/win/stub.c` GTK 臂落 L1——Bitmap 上传纹理 → 全屏 textured quad → swapchain present，GPU 不可用逐字回退 cairo。落地形态与坑：
- **双编译形态自动继承**：Linux 上 stub.c 的真臂由 prebuild 以 `-DWM_STUB_GTK` 编进 `libyue_win_stub.a`——moon 的 native-stub 那次编译没有该宏、落不进任何臂，产出空占位对象——L1 代码放 GTK 臂内即获得这个形态，**不与 native-stub 编译重复符号**；pkg-config 头路径也由 prebuild 给全。
- **vendor 头跨模块相对取**：`__has_include("../../modules/gui-gpu/vendor/include/webgpu/webgpu.h")`，gui/win 上跳两级到仓库根，+ 守卫——缺归档整节编译不进，行为恒等于改造前。**首次构建顺序坑**：gui 的 prebuild 若先于 gui-gpu 的 prebuild 跑，头不在 → L1 静默关——不报错，重建即好；本机 vendor 已在，无感。
- **回退逐像素一致的根据**：上传纹理用 BGRA8Unorm——MoonBit 位图是 ARGB32，内存字节 B,G,R,A，与 X11/Vulkan 地表格式同字节序，零转换；采样 nearest + ClampToEdge，1:1 不糊。surface 按**面积**配、纹理按**位图**建，稳态相等，resize 过渡期差几帧由拉伸兜着。
- **v29 API 三个反直觉点**：`WGPUStatus_Success = 1`，不是 0；`WGPUTextureAspect_All = 1`，不是 0；**没有 `wgpuSurfaceGetPreferredFormat`**，v29 移除，格式直接 BGRA8Unorm。枚举混写坑：头文件里是 `WGPUTextureUsage_TextureBinding`，驼峰，不是全大写下划线形态，写错是编译错误、好在报错信息直接给正确名。
- **行距 256 对齐**：`copyBufferToTexture` 的 `bytesPerRow` 必须被 256 整除——CPU 侧暂存按行垫，`bpr = align(bw*4, 256)`，每帧先垫行再 `QueueWriteBuffer`，多一次 CPU 拷贝，与 wm_store_frame 同量级。
- **GTK 盖内容的对偶**：GPU 挂上后 draw 回调 cairo 停手不够——GTK 还会用主题底色/双缓后备盖掉已上屏内容，必须同批设 `app_paintable=TRUE` + `double_buffered=FALSE`——后者自 GTK 3.14 deprecated、GTK3 无替代品，`#pragma GCC diagnostic` 局部静默；这是 GTK+GPU 集成的既定套路。
- **探测两档口径**，方案「fallback 探测粒度」：进程级一次——.so 缺/驱动无后端/非 X11 会话，Wayland 原生没有 XID 可挂，= 永久缓存不再试；未 realize、0×0 = 不标记死、下帧重试；对象真建不出或 present 回非 Success = 该窗永久回退。instance/device/队列/管线/采样器进程级跨窗复用，每窗只持 surface/纹理/暂存/bindgroup，关窗按「bindgroup→buffer→view→texture→surface」释放。
- **验证边界**：门禁全绿——回退路径零变化，wbtest 1296/1296；GPU 档本身要真机肉眼——showcase/hello 跑起来界面与改造前一致、无闪烁、resize 不花，归用户，见 TODO 复验条目。

## Linux GTK 窗口 present 被合成覆盖：L1 窗口档回退、改建独立 X 子窗口 · 2026-11-06

showcase 在 Linux 上「有 GPU 就白屏 / 黑屏 / 点击不更新」的现场排查与结论，按发生顺序：

- **白屏**：L1 挂上后窗口整片白。GTK 顶层窗口每帧先画主题底色 / 双缓后备；只在自绘区设 `app_paintable` 挡不住——DrawingArea 是 no-window，真正上屏的 GdkWindow 属于顶层 GtkWindow。补窗口层 `app_paintable` / 关双缓 / 清 GdkWindow 背景 pattern 后白屏消失。
- **黑屏**：present 的 clear 落了、quad 不出像素。根因是 **`WGPUMultisampleState.mask` 被 memset 清 0**，见上一节更正，补 `0xFFFFFFFF` 后 GPU 画布与 L1 的 draw 都能出像素。
- **界面正常但点击 / 悬停不更新**：`wm_present` 每帧都在 present——`NATIVEGUI_GPU_LOG` 的内容 hash 持续变化——屏幕却停在首帧。逐项排除：
  - `NATIVEGUI_GPU_DEBUG=green`，只清绿不画内容，→ 窗口纯绿，**present 本身可见**；
  - `NATIVEGUI_GPU_DEBUG=rainbow`，每帧换清屏色，→ 窗口颜色**固定**，后续 present 不可见；
  - resize 重建 surface 后仍固定；
  - 已试无效：draw 回调内重放、`GdkFrameClock::after-paint`、`g_idle_add`、`gtk_widget_queue_draw` + 迭代、拦截窗口 `draw` 返回 TRUE、给 area `has_window(TRUE)` + `double_buffered(FALSE)`、接受 `SuccessSuboptimal`。
  - 结论：**GTK 的整窗合成贴图总在 present 之后**，把 GPU 内容盖回旧帧。
- **为什么 mac 成立**：`CAMetalLayer` 是视图的合成层，系统合成器持续保留 / 合成其内容；GTK/X11 没有等价物，DrawingArea 的像素归 GTK 绘制周期管。
- **处置**：GTK 臂的窗口 present **默认回退 cairo**——`NATIVEGUI_GPU_L1=1` 才显式开启；离屏 GPU 画布不受影响。零拷贝 present 改为「自管 X 子窗口承载」：子窗口是 GTK 顶层窗口的 X 子窗口，设空输入形状让事件穿透，GTK 的整窗合成碰不到它——方案文档已随实现落地删除，口径见下一节。

**判据**：`NATIVEGUI_GPU_DEBUG=rainbow`，present clear 每帧变色，下窗口颜色必须持续变化；颜色固定即「后续 present 不可见」。

## Linux L1 子窗口承载落地：XShape 在 libXext、事件穿透必须靠空输入形状 · 2026-11-06

上一节定的「自管 X 子窗口」方案同日实现，2026-11-06 Linux 真机验收通过——界面/交互/rainbow 逐帧变色/webview 层级/挪库回退全过；`NATIVEGUI_GPU_L1` 门已删，GPU 档默认尝试、建不出自动回退 cairo——实测口径：

- **`XShape*` 符号在 libXext、不在 libX11**，`nm -D` 实证：libX11 里只有 Xkb 的几何 Shape 函数。头是 x11proto 的 `<X11/extensions/shape.h>`；GTK 传递依赖可达，但显式加进 prebuild 链接表——`LINUX_PKG_CONFIG_LIBS` 加 `xext`——明确归属。
  - XShape：X11 的窗口形状扩展，可给窗口单独设「输入形状」，决定鼠标事件算不算落在这个窗口上
  - libXext：X11 各扩展的公共实现库，XShape 这类扩展函数的符号住在里面，与 libX11 分属两个库
- **`event_mask=0` 不等于事件穿透**：X 的指针事件发给「指针所在窗口」，子窗口不选 mask 只会让事件**丢弃**——ButtonPress 不冒泡——父窗口收不到，子窗口成了输入黑洞。穿透必须 `XShapeCombineRectangles(…, ShapeInput, …, NULL, 0, ShapeSet, …)` 设空输入形状；Shape 扩展不可用则本档整体回退 cairo，不能只建窗口不设形状。
- **销毁次序**：`wm_close` 趁 XID 有效先 `XDestroyWindow` 子窗再销毁 GTK 窗；`wm_on_destroy`，即窗口已被 WM 销毁的路径，只清 XID、绝不再 `XDestroyWindow`——父窗已没，打无效 XID 是 BadWindow。
- **透明档判据**：`gtk_widget_get_app_paintable(w->window)`——透明档对 window 设过它——为真走 cairo，与 Win32 臂 `trans_mode` 同口径；旧「area 设 app_paintable/关双缓」补丁随子窗口方案删除——子窗口盖住父窗像素，GTK 画什么都不可见，不需要再挡。
- **诊断档常驻**：`NATIVEGUI_GPU_DEBUG=green/rainbow` 从「临时改代码」变成共享核心里的环境变量档，默认关，真机验收直接跑，不用再动代码。
- 顺手清 GTK 臂既有死变量 `wm_surface_next_id`——`-Wall -Wextra` 唯一警告；prebuild 自身不带 `-Wall`，C 桩的门禁要手动带警告档编一遍才看得见。

## L1 承载子窗口 × webview：挂原生子件的窗必须回 cairo · 2026-11-06 browser 示例实测

- **现象**：browser 示例网页区整块空白，工具栏/状态栏与其他交互全正常；`@win.gpu_present_status()` 为 `on`，L1 已挂。
- **定性**：L1 承载子窗口，即自管 X 子窗口 `wm_l1_child_ensure`，与 WebKitGTK 的原生窗口共存时网页不出像素。结构探针，窗口→GtkOverlay→绘制区+GtkFixed→L1 子窗口→webview，显示 L1 子窗在时根窗同一像素取到 L1 底色 `#00ff00`；`XUnmapWindow` / `XDestroyWindow` 掉 L1 子窗后立即恢复网页色 `#ff0000`。`XQueryTree` 显示 webview 窗口在 L1 子窗之上，**叠放序不是判据**——按窗口级实测行为收口。
- **顺序是那个洞**：只有「webview 先建、L1 子窗后建」成立；browser 示例是**首帧之后**才建 webview——L1 子窗已在——于是必现。此前「webview 层级全过」的验收走的是前一种顺序，漏了这一格。
- **修法**：GTK 臂 `wm_surface_new` 挂上子件时拆 L1 承载子窗口 + `wm_l1_window_drop` + `l1.dead=1` + `queue_draw`——挂原生子件的窗**永久**回 cairo 呈现，子件在的窗不存在回 GPU 的场景。下一帧 `wm_on_draw` 见 pending 为空置 `need_draw` 请 MoonBit 重画，不必另补帧。
- **代价**：这类窗的窗口级零拷贝 present 停用——自绘 UI 走 cairo；网页内容仍由 WebKit 自己合成，其 GPU 加速不受影响；离屏 GPU 画布——L2 `GpuCanvas`——不受影响。
- **验收**，像素级 A/B，探针留仓 `experiment/l1_webview_probe`：探针走真实库路径——`mount_window` + 首帧后 `webview_new` + 铺满 pane，页面底色 `#ff00ff`——窗口外 `XGetImage` 取根窗中心像素：修复前 `#f5f6f7`，应用底色、网页被盖；修复后 `#ff00ff`，网页出像素；browser 示例同一读数从应用底色变 `#ffffff`，即本地协议页底色。

## L1 窗口最小化恢复：map 时重配并重放最近一帧 · 2026-11-07 hello 实测

- **现象**：L1 窗口最小化再恢复后内容空白/花屏，要等下一次应用绘制才回来；静止内容——hello——一直不回来。
- **机理**：最小化 = toplevel unmap；原位重 map 后交换链已失效，而共享核心的「0×0 跳过重配」让尺寸账本停在旧值——恢复后第一帧撞 `Outdated` → 重配 + 丢帧，应用不重画就停在空白。
- **修法**：GTK 臂挂 `map-event`：`l1.on` 且最近帧在位时先 `wm_l1_child_sync` 对齐子窗口，再 `wm_l1_window_repaint`——清尺寸账本强制重配 + 同一张位图 present 一次——随后 `need_draw=1` 请 MoonBit 补新帧。`wm_present` 改为**先落帧再试 L1**，L1 路径也持有最近一帧——重放用；代价每帧多一次 memcpy，与 Win32 臂同口径。`wm_l1_try` 加「未 map 不 present」守卫，避免最小化期间打在不可见 surface 上被标死。
- **验收**，像素级 A/B：`xdotool windowminimize` → `wmctrl -i -a` 还原，窗口区域 `XGetImage` 哈希——hello 修复前恢复后哈希变化，中心色 `#f8f8f8`、空白；修复后与最小化前逐位一致，`062c4c686c8c03ed`；showcase 对照同样哈希一致，`27832eb2db1ff256`。

## Linux AppImage 自替换拿 /proc/self/exe 当落点必败:真身在 $APPIMAGE(2026-11-10,真机反馈)

**现象**:Linux 本地服务链路走到安装步,报「挪走旧 AppImage 失败:/tmp/.mount_showcaXXXX/usr/bin/…exe → …exe.mng-old」——落点路径在 `/tmp/.mount_*` 里。

**根因**:AppImage 类型 2 运行时把 squashfs 挂到 `/tmp/.mount_XXXX`(只读),`/proc/self/exe` 解析进挂载点内部;`autostart_exe_path()` 拿它当替换落点,对只读挂载点 mv 必败。同因还有第二处:`update_relaunch` 也用 exe 路径,就算替换成功重启起的也是挂载点里的旧二进制。AppImage 规范的口子是 runtime 预设的 `$APPIMAGE` 环境变量——指向 `.AppImage` 文件真身(挂载点外)。

**修法**:linux 替换与重启的落点统一走 `upd_linux_target`:「$APPIMAGE 非空且文件存在 → 真身;否则(裸 exe/dev 跑/解包跑)落回自身路径」。挪不动时的报错补一句可读指引(装在系统位置如 /usr/bin 时 v1 更新只支持 AppImage 载体)。

**判据**:①Linux 上凡「对自身文件做替换/重启」类功能,落点先问 `$APPIMAGE`,不能信 `/proc/self/exe`——它在 AppImage 里永远是挂载点内路径;②同一坑的两个面(替换落点、重启目标)要一次修齐,只修替换会出现「替换成功、重启回旧版」;③判别现场:报错路径含 `/tmp/.mount_` 即 AppImage 挂载点,真身看 `$APPIMAGE`。

