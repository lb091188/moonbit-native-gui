// L2 GPU 档派发回归（方案 gpu-architecture.md「L2 协议」）：
// - sink 未设（后端未落地/装载失败）时全走 Cpu 档——现有控件零变化；
// - 设了之后 on_render 控件拿 Gpu 档，rect/clip/opacity 随合成传；
// - on_draw-only 控件与 GPU 控件的子树照旧画 CPU 位图（混排一窗）；
// - 调用序 = 控件树序 = 合成序（重叠混排的像素正确性归 L1 present 路径）。
// 假 sink 只记调用不碰 GPU——协议面在无硬件环境下全可验。

///|
struct FakeSink {
  calls : Array[String]
}

///|
fn gpu_clip_str(c : @base.Rect?) -> String {
  match c {
    None => "none"
    Some(r) => "some(\{r.x},\{r.y},\{r.w},\{r.h})"
  }
}

///|
impl @render.GpuSink for FakeSink with fn draw_texture_rgba(
  self : FakeSink,
  _data : Bytes,
  w : Int32,
  h : Int32,
  dst : @base.Rect,
  clip : @base.Rect?,
  opacity : Double,
) -> Unit {
  self.calls.push(
    "tex \{w}x\{h} @\{dst.x},\{dst.y} \{dst.w}x\{dst.h} clip=\{gpu_clip_str(clip)} op=\{opacity}",
  )
}

///|
impl @render.GpuSink for FakeSink with fn fill_rect(
  self : FakeSink,
  rect : @base.Rect,
  color : String,
  clip : @base.Rect?,
  opacity : Double,
) -> Unit {
  self.calls.push(
    "fill \{color} @\{rect.x},\{rect.y} clip=\{gpu_clip_str(clip)} op=\{opacity}",
  )
}

///|
fn gpu_walk(log : Array[String]) -> (Widget, FakeSink) {
  let root = Widget::new()
  root.rect = { x: 0.0, y: 0.0, w: 200.0, h: 100.0, }
  let sink = FakeSink::{ calls: [], }
  gpu_set_sink(Some(sink))
  let g = Widget::new()
  g.rect = { x: 10.0, y: 10.0, w: 40.0, h: 30.0, }
  g.on_render = Some(fn(
    _self : Widget,
    ctx : @render.RenderCtx,
    r : @base.Rect,
  ) -> Unit {
    match ctx.as_gpu() {
      Some(gc) => {
        log.push("gpu")
        gc.sink.fill_rect(r, "#ff0000", gc.clip, gc.opacity)
      }
      None => log.push("cpu!")
    }
  })
  root.append_child(g)
  (root, sink)
}

///|
test "L2：sink 未设时 on_render 拿 Cpu 档（现有行为零变化）" {
  gpu_set_sink(None)
  let root = Widget::new()
  root.rect = { x: 0.0, y: 0.0, w: 200.0, h: 100.0, }
  let log : Array[String] = []
  let w = Widget::new()
  w.rect = { x: 10.0, y: 10.0, w: 40.0, h: 30.0, }
  w.on_render = Some(fn(
    _self : Widget,
    ctx : @render.RenderCtx,
    _r : @base.Rect,
  ) -> Unit {
    match ctx.as_gpu() {
      Some(_) => log.push("gpu")
      None => log.push("cpu")
    }
  })
  root.append_child(w)
  let p = @render.Painter::new(@render.Bitmap::new(200, 100))
  root.paint(p)
  assert_eq(log, ["cpu"])
  gpu_set_sink(None)
}

///|
test "L2：设了 sink 后 on_render 拿 Gpu 档，clip/opacity 随合成传" {
  let log : Array[String] = []
  let (root, sink) = gpu_walk(log)
  let p = @render.Painter::new(@render.Bitmap::new(200, 100))
  root.paint(p)
  assert_eq(log, ["gpu"])
  // dst = 控件矩形；clip = 自身矩形（clip_content 默认开，eff_clip 与父链
  // 根矩形求交后正好落回自身）；opacity = walk 累乘值（这里全 1）
  assert_eq(sink.calls, ["fill #ff0000 @10,10 clip=some(10,10,40,30) op=1"])
  gpu_set_sink(None)
}

///|
test "L2：clip_content 与 alpha 累乘进 eff_clip/opacity（父链求交）" {
  gpu_set_sink(None)
  let root = Widget::new()
  root.rect = { x: 0.0, y: 0.0, w: 200.0, h: 100.0, }
  root.clip_content = true
  root.alpha_paint = 0.5
  let mid = Widget::new()
  mid.rect = { x: 20.0, y: 10.0, w: 100.0, h: 80.0, }
  mid.clip_content = true
  root.append_child(mid)
  let leaf = Widget::new()
  leaf.rect = { x: 30.0, y: 20.0, w: 60.0, h: 40.0, }
  let log : Array[String] = []
  leaf.on_render = Some(fn(
    _self : Widget,
    ctx : @render.RenderCtx,
    r : @base.Rect,
  ) -> Unit {
    match ctx.as_gpu() {
      Some(gc) => {
        log.push("gpu")
        gc.sink.draw_texture_rgba(
          b"\x00\x00\x00\x00",
          1,
          1,
          r,
          gc.clip,
          gc.opacity,
        )
      }
      None => log.push("cpu")
    }
  })
  mid.append_child(leaf)
  let sink = FakeSink::{ calls: [], }
  gpu_set_sink(Some(sink))
  let p = @render.Painter::new(@render.Bitmap::new(200, 100))
  root.paint(p)
  assert_eq(log, ["gpu"])
  // clip = 根(0,0,200,100) ∩ mid(20,10,100,80) ∩ leaf(30,20,60,40) = leaf 自身
  assert_eq(sink.calls, ["tex 1x1 @30,20 60x40 clip=some(30,20,60,40) op=0.5"])
  gpu_set_sink(None)
}

///|
test "L2：混排一窗——调用序 = 控件树序（GPU draw 与 CPU 绘制按序叠合）" {
  gpu_set_sink(None)
  let root = Widget::new()
  root.rect = { x: 0.0, y: 0.0, w: 200.0, h: 100.0, }
  let log : Array[String] = []
  let sink = FakeSink::{ calls: [], }
  gpu_set_sink(Some(sink))
  let g1 = Widget::new()
  g1.rect = { x: 0.0, y: 0.0, w: 50.0, h: 50.0, }
  g1.on_render = Some(fn(
    _s : Widget,
    ctx : @render.RenderCtx,
    r : @base.Rect,
  ) -> Unit {
    match ctx.as_gpu() {
      Some(gc) => gc.sink.fill_rect(r, "#111111", gc.clip, gc.opacity)
      None => ()
    }
  })
  root.append_child(g1)
  // 中间一个纯 CPU 控件（只有 on_draw）：照旧画进 CPU 位图
  let c = Widget::new()
  c.rect = { x: 50.0, y: 0.0, w: 50.0, h: 50.0, }
  c.on_draw = Some(fn(
    _s : Widget,
    _p : @render.Painter,
    _r : @base.Rect,
  ) -> Unit {
    log.push("cpu-draw")
  })
  root.append_child(c)
  let g2 = Widget::new()
  g2.rect = { x: 100.0, y: 0.0, w: 50.0, h: 50.0, }
  g2.on_render = Some(fn(
    _s : Widget,
    ctx : @render.RenderCtx,
    r : @base.Rect,
  ) -> Unit {
    match ctx.as_gpu() {
      Some(gc) => gc.sink.fill_rect(r, "#222222", gc.clip, gc.opacity)
      None => ()
    }
  })
  root.append_child(g2)
  let p = @render.Painter::new(@render.Bitmap::new(200, 100))
  root.paint(p)
  // 合成序：g1(GPU) → c(CPU) → g2(GPU)——CPU 位图在 c 处落一笔，两次 GPU
  // draw 分居其前后，present 路径按这个序叠
  assert_eq(sink.calls.length(), 2)
  assert_eq(log, ["cpu-draw"])
  assert_true(sink.calls[0].has_prefix("fill #111111"), msg=sink.calls[0])
  assert_true(sink.calls[1].has_prefix("fill #222222"), msg=sink.calls[1])
  gpu_set_sink(None)
}
