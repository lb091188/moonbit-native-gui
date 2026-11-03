# 媒体解码白名单自建归档（发布形态）

播放档 ffmpeg 从「BtbN 全量共享库」换成「自编解码白名单归档」：Windows 随包运行期 dll 从 149.2 MB【实测：归档 67.5 MB 解出 7 个 dll】降到解码白名单量级【推断 15~30 MB，D0 探针实测定档】。与硬解线（[media-hwdecode.md](media-hwdecode.md)）互不绑定：本提案只动「构建/分发什么」，解码链路代码零改动。

## 现状三条腿（实测）

| 平台 | 现状 | 本提案动不动 |
|---|---|---|
| Linux | 发行版 ffmpeg（pkg-config 直探），本仓不分发 | 不动 |
| Windows | BtbN lgpl-shared **全量**，运行期 dll 149.2 MB/7 个，`win-ffmpeg-vendor` workflow 取归档上传 vendor-v1 | **换自编白名单归档**——workflow 从「取 BtbN」改「runner 自编」，归档命名/sha256/双镜像/vendor-v1 同管道 |
| macOS | 已是自建（`scripts/make_mac_ffmpeg_vendor.sh`，env -i 隔离 brew、otool 闭包断言、9.0.2），但 configure **全开**（只 --disable-autodetect，无白名单） | **configure 加白名单**——脚本骨架、@rpath 化与闭包断言原样复用 |

体积账：完全体 ~150 MB 是「BtbN 默认全开」的体积，不是播放链的必然体积——现链路只吃「解码 + demux + swscale + hwaccel」，编码面与大部分 demuxer 整段闲置。

## 白名单（首版草案，D0 后钉死）

- **demuxer**：mp4/mov/mkv/webm/flv/ts/avi/ogg/wav/mp3/flac（对齐 gui-media 现有素材面）
- **decoder**：h264/hevc/vp8/vp9/av1/mpeg4/mjpeg + aac/opus/mp3/vorbis/flac/pcm_s16le
- **保留**：swscale（下行 RGBA 靠它）；hwaccel 三档（videotoolbox/d3d11va/vaapi 属 avcodec 内部，与硬解线共存）；协议 file/https 按需
- **许可**：保持 LGPL——白名单全取 LGPL 解码器，不进 GPL 编码器（x264/x265），与现 lgpl-shared 口径一致

## 不做（边界）

- **编码器整档不做**：编辑/导出属批处理形态，归「ffmpeg CLI 独立进程」另一档（未立项）——进程外形态不传染 GPL、也不随基座分发。
- Linux 腿不动；`ffmpeg.mbt` 与 stub 的 API 面零改动，只换链接到的库。
- 格式边界（10bit 等）归硬解线管（media-hwdecode.md 定案 3）。

## 分期

- **D0 探针**（runner 上直接编，不动业务码）：Windows/macOS 各编一版白名单归档，读三个数——归档体积、解包体积、`ffmpeg_wbtest` + 本机真解码对照逐位一致；白名单外素材给明确错误而非崩。顺带读码确认 libavfilter 是否可整库不编（现链路只见 sws，待核）。
- **D1 Windows**：`win-ffmpeg-vendor` 改 runner 自编（工具链选型见待定项），归档/sha256/双镜像/vendor-v1 上传同管道，`prebuild.py` 换文件名与 sha。
- **D2 macOS**：脚本 configure 加 `--disable-everything` + 白名单；顺带修 `LICENSE.txt` 口径（现文写「--enable-lgpl」而该选项不存在，脚本注释自记过此矛盾——media-hwdecode.md §四 同款缺陷）。
- **验收**：体积读数落回本提案；解码对照全绿；release-bin 三平台 zip 更新；`docs/zh/build.md` §6 与 `THIRD-PARTY-NOTICES.md` 同步。

## 待探针定案项

- 实际体积，定「15~30 MB」还是另档。
- libavfilter / libavdevice 是否整库不编。
- 版本锚点与现归档同系 pin 死（9.0.x；BtbN 现归档实测 n9.0.2-27-g7e93014c5b）。
- Windows runner 自编的工具链（MSYS2 gcc / clang）与单次构建时长（进 CI 预算）。
