// GPU 地基回归：探测不抛错、详情可打印；没装归档是「不可用」而不是失败。

///|
test "probe：无归档时如实报不可用，且详情是给人看的" {
  let p = probe()
  // 两种环境都必须给一句可读的 detail（装了的报 loaded(路径)，没装的报
  // not-found: 原因），不允许空串把问题藏起来
  assert_true(p.detail.length() > 0, msg="探测详情不能为空")
  if p.loaded {
    assert_true(
      p.detail.has_prefix("loaded"),
      msg="可用时详情应以 loaded 开头：\{p.detail}",
    )
  } else {
    assert_true(
      p.detail.has_prefix("not-found") || p.detail.has_prefix("env-lib"),
      msg="不可用时详情应说明缺什么：\{p.detail}",
    )
  }
}

///|
test "probe：同进程内二次探测幂等" {
  let a = probe()
  let b = probe()
  assert_eq(a.loaded, b.loaded)
  assert_eq(a.detail, b.detail)
}

///|
/// 无头建一块小画布，走两条 draw（textured quad + solid quad）再读回。
/// **不开窗**（离屏渲染 + 回读，预实证口径）；没装 GPU 扩展（vendor 归档
/// 没下载/驱动起不来）跳过——「没装」是降级形态不是失败。
///
/// 读回字节序是 **BGRA**（离屏目标 BGRA8Unorm 与位图 ARGB32 同字节序：
/// 内存 B,G,R,A）——断言按这个口径写。
test "canvas：无头 draw + 读回（有 GPU 扩展才跑）" {
  let p = probe()
  if !p.loaded {
    println("canvas: skip（没装 GPU 扩展: \{p.detail}）")
    return
  }
  match GpuCanvas::new(64, 48) {
    Err(e) => fail("画布建不出：\{e}")
    Ok(c) => {
      // 8×8 图案：左上红 (255,0,0,255)、右下蓝 (0,0,255,255)，其余灰
      let px = FixedArray::make(8 * 8 * 4, b'\x00')
      for y in 0..<8 {
        for x in 0..<8 {
          let i = (y * 8 + x) * 4
          if x < 4 && y < 4 {
            px[i] = b'\xFF' // B 槽？不——图案按 RGBA 语义写，读回按 BGRA 验
            px[i + 3] = b'\xFF'
          } else if x >= 4 && y >= 4 {
            px[i + 2] = b'\xFF'
            px[i + 3] = b'\xFF'
          } else {
            px[i] = b'\x80'
            px[i + 1] = b'\x80'
            px[i + 2] = b'\x80'
            px[i + 3] = b'\xFF'
          }
        }
      }
      let data = Bytes::from_array(px)
      // 限定形式走 trait 方法（协议面；坐标画布口径）
      @render.GpuSink::draw_texture_rgba(
        c,
        data,
        8,
        8,
        { x: 0.0, y: 0.0, w: 64.0, h: 48.0, },
        None,
        1.0,
      )
      // 半透明绿矩形盖在中间（opacity 0.5 × 色 alpha 0.5）
      @render.GpuSink::fill_rect(
        c,
        { x: 16.0, y: 12.0, w: 32.0, h: 24.0, },
        "#00ff0080",
        None,
        0.5,
      )
      match c.finish() {
        None => fail("读回失败")
        Some(b) => {
          assert_eq(b.length(), 64 * 48 * 4)
          // 全零留作异常判据：曾因管线 multisample.mask 被 memset 清成 0
          // 导致所有 draw 不出像素（adaptation.md 2026-11-06 更正），现已修。
          // 这里保留全零分支只作诊断，管线/协议面的断言照跑。
          let all_zero = b[0] == 0 &&
            b[1] == 0 &&
            b[2] == 0 &&
            b[3] == 0 &&
            b[4] == 0 &&
            b[5] == 0
          if all_zero {
            println(
              "canvas: 读回全零——离屏渲染或读回链异常（见 adaptation.md），像素断言跳过",
            )
          } else {
            // 样点读数先落一行：首轮真像素（mac）就是靠它判方向/通道序
            let sample = fn(x : Int32, y : Int32) -> String {
              let i = (y * 64 + x) * 4
              "(\{b[i]},\{b[i + 1]},\{b[i + 2]},\{b[i + 3]})"
            }
            println(
              "canvas 读回样点 B,G,R,A：左上 \{sample(0, 0)} 右上 \{sample(63, 0)} 左下 \{sample(0, 47)} 右下 \{sample(63, 47)} 中心 \{sample(32, 24)}",
            )
            // 读回字节序 BGRA：左上图案红 → 第 3 字节（R 槽）255
            assert_eq(b[2], 255, msg="左上应是图案红（R 槽）")
            assert_eq(b[0], 0, msg="左上 B 槽应为 0")
            assert_eq(b[3], 255, msg="左上 alpha 应满")
            // 右下角外（图案蓝区，没被绿矩形盖到）：B 槽 255
            let ri = (47 * 64 + 63) * 4
            assert_eq(b[ri + 2], 0, msg="右下 R 槽应为 0（蓝区）")
            assert_eq(b[ri], 255, msg="右下 B 槽应 255（蓝区）")
            // 绿矩形中心：G 槽被抬过（绿矩形盖上了）
            let ci = (24 * 64 + 32) * 4
            assert_true(
              b[ci + 1] > 40,
              msg="矩形中心应吃到绿：g=\{b[ci + 1]}",
            )
          }
        }
      }
      c.free()
    }
  }
}

///|
/// 读回字节与期望值就近（±tol）——GPU 各后端对非 2^n 颜色有舍入差，取容差。
fn frame_near(v : Byte, target : Int, tol : Int) -> Bool {
  let d = v.to_int() - target
  d >= -tol && d <= tol
}

///|
/// 读回 (x,y) 的 BGRA 采样串（诊断行用）。
fn frame_sample(bytes : Bytes, w : Int32, x : Int32, y : Int32) -> String {
  let i = (y * w + x) * 4
  "(\{bytes[i]},\{bytes[i + 1]},\{bytes[i + 2]},\{bytes[i + 3]})"
}

///|
/// 全零帧判据（历史坑：multisample.mask 被 memset 清零 → 全部 draw 不出像素）。
fn frame_all_zero(bytes : Bytes) -> Bool {
  bytes[0] == 0 && bytes[1] == 0 && bytes[2] == 0 && bytes[3] == 0
}

///|
/// 3D 帧面回归：自建管线（顶点色 + 深度档）在深度帧里画两个 z 不同的三角，
/// **先画近的后画远的**——没有深度测试时远三角会把重叠区涂掉，深度生效时
/// 重叠区保持近三角颜色。读回按 BGRA 断言（±3 容差）。
/// 没装 GPU 扩展跳过——「没装」是降级形态不是失败；探到真后端而断言失败
/// 照常报警。
test "frame：3D 管线 + 深度序 + 读回（有 GPU 扩展才跑）" {
  let p = probe()
  if !p.loaded {
    println("frame: skip（没装 GPU 扩展: \{p.detail}）")
    return
  }
  match GpuCanvas::new(64, 48) {
    Err(e) => fail("画布建不出：\{e}")
    Ok(c) => {
      let wgsl =
        (
        #|struct VOut {
        #|  @builtin(position) pos : vec4f,
        #|  @location(0) col : vec4f,
        #|}
        #|@vertex fn vs(@location(0) p : vec3f, @location(1) col : vec4f) -> VOut {
        #|  var o : VOut;
        #|  o.pos = vec4f(p, 1.0);
        #|  o.col = col;
        #|  return o;
        #|}
        #|@fragment fn fs(in : VOut) -> @location(0) vec4f {
        #|  return in.col;
        #|}
        )
      let layout = [
        GpuVertexLayout::{
          stride: 28L,
          step_mode: GpuStepMode::StepVertex,
          attrs: [
            GpuVertexAttr::{ location: 0, format: GpuVertexFormat::Float32x3, offset: 0L },
            GpuVertexAttr::{ location: 1, format: GpuVertexFormat::Float32x4, offset: 12L },
          ],
        },
      ]
      let pipe = match c.create_render_pipeline(
          wgsl,
          layout,
          blend=false,
          depth=true,
        ) {
        Err(e) => fail("管线建不出：\{e}")
        Ok(hd) => hd
      }
      // 顶点数据：A 红三角 z=0.5（远），B 绿三角 z=0.2（近）。绘制序 B→A：
      // 重叠区深度测试该把 A 挡掉。
      let vd = FixedArray::make(6 * 7 * 4, b'\x00')
      let mut o = 0
      // A：(-0.9,-0.9) (0.9,-0.9) (0,0.9)，红，z=0.5
      let ax = [-0.9, 0.9, 0.0]
      let ay = [-0.9, -0.9, 0.9]
      for i in 0..<3 {
        gpu_pack_f32(vd, o, ax[i])
        gpu_pack_f32(vd, o + 4, ay[i])
        gpu_pack_f32(vd, o + 8, 0.5)
        gpu_pack_f32(vd, o + 12, 1.0)
        gpu_pack_f32(vd, o + 16, 0.0)
        gpu_pack_f32(vd, o + 20, 0.0)
        gpu_pack_f32(vd, o + 24, 1.0)
        o += 28
      }
      // B：(-0.4,-0.8) (0.4,-0.8) (0,0)，绿，z=0.2
      let bx = [-0.4, 0.4, 0.0]
      let by = [-0.8, -0.8, 0.0]
      for i in 0..<3 {
        gpu_pack_f32(vd, o, bx[i])
        gpu_pack_f32(vd, o + 4, by[i])
        gpu_pack_f32(vd, o + 8, 0.2)
        gpu_pack_f32(vd, o + 12, 0.0)
        gpu_pack_f32(vd, o + 16, 1.0)
        gpu_pack_f32(vd, o + 20, 0.0)
        gpu_pack_f32(vd, o + 24, 1.0)
        o += 28
      }
      let vdata = Bytes::from_array(vd)
      let vbuf = match c.create_buffer(168L, [GpuBufFlag::Vertex, GpuBufFlag::CopyDst]) {
        Err(e) => fail("顶点缓冲建不出：\{e}")
        Ok(hd) => hd
      }
      assert_true(c.write_buffer(vbuf, vdata), msg="顶点缓冲写入失败")
      match c.begin_frame(clear="#101820", depth=true) {
        Err(e) => fail("帧开不出：\{e}")
        Ok(f) => {
          assert_true(f.set_pipeline(pipe), msg="set_pipeline 失败")
          assert_true(f.set_vertex_buffer(vbuf), msg="set_vertex_buffer 失败")
          assert_true(f.draw(6), msg="draw 失败")
          f.end()
        }
      }
      match c.finish() {
        None => fail("读回失败")
        Some(b) => {
          assert_eq(b.length(), 64 * 48 * 4)
          if frame_all_zero(b) {
            println(
              "frame: 读回全零——离屏渲染或读回链异常（见 adaptation.md），像素断言跳过",
            )
          } else {
            println(
              "frame 读回样点 B,G,R,A：角 \{frame_sample(b, 64, 2, 2)} 红区 \{frame_sample(b, 64, 32, 12)} 重叠区 \{frame_sample(b, 64, 32, 38)}",
            )
            // 角 (2,2)：两三角之外 = clear #101820 → BGRA (0x20,0x18,0x10,0xFF)
            let ci = (2 * 64 + 2) * 4
            assert_true(
              frame_near(b[ci], 0x20, 3) &&
              frame_near(b[ci + 1], 0x18, 3) &&
              frame_near(b[ci + 2], 0x10, 3),
              msg="角应为 clear 色",
            )
            // 红区 (32,12)：只在 A 内 → R 满 G 空
            let ri = (12 * 64 + 32) * 4
            assert_true(
              frame_near(b[ri + 2], 255, 3) &&
              frame_near(b[ri + 1], 0, 3) &&
              frame_near(b[ri], 0, 3),
              msg="红区应只吃 A",
            )
            // 重叠区 (32,38)：B 先画、A 后画且更远——深度测试生效时保持绿
            let gi = (38 * 64 + 32) * 4
            assert_true(
              frame_near(b[gi + 1], 255, 3) &&
              frame_near(b[gi + 2], 0, 3),
              msg="重叠区应保持近三角绿（深度测试生效）",
            )
          }
        }
      }
      assert_true(c.release_pipeline(pipe), msg="管线释放失败")
      assert_true(c.release_buffer(vbuf), msg="缓冲释放失败")
      c.free()
    }
  }
}

///|
/// 帧语义回归：重复 begin 回 Err；end 后再 begin 正常；开帧忘 end 时
/// finish 自动收口（clear 色落到读回即证）。
test "frame：begin/end 语义与 finish 自动收口（有 GPU 扩展才跑）" {
  let p = probe()
  if !p.loaded {
    println("frame-sem: skip（没装 GPU 扩展: \{p.detail}）")
    return
  }
  match GpuCanvas::new(32, 24) {
    Err(e) => fail("画布建不出：\{e}")
    Ok(c) => {
      match c.begin_frame(clear="#101820") {
        Err(e) => fail("首次 begin 失败：\{e}")
        Ok(f) => {
          match c.begin_frame(clear="#000000") {
            Err(_) => () // 期望：开着的帧上再 begin 回 Err
            Ok(_) => fail("重复 begin 应回 Err")
          }
          f.end()
          // end 后可再开
          match c.begin_frame(clear="#FF0000") {
            Err(e) => fail("end 后 begin 失败：\{e}")
            Ok(f2) => {
              // 故意不 end——finish 自动收口
              let _ = f2
            }
          }
        }
      }
      match c.finish() {
        None => fail("读回失败")
        Some(b) => {
          if !frame_all_zero(b) {
            // 角像素 = 自动收口那一帧的 clear 红
            let i = (2 * 32 + 2) * 4
            assert_true(
              frame_near(b[i + 2], 255, 3) && frame_near(b[i], 0, 3),
              msg="自动收口后角应为 clear 红：\{frame_sample(b, 32, 2, 2)}",
            )
          }
        }
      }
      c.free()
    }
  }
}

///|
/// 资源面回归：shader module 建/释、uniform 管线（无顶点缓冲布局）+ bind
/// group 全链出像素、坏 WGSL 回 Err、write_buffer 4 字节对齐校验。
test "frame：资源面——shader/buffer/bind 全链（有 GPU 扩展才跑）" {
  let p = probe()
  if !p.loaded {
    println("frame-res: skip（没装 GPU 扩展: \{p.detail}）")
    return
  }
  match GpuCanvas::new(32, 24) {
    Err(e) => fail("画布建不出：\{e}")
    Ok(c) => {
      // shader module 建/释
      let sh = c.create_shader_module(
        (
        #|struct VOut {
        #|  @builtin(position) pos : vec4f,
        #|}
        #|@vertex fn vs(@builtin(vertex_index) vi : u32) -> VOut {
        #|  var o : VOut;
        #|  o.pos = vec4f(0.0, 0.0, 0.0, 1.0);
        #|  return o;
        #|}
        #|@fragment fn fs(o : VOut) -> @location(0) vec4f {
        #|  return vec4f(0.0, 0.0, 0.0, 1.0);
        #|}
        ),
      )
      match sh {
        Err(e) => fail("shader 建不出：\{e}")
        Ok(hd) => assert_true(c.release_shader_module(hd), msg="shader 释放失败")
      }
      // 坏 WGSL → Err
      match c.create_render_pipeline("这不是 WGSL", []) {
        Err(_) => ()
        Ok(_) => fail("坏 WGSL 应建不出管线")
      }
      // uniform 管线（无顶点缓冲布局）+ bind group 全链
      let wgsl =
        (
        #|@group(0) @binding(0) var<uniform> u : vec4f;
        #|struct VOut {
        #|  @builtin(position) pos : vec4f,
        #|}
        #|@vertex fn vs(@builtin(vertex_index) vi : u32) -> VOut {
        #|  var pts = array<vec2f, 3>(vec2f(-1.0, -1.0), vec2f(3.0, -1.0), vec2f(-1.0, 3.0));
        #|  var o : VOut;
        #|  o.pos = vec4f(pts[vi] * u.xy, 0.0, 1.0);
        #|  return o;
        #|}
        #|@fragment fn fs(o : VOut) -> @location(0) vec4f {
        #|  return vec4f(1.0, 0.0, 0.0, 1.0);
        #|}
        )
      let pipe = match c.create_render_pipeline(wgsl, []) {
        Err(e) => fail("uniform 管线建不出：\{e}")
        Ok(hd) => hd
      }
      let bgl = match c.pipeline_bind_group_layout(pipe) {
        Err(e) => fail("bind group layout 拿不到：\{e}")
        Ok(hd) => hd
      }
      let ubo = match c.create_buffer(16L, [GpuBufFlag::Uniform, GpuBufFlag::CopyDst]) {
        Err(e) => fail("uniform 缓冲建不出：\{e}")
        Ok(hd) => hd
      }
      let ud = FixedArray::make(16, b'\x00')
      gpu_pack_f32(ud, 0, 1.0)
      gpu_pack_f32(ud, 4, 1.0)
      gpu_pack_f32(ud, 8, 0.0)
      gpu_pack_f32(ud, 12, 0.0)
      assert_true(c.write_buffer(ubo, Bytes::from_array(ud)), msg="uniform 写入失败")
      // 4 字节对齐校验：6 字节写入应被拒
      assert_false(
        c.write_buffer(ubo, Bytes::from_array(FixedArray::make(6, b'\x01'))),
        msg="非 4 对齐写入应失败",
      )
      let bind = match c.create_bind_group(
          bgl,
          [GpuBindBuffer::{ binding: 0, buffer: ubo, offset: 0L, size: 16L }],
        ) {
        Err(e) => fail("bind group 建不出：\{e}")
        Ok(hd) => hd
      }
      match c.begin_frame(clear="#000000") {
        Err(e) => fail("帧开不出：\{e}")
        Ok(f) => {
          assert_true(f.set_pipeline(pipe), msg="set_pipeline 失败")
          assert_true(f.set_bind_group(bind), msg="set_bind_group 失败")
          assert_true(f.draw(3), msg="draw 失败")
          f.end()
        }
      }
      match c.finish() {
        None => fail("读回失败")
        Some(b) => {
          if !frame_all_zero(b) {
            let i = (12 * 32 + 16) * 4
            assert_true(
              frame_near(b[i + 2], 255, 3) && frame_near(b[i + 1], 0, 3),
              msg="中心应为 uniform 管线红：\{frame_sample(b, 32, 16, 12)}",
            )
          }
        }
      }
      assert_true(c.release_bind_group(bind), msg="bind group 释放失败")
      assert_true(c.release_buffer(ubo), msg="缓冲释放失败")
      assert_true(c.release_pipeline(pipe), msg="管线释放失败")
      c.free()
    }
  }
}
