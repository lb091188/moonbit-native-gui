# examples 示例集

`examples/` 下**每个示例目录就是一个独立模块**（各自一份 `moon.mod`，模块名 `NoahLiu/native-gui-examples-<目录名>`），全部注册在仓库根 `moon.work`。依赖只在自己的 `moon.mod` 里声明，示例之间互不相干：`hello` 一类基础示例不会牵出 ffmpeg 链路，媒体示例自己带 `gui-media`。

## audio / video（音视频播放示例）

依赖 `gui-media` 的两个播放器组件 `audio` / `video`（ffmpeg 解码 + miniaudio 设备直出，名字对齐 HTML 的 `<audio>` / `<video>`）。

- **audio**：左侧播放列表（当前曲目高亮、点击换曲）+ 右侧播放器与状态区；控制条是**图标按钮**（播放/暂停、±5 秒、全屏）+ 文字档位键（倍速）+ 自绘进度/音量条，播放器上方是**实时频谱条**（纯 MoonBit FFT，按设备队列回看对齐耳朵），歌词按**同名 `.lrc` 自动配对**（示例侧读文本、组件不做 IO，当前行画在频谱下方）。快捷键不点窗口也生效：空格播放/暂停、回车全屏、`←/→` ±5 秒、`↑/↓` 音量、`Esc` 退全屏。载入路径：默认资产 `assets/1.mp3` + `assets/1.lrc`（路径对工作目录稳健解析）、文件对话框选音频、目录对话框选文件夹后扫描成播放列表（无音频文件给空态）。
- **video**：视频区为主 + 侧栏播放列表/信息；字幕双来源——容器内嵌轨自动读取，或「选外挂 .srt」读文本传入（`on_subtitle` 回报来源与条数，可清除回内嵌轨）。控制条同上（逐帧键为 `←/→`），另有**缩放三档**（适配 / 铺满 / 1:1）与全屏。载入路径与 audio 同三条，默认资产 `assets/1.mp4`。

```sh
# 每个示例目录是一个独立模块，进目录跑；下面两条都从仓库根开始
cd examples/audio && moon run .
cd examples/video && moon run .
```

依赖：[native-gui](https://mooncakes.io/docs/NoahLiu/native-gui)、[gui-media](https://mooncakes.io/docs/NoahLiu/gui-media)、[ffmpeg-mbt](https://mooncakes.io/docs/NoahLiu/ffmpeg-mbt)。

Windows 跑这两个示例的 ffmpeg 运行期 dll——缺了会怎样、从哪来、发布时怎么随包——统一见 [docs/zh/build.md](../docs/zh/build.md) 的「Windows 运行期 ffmpeg dll」一节。
