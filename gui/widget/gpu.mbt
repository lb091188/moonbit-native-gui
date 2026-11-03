// GPU 档派发（L2 协议，方案 gpu-architecture.md）：宿主探测到 GPU 后端时
// 经 `gpu_set_sink` 设上，`paint_walk` 对挂了 `on_render` 的控件改派
// `RenderCtx::Gpu`；没设（后端未落地 / wgpu-native 装载失败）时全走 Cpu
// 档，现有控件一行不动。
//
// sink 是**进程级单槽**：绘窗逐窗顺序进行（一窗画完才画下一窗），L1 落地
// 后宿主在每窗 `root.paint` 前设、画完清，不会串窗。协议面（trait）住
// `@render.GpuSink`，实现住可选模块 `@guigpu`——主包不引不背。

///|
let g_gpu_sink : Ref[(&@render.GpuSink)?] = Ref(None)

///|
/// 设/清当前帧的 GPU sink（宿主用；`None` = 全 CPU 路径）。
/// L1（present 纹理合成）落地后由 `paint_frame` 在探测到后端时设。
pub fn gpu_set_sink(sink : (&@render.GpuSink)?) -> Unit {
  g_gpu_sink.val = sink
}

///|
/// 当前帧的 GPU sink（`None` = 没有 GPU 后端，控件走 `on_draw` CPU 路径）。
pub fn gpu_sink() -> (&@render.GpuSink)? {
  g_gpu_sink.val
}

///|
/// 矩形求交（GPU 档 clip 的父链累乘；任一侧空 = 不裁）。
pub fn clip_isect(rect : @base.Rect, outer : @base.Rect?) -> @base.Rect? {
  match outer {
    None => Some(rect)
    Some(o) => {
      let x1 = rect.x.max(o.x)
      let y1 = rect.y.max(o.y)
      let x2 = (rect.x + rect.w).min(o.x + o.w)
      let y2 = (rect.y + rect.h).min(o.y + o.h)
      if x2 <= x1 || y2 <= y1 {
        None
      } else {
        Some({ x: x1, y: y1, w: x2 - x1, h: y2 - y1, })
      }
    }
  }
}
