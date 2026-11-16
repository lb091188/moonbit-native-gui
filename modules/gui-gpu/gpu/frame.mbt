// GPU 内容画布的 3D 帧面（方案 gpu-architecture.md「GPU 内容画布」）：
// `GpuCanvas` 的薄壳原始接口——帧生命周期（begin/end/finish 读回）、应用
// 自建 shader / 顶点缓冲 / 管线 / bind group 的资源薄壳、帧内 set/draw
// 直通调用。库只给「句柄 + 生命周期 + 结构体组装」，3D 引擎与场景图归
// 未来 gui-3d 独立模块，不在本模块。
//
// 口径：
// - 枚举数值一律取 pin 住的 vendor 头（scripts/prebuild.mbtx 下载的
//   webgpu.h，v29.0.1.1）——webgpu.h 的枚举值是 ABI 固定的显式数值，
//   C 侧转调不做翻译，两边常量同源。
// - 句柄是裸 `Int64`（wgpu 对象指针）；应用可经 `GpuCanvas::lib()` 拿
//   dlopen 库句柄 dlsym 薄壳没覆盖的 webgpu.h 符号自行扩展——原始接口
//   的逃生口，本模块只保证自己这层薄壳语义。
// - 帧的提交时机在 `GpuFrame::end`：开帧期间的 3D 指令随 end 入队，与
//   2D 原语（`draw_texture_rgba` / `fill_rect` 各自即时提交）按调用序
//   排布——调用序即合成序，与 `GpuSink` 同一口径。`finish` 对开着的帧
//   先自动收口，忘调 end 不吞帧。
// - 失败一律静默回 0/False/Err，不抛错——与 probe/canvas 的「降级不是
//   错误」同档；失败原因从 `GpuCanvas` 建不出通道（canvas_detail）带出。

///|
/// 图元拓扑（webgpu.h `WGPUPrimitiveTopology`）。
pub(all) enum GpuTopology {
  Points
  LineList
  LineStrip
  TriangleList
  TriangleStrip
}

///|
pub fn GpuTopology::value(self : GpuTopology) -> Int32 {
  match self {
    Points => 1
    LineList => 2
    LineStrip => 3
    TriangleList => 4
    TriangleStrip => 5
  }
}

///|
/// 剔除面（webgpu.h `WGPUCullMode`）。
pub(all) enum GpuCullMode {
  CullNone
  CullFront
  CullBack
}

///|
pub fn GpuCullMode::value(self : GpuCullMode) -> Int32 {
  match self {
    CullNone => 1
    CullFront => 2
    CullBack => 3
  }
}

///|
/// 正面绕向（webgpu.h `WGPUFrontFace`）。
pub(all) enum GpuFrontFace {
  CCW
  CW
}

///|
pub fn GpuFrontFace::value(self : GpuFrontFace) -> Int32 {
  match self {
    CCW => 1
    CW => 2
  }
}

///|
/// 深度比较函数（webgpu.h `WGPUCompareFunction`）。
pub(all) enum GpuCompare {
  Never
  Less
  Equal
  LessEqual
  Greater
  NotEqual
  GreaterEqual
  Always
}

///|
pub fn GpuCompare::value(self : GpuCompare) -> Int32 {
  match self {
    Never => 1
    Less => 2
    Equal => 3
    LessEqual => 4
    Greater => 5
    NotEqual => 6
    GreaterEqual => 7
    Always => 8
  }
}

///|
/// 顶点属性格式（webgpu.h `WGPUVertexFormat`，数值 0x01..0x1F 全集）。
pub(all) enum GpuVertexFormat {
  Uint8
  Uint8x2
  Uint8x4
  Sint8
  Sint8x2
  Sint8x4
  Unorm8
  Unorm8x2
  Unorm8x4
  Snorm8
  Snorm8x2
  Snorm8x4
  Uint16
  Uint16x2
  Uint16x4
  Sint16
  Sint16x2
  Sint16x4
  Unorm16
  Unorm16x2
  Unorm16x4
  Snorm16
  Snorm16x2
  Snorm16x4
  Float16
  Float16x2
  Float16x4
  Float32
  Float32x2
  Float32x3
  Float32x4
}

///|
pub fn GpuVertexFormat::value(self : GpuVertexFormat) -> Int32 {
  match self {
    Uint8 => 0x01
    Uint8x2 => 0x02
    Uint8x4 => 0x03
    Sint8 => 0x04
    Sint8x2 => 0x05
    Sint8x4 => 0x06
    Unorm8 => 0x07
    Unorm8x2 => 0x08
    Unorm8x4 => 0x09
    Snorm8 => 0x0A
    Snorm8x2 => 0x0B
    Snorm8x4 => 0x0C
    Uint16 => 0x0D
    Uint16x2 => 0x0E
    Uint16x4 => 0x0F
    Sint16 => 0x10
    Sint16x2 => 0x11
    Sint16x4 => 0x12
    Unorm16 => 0x13
    Unorm16x2 => 0x14
    Unorm16x4 => 0x15
    Snorm16 => 0x16
    Snorm16x2 => 0x17
    Snorm16x4 => 0x18
    Float16 => 0x19
    Float16x2 => 0x1A
    Float16x4 => 0x1B
    Float32 => 0x1C
    Float32x2 => 0x1D
    Float32x3 => 0x1E
    Float32x4 => 0x1F
  }
}

///|
/// 顶点步进模式（webgpu.h `WGPUVertexStepMode`）：每顶点进一份属性还是
/// 每实例进一份。
pub(all) enum GpuStepMode {
  StepVertex
  StepInstance
}

///|
pub fn GpuStepMode::value(self : GpuStepMode) -> Int32 {
  match self {
    StepVertex => 1
    StepInstance => 2
  }
}

///|
/// 索引格式（webgpu.h `WGPUIndexFormat`）。
pub(all) enum GpuIndexFormat {
  Uint16
  Uint32
}

///|
pub fn GpuIndexFormat::value(self : GpuIndexFormat) -> Int32 {
  match self {
    Uint16 => 1
    Uint32 => 2
  }
}

///|
/// 缓冲用途旗标（webgpu.h `WGPUBufferUsage` 位值），建缓冲时按需给数组。
pub(all) enum GpuBufFlag {
  MapRead
  MapWrite
  CopySrc
  CopyDst
  Index
  Vertex
  Uniform
  Storage
  Indirect
}

///|
fn GpuBufFlag::value(self : GpuBufFlag) -> Int64 {
  match self {
    MapRead => 0x0000000000000001L
    MapWrite => 0x0000000000000002L
    CopySrc => 0x0000000000000004L
    CopyDst => 0x0000000000000008L
    Index => 0x0000000000000010L
    Vertex => 0x0000000000000020L
    Uniform => 0x0000000000000040L
    Storage => 0x0000000000000080L
    Indirect => 0x0000000000000100L
  }
}

///|
fn gpu_buf_flags_or(flags : Array[GpuBufFlag]) -> Int64 {
  let mut v = 0L
  for f in flags {
    v = v | f.value()
  }
  v
}

///|
/// 顶点属性：着色器槽位号 + 格式 + 距顶点起点的字节偏移。
pub(all) struct GpuVertexAttr {
  location : Int32
  format : GpuVertexFormat
  offset : Int64
}

///|
/// 顶点缓冲布局：步长（相邻顶点的字节距）+ 步进模式 + 属性表。
pub(all) struct GpuVertexLayout {
  stride : Int64
  step_mode : GpuStepMode
  attrs : Array[GpuVertexAttr]
}

///|
/// bind group 的 buffer 条目：着色器槽位号 + 缓冲句柄 + 区间；`size` 给
/// 0 表示整段缓冲。
pub(all) struct GpuBindBuffer {
  binding : Int32
  buffer : Int64
  offset : Int64
  size : Int64
}

#borrow(wgsl, vs_entry, fs_entry)
extern "c" fn mng_gpu_canvas_pipe_begin(
  h : Int64,
  wgsl : Bytes,
  wgsl_len : Int32,
  vs_entry : Bytes,
  vs_len : Int32,
  fs_entry : Bytes,
  fs_len : Int32,
  topology : Int32,
  cull : Int32,
  front : Int32,
  blend : Int32,
  depth_write : Int32,
  depth_compare : Int32,
  depth : Int32,
) -> Int32 = "mng_gpu_canvas_pipe_begin"

///|
extern "c" fn mng_gpu_canvas_pipe_buffer(
  h : Int64,
  stride : Int64,
  step_mode : Int32,
) -> Int32 = "mng_gpu_canvas_pipe_buffer"

///|
extern "c" fn mng_gpu_canvas_pipe_attr(
  h : Int64,
  location : Int32,
  format : Int32,
  offset : Int64,
) -> Int32 = "mng_gpu_canvas_pipe_attr"

///|
extern "c" fn mng_gpu_canvas_pipe_end(h : Int64) -> Int64 = "mng_gpu_canvas_pipe_end"

#borrow(wgsl)
extern "c" fn mng_gpu_canvas_shader_new(
  h : Int64,
  wgsl : Bytes,
  len : Int32,
) -> Int64 = "mng_gpu_canvas_shader_new"

///|
extern "c" fn mng_gpu_canvas_buffer_new(
  h : Int64,
  size : Int64,
  usage : Int64,
) -> Int64 = "mng_gpu_canvas_buffer_new"

#borrow(data)
extern "c" fn mng_gpu_canvas_buffer_write(
  h : Int64,
  buffer : Int64,
  offset : Int64,
  data : Bytes,
  len : Int32,
) -> Int32 = "mng_gpu_canvas_buffer_write"

///|
extern "c" fn mng_gpu_canvas_pipeline_bgl(
  h : Int64,
  pipeline : Int64,
  group : Int32,
) -> Int64 = "mng_gpu_canvas_pipeline_bgl"

///|
extern "c" fn mng_gpu_canvas_release_buffer(h : Int64, res : Int64) -> Int32 = "mng_gpu_canvas_release_buffer"

///|
extern "c" fn mng_gpu_canvas_release_shader(h : Int64, res : Int64) -> Int32 = "mng_gpu_canvas_release_shader"

///|
extern "c" fn mng_gpu_canvas_release_pipeline(h : Int64, res : Int64) -> Int32 = "mng_gpu_canvas_release_pipeline"

///|
extern "c" fn mng_gpu_canvas_release_bind_group(h : Int64, res : Int64) -> Int32 = "mng_gpu_canvas_release_bind_group"

///|
extern "c" fn mng_gpu_canvas_bind_begin(h : Int64, layout : Int64) -> Int32 = "mng_gpu_canvas_bind_begin"

///|
extern "c" fn mng_gpu_canvas_bind_buffer(
  h : Int64,
  binding : Int32,
  buffer : Int64,
  offset : Int64,
  size : Int64,
) -> Int32 = "mng_gpu_canvas_bind_buffer"

///|
extern "c" fn mng_gpu_canvas_bind_end(h : Int64) -> Int64 = "mng_gpu_canvas_bind_end"

///|
extern "c" fn mng_gpu_canvas_frame_begin(
  h : Int64,
  has_clear : Int32,
  r : Double,
  g : Double,
  b : Double,
  a : Double,
  depth : Int32,
) -> Int32 = "mng_gpu_canvas_frame_begin"

///|
extern "c" fn mng_gpu_canvas_frame_pass(h : Int64) -> Int64 = "mng_gpu_canvas_frame_pass"

///|
extern "c" fn mng_gpu_canvas_frame_target_view(h : Int64) -> Int64 = "mng_gpu_canvas_frame_target_view"

///|
extern "c" fn mng_gpu_canvas_frame_depth_view(h : Int64) -> Int64 = "mng_gpu_canvas_frame_depth_view"

///|
extern "c" fn mng_gpu_canvas_frame_set_pipeline(
  h : Int64,
  pipeline : Int64,
) -> Int32 = "mng_gpu_canvas_frame_set_pipeline"

///|
extern "c" fn mng_gpu_canvas_frame_set_bind_group(
  h : Int64,
  index : Int32,
  group : Int64,
) -> Int32 = "mng_gpu_canvas_frame_set_bind_group"

///|
extern "c" fn mng_gpu_canvas_frame_set_vertex_buffer(
  h : Int64,
  slot : Int32,
  buffer : Int64,
) -> Int32 = "mng_gpu_canvas_frame_set_vertex_buffer"

///|
extern "c" fn mng_gpu_canvas_frame_set_index_buffer(
  h : Int64,
  buffer : Int64,
  format : Int32,
) -> Int32 = "mng_gpu_canvas_frame_set_index_buffer"

///|
extern "c" fn mng_gpu_canvas_frame_draw(
  h : Int64,
  vertices : Int32,
  instances : Int32,
) -> Int32 = "mng_gpu_canvas_frame_draw"

///|
extern "c" fn mng_gpu_canvas_frame_draw_indexed(
  h : Int64,
  indices : Int32,
  instances : Int32,
) -> Int32 = "mng_gpu_canvas_frame_draw_indexed"

///|
extern "c" fn mng_gpu_canvas_frame_end(h : Int64) -> Int32 = "mng_gpu_canvas_frame_end"

///|
/// 进程级 wgpu 对象（wgpu_core 探测后的常驻件；跨画布复用）。
extern "c" fn mng_wgpu_lib_handle() -> Int64 = "mng_wgpu_lib"

///|
extern "c" fn mng_wgpu_device_handle() -> Int64 = "mng_wgpu_device"

///|
extern "c" fn mng_wgpu_queue_handle() -> Int64 = "mng_wgpu_queue"

///|
/// 句柄 32→64（3D 帧面的 C 入口按 int64 收槽号；GpuCanvas.handle 是 Int32）。
fn canvas_h64(c : GpuCanvas) -> Int64 {
  c.handle.to_int64()
}

///|
/// dlopen 库句柄（wgpu-native 动态库的装载句柄）。薄壳没覆盖的 webgpu.h
/// 符号——frame pass 高级方法、纹理与采样器、compute 之类——应用经它
/// `dlsym` 直调，pass / 视图句柄从 `GpuFrame` 各字段取。0 = 核心未就绪。
pub fn GpuCanvas::lib(self : GpuCanvas) -> Int64 {
  let _ = self
  mng_wgpu_lib_handle()
}

///|
/// wgpu 设备句柄（资源创建薄壳内部用的同一个件）。0 = 核心未就绪。
pub fn GpuCanvas::device(self : GpuCanvas) -> Int64 {
  let _ = self
  mng_wgpu_device_handle()
}

///|
/// wgpu 队列句柄（`write_buffer` 内部用的同一个件）。0 = 核心未就绪。
pub fn GpuCanvas::queue(self : GpuCanvas) -> Int64 {
  let _ = self
  mng_wgpu_queue_handle()
}

///|
/// 建 shader module（WGSL 源码）。回句柄，Err = WGSL 建不出。
/// 管线用不了的裸 shader 可 `release_shader_module` 释放。
pub fn GpuCanvas::create_shader_module(
  self : GpuCanvas,
  wgsl : String,
) -> Result[Int64, String] {
  let b = @utf8.encode(wgsl)
  let hd = mng_gpu_canvas_shader_new(canvas_h64(self), b, b.length())
  if hd == 0L {
    Err("shader module 建不出（WGSL 编译失败或后端不支持）")
  } else {
    Ok(hd)
  }
}

///|
/// 建缓冲（size 字节；usage 旗标数组按位或）。回句柄，Err = 建不出。
pub fn GpuCanvas::create_buffer(
  self : GpuCanvas,
  size : Int64,
  usage : Array[GpuBufFlag],
) -> Result[Int64, String] {
  let hd = mng_gpu_canvas_buffer_new(canvas_h64(self), size, gpu_buf_flags_or(usage))
  if hd == 0L {
    Err("缓冲建不出（\{size} 字节）")
  } else {
    Ok(hd)
  }
}

///|
/// 写缓冲（队列立即上传；`offset` 与字节数须 4 字节对齐——WebGPU 硬规，
/// 顶点数据可用步长凑齐）。False = 校验不过或缓冲句柄无效。
pub fn GpuCanvas::write_buffer(
  self : GpuCanvas,
  buffer : Int64,
  data : Bytes,
  offset~ : Int64 = 0L,
) -> Bool {
  if data.length() % 4 != 0 {
    return false
  }
  mng_gpu_canvas_buffer_write(canvas_h64(self), buffer, offset, data, data.length()) ==
  1
}

///|
/// 取管线的 bind group layout（组号 `group`，一般 0）。句柄可喂
/// `create_bind_group`，也可 `release_bind_group` 释放。Err = 拿不到。
pub fn GpuCanvas::pipeline_bind_group_layout(
  self : GpuCanvas,
  pipeline : Int64,
  group~ : Int32 = 0,
) -> Result[Int64, String] {
  let hd = mng_gpu_canvas_pipeline_bgl(canvas_h64(self), pipeline, group)
  if hd == 0L {
    Err("bind group layout 拿不到（组号越界或管线无效）")
  } else {
    Ok(hd)
  }
}

///|
/// 建 bind group（buffer 条目数组；`size` 给 0 = 整段）。Err = 建不出。
pub fn GpuCanvas::create_bind_group(
  self : GpuCanvas,
  layout : Int64,
  entries : Array[GpuBindBuffer],
) -> Result[Int64, String] {
  if mng_gpu_canvas_bind_begin(canvas_h64(self), layout) == 0 {
    return Err("bind group builder 开不出（layout 无效或核心未就绪）")
  }
  for e in entries {
    let _ = mng_gpu_canvas_bind_buffer(
      canvas_h64(self),
      e.binding,
      e.buffer,
      e.offset,
      e.size,
    )
  }
  let hd = mng_gpu_canvas_bind_end(canvas_h64(self))
  if hd == 0L {
    Err("bind group 建不出（条目空或与 layout 不匹配）")
  } else {
    Ok(hd)
  }
}

///|
/// 用自建 shader 组渲染管线（薄壳原始面的核心口）。缺省即常用档：
/// 三角表、不剔除、CCW 正面、SrcAlpha 混合、无深度。顶点入口固定 `vs`、
/// 片元入口固定 `fs`（对不上入口名的 WGSL 按这两个名字写）。
/// - `depth=true` 时管线挂 Depth24Plus 深度档，须与 `begin_frame(depth=true)`
///   的帧配套；不带深度档的管线（如 2D 风格）也能在深度帧里画（无深度测试）。
/// - Err = WGSL 或布局验证失败（静默错误回调吃诊断，逐项自查属性表）。
pub fn GpuCanvas::create_render_pipeline(
  self : GpuCanvas,
  wgsl : String,
  vertex_buffers : Array[GpuVertexLayout],
  topology~ : GpuTopology = GpuTopology::TriangleList,
  cull~ : GpuCullMode = GpuCullMode::CullNone,
  front_face~ : GpuFrontFace = GpuFrontFace::CCW,
  blend~ : Bool = true,
  depth~ : Bool = false,
  depth_write~ : Bool = true,
  depth_compare~ : GpuCompare = GpuCompare::Less,
) -> Result[Int64, String] {
  let wg = @utf8.encode(wgsl)
  let vs = @utf8.encode("vs")
  let fs = @utf8.encode("fs")
  if mng_gpu_canvas_pipe_begin(
      canvas_h64(self),
      wg,
      wg.length(),
      vs,
      vs.length(),
      fs,
      fs.length(),
      topology.value(),
      cull.value(),
      front_face.value(),
      if blend { 1 } else { 0 },
      if depth_write { 1 } else { 0 },
      depth_compare.value(),
      if depth { 1 } else { 0 },
    ) == 0 {
    return Err("管线 builder 开不出（WGSL 编译失败或核心未就绪）")
  }
  for vbl in vertex_buffers {
    let idx = mng_gpu_canvas_pipe_buffer(
      canvas_h64(self),
      vbl.stride,
      vbl.step_mode.value(),
    )
    if idx < 0 {
      return Err("顶点缓冲布局超上限（8 个）")
    }
    for att in vbl.attrs {
      if mng_gpu_canvas_pipe_attr(
          canvas_h64(self),
          att.location,
          att.format.value(),
          att.offset,
        ) < 0 {
        return Err("顶点属性超上限（每布局 16 个）")
      }
    }
  }
  let hd = mng_gpu_canvas_pipe_end(canvas_h64(self))
  if hd == 0L {
    Err("管线建不出（布局 / 入口 / 验证错误）")
  } else {
    Ok(hd)
  }
}

///|
/// 释放缓冲句柄。
pub fn GpuCanvas::release_buffer(self : GpuCanvas, res : Int64) -> Bool {
  mng_gpu_canvas_release_buffer(canvas_h64(self), res) == 1
}

///|
/// 释放 shader module 句柄。
pub fn GpuCanvas::release_shader_module(self : GpuCanvas, res : Int64) -> Bool {
  mng_gpu_canvas_release_shader(canvas_h64(self), res) == 1
}

///|
/// 释放管线句柄。
pub fn GpuCanvas::release_pipeline(self : GpuCanvas, res : Int64) -> Bool {
  mng_gpu_canvas_release_pipeline(canvas_h64(self), res) == 1
}

///|
/// 释放 bind group 句柄（layout 同走此口）。
pub fn GpuCanvas::release_bind_group(self : GpuCanvas, res : Int64) -> Bool {
  mng_gpu_canvas_release_bind_group(canvas_h64(self), res) == 1
}

///|
/// f32 位模式（C 侧 memcpy 读 float；MoonBit 侧无 to_bits，走此口）。
extern "c" fn mng_gpu_f32_bits(v : Double) -> Int32 = "mng_gpu_f32_bits"

///|
/// 把一个 f32 值按小端写进字节数组第 `i` 字节起 4 格（顶点 / 均匀缓冲
/// 数据打包的配套助手；WGPUBuffer 线路统一小端）。
pub fn gpu_pack_f32(out : FixedArray[Byte], i : Int32, v : Double) -> Unit {
  let bits = mng_gpu_f32_bits(v)
  out[i] = (bits & 0xFF).to_byte()
  out[i + 1] = ((bits >> 8) & 0xFF).to_byte()
  out[i + 2] = ((bits >> 16) & 0xFF).to_byte()
  out[i + 3] = ((bits >> 24) & 0xFF).to_byte()
}

///|
/// 一帧 3D：`GpuCanvas::begin_frame` 开出，帧内经 set/draw 薄壳提交内容，
/// `end` 收口提交，`finish`（画布既有方法）读回 BGRA 字节。pass / 视图
/// 句柄 `pub(all)` 暴露——应用经 `GpuCanvas::lib()` dlsym 直调薄壳没覆盖
/// 的 webgpu.h 方法时用；句柄只在 end 前有效。
///
/// 深度帧的深度比较恒 `Clear` 到 1.0、`storeOp=Discard`（跨帧不留深度）；
/// 管线侧的深度行为（比较函数、是否写深度）由 `create_render_pipeline`
/// 的 `depth*` 参数决定。
pub(all) struct GpuFrame {
  canvas : Int64
  pass : Int64
  target_view : Int64
  depth_view : Int64
}

///|
/// 开帧：`clear` 给 `#rrggbb` / `#rrggbbaa` 则 color loadOp=Clear，空串
/// 保留既有像素（Load）；`depth=true` 挂 Depth24Plus 深度附件。Err =
/// 已有开着的帧或画布失效（失败原因见建画布通道）。
pub fn GpuCanvas::begin_frame(
  self : GpuCanvas,
  clear~ : String = "",
  depth~ : Bool = false,
) -> Result[GpuFrame, String] {
  let (hc, r, g, b, a) = if clear.length() == 0 {
    (0, 0.0, 0.0, 0.0, 0.0)
  } else {
    let (r, g, b, a) = canvas_color(clear)
    (1, r, g, b, a)
  }
  if mng_gpu_canvas_frame_begin(
      canvas_h64(self),
      hc,
      r,
      g,
      b,
      a,
      if depth { 1 } else { 0 },
    ) == 0 {
    Err("帧开不出（已有开着的帧 / 画布失效 / 深度附件建不出）")
  } else {
    Ok({
      canvas: canvas_h64(self),
      pass: mng_gpu_canvas_frame_pass(canvas_h64(self)),
      target_view: mng_gpu_canvas_frame_target_view(canvas_h64(self)),
      depth_view: mng_gpu_canvas_frame_depth_view(canvas_h64(self)),
    })
  }
}

///|
/// 帧内：换管线（`create_render_pipeline` 的句柄）。False = 未开帧/句柄无效。
pub fn GpuFrame::set_pipeline(self : GpuFrame, pipeline : Int64) -> Bool {
  mng_gpu_canvas_frame_set_pipeline(self.canvas, pipeline) == 1
}

///|
/// 帧内：挂 bind group（`create_bind_group` 的句柄）。False = 未开帧/句柄无效。
pub fn GpuFrame::set_bind_group(
  self : GpuFrame,
  group : Int64,
  index~ : Int32 = 0,
) -> Bool {
  mng_gpu_canvas_frame_set_bind_group(self.canvas, index, group) == 1
}

///|
/// 帧内：挂顶点缓冲（整段，offset 0）。False = 未开帧/句柄无效。
pub fn GpuFrame::set_vertex_buffer(
  self : GpuFrame,
  buffer : Int64,
  slot~ : Int32 = 0,
) -> Bool {
  mng_gpu_canvas_frame_set_vertex_buffer(self.canvas, slot, buffer) == 1
}

///|
/// 帧内：挂索引缓冲（整段，offset 0）。False = 未开帧/句柄无效。
pub fn GpuFrame::set_index_buffer(
  self : GpuFrame,
  buffer : Int64,
  format : GpuIndexFormat,
) -> Bool {
  mng_gpu_canvas_frame_set_index_buffer(
    self.canvas,
    buffer,
    format.value(),
  ) == 1
}

///|
/// 帧内：按顶点数画（非索引）。False = 未开帧/参数无效。
pub fn GpuFrame::draw(
  self : GpuFrame,
  vertices : Int32,
  instances~ : Int32 = 1,
) -> Bool {
  mng_gpu_canvas_frame_draw(self.canvas, vertices, instances) == 1
}

///|
/// 帧内：按索引数画（须先 `set_index_buffer`）。False = 未开帧/参数无效。
pub fn GpuFrame::draw_indexed(
  self : GpuFrame,
  indices : Int32,
  instances~ : Int32 = 1,
) -> Bool {
  mng_gpu_canvas_frame_draw_indexed(self.canvas, indices, instances) == 1
}

///|
/// 收帧：End pass + finish encoder + 提交队列。之后的 `finish()` 读回
/// 这一帧。重复 end / 未开帧静默无害。
pub fn GpuFrame::end(self : GpuFrame) -> Unit {
  let _ = mng_gpu_canvas_frame_end(self.canvas)
}
