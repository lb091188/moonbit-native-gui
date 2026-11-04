# 音量与媒体

统一 `Result` 语义与支持矩阵见[系统能力总览](sys.md)。

## 系统音量

作用于默认输出设备（default sink）。后端自动探测：优先 wpctl（PipeWire/WirePlumber），不可用回退 pactl（pipewire-pulse / PulseAudio），两者都不可用即 `Unsupported`。探测每次真实执行，高频场景请调用方自行缓存结果。

| 函数 | 说明 |
|---|---|
| `vol_supported() -> Bool` | 当前系统是否支持音量控制 |
| `vol_get() -> Result[VolumeInfo, VolumeError]` | 读快照：`VolumeInfo{ sink, volume, muted }`；sink 取不到时为空串，不影响音量与静音 |
| `vol_set(percent) -> Result[Unit, VolumeError]` | 设绝对音量（0-100，出界钳制） |
| `vol_add(delta) -> Result[Unit, VolumeError]` | 相对增减；最终音量由工具侧钳制 |
| `vol_set_mute(mute) -> Result[Unit, VolumeError]` | 设 / 取消静音 |

错误 `VolumeError`：`Unsupported`（无可用音量工具）/ `CommandFailed(String)`（含超时）/ `ParseFailed(String)`（输出解析失败，带原文）。

```moonbit
match @sys.vol_get() {
  Ok(v) =>
    println(
      "sink=\{v.sink} 音量=\{v.volume}% 静音=\{if v.muted { "是" } else { "否" }}",
    )
  Err(e) => println("不可用：\{e}")
}
let _ = @sys.vol_set(42)
let _ = @sys.vol_add(-5)
let _ = @sys.vol_set_mute(false)
```

## 媒体控制（MPRIS）

枚举会话总线上的 `org.mpris.MediaPlayer2.*` 播放器实例，播放控制（play / pause / play_pause / next / previous / stop）与状态读取（PlaybackStatus + Metadata 的 title / artist / album）走 MPRIS Player 接口；总线失败可回退 `playerctl` 子命令。目前仅实现 Linux 路径，其余平台一律 `Unsupported`。

| 函数 | 说明 |
|---|---|
| `media_supported() -> Bool` | 会话总线可用（ListNames 通）或 playerctl 可用 |
| `media_players() -> Result[Array[MediaPlayerInfo], MediaError]` | 枚举播放器实例（含 playerctld 代理实例），保持 ListNames 应答序；一个都没有给 `NoPlayer` |
| `media_status(player) -> Result[MediaStatus, MediaError]` | 读某播放器状态与当前曲目 |
| `media_play(player)` / `media_pause(player)` / `media_play_pause(player)` / `media_next(player)` / `media_previous(player)` / `media_stop(player)` | 播放控制（返回 `Result[Unit, MediaError]`） |

`MediaPlayerInfo{ name, identity }`：name 为总线名（`media_status` / 播放控制的入参），identity 为播放器显示名。`MediaStatus{ player, playback, title, artist, album }`，`MediaPlayback` 为 `MediaPlaying` / `MediaPaused` / `MediaStopped` / `MediaUnknown(String)`。错误 `MediaError`：`Unsupported` / `NoPlayer` / `BusFailed(String)`（带错误名与说明）/ `CommandFailed(String)`（playerctl 回退失败）/ `ParseFailed(String)`。

播放控制属设置类操作，只在调用方显式调用时执行，探测与查询路径不会触发。

```moonbit
match @dbus.media_players() {
  Ok(players) if players.length() > 0 => {
    let p = players[0].name
    match @dbus.media_status(p) {
      Ok(s) => println("\{s.title} - \{s.artist}（\{s.playback}）")
      Err(e) => println("读状态失败：\{e}")
    }
    let _ = @dbus.media_play_pause(p)
  }
  Err(@dbus.MediaError::NoPlayer) => println("无播放器")
  Err(e) => println("不可用：\{e}")
}
```

### 媒体状态监视

MPRIS 无统一信号回调通路——`PropertiesChanged` 需要常驻读循环，与库的同步调用模型不兼容。状态监视采用轮询增量：按间隔读状态，播放态 / 标题 / 艺术家 / 专辑任一变化即触发 `on_change`；首轮只建立基线不触发；目标播放器（空 player 取首个实例）出现前每轮重试解析，出现后锁定；查询失败的轮次静默跳过。

| 函数 | 说明 |
|---|---|
| `MediaWatcher::make() -> MediaWatcher` | 建监视句柄（默认运行中） |
| `media_watch_status(player?, interval_ms? = 1000, on_change) -> MediaWatcher` | 启动轮询监视；player 为空监视首个 MPRIS 实例；on_change 得 `MediaStatus` |
| `media_watch_stop(w)` | 停止监视（下一帧注销定时器；不可恢复，重新监视请用新句柄） |
| `MediaWatcher::is_running() -> Bool` | 句柄是否在监视 |

`on_change` 回调抛异常会中断该定时器；组件销毁前调用 `media_watch_stop` 显式停止。

```moonbit
let w = @sys.media_watch_status(interval_ms=1000, fn(s : @sys.MediaStatus) {
  println("现在播放：\{s.title} - \{s.artist}")
})
// 不再关心时
@sys.media_watch_stop(w)
```

### 通知进度

freedesktop 通知协议无 progress 字段，Windows / macOS 的原生进度呈现各自为政。跨平台一致的做法是在正文内渲染字符进度条 + 百分比。

| 函数 | 说明 |
|---|---|
| `notification_progress_text(percent : Double, width? : Int = 10) -> String` | 进度文本：字符条 + 百分比（percent 钳到 [0,100]，NaN 按 0，width<=0 只给百分比） |
| `Notification::set_progress(body : String, percent : Double, width? : Int = 10) -> Unit` | 设通知正文：首行原文 + 第二行进度 |

```moonbit
let n = @shell.Notification::new()
n.set_title("导出中")
n.set_progress("正在导出 3/8 个文件", 37.5, width=4)
n.show()
```

## 音频/视频播放（gui-media 可选层）

媒体播放不在主模块的包里，在可选模块 `NoahLiu/gui-media`（依赖 `NoahLiu/ffmpeg-mbt`）：

```moonbit
// moon.mod import: "NoahLiu/gui-media@0.2.0"
// moon.pkg import: "NoahLiu/gui-media/media" @guimedia
```

解码走 ffmpeg FFI（进程内动态链，格式随系统 ffmpeg：MP3/OGG/M4A/AAC/FLAC/WAV…），输出由内嵌 miniaudio 设备层直出（s16 PCM 队列，零重采样）。无输出设备环境（CI/headless）自动静音降级，状态机照常。

三平台都要系统给得出 ffmpeg：Linux 用发行版的 dev 包（`apt install libav*-dev`），Windows 用 vendor 进仓库的头与导入库（运行期 dll 自行放置），macOS 用 `brew install ffmpeg`（构建期走 pkg-config 探测，探不到就非零退出并给出这一行安装提示——媒体线不静默降级成跑起来没解码器的样子）。音频设备后端按平台由 miniaudio 选：Linux ALSA/Pulse、Windows WASAPI、macOS CoreAudio。

### AudioPlayer（对标浏览器 `<audio>`）

```moonbit
let player = @guimedia.AudioPlayer::make("/path/song.mp3")?
player.play()
// 声明式节点组件:纯音频,含歌词与频谱条
let node = @guimedia.audio("/path/song.mp3", lyric="/path/song.lrc")
```

| API | 说明 |
|---|---|
| `AudioPlayer::make(path, volume?=0.8, looping?=false)` | 打开音频文件（ffmpeg 全格式）+ 输出设备 |
| `play() / pause() / stop() / seek(t_s)` | 播放控制（seek 清队列重定位，播放中从新位置续播） |
| `pump()` | 推进一步（补 PCM 队列/播完转态）——组件 50ms 时钟自动调，独立使用时自行定时调 |
| `is_playing() / current() / duration() / has_audio 对应 is_muted()` | 状态/位置（按设备已消费字节换算）/时长/静音降级查询 |
| `set_volume(0..1) / get_volume / set_looping` | 音量与循环 |
| `free()` | 释放（之后组件时钟自动停摆） |

### VideoPlayer（对标浏览器 `<video>`）

FFI 全链路：视频流逐帧 RGBA（时间戳级 seek），音轨是同文件的第二个独立解码器，解出 PCM 直推输出设备——无 CLI 子进程。无音轨/无输出设备自动静音。

```moonbit
let player = @guimedia.VideoPlayer::make("demo.mp4", fps=12, width=480)?
player.play()
// 声明式节点组件:含音轨与字幕叠加
let node = @guimedia.video("demo.mp4", subtitle="/path/demo.srt")
```

| API | 说明 |
|---|---|
| `VideoPlayer::make(path, fps?=12, width?=0, height?=0, volume?=0.8, looping?=false)` | 打开视频（含音轨双解码器；同步耗时，宜放 `set_timeout`） |
| `play() / pause() / stop() / seek(t_s)` | 播放控制（seek 双流各自重定位续播） |
| `is_playing() / current() / duration() / has_audio()` | 状态/位置/时长/音轨查询 |
| `current_frame() / frame_width() / frame_height()` | 当前帧 RGBA（自渲染场景） |
| `set_volume / set_looping / free()` | 音量/循环/释放 |

播放控制条内置于 `audio` / `video` 两个节点组件：播放/暂停按钮、可拖进度条（松手防抖 180ms 后 seek）、时间文本（m:ss / m:ss）、音量滑条、循环开关；50ms 时钟自动 pump + 刷新，`free()` 后时钟自动停摆。

播放演示见 `cd examples/audio && moon run .` / `cd examples/video && moon run .`——启动即自动载入默认资产，播放/暂停/拖进度/音量/倍速全部可交互。
