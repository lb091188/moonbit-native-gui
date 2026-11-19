# 构建与运行

原理与逐平台实测记录在 [experience/adaptation/common.md](https://github.com/lb091188/moonbit-native-gui/blob/master/experience/adaptation/common.md)「构建与链接」。

## 1. 装 MoonBit 工具链

```sh
# Linux / macOS
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
# Windows (PowerShell)
irm https://cli.moonbitlang.com/install/powershell.ps1 | iex
```

装完 `moon version --all` 看三件套（moon / moonc / core）是不是同一次安装的配套版本——非交互终端里半途失败的 `moon upgrade` 只换二进制、不动 `~/.moon/lib/core`，落得混搭时报的是「代码没问题却 no method」。

## 2. 装开发依赖

库走原生 FFI，构建期要三样：**C 工具链、pkg-config、Linux 上的 GTK3 / Pango / FontConfig / X11 开发包**。2026-11-11 起链接预构建移植为 MoonBit 脚本，2026-11-13 起 `gui` / `gui-media` / `gui-gpu` / `gui-webview` / `ffmpeg-mbt` / 探针模块的 prebuild 全部 mbtx 化，构建**不依赖 Python**（旧 prebuild.py 时代它是必需依赖）。

### Linux（Debian / Ubuntu 系）

```sh
sudo apt install build-essential pkg-config \
  libgtk-3-dev libpango1.0-dev libfontconfig1-dev libx11-dev
```

只有用到对应能力时才需要再装：内嵌 WebView（`@web`）加 `libwebkit2gtk-4.1-dev`；媒体模块（`NoahLiu/gui-media` / `ffmpeg-mbt`）加 `libavformat-dev libavcodec-dev libswscale-dev libswresample-dev libavutil-dev`。

**C++ 编译器也在必需之列**：`gui/text/dwrite_text.cpp` 在**每个平台**都要过一遍编译（非 Windows 平台编成空翻译单元，防与归档双定义），所以 `build-essential` 得真把 g++ 装上——机器上只有 gcc 时报的是 `cc: error trying to exec 'cc1plus'`，补 `sudo apt install g++` 即可。

（历史坑，已解除）旧 prebuild 是 Python 脚本时，`python` 指向 2.7 的机器会让构建起手就红；prebuild 已 mbtx 化，本条仅存档。

### 低版本发行版（deepin 20 / Debian 10 基线）——不承诺支持

这一档我们**不测也不保**（墙在最后一条），但踩坑记录留在这里给自救用：

- **解释器**：~~`python` 指向 2.7 时按 §6 第一行换成 3~~ 已随 prebuild mbtx 化解除，构建不再调 Python。
- **C++ 编译器是硬前置**：`gui/text/dwrite_text.cpp` 三平台都要编，缺 g++ 报 `cc1plus`。
- **开发包**：Debian 10 基线的 apt 包名与上面那份清单同名可装（GTK 3.24 / Pango 1.42）。
- **两处能力会降级**：内嵌 WebView 探 `webkit2gtk-4.1`，Debian 10 只有 4.0 → 退占位实现；媒体模块要的系统 ffmpeg 版本偏旧，未实测。
- **不支持的真正原因在工具链，不在本库**：MoonBit 自带 runtime 的 C 源（`~/.moon/lib/runtime/process.c` / `thread_pool.c`）无条件用 `SYS_pidfd_open`。deepin 20 实测：内核头已是 **5.18**（`pidfd_open` 是 5.3 引入的，内核侧有这个调用），却仍报 `undeclared`——机理推断是这个宏来自 **glibc 构建时冻结的 syscall 表**（该机 glibc 2.28 对着 4.18 时代的头生成），所以**升 `linux-libc-dev` 补不上**（该机已是最新）。这一步之前，本库的 prebuild 与 C/C++ 桩全部编过。（推断未在该机 grep 取证；要自救可试 `MOON_CC` 包一层补 `-DSYS_pidfd_open=434`，x86_64 号，未实测。）

### macOS

只需要 Xcode 命令行工具，GTK 与 brew 一概不用——窗口、文本、图片解码走系统 Cocoa / CoreText / ImageIO 框架，由 prebuild 直接编 Objective-C 桩并下发 `-framework` 参数：

```sh
xcode-select --install
```

媒体模块另需 ffmpeg：`brew install ffmpeg`，或让 prebuild 从 Release 拉我们自编的 arm64 归档（§10）。

### Windows（10 / 11，x64）

需要 MSVC C++ 工具链（构建不依赖 Python）。工具链选 VS 2022 Build Tools 的「使用 C++ 的桌面开发」工作负载：

```powershell
winget install Microsoft.VisualStudio.2022.BuildTools -e --override "--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
```

moon 在 Windows 上定位 MSVC **开箱即用**，普通 PowerShell / Git Bash 直接 `moon run`，不必进「x64 Native Tools Command Prompt」或手动 `call vcvars64.bat`；「还要装 CMake 与 ATL」是旧 CMake 构建链的口径，本栈不适用。

## 3. 环境自检

```sh
moon version --all                 # 三件套配套
pkg-config --modversion gtk+-3.0   # Linux：打出版本号 = 开发包齐
cc --version                       # Linux / macOS：C 工具链在位
```

Windows 没有 pkg-config 这一步，判据直接是 `moon build --target native` 能过链接。

## 4. 构建与运行

### 在自己的工程里

```sh
moon add NoahLiu/native-gui
moon run . --target native
```

链接参数由库的 prebuild 自动下发给依赖它的 main 包，`moon.pkg` 里不写 `link`、不写 `cc-link-flags`——写了与它冲突（§8）。

### 在本仓库里

仓库是 `moon.work` workspace，成员含库、探针、五个子模块、七个示例与工具。各示例的模块依赖与额外安装：

| 示例 | 模块依赖 | 额外安装 |
|---|---|---|
| `hello` / `components` / `sysmonitor` 等 | 仅 native-gui | §2 基础清单即可 |
| `browser` | + `gui-webview` | Linux 加 `libwebkit2gtk-4.1-dev`；Windows / macOS 用系统 WebView，无需额外安装 |
| `audio` / `video` | + `gui-media`（需 ffmpeg） | Linux 加 §2 的 `libav*-dev` 五件；Windows / macOS 构建期自动取得，见下 |

**先分清两种跑法**：

```sh
# 只想看效果：绕开 workspace，示例按注册表里已发布的库版本解析
cd examples/hello && MOON_WORK=off moon run .
```

这条只解析该示例自己的依赖闭包（`native-gui` + `yoga-mbt` + 传递依赖），**其余成员的 prebuild 一概不跑**——媒体、探针、ffmpeg 的开发包齐不齐都与你无关。代价是用的是注册表里的发布版，不是你工作区里改过的代码：**连库的 prebuild 脚本也是发布归档里那一份**，仓库里改的脚本要重新发包后这条路径才吃得到。

```sh
# 要连着库的改动一起跑：留在 workspace 里（默认）
cd examples/hello && moon run .
```

这条要整个 workspace 的模块图都能过：moon 对每个带 prebuild 的成员逐个跑脚本，任一非零退出就挡住整次构建，所以 §2 的开发包（含媒体模块那五个 `libav*-dev`）得装齐。构建**按模块点名，别裸扫全仓**：不带限定的 `moon test` 会连带 examples / experiment / 媒体模块，其中有平台适配缺口，不是库缺陷。

```sh
cd gui && moon check                       # 库门禁：零错误零警告
cd gui && moon test ui render text theme icons sys input win dbus chart mdview style base shell widget
cd examples/hello && moon run .            # 任一示例：进目录跑
moon build examples/components --target native   # 仓库根按路径点名构建
```

**audio / video 的 FFmpeg 动态库（本地源码跑）**：

- **Linux**：链系统 FFmpeg，运行用系统运行库，无需额外动作。
- **Windows**：构建时自动把 5 支 dll 取到 `modules/ffmpeg-mbt/vendor/win/bin/`（不入库，缺则从 Release 归档下载），该目录已编进 exe 作加载兜底——本地 `moon run .` 直接能跑。把 exe 分发给别人才需要 dll 与 exe 同目录，见 §10「Windows 运行期 ffmpeg dll」。
- **macOS**：`brew install ffmpeg` 优先；没装 brew 时构建期自动取预编译 dylib 到 `modules/ffmpeg-mbt/vendor/mac/` 并设好 rpath，本地直接跑。分发才要复制 dylib 进 `.app` 并重签（发布工作流代劳）。

### 产物落点与发布构建

```sh
moon build examples/hello --target native --release --strip
```

产物按模块名走：`_build/native/<debug|release>/build/<模块名>/<模块名>.exe`。MoonBit native 后端**三平台都带 `.exe` 后缀**（含 Linux/macOS），拿去用时改名。macOS 上 `scripts/make_app.sh` 把产物包成 `.app`。

## 5. 不想编：预构建二进制

GitHub Releases 现有两条：**Binaries**（tag `bin`，由 `release-bin.yml` 自动发布）——三平台 zip（`bin-windows-x64.zip` / `bin-macos-arm64.zip` / `bin-linux-x64.zip`），每包含 hello / components / browser / audio / video 五个演示应用与第三方许可，体验点与运行要求见 [experience.md](experience.md)；国内直连可用 [Gitee 镜像](https://gitee.com/noahliu0911/moonbit-native-gui/releases/tag/bin)；以及 `vendor-v1`（构建期 vendor 输入，见 §10）。

不想下载就按 §4 编一条示例——`examples/hello` 从零到窗口只吃 §2 那份依赖清单。

## 6. 常见失败 → 处置

| 现象 | 根因 | 处置 |
|---|---|---|
| 在仓库里跑 `examples/hello`，prebuild 却报**别的模块**缺依赖（如 `ffmpeg(prebuild): 缺少 libavformat 开发包`） | 不是示例依赖写错：moon 对 workspace 模块图里**每个**带 prebuild 的模块逐个跑脚本，任一非零退出就挡住整次构建；媒体模块在 Linux 上是硬失败（Windows / macOS 分支降级为空链接条目） | 照它打出的那行 apt 装上：`sudo apt install -y libavformat-dev libavcodec-dev libswscale-dev libswresample-dev libavutil-dev`；只想跑示例就 `MOON_WORK=off moon run .`（绕开 workspace，见 §4） |
| `cc: error trying to exec 'cc1plus': execvp: 没有那个文件或目录`（编译 `dwrite_text.cpp` 时） | 机器上没有 C++ 编译器：`gui/text/dwrite_text.cpp` 三平台都要编一遍，非 Windows 也只是编成空翻译单元 | `sudo apt install g++`（`build-essential` 本应带上它，装不全就单独补） |
| 仓库里已经修好的 prebuild 报错，在 `MOON_WORK=off` 下又原样出现（行号都一样） | 那条路径跑的是**注册表归档里那份脚本**（落在 `examples/<示例>/.mooncakes/NoahLiu/native-gui/scripts/prebuild.py`），注册表侧改不动 | 验证修复就回 workspace 跑（去掉 `MOON_WORK=off`）；要让消费方吃到只能**重新发包**——脚本随包发布，属对外 API 面的一部分 |
| `~/.moon/lib/runtime/process.c: error: 'SYS_pidfd_open' undeclared` | 地板在 **MoonBit 工具链自带的 runtime C 源**：它无条件用 `SYS_pidfd_open`，而这个宏来自 glibc 构建时冻结的 syscall 表（老 glibc 就算配新内核头也没有它，升 `linux-libc-dev` 补不上）。与本库无关，此时本库的 prebuild 与桩都已编过 | 换 glibc 较新的机器 / 发行版；这一档**不承诺支持**，自救口径见 §2「低版本发行版」 |
| prebuild 在 stderr 打「缺少 gtk+-3.0 开发包」与「已降级占位桩」提示后继续走，构建不炸 | 开发包没装全：prebuild 降级——占位桩只保链接符号不断，渲染走纯光栅、文本量宽走内建回退估算（见 §12 三档分工），测试照跑，但观感与真字体度量不可比 | 开发与使用就补 §2 的 apt 清单，重跑 `moon build`（仍链旧结果就 `moon clean`）；只想跑测试与逻辑断言，降级提示可以不管 |
| Windows 上 `moon install <工具包>`（或 `moon build --release`）爆 `LNK2019: 无法解析的外部符号 __imp_FindWindowW` 一类，**同一条 `moon build` 不加 `--release` 却是绿的** | 两种构建画像的链接行不同：debug 由 moon 追加显式系统库（`libcmt kernel32 shell32 user32 dbghelp …`），release 只有 `/link /LIBPATH:` 一行，系统库全靠对象自带的 `/DEFAULTLIB`。`tools/native-gui-tools` 这类**不挂 prebuild**的模块拿不到 `link_configs`，Win32 符号就成悬空引用 | 在用到该 API 的 `.c` 里写 `#pragma comment(lib, "user32.lib")`——MSVC 把 `/DEFAULTLIB` 写进该 TU 的 `.drectve`，链接器抽到这份 `.obj` 时自动带库，依赖方零配置。挂了 prebuild 的库模块仍按 §8 补链接串 |
| Windows 链接期爆 `error LNK2019: 无法解析的外部符号 __imp_SetDeviceGammaRamp`（或任意 `__imp_*`），紧跟着 `fatal error LNK1120` | `__imp_` 打头的是 Win32 **导入函数**：桩编得过，但它所在的 `.lib` 没链上。`SetDeviceGammaRamp` 在 `gdi32.lib`，旧版 `prebuild.py`（现 prebuild.mbtx）的 sys 包 Windows 分支当时缺它；`sys_stub.obj` 整个进不了链接，所以每个用到 sys 的 exe 都断在同一条 | 更新到当前 master（sys 包已补 `gdi32.lib`）。自己加 Windows 直调时按归属补库：取 DC 与消息循环→`user32`、DC 绘图与 gamma 斜坡→`gdi32`、注册表→`advapi32`、`ShellExecuteW`/`SH*`→`shell32`、COM 基础→`ole32`、`SysAllocString`→`oleaut32`、WMI 的 GUID 常量→`wbemuuid` |
| 构建不中断，但 MSVC 刷一片 `warning C4090: 不同的"const"限定符` / `C4113: 参数列表不同` / `C4133: 类型不兼容` | 桩里的 COM 写法与 SDK 头对不上三类：`const` 的 Vtbl 赋给非 `const` 的 `lpVtbl`、一个实现函数塞进多个接口的 vtable（`self` 形参类型必须逐接口各写一份）、`LPWSTR*` 与 `LPCWSTR*` 之差 | 不挡构建，但每一行都指着「这个槽运行期按 SDK 那份签名被调用」——照 `include/WebView2.h` 的声明逐条改桩；`modules/gui-webview/webview/webview2_stub.c` 三类已清 |
| `Package 'webkit2gtk-4.1' not found`，且只有 `@web` 用不了 | 不是故障，是设计：探不到 webkit 时 `@web` 退成占位实现、能力报 `Unsupported`，不让整包链接失败 | 要内嵌浏览器就装 `libwebkit2gtk-4.1-dev` |
| `moon.mod.json ... is no longer supported` | 依赖缓存里第三方包带的还是旧清单（注册表侧改不动） | 对 `.mooncakes/**/moon.{mod,pkg}.json` 逐个 `moon fmt`，循环到解图收敛（CI 同口径） |
| 改了 `gui/<包>/*.c` 但行为没变，`moon build` 说 `no work to do` | C 桩改动不一定触发重链 | §9 |
| prebuild 卡在下载或报 sha256 不符 | vendor 文件缺且镜像不可达 | §10：`NATIVE_GUI_VENDOR_BASE` 换源，或按提示手工放置 |
| Windows 跑 audio / video 报缺 dll | 运行期 ffmpeg dll 不在位 | §10「Windows 运行期 ffmpeg dll」 |
| `Failed to acquire file lock` | 同一构建目录上还有另一个 moon 进程（IDE 与终端同时在跑） | 等前一个结束再跑 |

`moon check` 不执行 prebuild（只查类型与警告），所以「check 全绿、build 起手红」基本就是上面 prebuild 那几条——别把它当成代码问题去翻库源码。

## 7. 链接从哪来

- moon 在构建时执行各模块的 prebuild 钩子（`moon.mod` 的 `options(--moonbit-unstable-prebuild)` 挂 `scripts/prebuild.mbtx`），按当前系统输出 `vars` 与 `link_configs`，并自动传播给依赖本库模块的所有 main 包。脚本由 moon 自带的 MoonBit 运行器执行，机器上不需要任何解释器。
- prebuild 同时探测系统库：Linux 找 GTK3 / Pango / FontConfig / X11，内嵌 WebView 找 `webkit2gtk-4.1`，媒体模块找 ffmpeg。探不到 GTK 就降级——占位桩只保链接符号不断，stderr 给降级提示（行为见 §6 与 §12）；探不到 webkit 则 `@web` 退成占位实现、能力报 `Unsupported`，不让整包链接失败。
- 结果：链接 flags 不用写也不该写，由 prebuild 统一给出。

## 8. 贡献者须知

- 库包不放 `link` 段——moon 会为库包生成无 `main` 的 `.exe`，构建失败。
- 不手写 `cc-link-flags`——链接一律由 prebuild 下发，手改会与它冲突。
- 新增平台 C 能力按「单一 `stub.c` 多分支 + prebuild 宏」组织，先例见 `gui/win/stub.c`；链接参数仍归 prebuild。
- Windows 分支每用一个新的 Win32 API，先查它属于哪个 `.lib`，同批把库补进 `gui/scripts/prebuild.mbtx` 对应包的 Windows 链接串——桩编译期不查库，缺库只在链接期以 `LNK2019 __imp_*` 露头（见 §6）。
- 不挂 prebuild 的模块（`tools/native-gui-tools` 这类独立模块）没有 `link_configs` 可下发，改为在该 `.c` 里 `#pragma comment(lib, ...)`，让 `/DEFAULTLIB` 随 `.obj` 的 `.drectve` 段走；先例 `tools/native-gui-tools/inst/inst_stub.c`（user32）、`modules/ffmpeg-mbt/src/ffmpeg_win_dll.c`（delayimp）。

FFI 声明与蹦床对齐的规范见 `.agents/skills/moonbit-c-binding/`。

## 9. 唯一的坑：改了 C 桩不重链

moon 把 `.c` / `.cpp` native-stub 编进静态库，改桩代码不一定触发重链：`moon build` 可能报 `no work to do` 并继续用旧 exe，`moon test` 的测试二进制同理会链旧归档。两种情况的表现都是「代码改了行为没变」，旧崩溃可能还在。

**判别**：改过 `gui/<包>/*.c` 或 `.cpp`，但 `moon build` 说没活干、跑出来还是老样子。

**处理**，二选一：

```sh
moon clean                 # 全量重建，最省事
# 或只删对应产物（路径随构建布局与 target 变）：
rm -rf gui/_build/native/**/build/<包>/     # 该包重编
rm -rf _build/native/debug/build/examples/<示例>/<示例>   # 该示例重链
```

删完再 `moon build` / `moon test`，会重新编译桩并链新 exe。

**webview / media 这类 prebuild 专编归档多一层**：`modules/gui-webview/webview/webkit_stub.c` 不走 native-stub，由 prebuild 专编成 `libgui_webview[-mac]-<指纹8>.a`（落在该模块 prebuild 的输出目录）——**归档文件名里编着源码 sha256 前 8 位**。源码变 → 归档名变 → `link_flags` 变 → moon 失效链接目标、exe 必然重链；三段缺一不可（归档重编而 link_flags 没变时，moon 不重链，exe 一直跑旧桩——真机踩实过）。判定「改动进没进」用符号最稳：

```sh
nm modules/gui-webview/build/libgui_webview-*.a | grep -c gtk_file_chooser_native_new
```

新代码引用的符号旧归档里必为 0；查 exe 同理（`nm -D <exe> | grep <符号>`，GTK/WebKit 动态链接的符号以未定义形式出现）。改这类桩后拿不准就：`rm -rf modules/gui-webview/build && moon clean`。

排查时先用新的 main 目标复现一轮：新 target 每次都是新链接，若 main 正常而 test 崩，基本可断定 test 二进制链了旧归档，不是代码逻辑问题。更细的平台实测记在 [experience/adaptation/common.md](https://github.com/lb091188/moonbit-native-gui/blob/master/experience/adaptation/common.md)。

## 10. vendor 大文件与镜像

`WebView2.h`、`WebView2LoaderStatic.lib`、`miniaudio.h` 三个第三方文件，以及 FFmpeg 的两个运行期归档（Windows 的 dll zip、macOS arm64 的 dylib tar.gz），都不入库——入库会永久占用 git 历史体积，改由**各自模块的 prebuild** 在缺失时下载。已在位的不动：prebuild 只补缺。

| 文件 | 下载方 | 何时下载 |
|---|---|---|
| `WebView2LoaderStatic.lib`（11 MB）、`WebView2.h`（2.8 MB） | `modules/gui-webview/scripts/prebuild.mbtx` | **仅 Windows**；Linux / macOS 直接跳过，省下 14 MB |
| `miniaudio.h`（4 MB） | `modules/gui-media/scripts/prebuild.mbtx` | 缺失即下（各平台都要编）；已就位也会校验 sha256，损坏自动重取 |
| `wgpu-*-release.zip`（30–64 MB，wgpu-native 动态库 + 头） | `modules/gui-gpu/scripts/prebuild.mbtx` | `vendor/` 缺 `.ok` 标记即下（按平台取对应资产）；解压 spawn 系统 unzip（Windows 走 PowerShell `Expand-Archive`） |
| `ffmpeg-windows-x64-9.0-lgpl-shared.zip`（约 64 MB，7 支 dll） | `modules/ffmpeg-mbt/scripts/prebuild.mbtx` | **仅 Windows** 且本地缺运行期 dll；取不到再退 BtbN 上游 |
| `ffmpeg-macos-arm64-9.0.2-lgpl-shared.tar.gz`（约 10 MB，5 支 dylib + 头） | 同上 | **仅 macOS arm64** 且缺 `vendor/mac`；装了 brew ffmpeg 的机器走 pkg-config，不下载 |

FFmpeg 这两个归档**由我们制作**（macOS 自编 LGPLv3、@rpath 化，Windows 是从 BtbN lgpl-shared 重打包运行期 dll），不是上游现成产物——所以它们的授权文本与源码提供义务单独记在 [THIRD-PARTY-NOTICES.md](/THIRD-PARTY-NOTICES.md)。

- **校验优先**：sha256 与 prebuild 里的常量一致才落盘，任何镜像都可验证。
- **镜像**：GitHub Release → Gitee，都**不做延迟探测**，统一**串行按序**（sha256 过了才落盘；py 时代 webview / ffmpeg 的并行竞速形态已随 mbtx 化收口，不再保留）。
- **超时**：单源 socket 超时之外另加**总预算**兜底（socket 级超时挡不住 DNS 挂起与慢速滴流，只靠它会把一次构建吊死）。预算按体积分档：`miniaudio.h` 与 WebView2 两件套 **60 秒**，mac 归档 **240 秒**，Windows 的 64 MB dll 归档 **480 秒**——否则「数据还在流、预算先到」会把那一路误判成失败。
- **换源与加源**：`modules/gui-webview/scripts/prebuild.mbtx` 的 `vendor_bases`、`modules/gui-media/scripts/prebuild.mbtx` 的 `vendor_bases` 各改一行（另有同文件管 dll 归档，镜像与超时口径同源）。三处**刻意各留一份**，每个模块都要能独立发布。**Gitee 的用户名与 GitHub 不同**（同一个仓在 gitee 归 `noahliu0911`，GitHub 是 `lb091188`），照抄会 404，而且只在 GitHub 不通时才暴露。
- **内网与离线**：环境变量 `NATIVE_GUI_VENDOR_BASE` 接受单个 base 或逗号分隔列表，排在最前（指定自定义源时只走自定义源，不并行外网）。也可手工把文件放到对应路径。
- 全部失败时 prebuild 不中断，只打印手工放置提示，把缺文件错误留给链接期。

授权与来源见 [THIRD-PARTY-NOTICES.md](/THIRD-PARTY-NOTICES.md)。

### Windows 运行期 ffmpeg dll（audio / video 的运行前置）

`ffmpeg-mbt` 在 Windows 由 prebuild 用 `vendor/*.lib` 导入库链接，生成的 exe 加载期依赖 5 支 dll：`avcodec-63` / `avformat-63` / `avutil-61` / `swscale-10` / `swresample-7`；另 `avdevice-63` / `avfilter-12` 与 vendor 同版本配套，口径列全 7 支。

- **缺 dll 不再启动即崩**：这 5 支已改延迟加载，构建期还把 `vendor/win/bin` 的绝对路径编进 exe——`ffmpeg_supported()` 首次调用按「exe 同目录 / PATH → 构建期目录」顺序找（`src/ffmpeg_win_dll.c`，`/DELAYLOAD`），找不到时媒体后端报不可用，窗口照常起。
- **开发期不用搬 dll**：上表的 `ffmpeg-windows-…zip` 下载干的就是这件事——解到 `modules/ffmpeg-mbt/vendor/win/bin`（不入库），加载兜底直接用它；`moon add` 引进来的工程同样吃这条路径。macOS 对称：`vendor/mac` 或 brew ffmpeg（pkg-config）；Linux：系统 ffmpeg 开发包（`libav*-dev`，pkg-config 探测）。
- **发布 / 分发才需要 app-local**：dll 与 exe 放同一目录（加载器第一顺位），或脚本代劳（缺 exe 先自动 `moon build`，`--run` 补完直接启动）：

```sh
python scripts/win_ffmpeg_dll.py                 # audio + video 一起补齐
python scripts/win_ffmpeg_dll.py audio           # 只补 audio
python scripts/win_ffmpeg_dll.py video --run     # 补齐后启动
python scripts/win_ffmpeg_dll.py --dll-dir D:\ffmpeg\bin   # 手头已有 bin 目录
python scripts/win_ffmpeg_dll.py --dry-run       # 只打印计划，不动文件
```

  来源顺序：`--dll-dir` → exe 同目录 → prebuild 落点 → PATH → winget → scoop → 旧缓存；`moon clean` 后重跑一次（dll 跟 exe 目录走）。
- **手工取 dll 的口径**：winget 装 `BtbN.FFmpeg.LGPL.Shared.9.0`，与 `vendor/` 导入库同源（BtbN / LGPL / **shared** / 9.0）。⚠️ 别拿 `Gyan.FFmpeg` 当来源——静态构建，`bin/` 只有三个 exe、零 dll，借不出来；BtbN 的 `*.GPL` static 分支同理。认准 **Shared**；包管理器只把文件放到某处，不能让 dll 被找到，仍要 app-local 或 PATH。
- 对外发预构建二进制时 dll 随包与版本串义务见 [THIRD-PARTY-NOTICES.md](/THIRD-PARTY-NOTICES.md)。

## 11. 新增示例模块

依赖隔离靠模块、不靠包：`moon.mod` 的 import 决定整个模块的依赖闭包，`moon.pkg` 只能从模块已解析的依赖里挑包。所以「某个示例不拖累其它示例」必须做成**每示例一个模块**，把多个示例塞进同一份 `moon.mod` 会重新耦合。新增一个示例：

1. 建目录 `examples/<name>/`（含 `main.mbt` + `moon.pkg`），写一份**自己的** `moon.mod`：
   `name = "NoahLiu/native-gui-examples-<name>"`，import 只列该示例真用到的模块。
2. 把 `examples/<name>` 追加进 `moon.work` 的 `members`。
3. 需要在 CI 里构建/冒烟就点名追加，别改成一个 `moon build` 扫整个 workspace（失败看不出是谁坏的）。
4. 产物路径按模块名走：`_build/native/<mode>/build/NoahLiu/native-gui-examples-<name>/native-gui-examples-<name>.exe`
   （`scripts/make_app.sh`、`release-bin.yml` 依赖这个口径）。

演示资产放各自示例的 `examples/<name>/assets/`（不是模块、不要往里放代码；旧共享目录 `examples/assets/` 已拆入各示例）。

## 12. 测试的三档分工

测试按「谁来跑、验什么」分三档，互相不替代：

| 档 | 覆盖 | 归谁 |
|---|---|---|
| 无头断言 | `moon test` 全套——逻辑与数量判据，无显示环境全绿 | CI 与贡献者裸机 |
| 平台冒烟 | hello 存活、编辑器与 mng 场景——真窗链路通不通 | CI 的 xvfb 步 |
| 真机人工清单 | 观感、输入法、读屏、托盘通知落系统——看着对不对 | 使用者按测试文档执行 |

- 无头：不开真实图形窗口、在无显示环境运行测试或渲染的方式。
- xvfb：Linux 的虚拟 X 显示服务，内存里模拟一块屏幕供真窗测试。
- 判据一句话：无头 = `moon test` 无显示环境全绿；xvfb 只留给真窗冒烟；真机清单不变。
- 缺 Linux 开发包的机器同样落在无头档：prebuild 降级占位桩，纯光栅渲染 + 文本走内建回退估算，测试照跑。CI 的 Linux bare 腿固化这条路径。
- 内建回退估算：文本后端不可用时按字符宽表估算尺寸的纯 MoonBit 兜底，量得出但画不出字形。

## 13. 相关

- 平台适配坑与验证：[experience/adaptation/](https://github.com/lb091188/moonbit-native-gui/tree/master/experience/adaptation/)
- 从零写代码：[上手体验](tutorial.md)
- 不写代码先看效果：[跑预构建包](experience.md)
- 组件与 API：[组件总览](../components/index.md)
