// 帧耗时分段统计（性能诊断）：paint_frame 每帧把「布局 / 绘制 / 上屏」三段
// 耗时累进一份进程级账本，宿主退出时取汇总。只累加不打印，每帧开销是几次
// Int64 加法，因此常开、不设开关；时间取自平台单调毫秒时钟，单段亚毫秒的
// 量化误差在多帧累计下可忽略。

///|
priv struct FrameProf {
  mut frames : Int32
  mut layout_ms : Int64
  mut paint_ms : Int64
  mut present_ms : Int64
  mut total_ms : Int64
  mut max_total_ms : Int64
  // 每帧重绘范围的两条计数：整帧与按脏矩形裁剪后画到的控件数、被视口剔除
  // 跳过的控件数（性能基线探针 `experiment/frame_cost_probe` 吃这三个数）。
  mut relayout_calls : Int32
  mut paint_visit : Int32
  mut paint_skip : Int32
}

///|
let g_frame_prof : FrameProf = {
  frames: 0,
  layout_ms: 0L,
  paint_ms: 0L,
  present_ms: 0L,
  total_ms: 0L,
  max_total_ms: 0L,
  relayout_calls: 0,
  paint_visit: 0,
  paint_skip: 0,
}

///|
pub fn prof_record(
  layout_ms : Int64,
  paint_ms : Int64,
  present_ms : Int64,
  total_ms : Int64,
) -> Unit {
  let p = g_frame_prof
  p.frames += 1
  p.layout_ms += layout_ms
  p.paint_ms += paint_ms
  p.present_ms += present_ms
  p.total_ms += total_ms
  if total_ms > p.max_total_ms {
    p.max_total_ms = total_ms
  }
}

///|
/// 记一次布局重算（`Widget::relayout_at` 走到 yoga 计算即一次）。
pub fn prof_note_relayout() -> Unit {
  g_frame_prof.relayout_calls += 1
}

///|
/// 记一个控件被画到 / 被视口剔除跳过（每帧重绘范围的读数）。
pub fn prof_note_paint_visit() -> Unit {
  g_frame_prof.paint_visit += 1
}

///|
pub fn prof_note_paint_skip() -> Unit {
  g_frame_prof.paint_skip += 1
}

///|
/// 清零账本（多窗共用一份进程级账本，新一轮观测前先清）。
pub fn paint_profile_reset() -> Unit {
  let p = g_frame_prof
  p.frames = 0
  p.layout_ms = 0L
  p.paint_ms = 0L
  p.present_ms = 0L
  p.total_ms = 0L
  p.max_total_ms = 0L
  p.relayout_calls = 0
  p.paint_visit = 0
  p.paint_skip = 0
}

///|
/// 累计汇总，一行可读串：
/// "frames=120 layout=2100ms paint=9800ms present=340ms total=12400ms max_frame=310ms"
pub fn paint_profile_summary() -> String {
  let p = g_frame_prof
  "frames=" +
  p.frames.to_string() +
  " layout=" +
  p.layout_ms.to_string() +
  "ms paint=" +
  p.paint_ms.to_string() +
  "ms present=" +
  p.present_ms.to_string() +
  "ms total=" +
  p.total_ms.to_string() +
  "ms max_frame=" +
  p.max_total_ms.to_string() +
  "ms relayout=" +
  p.relayout_calls.to_string() +
  " visit=" +
  p.paint_visit.to_string() +
  " skip=" +
  p.paint_skip.to_string()
}
