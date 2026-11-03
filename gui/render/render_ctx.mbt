// W38 渲染上下文：CPU 路径的现在形态 + GPU 路径的扩展口子。
// on_draw 保持 Painter 签名向后兼容；要接 3D/GPU 的控件走 on_render(ctx)。
// 将来 WebGPU 后端落地时只扩 enum，不改 Widget 协议。

///|
/// GPU 绘制出口（L2 协议的最小面，方案 gpu-architecture.md「L2 协议」）：
/// 控件经 `RenderCtx::Gpu` 拿到它提交绘制。
///
/// **主包只定协议不养猪**：`GpuSink` 是 trait——实现住在可选模块
/// `@guigpu`（wgpu-native 装载失败即没有实现，`gpu_sink()` 为 None，控件
/// 照走 `on_draw` 的 CPU 路径）。主包的依赖图里因此没有 GPU 任何东西。
///
/// 坐标一律**窗口坐标**（与 Painter 的绝对矩形同口径）；`clip` 为 None 时
/// 不裁；`opacity` 0..1 是 walk 现算的累乘值（祖先 × 自身），控件不用
/// 自己累乘。方法在控件树序上被调用——**调用序即合成序**（GPU draw 与
/// CPU 绘制按树序叠合；重叠混排的像素正确性归 L1 present 路径，首批
/// 消费者视频 quad 是叶子件、不与后续兄弟重叠）。
pub(open) trait GpuSink {
  /// 一帧 CPU RGBA（`w * h * 4`，行优先）上传成纹理并按 `dst` 贴出：
  /// 视频 quad 的最小面。GPU 线的「视频直纹理」落地后，帧源从 CPU 拷贝
  /// 升级成 hw frame 直导入——**只换这一处的帧源，合成路径零改动**。
  draw_texture_rgba(
    Self,
    data : Bytes,
    w : Int,
    h : Int,
    dst : @base.Rect,
    clip : @base.Rect?,
    opacity : Double,
  ) -> Unit
  /// 纯色矩形（简单图形档；`color` 为 `#rrggbb` / `#rrggbbaa` 口径，
  /// 与 Painter 的 fill 色同一解析）。
  fill_rect(
    Self,
    rect : @base.Rect,
    color : String,
    clip : @base.Rect?,
    opacity : Double,
  ) -> Unit
}

///|
/// GPU 档绘制上下文：sink + **随合成传**的裁剪与不透明度（walk 现算，
/// 控件直接拿来做 draw 的 dst/clip/opacity，不自己累乘）。
pub(all) struct GpuCtx {
  sink : &GpuSink
  clip : @base.Rect?
  opacity : Double
}

///|
/// 绘制上下文（渲染路径的分派点）：
/// - `Cpu(painter)`：软件光栅 / Cairo 光栅，控件走 Painter API；
/// - `Gpu(gpu)`：GPU 合成 / 3D 场景，控件经 `GpuCtx.sink` 提交纹理与绘制。
pub(all) enum RenderCtx {
  Cpu(Painter)
  Gpu(GpuCtx)
}

///|
/// 取上下文里的 CPU Painter（GPU 档返回 None）。
pub fn RenderCtx::as_painter(self : RenderCtx) -> Painter? {
  match self {
    Cpu(p) => Some(p)
    Gpu(_) => None
  }
}

///|
/// 取上下文里的 GPU 档（CPU 档返回 None）。
pub fn RenderCtx::as_gpu(self : RenderCtx) -> GpuCtx? {
  match self {
    Cpu(_) => None
    Gpu(g) => Some(g)
  }
}

///|
/// 是否走 GPU 路径（探测函数；后端未落地/装载失败恒 false——见
/// `@widget.gpu_sink()`，宿主探测到 GPU 后端才设）。
pub fn RenderCtx::is_gpu(self : RenderCtx) -> Bool {
  match self {
    Cpu(_) => false
    Gpu(_) => true
  }
}

///|
/// 当前窗是否可用 GPU 后端（探测函数，WebGPU 模块落地前恒 false）。
pub fn gpu_backend_available() -> Bool {
  false
}
