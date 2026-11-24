// 帧耗时分段统计（性能诊断）：paint_frame 每帧把「布局 / 绘制 / 上屏」三段
// 耗时累进一份进程级账本，宿主退出时取汇总。只累加不打印，每帧开销是几次
// Int64 加法，因此常开、不设开关；时间取自平台单调微秒时钟，60/120Hz 的
// 帧间隔分辨得开。
//
// 两本账：
//   ① 分段账本：layout / paint / present / total 按毫秒汇总，字段名与旧口径
//      一致，读数脚本不受影响；
//   ② 帧节奏账：相邻两帧结束时刻的间隔，出每秒帧数、p50 / p95 / 最大间隔与
//      丢刷新帧数。PROF 行由 paint_frame 每 2 秒打印一次，两本账同段输出。

///|
/// 帧间隔直方图粒度与覆盖上限（微秒）：100µs 一格、覆盖 0–100ms，超出落
/// 溢出格。p50 / p95 用直方图求，不打乱原数组也不依赖排序。
const PACING_BUCKET_US : Int64 = 100

///|
const PACING_BUCKETS : Int32 = 1000

///|
/// 空闲间隔判定（微秒）：超过 4 个刷新周期按空闲算、不进帧节奏统计——手势
/// 之间的自然停顿（100–200ms）不该记成「长停顿」，一次走神也不该把 p95
/// 拖到秒级。下限 50ms 兜住刷新率读不到时的 60Hz 假设。
fn pacing_idle_us() -> Int64 {
  let v = g_frame_prof.budget_us * 4L
  if v < 50000L { 50000L } else { v }
}

///|
priv struct FrameProf {
  mut frames : Int32
  mut layout_us : Int64
  mut paint_us : Int64
  mut present_us : Int64
  mut total_us : Int64
  mut max_total_us : Int64
  // 每帧重绘范围的两条计数：整帧与按脏矩形裁剪后画到的控件数、被视口剔除
  // 跳过的控件数（性能基线探针 `experiment/frame_cost_probe` 吃这三个数）。
  mut relayout_calls : Int32
  mut paint_visit : Int32
  mut paint_skip : Int32
  // 帧节奏：上一帧结束时刻、间隔直方图（末格为溢出）、间隔总数与总和、
  // 最大间隔、超预算帧数、预算（微秒）
  mut last_end_us : Int64
  mut buckets : Array[Int32]
  mut interval_n : Int32
  mut interval_sum_us : Int64
  mut max_interval_us : Int64
  mut over_budget : Int32
  mut budget_us : Int64
}

///|
let g_frame_prof : FrameProf = {
  frames: 0,
  layout_us: 0L,
  paint_us: 0L,
  present_us: 0L,
  total_us: 0L,
  max_total_us: 0L,
  relayout_calls: 0,
  paint_visit: 0,
  paint_skip: 0,
  last_end_us: 0L,
  buckets: Array::make(PACING_BUCKETS + 1, 0),
  interval_n: 0,
  interval_sum_us: 0L,
  max_interval_us: 0L,
  over_budget: 0,
  budget_us: 16667L,
}

///|
/// 设帧预算（微秒）：刷新率 60Hz 取 16667、120Hz 取 8333。默认 60Hz。
pub fn prof_set_budget_us(us : Int64) -> Unit {
  if us > 0L {
    g_frame_prof.budget_us = us
  }
}

///|
pub fn prof_record(
  layout_us : Int64,
  paint_us : Int64,
  present_us : Int64,
  total_us : Int64,
  now_us : Int64,
) -> Unit {
  let p = g_frame_prof
  p.frames += 1
  p.layout_us += layout_us
  p.paint_us += paint_us
  p.present_us += present_us
  p.total_us += total_us
  if total_us > p.max_total_us {
    p.max_total_us = total_us
  }
  // 帧节奏：上一帧结束到本帧结束的间隔。首帧与空闲后的首帧不入账
  if p.last_end_us > 0L {
    let iv = now_us - p.last_end_us
    if iv > 0L && iv <= pacing_idle_us() {
      let b = (iv / PACING_BUCKET_US).to_int()
      let bi = if b >= PACING_BUCKETS { PACING_BUCKETS } else { b }
      p.buckets[bi] += 1
      p.interval_n += 1
      p.interval_sum_us += iv
      if iv > p.max_interval_us {
        p.max_interval_us = iv
      }
      // 丢刷新口径：超过 1.5 倍预算才算这一帧错过了刷新；真实刷新周期
      // 常比名义值大半毫秒（59.94Hz 的 16.68ms），贴预算记会整窗误报
      if iv > p.budget_us + p.budget_us / 2L {
        p.over_budget += 1
      }
    }
  }
  p.last_end_us = now_us
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
  p.layout_us = 0L
  p.paint_us = 0L
  p.present_us = 0L
  p.total_us = 0L
  p.max_total_us = 0L
  p.relayout_calls = 0
  p.paint_visit = 0
  p.paint_skip = 0
  p.last_end_us = 0L
  p.buckets = Array::make(PACING_BUCKETS + 1, 0)
  p.interval_n = 0
  p.interval_sum_us = 0L
  p.max_interval_us = 0L
  p.over_budget = 0
}

///|
/// 累计汇总，一行可读串（毫秒口径，字段与旧读数脚本一致）：
/// "frames=120 layout=2100ms paint=9800ms present=340ms total=12400ms
/// max_frame=310ms relayout=120 visit=1800 skip=600"
pub fn paint_profile_summary() -> String {
  let p = g_frame_prof
  "frames=" +
  p.frames.to_string() +
  " layout=" +
  (p.layout_us / 1000L).to_string() +
  "ms paint=" +
  (p.paint_us / 1000L).to_string() +
  "ms present=" +
  (p.present_us / 1000L).to_string() +
  "ms total=" +
  (p.total_us / 1000L).to_string() +
  "ms max_frame=" +
  (p.max_total_us / 1000L).to_string() +
  "ms relayout=" +
  p.relayout_calls.to_string() +
  " visit=" +
  p.paint_visit.to_string() +
  " skip=" +
  p.paint_skip.to_string()
}

///|
/// 帧节奏汇总：每秒帧数、间隔 p50 / p95 / 最大（微秒）、丢刷新帧数。
/// 空闲间隔不入账；没有两帧相邻过时只给 fps=0。
pub fn paint_pacing_summary() -> String {
  let p = g_frame_prof
  let n = p.interval_n
  if n <= 0 {
    return "fps=0 interval=n/a"
  }
  let mean_us = p.interval_sum_us.to_double() / n.to_double()
  // 每秒帧数按平均间隔算，一位小数
  let fps10 = if mean_us > 0.0 {
    (10000000.0 / mean_us).round().to_int64()
  } else {
    0L
  }
  let fps_s = (fps10 / 10L).to_string() + "." + (fps10 % 10L).to_string()
  // 直方图求分位：累计格数首次达到分位即取该格上界
  let pick = fn(q : Int32) -> Int64 {
    let need = (n * q + 99) / 100
    let mut acc = 0
    let mut i = 0
    while i <= PACING_BUCKETS {
      acc = acc + p.buckets[i]
      if acc >= need {
        if i >= PACING_BUCKETS {
          return 100000L
        }
        return (i + 1).to_int64() * PACING_BUCKET_US
      }
      i = i + 1
    }
    100000L
  }

  "fps=" +
  fps_s +
  " budget=" +
  p.budget_us.to_string() +
  "us interval_p50=" +
  pick(50).to_string() +
  "us p95=" +
  pick(95).to_string() +
  "us max=" +
  p.max_interval_us.to_string() +
  "us over=" +
  p.over_budget.to_string()
}
