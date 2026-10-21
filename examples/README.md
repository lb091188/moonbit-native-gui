# examples 示例集

`examples/` 下**每个示例目录就是一个独立模块**（各自一份 `moon.mod`，模块名 `NoahLiu/native-gui-examples-<目录名>`），全部注册在仓库根 `moon.work`。依赖只在自己的 `moon.mod` 里声明，示例之间互不相干：`hello` 一类基础示例不会牵出 ffmpeg 链路，媒体示例自己带 `gui-media`。

## audio / video（音视频播放示例）

依赖 `gui-media` 的两个播放器组件 `audio` / `video`（ffmpeg 解码 + miniaudio 设备直出，名字对齐 HTML 的 `<audio>` / `<video>`）。

- **audio**：左侧播放列表（当前曲目高亮、点击换曲）+ 右侧播放器与状态区；控制条是**图标按钮**（播放/暂停、±5 秒、全屏）+ 文字档位键（倍速）+ 自绘进度/音量条，播放器上方是**实时频谱条**（纯 MoonBit FFT，按设备队列回看对齐耳朵），歌词按**同名 `.lrc` 自动配对**（示例侧读文本、组件不做 IO，当前行画在频谱下方）。快捷键不点窗口也生效：空格播放/暂停、回车全屏、`←/→` ±5 秒、`↑/↓` 音量、`Esc` 退全屏。载入路径：默认资产 `assets/1.mp3` + `assets/1.lrc`（路径对工作目录稳健解析）、文件对话框选音频、目录对话框选文件夹后扫描成播放列表（无音频文件给空态）。
- **video**：视频区为主 + 侧栏播放列表/信息；字幕双来源——容器内嵌轨自动读取，或「选外挂 .srt」读文本传入（`on_subtitle` 回报来源与条数，可清除回内嵌轨）。控制条同上（逐帧键为 `←/→`），另有**缩放三档**（适配 / 铺满 / 1:1）与全屏。载入路径与 audio 同三条，默认资产 `assets/1.mp4`。

```sh
# 仓库根（workspace 模式）
moon run examples/audio
moon run examples/video
```

依赖：[native-gui](https://mooncakes.io/docs/NoahLiu/native-gui)、[gui-media](https://mooncakes.io/docs/NoahLiu/gui-media)、[ffmpeg-mbt](https://mooncakes.io/docs/NoahLiu/ffmpeg-mbt)。

### Windows 运行前置：ffmpeg 运行期 dll（**不满足则进程起不来**）

`ffmpeg-mbt` 的 C 桩是**真绑定**（三平台同源、无平台条件编译，见该模块 `src/ffmpeg_stub.c` 文件头），Windows 侧由 `prebuild.py` 用 `vendor/*.lib`（BtbN win64-lgpl-shared 导入库）链接。导入库进链接意味着**生成的 exe 在加载期硬依赖下列 5 个 dll**：

`avcodec-63.dll` / `avformat-63.dll` / `avutil-61.dll` / `swscale-10.dll` / `swresample-7.dll`

（另 `avdevice-63.dll` / `avfilter-12.dll` 与 vendor 同版本配套，README 口径列全 7 个。）

**缺 dll 时的表现**：Windows 加载器在 `main` 之前就解析导入表，缺则进程根本起不来（窗口从不出现、控制台一闪就退，Git Bash 下退出码 127、无输出）。`ffmpeg-mbt` 已把这 5 个 dll 改成**延迟加载**，并用构建期记下的 `vendor/win/bin` 兜底，所以现在缺 dll 表现为 `ffmpeg_supported()` 返回 false（媒体后端判为不可用），而不是启动即崩。audio 与 video 两个示例各自成模块，都吃这条前置。

把 dll 放到 **exe 同目录**或**加进 PATH**（大版本须与 `vendor/` 导入库一致，取自同一份 BtbN/gyan win64-lgpl-shared 构建的 `bin/`）。开发期通常**不需要**做这件事——见下。

**dll 从哪来**：`ffmpeg-mbt` 的 prebuild 在 Windows 构建时会先看 `modules/ffmpeg-mbt/vendor/win/bin`（与 macOS 的 `vendor/mac` 对称，都不入库），缺则取本仓 `vendor-v1` Release 的 `ffmpeg-windows-x64-9.0-lgpl-shared.zip`（解出约 150MB，GitHub 与 gitee 双镜像竞速 + sha256 校验），两个镜像都拿不到才退 BtbN 上游；进度都打在构建日志里。离线可 `NATIVE_GUI_FFMPEG_ZIP=<本地 zip>` 指过去，CI 已自备 dll 时用 `NATIVE_GUI_SKIP_VENDOR=1` 跳过。

**开发期为什么不用搬**：prebuild 把 `vendor/win/bin` 的绝对路径编进 exe，`ffmpeg_supported()` 首次调用时按「exe 同目录/PATH → 该目录」顺序加载（`src/ffmpeg_win_dll.c`，`/DELAYLOAD`）——macOS 用 `-rpath` 做到的事，Windows 靠这一手等价完成。`moon add` 别人的工程时 dll 就在 `.mooncakes` 里，同样适用。

**发布/分发时才需要 app-local**：把 dll 与 exe 放同一目录（加载器第一顺位找 exe 所在目录，优先于上面那个构建期目录）。一条命令代劳（缺 exe 时先自动 `moon build`，`--run` 补完直接启动）：

```sh
python scripts/win_ffmpeg_dll.py                 # audio + video 一起补齐
python scripts/win_ffmpeg_dll.py audio           # 只补 audio
python scripts/win_ffmpeg_dll.py video --run     # 补齐后启动
python scripts/win_ffmpeg_dll.py --dll-dir D:\ffmpeg\bin   # 手头已有 bin 目录
python scripts/win_ffmpeg_dll.py --dry-run       # 只打印计划，不动文件
```

来源顺序：`--dll-dir` → exe 同目录 → prebuild 落点 → PATH → winget → scoop → 旧缓存。`moon clean` 清掉 `_build` 后需要重跑一次（dll 跟着 exe 目录走）。

**手工路径（脚本取不到来源时）**：

- Windows 没有 unix 那种「装一个 dev 包就全局可见」的机制，惯例是 **app-local 部署**——把依赖 dll 与 exe 放同一目录（加载器第一顺位就找 exe 所在目录），发布时随包带出去。放 PATH 只适合开发机；静态链接则与 `vendor/*.lib`（导入库）不兼容，且 LGPL 静态链接还要额外满足「可重链接」义务，本仓不走这条。winget/scoop/choco 这类包管理器只是把文件放到某处，**并不能让 dll 被找到**，仍要 app-local 或 PATH。
- **本仓最短路径**：winget 有与 `vendor/` **同源**的包 —— `BtbN.FFmpeg.LGPL.Shared.9.0`（BtbN / LGPL / **shared** / 9.0 分支，与 vendor 导入库出处一致）。装完 dll 落在该包目录的 `bin/`；winget 的 portable 包通常会把该 `bin` 加进 PATH，用 `where avcodec-63.dll` 确认，没有就手工把该目录加进 PATH。
- ⚠️ **别拿 `Gyan.FFmpeg` 当来源**：那是**静态**构建（`bin/` 只有 ffmpeg/ffplay/ffprobe 三个 exe、每个约 228MB，整个包目录零 dll）——静态 exe 把 ffmpeg 编进去了，不可能把库借给别的进程。同理 BtbN 的 `*.GPL`（static）分支也不行，要 `Shared`。

Linux 侧需系统 ffmpeg 开发包（`libav*-dev`，`pkg-config` 探测）。
