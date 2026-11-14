# 平台适配·macOS专有

收 macOS 专有的实测坑与口径：mac 平台批与对齐批、通知 / Dock / 无障碍 NSAccessibility 桥、拖放与访达、DMG 打包与自更新等真机反馈。

### MoonBit 原生 GUI 栈 · 批 F1 权限挂起待决（2026-10-29，用户拍板「权限不该干巴巴进日志」）

- **形态**：拒绝档（默认）从「立即 deny + 报事件」改为**扣住待决**——上层弹「同意/不同意」，点按后 `Webview::respond_permission(allow)` 落判（返回是否命中，区分「点了空」）；自动放行档（`set_permission_mode(true)`）不变，立即 grant 并报 kind=9。三平台扣法：GTK `g_object_ref` 住 `WebKitPermissionRequest`（挂起期间它一直活着，决定延后合法）；mac 扣 `decisionHandler` block（ARC 强持有，`requestMediaCapturePermissionForOrigin:` macOS 12+ 公开口）；WebView2 `GetDeferral` 扣 `PermissionRequestedEventArgs`，落判序 put_State → Complete → Release。
- **两条护栏**：① 新请求来了旧的没落判——旧的一律按拒绝收口，三平台同款「不留无主扣件」；② 视图销毁（wb_destroy）对挂起件也落一记拒绝，不给引擎留「永不回调」的悬案。
- **本轮两个坑**：① ObjC 实例变量没有 @property，点语法（`v.pending…`）编译报 property not found，一律 `v->`；② 「wbtest 链接缺 wb_* 符号」的真因是 prebuild 桩归档比源旧（缓存没跟源失效），clean 全量重建后恢复——以后见到 `Undefined symbols _wb_*` 先怀疑桩归档过期，别急着怀疑链接参数。
- **验证**：`moon check --deny-warn` 全绿、webview 18/18（新增「无挂起时落判是空操作且回 false」回归）、examples browser check/build 全绿；真机清单交用户（mac 用媒体项触发，定位无公开回调）。

## macOS(CI 构建链已验,GUI 待真机)

- libyue v0.15.6 发行包含 ARC / no-ARC 双库:Darwin 链接参数 = 主库 + `-lyue_mbt_noarc`(no-ARC 符号被主库引用,须排其后)+ AppKit / Carbon / IOKit / Security / WebKit / OpenDirectory 框架 + `-lobjc -lc++ -lpthread -lbsm -Wl,-dead_strip`;prebuild Darwin 分支已按此预修。
- CI(macos runner)承担构建 + 测试;headless 无 WindowServer,不做 GUI 冒烟。
- shim 平台分支的 `#else` 兜底会误吞 macOS:borderless 须 `#elif defined(OS_WIN)`;CurrentDirForDrag 拆三支(mac 用 `getcwd`);`Window::SetSkipTaskbar` / `SetIcon` / `App::SetID` 在 mac 头文件无声明,调用补守卫空操作。
- **AppleClang 17(macos-15 镜像更新后)把 `getRed:green:blue:alpha:` 返回值解析成 void**,`![...]` 一元取反编译错误;已判空且转 sRGB 后取分量必然成功,丢弃返回值写法对 BOOL/void 双解析都可编译(69136b7,曾被整树回退丢失又捡回——回退基线含带病文件时,后续修复会随回退消失,重推 vendor 前需对照该文件历史)。
- **0.5.0 发布前的 CI 连红三根因(9-22 起,Linux/macOS 红、Windows 绿)**:① `yue_accent_mac.mm` 的 AppleClang 编译错误(见上)卡死 prepare;② extern "C" 缺失(见 ABI 小节)卡死链接;③ sysmonitor 的 S4 硬件采样测试断「coretemp 必有 Package 传感器」,虚机 runner 无此硬件即败——环境缺件(无传感器/无 DISPLAY)只跳过不硬断。另:CI 原生层缓存 key 必须含 shim 源码哈希(只含 prepare.py 时,shim 变更不换 key,恢复的 build/ 缓存里是旧 shim 库);无 Actions 日志权限时,把失败输出切片塞进 `::error` 注解(check-runs annotations API 匿名可读)是唯一取证通道。

## macOS 后端首批（mac 平台批①-⑧，2026-10-15；编译与链接由 CI 的 macOS job 回证，真机项待复验）

- **环境**：GitHub Actions `macos-latest`（Apple Silicon，Xcode CLT 自带 clang 与 SDK 框架）。**本地开发机是 Ubuntu/X11，摸不到 macOS 的窗口服务**，所以这一族的「编得过、链得上」全部由 CI 证明，「跑得起来、看起来对」交真机（清单在 `测试文档/测试用例.md`）。
- **分支形态（与 Linux/Windows 同一条「单一 stub.c 多分支 + prebuild 宏」）**：`win/stub.c` 的 `WM_STUB_MAC`（Cocoa，Objective-C）、`render/stub.c` 的 `WM_STUB_MAC`（ImageIO，纯 C）、`text/stub.c` 的 `WM_STUB_MAC`（CoreText，纯 C）、`web/webkit_stub.c` 的 `WB_HAVE_WKWEBVIEW`（WebKit，Objective-C）。**占位分支的条件一律加 `&& !defined(__APPLE__)` 闸**：macOS 上 native-stub 那次不带宏的编译必须编出空翻译单元，否则与 prebuild 归档双定义。prebuild 的 Darwin 分支用 `cc -x objective-c -fobjc-arc` 编归档（`link_configs` 没有编译期字段，`c_flags` 被静默忽略——同 GTK/Pango 那条实测），框架按 `-framework` 逐包下发。
- **实测坑（CI 第一轮就炸出来的两处 API 形态错，记下来免得再犯）**：
  1. CoreText 的函数**文本对象在前**——`CTLineDraw(line, ctx)`，与 CGContext 一族 `(ctx, ...)` 的直觉相反；
  2. `CFAttributedStringReplaceString` / `SetAttribute` 收的是 **`CFRange`**，不是 location+length 两个数，且长度要问 `CFAttributedStringGetLength`（拿 `CFStringGetLength` 编不过：类型不同名）；
  3. 顺带一条非 mac 的：`sys_stub.c` 的 POSIX 臂里 `kill` 在 Linux 上靠别的头顺带声明到，macOS 的 clang 把隐式函数声明直接当错误 → 显式 `#include <signal.h>`。
- **实测坑（第二、三轮：新 SDK 上「已不再公开声明」与「名字记错」两类）**：
  1. `setCanShowHiddenFiles:`（NSOpenPanel）、`setSendActionOn:`（NSStatusItem 的按钮）、`setApplicationNameForUserAgent:`（WKPreferences）在 macOS 26 的 SDK 上都不再公开声明（clang 分别报 `no visible @interface` / `no known instance method`），旧 SDK 上它们是真实存在的。统一处理形态：给 `NSObject` 写一段 **informal 声明**让 selector 编译期可见，调用点先 `respondsToSelector:` 再发——运行期没这一口就退回默认行为（保存/打开面板的「显示隐藏文件」开关、托盘右键触发、UA 后缀失灵），**不去猜新名字**。
  2. `WKWebsiteDataStore` 没有 `dataStoreWithURLStoragePath:error:` 那个口（那是按 Linux 侧 `WEBKIT_DATA_DIR` 的语义想出来的名字，编不过）；公开的是 **`+[WKWebsiteDataStore dataStoreForIdentifier:]`**（macOS 14+，吃 `NSUUID` 且进程要有 bundle id，libyue 的 `nativeui/mac/browser_mac.mm:86` 用的正是它）。目录路径进不了这个口，于是由 data_dir 哈希出一个固定 UUID（FNV-1a 两条 64 位链，拼 RFC 4122 的版本/变体位，`NSUUID` 只认合法串）——同一目录跨运行拿到同一会话；兑现不了照旧退 `nonPersistentDataStore` 并由 `wb_persistence()` 出声。
  3. `WKWebsiteDataStore` 的 cookie 存储属性名是 **`httpCookieStore`**（写 `.cookieStore` 报 property not found，clang 的 fix-it 直接给对的名字）。
  4. **ObjC 的形参不能叫 `id`**：`wb_evaluate(int64_t id, ...)` 把类型名 `id` 遮住了，块参数表 `^(id result, NSError *error)` 因此被当成变量声明解析，报错炸成一片（`type-id cannot have a name` + 一串 `undeclared identifier`），根因只在一个参数名。
  5. 两条「警告级但真是错」的：`NSTextInputClient` 的协议方法是三段名 **`setMarkedText:selectedRange:replacementRange:`**（写成两段，clang 只给 `-Wprotocol` 警告，输入法组合串那条通道运行期接不上）；`resignFirstResponder` 的原型返回 **`BOOL`**（写成 `void` 是 `-Wmismatched-return-types`）。所以 macOS 桩的编译门禁把 warning 也一并读，不当噪声丢掉。
- **显示器枚举（mac 平台批⑧，`sys/monitor.mbt` + `sys_stub.c` 的 `__APPLE__` 分支）**：CoreGraphics 一家打齐——`CGGetOnlineDisplayList`（只列「在线」的，即已接且通电；macOS 没有「接了但关掉」的公开清单，故 mac 侧不产 `connected=false` 那种条目）、`CGDisplayBounds` 给逻辑点原点、由「当前模式像素宽 ÷ 逻辑宽」导出倍率后把原点与尺寸换成**物理像素**、`CGDisplayCopyAllDisplayModes` 给模式表（按「像素宽×像素高×刷新率」去重：CG 的清单里同一像素尺寸可以有多份时序配置，重复档对布局没有意义；表给不出时退当前档一条）、`CGDisplayScreenSize` 给物理毫米。**两个模式谓词在当前 SDK 上已不声明**（`CGDisplayModeIsCurrentMode` / `CGDisplayModeIsPreferred`，clang 报 `call to undeclared function`；这一族里只摘了它俩，同段的 `CGDisplayCopyAllDisplayModes`/`GetPixelWidth`/`GetRefreshRate` 都还在）：当前档改由「与 `CGDisplayCopyDisplayMode` 同像素尺寸同刷新率」判——去重后的清单里它只会出现一次，读数层面与那个谓词等价；`preferred` 没有公开信号，如实给 0，不拿「当前档」冒充「首选档」。三个给不了的如实说：名字（`NSScreen.localizedName` 在纯 C 桩里够不着，CG 侧无公开名 → 内建屏 `Built-in`、其余 `Display-<CGDirectDisplayID>`，与另两平台的输出名同为「本机特定」串）、毫米（引擎不给时 0）、内建面板刷新率（`CGDisplayModeGetRefreshRate` 对部分内建模式给 0=未知，照实传 0，不冒充 60Hz）。`MonitorInfo` 不需要新增缩放比字段：清单里的数字一律已是物理像素，与 xrandr 同口径。
- **与另两平台刻意不同、且写进契约的点**：
  - **事件循环**：不用 `[NSApp run]`，`wm_wait` 走 `nextEventMatchingMask:untilDate:`（AppKit 自己的阻塞取事件），`wm_wakeup` 走 `postEvent:` 投一个 `NSApplicationDefined` 标记事件把它唤醒——本栈「循环归 MoonBit + 不做 C→MoonBit 回调」两条纪律在 mac 上的等价实现。已知限制：拖窗/实时缩放时 AppKit 进 tracking mode，我们的泵拿不到那段事件（T6b 专测）。
  - **像素尺度**：整栈物理像素，Cocoa 侧一律点，进出边界各按所在屏 `backingScaleFactor` 换算一次；绘制区视图**不设 `isFlipped`**（非翻转视图里 `CGContextDrawImage` 与 `CTLineDraw` 的落点正则是「内存首行=顶行」，翻反而会把字面画倒）。
  - **文本预乘取整归 ImageIO/Quartz**：Quartz 只在预乘空间合成，RGB 画布拿不到非预乘形态，所以 mac 的像素不再走各平台那句 `(c*a+127)/255`——字节序与语义不变，舍入差 ±1 级，「编码→解码→再编码逐字节稳定」这条判据在 mac 上按「与 ImageIO 自身一致」看。
  - **GIF 动图 macOS 退回静帧**：分帧合成要逐帧读「帧矩形 + disposal」，而 disposal 不在 Apple 的 GIF 公开属性清单里，无真机回证不硬写（`img_anim_decode_file` 给 0，组件退回首帧）。
  - **菜单/托盘/通知是 App 级**：`wm_menu_apply` 落 `setMainMenu:`（菜单条属于应用不属于窗口，多窗后挂的赢）；托盘是 `NSStatusItem`；通知是 `NSUserNotification`——**非 bundle 的裸二进制能否弹出通知属待真机确认项**（T4e）。
  - **任务栏进度 macOS 给不支持**：dock 只有一枚文本角标，画不出进度条语义，不拿它冒充。
  - **webview**：`wb_signal_mask()` 在 mac 回 15——下载走 `WKDownload`（macOS **11.3+ 就是公开 API**，早前「要 macOS 15」的判断是错的：本机 SDK 头核对 `WKDownloadDelegate` 明确写着 `API_AVAILABLE(macos(11.3))`；保存落点用 `NSSavePanel`，拦下档/取消落判 `completionHandler(nil)`）；权限请求走 `requestMediaCapturePermissionForOrigin`（macOS 12+，媒体专用；定位在公开 `WKUIDelegate` 里没有回调）。`wb_persistence()` 按「macOS 14+ 且有 bundle id」探测，裸二进制回 0 并退非持久化存储。
  - **mac 的 kind=9（媒体权限）在本仓示例形态下不可验（2026-10-29 探针实证，`experiment/webkit_media_probe/`）**：`enumerateDevices()` 回**空列表**、`getUserMedia({audio:true})` 的 Promise 既不 resolve 也不 reject（挂起）、`requestMediaCapturePermissionForOrigin` 一次都不触发；同一 delegate 的 `runJavaScriptAlertPanelWithMessage` 正常触发，证明是引擎侧没发起请求而非接线问题。四种形态结果一致：裸二进制 / 带 `NSMicrophoneUsageDescription` 的 .app / 经 LaunchServices `open` 启动 / 打开 WebKit 私有偏好（`_setMediaDevicesEnabled:` 等，`respondsToSelector` 均存在）。即 WebKit 在拿不到采集设备（缺 TCC/签名身份）时不发页级授权请求——**扣 decisionHandler + 上层弹框**的路径只在正确打包签名的 .app 里可验，本机无签名身份，待有签名工程后再真机确认。示例的媒体触发改为如实回包：3 秒无请求即报「引擎未发起（平台限制）」，不再谎报已执行。
- **sys 各族的 mac 后端选择**：能用公开 CLI 的不进 C——`open`/`open -R`（揭示与选中）、`sw_vers`/`ioreg`/`sysctl`（系统信息）、`osascript` 的 `volume settings` 与 System Events 桌面图片（音量/壁纸）、LaunchAgents plist + `launchctl load/unload`（自启动）、`lpstat`/`lp`（macOS 自带 CUPS，与 Linux 同一条线，**这是声明过的选择不是漏跑到 Linux 分支**）；只有真要问内核的走桩（`hw.memsize`+`host_statistics64`、`kern.boottime`、`CGEventSourceSecondsSinceLastEventType` 的空闲读数）。四族**明确保持 Unsupported 并加平台门**：windowctl（Accessibility 要用户授权）、nightlight（CoreBrightness 私有）、powerprofile（`pmset` 对不上三值方案语义）、media（无 MPRIS 对等物）。
- **macOS job 第一次真跑 `moon test`：851 项里 4 红，都是「口径没对齐」而不是链路坏**（这条最值钱——CI 第一次把 mac 侧的测试跑起来，证明前四批的降级声明有代码没跟上）：
  1. **动图退回首帧静图，尺寸却没退**：`ui/gif.mbt` 在 `Animation::new_from_file` 给 None 时不设宽高，占位成 0×0——图本身解得出（`ui_decode_guard()` 在 mac 通过，ImageIO 的 GIF 首帧给 120×120），只是「画得出却摆不下」。None 分支改为跟随首帧静图的宽高；`render/image_wbtest` 与 `ui/basic_wbtest` 的动图断言改成**探测即分支**：解不出动图就验「静图入口给出首帧 + 组件不排自转 + 画得出墨」，有动图才走换帧节奏那串断言（Linux/Windows 覆盖不减）。
  2. **下划线按行数比，行距一重合就平**：`text_decoration` 的断言原是「下划线多出一整行墨」，macOS 上那条 1px 线落进字形最后一行的行距里，行数不变就判红。改成比**墨像素数**——那才与「画没画下划线」同义，三平台同一条判据。
  3. **launcher 的平台门过期**：测试还写着「非 Linux 一律 `Unsupported`」，而批⑤已给 macOS 上了 `open` 的真实现。现在 mac 与 Windows 同一形态：拿无效目标做探针，只验「不再给 Unsupported」（`Ok` 或 `SpawnFailed`），不开浏览器也不开 Finder。
- **应用查找（批⑬）的两个「公开口给不到」**：`.app` 的 `Contents/Info.plist` 有可能是**二进制 plist**（第三方应用常见），纯文本读取拿不到任何键——条目按包目录名回退给出（宁可名字粗一点，也不要应用从清单里消失），而不是整个应用消失；本地化名在 `.lproj/<lang>.lproj/InfoPlist.strings` 里，公开 plist 键只给 `CFBundleDisplayName`/`CFBundleName`，所以 `locale_name` 与 `name` 同值，`categories` 恒空（macOS 没有 desktop Categories 的对等物）。可执行文件查找的口径差异：从 Dock/Finder 起来的进程**没有 shell 的 PATH**，所以 `/opt/homebrew/bin`、`/opt/homebrew/sbin` 要按固定清单补进去，否则 Apple Silicon 上 Homebrew 装的工具一律找不到。
- **`ld: warning: ignoring duplicate libraries: '-lyue_win_stub_mac'` 这类重复库告警是预期噪声，别去「修」**：macOS job 的链接日志里每条测试 exe 都会报一到三行这种 warning，同一个归档在一次链接行里出现两次——原因是包之间走的是 **extern 直链**（web 要 win 桩的 `wm_surface_container`、sys 要 win 桩的 `wm_file_*`，都不是 MoonBit 层的 import 边），所以 win 归档必须同时出现在 win、sys、web 三份 link_flags 里；最终 exe 把三个包链到一起时就重复了。ld64 的处理是「忽略后一份」，链接结果与语义都不变；GNU ld 同样接受重复但不吭声，所以只有 macOS 看得见。要消掉它得改成包级 import 边（把原生成品套进一层门面），代价远大于消一行 warning。
- **媒体线的 mac 落地（批⑰）**：两支桩都不用自己动——`ffmpeg_stub.c` 本来就无平台分支（ffmpeg 的 API 跨平台），`audio_stub.c` 里 miniaudio 是 vendor 的单头实现库、自己按 `__APPLE__` 选 CoreAudio。要做的只有**两处 prebuild**：`ffmpeg-mbt` 在 Darwin 走 pkg-config 探测（与 Linux 同一路，探不到非零退出并给 `brew install ffmpeg` 提示；差别是 brew 的 `.pc` 与头不在默认搜索路径，得显式把 `/opt/homebrew/lib/pkgconfig`、`/usr/local/lib/pkgconfig` 拼进 `PKG_CONFIG_PATH`，并把 includedir/libdir 喂给 `vars.FFMPEG_INC` 与 `-L`——这两个值按 pkg-config 问出来，不写死前缀，Intel 与 Apple Silicon 一台脚本通吃）；`gui-media` 在 Darwin 下发 `-framework CoreAudio -framework AudioToolbox -framework Foundation`，**并且不能照抄 Linux 那一串库名**：`-ldl` 与 `-latomic` 在 mac 上分别「在 libSystem 里、根本没有这个库」，照抄会直接在链接期报 library not found。CI 的 macOS job 自这一批起 `brew install ffmpeg`，并把依赖媒体两包的 main 示例（systemprobe / native-web）加回构建点名——等于在真实 macOS 上把 ffmpeg 桩与 miniaudio 桩各编一遍、把 framework 真链一次。
- **验证方式**：CI 的 macOS job 起手是**原生桩编译门禁**——用与 prebuild 同一串 clang 旗标（`-fsyntax-only -O2 -x objective-c -fobjc-arc -D<宏>`）对 win/render/text/web 四个 mac 桩加纯 C 的 sys 桩逐个过语法检查。这一步不能省：`moon check` 根本不编这些桩，形态错要等到 `moon test` 的链接期才炸，而且炸出来是一串 `Undefined symbols`（归档没编出来 → 链接条目整条不下发），看不出真正的原因。之后是 `moon check` + 逐包 `moon test` + 逐包点名的库构建 + examples/hello 链接，最后一步是 `moon run examples/hello` 活到超时（真机按 `测试文档/测试用例.md` 另行走）。
- **CI 已回证的点（2026-10-15，run 38616056855 三平台全绿）**：五支 mac 桩在新 SDK 上编得过；`moon check` 零警告；逐包 `moon test` 全绿——其中包含只在真实 macOS 上才跑的那几条读数环（`appfind` 扫 `/Applications` 拿到应用、`appfind_executable("sh")` 命中；`sys` 族 `host_statistics64`/`kern.boottime`/空闲读数；`render` 的 ImageIO 解码与 `text` 的 CoreText 测量），以及 `hello` 在 runner 的登录会话里**建窗并转起循环**活到 20 秒超时。
- **仍待真机目视的点**（这些 CI 给不了）：T1-T6 的观感与交互（Retina 观感、输入法内联、拖窗期间的循环、通知在非 bundle 进程下是否弹出）、显示器枚举在多台外接屏下的读数、plist/launchctl 的实际生效、osascript 的自动化授权。

## macOS 对齐批（2026-10-18，mac 本机把 merge 717d246 记的函数缺口补平，全 workspace `moon test` 1236/1236 首次在本机回证）

- **窗口面补平（hide/is_hidden/opacity/layer/transparent_bg/im_set_active/hotkey_\*）**：
  1. **`wm_show` 必须清 `hidden` 标志**——Cocoa 的 `orderOut:` 不丢 frame，位置无需复位（与 GTK 那条「show 前要还原 saved geometry」刻意不同），但 W23 语义的「隐藏驻留窗口不进 `wm_wait` 枚举」靠的是我们自己记的 `hidden`，`orderFront:` 不顺手清它就会让 `hide_wbtest` 的「唤回后 is_hidden==0」判红。
  2. 输入法焦点门 `im_active` 与 GTK 支同语义同默认值（首窗默认 1，`im_set_active(0)` 后键不再过 `NSTextInputContext`）。
- **系统级拖放 mac 落地（dragdnd 八件）**：
  1. **判据口径又一次只编码了一侧**：`dragdnd_wbtest` 的 `count`/`effect` 断的是 **Win32 语义**（count=已注册窗口数、未注册窗 `effect` 回 -1），而 GTK 支给的是恒 1 的另一种语义。mac 按 Win32 这条实现（`wm_dnd_registered[]` 数组记账），并把「GTK 不同」写进注释——三平台里两派语义并存时，新平台跟**测试认的那派**。
  2. **拖出（send）要现场按下事件**：`beginDraggingSessionWithItems:event:source:` 的 `event:` 必须是本次 `mouseDown:` 的 `NSEvent`，不能凭空造——`mouseDown:` 里存档 `down_ev`，`send` 用掉即清（与 GTK「press 存档起拖」同一条契约）。
  3. **阻塞语义靠嵌套泵**：起拖后 `nextEventMatchingMask:NSEventMaskAny untilDate:+4ms inMode:NSDefaultRunLoopMode` + `sendEvent:` 的小循环自己转，直到 `draggingSession:endedAtPoint:operation:` 置 done 或 60s 超时——`cancelDragOperation:` 已废弃不再支持，超时不取消、直接回 3。
  4. **NSDragOperation 与门面效果位要显式映射**：Copy=1、Move=16、Link=512，回来是多位的按「没成交」给 0——mac 的原生枚举值与线协议位（0/1/2/4）数值全不同，不能透传。
  5. 载荷线协议三平台同一条：`[kind:i32 LE][body]`，kind 1=文本、4=路径 `\n` 连接绝对路径；投递取回用 `readObjectsForClasses:` + `NSPasteboardURLReadingFileURLsOnlyKey` 拿文件 URL，否则退 `stringForType:NSPasteboardTypeString`。
- **webview 模块 mac 链接补齐**：`webkit_stub.c` 的占位分支带 `!defined(__APPLE__)` 闸，mac 上 native-stub 那次编出的是**空翻译单元**——所以 `modules/gui-webview/prebuild.py` 必须自己带 Darwin 分支（`-DWB_HAVE_WKWEBVIEW -x objective-c -fobjc-arc` 编归档 + 链 WebKit/Cocoa 框架 + **主仓 `libyue_win_stub_mac.a`**：webview 要 win 桩的 `wm_surface_container`，extern 直链没有 MoonBit import 边，归档缺位就是整串 `_wb_*` Undefined symbols）。模块 prebuild 的失败形态是链接期一串符号炸，不是编译期一句错——查的时候先确认归档真的生成。
  顺带一条**分支冻结在旧线上形态**的实证：master 修过「kind=7 JS 求值全文走专用 65536 缓冲（`wb_eval_text`），事件槽只留空串」，mac 臂没有这套——`_wb_eval_text` 链接错把它炸了出来。对齐批不只补新函数，**旧函数改过的 wire 形态也要逐臂核一遍**。
- **sysmonitor mac 两支桩修复**：
  1. **`mach_task_self_` 是数据符号，`_mach_task_self` 才是函数**——libSystem 里带尾下划线的那个以 `extern 函数` 声明编得过、链得上，调一下就是**跳进数据页 SIGBUS**（signal 10）。定位靠解析崩溃报告 `.ips` 的帧符号；小复现程序（只调一句 `vm_deallocate`）五十秒出真相，比 lldb 挂全套测试快。
  2. **SIP 下 `proc_pidinfo(pid 1)` 返回 0 不是错误**：BSDINFO/TASKINFO 对 launchd 一律给 0 字节（非 root 拿不到），而 `proc_pidpath(1)` 可用——proc 表因此整列丢 launchd。修形态：读不到 stat 时由 path 的 basename 合成 comm、状态照实给运行中，让 pid 1 回到清单里（判据「0 字节」要与「失败」分开处理）。
- **mac 剪贴板换 NSPasteboard 主路径（pbcopy 对非 ASCII 静默空写）**：命令线 `printf … | pbcopy` 传**纯 ASCII** 回环正常，传**含中文/换行**的文本 rc 仍是 0、粘贴板却被清空或没写（`clipboard info` 看着健康，纯 no-op）——探针文本「yue-clip 探针·第一行\n第二行」就是这样把回环测成 None 的；同串走 `NSPasteboard setString:forType:` 完好。修法与 Linux GtkClipboard 同路：`clipboard.mbt` 的 mac 分支优先走 `yue_sys_clipboard_gtk_*` 转发层（`sys_stub.c` 非 `_WIN32` 臂 → win 桩 mac 臂的 NSPasteboard 真实现，`available` 恒 1），pbcopy/pbpaste 只作降级兜底。`sys_stub.c` 那条「Windows/macOS 给哑实现」的注释是过期的——哑分支只圈 `_WIN32`，mac 一直走的真转发，已随批改注释。
- **render mac 臂 W35 三支空桩**：`cr_set_line_cap/join/dash` 给空实现保链接——mac 走纯光栅路径（`cr_begin` 恒 0，Painter 从不进 cairo 会话），线帽语义归纯 MoonBit 光栅器，与 GTK/Win32 的 cairo 真实现刻意不同形态、同门面契约。
- **验证口径**：这批在 mac 本机跑的（`moon test --target native` 全 workspace 1236/1236），是 master 合并 mac 后**首次**在真 macOS 上全量跑库测试；CI 的 macOS job 覆盖面不变，真机目视项仍按 `测试文档/测试用例.md` 走。

- **Windows CI 链接缺 `wm_hotkey_supported`（2026-10-18）**：merge 后 CI 的 Windows job 在 shell 白盒 exe 上 LNK2019——三段式重建时 **WIN32 臂把 hotkey 的 supported 一条漏了**（register/unregister/poll 都在），GTK/mac/占位三臂反而都有。修复形态：WIN32 臂补 `return 1`（RegisterHotKey 恒在）。口径：改完单一 stub.c 的臂结构，要拿 `ffi.mbt` 的 extern 名清单与目标臂的定义逐个对——`grep -oE '= "wm_[a-z_]+"' | sort -u` 与臂内定义 `comm -23` 一步查全，别等 CI 逐个炸。（`wm_win_gui_marker` 是这类扫描要放过的合法例外：它定义在同包的另一支 native-stub `win_gui.c` 里。）

- **merge 之后 CI 才炸出来的四处「合并伤口」（2026-10-18）**：mac 分支是从 webview 出模块（4602886）**之前**的基线分叉的，并入 master 时带回了四类过期形态，本机测试全绿也照不出来，只有 CI 三平台各跑一遍才逐个现形——
  1. **主仓 prebuild 的 Windows 死调用**：mac 支把 `if system=="Windows": ensure_release_files()` 带回了 `link_configs()`，而这个函数（下载 WebView2 头/Loader）在出模块时已删到只剩模块那份——Windows job 直接 `NameError`，整条链接门都没走到。查法：CI 日志的 traceback 指到调用行，`git show <merge>^2:<file> | grep def` 确认定义只活在 mac 父侧。**跨分叉合并后，对被搬动过的文件要按「调用点全仓可解析」过一遍**（python 侧 `ast`+跑一次输出即可）。
  2. **macOS 桩门禁的旧路径**：ci.yml 的 mac gate 还写着 `web/webkit_stub.c`（模块化的前一站），clang 报 no such file、五桩门直接红。改指 `../modules/gui-webview/webview/webkit_stub.c`（working-directory 是 gui）——**门禁脚本引用源码路径时，移动包的批次要连 CI 配置一起改**，这与「重复库告警」不同，是硬引用。
  3. **macOS job 的包清单过期**：测试/构建步还点 `core`（已拆成 base/shell/widget 三层）与 `web`（已出模块），Linux/Windows job 当年改清单时 mac job 还没建所以没人回头补。对齐到 Linux 的包清单去掉 dbus（mac 无会话总线），并给 mac 补上「单元测试(gui-webview 模块)」一步（Linux/Windows 都有、mac 缺——模块的 Darwin 链接分支就此进 CI 覆盖面）。
  4. **mac job 构建步还点名已删的媒体示例**：第三条 `moon build` 写的是 `examples/systemprobe` 与 `native-web`，而 25192fe 已把这两块验证板收口删除、媒体示例换成同模块的 `audio` / `video`——CI 报 `Failed to canonicalize input filter directory`（路径不存在，测试全绿也照不出来）。改点名 audio/video 后在真 macOS 本机用同一条命令回证：ffmpeg prebuild 打出 brew 的 include/lib，gui-media 下发 CoreAudio/AudioToolbox/Foundation，14 任务链接通过。**这一族伤口同一个根**：CI 里所有「引用清单」（包名、桩源文件路径、示例包路径）都会在改名/搬家/删除的批次里变陈旧，跨分叉合并后要逐行读 ci.yml 的引用点核对存在性。
- 顺带一条同名族口径：CI 三 job 的库包清单今后以 **Linux job 为基准**（它是全量），Windows 按平台门减 sys/dbus，macOS 减 dbus；新增包要三处同改，少一处就是下一次 merge 的伤口。

- **CI 链接修复后首轮真跑到读数环，三处「runner 环境 ≠ 真机」的测试口径补齐（2026-10-18）**：Windows 链接门通了之后，模块步那条裸 `moon test`（workspace 全量）第一次把 sys 读数环暴露出来——
  1. **`/tmp` 是 Linux/mac 的落点，不是 Windows 的**：appfind 读盘用例的 `af_tmp()` 与 fsx `list_dir` 用例都写死 `/tmp`，Windows 上 `sys_write_text_file` 直接 false、五条判红。改运行时分派平台临时根（Windows 落 TEMP/TMP，探不到退 `.`；POSIX 读 TMPDIR 回 `/tmp`），与「Dock 起来的进程没有 shell PATH」同为「测试夹具也要过平台门」。
  2. **`vol_supported()` 不等于「读得到」**：Windows 的 supported 只证 COM 可起，**默认音频端点要到 `vol_get` 才暴露缺失**，而 CI runner 没有音频设备。读数环改「探针即分支」：首读 Err 就 skip 出声，设备在场（真机）才走回环断言——同 GIF 退帧那条的判据哲学。
  3. **墙钟冒烟窗不跟 runner 抖动对赌**：video 首 tick 的位置窗先按「一帧半」放宽（0.25）仍被 CI macOS 以 0.251 贴脸突破——解码积压没有上界可承诺。定稿把判据换成结构事实「已推进且未过半」（t1∈(0,0.5)，素材 1s），精确 ≈0.1 的期望只留在注释里；「推进了没跳段」的回环语义由后续 seek/pause 各步照旧钉住。
- 另记一条 CI 结构事实：三个 job 的「单元测试(gui-webview 模块)」步在工作区里会**裸跑全量 workspace**（`moon test` 从模块目录向上归一化），所以模块步实际是全平台最后一道全量闸——包清单只约束前几步，新增测试最先在这里现形。

- **焦点滞留：点击不可聚焦控件时焦点不转移、icon_button 没进键盘链（2026-10-18，真机反馈「空格回车还在操作目录按钮」）**：两个缺口叠加。①`icon_button` 建树时没领 `focus_id` 也没接键盘激活（`form.button` 有全套），于是点击它时 `focusable_at` 沿命中链找不到任何可聚焦者 → `App::route` 的 Down 分支拿到 None → **焦点原地不动**，还挂在侧栏「选择目录…」上，空格/回车继续驱动它。②更根本的：点击**不可聚焦**的自绘区时焦点应当让位（Web 的点空白 blur 语义）——原实现 None 分支什么都不做，焦点滞留是普遍行为，任何「点空白再按空格」都在盲操作远处按钮。修法：icon_button 补齐键盘口径（自动领号进 Tab 链 + 空格/回车激活 + 焦点环，与 button/menu_item 同款），`App::route` 的 None 分支改 `drop_current()`（注册表保留，IME 会话照 flush_ime_for_switch 交还）。语义现在的三档：点可聚焦控件 → 切给它；点不可聚焦自绘区 → 清焦点（空格/回车交给 key_fallthrough 兜底通道——video 的空格播放/暂停正是这条）；点原生子件 → 已有 ChildSurface 让位。gui 1239/1239、media 37/37。
- **媒体组件换载后旧音频继续解码播放（2026-10-18，真机反馈）**：现象三个一口——切换视频后响的是上一部的音轨、暂停停不掉残留的解码、窗口里的操作要点两次。根因是**结构性的**：组件把引擎（AudioPlayer/VideoPlayer）藏在建树闭包里，外层换载只能 `clear_children`（拿不到闭包），而组件的自续 tick 定时器（33ms / `ap_tick_ms`，`set_timeout` 无限自排）既没有停止钩子也没有守卫——组件被摘树后照常 `engine.pump()/tick()` 解码喂设备；用户点暂停停的是新引擎，旧引擎不受控。旧链（yue 时代）靠「换载协议：旧 stop→free→remove_child→挂新」+ closed 守卫活着，media 组件化之后这两层都断了。修法是**基础设施级**的：`Widget` 新增**控件级丢弃回调 `on_discard`**（进程级 `widget_discard_hook` 只管样式侧表清账，组件资源归组件自己停），`report_discard`（`clear_children`/`remove_child` 的递归上报）逐只触发；media 的 audio/video 组件在回调里 `engine.free()` + 置 dead 让 tick 链终止（free 幂等）。同族顺带接线：gif 动图与轮播的自转链本就以 running 标志为断链开关，`on_discard` 里拨一下即断。判据钉在 widget 层：clear_children/remove_child 触发子树逐只回调、不牵连树上兄弟、幂等不重复触发（discard_wbtest 3 条，gui 全量 1239/1239、media 37/37）。教训：**「组件持进程级资源 + 定时器自续」必须有对应的「被移除」事件**——没有卸载回调的组件系统里，任何持引擎/线程/句柄的组件都会在换树后变孤儿继续跑。
- **mac 输入法通道吞导航键：im_active 时退格/方向/Home/End/Tab 全部失灵（2026-10-18，真机反馈 T2a）**：`keyDown` 无条件把键先交 `NSTextInputContext handleEvent:`（im_active 时）——AppKit 对**导航键**的处理是派 `doCommandBySelector:`（moveBackward/deleteBackward 之类）并返回 YES，键就不进队列了；而我们的 `NSTextInputClient` 没实现那些动作（`doCommandBySelector` 是空实现），吞掉等于键凭空消失。字符键不受影响（无组合时 AppKit 对它们返回 NO）——所以真机表象是「能打字但编辑键全废」。修法：keyDown 加**功能键闸**——kVK 映射表能命中的键（退格/方向/Home/End/Tab/F 键/回车/空格/Esc）只在**组合串在飞**（`preedit_active`，候选区要用方向/回车/空格选词确认）时才交输入法，其余一律透传入队；表外的键（字母/数字/标点=文字键）照旧交（起组合要用）。组合流的每一格都闭合：起组合走文字键门、候选确认与选词走 preedit 门、无组合时功能键全透传。GTK 侧没这毛病（GtkIMContext 的 filter_keypress 对导航键返回 FALSE，4013 行的同门只拦组合），Win32 直通更没有——mac 独有。
- **NSView 没实现 `acceptsFirstMouse:`，非激活窗口首击被吞（2026-10-18，真机反馈「要点两次」）**：mac 桩的视图只实现了 mouseDown 族，没写 `acceptsFirstMouse:`——NSView 默认 `NO`，窗口不在 key 状态时第一击被 AppKit 吃掉只用于激活窗口，`mouseDown` 根本收不到；表现就是「从别的应用/面板切回来后控件要点两次，第一击凭空消失」。Win32（WM_MOUSEACTIVATE 默认 MA_ACTIVATE，首击照常派发）与 GTK 都没有这个吞没档，三平台只有 mac 缺。修法一行：`acceptsFirstMouse:` 恒 `YES`（自绘整窗的框架要的就是「点击即生效」）。完整排查口径顺带留档：库层 `App::route → route_pointer → dispatch_on_path → 组件 on_pointer` 是「Down 派发 + Up 抬起成交」的单击语义，不存在「先聚焦后点击」的两段结构；焦点在 Down 拍同步切换（`App::route` 的 Down 分支），窗口失焦/回焦的焦点保留与 ChildSurface 让位各有归属——遇到「点击要两次」先查平台首击语义，再查库层。
- **NSOpenPanel 的「选文件夹」要两把开关一起动（2026-10-18，真机反馈）**：真机测 video 示例「选目录」时确认钮恒灰——mac 桩的 `wm_file_dialog_set_options` 只写了 `setCanChooseFiles:(options & 1) == 0`，而 **`canChooseDirectories` 默认 NO 且从未被设置**：两把全关时 NSOpenPanel 里任何条目都不可选，AppKit 的表现正是「确认（选择）钮灰」，不是按钮 disabled。补 `setCanChooseDirectories:(options & 1) != 0`，与 Win32 的 FOS_PICKFOLDERS / GTK 的 SELECT_FOLDER 同语义。教训：AppKit 面板按钮灰优先怀疑「panel 当前没有可选条目」，选项位要按「默认值是什么」成对审视，不能只写要开的那一把。
- **mac ffmpeg 免 brew 化：两路探测 + Release 归档回退（2026-10-18，动态链）**：CI 的 mac job 每轮 `brew install ffmpeg`（分钟级），用户机器没 brew 就编不了媒体线。改为对齐 Windows 的 vendor 形态——`ffmpeg-mbt/prebuild.py` 的 Darwin 分支两级：pkg-config 探 brew（原路不动）→ 失败回退 **Release 下载预编译 dev 归档**（解包到 `vendor/mac/`，与 webview Loader 同族口径：sha256 逐字节校验、GitHub/Gitee 双镜像按序、`NATIVE_GUI_VENDOR_BASE` 覆盖、离线可手工放置；解包后对 `lib/*.dylib` 补 0755——dyld 映射执行段要求 x 位）。两路全断才非零退出。动态链的三个坑：
  1. **install_name 是打包机的绝对路径**：dylib 的 id 与互依赖写死 `/opt/homebrew/Cellar/...`，拷到别的机器 dyld 直接断。必须 `install_name_tool` 把 id 与全部互依赖改成 `@rpath/<basename>`，`link_flags` 下发 `-Wl,-rpath,<解包 lib 绝对路径>`，改完逐库 `codesign -f -s -` ad-hoc 重签——arm64 上改过 Mach-O 而未重签的 dylib 会被拒载。
  2. **依赖闭包决定归档来源**：brew 的 ffmpeg 闭包拖进 openssl/libvpx/x264/x265/svt-av1 等十几支 formula（otool 实测 21 库），且 x264/x265 是 GPL——「从 brew 拷五个库」两个死因（离机断链 + 许可污染）。正式归档由 `scripts/make_mac_ffmpeg_vendor.sh` **自编 LGPLv3**（`env -i` 净 PATH + `--disable-autodetect` 断掉 brew 探测；configure 后逐库 otool 断言「非 @rpath 依赖只许 /usr/lib 与 /System」），五支 dylib 闭包自持，与 Windows 的 BtbN lgpl-shared 同许可口径。
  3. **验证用等价物、真值不提前入库**：机制验证用 brew 产物 @rpath 化的 21 库测试归档 + `NATIVE_GUI_VENDOR_BASE=file:///tmp/...` + PATH 剔掉 `/opt/homebrew/bin`（pkg-config 消失）在本机走完「下载→校验→解包→链接→真解码」全链（mp3/ogg/m4a/wav/视频 6/6 绿）；测试归档是 GPL 替身不进库，prebuild 的 sha 表保持空 dict + 格式注释，正式归档上传 `vendor-v1` Release 后回填——空表时本路提示「归档尚未提供」，brew 路不受影响。
  4. **mktemp + TMPDIR 尾斜杠的「双斜杠分裂」（CI 首跑暴露）**：macOS 的 `TMPDIR` 是 `/var/folders/…/T/`（**尾斜杠**），`mktemp -d "${TMPDIR}/ffvendor.XXXXXX"` 返回 `T//ffvendor.xxx`；$WORK 拼进 `configure --prefix` 后，链接器把 install_name 里的 `//` **规范化成 `/`** 写进 Mach-O，而 @rpath 化循环拿仍是双斜杠的 `$WORK` 去 grep otool 输出——永不匹配，内部互依赖没改成 @rpath，闭包断言一枪毙命。表象极其迷惑：断言信息与 grep 模式「看起来是同一路径」（终端渲染不区分单双斜杠），本地最小复现还容易走岔（拿已签名的 brew 库测 `-change` 会先撞上「-change 改不动 LC_ID_DYLIB」的死循环，与真 bug 无关）。修法一行：`WORK=$(cd "$(mktemp -d …)" && pwd -P)` 统一物理路径。教训：拿 shell 变量当路径字符串去匹配另一工具的输出之前，先把它 `pwd -P` 规范化。
  5. **gitee 镜像当天闭环（用户手传 5 资产）**：写双镜像口径时 gitee 侧其实一个附件都没有（404 假装是「文件没传」，无法区分「格式错」）；真正上传后确认两件事——**gitee 的用户名与 GitHub 不同**（noahliu0911 / lb091188，镜像 URL 必须分开写），附件下载 URL 形状与 GitHub 兼容（`releases/download/<tag>/<文件名>`，无需改拼接）。实测价值当场兑现：本机网络直连 GitHub 下载 TLS 握手超时（gh CLI 走的通道不受影响，别把机器的网络差异读成代码故障），gitee 秒下且 sha256 逐字节一致；`NATIVE_GUI_VENDOR_BASE` 单指 gitee 跑 vendor 路，全链 6/6。仓库须**公开**——私有仓库的 release 匿名访问一律 404，而 prebuild 的镜像下载是匿名 HTTP。
  6. **urlopen 的 timeout 是 socket 级，镜像切换要另加「总预算」（另一台机器实测吊死在 GitHub）**：`urlopen(url, timeout=20)` 的 20 秒只管单次 socket 操作（连接/单次读）——**DNS 解析挂起与慢速滴流不在覆盖范围**：防火墙 DROP（而非 REJECT）的网络里 connect 可能永不返回，进程就吊死在第一个镜像上，「20 秒换下一个」永远不会发生。修法：单源下载线程化，给整个 GET 一个**总预算**（60 秒，按「10MB 归档慢网也下得完」定；连接层 socket timeout 仍 20 秒快失败），超预算放弃该镜像（daemon 线程留在后台随进程退出）换下一个。两个 prebuild（ffmpeg-mbt / gui-webview）同批加 `_fetch_with_budget`，各留一份（模块独立发布口径）。判据：本机（REJECT 网络）跑默认镜像序，GitHub 预算耗尽打「换下一个」后 gitee 接管 6/6。**随后升级为并行竞速**：串行总预算的残余浪费是「第一个镜像滴流时要干等 60 秒」——改为默认双镜像**同时发请求**，谁先给出 sha256 校验通过的完整文件就用谁（`_fetch_race`，总耗时=最快镜像；滴流镜像自然落选），60 秒总预算降级为全败兜底；`NATIVE_GUI_VENDOR_BASE` 指定自定义源（内网/私有镜像）时保持**串行按序**（`_fetch_serial`），不并行外网。本机判据同一条：gitee 先完成直接「命中镜像」，全链 6/6。

## 光标「隐藏」三平台各有一条路：mac 没有公开 hiddenCursor，GTK 别用 "none" 名串（2026-10-18,播放器全屏观感）

全屏播放器自动藏指针要的是第 6 种光标（`CURSOR_HIDDEN=5`），三平台宿主各给一条映射，两条有坑：
- **macOS**：`NSCursor` 没有公开的常驻隐藏口——`disappearingItemCursor` 是拖拽语义、`hide()` 是进程级全局藏（状态收不回来）。可用做法是自造空白光标：`[[NSImage alloc] initWithSize:NSMakeSize(1,1)]`（1×1 全透明）→ `initWithImage:hotSpot:`，并静态缓存一份（`resetCursorRects` 会被频繁调，别每次现造）。经既有 `addCursorRect:` 分派出口下发，不另开通道。
- **GTK**：`gdk_cursor_new_from_name(dpy, "none")` 看似对（CSS 光标名），但它依赖光标主题里有 none 条目，主题缺项时返回 NULL 落进「回退 default」分支——藏指针变成恒显箭头，而且这台机器看着正常、那台机器就坏。用枚举口 `gdk_cursor_new_for_display(dpy, GDK_BLANK_CURSOR)`，不查主题、恒在。
- **Windows**：`LoadCursorW` 没有隐藏档，`wm_load_cursor` 对 kind 5 返回 NULL，`SetCursor(NULL)` 即藏（WM_SETCURSOR 每次按 kind 重设，NULL 也照吃）——零特判。

## 删除线压在别的字上：逐段单独量宽再累加 ≠ 整行联合排版（CoreText 把串尾全角标点按压缩 advance 计）（2026-10-19,mac 真机反馈 showcase Markdown 段）

**现象**（用户 mac 真机）：showcase「代码文档→Markdown」里 `~~删除线~~` 的横线不压在被划的那几个字上，而是整体左偏压在「粗斜体、」上；同一段在 Linux 上看着正常。
**定位**（无头像素探针：挂 `md_rich_label` → 画进 Bitmap → 扫最长连续横run）：横线画在 x=137..183，而同一行真正排版出来的「删除线」三字从 x=153 起——**偏左 11~16px**。逐段比对「累加宽」与「联合宽」，11 段的行里漂移按 +6 / +11 / +17 一路涨；剥到最小样本、把字体区间与字节区间端点（`md_span_ranges` 给 0..6 / 6..9，正确）全部排除后只剩一条：`measure("支持、")=33`（这个「、」算 7）、`measure("支持、斜体")=65`（同一个「、」算 13）、`measure("、斜体")=39`。**CoreText 给落在串尾的全角标点一个压缩后的 advance**，而「单独量一段」正是串尾形态，于是逐段累加恒比整行联合窄。Linux 的 Pango 标点整宽一致，同一份代码在那边只是看不出来。
**修复**（两层，缺一不可）：
- **坐标层** `geo()`：段起点、段宽、行宽一律改成**整行联合量**——拿真正绘制用的那份 `AttributedText` 量前缀（`build_at(前 i 段).get_bounds_for(0,0).width`），删除线横线与链接命中从此与像素同源；
- **折行预算层** `unit_w()`：段宽改成「段尾补一个中性汉字、再减掉这个字自己的宽」，把该段还原成「后面还有字」的行中形态。只改坐标层不够——折行仍按低估的宽贪心装填，整行会超出容器：既有折行用例当场报「有内容宽 311 超出文档宽 300（未折行）」，正是这第二层。
**验证**：`gui/mdview/markdown_wbtest.mbt` 新增像素判据——横线起点须等于「删除线之前那些段」的联合行宽（容差 2px）；撤掉修复即红（`FAILED: 删除线起点 137 不在被划字段的起点 142 上`）。折行用例由红转绿。全仓 `moon test` 1253/1253、`--deny-warn` 干净。
**教训**：**「逐段量宽再累加」不能用来定绘制坐标**。凡是要落在字上的东西（装饰线、命中区、光标位），必须拿真正绘制那个对象量前缀；串尾压缩类的度量差是平台行为，Linux 不报不等于没有。

## mac 无边框来回切几次后整窗只会拖窗：`setMovableByWindowBackground:!on` 的布尔写反了（2026-10-19,真机反馈）

**现象**（用户 mac 真机）：showcase「窗口」页连点几次「无边框切换」，之后窗口只能被拖动，点按钮、点输入框全无反应。
**根因**：`wm_set_borderless` 的 mac 支里那句 `[s.win setMovableByWindowBackground:!on]` —— 取反写反，**装饰态（非无边框）反而开了「背景拖窗」**。AppKit 的 `movableByWindowBackground` 是在 `mouseDown` 阶段由窗口先拦一道：命中「不处理拖动的视图」就把这一击直接变成窗口拖动，**不再派发给视图**，于是本栈「按下入队 → MoonBit 侧派发」那条链整条收不到按下。来回切的过程中只要停在装饰态、或者缓存位与真实 `styleMask` 失真让那句早退生效（上一次的 YES 就留在窗上了），整片客户区都成了拖窗面。
**修复**：① 两档形态一律 `setMovableByWindowBackground:NO`——拖窗只认应用声明的拖拽区（`set_drag_rect` → `tryDragRect` → `performWindowDragWithEvent:`，与 Win32 的 `WM_NCHITTEST → HTCAPTION`、GTK 的按下存档起拖同一口径）；② 开关状态改从真实 `styleMask` 读、不信缓存位（全屏往返这类系统自己改 mask 的场合会让缓存失真，失真的早退表现为「按了没反应」）。
**验证**：真机复验归用户（T2 窗口段：连切数次无边框后按钮/输入照常响应，装饰态从内容区按下不再拖着整窗走）。全仓 `moon test` 1256/1256，mac 桩重编 134 tasks 无新警告。
**教训**：**自绘宿主与系统「背景拖窗」是互斥的两条鼠标路径**——开了后者，应用的按下事件在窗口层就被吞掉，看着就是「整窗只能拖、点什么都没反应」。要「声明区可拖、其余照常响应」，拖窗必须自己做（`performWindowDragWithEvent:`），系统那一档恒关。

## mac 拖文件到访达直接崩：`0 items on the pasteboard, but 2 drag images`——三支「相对路径绝对化」口径漏了 mac 这一支（2026-10-19,真机反馈）

**现象**（用户 mac 真机）：showcase 窗口页把文件拖到访达，进程当场终止——`NSGenericException: There are 0 items on the pasteboard, but 2 drag images. There must be 1 draggingItem per pasteboardItem.`，栈顶在 `wm_dragdnd_send` → `beginDraggingSessionWithItems:event:source:`。
**根因**：拖出载荷里的路径是**相对**的（演示页就写 `["README.md", "experience/adaptation.md"]`，门面注释承诺「相对路径由后端绝对化」）。Win32 支用 `GetFullPathNameW`、GTK 支用 `g_canonicalize_filename` 各自绝对化，**mac 支没做**，直接把相对串喂给 `[NSURL fileURLWithPath:]` —— 建出来的是**相对 NSURL**，它写不出任何 pasteboard 项，AppKit 于是数出「0 项 / 2 张拖拽图」并抛异常。注意这条不是返回失败而是 `raise`，救不回来。
**修复**（`wm_dnd_build_items` 的 kind 4 分支）：先 `stringByExpandingTildeInPath`，再以 `/` 开头判绝对、否则用 `[NSFileManager defaultManager].currentDirectoryPath` 拼成绝对路径（与另两支同基）；另加一道闸——`url == nil` 的路径不入拖拽项数组（空 writer 正是这条异常的直接成因）。
**教训**：**AppKit 的拖放项数量不变量以异常收场，不给返回码**——每个 `NSDraggingItem` 的 pasteboard writer 必须真能写出至少一项。跨平台的载荷口径（绝对化、去空段、编码）必须三支逐条对齐；一支漏了的后果是崩，不是降级。
**验证**：真机复验归用户（拖出到 Finder）；本机 mac 桩编译通过，全仓 `moon test` 1259/1259、`--deny-warn` 干净。

## mac 通知只从 `.app` bundle 里弹：探测按打包如实回答，并补上打包口（2026-10-19,真机反馈「mac 是不是没实现通知」）

**现象**（用户 mac 真机）：showcase「系统集成→通知」点了没影，看着像整条没实现。
**定位**（20 行 ObjC 探针跑两态，不靠目视）：裸二进制里 `deliverNotification:` 之后泵两秒，**`didDeliver` 与 `didFailWithError:` 一个都不回调**——系统静默丢弃，连错误都拿不到；同一个二进制放进带 `CFBundleIdentifier` 的 `Probe.app`（ad-hoc 签名）后立刻 `didDeliver=native-gui 探针`。顺带把现代那条路也量了：非 bundle 进程调 `UNUserNotificationCenter currentNotificationCenter` 是**直接 abort**（未捕获 NSException，exit 134），不是可 catch 的错误——换 UN 绕不开打包要求，反而更挑运行形态。
**结论与修复**：① **探测说实话**——mac 支 `wm_notify_supported()` 加一条 `[[NSBundle mainBundle] bundleIdentifier] == nil → 0`，于是 `notify_backend()` 给 None、showcase 明说「通知后端不可用（按钮会报失败）」，不再拿「已交给系统」的槽号冒充已发；② **给出路**——新增 `scripts/make_app.sh <包名> [显示名]`，把 `moon build` 的裸二进制包成 `_build/apps/Showcase.app`（Info.plist + bundle id + ad-hoc codesign），`open` 起来才真弹；③ 顺手修掉误导的后端名：mac 报 `ns-user-notification`（实现住 win 桩的 `wm_notify_*`，旧名 `win-balloon` 是 TODO 上挂着的一条）。
**验证**：探针两态读数如上；全仓 `moon test` 1259/1259、`--deny-warn` 干净；打包口本机实跑产出 `Showcase.app`，`codesign -dv` 回 `Identifier=com.moonbitlibyue.showcase`。真机（打包后）弹出与首次授权放行归用户（T4e 已按此改写）。
**教训**：系统面「代码写了」不等于「运行形态吃得到」。mac 的通知/权限一族按 bundle 身份放行，**探测必须把运行形态算进判据**，否则 UI 永远显示「可用」而什么都不发；这类「到底能不能用」先用带回调的探针问系统，别拿目视当证据。

## mac 托盘右键弹不出菜单：`respondsToSelector:` 守着一个**猜出来的假 selector**（2026-10-19,真机反馈）

**现象**（用户 mac 真机）：showcase 系统集成页「挂菜单」之后右键点托盘图标，菜单不出现。
**定位**：mac 这支的菜单链路本身是全的——`wm_tray_set_menu` 登记 `NSMenu`、`wm_tray_popup` 走 `popUpMenuPositioningItem:atLocation:inView:`。卡在最前一环：**右键动作根本没进应用**。状态栏按钮的触发掩码写成了 `[cell respondsToSelector:@selector(setSendActionOn:)] → [cell setSendActionOn:…]`，而 AppKit 这一口叫 **`sendActionOn:`**（`NSCell.h`/`NSControl.h` 都声明，传 `NSEventMask`、返回旧掩码；`NSStatusItem` 上那份 10.14 起标注 deprecated 并指名改用 button 的同名口），**没有 setter 形态**。探针回证（本机 macOS 26.5）：`respondsToSelector(sendActionOn:)=1`、`respondsToSelector(setSendActionOn:)=0`、`sendActionOn:` 返回的旧掩码 = 4（只有左键抬起）。守卫恒假 ⇒ 掩码从没设过 ⇒ `wmTrayClicked:` 只在左键抬起触发，右键那条永远不进托盘队列 ⇒ `dispatch_tray_event` 里「无 on_context 就弹已挂菜单」那支走不到。
**修复**：在 button 上调 `sendActionOn:(NSEventMaskLeftMouseUp | NSEventMaskRightMouseUp)`（守卫保留，但用真名）；顺手删掉文件头 informal 声明里那条猜出来的 `setSendActionOn:`（同处的 `setCanShowHiddenFiles:` 是真的——26.5 SDK 里查不到该属性，守卫照旧）。
**教训**：**别按 KVC 惯例猜 selector 名**。`respondsToSelector:` 守一个假名字不会报错，只会静默失效——比不写守卫更糟，因为它长得像「已经做过平台兼容」。查一眼 SDK 头或跑个运行时探针只要两分钟，比真机来回一轮便宜得多。
**验证**：探针读数如上；全仓 `moon test` 1259/1259、`--deny-warn` 干净、mac 桩编译无新警告；真机「右键托盘 → 菜单弹出 → 选中项回调跑到」归用户复验（T4d 已按此改写）。

## 系统能力探测页只列「三平台都有对应面」的族；顺带修掉三处看着像平台限制、其实是代码错的读数（2026-10-19,用户真机五张截图）

**现象**（用户 mac 真机）：showcase「系统能力探测」整页一片「读不到：…::Unsupported」，要逐条判哪些是代码问题、哪些不是通用能力。
**逐条判定**（先把同款命令在本机跑一遍，不靠猜）：
- **机器** `SiReadFailed(ioreg: Manufacturer)`——代码错。`ioreg -rd1 -c IOPlatformExpertDevice` 在 Apple Silicon 上给的是**全小写键** `manufacturer`，值还被 plist 的 data 尖括号包住（`<"Apple Inc.">`），而 `si_parse_ioreg` 按 `"Manufacturer"` 字面比、只认 `"v"` 形态。更糟的是**夹具与代码同错**（测试写 `"Manufacturer" = "Apple Inc."`），于是门禁全绿、真机恒读不到。修：键去引后按小写比，值加 `<"...">` 解包（纯 hex 的 `<6e75…>` 仍判取不到，机型走 `sysctl -n hw.model`）。
- **打印机** `PrtCommandFailed(lpstat: 退出码 1)`——查询用错了一口。macOS 的 CUPS 兼容层里 `lpstat -p` 答「未添加目的位置」（退出码 1），而 `lpstat -e` 列得出真实队列（本机 `EPSON_L3250_Series`）。修：`-p` 失败退到 `-e`（一行一个目标名，状态给新增的 `Unknown`），两条都不行才抛原错；Linux 无打印机时同样 `-p` 失败，那种情况答案本就是空列表，不该报错。
- **书签** `BookmarkError::BmNoBrowser`——契约过窄。发现逻辑与历史侧同源（同一张浏览器表、同一批 profile 候选），只把文件名写死成 `Bookmarks`；本机 Chrome 的 `Default` 里没有这个文件，书签在 `AccountBookmarks`（同一份 `roots{bookmark_bar,other,synced}` JSON）。修：候选表 `["Bookmarks", "AccountBookmarks"]`，端到端用例随即真读到并解析通过。
- **空闲 0 秒**——不是故障，`CGEventSourceSecondsSinceLastEventType` 的真实读数（刚有输入）。
- **窗口列表 / 电源计划 / 夜灯 / 最近文件 / D-Bus 会话与系统总线 / 通知能力 / MPRIS**——不是三平台概念：macOS 的窗口列表要先拿辅助功能授权、`pmset` 只有 lowpowermode 对不上「平衡/性能/节能」三值语义、Night Shift 无公开口（CoreBrightness 私有）、最近文件无公共格式、总线族是 Linux 专属。
**处置**：库侧 API 与 `@sys` 文档全保留（launcher 一类单平台目标仍要用），只把**演示板**收成「三平台都有对应面」的族——`sp_group` 从固定两块面板改成面板数组，删 `sp_windows`/`sp_dbus_media`/`sp_pp_name` 与夜灯/最近文件/电源计划四组行，pages 包随之撤 `@dbus` 依赖；页头注释与清单 T7e 写明这条口径和理由。
**教训**：① **夹具必须长得像源文**——本轮三处「Unsupported」里有两处是代码与夹具一起自洽地错，门禁全绿而真机读不到；能采一份真机原始输出当夹具就别手写。② 「读不到」先分**没做**与**做错**：同款命令本机跑一遍十秒钟，比在演示页摆一排「本平台不支持」便宜，也更接近真相。③ 演示板是**契约的形状**，不是能力全集——两平台概念进了板，等于把边界写进契约。
**验证**：`gui/sys` 包 200/200（新增 ioreg 双形态、`prt_parse_destinations`、书签候选表三条；书签那条端到端现在真读本机 Chrome 的 `AccountBookmarks`）；全仓 `moon test` 1261/1261、`--deny-warn` 干净。真机复验点见清单 T7g。

## mac 弹层整块空白：一次同步 resize 的零读数把尺寸账本永久打成了 0（2026-10-19,真机反馈浏览器示例三条）

**现象**（用户 mac 真机，`moon run examples/browser`）：工具栏「演示 ▾」点开以后，**区域确实弹出来了、也跟随主窗移动、也照样遮挡底下的点击，但整块是空的**；键盘操作不受影响（除非被那块盖住）。
**定位**（直连 `gui/build/libyue_win_stub_mac.a` 的真实 `wm_*` 口写 C 探针，用 `cacheDisplayInRect:` 把视图内容读回位图，不靠肉眼）：这条是**原生档浮层**（所在窗挂了 webview 子件时，浮层必须换成真窗口，否则自绘像素永远在子件之下）。探针读数——`wm_window_new` 之后 `桩内尺寸=320x200 风格=0xf`，紧接着 `wm_window_set_popup` **同拍**变成 `桩内尺寸=0x0 风格=0x0`，而 AppKit 侧窗框仍是 320x200、内容视图 `WMView` 内框仍是 320x200。机制：`setStyleMask:` 要换主题框架，那一拍**同步**派发一次 `windowDidResize` → `syncSize` 问 `[[self.view window] contentView].bounds`，而此时视图正从窗口上摘下来、`self.view.window` 是 nil，`nil.bounds` 就是 `{0,0}` → `s->width/height` 记成 0；**尺寸通知不会再来第二次**，账本从此停在 0。往上一层层咬合成了死局：`App::paint_frame` 见 `w<1||h<1` 直接 return（而它在 return 之前已经把 `session.dirty` 清了）⇒ 永不 `present`；`overlay_fit_pass` 要按内容实测尺寸收框，可内容的布局就发生在 `paint_frame` 里 ⇒ 永远量到 0，`w>1&&h>1` 的守卫又拦着不改尺寸。于是「窗在、位置对、吃点击、零帧」= 一块空白。
**修复**（三条各管一环）：① `syncSize` 定下**零读数不入账**的纪律——先问窗口、问不到退回视图自己的 bounds，两者都算出 0 就保留上一次的好值（平台回调里量到的 0 是「没量到」，不是「量到 0」）；② `wm_window_set_popup` 改完风格主动 `[s syncSize]` 重算并请重绘，与 `wm_set_borderless` 里 `resized/need_draw` 那条记账同纪律；③ `paint_frame` 画不了这一帧时把 `session.dirty` 留回 true——C 侧贴不出帧本来就会再请一次重绘，MoonBit 不该单方面把这笔请求吃掉。
**顺带**：`wm_is_borderless` 恒报 0。`NSWindowStyleMaskBorderless` 的**值就是 0**，`styleMask & Borderless` 永远是 0，照它判「无边框」判不出来（探针实测改完风格后仍报 0）；改成反问 `Titled` 位，与 `wm_set_borderless` 里 `now_borderless` 的写法对齐。
**教训**：① 「看着像绘制坏了」先查**尺寸账本**——一次坏读数如果能永久写进状态、而通知又不重发，故障就是永久的，跟绘制链路本身可以完全无关。② 原生档弹层此前只有 Linux 真机回证，mac 这支「编得过」被 CI 证明过、但「跑得对」没有；C 边界的问题就该在 C 边界取证（直连归档 + 读回像素），比在 MoonBit 侧猜便宜得多。③ 位标志为 0 的枚举值不能用来判「设置了该位」。
**验证**：同一探针修复后读数 `桩内尺寸=320x200`、弹层窗 `pop 帧 320x200`、视图侧非零采样 0 → 7169，`pop borderless` 0 → 1；全仓 `moon test` 1263/1263、`--deny-warn` 干净。真机「菜单条目可见、可点、Esc 收得起」归用户复验。

## mac 上 Cmd 这一族编辑快捷键全体失效：主修饰键被并进了 alt（真机：地址栏无法全选）（2026-10-19,真机反馈）

**现象**（用户 mac 真机）：浏览器示例的地址框 `Cmd+A` 全选无反应。
**定位**：不是 mac 键没送到——桩侧 `keyDown:` 对 Cmd+字母照常入队（探针：`mods=8`，且不插字符）。断在编辑内核：`gui/input/editor.mbt` 的 `handle_key` 把 `alt` 定义成 `mods & (MOD_ALT | MOD_META)`，而选全/复制/剪切/粘贴/撤销/重做全部门在 `ctrl` 上。于是 mac 上 Cmd+A **既不匹配** `ctrl && 'a'`、**又落进** `ctrl || alt → 不消费`那支——`Cmd+A/C/X/V/Z/Y` 这一族在 mac 上整体失效。上一批只做完了「菜单加速键与全局键」的 `CmdOrCtrl` 词表，编辑内核这一层没跟上。
**修复**：`handle_key` 收一个 `mac?` 位，显式区分**主修饰键**（`primary = mac ? Cmd : Ctrl`，管选全/复制/剪切/粘贴/撤销/重做）与**按词修饰键**（`wordwise = mac ? Option : Ctrl`），其余平台口径原样不变；两个调用方（`gui/ui/entry.mbt`、`gui/ui/textarea.mbt`）按运行期探测 `@shell.platform_is_macos()` 传入（建控件时探一次存下，不每按键问一遍，也不用 `#cfg`）。控件层还有两处跟着漏：只读输入框的「导航放行」掩码只写了 `CTRL|SHIFT`，mac 上只读框连全选和复制都进不来（补 `MOD_META`）；文本域把「无修饰的 Home/End = 行首行尾」判成 `!ctrl`，mac 上 `Cmd+Home` 会被当行首而不是文档首（同补 meta）。
**测试**：内核级新用例**两档都断**（`mac=true`：Cmd+A 全选、Cmd+V 被消费且不插字符、Option+箭头按词；`mac=false`：同一条 Cmd+A 不算全选、Ctrl+A 在 mac 档也不算），这样 Linux CI 与 mac 机器上跑的是同一份期望。控件级用例原先把 `MOD_CTRL` 写死，改成本宿走 `mod_edit()`——**改完先在 mac 上跑就红了**，正说明这批用例过去只在「宿主那一侧」被测过。
**教训**：把 `META` 并进 `ALT` 是一种静默失效，和「守着猜出来的假 selector」同一类：不报错，只是那一族功能永远不触发。跨平台键位的口径要落到**内核的修饰键分类**（主/次），只在词表层做 `CmdOrCtrl` 不够。用例里硬编码某一个修饰键，等于只测宿主平台。
**验证**：`gui/input` 全绿、`gui/ui` 190/190、全仓 1263/1263；真机 `Cmd+A/C/X/V/Z` 与 `Option+箭头` 归用户复验（浏览器示例地址框已 `use_system_clipboard`，复制粘贴走系统剪贴板）。

## 长 URL 在 mac 上折成「一行一个字」：硬断只切一个字符就回头重判（2026-10-19,真机反馈状态栏被顶穿）

**现象**（用户 mac 真机）：浏览器示例「新窗请求（默认拦下）」回显一条长 URL 后，底部状态栏高度乱掉、整块文字布局错位。
**定位**：mac 文本桩 `gui/text/stub.c` 的 `pt_layout` 折行档里，「断行单元比整行还宽」这一支只取**一个码点**就 `continue`；回头第一轮的判定 `line_w + uw > lim` 里 `uw` 仍是**整个剩余单元**的宽，于是立刻再次判超限——每行恰好一个字符。探针量得 214 字符的 URL 在 `max_width=200` 下折到 **1455px 高**（约 90 行），按「总宽 ÷ 盒宽」摊算只需 4 行。Linux 那支走真 Pango，没有这条路。
**修复**：硬断改成**逐字一直填到放不下为止**再断行——与 Pango 的 `WORD_CHAR`、DWrite 的 `WORD_WRAPPING_WRAP` 同形态（这两家文档都写着「单元本身超宽时按字符断，并填满该行」）。
**测试**：`gui/text/text_wbtest.mbt` 新增用例不断言具体行数（随字体变），只把行数与「总宽÷盒宽」的摊算值比、容一行取整差；把 C 改动临时回退跑一遍，用例红在 `长 URL 折到 1455px，按 789px 摊算只需 4 行`——回退即红，才算钉住。
**教训**：硬断循环的条件是「这一行还装得下」，不是「先切一个字」；同一份宽度既当判定又当步进时，**步进一格就必须重算判定**，否则判定永远指着剩余全宽。跨平台文本回归断言要用摊算/单调性，别把某平台的具体像素写死。
**验证**：`gui/text` 32/32、全仓 1263/1263、`--deny-warn` 干净；真机状态栏不再被长串顶穿归用户复验。

### macOS 真机反馈修复集（2026-10-19）

- **系统级拖出：拖拽图形不从指针下起飞、有时整趟拖不出来、回报效果恒为「没成交」**：三处独立根因同一条报障。
  - **桩与 extern 蹦床参数个数不对齐**：mac 臂的 `wm_dragdnd_send` 写成 6 参 `(id, payload, len, allowed, int64 x, int64 y)` 并把动作当返回值，而 `gui/win/ffi.mbt` 的声明与 Win32/GTK 两支都是 5 参 `(id, payload, len, allowed, int32_t *out_effect)`、返回「走没走成」。实际调用里第 5 个寄存器装的是 `Ref[Int]` 的指针，被 mac 侧当成 x 用、y 是残值；效果写不回 `out_effect` ⇒ 门面永远读 0（`Rejected`）。口径：跨平台符号一律「返回 0=这趟没起来、1=走完并写 `out_effect`」，新平台臂改签名前先对齐声明。
  - **算出来的起拖点没被用上**：`setDraggingFrame:` 的矩形按视图坐标系（左下原点）给，旧实现固定 `(-24,-24)`/`(-90,-14)` 一类以视图原点为基准的值 ⇒ 图标与文本纸片都从窗口左下角飞，且 frame 不覆盖指针所在处。改法：起拖点取存档按下事件的 `locationInWindow`，`[view convertPoint:fromView:nil]` 换到视图坐标，文件档以它为中心错位叠放、文本档以它为中心居中。
  - **拿拖入挂接当拖出的门**：起拖前查「本窗是否 `registerForDraggedTypes` 过」，没挂就直接 `return 1`——按门面语义这是「走完、效果 0」，于是 `drag_source(external=true)` 既不真拖、也**不再回落到应用内会话**（`Ok` 那支绝不回落）。出站拖拽不需要入站注册，门直接去掉。
- **验证方式**：`moon check`/`moon test win widget ui` 在库侧过；mac 臂的 C 只能在 mac 上编译，本批 Linux 主机无法自校编译，真机判据=色块/文本/文件三档各拖到访达与文本编辑器一次，拖拽图形跟手、松手成交、`on_external` 回报的效果与实际落点一致（复制/移动/链接随修饰键）。

### macOS 动图（GIF）ImageIO 合成落地（2026-10-20，macOS arm64）

- **旧口径「mac 动图族探测即不可用、退回首帧静图」已解除**：`gui/render/stub.c` 的 `WM_STUB_MAC` 臂此前把 `img_anim_*` 全写成返回 0 的桩。补了与 Windows(WIC) 同构的自建画布合成器（逐帧 `CGImageSourceCreateImageAtIndex` + `ImageRectangle`/`DisposalMethod`/`DelayTime` 属性 + disposal 2/3 语义 + 直通 alpha 合成），帧号/时长/换帧回报口径与 Linux/Windows 一致。三个实测坑：
  - **`CFRetain(NULL)` 当场 abort**（症状：render 测试整进程 SIGTRAP，崩栈停在 `img_anim_copy → anim_gif_prop → CFRetain`）：`CFDictionaryGetValue` 缺键返回 NULL，`CFRetain` 不接受 NULL，先判再 retain。
  - **GIF 帧是索引色位图，`CGBitmapContextCreate` 拒绝画它**（RGB 目标只认 8bpp 组件图；`CGContextDrawImage` 静默失败，症状=合成全透明、动图一片空白、`ink==0` 断言抓红）：常规路径失败后退回「取 data provider 原始索引 + `CGColorSpaceGetColorTable` 调色板手工展开」；`CGColorSpaceGetColorTableCount(space)` 是单参返回 size_t（不是出参式），字节序判定别用不存在的 `CGImageGetByteOrder`。
  - **公开属性清单口径修正（2026-11-06 复验时核对）**：`DisposalMethod` 其实在 Apple 公开清单上（公开常量 `kCGImagePropertyGIFDisposalMethod`，键值即裸字符串 "DisposalMethod"，在 GIF 子字典内）；**只有 `ImageRectangle` 不在公开清单**，实测可读，是 CGRect 字典表示（`CGRectMakeWithDictionaryRepresentation` 解）；读不到按默认（整幅/保留），不报错。
- **配套测试口径翻新（圆角擦角的既有断言）**：控件 `clip_rounded` 擦角 pass 落地后，`display_wbtest` 的 `mark_in` 拿 (6,6) 当基准色、且把预乘位图里「已擦掉的角」（RGB=0）当墨——改为带内取基准、`a==0` 不当墨；`basic_wbtest` 的「12 拍换 1 帧」平台差异口径不变（mac 与 WIC 同为一拍一帧）。
- **验证方式**：mac 本机 `moon test gui/render`（动图解码 61/61 过，含 `dot.gif` 逐帧前进与 `current()` 落墨断言——此前该测试在 mac 走「不可用」早退分支，等于从没验过合成器）、`moon test ui widget style theme render` 全绿（除 HEAD 既有 3 红）。**真机复验已过（2026-11-06）**：showcase「GIF 动图」段自转、暂停/继续、帧数读数、48×48 缩放档、透明底无底色块。

## 托盘图标三平台不同脸 + mac 大出菜单栏（2026-10-20，mac 真机截图 / Windows 真机截图）

- **环境**：同一份 `@shell.Tray::new`，Linux 走 SNI、Windows 走 Shell_NotifyIcon、mac 走 NSStatusItem。
- **现象**：Linux 面板上是库内置的金色月牙，Win/mac 是一枚琥珀圆；mac 那枚还大得离谱，顶出菜单栏。
- **根因**（两条独立）：
  1. **内置月牙只喂给了 SNI**：位图在 `@dbus/icon.mbt` 的 `default_icon_pixmap()`（SNI 规范的大端 ARGB），只有 Linux 支读它；Win/mac 显示的是调用方传进来的 `@win.Icon`——演示板自己现建的那枚琥珀圆。三条后端各拿各的图标源，没有共同的缺省档。
  2. **mac 按 NSImage 的点尺寸直贴**：`wm_icon_from_bgra` 建的是 `initWithCGImage:size:NSMakeSize(w,h)`，32px 原图就是 32pt，而状态栏厚度约 22pt——`setImage:` 不做缩放，图标就撑出菜单栏。Windows 侧 `nid.hIcon` 由 Shell 自己缩到小图标档，所以只有 mac 显形。
- **修复**：
  1. `gui/shell/tray.mbt`：native 支（Win/mac）在 `icon` 与 `icon_path` 都拿不到句柄时，用 `default_icon_pixmap()` 换序+预乘（大端 ARGB → 小端 BGRA 预乘，`icon_from_bgra` 的口径）建一枚内置月牙，句柄进程级缓存只建一次。三平台缺省同一张脸。
  2. `gui/win/stub.c` mac 支：新增 `wm_status_icon(icon_slot)`，按 `[[NSStatusBar systemStatusBar] thickness] - 6` 取档、保比例，返回**副本**（`copyWithZone:` 后 `setSize:`，不动图标表里的原件——同一份像素还要给窗口图标用）；建项与 `wm_tray_set_icon` 两处都改走它。
  3. `examples/showcase/pages/system.mbt`：托盘演示不再自绘琥珀圆，`Tray::new("libyue-showcase-tray")` 不传图标即得月牙（自绘档在段说明与代码里仍给出口径）。
- **验证**：`cd gui && moon check` 零错误零警告（含 mac 的 Objective-C 桩重编，`gui/build/win_stub_mac.o` 同批刷新）；`moon test shell base widget` 187/187；`examples/showcase` `moon build --target native` 通过。**助手侧看不到托盘**，以下待真机：三平台各跑一次 `moon run examples/showcase` → 系统集成页「托盘」段，看 ① 三处都是同一枚金色月牙 ② mac 菜单栏里那枚高度与相邻系统图标齐平、不被裁 ③ 切深色菜单栏月牙仍看得清。

## macOS 的 Dock 档「没效果」：只改 level 不改 collectionBehavior（2026-10-21，macOS arm64 真机反馈）

- **现象**：窗口页「层级」点 Dock（以及桌面两档），mac 上看不出任何变化。
- **根因**：Cocoa 分支的 `wm_set_layer` 只 `[win setLevel:CGWindowLevelForKey(...)]`。CG 层级是全局排序键，改完确实比普通窗高——但**窗口仍只属于它所在的那个 Space**，也不会进别的 App 的全屏 Space；而 `AlwaysOnTop` 已经给到 floating 层，两档在「同一个 Space、没有别的层可压」的场景下视觉等价，所以用户读到的是「没效果」。Linux 那侧不是这样：`_NET_WM_WINDOW_TYPE_DOCK` + `_NET_WM_STATE_ABOVE/STICKY/SKIP_TASKBAR` 由 WM 兑现，档位差别是实打实的（不进任务栏、跨工作区常驻）。
- **修**：mac 三档面板类（`Desktop`/`DesktopWidget`/`Dock`）统一配 `CanJoinAllSpaces | Stationary | IgnoresCycle`（切 Space 跟着在、切 Space 动画里不位移、不进窗口循环），`Dock` 再叠 `FullScreenAuxiliary` 并把层取 `kCGDockWindowLevelKey`——盖在全屏 App 的 Space 之上，这就是 Cocoa 上「面板常驻」的正规形态。回到 `Normal`/`AlwaysOnTop` 显式写回 `NSWindowCollectionBehaviorDefault`，不留上一档的行为位。**不做的**：macOS 没有 Windows AppBar 那种「预留工作区」的公共 API，Dock 档在 mac 不会挤压别的窗口；Windows 侧 `Dock` 仍等于 `HWND_TOPMOST`，这条口径写进 `WindowLayer` 的注释与演示段说明，免得按 Linux 的语义去预期。
- **验证**：`clang -fsyntax-only -x objective-c -fobjc-arc -DWM_STUB_MAC gui/win/stub.c` 通过（只剩既有的 API 弃用告警）；`cd gui && moon check` 零错误零警告；`moon test win base` 68/68；`examples/showcase` `moon build` 零警告。**待真机（mac）**：`moon run examples/showcase` → 窗口页「层级」：①点 Dock 后切到另一个 Space（或把别的 App 放全屏）窗口应跟过去、并浮在全屏之上，点「普通」后不再跟；②点「置顶」切 Space 应留在原 Space（与 Dock 档的区分点）；③桌面两档沉到壁纸/图标层且切 Space 常驻；④Windows 上复看 Dock 档=置顶、不预留工作区，与说明一致。

## Dock 档收敛成「面板身份」而不是「窗口类型」（2026-10-21，逐轴对比后定的口径）

- **为什么要改**：把 Dock 档按可观察轴摊开对比后，原语义是空的——Windows 上 `case 3` 与 `case 2` 同一行代码（纯别名）；Linux 靠 `TYPE_DOCK` 让 WM「按惯例」把它逐出任务栏/窗口列表/焦点列表，代码反而**主动发了 `SKIP_TASKBAR=0`**；macOS 只改 `level`，跨 Space 与全屏都不跟（就是上一节那条）。「能不能统一去边框」这条更是走不通：装饰归 WM/系统，客户端唯一「能」去掉装饰的办法是换窗口类型，而那正是连带把键盘焦点一起弄丢的做法。
- **定下来的承诺**：面板三档（`Dock`/`Desktop`/`DesktopWidget`）只承诺三件事——**不进任务栏与窗口列表、不进窗口循环、跨工作区常驻**，`Dock` 另带压顶。**边框与装饰明确不在承诺内**，外观照调用方的 `styleMask` 与用户自己的系统窗口设置走。
- **各平台落到哪条机制**：
  - X11：不再换窗口类型（`kind` 只给「图标下」保留 `TYPE_DESKTOP`——那一档非压到图标之下不可），身份改由 `_NET_WM_STATE_ABOVE / SKIP_TASKBAR / SKIP_PAGER / STICKY` 显式声明，`skip_taskbar_hint/skip_pager_hint` 同步给 `panel` 三档 TRUE。好处：装饰与焦点不动、WM 不必猜、Wayland 下也至少是个诚实的客户端提示。
  - Win32：`WS_EX_TOOLWINDOW`（1/3/4 三档给，切回普通/置顶清掉），并补一次 `SWP_FRAMECHANGED` 请 WM 重报框架——不改这个，任务栏与 Alt+Tab 的缓存要等下一次窗口变动才刷新，当场看着「没反应」。叠放仍走 `SetWindowPos` 的 TOPMOST/BOTTOM。
  - macOS：`CanJoinAllSpaces | Stationary | IgnoresCycle` 三条本就等价（⌘` 循环、跨 Space），`Dock` 档另取 Dock 层 + `FullScreenAuxiliary`；无任务栏概念，无预留工作区 API。
- **仍然没有的**：预留工作区。X11 要 `_NET_WM_STRUT(_PARTIAL)`、Windows 要 `SHAppBarMessage`（AppBar 那套约百行且只 Windows 有意义）、macOS 无公共 API。这条写成「不做」，免得再被按「Dock 就该挤开桌面」预期。
- **验证**：`clang -fsyntax-only -x objective-c -fobjc-arc -DWM_STUB_MAC gui/win/stub.c` 通过（mac 分支本地可编）；Win32/GTK 两分支本机没有对应 SDK/头文件，**编译由 CI 的 Linux 与 Windows 作业兜**（`ci.yml` 已装 `libgtk-3-dev` 等）；`cd gui && moon check` 零错误零警告、`examples/showcase` `moon build` 零警告、覆盖率门禁七条通道全绿（目录 934 条，中英文段描述同步改写）。**待真机**：Linux 上点 Dock 应「装饰与焦点照旧、XFCE 任务栏与窗口列表里消失、切视口跟着走」；Windows 上点 Dock 任务栏与 Alt+Tab 当场消失（标题栏会换成工具窗口矮框——这是 TOOLWINDOW 的系统规则，若介意可在调用方先用 `set_borderless` 定外观）；macOS 上切 Space 跟着、别的全屏 App 之上仍可见、⌘` 循环里跳过它。

## 窗口最大化 / 还原：AppKit 只有切换式 zoom:，GTK 才有同步查询口（2026-10-22，macOS arm64）

- **现象**：`Window` 有 `set_fullscreen` / `toggle_fullscreen` 却没有最大化，无边框自绘标题栏想放「最大化」键就没口可调（有系统标题栏的窗口三键本来就有）。
- **修**：`Window::set_maximized(on)` / `Window::is_maximized()` + `wm_window_set_maximized` / `wm_window_is_maximized` 两个 extern，四分支：Win32 `ShowWindow(SW_MAXIMIZE/SW_RESTORE)` + `IsZoomed`；GTK `gtk_window_maximize/unmaximize` + `gtk_window_is_maximized`（3.12+，3.12 是本仓的 GTK3 下限之内）；macOS `zoom:` + `isZoomed`；占位分支空实现返 0。
- **三处口径**：
  - **读回现问平台，不缓存布尔**：用户点系统按钮、或 WM/AppKit 自己改的态，`is_maximized` 都要读得对。三个平台都有同步查询口（`IsZoomed` / `gtk_window_is_maximized` / `isZoomed`），不需要像 `fullscreen` 那样在 GTK 上记账本。
  - **macOS 的 `zoom:` 是切换式**：AppKit 没有「设成最大化」的一等口（绿色按钮默认是全屏，按住 Option 才是 zoom），所以先 `isZoomed` 比态、相同就返回，否则 `zoom:` 切一次——不比对的话连调两次 `set_maximized(true)` 会来回翻。切完置 `resized` / `need_draw`，让宿主按新尺寸重排一帧。
  - Win32 的还原靠系统的 `WINDOWPLACEMENT`（`SW_RESTORE` 自己取回最大化前的矩形与最大化状态），GTK 靠 WM 记的 normal hint，macOS 靠窗口的 `standardFrame`——三边都不需要自己存几何。
- **验证**：新增 `gui/win/maximize_wbtest.mbt`：建窗 320×200 → 初始 `is_maximized == false` → `set_maximized(true)` 后读回 true 且客户区变大 → 再设一次幂等（尺寸读数不变）→ `set_maximized(false)` 后读回 false 且客户区回到 320×200（macOS 本机实跑通过，说明 `zoom:` 的还原几何确实由系统记着）。`cd gui && moon check` 零错误零警告、库门禁 1127/1127。**待真机**：①Linux X11 / Wayland 与 Windows 10/11 各跑同一 wbtest；②无边框档（`set_borderless(true)`）下切换仍可用；③用户手点系统最大化按钮后 `is_maximized` 读得对。（2026-10-30 Linux XFCE 系实机：①的读回恒 false——WM 回写 `_NET_WM_STATE` 是异步的，`set_maximized` 返回时态还没落定，原「设完立即读」的判据吃竞态；测试改为预算 2s 轮询读数落定（`wait_maximized` / `wait_size`），验「最终跟随」不吃时序。CI 无显示服务仍走 skip，不受影响。）

## 背景透视（`set_transparent_bg`）：窗口侧开了洞，视图侧还在声明不透明（2026-10-22，macOS arm64）

- **现象**：`set_transparent_bg(true)` 之后窗口外观没有任何变化；反过来 `set_opacity` 一切正常。roadmap 里这条写着「macOS 未接」，真机又看不出到底接没接。
- **先分清两个 API（这一条最容易混）**：`set_opacity` 是**整窗 alpha**，Cocoa 侧走 `[win setAlphaValue:]`——连文字与控件一起淡，合成器把整窗当一张图缩放，用户看到的「窗口半透明」全是它。`set_transparent_bg` 是**背景透视**：控件没铺到的像素留 alpha=0，桌面从那些洞里透出来，铺了底色的控件照旧不透明。两者互不替代，可以叠。
- **根因（macOS 少了半条）**：`wm_set_transparent_bg` 原本只做了窗口侧——`[win setOpaque:NO]` + `backgroundColor = clearColor`。但真正决定合成的是**视图**：`WMView` 没覆写 `isOpaque`，NSView 默认 `YES`，AppKit 于是仍按不透明视图合成，帧缓冲里 a=0 的像素不会露出桌面。窗口不透明位与视图不透明位是两个开关，缺一个都白搭。
- **修**：`WMState` 加 `transparent` 标记（`wm_set_transparent_bg` 里置位并 `setNeedsDisplay`）；`WMView` 覆写 `- (BOOL)isOpaque`，开透视时回 `NO`、否则回 `YES`（不开时保持原行为，常规窗的合成路径不变）。
- **另一半在绘制侧，不用改**：本栈的帧缓冲是 `Bitmap::new` 出来的全零数组，控件没画到的像素天然是 alpha=0；`root.paint` 只画树里真声明了底色的节点。所以「根容器不给 `background_color`」的窗，未铺底区域一直保持零 alpha——不需要每帧清透明。反过来说，**任何整片铺底的窗都测不出透视**：showcase 主窗整页有底色，开与不开长得一模一样。验证必须单开一扇「根不铺底」的窗（showcase 窗口页的「开透明测试窗」），窗里只放不透明卡片。
- **顺带的两个口径**：①先 `set_borderless(true)` 再开透视——标题栏归系统画，留着它那块就不跟透视走；②字直接落在透明底上时，字形不透明、字后像素透明，抗锯齿边缘按半透明合成，属于预期而非瑕疵。
- **待真机**：macOS 上点「开透明测试窗」，卡片外那圈应透出桌面；Windows（`WS_EX_LAYERED` 且色键留 0，需要 `UpdateLayeredWindow` 才有逐像素 alpha）与 GTK（RGBA visual 未在 realize 前选上）仍只有半条，路线图维持 🚧。

## mac 通知迁 UNUserNotificationCenter 后仍不弹：异步授权与同步投递之间没有排队（2026-10-24,真机反馈「还是不行」）

**现象**（用户 mac 真机）：迁到 UN 之后设置面板里通知全开、接口也报「已发送」，横幅还是不出现。
**定位**：两个硬伤叠着。① **授权是异步裁决，post 是同步立即 `addNotificationRequest`**——首次使用时授权状态是 notDetermined，UN 对未授权状态下 add 的请求**静默收下却不投（完成回调 err 也是 nil）**，之后授权框点完「允许」也**不补投**；而「弹授权框的那次点击」恰恰是第一次 post——首条必丢，点第二次本应好（授权已落定），但用户在首次失败后多半直接判死。② **诊断日志本身是坏的**：`NATIVEGUI_NOTIFY_LOG` 走 `vfprintf`，三处调用传了 `%@`（ObjC 对象格式符，`vfprintf` 不认识），读数成乱码——上一轮日志里 `didDeliver id=@` 就是它，等于盲修。另外 `UNAuthorizationStatusEphemeral` 是 iOS App Clip 专属，macOS 上编译不可用（`cc` 真编才暴露，不编 mac 分支的语法检查探不到）。
**修复**：`wm_un_ensure` 先 `getNotificationSettings` 读授权现状——authorized 直接放行、denied 明写日志并把队列清掉、只有 notDetermined 才 `requestAuthorization` 弹框；授权没落定前 `wm_un_post` 把 content 排进 `wm_un_pend`（照常返回槽号），落定后回主线程 `wm_un_flush` 补投（回调线程不保证是主线程，UN 的调用统一回 main queue）；denied 时 `wm_un_post` 返回 0 让门面报失败，不假装成功。日志 `%@` 全改 `UTF8String`+`%s`。NSUserNotification 时代的 `didDeliver/didFail` delegate 方法随之清掉（UN 时代永不回调的死代码）。
**教训**：① **「先 ensure 再 post」不构成时序保证**——异步授权与同步投递之间必须自己排队，UN 对未授权请求「不报错、不投递、不补投」的三不行为靠文档读不出来，只能按「首条必丢」倒推。② **诊断通道先自检再取证**——喂一条已知值看输出对不对，vfprintf 遇 `%@` 是未定义行为，日志坏了修什么都是盲修。③ 平台枚举按目标平台过一遍可用性，`-fsyntax-only` 不带平台宏等于什么都没查。
**验证**：mac 桩 `cc -DWM_STUB_MAC` 编译零错误、`moon build examples/showcase --target native` 通过并重新打包；库门禁 1143/1143、`--deny-warn` 干净。真机复验（授权框 → 允许 → 首条即弹横幅）归用户。

## mac UN 通知前台横幅：delegate 呈现询问只在 `[NSApp run]` 形态主循环里派发——手工循环下前台静默是架构边界（2026-10-24,「授权修完仍不弹」+「为什么默认静音」,忙循环探针多轮对照）

**现象**（用户 mac 真机）：授权竞态修完（22b5c896），通知照旧「已发送、进通知中心、没横幅没声音」；用户追问「为什么是默认静音的」。
**排除过程**（探针读数逐档收敛，纯 ObjC 探针与 MoonBit 全栈探针 `experiment/notify_mac_probe` 交叉对照）：授权状态 authorized、delegate 设置时机（启动早设/运行期设）无关；`NSApp.isRunning` 位、`[NSApp run]`、`active` 各档——**`open` 启动（active=1）+ 手工循环 + 空闲主循环：willPresent 正常派发、横幅正常弹**；同一探针加一个 16ms 高频重绘的忙循环：**willPresent 从此永不派发**；纯 ObjC 同款忙循环（`[NSApp run]`）：照常派发。为救回忙循环试了三种等待原语——投递后同步 `nextEventMatchingMask` 泵、`CFRunLoopRunInMode`、把等待挪回主循环顶层同款形态——全部等满时长零回调。期间量到一组关键读数：main queue 的 block 在**主循环顶层的等待拍**里 0.002s 就 drain，同样的 block 在投递调用栈（timer 回调内）发起的等待里永不执行；UN 的投递回执（post err=nil）0.002s 就回（XPC reply 不经主线程），delegate 呈现询问却彻底不来。
**结论**：UN 的前台呈现走「问 delegate」这一步，其回调派发依赖 `[NSApp run]` 形态建立的主循环机制；本库手工循环（主循环归 MoonBit）下，**空闲主循环偶尔能进、高频重绘一律静默**——通知照投、照进通知中心、post 无错误，只是横幅与声音都不出。这是架构级边界，不是能靠等待原语补齐的缺口。**后台路径不受影响**：应用失焦后发的通知由系统直接呈现，横幅与声音正常（用户在探针 v2 亲证过横幅）。
**本批保留的有效修复**：① 声音口径对齐 Win32（NIIF 默认有声）——UN 的 `content.sound` 不设即完全无声，之前只有 kind>=2（错误级）才带声，用户「默认静音」的直接来源；② `UNAuthorizationStatusEphemeral` 是 iOS App Clip 专属，macOS 编译不可用。
**教训**：① 平台回调「派发在主线程」的深层含义是「派发在 `[NSApp run]` 的事件循环」——手工循环必须实测 delegate 族回调，空闲时能进不算数（那个窗口不保证再来）；② 探针矩阵要包含「忙循环」档：性能形态差异能让「代码相同、行为不同」，只测空闲档会得出假阴性；③ `dispatch_async(main)` 是否被 drain 逐等待原语实测，别按「CFRunLoop 会带 main queue」的常识推。
**验证**：`experiment/notify_mac_probe`（MoonBit 全栈、自动发两条、`NATIVEGUI_NOTIFY_LOG` 读数）四轮对照读数如上；库门禁 1143/1143、`--deny-warn` 干净。真机复验口径：前台点按钮→通知进中心（横幅受边界）；把 showcase 切到失焦再发→横幅与声音正常。

## mac UN 前台横幅真相修正：钥匙是「时间敏感档」，不是主循环形态（2026-10-24,接上条,真机日志 + 探针双确认）

**上条结论被推翻**：加了 `content.interruptionLevel = TimeSensitive` + 授权带 `UNAuthorizationOptionTimeSensitive` 之后，忙循环探针与 showcase（前台高频重绘）的 `willPresent` 全部正常派发、横幅声音齐全——**「手工循环架构边界」的结论作废**，真正缺的是时间敏感档：没有这一档，UN 对前台通知的 delegate 呈现询问派发不可靠（空闲偶发可用、忙时一律静默），三种等待原语都救不回来；加上这一档，同样的忙循环立刻正常。机理推测：时间敏感通知走 UN 更积极的呈现询问通道，不依赖那条不可靠的派发路径。
**落地三件**：① `content.sound` 一律默认（对齐 Win32）；② `interruptionLevel = TimeSensitive` + 授权/补授权带 TimeSensitive 选项——老授权（alert|sound 时代给的）用 `getNotificationSettings` 的 `timeSensitiveSetting` 判缺后 `requestAuthorization` 补齐，已决定的选项不重弹框（真机日志 `auth re-grant=1`）；③ delegate 答复的呈现选项必须**带 Sound**（`Banner|List|Sound`）——给什么呈现什么，缺 Sound 前台无声。
**过程教训（对自己上一条的修正）**：① 「架构边界」的结论下早了——存在未试过的单一开关（时间敏感档）时，别把「多轮原语都救不回」升格成架构定论；② 「从 IDE 终端跑 → 责任进程身份挂终端」的推断也被真机日志推翻（终端跑补授权与 willPresent 一切正常），探索期的机制推测一律标注「待验证」，别写进结论段；③ 诊断日志的时间戳（`post at +0.001s` / `settle exit at +3.0s`）把「回执快、回调不来」拆成了两个可分别定位的事实，是这几轮排查里最值钱的读数。
**代价与待办**：时间敏感档用户可在系统设置里关，关了回到前台静默；档位已开放给应用自选（`notify_send` 的 `urgent?`，见文末 2026-11-03 节），按 kind 分档（警告/错误才 timeSensitive）不做。
**验证**：showcase 真机日志——`auth status=authorized, 补请求时间敏感档` → `auth re-grant=1` → `post ×2 err=nil` → `willPresent ×2`；忙循环探针同样 `willPresent ×2`。门禁 1143/1143、`--deny-warn` 干净。

## mac 单平台族昇格为跨平台实现：授权作为基础设施立项（2026-10-24,「能抽象的都应该做」决策）

**决策**：2026-10-19 收口系统能力探测页时判「macOS 四族明确不做」，用户复查推翻——「交给单平台的是无法抽象的；能抽象成跨平台接口的肯定应该做；授权是躲不开的场景，用最好的方式弹出授权」。本批落地：**@sys 权限族**（系统权限 probe/request，mac 走 TCC 公开口 + 系统自带引导框；操作提权随能力批）、**窗口管理 mac 档**（CGWindowList 列表/归属应用激活免授权，AX 关闭要辅助功能，缺失报 `WinError::Denied`）、**夜间色温 Windows 档**（SetDeviceGammaRamp 直调——推翻本仓「Windows 无公开色温 API」的旧判：gamma 桌面斜坡就是公开口，系统「夜间模式」开关存 CloudStore 私有 blob 与 gamma 直调互不干扰）、**夜间色温 mac 档**（Night Shift 私有口做不了 → f.lux 同款全屏点击穿透覆盖层，`CGShieldingWindowLevel` + 跨空间 + `ignoresMouseEvents`）、**电源计划 mac 档**（低电量开关降级映射 [Balanced, PowerSaver]，读 `pmset -g` 免权限、写 `osascript` 管理员授权弹框——用户取消按失败出声）。**评估后不做的**：SMAppService 登录项（只能注册主应用自身，与 `autostart_enable(app_id)` 按 id 参数化语义对不上，roadmap「明确不做」）。
**架构注**：sys 的 mac 侧窗口/屏幕实现在 win 桩（`wm_win_*_mac`/`wm_screen_tint_apply`/`wm_permission_*`），sys_stub.c 按 `__APPLE__` 分支转发——先例是 wm_file_*；sys 包（C native-stub）写不了 ObjC，转发是既定架构不是绕路。
**教训**：① 「明确不做」要带复查机制——判据（授权门槛/语义对不上）随基础设施变化会失效：权限族立项后「授权门槛」不再是理由；② 平台能力判据写进代码注释的（如「Windows 无公开色温 API」）要与 roadmap 同步复查，注释错误会传染决策；③ FFI 的 ok 出参漏写 C 侧参数不会链接失败、只在运行期读 0——extern 声明与 C 签名逐参数对照。
**验证**：全量库门禁（`moon test sys` 209/209 起步，各批独立全绿）；真机验证清单归用户（权限引导框、窗口列表/激活/关闭、色温覆盖层观感、电源计划提权弹框）。

## mac 折行器「单元孤测之和」低估联排实宽：限宽 842 排出 879 的行，行尾吞字（2026-10-26,截图「段描述吞三个字」第三轮）

**前两轮（cap 取小 / percent 100 + 探询语义）修的都是布局层，这轮探针抓到 mac 折行器本体**：CoreText 只排单行，折行是 `stub.c` mac 支自带的小排版器——贪心装断行单元，判据是「各单元**孤测**宽之和 ≤ 限宽」。探针读数：842 限宽下累加 838.5（判定放得下）、整行**联排**实宽 878.8，超 36px ≈ 3 个 CJK 字。根因是 CoreText 联排时才施加标点/混排字距调整（每单元约 +0.9px，60 单元累计 40px），孤测系统性低估整行宽。节点盒宽按容器 842 定，行尾超出的字被绘制裁剪吃掉——「（否则下一次」只看得见「（否」，第二行从「次」起笔。Pango/DWrite 在真布局对象上 `set_width` 折行，无此口径差，**mac 独有**。
**修复**：贪心装完后按「整行联排实宽」修剪——超限就回退到上一个断行单元边界（长单元硬断的尾巴按字回退），直到放得下；只剩单个断行单元时按 min-content 语义允许超（与长词硬断同档）。代价每行一次联排复测 + 少数回退轮，度量缓存兜底。
**教训**：① 折行器的累加宽必须与渲染口径同源——「逐件量、加起来估」在有联排效应的引擎（CoreText kerning）上不成立，估算只配当快路径，落锤要用整行实测；② 老用例（英文句 80px、纯 URL 200px）孤测差不到 1px，钉不住这条——折行越限的回归用例必须用 CJK 全角标点混排长句。
**验证**：新增 wbtest（真段描述串在 400/600/842/900 四档限宽下测宽 ≤ 限宽）；全量库门禁 1153/1153、`moon check` 零警告。真机：showcase 基础组件页「主题色板」段描述行尾不再吞字、窄窗拖宽折行随容器重排。

## macOS NSAccessibility 桥收口（阶段 1 二批）：焦点元素、hitTest、press 与事件上行（2026-11-03）

读屏查询全是拉取式，但**「什么时候该重新拉」是推的**——快照内容变了不发通知，VoiceOver 会拿旧树念。收口补四件：①元素从裸 `NSAccessibilityElement` 改 `WMA11yElement` 子类，press 动作压「点一下」进跨平台动作队列（与 Windows UIA 的 Invoke 同一条队列、同一条 MoonBit 合成点击路径，mac 不另设通道）；increment/decrement 不实现（值在组件闭包的 Store 里，桥够不着），如实落 NO 让读屏回落键盘。②`accessibilityFocusedUIElement` 按 MoonBit 每帧报的焦点 id 还元素（焦点通道 `wm_a11y_set_focus` 与快照表同住实现 TU）。③`accessibilityHitTest:` 按屏幕点还快照里最深的行（前序展开，后行更深）。④事件上行：快照 TSV 与上次发布不同才发 AX LayoutChanged、焦点 id 变了才发 FocusedUIElementChanged——静止界面逐帧全同，不扰民（判据放在 MoonBit 侧比 C 侧好断言，用例按通知计数增量钉）。两个本机没编译器能验的坑记牢：**宏不跨 TU**——`WM_UIA_ACT_CLICK` 在 stub.c 定义而 uia_provider.c 用，是两个翻译单元，必须各写一份（同 `WmA11yRow` 结构体两份声明的老路数）；**`@property` 不能箭头访问**——WMState 的 `view`/`win` 是属性，实现 TU 段里写 `s->view` 在 mac 上直接编不过（GTK 分支同名的 `s->container` 是 C 结构体，那种写法才对）。元素每次查询现建（批次一既定），VoiceOver 跨查询的元素身份不保证稳定，属已知边界。

## gui-gpu mac 腿五处平台硬伤：库名/后端/通道序/调试遗留/alpha 口径（2026-11-05，真机反馈驱动）

mac 跑 showcase「GPU 画布」页报「GPU 画布建不出（400x240；驱动起不来？）」。逐档加诊断（`mng_gpu_canvas_detail` 把失败原因原样交给 MoonBit 侧进 Err 串）后依次拔出五处，都与平台或「首次见到真像素」有关：

1. **库名写死 `.so`**：`wgpu_core.c` 的 dlopen 候选整链是 Linux 命名，而 mac 的 vendor 产物是 `libwgpu_native.dylib`——候选全落空，核心报 `not-found`。**两个「装载」不同源**：probe.c 一直按平台取库名（所以上层 `probe()` 报 loaded），core 另一份漏了。修法：`MNG_WGPU_LIB_BASE` 平台宏，与 probe.c / stub.c 的 L1 核心同口径。
2. **adapter 后端写死 Vulkan**：`wgpu_core.c` 里 2026-11-04 Linux 预实证原型的遗留（`aopt.backendType = WGPUBackendType_Vulkan`）；mac 没有 Vulkan 后端，直接拿不到 adapter。改 `WGPUBackendType_Undefined` 交给 wgpu 自选 primary（Linux=Vulkan / mac=Metal / Win=D3D12），与 stub.c / triangle.c 一致。
3. **上传纹理存成 BGRA8Unorm 而数据是 RGBA**：`draw_texture_rgba` 的入参语义按 trait 名与 `@render.Bitmap::to_rgba_bytes` 同口径（R,G,B,A），存进 BGRA 纹理红蓝互换。改 `RGBA8Unorm`（渲染目标仍 BGRA8Unorm，读回与位图内存同序的前提不变）。
4. **fill shader 调试遗留**：`o.col = vec4f(1.0, 1.0, 1.0, 1.0); // DBG：颜色写死`——所有 `fill_rect` 出白块。改回 `o.col = col`。Linux 读回全零时这条被盖住，真像素一出来就露。
5. **tex shader 的预乘与混合因子口径不一致**：fragment 输出 `c.rgb * op` 再用 SrcAlpha/OneMinusSrcAlpha 混合，opacity<1 时 rgb 被二次压暗。统一**直通 alpha**（`vec4f(c.rgb, c.a * in.op)`）；fill 顶点色本就是直通，两条管线同口径。

- **验证**：mac 测试进程 canvas wbtest 3/3（像素断言首次真正跑：左上红/右下蓝/中心绿混合都对上）；把 `probe.o` 抽出来从 `examples/showcase` cwd 实跑，祖先扫描报 `loaded(<repo>/modules/gui-gpu/vendor/lib/libwgpu_native.dylib)`。
- **顺带**：probe.c 补仓库布局祖先扫描（triangle.c / wgpu_core.c 同口径）——应用从 `examples/<name>` / 仓库根跑都能找到模块 vendor，不再依赖 `MNG_WGPU_LIB`。
- **边界**：Linux 腿行为等价（自选 primary 仍是 Vulkan）、未复跑；「读回全零」问题与本批无关，仍挂在上一节。
- **当前落地口径**：canvas 的管线/协议面（对象创建、两条 draw 的调用链、finish 的尺寸与字节序 BGRA、clip/opacity 走查）全部落成并有断言；**像素断言在「读回全零」时跳过并打印 notice**（已知问题见本条），真机应用进程复验归用户（TODO「首消费者」条目）。
- **顺带钉住的 wgpu 口径**（都进过报错）：sampler 零值描述符的 `lodMaxClamp=0` / `maxAnisotropy=0` 是验证错误且**默认错误处理器直接 abort**（core 里挂了静默回调后才是「降级不崩」）；`wgpuQueueWriteBuffer` 要 **COPY_DST**（不是 MAP_WRITE）；顶点缓冲另需 **VERTEX** 位；**所有 copy（buffer→texture / texture→buffer）的 bytesPerRow 必须 256 对齐**，CPU 侧垫行、读回侧解垫；v29 没有 `wgpuDevicePoll` / `wgpuSurfaceGetPreferredFormat`（前者用 InstanceProcessEvents 泵，后者格式直接 BGRA8Unorm）。

## mac 键盘的命令组合被 TSM 吞掉：keyDown 输入法门要放行 Cmd/Ctrl（2026-11-06，真机日志抓到）

`WMView keyDown:` 的输入法门原判据是「组合中（`preedit_active`）或 vk 表外的文字键（`mapped == 0`）才进 `handleEvent:`」——但 **Cmd/Ctrl 组合的字母键 keyCode 同样不在 vk 表里**（字母/数字由事件文本给，vk 表只有功能键），于是 `Cmd+A` 这类组合被 TSM 的 `handleEvent:` 整个消化：返回 YES，keyDown 不入队，**只有 keyUp 没有门、漏上来了**。真机症状是「编辑器复制/粘贴/全选/撤销/重做/查找（Cmd 族）全部失效」，`NATIVEGUI_ROUTE_LOG` 日志的指纹是「命令键只出现 `mods=8` 的修饰键按下 + `press=false` 的字母 keyUp，永无字母 keyDown」。修法：keyDown 进门判据补「命令修饰不进门」——`NSCommandKeyMask | NSControlKeyMask` 任一在即直接透传入队（命令组合语义归应用层）；**Option 保留进门**（Option+字母出特殊字符是文字键语义，走系统布局与 IME）。回车/翻页/方向键不受影响（vk 表内，本就直通）。教训：输入法门的「文字键」判据必须把「带命令修饰的文字键」摘出去，TSM 对带修饰键的 `handleEvent:` 返回值不可信。
## DMG 拖装副本双击「无法打开」：copy_tree 字节拷贝丢执行位(2026-11-08,真机反馈)

**现象**：mac DMG 拖进 Applications 后双击/聚焦「无法打开」，但跑 dist 目录里的二进制正常——一正一反。

**根因**：`copy_file` 走字节读写，权限位恒 0644。dist 内 `.app` 拷完有 `ensure_exec`(chmod +x)所以能跑；组 DMG 卷目录 `copy_tree` 又走一遍 `copy_file`，主二进制执行位丢了，`hdiutil` 按原样封卷——拖装副本不可执行，LaunchServices 直接拒启。Linux 腿无此病(AppDir 的二进制与 AppRun 都有 ensure_exec)。

**修法**：dmgroot 组装后对卷内主二进制补 `ensure_exec`；挂载 DMG `stat` 钉卷内 `rwxr-xr-x` 作验收。

**判据**：①字节拷贝(copy_file/copy_tree)不保权限位，凡拷可执行处后脚必须 chmod；②包产物验收不能只看 dist 内副本——要挂载 DMG 查卷内文件的_mode 与签名；③「A 能跑 B 不能跑」先 diff 两者生成路径上差了哪道工序。

## 自更新替换的落点是「自身旁边」：从 DMG 卷里跑的应用替换必败且旧副本混淆判断(2026-11-10,真机反馈)

**现象**：本地更新服务链路真机首测报「检测到了更新但更新失败,打开还是旧的」——而 `/Applications` 里的应用实际已替换成新版。

**根因**：两件事叠加。①替换落点按自身路径算(exe 上溯三级得 `.app` 根,往其父目录解压),应用直接从挂载的 DMG 卷里跑时父目录是只读卷,unzip 必败且原来只报退出码,看不出原因;②卷里那份旧版本没删,用户「打开」的多半是它,误判成替换没生效。实测顺序:先看 `/Applications/<App>.app` 的 Info.plist 版本与 mtime 定「替换到底成没成」,再找还在挂载的旧 DMG(`hdiutil info`)——这次时间戳一秒不差对上「重启并安装」时刻。

**修法**：mac 替换臂解压前先探父目录可写(建 `.mng-probe` 目录试),不可写报可读指引「把 .app 拖进应用程序」;替换从「unzip -o 就地覆盖运行中二进制」改成「旧 .app 整树挪 `.mng-old` 再解压新的」,解压失败撤半截树并把旧树搬回来(回滚),`.mng-old` 由新进程启动时 `update_cleanup` 清——顺带对齐了代码注释本来就声称的挪旧装新设计。

**判据**：①自更新复验先问「你跑的是哪一份」——挂载卷、/Applications、`moon run` 的 _build 三处同名应用并存时,更新链路操作的是自身旁边那份;②只读位置(挂载 DMG / 无权限目录)要在替换动作前探出来给可读报错,不能等 unzip 退出码;③替换成功的验收物是 `/Applications` 里的版本+时间戳,不是用户「打开看到的那份」。

## sysmonitor 苹果腿三坑：system_profiler macOS 26 格式漂移、APFS 容器同卷、CPU 主频档（2026-11-13，真机反馈）

- **GPU 枚举零卡**：新版 system_profiler（macOS 26 / M4 实测）的 `SPDisplaysDataType` 顶层键直挂数组、没有 `_items` 键——旧解析按 `_items` 花括号切分切不到对象，显卡页一块卡都不出。数组定位改双形态：旧版 `{"SPDisplaysDataType": {"_items": [...]}}` 与新版顶层直挂数组按锚点序试，命中哪个用哪个（syshw.mbt `json_items_objects`）。
- **磁盘两行同读数**：`/System/Volumes/Data` 与 `/` 是同一块 APFS 容器，getfsstat 出两行、容量与速率读数一致——Data 行并入 `is_system_mount` 黑名单只留 `/` 一行；黑名单顺带补 Recovery / xarts / Cryptexes。
- **CPU 主频读 0**：`hw.cpufrequency` 在部分机型无键（Apple Silicon 部分系统不导出），读 0 呈现为「无主频」——改先读 `hw.cpufrequency_max`，无键回退当前档 `hw.cpufrequency`。

## mac 透明档与 GPU 档互斥：swapchain 帧无 alpha 语义（2026-11-13，真机反馈）

- **症状**：透明测试窗整窗黑底——Metal swapchain 提交的帧没有 alpha 语义；已挂 GPU 档的窗半路开背景穿透则花屏。
- **拦**：透明档不走 GPU——`wm_l1_try` 对 `transparent` 窗不再进 GPU 档（对齐 Win32「逐像素透明档不走 GPU」的既有口径）。
- **退**：`wm_set_transparent_bg` 遇已挂 GPU 档摘 Metal 层退回 drawRect 的 CG 直贴（`wm_l1_window_drop` + `setWantsLayer:NO`；BGRA 预乘带 alpha、clearColor/opaque:NO，`dead` 挡后续 present 重挂，退回后 backing 无帧由 drawRect 经 need_draw 请一帧）。
- **配套**：hello 透明度段删主窗背景穿透按钮——主窗整片铺底验不出透视，开了只有副作用；透明演示归无边框测试窗（用例 HL-4.3）。

