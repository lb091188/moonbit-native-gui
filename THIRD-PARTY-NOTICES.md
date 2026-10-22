# 第三方授权与来源

本仓库自身是 **MIT**（见 [`LICENSE`](LICENSE)）。本文件登记**随我们分发的第三方资产**，也包括**由我们自行编译或重打包、挂在 Release 上供下载的第三方构建产物**——后者虽然不入库，但对下载者而言同样是「我们提供的二进制」，义务不变。

| 资产                                             | 许可                             | 在我们这里的形态                                                                                                                                                                                                    | 授权文本                                                        |
| ---------------------------------------------- | ------------------------------ | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| FFmpeg（Windows 开发包）                            | LGPL-3                         | `modules/ffmpeg-mbt/vendor/`：5 个导入库 `.lib` + 头文件，**入库存档**；取自 BtbN/FFmpeg-Builds 的 win64 **lgpl-shared** 构建，版本串 `n9.0.2-27-g7e93014c5b-20261012`                                                             | ✅ `modules/ffmpeg-mbt/vendor/FFMPEG-LICENSE.txt`            |
| FFmpeg（Windows 运行期 dll）                        | LGPL-3                         | **由我们打包并提供下载**：`ffmpeg-windows-x64-9.0-lgpl-shared.zip`（7 支 dll + 许可文本），取自同一份 BtbN lgpl-shared 构建的 `bin/`，**不入库**；由 `win-ffmpeg-vendor` workflow 制作后挂到本仓 Release `vendor-v1`，构建时按 sha256 校验下载                                                           | ✅ 归档内 + 同上 `FFMPEG-LICENSE.txt`                            |
| FFmpeg（macOS arm64 运行期 dylib）                  | LGPL-3                         | **由我们自编并提供下载**：`ffmpeg-macos-arm64-9.0.2-lgpl-shared.tar.gz`（5 支 dylib + 头 + 许可全文），源 `ffmpeg-9.0.2.tar.xz`，`--enable-version3 --disable-autodetect --disable-programs`，id 与依赖全部 @rpath 化、闭包只含系统库，**不入库**；由 `mac-ffmpeg-vendor` workflow 制作后挂到 Release `vendor-v1`，构建时按 sha256 校验下载。不用 brew 的 ffmpeg 是因为它带 GPL 组件（x264/x265）且依赖闭包拖进十几支 formula | ✅ 归档内 `LICENSE.txt` + `COPYING.LGPLv2.1` + `COPYING.GPLv3`；仓内 `modules/ffmpeg-mbt/vendor/mac/` 亦有副本 |
| FFmpeg（Linux 运行期）                              | LGPL-3                         | **不随我们分发**——动态链系统包，构建期 pkg-config 探测                                                                                                                                                                        | 由发行版附带                                                      |
| WebView2 SDK（Microsoft）                        | MIT                            | `modules/gui-webview/webview/include/WebView2.h` + `modules/gui-webview/webview/lib/WebView2LoaderStatic.lib`，**不入库**，构建时从 Release 资产 `vendor-v1` 下载并校验 sha256；NuGet 包 `Microsoft.Web.WebView2` 1.0.4258.31 | ✅ `modules/gui-webview/webview/include/SDK-LICENSE.txt`（入库） |
| miniaudio（mackron）                             | 公有领域（Unlicense / CC0）与 MIT 双许可 | `modules/gui-media/media/miniaudio.h`，**不入库**，构建时下载并校验 sha256                                                                                                                                               | 文件头即授权声明；此处登记                                               |
| `moonbitlang/x`、`moonbitlang/async`            | Apache-2.0                     | mooncakes 依赖（`moon install` 拉取，不入库）                                                                                                                                                                         | 各自包内 `LICENSE`                                              |
| `modules/mdparse`（派生自 `mizchi/markdown` 0.8.3） | MIT                            | **入库**：解析链路源码在 `modules/mdparse/src/`，保留上游版权声明                                                                                                                                                              | ✅ `modules/mdparse/LICENSE`、`modules/mdparse/NOTICE.md`     |
| `mizchi/zlib`                                  | Apache-2.0                     | 同上                                                                                                                                                                                                          | 包内 `LICENSE`                                                |
| `prowk/moonsqlitefile`                         | Apache-2.0                     | 同上                                                                                                                                                                                                          | 包内 `LICENSE`                                                |
| MoonBit 工具链与 `moonbitlang/core`                | Apache-2.0                     | 由 `~/.moon` 工具链分发，不入库                                                                                                                                                                                       | 工具链自带                                                       |
| GTK3 / Cairo / Pango / GdkPixbuf / WebKitGTK   | LGPL-2.1 / LGPL-3（各自）          | **不随我们分发**，发行版提供；构建期 pkg-config 探测，缺包即语义化降级                                                                                                                                                                 | 由发行版附带                                                      |
| Yoga（Facebook）                                 | MIT                            | **不使用其代码**：`modules/yoga-mbt` 按 W3C CSS Flexbox Layout Level 1 规范自写实现，只对齐规范与行为，不保留 Yoga 的双默认值                                                                                                               | 不适用（出处口径见该模块 README）                                        |

## 对外发预构建二进制时的义务清单

上表里标「mooncakes 依赖」的行，在只发源码（mooncakes）时由包管理器负责；**一旦我们发编译好的二进制**（GitHub / Gitee Release），它们变成「我们的产物包含第三方代码」，需要：

1. 把各依赖的 `LICENSE` 原文收进发布包的 `licenses/` 目录——直接从 `.mooncakes/<作者>/<包>/LICENSE` 拷贝即可，别手抄；
2. 本文件随包一起发；
3. LGPL 线（FFmpeg、GTK 族）保持**动态链**并给出替换路径：Windows 侧 dll 放 exe 同目录或加进 `PATH`（口径见 [`examples/README.md`](examples/README.md) 的「Windows 运行前置」节），这已满足 LGPL 的「用户可换库」要求；
4. 静态入库的 Windows 导入库（`*.lib`）本身不含 FFmpeg 代码，只是链接期符号表——但**运行期 dll 必须与同一份 LGPL 构建配套**，发布说明里要写清版本串。
5. **我们自编或重打包的 FFmpeg 二进制**（`vendor-v1` 上的 `ffmpeg-macos-arm64-*.tar.gz` 与 `ffmpeg-windows-x64-*.zip`）同样受 LGPL-3 约束，发版时要一并给出：**对应源码**的获取位置（`https://ffmpeg.org/releases/ffmpeg-<版本>.tar.xz`，版本见归档名）与**构建脚本**（mac 侧 configure 参数全在 `modules/ffmpeg-mbt/scripts/make_mac_ffmpeg_vendor.sh`，这是「同一份源码 + 同一份参数」可复现的唯一凭据）；并在发布说明写明归档名与 sha256（与 `prebuild.py` 里回填的常量一致）。`--enable-version3` 只是把默认的 LGPLv2.1 升到 LGPLv3，**不等于** GPL——`--enable-gpl` 才会改变许可，我们的构建没有用它。

## 挂在 `vendor-v1` Release 上、由我们提供的资产

上表里标「不入库」的文件都从本仓 Release `vendor-v1` 下载（GitHub / Gitee 双镜像），由**各自模块的 prebuild** 在**缺失时**取用，**sha256 通过才落盘**；已在位的不动，离线可手工放置。其中 FFmpeg 两个归档**由我们制作**，不是上游现成产物：

| 资产 | 来源与制作方式 | 下载方 | 何时下载 |
|---|---|---|---|
| `WebView2.h`（2.8 MB）、`WebView2LoaderStatic.lib`（11 MB） | NuGet `Microsoft.Web.WebView2` 1.0.4258.31，原样上传 | `modules/gui-webview/prebuild.py` | 仅 Windows；Linux / macOS 直接跳过 |
| `miniaudio.h`（4 MB） | 上游 mackron/miniaudio，原样上传 | `modules/gui-media/prebuild.py` | 各平台缺失即下 |
| `ffmpeg-windows-x64-9.0-lgpl-shared.zip`（约 64 MB） | **重打包**：BtbN win64 lgpl-shared 构建的 `bin/`，只含 7 支运行期 dll + 许可文本；由 `win-ffmpeg-vendor` workflow 产出 | `modules/ffmpeg-mbt/prebuild.py` | Windows 构建缺 dll 时；取不到再退 BtbN 上游 |
| `ffmpeg-macos-arm64-9.0.2-lgpl-shared.tar.gz`（约 10 MB） | **自编**：源 `ffmpeg-9.0.2.tar.xz`，LGPLv3 配置、五支 dylib @rpath 化、闭包只含系统库；由 `mac-ffmpeg-vendor` workflow 产出 | 同上 | macOS arm64 缺 `vendor/mac` 时；装了 brew ffmpeg 的机器走 pkg-config，不下载 |

- macOS 之所以自编而不发 brew 的 ffmpeg：brew 默认带 x264/x265（GPL），依赖闭包还拖进 openssl/libvpx/svt-av1 等十几支 formula，既与 Windows 的 lgpl-shared 口径不一致，归档也得把整个闭包捆进去才能离机运行。自编用 `--disable-autodetect` 把 brew 隔离在外，configure 后逐库 `otool` 断言闭包，破断言即构建失败。
- 两个 FFmpeg 归档的**版本与 sha256 同时写在** `modules/ffmpeg-mbt/prebuild.py`（`MAC_VENDOR_TARBALLS` / `WIN_VENDOR_ARCHIVE`）与归档文件名里；换版本时三处一起改，否则校验不过或下到旧包。
- 镜像 GitHub → Gitee，**不做延迟探测**：sha256 使得任何镜像都可验证，先测快慢会让两台机器从不同源取，丢掉可复现性。模块间策略不同——webview 与 ffmpeg 并行竞速（谁先交出校验通过的文件用谁），gui-media 串行按序。
- 超时：单源 socket 20 秒，另有总预算兜底（`urlopen` 的 timeout 管不住 DNS 挂起与慢速滴流）。预算按体积分档——mac 归档与 miniaudio 60 秒，Windows 的 64 MB dll 归档 360 秒，否则「数据还在流、预算先到」会把这一路误判成失败。
- 加镜像 = 在 `modules/gui-webview/prebuild.py` 的 `VENDOR_BASES` 或 `modules/gui-media/prebuild.py` 的 `_VENDOR_BASES` 加一行（`modules/ffmpeg-mbt/prebuild.py` 同名常量同源）。Gitee 上的用户名与 GitHub 不同（同一个仓归 `noahliu0911`，GitHub 是 `lb091188`），照抄会 404。外部源（内网 / 离线目录）用环境变量 `NATIVE_GUI_VENDOR_BASE` 覆盖，接受单个 base 或逗号分隔列表，排在列表最前。
- 下载逻辑有三份副本（`gui-webview` / `gui-media` / `ffmpeg-mbt`），刻意各留一份：每个模块都要能独立发布，不能反向依赖别处的 `scripts/`。改口径时先 `grep -rn "releases/download/vendor-v1" --include=prebuild.py .` 点清份数。
- 全失败时 prebuild **不中断**，只打印手工放置的提示，让链接期给出明确的缺文件错误。
