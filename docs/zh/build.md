# 构建与运行

从零到跑起来的完整流程：装什么、敲什么命令、产物落在哪、不想编的时候拿什么、报错怎么处置（§1–§6）。后半段讲这套构建的机制——链接参数怎么托管、改桩不重链的坑、vendor 文件从哪来（§7–§12）。原理与逐平台实测记录在 [adaptation.md](https://github.com/lb091188/moonbit-native-gui/blob/master/proposals/adaptation.md)「构建与链接」。

## 1. 装 MoonBit 工具链

```sh
# Linux / macOS
curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash
# Windows (PowerShell)
irm https://cli.moonbitlang.com/install/powershell.ps1 | iex
```

装完 `moon version --all` 看三件套（moon / moonc / core）是不是同一次安装的配套版本——非交互终端里半途失败的 `moon upgrade` 只换二进制、不动 `~/.moon/lib/core`，落得混搭时报的是「代码没问题却 no method」。

## 2. 装开发依赖

本库自绘、走原生 FFI，构建期要四样：**C 工具链、pkg-config、Python 3（≥3.7）、Linux 上的 GTK3 / Pango / FontConfig / X11 开发包**。Python 3 不是可选依赖——链接参数由 `gui/scripts/prebuild.py` 产出，moon 构建 native 目标时执行它（谁去执行它见 §6 第一条）。

### Linux（Debian / Ubuntu 系）

```sh
sudo apt install build-essential pkg-config python3 \
  libgtk-3-dev libpango1.0-dev libfontconfig1-dev libx11-dev
```

只有用到对应能力时才需要再装：内嵌 WebView（`@web`）加 `libwebkit2gtk-4.1-dev`；媒体模块（`NoahLiu/gui-media` / `ffmpeg-mbt`）加 `libavformat-dev libavcodec-dev libswscale-dev libswresample-dev libavutil-dev`。

⚠️ **`python` 这个命令本身必须是 Python 3**。deepin 20、CentOS 7 一类机器上 `/usr/bin/python` 还是 2.7，moon 会优先拿它跑 prebuild，脚本开头的中文注释直接触发 `SyntaxError: Non-ASCII character ... pep-0263`，整次 native 构建起手就红。两条修法见 §6 第一行。

### 低版本发行版（deepin 20 / Debian 10 / CentOS 7 一类）

这类机器的差别集中在两处：**`python` 指向 2.7**，以及 **Python 3 本身只有 3.7**。

- **先解决解释器**：按 §6 第一行把 `python` 换成 3，或临时 `MOON_PYTHON_OVERRIDE=python3`。
- **Python 3.7 够用**：五个 prebuild 脚本按 **3.7 口径**写——只用 f-string、`subprocess.run(capture_output=)`、`Path` 这些 3.7 就有的面，不用 3.8+ 才有的参数与语法（`Path.unlink(missing_ok=)`、`shutil.copytree(dirs_exist_ok=)`、海象等一律写成等价形态）。3.8 以下的机器上 prebuild 报 `TypeError: ... unexpected keyword argument` 就是这条口径破了，见 §6。
- **开发包**：Debian 10 基线的 apt 包名与上面那份清单同名可装（GTK 3.24 / Pango 1.42 都在库里）。
- **两处能力会降级**：内嵌 WebView 探的是 `webkit2gtk-4.1`，Debian 10 只有 4.0——探不到时 `@web` 退成占位实现、能力报 `Unsupported`，其余部分不受影响；媒体模块要的系统 ffmpeg 开发包在老发行版上版本偏旧，**尚未实测**。
- 工具链本身（moon / moonc）在这类机器上跑得起来：deepin 20 实测能一路走到执行 prebuild，卡住的点是上面那条解释器选择。

### macOS

只需要 Xcode 命令行工具，GTK 与 brew 一概不用——窗口、文本、图片解码走系统 Cocoa / CoreText / ImageIO 框架，由 prebuild 直接编 Objective-C 桩并下发 `-framework` 参数：

```sh
xcode-select --install
```

媒体模块另需 ffmpeg：`brew install ffmpeg`，或让 prebuild 从 Release 拉我们自编的 arm64 归档（§10）。

### Windows（10 / 11，x64）

需要 Python 3 与 MSVC C++ 工具链——Python 3 跑 prebuild，工具链选 VS 2022 Build Tools 的「使用 C++ 的桌面开发」工作负载：

```powershell
winget install Python.Python.3.12
winget install Microsoft.VisualStudio.2022.BuildTools -e --override "--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended"
```

moon 在 Windows 上定位 MSVC **开箱即用**，普通 PowerShell / Git Bash 直接 `moon run`，不必进「x64 Native Tools Command Prompt」或手动 `call vcvars64.bat`；「还要装 CMake 与 ATL」是旧 CMake 构建链的口径，本栈不适用。

## 3. 环境自检

```sh
moon version --all                 # 三件套配套
python -V && python3 -V            # 两条都必须是 3.x（≥3.7），第一条尤其
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

仓库是 `moon.work` workspace，成员含库、探针、五个子模块、七个示例与工具。构建**按模块点名，别裸扫全仓**：不带限定的 `moon test` 会连带 examples / experiment / 媒体模块，其中有平台适配缺口，不是库缺陷。

```sh
cd gui && moon check                       # 库门禁：零错误零警告
cd gui && moon test ui render text theme icons sys input win dbus chart mdview style base shell widget
cd examples/hello && moon run .            # 任一示例：进目录跑
moon build examples/showcase --target native   # 仓库根按路径点名构建
```

### 产物落点与发布构建

```sh
moon build examples/hello --target native --release --strip
```

产物按模块名走：`_build/native/<debug|release>/build/<模块名>/<模块名>.exe`。MoonBit native 后端**三平台都带 `.exe` 后缀**（含 Linux/macOS），拿去用时改名。macOS 上 `scripts/make_app.sh` 把产物包成 `.app`。

## 5. 不想编：预构建二进制

**现状如实**：GitHub Releases 上目前只有 `vendor-v1` 一条，装的是**构建期 vendor 输入**（ffmpeg 两平台归档、`miniaudio.h`、WebView2 两件套，见 §10），不是能双击运行的应用。应用二进制的发布链（`release-bin.yml`：推 `bin-*` 标签 → Linux / Windows 各编 hello + showcase 两件套 → `bin-linux-x64.zip` / `bin-windows-x64.zip` 挂 Release）已经就位，**新栈尚未发过正式 bin release**；macOS 产物暂不发，口径与该工作流头注一致。

所以「先看看效果」的正路仍是按 §4 编一条示例——`examples/hello` 从零到窗口只吃 §2 那份依赖清单。

## 6. 常见失败 → 处置

| 现象 | 根因 | 处置 |
|---|---|---|
| `SyntaxError: Non-ASCII character '\xe7' ... but no encoding declared; see pep-0263` 紧跟 `Failed to run prebuild script` | moon 执行 `.py` prebuild 时**不看 shebang**，按 PATH 里 `python` → `python3` 取第一个能用的解释器，于是拿到 Python 2 | 一次性：`MOON_PYTHON_OVERRIDE=python3 moon build`；长期：`ln -s "$(command -v python3)" ~/.local/bin/python` 并确保该目录在 PATH 最前，然后**重开终端**（Debian 系只在登录时把 `~/.local/bin` 前置进 PATH，目录当时不存在就不进） |
| `Running prebuild script for module ... needs \`python\` or \`python3\` executable in PATH` | 机器上没有 Python 3 | 按 §2 装 python3 |
| prebuild 抛 `TypeError: ... got an unexpected keyword argument 'missing_ok'`（或同类 3.8+ 才有的参数/语法） | 解释器是 Python 3.7 而脚本用到了更新版本的 stdlib 面——仓库口径是**脚本必须跑在 3.7 上** | 更新到当前 master（四处 `unlink(missing_ok=True)` 已改等价写法）；仍复现就把整行 traceback 提到 issue |
| prebuild 在 stderr 打「缺少 gtk+-3.0 开发包」一类提示后继续走，最后链接期爆 `undefined reference to gtk_*` / `pango_*` | 开发包没装全。prebuild 探不到包时只警告、**不下发链接条目**，错误推迟到链接期才露头 | 补 §2 的 apt 清单，重跑 `moon build`；仍链旧结果就 `moon clean` 一次 |
| `Package 'webkit2gtk-4.1' not found`，且只有 `@web` 用不了 | 不是故障，是设计：探不到 webkit 时 `@web` 退成占位实现、能力报 `Unsupported`，不让整包链接失败 | 要内嵌浏览器就装 `libwebkit2gtk-4.1-dev` |
| `moon.mod.json ... is no longer supported` | 依赖缓存里第三方包带的还是旧清单（注册表侧改不动） | 对 `.mooncakes/**/moon.{mod,pkg}.json` 逐个 `moon fmt`，循环到解图收敛（CI 同口径） |
| 改了 `gui/<包>/*.c` 但行为没变，`moon build` 说 `no work to do` | C 桩改动不一定触发重链 | §9 |
| prebuild 卡在下载或报 sha256 不符 | vendor 文件缺且镜像不可达 | §10：`NATIVE_GUI_VENDOR_BASE` 换源，或按提示手工放置 |
| Windows 跑 audio / video 报缺 dll | 运行期 ffmpeg dll 不在位 | §10「Windows 运行期 ffmpeg dll」 |
| `Failed to acquire file lock` | 同一构建目录上还有另一个 moon 进程（IDE 与终端同时在跑） | 等前一个结束再跑 |

`moon check` 不执行 prebuild（只查类型与警告），所以「check 全绿、build 起手红」基本就是上面 prebuild 那几条——别把它当成代码问题去翻库源码。

## 7. 链接从哪来

- moon 在构建时执行库模块的 `gui/scripts/prebuild.py`，它由 `gui/moon.mod` 的 `options(--moonbit-unstable-prebuild)` 挂上，按当前系统输出 `link_configs`，并自动传播给依赖本库模块的所有 main 包。声明的只有脚本路径，**没有命令字段**——用哪个解释器由 moon 按 §6 第一行的顺序挑。
- prebuild 同时探测系统库：Linux 找 GTK3 / Pango / FontConfig / X11，内嵌 WebView 找 `webkit2gtk-4.1`，媒体模块找 ffmpeg。探不到 GTK 就非零退出并给修复提示；探不到 webkit 则 `@web` 退成占位实现、能力报 `Unsupported`，不让整包链接失败。
- 结果：`moon add NoahLiu/native-gui` 后 `moon run` 零配置，链接 flags 不用写也不该写。

## 8. 贡献者须知

- 库包不放 `link` 段——moon 会为库包生成无 `main` 的 `.exe`，构建失败。
- 不手写 `cc-link-flags`——链接一律由 prebuild 下发，手改会与它冲突。
- 新增平台 C 能力按「单一 `stub.c` 多分支 + prebuild 宏」组织，先例见 `gui/win/stub.c`；链接参数仍归 prebuild。

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

排查时先用新的 main 目标复现一轮：新 target 每次都是新链接，若 main 正常而 test 崩，基本可断定 test 二进制链了旧归档，不是代码逻辑问题。更细的平台实测记在 [adaptation.md](https://github.com/lb091188/moonbit-native-gui/blob/master/proposals/adaptation.md)。

## 10. vendor 大文件与镜像

`WebView2.h`、`WebView2LoaderStatic.lib`、`miniaudio.h` 三个第三方文件，以及 FFmpeg 的两个运行期归档（Windows 的 dll zip、macOS arm64 的 dylib tar.gz），都不入库——入库会永久占用 git 历史体积，改由**各自模块的 prebuild** 在缺失时下载。已在位的不动：prebuild 只补缺。

| 文件 | 下载方 | 何时下载 |
|---|---|---|
| `WebView2LoaderStatic.lib`（11 MB）、`WebView2.h`（2.8 MB） | `modules/gui-webview/prebuild.py` | **仅 Windows**；Linux / macOS 直接跳过，省下 14 MB |
| `miniaudio.h`（4 MB） | `modules/gui-media/prebuild.py` | 缺失即下（各平台都要编） |
| `ffmpeg-windows-x64-9.0-lgpl-shared.zip`（约 64 MB，7 支 dll） | `modules/ffmpeg-mbt/prebuild.py` | **仅 Windows** 且本地缺运行期 dll；取不到再退 BtbN 上游 |
| `ffmpeg-macos-arm64-9.0.2-lgpl-shared.tar.gz`（约 10 MB，5 支 dylib + 头） | 同上 | **仅 macOS arm64** 且缺 `vendor/mac`；装了 brew ffmpeg 的机器走 pkg-config，不下载 |

FFmpeg 这两个归档**由我们制作**（macOS 自编 LGPLv3、@rpath 化，Windows 是从 BtbN lgpl-shared 重打包运行期 dll），不是上游现成产物——所以它们的授权文本与源码提供义务单独记在 [THIRD-PARTY-NOTICES.md](/THIRD-PARTY-NOTICES.md)。

- **校验优先**：sha256 与 prebuild 里的常量一致才落盘，任何镜像都可验证。
- **镜像**：GitHub Release → Gitee，都**不做延迟探测**。模块间策略不同——webview 与 ffmpeg 默认**并行竞速**（谁先交出校验通过的文件用谁，总耗时等于最快镜像）；gui-media 串行按序。
- **超时**：单源 socket 超时 20 秒，另加**总预算**兜底（`urlopen` 的 timeout 是 socket 级，DNS 挂起与慢速滴流不受它约束，只靠它会把一次构建吊死）。预算按体积分档：mac 归档、`miniaudio.h`、WebView2 两件套 **60 秒**，Windows 的 64 MB dll 归档 **360 秒**——否则「数据还在流、预算先到」会把那一路误判成失败。
- **换源与加源**：`modules/gui-webview/prebuild.py` 的 `VENDOR_BASES`、`modules/gui-media/prebuild.py` 的 `_VENDOR_BASES` 各改一行（另有 `modules/ffmpeg-mbt/prebuild.py` 管 dll 归档，镜像与超时口径同源）。三处**刻意各留一份**，每个模块都要能独立发布——别按「两处」去找，`grep -rn "releases/download/vendor-v1" --include=prebuild.py .` 点一遍份数。**Gitee 的用户名与 GitHub 不同**（同一个仓在 gitee 归 `noahliu0911`，GitHub 是 `lb091188`），照抄会 404，而且只在 GitHub 不通时才暴露。
- **内网与离线**：环境变量 `NATIVE_GUI_VENDOR_BASE` 接受单个 base 或逗号分隔列表，排在最前；设了它就不再并行竞速（webview 转串行按序）。也可手工把文件放到对应路径。
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

`examples/assets/` 是共享资产目录，不是模块，不要往里放代码。

## 12. 相关

- 平台适配坑与验证：[adaptation.md](https://github.com/lb091188/moonbit-native-gui/blob/master/proposals/adaptation.md)
- 环境准备与第一个工程：[tutorial.md](tutorial.md)
- 组件与 API：[components.md](components.md)
