# Volume & media

Uniform `Result` semantics and the support matrix: [System capabilities overview](sys.md).

## System Volume

Acts on the default output device (default sink). The backend is auto-detected: wpctl (PipeWire/WirePlumber) is preferred; when unavailable it falls back to pactl (pipewire-pulse / PulseAudio); when neither works the result is `Unsupported`. The probe runs for real on every call — cache the results yourself in high-frequency scenarios.

| Function | Description |
|---|---|
| `vol_supported() -> Bool` | whether the current system supports volume control |
| `vol_get() -> Result[VolumeInfo, VolumeError]` | read a snapshot: `VolumeInfo{ sink, volume, muted }`; the sink is an empty string when unavailable, which does not affect volume or mute |
| `vol_set(percent) -> Result[Unit, VolumeError]` | set absolute volume (0-100, out-of-range clamped) |
| `vol_add(delta) -> Result[Unit, VolumeError]` | relative adjust; the tool side clamps the final volume |
| `vol_set_mute(mute) -> Result[Unit, VolumeError]` | set / clear mute |

Error `VolumeError`: `Unsupported` (no usable volume tool) / `CommandFailed(String)` (includes timeout) / `ParseFailed(String)` (output parse failed, carries the raw text).

```moonbit
match @sys.vol_get() {
  Ok(v) =>
    println(
      "sink=\{v.sink} volume=\{v.volume}% muted=\{if v.muted { "Yes" } else { "No" }}",
    )
  Err(e) => println("Unavailable: \{e}")
}
let _ = @sys.vol_set(42)
let _ = @sys.vol_add(-5)
let _ = @sys.vol_set_mute(false)
```

## Media Control (MPRIS)

Enumerates `org.mpris.MediaPlayer2.*` player instances on the session bus. Playback control (play / pause / play_pause / next / previous / stop) and status reads (PlaybackStatus + title / artist / album from Metadata) go through the MPRIS Player interface; a bus failure can fall back to the `playerctl` subcommand. Only the Linux path is implemented so far; other platforms uniformly yield `Unsupported`.

| Function | Description |
|---|---|
| `media_supported() -> Bool` | the session bus works (ListNames succeeds) or playerctl works |
| `media_players() -> Result[Array[MediaPlayerInfo], MediaError]` | enumerate player instances, including the playerctld proxy instance; preserves the ListNames response order; yields `NoPlayer` when there is none |
| `media_status(player) -> Result[MediaStatus, MediaError]` | read one player's status and current track |
| `media_play(player)` / `media_pause(player)` / `media_play_pause(player)` / `media_next(player)` / `media_previous(player)` / `media_stop(player)` | playback control (returns `Result[Unit, MediaError]`) |

`MediaPlayerInfo{ name, identity }`: name is the bus name — the argument to `media_status` and the playback-control calls; identity is the player's display name. `MediaStatus{ player, playback, title, artist, album }`; `MediaPlayback` is `MediaPlaying` / `MediaPaused` / `MediaStopped` / `MediaUnknown(String)`. Error `MediaError`: `Unsupported` / `NoPlayer` / `BusFailed(String)` (carries the error name and description) / `CommandFailed(String)` (playerctl fallback failed) / `ParseFailed(String)`.

Playback control is a set-class operation: it runs only when the caller invokes it explicitly; probe and query paths never trigger it.

```moonbit
match @dbus.media_players() {
  Ok(players) if players.length() > 0 => {
    let p = players[0].name
    match @dbus.media_status(p) {
      Ok(s) => println("\{s.title} - \{s.artist} (\{s.playback})")
      Err(e) => println("Failed to read status: \{e}")
    }
    let _ = @dbus.media_play_pause(p)
  }
  Err(@dbus.MediaError::NoPlayer) => println("No player")
  Err(e) => println("Unavailable: \{e}")
}
```

### Media Status Watching

MPRIS has no unified signal-callback path — `PropertiesChanged` needs a resident read loop, incompatible with the library's synchronous-call model. Status watching therefore polls for deltas: it reads status at an interval and fires `on_change` when playing state / title / artist / album changes. The first round only establishes the baseline and does not fire. Before the target player appears, resolution is retried each round and locks once it appears (an empty player takes the first instance). Rounds whose query fails are silently skipped.

| Function | Description |
|---|---|
| `MediaWatcher::make() -> MediaWatcher` | create a watch handle (running by default) |
| `media_watch_status(player?, interval_ms? = 1000, on_change) -> MediaWatcher` | start polling; an empty player watches the first MPRIS instance; on_change receives a `MediaStatus` |
| `media_watch_stop(w)` | stop watching; the timer deregisters on the next frame. Not recoverable — use a new handle to watch again |
| `MediaWatcher::is_running() -> Bool` | whether the handle is watching |

An exception thrown in the `on_change` callback interrupts that timer; call `media_watch_stop` explicitly before the component is destroyed.

```moonbit
let w = @sys.media_watch_status(interval_ms=1000, fn(s : @sys.MediaStatus) {
  println("Now playing: \{s.title} - \{s.artist}")
})
// when no longer needed
@sys.media_watch_stop(w)
```

### Notification Progress

Notification progress has no unified field across the three platforms; presentation follows each backend:

| Platform | Presentation |
|---|---|
| Linux (freedesktop) | standard hint `value`; servers that support it render progress natively |
| Windows | percentage appended into the notification body (`body (42%)`) |
| macOS | no progress presentation (argument ignored) |

| Function | Description |
|---|---|
| `notify_send(app_name, summary, body, …, progress? = -1, …) -> Result[Int32, NotifyError]` | send a notification; when `progress` is 0..100 the progress is carried per the table above |
| `notify_progress(id, app_name, summary, body, pct) -> Result[Int32, NotifyError]` | update progress in place by id (re-sends the same notification; if the id changes, continue with the returned one) |

```moonbit
let id = match @shell.notify_send(
  "Example App",
  "Exporting",
  "Exporting 3/8 files",
  progress=37,
) {
  Ok(id) => id
  Err(_) => return
}
// As progress advances: update the same notification in place
let _ = @shell.notify_progress(id, "Example App", "Exporting", "Exporting 3/8 files", 50)
```

## Audio/Video Playback (gui-media Optional Layer)

Media playback is not in the main module's packages; it lives in the optional module `NoahLiu/gui-media` (depending on `NoahLiu/ffmpeg-mbt`):

```moonbit
// moon.mod import: "NoahLiu/gui-media@0.2.0"
// moon.pkg import: "NoahLiu/gui-media/media" @guimedia
```

Decoding goes through the ffmpeg FFI, linked dynamically in-process; formats follow the system ffmpeg: MP3/OGG/M4A/AAC/FLAC/WAV…. Output goes straight through the embedded miniaudio device layer (s16 PCM queue, zero resampling). With no output device (CI/headless) it automatically degrades to silent while the state machine proceeds as normal.

All three platforms need a system-level ffmpeg: Linux uses the distro dev packages (`apt install libav*-dev`), Windows the vendored headers and import libs in the repo (runtime DLLs placed by hand), macOS `brew install ffmpeg` (`modules/ffmpeg-mbt/prebuild.py` probes via pkg-config and exits nonzero with that one install hint when not found — the media line never silently builds a stub that "links fine but has no decoders"). The audio device backend is picked by miniaudio per platform: Linux ALSA/Pulse, Windows WASAPI, macOS CoreAudio, so on mac `gui-media` links three extra frameworks (CoreAudio/AudioToolbox/Foundation) and deliberately does **not** link `-ldl`/`-latomic` (mac's dlopen lives in libSystem, and there is no libatomic).

### AudioPlayer (browser `<audio>` counterpart)

```moonbit
let player = @guimedia.AudioPlayer::make("/path/song.mp3")?
player.play()
// declarative node component: pure audio, with lyrics and spectrum bars
let node = @guimedia.audio("/path/song.mp3", lyric="/path/song.lrc")
```

| API | Description |
|---|---|
| `AudioPlayer::make(path, volume?=0.8, looping?=false)` | open an audio file (all ffmpeg formats) + the output device |
| `play() / pause() / stop() / seek(t_s)` | playback control; seek clears the queue and relocates, then resumes from the new position while playing |
| `pump()` | advance one step — refill the PCM queue / transition state when playback ends; the component's 50ms clock calls it automatically, and when used standalone call it on your own timer |
| `is_playing() / current() / duration() / is_muted()` | state / position (converted from bytes the device has consumed) / duration / silent-degradation query; `is_muted()` is the counterpart of `has_audio` |
| `set_volume(0..1) / get_volume / set_looping` | volume and looping |
| `free()` | release; afterwards the component clock halts automatically |

### VideoPlayer (browser `<video>` counterpart)

The full FFI chain: the video stream yields per-frame RGBA with timestamp-level seek; the audio track is a second independent decoder on the same file whose PCM is pushed straight to the output device — no CLI subprocess. No audio track or no output device automatically goes silent.

```moonbit
let player = @guimedia.VideoPlayer::make("demo.mp4", fps=12, width=480)?
player.play()
// declarative node component: video with the audio track and subtitle overlay
let node = @guimedia.video("demo.mp4", subtitle="/path/demo.srt")
```

| API | Description |
|---|---|
| `VideoPlayer::make(path, fps?=12, width?=0, height?=0, volume?=0.8, looping?=false)` | open a video (dual decoders including the audio track); synchronous and time-consuming, best placed in `set_timeout` |
| `play() / pause() / stop() / seek(t_s)` | playback control; seek relocates each of the two streams and resumes |
| `is_playing() / current() / duration() / has_audio()` | state / position / duration / audio-track query |
| `current_frame() / frame_width() / frame_height()` | current frame RGBA, for self-rendering scenarios |
| `set_volume / set_looping / free()` | volume / loop / release |

The playback control bar is built into the `audio` / `video` node components: play/pause button, draggable progress bar (seeks 180ms after drag-release debouncing), time text (m:ss / m:ss), volume slider, loop toggle. The 50ms clock pumps and refreshes automatically; after `free()` the clock halts on its own.

Player demos: `cd examples/audio && moon run .` / `cd examples/video && moon run .` — the default asset auto-loads on startup, and play/pause/seek/volume/speed are all interactive.
