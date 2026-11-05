// GPU 画布页（第 16 页）：L2 协议首消费者验收面。容器挂 `on_render` 走
// `RenderCtx::Gpu` 派发，把 `fill_rect` / `draw_texture_rgba` 两条原语画进
// `@guigpu.GpuCanvas`（离屏 BGRA 目标）；GPU 派发的控件不往 CPU 位图涂写，
// 所以同帧由子控件 `finish()` 读回字节直拷上屏（读回 BGRA 与位图 ARGB32
// 内存序在 a=255 时零转换）。读回全零 = adaptation.md「wgpu 进程内队列写
// 不落地」的现场数据（真机复验就是验这条）；没装 GPU 扩展整段降级 notice，
// 探测读数如实显示。

///|
/// 32×32 不透明图案字节（draw_texture_rgba 语义：R,G,B,A，全 a=255）：
/// 红蓝棋盘 + 横向渐变，边缘与中心都可当采样点。
fn gpu_pattern(size : Int) -> Bytes {
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
fn gpu_pattern_bitmap(size : Int) -> @render.Bitmap {
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
  step : Int,
  r : @base.Rect,
) -> Unit {
  @render.GpuSink::fill_rect(
    sink,
    { x: 0.0, y: 0.0, w: r.w, h: r.h },
    "#1B2027",
    None,
    1.0,
  )
  @render.GpuSink::draw_texture_rgba(
    sink,
    pattern,
    32,
    32,
    { x: 16.0, y: 16.0, w: 168.0, h: 168.0 },
    None,
    1.0,
  )
  let colors = ["#E8B34B", "#4B8BE8", "#4BE888"]
  @render.GpuSink::fill_rect(
    sink,
    { x: r.w - 184.0, y: 16.0, w: 168.0, h: 168.0 },
    colors[step % 3],
    None,
    1.0,
  )
  @render.GpuSink::fill_rect(
    sink,
    { x: 16.0, y: r.h - 40.0, w: r.w - 32.0, h: 24.0 },
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
  step : Int,
  r : @base.Rect,
) -> Unit {
  p.set_fill_color("#1B2027")
  p.fill_rect(0.0, 0.0, r.w, r.h)
  p.draw_canvas(@render.Canvas::{ bitmap: pattern }, 16.0, 16.0, 168.0, 168.0)
  let colors = ["#E8B34B", "#4B8BE8", "#4BE888"]
  p.set_fill_color(colors[step % 3])
  p.fill_rect(r.w - 184.0, 16.0, 168.0, 168.0)
  p.set_fill_color("#3A4350")
  p.fill_rect(16.0, r.h - 40.0, r.w - 32.0, 24.0)
}

///|
/// 读回字节（BGRA）在 (x,y) 的采样串（R/G/B 十进制，四角对账用）。
fn gpu_sample(bytes : Bytes, w : Int, x : Int, y : Int) -> String {
  let i = (y * w + x) * 4
  "R\{bytes[i + 2].to_int()} G\{bytes[i + 1].to_int()} B\{bytes[i].to_int()}"
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
  let step : Ref[Int] = Ref(0)
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
                "GPU 画布建不出：\{e}\n需要 gui-gpu 的 vendor 归档（modules/gui-gpu/prebuild.py 下载 wgpu-native）与可用 GPU 驱动；不可用是降级形态，不影响其余页面。",
              ),
              wrap=true,
              class=[@style.text_secondary],
            ),
          ],
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
                    @render.Canvas::{ bitmap: bm },
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
          "容器挂 on_render 走 RenderCtx::Gpu 派发：fill_rect / draw_texture_rgba 两条原语画进离屏 GpuCanvas，同帧 finish() 读回 BGRA 字节直拷上屏。「检查读回」给非零率与四角采样；读回全零即已知问题（见 experience/adaptation.md），真机应用进程复验归用户。",
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
                      status.set(@shared.tx("读回失败：设备丢失或 map 超时"))
                    Some(bytes) => {
                      let n = bytes.length()
                      let mut nz = 0
                      for i in 0..<n {
                        if bytes[i] != b'\x00' {
                          nz = nz + 1
                        }
                      }
                      let corners = "左上 \{gpu_sample(bytes, canvas.w, 2, 2)}  右上 \{gpu_sample(bytes, canvas.w, canvas.w - 3, 2)}  左下 \{gpu_sample(bytes, canvas.w, 2, canvas.h - 3)}  右下 \{gpu_sample(bytes, canvas.w, canvas.w - 3, canvas.h - 3)}"
                      let head = if nz == 0 {
                        @shared.tx("非零 0%（\{nz}/\{n} 字节）")
                      } else {
                        "非零 \{nz * 100 / n}%（\{nz}/\{n} 字节）"
                      }
                      let verdict = if nz == 0 {
                        @shared.tx(
                          "读回全零——queue 写→GPU 执行链不落地（已知问题，把现象贴回）",
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
            "  w.on_render = Some(fn(_s, ctx, r) {",
            "    match ctx.as_gpu() {",
            "      Some(gc) => @render.GpuSink::fill_rect(gc.sink, r, \"#1B2027\", None, 1.0)",
            "      None => ...  // Cpu 档回退画同款",
            "    }",
            "  })",
            "})",
            "// 读回显示件 on_draw：canvas.finish() 读回 BGRA 字节直拷 Bitmap，",
            "// p.draw_canvas(...) 铺满同一区域（GPU 派发的控件不往 CPU 位图涂写）",
          ],
        ),
      ])
    }
  }
}
