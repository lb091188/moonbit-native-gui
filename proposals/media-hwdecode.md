# 媒体硬解方案（VideoToolbox / D3D11VA / VAAPI）

硬件解码独立成线，与 GPU 合成（[gpu-architecture.md](gpu-architecture.md)）**并行、互不绑定**：本线只把解码从 CPU 挪到 GPU 引擎，输出仍交回现有 CPU 帧链路；直纹理零拷贝归 GPU 线的 `GpuContext` 接口位，本线不做。
证据一律标级别：**实测**（本仓代码/命令读数/归档实物）、**官方文档**（lavu doxygen、doc/hwaccel）、**推断**（未验的机制猜测，禁止当契约写）。

## 一、现状链路与改造点（实测，读码定案）

```
vf_open_video_decoder（modules/ffmpeg-mbt/c/ffmpeg_stub.c:160）
  └ sws_getContext(codec->pix_fmt → AV_PIX_FMT_RGBA)      :210
vf_decode_next（同文件 :257）
  └ sws_scale                                              :292
Demuxer::decode_rgba（modules/ffmpeg-mbt/src/ffmpeg.mbt:223）
  └ 消费者 examples/video、gui-media video.mbt:325/392/555
```
改造量收在**一个 C 文件 + 两个字段**：`AVBufferRef *hw_device_ctx`（挂在 codec ctx 的 `hw_device_ctx` 上）与 `int hw_failed`（连续失败计数），帧上加一个 `AVFrame *hw_frame` 中转；`ffmpeg.mbt` 只加两个 getter（硬解是否启用、是否已回落）。解码端其余零改动——这是「帧输出抽象」（§五）能成立的前提。

## 二、三平台接口面矩阵

| 平台 | hwdevice 类型 | 建立调用 | 依赖与前提 | 依据 |
|---|---|---|---|---|
| macOS | `AV_HWDEVICE_TYPE_VideToolbox` | `av_hwdevice_ctx_create(&dev, type, NULL, NULL, 0)` | VideoToolbox/CoreVideo 由 ffmpeg dylib 自带，**本仓 prebuild 框架清单不必扩**（`gui/scripts/prebuild.py:162-187`） | 官方文档 + 实测（归档构建脚本） |
| Windows | `AV_HWDEVICE_TYPE_D3D11VA` | 同上 | 需**交互式会话**（服务/无桌面会话建不出）；`d3d11.lib` 类符号由归档侧带 | 官方文档 |
| Linux | `AV_HWDEVICE_TYPE_VAAPI` | 同上，`device` 传 `/dev/dri/renderD128` 可**免 X11**（CI 与无显示必需）；不传默认走 X11 | 依赖发行版 ffmpeg 与驱动；无 `/dev/dri` 即不支持 | 官方文档 |

`av_hwdevice_ctx_create` 失败（返回负值）就是「这台机器此刻不能硬解」，直接走软解，不重试不猜。

**格式约束（官方文档）**：`av_hwframe_transfer_data` 下传给 CPU 的目标格式只有 NV12（8bit）与 P010（10bit）两族；H264 常规档没有 10bit，HEVC/VP9/AV1 才见 10bit ⇒ 首版只做 8bit（NV12→RGBA 走现有 sws），`p010le→RGBA` 的 sws 支持属**推断级**，探针核过再开。

## 三、回落三层判据与 UI 语义

| 层 | 判定处 | 动作 |
|---|---|---|
| 驱动缺 / 初始化失败 | `vf_open_video_decoder`（`ffmpeg_stub.c:160`）建 hwdevice 失败 | `hw_device_ctx` 留 NULL，照常开软解解码器；上层无感 |
| 格式不支持 | 同处，按 `avcodec_get_hw_config` + profile 预判 | 不挂 hw，走软解 |
| 运行期失败 | `vf_decode_next`（`:257`）每帧计数，连续 3 帧置 `hw_failed` | 由 `video.mbt` 走既有「重开解码器 + seek 回 `last_frame_pts`」路径（`:389-396` 已有雏形），重开时不带 hw ctx |

**对外语义三档**（对齐本库「探测 + 语义化降级」家规，别把「已回落」报成「硬解」）：`软解` / `硬解` / `硬解失败已回落（带原因）`。探针与状态读数走 stdout 行，归 `测试文档/测试用例.md`。

## 四、vendor 归档核验（实测）

| 腿 | 结论 | 读数 |
|---|---|---|
| Linux | 用发行版 ffmpeg（pkg-config 直探），hwaccel 随驱动 | 本机 `ffmpeg -hwaccels` 列出 `vdpau cuda vaapi qsv drm opencl vulkan` |
| Windows | BtbN lgpl-shared 归档（`prebuild.py:57`）**已含 d3d11va** | `strings vendor/avcodec.lib` 命中 `av_d3d11va_alloc_context`；版本 `n9.0.2-27-g7e93014c5b`；`hwcontext_*.h` 14 个齐全 |
| macOS | CI 自编脚本（`modules/ffmpeg-mbt/scripts/*.yml` 的 configure 段 `:43-48`）**从创建起就带 `--enable-videotoolbox --enable-audiotoolbox`** | `git log -S --enable-videotoolbox` 唯一命中 `bebce1c8`（脚本初立那次） |

**H0 探针首跑（2026-11-03，Linux 开发容器，`experiment/hwdecode_probe/hwdecode_probe.c`）**：逐设备 `av_hwdevice_ctx_create` + `av_hwframe_ctx_alloc/init` + `av_hwframe_transfer_get_formats(FROM)` 读数——

```
ffmpeg 60.31.102；/dev/dri/renderD128 存在
HWPROBE platform=linux type=vdpau open=ok frames=ok pix=vdpau transfer=none
HWPROBE platform=linux type=cuda  open=ok frames=ok pix=cuda  transfer=none
HWPROBE platform=linux type=vaapi open=ok frames=ok pix=vaapi transfer=none
HWPROBE platform=linux type=qsv   open=fail:Generic error in an external library
HWPROBE platform=linux type=drm   open=fail:Bad address
HWPROBE platform=linux type=opencl open=ok frames=ok pix=opencl transfer=none
HWPROBE platform=linux type=vulkan open=ok frames=ok pix=vulkan transfer=none
```

两条实测口径，实现（H1）按此写：①**设备句柄建得起来 ≠ 能用**——容器里连无 NVIDIA 卡的 `cuda` 都报 `open=ok frames=ok`，光看这两档会被骗；②**transfer 列表全空**（本容器无真实 GPU 上下文，或该发行版 build 的 hwframe 传输未编进）——所以 H1 的可用判据必须落在**真实解一帧 + `av_hwframe_transfer_data` 成功**上，不能只看 device/frames 两档；探针后续加「解一帧」档（需样本文件，随 H1 一起进 `experiment/`）。
③ `qsv`/`drm` 建不起来属正常（无对应驱动），如实打 fail 原因，不静默跳过。

**推翻一条旧判**：roadmap「已规划·媒体」写「mac 归档 `--enable-videotoolbox` 重做评估」——前提过期（归档一直带着这一档），本线只需**验实物**：`otool -L libavutil.dylib | grep VideoToolbox`，vendor-v1（sha `9fdff76c`）与 brew 路各验一次。
**顺带缺陷**：归档里的 `LICENSE.txt` 由脚本 `:92` 写成「--enable-lgpl 配置构建」，与脚本 `:49` 的自述矛盾——随本线一并改口径，别让人对着不存在的配置串核许可。

## 五、帧输出抽象（与 GPU 线的接缝）

把「解码帧怎么变成 RGBA」收敛成一个策略位（`transfer` 模式：`SwScale` / 将来 `DirectTexture`）：
- 本线只实现 `SwScale`（hw frame → `av_hwframe_transfer_data` → NV12 → 现有 sws → RGBA）；
- GPU 线落地时新增 `DirectTexture` 一档，**只动输出端一行**，解码端（hwdevice 建立、回落、计数）零改动；
- 直纹理的接口位在 `GpuContext` 侧留（gpu-architecture.md L2 首消费者那条），本线不实现导入。

## 六、分期与 spike

- **H0 探针**（先跑，不动业务码）：三平台各建一次 hwdevice 并解一帧，打印 `HWPROBE platform=… type=… open=… decode=… transfer=…`；顺带核 §四 的归档实物。
- **H1 实现**：`vf_open_video_decoder` 挂 ctx + `vf_decode_next` transfer 下传 + 三层回落 + 状态三档对外。
- **H2 帧输出抽象**：transfer 策略位落地，为 GPU 线留口。
- **spike 未决项**：D3D11VA 在非交互会话的行为（CI 会不会建得出）；VAAPI 在 NVIDIA 专有驱动上的边界；`p010le→RGBA` 的 sws 支持；HEVC 10bit 样本是否首版就做（属产品决策）。

## 七、验收口径

- **正确性**：同一素材硬解与软解**逐位一致**（RGBA 缓冲 memcmp），H264 8bit 与 HEVC 8bit 各一样本；10bit 待探针结论。**Linux VAAPI 已实测通过**（2026-11-03，`testsrc_1s.avi` 96×64：`hw_status=1`，首帧与软解逐字节相同；`ffmpeg_wbtest` 7/7）。
- **收益**：解码一段固定素材的 CPU 时间对比（无头判据，`experiment/` 出一条 `HWDECODE-COST` 行）。
- **降级**：拔掉硬件（无 `/dev/dri`、非交互会话）时状态报「软解」而不是崩或假装硬解。
- 门禁：`cd modules/ffmpeg-mbt && moon test src` 与全库 `moon test media` 零错误零警告；真机观感（播放是否更稳）归用户三平台清单。

## 八、定案（2026-11-03，动工按此执行，不再重开选项）

1. **默认关、显式请求**：`VideoPlayer::set_hw_decode(true)`（或 decoder 侧同名开关）才建 hw_device_ctx。理由：硬件路径的失败形态依驱动而异，默认开会改变现有素材的解码结果与错误面——现有播放链的行为必须原样不动。
2. **失败永久回落，粒度是「本进程内 codec + 分辨率」**：一次失败即把这一组键钉回软解，重开解码器**不带** hw ctx，不逐素材重试（重试成本落在播放首帧上，用户能直接感觉到）。回落只发生一次，之后不再试。
3. **10bit 首版不做**：写进边界（不做 ≠ 支持但有坑）——`p010`/`yuv420p10le` 这类高分辨率格式在 sws 下传到 CPU 帧链的口径未验，等 H0 探针给结论再单批；文档里「HEVC 10bit」不再悬着。
4. **对外状态三档如实**：`软解 / 硬解 / 已回落（带原因）`。回落不许报成硬解。
