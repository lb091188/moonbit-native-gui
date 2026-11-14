# 平台适配·跨平台通用

收跨平台通用的实测坑与口径：构建链与工具链、FFI 与 C ABI、组件 / 布局 / 主题 / 渲染 / 字体 / sys / 图表等库面批次，三平台同现的真机反馈修复集，以及维护约定与工具链升级批。
平台专有内容见同目录 mac.md、windows.md、linux.md、linux-distros.md。

## 图标数据与生成器(2026-09-29)

图标数据的形状对比(803 个 iconfont 图标,debug 构建,2026-09-29):「代码形状」(每图标展开为 Painter 调用 match 分支)换「数据形状」(千分定点路径串 + `fill_icon_path` 解释绘制,`scripts/gen_icons.py` 发射)前后——`icons.mbt` 51k 行/3.5MB → 4.3k 行/0.7MB;showcase.exe 23.7MB → 14.9MB(hello 同步 7.9 → 7.5MB);库模块增量编译 6.8s → 0.78s;showcase 窗口 map 41ms → 7~9ms。绘制正确性以 probe-icon 全量网格截图对照旧形态(线条/填充/镂空一致);一帧可见图标 ≤ 百级 × 每图标几百字符解析,微秒级,无需缓存。教训:生成器发射「代码」还是发射「数据」差一个数量级——大量重复几何描述永远选数据形状 + 小解释器。

## 跨平台通用(构建链 / FFI)

### 构建与链接

- 库包不得写 link 段(moon 会生成无 main 的 exe,构建失败);链接参数全部由 `scripts/prebuild.py` 经 `--moonbit-unstable-prebuild` 钩子输出 link_configs,自动传播给所有依赖库模块的 main 包,任何包不手写 `cc-link-flags`。
- prebuild 脚本约束:stdout 只能输出最终 JSON(进度信息走 stderr);全部参数放 link_flags 单一字符串自控顺序(GNU ld 单遍扫描);脚本 cwd 是使用方项目根,库路径必须绝对。
- moon 新版弃用 `moon.mod.json` / `moon.pkg.json`(`moon fmt` 一键迁移);`moon doc` 只认新格式,旧版 moon 不认新格式。
- MSVC 按 cp936 误读无 BOM UTF-8 源码,中文注释会造出假预处理错误(报错行没有那个指令):CMake 对 MSVC 加 `/utf-8`。
- 新版 moon 弃用 trait 方法隐式提升:调用写显式静态形式 `ViewLike::method(obj)`;`impl Trait for X` 声明点须补 `pub extend X with Trait::{...}`(方法清单从 `moon check --no-render` 输出生成,勿手抄);黑盒测试内引用包内符号须限定 `@<包>.xxx`。此类警告增量编译漏报,clean 全量才见全量。
- mooncakes 包页 README 渲染器只显示绝对 URL 外链图片(0.5.3~0.5.5 连发实测:包内相对路径图片无论纯 md 语法还是 HTML 一律不渲染,HTML 块更被整段丢弃,而外链 CI badge 正常显示);门面图改 jsdelivr 绝对 URL(`cdn.jsdelivr.net/gh/<user>/<repo>@master/...`,国内外可达性均衡,@master 引用有数小时缓存延迟),GitHub 侧经 camo 代理显示不受影响。
- 工具链三件套(moon/moonc/core)必须配套同版本(0.5.3 发布实测):非交互终端跑 `moon upgrade` 半途报 `IO error: not a terminal` 时只换了二进制、`~/.moon/lib/core` 未动,落得 moonc 0.10.14 + core 0.10.12 混搭——core 无 `StringView::exact_view`(sysdata 报 4 处 no method),且升号改 moon.mod 触发的全量重查才暴露,之前的增量 `moon check`/`moon test` 全绿是假绿;nightly 版本号当日即滚动下架(CLI 服务器对指名历史版本一律 403),`MOONBIT_INSTALL_VERSION` 钉版本不可行,唯一修复路径是无参重跑 `install/unix.sh` 装 latest 全家桶(二进制与 core 同批换)对齐 CI;验证:`moon version --all` 与 `~/.moon/lib/core/moon.mod` 的版本一致后升号触发全量重查,133 测全绿。
- **mooncakes 构建器对已发布包跑旧清单迁移的真实后果(0.1.0 发布实测,2026-10-15)**:`native-gui@0.1.0` 发布后,包页为 **Build failed / Documentation failed for this version**(文档不生成,API 文档缺失,包仍可安装)。构建日志(公开 API 可取:`https://mooncakes.io/api/v0/builds/log?module=<owner>/<name>&version=<ver>`)显示四个目标 native / wasm-gc / wasm / js **全红且同一根因**——依赖 `NoahLiu/yoga-mbt@0.1.0` 已发布归档里仍是 `moon.pkg.json`(`moon.pkg.json ... is no longer supported. Run moon fmt to migrate`),构建器在依赖图上就失败(`Failed to calculate build plan / Failed when discovering packages`),压根到不了本包代码。这就是 CI「依赖缓存就地迁移」循环绕过的同一条坑——**CI 迁的是本机 `.mooncakes` 下载缓存,发布到注册表的包迁不动**,消费方和构建器必然踩到。修法:**把该依赖模块(仓库里 `moon.pkg` 已在)重新发布一次,再发依赖它的包**——发布链上游必须先修。验证方式:重发 yoga-mbt 后单开零依赖包验证构建器出队转绿,再发 native-gui 看包页 `build_status`;诊断入口即上面那条日志 API(登录后的包页按钮走的同一接口)。
- **发布前预演与重发口径(2026-10-15 定)**:从各自**模块根**执行 `moon publish`(可先 `--dry-run` 空跑);发前用 `moon package` 出预演归档(`<模块>/_build/publish/<Owner>-<name>-<版本>.zip`)解包核对——零 `.json` 旧清单、`moon.mod`/`moon.pkg` 就位;跨模块发布链**先上游后下游**(下游构建要读上游归档,上游修好重发后下游才能转绿);已发布版本注册表不可原地改写,修复只能递增版本号(本次 0.1.0 → 0.1.1,仓内各模块钉版同批改齐——`moon.work` 按名+版本匹配本地成员,漏改连本地都解不开)。归档级证据两例:`NoahLiu/yoga-mbt@0.1.0` 的发布 zip 顶层已是新格式 `moon.mod`、但 `src/moon.pkg.json` 旧清单还在(包在仓内迁移前发布,注册表侧改不动);`NoahLiu/native-gui@0.1.0` 的 zip 是仓库根时期快照(旧仓库 URL、旧描述)。**临时目录中转发布不必要**:`moon publish` 在模块根就地打包该模块内容(依赖不随包),`moon.work` 只影响本地解析、不影响归档;多一层拷贝反而引入漏文件与「发布源非 git 工作区」两个风险。
- **mizchi/markdown@0.8.3 引入与传递依赖发布链定案(MD1,2026-10)**:根 moon.mod import 钉 `mizchi/markdown@0.8.3`,独立控制台探针 `examples/probe-markdown` 实证 parse / render_html / serialize 三调用(`moon run examples/probe-markdown --target native` 输出 PROBE-OK:parse 11 块含标题/围栏代码/表格/引用/列表各 1,render_html 出 h1/strong/em/code/a/ul/li/pre/blockquote/table 且链接地址保留,serialize 往返重解析重渲染全过;moon check 零警告 + moon test 576 全绿)。native 支持有据:registry 索引 0.8.0 仅 js+wasm,**0.8.1 起才加 native**,0.8.2 起加 wasm-gc,钉 0.8.3(supported-targets=js+wasm+wasm-gc+native)是支持矩阵的第一个稳妥点;其 src/moon.pkg import 实验性 `moonbitlang/core/v128`(包内注释自述仅 linear-memory 目标可达),native 属 linear-memory,探针编译通过即实证可用,无需任何额外开关。**依赖闭包会层层展开**:直接依赖 moonbitlang/async@0.20.3 / moonbitlang/parser@0.3.18 / moonbitlang/x@0.5.1 / mizchi/syntree@0.2.4 / mizchi/moomaid@0.4.0,经各包 moon.mod 二级展开实装 .mooncakes 共 21 外部包(parser→lexer/moon_config/prettyprinter;moomaid→tui/signals/svg/font/css/crater-layout/crater-core 及其下级 tui-terminal-buffer/brotli/zlib/pixelmatch/layout);x 与 syntree 存在上游多版本声明共置(markdown 要 x@0.5.1、parser 要 0.4.39、moomaid 要 0.4.47;syntree 0.2.4/0.2.3),mooncakes 单版本空间取高版本一份实装——上游各自发版漂移时闭包版本由 moon 择高,升级 markdown 须留意级联。**moon add 传递机制实测**:消费方 `moon add mizchi/markdown@0.8.3` 只写入直接依赖一行,传递闭包不进 moon.mod、安装期按 registry 索引递归解析拉取(临时模块实测输出 Using cached mizchi/syntree 等)——即本仓发布后消费方 add 本模块时构建器自动拉全闭包,依赖面成本纯安装/编译期。**定案:接受传递,不拆独立模块**(MD2 起 markdown_view 桥接 mizchi/markdown 随主模块走);依据:闭包全为纯 MoonBit 源码包,无 native stub 无链接面,不碰 prebuild 托管,对消费方零 ABI/平台矩阵/发布物体积风险,与 ffmpeg-mbt 因二进制矩阵+许可+体积拆独立模块的性质不同;降级路径预留——消费方依赖面反馈过重或上游 0.x API 波及时,再下沉独立模块(库模块退回零 markdown 依赖,仿媒体三层拆分)。注意:模块内子包(如旧链的 browser 子包模式)解决不了依赖面——mooncakes deps 是模块级声明,子包 import 一样进发布闭包,browser 模式隔离的是链接 flags 层,两者机理不同勿混用。

- **MD1 的「不拆独立模块」定案被推翻:mizchi/markdown 解析链路 fork 成 `modules/mdparse`(2026-10-19)**:环境 moon 0.1.20261012 / moonc 0.10.15。现象:`cd gui && moon check` 起手失败,报 `Failed to resolve the module dependency graph / moon.mod.json at .mooncakes/mizchi/brotli is no longer supported`——闭包链 `mizchi/markdown@0.8.3 → mizchi/signals → mizchi/brotli@0.1.0`,最后一个仍是旧清单格式,新工具链直接不认。这印证上文「注册表侧没有退路」:CI 的就地迁移只治本机下载缓存,治不了上游发布归档;而该包作者不响应 issue,没有等上游修的路。修法:取上游 0.8.3 的解析链路自建模块 `NoahLiu/mdparse`(`modules/mdparse`,包路径 `NoahLiu/mdparse`,单一包),`gui/moon.mod` 与 `gui/mdview/moon.pkg` 的依赖改指它、别名保持 `@mdast` 不变,渲染层零改动。**取舍**:保留 `block_parser*` / `inline_parser*` / `scanner*` / `types` / `entity*` / `unicode` / `attributes` / `plugin`,删掉 renderer / serializer / incremental / bench / highlight / frontmatter / toc / slug / cmd,根包 15 874 行 → 6 117 行,模块级第三方依赖清零(上游的 async / parser / x / syntree / moomaid 全部不再需要)。**三处改动**:①`scanner_search.mbt` 的 `find_line_end` 去掉 `#cfg(target=...)` 与 `@v128` SIMD 分支,统一走标量扫描——既守「平台分派禁编译指令」,又把实验 API 依赖连根拔掉(短行场景标量本就不慢);②删 `inline_parser.mbt` 三个只服务渲染的 code span 规范化函数;③上游测试随源带入,删掉 6 条依赖 `serialize` / `md_to_html` / `md_parse_and_render` 的用例(这些函数在 fork 里不存在),另把 3 条序列化往返用例改写成 AST 断言(中日文保留 / wikilink label)。包级 `warnings = "-79-25"`:-79 是 AST 类型 `derive(Eq, Debug)` 触发的新版「impl 方法隐式提升」提示(解析链路不依赖该提升),-25 是上游测试用裸名引用包内符号(不批量改写上游测试);两串警告号连写是 moonc `-w` 的语法,`-79 -25` 或 `-79,-25` 会被当成多余命令行参数。**许可**:上游 MIT,`modules/mdparse/LICENSE` 保留 `Copyright (c) 2024 mizchi` 并补本仓库修改声明,`NOTICE.md` 逐条列出来源版本、保留/删除的文件、四处修改、分发义务;`THIRD-PARTY-NOTICES.md` 同步登记。**验证**:`moon test -p NoahLiu/mdparse` 147/147(上游解析基线全过)、`moon test mdview` 32/32、`gui/moon check --deny-warn` 与 `mdparse/moon check --deny-warn` 均零错误零警告。**定名**:该模块是通用 Markdown 解析层,与 GUI 无关,模块名定为 `NoahLiu/mdparse`(不绑定仓库名),`supported_targets` 恢复上游的 `js+wasm+wasm-gc+native`,已实测 native/js/wasm-gc 三目标 `moon check --deny-warn` 通过、native 与 js 各 147/147 测试通过。

- **sys 直连 `wm_*` 的 extern 必须在 stub.c 其余平台分支留占位(2026-10-27)**:系统权限(`wm_permission_probe`/`wm_permission_request`)与屏幕色温(`wm_screen_tint_apply`)的真实现只写进 WM_STUB_MAC 臂,GTK / Win32 / 其余平台分支无此符号,showcase 链接报 undefined reference——MoonBit 侧 `sys_platform() != "macos"` 的运行时早退挡不住链接器要符号。修法:三个非 mac 分支各补同签名空桩(probe 读回未授权、tint 置 ok=1 无操作),门面语义仍由平台早退决定。规律:凡 MoonBit 直接 `extern "c"` 指向 win 桩符号(如 `wm_file_*` 对话框族),每个平台分支都得有定义;走 `yue_sys_*` 包装桩(sys_stub.c 跨平台自编进 libsys.a,如剪贴板族)的可以免。(2026-10-30 修正落点:空桩须住**声明者 sys 的 sys_stub.c**(非 mac `#if !defined(__APPLE__)` 一份即可),而非 win 桩各臂——sys 的白盒测试 exe 只链 sys 包,空桩住 win 桩时 Windows 上 `modules/gui-webview` 下 `moon test` 连带 workspace 构建 sys 白盒报 LNK2019(Linux 因 prebuild 给 SYS_PACKAGE 单独下发 libyue_win_stub.a 才一直没炸);win 桩两臂的副本同步删掉防双重定义。)
- **mac 臂 stub.c 的改动 `moon check` 与 CI 都不编，必须真机专编验证（2026-11-04，GPU L1-mac 合入实测）**：远端合入的 L1-Win/L1-mac 在 mac 上 prebuild 专编 `gui/win/stub.c`（`-DWM_STUB_MAC -fobjc-arc`）直接两处 error——`CAMetalLayer` 未声明（QuartzCore 的头，Cocoa 不带）、`(void *)s.view.layer` 缺 `__bridge`。机理：`moon check` 不跑 prebuild 不编桩（见上文 Python2 条的判据②），CI 的 mac 腿同样没编到这个 TU，「编译归 CI」对 mac 臂不成立。三条规矩：①mac 臂引用新 ObjC 类，同批把框架加进 `gui/scripts/prebuild.py` 的 `MAC_*_FRAMEWORKS`——编译期单编不报缺框架，炸在最终 exe 链接（ObjC 类符号链接期才解析；win 与 sys 共链同一份单 TU 归档，框架挂 `MAC_WIN_FRAMEWORKS` 两包同享）；②`-fobjc-arc` TU 里 ObjC 指针转 `void*` 写 `__bridge`（所有权留在 view 侧、C 只借用）；③验证一条命令判零错误：`cc -c -O2 -x objective-c -fobjc-arc -DWM_STUB_MAC -o /tmp/w.o gui/win/stub.c`，改动过 stub.c 后再 `cd examples/hello && moon build` 看 exe 真重链（归档 mtime 判据会骗人时以 `otool -L` 里新框架出现为准）。
- **L1 present 的 wgpu v29 校验零值 abort 两处（2026-11-04，mac 真机首跑抓到）**：`MNG_WGPU_LIB` 指到 dylib 后 showcase 起窗即 `wgpuDeviceCreateSampler: Invalid anisotropic clamp: 0` panic abort（wgpu 未捕获错误处理器在不可展开函数里 panic → abort 整个进程）。两处同根：C 桩 `memset` 清零吃不到 v29 头文件默认值。①`WGPUSamplerDescriptor` 补 `lodMaxClamp=32.0` / `maxAnisotropy=1`（即 `WGPU_SAMPLER_DESCRIPTOR_DEFAULT` 的值；gui-gpu canvas.c 钉过同口径，stub.c 这份同源实现漏钉）；②暂存 buffer usage 改 `CopyDst | CopySrc`——present 走 `QueueWriteBuffer` 灌数要 COPY_DST、出数走 CopyBufferToTexture 要 COPY_SRC，不 map；v29 校验 MAP 族只能配对侧 COPY（`MAP_WRITE` 只配 `COPY_SRC`），在 MAP_WRITE 上叠 COPY_DST 是又一条 abort（第二跑抓到）。这段 TU 三臂共享，Linux/Windows 的 L1 首次真机会踩同一对雷。**同批记录的已知缺口（同日已补）**：mac 装载候选补 `.dylib`（无 env 自动逐级向上找 vendor）、`NATIVEGUI_GPU_LOG=1` 诊断口（探测结论带逐级失败原因、首窗挂上尺寸）、`@win.gpu_present_status()` 读数上 showcase 探测页。
- **mac AX 元素必须按 widget id 稳定缓存：每帧现建 = 读屏属性全查不动（2026-11-04，VoiceOver 真机首测抓到）**：现象是 VoiceOver 只念窗标题与提示窗，聚焦元素一字不念。取证三层（外部 AXUIElement 探针 + lldb 附加活进程）：快照 84 行在 C 存储里俱在、子元素能枚举到 80 个、但每个元素的 role/title/value 属性查询全部回 **-25202 kAXErrorCannotComplete**——AX runtime 拿 token 回应用侧按**对象身份**解析，`accessibilityChildren` 每次现建新对象，应用又是逐帧重绘，token 永远落空。修法：id 键控 `NSMutableDictionary` 缓存 + 行内容指纹（role/name/state/value/text/enabled/矩形 + 窗原点尺寸，FNV），指纹没变复用同一对象、变了才重建该 id、`accessibilityChildren` 收尾裁掉快照里已消失的 id；`accessibilityFocusedUIElement`/`accessibilityHitTest` 同走缓存保持身份一致。顺带一处语义修正：按钮文字落在 `text` 槽（`name` 空），label 取 `name ?: text`（VoiceOver 主要念 AXDescription），value 只在 name 在场时另设防同串念两遍。判据：`/tmp` 探针读子元素 role/description err=0 且带真值；Windows/Linux 桥（UIA provider / AT-SPI）同读一份快照，若也按查询现建 COM/DBus 对象需各自评估身份稳定性。

### CI runner 环境与开发机的差别（2026-10-15，Linux/Windows job 第一次跑到测试步骤）

- **环境**：GitHub Actions 的 ubuntu-latest / windows-latest。开发机是 Ubuntu 24.04 + X11 + XFCE：有会话总线、有通知服务、有显示服务。runner 上这三样都不齐，于是「本机全绿」的测试第一次在 CI 上跑就分头炸出口径问题——每条各自取证，不是一条根因。
- **依赖图解析（CI 长期红在这里，两条根因，与本仓代码无关）**：近 100 轮 master 的 CI（往回到 2026-10-13 15:29）只有本轮成功，其余每轮都红在起手第一步：`moon check` 还没开编就退出，报 `Failed to resolve registry dependency ... module was not found in the registry`。第一层是新装 runner 的注册表索引里没有 `prowk/moonsqlitefile` 与 `mizchi/markdown`，moon 自己给出口令 `you may need to run moon update`——两个 job 起手各补一步 `moon update`。第二层刷开索引才露出来：工具链 2026-10-12 起只认 `moon.mod`/`moon.pkg`，而注册表里已发布的第三方包带的还是 `moon.mod.json`/`moon.pkg.json`（报 `... is no longer supported`）；注册表侧没有退路，就在依赖缓存落地后就地迁移旧清单（对每个 `.mooncakes/**/moon.{mod,pkg}.json` 跑一次 `moon fmt`），**只动 git 忽略的下载缓存，不动仓库源码、不改依赖版本**；每轮只解到刚下载的那一批包，下一轮才看得见新下下来的，故循环到收敛（本轮两 job 都在**第 9 轮**过）。仓内 `modules/yoga-mbt/src/moon.pkg.json` 同批迁成 `moon.pkg`（`warn_list` 原样 `-6`）——它是 workspace 成员，新工具链同样不认旧清单。
- **通知门面（真口径问题，已修）**：runner 上会话总线在、通知服务没装，`@dbus.notify_caps()` 给 `NfFailed(ServiceUnknown)`，而 `notify_supported()` 说没有后端——原先的 `core/notify_caps()` 直接转 dbus 的错误码，两条探针就不一致了。改法：`notify_caps()` 先按 `notify_backend()` 定「有没有后端」，没有就 `Err(Unsupported)`，确认是 D-Bus 后端才去问 `GetCapabilities`。契约一句话：`notify_supported()` 为假时 `notify_caps()` 必给 `Unsupported`。`dbus/notify_wbtest` 的能力用例把「总线在、服务没装」按环境缺项打印跳过，与 `NfUnsupported` 同口径，不再误判成代码失败。
- **声明式挂载（测试断言写的是开发机的巧合，已改）**：`mount_window_render(render, ...)` 的形态是 `mount_window(render(), ...)`——render **恰好跑一次，与建窗成败无关**。原测试还断言「拿不到 app 时 render 一次都不跑」，那只在开发机成立（那里建窗成功），无显示服务的机器上建窗失败但那一遍已经算过，CI 因此红。断言改为「恰好一次」。
- **文本与布局那一族要真字体，而 runner 上是「字体不同」不是「没有字体」**：Linux job 的诊断步（`fc-list` 条数 + `fc-match` + 一小段 C 探针实测 `"Sans 14"` 量 `"AAAA"`）读数是 **53 条字体、默认 DejaVu Sans、52x23**，本机同一条探针是 **48x23**（Noto Sans CJK）。apt 里补 `fonts-dejavu-core` 保证至少有一族；判据里凡是按本机度量写死的都改成与字体无关的形态：
  1. `text/range` 的「区间色落在第一个字形上」：原来要求「红块右缘 < 黑块左缘」，相邻字形的墨一挨就破——改比「红块宽度 < 黑块宽度」（左缘关系那条判据保留）；
  2. `ui/form` 的链接悬停下划线：原来只探「底行那一格」，线落在第几行随降部变——改成比整块墨量（画没画线才是要验的）；
  3. `ui/textarea` 的上下键：原来两行是 `ab` / `cd`，「记住的像素 x」在两行的映射点取决于哪个字串更宽（DejaVu 上第二行更窄，上键回到行中）——两行改成同样的 `ab`，验的是规则不是某字体的宽度关系；
  4. `mdview` 的序号/正文基线：容差 ±2px → ±6px，并写下为什么——这条要防的是「标记格没注册测量、被居中摆到行中点」那种 10px 级错位，不是逐字体对齐到 1px；
  5. `ui/basic` 的「下划线要多出墨」：判据从「比有墨行数」改成「比墨像素数」（1px 的线落进最后一行的行距时行数是平的），**顺带炸出一支真 bug**——`ui/base.mbt` 的 `draw_underline` 里 `y = top + baseline + 1.5` 撞上 `if y >= r.h { return }`，后端行盒只到基线时整条线被丢掉，表现是「样式没生效」而不是画低一格；改成线必须落在盒内（`r.h<=0` 才不画，其余按 `min(r.h-1, max(0, y))` 贴底边收），并把 plain/under 墨量、两边行数与 `measure_font` 的 w/h/baseline 一起打进断言消息。
- **`/tmp` 不是通用可写目录**：`render/image_wbtest` 的「PNG 落盘再读回」在 Windows 上红——`/tmp/...` 在 Windows 解析成 `C:\tmp`（不存在），`write_to_file` 直接给 false。落点改成相对路径（`moon test` 的进程 cwd 是模块根 `gui/`），副产物进 `.gitignore`，并在写失败时把 path 打进日志（这条判据栽过两种原因：没目录、编码器不认格式，光看报错行分不清是哪种）。
- **Windows 的清单迁移循环**：PowerShell 没有 `Select-String -QuietPattern` 这个参数名（要写 `-Pattern … -Quiet`）。写错时循环在**第一轮**就因参数绑定异常退出，报的是 PowerShell 的错，看起来像「迁移没收敛」，实际一行都没跑完。
- **Linux 工作区解析要 ffmpeg 开发包**：Linux job 的 apt 补 `libavformat-dev` 等五个 `-dev` 包——不是主链路要，而是 `moon test`/`moon check` 在 workspace 里会连带跑 `modules/ffmpeg-mbt` 自己的 prebuild，pkg-config 探不到 `libav*` 就直接失败（脚本打出的提示正是那一行 apt 命令）。
- **验证方式**：CI run 38676488227（2026-10-15）两条 job 全绿——Linux 912/912 + 构建 + xvfb 冒烟，Windows 666/666（dbus/sys 按平台缺项排除）+ ffmpeg-mbt 24/24 + gui-media 6/6 + hello 链接；字体诊断步读数见上一条；清单迁移两 job 均第 9 轮收敛。本机对照实验 `env -u DISPLAY moon test core ui dbus sys` 能复现 runner 的「无显示服务」形态。

### MoonBit cfg(platform=)

- **定案(2026-10-11):平台分派弃用 cfg,即便日后工具链修好也不翻案**——MoonBit 侧跨平台选择一律「运行时探测 + 模式匹配」,探测形态照 render 包既有的降级探针(画一笔验像素、会话句柄非零)。

### 原生渲染/文本矩阵与文字三层差异(新栈定案,2026-10-11)

- **平台矩阵**:Linux=GTK3 窗口 + cairo 光栅 + Pango 文本(系统库动态链,LGPL 无义务);Windows=纯 MoonBit 软件光栅器 + DirectWrite 文本 + WIC 图片解码(全部系统组件,零第三方依赖);macOS=CoreGraphics + CoreText + ImageIO + WKWebView(**mac 平台批落地中,详见「macOS 后端首批」节**)。**sys 能力族双平台真实现(平台批①-⑥,2026-10-14)**:wallpaper/idle/launcher/desktop/powerprofile/sysinfo/windowctl/appfind/recent_files/volume/printer/print/browser/vscode 共 17 项,每项带真机读数环,sys 188/188;详见 system-capabilities.md 的平台状态表。曾评估 vcpkg 静态链 cairo/pango,因依赖重(glib/fontconfig/harfbuzz 全家)+ LGPL 静态链「提供重链接途径」义务,与本库「原生、轻量、无负担」定位相悖而弃。
- **文字三层差异与对策**:①**高度**——行高统一为 `max(引擎自然行高, ceil(size×K))`,K 实测三平台覆盖最肥字体(微软雅黑)后定为常量,行高成为 size 的纯函数,回退字体不再影响行高,多出空间半行距上下居中、取整写死;异字体超地板时行高就地长高(优雅退化不裁字形)。②**宽度**——折行/截断/省略全部是 MoonBit 组件层决策(平台只供测量),textarea 的 wrap_units/layout_lines 纯函数不动;CJK advance≈em 实际无差,拉丁差一个词(折行/省略点边界),内容不丢失。③**像素**——矢量层(矩形/路径/AA/25 混合模式/渐变)由 MoonBit 光栅器三平台同一实现、逐位一致,断言跨平台共用;文字度量/像素分平台固有(旧栈即 Pango/DirectWrite/CoreText 三引擎),断言分「结构性(共用)/数值(平台基线目录)」两档,默认字体按平台显式编码进主题(Windows 钉雅黑系,Linux 跟 fontconfig)。
- **Linux 红利**:cairo 与 MoonBit 光栅器可逐像素对拍,cairo 当标准答案验收自研引擎(渲染批 W4 的验收手段)。
- **平台 C 桩组织**:单一 `stub.c` 多分支 + prebuild 宏(见「Windows 窗口地基 W2」小节的 win/stub.c 先例);render/text 的桩合并照此办理,Windows 侧不引任何 C 渲染/文本库(仅 WIC 属系统组件)。

### MoonBit 原生 GUI 栈 · 纯 MoonBit 光栅器(W4,Windows/mac 渲染后端)

- **架构**:`render` 拆出四个纯 MoonBit 文件——`raster_path.mbt`(路径命令/仿射矩阵/贝塞尔自适应展平/弧→贝塞尔 kappa)、`raster_fill.mbt`(4×4 超采样非零环绕扫描线填充 + miter 上限 10/butt cap 折线偏移描边)、`raster_blend.mbt`(25 混合模式:Porter-Duff 九式预乘闭式 + 16 个 W3C 公式非预乘域 + 渐变求值)、`raster.mbt`(`Raster` 会话,与 `Cairo` 方法面逐条镜像);`Painter` 门面改双后端枚举,**运行时探针**(`Cairo::over` 建不出会话即纯路径)选择,无编译指令。桩合并为 `render/stub.c`:cairo 真实现挂 `WM_STUB_CAIRO` 宏仅 prebuild(Linux)编,非 Linux 全占位保链接、探针探到占位即退纯路径。文本层经 `Painter::cairo_id()` 探测:cairo 后端画在会话上下文,纯后端返回 None(W5 据此走直接往 Bitmap 画的 DirectWrite 形态),`Painter::raster()` 取纯会话。
- **覆盖量化的口径**:4×4 超采样、每像素 16 样本、覆盖 0..256(每样本 16)——与 cairo 解析覆盖的单像素差被「对拍容差带 ≤16(一个采样档)」吸收;满覆盖/零覆盖像素精确。跨点判定用半开区间 `(ay<=ys)!=(by2<=ys)` 防顶点重计;非零环绕扫描「非零区间收样」,开折线 fill 自动闭边(**末边就是环绕边,边数 = n 而非 n+1——写 n+1 会 pts[n] 越界,单测全是闭合路径测不出,真窗口 45 帧当场崩,教训:开放路径要有专项用例**)。
- **预乘取整必须两步,不能合并**:源预乘是 255 域(`(v·a+127)/255`)、覆盖缩放是 256 域(`·cov/256`),合并成 65536 域一步会吞掉 255/256 的比例差(不透明满覆盖实测 254 而非 255,成片差一);合成侧 Normal 的 `s+(d·inv+127)/255` 与 Bitmap::paint 同式,矩形路径逐位一致。
- **与 cairo 的已知口径差(容差带内)**:①AA 覆盖 16 级量化 vs cairo 解析覆盖;②blit 最近邻 vs cairo 双线性(1:1 与不透明像素逐位一致,缩放采样有差——采样域收口语义已镜像:恒落在源子矩形内防串色);③渐变 stop 非预乘插值(CSS/W3C 口径)vs cairo 预乘域(半透明 stop 中间色有差,不透明 stop 无差);④描边设备线宽 = 用户线宽×sqrt(|det|),非均匀缩放的笔帽近似;⑤斜矩阵 clip 取包围盒。25 混合模式的 W3C 公式值双平台同测同过(cairo 算子与手算公式在 8bit 域一致)。
- **MoonBit 写法坑(本批新踩)**:`moonbitlang/core/math` 才有 sin/cos(`@math.sin`,Double 无此方法);`let 大写` 非法要用 `const`;科学计数法 `1e-9` 解析报错须写全 `0.000000001`(旧坑复踩,建议 grep `1e-` 自查);match 臂尾逗号非法;三元组 match 臂 `(a,b,c)` 后不能带 `,`。测试侧:`Cairo::over` 直连的测试改为「后端探测 + 结构档断言」跨平台共用;解码依赖测试加 `decode_available()` 探针守卫(环境缺件只跳过不硬断)。
- **验证**(2026-10-11,Windows 本机):render 43/43(新增「路径/描边/弧两后端对拍(AA 容差)」)、icons 4/4(**图标路径全量出像素**经纯光栅器)、core 62/input 10/mdview 26 复绿、theme 7/8(剩字体实测归 W5);native-window 冒烟 45 帧干净退出(真窗口逐帧全走纯光栅器);全仓 check 287/68 持平。Linux 侧 cairo 路径逐位不动(桩内容原样平移),对拍测试在 Linux 上即「cairo vs 纯实现」验收,待用户侧复跑。

### MoonBit 原生 GUI 栈 · 自绘消息框（W21b：`@ui.message_box_t`，与 W20d 原生档并存）

- **自绘档与原生档是两条路、互补而非替代**：`@win.show_message_box`（W20d）走 `MessageBoxW`——系统外观、系统模态、**阻塞**返回编号，但**只有 Win32 有**（macOS 留桩）；`@ui.message_box_t`（本批）纯自绘、吃主题、**非阻塞**（点按钮回调编号），三平台同一份代码。调用方按需选，两者语义面对齐（标题 / 正文 / informative 副行 / 多按钮 / 响应回调）。
- **响应编号由调用方给，不借用 Win32 的 1..7**：`buttons` 是 `(文案, 响应编号)` 列表，组件原样回传。原生档的 `Ok(1)/Cancel(2)/…/No(7)` 是 `MessageBoxW` 的返回值口径，自绘档不该被它绑住——**两套编号刻意不互通**，状态行里也就分成 `NATIVE-APP-MSGBOX`（原生）与 `NATIVE-APP-MSGBOX2`（自绘）两行。
- **✕ / Esc / 点遮罩 = 收起但不给编号**（走 `on_dismiss`）：原生 `MessageBoxW` 的 ✕ 归 `IDCANCEL`，自绘档不这么借（见上条）；要「取消也算一个结果」，调用方自己放一个取消按钮即可。`close_on_mask` 默认 **false**——消息框通常要求显式作答，点空白处就关掉容易误操作。
- **Enter = 第一个按钮**（与原生档 `default_index=0` 同义）。Esc/Enter 要能收到，就得**接管焦点**：开层时 `msgbox_alloc_focus_id()` 取一个 700000 起的 id、`@core.host_active()` 上 `focus.register` + `focus.focus`，面板自己当焦点控件（层级上比遮罩深，键先到它）；收层时 `unregister` 并把**开框前那个焦点还回去**。取号从 700000 起是为了避开调用方常用的低号段（示例里用 1..25）——**焦点 id 是全局命名空间，组件内部取号必须留余地**。焦点栈改为「每回合按控件树对齐」之后（见本节末《键盘焦点全线失效》），这里的 `register` 仍成立：图层档的面板本来就在本窗树里，对齐只会保住它。
- **枚举变体名不许叫 `None`（本批踩到的编译期连带伤）**：`MsgBoxKind` 最初写 `None`，结果**同包其它文件**里所有 `Store::new(None)` 都开始按 `MsgBoxKind::None` 推断，`datetime_wbtest` 当场 6 条类型错。原因：`Store::new(None)` 这类**没有期望类型**的位置，同名构造器会被抢去解析。改叫 `Default` 即消。教训：往包里加枚举时，**变体名要先看包内有没有同名的无期望类型用法**（`None` 首当其冲，其次是 `Warning` 这类与 `SemanticType` 撞名的）。
- **与 `dialog_t` 的关系**：两者共用 `core/overlay.mbt` 的同一套浮层机制（铺满遮罩 / 居中 / 点外收起 / 开层即重排），差在语义面——`dialog_t` 是「内容对话框」（任意内容树 + 确定/取消两个出口），`message_box_t` 是「消息框」（按种类取图标 + informative 副行 + 任意多按钮各带编号）。要做纯内容对话框仍走 `dialog_t`，本批**没有**把两者合并。
- **回证**：`ui/message_box_wbtest.mbt` 新增 **8 条**（3 条纯函数：五种种类的图标名/取色互异/默认钮编号；5 条运行时：Store 驱动弹收 + 面板居中 + 四区结构 + 按钮回调编号与收起 + ✕/Esc 走 dismiss 而 Enter 走默认钮 + `close_on_mask` 两态 + informative 空则不留副行 + 空文案按钮跳过），用无头控件树 + 手动装的浮层宿主（同 `overlay_wbtest`），**不需要真窗口**。`moon test ./gui/ui` **118/118**（原 110）。示例 `examples/native-app` 新增自绘消息框区块（信息/警告/错误三个按钮各驱动一个消息框）与退出状态行 `NATIVE-APP-MSGBOX2 shots=… last=… ovl=…`（`ovl=` 是运行中浮层数的末次快照，理由同 W20c 的退出读数坑）；真机冒烟 `exit 0`、`NATIVE-APP-MSGBOX2 shots=0 last=- ovl=0 native_ovl=0`（未点按钮故未弹）。`moon check ./gui/ui ./examples/native-app --deny-warn` 零警告，全仓红点 **287/68** 持平。

### MoonBit 原生 GUI 栈 · 拖放门面（W21c：`core/drag.mbt` 会话模型 + `@ui.drag_source`/`drop_target`）

- **应用内拖放全自绘、三平台同构**：旧链路的拖源/投放是**平台回调**（GTK `gtk_drag_*` / Win32 `IDropTarget`），还要分别注册 enter/update/leave 三件；本栈的**应用内**拖放不碰任何平台接口——会话模型在 `core/drag.mbt`（进程级），声明式两个钩子在 `ui/drag.mbt`。**跨应用**的系统级拖放（拖出窗口 / 接系统文件）仍随平台批，门面接口形状已定，后端接上后 UI 侧不用改。
- **载荷是自有类型，不是平台图像类型**：`DragData{Text,Html,Paths,Img}`；`Img` 存**原始 PNG 字节**而非平台图像句柄——模型层不带平台类型，才能跨后端/跨进程传。`DataKind{Text,Html,Image,FilePaths}` 各给一个稳定编号（1/2/3/4），`drag_encode`/`drag_decode` 编成 `[kind:i32 LE][payload]`（`Paths` 用 `\n` 连接）——这是将来跨进程/跨后端传载荷的稳定 ABI。
- **会话是进程级单例，落点按窗口坐标算**：同一时刻只允许一个拖拽在跑（`drag_current`）。落点由 `Widget::drop_target_at` 从后往前找**最深**带 `on_drop` 的可见控件；悬停高亮由绘制方读 `@core.drag_hover()` 自判——**省掉 enter/update/leave 三个回调**，也就没有「离开回调漏发」的态同步问题（旧链路的老毛病）。
- **按下捕获的语义差异（本批踩到，务必分清）**：`route_pointer` 在 `Down` 记下的 captured id 是命中链上**最深**的控件（与 Web `pointerdown` 的 target 同义）；拖源包装层的 `on_pointer` 是靠**冒泡**收到事件的（内容件自己不处理指针，就往上传）。因此 `@core.drag_source()` 记的是**包装层** id，而捕获 id 是**内容控件** id——测试断言要按这个区分（曾误写成断言等于包装层 id）。
- **拖源内容里别放按钮**：指针事件**最深优先**，内容里的交互控件会先把按下吃掉，那样就拖不动它。拖源里放展示件（文本/图标/缩略图）即可。**这是使用约束，不是 bug**。
- **`payload()` 惰性求值**：只有**过了阈值**（默认 4px）才调 `payload()` 取数据开拖；没过阈值按普通点击放行——内容里的选择/点击不受影响。`payload()` 返回 `None` 时这一拖不成立，也退回普通按下。
- **给值类型 `derive(Eq)` 会触发 `implicit_impl_as_method` 告警**（本批的编译期坑）：正确形态是手写 `pub impl Eq for DataKind with fn equal(self, other) -> Bool` + `pub extend DataKind with Eq::{not_equal, equal}`。注意实现函数名是 **`fn equal`**（首次写成 `op_equal` 编译器报 `no method op_equal in trait Eq`）。`DragData` 因含 `Bytes`/`Array` 没有走 `Eq`（也没实现 `Debug`），测试观测一律走字符串/编号。
- 另一个实现坑（记档）：`Bytes` 没有 `op_set`，`raw[4:...]` 给的是 `BytesView` 不能直接切——拼字节用 `FixedArray::make` + `Bytes::from_array`；`split("\n")` 得 `Iter[StringView]`，要 `.map(fn(s){ s.to_owned() })` 才是 `Array[String]`。
- **回证**：`core/drag_wbtest.mbt` **6 条**（编号往返、`DragData::kind`/`as_text`、编解码往返与坏输入、`drop_target_at` 最深命中、会话 `begin→move→drop`、无落点/拒绝/`cancel`、无根时落点恒无）；`ui/drag_wbtest.mbt` **4 条**（按下→过阈值开拖→移到目标→松手投递、没过阈值当普通点击/投空白处不投递、`accept` 拒绝时回调不跑、`payload` 给 `None` 不产生会话），全走宿主的 `@core.route_pointer`（含按下捕获），**不需要真窗口**。`moon test ./gui/core` **115/115**、`moon test ./gui/ui` **122/122**。示例 `examples/native-app` 新增拖放区块（两个拖源「文本载荷 / 路径载荷」+ 两个落点「全收 / 只收路径」）与退出状态行 `NATIVE-APP-DRAG drags=… drops=… active=… last=…`；真机冒烟 `exit 0`、`NATIVE-APP-DRAG drags=0 drops=0 active=0 last=-`（未拖故计数为 0）。`moon check ./gui/core ./gui/ui ./examples/native-app --deny-warn` 零警告，全仓红点 **287/68** 持平。
- **本批未做且不假装完成**：跨应用系统级拖放（拖出窗口/接系统文件，随平台批）、拖拽视觉反馈（跟随指针的 ghost 缩略图——现在只描落点高亮）、macOS 后端、拖拽的真机观感（归 `测试文档/测试用例.md`）。

### MoonBit 原生 GUI 栈 · 全局快捷键跨平台门面（W22：`core/hotkey.mbt`，三族门面统一的最后一族）

- **W22 的范围收敛**：「托盘 / 通知 / 热键三族门面统一」里，托盘（`core/tray.mbt`）与通知（`core/notify.mbt`的门面在 W20c/W21a 已各自落成，本批**不重构它们的既有 API**（改错误类型与探测命名是纯破坏性改动，调用方零收益）；真正缺的一面是**热键根本没有跨平台门面**——W20b 只落在 win 包（`register_global_shortcut` 等自由函数 + `parse_accelerator` 纯函数），Linux/macOS 调用方无从写同构代码。故 W22 = 补 `core/hotkey.mbt`，形态对齐另两族：**探测 `hotkey_supported()` + 结构化错误 `HotkeyError{Unsupported, Failed(String)}` + 泵钩子 `hotkey_poll()`**。
- **后端现状与降级口径**：Windows 真实现（`RegisterHotKey` + 线程队列，W20b 已验）；Linux 的 X11 `XGrabKey` 与 macOS 的 Carbon/AppKit 热键**未接**，一律 `Err(Unsupported)`——「没做」与「失败」分两档，调用方据此藏 UI，与 tray 的 SNI watcher 不在线、notify 的无后端同口径。
- **加速串进出，id 回查在门面**：注册收字符串（`"Ctrl+Alt+F9"` / `"CmdOrCtrl+Shift+M"`，`CmdOrCtrl` 按平台映射 Ctrl/Cmd——解析委托 win 的纯函数，不在 core 重写一份）；轮询 `hotkey_poll()` 命中给 `Hotkey{id, spec}`——Win32 的 `poll` 只回 id，**加速串回查表由门面自己持**（进程级、与 win 注册表同生命周期；表外 id 的 `spec` 给空串，表示不是经本门面注册的）。
- **平台探测走运行期 `@sys.sys_platform()`**（C 桩 `ffi_sys_platform` 回 1/2/3 → "windows"/"macos"/"linux"），与「运行时探测 + 模式匹配、禁用 `#cfg`」的定案一致；`is_mac` 判据同源（决定 `CmdOrCtrl` 映射）。
- **两个本工具链小坑（都已在代码里踩过）**：① `Array` **没有 `find`**——回查表线性扫用手写循环（`for h in arr { if … return Some(h) }`）；数组追加用 `arr.push(x)`，**不要写 `arr + [x]`**（解析器把 `+` 当 infix，报 `unexpected token infix 1`，错误信息离根因很远）。② `inspect(value, content="…")` 的 `content` 是**与 value 字符串化结果比较**的字符串——布尔值要传 `"true"`/`"false"`，传 "supported" 这类描述词必失败（本批与 taskbar 批各踩一次，记此一处）。
- **回证**：`gui/core/hotkey_wbtest.mbt` 2 条（未注册 id 回查给空串；「连上了才硬断言」——后端可用时空加速串必须走 `Err(Failed)` 而不是崩或静默成功，其余平台只打印 skip）；`moon test ./gui/core` **118/118**（原 116 + 新增 2）。`examples/native-app` 的热键区块从直调 `@win.*` 切到 `@core.hotkey_*`（注册 / 轮询两处，轮询命中直接拿 spec 回显），`--deny-warn` 零警告、冒烟 100 秒无 panic 无 CRITICAL。
- **本批未做且不假装完成**：macOS 热键后端（门面已就位，后端落地不改调用方）；Linux `XGrabKey` 已在同批 W22 Linux 档落地，见下文「Linux 全局热键后端」条；tray/notify 两族既有 API 的统一重构（明确不做，理由见第一条）。

### 媒体音频后端跨平台化：单调时钟三平台（2026-10-12）

- **引子**：上一批把媒体包挪进独立模块时，把「媒体在 Windows 上构建不了」的根因概括成「POSIX 时钟 + ffmpeg 未接」。本批把其中**属于我们自己的那一半**做掉——`audio_stub.c` 是媒体的音频后端（miniaudio 设备层 + PCM 队列），**零 ffmpeg 依赖**，它能不能编、编出来能不能跑，可以单独钉死，不必等 ffmpeg 那条线。
- **现象（MSVC 实测）**：`audio_stub.c` 报 `error C2065: "CLOCK_MONOTONIC": 未声明的标识符`，并附一条 `warning C4013: "clock_gettime" 未定义`——`CLOCK_MONOTONIC` 是 POSIX 专有常量，MSVC 的 `<time.h>` 不提供（`clock_gettime` 也只在 UCRT 的部分版本里有）。
- **修复（单一 stub.c 多分支 + 平台宏，先例 `win/stub.c`）**：`mbt_now_ms` 按平台三分支——`_WIN32` 走 `QueryPerformanceCounter` / `QueryPerformanceFrequency`（QPC 是 Windows 的单调高精度计数器；**不用 `GetTickCount`**：粒度粗 ~15.6ms，且会被系统时间调整带偏）；`__APPLE__` 走 `mach_absolute_time` + `mach_timebase_info`（不用 `clock_gettime`：`CLOCK_MONOTONIC` 在 macOS 要 10.12+，mach 更保守且同为单调计数）；其余 POSIX 保持 `clock_gettime(CLOCK_MONOTONIC)` **原样不变**。三支都返回「自任意固定起点的毫秒数」，只用于差分（`elapsed = now - wall0`），绝对值无意义——所以起点因平台而异不影响播放时钟。
- **两处溢出防线**：①Windows 分支拆成 `(ticks / freq) * 1000 + ((ticks % freq) * 1000) / freq`，避免 `ticks * 1000` 在 64 位溢出（QPC 计数自开机起累计，10MHz 下一年 ≈ 3.15e14，乘 1000 后仍有量级余量，但拆开更稳）；②macOS 分支用 `__uint128_t` 过渡 `t * numer / denom`，防 Apple Silicon 上 numer/denom 非 1:1 时中间乘积溢出。
- **两份拷贝同步改**：`media/audio_stub.c` 与 `src/audio_stub.c` 此前逐字节相同（md5 `2b807752…`）。改时一度只在 `src/` 多写一句注释，结果两份**不再**逐字节相同——当场回退那行，两份恢复一致（改后 md5 均为 `856a4c98e3879e77aa5108f7bb4dcfd8`）。理由：旧链下线时的「归一」要能直接取一份，两份静默漂移会让这件事没法机械判断。
- **回证（纯 C 探针 `experiment/media_probe/audio_backend_probe.c`，直接 `#include` 平台后端）**：末行 **`AUDIO-BACKEND-OK`**、**48 条断言全过**、0 失败——①**时钟**：连续/五连读单调非减、为正、`Sleep(60)` 后推进 61ms（落在 [40,400] 区间）；②**设备开参数**：`channels ∈ [1,8]` 且 `rate > 0` 才收，`0`/`9`/`-1`/`rate=0`/负 rate 一律回 NULL；③**队列与音量语义**（与设备是否存在无关）：push 追加、`queued_bytes` 累计 400→600、非法 push 不改队列、`clear` 清零且二次幂等、`played_bytes` 非负、volume 钳到 [0,1]（0.5/1/0.25 读回一致、-1→0、2→1）；④**设备生命周期两分支都跑**（不假设环境）：本机有真设备 → `start=0`/`is_started=1`/二次 start=-1/`played_bytes` 真的推进（实测 35280 字节）/pause=0/二次 pause=-1；无设备（CI/headless）→ start=-1 且状态恒 0；⑤**NULL 参数防御全档**（该给失败档给失败档、不该崩的不崩）。探针另**直读 `QueryPerformanceFrequency` 报出 10000000 Hz**，证明走的是 QPC 高精度分支而非粗粒度回退。编法见探针头注释（`-I <moon>/include` 供 `moonbit.h`；补 `ole32.lib uuid.lib` 供 miniaudio 的 WASAPI 后端；`#pragma warning(disable:4244)` 只压 miniaudio 单头内部那一处赋值窄化，不压自家告警——探针本体 /W4 零告警）。
- **一手实测补记**：`miniaudio.h`（4.2MB 单头）**在 MSVC 下能编**——除其自身第 80532 行一处 `ma_uint64 → ma_uint32`（C4244）外无告警。这说明音频后端在 Windows 上是有落地路径的，缺的只是时钟这一处。
- **一条必须说清的边界**：改后 `audio_stub.c` 在 Windows 上**编得过、跑得起来**（探针即为证），但 `moon test ./modules/gui-media/media` **仍跑不起来**——测试可执行文件会把 `ffmpeg_stub.c` 一并链进来，而它要 `libavformat/avformat.h`（`ffmpeg-mbt` 那条线在非 Linux 上未接）。所以本批的 Windows 收益是**音频后端可编译可运行**，不是「媒体包能在 Windows 上用了」。Linux 分支代码逐字节未动，行为不变（本机跑不了 Linux，此为代码级判断而非实测）。
- **本批未做且不假装完成**：`ffmpeg-mbt` 的 Windows/macOS 后端（要接系统解码器或自带 DLL，是另一条独立的线）；媒体包在非 Linux 上因此仍不能整体构建与整体测试；macOS 分支（`mach_absolute_time`）无法在本机回证，只做了代码级正确性论证；真机听得见的声音与 seek 手感仍归 `测试文档/测试用例.md`。
- **顺带一条实测结论（免得后人「修」错地方）**：媒体 prebuild 的「非 Linux → 空 link_configs」是**对的**，不要往里加 `ole32.lib`/`uuid.lib`，也不要加 macOS 的 framework。①**Windows**：把 `audio_stub.c`（`#include` 了 miniaudio）拿去做实验——**不加任何额外库**直接链接即可通过（实测 `/Fe:probe_nolibs.exe` 零库链接成功且运行照样过 48 条断言），因为 miniaudio 默认走**运行期 `LoadLibrary`**（`MA_NO_RUNTIME_LINKING` 未定义），不产生链接期符号（此前那批探针带 `ole32.lib uuid.lib` 能过，是它们**不必要**而非必要）。②**macOS**：miniaudio 自述「the macOS build should compile cleanly without the need to download any dependencies nor link to any libraries or frameworks」——默认同为运行期框架链接（只有显式 `-DMA_NO_RUNTIME_LINKING` 才要求 `-framework CoreFoundation -framework CoreAudio -framework AudioToolbox`，且该宏的自动置位出现在 **DOS** 分支、不在 Apple 分支），命令行只需 `-lpthread -lm`，而这两者在 macOS 上由 libSystem 默认带上。所以三平台里**只有 Linux 需要显式系统库**（`-lpthread -ldl -lm -lstdc++ -latomic`）。

### 示例迁移首批：showcase 骨架 + 基础/反馈两页（G7，2026-10-12）

- **本批范围**：`examples/showcase` 从旧链路（`@yue` 根包 + `@declarative` + `@components`）改到新栈（`core` 的 `Node` 层 + `ui` + `theme`），先落**骨架 + 基础组件页 + 反馈组件页**。旧链路其余页（图标库/表单/事件与布局/导航/数据展示/图表/代码与文档/Store 对照/系统集成/窗口/浏览器/画布与富文本）**已从工作区删除**（`git rm`，源码在 `91204ca` 之前的历史里可随时取回），按「先基础、后重控件」逐批迁入——浏览器页含 WebKit 重控件、图标墙页要整墙建图标控件，都不适合先动。
- **四处机械差（旧链路 → 本栈，写在这里免得每页重踩）**：
  ① **`style=[...]` 不存在**。新栈组件只接显式参数（`padding`/`row_gap`/`width`…），间距是**布局容器的属性**而不是控件自己的；旧代码里成片的 `style=[("marginTop", 8.0)]` 一律删，改由父容器 `row_gap` 表达。
  ② **显隐与惰性挂载换层**：`View::set_visible` → `Widget::set_visible`（内部落 `display:none` 的 yoga 安全路径），`Node::mount_into(View)` → `Node::mount_into(Widget)`；`Node.mount` 的闭包签名也从「返回 View」变成「返回 Widget」，语义不变。
  ③ **「撑满剩余高度」不能写在控件上**：旧链路写 `style=[("flexgrow", 1.0)]`；新栈滚动容器（`scroll_v`）**不接** `grow` 参数，要在 `handle` 回调里对**视口控件**置 `node.set_flex_grow(1.0)`（`handle` 拿到的就是视口本身）。
  ④ **导航页要自己写**：旧链路 `nav_page` 本就是示例本地件（`examples/showcase/ui/section.mbt`），本栈同样没有对应物，照原机理重写成 `shared/section.mbt` 的 `nav_page`——`set_visible` 切显隐、**首次选中才 `mount_into`**（15 页全量挂载的启动开销不可行，这条机制必须保留）。
- **坑一：本地共享层不能叫 `ui/`**。旧链路里组件库叫 `@components`、示例自己的共享层叫 `@ui`，所以不冲；新栈组件库**就是** `ui`，两个包都派生成 `@ui` 直接歧义。改法：目录 `examples/showcase/ui/` → `examples/showcase/shared/`（包名派生成 `@shared`），顺带把 `@ui.App`/`@ui.page`/`@ui.section` 的调用点一并改准。**不要靠 `moon.pkg` 里给组件库另起别名绕过**——那样示例读起来会长期名实不符。
- **坑二：`popover_t` 的宽高是命名参数**。旧链路 `popover_t(trigger, content, 180.0, 60.0)` 位置传参；新栈签名是 `popover_t(trigger, content, width?, height?, handle?)`，位置传两个 `Double` 直接编译报 **4080**（`which requires 2 positional arguments, but is given 4`）。凡新栈签名多出可选参数，都要先确认它是命名参数——照旧调用点抄最容易踩这一类。
- **坑三：旧链路的 `@yue.VERSION` 不可用**。它在**主包**（旧链路根包，正是全仓 287 个红点的所在地），示例 import 它会把整个红包拖进依赖闭包。示例本地留一份 `SHOWCASE_VERSION` 常量，并注明权威值仍是 `moon.mod` + `yue/version.mbt`（后者的构建期一致性校验由 `scripts/prebuild.py` 负责）。
- **两条组件层收并（迁移时按新形状写，别找旧函数）**：`alert_closeable` 已并入 `alert(closable=true, on_close=)`；`result` 只吃 `(标题, 副标题, 语义类型)`，**不再**吃操作区数组——操作区由调用方在旁边摆（「组件只给形状、内容是调用方的」是本栈组件层的通用取向）。
- **一条顺带的接口澄清**：`toast_layer` 在本栈**只返回推送函数**，不再返回「层节点 + 推送函数」——提示带子开在**浮层图层**上（第一条推送才开、撤完就收），所以页面里不必再常驻一棵空树，提示也永远压在对话框与其它浮层之上。迁移时旧代码里那个 `@components.toast_layer()` 解出来的 `toast_node` 要**整条删掉**，别往树里挂。
- **验证**：`moon check ./examples/showcase ./examples/showcase/shared ./examples/showcase/pages --deny-warn` **零警告**；全仓 `moon check` 红点 **287/68 未变**（删掉的 14 个旧页本就在红点里）；真机冒烟 `exit 0`，控制台 `SHOWCASE-READY title=组件库演示板 pages=2 follow=1` 与 `SHOWCASE-DONE page=基础组件`，窗口标题正确、响应正常、`CloseMainWindow` 干净退出。退出时那条 `libpng warning: iCCP: cHRM chunk does not match sRGB` 是**既有**的（`examples/native-app` 同样打），与本批无关。
- **本批未做且不假装完成**：其余 13 页；菜单栏 / 托盘 / 单实例的接线（两个 `dialog_t` 已挂窗口根并可由反馈页打开，菜单栏、托盘、单实例按「各自随系统集成页/窗口页进来」处理，`examples/native-app` 已有对照演示）；真机观感（侧栏悬停、切段后滚动位置保留、跟随/手动主题切换的手感）归 `测试文档/测试用例.md`。

### 声明式层与自绘组件

- mouse 回调内禁止 `set_background_color`:运行期 CSS 改写会吞掉紧随的首次 press(「点两次才生效」)。交互态(hover / 按下)一律 on_draw 表达;set_background_color 只用于挂载期与主题订阅回调。
- flex 容器的挂载序同时是排列序与 z 序:夹层件(把手 / 分隔线)必须严格按排列位置挂入,且视觉常显——用户靠「看」找它,不靠 hover。
- **markdown_view 样式区间计量与 mdast 实测语义(MD2,2026-10)**:旧自写解析器(md_parse_inline / md_parse_blocks)已删,`yue/markdown.mbt` 改吃 mizchi/markdown(mdast)。①**富文本区间端点必须按渲染文本逐段累计 UTF-16 code unit(`md_utf16_len`),不能按码点数累计,也不能直接用 mdast Span 定位**——MoonBit `for ch in str` 按码点迭代而 `str.length()` 是 UTF-16 code unit 数(实测 "a👍b" 迭代 3 次、length 4),AttributedText 区间是 UTF-16 语义,emoji(非 BMP,1 码点 = 2 code unit)之后的样式按码点累计会整体前移;Span 定位则根本不可行:渲染文本 ≠ 源文(标记剥离、软换行空格化、链接地址丢弃),区间只能对渲染后文本计量。展平用显式栈携带样式集递归展平行内嵌套树(`md_flatten_inline`),相邻同样式段合并减区间数;渲染与测试共用同一计量 `md_span_ranges`(wbtest 断言 emoji 后粗体区间为 [4,6) 而非码点错位的 [3,5))。②mizchi/markdown 0.8.3 解析语义三则:`FencedCode.code` 尾带 `\n`(切行须丢末尾空行);`parse_code_block_info` 只认 `lang:file {meta}` 格式,**不认空格分隔 info 串**("rust title=x" 整串进 lang),语言须自取首词;段落间空白行会产出 `BlankLines` 块,AST 遍历不能按「块下标=文档序直觉」取块(测试曾因此踩 children[2] 实为空行块)。渲染面决策:HtmlBlock / 脚注默认不渲染,表格行式降级(单元格两空格分隔 + 表头加粗),任务列表吃 `ListItem.checked`(☑/☐),Blockquote 子块整体递归进竖条,有序列表带 `start`。验证:`moon check` 零警告 + `moon test` 595 全绿(19 条新 wbtest 覆盖换算 / 展平 / 区间 / info / 切行,及 CommonMark 偏差五项前后对比:setext 标题 / ~~~ 围栏 / info 串 / 缩进代码块 / 嵌套列表)。
- **markdown_view GFM 渲染面补齐(MD3,2026-10)**:①**删除线不上原生属性,MoonBit 层自绘**——上游 AttributedText 仅有 SetFontFor / SetColorFor(vendor libyue `attributed_text.h`,GTK Pango 底层有删除线但封装未暴露,shim 同样无入口),走 fork 补丁需重建三平台预构建库不在本批边界;`md_rich_label` 由 Label 改为挂载时自绘(themed_container + draw_attributed_text),**逐段用同字体独立测宽(get_bounds_for)得区间像素坐标表**,删除线段按坐标补画横线(行高中线,前景色),**链接命中与悬浮光标同用此坐标表**——跨层契约即「富文本行的区间语义是 UTF-16 端点 + 像素 x 区间并存:样式区间给 AttributedText,命中区间给鼠标事件」;单行(wrap=false)场景逐段测宽累计与整体拼排在亚像素级一致,点击命中天然容忍小偏差(多行 wrap 下该坐标表失效,本组件富文本行不换行故不涉及,若未来引入 wrap 须改为逐行布局)。②**链接点击**:MDSpan 携 url(Link 直接取、RefLink/RefImage 查 ParseResult.definitions 按 label 精确匹配,查不到降级为无地址的链接样式),on_mouse_down 的 view_x 落在 [xs, xs+ws) 即 open_url(复用系统能力,Linux 走 xdg-open);on_mouse_move 换手型光标,add_tooltip_for_rect 按 url 区间挂地址提示(挂载时一次性注册,主题切换不改几何无需重挂)。③**脚注两遍法**:预扫描正文(嵌套列表 / 引用 / 表格单元格 / 定义列表全递归)按出现顺序编号,FootnoteDefinition 自身跳过(定义内引用不进编号,防文末内容污染顺序);FootnoteReference 展平为上标 "[n]"(区间小四号字体,AttributedText 行内混排字号 Pango / CoreText / DirectWrite 均支持),markdown_view 主内容后分隔线 + 只渲染被引用的定义(未被引用不渲染,符合 GFM 语义)。④**图片**:块级「段落恰为单图」才显示(行内混排图降级 alt——富文本行不支持行内嵌图),Image::new_from_file 吃本地路径 / file:// 前缀(剥前缀),is_empty 即降级 alt;无网络图加载能力,网络 url 一律 alt 降级;等比缩放宽度上限 560(与 markdown_view 默认宽一致,外层更窄时溢出,同现状单行文本溢出行为)。⑤**表格等分网格**:格子宽用百分比字符串通道("33.33%",实测可用,showcase events 页 width "50%" 先例),列对齐经格子容器 alignItems(center 有先例;flex-end 未实测,值不被识别时 yoga 忽略退左对齐,无崩溃面),单元格富文本复用 md_rich_label;不与 table_t 混用——table_t 是 Store 驱动的数据面板(列宽固定 / 纯文本单元格),文档流表格列数不定、单元格富文本,自绘网格更贴。⑥任务列表 checkbox_t 空 title(固有宽 30 固定宽覆盖)+ 内容并排,勾选态即 ListItem.checked,点击切换纯视觉(文档源不变)。⑦showcase 演示文本与复制串同源:`demo_md_lines()` 单一来源,渲染吃 join("\n"),复制串逐行派生 MoonBit 字面量(反斜杠 / 双引号转义),复制所得与页面所见一致。验证:`moon check` 零警告 + `moon test` 600 全绿(markdown_wbtest 24 条,新增删除线标志 / 链接携址 / 引用式链接取定义 / 无定义退化字面文本 / 脚注编号与上标 / 块级忽略定义 / 图片路径换算 / 表格单元格与列对齐映射断言);真机视觉项(删除线横线位置 / 链接点击与悬浮 / 表格对齐与网格 / 图片显示 / 任务列表勾选 / 脚注上标与文末)由用户按 showcase「代码与文档」页 Markdown 段验证。
- **订阅必须可退订,否则重建式组件的死订阅无界累积(CORE2)**:Store/Signal 订阅闭包由信号内核持有、主题订阅由 theme_box.subs 持有,都没有退订入口——任何「重建行 / 重挂子树」的组件每次重建都漏下一整代死订阅:transfer 移动 N 次漏 N 套;table_t 每次 rows Store set 漏「行容器 + 每单元格 themed_container + bind_fg」一整套(千行表格一次刷新即上千条);snackbar 每次 push 漏两条;bind_node 每次重挂漏旧子树里 bind_label 的 Store 订阅。死订阅内存占用不大,但每次 set / theme_apply 都会对已销毁视图空跑(set_color / schedule_paint 打到已移除控件),且闭包捕获的视图子树永不回收。修复分内核与用法两侧:①订阅带 id——`Signal::subscribe` 返回句柄、`Signal::remove(id)`;Store 侧 `subscribe_id(f)` 取句柄、`remove(句柄)`(`Store::subscribe` 保持 Unit 不变:MoonBit 非 Unit 值不能隐式丢弃,改它的返回类型要动全仓上百个调用点)。②主题订阅同款:`on_theme_change` 返回句柄、`off_theme_change(句柄)`。③深层 / 成片订阅用**订阅回收袋** `sub_bag_begin() / sub_bag_end() / sub_bag_discard(闭包表)`:重建前开袋,重建期间注册的全部订阅(Store + 主题,含任意深度子树里的 themed_container / bind_fg / bind_label)把退订闭包压进袋,旧代整袋退订后再重建——transfer 的 render_all、table_t 的 rebuild、bind_node 的 rebuild、snackbar 的撤下定时器都走这条;袋是栈(嵌套安全),与 signals.mbt 既有 sig_collector 的「收集期全局上下文」同模式。验证:moon check 零警告 + moon test 657 全绿(新增 store 退订与幂等、Signal 句柄退订、回收袋三代与嵌套、主题 off 与回收袋、空栈收袋、组件重建走主题回收袋、carousel_stop 共 8 条)。
- **挂载即常驻的定时器要有回收通道,两条定时器 API 契约不同(CORE2)**:组件挂载时起的定时器没有「视图已移除」通知,不回收就继续对已销毁子树空转。libyue 侧两种定时器契约不同:`set_timeout` 返回 id、可 `clear_timeout(id)` 立即取消(自排链式轮播走这条);`set_timer` 是周期回调、**无取消 id,只能让回调返回 false 停**(shim yue_mbt.cpp 的 SetTimer 不回传 id)。因此 carousel_t 新增 `rotation? : CarouselHandle` 句柄与 `carousel_stop(handle)`(停自动轮播并取消已排下的那次超时,手动箭头 / 指示点不受影响);video_view_t 的帧推进定时器走文档契约——`vid_stop(handle)` 置 running=false,下一拍回调返 false 自停,**卸载前必须调用**(至多多转一拍)。两处的「卸载前必须 stop」都写进使用文档(components-ui / system-capabilities,中英同步)。

### 自绘画布与图表渲染

- 8 位 hex 颜色的 alpha 在**前**(`#AARRGGBB`,libyue `ParseHexColor` 源码级约定,与 CSS 的 `#RRGGBBAA` 相反;`yue/color.mbt` 的 `parse_hex` 亦然)。拼在尾部不会报错也不会改透明度——两位 hex 落到**蓝分量**,表现为颜色漂移。实例一:悬浮滚动条渐隐把 alpha 串从 "d9" 改 "73",实际蓝分量 0xd9→0x73、红绿不动,渐隐中的 thumb 变黄。实例二:图表面积填充 `color + "26"`,主题色 `#009688` 拼成 `#00968826` 按 AARRGGBB 解析 = alpha 0x00(全透明)+ RGB(150,136,38)——**面积填充从未显示过**。统一走 `with_alpha(hex, aa)`(拼头部)修复;凡 set_fill_color/set_stroke_color 需要透明度一律用它,禁手拼后缀。
- 离屏 `Canvas::new + get_painter` 在未 `initialize()` 时可做全部几何绘制(fill / stroke / arc / clip 均正常,无 DISPLAY 的 CI 也能跑绘制基准);但文本路径(`draw_text` / `AttributedText::get_bounds_for`)直接段错误——GTK 文本栈要 initialize 起过才在。测试基准因此分两级:无显示跑「纯函数管线 + 几何调用镜像」,有 DISPLAY 才 `initialize` 后跑真实全帧(含文本标注),两级数值都记入 `charts_wbtest.mbt` 的输出。
- painter 默认描边色下 `stroke()` 是空操作(不画任何东西):基准里忘记 `set_stroke_color` 会让描边成本显示为 ~0,虚假通过。所有描边基准必须显式设色后再测。
- 软件光栅化(GTK/X11 无 GPU 路径)下路径描边每段约 1.8µs,近垂直段(斜率 >30)约 13µs/段;`fill_rect` 每约 1µs(轴对齐快路径),`draw_text` 每次约 0.11ms,`line_to` 本身约 12ns(纯建路径)。折线图 1000 点 × 4 序列若全走路径描边,单帧 45~60ms,远超 5ms 验收线。
- 修复(图表族统一策略,见 `yue/charts.mbt`):密集态(点数 > 绘制区像素列数)按列抽稀(min/max 保极值)后改矩形路径——面积模式每列一个填到锚线的矩形(填充顶边即折线),折线模式每列画 min..max 竖条;稀疏态(点数 <= 列数)才走真实折线 + 多边形面积。绘制成本与窗口大小脱钩,只随绘制区宽度增长。
- libyue 的 Arc 无法表达逆时针弧:GTK 侧 `PainterGtk::Arc` 就是 `cairo_arc`,而 cairo 会把 `ea < sa` 规范化成「加 2π 的顺时针长弧」;Win 侧公开 API 也写死顺时针(底层 ArcPixel 有 anticlockwise 形参但没有暴露)。shim 里「ccw 用负角跨度表达」的换算因此两层都不生效——圆环内弧硬用 ccw 会把内孔包进长弧,填充出实心饼(真机截图实测:环形图/仪表盘中心不镂空,"总计"/百分比压在实心面上)。修复:内弧回程改折线近似(整圆 32 段,弦误差 <0.4px,三平台一致);纯描边场景(图标弧)直接交换起止角等价。fork 层若要把 `PainterGtk::Arc` 改成 `cairo_arc_negative` 才是根治,需走 vendor-* 出包,暂未做。
- 图表验收基准(release,Ubuntu 24.04 XFCE X11,离屏 Canvas + initialize,真实全帧含文本):折线 1000 点 × 4 序列(陡锯齿对抗数据)3.08ms / 平滑数据 1.81ms;柱状 200 类目 0.38ms;环形 50 扇区 0.70ms;仪表盘 0.15ms;散点 10000 点 3.03ms。纯函数管线(值域/刻度/抽稀/坐标换算)折线 0.028ms。推点长跑:4800 次(10 分钟 @2Hz × 4 序列)共 2.89ms,窗口长度恒定 1000 不增长——活数据 4 × 1000 × 8B = 32KB 有界,内存增量来自 GC 回收的换窗垃圾,连续推点不积累。
- 折线面积锚点:0 在值域内取零线,全正值取绘制区底,全负值取绘制区顶(跨零时一列上下两段矩形)。
- `Painter::DrawText`(画布 draw_text)默认 `wrap=true`:定高行 / 窄盒里的长文本被平台排版换行,溢出行界。实测三类症状:进程表命令行(动辄上百字符)换行穿透行高压到下一行;图表 y 轴大数值直出("21414.7")竖排成多行互相叠压;折线多序列末端值标签接近时叠字。修复:shim 增 `yue_mbt_painter_draw_text_ex` 透出 TextAttributes 的 wrap/ellipsis(纯 ABI 翻译),MoonBit 侧 draw_text 加可选参数,表格单元格统一 `wrap=false + ellipsis=true` 单行省略(截断由平台排版完成,免逐格测宽);`fmt_axis` 在 |v| ≥ 1e4 起按 k/M/G 换挡(一位小数去尾零),标签保持 5 字符内不触发换行;末端标签改为收集后按 y 排位(最小间距 14px,越界整体压回)再绘制。
- 图表 / 虚拟表格自适应(fill 开关):不设固定宽度,靠列容器默认 stretch 横向铺满,随窗口伸缩。表格 fill 模式下每次绘制按实际宽度重排列几何:固定列保留拖宽结果、弹性列分摊剩余宽度(拖宽两列此消彼长守恒,与弹性列重排不冲突);行内自适应固定坐标(w − 偏移)的自绘行容器本就跟随。
- 表格表头自绘装饰必须画在表头容器(head)的 `on_draw`,不能画在单元格容器(head_cell)上:GTK 上 libyue Painter 的路径填充(`begin_path` + `fill`)在单个表头单元格(约一列宽 × 32px、内有 Label 子 widget)里完全不渲染——代码跑了、无报错、就是不出像素;同一段代码画在整行表头容器或表格大画布容器上正常。`fill_rect` 与路径描边(`stroke`)在所有尺寸容器都正常,症状极易误判成「坐标算错」。复现方式:同窗口并排画 fill_rect / 路径填充 / 路径描边三块即可定位。修复:table_t / table_v_t 的排序箭头、列边界线、悬停高亮统一收敛到 head 容器单一 `on_draw`,head_cell 只留交互。根因待 fork 层深究(疑似与小容器 GTK draw 区域 / 裁剪有关)。
- 表头列边界的鼠标事件落点:列边界竖线右侧像素归属下一单元格,对准可见边界按下会落进下一格左缘(触发排序而非拖动)。修复:拖动热区认双向边界(右缘 4px → 边界 (j, j+1),左缘 4px → 边界 (j-1, j)),末列右缘不设把手。
- Painter 无 dash API:markLine 等虚线一律自绘段模拟(ci_dash_line,6px 实 4px 空),三平台观感一致,不依赖平台 dash 支持。
- 图表 hover 浮层自绘而不复用基础件(选型依据):Popover 是点击触发、相对视图定位、独立裸窗口,hover 跟随会闪;原生 tooltip 是单行系统样式,不满足多行 + 主题化。故浮层画在图表容器自身 on_draw 内(图表之后绘制即在最上层,无 z-order 问题),位置经 ci_tooltip_pos 钳制在画布内不出界;mouse 可达性经 bar_chart_t/donut_chart_t 同款路径验证。
- 地图与飞线的投影方案(geo_map_t,选型与实现口径):**等距圆柱投影(equirectangular)**——lon [-180,180] 线性映射到绘制区横向、lat [-90,90] 线性映射到纵向(上北下南),输入先钳制经纬度再算,输出不越过绘制区(geo_project)。没有选墨卡托 / Lambert:墨卡托的 85° 截断与纬度间距放大对中国纬度带不利、纬度外推会发散,Lambert 的双标准纬线又要为每个数据集挑参数,等距圆柱的全部几何都能被单测定点断言(北美 / 中国 / 全球三种典型数据集均可验证)。投影矩形 = 区域环与飞线端点的**合并包围盒**按自身长宽比居中缩进(geo_fit_rect,保形不变形),不用固定矩形:局部地图才不缩成一角,飞线两端落区域外也完整可见;退化轴(同经 / 同纬)给 1° 最小跨度,w/h 非正退化为 0 尺寸。质心用 shoelace 有向面积(|A| 为轴)加面积加权环内点平均(geo_ring_centroid / geo_region_centroid):环可能是 MultiPolygon 拼接的多环,取有向面积绝对值最大的环为主环,凹形(如山东半岛 / 辽宁)比 bbox 中心或首点都稳;angle-free 实现避免椭圆积分近似在细长环上跑偏。区域填充色用主题主色按**区域名 FNV-1a 哈希**做 ±0.06 明度微调(geo_name_hash,哈希取模 13 / 12 归一),同名同色、换主题或缩放不变——不用表格序号:序号随数据顺序变,深浅对比会闪。飞线弧线在**投影后的画布坐标**上算控制点(geo_flight_ctrl 取起终中点 + 方向法向偏移 bend × 起终距),弧的视觉凸量才均匀;直接在经纬度上算控制点,高纬弧会因经度权重而畸变(1° 经度在高纬比低纬短)。贝塞尔采样 geo_flight_points 默认 48 段,首点 from 末点 to(含端点保证箭头方向正确)。地图数据不内置:geojson_parse 复用 vscode_history 的手写 JSON 解析器(vsc_json,纯 MoonBit),只收 FeatureCollection / Feature / 裸 Polygon / MultiPolygon,几何不合规(缺 coordinates、环点数 < 3、坐标含非数值)给 GeoError::BadGeometry;geometry 为 null 的 Feature 合法跳过。

### 布局几何(Yoga flexbox)

- 布局断言 16/16 通过(±1px);叠加规律:内容区 = 容器 − 2×padding;gap 不与 margin 叠加;百分比基准为父内容区宽。
- 复合控件(Tab / Scroll / Group)在 yoga 树里是无 measure 的叶节点,外框尺寸必须显式给出(如 `flex:1`),否则塌缩(Tab 构造时固化最小尺寸,页区域归零)。
- tabs_t 曾把 outer 宽度写死 360px、内容页无 flex:放进页里的 Scroll / Table 因此塌缩归零(实测 sysmonitor 概览页整个空白,只有页签头)。修复:outer 去掉固定宽改 `flex:1`(列容器默认 stretch 拿宽度,父有确定高度时填充),内容页同样 `flex:1`。父容器无确定高度时 flex 不增长,内嵌场景(showcase 的分段演示)布局不变。
- 运行时改样式(set_style)后调 `update_layout`,GTK 上对「根容器」调用子树完全不刷新(yoga 状态已改,bounds 纹丝不动),对单个节点调用也只重排「该节点及其父下的兄弟」——跨子树(如表格 body 的行)不受影响。探针同构四组对照实证(挂载后立即 / 500ms 后、update 根 / 叶子、width / flexbasis):唯一可靠形态是「被改样式的容器逐个调用」。table_t 拖列宽曾因对根调用而「手柄在动(bounds 走的 col_w)、列宽纹丝不动(样式没生效)」;splitter 恰好只有一个包装容器要改,对 outer 调用看似通用,实则同坑未爆。修复:apply_col_widths 对表头两个单元格 + 每行两个单元格逐个调用。
- GUI 自动化:键盘驱动(Tab 聚焦 + Space 激活)首选;`xdotool key --window` 走 XSendEvent 会被 GTK 丢弃,必须 XTEST(不带 --window);坐标点击受 WM 装饰偏移影响不可靠。
- **Linux/macOS tabs_t 切页塌陷已根治(native ≥ v0.15.6-mbt.19)**:病灶在 yoga 本体与 display:none 的交互,三层机制——①`flex` 简写(flex:1)在这版 yoga 解析为 grow=1 且派生 basis=0(`resolveFlexBasisPtr`);②切页隐藏走 display:none,`YGZeroOutLayoutRecursively` 把布局整体 `= {}` 清零,`computedFlexBasis` 一并打回 undefined;③重显后的 flex basis 计算(Yoga.cpp `YGNodeComputeFlexBasisForChild`)只要解析值有定义且 `computedFlexBasis` 为 undefined 就把派生 basis=0 写回,**之后每轮都命中「已计算」分支永不再走内容测量**——auto 高父链(scroll 内容列)无剩余空间可分,页容器永久 0 高(探针实测新显页 1px、outer 65→36 塌成 head 高)。从未隐藏的页不塌是「内容测量曾进过 basis 缓存」的巧合而非稳定保证。修复(fork 补丁 lb091188/yue 93078300,display 清零时置 `zeroedByDisplayNone` 标记、basis 计算对标记节点该轮改走内容测量,显式 flexBasis 样式行为不变)只治简写路径;**显式 flexbasis 0 的塌陷是固有语义**(每轮按解析值重写 0,内容测量分支永不执行),tabs_t 因此平台分化——Windows 保显式 basis 0(治其显隐中间态压缩),Linux/macOS 回纯 flex 简写。回归工具:`moon run examples/probe-collapse`(四轮切换采样,简写页应恒稳 22 高)。坑位:CI 的 clang 命令行带 `-Wshadow -Werror`(本机 `-Wall -Wextra` 组合不含 shadow 补丁代码本机全绿 CI 全红,首查 shadow);fork 补丁落在 `patches/`(prebuilt 工作流 Bootstrap 后 `git -C third_party/yoga apply`),yoga 是子模块不进 fork 提交。
- **mbt.19 补丁的边界:showcase 复塌与 outer 简写禁用(次日真机复验闭环)**:mbt.19 上线后真机复验 showcase 仍塌——补丁只治「被 display:none 清零后重显的节点自身」,治不了「从未隐藏、被兄弟显隐 dirty 连坐重算的 flex 简写祖先」:tabs_t 的 outer 自身也写 flex:1 简写,切页把它 dirty 后,auto 高父(scroll 内容列)的内容测量轮里,outer 的派生 basis 0 按可用尺寸解析成 0(非 undefined),被父当成 0 高内容贡献——outer 塌成 margin 高、子树全 0(液位计实测 1px);初始一切正常只因首轮 natural 测量 owner 尺寸为 nan,basis 0 解析回 undefined 走内容测量。纯 yoga 最小复现(先 availableHeight=undefined 一轮,再固定 300 轮+切换)完整复刻两形态,Yoga.cpp 加打印追踪出三级塌链:`outer mainOwnerSize 300→10→0`(10 即 margin 高)。修复不动 native:tabs_t 的 outer 改 **flexgrow+flexshrink 单写**——grow/shrink 不参与内容测量,basis 走 auto 语义(CSS flex:1 1 auto):auto 父下按内容高、确定高父下照常填充压缩,与简写唯一差别即 basis auto。**规则:凡「确定高父填满、auto 父按内容」两栖的容器禁用 flex 简写,一律 grow/shrink 单写;简写仅适合父恒确定高、或节点自身就是显隐切换对象(mbt.19 补丁保护)的场景。**回归工具追加 `moon run examples/probe-collapse2`(showcase 主结构全复刻:sidebar+兄弟 page 互切+scroll 链+双形态 tabs,液位计组应恒 18)。探针侧栏摆设勿用 button_t:窗口销毁期 GTK focus-out 回调会踩已析构资源偶发段错误(gdb 栈 `OnFocusOut → Store<Responder>::get`),与塌陷无关,探针改 label 规避,button_t 焦点链生命周期已修(yue_mbt_quit 统一断信号,见「GTK 相关」退出段错误条目)。
- **超宽容器 flexWrap 不生效:Yoga 的 flexShrink 默认是 0(CSS 是 1)**。segmented 19 段一行 2400px 被窗口截断,内层 hbox 写了 flexWrap 仍不断行——换行的前提是容器宽度被约束,而该 hbox 作为外层子项 shrink 默认 0,拿到内容全宽,约束传不进去 wrap 永不触发。修复:内层显式 `flexShrink 1` + `flexWrap wrap` + `rowGap`(换行行距);段少页面不触发换行外观不变。通用规则:期望「超宽折行」的容器,若它同时是别人的子项,shrink 必须显式给。
- **yoga Web 语义对齐的最终定案:不开 useWebDefaults,shrink 默认维持 0、需要收缩显式给 1**。yoga 四处内核默认偏离 CSS(flexShrink 0 / flexBasis 隐式 0 / flexDirection column / alignContent flex-start),官方开关 `YGConfigSetUseWebDefaults` 可一次对齐(fork 接入点在 nu `State::State()` 全局 config 处一行),但它是**全局 config:原生控件内部的 yoga 布局同样翻面**,原生组件无封装无从逐个豁免——弃用。随后试过「声明式层默认化」(container_node 统一默认 flexshrink 1,只影响声明式 hbox/vbox),真机实测仍回归面过大:图标墙固定 50px 自绘画布被行挤压变形、一图多行错乱——声明式层内同样遍布「固定宽自绘控件 + 富余空间」布局,全局翻转的收益(超宽折行免显式)远小于代价(固定宽控件全要补锁)。**回退,最终定案:shrink 默认维持 yoga 原语义 0;需要收缩/折行的容器(segmented 等)显式给 1。**回归证据:probe-collapse 系液位计恒稳、showcase 基础/图标库/图表三页截图与改前一致、hello-themed/sysmonitor 冒烟存活。组件默认值抽查(control_height 32、字阶 12-18、语义色系)贴近 AntD/Element 与桌面 GUI 惯例,无需对齐动作。方法论沉淀:默认值翻转类变更,先在真实页面巡检一圈再定——showcase 本身就是最好的回归器。
- **惰性挂载 × flex 简写的新病理(tabs 初始 0 高,切换一轮才恢复)**:页/段改「首次选中才挂载」后,tabs_t 内容页的 Linux 分支(`flex 1.0` 简写)在新的挂载时序下暴雷——全量挂载时代首轮 natural 测量 owner=nan 走内容测量所以一直正常(派生 basis 0 的解析机理见「mbt.19 补丁的边界」条);惰性挂载让 tabs 在**父链布局稳定后**才挂入,子节点加入触发的首轮 basis 求值 owner 尺寸已定,简写派生的 basis 0 直接解析成 0 并进「已计算」缓存,而初始可见页从未隐藏、不落 mbt.19 的「display 清零重显」保护——初始页 0 高,切一轮页签(触发重显保护)才恢复。修复:Linux 分支内容页改 grow/shrink 单写(basis 走 auto 内容测量,与 outer 同款两栖语义),Windows 显式 basis 0 分支保留。教训:**mbt.19 的重显保护只覆盖「hidden→显示」路径,「布局稳定后新挂载即可见」是它的盲区;两栖容器禁 flex 简写的规则对「延迟挂载」场景同样成立**。回归:showcase 页签段初始即有高度、切换正常,probe-collapse2 液位计恒稳,sysmonitor(启动即挂载场景)概览完整。同族全库排查:yue 内 19 处 `flex 1.0` 简写里,column 主轴 + auto 高父链组合的 4 处(progress_line、divider 水平分支、slider 自适应宽分支、轮播面板)同样必塌,统一改 grow/shrink 单写;其余在 row 主轴(行宽确定)或启动挂载确定尺寸语境,不塌保留。验证:统计进度段首挂 25% 填充、分隔线 1px 横线、轮播面板高度均截图实证。测试方法学教训:xdotool 驱动验证时注意单实例合并(新实例会向首实例发唤醒后退出,截图打到旧代码窗口)与 X 窗口 id 复用,必须按「exe 路径过滤的 PID ↔ wmctrl 窗口」配对确认,且首次挂载类 bug 要在全新实例上验。


- **yoga-mbt 纯 MoonBit Flexbox 引擎首批(feature/yoga-mbt 分支,与内嵌 C++ Yoga 是两条线)**:为 MoonBit 化 libyue 预置布局层,独立子包(modules/yoga-mbt,零 FFI 无 prebuild)。定位差异先说清:本节此前「shrink 默认 0 / 不开 useWebDefaults」的定案管的是原生控件树里那颗 C++ Yoga,不可迁移;yoga-mbt 按用户要求只对齐 CSS Flexbox L1 单标准,默认值全 web 语义(row / shrink 1 / basis auto / align stretch / min:auto)。对照材料:W3C css-flexbox-1 §9 全文(w3.org/TR/css-flexbox-1,§9 算法在 li#algo-* 列表项里)+ Yoga 官方源码(github facebook/yoga,yoga/algorithm/CalculateLayout.cpp 与 FlexLine.cpp;raw.githubusercontent 直连超时,走 `git clone --depth 1 --filter=blob:none --sparse git@github.com:...` SSH 可达)。三点实质差异按规范取舍:①§9.7 冻结算法——规范是「目标尺寸从 flex base 起步、不弹性项(因子 0 / 被 min-max 截断)预冻结、循环按总违规正负选择性冻结(正冻结 min 违规、负冻结 max 违规、零全冻)」,Yoga 官方注释自认用两遍法偏离规范,本引擎按规范;②shrink 加权用内基准尺寸(base − 自身 padding/border,规范原文),Yoga 用 border-box 基准;③单行 + 容器交叉轴确定时行交叉尺寸直接取容器内交叉尺寸(§9.6),align-content 对单行无效——此前靠 align-content:stretch 补齐的实现会让非 stretch 的 align_content 在单行容器上错位。实测踩坑(纯 MoonBit 侧,moon 0.1.20260904 + moonc 0.10.x):续行运算符必须收在行尾(行首 `+`/`-` 报 unbound `~+`);无 `+=`/`-=` 复合赋值;裸 `0..n` 非法必须 `0..<n`;`1e15` 科学计数法字面量解析报错须写全 `1000000000000.0` 形态;`fold` 要求带标签 `fold(init=0.0, ...)`,`guard` 是保留字;泛型写 `fn[T] f(...)` 不是 `fn f[T]`;顶层常量用 `const NAME` 或小写 `let`;`pub priv struct` 的类型在外部不可见(pub fn 签名引用即报 4046「public definition cannot depend on private type」),字段私有需求实际只能 `pub struct`;mut 字段「从未赋值」按错误报(0015),经引用改内层字段不算外层字段突变;moon.pkg 新 DSL 不认 warn_list(报 Unexpected key),关包级 lint 要用旧 JSON 文件名 `moon.pkg.json` 写 `{"warn_list": "-6"}`(unused_constructor 对「构造器全给消费方」的枚举库是误报,此法显式关闭);测试断言是 `assert_eq(a, b)` 无 `!` 后缀,且只能在带错误类型的上下文用(test 块内)。验证:`moon check` 零警告 + `moon test -p NoahLiu/yoga-mbt/src` 19/19 全绿(预期值按规范手算;首版 5 条断言错在把 stretch 撑满与 min:auto 下限当 bug,浏览器同款行为,预期修正而非代码回退)。

- **yoga-mbt absolute 定位(YG2a)**:包含块取父容器 padding box(宽高 = border box − 两侧 border,含 padding),inset 与 margin 百分比相对包含块对应轴;尺寸规则:显式宽高 > 同轴两侧 inset 都设(撑出 = 包含块 − 两侧 inset − 两侧 margin,内容盒下限 0)> 内容测量;定位规则:该轴有 inset 用它(右侧取包含块 − right − margin − 尺寸),该轴双 auto 落静态位置——按父容器 justify-content(主轴)/align-items(交叉轴)摆放一个虚拟项(忽略兄弟,间距类 justify 取 0)。踩坑一条:内容测量得到的尺寸**不额外按可用空间截断**(可用空间只以 AtMost 形式传给 measure 函数,与 Yoga 同款),先做了 `min(avail)` 截断导致「auto 尺寸父容器 + 固定内容尺寸叶子」场景被压成 0(auto 父容器 padding box 为 0 时尤甚);验证:`moon check` 零警告 + 全仓 `moon test` 687/687(新增 7 条:脱流与 left/top 定位、同轴两侧 inset 撑尺寸、四向全 auto 静态位置居中、right/bottom 定位、不撑开容器内容尺寸、内嵌子树递归、百分比 inset 相对 padding box)。

- **yoga-mbt baseline 对齐(YG2b)+ 交叉轴 margin 定位缺陷**:API 取 `set_baseline(f : (可用宽, 可用高) -> Option[Double])`,返回值语义为**基线到内容盒顶部**(与 `set_measure` 对称,引擎叠加自身 padding/border);容器不设回调,基线由引擎按规范 §8.5 推出:首行有基线对齐项 → 取该行共同基线(升距最大值),否则取交叉轴起端最靠前的有基线 in-flow 项(嵌套容器逐层上抛)。行交叉尺寸按 §9.4 补齐前半:收集「inline 轴平行主轴 + align-self 为 baseline + 交叉轴两侧 margin 均非 auto + 有真实基线」的项,取 max(基线到外沿交叉起端) + max(基线到外沿交叉末端),与既有「最大外沿交叉尺寸」取大;定位按 §9.6「升距最大者贴行交叉起端」= maxAscent − margin 起端 − 基线。三条定案:①单行 + 容器交叉轴确定时行交叉尺寸仍直接取容器内交叉尺寸(§9.6 短路优先),基线只决定项的偏移不决定行高;②主轴为列时不做基线对齐(规范收集条件要求项的 inline 轴平行于主轴,列容器交叉轴是水平向),按起端摆放 = 浏览器行为;③**无基线的项排除在基线分组外并按 flex-start 定位**——规范只说「无基线则从 border box 合成」,未写明合成在哪条边(css-align-3 首基线合成于块起边,浏览器对替换元素/空块历史用底边,存在分歧),本引擎取「不合成」,与 Yoga 的 dimbound 分支一致,也让「无基线项」与改前「Baseline 当 FlexStart」行为完全兼容;想要浏览器那种「图片底边坐落基线上」的消费方,自行把基线回调返回自身高度即可。实测缺陷(实现本批时由新增断言打出,与 baseline 数学同源):**交叉轴 margin 从未参与子项定位**——`pos_cross` 只等于「行偏移 + 对齐偏移」,而 `free_c` 已按含 margin 的外沿算,于是 `margin_top: 30` 的项贴到行首(实测 `0 != 30`),`align-items: flex-end` + `margin_top: 20` 时 margin 被整体吞掉(实测 `130 != 150`);主轴方向无此问题(`pos_main` 累加了 `m.start`)。修复:定位改为「行偏移 + 对齐偏移 + margin 起端」(auto margin 解析值为 0,故 auto 分支不受影响)。另暴露一条**待修**缺陷:容器 auto 主轴尺寸按内容推算时 `content_main_sum` 只累加子项、漏加自身 padding/border,多行分支又把它写死 0(折行容器 auto 主轴尺寸会塌成 0),留作下一批(YG2b′,数值例与修复见该条),本批相应断言暂不合入。验证:`moon check` 零警告 + `moon test -p NoahLiu/yoga-mbt/src` 36/36 + 全仓 `moon test` 697/697(新增 10 条:交叉轴 margin 定位与拉伸、margin 与 flex-end、两项按基线对齐、基线决定行交叉尺寸(容器交叉轴不定)、stretch 项不参与基线分组、无基线项按 flex-start、margin-top 计入升距、多行时基线只在行内生效、嵌套容器基线上抛、column 容器不做基线对齐);对照材料:W3C css-flexbox-1 §9.4(algo-cross-line)/§9.6(algo-cross-align)/§8.5(Flex Container Baselines)原文。

- **yoga-mbt 容器 auto 尺寸漏算自身 padding/border + 多行主轴尺寸塌 0(YG2b′)**:YG2b 期间探针实测(父容器 `padding-top:10 / padding-left:10` + 100×50 子项,容器不给宽高)row 与 column 两种方向的 auto 尺寸都得到 100×50,浏览器为 110×60——根因在「自身尺寸」段用 `content_main_sum`(只累加子项 size_main + margin)与 `own_cross_content`(只累加行交叉尺寸)直接当容器的 border-box 尺寸,而宽高语义明确是 border-box,自身 padding/border 从没叠加;子项**定位**侧一直是对的(`layout_left = own_border.left + own_pad.left + x`),所以现象是「尺寸小一圈、子项位置正确」,容易被误判成测量函数报错。第二个洞在同一处:多行分支把 `content_main_sum` 写死 `0.0`,折行容器不给主轴尺寸时整条主轴塌成 0。修复:主轴按各行外沿(size_main + 两侧 margin + 该行 column/row gap)取最大值,交叉轴沿用各行交叉尺寸之和,两者统一再补 `pad_border_main / pad_border_cross`;`nlines == 1` 分支与旧值等价(auto 主轴容器不参与弹性解析,`size_main` 恒等于 `hyp_main`,故改用「按行取最大」不改变单行结果)。验证:`moon check` 零警告 + `moon test -p NoahLiu/yoga-mbt/src` 40/40 + 全仓 `moon test` 701/701(新增 4 条:行容器 auto 尺寸含 padding、列容器同款、含 border 的 47×23、折行容器「主轴取最宽行 + 交叉轴累加行高」= 90×50 且两行子项 top 10/30;并把 YG2b 撤下的嵌套容器 `b.height == 35` 断言合回)。

- **yoga-mbt aspect-ratio(YG2c)——比例语义定案为 border-box**:用户定的口径是「比例 = 边框盒宽 / 边框盒高」,与引擎既有的 width/height = border-box 一致,和 CSS 默认的 content-box 比例不同(README 已标注;换算处一律不做 padding 扣减)。四处接入点:①§9.2 flex base——项有比例 + 基准为 content + 交叉轴确定 → 主轴基准 = 交叉轴按比例换算(列容器则反过来除);②§4.5 自动最小尺寸——主轴 `min:auto` 取「内容尺寸」与「换算尺寸(transferred size suggestion)」的**较小者**,否则比例会被内容下限顶回去(实测例:内容宽 200 + 高 10 + 比例 2 → 应为 20,写成 `min:auto = 内容` 得 200);③§9.4 交叉轴假想尺寸——主轴已定(含 §9.7 弹性解析结果)→ 交叉轴 = 主轴按比例换算,再走 min/max 收顶;④容器自身尺寸——一轴确定(显式或由父级钦定)而另一轴 auto 时,按比例换算出的那一轴**当作确定尺寸**参与后续计算(即写进 `inner_main` / `inner_cross`),于是换行上限、弹性解析、行交叉尺寸与 stretch 全部按该尺寸走;不做这一步会出现「`width:320 + aspect-ratio:2` 的容器高按内容 50 塌着、子项也拉伸到 50」的错果。一条规范直译的行为要写清:`align-items: stretch`(本引擎默认)会覆盖交叉轴的比例换算结果——规范 §9.4 algo-stretch 的条件看的是「computed 交叉尺寸属性为 auto」,并有尾注「本步不影响项的主轴尺寸,即使它有首选比例」,所以比例项在 stretch 容器里按行交叉尺寸取高,要保持比例需给非 stretch 对齐或显式交叉尺寸(浏览器同款行为,已入单测)。绝对定位子项这一批**不做**比例换算(该路径仍只按显式尺寸 / 同轴两侧 inset / 内容定尺寸),记在 README 未实现清单。验证:`moon check` 零警告 + `moon test -p NoahLiu/yoga-mbt/src` 47/47 + 全仓 `moon test` 708/708(新增 7 条:宽推高、高推宽、列容器由高推宽、容器自身按比例定尺寸并让子项撑满、stretch 覆盖比例(含改 align_self 后恢复)、比例值给 min:auto 封顶、非正比例视同未设);对照材料:W3C css-flexbox-1 §9.2 / §4.5 / §9.4 与 css-sizing-4 的 preferred aspect ratio 定义。

- **yoga-mbt RTL(direction,YG2d)+ 翻转定位两处既有缺陷**:方向语义定为**按节点独立、不做 CSS 的 direction 继承**——引擎的 `layout_into` 只拿得到父给的可用尺寸、没有父链样式上下文,而 libyue 侧主题/控件自己知道该给哪个容器设 rtl,继承链交给上层封装。实现只动「解析与映射」层:两个派生标志 `rev_main = is_reverse(flex_direction) != (rtl && 主轴为行)`(行容器 direction 与 row-reverse 各翻一次,列容器主轴是块轴不受 direction 影响)与 `rev_cross = rtl && 主轴为列`(交叉轴即 inline 轴才翻);`axis_margin` 增 `cross_reverse` 参数决定交叉轴起端取 margin-left 还是 margin-right——**物理边始终是 margin-left/right,只是「起端/末端」的含义随方向换算**,auto margin 的分配跟随所属边(Yoga 同款语义)。行容器交叉轴是块轴,所以 baseline 分组、align-items 的垂直摆放与 rtl 完全无关;rtl 列容器折行时 `pos_cross` 含行偏移后整体翻转,首列自然落在右侧、次列在其左(单测实证)。本批由 RTL 的翻转参照打出两条既有缺陷:①**row-reverse / column-reverse 在容器 auto 主轴尺寸下算出负偏移**——翻转参照用 `inner_main_dim.unwrap_or(0.0)`,容器主轴靠内容推算时该项为 None,于是 100 宽的项落到 -100、第二项 -200(探针实测),修复为「容器内主轴确定尺寸优先,否则取内容推算的行主轴尺寸最大值(`line_main_max`,顺带从自身尺寸段上提到定位段之前)」;②**绝对定位四向全 auto 的静态位置恒按左/上落**——YG2a 的静态位置只按 justify/align 算偏移、没跟着主轴翻转,`column-reverse` 容器里应当贴底部却贴了顶部,修复为静态位置的起端随所属轴的翻转标志走(margin 也取所属起端的物理边)。验证:`moon check` 零警告 + `moon test -p NoahLiu/yoga-mbt/src` 60/60 + 全仓 `moon test` 721/721(新增 13 条:3 条 LTR 快照锁住翻转参照与静态位置的新行为 + 10 条 rtl:行容器右起端、rtl×row-reverse 回左起端、列容器交叉轴起端在右、起端取右边距、justify flex-end 落物理左端、margin 物理边参与主轴、margin auto 吸收、行/列容器的绝对定位静态位置靠右、rtl 列容器折行行序);改前 47 条 LTR 断言全部保持原值,即方向层未回归既有行为。对照材料:W3C css-flexbox-1 「主轴起端由 direction 与 flex-direction 共同决定」的定义(flex-direction 与 Writing Modes 的 inline/block 轴关系)+ css-position-3 的 static position 定义。

- **yoga-mbt 绝对定位子项吃 aspect-ratio(YG2e,YG2 标准面收尾)**:abspos 段的尺寸优先级原为「显式宽高 > 同轴两侧 inset 撑出 > 内容测量」,比例换算插在中间一步——先按老规则解出「已确定的一轴」(显式给出或由左右/上下两侧 inset 撑出),另一轴仍 auto 时按比例换算并以自身 padding/border 兜底,再走 min/max 收顶;两轴都 auto 时**仍按内容测量**(与 in-flow 项一致,比例不凭空造尺寸)。左右(上下)inset 全 auto 的落位沿用 YG2d 的方向翻转标志,不受本批影响。验证:`moon check` 零警告 + `moon test -p NoahLiu/yoga-mbt/src` 63/63 + 全仓 `moon test` 724/724(新增 3 条:由宽推高、由高推宽、两侧 inset 撑出宽后按比例推高)。

- **yoga-mbt 枚举跨包不可构造(E4036)+ 性能基线(YG3a 工程化首批)**:先报阻断级坑——本工具链(moon 0.1.20260920 / moonc 0.10.14)里 `pub enum` 只把**类型**与「匹配可读」开放给包外,**变体构造对外是只读的**:外部包写 `@lib.Green` 或 `@lib.Color::Red` 都报 `E4036 Cannot create values of the read-only type`;`pub(readonly) enum` 语法不被支持,变体上单独加 `pub` 报「No individual visibility for enum constructor」。正确形态是 **`pub(all) enum`**(依据:`moon check --explain` 输出的 E4036/E0006 官方解释 + 双包最小复现)。对 yoga-mbt 意味着:引擎的 `FlexDirection / AlignItems / AlignContent / JustifyContent / FlexWrap / PositionType / Display / Direction / Value` 九个枚举全是消费方要往 setter 里塞的值,原写法下**外部包一行样式都设不了**;这条在单测里永远不暴露(测试与实现同包),是新增 bench 这个**外部包**跑 `moon check` 时才炸出来的——YG4 集成前必踩。修复:九个枚举统一改 `pub(all) enum`,`Value` 已有的 `fixed/percent/auto/undefined` 辅助函数保留(消费方两种写法都通)。同批建立性能基线,工具 `modules/yoga-mbt/bench`(`moon run bench` / `moon run --release bench`;树 = 根 + 20 组 ×（1 组头 + 10 行）× 每行 5 节点 = 1121 节点,行带 `align-items: baseline` + grow + gap + padding,叶子带 measure、文本带 baseline 回调;把 `rounds` 改 0 即得「进程 + 建树」基线):本机 Ubuntu 24.04 x86_64 实测 500 轮 `calculate_layout` debug 4.57s / release 2.21s,0 轮基线 ≈0.106s,折得**每轮 debug ≈ 8.9ms(8.0µs/节点)、release ≈ 4.2ms(3.8µs/节点)**。下一个优化对象由代码结构直接指出:同一节点在「base 测量」与「交叉轴重测」两轮里被重复 `layout_into`,Yoga 用 16 槽测量缓存解决;yoga-mbt 的缓存形态与失效时机定案见下一条(YG3b)。验证:`moon check` 零警告 + `moon test -p NoahLiu/yoga-mbt/src` 63/63 + 全仓 `moon test` 724/724,且 bench 包作为外部消费者参与 `moon check`,等于「枚举可跨包构造」有了常驻回归。

- **yoga-mbt 测量缓存(YG3b)**:`measure_content` 在同一次布局里会对同一节点重复调用两遍(§9.2 base 测量、§9.4 交叉轴重测),容器还会被父链逐层重复,是基线里的主要冗余。形态:**缓存挂在 `Node` 上**(`measure_cache : Array[((可用宽, 可用高), (宽, 高, 基线))]`,键值全用元组与基础类型——`pub struct Node` 的字段不能引 priv 类型,否则重犯 E4046「public definition cannot depend on private type」),命中时**连基线一起回灌**(基线是容器上抛给父容器做 §9.4 分组的中间量,与尺寸同源,漏回灌会让 rtl/baseline 场景读到上一次的旧值)。**失效时机定案:缓存在单次 `calculate_layout` 内有效,入口整树前序遍历清一次**——理由是本引擎没有脏标记,消费方可以在两次布局之间随意改样式(实测例:padding-left 10→50、baseline 10→18),按 Yoga 那种「版本号/dirty」方案要引入变更通知面,而清缓存的一次 O(n) 遍历相对单次布局成本可忽略,换来零失效漏洞。收益(bench 同机同树,500 轮):**debug 每轮 8.9ms → 5.1ms、release 4.2ms → 2.6ms(1121 节点)**,即约 1.7 倍;剩余成本主要在「带 pinned 尺寸的最终定位轮」——那一轮必须真跑(子项坐标要落地),要进一步就是 YG4 的脏区增量重排,不在工程化批次内做。验证:`moon check` 零警告 + `moon test -p NoahLiu/yoga-mbt/src` 65/65 + 全仓 `moon test` 726/726(新增 2 条失效回归:改 padding 后重排不走旧缓存、改基线后重排不走旧缓存;63 条既有断言零回归即缓存语义未改变布局结果)。

- **yoga-mbt 像素网格取整(YG3c)**:根节点开关 `set_pixel_grid(interval)`(`0.0` / 负数关闭,只在节点作为布局根时生效),`calculate_layout` 末尾追加一趟后处理,把 `left/top/width/height` 落到网格上;关掉开关时全程保留小数值,65 条既有断言必须零回归。取整口径定为**按绝对边框取整再回推相对坐标**:同一物理边被相邻两项共用时两侧读到的是同一个绝对坐标,取整结果自然一致,等分 `100/3` 得到 `33 / 34 / 33`(和恰为总宽,相邻项之间不留 1px 缝)——若按「相对坐标 + 自身尺寸」各自取整,三项都记 33 就少 1px。**踩坑一条**:递归下传父项起端时**只能传「取整后的父起端」不够**,必须同时传「取整前的父绝对起端」:子项的 `layout_left` 是相对父**原始**坐标的,用取整后的父起端去还原子项绝对边,会把父项自己那半格误差算进子项——实测中间容器绝对起端 33.33→取整 33,内部两项原始宽 16.67,于是第二项绝对起端算成 `33 + 16.67 = 49.67`、绝对末端 `66.33`,取整得 50/66 → 宽 16(应为 17,`16 != 17` 断言炸出)。修复后参数分为四元 `raw_*`(还原子项真实绝对边)与 `snap_*`(换算子项相对坐标),误差只出现在各条边自身、不被父项误差转嫁。**未做**:Yoga 的贴父末端回推补偿(`pixelGridSnapError` 一类)——容器有尾部 padding/border 时,贴到内缘尽头的项其取整后末端与父内缘可差一个网格单位以内,记在 README 作为已知限制,真机出现可见缝隙再补。验证:`moon check` 零警告 + `moon test -p NoahLiu/yoga-mbt/src` 69/69 + 全仓 `moon test` 730/730(新增 4 条:整像素等分 `33/34/33`、半像素网格 `33.5/33/33.5`、不设网格保留 `100.0/3.0`、嵌套项按绝对坐标补偿 `mid.left 33 / width 34` 与 `inner 0/17 + 17/17`)。

- **yoga-mbt 内在尺寸 min/max/fit-content(YG3d,YG3 收尾)**:先记口径来源(Yoga 与规范都要核对,不能凭记忆)。**规范侧**:css-flexbox-1 §9.9「Intrinsic Sizes」只有三句话,把定义整体推给 css-sizing-3(§2.1 auto box sizes 给 stretch-fit / max-content / min-content / fit-content 四个尺寸,§5.2 intrinsic contributions 说「贡献 = 只含该项的 auto 浮动在零宽/无限宽包含块里的内容盒尺寸」并声明具体算法留给对应 display 的规范);**flex 容器自身的内在尺寸细则不在 L1**(w3.org/TR 与 drafts 两版都查过,`collected … contribution` 在 L1 里只出现在 §9.3 分行),只在 css-flexbox-2 草案(§9.10.1 还分 ideal / web-compatible 两套)。故本引擎按 css-sizing-3 的通用规则单套实现,不追 L2 的双算法(README 已记)。**Yoga 侧**(SSH 稀疏克隆 `facebook/yoga` 的 `yoga/algorithm`+`yoga/style`+`yoga/enums` 核对):①`Unit` 只有 `MaxContent / FitContent / Stretch`,**没有 min-content 关键词**,`SizingMode` 注释自认「Missing min-content」;②min-content 只作为 §4.5 内部量存在——`computeMinContentMainSize` 对叶子用「请求轴 `AtMost 0` + 另一轴 `Undefined`」调测量函数(文本回最长词宽),对容器直接递归且**只看容器自身主轴**(子项主轴求和、交叉轴取最大),忽略 flex-wrap、忽略 gap;③`MaxContent` 尺寸模式下测量函数的可用空间被改成 `YGUndefined`。本引擎取「Yoga 的探询约定 + 规范的合成规则」:叶子探询沿用 `Some(0.0)` / `None`(与既有 `set_measure` 签名兼容,不改 API),容器合成做换行感知(可换行容器的 min-content 主轴 = 最宽单项,并按该宽度贪心分行求交叉轴;不换行取单项之和)。**语义修正两处**:①§4.5 `min:auto` 的 content size suggestion 此前用「当前可用空间下的测量值」近似 → 改为真 min-content;②§9.2 `flex-basis: auto` 且主轴尺寸也 auto 时的基准此前同为该近似 → 改为 **max-content**(否则折行项的基准随可用空间漂移,收缩算不到溢出量;实测:100 宽容器里放 wrap 子容器(单项 60/50/40),改前基准 90 不收缩,改后基准 150 收缩到可用 100,可用 55 时被 min:auto=60 顶住)。新增取值 `min_content() / max_content() / fit_content()`,可进 width / height / min-* / max-* / flex-basis,绝对定位子项同样吃(`axis_size` 一处收口)。踩到两条:①**内在探询不能刷新节点基线**——第一版叶子探询走 `measure_content`,探询(不受约束那次)覆盖了真实布局的 `Node.baseline`,基线分组会读到「单行基线」,改为直接调测量函数的专用探询路径;②**热路径要为缓存键的分配买单**——`measure_content` 每次调用先构造键元组再线性比对,新增的内在递归把每节点探询从 2 次抬到 4~6 次,`release` 每轮从 1.30s(500 轮)涨到 2.54s,逐步止损(`release` 500 轮实测 2.54 → 2.07 容器只求主轴就不算交叉贡献 → 1.93 命中改逐项比较、只在写入时构造键 → 1.81 叶子探询绕开 `measure_content` 另加「显式尺寸已定就不探对应内在值」的短路,探到也要丢弃的值不再探)。bench 口径(直接计时构建出的可执行文件,0 轮基线 0.106s,与 YG3a/YG3b 的 `moon run` 口径不同批比较需谨慎,本批 A/B 是同机同法实测):每轮 debug 4.9→7.3ms、release 2.4→3.4ms(1121 节点),即真内在尺寸的成本约 +40%;进一步要靠「缓存跨布局驻留 + 脏区增量重排」,那属于集成层(YG4),本批不做。验证:`moon check` 零警告 + `moon test -p NoahLiu/yoga-mbt/src` 79/79 + 全仓 `moon test` 740/740(新增 10 条:max-content 不被可用空间压窄、min-content = 最长词、fit-content 三段夹取、min-width: max-content 顶住收缩、flex-basis: max-content 参与 grow、列容器 min/max-content 宽取最宽子项加 padding、折行容器基准 max-content 与下限 min-content、nowrap 容器 min-content 为子项之和、绝对定位项的 max-content、改子项后内在缓存不复用旧值;69 条既有断言零回归)。对照材料:css-flexbox-1 §9.9 / §4.5、css-sizing-3 §2.1 / §5.2、`facebook/yoga` 的 `yoga/algorithm/CalculateLayout.cpp`(`computeMinContentMainSize` / `measureNodeWithMeasureFunc`)与 `yoga/style/StyleSizeLength.h`。

### MoonBit ↔ C ABI

- 蹦床与 C 函数指针原型逐位对齐,含参数个数:C 以 `(closure, args...)` 调用,蹦床首参收 closure。错位后行数正常、部分回调能跑,极具掩盖性;每个回调都真实触发过才算验证。
- `extern "c"` 返回可空类型:旧版工具链直接段错误(成败经 `Ref[Int]` 出参报告);moon 0.1.20260904 + moonc v0.10.12 实测 `-> Bytes?` 已可用——C 侧返回 NULL 正确映射 None,debug / release 双模式、真实缺失文件与目录(EISDIR)路径均验证(sysmonitor 的 read_text_file)。其余可空类型(句柄等)未复测,仍按出参模式兜底。
- FFI 指针参数标 `#borrow`(编译器强制);控件参数写句柄类型 `View`,不写 MoonBit 包装 struct(否则运行时句柄全部无效且静默丢弃)。
- 闭包跨 ABI:无捕获顶层函数字面量即 C 函数指针;带捕获走「函数指针 + 闭包指针」双参模式。
- 回调闭包由注册表进程级保活,不随窗口回收(单窗口工具场景泄漏可忽略,已定案)。
- Toolbar / Vibrant 的 Linux 静态库无符号,链接必败,不暴露;Browser 空 Cookie 列表崩溃已在 fork mbt.7 修复。
- 改 shim 签名必须 `.cpp` / `yue_mbt.h` / ffi.mbt 三处同批;漏同步或整段漏声明的断链形态都是 mangle 分裂(`_Z` 前缀符号对纯 C 名引用),nm 对比定位;出包前跑「.cpp 全量定义 × 头文件声明」对照扫描。
- **独立翻译单元(如 `yue_accent_mac.mm`)不 include `yue_mbt.h` 时,函数定义必须显式 `extern "C"`**:缺了按 C++ mangling 导出(`__Z25yue_mbt_system_accent_macv`),`yue_mbt.cpp` 按头文件的 C 名引用即链接 undefined。此病三平台只有 macOS 暴露(Linux/Windows 不编 .mm),vendor/CI 的 prepare 阶段也不暴露(静态库不查 undefined),唯 macOS 真链接(moon test/build)必现;本机无 mac 时唯一防线是 CI。0.5.0 发布前实修一轮(符号经 vendor Actions 重出后 strings 复验为 `_yue_mbt_system_accent_mac`)。
- XFCE 面板 IconPixmap 优先于 IconName:set_icon_name 与 set_pixmap 互斥,设一方须清空另一方。
- **自定义协议拒绝编码与 C 端载荷预验(CORE1,高危)**:`Browser::register_protocol` 的 None 拒绝路径曾把载荷编成 `[1,0,0,0]`——C 端按首 4 字节小端读出的 `ok=1` 当成功,继续在 4 字节缓冲之外读 mime_len/content_len(原生堆越界读),再按垃圾长度 `std::string(p+8, mime_len)` 构造字符串,未定义行为;且拒绝从未真正生效(libyue WebKitGTK 侧只在 handler 返回 nullptr 时 `finish_error` 拒绝请求,见 yue fork 的 `nativeui/gtk/browser_gtk.cc` OnProtocolRequest)。修复:MoonBit 侧拒绝载荷改 `[0,0,0,0]`(ok=0,C 端直接返回 nullptr、不读后续字节),编码抽成包内纯函数 `encode_protocol_payload` 供白盒测试;C 侧先按 MoonBit Bytes 长度预验再逐段解码——ok==0 或载荷不足 12 字节即拒,mime_len/content_len 为负或越出载荷同样按拒(长度比较走 int64 防 `8+mime_len+4` 溢出),nullptr 载荷也兜底拒。Bytes 长度取数据指针前 4 字节(moonbit_object 头的 meta,VAL_ARRAY 即长度;布局照 moonbit.h 的 `Moonbit_array_length`,不引入 moonbit.h 以避免其 extern "C" memcpy 声明与 glibc 冲突),该假设用直链 libmoonbitrun.o + libruntime 归档的最小 C 探针实证(make_bytes(23/4/0) 三态读回长度全对)。教训:**带长度字段的自编码 ABI 载荷,C 端必须自己拿得到总长度并先预验**,不能信任对端"声称成功"后的字段;跨 ABI 的契约测试要与 C 端解码逻辑同构(先长度预验再逐段取值),而不是只验编码侧形状。验证:`moon check` 零警告 + `moon test` 636 全绿(新增 yue/browser/browser_wbtest.mbt 8 条:None 载荷逐字节为 `[0,0,0,0]`、Some 逐字节对齐 ok/mime_len/mime/content_len/content、UTF-8 多字节按字节计长、空 mime/content 的 12 字节最小载荷、旧版 `[1,0,0,0]` 形态与 ok=1 的 8 字节短载荷均按拒、mime_len/content_len 越界按拒、长内容含引号换行往返);shim 改动经 prebuild 增量重编,删 `_build` 下 showcase exe 后 `moon build examples/showcase` 重链零警告(nm 确认 exe 引用 yue_mbt_browser_register_protocol);showcase 补 demo-deny 拒绝路径按钮与代码片段,加载失败的真机表现由用户在 Linux WebKitGTK 下确认(Windows WebView2 自定义协议本就静默无效)。

### 统一 style 值模型(StyVal trait)与 MoonBit trait object 限制(0.5.2)

- 统一 style 值模型:`StyVal` 开放 trait(`yue/style.mbt`)给 builtin `Double`/`String` 实现 `apply_to(Self, View, String)`,混型数组 `Array[(String, &StyVal)]` 单参数收像素与字符串值,内部派发 `ffi_view_set_style_prop_float/_str` 两条 C 通道(C ABI 无重载,拆分消化在 yue 内)。期望类型已知时数组字面量自动装箱(tuple 内亦传播),存量纯数值调用点零改动迁移。
- **trait object 对 builtin 类型的 impl 判定限制**(moonc v0.10.12 实测,/tmp 探针):①一个 impl 块只能写一个方法,`impl T for X with fn a.. fn b..` 换行连排与同行连写都不存在;②impl 块必须一次写全 trait 全部方法——trait 两方法而某类型只 impl 其一时,报 "does not implement trait, although an impl is defined: method X is missing",且 `&Trait` 引用直接报 "trait not found";③「声明 `= _` + 包级默认 impl + 类型分块覆盖」对 builtin 类型不生效(对 struct 类型是官方文档形态,见 moonbit-docs trait 示例的 J),覆盖块写全两方法也判定失败;④结论:给 builtin 类型实现自有 trait,每类型一个 impl 块写全全部方法(core 的 Show/Hash 同此形态);因此 StyVal 只能单方法,「从 trait object 取回数值」(as_num 通道)不可行。
- **core 库版本敏感 API**:`StringView::exact_view` 在 moon 0.1.20260904 的 core 中不存在(报 no method)、0.1.20260920 中存在且 `sub` 反被标 deprecated——同类 API 随 nightly core 演化互斥存在,代码跟随当前 nightly 的正名,新旧版本切换时以 moon check 输出为准。
- **CI 挂排查路径与 nightly 特性**(实测):CI 三平台整排红时,匿名 API 拉不到日志(job logs 接口 403),但 `GET /repos/:repo/check-runs/:job_id/annotations` 可读错误注解;注解为空且"Process completed with exit code 1"时按 job 的 steps 列表(`.../actions/runs/:id/jobs`)看哪步红。moon nightly 滚动极快(0.1.20260918 数日内 404、0.1.20260920 当天傍晚即 403 下架),install 脚本按具体版本号下载会被滚动清掉——**CI 不能钉 nightly 版本号,只能跟随 latest 别名**。
- **bind_node 运行期重挂后 Windows 鼠标 hit-test 错乱**(真机实测,演进三版结论):bind_node 信号变化 remove+add 重挂子树,Windows 上点击链路触发重挂后,**后续全窗点击都被路由给重挂过的控件**(探针 v3 事件流实证:点行1/空白均触发行2 回调、根容器收不到任何事件),推迟一拍重挂也躲不开——有害的是 remove+add 本身,不是同步栈时机。hit-test 走 ContainerImpl::FindChildFromPoint 的 GetClippedRect(=size_allocation_ 布局分配 rect),remove 后 add 的新子树该值异常扩张,libyue 层根因待 fork 侧修。**规避**:点击链路会重挂自身落点的场景改「预建双份 + set_visible 显隐切换」——显隐走 is_visible_ 标志 + display:none(fork 的 yoga-display-none-flex-basis.patch 专门维护),不销毁不重建 view,探针行5 验证;bind_node 的 doc 已加警示。Linux 的 GTK 布局同步无此病,bind_node 照常。
- **swap_node:bind_node 的 Windows 安全替代**(0.5.2,真机验证通过):两态切换场景(换图标按钮/换整块视图)用 `swap_node(sig, a, b)`——预建两棵节点、信号选显隐,不销毁不重建 view,零 hit-test 风险;showcase 明暗切换改用后 Windows 真机多轮切换+后续操作全正常(此前 bind_node 版全窗点击失效连标题栏都关不掉)。代价:两棵子树常驻(低频场景可忽略)。fork 根修后 bind_node 恢复全平台,swap_node 保留(零重建低开销)。
- **theme_apply 的 Windows 分支勿改推迟**(教训入档):曾按「点击栈内同步重绘扰动消息状态」假设改与 Linux 同款 post_task/post_delayed_task 推迟——黑盒测试(components_wbtest 调 theme_apply)进程退出时 60ms 延迟任务对已销毁窗口执行 EnumWindows/RedrawWindow 直接崩,Windows CI exit -1 两连挂;且该假设已被探针否定(真凶是 bind_node 重挂)。Windows 保持同步 ffi_repaint_all,Linux 保持原有两拍推迟。
- **bind_node 运行期重挂后 Windows 鼠标 hit-test 错乱**(真机实测):bind_node 信号变化走 remove+add 重挂子树,Windows 上 yoga 根不重算(native v0.15.6-mbt.19 只修被清零节点自身,树结构变化不在修复面),新挂子树 bounds 停在脏值→鼠标命中测试恒命中它——表现为「点了深浅切换按钮后,全窗口的点击都触发明暗切换,其余操作全部失效」,键盘走焦点不受影响。修复:bind_node 的 rebuild 尾部在 Windows 上对挂载容器调 refresh_layout(整窗布局重算+根级重绘,与 tabs 切页同款兜底);Linux 的 GTK size request 自动覆盖新子树无需此步。同族面:toast 层动态移除条目属纯删(在 mbt.19 修复面),暂无恙。
- **仓库整体移动后 CMake 缓存拒绝配置**(真机实测):build/ 里的 CMakeCache.txt 记录配置期绝对目录,仓库从旧路径整体拷到新路径后 cmake 报 "current CMakeCache.txt directory is different than..." 且拒绝配置,prepare.py 中断。修复:prepare 的 cmake_build 前检测 CMakeCache 记录的 CMAKE_CACHEFILE_DIR/CMAKE_HOME_DIRECTORY 与当前路径不一致即清空 build/ 重新配置(顺带重编 shim),无需手动删目录。
- **Windows 用户名含撇号/空格的 LNK1104**(真机实测):moon 在 Windows 上拼 cl/link 命令行时对含单引号的绝对路径 quoting 失败——用户目录 `C:\Users\noah'liu\...` 的库路径被剥掉撇号,且 `yue_mbt.lib` 与 `yue_prebuilt.lib` 两个空格分隔的路径被黏成**一个**链接输入,LNK1104「无法打开文件 …lib …lib」;prepare.py/cmake 均不受影响(路径原样传递),只有 moon 的 link_flags 拼接炸。修复:prebuild 的 Windows 分支库/manifest 一律用**相对模块根**路径(`build/yue_mbt.lib`、`lib/windows-x64/…`),moon 链接子进程 cwd 即模块根(从模块根执行 `moon build` 为前提),相对路径只含安全字符天然绕开;Linux/macOS 走参数数组不经命令行拼接,无此问题仍用绝对路径。
- **同族第二条·撇号路径让**整条 link_flags 静默消失**(2026-10-15 Windows 10.0.19044 本机,新栈复现)**:moon 会把 prebuild 下发的 `link_flags` **按 shell 词法再拆一遍**,于是路径里的单引号(`C:\Users\noah'liu\...`)=**未配对的引号**,该条被整条丢弃且**不报任何错**——症状不是「找不到这个文件」,而是**这一条里的库全没了**。本仓两处绝对路径条目都中过:①`gui/scripts/prebuild.py` 给 web 包下发的 `web/lib/WebView2LoaderStatic.lib`(唯一含路径的一条,其余 4 条纯系统库不受牵连)整条丢 ⇒ `shlwapi.lib` 与静态 Loader 一起消失,链接报一串 `CreateCoreWebView2EnvironmentWithOptions`/`GetAvailableCoreWebView2LoaderVersion` 的 LNK2019;②`modules/ffmpeg-mbt/prebuild.py` 五条 ffmpeg 导入库同形同果(`av_*` 未解析)。修复:**link_flags 里的路径逐个用双引号包起**(`f'"{lib}"'`),配对引号让词法把撇号当普通字符;`stub-cc-flags` 同规(`-I"${build.FFMPEG_INC}"`,否则撇号路径在 cl 侧被拆成两个参数)。**判据**:`echo '{}' | python gui/scripts/prebuild.py` 看 web 那条是不是带引号的完整路径;产物 exe 里 grep 得到 `WebView2` 串即静态 Loader 真进了链接(ffmpeg 侧以「测试 exe 能链接出件」为判据,运行期 0xc0000135 是 README 记的「dll 不入库」另一回事)。**与上一条不同因**:那条是 link 子进程命令行拼接出错、当场 LNK1104;本条在 moon 解析 link_flags 阶段就整条丢掉、构建看似一路绿灯只剩符号错,更难归因。**通则**:Windows 上 prebuild 下发的任何含路径参数(link_flags / stub-cc-flags)一律加双引号,别假设 moon 会替我们转义;能相对化当然更好,但 web/ffmpeg 这两条要跨模块引用绝对路径,相对化不可行。
- **vendored 库级联误链(浅克隆)——CI 整排红的根因**(实测闭环):prebuild 的 `_native_dir()` 级联「lib/<平台>/ vendored 优先、build/ 回退」,其新鲜度判定 `_sources_newer` 依赖 git pathspec 提交时间;**actions/checkout 默认 fetch-depth=1 浅克隆下 pathspec 限定的 log 退化成 HEAD 时间,t_shim==t_lib 恒等 → 判定 shim 不比库新 → 恒走 vendored**,而 `ensure_native_lib` 对 vendored 就位直接零编译返回——shim 领先 vendored 出包的新符号(如 view_set_bounds/scroll_refresh_content_size)在 CI 链接全部 undefined,本机完整 clone 走 git 时间比较用 build/ 故不复现。修复:`_native_dir()` 改「**build/ 有 prepare 产物(stamp+库)即最高优先**」(开发/CI 链路的产物按当前 shim 全新编译,恒不旧于 vendored;vendored 只服务无 build/ 的 mooncakes 分发用户),`_sources_newer` 浅克隆恒等/mtime 竞态一律保守回退 build/。教训:**vendored 与 shim 的领先关系是常态**,级联判定宁可重编不可误链旧库。
- 布局参数收编后 Windows 单行输入垂直居中不再读数值:改纯布局方案——Entry 控件收窄到行高(`entry_ctrl_height`,文字在控件内天然居中),外壳 `justifyContent=center` 垂直居中,任意高度值(含百分比)自动适配;原 entry_vcenter 的「收窄+均分 margin」路径已删。
- select_t/dropdown_menu 弹层宽度在点击时 `get_bounds(field)` 现取(用户 style 覆盖字段宽后弹层自动跟随);弹层根容器宽高仍须创建期给定(事后 set_style 会被弹层分配时序吞掉,见 GTK 节)。

### 目录枚举与进程内环境变量(shim 的 POSIX / Win32 分支)

- 目录枚举(`yue_mbt_list_dir`,服务 fsx_list_dir;shim 由 prebuild.py 托管编译):POSIX 走 `opendir`/`readdir`(跳过 `.` 与 `..`),Windows 走 `FindFirstFileW`。**不能用 FindFirstFileA**——A 版是 ANSI 代码页,非 ASCII 路径(中文用户目录)全乱码;路径用 `base::SysUTF8ToWide` 转宽字符、拼 `L"\\*"` 模式,子项经 `SysWideToUTF8` 回转。返回扁平 UTF-8 文本、子项名以 '\n' 分行(与本包多字符串返回惯例一致:browser cookie / clipboard get_data 同编码);**子项名本身含 '\n' 的极端文件名会被拆开**,扁平文本编码的已知边界,文档须写明。`ok` 出参区分「空文本是失败」与「空目录」(空目录 ok=1 空文本,合法成功态)。
- 进程内环境变量(`yue_mbt_setenv` / `yue_mbt_unsetenv`,服务 fsx/envx):POSIX 直接 `setenv`/`unsetenv`;Windows 用 `_putenv_s`,它**恒覆盖**——`overwrite=0` 分支须先 `std::getenv` 探测再决定,否则「已是既有值则保持原值」语义会被静默改掉。删环境变量在 Windows 是 `_putenv_s(name, "")`(卸下该变量,不是置为空串),与 POSIX `unsetenv` 语义对齐;本就不存在也记 ok=1(幂等)。作用范围都是**当前进程**(之后 spawn 的子进程可见),不触碰系统持久配置、不影响父进程。
- fsx 把这两类薄原语收进一个模块(appfind / browser_history / envx 共用):要点是「只列条目名、不读内容」,修 appfind 的「大体积可执行文件全量读入仅判存在」取舍——之前 appfind 用 read_binary_file 判存在,现在走 fsx_list_dir 查目录条目。

### 按包拆分:yue 单包 → 核心 + 六个子包(0.5.11)

- 环境:moon 0.1.20260920 / moonc v0.10.14,模块 NoahLiu/native-gui;原生层预构建库就绪。
- 现象:拆包前 yue 单包容纳约 6 万行——FFI、原生控件、主题组件库、20+ 图表、markdown、声明式层、30 个系统能力文件混在一个包。MoonBit 按包编译、包内无树摇,webview 方案或只用核心的消费者也被迫把整套工具箱编进二进制。
- 根因(机制):MoonBit 跨包引用必须 `@别名.` 限定——实证两条:官方 moonbitlang/async 的 src/fs 子包用 `@async.xxx` 引用根包;本仓 yue/media.mbt 用 `@traybus.xxx` 引用 traybus 包。拆包因此=每子包独立 moon.pkg + 包内全部核心引用加 `@yue.` 限定(codemod 词边界替换,须跳过 `.字段`/`::方法`/字符串字面量)+ 外部依赖声明随包下沉(mizchi/markdown → yue/markdown,subproc 与 moonsqlitefile → yue/system)。链接参数无需改 prebuild:link_configs 按依赖闭包逐包拼 flags,新包只 import 核心即自动拿到 `-lyue_mbt`;webkit 仍只进 yue/browser 条目,按需化不被破坏。
- 修复(批次顺序即循环依赖规避):①markdown 先搬——它调 components 的 code_view,晚搬则核心→components→核心成环;②components——前置手术是把 `hand()` 光标助手从 components.mbt 提入核心并 pub(charts_interactive 跨包引用它,charts 后搬),主题块约 17 个私有 getter 及 bind_fg/bind_entry_theme/entry_ctrl_height 被 20+ 文件跨包引用,按需 pub 化;③icons;④charts(charts_wbtest.mbt 自带 extern "C",moon.pkg 须 targets 声明 native-only);⑤declarative——前置手术两步:Node 协议(struct Node + attach)从 declarative.mbt 抽留核心 yue/node.mbt(否则 components/icons/markdown/charts 等包对 Node 的无前缀引用全要改),signals.mbt 末尾的 `bind()`(内部调 bind_label)随 bind_label 迁入 declarative 包;⑥system——打开外部 `open_url`(system.mbt)与托盘 tray.mbt 留核心(markdown 的链接点击依赖 open_url,procrun 随系统层走);⑦版本收口 0.5.11:moon.mod、yue/version.mbt、modules/gui-media 钉版三处同步(prebuild 构建期校验一致,不一致 moon build 直接失败)。
- 验证方式与教训:每批 moon check 零警告 + moon test 全量 + moon build examples/showcase 与 sysmonitor;独立验收员只读审 git diff(符号逐位等价、moon.pkg 卫生、无夹带)。**教训:门控漏了 systemprobe**——批处理提交后,已推送的树 systemprobe 构建 15 处断链(导入适配留在工作区未随批提交),hello/hello-themed 不受影响故双示例门控无感;用 `git stash` 在已提交态实测才发现。拆包类改动的门控必须覆盖全部示例,提交范围须以 git status 逐批核对(并行工作流的未提交文件极易被整文件提交扫入)。

### MoonBit 原生 GUI 栈 G1（绘制契约）· 本工具链的 MoonBit 语法形态与缓冲选型

环境：Ubuntu 24.04 + X11 + XFCE，moon 0.1.20260920 / moonc v0.10.14。新增 `render`（纯 MoonBit，零 FFI）。

- **坑**：`pub method name(self : T, ...)` 直接解析失败——`method` 是保留字（Warning 0035 提示 reserved keyword）。**修复**：一律写 `pub fn T::name(self : T, ...)`。
- **坑**：`match expr with { }` 报 `unexpected token with`（仓库现有代码里 `match ... with {` 出现 0 次）。**修复**：写 `match expr { }`；注意**记录更新** `{ s with tx: 1.0 }` 里的 `with` 仍合法，两处不同构。
- **坑**：`Bytes` **只读**（无 `op_set`），且本版本**没有** `ByteArray` 类型（`The type/trait ByteArray is not found`）。**修复**：可变字节缓冲用 `FixedArray[Byte]`（`yue/png_rgba.mbt:12-19` 已在用），就地写入还不需要 `mut` 绑定。像素位图字段因此定为 `FixedArray[Byte]`，G2/G3 交给 Cairo/X11 时再取数据地址。
- **坑**：`self.field[i] = v`（经字段下标赋值）会把整个方法提成要求 `T &mut`，调用点就得写 `mut p`；对要承接组件层一万行既有调用点的绘制器不可接受。**修复**：写像素前先取局部句柄 `let d = self.data` 再 `d[i] = v`；而状态重绑（`self.state = {...}`）同样要求 mut，故把可变字段放到**内层** `PainterState` 的 `mut` 字段上、外层 `state` 字段从不重绑（与 `yue/signals.mbt:247` 的 `self.node.dirty = false` 同构），`p.fill_rect(..)` 因此在不可变句柄上可用。
- **坑**：结构体是引用语义，`save()` 把 `self.state` 直接入栈，`restore()` 拿回的是同一个对象，状态根本不会回退。**修复**：入栈逐字段拷贝快照（`snapshot`），出栈逐字段写回（`load_state`）；此行为已有单测覆盖（translate + restore 后两处像素分别断言）。
- **坑**：带类型名的构造 `Color { r: ... }` 解析失败。**修复**：按上下文写裸 `{ r: .., g: .. }`（参照 `yue/view.mbt:513-521`）。
- **坑**：跨 `moon.work` 成员的测试依赖只在 `moon.pkg.json` 的 `wbtest.import` 里声明会报 `Package ... not found`，且条目中的 `alias` 字段被静默忽略（默认别名取路径末段，故 bench 里是 `@src`）。**修复/取舍**：要让 `render` 的测试用 yoga-mbt，得在根 `moon.mod` 声明该模块依赖，会改动发布依赖图；本批不动它，「布局树→像素」的定位断言顺延到真正接线 yoga 的批次（G2/G7）。
- **口径分岔（记档待定夺）**：hex 8 位写法本栈按 CSS 的 `#RRGGBBAA`（透明度在尾）解析，而 libyue 的 `Color` 约定是 `#AARRGGBB`（`yue/color.mbt` 的 parse_hex 注释里写明混用表现为颜色漂移而非透明度变化）。新栈不沿用前者。
- **坑（工具链副作用，勿再踩）**：仓库级 `moon fmt` 在当前版本会重排约 80 个与本批无关的文件（本仓并非 fmt-clean），并把 `moon.pkg.json` **迁移**为 `moon.pkg`——而新 DSL 不认 `warn_list`（见 `modules/yoga-mbt/HANDOFF.md` §6.11），`yoga-mbt/src` 里那条 `warn_list: -6` 会被静默搬走。**修复**：`moon fmt` 只点名本批新文件；跑后以 `git status` 核对，误改的一律 `git checkout -- <显式路径>` 回滚。

- **验证**：`moon check` 零警告 + 全仓 `moon test` 748/748（`render` 新增 8 条像素级断言：半开区间覆盖、source-over 混合、translate+restore、clip 只收紧、内侧描边一圈、窄矩形整块填满、100/3 等分共用边不留缝、非法 hex 与零尺寸位图保持原状）。

### MoonBit 原生 GUI 栈 G4 首批（编辑内核与键码）· 内核语义与工具链写法

- **内核语义定案**：文本状态唯一权威在 `input`，输入法只是它的客户端之一（不做「通道持有文本」那份双状态）。坐标一律 **UTF-8 字节下标**，caret/anchor 只落码点边界（续字节 0xC0..0xBF 回退），与 G0 探针同源；改成码点下标会同时断掉 Pango 量宽与 IME preedit 偏移口径。`get_text_in_range` 的对齐方向是**起点回退、终点前进**（宁可多含一个码点，也不返回半字）。内核不碰系统剪贴板：`cut/copy` 返回文本、`paste_text` 接收文本，故整块逻辑可在无显示环境下测。`Tab`/`Shift+Tab` 返回「未消费」交上层焦点栈；可打印键由 `keysym_to_text` 落地（Latin-1 与 UCS keysym 两条路），其余功能键留给 G5 的 IME 通道。
- **坑（本工具链写法，均实测）**：① `fn helper(self : Editor, ..)` 这种隐式方法形式**不被识别**（报 unbound），私有辅助也要写 `fn Editor::helper(self : Editor, ..)`；② 顶层常量 `pub name : Int = v` 解析失败，要 `pub const NAME : Int = v`（大写）；③ `move` 是保留字（Warning 0035），方法改名 `move_caret`；④ `Int.to_char()` 返回 **`Char?`**，直接插值会报「Option does not have a meaningful string representation」，必须先 match 出 Char；⑤ `pub enum X derive(Eq, Show) { A B }` 的变体在别处不可构造，无载荷枚举要 `pub(all) enum`，本批进一步把二值枚举（Consumed/NotConsumed）直接换成 `Bool` 少一层语法面；⑥ `} else match ... {` 不合法，match 作分支体要裹 `{ }`。
- **坑（越界）**：`floor_boundary` 允许 k == 缓冲长度（末尾是合法边界），循环里必须 `k < n` 短路后再取字符，否则 `Array::at` panic（实测 SIGABRT）。
- **验证**：`moon test -p NoahLiu/native-gui/input` 10/10（中英混排 roundtrip、退格删整字不残留、选区替换、词跳转三个方向、shift 延长/折叠、copy 不动状态而 cut 删、undo/redo 往返、handle_key 路由与 Tab 归属、Ctrl+A/Ctrl+Z/Ctrl+左、区间对齐）；`moon check gui/{core,input}` 零警告；render 14/14、text 7/7、yoga-mbt 79/79 未掉。

### MoonBit 原生 GUI 栈 · Painter 契约补齐首批（门面化 + 混合模式 + 渐变）

- **门面化定案**：`Painter` 从「纯矩形子集」升为**完整契约门面**——`new(bitmap)` 即开一个 Cairo 会话，矩形/路径/变换/裁剪/混合/渐变都走 Cairo；Cairo 不可用（非 Linux 占位 stub、或 16 个会话槽耗尽）时退回纯矩形实现（路径类调用为无操作）。矩形类绘制在**两条路径上逐像素一致**（新增矩阵等价用例：取整、内侧描边、裁剪求交、平移、半透明叠色一段序列跑两遍比对）。
- **会话纪律**：Cairo 会话槽 16 个（`CR_MAX`），每帧一个会话的用法要求 `Painter::end()` 回收；泄漏会让后续 Painter 静默退回降级实现。新增「连续开合 20 个 Painter 仍持有会话」的回收用例；旧测试有 9 处没回收（累计 14 个泄漏），补 `end()` 后余量才回到安全区。
- **混合模式**：25 个 `BlendMode` 与 Cairo 算子 **1:1 映射**（前 16 个 W3C 混合 + 后 9 个 Porter-Duff）。独立 C 探针实测本机（cairo 1.18 + pixman）**25 个算子全部真实生效**（pigment 系与 HSL 系含），无需自实现混合算法；半透明源按 W3C 公式（`(1-α)·底 + α·Blend(底,源)`，实测 0.5 α 乘算 = 0.5·底 + 0.5·底×源），透明底上 Multiply 退化为源色。25 模式实测表落成断言行（混合/HSL 行留 ±2 容差防跨 pixman 定标差异，Porter-Duff 行精确值）。
- **坑（取整必须在设备空间）**：矩形取整若发生在**用户空间**，经 CTM 平移（如 `translate(1.3, 0.6)`）后的设备坐标是分数像素 → Cairo 抗锯齿出灰边，与纯实现分岔——「门面 vs 降级」矩阵等价用例正是靠这一条先红后绿。修法：`cairo_user_to_device` 换算后在**设备空间** `floor(v + 0.5)`，再临时换单位矩阵按整数矩形填充；矩阵含旋转/斜切（off-diagonal 非零）时不做取整，原样交给抗锯齿。
- **坑（裁剪区是图形状态）**：临时单位矩阵 + `cairo_rectangle` + `cairo_clip` **不能**用 `cairo_save`/`cairo_restore` 包住——裁剪属于被保存的状态，`restore` 会把刚设的裁剪一起回退；必须手动 `cairo_get_matrix`/`cairo_set_matrix` 还原（裁剪终值存设备空间，之后 CTM 再变不影响已设的裁剪区）。
- **坑（默认线宽不同源）**：Cairo 会话默认线宽 **2.0**、契约默认 **1.0**，`Painter::new` 里不同步会让不调 `set_line_width` 的描边（如 `stroke_rect` 的内侧带）粗一圈——「描内侧一圈」用例给出定位。
- **坑（不存在的函数）**：`cairo_pattern_get_status` 不存在（正确的是 `cairo_pattern_status`），写错报在**链接期** undefined reference 而非编译期。
- **坑（产物路径大小写，G3b 那条的补充）**：本仓测试产物路径是 `_build/native/debug/test/NoahLiu`（**首字母大写**），删小写路径静默不生效、测试继续跑旧二进制——本批一度在修好设备空间取整后仍见 20 像素差异，实为旧产物。改原生库后删产物的正确路径：`_build/native/debug/test/NoahLiu/native-gui/<pkg>`。
- **渐变**：`Gradient::linear`/`radial` + `add_stop`，offset 钳到 [0,1]、hex 非法忽略、无 stop 的渐变整体忽略、`set_fill_color` 覆盖渐变；实现为一次性 pattern（建 → 逐 stop 加色 → 设为 source 即释放句柄）。实测口径：线性在像素中心采样（`(x+0.5)/轴长`）、超端点 pad 复现端点色；径向同心、四角对称。
- **验证**：`moon test -p NoahLiu/native-gui/render` 25/25（新增 11 条：Porter-Duff 精确值、25 模式实测表、半透明公式、透明底退化、模式与设色顺序无关、线性渐变采样与 pad、径向对称、空渐变忽略与纯色覆盖、门面路径与抗锯齿、save/restore 变换与样式同退、会话槽回收）；逐包 `moon check` 零警告、core 15/15、input 10/10、text 7/7、yoga-mbt 80/80；`examples/native-window` 冒烟 49 帧、退出码 0（示例改为走门面，并用上渐变辉光、乘算方块与路径圆）；全仓红点仍 290 errors / 68 warnings 未增。

### MoonBit 原生 GUI 栈 · Painter 次批（离屏 Canvas 与图片）· 采样域与归档重建

- **图片解码**：走 **GdkPixbuf**（GTK3 既有依赖，零新增运行期依赖；`GdkPixbufLoader` 按内容嗅探格式），像素统一转成本栈 `Bitmap` 布局（ARGB32 预乘、小端 B,G,R,A），预乘取整与 `Bitmap::paint` 同口径 `(c*a+127)/255`，因此「编码 → 解码 → 再编码」字节稳定（`#12345680` 这类半透明色也精确往返）。解码器只取**静态首帧**——旧链路的 `Image` 是 `GdkPixbufAnimation`（GIF 会动），动画属已知缺口，不假装支持。
- **尺寸口径照老师**：`get_width`/`get_height` 返回**逻辑尺寸**（像素 / scale），`get_scale_factor` 返回记录比例——与 libyue `image_gtk.cc:75-77` 的 `ScaleSize(.., 1.f / scale_factor_)` 一致。
- **坑（blit 的采样域必须收在源子矩形内）**：直接给「整张源位图」建图案、只把源矩形写进图案矩阵，双线性会从子矩形**外**取色——精灵图/图标拼接会串色（测试里「取左上象限铺到 4x4」先红：右缘采到了隔壁绿块）。修法：`cairo_surface_create_for_rectangle(s, sx, sy, ssw, ssh)` 建**子表面**，采样空间随子矩形原点平移，再叠 `PAD` 扩展让边缘不越界成透明缝。
- **坑（`ar rcs` 对改名成员是追加）**：源文件从单个拆成 `cairo_stub.c` + `image_stub.c` 后，旧归档里残留的 `librender_cairo_stub.o` 与新对象**同时**进库 → 链接期 `multiple definition`。prebuild 的 `compile_stub` 改为「先删旧归档再 `ar rcs`」，并把「任一源更新即整体重编」写进缓存判据（原来是单源 mtime 比较）。
- **资产搬家的连带**：PNG 编码器从根包 `yue/png_rgba.mbt` 搬进 `render/png.mbt`（公共入口改名 `png_encode_rgba`，内部 `pngr_*` 保留），随包带走 6 条既有用例；根包私有 helper `utf8_bytes` 在外包不存在，要改用 `@utf8.encode` 并在 `moon.pkg` 加 `moonbitlang/core/encoding/utf8`。搬完红点从 290 降到 **287**（根包少了一个文件与一份测试）。
- **文件写入**：`Canvas`/`Image` 的 `write_to_file` 目前只支持 "png"，落盘经 C 端 `fsw_write_file` 兜底（系统层落地前的临时通道，路径按 UTF-8 字节收）。
- **验证**：`moon test -p NoahLiu/native-gui/render` 40/40（新增 9 条：PNG 往返不透明/半透明、空图语义与空图上不落像素、逻辑尺寸随 scale、`resize` 放大实心色保持、`draw_canvas` 2 倍放大四象限、`draw_canvas_from_rect` 子矩形无串色、blit 尊重混合模式乘算、PNG 落盘读回逐像素；另有 6 条 PNG 编码器用例随搬家并入）；逐包 `moon check` 零警告、core 15/15、input 10/10、text 7/7、yoga-mbt 80/80；`examples/native-window` 冒烟 49 帧、退出码 0（新增离屏画布精灵 4× 放大上屏）；全仓红点 **287 errors / 68 warnings**（较 290 减少，未增）。

### MoonBit 原生 GUI 栈 · 图标绘制面平移（803 条千分定点路径）

- **平移范围与保真**：master `icons/icons.mbt` 前 4197 行（`IconKind` 803 变体、`path_num`/`fill_icon_path` 解释器、`draw_icon`、`icon_path_data` 数据块、`kind_index`/`all_icons`/`icon_name` 三张表）整段搬入新包 `icons`；改动只有两处类型引用 `@yue.Painter → @render.Painter` 与头部说明，**数据块与本尊逐行零差异**（`diff` 只报头部 7 行与 2 行类型引用）。声明式包装 `icon`/`icon_button_t` 依赖声明式层，留给组件接线那批（G7）。
- **语义照搬不重造**：坐标为归一化值 ×1000 的整数定点、命令集 M/L/C/Z、每子路径 M…Z 闭合、整体一次 `fill`（iconfont 轮廓型）、安全边距 0.88（`v × s × 0.88 / 1000 + 中心`）、单命令即读即调不缓存（解析微秒级）。
- **测试口径**：①清单/名字/路径数据三表一一对应——用「计数数组每格恰为 1」代替哈希集合（不为此引入容器），名字唯一用平方比对（该规模够用）；②路径串字符集封闭**全量扫描**（只允许 M/L/C/Z、数字、`-`、`,`，且首 M 尾 Z）；③`draw_icon` 落像素且已画像素包围盒中心 ±2px（验居中语义，不锁具体形状）；④图标 24px **全量扫描无空图**（含解析 + 光栅化，0.7s 内跑完）。
- **环境观察（避免误判）**：示例退出行的 `seen` 计数含**指针移动**事件（motion 的 code 4 同样走输入队列），冒烟时鼠标停在窗口上会看到 `seen` 非 0 而文本不变，属预期，不是「按键乱入」。
- **验证**：`moon test -p NoahLiu/native-gui/icons` 4/4；`moon check icons` 零警告；`examples/native-window` 冒烟 49 帧、退出码 0（示例新增一排五个矢量图标）。

### MoonBit 原生 GUI 栈 · 字体与富文本子系统（Font / TextFormat / AttributedText）

- **面**：`Font`（族名 + 逻辑像素字号 + 9 档字重 + 斜体；字重数值就是 CSS 的 100..900，直传 Pango 的 `PangoWeight`）、`TextAlign`/`TextFormat`/`TextAttributes`/`SizeF`/`AttributedText`（本批为**整体属性**面：字体、颜色、对齐、换行、省略、`get_bounds_for`、`set_text`/`get_text`/`clear`）。区间属性（`set_font_for`/`set_color_for`）要把范围挂进 Pango attribute list，留次批。
- **绘制入口按包边界放 `text`**（`draw_in_box`/`draw_font`），不做 `Painter::draw_text` 方法：MoonBit 不能给外包类型加方法（render 也不能反向依赖 text）。组件层接线时调用点从旧契约的 `p.draw_text(..)` 改 `@text.draw_in_box(p.bitmap, ..)` 形态，属 G7 的定点改写。
- **坑（语义级，探针实测抓出）**：`wrap=false` 此前**根本未生效**——Pango 只要 `pango_layout_set_width` 就按默认 `WRAP_WORD` 折行（实测：120px 宽 + 不带换行标志，长文本仍折成 4 行 88px）。修法：宽度只在「要换行或要省略」时才交给 Pango；单行不省略时按自然宽绘制（可溢出盒界），盒内对齐改为自己算偏移（与垂直对齐同一套写法）。这也纠正了旧文档「定高行内长文本会溢出行界」的说法——它是折行。
- **坑（FFI 原型要三处同批改）**：给 `pt_font_line_height` 加 weight/italic 时只改了 MoonBit extern 与 portable 占位，**真实现**（`text/stub.c` 的 Pango 分支）还是 4 参——多传的实参按调用约定落进 `out_h` 指针位，症状不是崩而是「行高断言莫名变假」。规则：改 FFI 签名 = moon extern + 真实现 + 占位分支三处一起。
- **坑（本工具链派生 trait 是弃用路径）**：`pub(all) enum X { .. } derive(Eq)` 触发 `implicit_impl_as_method` 弃用警告（`equal`/`not_equal` 被隐式提升为普通方法）；把 `derive(Eq)` 写在枚举名之后更是直接编译错（正确位置是 `}` 之后）。为守住零警告，本批不派生 trait，测试用包内 id 映射比较枚举（`align_id`/`weight_value`）。
- **验证**：`moon test -p NoahLiu/native-gui/text` 14/14（新增 7 条：`wrap=false` 单行自然宽与 `wrap=true` 的高度对照、省略宽度受钳、粗体不窄于常规、盒内水平/垂直对齐落点与居中、`AttributedText` 属性面与包围盒、`new_with`/`format` 往返）；`moon check text` 零警告；`examples/native-window` 冒烟 49 帧、退出码 0（示例新增居中粗体标题，把 Font/TextAlign/AttributedText 跑了一遍）。

### yoga-mbt · 语料派生项结案：子项 flex-basis 被容器属性遮蔽（Chrome 对照）

- **来源**：语料 `93078300` 派生待查——显式 `flex-basis: 0` + `min-height: 0` 在 auto 高列容器下引擎给 60，按 CSS 推导应为 0。
- **Chrome 对照手法（可复用）**：本地 HTML + 浏览器 MCP 的 `getBoundingClientRect()` 读实高；规范正文用 drafts.csswg.org 页面内 DOM 抽取（`document.querySelector('#anchor')`）比 WebFetch 可靠（后者只拿到目录）。
- **结论一（Blink 口径）**：auto 主轴尺寸 = **各子项假想主轴尺寸之和**（flex base 被 min/max 钳制），growth 完全不参与。证据行：`basis 100 / 内容 300 / grow 1` → **100**（规范 §9.9.1 的 Ideal 算法会按弹性因子放大、Web-compatible 取 max-content contribution 给 300，两者都不符，实现以 Blink 为准）；`basis 0 + min 0` → 0；`basis 0 + min:auto` → 60（内容下限）；`basis auto + max-height 30` → 30；`basis 40%`（容器主轴不定、无参照）→ 60（退回内容）。
- **结论二（根因，一处笔误）**：弹性项构建时基准读成了**容器**的 `s.flex_basis`（应为 `c.style.flex_basis`），子项 flex-basis 于是在整条布局链路上从未生效——这也解释了为什么 basis 怎么设结果都一样。容器 auto 主轴尺寸同样不看子项基准，改由新的 `main_contribution` 承担：确定基准优先并按其确定的 min/max 钳制，auto / 无参照百分比退回内在尺寸；`min: auto` 的内容下限只在 §4.5 弹性解析里生效，不在容器推算里重复探内在尺寸（否则每次容器测宽/测高都多算一遍内在尺寸）。
- **验证**：Chrome 矩阵 7 行（A/C/D/F/G/I/L）逐行一致，落成 `patches_regression_wbtest.mbt` 的常驻用例；yoga-mbt 81/81（含 `display:none` 语料用例与全部既有断言）；bench 无变化（1121 节点 × 500 轮 release：修复前 1.93s、修复后 1.95s，A/B 实测）。

### MoonBit 原生 GUI 栈 · 主题系统首批（色板派生公式 + 变更订阅）

- **面**：`Theme`（20 字段色板）+ `default_theme`/`dark_theme` 预设 + `theme_from_accent`（EP 主题工作台公式：主色保色相、饱和度保底 0.45、明度按模式钳制（浅 0.34..0.52 / 深 0.55..0.72）、hover 浅 -0.09 深 +0.08、`*_light` 浅混白 12%/14%、深混面板底 30%/28%、语义色取固定色相轮 142/36/4/210 且饱和度假借主色（≥0.4）明度随模式、中性色不随主色偏移）+ `theme_current`/`on_theme_change`/`off_theme_change`/`theme_apply` + 20 个 getter + `control_height`（32）+ `entry_ctrl_height`。
- **三处刻意不做（与旧链路的差）**：①原生控件 CSS 下发（旧 `apply_native_theme_css`）——新栈控件全自绘，色板是绘制时唯一来源，没有「原生观感跟系统主题」这回事；②`ffi_repaint_all` 整体重绘兜底——重绘责任随组件批次落到各控件的订阅路径；③`theme_from_system`（跟随系统深浅与主色）依赖系统集成层读取，未接。`sub_bag_begin/end` 批量退订随 relink 层接。
- **色彩数学落点**：`theme/palette.mbt`（hex 解析 / `rgb_to_hsl` / `hsl_to_rgb` / `mix_hex` / `lighten_hex` / `darken_hex`），其中 hex 解析复用 `@render.Color::parse`——即 CSS 口径「8 位透明度在尾」，与 libyue 的 `#AARRGGBB` 分岔已在 G1 条记档；主题串只用 6 位写法，不受影响。
- **从 master 继承的一条实测坑**：`mix_hex(a, b, t)` 的 `t` 是取**前者**的比例，且端点（t=0/1）与非法输入要**原样返回输入串**，不经 `hex6` 往返——`hex6` 输出小写十六进制，会把主题里的 `#2D68C4` 改写成 `#2d68c4`，与原串比较不等。断言按小写写（`theme_from_accent("#FF0000").primary == "#ff0000"`）。
- **测试取向**：不断言派生出的具体色值（换基准盘就整片红），只断**公式不变量**——灰 accent 饱和度被抬到保底、白 accent 明度被钳上限、深模式把暗 accent 抬到下限、hover 的明度方向、语义色色相轮 ±1°、浅底变体的混色方向、非法 accent 回落基准盘；订阅面断「通知走快照」（回调里新注册的不进本轮）、退订幂等、未知句柄空操作、`theme_apply` 后 getter 跟随。
- **验证**：`moon test -p NoahLiu/native-gui/theme` 7/7；`moon check theme --deny-warn` 零警告；全仓红点仍 287 errors / 68 warnings；其余包与 yoga-mbt 未动。

### MoonBit 原生 GUI 栈 · 控件宿主首批（布局树 ↔ 控件树、命中与事件路由）

- **落点**：按计划 §2 的包表放在 `core`（循环/焦点栈同在本包，平台后端在 `win`，绘制契约在 `render`），本层不认识任何平台句柄。这也是 yoga-mbt 第一次成为主包的依赖——`moon.mod` 的 `import` 加了 `"NoahLiu/yoga-mbt@0.1.0"`（工作区里已有该模块，缺这句会报「containing module is not imported」）。
- **坐标口径（只在一处换算）**：yoga 的 `left/top` 是「相对父节点边框盒」的偏移；`relayout`/`relayout_at` 在布局后一次遍历（`collect_abs`）把它折算成窗口坐标的绝对矩形写回控件。命中测试与绘制遍历都只吃绝对矩形；事件交给处理器前再平移为控件本地坐标（本地 (0,0) = 该控件边框盒左上角）。绘制逐层 `translate + clip_rect`，所以控件的 `on_draw` 只写本地坐标、不需要自己裁剪。
- **传播规则**：从命中控件起沿祖先链向上，第一个返回 `true` 的处理器消费掉事件（指针/滚轮/按键同一条规则）。宿主**不存父指针**，冒泡靠命中路径（`hit_path` / 按焦点 id 寻路），因此重挂子树不会留下悬垂的父引用。
- **坑①（控件本体不能比 `==`）**：`Widget` 带闭包字段 → 派生不出 `Eq`，`Option[Widget] == None` 直接编译错（报在 `impl Eq for Option` 的约束上）。做法：控件自增 `id`，本体比较与测试断言一律走 id（命中不到给 -1 的辅助函数）。
- **坑②（隐藏子树留着旧矩形）**：布局引擎碰到 `display:none` 就**不再往下递归**，其后代的 `layout_*` 保留上一轮数值。若 `collect_abs` 不跳过隐藏子树，被隐藏的后代仍可能拿陈旧矩形被命中/绘制。修法：控件不可见时把**整棵子树**的矩形清零后再返回。
- **坑③（`local` 是保留字）**：`let local = ...` 触发 `Warning [0035] reserved_keyword`（本工具链把 `local` 留给未来），零警告门禁下必须改名。
- **真窗口回证（坐标对齐不是纸面结论）**：示例加了一条 200×28 的演示带（四个 50×28 单元格，各自 `on_draw` 画色块、`on_pointer` 只数按下）。`xdotool mousemove --window <id> X 250` + `click 1` 在窗口坐标 200/250/300/360 各点一次 → 退出行 `NATIVE-WINDOW-OK band_h=1/1/1/1`（每格恰一次、无错格无重计），同轮 `frames=49`、`queue=0`、退出码 0。
- **本批未做（G6 余项）**：脏区增量重排 + 测量/内在缓存跨布局驻留；`App` 宿主（把 `win` 的原始事件翻成本层 `PointerEvent`/`KeyEvent`、以及 present 循环的收包方）随声明式层 G7 一起落。
- **验证**：`moon test -p NoahLiu/native-gui/core` 22/22（新增 7 条：绝对矩形折算含父 padding、命中取最深/后画优先/出界与零尺寸与隐藏不命中、指针本地化与三级冒泡与消费即停、带偏移树的本地坐标 (12,45)→(12,15)、滚轮冒泡到容器且出界不路由、按键按焦点 id 定位并冒泡且隐藏后不可达、绘制遍历的平移与裁剪（子控件越界部分不留色）+ 隐藏子树不绘制）；`moon check gui/{core,input,render,text,win}` 与示例 `--deny-warn` 零警告；yoga-mbt 81/81；全仓红点仍 287 errors / 68 warnings。

### MoonBit 原生 GUI 栈 · `sys` 起包（JSON 解析器平移 + 本包自建测试）

- **落点**：新栈的系统能力包按方案 §2 命名 `sys`。第一个资产是零依赖 JSON 解析器——master 线 `yue/vscjson.mbt` 整段搬入（公共名 `VscJson`/`vsc_json_parse`/`vsc_json_get`/`vsc_json_str`/`vsc_json_int64`/`vsc_hex_val`/`vsc_codepoint_at` 一律不改，消费方只把包前缀从 `@yue.` 换成 `@sys.`），搬完根包少一个文件，红点数不变（该文件本就无错）。
- **覆盖补齐**：旧链路里这个解析器**没有独立测试**（覆盖散在 `vscode_history`/`browser_bookmarks` 的用例中），按「新栈每包自建 wbtest」的基线补 7 条：标量与类型门、Int64 毫秒时间戳精度、嵌套结构链式取值、字符串转义（常规 / `\u` / 代理对 / 孤立代理→U+FFFD / 未闭合 / 坏 `\u`）、9 条语法错误全拒 + 松散空白对照、GeoJSON 取点路径、十六进制与码点助手。
- **两条实测口径（写测试时踩出来的）**：① 本工具链的 `String.unsafe_get(i)` 返回的是 **UTF-16 码元**而不是码点——`vsc_codepoint_at("😀", 0)` 给 `(0x1F600, 2)`，这个「代理对合并」助手存在的意义正在于此；② 整值浮点转 Int64 的 2^53 门是拿**取整后的 double 值**判定的，`9007199254740993.0` 这个字面量本身在二进制里就落到 2^53，所以照样放行；要断「超范围拒绝」得用 `1e20` 这一类量级。
- **验证**：`moon test -p NoahLiu/native-gui/sys` 7/7；`moon check sys --deny-warn` 零警告；全仓红点仍 287 errors / 68 warnings。

### MoonBit 原生 GUI 栈 · App 宿主与 `TextEditorHost` 收口（`core/app.mbt`）

- **分层落点**：宿主放 `core`（方案 §2 把 App/Window、脏区重绘划给 core），一处收齐「窗口 + `Loop` + 控件树 + 输入法通道 + 上屏」，示例与组件不再各自抄一遍循环。编辑器接缝做成**焦点控件上的五个回调**（`on_key` / `on_commit` / `on_preedit` / `im_context` / `im_cursor`）而不是一个 host 对象——因为 `input` 已经依赖 `core`，core 反向 import input 会成环；G5b 记档的四签名（`process_key`/`commit`/`preedit`/`set_cursor_rect`）逐一对应，只是宿主从「持有一个 host」换成「按焦点投回调」。
- **原始事件口径**（`win` 的 `code` 来自 C 侧 `WmEv`）：`0/1` = 键按下/抬起，`2/3` = 按钮按下/抬起，`4` = 指针移动，`5` = 滚轮。两个数据槽按 C 的 `dx/dy` 命名传到 MoonBit：按钮号走 `button`（dx），滚轮纵向走 `axis`（dy，正=上滚）；`dx` 在滚轮事件里是横向。翻译单独成 `raw_to_event` 是为了无头可测（宿主其余部分要真窗口）。
- **点击接管焦点做成控件树函数**：`Widget::focusable_at(x,y)` 取命中链上从最深向上第一个声明了 `focus_id` 的控件，宿主在 `Down` 时据此改焦点栈（与 Web 同源：点表单控件即聚焦它），控件不必自己碰焦点栈；已在该控件上时**不做任何输入法动作**，否则在同一个框里点一下就把正在拼的字打断了。
- **输入法两条实测（本批真机踩到，都是「串框」）**：① 一个窗口只有一个 `GtkIMContext`，逻辑焦点换控件时必须 `gtk_im_context_reset`，否则前一个框攒下的组合串会在后一个框 commit 出来（注入 `a b Tab c` 实测 `t2='第二个框岸边'`，`岸`/`边` 明明是在第一个框打的）。新增 `Window::im_reset()`（extern + 真实 stub + portable stub 三处同批）；只在**焦点真的换了**那一瞬调，每拍调等于一直打断组合（G5 那条「绝不调 reset」说的是每拍）。② 光 reset 不够：提交文本是在按键事件处理当期就落进 C 侧缓冲的，脚本连发键时 Tab 事件排在若干 commit 之后，晚一拍排空就会把旧控件的提交投给新控件。所以切换点必须先按**旧** id 排空 commit、清旧组合串、再 reset（`App::flush_ime_for_switch(prev)` 在改焦点栈**之前**调用）。修复后同一注入序列 → `t1='hello岸边' c1=11 t2='第二个框曾'`，各归各框。
- **工具链四条**：① `loop` 是保留字（App 的调度字段叫 `sched`，`local` 上一批已记）；② `PointerKind` 带闭包字段派生不出 `Eq`，判定用 `match`；③ `FocusStack::focus(id)` 是**改**焦点的 setter，绘制里判高亮必须用新增的只读 `is_focused(id)`——示例原先在 `on_draw` 里调 `focus(id)`，每帧重绘都把焦点抢给最后画它的那个控件，退出行 `focus=3` 而第一个框永远收不到键，这类「查询/赋值歧义」靠命名与只读助手挡；④ 用脚本改文件时 `str.replace(...,1)` 不命中是**静默失败**（本批开工时那 8 个 `Widget has no field` 错误就是这么来的），必须断言命中次数。
- **注入手法（沿用并补两条）**：键盘必须走 XTEST，即 `xdotool key` **不带** `--window`（带 `--window` 是 XSendEvent，GTK 直接丢弃，见本文「GUI 自动化」条）；鼠标则要写成一条原子命令 `xdotool mousemove --window <id> X Y click 1`——拆成 `mousemove --window` 后单独 `click 1` 本轮实测 `clicks=0`（与既有的「XFCE click-to-focus 拦合成点击」同源）。另：测「字母必须原样进框」的链路时要把 IM 桥摘掉（`env -u GTK_IM_MODULE -u XMODIFIERS`），否则本机 fcitx5 双拼会把 `a b` 变成中文；反过来验输入法串框问题时**保留**默认环境才是有效对照。
- **坐标判据要与被点的布局同帧取（2026-10-12 靠这条撤掉一条假缺陷）**：一条「命中区与渲染错位」的缺陷记录（点某按钮的渲染中心却触发邻居、越靠右偏得越多）复测时不成立——按同一次运行的截图逐盒量出边界再取中心，七个中心全部命中自己。错在**取坐标的那一刻**：截图来自另一轮布局（同一示例在宿主提供整页滚动前后，按钮行整体位移过几十像素），拿旧截图的坐标点新布局当然会「偏」，而偏移量正比于横向位置，看着就像越靠右越歪。口径：注入点击的坐标必须与判据截图取自**同一次运行、同一次布局**（先 `xwininfo` 取窗口原点、再截同一窗口的图量盒边界，然后才点）；命中与绘制在本栈同源（都读 `Widget::rect`，滚动只是让 yoga 布局带上位移），所以「两者错开帧」在代码侧没有通路，出现这种症状先怀疑测量。
- **验证**：`moon test -p NoahLiu/native-gui/core` 28/28（新增 6 条：原始事件翻译表、commit 沿祖先链冒泡且消费即停、preedit 只投焦点控件不冒泡、`im_context`/`im_cursor` 可达性与隐藏后不可达、无 `im_context` 声明的控件不参与输入法轮次、`focusable_at` 取命中链上最近可聚焦者且隐藏不可达）；逐包（core/input/render/text/win/icons/theme/sys）`--deny-warn` 全零警告；yoga-mbt 81/81；全仓红点仍 287 errors / 68 warnings。新示例 `examples/native-app`（GUI 侧同类测试的累积页）：冒烟退出码 0、`frames=49`；注入回证 `a b Tab c` → `t1='helloab' c1=7 t2='第二个框c' focus=2`（打字 + Tab 环绕），点按钮中心 (116,128) → `clicks=1` 且焦点接管，持焦点回车 → `clicks=2`，点文本框最左端（窗口 x=17 → 控件本地 x=1）→ caret 归 0、再打 `z` 得 `t1='zhelloab' c1=1`——**「点击定位」这条此前只能靠肉眼的链路首次客观验通**。仍需用户目视：caret 闪烁观感、preedit 下划线、候选窗是否贴组合串末尾。

### yoga-mbt · 脏区增量重排 + 缓存跨布局驻留（YG3e，解 YG3d 留下的 40% 成本）

- **三条判据，缺一不可**：① **变更通知面**——39 个样式 setter 加 `append_child`/`clear_children`/`set_measure`/`set_baseline`/`set_pixel_grid`，第一件事都是 `mark_changed(self)`（全局时钟 +1 并记进本节点 `rev`）；漏标不会报错，只会**安静地拿旧结果**，是最难查的一类 bug。② **子树版本**——`calculate_layout` 入口 `scan_subtree_rev(root)` 自顶向下给每个节点写「子树内最大 rev」，这是 O(节点数) 的整数比较、不做任何测量与数学；有了它「这棵子树自上次布局以来没变」= `subtree_rev == laid_rev`，**不需要父指针**（父指针与 `children` 成引用环，本工具链回收处理不了环，长驻 GUI 里就是稳定泄漏）。③ **入参指纹**——`layout_into` 记上次的 `(avail_w, avail_h, pinned_w, pinned_h)`，跳过要求版本与指纹**都**对上：父容器重排后给子项的可用空间/钦定尺寸可能变，这时子树自身没变也得重算。
- **两条实现坑**：① 复用值必须记 `layout_into_impl` 的**返回值**（像素网格取整前），不能记 `layout_width/height`——后者被 `round_to_grid` 后处理改写，拿它复用会让带网格的树每轮往下漂（`round_to_grid` 仍无条件遍历整树，取整是幂等的）。② 缓存作废从「入口整树清」改成按版本门：`cache_fresh(node)` 见 `cache_rev != subtree_rev` 才清该节点两份缓存——深叶变更会连带祖先的**内在尺寸**缓存失效，靠子树版本而不是回溯清理；另加 `cache_slots = 16` 上限，连续改可用宽时「丢复用不丢正确」，否则每个宽度一条缓存就是无限增长。
- **bench 拆成三场景**（同一份程序，`git archive HEAD` 取改前引擎对照，同机 release，µs/轮 @1121 节点）：`steady` 同参数重复 **3652 → 4**、`one_leaf` 每轮改一个叶子 **3656 → 78**、`resize` 每轮换根宽（全树重排）**3664 → 3602**（全量路径无回归）。debug 同步量 7622→14 / 7570→176 / 7572→5940。**三场景校验值（探针布局结果之和）改前改后逐位相同**——这是跨引擎的独立正确性信号，比任何自说自话的断言都硬。计时用 `moonbitlang/core/env` 的毫秒时钟，只进 bench 包，引擎本体保持零依赖。
- **对宿主的意义**：`App::paint_frame` 每帧 `root.relayout(w, h)` 走的就是 `steady` 那条路（干净整树 4µs/千节点），「每帧重排」因此在 GUI 里成立；G7 把文本 `set_measure`/`set_baseline` 接上后，`one_leaf`（改一行文本）就是实际形态。
- **测试取向与四条工具链写法**：增量布局的唯一正确性标准是**「与同状态从零全量布局逐节点相等」**，10 条用例一律按这个断言（参考树按同一状态新建、只布局一次），不比对中间状态。踩到的：① 同包内顶层标识符必须唯一——测试里的 `snap` 与 `algorithm.mbt` 已有的取整 `snap` 撞名，报的是 `toplevel identifier declared twice`（不是普通重名提示）；② C 式三段循环的第三段只接受 `i = i + 3`，写 `i += 3` 直接语法错；③ `let a = []` 的空数组在零警告门禁下会报 `unresolved_type_variable`，要写全 `let a : Array[(Double, Double, Double, Double)] = []`；④ `UInt64` 的时长再 `.to_double()` 传给收 `UInt64` 的函数会类型门住，单位换算放进被调函数里做。另有一条写法规矩：reparent 用例先按「新父左边距 50」断言 `left == 50`，实际是 **150**（行内 `box_a` 宽 100 + 50 边距）——改成与最终结构直接新建的参考树比对，而不是猜数。
- **验证**：`moon test -p NoahLiu/yoga-mbt` **91/91**（81 条既有零回归 + 10 条增量：同参数复用不改结果、单点变更与全量一致、兄弟子树不重测、根宽变化与参考一致、像素网格 + 跳过仍贴格、隐藏重显不留旧坐标、自身样式变更作废本节点内在缓存、结构变更不被藏、子树跨父搬移、越过缓存槽位上限每轮都等于全量）；`moon check src --deny-warn` 与 `moon check bench --deny-warn` 零警告；主包不受影响（core 28/28 等全绿、`--deny-warn` 零警告）、全仓红点仍 287 errors / 68 warnings。

### MoonBit 原生 GUI 栈 · 字体族枚举与回退 + 多字体混排行高（`text` 第三批）

- **枚举的实现形态**：C 侧一次性把族表建进进程内缓存（`pango_font_map_list_families` → **排序 + 相邻去重** → `\n` 拼接的 `GString`，`g_string_free(out, FALSE)` 交出所有权），MoonBit 按「读长度 + 逐字节读」取回（本工具链不能把可写缓冲交给 C）。排序不是洁癖：fontconfig 的枚举次序随装载顺序变、同一族还会带多个 locale 名出现多次，不排就无法写任何稳定断言（本机 682 条）。
- **可用性判定放 C**：`pt_family_available` 在缓存里逐行 `g_ascii_strncasecmp`——族名比较不区分大小写是 fontconfig/Pango 的口径，放 MoonBit 侧就得自己实现同一套 ASCII 折叠，容易与后端不一致。
- **回退口径三条**：① 通用族 `serif`/`sans-serif`/`monospace` 一律算可用（它们不在枚举表里，由 Pango 解析到具体字面族）；② `resolve_family(candidates)` 按 CSS `font-family` 列表取第一个可用者，全不可用退 `""`（空族名就是「跟随系统默认」，测量/绘制都按它走）；③ `Font::resolve` 只在族名**不可用**时才退空族名，可用名与通用族原样保留——保留请求名才量得到那一族的度量。
- **一条实测纠正了预期**：不可用的族名并不会让测量失败，Pango 直接退默认族照样给数（`line_height_multi([base, Font::new("不存在的族", 13.0)])` 与给 `""` 的结果一致）。所以「回退」的价值在**行高口径确定 + 族名可诊断**，不是防崩溃；写测试时按「会 None/会炸」去假设反而会写出假绿断言。
- **混排行高定案**：行盒 = 逐字体上抛的 **max ascent + max descent**（每个 inline 盒按自己的字体贡献，两侧最大值可以来自不同字体），**不是**「取字号最大的那一份的行高」。实现上把 `pt_font_line_height` 已有的 ascent/descent 拆成 `FontMetrics`，`line_height_font`/`line_ascent_font` 改成它的投影（顺手去掉两处重复的 C 调用拼装），`line_height_multi(fonts)` 做聚合，`AttributedText::line_height()` 把基准字体与每条区间字体一起喂进去。断言取两条硬性质：行高**盖得住** `get_bounds_for` 的绘制高度；基准字体的行高**装不下**区间里 28px 的内容（盒矮了会裁字，这正是组件层最需要的判据）。
- **工具链六条**（都是本批写测试时踩的）：① **MoonBit 的 `String` 序是 shortlex——先比长度、再比码元**，`<` 与 `compare` 都**不是**字典序（`"Agency FB" < "Aharoni"` 为假、`"b" < "aa"` 为真）；要字典序用 `String::lexical_compare`，要忽略大小写用 `compare_ignore_ascii_case`。族表断言就是踩在这上面：C 侧明明已按字典序排好，`list[i-1] < list[i]` 大面积假红。② `Int::to_char()` 返回 `Char?`（要 `unsafe_to_char`），拼进字符串会得到 `"Some('x')"` 这种静默错值（编译期只有一条 deprecated 警告）。③ 本工具链的 `Buffer` 没有 `push`/`push_char` 可用名（写字符是 `write_char_utf8`），短串直接 `+=` 更省事。④ `Array[Byte]` 没有 `freeze`/`to_fixed_array` 通往 `FixedArray[Byte]`，要递给 C 当 `Bytes` 读就一开始用 `FixedArray::make(n, b'\x00')` 按下标写。⑤ `@utf8` 的包路径是 `moonbitlang/core/encoding/utf8`，写成 `moonbitlang/core/utf8` 报 `Cannot find import`。⑥ MoonBit 没有单引号字符串（`''` 是 lexer 错）。
- **验证**：`moon test -p NoahLiu/native-gui/text` 28/28（新增 8 条：族表非空/有序/去重/无分隔符、可用性含大小写翻转与通用族与空名、`resolve_family` 取第一个可用与全不可用退空、`Font::resolve` 与 `resolve_fonts` 保留字号字重样式、`font_metrics` 与既有两个口径同源且 28px 升距大于 13px、`line_height_multi` 的聚合规则与顺序无关且幂等、`AttributedText::line_height` 里颜色区间不掺和而字号区间掺和、行高盖得住绘制高度）；`moon check text --deny-warn` 零警告，逐包全零警告；core 28/input 10/render 40/icons 4/theme 7/sys 7/yoga-mbt 91 全绿；全仓红点仍 287 errors / 68 warnings。`examples/native-app` 加字体行（同段文字两个盒子，盒高分别取基准与混排 `line_height()`，右盒 visibly 更高）：冒烟退出码 0，状态行 `fam=682 use='monospace' lhm=42`；同轮 xdotool 注入序列结果与上一批逐字段相同（`clicks=2 t1='zhelloab' c1=1 t2='第二个框c' focus=1`）。**待用户目视**：新增字体行里右盒是否把 28px 的字完整包住、左盒没有多余空白。

### MoonBit 原生 GUI 栈 · 声明式地基（`Node`/`mount`/Store/signals/relink 跑在 Widget 上）

- **换的只有一件事**：master 的 `Node { mount : (View) -> View }` 变成 `Node { mount : (Widget) -> Widget }`——「构造器只建树、mount 才实例化控件并挂到父控件」的语义与「children 天然异构」的存在类型形态一字不改。地基件：`node_of`（已有控件包成节点）、`node_of_new`（新建 + 配置回调，回调**返回控件**，方便链式再建子树）、`mount_children`、`App::mount(children)`（内容入口，挂完标一次脏）。
- **relink（重挂）三条定案**：① **原位替换**——新一代先挂到 parent 尾部，再 `move_child` 挪回旧一代原先的下标，兄弟项顺序与坐标不受被换掉的这项影响；为此给布局引擎补了 `Node::insert_child(index)` / `Node::remove_child_at(index)`（越界钳制 / 越界返回 None 且不改树），控件层补了 `Widget::insert_child` / `remove_child` / `index_of` / `move_child`（控件表与节点表两层同步，摘除按 `Widget.id` 认身份——带闭包字段的控件比不了 `==`）。② **旧链路 Windows 的两条规避不需要**：master 的 `bind_node` 要 `post_task` 推迟一拍 + 重挂后 `refresh_layout` 整窗重算，防的是 native 侧 remove+add 之后 yoga 根不重算、hit-test 恒命中旧矩形（真机实证「点一次后全窗点击失效且不可逆」）。本栈的命中矩形每帧从布局结果重取（`App::paint_frame` → `relayout` → `collect_abs`），没有那个洞——注入回证：连点三次声明式行之后再点按钮，计数照常 +1。③ **每一代订阅进回收袋**：重建前 `sub_bag_discard(gen)`、挂载期 `sub_bag_begin/end` 收本代，死订阅不随重建次数累积；顺带的性质是**嵌套 `bind_node` 也正确**——内层在自己的 `mount` 里注册的 `sig.subscribe` 落在外层袋内，外层换一代时整袋退场。
- **重绘回路**：`set_repaint_hook` / `invalidate()` 是**进程级单槽**，`App::new` 装自己的 `schedule_paint`（置脏 + `@win.wake()`）；没装钩子（无头测试）时 `invalidate()` 空操作，组件层因此可以无条件调。已知限制：一进程一宿主，多窗口要等宿主层能「按控件找所属 App」再升级——当前没有多窗口消费者，不写猜测性实现。
- **平移纪律**：信号内核与 `Store` 自 master `yue/signals.mbt` / `yue/store.mbt` 逐行搬进 `core/signal.mbt` / `store.mbt`（本就零平台依赖，公共名 `Signal`/`Store`/`batch`/`sub_bag_*` 一律不改），19 条既有测试整段带过来（自动依赖收集、条件分支只依赖实际读到的信号、钻石依赖收敛、batch 合并、订阅句柄精确退订、袋内整代退订 + 无袋退化）。
- **两条写法坑**：① 同包多个 `_wbtest.mbt` **共享顶层助手名**，重复定义不报 `declared twice` 而是让**先定义的那个变成 unused**（我在 `node_wbtest.mbt` 里重写了 `sized`，`widget_wbtest.mbt` 那份立刻报 `Unused function 'sized'`）——写测试前先 grep 同包已有助手，别造第二个。② `node_of_new` 的配置回调若声明成返回 `Unit`，闭包体里用 `sized(w, ..)` 这类返回控件的助手会直接类型不匹配；返回 `Widget` 既省掉 `let _ =`，又允许回调里再建子树。
- **验证**：`moon test -p NoahLiu/native-gui/core` **53/53**（28 既有 + 19 平移信号/Store + 6 条声明式：`mount_children` 顺序与坐标、`bind_node` 原位换棵且兄弟项坐标跟随、旧代订阅整袋退订（重建 5 次源上仍只有 1 条）、重挂后 parent 里始终只有一棵不留半棵、`swap_node` 预建两棵只改显隐且隐藏那棵矩形清零、无钩子时 `invalidate` 空操作）；yoga-mbt **92/92**（新增原位增删：摘中间项再插回与参考树逐节点一致、越界不改动树）；逐包 `--deny-warn` 全零警告，全仓红点仍 287 errors / 68 warnings。真窗口回证（`examples/native-app` 新增声明式行，点击即 `Store.update` → 原位重挂）：`decl=3 kids=6/6`（根子项数恒定，说明没有泄漏也没有重复挂），同轮 `clicks=1`（重挂三次后按钮命中照常）、`t1='hellox' c1=6`（Tab 环绕与打字照常），退出码 0。**待用户目视**：声明式行底色随点击奇偶切换（证明确实换了一棵新树，而不是只改文本）。

### MoonBit 原生 GUI 栈 · 控件交互地基（悬停/按下归属、指针捕获、回调不得自捕获）

- **状态归宿主，控件只读**：`Widget` 加 `hovered`/`pressed` 两个字段，由宿主在每次指针事件里按命中与捕获统一维护（`set_hover(id)` / `set_press(id)`，只在归属**变化**时各走一趟树），控件在 `on_draw` 里直接读。旧链路的 `hover_group` 是轮询式（libyue 不给 move 事件，只能定时问鼠标在哪），本栈有完整路由，所以进入与离开都是事件：悬停者换了就给上一个补发 `Leave`——「只有进入没有退出」的悬浮提示形态在这里不成立。
- **按下即进入捕获期**：分发决策做成纯函数 `route_pointer(root, ev, hover_id, capture) -> (新悬停, 新捕获, 是否消费, 是否变了)`，`App` 只保存并写回两个状态。规则：`Down` 的命中者标 pressed 并成为捕获者，之后 `Move`/`Up` 一律投给捕获者（沿它到根的路径投递，本地坐标照常折算）；`Up` 清按下态、解除捕获，并**按抬起位置**重判悬停；捕获期悬停不动。为什么必须做：不做捕获，指针一离开控件就再也收不到 `Up`——按下态卡死只是 mild 症状（实测表现是控件常驻高亮），拖选与「拖动插入点」这两条输入框语义直接没有依据。等价于 Web 的 `setPointerCapture`。
- **回调不得捕获控件自身（引用环纪律）**：`on_draw` 首参改成 `Widget`、`im_cursor` 改成收 `Widget`，控件读自己的 `rect`/`hovered`/`pressed` 由参数拿，句柄不再进闭包。原因是本栈控件**持有**自己的回调表，闭包再捕获控件就是引用环，计数式回收断不掉环；一次性示例看不出来，`bind_node` 每重挂一次漏一棵树就是稳定泄漏。示例与测试的全部绘制回调随签名改完。
- **一条被实测纠正的预期**：`display:none` 的兄弟项会**上顶**（列容器 auto 高按可见项算），所以「隐藏项原来占的那片区域」命中的是顶上来的兄弟而不是父容器——我第一版按「命中父控件」下断言，`route_pointer` 直接给了兄弟的 id。含义是组件层不必为隐藏项额外清理悬停态，位置自然被活着的那一项拿走。
- **注入手法补一条**：拖动序列写成 `xdotool mousemove --window <id> X Y mousedown 1` 原子按下，随后 `xdotool mousemove --window <id> X2 Y2` 移动、`xdotool mouseup 1` 松开（不带 `--window`，XTEST 在当前点位松开）。实测带内按下、带外松开，捕获带仍收到抬起。
- **验证**：`moon test -p NoahLiu/native-gui/core` **59/59**（新增 6 条：悬停跟随与 `Leave` 补发、捕获期移动与抬起都投给按下者且悬停不动、点在空白处不进捕获也不炸、隐藏控件不参与悬停且兄弟上顶后命中跟着变、`by_id` 与 `dispatch_pointer_to` 按身份投递（坐标不参与判定）、滚轮沿用同一冒泡规则）；逐包 `--deny-warn` 全零警告，yoga-mbt 92/92，全仓红点仍 287 errors / 68 warnings。真窗口回证（`examples/native-app` 新增「捕获带」，绘制态直接读 `w.pressed`/`w.hovered`）：带内按下 → 拖到 (200,245) → 拖到 (300,100) 松手 → `band=d1/u1/m3`（**在带外松手仍收到抬起**），同轮按钮 `clicks=1`、声明式行 `decl=2 kids=7/7` 照常，退出码 0。**待用户目视**：拖动过程中带子保持按下色（橙）、离开后恢复常态而悬停色不再跟着指针跑。

### MoonBit 原生 GUI 栈 · 组件层首批（新包 `ui`：文本测量回灌布局 + 容器/标签/分隔线/图像/图标/按钮）

- **为什么不写进 `yue/components`**：那个目录是旧链路的组件实现（引用 `@yue` 根包与 `@declarative`，属全仓 287 个红点的主要来源）。新栈每批只把**要保留的语义**重做，若与旧文件同包，`moon check <包> --deny-warn` 这条分包门禁就永远无从执行（旧文件的错会一起报）。故新组件层另起 `ui`，旧包按批替换/删除，G7 收口时一并结算。
- **文本测量回灌布局引擎**（G7 欠的那块）：`attach_text_measure(w, src)` 给节点同时设 `set_measure`（尺寸来自 `measure_font`）与 `set_baseline`（`line_ascent_font`），于是文本第一次能参与 `align-items: baseline` 的真实排布，`label` 的宽高也就是 Pango 给的真尺寸。两条被实测纠正的断言：① **列容器默认 `align-items: stretch` 会把标签宽度拉到整行**——要看出测量给的真宽度，父项必须 `FlexStart` 或标签自带显式宽（我第一次直接断言测量宽，拿到的是 240 而不是 70）；② 基线对齐时**顶边差 = 两个 ascent 之差**（大字号更靠上），我把差写反过一次。min-content 探询（请求轴 `Some(0.0)`）暂按「不受约束」处理，属记档近似（等接进省略号自适应再细化）。
- **指针回调也要收控件本身**：`on_pointer` 首参改成 `Widget`（与 `on_draw` 同一条引用环纪律）。按钮需要 `self.rect` 才能判「松开是否仍落在自己范围内」——捕获期保证按钮一定收得到在别处松手的那次 `Up`，但只有拿到自己的矩形才分得清内/外。
- **两处与 master 的命名分岔**（记档，不做兼容层）：① `button(type="text")` 的 `type` 是 MoonBit **保留字**，作参数名直接语法错，换成 `kind : ButtonKind`（`Primary`/`Border`/`Text`）；② 禁用态配色暂用 `fill_hover` 底 + `text_secondary` 字，真正的 disabled 色板随主题批补进 `Theme`（现在 20 个字段里没有它）。
- **主题跟随做成进程级单订阅**：组件挂载时调 `watch_theme()`（幂等），主题变化 → 一次 `invalidate()`。不做按控件订阅：`invalidate` 本就是全局的，逐控件订阅会让每次重挂都留下一条死订阅，换不来任何精度。颜色一律在 `on_draw` 里现取（不在建树时固化），主题切了下一帧就是新色。
- **文本绑定的对应物**：`label_dyn(sig : Signal[String], ...)` 就是旧链路 `bind_label` 的位置——就地改文本 + 重设测量回调（节点标脏）+ 请求重绘，不重建子树；订阅退订经 `@core.sub_bag_register` 进本代回收袋（该函数为此从包内提到公开，组件层的清理都走它）。
- **验证**：新包 `moon test -p NoahLiu/native-gui/ui` 7/7（标签尺寸来自测量且随信号重测、两字号基线对齐的顶边差、按钮松开在内/在外两种结果、禁用态不消费也不回调、悬停态换色且文本仍落在盒内、容器/分组/分隔线几何与横线撑满、图标按尺寸占位并真出像素 + 图像缺文件不崩）；**逐包**（core/input/render/text/win/icons/theme/sys/ui）`--deny-warn` 全零警告，core 59/input 10/render 40/text 28/icons 4/theme 7/sys 7/yoga-mbt 92 全绿，全仓红点仍 287 errors / 68 warnings。真窗口回证：`examples/native-app` 底部新增一行全用 `@ui` 构造器（label + 竖分隔线 + icon + `加一` 按钮 + `禁用` 按钮），窗口加高到 420×372；xdotool 注入 `mousemove --window 135 278 click 1` 两次 → `comp=2`，再点禁用按钮那一段 → 计数不涨且 `decl=0`（禁用态确实不消费事件），`kids=8/8` 根子项数在多次重挂后仍恒定，退出码 0；同轮既有回证（打字/Tab/点击定位/捕获带）未退化。**待用户目视**：组件行的悬停/按下色、竖分隔线是否真的撑满行高、图标与文本在同一行的基线观感。

### MoonBit 原生 GUI 栈 · 表单控件首批，以及两处「只有截图才看得见」的渲染缺陷

- **缺陷一：文本无视控件原点**。文本层（`pt_draw*`/`rt_draw`）一直是「拿 `Bitmap.data` 自建 surface 画字」，那条路径**不经过 Painter 的 CTM 与 clip**——于是宿主每层 `translate + clip_rect` 对文字完全无效，真窗口上所有控件的文字都挤在窗口左上角（截图见 `控件首批` 前后对照）。修法是把 Cairo 会话交出去：render 桩新增 `void *cr_session_context(int64_t id)`（返回该会话的 `cairo_t*`），text 桩新增 `pt_draw_box_cr` 与 `rt_draw_cr`，在**调用方的上下文**上 `cairo_save → set_source_rgba → move_to → pango_cairo_show_layout → cairo_restore`（save/restore 保住调用方的 source 与裁剪，画完不污染）。MoonBit 侧对应 `Painter::cairo_id()`、`@text.draw_box_at / draw_at / draw_text_at`、`AttributedText::draw_at`。旧的 `draw_to/draw_in_box/draw(target,…)` 保留（离屏自绘、图表缓冲还要用）。
- **缺陷二：嵌套绘制重复累加偏移**。`Widget::paint` 逐层 `p.translate(self.rect.x, self.rect.y)`，而 `rect` 是**绝对**矩形——于是第二层起把祖先的偏移又加了一遍（第二行的文字直接掉到窗口外）。改成 `paint_at(p, ox, oy)`：只平移「自己相对已平移原点」的差值，并把本控件的绝对原点传给子层。
- **为什么前面几批没发现**：批次1 的绘制用例里中间那层控件正好在 `(0,0)`，绝对=相对，测试自然通过；示例的状态行只报计数与文本，不报像素。**结论：GUI 的「退出码 0 + 状态对」不等于画面对**——累积验证页从此留两条机器可查的路：`NATIVE-APP-RECTS` 几何行（每个根子项的 `x,y,wxh`，注入坐标按它取，不再靠猜截图）+ 需要看画面时 `import -window <id> x.png` 截图核对。
- **跨静态库的链接**：text 桩引用了 render 桩的符号，`moon test -p .../gui/text` 在**链接期**报 `undefined reference to cr_session_context`（编译期无感）。链接参数只在 `scripts/prebuild.py` 改：text 的 `link_flags` 追加 `-lrender_cairo_stub`（消费者在前的顺序即可）。
- **禁用态必须是单元而不是布尔**：测试抓到步进器的真 bug——`disabled` 若在建树时固化进闭包，值走到边界后 `-`/`+` 的禁用态仍停在挂载那一刻。改为 `Enabled { mut off : Bool }`，绘制与事件每次现取；组合控件（复选行、开关、步进器两侧）共用同一个单元，`set_disabled(cell, v)` 随时改。
- **拖动状态由组件自持**：滑块用 `dragging : Ref[Bool]` 而不是读宿主的 `pressed`——宿主的 `pressed` 只在真实事件流里置位，组件在**任何**投递路径下都要能把拖动做完（否则无头用例根本测不到拖动）。
- **两条坐标口径（本批 4 条用例一起踩的）**：① `dispatch_pointer` / `dispatch_pointer_to` 收的是**窗口坐标**，投递时才折算本地——测试里传局部坐标会静默不命中（表现为「点了没反应」）；② 按坐标命中的 `dispatch_pointer` **投不进来自控件外**的拖动，出界移动必须走 `root.dispatch_pointer_to(w.id, ev)`（等价宿主的捕获期投递）。
- **工具链写法七条**：`match` 多主语必须写成元组 `match (a, b) { (Some(x), y) => ... }`；`Double::clamp` 要 labelled `min=/max=`；`Int::to_char()` 返回 `Char?`（要 `unsafe_to_char`，否则静默拼出 `"Some('x')"`）；`String.split` 给的是 `Iter[StringView]`、`StringView::to_string` 已弃用改 `to_owned`；`Array[Byte]` 没有 `freeze`/`to_fixed_array`，要递给 C 当 `Bytes` 就一开始用 `FixedArray::make`；`Option[(A, B) -> R]` 结尾的 `]` 丢了会报「unexpected token infix」这种莫名错；跨行续写不能把 `+`/`&&` 放行首（MoonBit 按行尾断句），`type` 是保留字不能作参数名。
- **验证**：`moon test -p .../gui/ui` 15/15（新增 7 条：复选点击/再点/出界不触发/禁用不消费、单选组按项写值且点已选不改、开关尺寸固定且绘制跟随 Store 现值、滑块按下取值+出界拖动+步长吸附+禁用不消费、进度条按值填充、步进器夹取且边界自动禁用、Store 订阅随回收袋退订（重挂 5 次后 `sub_count=0`，不套袋则常驻 1 条）；另加两条渲染回归：文本随控件原点落位并被裁剪、富文本经会话绘制落位在平移后的盒内）、`text` 29/29；逐包 `--deny-warn` 全零警告，core 59/render 40/icons 4/theme 7/sys 7/yoga-mbt 92 全绿，全仓红点仍 287 errors / 68 warnings。真窗口注入（坐标取自 `NATIVE-APP-RECTS`）：`form=true/false/90/1`（复选切真、开关切假、滑块拖到 90 且按步长 5 吸附、步进 +1），`decl=3 kids=9/9`（声明式原位重挂未退化），`band=d3/u3/m3`（三次带外松手都收到抬起），`clicks=2 t1='zhelloab' c1=1`（打字/Tab/点击定位），退出码 0；截图复核：标题、两个输入框、计数按钮、混排行高盒、组件行与表单行全部落位正确。

### MoonBit 原生 GUI 栈 · 输入框全语义（`ui/entry.mbt`）

- **形态**：文本状态的唯一权威仍是 `@input.Editor`，组件不另存一份；`Store[String]` 只是它的对外投影——编辑后回写 Store，Store 被外部 `set` 时经订阅回灌内核（`subscribe_id` + 回收袋退订，重挂不留死订阅）。与宿主的接缝就是地基那五个回调，输入法四条件由 `App::pump_ime` 统一满足，组件只提供 `im_context`（已提交文本 + 字节 caret）与 `im_cursor`（候选窗定位矩形）。
- **焦点高亮改由宿主同步**：新增 `Widget.focused` 与 `Widget::set_focused_by_focus(focus_id)`，`App::paint_frame` 每帧画之前同步一次。原因与 `hovered`/`pressed` 同理——焦点栈只记 id，组件要的是「那个 id 是不是我」，让每个组件自己去问焦点栈既拿不到栈、又会把 `core` 的焦点结构漏进组件层。
- **只读白名单要按 keysym 族来写**：第一版按「65288..65300 是导航」放行，结果**退格（65288）被当成导航放过**，只读框照旧删字（测试抓到）。真实口径：方向键/Home/End/PageUp-Down 在 **65360..65367**，退格 65288、删除 65535 属编辑键。定案为「带 Ctrl/Shift 的组合、65360..65367、Tab 放行；退格/删除/可打印字符一律不吃」。
- **双击判定**：两次 `Down` 间隔 < 400ms 且位移 < 4px（时钟用 `@core.now_ms()`，是 `@win.now_ms()` 的转派）。**副作用要记档**：连续快速点击会被判成双击——无头用例里「按下-松开-再按下」验证拖动时，第二次按下实际走了选词分支，断言要按这个语义写。
- **CJK 选词是当前近似的点**：`is_word_byte` 把 `>= 0x80` 全算词内（与内核同口径），所以中文里双击会把**连续的整段中文**选中（真窗口实测：`组件框ab` 末尾双击选中 `组件框ab` 整段，替换后剩 `Q`）。ASCII 侧正常（空格分词，`组件框ab c` 双击只选 `c`）。要不要按 Blink 的词典分词收敛，等布局那套 Blink 对照手法排到文本时一并测，先记档不猜。
- **拖动选区**：按下记锚点，捕获期的 `Move` 用 `select_range(anchor, byte_at_x(x))` 扩选——指针拖出框外也连续（这是宿主捕获期的第二个消费者）；`Up` 结束拖动，之后再 `Move` 不跟手（用例断言 caret 不变）。
- **观测通道的取巧处**：内核句柄不外露（文本权威在组件里），无头用例改从两条公开面观测——`w.im_context()` 给「文本 + caret」，以及「打字会替换选区」这一行为本身（选区对不对，看替换后的文本）。比为了测试开一堆 getter 干净。
- **验证**：`moon test -p NoahLiu/native-gui/ui` **25/25**（新增 10 条输入框用例：键入回写 Store 与退格/undo、commit 落文本而 preedit 只进绘制、点击最左/最右定位、双击选词、拖动全选与松手不跟手、Shift+箭头扩选 + Ctrl+A/C/V 内部剪贴板、只读放行导航与复制、密码遮罩 Store 存原文、placeholder 有像素且 Store 为空、Store 外部改动回灌内核 + `focused` 由宿主同步）；逐包 `--deny-warn` 全零警告，全仓红点回到 287 errors / **68** warnings（中途一度 69，是测试里一个未用变量）。真窗口注入（`examples/native-app` 新增 `@ui.entry` 行，`focus_id=4`）：点进框 → 打 `ab c` → 末尾双击 → 打 `Q` → `Home`+`Shift+End`+`Delete`+`Ctrl+Z` → 状态行 `t3='组件框ab Q'`、`focus=4`，退出码 0；截图复核组件框落位与描边正常。**待用户目视**：caret 闪烁（组件的 `caret_on?` 由调用方时钟驱动）、preedit 下划线、候选窗是否贴组合串末尾。

### MoonBit 原生 GUI 栈 · 显示族首批（`ui/display.mbt`：标签 / 徽标 / 头像 / 分隔线 / 提示条 / 卡片 / 描述列表 / 空状态 / 结果页 / 折线进度）

- **与 master 的差一条（记档）**：CSS 风格的 `style=[("marginRight", 8.0)]` 通道还没接（随主题批的 style 通道一起做），这批只留**类型化**参数；语义色枚举 `SemanticType`（Primary/Success/Warning/Danger/Info）与 `type_color`/`type_light_color` 保留同名，色值现取 `theme` 的五档主色 + 五档浅色（主题首批已就位，不必新增字段）。
- **两条自绘组件的通用规矩（本批踩到并写进代码注释）**：① **绘制回调不改布局**——`statistic` 第一版在 `on_draw` 里 `set_width(按测量宽)`，等于让 paint 变成布局的写入方（同一帧内布局与绘制互相触发，且脏区增量重排的指纹判定会被自己搅乱）；宽度必须在挂载时按测量算定。② **控件高度要装得下自己的字**——折线进度的百分比列先按「和条同高 8px」占位，11px 的字被裁成半截（截图才看得出来）；文字类节点的高度至少给到字高，容器按最高子项撑开即可。
- **可关闭提示条的热区口径**：整条 alert 都消费按下（避免点击穿透到下层），但只在**右上角 24×24** 触发 `on_close`——热区判定用本地坐标（`ev.x >= rect.w - 24 && ev.y <= 24`），这条在捕获期下依然成立（松开一定回到本控件）。
- **验证**：`moon test -p NoahLiu/native-gui/ui` **33/33**（新增 8 条显示族：五档语义色互不相同且都是合法 hex、标签与徽标按内容定宽且超上限显示「99+」、头像首字符出像素、带文字分隔线整宽且两侧有线、提示条有描述时更高且关闭只在热区生效（非热区点击不计数）、卡片带标题多占两行（标题+分隔线）、描述列表行数按条目算、空状态/结果页真出像素、折线进度两列且填充随 Store 变化）；逐包 `--deny-warn` 全零警告，全仓红点仍 287 errors / 68 warnings。真窗口回证（`examples/native-app` 新增显示族区块，几何行给出坐标）：点提示条非热区 → `closed=0`，点右上角两次 → `closed=2`，同轮组件按钮 `comp=1`、`kids=11/11`，退出码 0；截图复核标签三色、徽标 7/99+/圆点、头像「刘」、「或」分隔线、提示条左侧色条与描述、进度条与百分比全部正常。

### MoonBit 原生 GUI 栈 · 显示族收尾（时间线 + 轮播，自转走宿主延时通道）

- **新增通道：进程级延时（`core/loop.mbt` 的 `set_timer_hooks`/`set_timeout`/`clear_timeout`）**。组件要的是「过一会儿跑一次」，不该知道自己属于哪个宿主，所以与 `set_repaint_hook` 同款进程级单槽：`App::new` 把两个函数转派给自己的 `Loop`（`timer`/`cancel`），组件只调 `@core.set_timeout(ms, f)`。**没有宿主时 `set_timeout` 返回 0 且不执行**——组件照常工作，只是不自动推进；无头测试于是可以自己装一条通道把回调拿到手手动派发，轮播的自排链因此能被确定性地测到（不必等真实时钟）。
- **轮播三条形态定案**：① 面板**全部预建**、切页只翻 `Widget::set_visible`（与 `swap_node` 同一理由：不销毁子树就不留悬垂回调，也不必重挂）；② 箭头悬停底色直接读**宿主维护的** `Widget.hovered`，master 那两条 `on_mouse_enter/on_mouse_leave` 在本栈省掉——交互态归宿主统一置位，组件只读；③ 悬停暂停靠本控件在**父链**上收到的 `Move`/`Leave`（事件从最深命中控件往上冒泡、第一个返回 true 者消费），因此若页面内容把移动与离开都吃掉，暂停就收不到信号——这条不是猜测而是路由规则的必然结果，故另开 `carousel_pause(handle, v)` 让调用方自己接管。
- **自排链的回收口径**：一次性延时 + 回调里排下一拍，句柄存进 `CarouselHandle.timer`；`carousel_stop` 既置 `running=false` 又 `clear_timeout` 取消待触发那次。测试实测到边界语义：stop 之后**已经在队里的那一拍仍会被跑一次**，但 `running` 兜底让它既不切页也不再排下一拍——所以「取消句柄」不能当唯一保险，`running` 标志必须同时存在。
- **时间线的竖线口径**（EP 原样）：首行从点心起、末行到点心止，中间行整条贯通；行高固定，绘制只写本地坐标（宿主逐层 `translate + clip_rect`，控件不必自己裁剪）。
- **两条工具链/测试实测**：① 无载荷枚举的同名构造器在跨类型字面量里会 `The constructor Primary is ambiguous`（本仓库 `ButtonKind` 与 `SemanticType` 都有 `Primary`），给数组字面量标注元素类型即可，别改成全限定名污染断言；② 指示点只有 8×8，注入点位按「行高一半」取到 `y+12` 就落到热区外，症状是「点了没反应」而**没有任何报错**——按坐标注入前必须回读该控件自己的 `rect`（本例几何行因此补了 `NATIVE-APP-CAR`/`NATIVE-APP-AUTO` 两行，直接给箭头、末指示点与自转面板的矩形）。
- **验证**：`moon test -p NoahLiu/native-gui/ui` **37/37**（新增 4 条显示族收尾：时间线逐行等高 + 首行点上方无线/末行点下方无线/点与线不同色、轮播预建三页只显当前页 + 箭头与指示点切页 + 越界回绕、自转走宿主通道（暂停不前进但链不断、stop 取消待触发）、空条目不崩）；`moon test -p NoahLiu/native-gui/core` **60/60**（新增 1 条：未装通道时 `set_timeout` 返回 0 且不执行、装完后 `set_timeout`/`clear_timeout` 成对转派、句柄 0 不转派取消）。逐包 `--deny-warn` 全零警告、`yoga-mbt` 92/92、全仓红点仍 287 errors / 68 warnings 未增。真窗口回证（`examples/native-app` 加「显示族收尾」区块，窗口加高到 560×900）：注入「右箭头 → 末指示点 → 左箭头」得 `car=2`（这条下标唯一，能同时证明两处箭头与指示点各自生效），基线自转 `auto=6`，把指针停在自转轮播上不动 → `auto=2`（悬停暂停实测）；截图复核时间线三色点与贯通线、两条轮播的箭头/指示点高亮均正常。

### MoonBit 原生 GUI 栈 · 日期族首批（值模型 + 自绘日历面板，「今天」走平台日历时间）

- **新增平台读数 `wm_local_date`（`win` 两个 C 桩 + `ffi.mbt` extern + `window.mbt` 公共 API，`core` 转派成 `local_ymd()`）**：日历要的是**日历时间**，而本栈已有的 `now_ms()` 是 `CLOCK_MONOTONIC`（单调钟，只给循环做时基），拿它推日期会得到一个稳定但错误的数字。C 侧用 `time()` + `localtime_r` 走系统时区，打包成 `年*10000 + 月*100 + 日`；**失败/便携桩返回 0**，`core` 翻成 `(0,0,0)`，组件层 `today_date()` 才退到 1970-01-01——分层上「平台给读数、上层决定退路」，本层不猜日期。
- **`today` 做成可显式传入的参数**（`calendar_t(today? : DateYMD = today_date())`）：默认走平台，测试传确定日期。否则「10 月 1 日落在第几格」这类断言会随运行当天漂移，等于没有断言。
- **42 格网格数学外置成纯函数 `month_grid(y, m) -> Array[(DateYMD, Bool)]`**（比 master 多一份）：面板只负责画与点，网格规则（首格前的上月尾巴、月末后的下月头部、本月格数=月长）脱离控件就能测，日期选择器与区间选择器后面共用同一份，不必各自再推一遍。
- **42 格一次建好、切月只改数据**：面板结构恒定，命中矩形不会因增删子控件而错位（`Widget::hit_path` 每帧从布局结果取矩形，但重建子树仍会让「按下-松开」跨代的控件对不上）；`rebuild_grid` 只写每格的 `Ref[DateYMD]`/`Ref[Bool]` 再 `invalidate()`。
- **选中语义走 Store 现取，不缓存副本**：`state_of` 每次画都读 `value.get()`（无 Store 才读自持的 `sel`），所以外部 `v.set(...)` 立刻换掉实心方块，不需要「订阅后手动刷新」这一步——master 的 `refresh()` 回调链在本栈被「画法现取」替掉，订阅只负责请求重绘（`follow_store`）。
- **松开才选中 + 跨月格不可选**：格子的 `Down` 只在 `in_month` 时消费（跨月格连按下都不吃，事件继续往上冒），`Up` 还要判松开仍落在本格内（捕获期把松开投回被按下的格，出界即不算一次）。
- **两条工具链实测（本批写测试时踩到）**：① `(x) -> Bool { ... }` **不是**闭包字面量（那是函数类型注解），`Array::filter` 要写 `fn(x) { x.1 }`，写错时症状是一串莫名的「cannot infer / unbound / Parse error」连锁报错；② 给值类型 `derive(Eq, Show)` 在本工具链里 `Show` 已弃用（提示改用 `Debug`），而 `derive(Eq)`/`derive(Debug)` 又会报 `implicit_impl_as_method` 弃用告警——零警告门禁下不划算，**断言一律走字符串观测**（`format()`、格子状态名），既不给组件加派生、也让失败输出更好读。
- **验证**：`moon test -p NoahLiu/native-gui/ui` **44/44**（新增 7 条日期族：闰年/月长/星期（Sakamoto 三个锚点：2026-10-11 周日、2000-01-01 周六）/月份进退含 ±12 与 15 个月、格式化补零与时间钳制与区间端点顺序不限、42 格网格（10 月首格 2026-09-27、第 5 格 10-01、末格 11-07、本月格数=31；闰年 2 月 29 格；1 月跨年头格落到上一年 12 月）、本地今天必须是真实年份（证明走的是日历时间而非单调钟）、面板点格写 Store + 跨月格不可选 + 格外松开不算一次、切月后可选日期跟着换 + 选中格画实心方块（比对该处是否仍是面板底色，因为面板底不透明）、外部改 Store 即换选中格、区间格子映射端点/中间/半开区）；逐包 `--deny-warn` 全零警告、`yoga-mbt` 92/92、全仓红点仍 287 errors / 68 warnings 未增。真窗口回证（`examples/native-app` 把 6b/6c 排成三列并把窗口改成 900×700，几何行补 `NATIVE-APP-CAL`）：注入「右箭头→末指示点→左箭头」+「点第 14 格→右箭头切到 11 月→再点同一格」→ 状态行 `car=2 auto=6 date='2026-11-15'`、`kids=12/12`、退出码 0；截图复核三列并排、日历头部「2026 年 10 月」、9 月尾巴灰显、10 月 11 日（今天）主题色、指示点高亮全部正常。

### MoonBit 原生 GUI 栈 · 导航族首批（分段 / 面包屑 / 分页 / 步骤条 / 折叠面板）

- **master 的 `stateful_item` 在本栈换成「画法现取 + 宿主交互态」**：旧那套是每项自持 `hover`/`focused` 两个 Ref 并在 enter/leave/focus 回调里置位+重绘；本栈的悬停与按下归属由宿主按命中统一维护（`Widget.hovered`/`pressed`/`focused`），所以底色/文字色回调只收本控件、现读现画，组件不再自己处理 enter/leave。收益有二：重建子树不会有「鼠标已离开但 hover 仍为真」的残留态；订阅面从「每项两条」降到「整组一条」（`follow_store` 只为请求重绘）。
- **选中态一律走 Store 且画法现取**：`segmented`/`breadcrumb`/`pagination` 都是「点即 `set`、画时 `get`」，所以同一 Store 挂在多处时全部同步高亮，不需要「改完再通知各控件」的登记表。
- **分页箭头的夹取写在宿主回调里而不是禁用按钮**：`‹`/`›` 在首/末页仍可点，值夹在 `[1, pages]`——与 Web 的 disabled 形态不同，但少一份状态（`pages` 可变时不用重算禁用），且无头测试能直接断言「连点 8 次左箭头仍停在 1」。
- **折叠面板收起即 `set_visible(false)`（display:none），不销毁内容**：内容子树预建常驻，开合只翻显隐 + `invalidate()`；测试用「整块高度回落」证明收起真的不占位（只断可见性会漏掉「隐藏但仍占高」这一类错）。各面板独立开合由每块自持的 `Ref[Bool]` 承担，互不影响。
- **一条自己写错的断言（记下来防再犯）**：步骤条是「连线插在方块前」的交错排布，子项顺序是 `方块0 文字0 连线1 方块1 文字1 …`，按「方块在 0/2/4」猜下标会拿到文字节点——文字处没有底色，两处取样同色，断言 `l1 != l3` 就以 `false` 失败。**自绘组件的像素断言必须先回读实际子项顺序**，别按视觉顺序猜结构。
- **验证**：`moon test -p NoahLiu/native-gui/ui` **49/49**（新增 5 条导航族：分段点即写 Store 且段宽随文本、选中段底色与未选段不同；面包屑分隔符占位、点非末项改值、末项不改值；分页点页码直落 + 箭头步进 + 两端各连点仍夹在 1/5；步骤条三态底色互不相同 + 连线随当前步着色 + 改 Store 后待办块换色；折叠面板默认只开第一块、各块独立开合、收起后整块高度回落）；逐包 `--deny-warn` 全零警告、`yoga-mbt` 92/92、全仓红点仍 287 errors / 68 warnings 未增。真窗口回证（`examples/native-app` 把该批排成第四列、窗口 1240×840，几何行补 `NATIVE-APP-NAV` 直接给四个注入点矩形）：注入「分段第二段 → 面包屑第二段 → 第 3 页 → 第二块标题行」得 `seg='分段乙' crumb='列表' page=3 step=1 fold='11'`（`fold='11'` 同时证明第二块开、第一块未被带跑），同轮 `kids=12/12`、`car`/`date` 等旧读数不变、退出码 0；截图复核分段高亮、面包屑分隔符、页码实底、步骤条三态与连线、折叠箭头方向全部正常。
- **一条验证手法上的坑（差点误判成组件不工作）**：把三批交互合到一轮注入（10 击）时，后三击全部无效——不是导航族没接上，而是示例的 5 秒自动退出赶在了注入之前。判据是「同一组坐标分批注入全中、合批注入只中前若干击」。累积验证页的存活窗口因此从 5 秒延到 9 秒；以后再加区块都要按「注入次数 × 每击间隔」核对存活时间，别拿退出码 0 当「交互全通过」的证据。

### MoonBit 原生 GUI 栈 · 导航族次批（侧边菜单 / 分组菜单 / 树 / 页签）

- **圆角落在组件层而不是等 Painter 补**：Painter 门面没有圆角矩形，`fill_round_rect` 用「四段直线 + 四个 90° 弧」在 `ui` 里拼路径（弧角一律递增——`Painter::arc` 的 `ccw` 参数在两层后端都不可用，逆时针需求要靠递增起止角表达）。菜单 4px 圆角与选中强调条因此和 EP 观感一致，不必给 render 层加新契约。
- **树与折叠面板同一形态：子层预建 + `set_visible` 切换**，收起即 `display:none`（不测量、不占位、不绘制、不命中），展开只翻标志；节点行按「行 + 子层容器」成对追加，测试因此能按 `children()[2i]` 取行、`children()[2i+1]` 取子层。叶子行连 `Down` 都不消费（`has_kids` 为假），事件继续往上冒，不会出现「点了没反应但把父容器的悬停吃掉」。
- **页签的显隐切换由 Store 订阅驱动，且先显示新页再隐藏旧页**：这条顺序在 master 是 Windows 专属规避（反序会让 yoga 在中间态把外层按 0 内容分配）；本栈每帧从根重排、没有那个洞，但「先显后隐」保留下来无害，且和 `swap_node` 的预建形态一致。页签头行**先**入树再挂页区，视觉顺序即子项顺序（测试用 `head.rect.y < page.rect.y` 钉住）。
- **两条测试写错的地方（都是「按坐标注入」这一类，值得记死）**：
  1. 取样像素必须**按各自控件的 y**取。侧边菜单三项同宽同 x，用第一行的 y 去取第二行，实际取到的还是第一行（选中行），于是「未选项应与容器底色相同」这条以「两处都是浅蓝」失败——症状像组件坏了，实际是断言取错了点。
  2. **隐藏的控件 rect 会被清零**（不可见子树整棵清零是 G6 定的口径），所以「点一个已收起的组内项」这种写法不会命中它自己，而是命中落在原点附近的另一个控件——本例里点到了组一标题行，把组一又展开，表现成「我什么都没做它却变了」。要验「收起即点不到」，得按窗口坐标显式判 `hit_path`/`hit_test`，不能拿控件自己的 rect 加偏移。
- **验证**：`moon test -p NoahLiu/native-gui/ui` **53/53**（新增 4 条导航族次批：侧边菜单项宽跟随容器 + 点项写 Store + 选中项底色与未选项不同（按各自行取样）；分组菜单标题行只影响本组、收起后整列上移需重取坐标、再展开后组内项可选；树子层预建即收起、点父行展开、点叶子行不动作、再点收起；页签预建三页只显当前页、点页签与外部改 Store 都换页、头行在页区之上）；逐包 `--deny-warn` 全零警告、`yoga-mbt` 92/92、全仓红点仍 287 errors / 68 warnings 未增。真窗口回证（`examples/native-app` 加第五列、窗口 1620×840，几何行补 `NATIVE-APP-NAV2` 给菜单第二项/树父行/页签第二页矩形）：合批 13 击（轮播三击 + 日历三击 + 导航首批四击 + 本批三击，注意页签要在树展开**之前**点，因为展开会把页签推下去）得 `car=2 auto=11 date='2026-11-15' seg='分段乙' crumb='列表' page=3 step=1 fold='11' menu='报表' tab=1 tree=1`、`kids=12/12`、退出码 0；截图复核菜单选中浅蓝圆角底 + 左缘强调条 + 「报表」图标、树折叠三角方向、页签指示条与页区内容全部正常。

### MoonBit 原生 GUI 栈 · 穿梭框收尾（导航族 10/10）与「重建式列表」的两条坐标纪律

- **选中集合改成组件自持的两张表，行不持订阅**：master 的穿梭框每建一行就订阅一次数据 Store，靠 `sub_bag_begin/end/discard` 在每次重建前整袋退订，防止死订阅随移动次数累积。本栈的行只读自持的 `Ref[Array[String]]`（选中集合按值存），重建就是「清子控件 + 按 Store 现值再挂」，行级根本没有订阅可漏——回收袋只留给列 Store 那两条（整列各一条）。少一层机制的代价是「选中集合不参与 Store」，换来的是重建次数与订阅数量解耦。
- **`Store.set` 不看值是否真的变了**：空搬运（选中集为空）也会 `from.set(remain)` + `to.set(merged)`，两个 Store 都发通知 → 整列又重建一次。这是 `Store` 的既有语义（不去重，见 `core/store.mbt`），组件不额外加「值相等就不 set」的判断——加了就把「同值也要刷新视图」的用法一起堵掉。测试因此必须按这条语义写：每次可能触发 `set` 的点击之后都要重取坐标。
- **两条「按坐标注入 + 重建式列表」的纪律（本批实测踩到）**：① 重建出来的行**没有矩形**，要等下一次布局才有——无头测试里每次可能引起重建的操作后必须手动 `root.relayout(...)`（真窗口由宿主每帧重排，无感）；漏掉时症状是「点了没反应」，因为零矩形加偏移会命中到别处。② 合批注入时，**任何会改变布局的点击都必须排在同列下方控件之后**：本例先点树父行（展开 +64px）再点穿梭框，穿梭框的两击就全打空（`xfer=3/1` 不变）；把树那一击挪到最后即 `xfer=2/2`。几何行给的是「最后一帧」的矩形，注入顺序必须与它一致，否则等于拿过期坐标点新位置。
- **验证**：`moon test -p NoahLiu/native-gui/ui` **54/54**（新增 1 条穿梭框：点行选中 + 箭头搬运 + 搬完清空选中（再点箭头不继续搬）+ 反向搬回 + 外部改数据整列重建，含上面两条 relayout 纪律）；逐包 `--deny-warn` 全零警告、`examples/native-app` 零警告、`yoga-mbt` 92/92、全仓红点仍 287 errors / 68 warnings 未增。真窗口回证（`examples/native-app` 第五列加穿梭框、窗口 1620×900，`NATIVE-APP-NAV2` 补 `xrow`/`xbtn` 两个注入点）：合批 15 击按「先点后移」顺序重排后得 `car=2 auto=11 date='2026-11-15' seg='分段乙' crumb='列表' page=3 step=1 fold='11' menu='报表' tab=1 tree=1 xfer=2/2`、退出码 0；截图复核左右两列描边、行首方块、`›`/`‹` 两键方向正常。

### MoonBit 原生 GUI 栈 · 滚动容器（yoga 补相对定位偏移 + `ui/scroll.mbt`）

- **滚动平移落在布局层而不是控件层**：`position: relative` + `top: -offset` 让内容整块上移，相对偏移**只改落位、不改常规流占位**——容器按内容自然高度撑开、后续兄弟不受影响，正是滚动要的语义；命中与绘制都吃布局结果（宿主每帧从 `collect_abs` 取绝对矩形），组件层不需要第二套坐标换算。为此给 yoga-mbt 补上了相对定位偏移：`top`/`left` 优先、同轴两端都给值时另一端忽略、`auto` 不偏移、百分比按父内容盒解；**绝对定位项不吃这套偏移**（它的 `top` 是 inset，从 padding 盒量起）。三条都在 `relative_wbtest.mbt` 里钉住。
- **内容必须 `flex-shrink: 0`**：CSS 里弹性项默认可收缩，内容是唯一子项时会被压成视口高、永远滚不动——这类「能滚的容器里内容却不变形也滚不了」的坑只有真滚一遍才看得出，所以配了「20 行 × 20 高 = 内容 400 / 视口 100 / 上限 300」的用例先钉住几何。
- **滚动条是视口的绝对定位子控件，不是画在视口上的一层色**：它贴在右缘、覆盖在内容之上，于是命中路径上它是最深的那个控件——内容行里的按钮抢不走条的按下与拖动（画在视口 `on_draw` 里的形态会被内容子控件的命中吃掉，这类「看得见点不着」只有真点才暴露）。条的绘制按「视口/内容」比例给拇指长（下限 16px 便于抓），拖动是「拇指中心跟随指针」的映射：`offset = clamp((y - 拇指/2) / (条高-拇指)) * 上限`，实测拖动到条中点得 `scr=171/320`、与手算逐位一致。
- **几何抄进状态放在第一帧绘制时**：视口高与内容高都来自布局结果，只能在绘制回调里读到（`self.rect.h` 与内容子控件的 `rect.h`），所以 `ScrollState.view_h/content_h` 由视口 `on_draw` 每帧刷新，滚动条比例与越界夹取都吃它。代价是**挂载后第一帧之前 `max()` 还是 0**（此时滚轮不动），实现上真窗口每帧都画所以无感；无头测试必须先 `paint` 一次再断言滚动行为，这条写进了用例注释。
- **跟随底部同理只能挂在 `on_draw`**：`max()` 依赖前一步抄进来的几何，首帧前恒为 0，「内容变高自动贴底」若只做成公开的 `scroll_to_bottom()` 调用就永远是空操作。实现为 `ScrollState` 的开关，视口 `on_draw` 抄完 `content_h/view_h` 后比对 `offset != max()` 落一次偏移（首帧即生效）。用户手动滚离底部只改内部暂停位 `follow_paused`，不动开关本身——否则「手动拖到底一次」会让所有滚动容器意外变成自动贴底，未开启的容器必须保持旧行为。
- **一条诊断口诀（本批花了十分钟找）**：类型里少一个右括号——`children : Array[@core.Node>`——会报成 `Inline wasm syntax error: unknown operator ?STRING` + `The type alias Array expects 1 argument(s), but is here given 5`，报错位置横跨整个函数签名、离现场很远。看到「Array 参数个数不对 / Inline wasm」这类**语义完全不搭**的报错，先回读签名里的括号配对，别去猜语言特性（对照实验：把函数体换成空体仍报同样错 → 病灶在签名）。
- **验证**：`moon test -p NoahLiu/native-gui/ui` **58/58**（新增 4 条滚动容器：视口/内容几何来自布局且滚轮改偏移两端夹取、内容随偏移整体上移且滚动条在内容之上（命中求证）、点轨道跳转与拖动拇指且松手后不再跟手、内容不足一屏时不滚也不画条（按像素求证该处露的是行底色））；`moon test -p NoahLiu/yoga-mbt` **96/96**（新增 4 条相对定位：top 只平移不改兄弟与容器尺寸、left 可负且 auto 不偏移、同轴两端 top/left 胜且只给 bottom/right 反向量、百分比按父内容盒解且绝对项不吃偏移）；逐包 `--deny-warn` 全零警告、全仓红点仍 287 errors / 68 warnings 未增。真窗口回证（`examples/native-app` 加第六列「滚动容器」：190×120 视口装 20 行 22 高、几何行补 `NATIVE-APP-SCR`）：注入滚轮下滚三格 → `scr=90/320` 且几何行 `row0=1182,437`（内容首行上移 90 = 527-90）、注入拖动条从顶到中 → `scr=171/320`（与手算逐位一致）、退出码 0；截图复核滚到第 7~11 行、行在视口边缘被裁、右缘滚动条拇指位置随偏移变化。

### MoonBit 原生 GUI 栈 · 浮层基座（`core/overlay.mbt`）与首批三件（气泡/下拉/悬浮提示）

- **宿主的浮层图层三条定案**：① **空图层不可见**——`display:none` 的控件不在任何命中路径上，所以没有浮层时点击原样落到内容；一旦开第一层就置可见并**立刻重排一次**（图层此前不可见、矩形还是清零的，不换算不出它自己的原点），浮层才能按「窗口坐标 − 图层原点」摆位。② **点浮层外收起放在抬起**——按下与抬起都由图层消费（不让这一击漏到内容里），但收起只在抬起做：若放在按下，同一击的抬起会重新命中触发件、把刚关掉的浮层又打开（实测：第二击把菜单关了又开，状态看上去「点不动」）。③ **浮层内容临开临建、关掉即摘**——不进内容树、不占位、没有隐藏态要同步；这与「预建 + 显隐」的切换式组件是两条路，浮层是瞬时的。
- **`popover_t`/`dropdown_menu` 包在触发件外层监听抬起**：触发件内部控件的事件先跑（按钮会消费按下），抬起冒泡上来才切换开合，所以包按钮、包标签都成立；「开着时再点触发件」的正常路径被图层消费掉了，组件里的 `overlay_alive` 分支是兜底（程序化投递或图层被撤掉的形态）。
- **`tooltip_t` 走宿主维护的悬停态而非冒泡的移动事件**：子控件可能自己消费移动（本仓按钮就是 `Move => !is_off()`），包在外面的组件再也收不到通知——真窗口实测「悬停 300ms 后没出气泡」就是这个原因。为此把 `Widget::set_hover` 改成**父链语义**（指针在子项上时父项也算悬停，与 CSS `:hover` 同义）并新增 `on_hover_change` 回调（只在悬停归属翻转时由宿主触发），提示组件挂在这个回调上起停定时器，包住谁都成立。核心用例把「命中链三层都算悬停、兄弟不算、重复设置不重复回调」钉住。
- **一条与 master 的差（记档）**：旧链路的 `tooltip_t` 是 GTK 原生 tooltip（`ffi_view_set_tooltip`），自绘栈没有原生 tooltip 通道，改成「悬停延时后开一层自绘气泡」——观感可控（吃主题与圆角），代价是自己管延时与收起（走 `@core.set_timeout`，无宿主时空操作）。
- **验证**：`moon test -p NoahLiu/native-gui/ui` **62/62**（新增 4 条浮层：空图层不挡内容 + 点触发件开层再点收起 + 浮层落在触发件下方 2px；点浮层外收起且这一击不漏给内容；下拉菜单 4 项含 1px 分隔线、选中回调序号并收起；悬浮提示延时到点才出现、离开即收、延时未到就离开则不出现）；`moon test -p NoahLiu/native-gui/core` **61/61**（新增 1 条：悬停父链语义 + `on_hover_change` 翻转触发、重复设置不重复回调）；逐包 `--deny-warn` 全零警告、全仓红点仍 287 errors / 68 warnings 未增。真窗口回证（`examples/native-app` 加「浮层首批」列，几何行补 `NATIVE-APP-OV`）：注入「点下拉 → 点第 2 项 → 点气泡 → 点浮层外 → 悬停在提示件上」得 `pick=2 ov=1`（`ov=1` 即退出时提示气泡还开着），同轮旧读数不变（`car=2 auto=14 date='2026-11-15' … xfer=2/2`）、退出码 0；截图复核下拉箭头朝上、面板四行含一条分隔线、浮层压在内容之上。
- **一条环境口径记档**：本机显示器中途变成竖屏（1440×2560），示例页七列并排（约 1800px）会超出屏幕、右缘列点不到——已把累积验证页拆成两排（4 列 + 3 列，窗口 1400×1260）。**窗口请求尺寸大于屏幕时 WM 会静默钳制**，只按几何行取坐标会在「看不见的区域」注入，症状是「某些列完全没反应」。

### MoonBit 原生 GUI 栈 · 浮层族收尾（对话框 / 轻提示 / 右键菜单）与三条实测口径

- **对话框开在浮层图层上**（与 master 的差，记档）：旧链路把遮罩做成**页面内绝对定位层**（同一份 `Node` 常驻页面树、靠 `set_visible` 弹收）；本栈改开在图层上——对话框天然要压过所有内容与其它浮层，图层正是这个语义，而且不必常驻一棵隐藏树。遮罩用 `overlay_show_full`（insets 全 0 的包裹层）+ **显式 `width/height: 100%`**：靠内部 `align-items: center` 撑满不可靠（内容比窗口宽时遮罩尺寸会跟着内容走，实测面板 420 > 窗口 400 时遮罩只有 420 宽、盖不住整窗）。
- **`node_of_new` 的 finish 是构造期执行的**——「按 Store 立刻开层」这类需要宿主已就位的初始化必须改用**显式 `mount`** 形态（`{ mount: fn(parent) { ... } }`）：测试里把 `dialog_t(visible=true)` 先在装好宿主之前构造，开层调用就落在一个空槽上、无声失败（`overlay_count == 0`）。真窗口里 App 建窗时先装宿主，所以只有测试会撞上；但组件把「构造期依赖进程级单槽」当常态是脆的，已按挂载期做。
- **右键改「祖先优先」派发**（`dispatch_on_path` 里 `button == 3` 时从根往最深走）：上下文菜单是容器级能力，包在内层控件外面要能先拿到它——否则包住按钮时按钮先把按下吃掉（本仓按钮的 `Down` 不分按键一律消费），菜单永远弹不出来。其余按键维持「最深优先」不变。
- **轻提示开在图层上、第一条才开层**（与 master 的差，记档）：旧链路返回「层节点 + 推送函数」，由调用方把层挂进页面树；本栈把顶部带子做成图层的一层（推送时开、最后一条撤下时收），于是**提示永远压在对话框之上**，页面里也不必常驻一棵空树；入口只剩一个推送函数，没有宿主时是空操作。叠放顺序「后开者在上」由图层条目顺序保证，用例直接断言两个条目的句柄先后。
- **验证**：`moon test -p NoahLiu/native-gui/ui` **67/67**（新增 5 条：对话框按下即弹、确定/取消都先收起再回调、Store 归假；✕ 收起且遮罩点击按 `close_on_mask` 决定收不收；轻提示推送后挂一条、宽度随文本、到点自动撤、撤完收层；右键在指针处弹出并回调选中项；轻提示开在对话框之上）。逐包 `--deny-warn` 全零警告、全仓红点仍 287 errors / 68 warnings 未增。真窗口回证（`examples/native-app` 第二排加「浮层次批」列，几何行补 `NATIVE-APP-OV2`）：注入「点弹窗 → 点确定 → 点提示 → 右键 → 点菜单项」得 `dlg=1 ctx=1 toast=1`、退出时 `ov=0`（提示已按 2 秒自动撤）、退出码 0；截图复核对话框半透明遮罩 + 居中面板（标题 / ✕ / 正文 / 取消+确定两键）、顶部居中的绿勾提示条。

### MoonBit 原生 GUI 栈 · 日期选择器四只（`ui/datepicker.mbt`，日期族 5/5）

- **弹层一律开在浮层图层上**（浮层基座刚落地就用上了）：日历面板与时间面板都是 `overlay_show_at` 的一层，点浮层外收起、再点字段收起都由图层与字段各自处理，组件不自己管「外面点掉了」。
- **日历面板与网格直接复用 `datetime.mbt`**：`build_calendar`（42 格一次建好、切月只改数据）与 `range_state_of`（端点实心、区间浅底）被四只选择器共用，`date_range_picker` 因此只是「两段式点击 + 写 Store」十几行；这也是把网格数学外置成纯函数的回报。
- **字段交互定案**：整字段吃下按下（进捕获期），抬起按**本地 x** 区分三件事——点 ✕ 清空（只在 `clearable`、悬停且有值时给热区，`width-40..width-20`）、开着则收起、否则开层。清空不触发 `on_change`（与 master 同：回调签名收的是非空值）。
- **与 master 的两条差（记档）**：① 旧链路弹层是原生 Popover，本栈用浮层图层上的自绘面板；② 旧链路时间是「时/分两个 `input_number` 输入框」，本栈改成**步进器**（时 ±1、分 ±5、循环进位），因为自绘栈没有原生输入框语义，键盘编辑要另配一套焦点与输入法通道（要键盘输入的多行文本用 `entry`/即将做的 `textarea_t`）。
- **验证**：`moon test -p NoahLiu/native-gui/ui` **71/71**（新增 4 条：日期选择器显示占位、点开日历、点选回填并收起、再点字段收起、悬停后点 ✕ 清空且清空不回调；日期区间两段式点击写回整段并收起；时间区间步进器改值 + 确定写回 + 取消不改；日期时间区间四字段各写各的、日期走日历时间走步进）。逐包 `--deny-warn` 全零警告、全仓红点仍 287 errors / 68 warnings 未增。真窗口回证（`examples/native-app` 第二排加「日期族选择器」列，几何行补 `NATIVE-APP-DP`）：注入「点日期字段 → 点 10 月 1 日格子」得 `dpk='2026-10-01'`、「点区间字段 → 点 10 月 3 日 → 点 10 月 7 日」得 `drg='2026-10-03~2026-10-07'`、「点时间字段 → 点 + → 点确定」得 `trg='10:00'`，退出码 0；截图复核日历弹层落在字段下方、时间弹层的时/分步进与取消/确定两键。
- **一条注入坐标的纪律（本批又踩一次）**：时间弹层的两步（点 + 与点确定）第一遍全打空，原因是我按「容器高度推中心」算坐标时把行高算错了一行（点进了「分」行、确定键点到了按钮右侧空白）——**浮层里的坐标不能靠推算，要用截图回读或把该控件的 rect 打出来**；本例改用「面板内边距 + 行序 × 行高 + 半高」重算后一次命中。

### MoonBit 原生 GUI 栈 · 表格首批（`ui/table.mbt`：模型 + `table_t`）

- **排序状态归组件、排序口径归使用方**：组件在表头点击时切换 `Store[TableSort]` 并画箭头（新列升序 → 同列翻转 → 同列第三次取消、`column = -1`），**不替调用方排序数据**——数字列要数值序、字典序、还是自定义比较都是业务口径，组件替它排反而会错（master 的注释里也是这条；本批沿用）。排序箭头分「当前排序列的实心三角（升/降）」与「可排序列悬停时的灰色 ↕ 提示」两种画法。
- **列宽分配外置成纯函数 `table_widths`**：固定列按声明宽、弹性列（`<= 0`）均分剩余宽、总宽不够时弹性列取 0（溢出而不压缩固定列）——这条单测直接钉住，不必真画一遍表。
- **行是重建式列表**（与 `transfer` 同款）：数据 Store 一变就清空子控件按新值重挂，行级不持订阅；选择与排序只影响**绘制**（`on_draw` 里现取），所以点选与排序切换都不会触发重建。选择存的是**源数据下标**（不是显示序），因此重排后选中行跟着数据走——比 master 的「显示位置 Ref」稳。
- **单元格四型**：纯文本（按列对齐）/ 语义标签（浅底 + 主色字，与显示族 `tag_of_type` 同口径）/ 颜色块（色块 + 文字）/ 多行（行高内最多两行）。
- **验证**：`moon test -p NoahLiu/native-gui/ui` **75/75**（新增 4 条：列宽分配三种情形；表头列数/斑马纹/点选行写选择 Store 且左缘出强调条/再点取消/行回调带源下标；表头排序状态机四步含不可排序列点了不动；标签与色块单元格出像素 + 数据变更整表重建）。逐包 `--deny-warn` 全零警告、全仓红点仍 287 errors / 68 warnings 未增。真窗口回证（`examples/native-app` 加「表格」区块，几何行补 `NATIVE-APP-TB`）：注入「点表头两次（升→降）→ 点第 2 行」得 `tsort=0/false tsel=1`、退出码 0；截图复核表头排序三角朝下、斑马纹、选中行浅蓝底 + 左缘强调条。
- **一条纪律（本批连踩三次同类笔误）**：嵌套泛型少写一个右括号（`@core.Store[Array[TableRow]>`，正确的是 `]]`）会报成 `The type constructor Store expects 1 argument(s), but is here given N` + `Expected upper case identifier for type name`，报错位置横跨签名、与真实病灶（少一个 `]`）无关。已把「写完嵌套泛型先 grep `]>`」当成本批后的固定自检——三次里有两次是通过「函数体换成空体仍报同样错 → 病灶在签名」这条对照实验定位的。

### MoonBit 原生 GUI 栈 · 虚拟列表与虚拟表格（万行级形态）

- **只挂可见区间**：视口固定、行高固定，滚动偏移一变就按「首行 = 偏移/行高 − overscan」重挂窗口，上下各放一个占位控件把内层总高撑到「行数 × 行高」。命中与绘制只跟挂载的行有关，200 行实测只挂 10~13 个行控件。
- **占位不等于平移，两者要同时在场**（真机缺陷：`examples/native-app` 的虚拟表格滚动后「从上往下一路白屏」）：初版只在 `first > 0` 时插一个 `first × 行高` 的上占位、内层不做相对定位，理由写成「占位同时把可见行摆到正确的滚动位置」。**这条理由是错的**：没有平移时第 `i` 行永远落在内层原点下方 `i × 行高` 处，也就是**比正确位置低整整一个 `offset`**，而宿主按控件矩形裁剪（`widget.mbt` 的 `clip_rect`），于是偏移越大可见行被推出视口下沿、视口上沿越空——正是「慢慢从上面开始往下白屏」。占位只补「窗口第一行 → 内容原点」这段差额，真偏移量必须由内容块的 `position: relative` + `top: -offset` 承担（与 `scroll_view`/`sticky_list` 同一套）。原来的写法只在 `offset` 恰为行高整数倍且极小时看不出问题。
- **钉桩要钉几何，不能只钉挂载数**：本缺陷能长期存活，是因为既有 3 条单测只断言「挂了哪几行、内层总高对不对」，没有一条断言「行的绝对矩形落在视口内」。补的回归钉桩滚 **1.5 行**（非整数倍偏移最容易暴露），断言内容块上移量 = 偏移、第一行顶部 = 视口顶 − 半行，再深滚到底断言「视口内仍有 5 行可见」。几何类组件的判据一律写成 `rect` 比较。
- **滚动条从 `scroll_v` 抽出来共用**（`scroll_bar(state)`）：轨道/拇指比例、点轨道跳转、按住拖动、松手即止这套只写一份，`scroll_v` 与 `virt_list` 都拼它。抽的时候踩到一个「脚本式抽取」的坑：按行号切片把设置代码复制了两遍（`let bar` 到 `append` 之间本来就含设置段），`--deny-warn` 立刻报 `unused dragging` ——**抽取后要重跑门禁**，重复段与未用变量都躲不过。
- **不在 `on_draw` 里重建窗口**：绘制遍历正在读 `kids`，改动子控件会踩迭代器；所以视口高只在 `on_draw` 里**抄进状态**，窗口重建一律发生在事件回调（`ScrollState.apply`）与数据订阅里。首帧还没有真实视口高时用声明的 `height` 兜底（否则首帧只按 overscan 挂几行、看上去空）。
- **数据变短要先夹偏移再重挂**：订阅里先把 `content_h` 按新行数写好、把越界偏移拉回上界，再重建窗口；少了这步，删数据后视图会停在一片空白上。
- **虚拟表格 = 固定表头 + `virt_list`**：表头不参与滚动，行控件与 `table_t` 共用同一份构造（把 `table_t` 里的表头与行各自抽成 `table_header`/`table_row_widget`，两者共用；抽取后 `table_t` 自身也只剩「拼表头 + 重建式行表」）。表头宽度扣掉滚动条 8px 与左右边框，列宽才与数据行一致。
- **验证**：`moon test -p NoahLiu/native-gui/ui` **78/78**（新增 3 条：千行只挂可见区间且滚动 4 格后窗口首行 = 偏移/行高 − overscan = 4、内层总高 = 行数×行高；拖滚动条改偏移、数据变短偏移夹回上界；虚拟表格表头固定不滚、行只挂可见区间、表头排序与行点选与 `table_t` 同口径）。逐包 `--deny-warn` 全零警告、全仓红点仍 287 errors / 68 warnings 未增。真窗口回证（`examples/native-app` 加「虚拟表格」区块，几何行补 `NATIVE-APP-VT`）：注入「滚轮下滚三格 → 点列表中部」得 `vt=1/1`、`NATIVE-APP-VT mounted=13 total=200`（**挂载数远小于总数**即虚拟化生效的机器可查证据）、退出码 0；截图复核滚到第 1~6 行、选中行浅蓝底 + 左缘强调条、右缘拇指位置随偏移变化。
- **修复批验证**：`moon test ui` **133/133**（含新钉桩）、`moon test core ui render text theme icons sys input win dbus chart mdview web` **865/865**、`cd gui && moon check --deny-warn` 零警告。真机复核项（待用户回证）：`moon run examples/native-app` 与 `moon run examples/sysmonitor` 的进程页——滚轮连滚十几格后行内容要始终跟着滚动条走、不出现上沿空白；点行选中与滚动条拖动落位一致。

### MoonBit 原生 GUI 栈 · 表格列宽拖动与粘性列表（表格 2/2、容器与滚动补充收口）

- **列宽是活的**：`table_t`/`table_v_t` 各持一份 `Ref[Array[Double]]` 列宽，表头拖动时改它、表头两格与**已挂载的行内单元格当场改宽**（不重建树）；虚拟表靠一个 `rev : Store[Int]` 让 `virt_list` 整窗重挂（可见行才十来个，重建便宜）。拖动语义是「相邻两列此消彼长」并夹在 `[MIN_COL_W, total − MIN_COL_W]`（40px 下限），末列右缘不设把手。
- **一条真窗口才暴露的接缝**：表头单元格自己会消费按下（点标题排序），于是**可排序列的边界拖动整个失效**——父控件（表头）收不到这次按下。修法是单元格判断「本地 x 距左右缘 3px 内就**不消费**」，把边界让给表头；单测因此特意用**可排序列**钉住（最初用不可排序列写，测试通过但真窗口拖不动）。
- **粘性列表的「当前组」靠读布局结果反推**，不是按偏移硬算：组高由内容决定（行数、换行都可能变），每帧布局后读各组控件的矩形、取「起点 ≤ 偏移」的最后一组写进 `StickyList.cur_group`，吸顶条只负责画它。吸顶条是视口里的一条绝对定位悬浮条（与 `scroll_v` 同一套相对定位平移内容），滚动与滚动条沿用共用件。
- **验证**：`moon test -p NoahLiu/native-gui/ui` **80/80**（新增 2 条：表头边界拖动改列宽且相邻两列此消彼长 + 越过界夹到最小列宽 + 行内单元格跟着改宽 + 松手后不再跟手（用可排序列）；粘性列表滚过组边界时吸顶标题换文字、内容整块上移、可滚上限 = 内容高 − 视口高）。逐包 `--deny-warn` 全零警告、全仓红点仍 287 errors / 68 warnings 未增。真窗口回证（`examples/native-app` 加「粘性列表」区块与表格拖动）：注入「按住表头 140px 边界往右拖 80px」得 `head0=24,521,200x40`（= 总宽 240 − 最小列宽 40，与手算逐位一致）、注入「滚轮下滚五格」得 `sticky='组二'`（`NATIVE-APP-STK max=238`）、退出码 0。

### MoonBit 原生 GUI 栈 · 分隔布局与文本族首批（`hsplit`/`vsplit`、`TextRole`/`label_t`/`measure_text_height`）

- **分隔把手拖动只改样式**：旧链路（master `yue/splitter.mbt`）是「直写 `set_bounds` + 双写 `width/flexbasis` 样式」——那套是 GTK 时代的老坑（运行期改布局属性重排不落地，见其 probe-splitter 条）。本栈每帧从根重排、样式改完下一帧就生效，所以只改样式；拖动期间靠宿主的**指针捕获**（按下即进捕获期），指针拖出把手范围仍投给把手，位移按窗口坐标算。
- **总量从三个控件的实际矩形读，不捕获父控件**：夹取要「把手两侧加起来的总长」，而父控件（容器）不能捕获进子控件的回调——父子互指就是引用环。改成 `first.rect + 把手常量 + second.rect`，语义等价且不引入环。
- **把手首栏初始用百分比、拖动后切成固定值**：初始 `percent(ratio*100)` 让首栏随容器缩放（不依赖「先量一次再算」），一旦拖动就换成 `fixed(px)`（此后由用户定）；两端下限 `min_first`/`min_second` 在拖动中夹取。
- **文本角色（`TextRole`）与 `measure_text_height`**：角色把「字号 + 颜色」收成一体（Title/Section/Body/Secondary/Accent），`role_color` 现取主题（不固化）；`measure_text_height(text, role, width)` 供运行期长高的标签显式设高——容器问到的自然高与绘制时按盒宽折行的高未必一致，显式高度最稳（这是旧链路记档过的坑，本栈沿用同口径）。
- **验证**：`moon test -p NoahLiu/native-gui/ui` **85/85**（新增 5 条：按宽量高给宽后明显变高且角色字号越大行越高；角色字号/颜色（Accent 用主色）；主题化标签按 `max_width` 折行、固定色覆盖角色色（像素求证）；水平分隔把手拖动改首栏宽 + 两轮极值夹取 + 松手后不再跟手；垂直分隔同上）。逐包 `--deny-warn` 全零警告、全仓红点仍 287 errors / 68 warnings 未增。真窗口回证（`examples/native-app` 加「分隔布局与文本族」区块，几何行补 `NATIVE-APP-SPL`）：注入「按住把手往右拖 100px」得 `first=24,1236,788x116` / `split=788`（688 + 100，与手算一致）、退出码 0。
- **一条窗口尺寸的复核纪律（本批又踩）**：示例页面已长到 1400px 上下，窗口还是 1260 时**下半页在窗口外**，注入点落在看不见的区域、静止不动；先把窗口加到 1500 再测即中。**每次给累积验证页加区块，都要按 `NATIVE-APP-RECTS` 的最后一项核对窗口高度**，别只看几何行有坐标就以为点得着。

### MoonBit 原生 GUI 栈 · 表单族首批五件（`button_t`/`link`/`form_item`/`form`/`rate_t`）

- **焦点环落在第几列像素**：`stroke_rect(0.5, 0.5, w-1, h-1)` 配线宽 1 的描边中心在 0.5，覆盖的是 x∈[0,1] 那一列的**第二格**——取样取 `ox` 读到的是底色，会误判「焦点环根本没画」（本批第一条用例就这么假失败）。取样一律 `ox+1`，或先扫一列确认环在哪。
- **越界点击命中不到控件，别拿它当「夹取」用例**：`dispatch_pointer` 先做命中测试（`rect.contains`），x 超出控件宽的事件压根不会投给这个控件，回调里的 `clamp` 也就无从验证。「点最右缘仍得最后一颗」要改用**框内**最右点（126 宽的评分用 x=120），确实要测出界路径用 `dispatch_pointer_to(id, ev)`（宿主的指针捕获就是这条）。
- **`on_change` 只在交互点触发**：master 把回调挂在 `value.subscribe` 里，外部写值也会回调；本栈统一成「回调 = 用户这一次操作」（与日期选择器同口径），外部写值只重绘。两种语义各有道理，混用会让调用方以为「自己写值又收到自己的回调」，故记档。
- **表单项的错误行常驻预留高度**：错误文案行固定 18 高（空文案也在），文案出现/消失不引起布局跳动——真窗口用 `NATIVE-APP-FORM item=` 矩形在点「危险并报错」前后逐位相同回证。文案本身用 `label_dyn(err.signal())`：Store 的信号直接喂给标签，改文案走 `relabel` 就地重测，不重建子树。
- **按钮宽度口径与 master 不同**：master 在 mount 期手动 `get_bounds_for` 测文本宽再 `+32` 定宽、绘制时自己水平居中；本栈的文本测量已经回灌布局引擎（`attach_text_measure` + 左右 padding 12），宽度是布局结果，绘制只按盒居中，不需要那份手动测量。
- **验证**：`moon test -p NoahLiu/native-gui/ui` **90/90**（新增 5 条：按钮配色求解（四变体 × 悬停 + 显式覆盖吃掉悬停）；主题化按钮宽度随文本、抬起出框不算点击、焦点环只在聚焦时画、禁用不消费；链接宽度=文字宽、悬停出下划线、抬起才回调；表单项标签定宽 + 错误行预留 18 高 + 空文案量 0 宽改文案后就地重测；评分星顶点几何、点击写值并回调、悬停只预亮不改值、离开清预亮）。逐包 `--deny-warn` 全零警告、全仓红点仍 287 errors / 68 warnings 未增。真窗口回证（`examples/native-app` 加「表单族余项」区块，几何行补 `NATIVE-APP-FORM`）：注入「点实心按钮 → 点链接 → 点危险按钮（写错误文案）→ 点第 4 颗星」得 `btn=2 lnk=1 rate=4 ferr=1`、`item=24,1475,245x39` 与未点击那轮逐位相同、退出码 0；截图复核四型按钮配色（实心白字 / 浅底主色字 / 无底主色字 / 红底白字）、链接悬停带下划线、标签右对齐、五颗空心星。
- **窗口高度按最后一项几何复核**：本批区块落在最下方，页面已长到 1542，窗口 1500 时评分那行在窗口外（点了没反应），加高到 1660 后一次命中；注入前另要注意自动退出定时器（12 秒）与「先 sleep 再找窗口」的竞态——sleep 到点会拿到已销毁窗口，报 `BadWindow`。

### MoonBit 原生 GUI 栈 · 下拉选择与取色器（`select_t`/`color_picker_t`，表单族 13/15）

- **浮层句柄要问「活性」而不是「非零」**：`overlay_show_at` 返回的 id 单调递增、**从不复用**，而「点浮层外收起」是图层代做的——组件自己那份 `open_id` 不会跟着归零。于是用 `open_id.val != 0` 判开关会把**已失效的句柄**当成还开着，症状是「点外面关掉之后，要连点两下字段才重开」（第一下只清了旧句柄）。判开关一律用 `overlay_alive(open_id.val)`（内部就是 `overlay_rect_of(id)` 是否还在）；`close_pop` 里保留 `!= 0` 的守卫无害（隐藏失效 id 是空操作）。浮层组件 `popover_t`/`dropdown_menu` 一开始就是这个写法，日期选择器四只与本批两只此前用的是弱判据，已统一，并各加一条「点外收起后再点字段一击即开」的回归。
- **单独画一个控件到位图，要抵消它的绝对落位**：`w.paint(p)` 会按 `rect.x/rect.y` 平移，而「贴合控件尺寸」的位图只有 w×h 大——浮层里的行控件绝对 y 在几十到几百，画出去之后像素断言恒等（症状：「选中行与未选中行同色」的假失败）。改用 `w.paint_at(p, w.rect.x, w.rect.y)`，平移量归零，位图坐标即控件局部坐标。
- **弹层列表套一层 `scroll_v`**：面板按公式定高（`项数×28+8`，上限 300），选项再多也不顶出窗口；滚动几何仍是第一帧绘制时才抄进 `ScrollState`（见滚动容器那条），所以无头用例点之前要先 `relayout` 一次。
- **`container` 的 `padding` 只给左/上**：`Widget::set_padding(left, top)` 的口径，不是 CSS 的四边内边距——色板容器实测 176×72 而非 176×80，右下那条带靠浮层面板自己的固定高兜住。按四边理解会把几何断言写错一格。
- **与 master 的三条口径差**：① 弹层是浮层图层上的自绘面板，不是原生 Popover，「点外面收起」由图层负责，组件不再跟踪；② master 靠字段失焦收起，本栈字段是否可聚焦取决于调用方给不给 `focus_id`，收起只走「点外面 / 再点字段」两条路；③ 下拉的 ✕ 清空**同样**回调 `on_change("")`（与 master 同），而日期选择器的清空不回调（也与 master 同）——两条口径各自保留，不是本栈内部不一致。
- **验证**：`moon test -p NoahLiu/native-gui/ui` **93/93**（新增 3 条：下拉点开列表与几何（弹层落在字段下方 2px、同宽、行 28 高）、点选项写回并收起、选中行浅底与右侧勾出像素、✕ 清空同样回调；下拉「点外收起后再点字段一击即开」；取色器色板网格几何（两行 5+1、面板 176×80）、选中格比未选格多描边与白勾（逐像素比对差异 >20）、点色块写值并收起）。日期选择器用例同步扩一条失效句柄回归。逐包 `--deny-warn` 全零警告、全仓红点仍 287 errors / 68 warnings 未增。真窗口回证（`examples/native-app` 的「表单族余项」区块加一行下拉与取色器，几何行补 `NATIVE-APP-FORM sel= col=`，状态行补 `sel= col= ovmax=`）：注入「点下拉字段 → 点第 2 项 → 点取色字段 → 点第 2 格 → 点下拉 ✕」得 `sel='选项乙/'`（先选中后清空）、`col='#2E9E5B'`、`ovmax=1`（浮层峰值计数——退出时早已归零，故每拍记一次最大值才证明确实开过层）、退出码 0；截图复核色板网格 5×3 落在字段下方并压在内容之上。

### MoonBit 原生 GUI 栈 · 多行输入框（`ui/textarea.mbt`，表单族 15/15）

- **`focus_id` 只是声明,焦点栈由宿主按控件树对齐(2026-10-15 改口径)**:当年记的是「控件带 `focus_id` 只表示可聚焦,`App` 在按下时若发现该 id **不在焦点栈里就不改焦点**,示例里新加的 21..24 四只要补 `app.focus.register(id)` 才吃键盘」——那条纪律从没进过库,结果 showcase 全线打不了字,详见本节末《键盘焦点全线失效》。现在的口径:声明 `focus_id` 即在栈里(`Widget::focus_ids` → `FocusStack::sync`,Down 与 Tab 前各对齐一次),`register` 只留给不在树里的临时焦点。
- **xdotool 注入按键的正确口径**：`xdotool key --window WID ...` 走 XSendEvent，GTK 侧不吃合成事件——于是出现「**鼠标注入全中、键盘注入全无反应**」的假象。改成先 `xdotool windowactivate --sync WID` + `xdotool windowfocus WID`，再用**不带 `--window`** 的 `key`/`type`（XTEST 投给当前聚焦窗口）就进得来。
- **中文输入法会吃掉字母与方向键**：真窗口里 `type "cd"` 没进文本框（字母被 fcitx 收去拼 preedit），而 `Return` 能过。判据是先看 preedit 是否出现；要回证 ASCII 打字得先把输入法切到英文模式（只读查询用 `fcitx5-remote -n`，**别用 `-t`，那是切换**）。多行框的键盘语义因此以白盒用例为主（`dispatch_key` 直投），真窗口只回证点击定位、回车换行与滚轮。
- **上下键的落点取「不超过 x 的最右码点边界」**：一开始写成「严格小于」，等长两行之间按上键会少走一个字符（实测 caret=1 而不是 2）——与单行框 `byte_at_x` 同口径才是对的。
- **逐字节推进后回退码点要先判末尾**：`while at > ln.start && (bs[at] & 0xc0) == 0x80` 在 `at == 文本长度` 时越界读，症状是测试驱动只报 `SIGABRT (core dumped)`（栈里连断言都看不到）。加 `at < n` 守卫。
- **段循环里别拿 `j = hi` 当 break**：`wrap_units` 内层 while 用「把游标推到端点」退出，等于把整行吞成一个段——外部表现为**任何宽度都不折行**。改成 `let mut go = true` 的显式退出标志。
- **插入点跟随的观感**：光标落在「最后一行半」时整块上移（实测 16px），于是第一行被裁掉一半——这是 `ensure_visible` 的正常结果，不是绘制 bug（截图复核时别当问题报）。
- **验证**：`moon test -p NoahLiu/native-gui/ui` **98/98**（新增 5 条：折行断点单位（空格/拉丁词/中日韩逐字分段与区间截断）；显示行布局（按换行符断行、空文本给一行、贪心折行且断行处不留行首空格、行间首尾相接、中文逐字断三行、超长单词不拆只溢出）；键入与回车、上下键按显示行移动并记住 x、Home/End 走行首尾、Shift+Home 扩选后替换、行首退格并行；点击定位到第几行（中文按字节算行首）、拖选跨行整删、只读不吃编辑键；内容超视口才出滚动条 + 滚轮到底后拇指与轨道换位 + 插入点滚进可视区后顶行像素变化）。逐包 `--deny-warn` 全零警告、全仓红点仍 287 errors / 68 warnings 未增。真窗口回证（`examples/native-app` 表单区块加多行框，几何行补 `ta=`，状态行补 `ta= tacur=`，示例内容改 8 行）：注入「点框内第 3 行（窗口 y=1644）」得 `tacur=12`（该行行首字节，与手算逐位一致）→ 注入 `Return` 得 `ta='行 1/行 2//行 3/…'`、`tacur=13`（多出一个空行）→ 滚轮上滚回顶，截图复核三行完整可见、右缘拇指回到顶部、插入点跟随造成的 16px 上移在中间帧可见。

### MoonBit 原生 GUI 栈 · 声明式层 L1 构造器（`ui/declarative.mbt`：vbox/hbox/bind_label/hover_group/mount_window…）

- **`hover_group` 在新栈不需要任何轮询机制**：旧链路（`yue/declarative/hovergroup.mbt`）靠一个全局 100ms 指针轮询拍，因为 GTK 的指针事件不冒泡、子控件的 GdkWindow 会独占事件，祖先容器收不到 enter。本栈宿主的悬停态本来就是**父链语义**（指针在子项上时父项也算悬停，与 CSS `:hover` 同义，见 tooltip 那条），所以组件只读 `Widget.hovered` 即可——没有定时器、没有指针查询、也没有「组静止时不触发回调」这类优化要做。记成**机制差**而不是「已实现同款」。
- **`bind_label` 的强制重排在本地栈里是免费的**：旧链路 `set_text` 只标脏不重排，标签变长就截断，必须补一次 `update_layout`；本栈改文本走 `relabel`（重设测量回调 → 节点标脏），下一帧布局自然跟着新文本走。真窗口回证：点一次按钮，标签从 36px 变 87px（`lblw=36/87`），期间没有重建任何子树。
- **`mount_window` 不提供 `center` / `on_close`**：旧链路的窗口居中与关闭回调走的是原生窗口通道；本栈窗口位置由 WM 决定、关闭只是让 `App::run()` 返回，收尾写在调用方 `run()` 之后。少给两个参数比给两个假参数好。
- **与组件同名的构造器不再包第二层**：`label`/`button`/`entry`/`checkbox`/`container`/`group`/`separator`/`image`/`icon`/`radio_group`/`slider`/`progress` 在 `ui` 里已经是返回 `@core.Node` 的声明式构造器，再套一层同名函数只是多一处要维护的签名。本批只补三类：改名者（`vbox`/`hbox`/`text_edit`/`picker`/`scroll`/`tab`/`date_picker`）、地基入口（`mount_window`、`bind`/`bind_label`）、新能力（`hover_group`）。`overlay_scroll` 在本栈就是 `scroll_v`（滚动条一直是视口的绝对定位子控件），`gif` 随图标/动画批，`cursor_group` 要窗口层光标通道（新增 FFI），单列一批。
- **三条工具链写法（本批实测）**：① `test "名字"` 与左花括号**必须同一行**——分行写时解析器把测试体当成独立的顶层块，报错现场跑到几十行外且语义完全不搭（`The value identifier tabs is unbound` + `Parse error, unexpected token id`）；② `Option::is_none()` 在本工具链已弃用（提示改用 `x is None`），别把它写进新代码；③ match 的守卫不是 `v when cond`，MoonBit 写 `| cond`——简单二分支直接退回 `if/else` 更省事。
- **验证**：`moon test -p NoahLiu/native-gui/ui` **103/103**（新增 5 条：vbox/hbox 的方向与间距来自参数、bind_label 改值后就地换文本并重测宽 + 出像素、bind 走派生信号且订阅随回收袋退订、hover_group 子控件悬停即整组换底色且抬起出组不算点击、旧名构造器落到新组件上（picker 点开浮层并回填、scroll 出滚动条且 max>0、tab 按 Store 切页））。逐包 `--deny-warn` 全零警告、全仓红点仍 287 errors / 68 warnings 未增。真窗口回证（`examples/native-app` 加「声明式 L1」区块，几何行补 `NATIVE-APP-DC`，状态行补 `dcl= lblw=`，页面又长一截故窗口 1760→1900）：注入「点卡片里的『加一』按钮」得 `dcl=1 lblw=36/87`（Store 一改，标签文本与宽度都跟着走）、`label=34,1377,87x19`，指针停在卡片空白处截图复核整块换悬停底色。

### MoonBit 原生 GUI 栈 · 可编辑下拉（`combo`，声明式 L1 收尾）

- **组合方式：编辑语义全在里面那只 `entry`，本组件只加「候选」这一层**。过滤随输入走（`entry` 的 `on_change` 里重开浮层），回车取高亮用 `entry` 的 `on_enter` 钩子，而 ↑/↓/Esc 靠**按键沿祖先链冒泡**：`entry` 对这三个功能键不消费（内核 `handle_key` 走到 `keysym_to_text` 得 None → `handled=false` → 宿主继续往上问），包在外层的 `combo.on_key` 才拿到它们。这是本栈第一次把「同一次按键先问控件、再问祖先」用在真实分工上，值得记：组件想吃子控件不消费的键，不必给子控件加回调参数，父层的 `on_key` 就是那条通道。
- **抬起才开层（与 popover/dropdown 同一套路）**：`entry` 消费了按下（要落插入点），同一击的抬起才冒泡到包装层，`combo` 在 `Up` 里开层——所以点字段任意位置都是「定位插入点 + 开候选」，不需要额外的下拉箭头热区。
- **高亮不重建浮层**：候选行的选中态是闭包现取（`fn() { hi.val == idx }`），↑/↓ 只改 `hi` 再 `invalidate()`，浮层内容不重挂；过滤结果变了才重开（`close()` + `overlay_show_at`）。
- **浮层 id 单调递增，测试里数错就崩**：每次 `overlay_show_at` 都换新 id（关层不回收编号），所以「第 N 次开层」的断言要按**开层次数**数而不是按当前层数——数错时 `overlay_root_of(不存在的 id)` 给 None，测试助手退回一个空控件，紧接着的 `children()[0]` 就越界，症状是测试驱动只报 `SIGABRT (core dumped)`（本批实测一次，栈里没有断言）。
- **与 master 的一条差**：旧链路的 combo 是原生可编辑组合框（GTK `ComboBoxEntry`），本栈全自绘——浮层开在浮层图层上、点外面收起同样由图层负责。
- **验证**：`moon test -p NoahLiu/native-gui/ui` **105/105**（新增 1 条：点字段开层给全量候选 → `dispatch_commit` 提交「甲」过滤成两行并自动开层 → 高亮行的浅底与勾出像素、下键把高亮挪到另一行 → 回车回填高亮项并收层并回调 → 再开层只剩一行、Esc 收层不改值 → 过滤到空集不开层）。逐包 `--deny-warn` 全零警告、全仓红点仍 287 errors / 68 warnings 未增。真窗口回证（`examples/native-app` 表单区块的下拉行里加 `combo`，几何行补 `cmb=`，状态行补 `cmb='…'`，焦点 id 25 补注册）：注入「点可编辑下拉字段 → 点第 3 项」得 `cmb='组件丙'`、退出码 0；另一轮四击「开层 → 点第 2 项 → 再点字段 → 点原第 3 行位置」停在 `cmb='组件乙'`——第二次开层时当前文本已是「组件乙」，过滤后只剩一行，点在旧第 3 行位置的点击自然落在浮层外，这正是「随输入过滤」的应有表现（不是丢点）。

### MoonBit 原生 GUI 栈 · 缩放绘制修正与 GIF 动图（`cr_blit` 重写 + `Animation` + `gif`/`icon_button_t`）

- **`cairo_pattern_set_matrix` 的缩放路径实测是错的（本批修掉的真 bug）**：旧写法把「源像素→设备像素」写进图案矩阵（`translate(d0,d1)` + `scale(k)`），Cairo 的语义与这个直觉相反——源 120×120 里 (20,20)-(99,99) 的方块缩到 72 时，图案矩阵路给出 (33,33)-(71,71)（推到目标矩形右下角并被裁掉），而 CTM 路（`identity` → `translate` → `scale` → `set_source_surface` → 以子矩形大小为填充范围）给出正确的 (12,12)-(59,59)。**等尺寸（目标=源大小）时两条路恰好一致**，所以这个错一直藏着：`draw_image`/`draw_canvas` 的缩放分支此前没有任何用例覆盖。诊断顺序值得照抄：先在 MoonBit 侧用**全不透明合成图**证明「能画出来」（2304 格全中），再换**带透明区的源**复现「画歪」，最后把整段 blit 搬进独立 C 程序对照三种写法（父表面+矩阵 / CTM 变换 / 子表面+矩阵），一次定位。
- **改了桩库，`moon run` 的产物同样不会重链**（此前只记过测试 exe 这一条）：`build/librender_cairo_stub.a` 是 13:50，而 `native-app.exe` 还是 13:39——MoonBit 源码没动，moon 就认为产物最新，于是白盒测试全绿、真窗口里 GIF 依旧空白。要删 `_build/native/debug/build/NoahLiu/native-gui/examples/<示例名>`（注意 `moon run` 的可执行文件在 `build/` 子路径下，不在 `execbin/`）。**判据**：比对 `.a` 与 `.exe` 的 mtime，别看「刚跑过就是新的」。
- **GdkPixbuf 动画迭代器是「懒起算 + 只认绝对时刻」**：`gdk_pixbuf_animation_iter_advance(iter, t)` 的第一次调用只把动画起点锚在 `t` 上、必回报「没换帧」；之后换不换完全由加载器按累计时间判定。所以本层的虚拟时钟**每拍只推「当前帧时长 +1ms」**（与真实时间同速），组件按 `delay_ms` 的节奏反复问——早期写成「一次调用里连推四拍」，动画就会比实际快四倍。
- **本机 gif 加载器读不到 `tDelay`**（实测该选项为 NULL，与 PIL 报的 400ms 不符）→ 退回 100ms/拍的轮询；因为换帧时机由虚拟时钟与加载器共同决定，实际仍是每 400ms 换一帧（真窗口 12 秒 `gif=30` 帧 ≈ 2.5 帧/秒，与素材逐帧时长对得上）。
- **`loop` 与 `static` 都是 MoonBit 保留字**：参数名 `loop~` 直接解析失败（改用 `looping~`），结构体字段 `static` 触发 `reserved_keyword` 警告（改 `is_static`）。
- **图标按钮的悬停底色取样点**：圆角 4 的 `fill_round_rect` 会把贴角那格裁掉，像素断言要取上缘中点（`(w/2, 2)`），取 `(1,1)` 会读到「没变」。
- **验证**：`moon test -p NoahLiu/native-gui/render` **42/42**（新增 1 条缩放回归：同一张源图在 120/72/48 三档目标下的不透明包围盒分别为 (20,20)-(99,99)/(12,12)-(59,59)/(8,8)-(39,39)，另含 `draw_image_from_rect` 的取样域不外溢）；`moon test -p .../gui/ui` **107/107**（新增 3 条：动图组件按帧自转/暂停断链/`play` 续上/静图不排自转，且 48×48 缩放后确实有墨；图标按钮尺寸、悬停换底、抬起出框不算点击、禁用不吃事件）；`core` 62/62、`yoga-mbt` 96/96，逐包 `--deny-warn` 全零警告、全仓红点仍 287 errors / 68 warnings 未增。真窗口回证（`examples/native-app` 加「图标与动图」区块，几何行补 `NATIVE-APP-MEDIA`，状态行补 `gif=`/`ib=`）：注入「点图标按钮」得 `ib=1`、`gif=30`（自转换帧数）、退出码 0；截图复核图标随主题取色、✕ 图标按钮、48×48 的 GIF 圆点确实画在框内（此前是一片空白）。

### MoonBit 原生 GUI 栈 · 主题跟随系统（`theme_from_system` + `App::follow_system_theme`）与 style 通道定案

- **主题包不依赖平台层，跟随逻辑放窗口层**：`theme` 只收两个读数函数作参数（`theme_from_system(sys_color_scheme, sys_accent)`），真正的探针在 `win`、轮询与 `theme_apply` 在 `core/app.mbt`（`App::follow_system_theme(interval_ms)` 返回停表函数）。这样主题包保持零平台依赖（`core` 反过来依赖它不成环），且「跟随」这条策略在无头测试里能用假读数函数直接测四态。与 `local_ymd` 同一个理由：平台探针经 core 转发，示例与集成层不必引用 `win`。
- **读的是桌面环境的 gsettings，不是原生控件样式表**：`org.gnome.desktop.interface` 的 `color-scheme` 优先（值里含 dark/light 才算），读不到再退 `gtk-theme` 名字（大小写归一后找 dark/light）；主色读 `org.gnome.desktop.wm.preferences button-settings`（若直接写了 `#rrggbb`）或 `accent-color`（GNOME 给的是 **blue/teal 这类名字**，本层查表转 hex）。**必须先 `g_settings_schema_has_key` 再读**：本机 schema 里就没有 `accent-color` 键，直接 `g_settings_get_string` 会打 GLib 关键警告。GSettings 对象建一次常驻（每拍新建销毁会反复走 dconf）。
- **本机实测口径（Ubuntu 24.04 + XFCE）**：装了 GNOME 的 schema（`gsettings list-schemas` 里 `org.gnome.desktop.*` 有 38 个），`color-scheme='default'`（既不是 dark 也不是 light → 落到 `gtk-theme='Orchis-Teal-Light-Compact'` → 归一后含 light → 报 "light"），`accent-color` 无此键 → 主色空串。所以 `theme_from_system` 走「亮色 + 内置主色」，与默认盘一致；真窗口状态行回证 `sys='light/'`、`fing=#2D68C4/#F5F6F7`。**判据**：跟随循环只在**指纹**（`primary/bg_page`）变化时才 `theme_apply`，读不出来的桌面每拍算出同一份 → 零重刷。
- **style 通道定案：新栈不做 CSS 风格式样式表**。master 那五个助手（`themed_container`/`set_panel_bg`/`bind_bg`/`bind_fg`/`bind_popover_bg`）存在的前提是「原生控件的底色/字色是命令式设进去的固定值，主题换了不会自己变」；本栈组件在 `on_draw` 里现取主题色板，换主题时靠进程级的一次订阅整体重绘（`watch_theme`），这五个助手在新栈里**结构性不需要**。调用方要覆盖尺寸/间距/底色，走两条更直接的路：组件的类型化参数（`width=`/`bg=`/`padding=`…），或 `handle=fn(w){ ... }` 拿到底层控件自己设 yoga 样式——后者就是本栈的「样式逃生舱」，比维护一张字符串样式表更类型安全。`sub_bag` 批量退订早已在 `core/signal.mbt` 落地并被组件批次反复覆盖（重建式列表整代退订）。
- **验证**：`moon test -p NoahLiu/native-gui/theme` **8/8**（新增 1 条：深浅与主色四态的指纹关系——读不出与读到 light 同指纹、dark 与 light 不同、给了 accent 就走派生公式且与 `theme_from_accent` 一致、`theme_apply_system` 之后 getter 与指纹跟随新快照）；`ui` 107/107、`core` 62/62、`render` 42/42、`yoga-mbt` 96/96，逐包 `--deny-warn` 全零警告、全仓红点仍 287 errors / 68 warnings 未增。真窗口回证（`examples/native-app` 起 `follow_system_theme(interval_ms=1000)` 并在 3 秒处停表验证停表函数归属）：状态行补 `sys='light/'` 与 `fing=#2D68C4/#F5F6F7`、`frames=118` 与其余读数不变、退出码 0。**系统主题真的切换时界面是否即时重着色**由用户在真机复验（可临时 `gsettings set org.gnome.desktop.interface color-scheme prefer-dark` 观察），助手侧不代改桌面设置。

### MoonBit 原生 GUI 栈 · 图表首批（`chart`：算法层 + 折线/柱状/环形/仪表/散点）

- **另起新包而不是原地改 `yue/charts`**：旧目录引用 `@yue` 根包与旧 Painter 契约，属全仓红点积压；新栈要守「本包 `--deny-warn` 零警告」这条分包门禁，混在一起就无从谈起（与 `yue/components` → `ui` 同一个理由）。新包三层：`algo.mbt`（纯函数，与 master 同源：滚动窗口/坐标换算/1-2-5 刻度/单位换挡/柱槽与命中/扇区角度/仪表弧度/最小二乘/值域留白/截断）、`draw.mbt`（绘制，只吃纯函数的结果）、`components.mbt`（`@core.Node` 组件）。
- **像素断言的口径换了**：图表组件在 `on_draw` 里先铺一层面板底，于是「有墨像素数（alpha>0）」恒等于整块面积——本批 5 条用例第一次全假失败就是这个原因。改判据：**两张位图逐像素比差异**（`diff_of`），「换数据后画面变了」与「离开后复原」都用它（后者断言差异恰为 0）。这条对所有「先铺底再画内容」的组件都成立，不只是图表。
- **密集折线的绘制成本与窗口大小脱钩**（沿用 master 定案）：按像素列抽稀，每列取 (x, y_min, y_max) 保极值；面积模式每列填一个到锚线的矩形（填充顶边即折线，不再另描），折线模式每列画 min..max 竖条。稀疏（点数 ≤ 列数）才走真折线 + 多边形面积。依据是软件光栅化下每段描边约 1.8µs，1000 点 × 4 序列全描边超 5ms 验收线。
- **环形命中是新写的 `donut_hit`**（极坐标判扇区，圆心/半径公式与 `draw_donut` 同源，中心孔与圆外给 -1）；柱状命中仍用 master 的 `bar_hit`（与绘制共用槽宽公式，否则高亮与柱子错位）。
- **复用 `ui` 的地基而不是重抄**：`follow_store`/`watch_theme`/`text_width`/`fill_round_rect`/`default_handle` 从 `pub` 出去给图表包用。之前它们在 `ui` 内是私有的，图表包若要同样的东西只能再抄一份订阅逻辑（`watch_theme` 的「进程级只订阅一次」正是不能复制的那条）。
- **四条工具链写法（本批实测）**：① `pub const` 的名字**必须大写**（`pub const pi` 直接报「Expected upper case identifier for name of const, found lower case. Did you mean let?」），小写常量用 `pub let`；② `for i = 1..<n { }` 不支持——range 只在 `for x in a..<b` 里合法，经典 for 要写 `for i = 1; i < n; i = i + 1`；③ `StringBuilder` 的写入方法是 `write_string`/`write_char`，没有 `add`/`append`；④ `Ordering` 类型在本工具链不可直接引用（写比较器函数会报「The type Ordering is undefined」），几个元素排序退回插入排序。
- **验证**：`moon test -p NoahLiu/native-gui/chart` **11/11**（6 条纯函数：窗口丢最旧与越界无操作、值域退化与留白比例、1-2-5 步长与负区间起点、单位换挡 k/M/G、柱槽与两形态命中、扇区只累计正值且单扇区留 0.0002 弧度、仪表分段取色与折线段数、回归退化、8 位色串、标签截断；5 条组件：折线换数据与密集抽推出图、柱状悬停换底与离开复原、环形出图 + 命中四态、仪表盘 smooth 两路（直接跳到位 / 逐拍逼近）、散点带趋势线）。逐包 `--deny-warn` 全零警告、全仓红点仍 287 errors / 68 warnings 未增。真窗口回证（`examples/native-app` 加「图表」区块：折线+柱状一行、环形+仪表+散点+推点按钮一行，几何行补 `NATIVE-APP-CH`，状态行补 `ln=`/`chp=`）：注入「点三次推点按钮」得 `ln=27/23 chp=3`（窗口 24→27 点、末值 7→23，与手算 `pushes*7%29+2` 逐位一致）、退出码 0；截图复核五图齐备——折线带面积填充与右端最新值标注、柱状正负异色带类目、环形中心汇总 + 右侧图例带百分比、仪表 68% 弧与中心数字、散点带最小二乘趋势线。

### MoonBit 原生 GUI 栈 · sys 批 3（硬件族六件：brightness / volume / nightlight / printer / powerprofile / monitor）

- **依赖注入解 DBus 耦合**：brightness 的写路径（logind 在线探测 + SetBrightness）在 master 走 `@traybus`；新栈把两处改成**进程级注入槽**——`brightness_set_logind_probe(()->Bool)` 与 `brightness_set_action((subsystem,name,value)->String)`（空串成功、非空错误串），DBus 线接入后由 traybus 侧注入实做，读路径（设备枚举/当前值/最大值，纯 sysfs）不依赖槽。模式与 `ci_tooltip` 的回调反转同构：**语义层定义槽、平台层注入**。
- **monitor 从会话族提前**：夜灯（nightlight）的显示器枚举依赖 monitor（xrandr），而 monitor 只依赖 platform + pr_run，无 DBus——按依赖序归入本批。
- **挪 DBus 线的三件**：`sensor`（iio-sensor-proxy）/`bluetooth`（org.bluez）走 `@traybus` 通用 D-Bus 层属性读取；`disk`（UDisks2）50 处 `@traybus.gdbus_call_system`——它们的核心是总线调用而非命令行，本批不强拆。
- **验证**：`moon test -p NoahLiu/native-gui/sys` **41/41**（新增 11：monitor 的 xrandr 解析矩阵 + 六文件的 pr_run 命令面/解析纯函数同源平移；brightness 注入槽未注入时 set 走 Unsupported、读路径本机真 sysfs）；`moon check sys --deny-warn` 零警告、全仓红点仍 287/68。**真机复验**：volume 音量增减与静音、brightness 读当前值、powerprofile 列表与切换、printer 打印机枚举、nightlight 色温生效、monitor 分辨率列表。

### MoonBit 原生 GUI 栈 · sys 批 1（`sys`：fsx / envx / procrun）

- **sys 桩直接走 native-stub**：目录枚举（dirent）/环境变量（setenv/unsetenv）/文本读写（fopen）/删文件只用标准头，**不需要** win/render/text 桩那套「prebuild 编静态库 + portable 占位」——那些是因为要 GTK 头（native-stub 拿不到 pkg-config 路径）。单文件 `sys_stub.c` 顶部 `#if` 分平台（Windows 分支占位，FindFirstFileW 宽字符路由待 M2），`moonbit_make_bytes` 以 `extern` 声明直接链运行时符号（ime_probe_stub 同款）。
- **`sys_getenv` 走 C 层 getenv 而非 core/env**：进程内 setenv 后要「立即可读」（master 的测试口径），core/env 的环境表在部分实现是启动快照——需要实时语义的读走桩，纯读取场景仍可用 core/env。桩上顺带落了 `sys_read/write_text_file`、`sys_remove_file`（幂等）、`sys_platform()`（编译期 `#if` 判定，master 的 `@yue.platform()` 等价）。
- **procrun 只换依赖面**：`@yue.read_text_file/ffi_remove_file/platform` → 本包 `sys_*` 三件；`@subproc`（chensuiyi/subproc）本就在主模块依赖，`pr_run` 的 spawn → 限时回收 → 临时文件捕获 → C locale 全套原样。
- **平移坑**：旧 wbtest 的 `utf8_bytes/from_utf8_bytes`（根包 helper）→ `@utf8.encode/decode_lossy`；`ffi_getenv_bytes` 的出参 `ok` Ref 断言模式换成返回 `Option` 的 `sys_getenv` 后，旁边残行的 `inspect(ok.val)` 要一并清（改签名不清断言是编译期炸）。
- **验证**：`moon test -p NoahLiu/native-gui/sys` **29/29**（fsx：真实目录枚举含临时文件/`..` 排除/打不开分支、扁平文本解码、进程内写读改删回环含 overwrite=false 保持/幂等删/`a=b` 拒绝；envx：单点读与 core/env 对照、common 集合存在才收/XDG_* 全扫、错误分支；procrun：`pr_available`/`pr_run` 真子进程回环——`echo`/非零退出 stderr 捕获/超时强杀、`/bin/sh` 脚本路）。`moon check sys --deny-warn` 零警告、全仓红点仍 287/68。

### MoonBit 原生 GUI 栈 · Markdown 视图（新包 `mdview`，组件库收口）

- **新包不复用旧目录**：master 的 `yue/markdown` 依赖 `@yue` 根包（红点区），新栈按「一文件夹一包」惯例落 `mdview`（`mizchi/markdown@0.8.3` 已在主模块依赖里，新包 import 即用）。纯函数层（展平/区间计量/脚注扫描/切行）与 master 零差异平移；渲染层换组件面（`@ui.hbox/vbox/label/separator/checkbox/code_view`、`@render.Image`、`@text.AttributedText`）。
- **链接打开改 `on_link` 回调**：master 的富文本行点击直接 `@yue.open_url`；新栈 open_url 属系统能力线（桌面集成族待平移），`markdown_view` 增 `on_link? : (String) -> Unit` 参数、经 `MDCtx` 链传进富文本行闭包——**初版用进程级单槽转发，因多实例互相覆盖改为 ctx 链传**（结构体函数字段按函数应用要写 `(ctx.on_link)(u)`，直接 `ctx.on_link(u)` 报「has no method」）。
- **富文本行的主题跟随按指纹缓存**：AttributedText 重建不能放 on_draw 每帧做（动画帧会反复重建），也不能只在构造期做一次（链接/代码色不随主题）——`on_draw` 里比对 `@theme.theme_fingerprint_of(theme_current())`，指纹变了才重建。
- **块间距策略换了**：master 各块自带 marginBottom（style 串）；新栈 `@ui.hbox/vbox` 只有四边 padding、无 padding_bottom 参数——块间距统一交最外层 `vbox` 的 `row_gap`，个别块的底部留白走 `node.set_margin_bottom(@yoga.fixed(...))`。
- **验证**：`moon test -p NoahLiu/native-gui/mdview` **26/26**（24 条纯函数/展平/区间/GFM 断言同源平移——UTF-16 计量/emoji、脚注编号顺序、引用式链接定义、删除线/上标区间、fence info 首词、切行、图片路径剥 `file://`、表格对齐映射改 `is` 模式断言（yoga 枚举未实现 Eq）；2 条组件挂载——GFM 全要素文档（标题/粗斜删/链接/任务列表/有序/引用/代码块/表格/分隔线/定义列表/脚注）子树 >5 节点且高度按内容长出、链接点击回调不崩）；`moon check mdview --deny-warn` 零警告、全仓红点仍 287/68。真窗口几何行确认布局（`md=24,2745,420x403`），观感留用户真机复验。**至此组件库各族 + Markdown 全部收口**。

### MoonBit 原生 GUI 栈 · code_view 代码高亮（`ui/codeview.mbt`）

- **分词器原样平移、组件换形态**：`Token`/`lang_keywords`（8 语言关键字表）/`tokenize_lang`/`classify_word` 与 master 的 `components_text.mbt` 同源零改动（工具链写法本就是新口径）；`code_view` 从「AttributedText 预排版 + draw_attributed_text」换成「构造期逐 token `@ui.text_width` 测宽 → on_draw 逐段 `@text.draw_box_at`」——旧链路为绕 Windows AttributedText 区间色缺陷的整段设色手法在新栈结构性不需要（自绘直出），行高取 `@text.line_height_font`。
- **逐纯色像素计数是脆弱断言**：13px 等宽小字形（如关键字 "fn"）经次像素抗锯齿后**字芯可能没有一个纯色像素**（本批 `purple=0` 而 6 字符的中文串 `green=22`）——组件像素断言改按「非底色墨迹总数」，逐色断言只对大面积色块（图表扇区/色带）可靠。
- **验证**：`moon test -p NoahLiu/native-gui/ui` **110/110**（新增 3：tokenize 断言同源平移——关键字/类型/限定名/调用/区间/字符串/注释/多语言；组件挂载——深底占九成、墨迹 >150、高度随行数线性）；`moon check ui --deny-warn` 零警告、全仓红点仍 287/68。真窗口几何行确认布局（`code=24,2745,400x153`，moonbit 带行号 + python 两块），观感留用户真机复验。

### MoonBit 原生 GUI 栈 · 专项图批 4（`chart`：effectscatter / themeriver / geo，图表线收口）

- **8 位色串的两种语义冲突（本批实测）**：旧链路图表约定 `#AARRGGBB`（alpha 在前，见「yue 色值与绘制三坑」），而新栈 `@render.Color::parse` 的 8 位语义是 **RGBA（alpha 在后）**。`eff_alpha_color` 直接把 8 位输入喂 `@theme.parse_hex` 会把 alpha 位当红色（`#ff009688` 解析出 r=255——`"#ffff0096" != "#ff009688"` 的根因）；修复：**8 位输入先剥前两位 alpha、取后 6 位解析**（旧链路「RGB 不被改写」语义），新 alpha 由参数重新合成。
- **涟漪动画从「回调返 false 注销」改成真句柄**：旧链路 `set_timer` 无取消 id，停止靠回调返回 false；新栈 `@core.set_timeout`/`clear_timeout` 有真句柄——`EffAnim` 持 `running + timer`，`eff_stop` 即时取消待触发回调（carousel 自转同款续排模式：回调里再 `set_timeout` 下一拍）。
- **GeoJSON 的 JSON 解析走 `@sys`**（`vsc_json_parse` 已平移在 sys），`RectF` 改本地 `GeoRect`（与 treemap 的 `TmRect` 同形各自定义）；`argb_hex` 旧链路在根包红点里，图表包本地实现（`Int::unsafe_to_char` 拼 hex，注意 `Char::from_int` 已弃用）。
- **三条测试教训（本批踩全）**：① `ink_of` 对「铺面板底」的组件恒等于整块面积（首批图表的坑，无头默认主题 bg_panel 还是**纯白** `#FFFFFF`，白底也算墨）——断言内容用**特征色采样**或 `diff_of`；② themeriver 图例预留 240px，画布须 >298 才有绘制区（组件默认宽 560），窄画布测试会整幅早退且无任何报错；③ **测试里手写的 JSON 要用外部验证器过一遍**——本批坐标数组多写一个 `]`，解析器如实返回 None，一度误判为解析器 bug（分段二分全过、完整串挂时优先怀疑字符串本身）。
- **验证**：`moon test -p NoahLiu/native-gui/chart` **189/189**（新增 43：三份 wbtest 同源平移 40 + 组件挂载 3——涟漪换数据变与 eff_stop 后 is_running=false、河流换序列变（画布 560）、地图解析+区域飞线出像素+清空变）；包 `--deny-warn` 零警告、全仓红点仍 287/68。真窗口几何行确认布局（`eff=24,2542,300x170`），视觉观感留用户真机复验。**至此图表线 15 种专项图 + 五种通用图 + 交互层全部收口**。

### MoonBit 原生 GUI 栈 · 专项图批 3（`chart`：sunburst / graph / parallel / pictorialbar）

- **与批 2 同一套路**：转换脚本做依赖名替换，手工段三类——「暂无数据」块、条件对齐的 `draw_text`（pictorialbar 的 4 处省略 `wrap=` 参数，正则要求 wrap 才匹配故漏，这类「省默认参数」的调用形态也要手改）、组件层 mount 块。旭日图中心汇总（20px SemiBold + 「总计」caption）与 `draw_donut_core` 同款 `@text.draw_box_at` 写法。
- **`SunItem`/`TreeItem`/`TmItem` 同字段结构在包内字面量构造会「Mutiple possible record types」**：三个 `{name, value, children}` 形状相同，字面量无法消歧——统一走 `make` + `children.push`（数组字段内容可变），跨包同理（批 2 的坑在此复现并定案为通用口径）。
- **可选参数的位置传参限制**：`GraphNode::make(name, value? : Double)` 与 `GraphEdge::make(s, t, weight? : Double)` 的可选参数**不能按位置传**（`make("甲", 30.0)` 报 requires 1 positional arguments）——一律 `value=30.0`/`weight=5.0` 命名传参。`SunItem::make` 的 `value? : Double?` 是双层 Option，数值要包 `Some(v)`。
- **graph 的布局缓存改挂回收袋**：旧链路 `subscribe` 里清缓存 + `schedule_paint`；新栈 `follow_store` 只管重绘，缓存失效单独 `subscribe_id` + `sub_bag_register` 退订（与 gauge_t 同模式）。
- **验证**：`moon test -p NoahLiu/native-gui/chart` **146/146**（新增 48：四份 wbtest 同源平移 44 + 组件挂载 4——旭日换数据变、关系图数据变更后布局缓存失效画面变、平行坐标换行变、象形柱两形态出像素）；包 `--deny-warn` 零警告、全仓红点仍 287/68。真窗口几何行确认布局（`gph=282,2346,260x190`），视觉观感留用户真机复验。

### MoonBit 原生 GUI 栈 · 专项图批 2（`chart`：kline / sankey / treemap / tree）

- **机械平移 + 手工段**：四个文件用转换脚本做依赖名替换（`@yue.*` → `@theme`/`@render`/`@core`/本包函数），「暂无数据」块、条件 align 的 `draw_text`、组件层 mount 块三处手工改写——`draw_text` 的 `align=` 允许任意表达式（`align=if first_col { @text.End } else { @text.Start }`），转换器按字面量枚举匹配会漏，这类段落一律手改。
- **treemap 的 `RectF` 改本地 `TmRect`**：旧链路复用根包 `RectF`（x/y/width/height），新栈 core 的 `Rect` 字段名是 w/h 且语义是布局矩形——图表包自带同形 `TmRect`（15 处替换），不引跨语义依赖。`from_hsl` 在 `@theme.palette` 就位。
- **`tree_chart_t` 的 `orientation : String` 改 `vertical : Bool`**：旧链路字符串参数（"horizontal"/"vertical"）是历史 API 形态，新栈组件参数一律类型化（对齐 `bar_chart_t` 的 `horizontal?`）。
- **TreeItem/TmItem 跨包构造必须走 `make`**：`pub(all) struct` 的字面量构造在定义包之外报「There is no record definition with the fields」（native-app 里构造树数据踩到）——跨包构造统一 `TreeItem::make(name, value=…)` + `children.push(…)`（children 是数组字段，内容可变）。
- **验证**：`moon test -p NoahLiu/native-gui/chart` **98/98**（新增 34：kline/sankey/treemap/tree 四份 wbtest 同源平移 29 条 + 组件挂载 5 条——K 线涨红跌绿两色都出像素、桑基出图换数据变、树图 hover 提亮与复原（flat 画卷与绘制同源）、树图两形态出像素）；包 `--deny-warn` 零警告、全仓红点仍 287/68。真窗口几何行确认布局（`NATIVE-APP-CHSP sankey=332,2190,300x150`），截图复核受限：窗口 2500 高已超 XFCE 允许的移动范围（`windowmove -1346` 被 WM 钳到 -1278，目标区块底部出屏且钳制路径下 GTK 丢失 expose、截到空 backing）——**视觉观感留用户真机复验**（native-app 专项图区块第二行）。

### MoonBit 原生 GUI 栈 · 专项图批 1（`chart`：boxplot / funnel / heatmap / radar）

- **一图一文件、同源平移**：master 的 `charts_boxplot.mbt`/`charts_funnel.mbt`/`charts_heatmap.mbt`/`charts_radar.mbt` 各平移为 `boxplot.mbt`/`funnel.mbt`/`heatmap.mbt`/`radar.mbt`（纯函数层原样 + 绘制层换 `@render.Painter`/`@text.draw_box_at`/`@theme` 现取色 + 组件层换 `node_of_new` 形态），wbtest 四份对应平移并各补一条**组件挂载出像素断言**（`ink_of > N` + 换数据 `diff_of > 50` + 空数据/维度不足不崩）——纯函数对而组件没接线的回归第一次就能被抓住。旧链路 `AttributedText`「暂无数据」统一换成 `@text.draw_box_at` 固定盒写法（与 `draw.mbt` 同款）。
- **依赖全在新栈就位**：`mix_hex`/`lighten_hex`/`parse_hex`/`rgb_to_hsl` 在 `@theme.palette`，`bar_slot`/`draw_hgrid`/`series_color`/`fmt_axis`/`truncate_to` 复用本包；`mut_view().sort_by(fn(a,b){ -1/0/1 })` 在本工具链可用（返回 Int 的比较器，与 `Ordering` 不可用的坑无关）。
- **验证**：`moon test -p NoahLiu/native-gui/chart` **64/64**（新增 27：箱线分位插值/五数/双端离群/IQR 零、漏斗排序保序/层几何/梯形宽/占比、热力量程/色带插值/格坐标、雷达角度/多边形/量程归一/布局 + 四组件挂载）；`moon check chart --deny-warn` 零警告、全仓红点仍 287 errors / 68 warnings。真窗口回证（`examples/native-app` 加「专项图」区块，窗口加高到 1400×2300，几何行补 `NATIVE-APP-CHSP`）：退出码 0；截图特征色采样四图齐全——箱线 success 箱体 68px + danger 离群红点 28px、漏斗主色首层 3508px、热力浅主色 5773px + 深主色 1944px（色带梯度）、雷达双系列 169/168px。**观感由用户真机复验**。
- **截图实操补充**：窗口移出屏幕过远时 X 会清掉屏外 backing（`import -window` 截到全灰 242）——把目标区块移进屏但**保留窗口大半可见**（本机窗口高 2300 时 client 原点 -1200 左右），截图像素采样才有效。

### MoonBit 原生 GUI 栈 · 图表交互层（`chart`：tooltip + DataZoom/VisualMap/mark/导出 + 可点击图例 + `charts_it` 三交互图）

- **平移面与文件对应**：master 的 `charts_tooltip.mbt`/`charts_interactive.mbt`/`charts_it.mbt` 三个文件同源平移为 `tooltip.mbt`（`CiTip` 浮层状态与防出界定位、`CiPlot` 绘制区、最近点 `ci_nearest_idx`/扇区 `ci_sector_at` 命中、`ci_tooltip` 交互画布组件）、`interactive.mbt`（`CiZoom` 窗口数学全套、`CiVisualMap` 色带、`ci_mark_line`/`ci_mark_area`、`ci_save` 离屏导出、图例命中与显隐位工具、`ci_legend` 组件）、`charts_it.mbt`（`line_chart_it`/`bar_chart_it`/`donut_chart_it`）；wbtest 三份对应平移。
- **图例色的形态改了：不存色串，存 (名字, 原始序号) + `color_at` 现取**。master 把 (名字, 色串) 固化进 Store，主题一换色板全旧，要靠 `on_theme_change` 重建整套 items；新栈 `ci_legend` 收 `color_at : (Int) -> String` 在 `on_draw` 里现取（系列色/环形色/柱状正负色都是主题色现取），主题切换经进程级 `watch_theme` 整体重绘即自动新色，**`on_theme_change` 重建那条链结构性不需要**。柱状的正负分色闭包直接捕获数据 Store 现值判定。
- **`on_scroll` 的回调签名没有控件首参**（`Option[(ScrollEvent) -> Bool]`，与 `on_draw`/`on_pointer` 不同——后两者首参给控件是为了避免引用环，滚轮回调拿不到）。滚轮换算缩放锚点要画布宽高，解法是**构造闭包里持一个尺寸 Ref，`on_draw`（有首参）每帧刷新，`on_scroll` 读最近一帧**——组件可见必然先画过一帧，不存在读到 (0,0) 的窗口期。
- **`ci_tooltip` 加了 `on_leave` 回调**：浮层收起只藏 `CiTip`，但调用方自记的 hover 状态（折线准线/落点、扇区外扩）是 `hit` 之外的绘制态，不清就残留——白盒「离开后复原」断言第一次失败（diff=276/1012）就是准线与外扩还在画。三个交互组件都接 `on_leave=fn(){ hover.val = -1 }`。
- **拖拽捕获不再自己管**：master 的 `set_capture`/`release_capture` 在新栈结构性不需要——宿主 `route_pointer` 在 `Down` 时自动让命中者成为捕获者，之后的 `Move`/`Up` 一律投给它（指针出界不丢抬起）。
- **`draw_donut` 拆出 `draw_donut_core`**（扇区 + 中心汇总，色经 `color_at` 参数）：交互版的图例由 `ci_legend` 承担（可点击/可显隐），不能复用原图例内嵌的 `draw_donut`；`draw_donut` 自己变薄壳（core + 内嵌图例）。`ci_sector_at`（带厚度参数的通用扇区命中）与首批为固定厚度写的简化版 `donut_hit` 并存——交互版环厚可配，命中几何必须同源跟随。
- **PNG 导出在本栈 Linux 真可用**（`render/png.mbt` 纯实现，不走平台 shim）：master 的 `ci_save` 在非 Windows 恒失败（shim 未暴露导出 API），wbtest 只能测格式校验不触盘；新栈 wbtest 直接真落盘 `/tmp` 断言 `Ok`，`ci_save_chart` 的离屏 `Painter` 用完必须 `end()`（Cairo 会话槽有限）。
- **xdotool 的 XTest 滚轮注入对 GTK3 无效（本批实测，注入工具局限而非代码问题）**：`xdotool click 4/5` 在 X 层正常产生 button4/5 事件（`xev` 收到、synthetic NO），但 GTK3 的 X11 后端走 XInput2，**不把 XTest 的 core 按钮事件转成 scroll-event**——20 行最小 GTK 探针（只连 scroll-event + fprintf）复现实锤，桩侧 `wm_on_scroll` 一条都没进。滚轮缩放的组件链路由白盒 `dispatch_scroll` 直调覆盖（注入 `dy:1` → 窗收窄 → 像素变），**真机滚轮手感/观感留给用户复验**；将来要程序化注入滚轮得走 uinput（`/dev/uinput` 在，ydotool/evemu 未装）。
- **真机截图的坐标三重对齐（10px 小目标踩的坑）**：① `xdotool mousemove --window` 给的是 **client 相对坐标**（与 GTK 事件坐标同系，注入不用换算）；② `import -window` 在窗口比屏幕高时只截**屏幕可见部分**，截图原点是屏幕而不是窗口（本机窗口 2080 高 vs 屏幕 1080，窗口被移到负 Y 后截图 y = client y − 866）；③ frame 与 client 差一个标题栏（XFCE 34px）。第一次按错误偏移采样得出「图例色块没画」的错误结论——10px 的色块偏 34px 就完全错过，**先对齐（鼠标落点 `getmouselocation` 反推 client 原点）再下「没画」的结论**；同理窗口比屏幕高时注入点必须先 `xdotool windowmove` 负坐标把目标区块移进屏（XTest 坐标被钳屏幕底边，落在屏外等于没注入）。
- **验证**：`moon test -p NoahLiu/native-gui/chart` **37/37**（新增 26 条：tooltip 三份 wbtest 平移——浮层尺寸估算/防出界定位/最近点与 map_idx 互逆/扇区四象限与环带容差/`CiPlot` 分数与退化；zoom 数学全套——归一/设窗/滚轮锚点不变式/平移边界/可见区间、VisualMap 两色带三色带与非法色回退、图例命中累加几何与宽度门槛、显隐位补齐/翻转/过滤（含偏移寻址）、切片收窄、`ci_save_chart` 尺寸与格式校验 + PNG 真落盘；三交互组件挂载注入——折线 hover 出浮层与准线且离开复原、图例点击隐藏序列画面变、柱状 `dispatch_scroll` 直调缩放改窗、环形扇区 hover 外扩与复原；纯函数——plot 边距与绘制同源、环形几何环厚钳内径、items 原始序号与色板循环、窗口定标取最长序列）。逐包测试全绿（core 62/input 10/render 42/text 29/icons 4/theme 8/sys 7/ui 107/chart 37）、逐包 `--deny-warn` 全零警告、`yoga-mbt` 96/96、全仓红点仍 287 errors / 68 warnings 未增。真窗口回证（`examples/native-app` 加「交互图表」区块，窗口加高到 1400×2080，几何行补 `NATIVE-APP-CHIT`）：退出码 0；注入「柱状画布滚轮（未生效，见上）→ 环形图例第一项点击 → 环形扇区 hover → 折线画布 hover」后像素采样逐项对上——图例色块齐全（含柱状负值项红色 `(214,69,80)`）、**隐藏项色块变 border 灰 `(216,220,225)`**、12 点方向第一扇区（primary 蓝）消失且剩余扇区重分配（该位置变 success 绿）、tooltip 深底 `(49,49,51)` 落在 hover 点右侧、折线 hover 处有落点色。**滚轮缩放、tooltip 跟手观感、图例点击手感**由用户真机复验。

### MoonBit 原生 GUI 栈 · 平台输入映射层（另线 #19 首批：`core/input_map.mbt`）

- **为什么先落表不先后端**：Windows/macOS 后端在这台机器上验不了（无真机），按「不写不可验的代码」的纪律，先把**平台无关的口径**做成纯函数 + 回归：三平台修饰位折算、两套键码表（Win32 虚拟键码 / macOS `kVK_*`）、shift 折算、按钮号、以及「这颗键先交给谁」的路由表。后端落地时照表填，不必各自再决定一次语义、也不会决定成三个版本。
- **三条口径**：① keysym 用 **X11 值**（Linux 后端本来就是 GDK keyval，另两平台向它对齐），可打印 ASCII 就是字符码；② 字母与数字给**未加 shift 的基码**，shift/caps 由 `win_apply_shift` 折算——X11 的 keyval 已带 shift 语义而 Windows 的虚拟键码没有，不补这一步「Shift+A」会被当成 'a'；③ 符号键（OEM 那一排）**不硬编键盘布局表**：Windows 走 `WM_CHAR`/Unicode、macOS 走 `charactersIgnoringModifiers`，硬编既错得多也维护不起。
- **一条实测语义纠正（写进判定表）**：光标与选区类键要**带 Ctrl 也算内核键**（Ctrl+左右=按词跳、Ctrl+Home/End=到首尾，正是编辑器最常用的动作），但**带 Alt 不算**（Alt+左右是「后退」这类宿主动作）。次序即语义：组合中 → 光标键 → Tab/Shift+Tab（焦点环绕）→ 快捷键组合 → 可打印键（先过输入法）→ 其余归宿主。
- **权威归属要写死在两处注释里**：Linux 的修饰位折算目前在 `win/stub.c` 的 `wm_mods`（C 侧必须自己折，不能反过来调 MoonBit），它与 `gtk_mods_to_mods` **逐位一致**——两边注释都点名了对方，改一处必须改另一处；表的可执行定义在 MoonBit 侧（有回归钉住）。
- **macOS 的 `kVK_*` 只覆盖特殊键**：Return/Tab/Space/退格/ForwardDelete/Home/End/PageUp/PageDown/方向/F1-F12/小键盘——字母与数字**故意不映射**（mac 的字符要由事件带的 Unicode 文本给，键盘布局由系统解析）。另外 mac 的 `kVK_Delete`(51) 是**退格**、`kVK_ForwardDelete`(117) 才是删除，这条最容易记反，断言里两条都钉了。
- **验证**：`moon test -p NoahLiu/native-gui/core` **78/78**（新增 7 条：三平台修饰位含「GDK lock 位不算修饰键」「Windows 按钮位不混进修饰位」、Win VK 表（字母/数字/控制/功能/小键盘/未知给 0）、shift 折算（字母看 shift 异或 caps、数字符号查表、表外原样）、mac VK 表（退格与删除分别钉）、按钮号（Win `MK_*` 与 mac `buttonNumber` 都折成 1 左 2 中 3 右）、路由表六条规则、reset 与 surrounding 的触发条件）；`moon check core` `--deny-warn` 零警告；全仓红点仍 287 errors / 68 warnings。本批**没有真机回证**（全是纯函数），后端接线随 Windows 地基与 mac 真机走。

### MoonBit 原生 GUI 栈 · 媒体播放器（批 D：新包 `yue/media`，CPU 回灌 + 软解）

- **引擎是平移不是重写**：`modules/gui-media` 的 `audio_player.mbt`(416 行) 与 `video_player.mbt`(476 行) 实测**零 @yue 依赖**（只有组件包装层碰 UI），于是引擎与 15 条既有回归整段搬进新包 `yue/media`，只改测试素材路径与一个公开口。旧链踩过的坑（音画不同轴、seek 后进度从零重涨、换载崩溃、播完态与初始态要区分）就随那批测试一起进了新栈——**这批的价值一半在「把老师写对的东西接住」**。
- **素材路径口径变了**：native 测试的可执行文件 cwd 是**工作区根**，不是包目录（旧包在 `modules/gui-media/src` 时写的是 `../ffmpeg-mbt/src/testdata/`）。新包写 `modules/ffmpeg-mbt/src/testdata/av_1s.mp4` 才对，判据是报错里原样打印的那个相对路径。
- **帧回灌的字节序**：ffmpeg 的 sws 目标是 `AV_PIX_FMT_RGBA`（R,G,B,A），而 `render` 的 `Bitmap` 内部是 Cairo `ARGB32` 的小端布局（B,G,R,A、预乘）。所以灌帧必须换 R/B；不透明像素下预乘等于非预乘，alpha 直接写 255。这条在 `rgba_to_bitmap` 里逐字节钉住（wbtest 断言 `10 20 30 00 → 30 20 10 ff`），真窗口回证是 testsrc 彩条颜色不错位。
- **本工具链没有 `FixedArray::of_list` / `Array::freeze` / `Bytes::of_list`**：造测试字节只能 `FixedArray::make(n, b'\x00')` + 按下标写 + `Bytes::from_array`。另外 `String::split` 给的是 **`StringView` 迭代器**（要 `to_owned()` 才拿到 `String`）、`replace` 是带标签参数（`old=`/`new=`）、`StringBuilder()` 才是构造形态（`Buffer::new` 不存在）、`y` 这类未用形参要写 `_y`。
- **UI 与引擎的分层**：`video` 放在 `yue/media`（包内 import `@core`/`@render`/`@text`/`@theme`），**不放进 `ui`**——否则每个只用按钮的应用都要链 ffmpeg 与 miniaudio。引擎文件（`audio.mbt`/`video.mbt`/`subtitle.mbt`）保持零 UI 依赖，媒体层不依赖 webview，两者只依赖窗口/布局/事件层（积木原则第 1 条）。
- **时钟与重绘**：引擎的 `tick()`（原 `vp_tick`，本批开成公开口 `tick` + 新增 `frames_decoded()`）由 `@core.set_timeout(33, ...)` 自续驱动，**不在绘制里推进**；每 tick 调 `on_tick(位置, 帧数, 是否在播)` 观测口，示例用它证明「帧在推进、时钟在走」而不是一张贴图。图片对象按 `frames_decoded()` 变化才重建（每帧重建 Image 会把 cairo surface 反复建掉）。
- **seek 防抖做成了分区纯函数**：`player_bar_hit` 把控制条切成「最左 34px 播放键 / 右侧 150px 时间文字 / 中间进度轨」，拖动期间只更新显示位置、**抬手才真 seek**——旧链的坑是每次拖动都 seek，关键帧距离长时画面卡一整拍。断言里两条边界值得记：轨道两端是钳制而非越界（449px 处 >0.99 而不是 ==1.0），负坐标落进播放键区（先分区再算比例）。
- **打不开媒体不静默**：`video` 的 `make` 失败时画一块说明板并把原因经 `on_error` 交出去（探测 + 语义化降级），示例的 `err=''` 就是「没有降级发生」的回证。
- **本批未做（记在 TODO，不假装完成）**：倍速（音频侧要时间拉伸，只做视频侧会破坏音画同步——正是本档反复警告的那条）、内嵌字幕轨（mov_text/ass，本批只吃外挂 SRT/VTT 文本）、全屏、音量条 UI（引擎有 `set_volume`，控件没画）、逐帧步进。
- **验证**：`moon test -p NoahLiu/native-gui/yue/media` **18/18**（15 条平移：音频播放/pump/seek/循环、视频解码/时钟/时长/帧尺寸/无音轨静音推进；新增 3 条：字幕四段（时间戳两种写法、SRT/VTT 通吃、行内标记剥离、命中边界含起止与多条拼接）、帧回灌字节序与短包尾像素、控制条分区）；`moon check yue/media`/`./examples/native-web` `--deny-warn` 零警告；core 70/70、ui 110/110、web 11/11、render 43/43、text 29/29 未掉；全仓红点仍 287 errors / 68 warnings。真窗口回证（`examples/native-web` 的「开一扇播放器窗」= 第三扇窗播 `av_1s.mp4` + 内联 SRT）：`NATIVE-WEB-MEDIA frames=10 pos_ms=1000 playing=0 err=''`（1 秒片解满 10 帧、时钟走到 1000ms、播完自动停、无降级），截图见彩条画面颜色不错位 + 白字「第二条字幕（0.6~1.0 秒）」叠在画面上 + 控制条进度满格与 `0:01 / 0:01`。**待使用者肉眼复验**：有声播放是否真出声（本机有 miniaudio 设备）、拖动进度条的 seek 手感、长片倍速与逐帧（本批未做）。

### MoonBit 原生 GUI 栈 · 窗口级按键兜底通道（`App::add_key_fallthrough`）

- 缺口：宿主的按键只投给**焦点控件及其带 `on_key` 的祖先链**（`App::route` 的 Key 分支），焦点为空时按键直接丢弃。于是「不点一下就不吃键盘」是框架现状，播放器这类「窗口级快捷键」在组件层没有入口。
- 口径：焦点链没消费（或压根没焦点）时，按注册序问兜底处理器，第一个返回 true 的截断。三条边界——① 焦点在输入框里时按键被编辑器消费，通道**不会抢字**，不需要额外判据；② 只在本窗事件循环里生效，与 `sys`/`win` 的**系统级**热键（X11 grab 那条线）不是一回事；③ 通道没有反注册口（本层还没有控件卸载钩子），所以处理器**自己负责活体判断**——用 `Widget::is_painted()` 问「我这棵子树本帧还在被画吗」，不在就返回 false 放行，别让摘掉的组件继续吃键。
- 实现代价：`App` 加一个字段即三处手搓假窗的字面量要跟着补（record 字面量不能省字段），全仓只有 core 的三个 wbtest 与 `App::new` 命中。
- 验证：`moon test ./core` **149/149**，新增 `key_fallthrough_wbtest.mbt` 两条（无焦点吃到键 + 抬起不进通道；焦点链消费不抢 + 多处理器按注册序截断）；`moon check ./core --deny-warn` 零警告。真机（空格/回车是否只被当前那台播放器接走）随控制面一批由用户复验。

### MoonBit 原生 GUI 栈 · 播放器倍速（批 D2b：纯 MoonBit 重采样 + 时钟同轴）

- **零 C 做到的倍速**：音频侧不需要新桩——解码出的 s16 交错 PCM 在推给设备前按 `1/speed` 做线性重采样（`media_resample_s16`，纯 MoonBit），设备仍按原采样率消费，于是样本少一倍、走完就快一倍。代价是**音高随动**（这是"变速"而不是"变速不变调"，后者要相位声码器）。视频侧时钟只改一处：`vp_target_pts(base, elapsed_ms, speed) = base + elapsed × speed`，两边同轴，所以不会出现「画面快、声音慢」——那正是旧链反复警告过的失同步形态。
- **一条被倍速逼出来的既有缺陷**：tick 原先是"每 tick 至少解一帧"（解一帧后才比 `pts >= target`），于是低帧率视频与**任何慢速**都会跑在时钟前面（画面 30 帧/秒地走、时钟按 0.5 倍速走）。修法是把闸门提到解码**之前**：先看已解帧的 pts，已在时钟前面就不再解。这条同时兑现了 tick 注释里早就写着的「低帧率视频画面跨 tick 保持」。
- **换速要把时钟基准重钉一次**：`set_speed` 先读当前位置、再改倍速、然后把 `base_pts/pos_base` 设成这个位置、`wall0/played_base` 设成当下——不重钉的话位置会按新旧倍速差跳一下。音频位置口径跟着变：队列里是重采样后的样本，所以「消费 N 个样本 = 走过 N×speed 个源样本」，`AudioPlayer::current()` 里那一项要乘 speed。
- **无时间戳的流不假装支持**：回退路径（每 tick 一帧、按流帧率步进）没有 pts 可追，倍速只影响时钟不影响画面，这一点写在 `tick` 的注释里而不是藏在代码里。
- **档位取自表而不是就地加减**：`bar_speeds = [1.0, 1.25, 1.5, 2.0, 0.75]`，点击只推进下标（`player_speed_at(i)`，含负数与回绕），所以不存在 `+= 0.25` 累加漂出档位的可能；钳制在引擎侧（`media_clamp_speed`，[0.25,4.0]，NaN 回 1.0 而不是最快/最慢档）。控制条多出第六个分区（`speed`），轨道起点随之从 114px 挪到 154px，音量条让位阈值从 400 抬到 440——**绘制与命中读同一组常量**这条判据在这批第二次发挥作用。
- **观测口而不是猜**：`video` 加 `on_speed(v)`（与既有 `on_tick`/`on_error` 同构），示例把档位写进退出行 `NATIVE-WEB-MEDIA ... speed=1.5x`，回证不必去读引擎内部状态。
- **本批未做（不假装完成）**：内嵌字幕轨（mov_text/ass 要 `ffmpeg-mbt` 先暴露字幕流）、真出声与听感复验（倍速下是否仍同步、音高随动是否可接受）。
- **验证**：`moon test -p NoahLiu/native-gui/yue/media` **22/22**（新增 3 条：倍速档位表含回绕与负下标 + 标签短写法、`media_clamp_speed` 与 `vp_target_pts` 三条算式、`media_resample_s16` 的 2 倍/0.5 倍样本数与插值中点与双声道不串位及三种原样返回情形；另在真机解码那条里加 `get_speed` 钳制回环；控制条分区测试改到六段）；`moon check yue/media`/`./examples/native-web` `--deny-warn` 零警告。真窗口回证（`examples/native-web`「开一扇播放器窗」→ 在控制条倍速区连点两下：1x→1.25x→1.5x）：`NATIVE-WEB-MEDIA frames=10 pos_ms=1000 playing=0 speed=1.5x err=''`——档位由 `on_speed` 观测口报出（不是读引擎内部），1 秒片在 1.5 倍速下仍解满 10 帧并走到 1000ms 后自停、无降级；截图见控制条 `▶ |< >| 1.5x` + 进度满格 + 音量条 + `0:01 / 0:01`。**使用者已真机复验（2026-10-12）**：倍速下音画仍同步、音高随动可接受、音量条拖动确实变响。

### MoonBit 原生 GUI 栈 · 播放器控制面补齐（批 D2a：逐帧步进、音量条、全屏）

- **逐帧步进必须「当场解到落点那一帧」**：`seek` 会把当前帧清成 `None` 等下一 tick，而**暂停时 `tick()` 直接返回**——于是步进后画面停在黑帧，看起来像「按了没反应」。修法是把 tick 里那段「从解码点向前解到目标时刻（上限 8 帧）」抽成 `vp_settle`，步进 = 先暂停 → 按 `1/fps` 挪位置 → `seek` → `settle`。判据全在无头那条里：步进后 `frames_decoded()` 增加、`current()` 前进、`current_frame()` 非空、`is_playing()` 仍为假（步进不许把播放态带起来）。
- **控制条从三段分区变五段**（播放 / 上一帧 / 下一帧 / 进度轨 / 音量 / 时间文字），绘制与命中读**同一组** `BAR_*` 常量——分区写在两处迟早会对不上。另加一条「窄条让位」判据：`w < 400` 时音量条整个不画也不响应（轨道右端改按时间文字算），否则会出现「看得见却点不着」或反过来。轨道两端仍是**钳制**而不是越界（114px 处 =0.0、354px 处 >0.99）。
- **音量与 seek 的防抖方向相反**：seek 抬手才真做（每次真 seek 要回关键帧，代价高），音量**每步都生效**（边拖边听才是预期，且它不触发解码）。音量条画的是 `engine.get_volume()`（引擎里那份钳制值）而不是组件本地副本——本地副本在 set 被钳制时会与显示不一致。为此给 `VideoPlayer` 补了 `get_volume`（`AudioPlayer` 早有，两边口径对齐）。
- **全屏是窗口级动作**：控件层拿不到窗口，所以链路是 `Window::set_fullscreen` → `App::set_fullscreen`，由宿主（示例）挂按钮请求；C 侧只有 `gtk_window_fullscreen`/`unfullscreen` 两行（ABI-only，判据见「C 桩按需且 minimal」那条口径）。切换后尺寸变化照常走 allocate 事件，宿主不需要自己算新矩形。
- **本批未做（不假装完成）**：倍速（音频侧要么时间拉伸、要么走 miniaudio 的 pitch，两者都要改设备线程那条路，另批做并写清音高随动的代价）、内嵌字幕轨（mov_text/ass 要 `ffmpeg-mbt` 先暴露字幕流）、真出声复验。
- **验证**：`moon test -p NoahLiu/native-gui/yue/media` **19/19**（新增 1 条逐帧步进：`n=0` 不动、步进后帧数/位置/有帧/仍暂停四条都成立、两端钳制、`get_volume` 给钳制值；控制条分区测试改到五段 + 窄条让位）；`moon check win`/`core`/`yue/media`/`./examples/native-web` `--deny-warn` 零警告。真窗口回证（`examples/native-web`「开一扇播放器窗」→ 注入 `>| ×2`、`|< ×1`、音量条中段、全屏按钮）：`NATIVE-WEB-MEDIA frames=21 pos_ms=1000 playing=0 err=''`（1 秒片正常播完 10 帧后再被步进解到 21 帧，说明步进真在解码；`err=''` 即无降级），点全屏后 `xdotool getwindowgeometry` 给 `Position: 2560,0 Geometry: 2560x1440`（附窗真的铺满第二块屏），截图见控制条 `▶ |< >|` + 进度轨 + **音量条**（拖到中段后填充可见）+ `0:00 / 0:01`。**待使用者肉眼复验**：逐帧步进的画面跳动观感、音量条拖动手感与是否真变响、全屏下字幕与控件的位置。

### MoonBit 原生 GUI 栈 · 多窗口宿主（`core/host.mbt`：一宿主管 N 窗）

- **形态**：一扇窗 = 一个 `App`（自己的平台窗口 + 控件树 + `FocusStack` + 输入法/悬停/捕获状态），窗与窗只共用两样——`Loop`（进程级唯一时基，`host_loop()` 建一次）与平台泵（`@win.wait`/`wake` 本就进程级）。注册表只管「有哪些窗、当前是哪扇、关一扇退不退」，`App::step` 改成逐窗排空事件 → 逐窗喂输入法 → 脏窗上屏，遍历一律走 `host_windows()` 快照（排空途中关窗会改表）。
- **主窗裁决**：注册表里第一扇是主窗，关掉主窗或关掉最后一扇才整体退出（`host_close_action(primary, remaining)` 是纯函数，无头可测）；关附窗只摘自己。关窗顺序仍是「先停派发、再拆对象」：`running=false` → 摘表 → `window.close()`。`App::shutdown` 则把**所有**还在的窗一起拆（附窗可能开着），句柄已回收成 -1 的窗 `wm_close` 幂等。
- **两条进程级单槽必须升级，否则多窗会画错/查错**：① `invalidate()` 的重绘钩子改成**广播**（所有在窗置脏 + 一次唤醒）——一个 Store 同时影响两扇窗时两边都重画，被多余置脏的那扇只多一帧，不会画错；② 浮层宿主从「一个 `OverlayHost`」改成**取用函数**（`set_overlay_provider(() -> OverlayHost?)`），浮层开在**当前窗**（新窗建好即当前窗，哪扇收到输入就切哪扇，当前窗被关退回最后一扇）。`set_overlay_host(h)` 保留为静态形态，无头测试照旧用。
- **一条设计缺陷是本批被多窗暴露出来的**：浮层句柄原先按宿主各自从 1 数起，两扇窗的「1 号」撞号；改成**进程级递增**（`overlay_cid()`）并新增 `overlay_ids()`/`overlay_top_id()`。判据不是编译错而是**测试崩**：`ui` 里十几处把句柄写死成 `overlay_root_of(1)`，跨测试累积后取到 `None` → `children()[0]` 直接 `Array::at` 越界 SIGABRT。纪律：**句柄是运行期分配的，调用方只能拿返回值或 `top_id()`，不许写字面量**。
- **`raise` 是 MoonBit 关键字**：`pub fn OverlayHost::raise(...)` 不是报「保留字」而是**整条函数头解析失败**，错误连锁成 `The value identifier self is unbound` + `unexpected token if, you may expect pub|fn|...`，看上去像函数体写坏了。方法名撞保留字时改叫 `raise_layer` 之类，判据是错误从函数头那行开始。
- **GTK 桩的窗口槽要能复用**：`wm_window_new` 原先只 `wm_next_id++`，附窗反复开合会把 32 个槽吃光（表现为 `App::open_window` 静默返回 None）。改成扫第一个 `area == NULL` 的槽——建窗时 `area` 必设、`wm_close` 里 `memset` 清零，所以「拆过的」与「没用的」同样可取。
- **跨窗注入的坑：点击会把别的窗抬上来**（XFCE 默认 click-to-raise）。第一轮实测里「关闭这扇窗」的点击没生效、`closes=0`，看着像按钮坏了；实际是先点主窗把主窗抬到关于窗之上，那一击落在了主窗覆盖的区域上。判据：**跨窗注入前必须 `xdotool windowactivate --sync <目标窗>`**，并且用「点完后 `xdotool search --name 关于` 还在不在」这种可观察状态判定，而不是只看计数。
- **示例侧两条口径**：① 每扇关于窗**自持 Store**（两窗共用一个 Store 会让「打字进哪扇」失去意义，退出读数也会互相覆盖）；② 冒烟自杀点从 12 秒放宽到 25 秒——多窗形态要按「开窗 → 在第二窗点与打字 → 关窗 → 再开」多步注入，12 秒走不完一轮。
- **验证**：`moon test -p NoahLiu/native-gui/core` **70/70**（新增 8 条无头注册表回归：`host_loop` 两次取回同一对象（用 `pending()` 计数证同一性，`started()` 证不了）、主窗/附窗与摘表回退、关窗裁决三态、`close_window` 幂等且附窗不停主窗、`invalidate` 广播置脏、浮层落当前窗且两窗各自一套栈与句柄、`mount` 只升本窗图层、`shutdown` 拆所有窗并复位）；`ui` 110/110、`chart` 189/189、`mdview` 26/26、`render` 42/42、`text` 29/29、`input` 10/10、`theme` 8/8、`sys` 163/163、`dbus` 64/64、`yoga-mbt` 96/96 全绿；`moon check ./examples/native-app`/`./examples/native-sys` `--deny-warn` 零警告；全仓红点仍 287 errors / 68 warnings 未增。真窗口回证（`examples/native-app` 顶部「多窗口（批 A）」面板 + 「关于（第二窗）」）：`NATIVE-APP-MW wins=1 opened=1 closes=1 main_clicks=1 sub_clicks=2 sub_entry_bytes=2 sub_focus=101`，几何行 `NATIVE-APP-MW-GEO open=688,262,160x32 sub_btn=16,53,464x32 sub_entry=16,85,280x32 sub_close=16,117,464x32`；注入序列「点开 → 第二窗计数两下 → 第二窗输入框打字并提交 → 主窗对照键 → 第二窗关闭 → 再开一窗」，中途 `xdotool search --name 关于` 从有到无而主窗 id 始终在（**关单窗不影响宿主**），第二窗截图见「本窗点击 2 / 在窗 2」与输入框里的提交文字（**每窗一棵树、焦点栈按窗独立**）。**待使用者肉眼复验**：两窗同时拖动/遮挡时的重绘、关于窗里 preedit 下划线观感。

### MoonBit 原生 GUI 栈 · 系统能力累积验证页（`examples/native-sys`）

- **一页看全部 `sys`**：五个面板（系统与机器 / 桌面与硬件 / 应用与文件类型 / 窗口与剪贴板 / 最近与历史）全是**只读**探测，三个按钮里只有「重新探测」也是只读（注入回证就点它），「打开链接」「打开目录」是设置类、点了才交给系统。退出前打两行：`NATIVE-SYS-GEO probe=… open=… reveal=…`（注入点位）与 `NATIVE-SYS-STAT os=… de=… mon=… wp=… vol=… prof=… mime=… def=… apps=… recent=… hist=… dl=… bm=… ffx=… vsc=… wins=… clip=… probes=… opens=… reveals=… changes=…`（与屏上读数一一对应）。本机一轮：`os=ubuntu de=XFCE mon=9 wp=ok vol=65 mime=text/plain def=sublime_text.desktop apps=179 recent=156 hist=5 dl=5 bm=166 vsc=1 wins=9 probes=3`、退出码 0。
- **`@core.App` 的根容器默认是 Row**：只调 `app.mount([...])` 而不 `app.root.set_column()`，多块面板会横排挤出窗口（本例第一版就是这样，按钮 rect 的 x 到了 1442 而窗宽只有 1200——注入自然全数落空）。`examples/native-app` 一开始就 `root.set_column()`，新页要照做；面板内部要横排则给容器显式 `direction=@yoga.Row`。
- **注入计数会「少点一次」不是丢事件**：「重新探测」一次要把整库重读（Chrome 的 `History` 本机 37 MB），处理期间 UI 线程阻塞，间隔太短的下一击会被拆成「按下在阻塞前、抬起在阻塞后」而不算点击。判据：同一位置连点三下、每下间隔 1.6 s 得 `probes=3`，间隔 1 s 内则只涨 1——**注入脚本要给重活留一拍**。
- **剪贴板监听的接线形状**：`@sys.cbw_start_watch(fn(ms, f) { let _ = app.timer(ms, f) }, cb, interval_ms=1000)`——排期通道由宿主给，`sys` 不认识事件循环（无头测试用假通道逐拍派，见前一条批次记录）。本机未装 xclip，读数如实写 `ClipboardError::Unsupported`，不是页面缺陷。
- **验证**：`moon check ./examples/native-sys --deny-warn` 零警告、`moon build ./examples/native-sys` 通过；`sys` 163/163、`core` 62/62、`ui` 110/110、`chart` 189/189、`mdview` 26/26、`render` 42/42 全绿，全仓红点仍 287 errors / 68 warnings 未增。**待使用者肉眼复验**：点「打开链接」是否拉起默认浏览器、「打开目录」是否在文件管理器里打开 `/tmp`（注入只证明按钮确实把动作交给了系统调用，不证明对端窗口）。

### MoonBit 原生 GUI 栈 · 系统集成历史族（`sys`：浏览器历史/书签/Firefox/VS Code）

- **SQLite 读依赖要在包级声明**：`prowk/moonsqlitefile` 已在 `moon.mod` 的 `import` 里，但 `sys` 用到 `@moonsqlitefile.*` 时报的是 `Package "moonsqlitefile" not found in the loaded packages`——**模块级 import 不代替包级声明**，要在 `sys/moon.pkg` 写 `"prowk/moonsqlitefile" @moonsqlitefile`。旧链 `yue/moon.pkg` 里没有这一行（那批文件本就在全仓红点里），照抄旧链的包配置会踩空。
- **读 SQLite 必须有原始字节入口**：新增 `sys_read_bytes_file`，与 `sys_read_text_file` 共用同一条桩（`yue_sys_read_text_file` 本就把文件整段读成 `Bytes`，区别只在 MoonBit 侧解不解码）。文本版那条不能拿来喂 SQLite：`decode_lossy` 之后再 encode 回去与原文不逐字节相等（非法 UTF-8 序列被替换字符吃掉），SQLite 页头一看就错。
- **时间基准各不相同**：Chrome/Edge/Brave 的 `History` 用 **1601-01-01 UTC 起微秒**（换算常数 `11644473600000`，`<=0` 视为未知给 0，微秒以下截断）；书签的 `date_added` 是同一基准但**以数值字符串**存；VS Code 的 entries 用 Unix 毫秒。混用会得到 1601 年或 5 万年后的时间。
- **profile 探测「存在才收、不读库内容」**：目录枚举只看有没有名为 `History`/`Bookmarks` 的条目，取数路径才把命中的库整读——列 profile 不再为判存在把数十 MB 的库读进来。边界：本层没有 profile 目录的枚举手段，按固定候选名探测（`Default` + `Profile 1..24`），自定义目录名的 profile 收不到。
- **本机端到端已真跑**（新增 `bh_browsers`/`bh_history`/`bh_downloads` 的严格冒烟）：Chrome 的 37MB `History` 真读，两个 profile 命中、返回条目时间落在 2026 量级、排序不变式（时间降序、并列按 url 升序）成立、`downloads` 表可读；VS Code 的 `state.vscdb` + recent 端到端 OK；本机未装 Firefox（无 `~/.mozilla/firefox/*/places.sqlite`）→ 走合法跳过分支。**纪律同上一批**：探测到库却读不出必须 `fail`，`Err(_) => ()` 只允许出现在「本机确实没有这份数据」时。
- **验证**：`moon test -p NoahLiu/native-gui/sys` **127/127**（新增 41：浏览器历史 12、Firefox 10、书签 9、VS Code 10，全部含纯函数断言与本机冒烟）。`sys` `--deny-warn` 零警告、全仓红点仍 287 errors / 68 warnings 未增。

### MoonBit 原生 GUI 栈 · 桌面集成族前半（`sys`：桌面识别 + 应用查找 + 打开外部）

- **平移面与文件对应**：master 的 `yue/system.mbt`（`open_url`/`reveal_in_file_manager`）+ `yue/system/appfind.mbt` + `yue/traybus/detect.mbt`（桌面环境识别）→ 新栈 `sys/launcher.mbt` + `sys/appfind.mbt` + `sys/desktop.mbt`。桌面识别**在 sys 包内自带一份纯函数**而不引 `@traybus`：旧链 traybus 属全仓红点积压，且 sys 反过来要给它用（壁纸/默认应用按 DE 分派），引了就成环。DBus 线接入后复用这份识别结果，不要重抄第二个 `detect_desktop`。
- **分离式启动落到本栈自己的桩**：master 走 shim 的 `g_spawn_async`，而 `sys/sys_stub.c` 只用标准头，所以这里是 `fork → setsid → fork → execvp` + 一根 **CLOEXEC 管道**回传 exec 成败。**不用 [pr_run] 等它**是刻意的：`xdg-open` 交出窗口后往往还驻留，等它等于把调用线程钉住；双 fork 同时保证不留僵尸（中间进程由本函数 `waitpid` 收掉，真孙进程过继给 init）。
- **本批踩到并修掉的真 bug（管道写端关早了）**：中间进程在**派生孙进程之前**就 `close(fds[1])`，孙进程就没带写端的 fd，`execvp` 失败时无处可写 → 中间进程读到 EOF（写端全关）当成成功 → 「命令不存在」被报成 `Ok`。判据就是那条「不存在的命令必须 Err」的断言（第一次跑就红）。正确顺序：中间进程先 `fork` 孙进程（它继承写端），**然后**自己关写端、只留读端等信号；写端标 CLOEXEC，所以孙进程 exec 成功那一刻写端自动关闭、中间进程读到 EOF，exec 失败才走到 `write("E")`。
- **`open_url`/`reveal_in_file_manager` 的 `Ok` 只表示「已交给系统」**，能不能真打开由平台负责；参数不经 shell（argv 直传），所以 URL/路径里的shell 元字符不构成注入面。
- **`reveal` 的「选中」这一半本批是缺口**：master 先问 FileManager1 总线 `ShowItems`，服务不在线才回退打开父目录；新栈暂无总线通道，因此**当前每次都是回退路径**（打开父目录、选中态丢失），随 DBus 线补 `ShowItems`。
- **appfind 清单排序按 master 原形保留 `mut_view().sort_by`**：本工具链里**返回 `-1/0/1` 字面量的比较器是可用的**（前批「`Ordering` 类型不可直接引用」那条只针对显式写 `Ordering::Less` 或标注 `Ordering` 类型的写法，与返回 Int 的比较器无关）。排序口径不变：先比 `name` 的码点字典序、同名再比 `id`；`appfind_str_cmp` 逐码点比而不吃 String 默认的「先比长度」shortlex 序（否则 `"New"` 会排在 `"Beta"` 前）。
- **平台面**：Windows 开始菜单（`.lnk`）与 macOS（`.app`）分支未随本批——`sys_stub.c` 的 Windows 侧仍是占位，`open_url`/`reveal`/`appfind_*` 在非 Linux 一律 `Unsupported`；平台分派批接入时按 master 的纯函数（`appfind_win_*`/`appfind_mac_*`）直接补即可。
- **两条工具链写法（本批实测）**：① `500u64` 这类 Uint64 字面量后缀**解析不过**（`unexpected token id (lowercase start)`），单调钟差值要比大小先 `.to_int()`；② **无载荷的 `pub(all) enum` 同样不自动带 `Eq`**（前批记的是带闭包字段的 `PointerKind`，这条补上「简单枚举也一样」）——`desktop_detect() == before` 编译不过，跨态判定用 `match` 或比 `desktop_name()`。
- **验证**：`moon test -p NoahLiu/native-gui/sys` **59/59**（新增 18 条：桌面识别 3——单值映射/冒号多值取首个可识别/真实环境「存—改—断—复」环；应用查找 10——INI 子集解析、条目过滤与 zh_CN 回退、去重合并排序、目录拼装三态、真实读盘收集与静默跳过、`NoScanDir`、`appfind_installed` 真扫本机、`appfind_executable` 命中 `/usr/bin/sh` 与参数防御；打开外部 5——`parent_dir`/相对路径归一、真实 cwd、分离式启动的成功/失败/不阻塞（`sleep 3` 交出后 <500ms 返回）、两个错误枚举的 Show 与平台门）。`core` 62/62、`ui` 110/110、`render` 42/42、`mdview` 26/26、`theme` 8/8，逐包 `--deny-warn` 全零警告、全仓红点仍 287 errors / 68 warnings 未增。**真机复验项**（`examples/native-sys` 批接入后可观感）：`open_url` 是否真拉起默认浏览器、`reveal_in_file_manager` 是否打开父目录窗口、`appfind_installed` 的本机应用清单条数。

### 文本布局对象 C 侧缓存(Pango / DirectWrite,2026-10-14,实测数据驱动)

- **背景与实测依据**:帧耗时分段账本(`gui/core/prof.mbt`)在 native-app 真机读数 `frames=190 layout=220ms paint=34487ms present=78ms total=34785ms`——**paint 占 99.1%,layout 只占 0.6%**(yoga 内部缓存有效,「每帧全树 relayout」不是瓶颈),瓶颈是每帧全窗重画时屏内每个文本控件都在 C 侧重建布局对象(Pango `PangoLayout` / DirectWrite `IDWriteTextLayout`,itemize+shaping+字体解析全重算)。
- **修法(两分支同构)**:布局对象按键缓存,键 = 路径标记(`"m"` 测量/无盒绘制、`"b"` 盒内绘制)+ 全量文本字节 + 字体四要素(族/号/重/形)+ 宽约束/换行/省略/对齐——同键的布局配置完全一致,复用是只读的。上限 1024(Pango)/1024(DWrite),超限整表清空(与 MoonBit 侧度量缓存同口径)。测量与无盒绘制共用 `"m"` 键(配置路径相同);盒内绘制走 `"b"`(宽约束按 wrapped_axis 归一化,对齐只在有宽约束时参与布局)。
- **复用只读的前提(两平台各自成立)**:Pango 侧颜色在 `cairo_set_source_rgba` 设、几何偏移逐调用现算,都不碰布局;DWrite 侧 `ptw_render` 无区间时不改布局(区间字体/颜色只属于富文本 rt_* 路径,rt_* 仍现搭布局不走缓存),文字色在共享画笔上 `SetColor`。
- **Windows 侧的免费前提**:`img_anim_advance`(WIC)是「一拍一帧」、组件按 `delay_ms` 节奏问一次,布局对象天然按拍复用;画布资源(WIC 位图 + D2D 渲染目标)此前已进程级缓存,本次补的正是 `CreateTextLayout`(含整段 shaping)这块剩余大头。
- **实测(平台更正 2026-10-14)**:`experiment/anim_cost_bench`(30 行「按钮+输入框+文本」典型页,1400×900)全窗重绘 **21ms/帧**、90×32 小脏区一帧 **0.8ms**、relayout 0ms。**这批读数出在本机 Linux/X11(cairo 后端),不是 Windows 纯光栅**——见下面「动画开工判据」一节对同一台机器后端选择的实测判定;`PureBackend(Raster)` 那条路径的每帧代价至今没有真机数(使用者目前全部真机验证都在本机 Ubuntu + X11 做,Windows/mac 侧待有机器时复跑同一探针)。P5 的开工判据按本机读数放行,Windows 侧风险已在此记档。native-app 全页的 after 读数以复跑 `NATIVE-APP-PROF` 为准(账本已落盘 `native-app-prof.txt`)。
- **未做且不假装完成**:富文本 rt_*(AttributedText)仍逐次现搭布局(演示页用量小,收益另估);测量路径在 MoonBit 侧缓存命中时根本不会到 C 侧,这层 C 缓存主要服务绘制路径与 MoonBit 缓存清空后的冷启动。

### 光栅填充快路径:fill_rect 直写 + 圆角矩形解析填充(2026-10-14,探针定位)

- **定位过程**:NATIVE-APP-RENDER 三段统计证明文本只占全窗帧 ~15ms/232ms——真凶在非文本侧。`experiment/paint_probe`(组件级隔离计时)给出分解:60 张 400×120 圆角卡片 **432ms/帧(单张 7.2ms)**、直角 110ms、三张图表 56ms、表格 22ms——**圆角矩形走通用路径扫描(路径化+多边形 AA)是全帧 paint 的最大单项,单张 20ms**。
- **修法(纯光栅后端,render 包)**:①`composite_solid_span`——纯色**不透明**源 + Normal 算子的整段直写(免逐像素取源/预乘/混合函数调用,预乘 BGRA 序不透明源即原色);②`Raster::fill_device_rect` 先试快路径再走通用 cov 合成;③`Raster::fill_round_rect` **解析填充**——不走路径扫描,按行求墨迹:中段整行(快路径),角部条带像素按「像素中心到角圆心的距离」求覆盖(圆外 0/圆边 AA/圆内 256),轴对齐且 x/y 等比(角仍是圆)才适用,斜矩阵/非等比退通用路径(`fill_round_rect` 返回 Bool,Painter 侧退 `trace_round_rect+fill`)。
- **陷阱(实测踩过)**:快路径入口**必须先 `apply_fill()`**——直接调 `raster.fill_round_rect` 绕过了 Painter::fill 的设源步骤,画出来的是上一次的源色(表格色块/浮层面板两条像素断言立刻红,即此因)。
- **实测(paint_probe 同口径复跑)**:单张圆角 20ms→**1ms(20×)**、60 张卡片 432→**23ms(19×)**、直角 60 张 110→**10ms(11×)**、虚拟表格 22→**5ms(4×)**;图表排 56→36ms(矢量路径/stroke 仍是下一大头)。分包 866+ 全绿(仅 virtlist 样式槽 1 条为前端化会话既有红)。
- **追加批·文本帧级批（DWrite 提交合并）**（2026-10-14）：NATIVE-APP-RENDER 显示 d2d 段 132us/段（62 段/帧 8.2ms）——每段一次 BeginDraw→EndDraw 的固定提交开销是大头。`dwrite_text.cpp` 加批队列：连续的 pt_draw/pt_draw_box（同一目标位图）攒批（上限 128），冲刷时一次 BeginDraw → Clear(**并集**) → 逐段 DrawTextLayout → EndDraw → 读回并集一次、逐像素混合一次（批内重叠段由 D2D 按入队序合成）。**z 序三重保障**：①目标/尺寸变化即冲（多窗交替）②render 加进程级「光栅前置闸」——每个写像素操作（fill/stroke/圆角/box_shadow/draw_image/draw_canvas 共 11 个入口）前以当前裁剪矩形调 `pt_flush_if_overlap`，与本批墨迹相交才冲（不相交继续攒批，卡片墙的「填充-文本」交错序列照样攒长批）③core `paint_frame` 帧尾 present 前 `flush_pending`。布局缓存整清可能发生在入队与冲刷之间，入队 AddRef/冲刷后 Release 防悬垂。**开关隔离**：批只在生产路径开（core `text_batch_init` 接线），测试/探针默认走旧路径逐位一致—— suite 零扰动。实测（paint_probe）：200 段/帧逐段提交 **21ms → 攒批一次 2ms（10×）**；即时路径（rt_* 富文本）入口先冲批保序。Pango/mac 分支无批（桩空操作），stub.c 公共尾部用 `#ifndef _WIN32` 防与 dwrite_text.cpp 双定义。
- **后续·攒批的目标缓冲是裸指针，Windows 文本通道因此造堆损坏（2026-10-15 Windows 10.0.19044 本机复现并结案）**：**症状**=showcase / hello-themed 一启动就没了（窗口框与原生菜单先出现、内容区全黑，不到一秒退出），`hello`（只一行裸文字）不复现；Git Bash 只给退出码 139，判据来自 WER（`Get-WinEvent` Application Id=1000/1001）：异常码 **0xc0000374 = STATUS_HEAP_CORRUPTION**、故障模块 ntdll、P4 为 StackHash。**根因**=批队列存的是目标位图像素缓冲的**裸指针**，而 Windows 的文本通道 `draw_box_raster`（`cairo_id()==None` 那条，`draw_at`/`draw_box_at` 的全部调用点都落它）把每段文本画进**函数内新建的离屏 `Bitmap`**，`blit` 完就出作用域释放；帧尾 `flush_pending` 写回时那块缓冲早已还给分配器——往已释放的堆块逐像素写，堆自然坏。**两道保障都拦不住**：①光栅前置闸按「本批墨迹矩形」判交，而批里的矩形是**离屏局部坐标**、闸传进来的是**窗口坐标**，不同源，相交判断纯属碰运气；②`data != g_batch_data` 的「换目标即冲」反而是主引爆点——下一段的新缓冲让上一段**早已死掉的**缓冲当场被冲一遍。**为什么以前看着能用**：同尺寸小块连续 malloc/free 会复用同一地址，于是比对通过、像素落进「当下正占着该地址的别的对象」，表现为不定期崩（与文本段数、分配节拍耦合）而非必崩；本机 7 级组件探针重跑 5 次同一级，139/124/127 交替即此。**修法**=`draw_box_raster` 在 `blit` 之前调 `flush_pending()`（离屏位图还活着时把墨落定），并把契约写进 `enable_batching` 的文档与注释：**攒批的目标缓冲必须活到下一次冲刷，画进临时位图的通道要在释放前自己冲**。**定位手法**（比读代码可靠，记此备后来）：把 `pt_set_batching` 临时改成恒关批重编，7 级探针 x4 全存活、还原即复现——一次 A/B 就锁定归属，无需调试器。**代价（未回避）**：Windows 这条离屏+blit 通道因此吃不到攒批，回到逐段 BeginDraw/EndDraw（即上一条 10× 之前的形态）；要真兑现那 10×，得让文本直接画进窗口画布——把 Painter 的原点与裁剪矩形交给 C 端夹取（`rx*/ry*` 已按缓冲夹，加一道按裁剪夹即可），属独立的性能批，本批只做正确性。Linux/mac 无影响（Pango/mac 桩本就不攒批）。
- **追加批·增量活动边表（AET）**（fill_polys 第二次重写，pixman 同构）：GET（全局边表）按 y_lo 排序一次，扫描线推进时每子采样只做「失活压缩 / 新边激活（指针只前进）/ x 全精度重算 + 近有序插入排序」——不再每子采样全边重扫。**两条实测铁律**：①x 必须与旧跨点公式 `ax + (bx-ax)×t` **逐位一致**（保存原始遍历方向端点 ax/ay/bx2/by2；步进增量的浮点漂移、以及 t 分母误用 bx2 当 by2，都会让边界像素覆盖量化翻转——box_shadow/星形/图标断言实测抓红）；②跨度 <1px 但骑在两个像素上（如 [10.6,11.4)）的短跨段覆盖范围是 `[floor(xa), ceil(xb))` 而非单像素（星形尖端/细环实测抓红）。**对拍方法论**：旧算法从 git 提取改名嵌进临时 wbtest，同形状双渲染逐像素 diff（本轮抓出三角形整块零墨迹=激活指针误用未排序下标）。实测（paint_probe）：折线 80 段 11→**4ms**、圆弧 15→**2ms**、图表排 28→**17ms**；icon 全量扫描崩溃为调试打印 cov 越界（非 AET）。已知渲染变化：自交多边形（五角星）内边界像素的欠覆盖瑕疵（旧实现 239/207/159 的暗缝）修正为满覆盖 255——非零环绕下 wind 1↔2 边界两侧都非零，理应全覆盖。**补记（2026-10-14 晚）**：AET 批带进一个崩溃真凶——y1 夹取误写 `cx1`（裁剪框右界）应为 `cy1`（下界），位图宽>高且几何越出底边时行循环越过位图高、composite_span 越界写（0xc0000409，graph_wbtest 抓住，494fa72→728d0d5 修复）；同批曾误归因前端化会话，git worktree 二分（3be0d9b 189 全绿→e2c7c14 崩）纠正。
- **追加批·扫描线引擎 pixman 化**（fill_polys 重写，2026-10-14）：照搬 pixman/Cairo 扫描线的四个成熟套路——①**满覆盖段直取**：跨点区间内四样本全入的整段像素直接置 256（原实现逐像素逐样本判 `xs∈[xa,xb)`，多边形内部白烧 16 次样本判断）；②**只在跨度两端各至多一个边界像素做采样**（`add_pixel_samples`，封顶 256）；③**只合成有墨区间**（逐行记录 ink_l/ink_r，composite 不再扫全 bbox 宽——宽度里通常九成是空覆盖）；④`composite_span` 加**纯色不透明满覆盖 run 直写**（cov==256 连续段绕过取源/预乘/混合，部分覆盖像素展开同式保证逐位一致）；⑤跨点排序换 `sort_by` 索引排序（原插入排序 O(n²)：160+ 跨点 × 4 子采样 × 每行重排）+ **零分配刮擦数组**（三元组直 push 每跨点装箱一次，实测 5.7 万次分配/帧的 GC 压力，刮擦区+索引排序降为零）。实测（paint_probe）：折线 80 段 18→**11ms**、圆弧 15→**12ms**、图表排 39→**28ms**。剩余结构性大头=增量活动边表（AET：边每行只遍历一次、x 增量步进、免每子采样全边重扫+排序），属更大的重写。
- **追加批·解析描边**:`paint_probe` 补 stroke 基准后定位——60 张 400×120 圆角卡片**描边 49ms/帧**(0.82ms/张,卡片密集页的剩余最大项)。`Raster::stroke_round_rect` 解析描边:环带像素按中心唯一分区(直段按行/列与 `[边-hw,边+hw]` 重叠求覆盖、角部象限逐像素 `|dist-rr|≤hw` SDF、线宽≥2×圆角时内孔自然消失),实测 **49→6ms(8×)**;顺带补 `Painter::stroke_round_rect` 公开 API。折线(80 段 18ms)与圆弧(3 个 14px 环 15ms)仍是通用路径,图表图元解析化列为下一批候选。
- **收官实测(native-app 真机,五批优化全量后)**:`frames=4421 paint=144299ms`——**全帧 paint 232ms→32.6ms(7.1×)**,max_frame 344→188ms;文本占 paint ~28%(d2d 9.3ms/帧),剩余大头为图表矢量路径与 stroke。布局 0.23ms/帧、present 0.5ms/帧均可忽略。
- **未做**:stroke_round_rect/图表矢量路径(stroke_polys)仍是通用路径——图表页与卡片描边是剩余大头;斜矩阵与非等比缩放下的圆角(椭圆角)仍走通用路径;DWrite 逐段 BeginDraw/EndDraw 的按帧合并(文本 9.3ms/帧的下一步)。

### ffmpeg CLI 视频解码路线(帧集整读 + 偏移切片)

- 环境:Ubuntu 24.04,ffmpeg 6.1.1 + ffprobe(apt)。决策:mooncakes 无 ffmpeg 绑定(ABI 面 +100 不收),视频解码走 ffmpeg CLI:`vidf_probe` 用 ffprobe CSV(`-show_entries stream=... -of csv=p=0`),`vidf_extract` 用 `-f rawvideo -pix_fmt rgba` 解码为单个连续帧文件(rawvideo muxer 顺序写帧,无需 image2 序列),`read_binary_file` 整读进内存后按帧号偏移切片——帧数据不落 stdout(pr_run 的 stdout 捕获是文本语义,二进制会坏),直接 ffmpeg 写文件绕开。
- 内存钳制:帧集大小 = 帧数×宽×高×4,默认 fps=8/max_frames=240;480p 12fps 60 秒会到 ~630MB,长视频必须降采样,文档已写明。
- ffprobe CSV 解析坑:r_frame_rate 是分数("30000/1001"),format duration 是纯小数行("2.000000")且无标签前缀——用「video,/audio, 前缀分流 + 其余纯数字行当时长」解析;分隔符逗号,字段无引号(探测输出字段不含逗号,不处理转义)。
- 真机全链路验证:lavfi `testsrc` 生成 2 秒 160x120@5 AVI(容器验证用 AVI 对齐需求方场景)→ probe 宽高帧率对 → 提取 8fps 得 9 帧 → 帧源切片首帧 76800 字节;systemprobe 演示板点「载入演示视频」实渲染 testsrc 彩条画面(xdotool 截图确认),状态栏显示「已载入 160x120 × 16 帧(@8fps,循环播放)」。
- 音画同步:音轨提取 WAV 交 AudioEngine 各自从 0 起播,属近似同步;精确同步需播放时钟对齐,留后续批次。

### 媒体三层拆分(yue 零 ffmpeg / gui-media 可选层 / ffmpeg-mbt FFI)

- 背景:VideoPlayer 曾直接放 yue 且引 ffmpeg FFI——moon 依赖是 **module 级**的,yue 只要 import 了 ffmpeg,所有 GUI 库用户构建都会跑 ffmpeg prebuild(没装 dev 包即失败),不用视频的人被传染依赖。音频曾走 `CorvusCinereus/miniaudio`(MoonBit 依赖),2026-10 用户定案「音频也交给 ffmpeg」后连音频一并统一:yue 核心删 AudioEngine/audio.mbt,音视频都在可选层。
- 三层:①yue 核心(零 ffmpeg 零 miniaudio 依赖,纯 GUI);②modules/ffmpeg-mbt(FFI 绑定,零 yue,moon 名称 `NoahLiu/ffmpeg-mbt`——用户定名,ffmpeg 训练语料污染太重不敢占 ffmpeg 裸名);③modules/gui-media(VideoPlayer/AudioPlayer + 播放器组件,依赖前两者)——要媒体播放的人 import 这层,别 import 这层就零额外依赖。workspace 成员互相引用:被引 module 在主 moon.mod import 列表带版本号,moon 就近解析 workspace 成员(不去 registry);**workspace 内改名**(ffmpeg→ffmpeg-mbt)三处同步:moon.work members、主/依赖方 moon.mod import、prebuild.py 的 link_configs package 字段(写死包名,漏改报 "Link config package name ... does not start with module name")。
- **「视频只有第一帧」根因**:旧版播放时钟只推进位置 Ref,画面容器的 schedule_paint 无人调用——GTK 不重绘,永远停首帧。修复:组件 50ms 时钟里 vp_tick()(FFI 逐帧解码)+ ViewLike::schedule_paint(cv) 成对出现。
- FFI 流式语义:播放时钟按 fps 每 tick 解一帧(decode_rgba 顺序流),seek 为时间戳级(Demuxer::seek → avformat_seek_file + 解码器 flush);容器无时长元数据(lavfi AVI 的 N/A)时 duration 为 0,进度条按 0 处理(帧照常播)。
- 跨包组件基建:yue 的 attach/themed_container/set_panel_bg/theme_border/theme_bg_panel 原为包私有,yue-video 组件层需要,最小 pub 化这 5 个(组件扩展 API)。
- yue 侧接口对齐:VideoPlayer 迁至 yue-video 后 vpc_frame_image(RGBA→PNG→Image)替代 vid_frame_image 直调;音频切段/提取保留 CLI 单命令(audiof_extract_wav/audiof_supported),FFI 音频 PCM 直出留后续。
- 真机验证:X11 合成点击(xdotool mousedown/up)持续被 XFCE click-to-focus 拦截(motion 事件可达、button 不可达),播放中视觉验证留真机;逻辑层 wbtest 全断言(make→play→vp_tick 帧推进→seek 清帧重解→pause/stop→free)。演示板视频页载入即 autoplay。

### 声明式根容器高度塌陷(mount_window 默认 flex)

- 环境:Ubuntu 24.04 + X11 + XFCE,systemprobe 示例。现象:`mount_window([scroll(vbox(...))])` 打开是空白窗口(纯底色,无内容,进程正常)。
- 根因:mount_window 的根容器无任何样式,窗口内容区不弹性分配;Scroll 视口高度来自 flex 分配,无高度约束时塌陷为 0。showcase 未踩坑是因为外层恰好有 `hbox(style=[("flex", 1.0), ("alignItems", "stretch")])` 包裹。
- 修复:mount_window 的根容器默认 `style=[("flex", 1.0)]`(窗口根语义即撑满窗口,默认化安全;`mount()` 面向任意父容器的子树,不默认化以免改坏既有布局);scroll 的文档注释补弹性高度警示;systemprobe 的 scroll 同时显式给 `("flex", 1.0)`(双保险,滚动子节点按需自给 flex 的用法不变)。
- 验证:xdotool + import 截图窗口区域像素方差,修复前纯底色、修复后完整渲染(标题/按钮/雷达图可见);showcase/hello 无回归。

### toolchain 版本升级(弃 fork 路线)

- 环境:本机 toolchain 曾被切到 moonc v0.10.12+1634b282e(core 0.10.12),而 moonsqlitefile 0.7/0.8 全线、moonbitlang/async 均要求 v0.10.14 的 API(`Bytes::exact_view`、`eprintln`);CI 无版本锁定(install.sh 装最新),两端漂移导致本机 clean 后全仓编译失败,而 `_build` 旧缓存掩盖了这一点。
- 决策演变:一度把 moonsqlitefile 0.8.0 vendored 进 `third_party/`(patch exact_view 为字节切片)应急;确认正解是**升级 toolchain 而非 fork 规避**(fork 生态包是长期维护债,只为应急),遂执行官方 install.sh 升级 moon 至 v0.10.14,撤销 third_party fork、恢复 prowk/moonsqlitefile@0.8.0 官方依赖,sysmonitor 的 4 处 String::exact_view 恢复正版写法。
- 结论:版本代差一律升级 toolchain 解决(与 CI 对齐),不 fork 生态包;third_party/ 仅保留确无替代的 vendored。
- 验证:moon clean 后全量重建 check 零警告、moon test 575 全绿、moon build 通过。

### ffmpeg 动态链 FFI(workspace 子模块 modules/ffmpeg-mbt)

- 形态:moon.work workspace 成员 `modules/ffmpeg-mbt`(module `NoahLiu/ffmpeg-mbt`),与主 module 并列(yue 不 import 它,避免给 GUI 库强加系统库依赖;主 module 因 examples 直接用 @ffmbt 而声明,GUI 库用户不传染)。动态链零 vendored:编译期 pkg-config 探测 libav*(含音频的 libswresample),运行期加载系统 .so。
- **链接传播**:库包 moon.pkg 的 link 段不会传播给最终链接——照主仓库架构给子模块挂自己的 `prebuild.py`(moon.mod options --moonbit-unstable-prebuild),输出 `{"link_configs":[{"package":"NoahLiu/ffmpeg/src","link_flags":"-lavformat ..."}]}` 自动传播给依赖方 main 包;link 段从 moon.pkg 移除。测试方式:在 module 目录内 `moon test src`(workspace 根的全量 test 会连带 examples,他人未完成代码会干扰)。
- **FFI 三个坑(真机 gdb 定位)**:① extern 类型声明必须 `#external`(缺它时 GC 把 FFI 返回裸指针当 GC 堆对象,drop 走 mi_free 段错误——崩栈 moonbit_drop_object→mi_free);② C 侧句柄失败不返回 NULL,统一哑句柄+vf_ok 探测(NULL↔Option 转换语义不确定);③ MoonBit 侧中间裸值立即装 struct 字段再传(miniaudio 的持有模式)。FFI 指针参数按新 toolchain 要求逐个 `#borrow` 注解。
- Demuxer 形态(2026-10 音频并入后):open 只开容器探测流(vstream/astream),视频/音频解码器**显式按需打开**(open_video_decoder RGBA/sws、open_audio_decoder s16 交错/swr)——纯音频文件不再因无视频流被拒(旧版 NoVideoStream 直接 Err 的坑)。同一 Demuxer 实例上视频/音频解码器**共享 AVFormatContext 读游标会互吃 packet**,视频带音轨的场景必须双 Demuxer(同文件各 open 一个,VideoPlayer 即此形态)。
- 音频解码坑:①vf_decode_pcm 的 EOF 冲刷——av_read_frame 返回 AVERROR_EOF 后还要 `avcodec_send_packet(NULL)` + 继续 receive_frame 取解码器残留帧(AAC 尾部 ≈1 帧样本),否则尾部丢帧(实测 m4a 45056 帧 vs wav 44100 帧的差即编码器延迟);②seek 后 swr 要重 init 丢弃旧位置重采样缓存,否则残音。
- 测试素材内置:src/testdata/ 进仓(mp3/ogg/m4a/wav 各 1 秒正弦 + testsrc AVI + 带音轨 av_1s.mp4,ffmpeg lavfi 生成,共 <120KB),摆脱「本机 trae 素材路径」依赖,CI 可复现。**moon test 的 cwd 是各 module 目录**(workspace 全量 test 时 ffmpeg-mbt 包里 `src/testdata/...` 过、gui-media 包里同串失败),跨模块引用素材用 `../ffmpeg-mbt/src/testdata/...`。
- 真机验证:四格式音频 PCM 直出(累计帧数 ±10% 断言 + seek 后续解)+视频 RGBA 逐帧/seek,全部内置素材,CI 可跑;错误路径(不存在文件 OpenFailed)与版本探测自包含。
- 运行库版本:Ubuntu 24.04 = libavcodec60(avformat 60.16);CI 与本机一致需 apt 装 dev 包(见 modules/ffmpeg-mbt/README)。

### 音频 ffmpeg 全链路(miniaudio 降级为内嵌设备层)

- 起因:用户真机载 MP3 报 `音频加载失败: Invalid file`(浏览器可播)。独立 C 程序直链同一份 miniaudio 0.11.25 实测:libmp3lame 标准 MP3、系统 MP3 全部解码 OK——miniaudio 上游没有坏,是 `CorvusCinereus/miniaudio` MoonBit 封装的错误语义脏(load_sound 复用 engine->result 传错误码,加载失败后引擎 result 被污染,后续所有 load 永远报 Invalid file)且解码器集合仅 WAV/MP3/FLAC(OGG 需 stb_vorbis、m4a/aac 无内置)。用户定案:音频也交给 ffmpeg(全格式、与视频同栈、音画同源)。
- 架构:**ffmpeg 管解码,miniaudio 只管输出设备**。miniaudio.h(0.11.25 上游单头)vendored 进 `modules/gui-media/src/`,与 audio_stub.c 一起作为 native-stub 编译——miniaudio 从「MoonBit 依赖(mooncakes)」降级为「播放器的内部实现细节」,不再出现在任何 moon.mod import 里,不引入 gui-media 的人零感知。
- 设备层设计(audio_stub.c):ma_device(playback,s16,声道/采样率与 ffmpeg 解码输出一致零重采样)+ 互斥锁保护的 PCM chunk 链表;MoonBit 层 pump(50ms)把 decode_pcm 的字节 push 进队列(高水位 40KB≈0.3s),设备回调线程从队列取数混出、音量在回调内逐样本钳制乘。位置 = 设备累计消费字节(played_bytes)- seek 时记录的基准;自然播完 = demuxer EOF && 队列空。seek = 清队列 + 双 Demuxer 重定位 + 重填。
- **无输出设备降级**:headless/CI 环境 ma_device_init 失败时返回哑设备句柄(has_device=0),push 静默丢弃、状态机照常(pump 按 tick×25ms 近似推进位置)——AudioPlayer 冒烟在无设备环境也能全断言跑通,不为环境写跳过分支。
- AudioPlayer/VideoPlayer 共用这套设备层;组件(audio_player_t/video_player_t)50ms 时钟 pump+refresh,free 后凭 closed 标志停摆。
- 踩坑:① C 侧 data_callback 里消费 chunk 后 queued_bytes 统计口径要统一 recount(半播块/整块消费混写递减会漏);② ma_device_init 是三参 (context,cfg,device),漏 context 编译错;③ MoonBit `guard` 是保留字(循环哨兵变量名撞上,Parse error);④ 自定义 Node 的 mount 闭包返回 View 不是 Node(结尾 `(row.mount)(parent)`);⑤ 换载 free 旧播放器后旧组件 50ms 时钟还在 pump 已释放的 FFI 句柄(悬垂)——free() 置 closed、时钟查 is_closed 返回 false 停摆,同理 VideoPlayer::duration 改用 make 时缓存的字段(free 后旧时钟的 refresh 曾会调 demuxer.duration_s() 解引用已释放的 fmt)。
- 真机验证:AudioPlayer 冒烟 1 秒 MP3 从 play 到自然播完 17 tick(真实设备消费队列,非降级路径)+seek/循环重播/错误路径;VideoPlayer 双路(视频帧+音轨 PCM 队列)与无音轨静音路径;全仓 575 测全绿;systemprobe 冒烟进程存活。

### 播放器组件换载崩溃与 seek 防抖风暴(2026-10 真机)

- 现象(用户真机):视频页「选择本地视频」后崩溃(段错误)、音频页「选择本地音频」后卡死。本机复现(GUI 复现程序模拟用户时序:演示视频播放中换载真实 960x720 大 mp4):稳定段错误,gdb 栈定格 `vf_seek_s → d->fmt->streams[...]` 悬垂。
- 根因(两层叠加):①slider_t 的 on_change 对**程序性 Store.set 同样触发**(订阅无来源区分)——播放中 50ms 时钟每 tick 刷新进度条都排一个 180ms seek 防抖定时器(seek 风暴,每 ~230ms 一次冗余 seek);②换载时 vid_mount_player 先 make 新(含新设备)、free 旧,而旧组件的最后一个防抖定时器仍在飞,180ms 后触发对已 free 的 demuxer 调 vf_seek_s——use-after-free。触发窗口=「最后一次程序刷新排定的定时器恰落在 free 之后」,演示视频播放中换载必然命中。「卡死」是同源另一个面:FileDialog 回调里同步跑 make(大文件双 Demuxer find_stream_info + 设备握手,数秒)冻结 GTK 主循环,观感即死机。
- 修复(三层):①组件 refresh 用 syncing 抑制标志包住 pos_store.set(程序性刷新不再触发 on_change/不再排 seek 定时器);②user_seeking 标志——用户拖动+防抖期间 refresh 跳过进度条(顺带修了拖到一半被弹回播放位置);③防抖闭包与两播放器全部公开 mutating 方法(play/pause/stop/seek/set_volume/set_looping)开头补 closed 守卫(free 后一律 no-op,残留闭包不触碰 FFI);④音频页 FileDialog 选完先 set_text「载入中」+ set_timeout(50) 延后 make(对话框先关、UI 先渲染,同步耗时不再叠加模态循环)。
- 验证:复现程序(修复前 100% 段错误)修复后连跑 3 轮×20 秒全存活;575 测全绿;systemprobe 冒烟存活。真机视觉/交互验证由用户执行。
- GUI 免点击复现方法论(本轮关键手法):xdotool 合成点击被 XFCE click-to-focus 拦截(见前文),「用户点了才崩」类问题用 **set_timeout 编排用户时序**复现——按用户真实操作序列排定时器(0.3s autostart 演示视频 → 4s 播放中换载本地大文件 → 12s 二次换载),零交互稳定命中崩溃窗口;配合 `import -window root` 差分截图确认画面在更新。gdb 抓栈用 `gdb -batch -ex "set environment DISPLAY :0.0" -ex "handle SIGSEGV stop nopass" -ex run -ex bt` 直跑 `_build/.../xxx.exe`(gdb 环境可能丢 DISPLAY,gdb 内显式 set;moon run 是包装进程,gdb 要直指 exe)。
- 排查弯路两则:①yue 应用必须先 `@yue.initialize()` 再创建任何控件/窗口(mount_window 内的 Window::make 也依赖它),复现程序漏掉会在 `nu::View::View()` 段错误或 `Gtk-ERROR: Can't create a GtkStyleContext without a display connection`——极易误判为音视频问题;②`pgrep -f` 匹配 `moon run` 会命中 moon 父进程造成「进程存活」假象,验证存活要核对真实 exe 进程名或退出码语义;gdb 调试前 `touch` 源文件强制重编,防旧产物误导。

### 视频播放时钟与时长不同轴(帧计数 / 硬编码 fps,2026-10 真机)

- 现象(用户真机):「视频的时长对不上」——时间文本与进度条和真实视频时长脱节:帧率高于 12 的视频进度早早爆表(30fps 视频播完位置=2.5×时长)、低于 12 的走不满格;且画面播放速率随真实帧率漂移(解码固定 20fps,30fps 视频画面 0.67 倍速拖慢),音轨设备实时直出,音画偏差随播放发散。
- 根因:`vp_tick` 的播放时钟 = `frame_no / fps`,fps 是 make 参数(演示视频传 8、本地文件传 12,全是调用方硬编码),而 duration 是容器头真实秒数——**两条时间轴不同尺度**,pos 与 duration 相除无意义。演示视频自己都是歪的:生成 `rate=5` 却传 `fps=8`,2 秒视频播完 pos 停在 1.25s(进度只到 62%)。内置测试素材恰好 12fps、测试恰好传 12,单测全绿完全掩盖问题——**时钟类回归必须故意传错 fps 参数断言时间轴不受影响**。
- 修复(墙钟 + 帧时间戳,与 duration 同轴):ffmpeg-mbt 透出帧级信息——`vf_decode_next` 成功时记录帧 pts(`best_effort_timestamp` 优先,流时间基换算成秒,`vf_frame_pts_s` 读出;seek 后重置 -1)与流真实帧率 `vf_stream_fps`(avg_frame_rate 优先 r_frame_rate 回退);gui-media 增单调墙钟 `mbt_now_ms`(audio_stub.c,CLOCK_MONOTONIC)。VideoPlayer 时钟重写:play/seek 记基准(位置 + 墙钟),每 tick `target = 基准 + 真实流逝`,解帧推进到 target 时刻的帧(高帧率视频跳帧追时钟、低帧率画面跨 tick 保持,追帧上限 8 帧/tick——seek 落点离关键帧远也不卡 UI 一整拍),`pos = clamp(target, duration)`——恒 1 倍速,EOF 位置钉在时长(进度满格)。fps 参数降级为**无 pts 流的回退帧率**(优先用流真实帧率)。附带收益:音频设备按采样率实时消费、视频按墙钟推进,两条速率天然同尺度,音画偏差从「随帧率倍率发散」降为常数级。
- 验证:回归测试故意传错 fps=5(素材实为 12fps)断言位置仍按时间戳走(墙钟回拨 500ms → pos=0.5;回拨超时长 → EOF 钉 duration=1.0 转停);ffmpeg 侧 pts 非负单调、末帧贴近容器时长、seek 重置 -1。576 测全绿;systemprobe 冒烟存活。真机交互(进度/时间显示)由用户复验。

### 音频进度条「拖不动」(seek 后 current 从零重涨,2026-10 真机)

- 现象(用户真机):音频页进度条拖到一半松手,进度条立即被拉回开头——观感即「拖不动」。视频页进度条正常(两侧组件层 syncing/user_seeking 同构,差异在播放器层)。
- 根因:AudioPlayer 的 `current()` = 自 played_base 以来设备已消费秒数,**语义是"消费量"而非"媒体时间轴位置"**。seek 只重置了 played_base(消费基准),pos 语义仍从 0 重新累计——seek(0.3) 后 current 从 ~0 开始涨,组件 refresh 每 50ms 把进度条 set 回 vp_pct(current≈0)=开头。VideoPlayer 的 seek 直接 pos=target,所以视频侧无此问题。组件层的 user_seeking 拖动锁只保护「拖动+180ms 防抖期间」,防抖定时器触发 seek 后锁即释放,下一拍 refresh 就把条弹回。
- 修复:AudioPlayer 加位置基准 `pos_base`(seek 时=target,stop/循环重启归零),`current() = pos_base + 自基准以来消费秒数`(哑设备分支同样加 pos_base,pump 哑设备 EOF 判断改用 current())——回到媒体时间轴语义,与 duration/进度条同轴。
- 验证:回归断言 seek(0.3) 后 current ≥0.29、pump 一拍不回落(真设备=0.3+消费、哑设备=0.3+0.025 两分支覆盖);576 测全绿;systemprobe 冒烟存活。真机拖动手感由用户复验。
- 教训:**「位置」字段的语义必须在 seek/play/pause 全生命周期自洽**——消费计数型时钟(设备字节/帧计数)换算位置时,seek 必须携带位置基准,否则进度 UI 会被拉回。与上一条视频时钟 bug 同族:都是播放时钟与媒体时间轴脱节,一个差在速率,一个差在原点。

### 视频比例畸变与透明色失效(HEX 字节序 + 解码器单边尺寸,2026-10 真机+探针实证)

- 现象(用户真机):控制条「背景色还是没有,是不是不支持透明?」;「比例还是不对」。全屏/页面 letterbox 数学此前已修,用户复测仍不对。
- 根因一(**透明**):nu::Color 的 8 位 HEX 是 **AARRGGBB 序(alpha 在前)**——库自家 `argb_hex()` 即产出 `#ffd46a6a` 形态。组件里全部按 RRGGBBAA 语义写(`#00000080` 意图 50% 黑),实际 AA=00 全透明,控制条半透明黑底、滑杆半透轨道、按钮 hover 蒙层全部不可见;`#ffffffe6` 之类前三位白被当 AA=ff 才侥幸可见。**dialog_t 遮罩 `#00000059` 同款错序(AA=00),对话框淡黑遮罩一直是透明的**(存量 bug 一并修)。探针实证:`#80000000` 50% 黑、`#ff000000` 不透明黑、`#000000ff` 全隐形(前导 00=全透明)。
- 根因二(**比例**):页面调用 `VideoPlayer::make(width=480, height=0)`,C 层 `vf_open_video_decoder` 对 0 尺寸直接用源值→16:9 视频被 sws 解码成 480×1080(横向压扁的竖长帧),后续 letterbox 数学再对也无救。修复:单边指定时另一边按源宽高比补齐(ffmpeg `-1` 语义,双向支持,最小 1)。探针实证:320x180 视频传 width=480 解码帧变 `480x270`(修复前 480x180)。
- 定位手法:GUI 探针 × 截图像素采样(`import -window` + ImageMagick `pixel:p{x,y}`)+ 组件内临时 DBG 打印帧尺寸;2×2/组合矩阵探针逐因素隔离(absolute 定位/画法/高度来源均排除,最终靠「不透明黑也不显示」锁定色值解析)。注意探针窗口截图坐标含标题栏偏移,肉眼比对裁剪图比逐点采样更快。
- 排查弯路:曾误判「absolute 定位子容器不渲染」——实为采样坐标落窗外;曾怀疑「宿主 on_draw 吞子绘制」——矩阵证明 absolute+on_draw 照常渲染,一切归因到色值字节序。
- 验证:576 测全绿;探针数值证明(帧 480x270 + 条背景 50% 黑实证);systemprobe 冒烟存活。真机最终观感由用户复验。
- 教训:**库约定色值序是 ARGB(AARRGGBB),写 8 位 HEX 时 alpha 在前**;半透明色务必上真机/探针采样验证——全透明与半透明在深色底上肉眼难分。解码器输出尺寸改写(缩放)必须保持宽高比,单边指定即隐含「按比例补齐」预期。

### 音频播放无声、仅拖动进度时响一下(has_device 状态判定写反,2026-10 真机)

- 现象(用户真机):音频播放全程无声,只有拖动进度条的瞬间响一下(约 0.4 秒)又静默。视频页音轨正常。
- 根因:C 层 `mbt_adev_has_device` 写成 `started == 0 ? 1 : 0`——`started` 是三值状态(-1=init 失败哑设备 / 0=已初始化停止 / 1=播放中),**`play()` 一把设备 start(started=1),"有设备"判定立刻翻成 0**,pump 误走哑设备降级分支:解码丢弃、永不推队列、设备零消费(无声但状态机照常)。拖动时的声音来自 `seek()` 里的 `ap_fill`——它不查 has_device,直接 push 到真实设备(设备 start 后回调线程活着),队列 ≈0.43s 播完后无人再补,正是「一下子的声音」。视频侧不受影响:VideoPlayer 的 `vp_fill_audio` 从不查 has_device,一直直推。
- 定位手法:**真实节奏探针**——wbtest 里 busy 等待 `mbt_now_ms` 逐 50ms 拍打点 `started/has_device/queued/consumed/current`:`play 后 started=1 has_device=0` 一行铁证;修复后同探针 t0 起 queued≈高水位、consumed 按拍上涨(44100Hz 精确 0.05s/拍)。
- 修复:`has_device` 改 `started >= 0`(停止/播放中都算真设备,只有 init 失败才是哑);wbtest 冒烟改真实节奏(25ms/拍 busy 等待)并新增「真设备播放中队列应有 PCM 在途」回归断言(哑环境自动跳过)。
- 深层教训两条:①**三值状态标志的判定必须写全区间**(`==0` 与 `>=0` 一字之差,把"播放中"判成"无设备");②**降级分支的「能跑通」会掩盖上游判定 bug**——哑设备降级设计让误判表现为无声而不报错,且旧 wbtest 连打 pump 正好借误判的哑分支 0.025/tick 快进"播完"(17 tick 播完 1 秒的假象),测试反而依赖了这个 bug;设备消费类时序必须用真实节奏(按拍等待)测,不能连打。
- 验证:探针修复前后对比复现;576 测全绿(3 存量环境失败);systemprobe 冒烟存活。真机听感由用户复验。

### 视频播放器(FFI 双 Demuxer:视频帧 + 音轨 PCM 直出)

- 组件:VideoPlayer + video_player_t(播放/暂停/进度拖拽/音量/循环/时间文本)。2026-10 音频并入后:音轨是同文件的第二个独立 Demuxer(读游标与视频互不干扰),vp_tick 按墙钟目标解帧 + 补音频队列到高水位(时钟语义见「视频播放时钟与时长不同轴」节);音画从 play/seek 点各自起播,误差数十毫秒级(精确同步需音频光标回读,留后续)。
- 悬浮控制条 + 全屏(2026-10,纯组件层零平台代码):控制条 `position:absolute` 钉画面底部(bottom/left/right 0,半透明黑 on_draw),与 dialog_t/toast_layer 同一 absolute 先例;控件白色系(label_t/checkbox_t/slider_t 各加可选 color/bar_color/track_color 参数,空=主题色——深色遮盖层上的白字白条是通用需求,提为组件库能力)。显隐为**移动唤醒状态机**——enter/mouse_move 即显示并排静止计时,静止 1s 或移出(250ms 短延时,防指针滑经控制条时画面 leave 先到而闪烁)后隐藏,**与播放状态无关**(初版"暂停/未播常显"被用户实测否决:演示视频播完停在停止态,控制条永不隐藏,观感即"移入移出没有用");拖动进度(user_seeking)顺延;指针移到控制条时 GTK 先给画面发 leave,控制条自身 enter/move 兜底。画面绘制黑底 + 显示模式两态(**等比 letterbox / 原始 1:1 居中超出裁剪**,控制条"等比/原始"文字按钮循环切换)。全屏为**独立全屏窗口自绘画面**:全屏根容器(flex:1,几何来自窗口布局)挂同一份画面绘制函数与事件(enter/move/leave/双击/Esc),控制条 re-parent 过去(absolute 随全屏宽);**不做画面容器 re-parent + set_view_bounds 直写**——直写几何会被后续任意布局事件(控制条显隐触发的重排等)冲回旧尺寸,用户实测"全屏后视频没有放大且比例变了"的根因;几何交给窗口布局才是稳的。退出四路:控制条按钮/Esc(根容器 set_focusable+focus+on_key_down VKEY_ESCAPE)/双击画面(ClickTracker 连击计数,libyue MouseEvent 无 click_count)/WM 关闭(on_close 兜底归还控制条);换载 free 时 tick 的 is_closed 分支顺带收全屏窗口。事件装配先于全屏函数定义的相互递归用 `Ref[() -> Unit]` 间接绑定(MoonBit 局部函数无前向引用,Ref 字段调用要写 `(x.val)()`)。真机显隐/全屏/两模式由用户复验。
- seek 实现:avformat_seek_file 时间戳级(视频/音频 Demuxer 各自 seek + 解码器 flush + swr 重 init),拖拽防抖 180ms;不再走 ffmpeg CLI 切段(音轨 CLI 提取/切段残留 audio_extract.mbt 已删,媒体链路零 CLI)。
- 音轨失败(无音轨/解码器不可用/无设备)时自动静音播放,不阻断视频路径。
- 换源顺序必须是「旧播放器 stop → free(closed 置位,旧刷新定时器停摆)→ 旧根视图 `remove_child_view` → 挂新节点」,乱序会留残音/残定时器;但顺序正确也不够——free 旧后其组件的在飞定时器(seek 防抖等)仍会触发,组件侧必须自防御(closed 守卫),详见「播放器组件换载崩溃与 seek 防抖风暴」节。systemprobe 视频页首次挂载 set_timeout 300ms 自动载入(make 同步耗时);音频页换 AudioPlayer 后:载入即播放、控制条 audio_player_t 挂 holder、200ms 轮询 is_playing 状态标签、演示素材改 MP3(lavfi + libmp3lame)。

### VideoPlayer 重播状态机:播完再 play 不走 / stop 后重播无声(2026-10 白盒回归)

- 现象:视频播完(EOF 非循环)后再点「播放」毫无变化——位置钉在时长、画面钉末帧、音频队列已空;stop 后再 play,画面倒是从头了,但全程无声。
- 根因一(**播完再 play 不走**):`vp_tick` 的 EOF 非循环分支把 state 置回 `VpIdle`,与初始 idle 无法区分——`play()` 对 VpIdle 一律「从当前位置续播」,而播完态 pos=duration,续播目标时刻恒超时长、demuxer 又已在 EOF,首 tick 立刻再次 EOF 转停,点了等于没点。
- 根因二(**stop 后重播无声**):`stop()` 只 seek 了视频 demuxer;**音频 demuxer 是同文件另开的独立容器实例**(读游标与视频互不干扰,见上节),停在 EOF——重播时 `vp_fill_audio` 的 `decode_pcm` 直接 None,队列全空、全程静音。凡「回起点」类操作必须双 demuxer 都 seek,漏一个就是有声画面配静音。
- 修复:① 显式增加 `VpEnded` 态(对标 AudioPlayer 的 `ApEnded`),EOF 非循环转 VpEnded;`play()` 对 VpEnded 先走 `vp_restart`(双 demuxer seek(0) + pos/base_pts/frame_no 归零 + 音频队列重填)再起播;② `stop()` 补音频 demuxer seek(0);③ `seek()` 把 VpEnded 迁移到 VpPaused——播完态拖进度后再 play 从落点续播,不被误判成重播(重播语义只属于「停在末尾直接再 play」)。
- 设计取舍:**用显式态而非 `pos>=duration` 启发式**——播放中 target 超时长但尚未 EOF 时 pos 会被 clamp 到 duration(启发式假阳性,「暂停在末尾再播放」会被误判成重播回 0);且容器无时长头(duration=0)时启发式完全失效,显式态两种场景都对。
- 验证:白盒对照——把 video_player.mbt 暂存回修复前跑 `moon test -p gui-media`,新增两条用例精确失败(播完→play 的 is_playing 断言、stop→play 的音轨 decode_pcm 断言),恢复修复后 11/11 通过;全仓 `moon check --deny-warn` 零警告 + `moon test` 641 全绿(较此前 636 新增 5 条:循环 EOF→vp_restart、播完→play、播完态 seek→play、stop→play、音量钳制)。真机交互(播完再点播放、stop 后重播的观感)由用户复验。

### 纯音频在组件层被拒（播放器只挂视频引擎）与组件名去 `_t` 尾巴（2026-10-16 用户真机反馈）

- 环境：Ubuntu 24.04 + X11 + XFCE，`examples/audio` 载入 `assets/1.mp3`。
- 现象：右侧红字「打不开媒体：视频解码器打开失败：解码失败：无视频流」，音频示例一首都放不出来。
- 根因（两层，此前只修过下层）：Demuxer 层 2026-10 已改成「open 只探测流、解码器按需开」，纯音频不再在 `Demuxer::open` 被拒（`ffmpeg_wbtest.mbt` 有断言）；但**组件层**的播放器组件无条件走 `VideoPlayer::make`，而该引擎的时钟是墙钟 + 帧时间戳，`open_video_decoder` 在无视频流时直接 `Err(DecodeFailed("无视频流"))`。`AudioPlayer`（设备已消费字节时钟）作为引擎一直存在且功能完整，**全仓没有任何 UI 用它**——示例头注释「纯音频文件同样走它，引擎自动识别无视频轨」是一句没实现的话。
- 为什么不把纯音频塞进 `VideoPlayer`：`vp_tick` 在无视频流时首拍 `decode_rgba()→None` 就判 EOF 转 `VpEnded`，要让它有声等于在视频引擎里重做一套设备时钟——就是抄一遍 `AudioPlayer`。两条时钟不同轴，分开是对的。
- 修复：① 新增音频组件 `media/audio_player.mbt`，控制条与视频组件共用同一套分区常量与命中判据（`BAR_*` / `bar_hit` / `bar_speed_at`），逐帧键在音频侧换成 ±5 秒跳转（`ap_skip`：时长未知时只钳下界，否则 `vp_clamp_t` 会把任何落点打回 0）；组件被外层撑高时多出的高度归舞台区，无输出设备的降级说明写在那块，频谱动画也落这块。② `VideoPlayer::make` 探测到无视频流时给可行动文案（「纯音频文件请用 audio」），不再让解码器报「无视频流」。③ tick 周期归一为 `ap_tick_ms`：原先组件注释写 50ms、静音降级的位置近似按 25ms 算，两处不是一个数，无设备环境进度会漂。
- 命名口径：按 `experience/design.md` §2 改名批的既定方向去掉 `_t`（历史 themed 变体尾巴）并对齐 Web 元素——播放器组件 `player_t` → `video`，新组件叫 `audio`（gui-media 0.1.0 未发布过，改名零破坏）；共用件 `player_bar_hit`/`player_speed_at` 随之叫 `bar_hit`/`bar_speed_at`。**注意 `audio_player_t`/`video_player_t` 是已删旧链（`modules/gui-media/src`）的组件名**、签名收引擎实例，与本轮无关，本文与 `system-capabilities.md` 里那些历史条目保持原样不改名。
- 验证：`moon test ./media` **25/25**（新增 `ap_skip` 用例）；`modules/gui-media` 与 `examples` 的 `moon check --deny-warn` 零警告、两示例 native 构建通过；全仓 `moon test` **1179/1179**。真机观感（是否出声、-5s/+5s 落点、倍速听感、换曲）由用户复验。

### 音频频谱动画（纯 MoonBit FFT，零 C / 零 libavfilter，2026-10-16）

- 形态：取样点在 `ap_fill` 的**重采样之后、入队之前**（引擎开一个 `pcm_tap` 回调，跑在主线程的 MoonBit 侧，不碰设备回调线程——「不做 C→MoonBit 回调」在组件内部同样成立）。样本环是 1024 点窗口 + 16384 帧回看深度，绘制时按 `queued_frames` 往回看同样多的帧再算，把「取样比耳朵快约 0.23 秒（高水位 40000 字节 ÷ 44.1kHz 立体声 s16 的 176400 B/s）」这条补回来；倍速下喂的是重采样后的流，与耳朵听到的同源。
- 为什么不走 ffmpeg：`showspectrum`/`ebur128` 要先给绑定层搭一套 filter graph，新增的 C 面远大于收益；1024 点 radix-2 在 MoonBit 里百来行、30fps 下算力可忽略，符合「能用 MoonBit 解决的不进 C」。
- 判据（全在无头层钉死）：FFT 本体用**直流输入**钉（只有 bin 0 有值、其余 bins < 1e-6）；分带用 440 Hz / 1000 Hz 正弦钉落点（24 段对数分带 40 Hz..16 kHz，440 Hz 在第 9 段附近）；立体声下混与单声道同形；喂两窗后回看一窗仍点亮同段。
- 工具链坑：① **记录字段存闭包必须写成 `(self.tap)(...)`**，`self.tap(...)` 会被当方法解析、报 `Type AudioPlayer has no method tap`；② `String.trim()` 给的是 `StringView`，喂要 `String` 的函数得 `.to_owned()`（`s[0:n]` 同理）；③ 只改数组内容不整体重赋值时字段别标 `mut`，否则吃 `unused_mut` 警告（`--deny-warn` 下就是错误）。
- 验证：`moon test ./media` **33/33**（新增 4 条频谱用例）、全仓 `moon test` **1187/1187**、`gui-media` 与 `gui-examples` `--deny-warn` 零警告、audio 示例 native 构建通过。真机观感（条子跟不跟得上节奏、seek 后闪不闪、静音降级环境下的空态）由用户复验。

### 播放器控制面：图标按钮行、缩放三档、全屏与窗口级快捷键（2026-10-16 用户真机反馈）

- 现象（用户报）：控制条是**画出来的文字字形**（`▶ ❚❚ |< >|`），没有悬停、没有焦点环、进不了 Tab 链；视频组件**没有缩放也没有全屏**（全屏能力在 `App::set_fullscreen`，但控件层拿不到窗口，一直没人接）；两个播放器**都不吃键盘**。
- 图标库够用：`gui/icons` 的 `IconKind` 里 `video-play`/`video-pause`/`pause`、`d-arrow-left/right`、`full-screen`/`fullscreen-exit`、`zoom-in/zoom-out`、`sound`/`sound-fill`、`folder-open`/`file` 都在，自绘侧走 `draw_icon(painter, kind, cx, cy, size, color)`。
- 形态：控制条拆成**左边真按钮 + 右边自绘显示区**（`media/control_bar.mbt`，两个组件共用一份）。播放/暂停与全屏用 `ui.icon_button`（悬停浅底、按下更深、焦点环、Tab 可达都由 ui 给）；倍速与缩放用 `ui.button(variant=Text)` 显示当前档——图标说不清「1.25x」和「铺满」。档位读数走 `Store` + `bind_node` 重挂（`Store::set` 等值不重发，每 tick 刷一次不产生重建）。
- 旧判据作废重写：`bar_hit` 原来在一条自绘区里分「播放/逐帧/倍速/轨道/音量/时间」六区，现在只剩显示区三区（seek/volume/时间文字），坐标从「整条控件」改成「显示区本地横坐标」；分区常量仍只有一份，绘制与命中同读。
- 缩放三档：`vp_fit_rect(vw, vh, rw, rh, mode)` 纯函数——适配取小边、铺满取大边（超出由控件矩形裁掉）、1:1 原始像素，都居中；无头断言钉三档落位与非法尺寸给零矩形。
- 全屏：组件经 `@core.host_active()` 拿当前窗再 `App::set_fullscreen`（这条是 `core/app.mbt` 门面注释里「控件层拿不到窗口」的既有出口，不是新开后门）；没有宿主（无头）返回 false，本地档位状态不动。
- 快捷键：走上一节的**窗口级兜底通道**，空格播放/暂停、回车全屏、`←/→`（音频 ±5 秒、视频逐帧）、`↑/↓` 音量、`Esc` 退全屏（只在全屏态接管）。活体判据是 `watch.is_painted()`——通道没有反注册口，摘掉的播放器下一帧起不再被画，也就不再吃键。
- 依赖口径：`gui-media/media` 因此新依赖 `NoahLiu/native-gui/ui`（图标按钮要真控件，自己重画一套按钮等于把 ui 抄进媒体层）。方向仍是 media → ui，`ui` 不认媒体，无环。
- 验证：`moon test ./media` **35/35**（新增 `control_bar_wbtest.mbt` 三条：显示区分区、缩放三档落位、档位标签；旧六区判据随形态作废）、`moon check --deny-warn` 零警告、两示例 native 构建通过。真机复验清单：图标按钮悬停/焦点环出不出、Tab 能不能走到播放键、空格不点窗口能否暂停、回车/Esc 全屏进出、铺满档左右溢出是否被裁、1:1 是否居中。

### Store 内建去重与 `T : Eq` 限定实现（2026-10-13，前端化 P3 第 0 步）

- 口径：`Store::set` / `Store::update` 给 `pub fn[T : Eq]` 限定实现（相同值只存不发，走 `Signal::set_eq`）；`Signal::set` 本体与通知发射不动，`Store::signal()` 仍可直连 `Signal::set` 强发。需要无条件重发用 `set_always` / `update_always`。
- 坑①：**同名限定实现会盖过通用实现**——无约束的 `Store::update` 体内调 `self.set(...)` 会撞 `Type T does not implement Eq`，因为名字只绑到限定那条；跨约束复用逻辑要直调底层（`sig.set_eq` / `sig.update`），不能经公共名。
- 坑②：去重要求**元素类型有 Eq**：`Array[T]` 的 Eq 由 `T : Eq` 派生。复合值类型补 `pub impl Eq for X with fn equal` + `pub extend X with Eq::{not_equal, equal}`（不带 extend 会吃 `implicit_impl_as_method` 废弃警告，同 W21c 先例）；`impl Eq for (T,T)` 二元组 core 已有，重复定义报「already defined」。
- 坑③：图表数据窗口（`Array[LineSeries]`、`TreeItem`、`GeoRect` 等）元素无 Eq 且整窗比较代价高于收益——chart 与示例一律 `set_always`，共 33 处调用点由编译器逐点钉出。
- 验证：core 121/121（新增去重回归 1 条：同值不发/异值发一次/`set_always` 强发/`update` 走同口径）；全仓 `moon check --deny-warn` 零错零警；库测试 861 条 859 过（2 条红为 W9/排序既有基线）。

### 动画开工判据:纯软件光栅下 transition = 每帧全窗重绘(2026-10-14,决定 P5 排期)

- 问题:P4 之后要不要马上做 P5(`transition` 状态桶属性插值 + 帧驱动)。判据不能靠感觉,量了一版:`experiment/anim_cost_bench`(30 行「按钮+输入框+文本」的典型页,1400×900,`page.paint` 20 帧)本机读数 `full=16ms/20帧`、`relayout=0ms/20帧`、局部 90×32 圆角填充 `<1ms/帧`。
- **但这台是 Linux,`Painter::new` 探针选中的是 cairo 后端**(见 `render/painter.mbt` 后端选择与 `Cairo::over` 优先),这 0.8ms/帧是**交给系统 cairo/X 的宿主侧提交成本**,不代表 CPU 光栅的每帧代价;真正的纯光栅代价在 Windows/mac 那条 `PureBackend(Raster)` 路径上(§6.6 性能批的真机读数:全窗一帧 300–500ms,修复后仍待分档计时;`text_bench` 在 Win 上单次盒内绘制约 0.35ms,而一次全窗重绘要为**屏内每个文本节点**各付一次布局+落墨)。
- 结论与口径:**动画的本质是连续置脏重绘**,在没有脏矩形之前,Windows 上「一个 150ms 的 hover 过渡」= 约 9 次全窗重绘,反馈会明显掉帧,还会把「输入只重绘那一格」的粒度承诺反噬掉。故 **P5 改排到 §6.6「脏矩形重绘 + 文本布局缓存」之后**,开工判据:局部变化(悬停一颗按钮)一帧 < 16ms。P4 的 `opacity`/`box_shadow` 是**静态属性**(画一帧就够),不受该闸门影响,已先行落地。
- 顺手一条工具链坑:`local` 是**保留字**(实测 `[0035] The word 'local' is reserved`),`let local = ...` 直接撞;探针变量改名 `part`。写新代码遇到 `alias`/`abbrev`/`local` 一类词先当保留字看待(与 §1.6 表同源)。
- 下一步要的真机数(用户执行,一条命令):本机 `moon run examples/native-app` 跑起来后退出,读 `NATIVE-APP-PROF` 行(布局/绘制/上屏三段累加 + 最长帧,由 `core/prof.mbt` 常开统计)——用它定「脏矩形收益有多大」并作为 P5 的开工判据。

### 前端化 P4:Painter 全局 alpha 与硬阴影(2026-10-13)

- 全局 alpha 收在**门面状态机**(`PainterState.global_alpha`,save/restore 随栈):填充/描边(含渐变 stop)在 `apply_fill/apply_stroke` 折算色 alpha;文本经 `Painter::paint_color`(画期把串解析→乘系数→回写 hex);图片/画布在 `global_alpha < 1` 时走 `dim_bitmap` 逐像素降 alpha 再 blit。两后端(cairo/纯光栅)零改动即全路径生效——门面是唯一入口。
- 坑①:**叠加断言量错通道**——不透明目标上再叠 50% 红,像素 alpha 仍是 255(alpha 合成只改颜色不改覆盖度),`alpha==0` 这类判据必须落在**透明目标**上;渐变同理,要在空白位图上比 `full.a` vs `0.25.a`。
- 坑②:`round_rect_path` 自带 `begin_path` 时,阴影「外环+内环」两子路径会被第二个调用清掉——tracer 拆成 `trace_round_rect`/`round_rect_path_ccw`(不开新路径),环=一外一圈+一内逆时针圈,非零环绕只描环不叠色。
- `Style.opacity` 通道:`apply` 落 `Widget.alpha_paint`,绘制遍历进控件时 `p.set_global_alpha(继承 × 自身)`、子树画完还原(CSS 式盒树累乘);`box_shadow` 现给**硬阴影**档(偏移多层圆角矩形、`layers` 等步长描环),模糊档随 blur 能力再评估。
- 验证:render 新增 3 条(全路径系数/圆角/阴影环),render 45/46(1 红为既有 W9 基线);`ui` 的 `fill_round_rect` 上收门面后 ui/nav 行为零改;全仓 `moon check --deny-warn` 零错零警、库测试 882 条 880 过(2 红同基线)。真机观感(opacity 演示页/阴影卡片)归 `测试文档/测试用例.md`。

## 前端化 P2-e 帧成本对照 + 自转组件的无效重绘闸门(2026-10-14)

真机反馈「showcase 切页卡顿、页面中段组件渲染延迟」后先做对照实验再归因(探针 `experiment/showcase_cost_bench`:14 页 ×120 条文本次、1835 个绘制控件、整页重绘 20 帧,同机同树只换版本):

- **读数**:无文本布局缓存的 `380610a` = 9.9/11.95 ms 每帧(warm/cold);加了 C 侧文本布局缓存的 `323b537` = 3.35/3.25;P2-e 四批之后的 `HEAD` = 3.4/3.35。⇒ **缓存让整页重绘快约 3 倍**,**每帧读样式槽(P2-e)在噪声内**,不是卡顿来源。cold(1680 条各不相同,超缓存 1024 上限)在本机 Pango 路径没有退化到无缓存水平,但**「超限整表清空」这条策略在 Windows/DWrite 侧还没量过**——判据已留(同一探针跑两版对照),真机账本由 `SHOWCASE-PROF` / `showcase-prof.txt` 出。
- **闸门落在「这一帧我被画到了吗」**:轮播自转与动图换帧走进程级 `@core.set_timeout`,原来只判 `rotation.paused`,**所在页被隐藏时照样每个周期切页 + `invalidate()` ⇒ 整窗重绘白做**。控件层**没有指向父控件的引用**——父子互指是引用环,本工具链的计数式回收断不掉(见「分隔布局」批那条),所以不能问「祖先可见吗」。做法:core 加进程级绘制轮次 `bump_paint_epoch()`(宿主 `App::paint_frame` 每帧进遍历前 +1),`paint_at` 过了 `visible` 与视口剔除两道关才把轮次记进 `Widget.paint_epoch`,`Widget::is_painted()` 即「本帧被画到」;自转回调里 `if !w.is_painted() { 只排下一拍,不切页不置脏 }`——隐藏页省掉全部无效帧,复现可见后自动接上。
- **配套坑(测试侧,顺序敏感)**:轮次是**进程级**的,同包多条测试共用。原来那些「不画直接 `fire()` 派拍」的自转测试靠 `0 == 0` 蒙对——新测试一 bump 轮次就把它们变成假红。定则:**驱动自转的测试必须先画一帧**(与真实宿主同形),否则断言量的不是「被画到」而是初始零值。
- **验证**:新增 1 条白盒(隐藏整块 → 派拍:不切页、`invalidate` 计数不涨;恢复可见 → 继续切页),`moon test ui` 140/140、库全包 872/872、`cd gui && moon check --deny-warn` 零警告;showcase 退出打 `SHOWCASE-PROF`(帧数/布局/绘制/上屏/最坏一帧)。`frames` 数还是异常高 = 仍有别的东西在空转(下一步就按这一格判)。

## 脏区局部重绘的收窄缺陷:切段/切页不自动刷新(2026-10-14,真机反馈)

- **环境**:真机走查 `examples/showcase`,在「脏区局部重绘」落地(帧位图复用 + 按裁剪框绘制)之后;账本由示例退出时的 `SHOWCASE-PROF` 行给出。
- **现象**:切段/切页**页面不刷新**,要把鼠标悬浮到某个控件上,那块内容才跟着重画出来;`SHOWCASE-PROF`(615 帧 / 1323ms,均 2.2ms,最坏一帧 134ms)看不出异常——帧确实画了,只是只画了一小块。
- **根因**:`App.dirty_rect : Rect?` 用 `None` **一词双义**——既表示「整窗脏」又表示「本批还没有脏区」。同批里先来一次整窗请求(`invalidate()` / `schedule_paint` / `host_repaint_all` 都只写 `dirty_rect = None`),随后指针路由按 hover 变更走了 `mark_widget_rect`,而它的形态是 `Some(rect_union(dirty_rect, w.rect))`,`rect_union(None, r) = r` ⇒ **整窗请求被收窄成鼠标底下的那个小矩形**,这一帧只重画那一格,其余部分保留上一帧像素。「悬浮才刷」就是收窄后的小矩形恰好盖住了鼠标底下那一格。
- **修复**:`App` 加 `mut dirty_full : Bool`,整窗请求(`schedule_paint`、`host_repaint_all`)置位;局部置脏改走纯函数 `accept_widget_rect(full, cur, r)`——`full` 为真时**只维持不收窄**;`paint_frame` 用 `dirty_clip(full, rect)` 取这一帧的裁剪框(整窗请求 → `None` 即不裁),取完把标志与脏区一起复位。两个判定抽成纯函数是为了能钉桩:宿主 `App` 要真窗口,而这两个判断不需要。
- **通用口径**:`Option` 承载「两种不同的无」迟早出这类事故——同一个 `None` 表示「整窗」又表示「空集」时,任何「往累积里并一笔」的操作都会把强语义写成弱语义。要么加一位标志(本批做法),要么换成显式枚举(`Whole | Region(Rect)`)。
- **验证**:core 新增 1 条纯函数回归(未请求整窗时照常累积成并集;已请求整窗时局部置脏不得写成小矩形;裁剪框整窗优先),`moon test core` 133/133、分包全跑 882/882(逐包绿)、`cd gui && moon check --deny-warn` 零警告。真机复验(用户执行):showcase 切段/切页后**鼠标不动**应立即看到新页,复跑 `moon run examples/showcase` 退出贴 `SHOWCASE-PROF` 行(`frames` 不应因这一改动上涨——只在同批已有整窗请求时维持整窗语义)。

## 表格悬停不是整行 & 「添加一行」没反应:脏区只标最深那颗 + 去重 Store 存了被原地改的数组(2026-10-14,真机反馈)

- **现象①**:单选表格鼠标悬停时只有指针底下那一格变色,整行底色不亮(用户确认所有表格都有这问题)。
- **根因①**:不是绘制问题——无头探针实测,`set_hover(cell.id)` 之后整行(440px)从 x=10 到 x=400 全是 `fill_hover` ✓。坏在**脏区范围**:悬停是父链语义(与 CSS `:hover` 同义,`set_hover` 会把整条祖先链标 `hovered`),而宿主在指针路由后只标了「旧/新悬停那颗控件的矩形」——行画了整行底色,重绘窗口却只有鼠标那一格,于是看起来「只亮一格」。
- **修复①**:`App::mark_state_chain(id)` 沿命中链标脏——最深那颗必标,祖先只在**自己的绘制随状态变**时才标。这个「会随状态变」由 `@style.apply` 落成 `Widget.paints_state`(样式带 `hover`/`active`/`focus` 任一桶即为真),core 不认识样式层、只读这个布尔。链上没有状态祖先时代价仍是一格,不会因为改用链标脏就退回整窗。
- **现象②**:showcase 点「添加一行」表格不长行。
- **根因②**:Store 的内建去重按**值**比(`T : Eq` 时走 `set_eq`),而示例把 `lang_base` **这个数组对象本身**存进了 Store,之后「添加一行」原地 `lang_base.push(...)` 再 `table_rows.set(lang_base)`——新旧值是同一个对象(内容也一起被改了),必然相等 ⇒ 通知被吞,订阅里的整表重建根本不跑。换 `set(rows.copy())` 也一样被吞(存着的那个对象已经是新内容)。
- **修复②**:初值存快照 `Store::new(lang_base.copy())`,让 Store 里的值与原地被改的数组不是同一个对象 ⇒ push 后 `set` 的新旧值才真的可比、通知正常发出(排序路径同样受益:顺序变了才通知,顺序没变就跳过——正是去重该做的事)。
- **通用口径**:① 任何「父链语义」的状态(悬停/按下/焦点)都必须在标脏时覆盖到**会自绘该状态的祖先**,否则局部重绘会画出半更新的一帧;② 「原地改数组 + set 同一个数组」在去重 Store 上是死路,要么每次给新快照,要么显式 `set_always`。
- **验证**:`moon test core` 136/136 新增 1 条钉桩(带状态桶的祖先被并进脏区→宽 ≥200;链上无状态祖先→脏区宽 ≤50.5),库全包 922/922,`cd gui && moon check --deny-warn` 与 examples 模块零警告(顺带删掉因此不再被引用的 `App::mark_id_rect`)。真机复验:悬停整行变色;点「添加一行」表格多一行且回显跟着走。

## 时间线连接线断成几截:行间距用 `row_gap` 分行、线只画在行内(2026-10-14,真机反馈)

- **现象**:showcase「数据展示 → 时间线」三个节点之间的竖线是断的(每处间隙空 12px)。
- **根因**:每行的标记格只在自己的行盒里画线(`fill_rect(9, top, 2, bottom - top)`,`top/bottom` 由首/末行夹到点心),而行与行之间的 12px 是容器 `row_gap` 给的——**那段不属于任何控件**,没人画它,线就在每一处间隙断开。
- **修复**:行间距画进**本行**(非末行的 marker 与行盒长到 `height + gap`,末行不带间距),`timeline` 不再传 `row_gap`。点心仍按内容带算(`cy = height / 2`),所以圆点位置与首/末行的起止都没变,只是线多长了一段属于自己的间距。修后行高实测 68 / 68 / 56,行位仍 0 / 68 / 136(整体高度不变)。
- **通用口径**:凡是「跨行连续的装饰」(连接线/时间轴/表格分隔线/滚动条轨道)都不能靠容器间距留白——间隙不属于任何绘制单元。要么把间距画进本行(本批做法),要么让容器自己画那条贯通线。
- **验证**:`moon test ui` 156/156——时间线那条用例改成断言行高 `(68, 68, 56)` 并新增两处**间隙必须有线**的像素断言(`pixel(10,60)`、`pixel(10,130)`);对照实验=改回 `row_gap` + 行内不带间距,当场红 `(56,56,56) != (68,68,56)`。库全包 921/921、`cd gui && moon check --deny-warn` 与 examples 模块零警告。真机复验:时间线竖线从首行点心一路连到末行点心,中间无断口。

## 面包屑「点击不导航」:当前项按位置判(末项)而不是按导航状态判(2026-10-14,真机反馈)

- **现象**:showcase「导航组件 → 面包屑」点末项「基础组件」没反应。
- **根因**:组件自己的注释写的是「**当前项**深色不可点」,代码却按位置判——`is_last` 既当「当前项」用来上深色,又当「不可点」用来拦 `on_click`。演示给的三项是静态列表 `["数据展示", "导航组件", "基础组件"]`,当前页是中间那项 ⇒ 末项既不是当前页又被判成「当前项」,永远点不动。组件逻辑没坏(点非末项确实写 Store),坏在**「当前」的定义取错了**——导航状态才是唯一的权威。
- **修复**:可点与配色都改按 `selected.get() == mine` 判:等于导航状态的那一项深色、点它不改值;其余一律可点直达(含末项)。分隔符 `/` 照旧不可点。
- **配套**:nav_wbtest 那条用例原本断言「末项不改值」(照着错规则写的),改成「末项也直达 + 当前项不改值 + 分隔符不改值」;对照实验=把判据换回按位置(`i < n - 1`)当场红 `"列表" != "详情"`,换回即绿。showcase 段说明同步(原文写「当前项无特殊高亮、点击直达」,与代码两头都对不上)。
- **通用口径**:「哪一项是当前」只有一个来源——绑定的那个 Store。任何用位置(末项/首项)代替状态做判据的写法,在演示与真实层级不一致时就会露出「看着能点却点不动」的死角。
- **验证**:`moon test ui` 156/156、库全包 921/921、`cd gui && moon check --deny-warn` 与 examples 模块零警告。真机复验:面包屑三项逐个点都能换页,只有当前页那一项不变灰也不响应。

## 时间弹层的标题画在面板上不占位:第一行步进被压住(2026-10-14,真机反馈)

- **现象**:时间选择器弹层顶部「00:00」与第一行 `[−] 时 [+]` 叠在一起。
- **根因**:那行时间不是子控件,是面板自己的 `on_draw` 里画在 `(0, 0, w, 28)` 上的一块浮墨;而步进/按钮是真正的子项,从内边距 `top=10` 起排 ⇒ 第一行落在 y=10..42,正好被 0..28 的标题压住。**绘制层「顺手画个头」不等于占了一个布局位**——同一条坑在 `md_marker`(序号格没注册测量→0 高、数字掉到基线)已经记过一次。
- **修复**:标题改成**占位的子件**(高 28、宽 100%),面板 `on_draw` 只留底色与描边;顺手把内边距补成四边(原来只给 `top`/`left`,按钮行贴死下边缘)。修后弹层子项实测:`y=10 h=28`(标题)→ `38/32` → `70/32` → `102/28`,面板高 140,相邻零重叠。
- **配套(测试侧)**:三条按 `panel.children()[0]` / `[2]` 取步进行与按钮行的既有用例索引整体后移一位(标题现在是第 0 个子项),注释写明「标题是占位子件」;另加一条布局钉桩——子项数=4、首项是 28 高标题、逐对相邻不重叠、面板高度包住内容。
- **验证**:`moon test ui` 156/156、库全包 921/921、`cd gui && moon check --deny-warn` 与 examples 模块零警告。真机复验:时间弹层顶部时间独占一行,步进两行与取消/确定依次排开、四周留白一致。

## `stroke_rect` 是内侧描边,调用点却按居中口径给参:整圈往右下偏 1px(2026-10-14,真机反馈)

- **现象**:色板(color_picker)那一格格色块的描边看着「位置偏了」——左/上边留一条 1px 的色底,右/下边描边贴死边缘。
- **根因(逐像素量出来的)**:门面对外口径写死「`stroke_rect` 描边落在矩形**内侧**」(两后端同实现:cairo 桩 `cr_stroke_rect` 与纯光栅 `Raster::stroke_rect` 都按 `lw` 往里画并做像素吸附),但**全仓 28 处调用点按的是 Canvas/CSS 那套「描边居中」习惯**,给的是 `stroke_rect(0.5, 0.5, w - 1.0, h - 1.0)`。内侧语义下这条调用把环画进 `[0.5, 1.5]` → 吸附到第 1 列,而右/下边落在最后一列 ⇒ 环整体往右下偏 1px。探针读数(26×26 色格,中线一行):修前 `F B F…F B`(第 0 列是填充),修后 `B F…F B`(第 0 列与第 25 列都是描边)。
- **换算规则(居中口径 → 内侧口径)**:`(x, y, w, h)` 配线宽 `lw` ⇒ `(x - lw/2, y - lw/2, w + lw, h + lw)`。所以 1px 外圈就是 `stroke_rect(0.0, 0.0, r.w, r.h)`;往里缩一圈的焦点环 `stroke_rect(1.5, 1.5, w - 3.0, h - 3.0)` ⇒ `stroke_rect(1.0, 1.0, w - 2.0, h - 2.0)`。
- **改动范围**:ui 族(overlay/datepicker/form/virtlist/table/nav/datetime/scroll/message_box/declarative)与 chart 族(tooltip/boxplot/draw/treemap)、示例两处(sysmonitor、showcase 的 events/canvas)一起切过,共 28 处;`fill_rect`/`clip_rect` 不受影响(它们本就是整数像素盒语义)。
- **一条测试跟着几何改**:form_wbtest 的按钮焦点环用例原先采第 1 列像素(那是照着偏移后的错几何写的),现在采第 0 列并在注释里写清「内侧描边、环贴盒边」;另加一条色板对称性钉桩(左右同列、上下同列、描边不等于填充)——偏移回归会当场红。
- **验证**:`moon test ui` 155/155、库全包 920/920、`cd gui && moon check --deny-warn` 与 examples 模块零警告。真机复验(本机 Linux/X11):色板每格四边描边等宽、不再有一侧露出色底;按钮/输入框/面板/浮层的 1px 边框四边对齐。

## 输入框默认吃不到键盘焦点:`focus_id=0` 的口径要收在库里(2026-10-14,真机反馈)

- **现象**:showcase「表单组件」页的输入框点不进、打不了字;同页缺 EP 那个清空 ✕;「数据输入」的步进器三格高度看着不齐、没粘成一块。
- **根因①(点不进)**:宿主按「命中路径上第一个非零 `focus_id`」判可聚焦(`Widget::focusable_at`),而 `input` / `textarea` 的 `focus_id?` 默认 **0** —— 不显式给号就是**永久不可聚焦**。示例与使用者都得自己记得给号,等于把「输入框打不了字」埋进每个调用点(探针实测:不给 focus_id 时 `focus_id=0`、`focusable_at` 返回 `None`)。
- **修复①**:文本类组件默认**自动分配**焦点号(`auto_focus_id`:未给就从 1000000 起递增,避开使用者手写的 21/101 那类小序号;显式给了仍以它为准)。Tab 环绕按注册顺序=挂载顺序,与树序一致。`select` / `button` 的 `focus_id` 保持原口径(它们的可聚焦是刻意 opt-in,涉及浮层与激活键语义,不在这个批里动)。**注**:只给号还不够——号还得进宿主焦点栈,而当时「谁建控件谁注册」这条纪律只在示例里成立,所以表单页照样打不了字;补的口子见本节末《键盘焦点全线失效》(声明 `focus_id` 即由宿主对齐进栈)。
- **根因②(焦点环/光标不重画)**:`App::mark_focus_rect` 把**焦点栈的 id** 直接喂给 `mark_id_rect`,而后者按**控件实例 id** 查树(`root.by_id`)——两个 id 空间不是一回事:命中不到就整窗兜底(白画),恰好撞上某个实例 id 就把脏区标到**别的控件**上,新焦点格的焦点环与光标当帧不重画。
- **修复②**:新增 `App::mark_focus_id_rect`,走 `find_by_focus_id` 查树(查不到才整窗兜底);Down 里那次 `mark_id_rect(id)` 同步切过去。
- **`clearable`(清空 ✕)**:`input` 补同名参数(与 EP 一致**默认关**):有内容且「悬停或已聚焦」时右缘画一块 14×14 的 ✕(先盖一小块底色,长文本不与之叠字),点它整框清空并回写 Store、这一次按下不再定位光标;禁用态与只读态都不画。密码框按 EP 不给清空口。
- **步进器共框**:旧形态 `[-] 值 [+]` 各画一圈边框(左右圆角、中间方角),看着就是三个没粘住的盒子——**布局量出来三格同高**(都等于 `control_height`),不齐的是边框。改法:外框交给行容器按样式槽画一次(底色/描边/圆角/1px),三格只画自己的悬停底(内缩 1px 不盖外框)、内容字与靠内侧那条分隔线;整组宽 108 固定,不再随父容器拉伸。
- **验证**:`moon test ui` 154/154,新增 3 条——不给 focus_id 也能被 `focusable_at` 命中且键入回写 Store(并验显式号优先、两个自动号不撞号)、`clearable` 悬停时热区像素确有变化且点它 Store 归空、步进器三格同高同边首尾相接 + 点 +/- 改值 + 触界不再改值;库全包 918/918、`cd gui && moon check --deny-warn` 与 examples 模块零警告。真机复验:表单页输入框能点进能打、悬停出 ✕ 点它清空、步进器三格粘成一块。

## 文本帧级批的三件桩双定义:Linux 链接失败(2026-10-14,`moon run examples/showcase` 当场报)

- **现象**:`/usr/bin/ld: ... multiple definition of pt_flush`(以及 `pt_flush_if_overlap`/`pt_set_batching`),两处分别是 `gui/build/libyue_text_pango.a(stub.o)` 与 `_build/native/debug/build/NoahLiu/native-gui/text/libtext-*.a(stub.o)`——同一个 `stub.c` 的两个编译产物。
- **根因**:Linux 上 `gui/text/stub.c` **被编译两次**:prebuild 带 `-DWM_STUB_PANGO` 编进 `build/libyue_text_pango.a`(真实现),moon 的 native-stub 拿不到 pango 头、不带宏再编一次——那次**必须落空**(文件末尾的注释就写着这条纪律:落不进任何分支、编成空翻译单元,真实现由归档提供)。帧级文本批新增的三件写在文件最外层 `#endif` 之后的 `#ifndef _WIN32` 里,落在所有分支之外 ⇒ 两次编译各出一份。Windows 侧靠 `_WIN32` 排除躲过了,Linux 侧没躲过。
- **修复**:三件挪进分支——`WM_STUB_PANGO` 分支一份(Pango 逐段即绘即混、不攒批,冲刷是空操作)、`#elif !defined(__linux__)` 分支一份(macOS 占位);Windows 的真实现仍只在 `dwrite_text.cpp`;Linux 的 native-stub 那次继续编成空 TU。
- **通用口径**:往 `gui/text/stub.c`(同构的还有 `render`/`win` 等按「单一 stub.c 多分支 + prebuild 宏」组织的平台桩)加跨平台函数,只能加进**已有分支**或新开一条 `#elif`,写在最外层 `#endif` 之后就会与 prebuild 归档双定义。判据一条命令:`nm --defined-only _build/native/debug/build/NoahLiu/native-gui/text/libtext-*.a | grep -c <符号名>` 应为 **0**。
- **验证**:`moon build examples/showcase --target native` 从 workspace 根与 `examples` 模块各跑一次都通过、`showcase.exe` 出件;`nm` 复验 moon 侧归档里 `pt_flush` 定义数 0;`cd gui && moon check --deny-warn` 零警告、text+core+ui+render 360/360。

## 页面构造期排的定时器永不触发:图表页一直「暂无数据」(2026-10-14,真机反馈)

- **现象**:showcase「图表 → 折线」两段画布恒为「暂无数据」、y 轴停在 0..1,仪表盘也不动;「暂停推点」勾与不勾都没反应(这条正是早前那条「点线图推点按钮没用」反馈的剩余部分)。
- **根因**:`@core.set_timeout` 走的是**进程级**延时通道,这条通道由 `App::new`(内部 `install_host_hooks`)安装;没有宿主时它是**空操作并返回 0**(`core/loop.mbt` 的契约)。而示例里 `page_charts(app)` 是 `@ui.mount_window([...])` 的**实参**,求值早于建窗——所以「页面函数体最后一行排第一拍」这种写法排进的是空通道,回调永不触发,自重排的循环也就永远起不来。数据侧没问题:`series_push` 走 `set_always`(绕开 Store 去重)、画布在订阅回调里 `invalidate()`,都是通的。
- **修复(示例侧口径)**:**第一拍挂在挂载回调上**——`@ui.row([...charts...], handle=fn(_) { line_pump() })`。页面构造期那两行 `let _ = @core.set_timeout(...)` 删除;页内代码示例串同步改写(不然演示文本继续教错写法)。**〔更正 2026-10-15:本条把 `view` 的 `handle` 当成了挂载回调,口径是错的——`handle` 同样在构造期就跑,这次修复没有生效,见下一条。〕**
- **通用口径**:任何在「页面/组件构造函数」里排的定时器、以及任何读 `set_timeout` 返回句柄去 cancel 的写法,都要放到挂载后(或宿主 App 建好之后);`set_timeout` 返回 0 就是「没有宿主」的信号,别把 0 当句柄存。
- **同批一条(同一张截图看到的)**:段说明 `@ui.text(s.desc, max_width=900.0)` 没给 `wrap=true` ⇒ 长说明是**一条不折行的 900px 文本**,超出部分整片被裁(截图里折线段说明末尾断字)。改 `wrap=true`,段容器不再被单行长文本撑宽。
- **验证**:`cd examples && moon check showcase --deny-warn` 零警告、`cd gui && moon check --deny-warn` 零警告、库全包 915/915 不回归。真机复验(用户):打开「图表」页 → 折线两幅应在 0.5s 一拍爬出三角波、y 轴随值自适应、右端有最新值标注;勾「暂停推点」曲线停住、取消勾选继续;仪表盘左环应 2Hz 平滑走。**〔更正 2026-10-15:这条复验当时并未真正通过——推点链仍死,当时误判为已修。〕**

## `view` 的 handle 不是挂载回调:图表页推点链在「修复」后仍死(2026-10-15,Windows 真机反馈 + 本机探针实证)

- **现象**:上一条按「第一拍挂 `handle`」修复并记档后,图表页折线仍无推点;真机退出读数 `showcase-prof.txt` 里一条 `CHART-DIAG` 都没有(每拍一行,链活着必有),即自重排循环整条没起来。上一轮的「真机复验通过」结论是误判。
- **根因**:`node_of_new(finish)` 的 `finish` 是**构造期急切执行**的(`gui/core/node.mbt`,等价于「先 new 再配置」),`view`(`ui/basic.mbt`)把 `handle(w)` 写在 `finish` 里 ⇒ `handle` 在**建树时**就跑,不是挂载回调。而 `page_charts(app)` 是 `@ui.mount_window([...])` 的实参、求值早于建窗 ⇒ `handle` 里排的 `set_timeout` 落在**空通道**——与构造期直接排是同一个坑,换个位置没换时机。
- **实证**(`experiment/timer_probe`,Windows 本机,`moon run experiment/timer_probe`,读数落 `C:/tmp/timerprobe.log`):探针把首拍挂 `@ui.col(..., handle=...)`,日志 `ARMED pending=0`(挂载回调里排的定时器没进队列);`mount_window` 返回**之后**再排的定时器 `POST-ARM pending=1` 且 400ms 后准点响——钩子本身是好的,断的只是时机。
- **修复**:`core` 新增 `Node::on_mount(f)`——包一层 Node,把 `f` 推迟到**真·挂载时机**(`mount_into` 把本体挂进父控件之后)跑;showcase 图表页折线/仪表盘两处首拍从 `handle=` 改为 `@ui.row([...]).on_mount(fn() { pump() })`,段正文惰性挂载在首次选中该段时才 `mount_into`,那时宿主早已就绪。页内代码示例串与 charts.mbt 头注释同步改成 on_mount 形态;CHART-DIAG 诊断行拿到读数后删除。
- **通用口径**:`view`/`row`/`col` 的 `handle` 是**构造期**回调(适合做布局微调、订阅 Store 这类不依赖宿主的事);凡要等宿主的(排定时器、读宿主句柄),一律 `Node::on_mount` 或 `mount_window` 的 `handle(app)`(那是真·挂载后)。`on_mount` 挂载几次跑几次,一次性启动回调由调用方保证只挂一次(段正文的惰性挂载有 `mounted` 守卫,天然满足)。
- **验证**:core 新增 1 条 on_mount 回归(构造期不跑、`mount_into` 时在本体已进父之后跑),`moon test core` 144/144;`cd gui && moon check --deny-warn` 零警告、`cd examples && moon check --deny-warn` 零警告、showcase 构建链接通过;库全包回归见当轮读数。真机复验归 P42:图表页折线 0.5s 一拍爬三角波、勾「暂停推点」停、取消恢复;仪表盘左环 2Hz 走。

## yoga-mbt 自由空间漏减行间隙:grow 项吃掉 gap 把整行顶出容器(2026-10-14,真机反馈「复制按钮还是有问题」)

- **现象**:showcase 段正文代码区那行(左「代码」+ 中间 grow 撑开的空文本 + 右「复制」)里,按钮右半边裁在窗口外。同类形态到处都在用(`@ui.row([..., spacer, 按钮], column_gap=...)`),只是别处溢出的是一点边距、没人注意。
- **根因**:本端口的 §9.7 分配里,`initial_free`、循环内的 `remaining`、auto margin 的 `free`、justify-content 的 `free2` 都只减「子项外框之和」,**没减本行的间隙总和** `gap x (n-1)`;而定位阶段又逐项加 `main_gap` ⇒ 有 grow 项时它正好多吃 `gap x (n-1)`。
- **最小判据**(钉在 `modules/yoga-mbt/src/layout_wbtest.mbt`):行宽 100、`column_gap=10`、子项 [固定 30, grow 1] ⇒ grow 项应为 60,修前算成 70(整行 110)。
- **修复**:行分配前先算 `gap_total = main_gap x (line.length()-1)`,上述四处自由空间统一减它(规范:间隙占位、不参与 grow/shrink 分配)。
- **实测**(无头探针挂真实页面树,窗口 1010、侧栏 180 → 视口 830):修前 spacer=728、按钮 `x=962 w=50` → 右边界 1012,越过窗口(1010)与滚动条(1002);修后 spacer=712、按钮 `x=946..996`,正好贴在行右界(内容 802 + 左右 padding 14)上。
- **验证**:`moon test src`(yoga-mbt)102/102(含新增这条)、库全包 916/916、`cd gui && moon check --deny-warn` 与 examples 模块零警告、`moon build examples/showcase --target native` 通过。这条与「段条换行」「视口 min 0」是三个独立问题,叠在一起才造成用户看到的「正文塌 + 按钮裁一半」。

## 段条「超宽自动换行」是假口径:`Style` 补 `flex_wrap` 才真换行(2026-10-14)

- **现象**:showcase 页面顶部的段条(segmented)段数一多就横向溢出被裁,而 `shared/section.mbt` 的注释写着「超宽自动换行」。
- **根因**:本栈 `ui` 从不写 `flex_wrap`,样式层也**没有这个属性**(CSS 有 `flex-wrap`,我们的 `Style` 少一条),所以任何容器都是 `NoWrap` —— 注释描述的是一个不存在的能力。
- **修复(按「属性名 = CSS 属性名」补进样式层,而不是给组件开参数)**:`Style` 开 `flex_wrap : FlexWrap?`(`types.mbt` 用 `pub using @yoga {type FlexWrap}` 引类型短名),工厂收 `flex_wrap=`、`merge`/`empty_style`/setter 同步、`apply` 落 `Node::set_flex_wrap`。
- **换行的两条必备配套(真机第一版只加了 `flex_wrap`,结果把正文压扁)**:
  1. **段条放在列里,不要放在 row 里**:row 的交叉轴不拉伸,换行容器按内容定宽(实测 1000 可用只给到 450),段被折成六七行;列的交叉轴默认 stretch ⇒ 拿到整宽,段多才按整宽折。
  2. **换行容器与父链每一层都显式 `min_height=0`(横向同理 `min_width=0`)**:规范 §4.5 里列内子项的 `min-height:auto` 取其 **min-content 高**,而可换行行容器的 min-content 高 = 全部子项堆叠(6 段 ×30 + 5 间隙 = 200)。这条下限沿父链一路上传——实测段条 224px、正文从 646 掉到 476。引擎行为符合规范、不是 bug:显式归零才是段条这类容器该有的写法。
- **最终形态**:`strip = @ui.col([@ui.segmented(names, selected, class=[style(flex_wrap=Wrap, row_gap=4.0), style(min_height=0.0, min_width=0.0)])], padding=10.0, class=[style(min_height=0.0, min_width=0.0)])`。
- **验证**:`moon test style` 26/26 新增 1 条布局钉桩(100 宽行内容器放两个 60 宽子项:`NoWrap` 时第二项 `top=0`,`flex_wrap=Wrap` 后 `top>=20`);`modules/yoga-mbt` 新增 1 条钉住 §4.5 那条下限与归零后的取值(同一棵树:min:auto 时 strip 高 200,显式 `min_height=0` 后 30)。修完用无头探针量真实页面树(1200×700):段条 54、正文容器 646、代码文档页视口 652 / 内容 808(可滚 155)——段条不再吃高度,正文有确定视口且内容超出即可滚。`cd gui && moon check --deny-warn` 零警告、库全包 915/915、yoga-mbt 全绿。

## 滚动容器视口被内容撑高:内容超出窗口却滚不动(2026-10-14,真机反馈)

- **现象**:showcase 段正文超出窗口高度,滚轮与滚动条都没有可滚的量(内容被底部直接截断)。
- **根因**:`scroll_view` 的视口节点没有设 `min-height`。Yoga 的 flex 子项默认 **min-size = auto**(内容多大就不许小于一屏那么多),于是视口被自己的内容顶到自然高——`view_h == content_h`,`max() = content_h - view_h` 恒为 0,滚轮与滚动条算出来都是「不需要滚」。调用点写 `handle=fn(v){ v.node.set_flex_grow(1.0) }` 只给了 grow,救不了这条默认值。
- **对照实测**(无头探针,20 行 ×20px 内容放进 240×140 的父容器):修前 `viewport=676 content=676`(视口等于内容高)→ 修后 `viewport=200 content=676`(视口停在父给的尺寸,内容按自然高撑开)。
- **修复**:`scroll_view` 内部给视口写 `min_height=0` 与 `min_width=0`(库级收口,所有调用点一起受益:showcase 段正文与侧栏、native-app、`virt_list` 的宿主等)。显式给了 `height=` 的用法不受影响(显式尺寸赢过 min)。
- **验证**:`moon test ui` 151/151,新增 1 条钉桩——只给 `flex_grow` 不给高度时:视口高 ≤ 父高、`content_h=400`、`view_h=140`、`max()>200`,且 `scroll_by(60)` 后内容节点确实上移;库全包 914/914、`cd gui && moon check --deny-warn` 零警告、examples 模块零警告。真机复验:showcase 段正文与侧栏长列表应可滚轮滚、可拖滚动条。

## Markdown 页两处缺陷:样式区间单位错口径 + 富文本行从不折行(2026-10-14,真机反馈)

- **现象**(showcase「代码文档 → Markdown」段):① 中英混排段落里粗体/斜体/行内代码/链接那几段出豆腐块并互相压字;② 右边缘整片被裁字;③ 代码区顶行的「复制」按钮有一半在可视区外;④ 内容区纵向滚不动(同批另查,见下一条)。
- **根因①(单位口径)**:`md_span_ranges` 按 **UTF-16 code unit** 累计区间端点,而 `AttributedText` 的契约是 **UTF-8 字节下标**(`text/attributed.mbt` 头注与 `rt()` 传给 C 的 `tlen` 都是字节;C 侧 Pango 直接把 `start_index/end_index` 当字节索引用,Windows/DWrite 侧再经 `ptw_widx` 换算)。一个汉字 3 字节只算 1 个 code unit ⇒ 区间整体前移,样式落到前面的字符上、端点还会切进字符内部(真机即豆腐块 + 压字)。纯 ASCII 段两者相等,所以这段代码在英文示例里一直是「看起来对」的。
- **根因②(从不折行)**:`md_rich_label` 用 `wrap=false` 并把节点宽设成**整段自然宽**(实测:一段在 `width=480` 的文档里量出 656px)。后果是右边缘整片裁字,并且段容器的宽度被这条超宽行撑到可视区外——「复制」按钮排在行尾,于是被裁一半。
- **修复①**:改 `md_byte_len`(按码点算 UTF-8 序列长度)出区间;`md_span_ranges` 的口径注释与文件头同步改成「UTF-8 字节」。
- **修复②**:构造期贪心折行——中文与全角标点**逐字**为单元(中文没空格,断点只能在字之间)、拉丁词连尾随空格为一个单元(不在词内断)、`\n` 为硬换行、**单个单元就超宽**(长 URL)时按字符硬切;一行一个 `AttributedText`,删除线横线按该行像素区间画,链接命中改成「先按 y 定行、再按行内像素区间定段」。折行宽度按容器派生:`md_narrow(ctx, by)` 给列表项(扣标记列/复选框)、引用块(扣竖条)、脚注定义、定义列表各自收窄,表格单元格按列宽 `max_w=ctx.width/列数`。
- **工具链读数**:MoonBit `String.length()` 返回的是 **UTF-16 code unit 数**(`"甲乙"=2`、`"👍"=2`、`"abc"=3`),既不是字节数也不是码点数;`String.sub(start=,end=)` 也不是字节口径。所以「按字节契约」的 API 一律不能拿这两条当长度 oracle,字节长度要自己按码点算或走 `@utf8.encode`。
- **验证**:`moon test mdview` 31/31,新增 4 条——字节读数(`前👍中` 后粗体段应落 `[10,16)`)、区间端点必须落在字符边界上、折行后没有任何子孙宽过文档宽且段落高明显多于一行、长 URL 必须硬切。**判据有效性已对照实验**:把 `md_span_ranges` 换回旧的 UTF-16 累计,两条新判据当场红(`4 != 10`、「区间终点切进字符内部: 4」),换回即绿。库全包 913/913、`cd gui && moon check --deny-warn` 零警告、`cd examples && moon check --deny-warn` 零警告。
- **待真机复验**(用户执行):豆腐块/压字是否消失、右边缘是否不再裁字、复制按钮是否完整。「内容区纵向滚不动」另查得根因(视口被内容撑高),见下一条。

## 观感修正:`badge_dot` 由方角改真圆点(2026-10-14)

- **现象/根因**:`badge_dot` 注释与命名都是「圆点徽标」,但绘制走的是 `fill_rect`——出来是个 8×8 方角块。属前端化 P2-e 记档的边界项(当时只迁样式通道、不改画法)。
- **修复**:改走 `Painter::fill_round_rect`,默认半径 = 短边一半(内切圆);`class` 给了 `border_radius` 就按它,并夹到短边一半以内——想要方角写 `border_radius=0.0`,旧画法这条路仍然可达。底色仍从样式槽现取(`color_of(s.background_color, "")`),主题切换照旧跟。
- **验证**:`moon test ui` 150/150,新增 1 条像素回归——16×16 档下左上角那格无墨、中心有墨(内切圆判据),`class=[style(border_radius=0.0)]` 档左上角有墨。真机观感(`showcase` 数据展示页 / `native-app` 的圆点)归 `测试文档/测试用例.md`。

## 分隔把手拖动不跟手:增量按把手自己的局部坐标算,把手平移后把上一帧位移扣了回去(2026-10-14,真机反馈)

- **现象**:嵌套布局页的 `split` 把手,拖动过程中不跟手——拖到一半会往回弹。
- **根因**:`splitter_impl` 的拖动增量用的是**把手的局部坐标**(`ev.x` 由宿主按 `ev.x - w.rect.x` 下发),而把手本身会随首栏变宽而平移。于是每一帧的增量都少掉了上一帧把手自己的位移:`nw = first0 + (鼠标局部 - 起手局部)`,其中鼠标局部已经减过新的把手原点。实测(400 宽、ratio 0.5、起手在把手中心):第一次移动(鼠标 +50)把手落到 250 **看着对**;第二次移动(鼠标累计 +60)把手却退回 **210**——正确值 260。位移越大退回越多,观感就是"拖不动/往回弹"。
- **修复**:起手与移动都换成**窗口坐标**(`ev.x + s.rect.x`),增量与把手自己的平移解耦。这条换算即使在「一批事件里 rect 还没重排」的情况下也精确:局部值本来就是「窗口值 - 当时那个 rect.x」,加回同一个 rect 就还原。夹取口径不变(`min_first` / `min_second` 照旧生效)。
- **验证**:新增 `gui/ui/split_wbtest.mbt` 两条(本组件此前**零测试**)——① 起手 `hit_test` 必须命中把手、拖 +50 落到 x0+50、再拖 +10 落到 x0+60(旧口径这里退回 210)、抬起后再拖不改布局;② 两个最小宽度夹取(把手最远停在 `总宽 - 8 - min_second` = 312)。测试走的是宿主同款路径:`dispatch_pointer_to(把手 id, ...)` 模拟指针捕获期(直接对根调 `dispatch_pointer` 不带捕获,第二个事件就命中到别的栏里去了——第一版测试就是这么假红的)。**判据有效性已对照实验**:把 `win = at + origin` 换回 `win = at`,第二条移动当场红(实测 210)。`moon test ui` 160/160。
- **残留的那一半**:`@core.invalidate()` 走的是整窗广播(`host_repaint_all` 置 `dirty_full`),一次拖动 = 一拍一帧全视口重绘,debug 构建实测帧成本百毫秒量级——这一档是「已知差异」里的帧成本项(TODO §6.6),不是坐标问题;先确认坐标这条修完后再看观感是否可接受。
- **待真机复验**(用户执行):拖动把手是否跟手(快速来回拖动不往回弹)、两个最小宽度边界仍夹得住、抬起后不再跟随。

## 提示条 `closable` 只有热区没有标记:看不见的热区等于没有按钮(2026-10-14,真机反馈)

- **现象/根因**:`alert(..., closable=true)` 的 `on_draw` 只画浅底 + 左缘 3px 强调条 + 标题/描述,`closable` 那条分支**只装了 `on_pointer` 的右上角 24×24 热区,一个像素的标记都没画**。演示文案写着「点我右侧的 ✕ 试试」,右侧却什么都没有 → 真机报「图标的渲染有问题」。与图标尺寸那条批无关(那条是字形画到盒子短边 176% 被裁),这条是标记整只缺失。
- **修复**:标记与热区同源,一并画进 `on_draw`——`@icons.draw_icon(p, @icons.IconKind::Close2, r.w - 12.0, 12.0, 6.0, main)`:中心落在 24×24 热区正中、字形半径 6(落墨 ≈ 10.6px,走的是「s 为内容半径」口径),颜色用横幅主色 `main`(语义色 token 现取,换主题跟着走)。命名提醒:纯 ✕ 是 `Close2`(font_class 就叫 `close`),`CircleClose` / `CloseCircleFill` 是带圈档,别混用。
- **验证**:`moon test ui` 158/158,原「关闭热区只在右上角」扩成「热区与标记都只在右上角」,加两条判据——可关闭横幅右上角 24×24 里「与浅底不同」的像素 > 8,不可关闭横幅同区域必须 == 0(不许多画)。筛墨用「离浅底三通道差之和 > 30」,范围避开左缘 3px 强调条,不锁具体色值(换主题不假红)。**判据有效性已对照实验**:撤掉 `draw_icon` 那一行,标记判据当场红(`false` is not true),补回即绿。库全包 932/932、`cd examples && moon build showcase --target native` 链接通过。全仓 `--deny-warn` 仍被并行批 60e094e 的 5 条 sys 警告挡住(`appfind.mbt` 4 条、`recent_files.mbt` 1 条),非本批文件。
- **顺带排除**:演示文案里那两个「✕」是**正文里的 U+2715 字符**,本机 DejaVu Sans 与文泉驿微米黑都覆盖该码位(`fc-list :charset=2715` 实测有),不是缺字豆腐块;截图里那三个红框是用户手绘标注。
- **待真机复验**(用户执行):反馈组件页的可关闭横幅右侧应出现 ✕ 标记、点它整条收起;其余不可关闭的横幅不该出现标记。

## 硬阴影在四个角叠成深色圆斑：两个后端都没有反向弧，「内外环挖洞」挖不出洞（2026-10-14，真机反馈）

- **现象**：「过渡与效果」页那张 `box_shadow=8` 的卡片，四个角各一团深色，四条边倒是均匀一圈。
- **根因**：`Painter::box_shadow` 用「外环 + 反向内环 + fill 非零环绕」描环形带，内环走 `round_rect_path_ccw`，它靠**递减角度**调 `arc` 表达逆时针。但 `arc` 的 `ccw` 参数**两个后端都不生效**（`painter.mbt` 的文档自己写着：`cairo_arc` 对 `ea < sa` 会规范化成顺时针长弧，纯光栅器复刻同一条规范化）——于是内环每段实际扫了 270°，内边界根本没落在该在的位置，角上的洞没挖出来，多层环在角上互相叠加 → 圆斑。离屏出图对照（PNG 直读）：单层就有角斑，层数越多角上越黑（16 层时角上是实心黑圆）。
- **修复**：改成**一条描边**——线宽 = `spread`、中心线外扩 `spread/2`，正好铺满 `[0, spread]`；两后端各走自己的 stroke（宽描边在纯光栅器里是既有的 `stroke_polys` 能力，与所有边框同款）。`layers` 参数一并摘掉：各层 alpha 相同、层与层不相交，它只是把一条均匀色带切成 N 段，没有视觉作用。反向内环 helper `round_rect_path_ccw` 随之删除（包外无引用）。
- **同页另一条反馈（字号不会变）**：不是过渡的锅——演示把 `font_size` 写在**容器**的 `class` 上，而状态桶按控件各算各的，父块 hover 不会替子件换字号；改写到文本控件自己的槽上，并让它铺满整块（这样指针在块内任意位置都命中文本自己）。
- **验证**：render 的 `box_shadow` 回归改成**四角 45° 采样**（每个角取内外边界正中那点——旧画法在这里要么缺一块要么叠成斑）+ 本体内部与远处必须为 0；`moon test render ui` 206/206、库全包 939/939、`cd gui` 与 `cd examples` 的 `--deny-warn` 零错误零警告、`moon build showcase --target native` 链接通过；出图对照确认角斑消失、四周等浓。
- **口径**：**需要反向路径的填充（挖洞）在本栈两条后端上都不成立**——`arc` 只有正方向。要挖洞只能走折线近似（图表圆环那套先例）或改成描边；新画法一律优先「与 winding 无关」的形态。
- **待真机复验**（用户执行）：阴影卡片四周应是均匀一圈、角上无黑斑；「字号+底色」块悬停时字号 13→17 **一步**变大（字号不参与插值）、底色仍按 300ms 过渡。**（口径已变：2026-10-15 用户复验后要求字号也要渐变，字号已进插值集合并让测量期读同一份值，见「字号动画不是动画」节；阴影那条同样在本批复验）**

## 周期表「停不住」：自重排时把新句柄丢了，取消打在早已跑掉的旧号上（2026-10-14，真机反馈）

- **现象**：系统集成页的定时器区块，「1.5 秒后提示」正常出，「起周期表(1s)」也在响，但点「停表」后计数照涨。
- **根因**：演示里周期表是**回调尾自重排**的（本栈 `timer` 是一次性句柄），而重排那一行写的是 `let _ = a.timer(1000, tick.val)` —— **新句柄被丢弃**，`tick_id` 里留的还是第一次那个号。那个号在上一拍就已经从队列里移除，`cancel_timer(旧号)` 找不到项、什么也不取消，于是表照旧响。不是 `Loop::cancel` 的错：它按 id 找、找不到返回 false，语义正确。
- **修复**：重排时把新句柄记回去（`tick_id.val = a.timer(1000, tick.val)`），起表那一拍同样记；演示页的代码示例文案同步改成「每次都要记回新句柄才可停」。
- **口径**：一次性句柄 + 自重排 = **句柄每拍都要更新**；这条与 `Store` 去重那类一样是「形态自带的约束」，写进 design.md §6 与组件示例，别只留在提交说明里。
- **验证**：`gui/core/loop_wbtest.mbt` 新增一条把语义钉住——跑若干拍后 ①取消首号（早已跑掉）表照旧响、②取消最新句柄才停得住（`hits` 不再涨）。`moon test core` 137/137、库全包 938/938、`cd gui && moon check --deny-warn` 与 `cd examples && moon check --deny-warn` 零错误零警告、`moon build showcase --target native` 链接通过。
- **待真机复验**（用户执行）：起周期表 → 点停表 → 计数应立刻冻住；再点一次停表应回「表没在跑」；重新起表仍可停。

## 段条被正文高度挤塌:定高头部要 flex_shrink=0、可伸缩正文要 min=0(2026-10-14,真机反馈)

- **现象**:`代码文档` 页切到 Markdown 段后，页面顶部的 segmented 段条高度塌下去，标签戳出条外；切到「代码高亮」段就正常。
- **根因**：页面装配是「段条 + 正文列(`grow=1.0`)」放在一个列里，两边都给了 `min=0`（段条那侧是上一批为「段条超宽换行」加的：换行容器的 CSS §4.5 主轴 `min:auto` 等于 min-content 高，不归零会反过来吃掉整块正文高度）。**只归零不锁收缩**就留下反向通道：正文列没给 `min=0`，它的 min-content 高 = 整篇正文（Markdown 段是全文，2000px 量级），窗口只有 720，父列超容后 yoga 把**全部压缩量落到唯一可自由收缩的段条**上（它 min=0，而 yoga-mbt 的 `flex_shrink` 默认 **1.0**，`modules/yoga-mbt/src/style.mbt:53`）。短正文的段不触发，所以看着像「切了标签才塌」。
- **无头复现读数**（`gui/ui` 临时探针，结构与装配一致：根 300 高、段条 24 + padding 10、正文 2000）：现状段条实测 **23.32**（自然高 44，标签 24 直接戳出）；加「段条 `set_flex_shrink(0.0)` + 正文列 `min=0`」后实测 **44**。探针跑完即删，修复落在 `examples/showcase/shared/section.mbt`。
- **口径**：一列里「定高头部 + 可伸缩正文」两件事要分开锁——**头部锁收缩**（`flex_shrink=0`），**正文放开收缩**（`min_height=0` + `grow`），滚动交给正文里的 `scroll_view`。只给 `min=0` 是必要条件不是充分条件：它让容器能折行，同时也让它成了唯一能吃压缩的那一层。
- **本栈边界**：`Style` 字段集里有 `flex`(=grow) 没有 `flex_shrink`，所以头部锁收缩走 `handle=` 落 `w.node.set_flex_shrink(0.0)`（与 `scroll_view` 内容列同款）。要不要把 `flex_shrink` 补进样式工厂另计（见 design.md §6）。
- **验证**：`cd examples && moon build showcase --target native` 通过；本批只动演示装配，库侧无改动。全仓 `--deny-warn` 仍被并行批 60e094e 的 5 条 sys 警告挡住（`gui/sys/appfind.mbt` 4 条、`recent_files.mbt` 1 条），非本批文件。
- **待真机复验**（用户执行）：切到 Markdown 段后段条是否恢复定高（标签不再戳出）、段条在窄窗口下仍能换行、正文段内滚动照旧；其余 14 页逐页切一遍看有没有别的定高条被挤。

## 散点图千点级糊成实心带:点径按「点面积 × 点数 ≤ 绘制区面积」收口(2026-10-14,真机反馈)

- **现象/根因**:`scatter_t` 默认 `dot=6.0`,画法是不透明 `fill_rect` 方块。演示页 2000 点画进 320×260 的图(绘制区 260×224),点面积合计 2000×36=72000 px² 已是绘制区的 1.24 倍——**默认点径与点数量级根本不匹配**,相邻点互相咬合,整条相关带涂成一块实心,看不出任何分布形状。方块还额外吃掉 π/4 的视觉留白,密处连缝都不剩。
- **修复口径**:①默认 `dot` 收成 **3.0**,并把这条写成组件文档里的取值规则(点面积 × 点数 ≤ 绘制区面积,大点径要显式传);②画法改 `Painter::fill_round_rect`(半径=短边一半)=**圆点**,点与点之间天然留缝;③点阵层套 `set_global_alpha(0.7)`(在 `save()`/`restore()` 内,恢复照常),重叠处靠叠加显深而不是涂实,疏处仍看得见网格。趋势线与网格不受影响(画在 alpha 之前)。
- **实测读数**(离屏 `Painter::new(Bitmap)` 会话,判据用「离点色比离面板底更近」筛点阵墨迹,网格线/刻度天然排除):单点 `dot=15` 的着色包围盒 14×14、四角不沾墨、中心沾墨(旧画法 15×15 且**四角全沾墨**=方块);2000 点默认档下「纯点色」像素 201 格(旧画法 20189 格 = 绘制区 58240 的 35%,即实心)。两条判据都写进 `moon test chart` 回归。
- **工具链读数**(moon 0.1.20260920):①演示页那串 LCG 用 `% 2147483647` 取正余数不成立——**MoonBit 的 `%` 结果随被除数取号**,而 `seed * 1103515245` 溢出 int64 回绕成负数后余数就是负的,散点于是散到负半轴(真机读数:坐标轴成了 -100..100,而注释写的是 0..100)。取低位一律 `& 0x7fff_ffff`,溢出与符号一起消掉。②多行表达式里**运算符不能起新行**:`a + b
< c` 直接 `[3002]`/`[4139]`,比较要挪成中间 `let`。
- **验证**:`moon test chart` 190/190(新增 1 条双判据回归),**判据有效性已对照实验**:把画法与默认点径换回旧形态(`fill_rect` + `dot=6.0`),四角判据当场为真、纯点色 20189 格越过上界,换回即绿。库全包 931/931、`cd examples && moon build showcase --target native` 链接通过。全仓 `--deny-warn` 现被并行批(60e094e sys 平台批③)的 5 条警告挡住(`gui/sys/appfind.mbt` 重复 `#borrow`、未使用的 `ffi_file_mtime`、两处已废弃的字符串切片写法),非本批文件、未代为改动。
- **待真机复验**(用户执行):散点两图是否读作「一团点」而不是实心带、趋势线仍清晰、右侧小图(250×130,`native-app`)不回归。

## 图标字形画到盒子短边的 176% 再被裁:`draw_icon` 的内容半径口径要收在组件层(2026-10-14,真机反馈)

- **现象/根因**:`@icons.draw_icon` 第 5 参一直是**内容半径**(落墨 ≈ 1.76×s,路径数据 ±1000 归一 × `s*0.88/1000`),但 `@ui.icon` 与 `@ui.icon_button` 把**盒子边长**当半径传了进去(`size` / `icon_size`),字形于是画到盒子短边的 176%;宿主又按控件矩形裁剪,四边各切掉一大块。离屏像素探针读数(`Painter::new(Bitmap)` 会话上直接量落墨包围盒):`icon(size=24)` 的包围盒是 24×24 且**正好顶满盒子边界**(未裁时该是 44×44,`draw_icon(...,24.0,...)` 直接读得 `10,10-53,53`),`icon_button(box_size=28, icon_size=16)` 同样顶满 28 的盒——观感即「图标撑破容器、边缘被切、与容器不协调」。库里另外三处直连调用本来就是半径口径,不受影响:`message_box`(24 盒传 11)、`overlay` 弹条(传 7)、`nav` 侧栏项(传 6.72)。
- **修复**:`@ui.icon` 改按**当前矩形**取半径(`r.w.min(r.h) / 2.0`)——class 覆盖过宽高时字形仍随盒子走、不会溢出;`icon_button` 传 `icon_size / 2.0`,按钮盒(`box_size`)与字形盒(`icon_size`)各管各的,默认 28/16 落墨 ≈ 16,盒内留 6px 以上余量。`draw_icon` 与 `icon` 的文档注释把口径写进入口(「s 为内容半径 = 盒子边长的一半」「字形按盒子短边 88% 光学留白居中」)。图标数据侧无需动:803 条路径全量扫过,包围盒都占满 ±1000 且几何中心偏移 ≤60 定点单位(≈盒子 3%),没有偏心或尺寸不齐的条目。
- **工具链读数**(moon 0.1.20260920):`println` 只收一个 `String`(多参报 `[4015]`);`debug_printline` 对「4 个 Int + 2 个 Double」这类混参没有匹配重载(`%g` 亦不认,报 `[4021]`)——多条数值诊断一律走字符串拼接。
- **验证**:`moon test ui` 158/158,新增 1 条像素回归——`icon(size=24)` 落墨包围盒须落在 `[1,1]-[22,22]` 且横纵中心相等(实测 `1,1-22,22`),`icon_button(box_size=28, icon_size=16)` 须落进 `[5,5]-[22,22]`、宽度 10..17(实测 `6,6-21,21`)。**判据有效性已对照实验**:把两行换回旧口径(直接传 `size` / `icon_size`),该判据当场红(`a.0=0`、`b.0=0`,即顶到盒边界被裁),换回修复即绿。库全量 926/926、`cd gui && moon check --deny-warn` 与 `cd examples && moon check --deny-warn` 零错误零警告、`moon build showcase --target native` 链接通过。
- **待真机复验**(用户执行):空状态/结果页的大图标、侧栏深/浅切换按钮(月亮图标)、图标墙页(`size=30`)、表单前后缀与表格排序小图标,是否都不再顶破容器、边缘不再被切且居中。

## 前端化 P5:`transition` 属性过渡(状态桶插值 + 帧驱动,2026-10-14)

- **插值集合按「每帧从样式槽读出」这条线划**:参与过渡的只有 `color` / `background_color` / `border_color` / `border_width` / `border_radius`。理由不是省事——进布局的属性(字号、行高、尺寸、边距)一旦插值,每一帧都要重排整树;`opacity` / `box_shadow` 的生效点在 `apply` 落 `Widget.alpha_paint` / `shadow_paint`,绘制遍历按的是宿主字段而不是槽,插值它们不会有效果。集合外的属性**切换即生效**,`step` 比较的是「插值字段投影」,投影相等就直接落定。
- **状态机口径**:①第一次见到某条控件只记目标、不动画(否则建树与重挂会整片淡入);②目标中途变化时从**当前显示值**续接(`from = shown`,反向打断不跳变);③同一目标按原时钟继续,非插值字段跟着新目标走;④`transition_ms` 未写或 0 立刻落定,并且**不留账**(`style_for` 走 `forget_anim`)。缓动取 smoothstep(`t·t·(3-2t)`)。
- **帧驱动只维持一条定时器**:进程级 `@core.set_timeout(16)` 起表,每拍只给活动中的控件调 `@core.invalidate_id(id)`(命中哪扇窗标哪扇窗的脏区,所有窗都找不到才整窗广播兜底),全部收敛即停表——不按控件各排一条,也不空转。插值按**真实经过时间**算而不是数拍数,所以掉帧/宿主忙只会少几帧,不会让动画变快变慢。隐藏中的账在超时那一拍补交终点值并标脏一次,不留长尾。
- **颜色两端的取法**:`Var` token 现取当前主题再混色(`@theme.mix_hex`),所以过渡中途换主题,这一段动画的端点色停在换色前的值,下一次切换才跟上新主题——主题切换本就整窗置脏,不构成可见缺陷。任一端没写、或写法不是 hex(命名色那类)时 `mix_hex` 退成端点值,中间帧停在起点、终点仍是目标值,**不会画错颜色**。
- 工具链读数(moon 0.1.20260920,`cd gui && moon check --deny-warn` 口径):
  - **`pub(all) enum Color` 不带 `==`**:`Option[Color]` 参与的元组比较直接报 `[4018] Type Color does not implement trait Eq`。与既有记档同族(给值类型 `derive(Eq)` 会把 impl 方法隐式升成普通方法并告警),所以**状态比较一律走字符串投影**(按写法前缀 `#`/`n`/`@` 区分 Hex/Named/Var),不 derive。
  - **包内私有结构必须写 `priv struct`**:裸 `struct Anim` 报 `missing_priv` 警告,在 `--deny-warn` 下即失败。
  - **`}` 与下一段条件的 `{` 不能分行**:`} else if cond` 换行再写 `{` 报 `[3002] Unexpected line break here, missing {`——花括号必须跟在条件那一行行尾(与 `test "名字" {` 同一条纪律)。
  - **`moon fmt` 会顺手改一堆无关文件**:本仓已提交内容**不是** fmt 的规范形态(`moon fmt style core` 一次改了 42 个文件,含 `keys.mbt` 里给每条 `pub const` 前插空行这类)。要格式化只按**本批文件**跑,且跑完逐行看 diff;本批按「只改自己写的行」收口。
- **验证**:style 新增 6 条(插值端点/中点/单端缺省、状态机首帧不动画、150ms 三点读数 `#000000→#808080→#d7d7d7→#ffffff`、中途反向从 `#282828` 续接、集合外属性直接落定、没配过渡不留账)、core 新增 1 条(`invalidate_id` 只标命中窗、另一扇窗不牵连、未知 id 回退整窗),`moon test style core` 159/159、13 库包全绿合计 908/908、`cd gui && moon check --deny-warn` 零警告、`cd examples && moon check showcase --deny-warn` 零警告。观感页:showcase 新增「过渡与效果」页(0/150/600ms 三块对照 + 反向打断 + 文本与效果字段),真机复验归用户(悬停三块比较速度、中途移开看是否跳变)。

## 前端化 P1:gui/style 样式包与 yoga-mbt z_index(2026-10-13)

工具链边界(moon 0.1.20260920 / moonc v0.10.14,读数随升级要重测,同步 design.md §1.6):
- **`alias` / `abbrev` 都是保留字,没有函数或类型别名语法**;类型短名只能 `using @pkg {type X}` 引,且该声明是**包级**的——两个文件各写一遍会撞 `[4051] declared twice`,正确形态是在一个文件里 `pub using` 一次、全包与外部共用短名。
- **labelled 参数没有任何透传通道**:`f(width=width)` 类型不符(体内可选参数是 `T?`)、`f(width?)` / `f(width!)` / `f(...)` 全 `[3002]` 不解析、`pub let g = f` 绑函数值再 `g(width=1.0)` 报 `[4117] labelled 函数只能直接应用`;`moon.pkg` 的 import 不收键值形态(`unexpected token :`),包短名也配不了。结论:样式工厂调用点定死 `@style.style(...)`,状态方法 `.hover/.active/.focus` 的绘制期构造体三处各写一遍。
- `priv` 只修饰 `let`/`fn` 之外的声明形态,顶格 `priv named_x = ...` 解析失败——包内值直接写 `let`。
- `Array::contains` 要 `T: Eq`;`Option` 判含有值用 `is Some(_)`(`is_some()` 已废弃告警);`Map::new()` 已废弃,写 `Map([])` 字面量。
- `for i in 0..n`(半开)与 `0..=n` 在 for 之外都不可用,范围循环要求 `for i in (0..<n)` 形态或直接改 `while`;本包统一退回 `while`。

架构口径:
- **core 不能依赖 style**(style 依赖 core 的 Widget/yoga 落点,反向成环)。Widget 的 resolved Style 槽落为 `@style` 包内**进程级侧表** `Map[控件 id, Style]`(与 overlay_native 的进程级句柄表同款先例),`apply` 写入、绘制期 `resolved(w)` / `style_for(w)`(按 `hovered/pressed/focused` 选桶)读出;从未 apply 过的控件读回空样式。**残账清理已落地(P2-e 收尾)**:core 加进程级「控件丢弃钩子」`set_widget_discard_hook`,`clear_children` 与 `remove_child` 把摘下的整棵子树逐只报出 id,`@style` 首次 `apply` 时自己装钩子把条目清掉——动态换树(`bind_node` 重挂、`for_list` 删行、虚拟列表重挂窗口、浮层收起)不再逐代累积。**口径:摘下来就是丢弃,挪位必须走 `move_child`**(core 不认识挪与丢的区别,钩子只看这两条 API)。判据是 `@style.resolved_count()`(诊断用),回归用例钉住「remove 一棵带子树的控件 ⇒ 条目数回落」。
- **cursor 是绘制期属性,状态桶可携带**;控件的**静态** `cursor` 字段由 `apply` 直接落,状态桶里的 cursor 由 P2 的悬停路径下发读 `style_for`。
- yoga-mbt 的 `z_index` 纯绘制期:setter 不 `mark_changed`(几何无关)、引擎**不物理重排 children**(增量布局按下标缓存),给 `Node::paint_order` 下标投影;gui 侧 `Widget.z_index_paint` 由 `apply` 写入,`widget_paint_order` 插入排序稳定重排 kids(全 0 时恒等序,现有示例逐帧不变)。

验证:style 18/18、yoga-mbt 100/100(基线 95+新增 5)、core 120/120、`cd gui && moon check --deny-warn` 与全仓 `moon check` 零错零警;set_margin labelled 化 14 处调用点整批改完,库测试 858 条 856 过(2 条红为 W9/排序批既有缺口,stash 纯净态复跑同红)。

## 轻提示带着整窗底色:浮层按内容尺寸开(2026-10-14,真机反馈)

- **环境**:Ubuntu 24.04 + X11 + XFCE,`examples/showcase`(浏览器页与其余页同挂在一棵 `bind_node` 树里,网页区常驻)。
- **现象**:弹 message 轻提示时,顶部那条提示之外**整扇窗口像被盖了一层不透明背景**(用户口径:「message 不应该有遮罩背景」)。
- **根因**:`toast_layer` 用 `overlay_show_full` 开层。所在窗挂着原生子件(网页区)时浮层走**原生档**(`overlay_native_tier()` = `Window::has_child_surfaces()`),铺满档=按 owner 内容区大小开**一扇真窗口**,而每扇 `App` 的根控件默认 `on_draw` 铺 `theme_bg_page()`(`core/app.mbt`)——于是一整块页面底色的窗扣在主窗上,提示条只是它上面的圆角条。图层档同样把带子做成 `absolute` + 四边 0 的整窗包裹层(不画底色,但整窗命中都归它)。
- **修复**:轻提示改按**内容尺寸**开(`overlay_show_at`,`y=0`、`x` 按窗口宽居中,居中算式抽成纯函数 `toast_left` 便于钉桩);带子不再 absolute,列 + `align-items: center` 让它的宽度自然等于最宽那一条。配套两条:
  - core 加 `overlay_set_pos(id, x, y)`(窗口坐标搬动**图层档**浮层;原生档那扇窗开出来后位置归窗口系统管,对它返回 false、不搬)——后来又推来一条更宽的提示时,整组要重新居中。
  - 原生档收框补一条口径:`overlay_fit_pass` 的三帧预算用尽后**仍放行放大**——内容长宽了框子不跟着长就会把多出来的部分切掉;收缩仍受三帧限制(宽度回环里不来回改尺寸)。
- **没动的一条,记档**:图层是根控件的满窗 absolute 子控件,只要有任何浮层开着,浮层之外的按下仍被图层消费(`core/overlay.mbt` 的「点浮层外收起」)——轻提示在屏的那两秒里,点页面控件收不到这一击。这是浮层族的共同输入模型,本批只收视觉尺寸,派发不动;要不要让「本来就没有点外收起语义」的浮层(轻提示)放行点击,另批定。
- **验证**:`moon test core ui` 299/299(core 新增 1 条:`overlay_set_pos` 搬动后 `overlay_rect_of` 落在新窗口坐标、未知句柄给 false;ui 轻提示用例补断言:浮层矩形宽高都小于窗口、`toast_left` 的居中与钳 0 三点)、库全包 914/914、`cd gui && moon check --deny-warn` 与 `cd examples && moon check --deny-warn` 零警告、`moon build showcase --target native` 链接通过。真机观感(提示条外不再有整窗底色、逐条推来宽度变化仍居中)归 `测试文档/测试用例.md`。

## 键盘焦点全线失效:焦点栈只认手动注册,而生产代码里没人注册(2026-10-15,真机反馈 Linux + Windows 同时)

- **现象**:两处平台上输入框**点不进也打不了字**,英文与中文一样;中文的输入法预览(组合串)出现在**不确定的位置**、不跟着输入框走;按钮/菜单/段条那类没有焦点环。`examples/showcase` 全集中出现,`examples/native-app` 反而正常。
- **根因**:`App::route` 的 Down 只做 `if self.focus.focus(id)`——**焦点栈里没有那个号就不改焦点**,而填栈的 `FocusStack::register` 在全仓**只有两处调用**:`ui/message_box.mbt`(浮层临时焦点)与**示例自己**(`native-app` 手工注册 1..25、showcase 只注册事件页那一只)。也就是「谁建控件谁负责把焦点号交给宿主」这条纪律从没进过库,示例记得补、演示板没补 → showcase 里所有 `input`/`textarea` 拿得到自动焦点号(`auto_focus_id`)、却在栈里查无此号:点击走指针链路(光标照样画、描边照样亮)所以看着「点进去了」,键只投给焦点栈里那只控件,于是打字全无。中文更完整地对上:没有焦点控件时 `im_cursor` 供不上插入符矩形,候选窗落在系统默认位置 = 「不确定的位置」。
- **修复(口径改成「声明即注册」)**:焦点栈的内容由**控件树**决定,调用方只声明 `focus_id`。
  - `Widget::focus_ids()`:按树序(深度优先、子项按挂载次序)收集「在树里且未被隐藏」的焦点号,同号去重、`focus_id<=0` 不算。藏起来的整块(未选中的页、收起的浮层)自然退出 Tab 次序。
  - `FocusStack::sync(ids)`:整体对齐注册表。**当前焦点按号保留**(号还在列表里就还是它,被摘掉才置空);列表非空而本来没焦点时**不抢焦点**——`drop_current` 把键让给网页子件之后,下一次对齐不能又抢回自绘控件。
  - `App::route` 的 Down 与 `App::move_focus`(Tab)之前各对齐一次。这两处就是仅有的两个消费点:绘制只看 `focus.current()`(`set_focused_by_focus`),不需要栈的次序,所以**不必每帧走树**。
  - `register`/`unregister` 保留,用途收窄为**不在控件树里的临时焦点**(消息框浮层那种);代价:这类号在下一次对齐时会被摘掉,要长期占位就每次对齐后重新 `focus` 一次。
- **为什么不选「组件自己挂载时注册」**:控件可能挂到别的窗(每窗一栈)、`bind_node`/`for_list` 重挂与虚拟列表换行都要成对退订,而 `focus_id` 是公开可变字段(`w.focus_id = 910`)拦不住——挂在树上做记账必然漏。树序读数一次遍历解决全部,且与 `focusable_at`(命中链取第一个非零号)同一判据。
- **按钮/段条/菜单照旧是刻意 opt-in**(要给 `focus_id` 才进 Tab 次序):本栈还没有「焦点 + Enter/空格激活」这套键盘激活语义(焦点环早就有),把它顺手做成默认聚焦会出现「Tab 得上去、回车什么都不干」的半截功能,另批定。
- **验证**:`moon test core` 143/143,新增 4 条(`gui/core/focus_route_wbtest.mbt`):`focus_ids` 的树序/隐藏跳过/同号去重、`sync` 保住当前焦点且「本来没焦点不许抢」、端到端**全程不调 register** 的「点进焦点号 7 的控件→键投给它→Tab 到 9→把 9 藏起来后 Tab 只在 7 上绕」、点空白不改焦点;库全包 906/912(6 条红为本机 Windows 环境基线:sys 的 `/tmp`·`.desktop` 路径断言与 render 的 PNG 读回,与本批无关)、`cd gui && moon check --deny-warn` 与 examples 模块零警告。同步把 showcase 事件页的「挂载时注册」示范删掉(现在只声明 `focus_id`)。真机复验归 `测试文档/测试用例.md`。

## 纯光栅器漏清路径:上一只控件的圆弧,在这一只控件的原点上重画一遍(2026-10-15,真机反馈 Windows)

- **现象**:`examples/showcase` 表单组件「开关」段,checkbox 选中与未选中**看不出差别**——两只都成了一块实心色板;radio 选中项画成实心圆盘(环与心之间那圈空白没了),连**未选中**的那只也带上一颗圆心。Linux(cairo 后端)上同一份代码正常。
- **根因**:`Raster::fill` / `Raster::stroke` 落笔后**不清空当前路径**,而 `cairo_fill` / `cairo_stroke` 用完即清(`Painter` 头注释第 3 条口径要求两后端方法面逐条同形,这条漏了)。整页共用一个 Painter 会话,每只控件在 `paint_at` 里 `save()+translate()` 到**自己的原点**作画,于是前一只控件留下的子路径会在后一只控件的坐标系里被重新描一遍:radio 的「环 + 心」两笔之后,checkbox 的勾那一次 `stroke()` 把这两段圆弧按 checkbox 的原点又描了一次 2px 强调色——看着就是框里凭空多了块实心板;未选中的 radio 也被下一笔带上别人的圆心。**单测自洽看不出来**:一只控件单独画到干净位图时路径里只有它自己那一份,而这条污染恰好要「前一只画过圆弧」才现形(探针里第三只 radio 的红心来自第二只)。
- **修复**:
  - `Raster::fill`/`Raster::stroke` 落笔即清路径,与 cairo 同口径(零线宽那支不描像素但同样清)。
  - 连带修**唯一一处依赖旧行为**的调用点:`chart/geo.mbt` 的区域环先 `fill()` 再直接 `stroke()`——这一笔在 Linux 上本来就描不出边(路径早被 fill 清掉,地图区域一直没有描边),抽成 `geo_ring_path` 铺两次,填充与描边各用一份新路径。
  - 组件侧补显式 `begin_path`(checkbox 的勾、radio 的环与心):这是 house style(`cairo_wbtest.mbt` 的 `paint_seq_aa` 每笔都 begin),也是「每笔自带路径」的写法纪律。
  - 勾太细是另一码事,同批改:线宽 1.0 → **2.0**,几何收到 `(3.2,7.3)→(5.8,10.0)→(10.9,3.9)`(14×14 的框里 1px 折线只剩十几个像素,不成其为勾)。
- **验证**:`render` 新增 1 条两后端同口径回归(第一笔三角填红后,第二笔绿填充/蓝描边都不许把红三角连着重画)、`ui` 新增 2 条像素回归(勾的实心覆盖 >20 像素、未选框内 0 个强调色像素、未选 radio 圆内 0 个强调色像素——三条都在旧实现下红)。库全包 909/915(6 条红为本机 Windows 环境基线:sys 的 `/tmp`·`.desktop` 路径断言与 render 的 PNG 读回,与本批无关)、`cd gui && moon check --deny-warn` 与 examples 模块零警告。真机观感(checkbox 未选=灰框、选中=强调色框+粗勾;radio 选中=环+心、未选=干净灰环)归 `测试文档/测试用例.md`。

## 控件形状:开关画成两块直角矩形,radio 的环与心糊成一团(2026-10-15,真机反馈 Windows)

- **现象**:清掉路径污染之后,同一张「开关」段截图仍能看出形状不对——开关是一根**直角长条**配一颗**方块滑块**(没有胶囊弧、没有圆珠);选中项的 radio 环与心之间没有缝,糊成一块实心板;checkbox 的勾右上臂顶到框角。Linux(cairo)上同一份代码同样是这样,所以这批不是后端分裂,是组件自己的画法。
- **根因**:
  - `ui/form.mbt` 的 `switch` 早先写的是两次 `fill_rect`(40×20 矩形 + 16×16 方块),注释里挂着「胶囊按圆角矩形近似,直角先记档」——记档一直没落地,画出来就是长条配方块。
  - radio 环线宽 1.0(半径 6 → 内沿 5.5)配圆心半径 3.5:两边只剩 1px 缝,AA 一糊就看不出环。
  - checkbox 的勾上一批改到 2px 后,右上臂末端 `x=10.9` 离框右缘(14)只剩 3px,加粗的端帽把它顶到角上。
  - 试「复选框圆角边框」时探出后端一条:`Raster::stroke_round_rect` 在**线宽 1.0** 下四条直段**整段不落墨**——`rect_device` 把矩形取整到整数边,覆盖又按**像素中心**量(`hw=0.5` 时中心到整数边的重叠恒为 0),只有角部 SDF 那圈还有墨。因此本轮复选框边框退回 `stroke_rect`(内描边,1px 正好落满一格),1px **圆角**边框要等后端把边按精确设备坐标算,另批处理。
- **修复**:
  - `switch` → `fill_round_rect(0, 0, r.w, r.h, r.h / 2)` 真胶囊 + `arc(cx, r.h / 2, 8)` 圆珠,圆心在两端各留半高,珠沿与胶囊壁齐平。
  - radio 环线宽 1.0 → **1.2**、圆心半径 3.5 → **2.8**。中心行实测读数 `##..######..##`(环 2 格、空白 2 格、心 6 格、空白 2 格、环 2 格)。
  - checkbox 的勾再收一格:`(3.2,7.3)→(5.8,10.0)→(10.9,3.9)` → `(3.4,7.4)→(5.9,9.9)→(10.5,4.3)`,两端离框边各留 2px 以上。
- **验证**:`ui` 新增 2 条形状回归(单选中心行按上表逐格断言「环—空白—心—空白—环」;开关四角不落墨 + 滑珠中缝 16 格满宽、上下边缘行只剩 6 格即珠是圆的),`moon test ui` 164/164、库全包 912/917(5 条红为本机 Windows 环境基线:sys 的 `.desktop`/目录枚举断言,与本批无关)、`cd gui && moon check --deny-warn` 零警告。真机观感归 `测试文档/测试用例.md`。

## 圆角矩形 1px 描边四条直段整段不落墨:光栅器把边取整、覆盖却按像素中心量(2026-10-15,开发机 Windows)

- **现象**:给复选框换 1px **圆角**边框(`stroke_round_rect(0.5, 0.5, 13, 13, 3)`、线宽 1.0)后,Windows 上只剩四段角弧,四条直边一格墨都没有;同一行代码在 Linux(cairo 后端)上描得出完整一圈。`stroke_round_rect` 是公开 API(库内暂无调用点),等于「居中式的 1px 圆角边框」在这条解析快路径上从来没画出来过。
- **根因**:`Raster::stroke_round_rect` 的边取自 `rect_device` 的**取整**结果,覆盖却按**像素中心**算:`hw = line_width / 2 = 0.5`,边落在整数上时最近的像素中心离边正好 0.5 → `d = hw - 0.5 = 0` → 覆盖 0,整段直边消失。角部走的是「到弧心距离」的 SDF,弧心不必是整数,所以只有角活下来。与 cairo 不同形(方法面同形口径见 `Painter` 头注释)。
- **修复**:边一律取**精确设备坐标**(`m.apply` 两个对角,负缩放取 min/max),取整只用于圈定循环范围;覆盖改成把像素当一格的面积重叠 `cov = hw + 0.5 − |中心到环的距离|`(SDF 抗锯齿的常规写法,+0.5 是「一格」的面积修正),直段与角部同式。
- **连带记档(先不改)**:居中式描边落在**半像素原点**上必然摊成相邻两格各半墨。复选框的标记在行里垂直居中,14 高的标记放进 17 高的行 → `rect.y = 1.5`,换圆角居中描边后框线只剩约 50% 浓度,比原来的内描边淡一档——所以框线仍走 `stroke_rect`(整数吸附,任意原点都锐利)。要给标记类控件上圆角边框,得先把它们对齐到整数设备格(或给 `Painter` 加「按设备格取整的居中描边」),另批。
- **另一个坑(与本轮改动无关,顺手记)**:批内跑了 `moon fmt` 一次,工具链的重排口径与本仓既有风格不一致,一条命令改到 287 个文件(把 `if … { x }` 拆成多行、把短参数列表折行等),只能整树回退重贴本批四处改动。**批内不要跑 `moon fmt`**;要统一格式另开一批,并先确认工具链 fmt 口径与仓库风格一致。
- **验证**:`render` 新增 1 条两后端同口径回归(边压在格中心 0.5 → 四边中点满墨 255、角弧外与框内 0;边压在整数边界 → 直段仍有半墨 >60)、`ui` 新增 1 条框线锐利回归(四边四角都 >200)。`moon test render ui chart` 403/403、库全包 914/919(5 条红为本机 Windows 环境基线:sys 的 `.desktop` 与目录枚举断言,与本批无关)、`cd gui && moon check --deny-warn` 零警告。

## 弧形与圆角的「像素画感」三条根因:miter 交点符号反了、闭合描边缝成一圈、圆角填充取整到整数格(2026-10-15,真机反馈 Windows)

- **环境**:开发机 Windows 10 22H2 + 纯 MoonBit 光栅器后端(`PureBackend`,Linux 走 cairo 后端同一份组件代码)。
- **现象**:radio 外圈沿线有断口(逐格读数在顶点处出现 `...-####.###-...` 这种空洞)、勾选的对勾像一排阶梯、**所有**圆角/弧形/切边处都有马赛克感。用户判断为「画布分辨率低了」。
- **根因**(三条都在光栅器,与画布分辨率无关):
  - **画布分辨率不是原因**:进程只声明 per-monitor-v2 DPI 感知(`gui/win/stub.c`),但全仓**从不读取 DPI 数值**(没有 `wm_dpi`/`wm_scale` 出口,Linux 也不读 `Xft.dpi`/`GDK_SCALE`),帧画布按物理像素 1:1 开(`gui/core/app.mbt` 的 `paint_frame`),`StretchDIBits` 源/目标尺寸相同。本机 `AppliedDPI = 96`(100%),既没有 DWM 拉伸也没有缩放丢样。**待办**:高缩放屏(125%/150%)上这套口径会让整窗 UI 偏小,需要另批按缩放因子布局。
  - **`stroke_polys` 的 miter 交点符号反了**:两条偏移线求交解的是 `s·prev − t·cur = n − pn`,叉乘 `cur` 应得 `s = cross(r, cur) / det`,代码写成 `cross(cur, r) / det`(**反号**)→ 外角 mitter 点跑到内角、内角点跑到外角,轮廓在每个接头自交,折线/弧/切边的转角处各咬掉一块。`git log` 里那条「勾的右上臂顶到框角」也是它的表现。
  - **闭合折线描边缝成单条轮廓**:侧 A 正向 + 侧 B 反向缝成一条闭合轮廓,缝合处两圈环绕相消,环沿线留下空洞;整圆 `arc(0..2π)` 虽未 `close_path`,首末点重合却被当开放折线处理,又加了两个 butt 端帽。
  - **`Raster::fill_round_rect` 把矩形取整到整数格**:直边一格 AA 都没有(分数原点的面板四条边整段错位半格),只有角部按到弧心距离算覆盖——圆角看着像像素画的主因;同一条快路径还让同心的标记(环/心/滑珠)各自被取整到不同格,视觉上偏心。
  - 展平阈值 `RASTER_FLAT_TOLERANCE` 取 0.25(cairo 默认 0.1)在小半径上只切出十二段,段间接头把上面两条放大成可见缺口。
- **修复**:
  - miter 解改为 `s = (rx·uy − ry·ux) / det`(`gui/render/raster_fill.mbt`)。
  - 闭合(含首末点重合)子路径两侧**各自成环**:外圈正向 + 内圈反向,非零环绕自动挖孔;接头在回绕顶点同样求交,不加端帽。
  - `Raster::fill_round_rect` 重写为**精确设备坐标** + 逐像素带符号距离覆盖(256 级),每行解析出满覆盖列区间仍整条直写(纯色不透明源的快路径不变),只在区间两端几个像素走距离式 AA;半径为 0 时仍走整格矩形(锐边)。
  - `RASTER_FLAT_TOLERANCE` 0.25 → **0.1**(与 cairo 同值)。
  - 组件侧:`radio` 的环改 `stroke_round_rect(1,1,12,12,6)`、心改 `fill_round_rect(4,4,6,6,3)`、`switch` 滑珠改 `fill_round_rect` 圆——14px 级的小圆不该展平成折线;环线宽 1.2 → 1.3(12 格里实体只剩 1 格时读起来发虚);对勾 2.0 → 2.4。
- **验证方式**:`render` 新增 3 条两后端同口径回归——整圆描边沿线逐格扫(`r=6`、线宽 1.3,环带内不许有 1 格断墨)、直角接头 miter 顶到外角(`(17,17)` 必须满墨 255、外角格外 0)、`fill_round_rect` 分数边有边缘 AA(左直边那格落在 60~200 的半墨);三条**在旧实现下都是红**(逐条 `git stash` 回退验证:miter 那条旧值 128、环线那条旧值 1 格断口、分数边那条旧值 0)。`ui` 的两条形状回归按新读数改判据(单选中心行仍 `##..######..##` + 心 6 格实心;开关滑珠第 4/15 行实体 10 格)。`moon test render ui chart` 406/406、库全包 917/922(5 条红为本机 Windows 环境基线:sys 的 `.desktop`/目录枚举断言,与本批无关)、`cd gui && moon check --deny-warn` 零警告。真机观感归 `测试文档/测试用例.md`。
- **仍待处理(另批)**:通用路径填充的 AA 仍是 4×4 超采样(16 级量化),斜边有轻微阶梯;`stroke_round_rect` 的居中式 1px 在半像素原点仍摊成两格;库里所有圆角背景上的边框一律走 `stroke_rect` 内描边(方角压圆角),要统一成圆角边框得先把控件对齐整数设备格。

## 输入框敲空格没反馈:两个排版引擎都把行尾空白从测量宽里剪掉(2026-10-15,真机反馈 Windows)

- **现象**:输入框里打空格,光标不动、什么反馈都没有;打下下一个非空字符时,之前那个空格连同新字一起「冒出来」。
- **根因**:空格本身无墨,「空格显示出来」的可见信号就是**光标右移**——输入框光标位移全部来自 `@text.measure_font` 的前缀宽(`gui/ui/entry.mbt` 的 `prefix_width`)。而两个排版引擎的「文本宽度」按对齐口径都**不含行尾空白**:DWrite 的 `DWRITE_TEXT_METRICS.width` 定义上排除行尾空白(含空白的字段是 `widthIncludingTrailingWhitespace`,C 侧 `pt_measure_font` 取的是前者);Pango 自 1.44 起也把行尾空白从布局宽里剪掉(`pango_layout_get_pixel_size` 同样剪)。于是量 `"abc "` = `"abc"`,敲空格前后宽度不变、光标不动。绘制路径(`ptw_render`/批队列的墨迹矩形)用的是 `widthIncludingTrailingWhitespace`,所以空格在**行中**时一直正常——只有**行尾**那一个受影响,单测里量整串词也测不出来。
- **修复**:
  - DWrite(`gui/text/dwrite_text.cpp`):`pt_measure_font` 与 `rt_measure` 的宽度改取 `tm.widthIncludingTrailingWhitespace`;对齐用的 `ptw_box_offsets` 仍取 `tm.width`(居中/右对齐不该把行尾空白算进去),两条口径各归各。
  - Pango(`gui/text/stub.c`):新增 `pt_width_with_trailing_ws`——文本以空白结尾(`g_unichar_isspace` 判末字符)且布局单行时,用 `pango_layout_index_to_pos(len)` 取**光标终点**(Pango 的光标位置覆盖行尾空白)补回宽度,与像素宽取大者;多行不补(末行终点不是总宽)。
- **验证方式**:`text` 新增 1 条两后端同口径回归(`measure("ab ")` 必须宽于 `measure("ab")`、纯空格宽 > 0)。`moon test text` 30/30、库全包 918/923(5 条红为本机 Windows 环境基线:sys 的读数环与目录枚举断言,与本批无关)、`cd gui && moon check --deny-warn` 零警告。真机复验归 `测试文档/测试用例.md`。

## 可关闭横幅点 ✕ 没反应:组件没实现「默认收起」,默认回调是空函数(2026-10-15,真机反馈 Windows)

- **现象**:反馈组件页「可关闭」段的横幅点右上角 ✕,横幅纹丝不动。
- **根因**:`alert` 的关闭**热区与回调链路本身是好的**(白盒测试里点热区 `on_close` 确实被调),坏在语义分层——`on_close` 的默认值是空函数,showcase 恰好没传回调,而组件本体又没实现「收起」这个本体行为:点 ✕ 等于调用一个空函数,什么都不发生。组件页文案写的「这里留默认(只收起)」承诺的正是这个没实现的行为。
- **修复**(`gui/ui/display.mbt`):✕ 的本体行为进组件——点热区一律 `set_visible(false)`(与 yoga `Display::None` 同步,布局自然回流)+ `@core.invalidate()`(全窗置脏:收起会让下方内容整列回流,局部脏区盖不住);`on_close` 降级为收起之外的**可选通知**,传不传都收起。`native-app` 里传了计数回调的用法顺带获得一致行为(横幅收起 + 计数加一)。
- **验证方式**:`ui` 既有提示条回归改写——打开态先画图断言 ✕ 标记存在,点热区后断言回调被调 + `visible == false` + 重排重绘后整幅无墨;非热区点击不收起。库全包 918/923(同上基线)、`cd examples && moon check --deny-warn` 零警告。真机复验归 `测试文档/测试用例.md`。

## 表单族控件 Tab 不上、没有键盘交互:焦点号 opt-in 口径把整族控件关在 Tab 链外(2026-10-15,用户反馈)

- **现象**:步进器、滑杆、评分、选择(普通/颜色/日期/时间)、开关、多选、单选都无法 Tab 选中,按空格/方向/回车没任何反应;按钮、菜单、段分组同样。
- **根因**:焦点基础设施(焦点栈、Tab 环绕、`dispatch_key` 沿焦点控件祖先链投递、`focus_ids` 树序对齐)都是现成的,2026-10-14 批只给输入框自动领号,`select`/`button` 等当时的口径是「可聚焦是刻意 opt-in」(见《键盘焦点全线失效》批末尾那条注)——因为当时「焦点 + 激活键」语义还没做,默认聚焦会出「Tab 得上去、回车什么都不干」的半截功能。本批把激活语义补齐,口径翻转:表单族/导航族/菜单**默认自动领号进 Tab 链**(`auto_focus_id`,显式号仍优先),不再需要调用点逐个给号。
- **修复**(键语义逐控件):
  - `button`/`checkbox`/`switch`/单选项/分段项:空格/回车激活(切换或选中);
  - `radio_group`/`segmented`:方向键按**焦点项下标**换选(不是相对当前值),到头环绕;回车/空格是激活焦点项;
  - `slider`:←/↓ 减、→/↑ 加(无 step 按百分之一量程),Home/End 到两端;
  - `stepper`:←/↓ 减、→/↑ 加,触界侧吃掉键不改值;
  - `rate`:方向键加减一星、Home/End 到两端,写值与点击同回调;
  - `select`(非可编辑)/`color_picker`/`dropdown`:空格/回车/↓ 开层,↑/↓(色板是 ←→ 移一格、↑↓ 移一行)移高亮,回车/空格取高亮,Esc 收层;`dropdown` 的分隔线 `-` 不占高亮位;
  - `date_picker`/`date_range_picker`/时间字段:空格/回车/↓ 开层、回车/Esc 收层(`attach_field_toggle_key`;日历内部的方向键导航未做,弹层里仍只点选);
  - 焦点环:输入框/选择器字段描边聚焦时转主题色(覆盖在常态描边上),标记控件(复选框线、单选环、开关胶囊、步进器外框、评分/分段/滑块)画主题色描边圈,按钮沿用原焦点环。绘制按控件矩形裁剪,环一律画在控件矩形**内**。
- **验证方式**:`ui` 新增 8 条无头回归(标记控件空格/回车/禁用不吃键 + `focus_ids` 收录、单选环绕换选、滑块/步进器/评分键调值、按钮空格/回车、select 键盘全流程、取色器网格导航、dropdown 分隔线跳过、分段换选、日期字段开合)。`moon test ui` 176/176、库全包 934/935(1 条红为本机 Windows 环境基线)、`cd gui && moon check --deny-warn` 与 examples 模块零警告。真机复验归 `测试文档/测试用例.md`。

## 圆/弧/圆角的像素画感（第二层根因）：4×4 采样点计数只有 17 档覆盖，浅角度边缘实测只剩 2 档（2026-10-15,真机反馈）

- **环境**：Windows 10 19044 真机；后端是纯 MoonBit 光栅器（`gui/render/raster*.mbt`，Windows/mac 走这条，Linux 走 cairo）。此前一轮已修掉 miter 交点符号、闭合描边接缝、圆角填充取整三条（见「弧形与圆角的「像素画感」三条根因」），用户复验后仍说「圆形、弧形、圆角还是有像素感」。
- **现象**：曲线沿线的明暗是**跳变**的，不是渐变——小圆（开关滑珠、单选圆心 r≈6）边缘尤其明显。
- **读数定位**（先量再改，临时探针跑完即删）：统计画布里「半墨像素」的**互不相同 alpha 档数**——旧实现下 r=25 填充圆整圈只有 **8 档**、lw=2 圆环 **9 档**、r=6 小圆 **2 档**（值只有 16 与 96）、分数坐标圆 12 档。
- **根因**：`fill_polys` 的覆盖是**采样点计数**：纵向 4 个子行 × 横向 4 个样本，每样本定值 16 ⇒ 覆盖只能是 16 的倍数（17 档）。横向还能靠 4 个样本凑出 0/16/32/48/64，**纵向一个子行要么整条计入要么不计** ⇒ 近水平边的步长是 64（一格四档），曲线顶部/底部与浅角度斜线就糊成台阶。圆角矩形的直边没这问题（`fill_round_rect`/`stroke_round_rect` 走解析 SDF，覆盖连续）——这也解释了「圆角还是有点硬但圆更糟」。
- **修复**（`gui/render/raster_fill.mbt`）：① 纵向子行 4 → `RASTER_AA_SUB = 8`（每子行权重 32）；② 横向从「数样本」改成**精确相交宽度**——边界像素按 `min(xb, px+1) − max(xa, px)` × 子行权重计入，覆盖横向连续。满覆盖内段仍直取 256，`s0 = ceil(xa)`/`s1 = floor(xb) − 1` 的判据也从「样本中心」改成「整列真被包住」，顺带修掉旧口径把差一点点的像素当满覆盖的高估。代价：子行翻倍（x 方向反而省掉 4 次内层判定），render 全包 53 条 1.5s、库全包 20.8s，未见可感回归。
- **改后读数**：r=25 填充圆 **22 档**（右缘剖面 28/94/146/185/220/235/248 平滑过渡）、lw=2 圆环 **37 档**、r=6 小圆 **5 档**、分数心圆 **45 档**、32° 斜线 **7 档**。
- **顺手记一条别踩**：**正好 45° 的直线段只有约 2 档是几何事实**（`x+y=c` 的半平面切每个像素的相对位置相同，lw=1 与 lw=3 实测都是 2 档），不是 AA 缺陷——第一次写判据时按「45° 该有很多档」断言，直接把这条改对的代码判红了。灰级判据要用**浅角度**线段与圆。
- **验证方式**：`gui/render/painter_wbtest.mbt` 新增 `aa_levels` 助手与 2 条判据（「圆与圆环的边缘灰级」：r=25 圆 ≥16 档且半墨格 ≥60、圆环 ≥20 档、r=6 小圆 ≥4 档；「浅角度斜线边缘的灰级连续」：32° lw=1.5 ≥5 档）——旧实现下这几条全红；两后端同口径（cairo 是解析覆盖，档数远高于阈值）。`moon test render` **53/53**、库全包 **947/948**（唯一红仍是 `si_machine` 的 BIOS 注册表读数，本机环境基线）、`cd gui && moon check --deny-warn` 零警告。真机观感归 `测试文档/测试用例.md`。
## radio 圆心「实心板」判据在 Linux 必红:cairo 面积采样与纯光栅器在小尺寸圆边缘格的读数差(2026-10-15,Linux CI + 本机)

- **环境**:Ubuntu 24.04(X11/XFCE,cairo 可用,`Painter::new` 优先 cairo 会话)对照 Windows 开发机(cairo 建不出,落纯光栅器);同一条 `ui/form_wbtest` 的像素判据在两边走**不同后端**。
- **现象**:0213284 批次后 CI 的 Linux job 连续红(`ui/form_wbtest.mbt`「单选标记的环与心之间留得出一条空白」报「圆心不是实心的」),Windows job 全绿;本机 Linux 复现 941/942。
- **根因**:判据要求圆心直径六格(格 4..10)不透明度全过 200,这按**纯光栅器读数**写死——0213284 的 fill 覆盖口径是「像素是一格」(带符号距离 + 0.5 格补偿),直径两端格(格中心距圆心 2.5 < 半径 3)算满 255。cairo 是标准抗锯齿**面积采样**,同几何下两端格只有 ~196/197(0.76 覆盖),差 3~4 过不了 200 阈值。形状本身两后端都正确(阈值 60 的形态判据「环-空白-心-空白-环」全绿)——这是**方法面同形、小尺寸边缘格读数不同**的口径差,不是实现错。教训与 6dff6c1 记的「判据按本机度量写死」同族:像素级判据要么按双后端读数取交集,要么避开边缘格。
- **修复**:判据改两后端同口径——「实心」断言从直径六格收紧到**中段四格(5..9)全过 200**(cairo 下 255 满墨、raster 下亦满),直径两端「有墨」由阈值 60 的既有形态断言覆盖;注释写明两种口径与不进判据的理由。
- **验证方式**:本机 Linux `moon test ui` **180/180**、库全量 **968/968** 零红、`cd gui && moon check --deny-warn` 零警告;判据收紧端(raster)仍被 Windows CI 覆盖(5..9 ⊆ 4..10 全满读数)。

## 字号动画不是动画：插值集合当年以「等于每帧重排」为由把字号挡在外面，而本栈每帧本来就重排（2026-10-15,真机反馈）

- **环境**：Windows 10 19044 真机，showcase「过渡与效果」页原「集合外属性」段（`@ui.text(class=[style(font_size=13.0, transition_ms=300.0).hover(font_size=17.0)])`）。
- **现象**：悬停时字号 13→17 **一步**变大，没有渐变过程（底色那一条是过渡的）。
- **根因**（两层，且都写在设计口径里）：
  1. `gui/style/transition.mbt` 的 `lerp_style` 只覆盖三条颜色 + 边框宽 + 圆角，集合外字段一律「取目标值」；
  2. 更硬的一层是 `animatable_key` 的投影里没有 `font_size` ⇒ 「只改字号」的状态切换被判成 `at_shown == true` → `settle` → **连表都不起**。§1.1 当时给的理由是「进布局的属性参与插值等于每帧重排」。
- **为什么这条理由在本栈不成立**：绘制帧本来就是 `App::step` → `root.relayout(...)` → `paint`（每帧全树重排，见「一帧仍是全视口重绘」那条已知差异），插值字号**不额外排一次**。真正缺的是另一半：**测量期读的是基块**——`gui/ui/base.mbt` 的 measure 与 baseline 回调按 `@style.resolved_by_id(id)` 取字号，绘制期读的是插值值 `style_for(w)`。两边不同值时，字按大字号画、盒子还按小字号量，观感仍是「跳变 + 被裁」。
- **口径先对表 CSS**（用户给的判据：「CSS 有实现的就做，没有的不做」）：CSS Transitions 里 `font-size` 与 `line-height` 都是可动画的 `<length>`，浏览器的做法正是每帧重新布局——所以这两条都进集合；`font-family`/`display` 是离散的、`opacity`/`box_shadow` 在本栈生效点不在样式槽读取路径上，仍不进集合。
- **修复**：`lerp_style` 加 `font_size` 与 `line_height`；`animatable_key` 投影带上这两条（否则「只改字号」被判成「状态没变」→ `settle` → **连表都不起**，这是看不见渐变的主因）；新增 `anim_shown_font_size(id)` / `anim_shown_line_height(id)` 与 `resolved_for_measure(id)`（基块 + 插值中的这两条），`ui/base.mbt` 两处测量回调改用它。`resolved_for_measure` 用 `merge(st, empty_style())` **造副本**再覆盖——`resolved_table` 里存的是同一个对象，直接改字段会把基块写坏。账落定后 `shown` 就是目标值（含状态桶），所以悬停结束后盒子仍与绘制一致，不会「动画完了盒子又缩回去」。
- **顺带补的一条接线**（不做就会「渐变到一半被裁」）：字号/行高在变 ⇒ 控件矩形会长大 ⇒ 局部脏区按**上一帧**的矩形并进去，新露出的那圈画不到。`transition.mbt` 的 `grows_layout(a)` 判这两条是否变化，`mark_dirty` 据此在「整窗置脏 / 局部置脏」之间分派——只改颜色/边框宽/圆角的过渡仍走局部（P5 的优化不为它们让路）。`anim_needs_full_paint(id)` 把这条决策暴露给测试。
- **仍在集合外的**：`opacity` / `box_shadow`（生效点是 `apply` 落 `Widget` 字段，绘制遍历不逐帧读槽）与尺寸类布局属性。`box_shadow` 要不要做动画取决于阴影本身能不能做成「真投影」（CSS 里它是可动画的 shadow list），见下一节。
- **口径同步**：showcase 段名「集合外属性 / 不参与插值的属性」改为「插值范围 / 哪些属性会渐变」并改写正文；`experience/design.md` §1.1「过渡」行重写（字号与行高进集合、测量期同读一份值、这两条改走整窗置脏、理由从「每帧重排」改成「每帧本来就重排」）；P5 那节的「待真机复验」补了口径变更指针，避免后人照旧文案判 bug。
- **验证方式**：`gui/style/transition_wbtest.mbt` 改 1 条 + 新增 2 条——`lerp_style` 中帧 12→16 给 14、行高 16→20 给 18（旧口径两条都取目标），集合外的 `opacity` 仍直取目标；`step` 只改字号也起表，25/50/100ms 读数 12.625 / 14.0 / 16.0（smoothstep），中途换回原值时反向段从当前 14.0 续接不跳端点，且 `anim_needs_full_paint` 为真（只改颜色的那条账为假）；只改行高同样起表并给 18.0；`resolved_for_measure` 与同帧 `style_for` 的字号与行高**同值**、两值分别落在 [13,17] 与 [20,28] 内、且 `resolved_by_id` 的基块没被写坏。旧实现下这几条全红。`moon test style ui core` **354/354**，真机观感归 `测试文档/测试用例.md`。

## 阴影突兀：它是「一圈等浓度描边」而不是投影——改成分层羽化做出来后，真机复验仍不过关，整条撤除（2026-10-15,真机反馈）

- **环境**：Windows 10 19044 真机，showcase「过渡与效果」页的阴影卡片。
- **现象**：用户说「阴影效果很突兀，现在是**一个区域内有限的一块**，不是真的悬浮在指定元素下方」，并给了退路——做不出悬浮就砍掉。
- **根因**（三层）：
  1. `Painter::box_shadow` 画的是**一条描边**（线宽 = spread、中心线外扩 spread/2），整圈只有一档浓度、内外两端都是硬边 ⇒ 看着像给盒子套了圈灰框，不像投影；
  2. 调用点 `ui/basic.mbt` 传的是 `dx=dy=0`，且 `Style` 只有一个 `box_shadow : Double?`，**没有偏移/模糊/颜色的落点** ⇒ 永远四周对称，没有「往下投」的方向感；
  3. 为什么早先不敢用多层：`experience/adaptation/common.md` 记过「硬阴影在四个角叠成深色圆斑：两后端都没有反向弧，『内外环挖洞』挖不出洞」——那版是**外环填充 + 反向内环挖孔**，孔挖不干净才在角上叠墨。而分层填充**根本不需要挖孔**：本体随后画在最上面，内层的过度累积正被本体遮住，所以这条路重新可行（也符合 CSS：背景透明的本体本来就会透出阴影）。
- **修复**：`Painter::drop_shadow(x, y, w, h, radius, blur, dx, dy, color)`——圆角矩形与半径 e 的圆盘做 Minkowski 和，结果仍是圆角矩形（宽高各 +2e、半径 +e），于是从外到内画 N 层同一形状（每层≈1px 过渡带，2..8 层封顶），每层 `global_alpha = 总浓度 / N`（source-over 累积近似线性）：贴本体边最浓、到 blur 处褪零，且**同一距离上角与边浓度相同**。`Painter::box_shadow` 直接删掉，不留兼容壳。
- **API 对表 CSS**：`Style` 新增 `shadow_x` / `shadow_y` / `shadow_color`，`box_shadow` 的含义改为模糊半径——四位合起来就是 CSS `box-shadow: blur x y color`（颜色自带 alpha 即浓度，未写用内置基调 `#00000040`）。取值统一走 `@style.shadow_of(s)`。`apply` 把**外扩量 = blur + |dx| + |dy|** 落进 `Widget.shadow_paint`，且按**合并后的基块**算（原来只看本次传入的 `s`，后一次 apply 只补偏移时外扩量不会跟着变，下缘会被裁剪窗口切掉）。
- **顺带修的两处边角**（真投影会把它们放大）：① `core/widget.mbt` 的视口剔除判交只用裸矩形 ⇒ 本体刚滑出视口时软边整圈消失 ⇒ 判交同样放大 `shadow_paint`；② 裁剪窗口原先按「spread」放大，加了偏移就不够 ⇒ 与 ①同源，现在都是 blur+|dx|+|dy|。
- **仍待评估**：分层是**近似**（N 档台阶，blur≥8 时肉眼基本看不出台阶），真高斯 blur 等渲染层有 blur 能力再换；`box_shadow` 还在插值集合外（生效点是 `apply` 落 `Widget` 字段，绘制遍历不逐帧读槽），要做「hover 阴影渐变」得先把这三位挪进槽读取路径，随后续批。
- **实测读数**（200×160、本体 40,40,120×80、圆角 8、blur 8、dy 6、`#00000040`）：左缘由内向外 `57 57 57 51 44 37 30 23 16 8 0`（单调递减、十档）；下方 y=124/128/132/136 = `57/44/16/0`，上方 y=48/40/36 = `57/23/0` ⇒ 下面比上面多投出偏移那 6px；同距离处角 `34` vs 边 `37`（旧版这里要么缺一块要么叠成深斑）；本体心 `57`（内层累积，随后被本体盖住）。
- **验证方式**：`render/painter_wbtest.mbt` 换掉旧的 `box_shadow` 用例、新增 2 条（方向 + 梯度 + 角边同浓度；四种「没有投影」的输入一律不落墨）；`ui/basic_wbtest.mbt` 新增第 6 项判据（先放一只 24 高垫块把卡片推到 y=24，再数盒外**上带/下带**的墨格：给 `shadow_y` 后下方变多、上方变少）。`moon test render` **54/54**、`moon test ui` **180/180**、库全包 **976/977**（唯一红仍是 `si_machine` 的 BIOS 注册表读数）、`cd gui && moon check --deny-warn` 与 examples 零警告、`moon build showcase --target native` 链接通过、本机冒烟 4 秒存活后按 Windows pid 收尾。真机观感归 `测试文档/测试用例.md`。
## 浏览器 DOM 四档抓取两平台全 ok=false:JS 求值回包被事件文本槽 768 截成半截 JSON(2026-10-15,Linux + Windows 真机同时)

- **环境**:examples/browser 两平台真机,「抓正文/抓链接/抓 meta/抓结构」四档回显全部 `ok=false`。
- **根因**:`capture_dom` 的回包走 `JSON.stringify({title,url,…})`(正文上限 4000 字、链接 200 条、meta 100 条),而 JS 求值回包当时走**事件通道**——事件文本槽 `WB_EV_TEXT=768`,`wb_push` 的 `strncpy` 硬截断,回包超 768 就成**半截 JSON**,MoonBit 侧 `vsc_json_parse` 必 None → `ok=false` 且 raw 是残文。两平台的桩是镜像实现、同一常数,所以 Linux(WebKitGTK)与 Windows(WebView2)同灭——「回包走事件槽」这个设计从写下那天起就装不下 DOM 档的量级,此前 showcase 时代没暴露是因为当时的演示回包恰好都短。
- **修复**:JS 求值回包改走**每视图专用大缓冲**(上限 `WB_EVAL_TEXT_MAX=64KB`,与拖放载荷缓冲同制)——C 侧完成回调(GTK `evaluate_javascript_finish` / WebView2 `ExecuteScriptCompleted`)把全文存进 `WbView.eval_text`,事件 kind=7 只带序号、text 恒空;新 extern `wb_eval_text(id,out,cap)` 取全文(返回总长,>cap 即读到了截断的前段);MoonBit 侧泵的 kind=7 分支改读大缓冲(`WB_EVAL_CAP=65536`),其余事件仍走 768 槽(标题/URL 那类短文本足够)。mac 桩同步补空实现。
- **验证方式**:`moon test web` **18/18**(新增 1 条长回包回归:4000 字正文与 200 条链接的完整 JSON 整体解析、截断链路下必红)、库全量 **978/978** 零红、`cd gui && moon check --deny-warn` 零警告、examples `--deny-warn` 零警告、browser 构建链接 + 本机 8 秒冒烟存活;两平台真机复验归 `测试文档/测试用例.md`。
## 曲线的第三层根因：满覆盖内段写 `cov[px] = 256` 且落在带循环里，纵向覆盖从未累加（2026-10-15,真机反馈）

- **环境**：Windows 10 19044 真机。上一批把光栅器覆盖从「4×4 数采样点」改成「8 子行 + 横向精确宽度」后，用户复验仍说「曲线平滑度还是不够，没有 Linux 上那种自然的感觉」。
- **为什么上一批没治好**：那批只核了**右缘剖面**（竖边——横向精确宽度当场见效），但带循环里那句 `cov[px] = 256` 是**赋值**：只要有一个带把整列包住，这一行就直接记满覆盖，**纵向从未真正累加**。于是近水平边（圆的顶/底）与顶点所在的角区仍是「整格有 / 整格无」，剖面出现 `0 → 249 → 255` 这种跳。
- **修复**（`gui/render/raster_fill.mbt`）：① 覆盖改 `+= 面积`，且先用一条 Double 侧（`cov_f`）逐片累进、行尾统一量化一次（逐段 round 会把误差累到 ±2）；② 「带心采样」升级为**按切片解析积分**——每行先把跨本行的边收进行内活跃表，再用「带边界 ∪ 本行内每条边被裁到本行的端点」把行切成切片，切片内没有顶点，span 的左右边界都是 y 的线性函数，与像素列的相交面积有闭式解（`span_slice_cover`：被积函数分段线性，断点只在左右边界各撞上 `px`/`px+1` 以及两边重逢处，逐段梯形公式即精确）。带数因此从「量化台阶的来源」降级为「只限制同片内双边交叉重排的误差」，8 子行退回 4 带，代价不涨。
- **顺带修掉一条真 bug**：「片顶或片底两端重合」的退化 span 被 `if ra0 <= la0 || ra1 <= la1 { continue }` 整片跳过，而那片真实面积是个三角形——三角形顶点那一圈直接丢墨，独立参考实测偏差 33-44 档；去掉这条跳过、交给解析积分（它含 `la=ra` 断点）即正确。**这条判据是拿独立参考量的，实现自己的输出当期望值就会像上一批那样"自洽地错"。**
- **精度证明方式**：另写一份与实现零共享的参考（32×32 网格采样 + 射线法判多在多边形内 / 逐点比半径），量最大偏差——多边形 1-2 档（旧 33-44），圆 7-9 档；圆的残余里约 8 档来自**贝塞尔展平容差 0.1 设备像素**本身（与 cairo 默认同档），不是覆盖算法。判据进永久回归：`worst_cover_gap`（4 种形状 ≤4 档，含一条近水平长边的扁三角）与 `ref_circle_cover`（r=25 圆 ≤12 档），旧实现下全红。
- **读数前后**：r=25 圆的半墨格 100→180、灰级 22（整数心）/77（分数心）；r=6 小圆 24→44 格；r=3.5（单选圆心）半墨 28 格。render 全包 1.5s→2.0s（其中含两条新增的参考比对用例），库全包 20.8s→20.4s。
- **验证方式**：`moon test render` **54/54**、库全包 **976/977**（唯一红仍是 `si_machine` 的 BIOS 注册表读数，本机环境基线）、`cd gui && moon check --deny-warn` 零警告、`moon build showcase --target native` 链接通过、本机冒烟 4 秒存活。真机复验仍归 `测试文档/测试用例.md`（重点看圆的顶/底与浅角度斜边）。


## 轻提示被第二次点击「吃掉」与侧栏键盘缺口:图层点外策略要分层声明、命中穿透要在 hit 层做(2026-10-15,Linux 真机反馈)

- **环境**:showcase 真机。用户报:①轻提示在屏时连续点触发按钮,第二次把第一次的提示「吃掉」;等提示关闭后再触发正常;去 dialog 开关一次回来也正常。②侧栏菜单 Tab 进不去、没有焦点环。
- **根因①(505f3ba 留档的「另批」正是这批)**:浮层图层满窗且命中从后往前——**任何点击都先命中图层**;图层的 `on_pointer` 对「点在浮层外」一律消费并在抬起时 `overlay_hide_top()`。轻提示没有「点外收起」语义,却享受同一条规则:在屏那两秒点按钮,按钮收不到这一击(第二条不出现)、提示还被这一击误收(第一条消失)——两条合看正是「第二次吃掉第一次」。等提示过期或经 dialog 开关(期间到期回调复位 `open_id`)后图层收起,点击恢复直达,所以「过一阵/经 dialog 又正常」。
- **修复①(点击策略 + 命中穿透)**:`OverlayHost.items` 从 `(id, w)` 扩成 `OverlayItem{id, w, dismiss}`——`overlay_show_at` 新增 `dismiss_on_outside`(默认 true,菜单/对话框的模态语义不变);`toast_layer` 传 false。**光让图层 `on_pointer` 返回 false 不够**:命中链在进图层前就把页面控件排除了(图层满窗、后挂优先),所以穿透做在 **hit 层**——`route_pointer` 命中落在图层自身(不在任何子浮层内)且最上层声明放行时,临时把图层 `visible=false` 重命中一次再恢复,点击/悬停一并回到页面控件(布局不动、rect 保留)。取舍记档:多层叠开只看**最上层**——轻提示压在对话框上时点外会穿到页面而不关对话框。
- **根因②**:a1b2c89 批把表单族接进 Tab 链时,`menu_sections` 的菜单项没接——`focus_ids()` 为空(上批无头诊断已证),Tab 无处落、也无焦点环可画。
- **修复②**:`menu_item` 加 `focusable`/`step` 参数(与 segmented 同一条键盘口径):声明 `focus_id` 进 Tab 链、空格/回车选中本项、↑/←/↓/→ 组内环绕换选,`on_draw` 尾部聚焦时描主题色环;`menu_sections` 全部项接上。
- **验证方式**:`moon test ui` **182/182**(新增 2 条:轻提示层点外放行且不误收 + 普通层点外仍收起的对照、菜单键盘链可达且空格/方向键有效——第一项 UP 环绕到最后一项是环绕语义的正确形态)、库全量 **978/978** 零红、`cd gui && moon check --deny-warn` 零警告、showcase 构建链接 + 8 秒冒烟存活;真机复验归 `测试文档/测试用例.md`。

## 渲染覆盖精度判据在 CI Linux 必红:又一次按单侧后端读数写死(2026-10-15,Linux CI)

- **环境**:610bf7f(光栅器覆盖第三层根因修复)新增的「与独立解析参考比偏差」判据,在 Windows(纯光栅器)读数多边形 1-2 档、圆 7-9 档,阈值按它写成 ≤4/≤12;CI 的 Linux job 走 cairo 后端——三角形实测 18、扁三角 16、圆 21,**全部越阈**,连续红。
- **根因**:cairo 的 AA 算法本身与「32×32 网格采样 + 射线法」参考的口径差,在三角形/圆的斜边上天然比光栅器大(16-21 档);阈值只按 raster 读数留余量,cairo 过不了——与 radio 圆心判据(cairo 面积采样 vs raster 像素格口径差)同族,本仓第四次踩到同款。
- **修复**:阈值改**双后端交集**——多边形 ≤20(cairo 16-18 过、旧实现 33-44 仍红)、圆 ≤24(cairo 21 过、旧实现 33-44 仍红),回归力度不丢;断言消息带实测档数,下次再红一眼看出量级;注释写明两侧读数来源。
- **验证方式**:本机 Linux `moon test render` **54/54**;Windows 侧由 CI 复验(raster 读数 1-2/7-9 远低于新阈)。
- **口径(再次记档)**:像素级/数值级判据一律先问「另一侧后端的读数是多少」,阈值取交集;本仓判据翻车四连——radio 圆心、launcher 回读、dragdnd effect 初值、本次覆盖精度——全是同一形状。
## 单行标签在自己的盒里折成两行：测量宽四舍五入报窄，与断行判定不同源（2026-10-18,mac 真机反馈 showcase 两页）

**现象**（用户 mac 真机，两处同族）：showcase「表单组件→日期」里 picker 下方的「选中：」压住 picker 下缘，「对话框」页「最近确认：」的冒号孤零零掉到第二行。不是绘制偏移、也不是弹层——文字**真的**折了行。
**定位**（无头探针 `mounted()` + 逐字测量）：布局给的盒宽 31/32、`measure_font("选中：", 13px)` 也返 32，但同一个串在 `max_width=32` 下 `pt_layout` 出两行、要 33 才单行——**测量与断行在边界上不闭合**。CoreText 的 advance 是浮点（`CTLineGetTypographicBounds` 实测 32.x），`pt_write_metrics` 用 `+0.5` 四舍五入 → 报窄；布局照这个窄宽下盒，绘制/测量再拿同一个 `total_w` 做贪心断行（`line_w + uw > lim`）就必然多一行。`ui.text(role=Body)` 隐含 `wrap=true`（basic.mbt），标签盒一窄就折行；折出来的高盒在行内 `valign=Center` 居中，首行墨迹上移骑到上方控件下缘——观感即「错位重叠」。
**修复**：测量宽一律**上取整**，让「盒宽 ≥ 真实浮点宽」成为测量与断行的不动点。三平台同批对齐口径——mac `pt_write_metrics`（`ceil(total_w)`）、Windows 两处 `pt_measure_font`/`rt_measure`（`ceilf(widthIncludingTrailingWhitespace)`）、Linux 的行尾空白补宽（Pango 的 `get_pixel_size` 本来就上取整，只有 `pt_width_with_trailing_ws` 用的是四舍五入）。高/基线取整维持原样：越界风险在横轴（折行），纵轴不在这条判据里。
**验证**：`gui/text/text_wbtest.mbt`「测量宽自洽：按测量宽下发的盒不再折行」——串含全角标点，先自由测宽再以该宽为约束折行，断言高度不变（不打具体像素，随字体配置走）；撤掉 ceil 该用例必红（本机回证：`FAILED: '选中：' 在自身测量宽 32px 的盒里折成了多行`）。UI 侧 `gui/ui/datepicker_wbtest.mbt`「日期段标签不折行」守整条链（标签与值标签同高、选中行不压 picker）。mac 本机 `moon test` text+ui 219/219；Linux/Windows 侧同口径改动由 CI 回证。

## 交互图表默认宽塌成 120px 窄带：包壳留 auto 宽，画布的 percent(100) 对 auto 父无解（2026-10-18,mac + Linux 真机同现）

**现象**（用户真机，两平台一致）：showcase 图表页·交互段的三张图（`line_chart_it`/`bar_chart_it`/`donut_chart_it`）全挤成一条窄带，同数据的非交互版正常。两平台同现即与文本/渲染后端无关，是布局层。
**定位**（无头探针 `mounted()` 打矩形）：默认宽时交互图壳 120×290、画布 120 宽；显式 `width=480.0` 一切正常。根因是交互版比非交互版多一层「图例 + 画布」的 vbox 包壳，而壳的宽写成 `width=if width > 0.0 { width } else { 0.0 }`——`view` 里 0 的语义是「不设宽」= auto；画布那侧 `width<=0` 走的是 `percent(100)` + `min_width(120)`。**yoga 的百分比要父尺寸确定才可解**，父是 auto 就无解 → 画布被 `min_width` 钳到 120，壳又是 auto 由子顶出来 → 也 120，整条链锁死。非交互版没有包壳，`percent(100)` 直接对确定宽的段容器求解，所以一直是对的。
**修复**：`width<=0` 的语义在交互版里就是「铺满父宽」，于是包壳自己写 `percent(100)`（新增 `ci_it_handle`，三处同批），显式 `width` 语义不变、仍走 `fixed`。
**验证**：`gui/chart/charts_it_wbtest.mbt`「交互图默认铺满父宽，显式 width 照旧」——默认宽时画布宽 == 父宽 600、`width=320.0` 时壳与画布都 320；撤掉修复该用例必红（本机回证 `FAILED: 默认宽的画布没铺满父宽`）。全仓 `moon test` 1252/1252。
**教训**：**「auto 父 + 百分比子」在 yoga 里恒塌**。包壳类组件（图例/标题 + 主画布那种）的默认宽要么靠父的 `Stretch` 拉出来，要么自己显式写百分比，不能留 0 让 `view` 当「不设宽」处理；`min_width` 兜底在这种场景下不会报错，只会把塌陷伪装成「内容就这么窄」。

## 自绘弹框三条焦点/边距缺口：视觉模态不等于焦点模态（2026-10-19,真机 Linux + mac 同现）

**现象**（用户真机，两平台一致）：消息框那一排按钮贴着面板右缘、没有右边距；框开着按钮拿不到焦点，Tab 还能跳到被遮罩盖住的页面控件。
**根因三条**：① 按钮区只写了一边内边距（`footer.set_padding(left=16.0)`），而钮是 `FlexEnd` 靠右排 ⇒ 右缘零间距；② 本栈焦点模型是「控件声明了 `focus_id` 就在链里」，弹框的底钮是自绘裸控件、没领号 ⇒ 链里根本没有它们，焦点只能挂在面板那个手动号上；③ 宿主 `App::sync_focus` 永远按**整棵树**收号，浮层里的控件和页面控件同一条链——遮罩只吃点击，键盘不模态。
**修复**：
- `OverlayItem` 加一条 `full`（只有铺满整窗的遮罩档 `overlay_show_full` 为真），`OverlayHost::focus_root()` 回答「当前焦点链归哪棵子树」，`App::sync_focus` 按它对齐：弹框开着时链只收这一层，其上再叠轻提示/气泡（放行档）不改变归属，收框后页面控件自然回到链里。
- 消息框与对话框的每个底钮领 `auto_focus_id(0)`、画焦点环（主色实底上用白环，与 `ui.button` 同口径）、`on_key` 吃空格/回车激活；开框即把焦点交给第一个钮并记住开框前的号，收框整批注销、还回原焦点。
- 一个按钮都没有的消息框仍给面板挂手动号——按键是按 `focus_id` 在树里定位控件的，没号连 Esc 都没有落点。
- 消息框按钮区补 `right=16.0`。
**验证**：`gui/widget/host_wbtest`「弹框开着时焦点链只收遮罩层，收框后页面回来」（含放行档叠加不改归属）；`gui/ui/message_box_wbtest`「消息框：底钮可聚焦、按钮区留右边距」与 `gui/ui/overlay_wbtest` 的对话框同名用例（钮 `focus_id>0`、右缘留 ≥12px）。全仓 `moon test` 1256/1256、`--deny-warn` 干净；真机目视归用户（T4 对话框/消息框段）。
**教训**：**视觉模态 ≠ 焦点模态**。一层盖住整窗的浮层要显式声明「焦点链归我」，否则键盘照常穿透；本栈把这个声明落在 `OverlayItem.full` 一个布尔上，判据集中在 `OverlayHost::focus_root()` 一处。

## 修饰键要入乡随俗：一套 `CmdOrCtrl` 词表 + mac 系统档加速键由宿主内置（2026-10-19,用户提需求）

**需求**（用户）：全局按键按平台习惯走——Linux 没有「Win 键」只有 Super、mac 的主修饰键是 Cmd；并且 mac 上要默认有 Cmd+Q / Cmd+W / Ctrl+Cmd+F 这类系统档加速键，体验与系统其它软件一致。
**三条口径**：
- **词表同源**：`CmdOrCtrl`（连同 `cmdorctl`/`commandorcontrol` 与 `control`/`option`/`command`/`win` 别名）在 `@win.parse_accelerator`（全局热键、菜单加速键）早就有，窗口内的 `parse_combo` 这次补齐同一套——同一串 spec 不该在窗口内与系统层有两个意思。平台读数走运行期 `@shell.platform_is_macos()`（不用 `#cfg(platform=)`）。
- **系统档只在 macOS 注册**：Linux 的 Super、Windows 的 Win 各有桌面归属，应用不该抢；那两档的关窗/退出本来就由 WM 与系统给。
- **派发排在焦点链与兜底通道之前**：本栈没有原生应用菜单，这三条在别的 mac 软件里由菜单给；排在页面之后就会被输入框或播放器快捷键抢走。`App::set_system_keys(false)` 留给要自己接管的调用方。mods 按全等比——多按一个 Shift 不算命中。
**新增口**：`Window::toggle_fullscreen`（三平台桩各一条）。mac 直接问 AppKit（`styleMask` 的全屏位），自己不记态——绿色按钮那条路改的态也跟得上；Win32/GTK 按记录态取反，WM 自己改的（F11 一类）追不上，记档取舍。
**验证**：`gui/widget/combo_wbtest` 三条——`CmdOrCtrl` 双档落地、别名与 win 侧同源、`system_key_action` 纯函数（含「非 mac 一律不抢」「抬起不算」）。全仓 `moon test` 1259/1259、`--deny-warn` 干净；真机（Cmd+Q/W、Ctrl+Cmd+F）归用户。

## 单窗口路由：空闲预加载会把「没做的事」真的做出来（2026-10-20，Ubuntu 24.04 + X11，`gui/router` + showcase）

- 现象：把页构造推迟之后，按「空闲时逐页预建」跑，会在没人点的时候冒出站栏托盘
  （`pages/system.mbt:431`）、启动空闲期去读浏览器 sqlite 与进程表
  （`pages/sysprobe.mbt:85`）、悄悄解码 GIF 并排好首帧动画（`pages/anim.mbt:52`）、
  把轮播的自转链起起来（`pages/data.mbt`）。
- 根因：这些动作写在 `node_of_new` 的 finish 里，而 finish 是**构造期**执行
  （`gui/widget/node.mbt:42`）——「构造」就等于「真做一遍」，跟挂没挂载无关。
- 修复：`LoadPolicy` 给三档（`Eager`=建窗当场建 / `Prefetch`=空闲按先序队列建 /
  `Lazy`=点开才建）。`系统集成` 标 `Eager`，托盘出现时机与改造前一致；
  `系统能力探测` 标 `Lazy`，启动期不再空跑探测。
- 验证：`cd examples/showcase && moon run .`——看 `SHOWCASE-READY ... startup_ms=`
  与切页时打出的 `SHOWCASE-ROUTE page=… built=… pending=… path=…`；托盘应在启动即出，
  系统能力探测页的读数应在点开之后才出现。
- 真机读数（Linux + X11）：`startup_ms=88`（无头量的全量构造是 261ms，启动只付首屏
  34ms 那一份）、`SHOWCASE-PROF frames=860 layout=214ms paint=1043ms present=420ms
  total=1677ms max_frame=80ms`——`max_frame` 对上判据里数据展示页的首帧 77ms，说明
  剩下的账在 paint 不在构造；15 页逐页切完均无感。切页路径全对、退出正常。

## 样式侧表残账：丢弃钩子只挂在 remove_child 上，预建的构造也要包进回收袋（2026-10-20，`gui/router` + `gui/style`）

- 读数（`examples/showcase/cost_bench` 的 A/B 对照，量 `@style.resolved_count()`）：
  同一页反复「建→挂→排→画→摘树」每轮仍留 33 条（基础组件）/ 182 条（数据展示）；
  改成「只丢引用、不摘树」涨到 99 / 315 条。
- 根因：外观槽放在进程级 `Map[控件 id, Style]`，清理钩子只挂在 `Widget::remove_child`
  的 `report_discard` 路径上（`gui/style/apply.mbt:14`、`gui/widget/widget.mbt:269`）。
  ① 只丢引用等于没摘树，整棵留在表里；② 「建好但从未挂载」的子树从没进过树，
  摘不到——这就是空闲预加载的固有残账量级。
- 修复：淘汰一律走 `remove_child` + 整代 `sub_bag` 退订 + 丢内容缓存，`Lru` 只数
  已挂载子树。另外组件在构造期就会订阅（`follow_store`，`gui/ui/nav.mbt:157`），
  而回收袋原本只兜挂载窗口，所以缓存条目连着存一份构造期退订闭包
  （`struct Built{node, offs}`），淘汰时两代一起退。
- 验证：`cd gui && moon test router` 里「淘汰把这一代订阅退掉」「Lru 淘汰是摘树，
  重进按 thunk 重建」两条；残账量级由 `cost_bench` 的 `RCB-RECYCLE-A/B` 复现。

## 「图标墙 803 控件卡启动」是旧账，实测大头在代码文档页（2026-10-20 实测修正）

- 读数（`examples/showcase/cost_bench`，1280x720，预热后；debug 与 `--release` 同量级）：
  全量构造 265ms、首屏页 33ms；图标库整页构造 9ms（`icon_grid` 确实逐个建 tooltip+icon，
  `pages/icons.mbt:9`）；代码文档页 138ms 独占全量的五成多（`code_view` 构造期逐 token
  量化 + markdown 解析）。最慢「点开当场建」= 代码文档 143ms；数据展示 102ms 里 77ms
  是首帧 paint——预建搬不动 paint，只能在挂载那一刻付。
- 结论：300ms 阈值未破，页内虚拟化不做；`shared/section.mbt` 注释与提案 §〇 里
  「图标墙是卡启动根因」的口径已按实测改掉。
- 验证：`cd examples/showcase && moon run ./cost_bench`，看 `RCB-PAGE` / `RCB-SUM` /
  `RCB-CLICK` 三类行。

## 工具链 · `derive(Eq)` 触发隐式提升告警；`x? : 函数类型` 把 Option 贴到返回值上（2026-10-20，moon 0.1.20260920）

- 给枚举写 `derive(Eq, Show)` 出两条警告（`implicit_impl_as_method`、`derive(Show) is
  deprecated`），库门禁要求零警告 ⇒ 策略判等改走 `match` 谓词
  （`LoadPolicy::is_lazy` / `is_eager`），与 `gui/widget/drag.mbt:60` 同一条口径。
- 形参写 `bar_of? : SlotBar`（`SlotBar` 是函数类型别名）时，可选标记被贴到函数的
  **返回值**上（体内成了 `... -> Node?`），传回原参数就报类型不符 ⇒ 改成显式
  `bar_of : SlotBar?` 位置参数。
- 同批读数：`String.split` 返回迭代器（要么 `for` 要么先收进数组）、`String` 没有
  `to_int`、`Map` 没有 `key_exists`/`has`、`Array` 没有 `enumerate`。

## 步进器：聚焦环压在格子悬停底够不到的那一列，中间格从「显示」改成「输入」（2026-10-20，Ubuntu 24.04 + X11/Cinnamon，真机截图）

- **环境**：`gui/ui/form.mbt` 的 `stepper`，showcase 表单段，用户报两条：① 悬停 `+`/`-` 那一格时灰块看着溢出外框；② 中间数字格点不进、打不了字。
- **根因**（①）：绘制序是「父件先、子件后」，外框与聚焦环都由行容器画，格内悬停底按既有口径内缩 1px 铺满自己那格。环当时走 `stroke_rect(0.5, 0.5, w-1, h-1)`，而门面契约是**内侧**描边——1px 宽的带因此落在第 1 行/列（不是第 0 圈），与格底抢同一圈像素，子件后画即吃掉环；同一条口径下 `(0.5,…)` 还让环左右上下不对称（左/上在第 1 圈、右/下贴在末圈）。真机截图与无头位图逐列读数同一条：环在第 1 行、灰底也从第 1 行开始。
- **修复**（①）：环改走外框自己那条路——`round_rect_path(0.5, 0.5, w-1, h-1, radius)` + `stroke`（居中描边，压在盒子最外一圈像素上），半径从样式槽现取。环占第 0 圈后，格底内缩 1px 与它天然不撞。口径：**父件画的环要吃边框那一圈，子件的填充就只能从第 1 圈开始**——用内侧描边接口画「贴边一圈」时参数给 `(0,0,w,h)` 而不是照居中习惯给 `(0.5,…)`。
- **根因**（②）：中间格是 `node_of_new` 的纯显示件（`draw_box_at` 现取 Store 值），没有编辑内核，也没有焦点号。
- **修复**（②）：中间格换成同包的 `input`，复用编辑内核（光标、选区、输入法、剪贴板）。四处配套：
  - 值与串双向：`Store[Int]` ↔ 内部 `Store[String]`；值变时按「串表示的数 ≠ 现值」才回灌，`007` 这类正在打的串不被顶回。
  - 闸门：按键与输入法提交都过一遍数字判定，只放行数字（`min<0` 时放行 `-`）；粘贴与不成数的半截串由提交时整串解析挡下，值永不被脏串污染。
  - 提交时机：回车或失焦。为此在 widget 层补 `Widget.on_focus_change`，触发口径与 `on_hover_change` 同一条（宿主每帧同步 `focused` 时只在真正翻转那一下调）。
  - 键盘口径改为 ↑ 加 / ↓ 减：←/→ 由编辑内核移光标吃掉、经祖先链不再到达行容器。**覆盖 2026-10-15 批「←/↓ 减、→/↑ 加」那条**。
- **附带坑**：`input` 整格铺底会啃掉上下那圈环——给它 `height=control_height-2`（行容器 `align_items=Center` 自然让出上下各 1px）并关掉自身边框（`border_width=0.0`）；整支控件仍只占一个 Tab 位，号给中间格、行容器不领号。
- **验证方式**：`moon test ui` 新增/改 4 条——悬停 `+` 时逐像素钉住四边中点为 `primary`、环内侧第一圈为 `fill_hover`（钉住「环不被吃」）、中间格打字夹取/回车与失焦提交/字母吃掉/值从别处变时串跟随、三格几何新口径、键控回归改 ↑/↓。读数：`moon check` 零警告、`moon test ui` 196/196、库全包 1077/1077。真机复验（视觉与手感）归用户。

## 维护约定

1. 新增结论写进对应小节,只记「坑 + 修复」;协议互操作结论必须来自真总线、真面板,单测自洽不算数。
2. 影音与桌面控制批次的落点:`影音与桌面控制命令路线`(Linux 系统能力数据层下)、`系统信息与系统级安全边界`、`目录枚举与进程内环境变量`(跨平台通用下)、`通用 D-Bus 调用层`(DBus 线路协议下)、`地图与飞线的投影方案`(自绘画布与图表渲染下);浏览器侧结论进 `Firefox places.sqlite` 小节。
3. 功能批次内不跑 `moon fmt`:当前工具链的重排口径与本仓既有风格不一致(一轮改到 287 个文件),要统一格式另开一批,并先确认口径一致。

### 前端化批次真机反馈修复集（2026-10-14，2026-10-16 自 TODO 迁入）

> 这批是「用户真机报障 → 定位 → 修」的一条一因记录，原先只存在于 TODO.md；按「全景在 roadmap、未完成在 TODO、过程在 adaptation」的分工整段迁入此处，TODO 侧删除。

- [x] **描边口径统一（2026-10-14，真机反馈「色板边框偏移」）**：门面契约是「`stroke_rect` 落在矩形**内侧**」（两后端同实现），但全仓 28 处调用点按居中习惯给 `(0.5, 0.5, w-1, h-1)` ⇒ 环整体往右下偏 1px（左/上露一条色底）。换算 `(x-lw/2, y-lw/2, w+lw, h+lw)` 并全仓切过（ui + chart + 示例）；按钮焦点环那条测试原本照着错几何采第 1 列，改采第 0 列，另加色板四边对称钉桩。
- [x] **非 Windows 侧编不过**（2026-10-14）：sys 电源方案批把两条带 `GUID` 形参的 `static` helper 写在所有守卫外（`static` 未调用也要过类型检查），Linux 上 `unknown type name 'GUID'` 直接炸掉整仓构建；两条 helper 圈进 `#if defined(_WIN32)`。口径：类型来自平台头的函数整段进守卫，改完 C 至少跑一次非目标平台编译。
- [x] **穿梭框面板太小**（2026-10-14，真机反馈）：默认 160×min 60 小得不像可操作列表 ⇒ 默认 200×160，并开 `height?` 参数（项多了仍自己长高，不裁行）。
- [x] **表格悬停只亮一格 + 「添加一行」无反应**（2026-10-14，真机反馈）：① 悬停是父链语义，但宿主只标「旧/新悬停那颗」的矩形 ⇒ 行画整行底色、重绘窗口只有一格。新增 `App::mark_state_chain` 沿命中链标脏，祖先仅在自己带状态桶时标（`@style.apply` 落 `Widget.paints_state`，core 不认样式层只读布尔）；无状态祖先时代价仍是一格。② Store 内建去重按值比，示例把「会被原地 push 的那个数组」存进 Store ⇒ 新旧同对象必相等、通知被吞；初值改存快照。口径见 adaptation 同批条。
- [x] **时间线连接线断成几截**（2026-10-14）：行间隙是容器 `row_gap` 给的、不属于任何控件 ⇒ 线在每处间隙断开。改成间距画进本行（非末行 marker 与行盒长到 `height+gap`），并加「间隙必须有线」的像素断言。跨行连续的装饰（连接线/轴/分隔线/轨道）都不能靠容器间距留白。
- [x] **面包屑点击不导航**（2026-10-14）：「当前项」按位置（末项）判而不是按导航状态判 ⇒ 末项不是当前页时永远点不动。改按 `selected.get() == mine` 判可点与配色。
- [x] **表单页三件**（2026-10-14，真机反馈）：① 输入框默认吃不到键盘焦点（`focus_id?` 默认 0 = 宿主判「不可聚焦」）⇒ `input`/`textarea` 未给号时自动分配（1000000 起，显式号仍优先）；② 焦点变化标脏把**焦点 id** 当**实例 id** 查树（`mark_focus_rect`→`mark_id_rect`）⇒ 新增 `mark_focus_id_rect` 走 `find_by_focus_id`；③ `input` 补 `clearable`（EP 同名，默认关，悬停/聚焦出 ✕，点它清空回写）；④ 步进器 `[-] 值 [+]` 改共框（外框由行容器画一次，格内只画悬停底+分隔线；旧形态三圈边框看着没粘住，实测三格本就同高）。
- [x] **表单族控件键盘可及性**（2026-10-15，用户反馈「非输入框都 Tab 不上、没键盘交互」）：button/checkbox/radio/switch/stepper/slider/rate/select/color_picker/date_picker/date_range/time_field/dropdown/segmented 全量默认自动领焦点号（`auto_focus_id`，2026-10-14 那条「刻意 opt-in」口径就此翻转）；空格/回车激活，radio/segmented 方向键按焦点项下标换选、slider/stepper/rate 方向键调值（slider 带 Home/End）、select/color_picker/dropdown 弹层 ↑↓ 高亮 + 回车取 + Esc 收、日期/时间字段开合层（日历内部方向键导航未做）；焦点环走「描边转主题色」与内圈两式。`moon test ui` 176/176、库 934/935（1 红为 Windows 基线）、真机复验归 S22。
- [x] **Windows 全屏与尺寸切换无效**（2026-10-15，真机反馈）：`gui/win/stub.c` Windows 分支的 `wm_window_set_size`/`wm_window_set_fullscreen` 是带符号空壳桩（GTK 分支早接了真实现），链接不断、调用静默无效。补 Win32 真实现：set_size 按当前样式把客户区物理像素外扩成整窗再 `SetWindowPos`，全屏记样式 + `WINDOWPLACEMENT` 现场、剥装饰换 `WS_POPUP` 摆到最近显示器整屏、退屏原样还原；`WM_SIZE` 既有记账让 MoonBit 侧照常收 `Resized`。`experiment/window_probe` 的 C 探针新增两节（尺寸读回 + 全屏进退现场还原，全量 `WIN-ENHANCE-OK`），真机复验归 S23。
- [x] **全局快捷键按了没反应**（2026-10-15，真机反馈）：库侧链路（RegisterHotKey → 泵截 WM_HOTKEY → poll）是好的，坏在 showcase 轮询表挂错时机——「零尺寸挂载钩子」写在 `node_of_new` 的 finish 里（构造期执行），页面函数求值早于建窗，第一拍跑在空 timer 通道上且 `app.host` 还是 None、循环不再重排当场死掉（与图表页推点同坑第 2 处）。改挂 `Node::on_mount`；window_probe 新增热键节（PostThreadMessageW 打 WM_HOTKEY 同路验截获/取出/去重/排他/注销）`WIN-ENHANCE-OK`，真机复验归 S24。
- [x] **图表页一直「暂无数据」**（2026-10-14，真机反馈）：`set_timeout` 的进程级通道由 `App::new` 装，无宿主时空操作返回 0；而 `page_charts(app)` 是 `mount_window` 的实参、求值早于建窗 ⇒ 构造期排的第一拍永不触发。改成挂在 `handle`（`mount_children` 之后跑）上；页内代码示例同步改口径。同批：段说明补 `wrap=true`（原来是一条 900px 不折行的文本，尾部整片裁字）。
- [x] **yoga-mbt 自由空间漏减行间隙**（2026-10-14，真机反馈「复制按钮还是有问题」）：§9.7 分配里 `initial_free` / `remaining` / auto-margin `free` / justify `free2` 只减子项外框和、没减 `gap x (n-1)`，而定位又逐项加 gap ⇒ grow 项多吃间隙、整行溢出容器（判据：行宽 100 + gap 10 + [固定 30, grow 1] 应为 60，修前 70）。四处统一先减 `gap_total`。
- [x] **段条「超宽自动换行」是假口径**（2026-10-14）：`ui` 从不写 `flex_wrap`、样式层也没这条属性 ⇒ 任何容器都是 NoWrap，段一多就横向溢出被裁。按「属性名 = CSS 属性名」给 `Style` 补 `flex_wrap`（工厂/merge/apply 全接线）。真换行还差两条配套：段条要放在**列**里（row 交叉轴不拉伸 → 换行容器按内容定宽，段折成六七行），并且**换行容器与父链每层显式 `min_height/min_width=0`**（规范 §4.5 列内子项 min:auto = min-content 高 = 全部堆叠，实测段条 224px、正文从 646 掉到 476；引擎符合规范）。修完量数：段条 54、正文 646、代码文档页视口 652/内容 808 可滚。
- [x] **滚动容器滚不动**（2026-10-14，真机反馈）：`scroll_view` 视口没写 `min-height`，Yoga flex 子项默认 min-size=auto ⇒ 视口被内容顶到自然高、`max()` 恒 0（实测 240×140 父里 viewport=676=content）。库级补 `min_height/min_width=0`，所有调用点（showcase 段正文与侧栏、native-app、virt_list 宿主）一起受益；显式 `height=` 不受影响。判据与对照读数见 adaptation 同批条。
- [x] **Markdown 页两处缺陷**（2026-10-14，真机反馈）：① 富文本区间按 UTF-16 code unit 出、`AttributedText` 契约是 UTF-8 字节下标 ⇒ 中英混排样式整体前移、端点切进字符（豆腐块 + 压字）；② `md_rich_label` 从不折行、节点宽=整段自然宽（一段 656px 撑进 480 文档）⇒ 右边缘裁字、代码区「复制」被推出可视区。修：`md_byte_len` 出区间 + 构造期贪心折行（中文逐字/拉丁逐词/`\n` 硬换行/超长单元按字符硬切），一行一个 AttributedText，删除线与链接命中按行换算，列表/引用/脚注/表格单元格按各自可用宽收窄（`md_narrow`）。判据与「换回旧单位当场红」的对照实验见 `experience/adaptation/common.md` 同批条。**待真机**：豆腐块/裁字/复制按钮是否消失、内容区纵向滚动是否恢复。


### 真机反馈修复集（2026-10-17，W30–W38 验证批）

- **折线图推点不跑（第 3 次同坑，这次修根）**：`set_timeout` 的进程级通道由 `App::new` 装，无宿主时空操作；showcase 默认选中段的 `on_mount` 在页面构造期就跑（`section_body` 的 `ensure(selected.get())` 在 handle 构造期执行），首拍落进空通道、自重排循环永不启动。前两次（2026-10-14 图表页、10-15 热键表）是**改调用点**绕开；本次修在 `shell/loop.mbt`——宿主未就绪时定时器进 `pending_timers`（负句柄、可 `clear_timeout`），`set_timer_hooks` 装上后按原延时补发。`host_reset` 复位通道。判据：默认段图表的 500ms 推点循环无需任何 on_mount 技巧即可自持。
- **密码框光标落在点串中间**：遮罩显示串 `•` 的字宽与原文数字/汉字不同（28px 字号实测 `"123"` 45px、`"•••"` 84px），光标与点击命中却按原文前缀测量 ⇒ 光标漂到点串中间、点击定位也偏。修：`prefix_width` / `byte_at_x` 加 `mask` 档，密码模式下前缀先过 `mask_of` 再测量；光标、选区、拖动、双击选词四处同口径。回归用 offscreen 渲染位图钉住「光标相对 x ≈ pad + mask 宽」。
- **stepper 悬停底盖住外框**：外框（含聚焦高亮环）由行容器在子件**之前**绘制，格内悬停/按下底是方形 1px 内缩填充，圆角处啃掉外框。改 `fill_round_rect` 内缩 1px、半径 3（外框 4 − 内缩 1）。
- **图表配色不随主色**：`series_color` 原先复用 primary/success/warning/danger 四语义色——主色偏红时 primary 与 danger 几乎同色，系列不可分辨。`Theme` 增 `chart_palette`（5 色，从主色色相按 128°/38°/210°/285° 旋转，饱和与明度按深浅模式钳制），`theme_chart_color(i)` 供图表取色；`theme_from_accent` 现算，内置深浅主题各带一份静态表。判据：换任意主色后前两系列色差可辨，系列 1 恒等于主色。
- **Alert 关闭钮在右上角**：用户口径是右缘垂直居中。✕ 与热区一起改为 `r.h/2` 居中，测试同步改采样区。
- **键盘键多击**：鼠标多击（W32 ClickTracker）之外补 `KeyTracker`——同 keysym+mods 的按下在 60–400ms 内再按计多击（下限滤系统自动重复 25–40ms/拍）；`Widget.on_key_double/on_key_triple` 只喂焦点控件，`App::bind_key_double(spec, cb)` 走窗口级兜底通道。单测直接改 tracker 的 last_time 造时间窗（真实间隔无法等待）。

## 工具链 · moon 的依赖解析单位是模块，不是包（2026-10-19，moon 0.1.20261012）

- **环境**：仓库根 workspace（`moon.work` 8 成员），想把 `modules/gui-examples`（audio / video / headless-audio，依赖 `gui-media` + `ffmpeg-mbt`）并进 `examples/`，同时不让 ffmpeg 链路拖累 `hello` 一类基础示例。
- **现象**：直觉方案是「每个示例目录放自己的 `moon.mod`」，但先怀疑 moon 不支持——一个模块目录下再放子 `moon.mod` 会不会被父模块吞掉、或根本解析不出来；`moon check examples/hello` 从仓库根跑还会连带报出 `showcase` 的包路径错，看不出是谁的问题。
- **根因**：`/tmp` 三组探针（moon 0.1.20261012）实测出三条口径：① 依赖解析以**模块**为单位——`moon.mod` 声明了一条 registry 里不存在的依赖，即使没有任何包 import 它，`moon check` 也在 `Failed to resolve the module dependency graph` 阶段整体失败；② 嵌套在模块目录里、自带 `moon.mod` 的子模块**完全不碰**父模块的依赖，各自独立解析，即一目录一模块的形态是支持的；③ `moon.pkg` 只能从模块已解析的依赖里挑包，做不到包级自带依赖版本。本地模块间依赖不写 `moon.mod` 的 `path:`（官方文档已弃用该形态，实测解析报错），而是**两边都注册进 `moon.work` 的 `members`**，`import` 照写名字与版本，workspace 命中时忽略版本号走本地源码。
- **修复**：`examples/` 从「一模块带全部示例」拆成 8 个独立模块（`NoahLiu/native-gui-examples-<目录名>`），`modules/gui-examples` 的 audio / video / headless-audio 移进 `examples/` 同样各自成模块，`assets/` 留作纯资产目录（无 `moon.mod` 即不是模块）；`moon.work` 列全部成员；showcase 内部包路径由 `NoahLiu/native-gui-examples/showcase/*` 改为 `NoahLiu/native-gui-examples-showcase/*`；产物目录随模块名变为 `_build/native/<mode>/build/NoahLiu/native-gui-examples-<name>/native-gui-examples-<name>.exe`，`scripts/make_app.sh` 与 `release-bin.yml` 同步。附带收益：`gui-media` / `gui-webview` 走 workspace 本地解析后，示例不再要求这两个模块先发布到 mooncakes。
- **验证**：各示例模块 `moon check --deny-warn` 全绿；仓库根 `moon check --deny-warn`（workspace 全量）通过；`moon test examples/sysmonitor` 66/66；`moon run examples/headless-audio` 在真 macOS 上播到 t=6.019s 正常退出并读到 `examples/assets/1.mp3`（资产路径与 ffmpeg/miniaudio 链路同批回证）；产物目录实测出现 `native-gui-examples-hello/`、`native-gui-examples-headless-audio/` 等按模块名分目录。

## 模糊链路（`@ui.glass` / `Painter::backdrop_blur` / `Bitmap::soft_blur`）整条下线（2026-10-20，使用者真机反馈「不可用」）

- **环境**：Ubuntu 24.04 + X11 + XFCE 主链路，showcase 侧栏「半透玻璃」开关（`@icons.MagicStick` 那颗）。
- **现象**：开关按下只有整窗透明 + 侧栏换一层固定色底（`#12161FCC`），看不到任何模糊；使用者判定该功能不可用，要求整条去掉。
- **根因**（两条叠加，都在代码里可对证）：
  1. **模糊 pass 从没接进侧栏**：`@ui.glass` 在全仓库零调用点（只在 `shared/app.mbt` 的注释里被提过一次），侧栏透明靠的是 `background_color` 常量，开关实际只调 `Window::set_transparent_bg`——「玻璃」二字没有落点。
  2. **即便接上也不是想要的东西**：`backdrop_blur` 读回的是 `Painter.self.bitmap`，即**本窗口内已绘制的像素**，糊不到窗口外的桌面/下层内容；`soft_blur` 是 1/8 块平均降采样 + 双线性回放的近似，两后端都没有真卷积（`proposals/style-css-expansion.md` §1.1 与 §59 已记「目标读回+分组+模糊」为未做项）。加上 `set_transparent_bg` 本身需合成器（窗口页文案：无合成器静默无效），三段里任何一段缺位都出不了毛玻璃。
- **修复**：整条删除，不留半套 API——`gui/render/blur.mbt`、`gui/render/blur_wbtest.mbt` 删文件；`gui/render/painter.mbt` 去 `Painter::backdrop_blur`；`gui/ui/overlay.mbt` 去 `glass`；`docs/components.md` / `docs/zh/components.md` 去 glass 行；showcase 侧 `main.mbt` 去开关按钮与侧栏透明底色、`shared/app.mbt` 去 `translucent` 字段、`cost_bench/main.mbt` 去对应初始化。要做真毛玻璃只能重来：先补后端的高斯/分组能力，再谈 API。
- **验证**：`cd gui && moon check` 零错误零警告；`moon test render ui base widget` 中 render 全绿，ui 的 3 条失败（步进器两条、密码遮罩光标一条）在 `1d1ff8f0` 干净 worktree 上同样失败，与本批无关；`examples/showcase` `moon check` 全绿。真机口径：侧栏底部只剩深浅/圆角/语言三颗按钮，不再有无效果的玻璃开关。

## 圆角四角的黑/白勾勾：擦角 pass 两条根因（2026-10-20，mac 与 Ubuntu 都复现，真机截图）

- **环境**：macOS（纯光栅后端）与 Ubuntu 24.04 + X11（Cairo 后端）同一条控件绘制收尾——`Widget::paint_at` 的 `clip_rounded` 圆角 pass。
- **现象**：圆角容器（卡片、悬停组、输入框这类带底带框的）四角外侧各露出一道小勾勾，mac 上是黑的、Linux 上是白的；同一道缺口在底角比顶角更明显。
- **根因一（打洞）**：收尾 pass 用 `set_blend_mode(Clear)` 把弧外像素擦成 `a=0`。整窗是**一张位图**贴给宿主的——mac 走 `CGImageCreate(kCGImageAlphaPremultipliedFirst)` 贴进 `drawRect:` 的上下文、Windows 走 WIC/32bpp 位图，两处都没有「窗口自己逐像素透明」这回事，透明像素就露出上下文底色（黑或白）；X11 那边有合成器，擦洞透出的是桌面。三条路径都不对，因为**要的不是洞，是父层原本那张脸**。
- **根因二（底角公式镜像）**：逐行扫描的 `yc`（该行行心到圆心的竖直距离）四角共用顶角公式 `r-y-0.5`。顶两角圆心在角盒底，这个式子对；底两角圆心在角盒顶，应为 `y+0.5`。用错的结果是把弧外带镜像到角盒内侧——底角首行被啃进 3~4px（半径 6 时），正是截图里底角那道更粗的缺口。
- **修复**：
  1. `gui/render/painter.mbt` 新增 `Painter::pixel_at(x, y) -> Color?`：与 `fill_rect` 同一套本地坐标，先 `flush` 再读缓冲，越界返回 None（不当全透明）。
  2. `gui/widget/widget.mbt` 收尾 pass 改为**补回父层原值**：每角读本控件外侧紧邻那一像素（左角 `x=-1`、右角 `x=w`，纵向取角盒中段）作底色，`set_blend_mode(Copy)` 整像素放回（不与刚画的方底做 source-over）；读不到（贴窗口边、外侧本身没画）时这一角保持方角——宁可方角也不要黑角。
  3. 同处 `yc` 按 `top` 分支：顶角 `r-y-0.5`、底角 `y+0.5`。
- **验证（助手侧无头判据）**：`gui/widget/widget_wbtest.mbt` 新增两条——① 卡片落在 (10,10)-(30,30)、半径 6：正中蓝、顶角弧外=父层红、底角弧外 (29,29)=红、底角弧内 (29,24)/(24,29) 仍是蓝（这条专挡根因二，旧公式下被啃成红）、整幅 40×40 无一个 `a=0`（这条专挡根因一，旧 pass 下角上全是洞）；② 卡片贴满 20×20 画布、四角外侧都读不到：保持方角且无 `a=0`。`moon check`（gui）零错误零警告；`moon test ui render text theme icons sys input win dbus chart mdview style base shell widget router` 1101 条，只剩上面那 3 条既有红。
- **待真机（使用者判据）**：`moon run examples/showcase` → 基础组件页「悬停组与光标组」段（截图那处），顶角与底角四角都应与父层底色连续，无黑/白勾勾；切深色主题再看一遍。注意本栈仍**没有真圆角裁切**（后端缺 path clip），这道 pass 只是把弧外补回父层色，压在渐变/图片上的圆角仍会看到一圈采样底色。

## 演示板整页换语言：三条取译通道 + 目录读手的静默坑（2026-10-20，macOS arm64 开发机）

- **报障口径**：「点地球只有系统菜单有反应」→「页面还是不会更新语言，是不是页面没有引入 key(t) 函数呢？」两条都对，根子是三件事叠在一起，逐条拆开记。
- **读手层（`gui/i18n/catalog.mbt`）三个静默失效**，都不报错、只查不到：
  1. 键写成 TOML 的带引号形态（`"中文原文" = "English"`）时，旧读手把引号留在键里，按裸文本永远查不到 → `i_unquote` 现在对**键与值同一条口径**：脱引号 + 解 `\n \t \r \" \\` 转义。
  2. `[meta] locale = "en"` 写在**最前**时，按 TOML 段头规则它之后的裸键全带 `meta.` 前缀——整本目录静默作废。落成的 `EN_CATALOG` 把 `[meta]` 挪到最尾，并在 shared 的 `catalog_guard_wbtest` 里逐条自检「每条目录键都能按它应有的键查到」+ 显式断言 `[meta]` 之后不许再有顶层键。
  3. 键里带 `=`（`white_space=NoWrap` 这类原文当键）被第一个 `=` 截断 → `i_split_eq` 跳过引号内的 `=`。
- **广播层**：换语言不再靠调用方各自记得刷新——`i18n_load / i18n_extend / i18n_reset` 末尾统一 `locale_notify()`；原生菜单栏走 `@widget.set_menu_bar_localized`（注册表口径，重复注册替换），页面走 `@router.localize_remount()`（原地 unmount + 逐层 `set_always` 触发重建）。两个口都挂同一条广播，不会再出现「菜单动了、页面不动」。
- **正文层（真正缺的那一刀）**：`@ui.text` 收到的字面量从来没经过 `t_or`，所以目录再全也不会显示。这轮把口径固定成**三条通道**，全部由 `scripts/check_showcase_i18n.py` 兜底：
  ① 正文显示串 = `@shared.tx("中文原文")`（中文态回落原文，英文态命中「原文→译文」），共 484 处；
  ② 页内段条 = `seg.` + 段名，`@ui.segmented` 新增 `label_of?` 形参（**只改显示，`options` 仍是选中值与 `selected` 的取值域**），`page()` 出口传 `@i18n.t_or("seg." + n, n)`，共 101 段；`@router.Router::strip_at` 同带 `label_of?` 透传；
  ③ 侧栏/段条里的页名 = `nav.` + 页名（`nav_label`），路由表里那 15 个键值不参与翻译。
  门禁跑法：`python3 scripts/check_showcase_i18n.py`（反解 `EN_CATALOG` 拼出的 TOML 文本，三条通道逐条查，缺任一即非零退出）。
- **刻意不动的两类**，避免把演示内容翻成另一回事：`code=[…]` 代码块与 Markdown 样例正文（那是被渲染的**素材**，不是控件文案）；带 `\{}` 插值的动态回显串（按号数、按探测结果现拼，仍走中文；要译得逐处换成 `@shared.tr_with(key, vars, zh)`，目录条目用 `\{名}` 占位——机制已在，属可增量补的尾巴）。富文本段的范围属性按**字节区间**打点，样例串一旦换字就会错位，故那几处不套取译口。
- **验证**：`cd gui && moon check` 零错误零警告；`moon test widget ui style theme render i18n router` 465 项里 462 通过（3 项红是 HEAD 上就红的步进器打字 ×2、密码遮罩光标 ×1，与本批无关）；`gui/i18n` 12/12（含把临时探针 `keyprobe_wbtest` 折成具名回归测试「顶层键引号 / 段前缀 / 值内转义 / `[meta]` 顺序」）；`examples/showcase` `moon build` 通过、`moon test shared` 3/3；覆盖率门禁 484/101/15 全绿，目录条目 827。**整页换语言的真机观感归使用者**：`moon run examples/showcase` → 点地球，看段条、段标题/说明、正文控件文案、侧栏与原生菜单一起切，再切回中文不残留。

## 切语言后「新页面还是默认语言」：预建缓存没跟着作废（2026-10-21，macOS arm64 开发机）

- **现象**：点地球后，正看着的那一页换了英文，但**再点开别的页**仍是中文——只有系统菜单和当前页对。
- **根因**：`Router::remount_all` 只 unmount **在挂**的路径（`unmount` 里顺带 `purge_built(path)`），而演示板启动就 `Prefetch` 预建了十几页：**建过但没点开过的页只活在 `built` 缓存里，不在挂载表里**，重挂碰不到它们。下次导航到那条路径时 `build_now` 命中缓存，直接把旧语言（内置中文）建好的节点复用出去——看着就像「新页面用默认语言渲染」。
- **修复**：`gui/router/prefetch.mbt` 新增 `Router::purge_all_built()`（全表丢节点 + `sub_bag_discard` 退掉构造期那批订阅）；`remount_all` 在卸完在挂子树后调它，再 `reanchor()` 把空闲预建队列拨回起点（`prefetch_step` 会跳过已建的，于是这些页按新文案在空闲里逐个补建回来）。回归测试 `remount_all：未挂载的预建页一并丢缓存，再点开按当前目录重建` 把「建过→重挂→`is_built` 必须为假→点开再跑一次 thunk」四步钉住。
- **代价**：切语言那一刻缓存全空，**第一次**点开某页要现建（预热的收益推迟一轮空闲）；换语言本来就要整树重建，这笔比「页面语言错了」划算。

## 状态/回显类插值串接 `tr_with`，以及按行扫描漏掉的那批（2026-10-21）

- **报障**：主题色段的「当前主色：内置默认」翻了，但选了自定义色之后那行仍是中文「当前主色：#D64550」——**同一行里两个串，只套到了一个**。
- **根因**（批处理脚本的口径错）：上一轮补套是按**整行**判断「这行已经有 `@shared.tx(` 就跳过」，于是同一行里剩下的字面量（`if … { tx("中文") } else { "中文：\{v}" }` 这种两分支、`@ui.tooltip(button(tx("…")), "提示正文")` 这种嵌套实参）全部漏网。改成**按字面量**判定：只有紧邻前缀是 `tx(` 的那一处算已套，同行其它 occurrence 各自处理。
- **插值串换通道**：带 `\{}` 的显示串不能整串当键（值每次都不同），一律走 `@shared.tr_with("dyn.<语义名>", [("占位", 取值)], "中文原文\{原插值}")`——中文态回落原串，英文态按目录模板填 `{占位}`。本轮转 45 处（状态回显、计数、错误原因），另把 `"中文 " + x + " 中文"` 的**拼接式** 7 处也整式改成 `tr_with`。取值表达式注意类型：`r : Int` 要 `.to_string()`，`Err(e)` 里的 `e` 是 `AutostartError`/`NotifyError`/`OpenUrlError` 这些枚举、**不是 String**，目录表项要写 `("\{e}", …)` 形式借用它原本的 Show 口径，直接 `("e", e)` 会 4014 类型不匹配。
- **两套转义别混**：目录条目本身是 MoonBit 源里的串，`"\"键\" = \"值\"\n"` 解一层给 TOML；值里要放 TOML 的换行转义（像 `form.textarea_demo` = `"Text area demo.\nSecond line."`）就得多写一层——源里落成 `\\n`，解一层后才是「反斜杠 + n」两字符交给 TOML 读手；写成 `\n` 会在拼出的目录文本里直接断行，那条键整个静默查不到（`scripts/check_showcase_i18n.py` 反解时也栽过一次，改成按 MoonBit 源规则单遍解转义才对）。
- **MoonBit 的 `x.foo"str"` 语法是坑**：脚本套口时写成 `@shared.tx` + 字面量（少了括号），MoonBit 按 message-send 照收不误，**只有实参类型不是 String 的那两处才炸**（`@ui.tooltip` 的第二参）。批处理生成函数调用务必带括号：`@shared.tx("…")`。
- **门禁加了第五条通道**：`scripts/check_showcase_i18n.py` 现在查 正文 tx 501 / 段名 seg 101 / 侧栏 nav 15 / 插值 dyn+显式 tr 57，缺任一即非零退出；`catalog_guard_wbtest` 抽查也补了 `seg.主题`、`dyn.accent_now` 填占位、`form.textarea_demo` 值内换行三条。
- **验证**：`cd gui && moon check` 零错误零警告；`moon test router widget ui i18n style theme render base` 503 项 500 通过（3 项红是本机 HEAD 上就红的步进器打字 ×2、密码遮罩光标 ×1）；`examples/showcase` `moon build` 通过、`moon test shared` 3/3；覆盖率门禁四通道全绿、目录 900 条。**待真机**：`moon run examples/showcase` → 切英文 → 挨个点开没看过的页（尤其图表 / 系统集成 / 窗口），确认按当前语言建；再回中文切一次，看空闲预建把页面重新建回来不闪不炸。

## 托盘提示语 / 右键菜单 / 窗口标题补进原生表面语言口（2026-10-21，macOS arm64 真机反馈）

- **报障**：切语言后托盘图标的悬停提示仍是中文——页面、侧栏、原生菜单都换了，只有托盘不动。
- **根因**：提示语是**建托盘那一刻**写进原生侧的（`t.set_tooltip(tx("…"), tx("…"))`），SNI/Win32 拿到的是一份**已经算完的字符串**；语言广播只管控件树与菜单栏，托盘这一头没人登记，原生侧就永远停在旧串。同一条缺陷还有两处：**右键菜单**（`set_menu` 一次成型）与**窗口标题**（`title=SHOWCASE_TITLE` 建窗时定死）。
- **修复（按通道，不按控件）**：`gui/shell/tray_locale.mbt` 新增托盘语言口登记表——`Tray::set_tooltip_localized(title_of, body_of)` / `Tray::set_menu_localized(build)` 登记即算一次并写回原生侧，之后每次 `locale_notify` 按登记序重算；`TrayState.locale_key` 存登记号，`Tray::remove` 自动撤下，登记表不留孤儿。普通 `set_tooltip` / `set_menu` 生效即清掉对应口——**以最后一次写法为准**，两条入口不打架。`gui/widget/locale_surface.mbt` 同形补 `set_window_title_localized(title_of)`，与菜单栏共用一条 `on_locale_change` 链（单登记位，重复登记替换）。
- **演示板接线**：托盘页改用两个 localized 口；`tray_holder` / `tray_clicks` 从页内 `let` **提到模块级**——切语言会原地重挂本页，页内 Ref 每次重挂都换新的，旧句柄成孤儿就是「图标还在、按钮管不着它」，还会同 Id 重复注册（僵尸注册项那条老坑）；建托盘处加「有货就只重接线」的守卫。「改标题」按钮改成再登记一任取串口（后登记者为准），改名后再切语言不会被默认标题盖回去。
- **口径顺带补齐**：`托盘后端失败：\{msg}` 这类漏网的插值串改走 `dyn.` 通道；`scripts/check_showcase_i18n.py` 的取值正则原来要求 `tx("` 紧邻，取译口跨行写就漏检——改成先把源码折行再匹配（当场逮到 `dyn.tray_backend_failed` 缺条目）。窗口标题走常量 `tx(SHOWCASE_TITLE)`，脚本看不见常量，`catalog_guard_wbtest` 里按「组件库演示板」这条键抽查兜住。
- **验证**：`cd gui && moon check` 零错误零警告；`moon test widget ui style theme render i18n router shell base` 548 项 545 通过（3 项红是步进器打字 ×2、密码遮罩光标 ×1，本机 HEAD 上就红）；`gui/shell/tray_locale_wbtest` 2 项、`gui/widget/locale_surface_wbtest` 2 项新登记链全过（含「换一任后旧口停住」）；`examples/showcase` `moon build` 零警告、`moon test shared` 3/3、覆盖率门禁 tx 501 / seg 101 / nav 15 / dyn+tr 59 全绿、目录 902 条。**待真机**：`moon run examples/showcase` → 系统集成页建托盘 → 切英文，悬停托盘图标看提示语换、右键看菜单项换；改提示后再切一次语言看续着换；主窗标题随语言换，「窗口」页点「改标题」后再切语言看没被盖回；退出进程确认托盘注销干净。

## 托盘归 main：应用级单例不在页里建（2026-10-21，使用者定的架构口径）

- **判据**：托盘、原生菜单、窗口标题这类**控件树之外**的表面，生命周期归应用（`main` 挂载期），不归某一页。演示板原先在「系统集成」页的构造期建托盘，页随切语言原地重挂 → 页内 `Ref` 每次换新的，旧句柄成孤儿（图标还在、按钮管不着），同 Id 还会重复注册（就是「托盘僵尸注册项」那条坑的另一半成因）。
- **落位**：`@shared.App` 加 `tray : Ref[@shell.Tray?]` / `tray_clicks` / `tray_note` 三个槽（句柄类字段用到才加，这里三样都被页按钮真读）；main 的 `handle` 里建托盘 → `set_tooltip_localized` 默认提示语 → `set_menu_localized(build_tray_menu)` **默认挂上右键菜单** → `on_click` 计数 → 起 200ms 派发表（起表点在 main，那时宿主已就绪，不会再踩「首拍 `host_active()` 为 None 就永久不再重排」那条）。系统集成页只剩三个操作按钮：改提示、换自绘图标、回内置图标，回显与计数都 `bind_label` 读 App 槽。
- **补的库面**：`Tray::set_icon_pixmap(w, h, argb)` 与 `Tray::set_icon_builtin()`——换图标此前只有 `set_icon(路径)` 和 `new` 的 `icon?` 两条，**建好之后拿不到自绘档**，演示「更改图标」就无从下手。位图口径统一吃 SNI 规范的**大端 ARGB（不预乘）**：SNI 侧直接进 `IconPixmap` 并发 `NewIcon`；Win/mac 侧内部换成 `icon_from_bgra` 要的 BGRA 小端预乘（换算从 `builtin_tray_handle` 抽成 `argb_to_icon_handle` 共用）。像素不合法（尺寸非正 / 字节不够）静默保持原图标，不把 0 句柄塞给后端。
- **验证**：`cd gui && moon check` 零错误零警告；`moon test shell` 46/46（新增「换算与非法输入」与「`set_icon_pixmap`/`set_icon_builtin` 冒烟」两条，后者无后端机器自动跳过；`argb_to_icon_handle` 断言只咬非法输入给 0 与「native 建得出句柄、GTK 桩给 0 都不崩」两档，不越口径断言平台差异）；`examples/showcase` `moon build` 零警告、`moon test shared` 3/3；覆盖率门禁 tx 492 / seg 101 / nav 15 / dyn+tr 57 全绿、目录 906 条（按钮新增四条：换自绘图标 / 回内置图标 / 两条回显）。**待真机**：`moon run examples/showcase` → 启动就该在通知区看到月牙且**右键直接有菜单**（不用先进页点「挂菜单」）；系统集成页依次点改提示 / 换自绘图标 / 回内置图标，看悬停提示与图标即时变；切英文再重复一遍，看提示语随语言、图标随操作；左键点图标看页内计数与菜单里「报左键计数」一致；退出后确认通知区无残留。

## 日期时间族：占位/表头取译 + 时间弹层改列式步进（含可选秒）（2026-10-21）

- **报障三则**：①「基础组件-字体排版」段标题与描述没翻；②步进器点按钮不聚焦、框内内容与显示值不一、失焦不同步，「步进器和它的输入框各自为战」；③日期 placeholder 与日期选择不国际化，时间选择应改成 `+ / 时:分:秒 / −` 的列式形态、秒可选。
- **①段标题/描述**：`section()` 的出口是 `t_or(title)` + `t_or("desc§"+title)`，机制没问题，缺的是**目录少这两条**——「各语言的行首方向」及其 `desc§`。这类漏网此前查不到：`catalog_guard_wbtest` 只保证「目录里已有的键都能查到」，不保证「页上每段都在目录里有条目」。已在 `scripts/check_showcase_i18n.py` 加两条通道：逐段抽 `@shared.section(name, title, desc)` 的 title 与 `desc§title`，缺任一即非零退出（本轮逮到 2 条）。
- **②步进器**：两条红测的根因**不在控件而在用例口径**——`key(..., 'a', MOD_CTRL)` 在 mac 上等于没按键（编辑主修饰键跟平台走，mac=Cmd），全选没发生 → 打字变成追加，格上 `725` 而期望 `25`。改用 `entry_wbtest` 既有的 `mod_edit()`（按平台给 META/CTRL）后两条即绿；顺带把「密码遮罩光标」那条也改成**平台无关判据**（实测 mac 的遮罩比数字窄：mask=19 vs raw=22，旧断言写死「圆点比数字宽」是错的口径，只咬「光标贴遮罩串宽度」）。真缺的功能补上：新增 `App::focus_by_id(id)` 与 `Widget::request_host_focus()`（先 `sync_focus` 再落焦点、同步 `focused` 标志并置脏；号不在册/无宿主静默给 false），步进器 `bump()` 走完步长调 `take_focus()`——点 +/- 之后中间格拿到焦点，接着打字有去处。另加一条「从没聚焦过连按 +/-，值与格上串必须一路同步」的回归。
- **③日期时间族取译**：库内 chrome 全部走 `gui.ui.datepicker.*` 键——月历头 `"{y} 年 {m} 月"`（`t_with_or` + `{y}/{m}` 占位）、星期单字 `wd.0..6`（周日在前，与 `date_weekday` 同口径）、字段占位 `placeholder`/`range_placeholder`（**默认值仍是中文原文，取译发生在读值那一刻**，调用方自定义占位串照旧回落自身）、面板标题 `title`、按钮 `ok`（`cancel` 早已键化）。中文源串同时补进 `gui/i18n` 的 `BUILTIN_DEFAULT`，`t()` 无回落也能出中文。
- **③时间弹层改形态**：旧形态是两行 `[−] 时 [+]`，且顶部时间画在面板 `(0,0,28)` 不占布局（真机反馈「第一行步进被压住」那条坑）。现改成**列式**：每列自上而下 `+ / 数值 / − / 单位`，列间 `:` 分隔，按「行」组织（`+ 行 / 数值行 / − 行 / 单位行 / 按钮行`）——同一行的格子高度天然对齐，不需要任何手算 margin。时 0-23、分秒 0-59 一律 `wrap_add` 到界回绕，分步进从 **5 改为 1**。内部态从 `Ref[TimeHM]` 换成 `Store[TimeHMS]` + `bind_label`，数值格随点随新（不再靠整树 invalidate 的隐式约定）。
- **秒是可选的**：`TimeHM` → `TimeHMS{h,m,s}`，`time_clamp(h, m, s?=0)`、`format(show_seconds?=false)`、`compare` 按秒、`Eq` 带秒；`time_field` / `time_range_picker` / `datetime_range_picker` 一路透传 `show_seconds?`。类型改名影响 7 个文件（gui/ui 两处 + 两处测试 + 中英文档），`pkg.generated.mbti` 不是构建门禁物、未随改。
- **验证**：`cd gui && moon check` 零错误零警告；`moon test widget ui style theme render i18n router shell base` **553/553 全绿**（本会话内第一次没有红项：步进器两条与密码遮罩那条的根因都已定位并修）；`examples/showcase` `moon build` 零警告、`moon test shared` 3/3；覆盖率门禁七条通道 tx 493 / seg 101 / nav 15 / dyn+tr 59 / 段标题 101 / 段描述 103 / 库 chrome 19 全绿、目录 930 条。**待真机**：`moon run examples/showcase` → 表单页「日期」段：切英文看占位「Select a date」、月历头 `10/2026`、星期 Su Mo Tu…、确定/取消；打开时间弹层看四行列式与 `:` 分隔，点 + / − 看时/分（带秒那条多一列）到界回绕；基础页步进器点 +/- 后中间格应有光标聚焦环、直接打字替换后再失焦值同步；切英文回看「字体排版」段标题与描述。

## 验证消息、Markdown 行距、对话框内容补上语言口径（2026-10-21）

- **验证消息**：`gui/ui/validation.mbt` 的四条默认串（不能为空 / 至少 N 个字符 / 邮箱格式不对 / 须在 lo..hi 之间）此前是**写死的中文**，规则在页面构造期建好就把串摊进闭包，切语言只能显示中文。改成默认参数留空 + 构造时走 `gui.ui.validation.*` 取译（带数值的用 `t_with_or`，模板 `{n}`/`{lo}`/`{hi}` 填占位），中文源串同时进库内置默认目录；显式传 `msg=` 的调用方照旧用自己的串。演示页用的是默认规则，所以自动跟随（页随语言重挂 → 规则重建）。
- **Markdown 行距**：`md_rich_label` 的行带此前直接取字体天然行高（`line_height_multi`，13 号约 17px），只保证字形不相撞，排出来每行贴脸。改成 `line_h = 字体行高.max(字号 × 1.6)`，块级容器 `markdown_view` 外层 `col` 补 `row_gap=6.0`（原来块与块也贴在一起）。两处口径都在同一函数里，标题/表格单元/脚注一并跟着走。链接命中按 `my / line_h` 定行、删除线按 `y + line_h × 0.5`，都吃同一个 `line_h`，改行距不需要动别的口径。回归：一段必然折行的中文长文，高度按 1.6 倍字号 × 行数校；两段之间空隙 ≥5.5。
  - 顺带一个测试口径坑：Markdown 源里单个 `\n` 是**软换行**（并成一行），别拿它当两行写判据；要么用空行分段，要么用窄宽逼出折行。
- **对话框内容**：`@ui.dialog` 的 confirm/cancel 早就走 `gui.ui.dialog.*` 取译，但**内容 children 是调用方在构造期建好的 Node**，字符串一旦摊进 `@ui.text("名称")` 就与语言无关了；演示板的两个对话框挂在窗口根、不在路由树上，`localize_remount` 管不到它们 → 切英文标题里的正文仍是中文。补通用一条通道：`@widget.localized(build)`——内部一个 `Store[Int]` 订阅 i18n 广播，广播时 `bind_node` 原位换一棵新树。对话框各套一层即可（开着的那层按可见性 Store 重开，内容换成新语言）。口径写进注释：这条只给**建一次用到底**的常驻外壳用，别塞进反复建拆的循环（监听随进程常驻，不随节点注销）。
- **验证**：`cd gui && moon check` 零错误零警告；库门禁 `moon test widget ui style theme render i18n router shell base mdview` **588/588 全绿**（新增 `localized` 重建、验证消息换语言、Markdown 行距三条）；`examples/showcase` `moon build` 零警告、`moon test shared` 3/3；覆盖率门禁八条通道全绿、目录 934 条。**待真机**：`moon run examples/showcase` → ①表单页「表单校验」：空值提交看红字，切英文红字变 Required / At least 2 characters / Not a valid email；②代码文档页「Markdown 渲染」：逐行之间有明显呼吸，段与段之间留缝；③反馈页两个对话框（删除确认 / 新建连接）切英文后标题、正文、按钮全英文，开着时切语言会按新语言重开。

## 下拉弹层被窗口底边切掉：浮层开出来还要按图层边界收位（2026-10-21，macOS arm64 真机反馈）

- **报障**：表单页「Select 与 ColorPicker」贴近窗口底边时点开下拉，候选列表最后一项贴着窗口底边只剩半截——「下拉这种弹出会被窗口吃掉」。
- **根因**：`overlay_show_at` 只把包裹层摆到「锚点下缘 + 2」，而弹层画在**整窗浮层图层**上，图层就是裁剪框，越出窗口的那部分像素直接没有。列表侧原有的「超 300 高套一层滚动」只保证**弹层自身**不超高，管不了「锚点离底边只剩十几像素」；`popup_place`（原生档弹层窗的翻边规则）也只服务原生档那一扇窗，图层档没人调它。
- **修（补共用机制，不按组件各修一遍）**：`gui/widget/overlay.mbt` 新增纯函数 `popup_fit(x, y, w, h, bounds_w, bounds_h, anchor?)`——放得下不动；下方不够就翻到锚点上方（间距从「请求位 − 锚点下缘」里还原，翻上去同间距）；右方不够就与锚点右缘对齐；翻完仍越界（弹层比窗口还高）钳回边界内，宁可压住锚点也不切内容；边界给 0 视为未知，一律原样。`overlay_show_at` 在「内容挂进包裹层 + append 图层」之后多跑一轮 `relayout` 量出实测尺寸，收位后再布局一次——弹层尺寸必须挂载并布局才量得出，与原生档「先开框、量完再收框」是同一条口径。新增可选 `anchor? : Rect?`，各锚点浮层（popover / dropdown / tooltip / select / 取色 / combo / 日期时间四处）把触发件矩形传进去；右键菜单与轻提示没有锚点语义，只吃钳位那一半。
- **两条坐标坑**：① 请求位是窗口坐标、包裹层的 left/top 是图层局部，`popup_fit` 全程在局部系里算（锚点同样先减图层原点），两个系混进一次比较就会错开一个图层宽；② tooltip 的锚点要在**排延时之前**把 `Rect` 抄出来——定时回调捕获控件本体是引用环（老坑），而翻边用的矩形必须与请求位同源，否则算出的间距是别的帧的。
- **验证**：`gui/widget/overlay_wbtest` 新增 `popup_fit` 六情形纯函数用例（原样 / 翻上 / 翻左 / 钳到 0 / 无锚点只钳 / 边界未知原样）；`ui/overlay_wbtest` 新增「下拉贴窗口底边翻到锚点上方」端到端一条。**回退验证**：把收位结果改回写请求位（等于不翻边），该条即红并打出「没翻到锚点上方：弹层底 376 / 锚点顶 260」——切掉的正是真机上那 76px。`cd gui && moon check` 零错误零警告，库门禁 `moon test widget ui style theme render i18n router shell base mdview` 591/591 全绿，`examples/showcase` `moon build` 零警告；中英文档「浮层与消息」段补上这条收位承诺。**待真机**：`moon run examples/showcase` → 表单页滚到底边点开「下拉选择」与「取色」，看候选整块翻到字段上方；日期/时间弹层同看；再点靠近右缘的字段，看弹层与字段右缘对齐；顺手确认贴顶边的字段仍朝下开（不该无脑翻上）。

## 表单校验红字画成黑色：不进样式槽的散参数颜色要在绘制期落色（2026-10-21，macOS arm64 真机反馈）

- **报障**：表单校验的错误文案颜色是黑的，不是红色。
- **根因**：`form_item` 的错误行走 `text_dyn(..., color="danger")`，而 `text_dyn` **不像 `text` 那样把散参数 `color` 折进样式槽**：`text` 那条是 `fg_block` → 样式槽 → 绘制期 `resolve_color(Var("danger"))` → 主题 hex；`text_dyn` 把串原样塞进 `TextSource.color`，`src.fg()` 又原样返回 `"danger"`，交给只认 hex 的文本层解析（`@render.Color::parse` 逐字符吃十六进制，`n` 一位就 `None`）→ 回退 `{0,0,0}` 黑。同一条取色口还管着 `bind`/`bind_label` 的 `color="text_secondary"`，凡散参数写 token 名都是黑字；样式表里那条 `form_error_base`（`color="danger"`）从来没接进这条链，所以缺陷一路活到真机。
- **修**：`TextSource::fg()` 出口统一落色——空串照旧按角色现取主题色，给了串的过一遍 `parse_color` + `resolve_color`：hex 与命名色原样（与样式槽那条同口径），token 名在**绘制期**现取当前主题，换主题/暗色当场跟着变、不固化。修在这一处而不是给 `text_dyn` 补折块：`fg()` 是所有 `TextSource` 绘制路径的唯一取色口，`bind` 那条一起受益，也不必把 `text` 已有的折块改第二遍。
- **验证**：`ui/basic_wbtest` 新增「文本散参数给 token 名：绘制期现取主题色，不落黑」——内存位图画一遍，数红通道压过绿蓝的墨像素；判据吃的是颜色像素，所以先拿 `#ff0000` **探一次管道**（本机文本层能否把 hex 落进位图），落不进去的平台打印跳过，不给假红。**回退验证**：把 `fg()` 改回原样返回串，该条即红并打出「红像素=0 黑像素=313」，与真机看到的一致。`cd gui && moon check` 零错误零警告、库门禁 591/591、`examples/showcase` `moon build` 零警告。**待真机**：`moon run examples/showcase` → 表单页「表单校验」清空必填项看错误文案是 danger 红；切暗色主题看红跟着主题走；切英文仍是同一条红字（消息换语言、颜色不换）。

## 日期段那条长期红测：判据咬错了量（Linux 19/17 是折行档行带，不是折行）（2026-10-21，按 CI 数字定案）

- **现象**：`ui/datepicker_wbtest.mbt:340` 在 Linux CI 上长期红、mac 本地绿。上一轮把四个量打进失败消息，这轮 CI 给出：标签高=19 值高=17 盒宽=45 测量宽=45。
- **定案**：盒宽 == 测量宽 ⇒ 文本一行放得下，**根本没折**（真折行会是 ~34）。差的 2px 只能来自两条标签的测量档不同（同字号 13、同字族、同单行）：`text(role=Body)` 默认折行，带父给的宽度约束去量；`bind_label` 不折行，走自然宽度档。也就是说 Pango 在「set_width + WRAP_WORD_CHAR」那档用 `pango_layout_get_pixel_size` 报出的单行行带比自然档高 2px，CoreText 两档刚好相等。
- **结论：判据写错了量，不是实现坏了**。这条用例要守的是「标签别折行、别压住 picker」——mac 上真实坏过（测量宽四舍五入报窄 1px → 折成两行 → 变高的盒行内垂直居中，把首行墨迹骑到 picker 下缘）。「两条盒高相等」从来不是这条缺陷的判据，只是 mac 上的巧合，拿它当判据就把 Linux 永久钉红。改成按**本平台自己的单行高**（值标签）算尺子：标签盒 ≥ 两倍单行高即折行；「选中行不压 picker」那条照旧。折行时新判据同样红（34 ≥ 2×17−1），mac 行为不变。
- **验证**：`moon test ui -f "*日期段标签*"` mac 绿；**待 CI 回验**：Linux 该项转绿（这条不需要真机——CI 的四个量已经足够定案）。

## 居中档输入格只挪字不挪光标：起点一处算、三处共用（2026-10-21，Windows 真机反馈）

- **报障**：步进器的数字和光标位置对不上。
- **根因**：`gui/ui/entry.mbt` 的居中档是**半条路**——绘制时按样式槽 `text_align=Center` 把整串挪到盒中线，光标却仍按 `pad + 前缀宽` 画，选区底色与点击命中（`byte_at_x`）也按左对齐算。步进器数值格正是居中档（`width=44` + `text_align=Center`），于是数字在中间、光标钉在左边。原注释写着「光标/选区仍按左对齐口径，短数字格的显示居中就够用」——「够用」不成立，用户一眼就读成错位。
- **修（一个起点，多处共用，不按组件补）**：把居中换算抽成 `origin_x(self, txt)` 与 `shown_origin(self)`（空框画占位符时按**占位符**宽度定起点，光标也贴它开头，不落在盒中线空处）；文本、光标、选区、组合串 preedit、`im_cursor`（输入法候选窗落点）、按下与拖拽的字符命中（`byte_at_x` 的 inset 参数）全部走同一个 `shown_origin`。左对齐档返回值就是原来的 `pad`，那条路径行为不变。
- **验证**：`ui/entry_wbtest` 新增「居中档：光标跟着文本起点，不钉在左内边距」——经 `im_cursor` 拿光标矩形，判据两条：「光标 = 盒中线换算后的串尾」且「与老位置差出 >8px」（120 宽盒、22px 串：新 71 / 老 26，差 45）。**回退验证**：把 `origin_x` 短路成 `pad`，该条即红并打出「光标=26 期望=71」。`cd gui && moon check` 零错误零警告、`moon test ui` 208/208（步进器既有用例全过）。**待真机**：Windows/mac 点步进器数值格，光标贴数字末尾，打字、方向键、鼠标点选都跟手；空框有占位符时光标贴占位符开头。

## 滚动条改浮层档：轨道不画、拇指淡档 15%、悬停视口满色（2026-10-21，使用者定的形态）

- **报障**：侧边菜单被滚动条遮挡一部分，想要「悬浮显示的滚动条」，问现框架能不能做。
- **本来就有的一半**：滚动条早就是视口的**绝对定位子控件**（贴右缘、压在内容之上、不占布局宽度、命中也归它），缺的只是「不常驻」。用到的原语全在库里，零新依赖：`Painter::set_global_alpha`（对话框遮罩在用）、宿主按祖先链派发的悬停态（`hovered` / `on_hover_change`，与 CSS `:hover` 同义，指针在子项上时父项也算悬停）、`invalidate()`。
- **定下来的形态**：轨道整条不画——那条 `fill_zebra` 灰带正是压住侧栏右缘的东西；拇指两档，平时 **15% 不透明度**（不留 0%，否则长列表里完全看不出滚到哪），指针进入视口或按住拖动时提到满色。显形位挂 `ScrollState.bar_hot`，由 `scroll_bar_hover(viewport, state)` 一处接线；`scroll_view` / `virt_list` / 吸顶列表 / 多行框四处共用同一条 `scroll_bar`，各接一次即全变。
- **不做定时器（使用者定的）**：少一个常驻 timer 与一轮淡出重绘，代价是「手一移开就落回淡档」而不是过一会儿再淡；换来的是零状态泄漏（页面反复建拆不留悬挂回调），也不必给每个滚动容器配回收袋。
- **验证**：`ui/scroll_wbtest` 新增「滚动条浮层档：不画轨道，悬停视口拇指提亮」，三条判据：拇指之外露内容行底色（轨道确实没画）、淡档落在「内容底色 → 满色」之间（既不是满色也不是没画）、`root.set_hover(vp.id)` 后同一点位等于主题 border 满色。**回退验证**：把轨道画回去、淡档设成 1.0，该条即红并打出 `(245,247,250) != (51,68,85)`（fill_zebra 盖住了内容）。`textarea_wbtest` 的「滚到底拇指与轨道换位」判据在浮层档下语义不变（顶格回到内容底色），只改注释。`cd gui && moon check` 清缓存重编零错误零警告、库门禁 593/593、`examples/showcase` `moon build` 零警告；中英文档 `scroll_view` 行同步改写。**待真机**：`moon run examples/showcase` → ①侧栏右缘不再有灰带，进侧栏拇指亮起、离开落淡；②段正文与图表区同看；③多行框、虚拟列表拖拇指仍跟手；④暗色主题下淡档仍可辨。

## 字距（`letter_spacing`）：样式层有字段、测量与绘制没人读（2026-10-22，macOS arm64）

- **现象**：`Style.letter_spacing` 从 P1 起就在样式槽里（`style.mbt:14`），`set_letter_spacing` / `text` 的散参数都能写进去，但 `gui/style` 之外零处消费——写多少都不影响量宽与字形间距，等于死字段。
- **根因**：字距是「度量」属性而不是「绘制」属性，必须进 `Font` 才可能同时被布局（yoga 的 measure 回调）与绘制（`draw_box_at`）看到；而 `Font` 只有四要素，`font_key` 也只哈希这四者，直接往后端传参数而不进 `Font` 的话，同串不同字距会命中同一条缓存宽度（错宽度比不生效更难查）。
- **修**：`Font` 加 `spacing`（`Font::new` 的可选参，默认 0.0）；`font_key` 与 `measure_cached` 的键加上它；`pt_measure` / `pt_measure_font` / `pt_draw` / `pt_draw_box` / `pt_draw_box_cr` 五个 extern 各加一个 `double spacing`（紧跟字体参数之后）；`ui/base.mbt` 的 `text_eff` 读 `st.letter_spacing` 折进它建的那份 `Font`——这样测量与绘制两条路吃的是同一个字段，不需要第二处接线。
- **三平台原语与口径差异**（这是本条最费劲的地方，三种实现的「每个字加几份」并不一致）：
  - Pango：`pango_attr_letter_spacing_new(units)` 挂 attr list，只加在真的 `spacing != 0` 时（不挂 attr 的路径与改动前逐位同源）；布局缓存键加上 spacing。
  - DWrite：`IDWriteTextLayout1::SetCharacterSpacing(leading, trailing, minimumAdvanceWidth, textRange)`——**四参，不是三参**：第 4 个 `DWRITE_TEXT_RANGE` 少给会 C2660「函数不接受 3 个参数」（Windows 首次真机编译就是这么挂的）。**只给 trailing**（`(0, S, 0, {0, 整串 UTF-16 码元数})`）——leading+trailing 都给会变成字间加两倍；只给 trailing 时每个字各加一份，整串宽 = 自然宽 + 字符数 × S。range 长度必须用 `MultiByteToWideChar` 数出来的码元数，不能拿 UTF-8 字节数（CJK 会多算一倍多）。
  - CoreText：`kCTKern` 挂整行。原以为它只管「字与字之间」，末字那一道要自己补，先按「kern 补偿 + 量宽时加 n×S」写了一版，**实测宽度增量是期望的两倍**：13px 下 S=1 时 `"a"/"ab"/"abc"` 的增量是 2/4/6、`"中文测"` 是 6，即 kCTKern **对每个字各加一份（含末字）**，已经就是 CSS 口径。补偿撤掉后增量恰好是 字符数 × S。结论记在这里：CoreText 的 kern 值就是逻辑像素、按字计，不要当「字间一对」去算。
- **验证**：新增 `gui/text/spacing_wbtest.mbt` 三条——①`"a"/"abc"/"中文测"/"hello world"` 在 S=1/2/4 下量宽差 = 字符数 × S（允许 1px 上取整误差）；②绘制同源：同串同原点，spacing 8 的墨迹右界严格大于 spacing 0（证明绘制那趟也吃到了字距，而不是只有测量被骗过去）；③同串不同字距不串缓存。`cd gui && moon check` 零错误零警告、库门禁 1121/1121。**待真机**：Linux（Pango）与 Windows（DWrite）各跑一次上面三条，读数应同为「字符数 × S」；观感项是 showcase「画布与富文本」页「字体」段的「字距 0 / 4」两行。（2026-10-22 Windows 首次编译：三参调用报 C2660，按四参补 `DWRITE_TEXT_RANGE` 后待复验。同日 Linux CI 的 `spacing_wbtest` 红（实测差恒 0）：属性挂在 `set_text` **之前**作用在当时的空文本上，Pango 不吃到——已改为 set_text 之后再挂，待 CI 回证。）（2026-10-30 CI 再红、本机复现，根因是最后一处口径差：**Pango 的 letter_spacing 只落在字与字之间，末字不加**——探针实测增量 = (字符数−1)×S、单字符恒 0，而 DWrite trailing 与 CoreText kCTKern 都给到 字符数×S。测量出口处补回一份 S（`pt_measure` / `pt_measure_font` 两处，`len > 0` 才补），三平台测量总量同口径，三条 wbtest 全平台绿。）

## 虚线（`set_dashes`）：Painter 状态没有 dash，两后端也各缺半边（2026-10-22，macOS arm64）

- **现象**：`Painter` 的线型状态只有线宽/端点/拐角，没有虚线；想要参考线、分隔带、选中框这种「虚线框」只能自己按段拼 `move_to/line_to`。
- **已有的半边**：`render/stub.c` 的 cairo 分支早就有 `cr_set_dash(id, double*, n, offset)`（只是 MoonBit 侧没人声明，属死代码）；纯光栅器一侧完全空白——`Raster::stroke` 是 `stroke_polys(path.flatten(m), lw)`，没有「按弧长切段」这一步。
- **修**：`PainterState` 加 `dashes` / `dash_offset`（`snapshot` / `load_state` 同步拷贝，数组要 `copy()`——结构体是引用语义，浅拷会让 `save` 之后的 `set_dashes` 改到栈里那份）；`Painter::set_dashes(pattern, offset)` 做口径归一（负值按 0、全 0 或空 = 回实线，避免 cairo 报 invalid dash）后下发后端。
  - Cairo：新增 `cr_dash_begin/add/end` 三段式，C 侧静态暂存 16 段再一次性 `cairo_set_dash`。**不走 `FixedArray[Double]` 直传**——MoonBit 数组当 `double*` 传 C 在这个仓里没有先例可依（只有 `FixedArray[Byte]` / `Bytes` 的既有用法），暂存式与渐变 stop 的三段式同形，风险最低。
  - 纯光栅器：`Raster` 状态同样带 dashes/offset；`stroke` 先把折线过 `dash_polys`（新增于 `raster_path.mbt`，按累计弧长在段内线性插值切点），再交给 `stroke_polys` 走常规描边——切出来的都是开口折线，段端自然落 butt 端帽，与 cairo 的虚线语义一致。
- **口径（TODO 里原来待定的两条，这里定死）**：①相位在**每个子路径起点重置**（cairo 的 dash 状态机就是 moveto 时 reset，两后端才能逐段对上）；②闭合子路径**不绕回补相位**，首尾接缝按图案留缝，不强行对齐成整周期。图案里出现 0 长段时状态机跳过（带 n×4+8 的步数上限防死循环）。
- **验证**：新增 `gui/render/dash_wbtest.mbt` 五条——段数与周期（100px 线 + `[10,10]` ⇒ 5 段、段长 10、起点 5、周期 20）、相位偏移（offset=10 ⇒ 首段起点 15）、`set_dashes([])` 回整条实线、闭合矩形按图案断段、虚线进 `save/restore`。库门禁 1126/1126。**待真机**：Linux cairo 档同一图案的段落数与首段长度应与上面读数一致（这是两后端唯一的交叉校验点，mac 上跑不到 cairo）。
- **已知边界**：只作用于 `stroke` 的路径档——`stroke_rect` / `stroke_round_rect` 在两后端都是「内侧边带填充」，不吃 dash（要用虚线框就自己 `move_to/line_to` 走路径档）。

## 背景透视：三个平台各有一道「第二开关」在丢 alpha（2026-10-22，Win32 / GTK 补口）

- **同一件事的三个化身**：透视要的是帧里的逐像素 alpha 真到达屏幕，而三个平台都还有第二道门在丢它——AppKit 看**视图**的 `isOpaque`（NSView 默认 YES，窗口设了 `opaque=NO` 也没用），Win32 的 `StretchDIBits` 走 `BI_RGB` 时**忽略第 4 字节**，GTK 的 visual 不是 32 位时 cairo 直接把 alpha 拍平。三处都验证过「只开窗口级那个开关 = 什么都没发生」。
- **Win32 特有的互斥**：整窗 alpha（`SetLayeredWindowAttributes` 的 `LWA_ALPHA`）与逐像素 alpha 共用同一个 `WS_EX_LAYERED`，一次只能用一种。两个门面各管一摊的写法会让它们互相顶掉——先开透视再调 alpha，透视当场消失；调回 100% 又把 layered 位摘掉，两者都失效。所以 alpha 与透视必须是**同一套窗级模式**，由最近一次设置决定谁在管这个位。
- **约束**：Win32 的逐像素提交面就是**整窗内容**，只有「客户区 == 整窗」（无边框）时成立；带边框的窗只能退回整窗 alpha，这也是透视窗的真实形态。GTK 的 visual 只能在 realize **之前**选上，所以它是建窗动作、不是开关动作——等 `set_transparent_bg` 来了再补必然无效。
- **GTK 另半条**：`app_paintable` 只关掉 GTK 自己画底，visual 不换照样不透；切完还要主动 queue_draw，GTK 不会因为 paintable 变了就把旧底清掉。
- **待真机**：Windows 无边框窗上「透视 + 25% alpha」叠用（洞仍透出桌面、卡片一起变淡）；带边框窗点透视应当无变化。Linux 分 X11（有/无合成器）与 Wayland 各跑一次透视窗。

## vendor 镜像有三份副本，不是两份：`gui-media` 被漏在名单外（2026-10-22）

- **现象**：`miniaudio.h` 明明配了 Gitee 镜像，国内网络下却总是退回 GitHub 硬碰；而且只有单源 socket 超时，遇到滴流时一次构建可能吊死在第一个源上。
- **根因**：vendor 下载逻辑在仓库里有**三份**——`modules/gui-webview/prebuild.py`、`modules/gui-media/prebuild.py`、`modules/ffmpeg-mbt/prebuild.py`，刻意不共享（每个模块都要能独立发布）。2026-10-18 那轮「并行竞速 + 60 秒总预算」只改了点名的两份（ffmpeg-mbt / webview），`gui-media` 不在名单里，于是它的 Gitee 地址一直写着 `lb091188`（**404**，同一个仓在 Gitee 归 `noahliu0911`），超时也一直只有那个 socket 级的 20 秒。
- **为什么长期没暴露**：GitHub 通的时候一切正常，404 的镜像只是被静默跳过；而文档里「两处刻意各留一份」这句写得越肯定，越没人会去数第三份。
- **做法**：改 vendor 的镜像或超时口径时，先用 `grep -rn "releases/download/vendor-v1" --include=prebuild.py .` 点清份数，别信文档里的「两处/三处」。三处已统一为：Gitee 用户名 `noahliu0911`、单源 socket 20 秒 + 总预算 60 秒（ffmpeg 的大归档另按体积放宽到 360 秒）。
- **实测**：把 `modules/gui-media/media/miniaudio.h` 移走后用 `NATIVE_GUI_VENDOR_BASE=<gitee>` 跑 `ensure_miniaudio()`，命中 Gitee、sha256 通过、4 MB 落位。

## 授权文件只有一份，且必须是 `docs/` 下的页面（2026-10-22）

- **根因**：VitePress 的 `cleanUrls` 会把页面里的 `[x](/THIRD-PARTY-NOTICES.md)` 改写成 `/THIRD-PARTY-NOTICES`，而 `docs/public/` 下的静态资产原名带 `.md`，于是「放 public 当原始文本」这条路线上链接必 404（实测线上 `/THIRD-PARTY-NOTICES` 404、`/THIRD-PARTY-NOTICES.md` 200）。想让两种写法都通，只能是 `docs/` 根下的页面：改写后的 `/THIRD-PARTY-NOTICES` 按 clean URL 命中 `THIRD-PARTY-NOTICES.html`。
- **判据**：文件内的仓库引用一律写 GitHub 绝对 URL（`blob/master/...`）——页面按 `docs/` 解析相对链接，`LICENSE`、`examples/README.md` 这类同层路径会指空。仓库根不要再放副本，也不要再塞进 `docs/public/`。
## Cloudflare Pages 的子域在创建项目时选定，重命名项目不换域名（2026-10-15 实测）

- **根因**：`<项目名>.pages.dev` 在创建那一刻写定，后台没有改名入口；本仓试过「重命名旧项目占住新名字」，域名仍是旧的 `moonbit-libyue.pages.dev`，最后只能新建项目再删旧的（旧域随之成死链，站内链接已全部改指 `moonbit-native-gui.pages.dev`）。
- **判据**：要换 pages.dev 域名只有「新建项目」与「挂自定义域」两条路，重命名不是。

## 单实例补齐三平台：Win32 互斥体 + WM_COPYDATA、POSIX 套接字臂，门面落 `shell`（2026-10-22，Win32 / macOS / Linux）

- **门面落位判据**：跨平台单实例的门面放 `shell/instance.mbt`（与 `Tray` 同制：shell 已同时引 `win`/`dbus`/`sys`），**不新建 `gui/instance` 包**——`dbus` 依赖 `sys`、反向不成，门面若引 `dbus` 又落在 `sys` 或 `dbus` 里都会把依赖方向拧断；新建包还要动 prebuild 与门禁清单，收益只有目录好看。
- **Linux 无 SOCK_NONBLOCK 差异不露脸**：`dbus_stub.c` 的 POSIX 支在 `_WIN32 || __APPLE__` 编的是失败桩，`SOCK_NONBLOCK|SOCK_CLOEXEC` 从没在 macOS 上编译过；新的 `shell_stub.c` 要在 macOS 真跑，两个标志都不能用，一律 `socket(AF_UNIX, SOCK_STREAM, 0)` + `fcntl(F_SETFL, O_NONBLOCK)` + `fcntl(F_SETFD, FD_CLOEXEC)`。判据：凡要在 macOS 编的 socket 代码，创建标志只用 `SOCK_STREAM`，非阻塞与 CLOEXEC 走 fcntl。
- **唤起通道不能等回执**：同进程自测时「发一条唤起」与「抽一条唤起」是同一个线程，发端阻塞等 ack 就是自等——实测 `poll` 满 3 秒给 `errno=60 (ETIMEDOUT)`。改成写完即 `shutdown(SHUT_WR)`、帧边界用 EOF 表达，收端下一拍读到 EOF 即成帧。判据：套接字臂的 wake 只保证「已交给内核」，不保证「已被对端抽走」（与 D-Bus 档的同步应答同级，别再往回加 ack）。
- **`FindWindowW` 查不到消息窗**：`HWND_MESSAGE` 下的窗不进顶层窗枚举，跨进程按类名找不到（本仓的托盘窗 `yue_wm_tray` 就是消息窗，只能同进程用）。单实例的接收窗必须是**顶层隐藏窗**（`WS_POPUP`、不给 `WS_VISIBLE`）。判据：跨进程按类名/标题找窗的，一律建顶层窗；`adaptation/windows.md` 里「单实例消息窗口是仓内首例自有 WNDPROC」是旧 libyue 链的说法，本仓自有 WNDPROC 已有 `wm_wndproc`、`wm_tray_wndproc` 两处。
- **同进程二次 `CreateMutexW` 也回 `ERROR_ALREADY_EXISTS`**：幂等不能靠返回码，必须靠 static 句柄守卫（守卫在前，返回码才有意义）。
- **sun_path 有硬上限**：macOS 104 / Linux 108，超长时 `bind` 直接失败而不是截断。判据：套接字路径由门面按 `SOCKET_PATH_LIMIT=100` 预算反推 slug 长度（目录长就截短），并且文件名带 uid——`/tmp` 是多用户共享目录，不带 uid 会让 B 用户把 A 用户的实例认成自己的。
- **判活用的空连接会把「待抽槽」占死**：套接字臂的 `instance_claim` 判「有没有人在听」靠连一下就关，收端因此会先收到一条**零字节帧**；单槽待抽位若被这条空帧置位又不清（`take` 见长度为 0 就早退，没清标记），后面那条真帧永远抽不出来——`yi_inst_poll` 恒回 1、载荷恒为空。判据：读到 EOF 时按帧长分流，零字节只关连接不置位；`take` 一进就清位。实测（macOS 双进程探针）：修复前首实例 `done wakes=0`，修复后两条唤起按序落地 `wake #1 / wake #2`。
- **`String[i]` 拿到的是 UTF-16 代码单元，不是 `Char`**：拿它 `.to_string()` 出的是十进制数（`'0'` 位写成 `digits[i].to_string()` 得 "48"，8 位十六进制哈希实测变 17 位），编译不报错、只有测出来的长度不对。判据：按码点处理一律 `s.to_array()` 或显式字符串表；`s[i]`/`unsafe_get` 只用于比较。
- **验证**：本机 macOS `moon test -p NoahLiu/native-gui/shell` **54/54**（新增 7：slug 与哈希、路径预算、帧往返、解码防御、套接字臂同进程自环、判活空连接、门面端到端），全量库门禁 1134/1134、`moon check` 零警告、`moon build examples/showcase --target native` 通过；`experiment/instance_probe`（hold/wake/self 三档命令行探针）在 macOS 真双进程跑通「第二个进程判到 existing → 唤起送达 → 首实例按序收到」。CI Windows job 870/870（含 win32 档的门面自环：互斥体 + 隐藏窗 + WM_COPYDATA 全链）、Linux 只剩既有的 `text/spacing_wbtest` 一条红（与本批无关，前一版 master 同样红）。**待真机**：Windows 双进程防多开与置前、Linux 双进程 dbus 档、Linux 拔总线后落 socket 档。



## 组件「缺省跟随容器宽」的布局语义：yoga 的「不设宽」在主轴是内容宽（2026-10-24,真机「resize 后内容不重排」定位）

**现象**（用户 mac 真机）：拖窗口宽度，showcase 右侧内容不 reflow（图标不换行、markdown 不重排）。**LAYOUT-FRAME 诊断读数（NATIVEGUI_LAYOUT_LOG 门控，paint 帧宽度变化时打一行）证明框架的 resize→relayout 链路全程健康**（拖动中 w 逐级更新、每帧 relayout），现象全部出在内容侧定宽：markdown_view 演示写死 width=480（构造期定宽）、icon_grid 手工按 per_row 分行（已改 flex_wrap）、code_view 按最长行定宽（已改 percent 100）。
**库级语义定案**：**块级组件不显式设宽 = 跟随容器，必须显式 `set_width(@yoga.percent(100.0))`**——yoga 的「不设宽」在交叉轴（col 里的子项）是 stretch、在主轴上是内容宽，组件内部无法预知父形态，percent 是唯一任何父形态都跟的写法。`input` 的 `width?=0`（不传不定宽）就是这个语义的既有范例。
**mdview 响应式改造**：段落折行产出 Ref 化，跟随模式下节点挂 `set_measure`（yoga 布局时按可用宽问高度）——宽变即重折，折行缓存按 limit 失效，零 resize 监听；显式 width 保留静态路径（构造期折一次、定宽定高，wbtest 旧用例零回归）。`markdown_view` 的 `width?` 缺省从 560 改 0（跟随）。
**教训**：① 「resize 后不重排」先拿 LAYOUT-FRAME 读数分层（事件/账本/布局/内容四层各一段证据），不要从视觉直接跳框架结论；② yoga 尺寸语义按轴理解——「auto」永远先问内容，跟随是显式选择（stretch/percent），组件作者不能假设父的轴向；③ 生成脚本生成的页面改布局，脚本模板要同批改（icons.mbt 与 gen_showcase_icons.py 双改）。
**验证**：mdview 33/33（显式 width 用例零回归）+ ui/mdview 合跑 247/247；全量库门禁 1152/1152、`--deny-warn` 干净。真机（showcase「代码文档」页拖宽度 markdown 重排、图标库 wrap 重排）归用户。

## 布局语义补全：不可折内容「内容宽 + 横滚」（2026-10-24,「最小宽应该有滚动」决策)

**决策**：窄窗时「最小宽 + 横向滚动」与「收缩 + 折行」并存，按内容可折性选——可折内容(文本/段落)跟随容器折行；不可折内容(代码长行/表格列宽)内容宽撑开 + 外层横向滚动，不裁字。落地：ScrollState 扩横向三件(offset_x/content_w/view_w + apply_x)，`scroll_view(hscroll=true)`——content `align_self FlexStart` 退掉交叉轴 stretch、不收缩、`left = -offset_x` 平移(与纵向下移同机制)；横条底缘浮层(纵条镜像)；滚轮 dx/触控板横滑先消费横向余量。mdview 三处代码块与 showcase section 代码块接 `md_code_scroll` 包裹。
**坑**：① yoga `set_align_self` 收 `AlignItems?`(Some 包裹)，与 set_align_items 的非可选不同；② scroll_view 的描边只在「纵向可滚」时画——横滚视口纵向不滚时无描边，代码块自带深底圆角，视觉自洽；③ 视口高 auto = 内容高(纵向不滚)，`min_height 0` 不影响。
**验证**：ui/mdview 合跑 247/247；全量库门禁 1152/1152、`--deny-warn` 干净。真机：窄窗看「代码文档」页长行代码块出底缘横条、拖动横滚；markdown 表格(表格列宽未包,随本批口径另批)。

## 文本节点「不设宽 = measure 行宽」撑破容器：折行文本必须显式 percent 100（2026-10-24,截图「段描述仍被裁」第二轮）

**上轮 cap 修复（max_width 与可用宽取小）后段描述仍单行溢出——wbtest 复现读数 `rect=891x92`（430 容器）定位到第二层机制**：yoga 对「不设宽」的 measure 节点，**节点宽 = measure 返回的内容宽**（891 = 按 max_width 900 折后的最长行）——measure 的折行正确、高度正确，宽却把节点撑出容器。min-content 探询（请求轴 `Some(0.0)`）同罪：按「不受约束」答 900 宽，yoga 把它当节点最小宽沿父链撑。
**修复两件**：① min-content 探询改语义——wrap 文本按「最窄可折」答（`max_width=1` 箱折，宽 = 最宽不可断单元，高答单行）；不折文本照常答整行（行内标签的 min-content 本来就是整行）。② **折行文本（`wrap=true`）节点显式 `set_width(percent 100)`**——折行文本必然是块级内容（折行宽度离开容器约束没有意义），单行标签保持按内容宽占位（标签形态）。**库级语义补全**：块级组件跟随容器必须显式 percent，「不设宽」任何轴上都先问内容。
**教训**：① measure 回调「被调且折行正确」不等于「节点尺寸正确」——yoga 用返回的 w 定节点宽，返回值本身就是布局输入，读数（`rect=891x92` 的宽高不自洽）是拆穿它的唯一手段；② 探询与正式测量是两次不同约束的调用，语义要分开答。
**验证**：复现用例入 wbtest（430 容器、900 上限、380 字长句：`rect=430x92`、多行），ui 215/215；全量库门禁 1153/1153、`--deny-warn` 干净。真机段描述/各页文本折行归用户。

## 「段描述吞字」第四轮：内在探询与 percent 参照的三处口径漏（2026-10-26,用户「还是固定宽」+「表格 resize 不更新」）

上轮（mac 折行器孤测低估联排实宽）只收了半条链，这轮三处同源的「拿常量/探询值当布局输入」：

**① yoga 子项基准混用「基准」与「落地尺寸」**。子项主轴基准此前一律取 max-content 内在值（YG3d 定案，为的是弹性收缩算得到溢出量）。但**交叉轴已确定**时，该项的真实主轴尺寸是「按那个定宽量出来的内容尺寸」，不是 max-content——定宽折行文本因此高按单行落地（探针：容器 661、measure 已答 28，`size_main=14`）。修成三档：显式尺寸/比例 → 用它；交叉轴确定 → 按定宽量得值（`algorithm.mbt` 里 `content` 那一趟本来就已带 `c_avail_cross` 量过，容器还会递归，故文本叶子与「percent 宽 + auto 高」的嵌套容器同时受益）；交叉轴不确定 → 仍 max-content。反向守卫两条用例钉边界（撤修复只有第一条红：`10 != 20`）。
**结构性债（记下未做）**：叶子子项没有自己的布局趟——`algorithm.mbt` 里「有子节点 → `layout_into(pinned)`，无子节点 → 直接赋 `layout_width/height`」，所以叶子的尺寸完全由父级在交叉轴未知时算好的数决定，缺了真 yoga「measure 以 resolved 交叉宽、exactly 模式再调一次」那一趟。① 的收口盖住了当前所有已知形态；残余风险是「交叉轴事后被拉伸改变而主轴位置已按旧值算过」。补那一趟要给每帧布局加量（内在尺寸已记 +40% 成本），等打出第二个具体反例再动。

**② 横滚内容没有视口下限**。`scroll_view(hscroll=true)` 的内容只有自然宽（`align_self FlexStart` 退 stretch），于是内部 percent 子项（markdown 表格的等分列）参照的就是那个自然宽——resize 后列宽纹丝不动、溢出部分滚不回来（无头对照：段落 900→500 跟得动，表格列冻在 560×3=1680）。修：内容补 `min_width percent(100)`，即「内容宽 = max(自然宽, 视口宽)」。A/B 证明这条与 ① 无关（把上批 yoga 提交退回旧版，读数一字不差），是 43791a59 那批「表格包横滚」留下的参照缺口。

**③ 富文本 max-content 探询兜了常量 560**。`md_rich_label` 在 `aw` 拿不到时把限宽兜成 560（与 markdown_view 默认宽同源），这个值顺着「单元格自然宽 → 行自然宽 → percent 列参照」传导并冻住整张表。内在探询必须答**自身最长行自然宽**，任何常量都会变成假参照。

**教训**：内在尺寸探询是规范必需（§4.5 min:auto、flex-basis:auto、fit-content、溢出量算术都要它），缺陷从不在「有探询」，而在**把探询值当成落地尺寸或参照**——判据是同一条：凡进入布局算术的数，必须来自「当前确定约束下的实测」，不得来自常量兜底或另一档约束。

**接口口径改定**：不可折内容自带横滚视口——`code_view` 本体包 `scroll_view(hscroll=true)`（视口高即内容高，纵向不滚），`md_table` 同理，`md_code_scroll` 助手撤除。此前每个调用点都要记得外包，漏了就裁字；「组件缺省跟随容器」与「不可折内容自带横滚」两条语义至此对称。

**min-width 被「自然宽」顶掉**：横向档的内容宽原本是 `max(子项自然宽, 视口)`，而子项自然宽会逐层上浮——自带横滚的宽代码块（画布 `min_width=最长行`）把它顶到外层，用户设 `min_width=400` 实测得 **806**，即「设了不生效」。滚动容器本不该让内容宽决定自己的宽（CSS 里 scroll container 的 min-content 为 0 就是这个意思），故横向档拆两档：自然宽档（不可折内容用）与**下限档** `min_content_width`（`max(该值, 视口)`，不看子项宽）。判据补一条：**min-width 的语义是「取大」，参与取大的只能是「容器给的宽」与「这个下限」两个数；任何第三个数（尤其是内容自然宽）挤进来，用户设的值就静默失效。**

**下限档仍不够（同批第二轮）**：`max(下限, 视口)` 里那个「下限」在引擎侧还被绕过了一次——交叉轴走「确定值」分支时直接采纳、**没过 min/max 夹取**（`final_cross = v`），而 `width: percent(100)` 恰好在「确定值」这一档，于是 `width:100% + min-width:400` 在 300 宽的容器里得 300。规范 §9.4 要求无论来自确定值还是内容都要夹取，补齐即 `clamp3(v, min_cross, max_cross)`。探针：夹取前 `300 != 400`，夹取后 400 且 `max_x=100`。**教训：一个语义要两个地方都成立——外层「不参与取大」的公式、内层「确定值也要过夹取」的算术，缺任何一个用户设的 min-width 都不生效。**

**同批追加（用户「代码块也要 flex 1」）**：`code_view` 的视口与画布都取 `percent(100)`，画布另钉 `min_width=fixed(最长行)`——只设 percent 会让长行被视口裁掉（percent 是**定宽**不是**下限**），只设内容宽则深底条断在最长行处；两者合起来才是「窄时铺满、宽时溢出可滚」。无头读数：640 容器 + 短代码 → 画布 640；400 容器 + 长行 → 画布 979 且 `content_w > view_w`。

## 换行容器的「主轴 min:auto」要按**定住的交叉宽**算（2026-10-27,真机「图标页样式烂掉 / 段不换行」）

同一处下限，两个方向都错过，根因都是**没按定宽算**：

- **旧口径**：列内可换行子项的 `min:auto` 取其 min-content 高，而 min-content 是按「无定宽时全堆叠」算的——18 个 30px 图标的网格下限 = 18 行 = 676（真值一行 30），容器白撑一大块空白，看着像「纵向堆叠 / 不换行」；段条实测 224px 挤扁正文。
- **当年的解法**：调用方补 `min_height=0`。这把下限归零了，但也把容器**钉死在一行高**——真折到第二行时超出部分被父裁掉，就是这次的「段不能换行」。
- **现在的口径**：交叉轴被定住（自身给确定交叉尺寸，或被拉伸到父的确定内交叉）时，主轴 min-content **按那个定宽量**（css-sizing：内在贡献以确定的交叉尺寸为参照）。于是一行放得下就是一行高，放不下自动长到两行，两个症状同时消失，调用方的 `min_height=0` 全部撤除。

**实现约束（踩过的坑）**：这一步只能复用**已经算过的那一趟** `content`（它带着 `c_avail_cross` 量的），不能在这里新调 `measure_content`——那对**容器**节点会递归布局并写子项 `layout_*`，在「收集子项」阶段调用会把兄弟项的尺寸就地改掉（实测同一条改动让另一条用例的宽从 100 变 150）。

**只在父主轴为列时启用**：父为行时 `c_avail_main` 是**可用宽限制**而非定宽，拿它量的值当基准会把项压窄（老用例「行容器内确定高度的内容项」正是这条守卫）。

**验证**：无头探针复刻右侧新宽度形态（hscroll 下限档 + percent 页列 + padding 段容 + 18 项网格）：900→30（1 行）、500→68（2 行）、420→68；yoga 用例改写到新语义并双向断言（1000 宽=30、300 宽=64）。yoga 106/106、库 1159/1159、`moon check` 零警告。真机：图标库页各组按窗口宽流式换行、段条折行完整可见。

## stretch 钦定的定宽要随测量链下传：min:auto 修复在「自身无宽的列」处漏了一整层（2026-10-27,真机「段条下大片空白 + 段正文高 0」）

上一条的「min:auto 按定住的交叉宽算」只覆盖**换行容器直接作列子项**。showcase 实测段条列 236（真值 66）、段视口 0，两个症状各归一处：

**症状一（段条虚高）**：段条外面包着一层自身不给宽、只靠拉伸定宽的 padding 列。父级在收集子项阶段用 `measure_content` 量这层列时，把定宽当 `avail_w`（限制）传了进去，却没当 `pinned_w`（钦定）传——该层内 `own_cross_def=None`，里面的折行孙项于是退回「无定宽全堆叠」口径（6 段 =204），下限沿父链一路上顶。**定住性不会自动传播**：它是要显式下传的测量属性。修：收集子项时，对「父主轴为列 + stretch + 无显式交叉宽」的项按 `pinned_w=父内交叉` 测（measure 缓存键同步带上 pin）；非 stretch 上下文的内在贡献仍按全堆叠的规范口径，不动。
**当时的探针为什么没抓到**：断言量的是换行容器**本体**（900→30、500→68，都对），症状在包它的相邻节点上。判据补一条：**回归要断言「症状所在的那个节点」，不是「刚改的那个节点」**。

**症状二（段视口 0）**：31c66cc8 为横滚形态把路由视图包进页级纵滚，滚动内容列 auto 高 + 不收缩 → 页列 `grow=1` 没有剩余空间可分，段自带滚动拿不到确定高（该提交前 nav.view 直挂定高主列，「段条 54 + 正文 646」形态本来是好的——这笔是回归）。修：`scroll_view` 加 `vscroll=false` 档——内容高钉视口（percent 100）、不出纵条，只留横滚档；中间包裹列补 `grow=1` 把确定高递给页列。示例侧同时把段条改 `margin=16` 直接作页列子项、页列自带 `width percent(100)`（这两条各自都能绕开虚高，与引擎修双保险）。

**验证**：yoga 新增「换行容器隔着 stretch-only 列层」两层用例（1000→30/30、300→64/64），yoga 113/113、库门禁 1158/1158、`moon check` 零警告。无头复刻真实装配（hscroll 下限档 + vscroll=false + grow 包裹列 + 页列 percent100 + 6 段，1100×700）：段条 34（含 margin 占 66）、页列 700、段视口 **634 = 700−66**。真机待复验：基础组件页空白带消失、段内自滚、窄窗段条折两行且正文高度让足。

## percent 主尺寸的 min:auto 要按内容建议收口（2026-10-27,真机「链接点击后 bind 回显不出字 / md 列表逐字一行」）

**症状**：基础页点「打开文档/帮助中心」，旁边的 bind 回显不出字，拖窗口也不回来；md 列表项逐字一行（另一根因见上批「富文本 measure 三档分答」）。
**机制**：行容器里 `role=Body` 的折行文本带 `width percent(100)`，而引擎对**内在尺寸的 min 探询**把「可解析 Percent」当确定尺寸**直取解析值**——flex 项的 `min:auto` 于是 = percent 基准本身（1100），收缩算到 1040 后又被 min 钳回 1100，行容器一挤 percent 项永远缩不动，兄弟件整件顶出窗口（探针读数：回显件 `30x15@1228`，行宽 1100）。加上组件侧折行档同时被 `shrink_by_role` 停用收缩（`flex_shrink=0`），两条路都堵死。
**修复（CSS §4.5 两半，缺一不可）**：① 引擎内在 min 探询不再直取 Percent 解析值（`Fixed` 保持直取，内容可溢出现状口径不变）；② flex 项收集时 min:auto 过「**指定尺寸建议**」收口——钳到**主轴尺寸属性**（width/height 样式）的解析值，**不是 flex-basis**（语料 F 行：basis 0px + min:auto 仍按内容下限 60，钳到 basis 会把 60 钳成 0）。两半合起来：percent 项溢出时正常收缩、遮罩这类「percent 跟宿主」的件不被自己的子项顶大。③ 组件侧 `text_dyn` 的「不参与收缩」只归单行标签档（`wrap=false`）——折行档是块级内容，行容器里必须让位。
**教训**：**同一语义三个地方都要成立**——内在探询不给 percent 顶腰、flex 收集处按指定尺寸收口、组件侧不折行才停用收缩；缺任何一处，行容器就溢出。另外「症状所在的节点」不等于「刚改的节点」：bind 无字的病灶在它左边的兄弟件上。
**验证**：yoga 新增「行内 percent(100) 项溢出时被 shrink」（基准 1100+固定 52+间隙 8 → percent 项 1040、行不溢出）；ui 新增「行容器内折行文本可收缩：bind 回显件不被顶出容器」（点击后回显件完整落行内）。全 workspace 1585/1585、`moon check` 零警告。真机待复验：基础页链接点击出字、反馈页「最近确认」出字、对话框确认有反馈、md 列表正常宽。

## 文本件口径定案：TextRole 退役进 @style 字阶预设，缺省折行 + flex 0 1 auto（2026-10-27,真机「回显不贴标签、中间一个 flex 占位」收口）

**症状**：上一批把折行档改可收缩后，基础页「最近点击：」仍与回显件隔着半行空白——percent 盒收缩只解到「行内剩余宽」，盒本身还占满行，兄弟件被推到行尾。占位不在收缩量上，在**基准**上：折行档的 percent(100) 基准天生是整行。
**定案（三件一体）**：① `TextRole` / `role_font` / `role_color` / `has_role` / `shrink_by_role` 全退役，五档角色收编为 `@style` 字阶预设（`text_heading` / `text_title` / `text_secondary` / `text_accent`，正文 13 是缺省档不挂），字号读新增的 `@theme.font_size_*` 字阶令牌；`default_font_family` 的平台探族（Windows 钉雅黑）并入 `text_source` 缺省字族，不再只随角色生效。② `text` / `text_dyn` 的 `wrap` 缺省翻 true（块级段落语义缺省），单行标签显式 `wrap=false`。③ 布局基准全线 `0 1 auto`：折行档**撤 percent(100)**——不设 grow/shrink，内容基准（measure 自然宽）起步，溢出靠上批修好的 min:auto 内容下限收缩；单行档 `min_width` 归 0 且 ellipsize 恒真，挤不过兄弟件时收缩、末端出 …（`bind` 同步这条）。
**块级跟随的新前提**：撤 percent 后，折行文本的折行宽来自「父给确定宽」——列容器 stretch 子项走 `measure_content` 的 `pinned_w` 传播（yoga-mbt 已有），父列自己被 shrink-to-fit（auto 宽 / align FlexStart）时子项按 max-content 排、不折行。这与 CSS `align-items:flex-start` 下的 shrink-to-fit 同口径，**不是引擎 bug**；坑在测试语境——wbtest 的 `mounted` 助手把根定成 FlexStart，量块级跟随必须直挂确定宽根，否则测到的是 shrink-to-fit。
**验证**：ui 新增「文本件口径：缺省折行按可用宽排，单行档收缩让宽不溢出」与「回显紧贴标签（±1px）」断言；`text_split_wbtest` 角色档改钉字阶预设（theme 令牌值 + 预设色键现取）。库门禁 1165/1165、`moon check` 零警告、全 workspace 构建过（showcase 100 处 + 其他示例 26 处 `role=` 全迁 `class`）。真机待复验：基础页文字链接段（五档观感、回显贴标签）、面包屑、表单/卡片标题、日期格标题、窄窗单行标签出 …、md 页与反馈页回显。

## 富文本 measure 三档不许共用一份折叠状态：探询档顶高块盒 + 每档全量重折（2026-10-27,真机「Markdown 页列表项之间空出半屏、开页与滚动发涩」）

**症状**：showcase「代码文档 → Markdown」段，一行高的列表项各占 6~13 行（圆点被居中的高行盒甩到半屏之下），整篇文档高 1409（真值 369）；换宽与开页时明显发涩。上一批「三档分答」只把 max-content 的**宽**改对，没动三档共用的那份折叠状态。
**机制**：`md_rich_label` 的 measure 三档（正式档 `Some(v)`、min-content `Some(<1)`、max-content `None`）都写同一个 `rows_ref`/`row_w_ref`，而两个探询档返回的高度是**重折之前**读出的行数——1px 箱折出「一单元一行」的几十行，这个数被下一档当成本档的内在高答出去，沿「行盒高 → 块高 → md 列高」一路上顶，父列照这个虚高的 max-content 排，于是每项之间空出半屏。另一半是开销：一次布局三档交替，每档都全量重折并逐行建 `AttributedText`（`geo` 还按前缀量段宽，一行 n 段就是 n² 次会话），而探询档折出的那些行**永远不会被画**。
**修复**：① 三档各自成答——宽高一律取**本档自己那次**折叠的产出；② `rows_ref` 只由正式档与定宽档写，两个探询档各按档备忘一个 `(w,h)`，不再互相顶掉，也就不再重折；③ 行几何全惰性：`at`/`xs`/`ws`/`w` 只在真要画、或真被父级当内在宽用时才建，探询档改用折行期顺手累加的逐单元估算宽，删除线横线与链接命中的像素区间按需补一次。
**教训**：measure 的返回值本身就是布局输入，**任何一档都不许拿别的档的产出作答**（与「不设宽=measure 行宽撑破容器」「max-content 兜常量成假参照」两条同族）；内在探询的中间产物不进绘制，给它建绘制对象纯属白付——判据是「这份产出的消费者是谁」，不是「这条代码路径跑没跑」。
**验证**：无头探针（拉伸列 900 宽、演示文档）块0 高 124.8→20.8、整篇 1409→369；冷路径（建树 + 首次布局 + 首绘）20 轮 1.14s→0.48s（45ms→12ms/次），折行次数 73→44。新增 wbtest「探询档不顶高块盒」在 900/640/1100 三宽各钉一遍「每块不超过两行行盒、整篇不超过块数×两行 + 块间距」，旧实现红（`宽 900 下块0 高 124.8 超过两行行盒`）、新实现绿。库门禁 1165/1165、`moon check` 零警告。真机待复验：Markdown 页列表一项一行、滚动区间不再空半屏、切页与拖窗口不涩。

## 行容器里的块内容要吃掉剩余宽：shrink-to-fit 定盒与折行判据差 1px 就整体折第二行（2026-10-27,真机「任务项尾巴看不见 / 脚注定义丢尾」）

**症状**：顶高那批修好后 Markdown 页仍丢字——`- [x] 任务列表已完成项(点复选框可勾选)` 的右半与两条脚注定义的尾部看不见，`- 无序列表项二(含 \`代码\`)` 的收尾括号单独折到第二行。
**机制**：列表/任务/脚注/引用行的右半是一层**不给宽的列**，行容器里按 shrink-to-fit 取自身 max-content 定盒（探针读数 130、205、256、171）；而盒内的折行判据按**逐单元累加宽**算，与 max-content 的**联合排版宽**不同源（行尾压缩 advance、yoga 整像素落位都会让两者差出几分之一像素），差不到 1px 就整体折出第二行——行盒只有一行高 20.8，第二行被裁，看着就是「尾巴丢了」。这不是折行算错，是**盒宽给错**：块级内容的折行宽应当是文档宽减去标记列。
**修复**：mdview 的「标记 + 块内容」行统一给右半 `grow=1.0`（新增 `md_content_col`），行内剩余宽就是它的定盒宽；短项一行、长项按文档边界折，嵌套层逐层递减。
**教训**：① shrink-to-fit 的盒子拿自身自然宽当约束，等于把「差多少算放不下」交给两套测量口径去比——只要两者不严格同源，knife-edge 必在真机翻车；块级内容在行容器里要显式吃剩余宽。② 判据要扫**整棵树**而非盯单个节点：同一条机制下三处症状各在不同父盒里，逐节点断言会漏。
**验证**：无头扫描演示文档（1100/680/460 三宽）「自己画字的叶子比父盒高」计数 3→0；列表项内容列 130/205→662/660，任务项从 `205x41.6` 被 20.8 行盒裁回一行完整。新增 wbtest「行内块内容吃掉行内剩余宽」（旧实现红：`父高 20.8 叶 (20,128,205x41.6)`）。库门禁 1167/1167、`moon check` 零警告。真机待复验：Markdown 页任务项整行可读、脚注定义不丢尾、含行内码的列表项不再单独折出「)」。

## dotted 边框在 mac/Windows 看不见点：line_cap 是纯光栅档的空操作（2026-10-27,真机「Linux 点点点很清楚、mac 没有」）

**症状**：showcase「分隔提示」dotted 卡片（圆角点边框）Linux 出点正常，mac 整圈无墨。
**根因（两层，都在光栅档）**：dotted 的画法是「0.1px 段 + `set_line_cap(Round)`」——段本身近零长，墨全靠圆头端帽补出直径=线宽的圆点。而门面 `Painter::set_line_cap` 只接了 Cairo 支，`PureBackend` 分支是 `()` 空操作，C 桩 mac 支 `cr_set_line_cap` 也是占位——0.1px×butt 端帽 = 没有像素，点整圈蒸发。cairo 吃真端帽，所以 Linux 一直好。**同批探出的第二层**：直角边框走 `stroke_rect`，两后端都是「四带填充」的内侧复现、根本不吃虚线——直角 dotted/dashed 边框在 mac 与 Linux 都会画成实线一圈（此前没有真机读数所以没暴雷）。
**修复**：① `Raster` 状态机接上 `line_cap`（save/restore 同族），`stroke()` 在 Round 档给每条**开口**段两端补「半径=设备线宽一半」的正 24 边形墨点（闭合回路与首尾重合的整圆不加，与 cairo 同口径；dotted 每段都是开口小段，逐段落点）；② `Painter::stroke_rect` 在虚线档两后端统一退「内缩半线宽的居中路径 + stroke()」（内侧语义换算规则见「stroke_rect 两侧同口径」条），`Raster::stroke_round_rect` 解析快路在虚线档返回 false 走门面既有退路。
**教训**：门面把某参数只接一个后端时，空操作分支必须留注释点名「哪条真实语义会缺」——`PureBackend => ()` 这种静默吞参数，比报错更难发现；跨后端像素判据（本批 butt 对照档）能把它钉死。
**验证**：`line_style_wbtest` 新增两条：「Round 端帽 ±1px 有墨 + 点间留白 + butt 对照无墨」（旧实现红在端帽断言、butt 档天然复现旧行为）与「stroke_rect 虚线档点边框：点心墨、点间空」（旧实现是一圈实线必红）。库门禁 1169/1169、`moon check` 零警告、showcase 构建过。真机待复验：mac/Windows showcase「分隔提示」dotted 卡片出点、dashed 卡片虚线段、直角点边框容器（若有）不再实线。

## draw_image_from_rect 是「源矩形在前、目标矩形在后」：演示按直觉写反，蓝点压在第一块月亮上（2026-10-27,真机「Linux showcase 位图段多一个蓝圈，mac 没有」）

**症状**：Linux 的 showcase「画布与富文本 → 位图」里，第一块米色月亮上压着一个蓝色圆盘；mac 同页干净。
**定位**：蓝盘色 `#356aa0` 与 `dot.gif` 首帧同色（月亮 PNG 本体是 `#f2edda`）→ 画出来的是 GIF。门面签名是 `draw_image_from_rect(image, sx,sy,sw,sh, dx,dy,dw,dh)`，演示按「目标在前」的直觉写成 `(260,34,80,80)+(40,40,40,40)`，于是**源窗取到 120×120 画面之外、目标窗变成 (40,40) 的 40×40**——正落在第一块月亮上。mac 那张截图没有蓝盘不是 mac 画对了，而是那份构建更旧（段描述里还没有 GIF 那一句）。无头实测（本机光栅档）：现写法落点 `(40,40)..(79,79)`，按签名改对后 `(260,34)..(339,113)`。
**顺带量到的库侧缺口（记债未做）**：光栅档对越界源窗没有统一口径——源窗**完全**在图外时把整张源图缩进目标画了出来（n=1600），源窗**部分**越界时整块不画（n=0），两种都不是可预期的语义；cairo 档形态又不同（Linux 真机看得见、mac 看不见同一处误用）。触发条件：任何一次 from_rect 误用都会被它掩盖成「某一平台没画」。修法方向：在门面 `draw_canvas_from_rect` 里先把源窗与位图求交、交集按比例映进目标矩形、空集不画，三平台一实现，两后端不再各自解释越界。
**教训**：八参数、两组同型矩形的 API 天生易写反，且**写反了往往只是画错位置而不报错**——演示里它活了很久，因为「看不见」在 mac 上被当成正常。参数序要有用例钉（`painter_wbtest`「源子矩形 → 目标矩形」已在），跨后端可见性差异要按「同一份代码两个平台读数不同」来查，不能按「哪个平台是对的」来猜。
**验证**：showcase 构建过；演示两处（绘制与复制串）同步改为源在前，段描述去掉未渲染的 `**` 星号。库门禁与 `moon check` 见提交信息。

## prebuild 专编归档「重编了但 exe 没重链」：moon 失效链只认 link_flags 字符串，不认归档内容（2026-10-29，用户 Linux 真机 `examples/browser` 下载仍 102）

**症状**：decide-policy 响应决策修复（不可展示 MIME 显式 `webkit_policy_decision_download()`）推送后真机验证依旧 `WebKitPolicyError/102`。按 §9 口径 `nm libgui_webview.a | grep -c webkit_response_policy_decision_is_mime_type_supported` 返回 1——归档确认是新代码；行为却还是旧的。
**判据升级**：102 此前误读为「展示不了」，对着 WebKit 源码（`WebKitError.h.in`）核枚举值才定案：`102 = WEBKIT_POLICY_ERROR_FRAME_LOAD_INTERRUPTED_BY_POLICY_CHANGE`——导航被策略决定**打断**，正是默认 class handler 走 `ignore` 分支（MIME 不支持且非 attachment → ignore）的产物；download 分支的产物是 `download` 信号。于是「102 仍在 + 下载事件从未出现」唯一自洽的解释就是 exe 里还是旧桩：**归档新 ≠ exe 新**。
**根因**：moon 的构建失效判定按「下发的 JSON 是否变化」走。归档路径固定、`link_flags` 字符串在归档重编前后逐字节相同 → 目标不失效 → exe 不重链。归档只是躺在盘上被 exe 无视。这层叠在「mtime 判据被保留时间戳的同步骗过」（上一条，`*.srcsha` 指纹边车修的那层）之上：修好第一层只保证归档重编，没保证 exe 重链——两段失效链断在中间。
**修法**：源码 sha256 前 8 位**编进归档文件名**（`libgui_webview-<tag>.a` / `libgui_webview_mac-<tag>.a`），`link_flags` 的 `-l` 名跟随实际文件名。源码变 → 归档名变 → link_flags 变 → moon 失效链接目标、必然重链。这条传导走的是 moon 的核心失效判据（配置字符串变化），不依赖任何边车文件；同前缀旧指纹归档与无指纹旧名、`*.srcsha` 残留由 prebuild 顺手清掉。重编时 stderr 打一行「指纹 xxxxxxxx」便于对读数。
**验证**：本机（mac Darwin 分支）实跑 prebuild：归档产出 `libgui_webview_mac-079d8a87.a`，JSON 的 `link_flags` 变为 `-lgui_webview_mac-079d8a87`（与旧版字符串不同 → moon 必然重链）；旧名与 `.srcsha` 残留清干净。Linux 分支同一套代码路径。真机口径：pull 后直接 `moon build`（不必 moon clean——link_flags 变化自动触发重链），`nm -D <exe> | grep -c webkit_response_policy_decision_is_mime_type_supported` 应 >0（查 exe 不止查归档），然后直链 .deb 应弹保存框。
**教训**：① 「归档/库是新的」到「二进制是新的」之间还有一跳——构建系统的失效链认的是**下发的配置字符串**，不是文件内容；让产物进二进制的可靠姿势是把指纹编进文件名、让配置串自己变化；② 排障读数要对齐到「链进 exe 的东西」：查归档的 nm 只证归档，查 `nm -D <exe>` 才证二进制；③ 错误码要对着源码核枚举值再归因——102 从「展示不了」改成「策略打断」是本条归因翻转的转折点。

## 下载落点归应用层：库内弹框整批删除，下载对齐权限的「上报 + 落判」形态（2026-10-30，架构决策）

**动机**：库替应用做了 UI 策略——三平台桩里内嵌保存框（mac `NSSavePanel` / Linux `GtkFileChooserNative` / Windows 交运行时默认），做库不是做浏览器；且 Windows 放行档与另两家语义不一致（运行时浮层 + 默认目录 vs 系统保存框）。
**形态**：对齐权限那条线（`Permission` 事件 + `set_permission_mode` + `respond_permission`）：`Download` 事件带 `id/uri/建议名`，`set_download_mode(true)`=自动档（默认，报事件后交引擎默认落点——Windows 运行时默认体验、mac/Linux 静默存系统下载目录，库内零弹框），`set_download_mode(false)`=询问档（扣住待决，`respond_download(id, allow, path)` 落判；allow 且 path 空=取消，不存在「事后改交引擎默认」——Linux/mac 扣住后没有回退口）。应用层要保存框就自己在事件里弹（browser 示例用 `sys` 文件对话框演示；对话框在事件回调里模态跑与 sys 先例同形态，引擎回调早已返回，不再有「引擎回调里嵌套主循环」的问题）。
**三平台扣住机制**：Linux=`decide-destination` 返回 TRUE 扣住（2.40+ 异步契约），`webkit_download_cancel` 落判时顺手释放引擎侧挂起的落点回调；mac=扣住 `decideDestination` 的 completionHandler（ARC 持 block，允许延后调）；Windows=`DownloadStarting` 走 `GetDeferral` + `put_Handled(TRUE)` 压默认浮层，落判 `put_ResultFilePath` / `put_Cancel` + `Complete`。三平台待决槽同容量（8），视图销毁一律按取消收口（mac 落 nil、Windows Cancel+Complete）。
**判据**：① 库的能力面上，UI 策略（弹什么框、存到哪）一律归应用层，库只给「上报 + 扣住 + 落判」三件套——新接引擎能力先问「这件事的落判归谁」；② 事件载荷要带 id 的场景=同视图可有多件挂起（下载天然并发，权限单件挂起即可）；③ Windows 的建议名没有独立口，从默认 `ResultFilePath` 末段拆。
**验证**：`moon check` 零警、`moon test` 1597/1599（2 红为本机环境固有）、`examples/browser` 构建过、Linux 真机清单（保存框/拦下/自动档三路）；Windows/mac 待真机。

## 模板 props 的语言层边界：位置参无默认值、具名可有非常量默认、未用参数与未用 let 都报警告（2026-11-02，MoonBit 0.1.20261016 探针）

- **要定的事**：`.mng` 组件的参数表用「只有签名、无函数体」的 `fn` 头承接，参数能否带默认值决定 props 是否必填。
- **实测**（临时模块，只依赖 `NoahLiu/native-gui/base`）：
  1. 位置参数写默认值即报错 3010「Only labelled arguments can have default value」——`fn f(x : Int = 3)` 不成立。
  2. 具名可选参数可以有默认值，且默认值允许是**非常量表达式**：`fn f(s? : @base.Store[Int] = @base.Store::new(9), cb? : () -> Unit = fn() {})` check + test 双绿。
  3. 带默认值的具名参数在**函数体内绑定为裸类型**（`s` 直接是 `Store[Int]`，不是 `Store[Int]?`），`match s { Some(v) => … }` 反到报错。
  4. 这类参数调用时**不能占位**：`f(1)` 对已升具名的参数报 4080「requires 1 positional arguments」，只能 `f(b=2)`。
  5. 未用即警告：函数体内未引用的 `let`（0002 unused_value）与**函数参数**都进警告；消法两种——参数名前置 `_`（会改掉 API 名），或体内 `let _ = 名`（保留名字，`.mbti` 与调用点不变）。
- **定案**：props 必填=位置参数、可选=`名? : 类型 = 默认值`（Store/回调都能带默认）；模板按参数名写属性，回调 prop 用 `@事件名`（按 `名` / `on_名` 查参数表）。生成器对未被模板/script 引用的 prop 出 `let _ = 名` 垫片，保住「生成码零警告」门禁；只作组件绑定的 `let 名 = @包.函数` 直接从生成体里丢掉（否则同样报未用）。
- **判据**：给「生成码」定形态前，先把语言层的**警告面**当契约测一遍——门禁是零警告，生成器必须比作者更在意未用变量。

## 通知的「打扰档」开放给应用：`urgent?` 只有 macOS 有对位物，freedesktop 的 urgency hint 故意不映射（2026-11-03）

**契约**：`@shell.notify_send(..., urgent? : Bool = true)` → 仅 mac 臂落 `UNNotificationContent.interruptionLevel` 二档：`true`=`TimeSensitive`（应用在前台忙时也直接出横幅，这是本仓真机定案的前台横幅钥匙）、`false`=`Active`（前台忙时静默，只进通知中心）。缺省 `true` 保持既有行为不变。用户在系统设置里关掉「时间敏感」授权后，传 `true` 同样回落静默——这一档不是「必定弹出」，是「不主动降级」，文档与函数注释都写死这半句。
**不映射的口径**：Linux 的 freedesktop `urgency` hint（low/normal/critical）**不接**这一参数——`critical` 的标准语义是「常驻不自动消失」，与「绕过前台静默」不是一回事，接上会把调用方的意图翻译成另一个含义；Win32 气泡压根没有打扰级别概念。两臂收下参数并忽略，门面无需按平台拆调用。
**签名同步的面**：`wm_notify_send` / `wm_notify_update` **四臂**（Win32 / GTK / mac / 兜底）一律加 `int urgent` 尾参，非 mac 臂 `(void)urgent`；`win.notify_send` / `win.notify_update` 开 `urgent? : Bool = true` 具名可选参，C 侧收 0/1。`shell.notify_send` 的 `replaces_id>0` 覆盖路径也带档——只给首发带档而覆盖走默认档会让「urgent=false 的进度型通知」在 mac 上被替换回时间敏感，契约不成立。**extern 声明与四臂签名逐参数对照**是本批唯一的编译期风险（漏改一臂只在链接期炸，`moon check` 不编 C）。
**后端名读数一并收口**：mac 档 `notify_backend_name()` 从 `ns-user-notification` 改 `un-user-notification`（UN 迁移后名实对齐；`NotifyBackend::WinBalloon` 枚举名不动，mac 的实现住在 `wm_notify_*` 同一支桩是既定架构，注释与 wbtest 按平台分档期望）。名字是纯 MoonBit 硬编码，C 桩不返回名字。
**验证**：`moon check --deny-warn` 干净；`moon test base shell win dbus` 192/192（本机无通知服务，生命周期用例自动跳过；后端名用例在三平台各自分支判定）。Windows 纯 C 探针 `experiment/notify_probe/notify_backend_probe.c` 的 12 处调用点同批补第 5 参，待 Windows 侧复跑（末行 `NOTIFY-BACKEND-OK`）。mac 臂由 CI 的 `clang -fsyntax-only WM_STUB_MAC` 门禁编一遍，二档真机观感归用户复验。

## CI 两条长期红灯的根因：生成码里嵌了绝对路径、透视用例漏了自己写下的前置（2026-11-03，master 自 11-02 起 CI 全红）

**现象一（Linux「生成物新鲜度(模板对账)」）**：`mng gen` 重生成后与提交的 `<stem>.gen.mbt` diff 永不为空，差异只有一行——头注「来源：」后面那串路径。**根因**：codegen 把调用方传入的 `filename` 原样写进生成码头注与 source map 的 `source` 行；本机传 `/home/<user>/…`，runner 传 `/home/runner/work/…`，对账按字面 diff 必然判过期。source map 的消费端（`cmd_map`）本来就只取末段 basename，全路径没有任何消费者。**修复**：`mngkit/gen.mbt` 加 `base_of`，头注与 map 都记 basename；重新生成 `dev_demo.gen.mbt`。**判据**：新鲜度对账的可比性要求生成码里**不出现任何机器相关量**（绝对路径、用户名、时间戳）——重生成 diff 是内容判据，机器量把它变成恒红。

**现象二（Windows `shell_caps：真窗探测…透视按能力走`）**：`inspect(w.set_transparent_bg(true) is Ok(_))` 在 Windows runner 上给 Failed。**根因**：用例按「能力位在 → 就开得成」写断言，而本仓对 Windows 透明底定的是**另有前置**（带边框的窗不支持透视，要先 `set_borderless(true)`，前置不满足进 `Failed` 档）——契约写在 `set_transparent_bg` 的文档里，用例没读自己包的契约。**修复**：`caps.transparent_bg` 支内先切无边框、两条断言后复位。**判据**：`caps` 的位是**平台级能力**，不等于「这个窗此刻能开」——凡有前置条件的档，用例要按契约把前置摆上，否则 runner 与真机（用户已验通过）长期分歧。

**现象三（Windows 链 `sys` 白盒测试 exe）**：`LNK2019 unresolved yue_sys_pr_signal / yue_sys_sleep_ms`。**根因**：这两个函数**内部**各自有 `#if defined(_WIN32)` 分支，却被整块放在文件里那个更大的「`#if _WIN32` / `#else` POSIX」分块的 **POSIX 侧**——Windows 编译时外层先把它们挡掉，内层的 Win32 分支成了永远到不了的死码，符号根本不存在。与「借别的子系统当门」同款：外层平台块是**子系统归属**，内层是**实现分流**，两者不是一回事，写的时候看着都带 `_WIN32` 就以为安全。**修复**：把两函数整体挪到外层分块之外（`#endif` 之后），并在那里写一句「住平台分块之外」的理由。**判据**：内部自带平台分流的函数不许嵌进任何单平台大块；新增这类函数后，在另一平台的链接产物里确认符号存在（`moon test sys` 只在 Linux 过不代表 Windows 能链上）。

**现象四（Windows 跑 tools 用例）**：`写不出 /tmp/mng_proj_conf/moon.mod` → `PanicError`，整个 mng 白盒测试 exe 挂掉。**根因**：项目级 dev 配置的回归用例把临时目录硬写 `/tmp`，Windows 上写不进就 `abort`（`write_file_p` 的既定行为）——用例把 POSIX 路径当成跨平台前提，与库能力无关。**修复**：`tmp_dir(sub)` 依次取 `TMPDIR` / `TEMP` / `TMP`，都没有才回落 `/tmp`；`project_wbtest` / `dev_wbtest` / `lsp_wbtest` 的用例根目录与 `Artifacts` 解析用例的落盘路径同批改过去（解析断言按变量比对，不再钉死字面路径）。**判据**：用例里出现的每一条绝对路径都要问一句「另一台机器上它存在吗」；临时文件走环境给的临时目录，`proc` 那族用 `posix_only()` 明确分流。

**验证**：`cd tools/native-gui-tools && moon test ./mngkit ./mng` 55/55（改后 `moon test ./mng ./mngkit ./proc ./inst` 62/62）；本地按 CI 同法跑一遍全量模板对账（逐 `examples/**/*.mng` 重生成到 /tmp 再 diff）零差异；`moon test win` 36/36（Linux 有合成器支同走一遍）；两条推上去后看 CI 三平台腿。

## 性能基线探针首批读数：yoga 布局缓存不立项，增量重绘要等纯光栅腿的对照（2026-11-03，`experiment/frame_cost_probe` Linux 无头）

**观测面三件**（都常开、只加整数）：`gui/base/prof.mbt` 的进程级账本新增 `relayout` / `visit` / `skip` 三条计数（打点 `Widget::relayout_at` 与 `Widget::paint_at` 的视口剔除分支）；`modules/yoga-mbt/src/stats.mbt` 新增 `measure` / `hit`（打点 `measure_content` 入口与缓存命中返回）；探针模块按场景打印 `FRAME-COST` 行，判据进 `测试文档/测试用例.md` 附录 D。
**Linux（cairo 腿）读数**：① 树不变的连续 20 帧 relayout = **0ms、`measure=0`**——yoga 的 `measure_content` 只在内容真变时才被问，**「再加一层布局缓存」没有可省的开销**，不立项；② 每帧改一段动态文本：15/60/240 行的 `measure` ≈ 1460/5060/19460（命中率 90%+），单帧仍 0.1–0.45ms——失效重测本身很便宜；③ 整页绘制成本随规模线性（0.5/1.2/3.5 ms/帧，每行约 81 个控件）；④ **脏矩形裁剪在 cairo 腿几乎不省**（clip 到 60px 高的窄条：240 行 3.45→3.3ms，`skip` 恒 0）——视口剔除只在纯光栅后端判交（`widget_cull_skip` 的既定口径），所以这不是「局部重绘没用」，而是**这条腿量不到**。
**判读纪律**：跨后端的能力不能用一条腿的读数立项——`paint_clip` 的收益要 Windows/macOS 跑同一支探针看 `skip` 是否真把控件挡在遍历外；那两条腿的差值才是「图表/整页增量重绘」立不立项的依据。探针里 `ledger=frames=0 layout=0ms` 是常态（无头不走 `App::paint_frame`，分段 ms 归真机 `SHOWCASE-PROF` 那本账），别当故障。
**验证**：`moon build frame_cost_probe` 绿；`moon test src`（yoga）108/108；库门禁 `moon test base shell widget ui render text theme icons sys input win dbus chart mdview style router` 与 `--deny-warn` 同批跑过（计数常开不进断言，读数随平台而变，钉死会假红）。

## 静态文本 selectable 档：缺省档「一行不动」怎么做到，以及选中几何同源的两处取舍（2026-11-03）

**做法**：`text`/`text_dyn` 各加一个 `selectable? : Bool = false`，内核 `text_node_of` 多一个参数，在挂载闭包里**二选一**——`if selectable { sel_setup(w, src) + 本档 on_draw } else { attach_text_measure + draw_text_in }`。并列新函数（`attach_sel_measure` / `draw_sel_text` 在 `gui/ui/textsel.mbt`），不改原函数体、不包一层：缺省档在物理上没有新路径可走样。装饰线两边共用抽出的 `draw_text_deco`（否则两档画不出同一条线）。
**选中几何同源**：`sel_layout` 一份 TextLayout 同时供测量（内容宽=最宽行、高=行数×行高、min-content 探询按 1px 箱折）、绘制（逐行 `draw_at` + `rects` 填色）与命中（`hit`）。居中偏移折算进 `offset_y = pad - top`——TextLayout 只有一个 `pad`（textarea 的四周内边距语义），横向块偏移占它，纵向就靠 offset 补偿，别再往结构里加第二个 pad。
**两处定案外的取舍**：① 折行块内不逐行对齐（整块随 `text_align` 偏移、各行贴块左缘）——`hit`/`caret_x` 的换算是「行首 + 段宽」，逐行不同起点要动结构，本批不值；② `max_lines`/省略调 `@text.clamp_lines`（从包内升 pub）——与缺省档同一把刀，代价是**选中范围=可见范围**（被截掉的行选不到），这正好也是想要的语义。
**动态文本的钩子点**：`relabel` 是 `text_dyn`/`bind`/`bind_label` 唯一的变化口，按控件 id 查 `sel_hooks`：注册过就走本档收尾（重设测量标脏 + `Editor::set_text` 清选区 + 让出持有），没注册走原路 `attach_text_measure`。收尾闭包只捕 `@yoga.Node` 与 id，**不捕 Widget**（回调禁捕铁律；`mark_changed` 不对外，重设 measure 就是标脏的既定手法）。摘除经 `on_discard` 把 id 从两份表里删掉，不留死登记。
**宿主复制支的位置**：`App::fire_selection_copy` 插在「焦点链吃掉」之后、`fire_key_fallthrough` 之前——于是「焦点在输入框且它有选区时 Ctrl+C 复制焦点件」这条已知限制自动成立，不用额外判定。primary 按平台取 Cmd/Ctrl（`@shell.platform_is_macos()`），与编辑内核同一式。
**用例的位置**：无头投递 `dispatch_pointer` 按矩形命中派发，**落点必须留在件内**（拖到框外的 Move 在测试里不会送到这件——真机靠按下捕获才不丢）；行中点取 `w.rect.y + w.rect.h / 2.0`，写死 +10/+20 会打到单行标签之外，整条用例静默空转后在后面的断言上炸。
**验证**：`moon check --deny-warn` 干净；`moon test base shell widget ui render text theme icons sys input win dbus chart mdview style router` 1236/1236（新增 ui 4 条：四种指针交互与复制、跨件互斥、文本变化清选区、缺省档零变化）。真机清单进 `测试文档/测试用例.md` SC-1.7（剪贴板互通、I 梁出没、手感和高亮可辨归用户）。

## code_view 选中：行几何复用单行 TextLayout，与「无头投递按矩形命中」的两条测试口径（2026-11-03）

**做法**：选区参照系是「各行按 `\n` 拼接的全文」+ `line_off[i]`（第 i 行行首的全局字节号），Editor 就装这份全文——于是复制天然带换行、`Editor::floor_boundary` 天然不劈半字（代码里有中文注释）。每行的命中与高亮用一个**单行 TextLayout**：`build(line, 1000000.0, measure, line_h, pad=text_l, offset_y=text_l)`——`pad` 与 `offset_y` 都取文本左缘（行号列宽 + 16px 内缩），于是 `rects` 的 y 落回 0（行原点由绘制循环加）、`hit` 的定行恒定 0 行、x 直接是「左缘 + 行内前缀宽」。不加第二个 pad 字段，几何半边零改动。
**行号列结构性不进选区**：它压根不在参照系文本里（`lines` 只装代码行），点在行号那一侧 `x < 左缘` → 列夹到 0 → caret 落该行行首。不需要「排除」逻辑，也就没有「排除漏了一处」的坑。
**测试口径两条**：① 无头 `dispatch_pointer` 是**按坐标命中路径**投递（`Widget::dispatch_pointer` = `hit_path` + 传播），**视口裁掉的坐标收不到事件**——code_view 的画布住在自带横滚视口里，探针落点必须留在视口内（拖到 `rect.x + rect.w - 2` 会静默不投递，看起来像「拖选坏了」）；真机靠按下捕获不受此限。② 同一位置 400ms 内连点两次就是**双击**（组件手算，与 textarea 同式），所以「先单击再单击别处再单击原处」的用例里，第二次与第三次同点必然触发选词——单击断言要换位置或换实例，否则 `caret` 断言会被选区断言抢先。
**验证**：`moon test ui` 246/246（新增 3 条：单击定位 + 行号侧落 0、双击选词整词一致、跨行拖选到末行整段复制、缺省档不挂指针）；`moon check --deny-warn` 干净；showcase 第一块代码开 `selectable=true` 供真机复验（SC-6.1 已扩判据）。
## markdown 逐字选中改前缀实测量：「必须动三平台 C 桩」的前提被证伪（2026-11-04）

一期把「AttributedText 逐字选中」挂为缓批，理由写的是「需在 @text 开逐字几何接口动三平台 C 桩，违背一期不碰平台桥约束」。真做时发现**前提不成立**：逐字边缘的真值不需要新平台接口——`measure_font(前缀)` 就是该前缀在给定字体下的精确 shaping 宽（Pango/DWrite/CoreText 三平台各自的 measure 路径早就通了，entry/textarea 的光标定位 `TextLayout::caret_x` 一直用的就是这个口径）。markdown 选中旧口径是「逐字单独量 → 按比例分摊到段联合宽」，shaping 误差全落在分摊比例上（本机 Pango 实测 "AV"×20 累加 180 vs 联合 161，差 19px；mac 上混排差 11px 的旧注同源），点击落点整体漂移、选不中字。新口径：**段界仍取联合排版**（`joint_w` 把整条前缀建成多字体 AttributedText 实量，跨段 kerning 在这一层），**段内逐字边缘取前缀实测量**（段内 uniform 字体下是精确值），两头都真且零新 C 代码。用例自带「牙齿」断言：扫全边界算旧口径与真值的最大差，>0.4px 才认（否则判据抓不回退）；逐边界点击落点断言到字节精确，不再用旧的「±1 个字」容差。若要更真（多字体逐字、AT-SPI Text 的 GetCharacterExtents），那才需要 rt_* 的逐字游标接口——留到有消费者时再说。

## L1 三臂共享核心：surface 源分平台、贴像素路径各自停手（2026-11-04）

Win/mac 臂落地时把 L1 核心从 GTK 臂上收进文件末「实现 TU」段（`#if WM_STUB_MAC || WM_STUB_GTK || (!linux && !apple)`——恰好是三平台真臂的编译条件，moon 的 native-stub 空占位编译落不进去），三臂各留 ~50 行薄适配：
- **surface 源三形态**（都在 vendor 头的 `WGPUSurfaceSource*`，无需 D3D12/Metal 头）：GTK 用 `XlibWindow{display, window}`（XID = area 的 GdkWindow）；Win32 用 `WindowsHWND{hinstance, hwnd}`（hinstance 取 `GetModuleHandle(NULL)`，hwnd 是桩内槽表里的窗句柄）；mac 用 `MetalLayer{layer}`——**视图要改 layer-backing**：首次绑定时 `[view setWantsLayer:YES]` + `[view setLayer:[CAMetalLayer layer]]`（原 WMView 是 drawRect 的 CG 直贴、且设过 `setWantsLayer:NO`，见 mac 臂视图创建处）。
- **贴像素路径各自停手**：GTK 的 draw 回调、Win32 的 WM_PAINT（BeginPaint/EndPaint 照常销脏区、不 blit）、mac 的 drawRect:（直接 return）——判据都是每窗 `WmL1.on`。Win32 的**逐像素透明档（trans_mode==1）不走 GPU**：合成面由 UpdateLayeredWindow 整块管，wgpu surface 与它不是一回事。
- **WmL1 状态放文件头**（三臂共有、实现 TU 段定义入口 + 前置声明）：臂在文件前部就要用它做结构体成员——与读屏动作队列「定义在文件末、前置声明」同户型。每窗只持 surface/纹理/暂存/bindgroup，instance/device/queue/管线/采样器/bgl 进程级跨窗复用。
- **验证边界**：Linux 腿全量可编可测（门禁 1296/1296，回退路径零变化）；Win/mac 两臂只过了人工复查（结构/符号/调用形状与 Linux 臂同构），**编译归 CI 三平台腿、真机肉眼归用户**——这是本仓对「本机没有的平台」的既定口径（同 uia_provider 的头桩语法校验先例，本次连语法桩都没搭：改动是 GTK 已验证同构代码的平台参数替换）。

## wgpu 进程内队列写不落地：standalone C 原型可用、moon 测试进程全零（2026-11-04，未结案）

GpuCanvas（@render.GpuSink 的 gui-gpu 实现，GPU 线首消费者）落地时撞上的怪现状，**根因未定，先记账**：
- **现象**：同一台机器、同一份 vendor 归档——standalone C 原型（dlopen → instance → adapter(Vulkan) → device → queue → `wgpuQueueWriteTexture` → copyTextureToBuffer → mapAsync 读回）**完全可用**（读回 1..16 与写入逐字节一致）；而 moon 测试进程里跑同口径代码（canvas 的 draw + finish，以及进程内自建 device 的复刻）**读回全零**。
- **已排除**：① 编译优化（原型用 moon 同款 `-Og` flags 仍可用）；② 双 dlopen 实例（core 与 probe.c 同路径串，且屏蔽 probe 用例后仍复现）；③ 错误回调（原型加 `uncapturedErrorCallbackInfo` 仍可用）；④ DISPLAY/X11（拔掉仍复现）；⑤ submit 后立刻 release 纹理、小 size map（原型照做可用）。
- **进程内可见的事实**：instance/adapter/device/queue/buffer/texture/pipeline/sampler/bindgroup **全部建得出**；render pass 的 **clear 能落**（读回看得到 clear 色）；texture→buffer 的 copy 与 mapAsync **能落**（clear 读回为证）；**唯独 `wgpuQueueWriteBuffer` / `wgpuQueueWriteTexture` 之后的 GPU 执行看不到写入的数据**（copy 链读回全零）。
- **未做的判决**：进程内自建 instance（绕开 core）也是全零——所以不是 core 的 device 有问题，而是**进程环境**（moon runtime / 链接进来的 native-gui 全套桩）与 wgpu-native 的某处交互。下一步候选：① 在 `moon run` 的真实应用进程里跑一遍 demo（可能测试进程特有）；② `wgpuInstanceWaitAny` 等 future 原语替换「pump + flag」模式；③ 缩小链接面（只链 @guigpu 的最小可执行）复现。
- **mac 腿已结案、不是本条的成员（2026-11-05）**：mac 上「画布建不出」的根因是 gui-gpu 自己的五处平台硬伤（库名写死 `.so`、后端写死 Vulkan、上传纹理通道序、fill shader 调试遗留写死白、tex 与混合因子的 alpha 口径不一致——详见下一节「gui-gpu mac 腿五处硬伤」），与进程环境无关。修复后 mac 测试进程里 canvas wbtest **像素断言首次真正执行并全过**（读回 BGRA 样点与图案逐点对上）。本条「queue 写不落地」因此收窄为 **Linux/lavapipe 腿专有**（或 Linux 测试进程专有）；mac 腿不再是取数对象，候选②「future 原语替换泵」的验证面只剩 Linux。
- **2026-11-06 更正：本条结论不成立。** 在 canvas.c 里补了两路独立探针（纯 buffer→texture→buffer，不经渲染与顶点）：`QueueWriteBuffer` 写 16×16 图案后 copyBufferToTexture→copyTextureToBuffer→map 读回 **1024/1024 非零字节**；mapAsync 写一路同样 1024/1024；render pass clear 也全落。真正让「读回全零」的是 **pipeline 的 `WGPUMultisampleState.mask`**：C 桩 `memset` 把 mask 清成 0（头文件默认值 `0xFFFFFFFF`），mask=0 把全部样本遮掉——clear 照落、所有 draw 一条像素不出。补 `pd.multisample.mask = 0xFFFFFFFFu` 后 canvas wbtest 3/3，像素断言首次在 Linux 真正执行并全过（左上红 / 右下蓝 / 中心绿混合）。queue 写链路一直是好的；本条降级为诊断记录，不再按「进程环境」追。

## 选中档指针链的分支遗漏：带链接段落的 Up 没进选中链（2026-11-04，真机抓到）

`md_rich_label` 带链接的段落装的是「链接命中优先」的指针分支——Down 落在链接字上打开链接、落空才转 `sel_via`，Move 只在非链接区转发。**Up 分支当时直接 `return false`，没转发进选中链**：`sel_pointer` 靠 Up 清 `dragging`，这一漏，带链接段落里拖选过一次后 `dragging` 永远为真，之后鼠标在这段里移动就一直 `select_range(旧锚点, 当前)`——真机表现即「起点钉死在一个位置、松手后移动还改选区」。修法一行：Up 也走 `sel_via`（sel_pointer 的 Up 本就返回 false，外层语义不变）。教训：**复合分支的指针处理要四态对账**——Down/Move/Up/Leave 每一态要么转发进公共链、要么明确说明为什么不转；「只加分支不改公共链」的补丁最容易漏 Up。回归用例（`markdown_wbtest`「拖选松手后再移动不改选区（带链接的段落也必须成立）」）自带牙齿：撤修复即红「松手后移动仍改选区」。

## 列容器套折行内容的命中死区：探到根因、暂不动布局引擎（2026-11-04）

真机报「markdown 只有第一行前面三分之一可以选中」，无头复现出一族**容器矩形盖不住子项**的布局缺陷：auto 高的列容器，子项主轴基准取**未约束宽的内在高**（YG3d ③ 档），而子项最终按钦定/stretch 宽折行落地（更高）——容器 rect 矮一截，`hit_path` 要求每个祖先矩形都包含点位，于是容器底缘以下的子项整块收不到指针（探针：四块文档的最后一块 `hit_test` 全落到父列；双层 auto 列 + 宽度相关测量叶最小复现 outer=20 / inner=40）。三处候选修法都试过并**全部撤销**：①叶子高度内在探询传宽基准、②列容器求高先收 max-content 行宽、③③′基准按占用行宽现量——①②破坏 min-content 语义（探询档被顶高，mdview/ui 五处用例红），③与 YG3d 定案「交叉轴不定 → 基准取 max-content（不随可用空间漂移，收缩算得到溢出量）」直接冲突（专项用例钉着）。判别要点：**对「测量契约干净」的测量函数（f(None) 的高 == f(Some(自身 max-content 宽)) 的高），③ 与 ③′ 同答**，YG3d 并无漏洞；踩坑的是「正式档答案宽度取 `.max(v)`（claims 可用宽）」这类**答案与内容宽脱钩**的测量——子项声称的宽 ≠ 内容宽时，行宽与折行高互相矛盾。后续若真要收这族：方向是给 mdview 这类测量「正式档答案宽度改答内容宽 + 块级铺满交给 stretch」，或布局层加「容器高按子项落地高回灌」的收尾校验（涉及全部容器的尾段重算，动 flex 核心，单独立项）。最小复现与探针手法记档待用：双层 auto 列 + 测量叶 `f(None)=(100,20) / f(Some(w))=(w,40)`，`calculate_layout` 后断言三层同高。

## markdown 文档级跨段选中：三处联动修复与「shrink-to-fit 列被内在高钉死」的收口（2026-11-05）

**跨段机制**：`markdown_view(selectable=true)` 一份文档级 Editor——可选块按构造序（=视觉序）拼全文、块间补 \n；块条目（`MDBlockEntry`）构造期分配全文字节偏移、**on_draw 每帧回填矩形**（闭包禁捕 Widget，命中要的落点几何走纯数据登记表）；命中「本块局部 → 绝对坐标 → 找罩住的块 → 它的逐字行模型 → 全文字节」，块间空隙按中点归前/后块端点；绘制把全文选区裁到本块区间铺底色。代码围栏/表格不进全文，是文档流里的独立选中岛。拖选靠共享 TextSel 天然跨块（按下捕获把 Move 送回起手块，起手块的命中表能把界外落点换算到别的块）。

**三处联动坑**：
1. **选区持有者登记必须同号认领**：块间换手时 `text_sel_claim` 会 clear「前任」——共享同一份 Editor 时前任=自己，刚画的选区当场被折掉。修法：`TextSel` 加 `claim` 字段（0=按按下控件 id 的独立档；共享档全块固定一个号）。
2. **双击判据必须绝对坐标**：`last_xy` 原存各块局部坐标，共享状态后「不同块里的相同相对位置」（都在块顶附近）被误判成双击、整段中文被当词选中。修法：按 `w.rect` 平移成绝对坐标再比。
3. **markdown_view 跟随容器档必须 percent(100)（块级铺满）**：shrink-to-fit 的列会被父级按「未约束内在高」钉死高度（测量趟 ③ 档答「单行不折」的矮基准、落地趟按定宽 ② 折成多行），容器矩形盖不住折行子项，命中链在容器底缘断掉——真机「只有第一行能选中」即此。percent 让交叉轴确定，两趟同走定宽档同答。这正是 `proposals/layout-fold-hit-gap.md` 活案例的 mdview 侧收口；yoga 侧同批补 ③′（NoWrap 列且交叉宽不定时，测量趟基准按「内容宽最大值被可用宽夹住」的行宽现量，非 stretch 项仍占自己 content 宽——与 YG3d 专项用例同答，全量布局用例零回归）。

**用例**：mdview「跨段选中：markdown_view 文档级拖选跨块连续、复制得跨块原文」——三块文档从标题拖到末段，断言选区跨三块、复制串带块间换行、点另一块折叠；无头测试**必须先 paint 一帧**（块矩形靠 on_draw 回填）。白盒共享登记表/全局认领槽，回归验证建议 `-j 1` 或保证用例内自洽。

## AttributedText 选中几何：三平台同一组 C 符号、盒空间口径与返回值语义（2026-11-05）

**四个 C 符号**（`rt_line_count` / `rt_line_box` / `rt_hit` / `rt_caret_x`）：坐标一律是**盒空间**——调用方 draw 给的 x/y 偏移之外、box_w/box_h 之内的那套，对齐偏移（dx/dy）查询内部自己算，与各平台 rt_draw 同式。三平台实现：Pango 走 `xy_to_index`/`index_to_pos`（trailing 逐字符 `g_utf8_next_char` 前进折成字节）、CoreText 复用既有 PtPara（行盒 c0/c1 + `pt_range_width` 前缀量，行堆叠 = ascent+descent+leading，与 pt_draw_para 同式）、DWrite 走 `HitTestPoint`/`HitTestTextPosition`（宽下标↔字节下标用 `ptw_widx` + 二分逆查，trailing 即 pos+1）。占位臂（非 Linux/mac 的 stub 分支）同步补四个空桩，防符号缺失。

**两处坑**：①返回值语义要钉死 1/0——mac 臂第一版把命中字节当返回值 `return result`，MoonBit 侧 `ok == 1` 判断直接吞掉全部命中（测试抓回）；②字节位只在**字符边界**有意义（CJK 续字节不是合法插入位），往返断言要按字符边界走，与 Editor 内核同口径。

**预编译链**：stub.c 加新 C 符号后必须重跑 `gui/scripts/prebuild.py`——mac 的 `libyue_text_mac.a` 是脚本现编的归档，moon test 不会自动重编（链接 undefined symbols 即此因）。MacRT 的字节长度字段叫 `len`（Rt/Pango 叫 `tlen`、PtwSession 也叫 `tlen`），跨分支抄代码时易踩。

**组件**：`@ui.rich_text(at, selectable)`——AttributedText 直绘（draw_at 已有的 Painter 会话）+ TextSel 复用链；高亮按 `line_boxes` 铺行矩形、行内区间 = `caret_x` 前缘差；测量三档同 mdview 口径（min/max 探询答单行自然宽）。用例在 ui/richsel_wbtest（字符边界往返 + 拖选子串 + 非可选档不进登记）。

## 测量宽取整 × 亚像素绘制：光标错位半格、标签在自己盒里折行（2026-11-06，win/mac 真机反馈）

- **现象**：win/mac 上光标/选区与字符错位（约半格，行越长越歪），Linux 正常；观感「符号比字母占位宽」。同批还暴露：单行标签按自己的测量宽下盒，却折成两行（datepicker「选中：」32.37px 的盒）。
- **根因**：caret x / 命中列 = **逐字符测量宽累加**，而绘制 advance 是亚像素浮点。win/mac 的测量出参在 C 层被 `ceil` 成整数像素（Menlo 13px ≈7.8px/字 → 量成 8，一行 30 字符漂 6-7px）；不同字符取整误差不同，观感即「符号处跳」。Linux 无感纯属 Pango 的绘制 advance 被 hinting 钉在整数网格，测量与绘制恰好同口径——**不是 Linux 链路更对，是两边误差抵消**。
- **定案（文本层口径）**：测量**宽**全链浮点——`TextMetrics.width` 与 `pt_measure`/`pt_measure_font`/`rt_measure` 出参 `double`，C 桩不再取整；**高/基线保持整数**（行高取整反而稳定，行盒不随内容小数抖）。凡「盒宽(float) → 限宽(int)」一律 **ceil**：限宽比盒宽窄，按测量宽下发的盒就会自己折行——四处收口：绘制 `draw_box`、布局测高（`attach_text_measure`/`measure_text_height`）、`clamp_lines` 两处调用。`floor` 只许用于坐标采样与像素取整，不许用于限宽。
- **判据**：datepicker「测量宽与断行口径一致」守门用例（本轮真抓住）；text/ui 331 项全绿；真机 win/mac 光标逐字符贴字、点击落点即所指字符。
## 原生弹层窗三件：不激活、禁 GPU present 档、延迟上屏（2026-11-06，win/mac/linux 真机迭代）

菜单/下拉类弹层在原生档下是独立窗口，三端各自的坑都出在「这是个窗」上：

- **弹层窗不能抢键盘焦点**：菜单/下拉/提示类弹层开了以后，键盘（↑↓/回车/Esc）必须留在 owner 的触发件上——弹层窗的控件树里没有导航逻辑，抢走焦点就是键盘全灭（win 真机：方向/回车/搜索全无；GTK 真机：方向/回车无、Esc 靠弹层窗兜底通道碰巧能用）。三端不激活口径：win `WS_EX_NOACTIVATE` + `ShowWindow(SW_SHOWNA)`、mac `canBecomeKeyWindow` 按标志返回 NO + `orderFrontRegardless`、GTK `gtk_window_set_accept_focus(FALSE)` + `gtk_window_set_focus_on_map(FALSE)` 且不 `gtk_window_present`。另有一条隐蔽入口：`session_open` 建窗后无条件 `window.request_focus()`（win SetFocus / mac makeKeyWindow / GTK grab_focus），菜单类必须跳过。对话框相反——`want_focus=true` 保持激活，输入框才能打字。
- **点外收起不能靠失焦**：弹层不激活后永远收不到「失焦」，改由 owner 窗的按下事件判定：本 owner 的收起型弹层开着时，owner 上任何按下都是点外（弹层是独立窗，弹层内的点不会到 owner），收起最上层并**吞掉整段手势**（Down/Up 都不再派发）。不吞的话，点触发按钮会先点外收起、紧接的 click 又把它打开——「关了再开闪一下」（win 真机成因）。
- **弹层窗不能走 GPU present 档（L1）**：mac 真机症状「菜单空白、动鼠标才出来」的根因——弹层窗也挂了 Metal layer，而首帧是在窗口上屏**之前** present 的，CAMetalLayer 会丢弃；同时 `drawRect` 在 `l1.on` 时直接 return（像素交给 Metal 了），于是窗口显示后既无 Metal 帧也无 CG 帧，直到鼠标事件触发重绘再 present 一次。修法：`set_popup` 时 `l1.dead = 1`，弹层走纯光栅贴帧缓冲（内容小，完全够用）。win 的同款隐患（swapchain 首帧早于显示）一并禁。
- **显示必须晚于首帧内容**：`show` 时内容还没 mount，立刻上屏会露出空框（win 真机：菜单出现瞬间一道黑影；GTK：闪现）。三端统一「延迟显示」：`wm_show` 对弹层只记 `pending_show`，`wm_present` 填好首帧后 materialize（win ShowWindow+`need_draw=1`、mac orderFront+`setNeedsDisplay`+`need_draw=1`、GTK show_all+`wm_mark_draw`）——上屏时序不依赖任何平台回调。
- 关联的既有口径不变：`show` 前 `set_popup`（类型提示/transient 在映射期定）、Esc 兜底通道保留给对话框、点外收判定按 owner wid 隔离（多窗应用互不干扰）。

## 终端控件批实测坑：fmt 全仓重排、match 臂解析怪癖、终端 \n 口径（2026-11-07，terminal 五件 + 模板 v-for 落地批）

- **不要在仓库里跑 `moon fmt`**：它按自己的规范重排**整个 workspace**（一次实测改了 564 个文件，含大量与改动无关的示例/文档包），而本仓门禁只有 `moon check`、CI 也没有 fmt-check——重排会以「无关格式化」污染所有在途 diff。误跑后的自救：`git stash` 目标文件 → `git checkout -- .` → 取回。工具链对单文件的格式化结果与本仓手写风格也不一致（如 `pub fn` 签名折行、尾逗号），新增文件保持手写风格即可。
- **MoonBit 解析器怪癖（moonc 0.10.x，现象级记录）**：`match` 臂的花括号块里出现「`out.push((` 多行嵌套元组 + 后随 `for` 循环 + 再一个 push」的组合时，报 `[3002] Parse error: unexpected token }`（提示 expect `,` or `)`），且报错行指向块闭合括号、位置随前面代码增删整体漂移；把字符串拼接先 `let` 再 `push`、或 `match` 臂退化为表达式（无花括号）即过。同一函数「先 let 后 push」与「臂内直接 push」混用时的判据不稳定，没法给更精确的触发条件——遇到就把拼串提出来 `let`，别跟解析器较劲。同批附带：`derive(Eq, Debug)` 要配 `pub extend T with Eq::{equal, not_equal}` 与 `Debug::{to_repr}` 才不报 implicit_impl_as_method（icons 先例）；`Char::from_int` 已 deprecated，用 `Int::to_char()`（返回 `Char?`）。
- **终端 `\n` 口径偏离 VT**：`Terminal::feed` 的 `\n` = 回行首 + 下移（日志源都是裸 `\n`，按 VT 的「只下移留列」会让纯文本喂入呈楼梯）；进度条类原地重画走 `\r` 不受影响，真 PTY 批若需严格 VT 再按需分化（POSIX tty 的 ONLCR 本就把 `\n` 转成 `\r\n` 下行）。
- **`scan_dir_mng` 的 `.mng` 目录**：dev 产物目录 `.mng/` 名字恰以 `.mng` 结尾，模板扫描的点目录跳过必须放在 `.mng` 后缀判断**之前**，否则第二轮 `mng dev`/项目级 `mng build` 会把产物目录当模板撞名报错（同包撞名文本极具迷惑性，报的是「.mng 与 page.mng 都生成 page」）。同目录单文件撞名检查 `stem_conflicts` 同样要跳过目录。

## shell 平台感知映射的用例写死非 mac 预期：mac 本地门禁即红（2026-11-07）

`gs_trigger_of` 的 `CmdOrCtrl` 落平台主修饰（mac→Super，余→Control）、`notify_backend_name_of(WinBalloon)` 按平台报真名（mac→"un-user-notification"），两条 wbtest 却写死 Linux/Windows 预期值——真机 Windows 全绿，mac 本地跑门禁必红。修法：用例内按 `platform_is_macos()` 分支给预期（与实现同一判据），三端各自钉死全强度断言。写平台感知函数的单测时，预期值要么按平台分支、要么把用例挪进平台门禁清单，不能只在自己真机上验证。
## 工具链 2026-11 升级批：moonc 0.10.20 两条弃用 + async 并入 core（2026-11-07）

- `derive(...)` 后置语法弃用：`} derive(Eq, Debug)` 改为类型声明前的 `#derive(Eq, Debug)`（`///|` 与 doc 注释之后、`pub` 之前）。本仓 16 处已迁。
- `String.view(start_offset~, end_offset~)` 弃用，拆成 `clamped_view(start~, end~)`（越界钳制）与 `exact_view(start~, end~)`（须精确对齐）。本仓仅 mdparse 三处测试用例，按旧 view 的钳制语义迁 `clamped_view`，断言全过。
- `moonbitlang/async` 独立库并入 core：全仓排查（moon.mod / moon.pkg / .mbt / .mbtx / .mooncakes 传递闭包）零使用，无需迁移；`experience/adaptation/common.md` 旧条目中的 async 提及均为历史记录。`.agents/skills/moonbit-agent-guide/` 里指名 async 库的段落系上游指南文档，随上游更新，不在本仓代码面。

## mng lsp 定义跳转在非 ASCII 路径下空白：URI 百分号解码逐字节落 Latin-1（2026-11-08，Windows 远程会话真机反馈）

**现象**：win 远程会话里模板内 `{{ 引用 }}` 转到定义，peek 打开本文件但内容空白、头部路径中盘名段变乱码，行号是对的；mac/Linux 真机均正常。

**根因**：客户端把非 ASCII 路径按 UTF-8 百分号编码送来，`uri_to_path` 把 `%XX` 逐字节解成 Latin-1 字符（`%E7%AC%AC`「第」→`ç¬¬`），同文件定义的目标路径经 `path_to_uri` 再编码成双重编码 URI，VS Code 解一次码得到的乱码路径不存在 → peek 空白；行号来自文本解析所以正常。mac/Linux 仓库路径纯 ASCII，同一段代码不触发。

**修法**：`uri_to_path` 按 UTF-8 组装多字节序列解码（`utf8_seq_at`：首字节 + 1~3 个续字节，均须 %XX 形态且取值合法），不完整/非法序列原样保留；wbtest 补非 ASCII 解码、双向往返稳定、非法序列保留三条。`path_to_uri` 本就按 UTF-8 编码，无需动。

**判据**：LSP 报文里的 URI 解码/编码必须成对按 UTF-8 处理，往返稳定要有非 ASCII 用例钉住；Windows 会话常带中文盘名/用户名路径，纯 ASCII 仓库路径测不出这类坑。
## mng doctor 的 Windows MSVC 判据:vswhere 组件判定对能编译的机器误报红(2026-11-11,win 真机反馈)

- 现象:win 真机 `moon build --target native` 能过,doctor 却按 vswhere `-requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64` 判缺——组件 id 对不上的安装形态(全量 VS/异版 BuildTools/免安装器形态)会误报。
- 根因:把「信息查询」(vswhere 组件表)当成了「能力判定」。build.md §3 的口径本来就是「能过链接即通过」,gui/scripts/prebuild.py 同判据。
- 修正:vswhere 只做快路(查到 VCTools 免探针直接过);查不到/无 vswhere 一律落构建探针——`~/.mng/doctor/probe/` 最小 hello 工程真跑 `moon -C … build --target native`,以成败为判据,失败指日志 `~/.mng/doctor/native-probe.log`。POSIX 同款探针作收尾必选项(cc/pkg-config 便宜且准,保留;探针管端到端)。mac 实测探针全链 ~1.6s(warm)。
- 附带:winget 不普适(部分 Win10/LTSC 无),win 修复文案一律双路——winget 命令 + 官方安装器直链(VS BuildTools / python.org)。

## mng doctor 落盘路径的 Windows 形态坑:Git Bash 的 HOME 与盘符 ensure_dir(2026-11-11,win 真机反馈第二轮)

- 现象:win 真机 doctor 的 MSVC 项报 [!]「探针工程写盘失败」——探针工程根本没落下去,且该 [!] 当时仍放行了 ready(Warn 不拦),语义双错。
- 两处根因:①Git Bash 会设 `HOME=/c/Users/…`(MSYS 形态),原生 fs 与子进程都不认;②doctor 的递归 ensure_dir 只认 `/` 开头,`USERPROFILE` 的 `C:\Users\…`(拼成 `C:/…`)被当相对路径拼成 `./C:/…` 建目录失败。
- 修正:`home_dir` 按 win 优先 `USERPROFILE`;`ensure_dir` 认盘符(第二码元 `:` + 首码元 ASCII 字母,盘符段钉盘根);探针写盘失败从 Warn 改 Fail——「无法验证」不能放行 ready。
- 教训:第一轮 win 复验把 [!] 误读成 ✓ 并记了「win 腿过」,下一轮截图复读才发现。真机结论必须逐字核对状态符号,不能凭「应该会过」的预期带过去。

## moon prebuild 钩子去 py 探针:mbtx 路线成立(2026-11-11,mac 本机探针)

- 背景:`--moonbit-unstable-prebuild`(gui/gui-media/gui-gpu 三处 py 脚本)是应用开发者被强绑 Python 3 的根因。钩子按扩展名锁运行器——`.js/.cjs/.mjs`→node、`.py`→python、`.mbtx`→编译 wasm 用 moonrun,没有任意可执行的口子;**mbtx 是去 py 的正门**。
- 探针定案(官方参考 moonbitlang/moon docs/dev/reference/prebuild.md + /tmp 微模块实测):
  1. `.mbtx` frontmatter 必须用 `----`(三连字符及以上)围栏,内含 `import {}` 与可选 `permission(...)`(moon.pkg 文法);裸 import 块在 prebuild 语境不行(脚本模式可以)。
  2. **stdout 协议**:必须恰好输出一个构建配置 JSON(`vars`/`link_configs`/`rerun_if` 可选字段);诊断一律走 stderr——println 调试输出会让 moon 报「failed to deserialize prebuild script / expected value at line 1 column 1」,这个报错指脚本的 stdout 而非文件本身,极易误判为格式问题。
  3. 环境变量齐备:MOON_MOD / MOON_BUILD_DIR(输出目录,moon 预建,持久跨构建) / MOON_HOST_OS / MOON_HOST_ARCH / MOON_BACKEND / MOON_PROFILE / MOON_JOBS。
  4. 能力实测:进程 spawn(async/shell 跑 /usr/bin/touch)✓、写 MOON_BUILD_DIR ✓——prebuild.py 的全部动作(pkg-config 探测、编 stub 静态库、拼 link_flags)都在能力面内;gui/scripts/prebuild.py 407 行纯 spawn+文件+JSON,无网络依赖。
- 结论:gui 三处 prebuild 可整体移植为 prebuild.mbtx,应用开发者不再需要 Python 3;归档下载类 prebuild(gui-media/gui-gpu 的 ffmpeg/wgpu)是否含 HTTP 待移植时探,必要时下载逻辑前移 mng。win/linux 腿随移植批验证(mbtx 是 wasm+moonrun,平台差异面小)。

## prebuild.py → prebuild.mbtx 移植坑(2026-11-11,mac 对拍实证)

- **编译参数必须在源文件之前**:`cc -c … src.c -x objective-c …` 里 `-x` 只作用于其后的输入,落在源后面等于没给,ObjC 桩按 C 编报 `@protocol` 语法错——py 版参数序是 flags 在前,移植时要保持。症状有迷惑性:错误是「ObjC 语法错」而不是「flag 无效」。
- **全局常量**:mbtx 里 `let` 不收全大写名(编译器提示用 `const`),`const` 又只收不可变原始类型不收数组——数组全局用小写 `let` + 类型标注。
- **async 无 await**:MoonBit 没有 await 关键字,async fn 里裸调即可(skill 有载,从 py 翻译时容易顺手写出)。
- **stdout 纪律**:prebuild 协议要求 stdout 恰好一个 JSON,任何 println 调试输出都会变成「failed to deserialize prebuild script / expected value at line 1 column 1」——报错指向脚本 stdout 而非文件,极易误判;诊断一律 `@stdio.stderr.write`。
- 对拍口径:同机跑 py 与 mbtx,归一化 -L 路径后逐字段 diff(包名/flags/库文件/框架清单);mac 四条目 ALL-MATCH,hello 端到端链接过,二次构建 0.3s(stamp 命中)。

## gui-media prebuild 去 py 批坑(2026-11-12,mac 实测)

- **`moonbitlang/async/http` 不跟随 302**:GitHub/Gitee 的 release 下载链接一律 302 → CDN,`@http.get` 把 302 原样返回(带 location 头但不跟),py 的 urllib 默认跟随——直接移植会「全部镜像都没取到」。两条路:手动跟 location(限跳数),或换 `q2316367743/moonhttp`(axios 风格、基于 async、内置自动重定向/超时/取消);gui-media 用了后者,frontmatter import `"q2316367743/moonhttp/client" @mhttp`,`default_client().get(url)` + `resp.bytes()` 一趟到位。wasm(moonrun)后端可用。
- **mbtx 编译警告即失败**:prebuild 脚本编译有 warning(如 `package` 是保留字,做具名参数报 reserved_keyword)整个 prebuild 就挂,不像普通工程 warning 放行——参数名用 `pkg` 这类避开保留字,零警告才算过。
- **UInt 算术**:`UInt` 没有 `wrapping_add`/`not` 方法——`+`/`-` 本就是 wrap 语义直接用,取反写 `x ^ 0xFFFFFFFF`;`Int::to_uint`/`Byte::reinterpret_as_int` 等转换有的弃用有的不存在,可靠链是 `byte.to_int().reinterpret_as_uint()`。sha256 纯 MoonBit 实现 ~100 行,k256 表用 `Array[UInt]` 小写 `let`。
- **缓存口径顺带升级**:py 版 miniaudio.h 是纯存在性检查(损坏文件永不重下),mbtx 版落盘前 sha256 校验、已存在也校验,坏文件自动重取。
- **总预算实现**:`@async.with_timeout_opt(毫秒, () => …)` 现成,不必像 py 那样开线程 join;超时返回 None 换下一个镜像。
- 端到端实测:删 miniaudio.h 重建,GitHub 镜像 60s 预算内无产出自动换 gitee,下载 sha256 ✓ 落盘,moon check 零警告 + 42 测试全过。

## gui-gpu prebuild 去 py 批坑(2026-11-12,mac 实测)

- **MOON_HOST_ARCH 的值是 x86_64/aarch64**,py 版 platform.machine() 产出 x86_64/arm64——归一要两个都处理(x86_64→amd64、aarch64→arm64),只抄一边会在 mac arm 上「no wgpu-native asset」静默降级。
- **mbtx 无 zip 解包库**,上游 wgpu-native 资产又全是 zip 无 tar.gz——解压 spawn 平台工具(mac/linux `unzip -o`、Windows PowerShell `Expand-Archive`);unzip 缺失时给发行版安装提示。这是平台工具依赖的最小残留(unzip 比 python3 普遍得多,mac 自带)。
- **具名参数混用有解析坑**:`f(label=value~)`(label= 简写混合)与多具名 `f(a~, b~)` 报 parse error——调用处全写显式 `f(a=a, b=b)`。
- 端到端实测:删 vendor 重建,GitHub 直连 180s 预算超时自动换 ghfast 镜像,下载 sha256 ✓ → 解压出 libwgpu_native.dylib + include → marker 三行写入;1983 测试全过。

## mng 工具批坑(2026-11-12)

- **`*_test.mbt` 结尾的文件是黑盒测试**:`mng/run_check_test.mbt` 被收进测试编译单元,包内符号(顶层私有 fn)全部 unbound,且语法错误探针都不报——check 输出完全看不出这个文件存在。普通源文件命名避开 `_test.mbt` 结尾。
- **moon 嵌套会卡构建锁**:`moon run …/mng -- run` 里 mng 再 spawn `moon build`(同一 workspace)会等外层 moon 的构建目录锁,看起来像「日志停在 prebuild 不动」。本地冒烟要先把 mng 构建成二进制再直跑(CI 的 mng_scenario 同款);`mng dev` 真机用法(装的二进制)天然无此问题。

## prebuild.mbtx 本地门禁不覆盖(2026-11-12,CI 三平台全红复盘)

- **改 prebuild.mbtx 后本地 check/test 不抓语法错**:`moon check`/`moon test` 不编译 prebuild 脚本,target 缓存命中时连旧编译产物都不重建——坏文件本地全绿、CI 全新 checkout 才现形(2026-11-11 dir_of 改坏,gui/gui-gpu 两份同坏,三平台 CI 同时红,本地门禁零感知)。
- **验证手段**:改完 `moon run <模块>/scripts/prebuild.mbtx` 编译运行一遍(脱离 prebuild 环境运行期报错属预期,编译过即解析过);或清 target 重建再跑门禁。
- **mac 对拍不覆盖 linux/win 腿**:mbtx 移植只对拍过 mac,linux/win 分支首次在 CI 跑出两坑——① pkg-config 输出带结尾换行,`split(" ")` 切完末尾 token 是 `"\n"`,cc 报「linker input file not found」且文件名空(打印像空参),要按换行+空格双切分;② dir_of 认反斜杠的修复只改了 gui/gui-gpu,gui-media 漏改,win 的 `MOON_MOD` 是反斜杠路径原样返回,拼出 `moon.mod/media/...` 致 `@fs.open` 炸——三份脚本的公共函数改完要对账。
- **保留字参数名**:gui 的 `entry(package~, …)` 触发 `[0035] reserved_keyword` 警告(与 gui-media 移植批同款),具名参数一律避开保留字,用 `pkg` 这类名字。
- **L1 绑帧前必须探 surface capabilities**：wgpu-native 对 configure 的校验失败是进程级 panic（abort），桩侧的「逐字回退」纪律拦不住——CI 的 xvfb 软渲染（llvmpipe 队列族不支持呈现）实测炸出 `wgpuSurfaceConfigure: Surface does not support the adapter's queue family`（hello GUI 冒烟退出码 134）。修法：bind_frame 先 `wgpuSurfaceGetCapabilities`，返回非 Success 即判死永久回退（同款 alpha 档探测已先行存在，此次补的是状态检查）。
- **CI 的 GUI 步骤用 `MNG_WGPU_LIB=off` 显式关 L1**：get_capabilities 在 llvmpipe 上返回 Success 但 configure 仍炸队列族校验（capabilities 探测拦不住这一档），env 候选失败后桩还会继续试 vendor 路径（指错路径关不掉）——桩里加了 off/0/none 显式关闭档，无 GPU runner 与用户排障共用。
- **CI GPU 验证矩阵定案**：GPU 验证只在 mac 腿（GUI 冒烟步跑真 Metal 的 L1，continue-on-error 不卡门禁）；Linux/Windows runner 无真 GPU，GUI 相关步骤显式 `MNG_WGPU_LIB=off` 走 CPU 路径（验的是「L1 显式关闭/不可用时逐像素回退」这条断言）。编译链接层覆盖（gui-gpu 单测、showcase 构建）不受此开关影响。

## Int→Int32 批量替换漏 .mng 与生成器类型白名单（2026-11-13，CI 模板对账红复盘）

- **批量类型替换要扫全部内嵌 MoonBit 的扩展名**：`.mng` 的 `<script>` 段是 MoonBit 原文——Int32 批只扫 .mbt/.mbti，`vfor_demo.mng` / `hello.mng` 的 `Store[Int]` 漏改，CI 模板对账（按 .mng 重新编译与提交的 .gen.mbt 比对）必红。
- **.gen.mbt 不能手工改**：手工替换生成码里的类型后与模板源头脱节，而本地门禁不对账模板（同 prebuild.mbtx「本地门禁不覆盖」一条）——改模板源头 + 重新生成是唯一正道。
- **生成器两处类型白名单断线**：mngkit 的 `state_kind_of`（"Int"→reg.int 登记方法名）与 `etype_of_store`（"Int"→TInt，热更白名单的符号类型表）都按槽元素类型原文匹配——模板换 Int32 后 reg.int 不再生成（mng dev 热更状态保活断）、热更条件报「表达式符号未登记为顶层 Store」；两处白名单改认 "Int32" 后恢复（mngkit 44/44）。

## mng dev 场景三类假红：DEV_PID 子 shell、旧实例占坑、补丁先于应用就绪（2026-11-13，场景脚本连红复盘）

- **`DEV_PID` 是子 shell 不是 dev**：`(cd X && "$MNG" dev >log 2>&1) &` 的 `$!` 是子 shell pid，`kill $DEV_PID` 只杀壳、dev 成孤儿继续 watch——多轮场景各留一个 dev，同一工程并发扫码互删生成码（「about.gen.mbt 写了又没」的元凶）。修法：子 shell 内 `exec "$MNG" dev`，`$!` 即 dev 本体。
- **旧实例占坑会让新进程秒退**：应用是单实例语义——新进程发现已有实例就「唤醒旧实例并退出」，dev 记下的 pid 是秒退进程，补丁实际投给旧实例；旧实例注册表来自上一轮生成码，必然 stale（表现为「补丁缺 N 键」的假回归）。修法：dev spawn 前按可执行名 `pkill -9 -f <basename>`（受控单实例语义），并 spawn 后查 `@proc.alive` 报「已退出（单实例占坑？）」。
- **补丁不能早于应用就绪**：dev 通道（单实例套接字）在首页首次挂载时才建——首轮 build 完刚 spawn 就推补丁必然「连不上套接字」。修法：spawn 后等套接字文件出现（POSIX 10s 上限、`@proc.alive` 短路；Windows 无文件面短等），就绪后再进 watch。
- **删模板与 dev 的 build 抢跑**：场景脚本 `[NEW]` 出现就删模板，而 NEW 拍的 workspace build 还在跑（moon 报 `input about.gen.mbt missing`）——等 `[COLD] 应用已重启` 再删。

## mng 应用侧场景移出 CI：xvfb 腿偶发红不可收敛（2026-11-13，CI 移出门禁复盘）

- **症状**：`scripts/mng_scenario.sh` 本机 mac 连跑 4 轮 15/15 全绿，CI Linux（xvfb）/ mac 两腿仍偶发红，且 `continue-on-error` 挂着也不收敛——进程级 watch / 单实例 / HOT-COLD 编排对启动耗时与负载敏感，xvfb 冷缓存环境的时序与本机不可比，红绿不出信号。
- **口径**：该场景 2026-11-13 起从 ci.yml 两腿删除（连 continue-on-error 一起删），改「改到对应面时本地跑 `bash scripts/mng_scenario.sh`」兜底（AGENTS.md 已同步）；CI 剩余的 `continue-on-error` 只有 mac hello 存活冒烟一条，口径不变。

## py prebuild 全量 mbtx 化：移植语法坑与验证口径（2026-11-13，三模块移植实录）

- **MoonBit 与 Python 的形态差**（ffmpeg-mbt / gui-webview / experiment 三份移植实测）：无 `defer`（临时目录清理改显式 `rmdir`）；`String::replace` 是 labeled 参数（`replace(old=, new=)`）；`match` 带 guard 报 `partial_match`（guard 不计入分支覆盖，改取值后 `if`）；`Array` 的 `push` 不需要 `let mut`（`mut` 是绑定重绑语义，多余即 `unused_mut` 红）；`macro` / `define` / `fn` 均为保留字（参数命名避开）；async 调用无 `await` 关键字，直接调用。
- **sha256 常量表必须整块照抄**：k256 抄错一个常量（丢 `0xa81a664b`）不报编译错，运行期 `Array::at` 越界 trap；抄完与已验证实现 `grep -o | wc -l` 数个数（64）+ diff 全表。归档名指纹（sha256 前 8 位）与 py 时代同源，py 时代的旧桩归档能直接复用。
- **验证口径三级**：`MOON_MOD` / `MOON_HOST_OS` 手工注入直跑 mbtx（协议语法门禁）→ 借 moon 真协议环境找产物落点（桩是否编进 `MOON_BUILD_DIR`）→ PATH 注入假 python 桩（stub 报 `PYTHON-INVOKED` 并退出 127）跑 `moon build examples/hello examples/audio examples/video --target native` 全链绿。workspace 的 prebuild 阶段是模块图全量执行，任何一个 py prebuild 都挡住不相干模块的构建。
- **下载口径统一**：py 时代的「双镜像并行竞速」在 mbtx 一律改「串行按序 + 总预算」（与 gui-media 同口径）；预算按体积给足（mac 归档 240s、win dll 归档 480s）。zip/tar.gz 解包统一 spawn `tar`（三平台自带，bsdtar 支持 zip）。
