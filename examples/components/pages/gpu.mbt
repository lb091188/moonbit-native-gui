// GPU 画布页（第 16 页）：L2 协议首消费者验收面。容器挂 `on_render` 走
// `RenderCtx::Gpu` 派发，把 `fill_rect` / `draw_texture_rgba` 两条原语画进
// `@guigpu.GpuCanvas`（离屏 BGRA 目标）；GPU 派发的控件不往 CPU 位图涂写，
// 所以同帧由子控件 `finish()` 读回字节直拷上屏（读回 BGRA 与位图 ARGB32
// 内存序在 a=255 时零转换）。「检查读回」给非零率与四角采样，全零是渲染
// 或读回链异常的判据；没装 GPU 扩展整段降级 notice，探测读数如实显示。

///|
/// 32×32 不透明图案字节（draw_texture_rgba 语义：R,G,B,A，全 a=255）：
/// 红蓝棋盘 + 横向渐变，边缘与中心都可当采样点。
fn gpu_pattern(size : Int32) -> Bytes {
  let out = FixedArray::make(size * size * 4, b'\xFF')
  for y in 0..<size {
    for x in 0..<size {
      let i = (y * size + x) * 4
      let v = x * 255 / (size - 1)
      if (x / 4 + y / 4) % 2 == 0 {
        out[i] = v.to_byte()
        out[i + 1] = 0
        out[i + 2] = (255 - v).to_byte()
      } else {
        out[i] = (255 - v).to_byte()
        out[i + 1] = (v / 3).to_byte()
        out[i + 2] = v.to_byte()
      }
    }
  }
  Bytes::from_array(out)
}

///|
/// 同一图案的位图形态（CPU 回退参照）：RGBA → 位图内存序 B,G,R,A 换槽。
fn gpu_pattern_bitmap(size : Int32) -> @render.Bitmap {
  let bm = @render.Bitmap::new(size, size)
  let px = gpu_pattern(size)
  let d = bm.data
  let n = size * size * 4
  for i in 0..<n {
    let s = match i % 4 {
      0 => i + 2 // R → 内存第 3 槽
      1 => i + 1 // G 原位
      2 => i - 2 // B → 内存第 1 槽
      _ => i // A 已是 255
    }
    d[i] = px[s]
  }
  bm
}

///|
/// GPU 场景（GpuSink 两原语，坐标画布口径）：底色 + 纹理 quad + 计数色块
/// + 底部条带；颜色 a 全 255。
fn gpu_scene_gpu(
  sink : &@render.GpuSink,
  pattern : Bytes,
  step : Int32,
  r : @base.Rect,
) -> Unit {
  @render.GpuSink::fill_rect(
    sink,
    { x: 0.0, y: 0.0, w: r.w, h: r.h, },
    "#1B2027",
    None,
    1.0,
  )
  @render.GpuSink::draw_texture_rgba(
    sink,
    pattern,
    32,
    32,
    { x: 16.0, y: 16.0, w: 168.0, h: 168.0, },
    None,
    1.0,
  )
  let colors = ["#E8B34B", "#4B8BE8", "#4BE888"]
  @render.GpuSink::fill_rect(
    sink,
    { x: r.w - 184.0, y: 16.0, w: 168.0, h: 168.0, },
    colors[step % 3],
    None,
    1.0,
  )
  @render.GpuSink::fill_rect(
    sink,
    { x: 16.0, y: r.h - 40.0, w: r.w - 32.0, h: 24.0, },
    "#3A4350",
    None,
    1.0,
  )
}

///|
/// 同一场景的 CPU 参照（on_render 拿到 Cpu 档时画，与 GPU 版逐块对应）。
fn gpu_scene_cpu(
  p : @render.Painter,
  pattern : @render.Bitmap,
  step : Int32,
  r : @base.Rect,
) -> Unit {
  p.set_fill_color("#1B2027")
  p.fill_rect(0.0, 0.0, r.w, r.h)
  p.draw_canvas(@render.Canvas::{ bitmap: pattern, }, 16.0, 16.0, 168.0, 168.0)
  let colors = ["#E8B34B", "#4B8BE8", "#4BE888"]
  p.set_fill_color(colors[step % 3])
  p.fill_rect(r.w - 184.0, 16.0, 168.0, 168.0)
  p.set_fill_color("#3A4350")
  p.fill_rect(16.0, r.h - 40.0, r.w - 32.0, 24.0)
}

///|
/// 读回字节（BGRA）在 (x,y) 的采样串（R/G/B 十进制，四角对账用）。
fn gpu_sample(bytes : Bytes, w : Int32, x : Int32, y : Int32) -> String {
  let i = (y * w + x) * 4
  "R\{bytes[i + 2].to_int()} G\{bytes[i + 1].to_int()} B\{bytes[i].to_int()}"
}

// ===== 3D 段（GPU 内容画布 3D 接口的验收面）=====

///|
/// 列主序 4x4（16 f32）乘法：`a * b`（先 b 后 a 作用）。
fn cube_mat_mul(
  a : FixedArray[Double],
  b : FixedArray[Double],
) -> FixedArray[Double] {
  let m = FixedArray::make(16, 0.0)
  for c in 0..<4 {
    for r in 0..<4 {
      let mut s = 0.0
      for k in 0..<4 {
        s += a[k * 4 + r] * b[c * 4 + k]
      }
      m[c * 4 + r] = s
    }
  }
  m
}

///|
/// 透视投影（WebGPU 0..1 深度；yy 取负——NDC y 向上、画布读回 y 向下）。
fn cube_perspective(
  fov_y : Double,
  aspect : Double,
  near : Double,
  far : Double,
) -> FixedArray[Double] {
  let f = 1.0 / @math.tan(fov_y / 2.0)
  let m = FixedArray::make(16, 0.0)
  m[0] = f / aspect
  m[5] = -f
  m[10] = far / (near - far)
  m[11] = -1.0
  m[14] = far * near / (near - far)
  m
}

///|
/// 绕 Y 轴旋转（列主序）。
fn cube_rotate_y(t : Double) -> FixedArray[Double] {
  let m = FixedArray::make(16, 0.0)
  m[0] = @math.cos(t)
  m[5] = 1.0
  m[2] = -(@math.sin(t))
  m[8] = @math.sin(t)
  m[10] = @math.cos(t)
  m[15] = 1.0
  m
}

///|
/// 绕 X 轴旋转（列主序）。
fn cube_rotate_x(t : Double) -> FixedArray[Double] {
  let m = FixedArray::make(16, 0.0)
  m[0] = 1.0
  m[5] = @math.cos(t)
  m[6] = @math.sin(t)
  m[9] = -(@math.sin(t))
  m[10] = @math.cos(t)
  m[15] = 1.0
  m
}

///|
/// 平移（列主序）。
fn cube_translate(x : Double, y : Double, z : Double) -> FixedArray[Double] {
  let m = FixedArray::make(16, 0.0)
  m[0] = 1.0
  m[5] = 1.0
  m[10] = 1.0
  m[15] = 1.0
  m[12] = x
  m[13] = y
  m[14] = z
  m
}

///|
/// MVP（16 f32）打包 64 字节（WGSL mat4x4 同布局）。
fn cube_mat_bytes(m : FixedArray[Double]) -> Bytes {
  let out = FixedArray::make(64, b'\x00')
  for i in 0..<16 {
    @guigpu.gpu_pack_f32(out, i * 4, m[i])
  }
  Bytes::from_array(out)
}

///|
/// 立方体 36 顶点（pos3 col4，六面各 2 三角、CCW 朝外、每面一色）。
fn cube_vertices() -> Bytes {
  let all = FixedArray::make(36 * 7, 0.0)
  let vi = Ref(0)
  let face = fn(
    v : Array[(Double, Double, Double)],
    r : Double,
    g : Double,
    b : Double,
  ) -> Unit {
    for idx in [0, 1, 2, 0, 2, 3] {
      let (x, y, z) = v[idx]
      let o = vi.val
      all[o] = x
      all[o + 1] = y
      all[o + 2] = z
      all[o + 3] = r
      all[o + 4] = g
      all[o + 5] = b
      all[o + 6] = 1.0
      vi.val = o + 7
    }
  }
  let a = 1.0
  // 前 +Z 红 / 后 -Z 橙 / 上 +Y 绿 / 下 -Y 蓝 / 右 +X 黄 / 左 -X 青
  face([(-a, -a, a), (a, -a, a), (a, a, a), (-a, a, a)], 0.9, 0.25, 0.25)
  face([(a, -a, -a), (-a, -a, -a), (-a, a, -a), (a, a, -a)], 0.93, 0.6, 0.24)
  face([(-a, a, a), (a, a, a), (a, a, -a), (-a, a, -a)], 0.3, 0.75, 0.35)
  face([(-a, -a, -a), (a, -a, -a), (a, -a, a), (-a, -a, a)], 0.3, 0.5, 0.9)
  face([(a, -a, a), (a, -a, -a), (a, a, -a), (a, a, a)], 0.95, 0.8, 0.25)
  face([(-a, -a, -a), (-a, -a, a), (-a, a, a), (-a, a, -a)], 0.25, 0.8, 0.8)
  let out = FixedArray::make(36 * 7 * 4, b'\x00')
  for i in 0..<(36 * 7) {
    @guigpu.gpu_pack_f32(out, i * 4, all[i])
  }
  Bytes::from_array(out)
}

///|
/// 3D 段节点：自建画布/管线/缓冲/bind group 画旋转立方体（深度测试档），
/// 「自动旋转」用 shell 定时器自续驱动、被换树摘下断链；GPU 建不出整段
/// 降级 notice——3D 无 CPU 回退档，如实声明。
fn gpu_cube_section() -> @widget.Node {
  match @guigpu.GpuCanvas::new(360, 240) {
    Err(e) =>
      @ui.text(
        @shared.tx(
          "3D 画布建不出：\{e}\n3D 段无 CPU 回退档——需要 gui-gpu 的 vendor 归档与可用 GPU 驱动。",
        ),
        wrap=true,
        max_width=436.0,
        class=[@style.text_secondary],
      )
    Ok(canvas) => {
      let wgsl =
        (
        #|struct U {
        #|  mvp : mat4x4<f32>,
        #|}
        #|@group(0) @binding(0) var<uniform> u : U;
        #|struct VOut {
        #|  @builtin(position) pos : vec4f,
        #|  @location(0) col : vec4f,
        #|}
        #|@vertex fn vs(@location(0) p : vec3f, @location(1) col : vec4f) -> VOut {
        #|  var o : VOut;
        #|  o.pos = u.mvp * vec4f(p, 1.0);
        #|  o.col = col;
        #|  return o;
        #|}
        #|@fragment fn fs(frag_in : VOut) -> @location(0) vec4f {
        #|  return frag_in.col;
        #|}
        )
      let layout = [
        @guigpu.GpuVertexLayout::{
          stride: 28L,
          step_mode: @guigpu.GpuStepMode::StepVertex,
          attrs: [
            @guigpu.GpuVertexAttr::{ location: 0, format: @guigpu.GpuVertexFormat::Float32x3, offset: 0L },
            @guigpu.GpuVertexAttr::{ location: 1, format: @guigpu.GpuVertexFormat::Float32x4, offset: 12L },
          ],
        },
      ]
      let pipe = match canvas.create_render_pipeline(
          wgsl,
          layout,
          blend=false,
          depth=true,
        ) {
        Err(e) =>
          return @ui.text(
            @shared.tx("3D 管线建不出：\{e}"),
            wrap=true,
            max_width=436.0,
            class=[@style.text_secondary],
          )
        Ok(h) => h
      }
      let bgl = match canvas.pipeline_bind_group_layout(pipe) {
        Err(e) =>
          return @ui.text(
            @shared.tx("bind group layout 拿不到：\{e}"),
            wrap=true,
            max_width=436.0,
            class=[@style.text_secondary],
          )
        Ok(h) => h
      }
      let vbo = match canvas.create_buffer(
          1008L,
          [@guigpu.GpuBufFlag::Vertex, @guigpu.GpuBufFlag::CopyDst],
        ) {
        Err(e) =>
          return @ui.text(
            @shared.tx("顶点缓冲建不出：\{e}"),
            wrap=true,
            max_width=436.0,
            class=[@style.text_secondary],
          )
        Ok(h) => h
      }
      let ubo = match canvas.create_buffer(
          64L,
          [@guigpu.GpuBufFlag::Uniform, @guigpu.GpuBufFlag::CopyDst],
        ) {
        Err(e) =>
          return @ui.text(
            @shared.tx("uniform 缓冲建不出：\{e}"),
            wrap=true,
            max_width=436.0,
            class=[@style.text_secondary],
          )
        Ok(h) => h
      }
      let bind = match canvas.create_bind_group(
          bgl,
          [@guigpu.GpuBindBuffer::{ binding: 0, buffer: ubo, offset: 0L, size: 64L }],
        ) {
        Err(e) =>
          return @ui.text(
            @shared.tx("bind group 建不出：\{e}"),
            wrap=true,
            max_width=436.0,
            class=[@style.text_secondary],
          )
        Ok(h) => h
      }
      let _ = canvas.write_buffer(vbo, cube_vertices())
      let angle : Ref[Double] = Ref(0.5)
      let status : @base.Store[String] = @base.Store::new(@shared.tx("（点「自动旋转」或「转 30°」驱动立方体）"))
      // 画一帧 3D：MVP 更新 → begin(depth) → set×3 → draw(36) → end
      let draw_cube = fn() -> Bool {
        let aspect = 360.0 / 240.0
        let proj = cube_perspective(50.0 * 3.14159265 / 180.0, aspect, 0.1, 40.0)
        let view = cube_translate(0.0, 0.0, -4.0)
        let model = cube_mat_mul(
          cube_rotate_y(angle.val),
          cube_rotate_x(angle.val * 0.6),
        )
        let mvp = cube_mat_mul(proj, cube_mat_mul(view, model))
        if !canvas.write_buffer(ubo, cube_mat_bytes(mvp)) {
          status.set(@shared.tx("uniform 写入失败"))
          return false
        }
        match canvas.begin_frame(clear="#101820", depth=true) {
          Err(e) => {
            status.set(@shared.tx("帧开不出：\{e}"))
            false
          }
          Ok(f) => {
            let ok = f.set_pipeline(pipe) &&
              f.set_bind_group(bind) &&
              f.set_vertex_buffer(vbo) &&
              f.draw(36)
            f.end()
            if !ok {
              status.set(@shared.tx("帧内提交被拒（句柄无效或未开帧）"))
            }
            ok
          }
        }
      }
      let _ = draw_cube()
      // 自动旋转：shell 定时器 16ms 自续（display 自转同一手法）；被换树
      // 摘下 on_discard 断链；隐藏页不置脏不读回（is_painted 守卫）
      let running : Ref[Bool] = Ref(false)
      let timer_id : Ref[Int] = Ref(-1)
      let wref : Ref[@widget.Widget?] = Ref(None)
      let tick : Ref[() -> Unit] = Ref(fn() { () })
      tick.val = fn() {
        timer_id.val = @shell.set_timeout(16, fn() {
          if running.val {
            angle.val = angle.val + 0.05
            let _ = draw_cube()
            match wref.val {
              Some(w) => if w.is_painted() { @widget.invalidate() }
              None => ()
            }
            (tick.val)()
          }
        })
      }
      let stop_auto = fn() -> Unit {
        running.val = false
        if timer_id.val > 0 {
          @shell.clear_timeout(timer_id.val)
          timer_id.val = -1
        }
      }
      let shot : Ref[@render.Bitmap?] = Ref(None)
      let view3d = @ui.view(
        [
          @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget {
            w.node.set_width(@yoga.fixed(360.0))
            w.node.set_height(@yoga.fixed(240.0))
            wref.val = Some(w)
            w.on_discard = Some(fn(_w) { stop_auto() })
            w.on_draw = Some(fn(
              _self : @widget.Widget,
              p : @render.Painter,
              r : @base.Rect,
            ) -> Unit {
              match canvas.finish() {
                None => {
                  p.set_fill_color("#101820")
                  p.fill_rect(0.0, 0.0, r.w, r.h)
                }
                Some(bytes) => {
                  let bm = match shot.val {
                    Some(b) => b
                    None => {
                      let b = @render.Bitmap::new(360, 240)
                      shot.val = Some(b)
                      b
                    }
                  }
                  let d = bm.data
                  for i in 0..<(360 * 240 * 4) {
                    d[i] = bytes[i]
                  }
                  p.draw_canvas(
                    @render.Canvas::{ bitmap: bm, },
                    0.0,
                    0.0,
                    r.w,
                    r.h,
                  )
                }
              }
            })
            w
          }),
        ],
        width=360.0,
        height=240.0,
        border_color="border",
      )
      let auto : @base.Store[Bool] = @base.Store::new(false)
      @ui.col(
        [
          view3d,
          @ui.row(
            [
              @ui.switch(auto, on_text="转", off_text="停", on_change=fn(v : Bool) -> Unit {
                if v {
                  running.val = true
                  (tick.val)()
                } else {
                  stop_auto()
                }
              }),
              @ui.text(@shared.tx("自动旋转"), class=[@style.text_secondary]),
              @ui.button(@shared.tx("转 30°"), on_click=fn() -> Unit {
                angle.val = angle.val + 3.14159265 / 6.0
                if draw_cube() {
                  status.set(@shared.tx("已转 30° 并重绘一帧"))
                }
                @widget.invalidate()
              }),
            ],
            column_gap=10.0,
            align_items=@yoga.AlignItems::Center,
          ),
          @ui.text_dyn(status.signal(), wrap=true, max_width=436.0, class=[
            @style.text_secondary,
          ]),
          @ui.text(
            @shared.tx(
              "自建管线（顶点色 + Depth24Plus）/ 顶点与 uniform 缓冲 / bind group 均走 GpuCanvas 薄壳接口；MVP 每帧 write_buffer 更新。句柄应用自有——不占进程级 sink 槽。",
            ),
            wrap=true,
            max_width=436.0,
            class=[@style.text_secondary],
          ),
        ],
        row_gap=10.0,
      )
    }
  }
}

///|
pub fn page_gpu(_app : @shared.App) -> @widget.Node {
  // 探测读数（probe 进程级幂等，构建时算一次即可）
  let pr = @guigpu.probe()
  let l1 = @win.gpu_present_status()
  let probe_text = if l1 == "on" {
    "\{pr.detail}\n呈现档: on（位图上传纹理 → GPU present）"
  } else {
    "\{pr.detail}\n呈现档: 回退 CPU 路径（\{l1}）"
  }
  let probe_panel = @ui.view(
    [
      @ui.text(@shared.tx("GPU 扩展与呈现档"), class=[@style.text_title]),
      @ui.text(probe_text, wrap=true, max_width=436.0, class=[
        @style.text_secondary,
      ]),
    ],
    width=460.0,
    row_gap=4.0,
    padding=12.0,
    align_items=@yoga.AlignItems::FlexStart,
    background_color="bg_panel",
    border_color="border",
    class=[@style.style(border_radius=6.0)],
  )
  let step : Ref[Int32] = Ref(0)
  let status : @base.Store[String] = @base.Store::new(
    @shared.tx("（点「检查读回」分析最近一帧读回）"),
  )
  match @guigpu.GpuCanvas::new(400, 240) {
    Err(e) =>
      @shared.page([
        @shared.section(
          "探测",
          "GPU 探测",
          "gui-gpu 扩展装载读数与 L1 呈现档（窗口呈现走 GPU 或回退 CPU 的原因）。",
          [probe_panel],
        ),
        @shared.section(
          "画布",
          "GPU 画布",
          "GPU 画布不可用时的降级形态。",
          [
            @ui.text(
              @shared.tx(
                "GPU 画布建不出：\{e}\n需要 gui-gpu 的 vendor 归档（scripts/prebuild.mbtx 下载 wgpu-native）与可用 GPU 驱动；不可用是降级形态，不影响其余页面。",
              ),
              wrap=true,
              class=[@style.text_secondary],
            ),
          ],
        ),
        @shared.section(
          "3D",
          "GPU 3D 立方体",
          "GPU 内容画布 3D 接口的验收面（自建管线 + 深度帧）。",
          [gpu_cube_section()],
        ),
      ])
    Ok(canvas) => {
      // 进程级 sink 槽（@widget.gpu_set_sink）：设了且控件挂 on_render 才派
      // Gpu 档。本页是全应用唯一 on_render 消费者，装上不摘（导航走不摘也
      // 无旁效）；画布随页面重建各持一份，wgpu 对象进程所有、不显式释放。
      canvas.install()
      let pattern = gpu_pattern(32)
      let pat_bmp = gpu_pattern_bitmap(32)
      let shot : Ref[@render.Bitmap?] = Ref(None)
      let scene = @ui.view(
        [
          @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget {
            w.node.set_width(@yoga.fixed(400.0))
            w.node.set_height(@yoga.fixed(240.0))
            w.on_draw = Some(fn(
              _self : @widget.Widget,
              p : @render.Painter,
              r : @base.Rect,
            ) -> Unit {
              // 同帧顺序：容器 on_render 先画进画布，这里再读回——兄弟/父子
              // 绘制序由 paint_at 保证（先自己后 kids）。全零帧显示黑底，
              // 「检查读回」给判定。
              match canvas.finish() {
                None => {
                  p.set_fill_color("#1B2027")
                  p.fill_rect(0.0, 0.0, r.w, r.h)
                }
                Some(bytes) => {
                  let bm = match shot.val {
                    Some(b) => b
                    None => {
                      let b = @render.Bitmap::new(canvas.w, canvas.h)
                      shot.val = Some(b)
                      b
                    }
                  }
                  let d = bm.data
                  let n = canvas.w * canvas.h * 4
                  for i in 0..<n {
                    d[i] = bytes[i]
                  }
                  p.draw_canvas(
                    @render.Canvas::{ bitmap: bm, },
                    0.0,
                    0.0,
                    r.w,
                    r.h,
                  )
                }
              }
            })
            w
          }),
        ],
        width=400.0,
        height=240.0,
        border_color="border",
        handle=fn(w : @widget.Widget) -> Unit {
          w.on_render = Some(fn(
            _self : @widget.Widget,
            ctx : @render.RenderCtx,
            r : @base.Rect,
          ) -> Unit {
            match ctx.as_gpu() {
              Some(gc) => gpu_scene_gpu(gc.sink, pattern, step.val, r)
              None =>
                match ctx.as_painter() {
                  Some(p) => gpu_scene_cpu(p, pat_bmp, step.val, r)
                  None => ()
                }
            }
          })
        },
      )
      @shared.page([
        @shared.section(
          "探测",
          "GPU 探测",
          "gui-gpu 扩展装载读数与 L1 呈现档（窗口呈现走 GPU 或回退 CPU 的原因）。",
          [probe_panel],
        ),
        @shared.section(
          "画布",
          "GPU 画布",
          "容器挂 on_render 走 RenderCtx::Gpu 派发：fill_rect / draw_texture_rgba 两条原语画进离屏 GpuCanvas，同帧 finish() 读回 BGRA 字节直拷上屏。「检查读回」给非零率与四角采样；全零表示离屏渲染或读回链异常，见 experience/adaptation.md。",
          [
            scene,
            @ui.row(
              [
                @ui.button(@shared.tx("重绘"), on_click=fn() {
                  step.val = (step.val + 1) % 3
                  @widget.invalidate()
                }),
                @ui.button(@shared.tx("检查读回"), variant=@ui.Soft, on_click=fn() {
                  match canvas.finish() {
                    None =>
                      status.set(
                        @shared.tx("读回失败：设备丢失或 map 超时"),
                      )
                    Some(bytes) => {
                      let n = bytes.length()
                      let mut nz = 0
                      for i in 0..<n {
                        if bytes[i] != b'\x00' {
                          nz = nz + 1
                        }
                      }
                      // 四角是底色基准（全零 vs 画了底色），图案/色块中心分辨
                      // 「clear 落了但原语没执行」（Linux 未结案现象的细分）
                      let corners = "四角 \{gpu_sample(bytes, canvas.w, 2, 2)} \{gpu_sample(bytes, canvas.w, canvas.w - 3, 2)} \{gpu_sample(bytes, canvas.w, 2, canvas.h - 3)} \{gpu_sample(bytes, canvas.w, canvas.w - 3, canvas.h - 3)}\n图案中心 \{gpu_sample(bytes, canvas.w, 100, 100)}  色块中心 \{gpu_sample(bytes, canvas.w, canvas.w - 100, 100)}"
                      let head = if nz == 0 {
                        @shared.tx("非零 0%（\{nz}/\{n} 字节）")
                      } else {
                        "非零 \{nz * 100 / n}%（\{nz}/\{n} 字节）"
                      }
                      let verdict = if nz == 0 {
                        @shared.tx(
                          "读回全零——离屏渲染或读回链异常（见 experience/adaptation.md）",
                        )
                      } else {
                        @shared.tx("读回有像素 ✓")
                      }
                      status.set("\{head}\n\{corners}\n\{verdict}")
                    }
                  }
                }),
              ],
              column_gap=8.0,
            ),
            @ui.text_dyn(status.signal(), wrap=true, max_width=476.0, class=[
              @style.text_secondary,
            ]),
          ],
          code=[
            "canvas.install()  // 进程级 sink 槽（@widget.gpu_set_sink）",
            "@ui.view([读回显示件], width=400.0, height=240.0, handle=fn(w) {",
            "  w.on_render = Some(fn(_s, ctx, r) {", "    match ctx.as_gpu() {",
            "      Some(gc) => @render.GpuSink::fill_rect(gc.sink, r, \"#1B2027\", None, 1.0)",
            "      None => ...  // Cpu 档回退画同款", "    }", "  })", "})",
            "// 读回显示件 on_draw：canvas.finish() 读回 BGRA 字节直拷 Bitmap，",
            "// p.draw_canvas(...) 铺满同一区域（GPU 派发的控件不往 CPU 位图涂写）",
          ],
        ),
        @shared.section(
          "3D",
          "GPU 3D 立方体",
          "GPU 内容画布 3D 接口的验收面：GpuCanvas 薄壳接口自建管线（顶点色 + Depth24Plus）、顶点与 uniform 缓冲、bind group，MVP 每帧更新画旋转立方体；「自动旋转」驱动逐帧重绘。3D 无 CPU 回退档——GPU 建不出时整段降级 notice。",
          [gpu_cube_section()],
        ),
      ])
    }
  }
}
