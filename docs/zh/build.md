# 构建与链接

链接参数**全权由 prebuild 托管**——使用者和贡献者都不手写链接参数。本文讲这套机制对你意味着什么，以及改原生桩后唯一的坑：不重链。原理与逐平台实测记录在 [adaptation.md](https://github.com/lb091188/moonbit-native-gui/blob/master/proposals/adaptation.md)「构建与链接」。

## 1. 链接从哪来

- moon 在构建时执行库模块的 `gui/scripts/prebuild.py`，它由 `gui/moon.mod` 的 `options(--moonbit-unstable-prebuild)` 挂上，按当前系统输出 `link_configs`，并自动传播给依赖本库模块的所有 main 包。
- prebuild 同时探测系统库：Linux 找 GTK3 / Pango / FontConfig / X11，内嵌 WebView 找 `webkit2gtk-4.1`，媒体模块找 ffmpeg。探不到 GTK 就非零退出并给修复提示；探不到 webkit 则 `@web` 退成占位实现、能力报 `Unsupported`，不让整包链接失败。
- 结果：`moon add NoahLiu/native-gui` 后 `moon run` 零配置，链接 flags 不用写也不该写。

## 2. 贡献者须知

- 库包不放 `link` 段——moon 会为库包生成无 `main` 的 `.exe`，构建失败。
- 不手写 `cc-link-flags`——链接一律由 prebuild 下发，手改会与它冲突。
- 新增平台 C 能力按「单一 `stub.c` 多分支 + prebuild 宏」组织，先例见 `gui/win/stub.c`；链接参数仍归 prebuild。

FFI 声明与蹦床对齐的规范见仓库根 [AGENTS.md](https://github.com/lb091188/moonbit-native-gui/blob/master/AGENTS.md) 与 `.agents/skills/moonbit-c-binding/`。

## 3. 唯一的坑：改了 C 桩不重链

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

## 4. vendor 大文件与镜像

`WebView2.h`、`WebView2LoaderStatic.lib`、`miniaudio.h` 三个第三方文件，以及 FFmpeg 的两个运行期归档（Windows 的 dll zip、macOS arm64 的 dylib tar.gz），都不入库——入库会永久占用 git 历史体积，改由**各自模块的 prebuild** 在缺失时下载。已在位的不动：prebuild 只补缺。

| 文件 | 下载方 | 何时下载 |
|---|---|---|
| `WebView2LoaderStatic.lib`（11 MB）、`WebView2.h`（2.8 MB） | `modules/gui-webview/prebuild.py` | **仅 Windows**；Linux / macOS 直接跳过，省下 14 MB |
| `miniaudio.h`（4 MB） | `modules/gui-media/prebuild.py` | 缺失即下（各平台都要编） |
| `ffmpeg-windows-x64-9.0-lgpl-shared.zip`（约 64 MB，7 支 dll） | `modules/ffmpeg-mbt/prebuild.py` | **仅 Windows** 且本地缺运行期 dll；取不到再退 BtbN 上游 |
| `ffmpeg-macos-arm64-9.0.2-lgpl-shared.tar.gz`（约 10 MB，5 支 dylib + 头） | 同上 | **仅 macOS arm64** 且缺 `vendor/mac`；装了 brew ffmpeg 的机器走 pkg-config，不下载 |

FFmpeg 这两个归档**由我们制作**（macOS 自编 LGPLv3、@rpath 化，Windows 是从 BtbN lgpl-shared 重打包运行期 dll），不是上游现成产物——所以它们的授权文本与源码提供义务单独记在 [THIRD-PARTY-NOTICES.md](/THIRD-PARTY-NOTICES.md)。

- **校验优先**：sha256 与 prebuild 里的常量一致才落盘，任何镜像都可验证。
- **镜像**：GitHub Release → Gitee，都**不做延迟探测**。两模块策略不同——webview 默认**并行竞速**（谁先交出校验通过的文件用谁，总耗时等于最快镜像）；gui-media 串行按序。
- **超时**：单源 socket 超时 20 秒，另加 **60 秒总预算**兜底。`urlopen` 的 timeout 是 socket 级，DNS 挂起与慢速滴流不受它约束，只靠它会把一次构建吊死。
- **换源与加源**：`modules/gui-webview/prebuild.py` 的 `VENDOR_BASES`、`modules/gui-media/prebuild.py` 的 `_VENDOR_BASES` 各改一行（另有 `modules/ffmpeg-mbt/prebuild.py` 管 dll 归档，镜像与超时口径同源）。三处**刻意各留一份**，每个模块都要能独立发布——别按「两处」去找，`grep -rn "releases/download/vendor-v1" --include=prebuild.py .` 点一遍份数。**Gitee 的用户名与 GitHub 不同**（同一个仓在 gitee 归 `noahliu0911`，GitHub 是 `lb091188`），照抄会 404，而且只在 GitHub 不通时才暴露。
- **内网与离线**：环境变量 `NATIVE_GUI_VENDOR_BASE` 接受单个 base 或逗号分隔列表，排在最前；设了它就不再并行竞速（webview 转串行按序）。也可手工把文件放到对应路径。
- 全部失败时 prebuild 不中断，只打印手工放置提示，把缺文件错误留给链接期。

授权与来源见 [THIRD-PARTY-NOTICES.md](/THIRD-PARTY-NOTICES.md)。

## 5. 新增示例模块

依赖隔离靠模块、不靠包：`moon.mod` 的 import 决定整个模块的依赖闭包，`moon.pkg` 只能从模块已解析的依赖里挑包。所以「某个示例不拖累其它示例」必须做成**每示例一个模块**，把多个示例塞进同一份 `moon.mod` 会重新耦合。新增一个示例：

1. 建目录 `examples/<name>/`（含 `main.mbt` + `moon.pkg`），写一份**自己的** `moon.mod`：
   `name = "NoahLiu/native-gui-examples-<name>"`，import 只列该示例真用到的模块。
2. 把 `examples/<name>` 追加进 `moon.work` 的 `members`。
3. 需要在 CI 里构建/冒烟就点名追加，别改成一个 `moon build` 扫整个 workspace（失败看不出是谁坏的）。
4. 产物路径按模块名走：`_build/native/<mode>/build/NoahLiu/native-gui-examples-<name>/native-gui-examples-<name>.exe`
   （`scripts/make_app.sh`、`release-bin.yml` 依赖这个口径）。

`examples/assets/` 是共享资产目录，不是模块，不要往里放代码。

## 6. 相关

- 平台适配坑与验证：[adaptation.md](https://github.com/lb091188/moonbit-native-gui/blob/master/proposals/adaptation.md)
- 环境准备与第一个工程：[tutorial.md](tutorial.md)
- 组件与 API：[components.md](components.md)
