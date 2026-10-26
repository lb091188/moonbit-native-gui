// 系统权限（跨平台门面）：躲不开的系统授权做成横切族。两档语义——
//   系统权限（一次性）：辅助功能、屏幕录制…授权一次长期有效；mac 走 TCC，
//     探测公开口、请求弹系统自带引导框（不替用户点任何东西）；
//     Windows / Linux 无此概念，恒 NotNeeded。
//   操作提权（每次一弹）：macOS 管理员密码框（osascript）、将来 Windows
//     UAC——不落本族，随各自能力批处理（如电源计划 mac 档的写操作）。
// 状态语义只有「当前已授 / 未授」两态：TCC 的「未请求」与「拒绝」在公开 API
// 层不可区分，应用侧统一按「未授 → 请求 → 引导 → 用户回来再探」的节奏走。
//
// 典型用法：
//   match @sys.permission_probe(@sys.PermAccessibility) {
//     Ok(PermGranted) => ()                       // 直接干活
//     Ok(_) => { let _ = @sys.permission_request(@sys.PermAccessibility) }
//     Err(e) => println(e)
//   }

///|
/// 权限种类。首批两档都是窗口管理 mac 档要用的；后续按需扩
/// （通知已由 `@shell.notify_*` 自带授权流程，不在此族）。
pub(all) enum PermissionKind {
  /// macOS 辅助功能（Accessibility）：控制/操作其他应用的窗口要
  PermAccessibility
  /// macOS 屏幕录制（Screen Recording）：读到其他应用窗口的标题要
  PermScreenRecording
}

///|
/// 权限状态。macOS 只区分「已授/未授」两态（公开 API 不区分未请求与拒绝）；
/// Windows / Linux 恒 NotNeeded。
pub(all) enum PermissionStatus {
  /// 本平台没有这类权限概念
  PermNotNeeded
  /// 当前已授权
  PermGranted
  /// 当前未授权（未请求与拒绝在公开层不可区分）
  PermNotGranted
}

///|
pub impl Show for PermissionStatus with fn output(self, logger) {
  match self {
    PermNotNeeded => logger.write_string("PermNotNeeded")
    PermGranted => logger.write_string("PermGranted")
    PermNotGranted => logger.write_string("PermNotGranted")
  }
}

///|
pub extend PermissionStatus with Show::{to_string, output}

///|
pub(all) enum PermissionError {
  /// 当前平台没有权限族（非 mac）
  PermUnsupported
  /// 探测调用失败（极少见：桩链路异常）
  PermProbeFailed(String)
}

///|
pub impl Show for PermissionError with fn output(self, logger) {
  match self {
    PermUnsupported => logger.write_string("PermissionError::PermUnsupported")
    PermProbeFailed(msg) => {
      logger.write_string("PermissionError::PermProbeFailed(")
      logger.write_string(msg)
      logger.write_string(")")
    }
  }
}

///|
pub extend PermissionError with Show::{to_string, output}

///|
/// 系统权限探测口（mac 上是 TCC，读数即时；高频场景请调用方自行缓存）。
pub fn permission_supported() -> Bool {
  sys_platform() == "macos"
}

///|
/// 探测一项权限的当前状态。
pub fn permission_probe(
  kind : PermissionKind
) -> Result[PermissionStatus, PermissionError] {
  if sys_platform() != "macos" {
    return Ok(PermNotNeeded)
  }
  let code = match kind {
    PermAccessibility => 0
    PermScreenRecording => 1
  }
  let ok = Ref(0)
  let v = ffi_permission_probe(code, ok)
  if ok.val != 1 {
    return Err(PermProbeFailed("权限探测失败（kind=\{code}）"))
  }
  match v {
    1 => Ok(PermGranted)
    0 => Ok(PermNotGranted)
    _ => Err(PermProbeFailed("未知权限种类（kind=\{code}）"))
  }
}

///|
/// 请求一项权限：弹系统自带引导框（辅助功能是「打开系统设置」对话框，
/// 屏幕录制同）。**不阻塞等待授权结果**——用户跳走设置再回来需要时间，
/// 引导弹出后由调用方在合适时机重新 [permission_probe]。
pub fn permission_request(kind : PermissionKind) -> Result[Unit, PermissionError] {
  if sys_platform() != "macos" {
    return Ok(())
  }
  let code = match kind {
    PermAccessibility => 0
    PermScreenRecording => 1
  }
  ffi_permission_request(code)
  Ok(())
}

///|
/// 便捷组合（能力入口的内联权限守卫）：已授权（或本平台不需要）返回
/// `true`，调用方直接干活；未授权则**弹系统引导框**并返回 `false`——调用方
/// 提示「已弹授权框，授权后重试」即可，用户回来再走一遍入口自然通过。
/// 探测失败按未授权处理（同样给引导，宁多弹不静默失败）。
pub fn permission_ensure(kind : PermissionKind) -> Bool {
  match permission_probe(kind) {
    Ok(PermGranted) => true
    Ok(PermNotNeeded) => true
    _ => {
      let _ = permission_request(kind)
      false
    }
  }
}

///|
#borrow(ok)
extern "c" fn ffi_permission_probe(kind : Int, ok : Ref[Int]) -> Int = "wm_permission_probe"

///|
extern "c" fn ffi_permission_request(kind : Int) -> Unit = "wm_permission_request"
