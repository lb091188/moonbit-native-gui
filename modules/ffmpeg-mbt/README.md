# NoahLiu/ffmpeg

ffmpeg 的 MoonBit 动态链 FFI 绑定（libavformat/libavcodec/libswscale/
libswresample/libavutil），进程内解码：容器 demux、视频逐帧解码为 RGBA、
时间戳 seek。三平台实现同源，链接参数由本模块 `prebuild.py` 按平台下发，
自动传播给依赖方 main 包（无需手写链接配置）。

## 依赖

**Linux**：构建机 ffmpeg 开发包（Ubuntu：`sudo apt install -y
libavcodec-dev libavformat-dev libavutil-dev libswscale-dev
libswresample-dev`），`pkg-config` 探测；运行机：对应运行库
（`libavcodec60` 等，通常随 ffmpeg 安装）。

**Windows**：dev 内容 vendor 进本仓（`vendor/`——`include` 头 + `*.lib`
导入库，取自 BtbN `ffmpeg-n9.0-latest-win64-lgpl-shared-9.0` 构建，
LGPLv3，见 `vendor/FFMPEG-LICENSE.txt`；头路径经 prebuild 的
`vars.FFMPEG_INC` 注入 stub 编译）。**运行期 dll 不在仓库里**：把
`avcodec-63.dll` 等 7 个 dll 与 exe 同目录、或放进 PATH（自行从
BtbN/gyan 的 win64-lgpl-shared 构建取同一大版本的 `bin/*.dll`；dll 主版本
须与 vendor 导入库一致——avcodec-63/avformat-63/avutil-61/swscale-10/
swresample-7/avdevice-63/avfilter-12）。

**macOS**：两级——prebuild 先 pkg-config 探系统 ffmpeg（`brew install
ffmpeg pkg-config`；brew 前缀显式拼进 `PKG_CONFIG_PATH`）；探不到回退
**Release 下载的预编译 dev 归档**（LGPLv3 自建、动态链 `.dylib`、id/依赖
全部 `@rpath` 化，sha256 校验 + GitHub/Gitee 双镜像 +
`NATIVE_GUI_VENDOR_BASE` 可覆盖，与 webview Loader 的 vendor 口径同族），
`link_flags` 下发 `-Wl,-rpath` 指向解包的 `vendor/mac/lib`，dyld 运行期
就地加载，运行机无需任何安装。归档由
`scripts/make_mac_ffmpeg_vendor.sh` 制作（自编 LGPL 隔离 brew 的 GPL 闭包，
产物入 `dist/`，sha256 回填 `prebuild.py` 后上传 `vendor-v1` Release）；
离线机器也可手工把归档解开到 `vendor/mac/`（`include/` + `lib/`）。两路
都拿不到才构建失败（不做「能链不能跑」的假可用降级）。

## API

```moonbit
// 打开（width/height 为输出帧目标尺寸，0 = 源尺寸）
let d = @ffmpeg.Demuxer::open("demo.avi")?    // AVI/MP4/MKV/WebM…
d.stream_width()    // 视频流原生宽
d.stream_height()   // 视频流原生高
d.duration_s()      // 时长秒（容器未知时 0）

// 逐帧解码（RGBA 字节，恰好 w*h*4；流结束 None）
while let Some(frame) = d.decode_rgba() { ... }

d.seek(1.5)?        // 时间戳 seek（avformat_seek_file + 解码器 flush）
d.close()           // 释放（之后不可再用）
```

错误 `VfError`：`OpenFailed(String)` / `NoVideoStream` / `DecodeFailed(String)`。
`ffmpeg_supported()` / `ffmpeg_version()` 探测库可达性与版本。

## FFI 约定（坑，详见主仓库 docs/zh/adaptation.md）

- extern 类型声明必须带 `#external`（否则 MoonBit GC 把 FFI 返回的
  裸指针当 GC 堆对象 drop → mi_free 段错误）；
- C 侧句柄失败不返回 NULL，返回哑句柄 + 显式 ok 探测（规避 NULL↔Option
  语义不确定性）；中间裸值立即装进 struct 字段再传递。
