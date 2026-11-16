// 帧泵钩子表：声明式挂窗（@ui.mount_window）每拍无条件遍历执行的一组回调。
// 给 inspector 服务这类「要在应用事件循环里搭车跑一小步」的能力用——钩子表
// 放 shell 层是因为 ui 与 inspector 互相依赖成环（面板吃 ui 控件），两边都
// 只能向上依赖 shell。表空时遍历零开销；注册没有反注册（服务生命周期与
// 进程一致，没有停下来的形态）。

///|
let g_frame_pumps : Ref[Array[() -> Unit]] = Ref([])

///|
/// 注册一个帧泵回调：宿主挂窗后每 200ms 一拍被调一次（自排续泵，进程内
/// 一直跑）。重复注册会重复执行——注册方自己保证幂等。
pub fn add_frame_pump(f : () -> Unit) -> Unit {
  g_frame_pumps.val.push(f)
}

///|
/// 遍历执行全部帧泵回调（declarative 挂窗时无条件接入）。回调里抛出的
/// 异常照常向上传——泵里不做静默兜底。
pub fn frame_pumps_fire() -> Unit {
  for f in g_frame_pumps.val {
    f()
  }
}
