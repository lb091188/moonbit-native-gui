// 单实例的 Win32 原生包装：命名互斥体判进程唯一，隐藏顶层窗收 WM_COPYDATA 帧。
// 消费方用 `@shell` 的跨平台门面（`shell/instance.mbt`），这里只放门面吃的
// 原生口。桩的返回码：listen/wake 给 >0 成功、<0 失败，失败原因取
// `inst_last_errno`；帧由 `inst_poll` 探、`inst_take` 抽走。

///|
/// 本臂是否可用（Windows 恒可用，其余平台为 false）。
pub fn inst_supported() -> Bool {
  wm_inst_supported() > 0
}

///|
/// 声称进程唯一。`slug` 是门面派生过的名字（只含 [A-Za-z0-9_-]）。
/// 返回 1 = 本进程是首实例，2 = 已有首实例，<0 = 失败。
pub fn inst_listen(slug : String) -> Int {
  wm_inst_listen(@utf8.encode(slug))
}

///|
/// 把一帧字节送进首实例（同步送到，对方没在抽消息时最多等 3 秒）。
/// 返回 >0 已送达，<0 失败。
pub fn inst_wake(slug : String, frame : Bytes) -> Int {
  wm_inst_wake(@utf8.encode(slug), frame, frame.length())
}

///|
/// 是否有一条完整帧待抽。
pub fn inst_poll() -> Bool {
  wm_inst_poll() > 0
}

///|
/// 抽走最近一条帧（抽完即清；没有帧给空 Bytes）。
pub fn inst_take() -> Bytes {
  let buf = Bytes::new(65536)
  let n = wm_inst_take(buf, 65536)
  if n <= 0 {
    Bytes::new(0)
  } else {
    buf[0:n].to_owned()
  }
}

///|
/// 最近一次失败的操作系统错误码（无错误为 0）。
pub fn inst_last_errno() -> Int {
  wm_inst_last_errno()
}

///|
/// 撤回本进程的声称（幂等；不调也随进程回收）。
pub fn inst_release() -> Unit {
  wm_inst_release()
}
