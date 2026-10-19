// 只读系统探针：窗口层之外、与控件树零耦合的
// 平台读数——单调时钟、深浅偏好、系统主色、本地日期。
// 示例与集成层经此取值，不必引用平台包。

///|
/// 单调时钟（毫秒）。声明式组件的双击判定等要它；无后端时返回 0。
pub fn now_ms() -> Int64 { @win.now_ms() }

///|
/// 系统深浅偏好（"dark" / "light" / ""）。
pub fn sys_color_scheme() -> String {
  @win.sys_color_scheme()
}

///|
/// 系统主色（"#rrggbb" / ""）。
pub fn sys_accent() -> String {
  @win.sys_accent()
}

///|
/// 本地时区的今天 (年, 月, 日)。平台给不出时返回 (0, 0, 0)——组件层据此退回
/// 自己的兜底值，本层不猜日期。
pub fn local_ymd() -> (Int, Int, Int) {
  let v = @win.local_date()
  if v <= 0L {
    (0, 0, 0)
  } else {
    let iv = v.to_int()
    (iv / 10000, iv % 10000 / 100, iv % 100)
  }
}

///|
/// 平台标识："linux" / "windows" / "macos"（桩编译期判定）。上层按它做**运行时**
/// 平台分派（本栈不用 `#cfg(platform=)` 分派运行期行为）。
pub fn platform_name() -> String { @sys.sys_platform() }

///|
/// 是否 macOS：修饰键习惯与系统默认加速键都按它分档（Cmd 而非 Ctrl）。
pub fn platform_is_macos() -> Bool { platform_name() == "macos" }
