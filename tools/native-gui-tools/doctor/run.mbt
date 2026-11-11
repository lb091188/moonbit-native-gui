// 全量体检编排与判据。

///|
/// 全量体检：按平台挑必选与可选项；探针日志落 `<home>/.mng/doctor/`。
pub fn run_all(
  platform~ : String = host(),
  home~ : String = home_dir(),
) -> Array[DItem] {
  let log_dir = home + "/.mng/doctor"
  let items : Array[DItem] = []
  items.push(check_moon(platform, log_dir))
  items.push(check_python(platform, log_dir))
  if platform == "linux" {
    items.push(check_cc(platform, log_dir))
    items.push(check_gtk(log_dir))
    items.push(
      check_pkg_lib(
        log_dir,
        id="webkit",
        lib="webkit2gtk-4.1",
        title=bi(
          "WebView 开发库（可选）", "WebView dev package (optional)",
        ),
        why=bi(
          "未找到 webkit2gtk-4.1——内嵌 WebView 需要", "webkit2gtk-4.1 not found; required by the embedded WebView",
        ),
        fix="sudo apt install libwebkit2gtk-4.1-dev",
      ),
    )
    items.push(
      check_pkg_lib(
        log_dir,
        id="ffmpeg-dev",
        lib="libavformat",
        title=bi("媒体开发库（可选）", "Media dev packages (optional)"),
        why=bi(
          "未找到 libavformat——媒体模块（gui-media / ffmpeg-mbt）需要",
          "libavformat not found; required by the media modules (gui-media / ffmpeg-mbt)",
        ),
        fix="sudo apt install libavformat-dev libavcodec-dev libswscale-dev libswresample-dev libavutil-dev",
      ),
    )
  } else if platform == "mac" {
    items.push(check_cc(platform, log_dir))
    items.push(check_ffmpeg_mac(log_dir))
  } else {
    items.push(check_msvc(log_dir))
  }
  items
}

///|
/// 必选项是否全过（可选项的 Warn / Fail 不拦 ready）。
pub fn required_ok(items : Array[DItem]) -> Bool {
  for it in items {
    if !it.optional && it.status is Fail {
      return false
    }
  }
  true
}
