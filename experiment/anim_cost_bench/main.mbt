// 动画前置判据探针（CPU 光栅栈下 transition 值不值得做）：
// 量四件事——① 全窗重绘一帧多少钱；② 只有小面积变化时多少钱（有没有
// 「脏矩形」这类的天然便宜可占）；③ 小面积变化单独算多少钱；
// ④ 带旋转的小控件一帧多少钱（transform 档）。
// 跑法：moon run experiment/anim_cost_bench

///|
fn ink(bm : @render.Bitmap) -> Int32 {
  let mut n = 0
  let mut y = 0
  while y < bm.height {
    let mut x = 0
    while x < bm.width {
      if bm.pixel(x, y).a > 0 {
        n += 1
      }
      x += 4
    }
    y += 4
  }
  n
}

// 一屏典型内容：30 行「按钮 + 输入框 + 文本」（native-app/showcase 的密度量级）

///|
fn build_page() -> @widget.Node {
  let rows : Array[@widget.Node] = []
  for _ in 0..<30 {
    let _ = rows.push(
      @ui.row(
        [
          @ui.button("保存", variant=@ui.Solid),
          @ui.input(@base.Store::new("输入框内容")),
          @ui.text("一行说明文字，用来占住交叉轴", class=[
            @style.text_secondary,
          ]),
        ],
        column_gap=8.0,
      ),
    )
  }
  @ui.col(rows, row_gap=6.0, padding=12.0, width=1400.0, height=900.0)
}

///|
fn main {
  let w = 1400
  let h = 900
  let bm = @render.Bitmap::new(w, h)
  let root = @widget.Widget::new()
  root.set_size(w.to_double(), h.to_double())
  root.set_column()
  let _ = (build_page().mount)(root)
  root.relayout(w.to_double(), h.to_double())
  let r0 = root.children()[0].rect
  let page = root.children()[0]
  let r1 = page.children()[0].rect
  println("DIAG rows=" + page.children().length().to_string())
  println(
    "DIAG r0w=" +
    r0.w.to_string() +
    " r0h=" +
    r0.h.to_string() +
    " r1w=" +
    r1.w.to_string() +
    " r1h=" +
    r1.h.to_string(),
  )
  let p = @render.Painter::new(bm)
  // ① 全窗重绘
  let t0 = @win.now_ms()
  let n = 20
  let mut it = 0
  while it < n {
    page.paint(p)
    it += 1
  }
  let full = @win.now_ms() - t0
  // ② 小面积变化：只画一颗按钮大小的圆角矩形（悬停/按压一类的局部变化下限）
  let t1 = @win.now_ms()
  it = 0
  while it < n {
    p.set_fill_color("#2D68C4")
    p.fill_round_rect(20.0, 20.0, 90.0, 32.0, 4.0)
    it += 1
  }
  let part = @win.now_ms() - t1
  // ③ 全树文本布局测量一次要多少钱（relayout 成本：动画每帧不变的话可摊掉）
  let t2 = @win.now_ms()
  it = 0
  while it < n {
    root.relayout(w.to_double(), h.to_double())
    it += 1
  }
  let layout = @win.now_ms() - t2
  // ④ 旋转小控件：90×32 控件挂 rotate 14°，走控件绘制链与光栅矩阵 CTM（对照 ② 同尺寸裸图元）
  let rw = @widget.Widget::new()
  rw.set_size(90.0, 32.0)
  rw.on_draw = Some(
    fn(_w : @widget.Widget, p : @render.Painter, r : @base.Rect) -> Unit {
      p.set_fill_color("#2D68C4")
      p.fill_round_rect(0.0, 0.0, r.w, r.h, 4.0)
    },
  )
  rw.tr_rot = 14.0
  root.append_child(rw)
  root.relayout(w.to_double(), h.to_double())
  let t3 = @win.now_ms()
  it = 0
  while it < n {
    rw.paint(p)
    it += 1
  }
  let rot = @win.now_ms() - t3
  println(
    "ANIM-COST \{w}x\{h} frames=\{n} full=\{full}ms(\{full / n.to_int64()}ms/帧) part_90x32=\{part}ms(\{part / n.to_int64()}ms/帧) rot_90x32=\{rot}ms(\{rot / n.to_int64()}ms/帧) relayout=\{layout}ms(\{layout / n.to_int64()}ms/帧) ink=\{ink(bm)}",
  )
  // ⑤ 滚动档：万行虚拟列表滚动一帧（视口 800×600、行高 24；无宿主档
  //    scroll_by 走步进，等价「滚轮一格」的呈现成本）
  let items : Array[Int32] = []
  let mut k = 0
  while k < 10000 {
    items.push(k)
    k += 1
  }
  let store = @base.Store::new(items)
  let vroot = @widget.Widget::new()
  vroot.set_size(900.0, 640.0)
  vroot.set_column()
  let list_node = @ui.virt_list(
    store,
    600.0,
    24.0,
    fn(i : Int32, _v : Int32) -> @widget.Node {
      let row = @widget.Widget::new()
      row.set_size(800.0, 24.0)
      row.on_draw = Some(fn(
        _w : @widget.Widget,
        p : @render.Painter,
        r : @base.Rect,
      ) -> Unit {
        p.set_fill_color(if i % 2 == 0 { "#F5F5F5" } else { "#FFFFFF" })
        p.fill_rect(0.0, 0.0, r.w, r.h)
      })
      @widget.node_of(row)
    },
    width=800.0,
  )
  let list = list_node.mount_into(vroot)
  vroot.relayout(900.0, 640.0)
  list.paint(p)
  let t4 = @win.now_ms()
  let n2 = 200
  it = 0
  while it < n2 {
    let _ = vroot.dispatch_scroll({
      x: 400.0,
      y: 300.0,
      dx: 0.0,
      dy: -1.0,
      mods: 0,
    })
    vroot.relayout(900.0, 640.0)
    list.paint(p)
    it += 1
  }
  let scroll = @win.now_ms() - t4
  println(
    "ANIM-SCROLL rows=10000 view=800x600 frames=\{n2} scroll=\{scroll}ms(\{scroll.to_double() / n2.to_double()}ms/帧)",
  )
  p.end()
}
