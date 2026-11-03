// 性能基线探针（无头，不弹窗）：把「要不要给 yoga 再加一层布局缓存」「图表
// 增量重绘值不值得立项」这两个问题变成有数可依。三组读数——
//   ① 帧耗时分段（布局 / 绘制，与 App 的 `SHOWCASE-PROF` 同一本账）
//   ② 每帧重绘范围（一帧里画到多少控件、视口剔除跳过多少）
//   ③ 布局重算次数（yoga 被问了多少次测量、其中多少命中同参数缓存）
// 跑法：moon run experiment/frame_cost_probe
// 读数行前缀 FRAME-COST，一个场景一行；对照关系：
//   layout_steady vs layout_mutate ⇒ 文本变了才重算，缓存省了多少
//   paint_full vs paint_clip       ⇒ 脏矩形裁剪把多少控件挡在遍历之外
//   rows 扫 15/60/240              ⇒ 单帧成本随树规模的生长曲线
// 注意后端差异：视口剔除只在纯光栅器后端（Windows / macOS）判交，Linux 的
// cairo 分支不查（`skip=0` 属预期，不是坏了）——行首 `platform=` 标明这台是哪条腿。

const W = 1400
const H = 900
const N = 20

///|
/// 一页典型内容：每行「按钮 + 输入框 + 动态文本」，动态文本挂同一枚 Signal，
///  mutate 场景改它即触发整页重测。
fn page_of(rows : Int, sig : @base.Signal[String]) -> @widget.Node {
  let rows_nodes : Array[@widget.Node] = []
  for i = 0; i < rows; i = i + 1 {
    let _ = rows_nodes.push(@ui.row(
      [
        @ui.button("保存" + (i % 7).to_string(), variant=@ui.Solid),
        @ui.input(@base.Store::new("输入框内容")),
        if i == 0 {
          @ui.text_dyn(sig, class=[@style.text_secondary])
        } else {
          @ui.text("第 " + (i % 11).to_string() + " 行说明文字", class=[@style.text_secondary])
        },
      ],
      column_gap=8.0,
    ))
  }
  @ui.col(rows_nodes, row_gap=6.0, padding=12.0, width=W.to_double(), height=H.to_double())
}

///|
/// 挂好一页并布局一次，返回页控件。
fn mount_page(rows : Int, sig : @base.Signal[String]) -> @widget.Widget {
  let root = @widget.Widget::new()
  root.set_size(W.to_double(), H.to_double())
  root.set_column()
  let page = (page_of(rows, sig).mount)(root)
  root.relayout(W.to_double(), H.to_double())
  page
}

///|
/// 布局场景：`mutate` 为真时每帧改一次动态文本（缓存必然失效）。
fn run_layout(rows : Int, mutate : Bool) -> Unit {
  let sig = @base.Signal::new("基线文本")
  let root = @widget.Widget::new()
  root.set_size(W.to_double(), H.to_double())
  root.set_column()
  let _ = (page_of(rows, sig).mount)(root)
  let _ = root.relayout(W.to_double(), H.to_double())
  @base.paint_profile_reset()
  @yoga.layout_stats_reset()
  let t0 = @win.now_ms()
  for i = 0; i < N; i = i + 1 {
    if mutate {
      sig.set("基线文本 " + i.to_string())
    }
    let _ = root.relayout(W.to_double(), H.to_double())
  }
  let ms = @win.now_ms() - t0
  let per = ms.to_double() / N.to_double()
  let scene = if mutate { "layout_mutate" } else { "layout_steady" }
  println(
    "FRAME-COST scene=" + scene + " rows=" + rows.to_string() +
      " n=" + N.to_string() + " ms=" + ms.to_string() +
      " per_frame=" + per.to_string() +
      " ledger=" + @base.paint_profile_summary() +
      " yoga=" + @yoga.layout_stats_summary(),
  )
}

///|
/// 绘制场景：整页重绘 vs 裁到页首一小条（脏矩形的量级）。
fn run_paint(rows : Int, clip_h : Double) -> Unit {
  let sig = @base.Signal::new("基线文本")
  let page = mount_page(rows, sig)
  let bm = @render.Bitmap::new(W, H)
  let p = @render.Painter::new(bm)
  @base.paint_profile_reset()
  let t0 = @win.now_ms()
  let mut it = 0
  while it < N {
    if clip_h < 0.0 {
      page.paint(p)
    } else {
      p.save()
      p.clip_rect(0.0, 0.0, W.to_double(), clip_h)
      page.paint(p)
      p.restore()
    }
    it += 1
  }
  let ms = @win.now_ms() - t0
  p.end()
  let per = ms.to_double() / N.to_double()
  let scene = if clip_h < 0.0 { "paint_full" } else { "paint_clip" }
  let clip = if clip_h < 0.0 { "full" } else { clip_h.to_string() }
  println(
    "FRAME-COST scene=" + scene + " rows=" + rows.to_string() +
      " clip=" + clip + " n=" + N.to_string() +
      " ms=" + ms.to_string() + " per_frame=" + per.to_string() +
      " ledger=" + @base.paint_profile_summary(),
  )
}

fn main {
  println(
    "FRAME-COST bench=frame_cost_probe platform=" + @sys.sys_platform() +
      " size=" + W.to_string() + "x" + H.to_string(),
  )
  for rows in [15, 60, 240] {
    run_layout(rows, false)
    run_layout(rows, true)
    run_paint(rows, -1.0)
    run_paint(rows, 60.0)
  }
}
