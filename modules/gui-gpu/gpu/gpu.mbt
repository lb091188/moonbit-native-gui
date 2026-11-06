// GPU 地基（wgpu-native 运行期装载）。
//
// 本包回答两件事：**这台机器上现在能不能用 wgpu-native**（`probe()`：按
// vendor/ 下的归档（模块根 prebuild.py 按平台拉取并校验 sha256）dlopen，
// 取到 `wgpuCreateInstance` 才算可用），以及**整条链路上不上得去屏**
// （`run_triangle()`：X11 wgpu 三角形探针，GPU 线第一步真机验收面）。
// 装载走运行期、不占链接面：没装 GPU 扩展的应用照常编译运行，只是
// `probe().loaded` 为假、界面走纯光栅/软件合成。
//
// 后续批次（L1/L2）在这里长 `GpuSink` 实现与 present 合成；本批只有地基、
// 探针契约与三角形探针。

///|
#borrow(out)
extern "c" fn mng_gpu_probe(out : Bytes, cap : Int) -> Int = "mng_gpu_probe"

///|
/// 探测结果：`loaded` 可用性 + `detail`（装载路径或失败原因，原样可打印）。
pub(all) struct GpuProbe {
  loaded : Bool
  detail : String
}

///|
/// 探测一次（进程内幂等：库装过一次就直接答 loaded）。
/// 候选路径依次是 `MNG_WGPU_LIB` 环境变量、`vendor/lib/…`、`vendor/…`、
/// 系统搜索路径上的库名；都没成就报 not-found，不抛错。
pub fn probe() -> GpuProbe {
  let cap = 256
  // 同一份 Bytes 既喂给 C 又用来读回：from_array 是拷贝，先后各造一次就读不到写入了
  let bytes = Bytes::from_array(FixedArray::make(cap, b'\x00'))
  let ok = mng_gpu_probe(bytes, cap)
  let mut n = 0
  while n < cap && bytes[n] != b'\x00' {
    n += 1
  }
  let detail = if n == 0 {
    ""
  } else {
    @utf8.decode_lossy(bytes[:n])
  }
  { loaded: ok == 1, detail }
}

///|
/// 跑一次 X11 wgpu 三角形探针（GPU 线第一步，真机肉眼验收面）：自开一个
/// Xlib 窗，wgpu 全链路（instance→surface→adapter→device→pipeline）上屏
/// 一个三色三角形，关窗或按 Esc 退出。`frames` 是帧数上限（≤0 取 600）。
/// 不可用（没装 GPU 扩展/没有 X 显示/驱动起不来）如实回 Err，不抛错——
/// 与 `probe()` 同一套「降级不是错误」口径。wgpu 库与 libX11 都 dlopen，
/// 本模块不占链接面；vendor 归档或 Xlib 头缺失的平台是编译期桩，同样回 Err。
#borrow(out)
extern "c" fn mng_gpu_triangle(out : Bytes, cap : Int, frames : Int) -> Int = "mng_gpu_triangle"

///|
pub fn run_triangle(frames~ : Int = 600) -> Result[Unit, String] {
  let cap = 320
  let bytes = Bytes::from_array(FixedArray::make(cap, b'\x00'))
  let rc = mng_gpu_triangle(bytes, cap, frames)
  if rc == 0 {
    Ok(())
  } else {
    let mut n = 0
    while n < cap && bytes[n] != b'\x00' {
      n += 1
    }
    let detail = if n == 0 {
      "未知原因（rc=\{rc}）"
    } else {
      @utf8.decode_lossy(bytes[:n])
    }
    Err(detail)
  }
}

///|
/// GPU 画布（@render.GpuSink 的 gui-gpu 实现；GPU 线首消费者，方案
/// gpu-architecture.md「首消费者」）。
///
/// 形态：一块离屏 wgpu 渲染目标（BGRA8Unorm，与 MoonBit 位图 ARGB32 同
/// 字节序）。控件经 `RenderCtx::Gpu` 拿到的 sink 就是它；宿主设
/// `@widget.gpu_set_sink(Some(canvas))` 后，挂 `on_render` 的控件走 GPU 档
/// 提交绘制，每帧调 `finish` 读回 RGBA 字节、走既有 CPU 绘制贴上屏。
/// **compositor 落地前的过渡形态**（终局是 GPU 控件各渲到自己的 render
/// target、由 present 路径按控件树叠合成），协议面不变、消费者代码不改。
///
/// 坐标口径：**画布坐标**（0..w/0..h，sink 渲染到自己的离屏目标，窗→画布
/// 换算归宿主）；clip/opacity 与 trait 一致。不可用（没装 GPU 扩展/驱动
/// 起不来）时 `new` 回 Err——调用方照走 CPU 路径，「降级不是错误」。
pub(all) struct GpuCanvas {
  handle : Int
  w : Int
  h : Int
}

///|
extern "c" fn mng_gpu_canvas_new(w : Int, h : Int) -> Int = "mng_gpu_canvas_new"

///|
#borrow(out)
extern "c" fn mng_gpu_canvas_detail(out : Bytes, cap : Int) -> Unit = "mng_gpu_canvas_detail"

///|
/// 最近一次 `GpuCanvas::new` 失败的原因（C 侧逐档记录：核心未就绪/缺符号/
/// 尺寸要求逐个对象建不出的口；成功路径不动它）。
fn canvas_detail() -> String {
  let cap = 256
  let bytes = Bytes::from_array(FixedArray::make(cap, b'\x00'))
  mng_gpu_canvas_detail(bytes, cap)
  let mut n = 0
  while n < cap && bytes[n] != b'\x00' {
    n += 1
  }
  if n == 0 {
    ""
  } else {
    @utf8.decode_lossy(bytes[:n])
  }
}

///|
extern "c" fn mng_gpu_canvas_resize(h : Int, w : Int, hh : Int) -> Int = "mng_gpu_canvas_resize"

///|
#borrow(data)
extern "c" fn mng_gpu_canvas_draw_texture(
  h : Int,
  data : Bytes,
  dw : Int,
  dh : Int,
  dx : Double,
  dy : Double,
  dw2 : Double,
  dh2 : Double,
  has_clip : Int,
  cx : Double,
  cy : Double,
  cw : Double,
  ch : Double,
  opacity : Double,
) -> Int = "mng_gpu_canvas_draw_texture"

///|
extern "c" fn mng_gpu_canvas_fill(
  h : Int,
  x : Double,
  y : Double,
  w : Double,
  hh : Double,
  r : Double,
  g : Double,
  b : Double,
  a : Double,
  has_clip : Int,
  cx : Double,
  cy : Double,
  cw : Double,
  ch : Double,
  opacity : Double,
) -> Int = "mng_gpu_canvas_fill"

///|
#borrow(out)
extern "c" fn mng_gpu_canvas_finish(h : Int, out : Bytes, cap : Int) -> Int = "mng_gpu_canvas_finish"

///|
extern "c" fn mng_gpu_canvas_free(h : Int) -> Unit = "mng_gpu_canvas_free"

///|
/// 建一块 w×h 的 GPU 画布（上限 8192）。没装 GPU 扩展/驱动起不来/尺寸
/// 非法回 Err，调用方照走 CPU 路径。
pub fn GpuCanvas::new(w : Int, h : Int) -> Result[GpuCanvas, String] {
  // 不拿 probe() 当前置门槛：probe 与 core 是两套装载器，候选表一旦分叉，
  // 「core 能建设备、probe 却报 not-found」会把可用画布误判成降级。画布只
  // 信自己实际用的那条链——mng_gpu_canvas_new 内 mng_wgpu_ready() 判定，
  // 失败原因由 C 侧写进 canvas_detail()。
  let hd = mng_gpu_canvas_new(w, h)
  if hd <= 0 {
    Err("GPU 画布建不出（\{w}x\{h}）：\{canvas_detail()}")
  } else {
    Ok({ handle: hd, w, h })
  }
}

///|
/// 画布尺寸（建时给定；`resize` 后跟着变）。
pub fn GpuCanvas::size(self : GpuCanvas) -> (Int, Int) {
  (self.w, self.h)
}

///|
/// 改画布尺寸（重建离屏目标与读回缓冲）。失败回 Err（调用方应弃用这块画布）。
pub fn GpuCanvas::resize(self : GpuCanvas, w : Int, h : Int) -> Result[Unit, String] {
  if mng_gpu_canvas_resize(self.handle, w, h) == 1 {
    Ok(())
  } else {
    Err("GPU 画布 resize 失败（\{w}x\{h}）")
  }
}

///|
/// 读回这一帧的 RGBA 字节（w*h*4，行优先，与 `@render.Bitmap::to_rgba_bytes`
/// 同口径；BGRA8Unorm 目标按字节序即 B,G,R,A）。设备丢/map 超时给 None。
pub fn GpuCanvas::finish(self : GpuCanvas) -> Bytes? {
  let len = self.w * self.h * 4
  let buf = FixedArray::make(len, b'\x00')
  let out = Bytes::from_array(buf)
  if mng_gpu_canvas_finish(self.handle, out, len) == 1 {
    Some(out)
  } else {
    None
  }
}

///|
/// 便捷接线：把这块画布设成进程级 GPU sink（内部就是
/// `@widget.gpu_set_sink(Some(self))`）。之后挂 `on_render` 的控件即走
/// GPU 档（`RenderCtx::Gpu`）；卸载传 None 回 CPU 档。
pub fn GpuCanvas::install(self : GpuCanvas) -> Unit {
  @widget.gpu_set_sink(Some(self))
}

///|
/// 释放画布（wgpu 对象归进程所有，不释放也可——进程退出时由 OS/驱动收拾；
/// 长时间反复建/弃的场景显式调）。
pub fn GpuCanvas::free(self : GpuCanvas) -> Unit {
  mng_gpu_canvas_free(self.handle)
}

///|
/// clip（None = 不裁）→ C 侧的 (flag, x, y, w, h)。
fn canvas_clip(c : @base.Rect?) -> (Int, Double, Double, Double, Double) {
  match c {
    None => (0, 0.0, 0.0, 0.0, 0.0)
    Some(r) => (1, r.x, r.y, r.w, r.h)
  }
}

///|
/// 单个 hex 数位（0-9/a-f/A-F → 0..15；非法 -1）。
fn canvas_hex_digit(c : Char) -> Int {
  if c >= '0' && c <= '9' {
    c.to_int() - '0'.to_int()
  } else if c >= 'a' && c <= 'f' {
    c.to_int() - 'a'.to_int() + 10
  } else if c >= 'A' && c <= 'F' {
    c.to_int() - 'A'.to_int() + 10
  } else {
    -1
  }
}

///|
/// 两位 hex（下标 i 起）→ 0..255；非法 -1。
fn canvas_hex_pair(s : String, i : Int) -> Int {
  let hi = match s.get_char(i) {
    Some(c) => canvas_hex_digit(c)
    None => -1
  }
  let lo = match s.get_char(i + 1) {
    Some(c) => canvas_hex_digit(c)
    None => -1
  }
  if hi < 0 || lo < 0 {
    -1
  } else {
    hi * 16 + lo
  }
}

///|
/// `#rrggbb` / `#rrggbbaa` → (r,g,b,a) 0..1（解析不了按不透明白，与 Painter
/// 的 fill 色同一式容忍）。
fn canvas_color(hex : String) -> (Double, Double, Double, Double) {
  let s = if hex.has_prefix("#") {
    hex[1:].to_owned()
  } else {
    hex
  }
  let n = s.length()
  if n != 6 && n != 8 {
    return (1.0, 1.0, 1.0, 1.0)
  }
  let r = canvas_hex_pair(s, 0)
  let g = canvas_hex_pair(s, 2)
  let b = canvas_hex_pair(s, 4)
  if r < 0 || g < 0 || b < 0 {
    return (1.0, 1.0, 1.0, 1.0)
  }
  let a = if n == 8 {
    let v = canvas_hex_pair(s, 6)
    if v < 0 {
      255
    } else {
      v
    }
  } else {
    255
  }
  (
    r.to_double() / 255.0,
    g.to_double() / 255.0,
    b.to_double() / 255.0,
    a.to_double() / 255.0,
  )
}

///|
impl @render.GpuSink for GpuCanvas with fn draw_texture_rgba(
    self : GpuCanvas,
    data : Bytes,
    w : Int,
    h : Int,
    dst : @base.Rect,
    clip : @base.Rect?,
    opacity : Double,
  ) -> Unit {
  let (hc, cx, cy, cw, ch) = canvas_clip(clip)
  let _ = mng_gpu_canvas_draw_texture(
    self.handle,
    data,
    w,
    h,
    dst.x,
    dst.y,
    dst.w,
    dst.h,
    hc,
    cx,
    cy,
    cw,
    ch,
    opacity,
  )
}

///|
impl @render.GpuSink for GpuCanvas with fn fill_rect(
    self : GpuCanvas,
    rect : @base.Rect,
    color : String,
    clip : @base.Rect?,
    opacity : Double,
  ) -> Unit {
  let (r, g, b, a) = canvas_color(color)
  let (hc, cx, cy, cw, ch) = canvas_clip(clip)
  let _ = mng_gpu_canvas_fill(
    self.handle,
    rect.x,
    rect.y,
    rect.w,
    rect.h,
    r,
    g,
    b,
    a,
    hc,
    cx,
    cy,
    cw,
    ch,
    opacity,
  )
}
