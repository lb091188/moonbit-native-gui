// 布局测量计数（性能基线探针的第三组读数）：`measure_content` 被问了几次、
// 其中多少次命中同参数缓存。只多两次整数加法，常开不设开关。
//
// 判据：一帧里 `measure` 远大于节点数、`hit` 又远低于 `measure`，说明同一棵树
// 每帧真在重测——那才是「再加一层布局缓存」的立项依据；命中率已经很高时再补
// 缓存就是白付失效判定的钱。读数经 `layout_stats_summary()` 取，探针在
// `experiment/frame_cost_probe` 里按场景分段打印。

priv struct LayoutStats {
  mut calls : Int
  mut hits : Int
}

///|
let g_layout_stats : LayoutStats = { calls: 0, hits: 0 }

///|
/// 清零（新一轮观测前）。
pub fn layout_stats_reset() -> Unit {
  g_layout_stats.calls = 0
  g_layout_stats.hits = 0
}

///|
/// 累计汇总，一行可读串："measure=1234 hit=1100"。
pub fn layout_stats_summary() -> String {
  "measure=" + g_layout_stats.calls.to_string() + " hit=" + g_layout_stats.hits.to_string()
}

///|
fn note_measure_call() -> Unit {
  g_layout_stats.calls += 1
}

///|
fn note_measure_hit() -> Unit {
  g_layout_stats.hits += 1
}
