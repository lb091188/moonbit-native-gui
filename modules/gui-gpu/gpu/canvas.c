// GpuCanvas：@render.GpuSink 的 gui-gpu 实现（GPU 线首消费者，方案
// gpu-architecture.md「L2 协议」+「首消费者」）。
//
// 形态：一块离屏 wgpu 渲染目标（BGRA8Unorm——与 MoonBit 位图 ARGB32 同
// 字节序，零转换）。控件的 on_render 经 RenderCtx::Gpu 拿到的 sink 就是本
// 实现；绘制指令落到离屏目标，宿主每帧调 finish 读回 RGBA 字节、走既有
// CPU 绘制贴上屏。**这是 compositor 落地前的过渡形态**（终局是 GPU 控件
// 各渲到自己的 render target、由 present 路径按控件树叠合成——见方案
// 「融合模型」），但 GpuSink 协议面（调用序=控件树序、clip/opacity 随合成
// 传）与本形态无关，消费者代码到时不改。
//
// 坐标口径：**画布坐标**（0..w/0..h）——sink 渲染到自己的离屏目标，窗 →
// 画布的换算是宿主的事（trait 文档的「窗口坐标」是 compositor 终局口径）。
// clip/opacity 口径与 trait 一致：clip 为 None 时不裁，opacity 0..1。
//
// 装载/探测走包内共享的 wgpu_core；本文件只带自己的两条管线（textured
// quad / solid quad）、离屏目标、上传纹理与读回。

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "moonbit.h"
#include "wgpu_core.h"

#if defined(__has_include)
#if __has_include("../vendor/include/webgpu/webgpu.h")
#define MNG_CANVAS_REAL 1
#include "../vendor/include/webgpu/webgpu.h"
#endif
#endif

#if defined(MNG_CANVAS_REAL)

#include <unistd.h> // usleep（mapAsync 泵）
#include <dlfcn.h>  // dlsym（DBG 自建 device 用）

// ---- 函数指针表（PFN typedef 取 vendor 头；装载/探测在 wgpu_core） ----
#define MNG_CV_FN(name) static WGPUProc##name p_wgpu##name = NULL;
MNG_CV_FN(DeviceCreateTexture)
MNG_CV_FN(DeviceCreateBuffer)
MNG_CV_FN(DeviceCreateShaderModule)
MNG_CV_FN(DeviceCreateRenderPipeline)
MNG_CV_FN(DeviceCreateSampler)
MNG_CV_FN(DeviceCreateBindGroup)
MNG_CV_FN(DeviceCreateCommandEncoder)
MNG_CV_FN(RenderPipelineGetBindGroupLayout)
MNG_CV_FN(CommandEncoderBeginRenderPass)
MNG_CV_FN(CommandEncoderCopyBufferToTexture)
MNG_CV_FN(CommandEncoderCopyTextureToBuffer)
MNG_CV_FN(CommandEncoderFinish)
MNG_CV_FN(RenderPassEncoderSetPipeline)
MNG_CV_FN(RenderPassEncoderSetBindGroup)
MNG_CV_FN(RenderPassEncoderSetScissorRect)
MNG_CV_FN(RenderPassEncoderSetVertexBuffer)
MNG_CV_FN(RenderPassEncoderDraw)
MNG_CV_FN(RenderPassEncoderEnd)
MNG_CV_FN(QueueSubmit)
MNG_CV_FN(QueueWriteBuffer)
MNG_CV_FN(QueueWriteTexture)
MNG_CV_FN(TextureCreateView)
MNG_CV_FN(BufferMapAsync)
MNG_CV_FN(BufferGetMappedRange)
MNG_CV_FN(BufferUnmap)
MNG_CV_FN(BindGroupRelease)
MNG_CV_FN(BindGroupLayoutRelease)
MNG_CV_FN(BufferRelease)
MNG_CV_FN(TextureViewRelease)
MNG_CV_FN(TextureRelease)
MNG_CV_FN(SamplerRelease)
MNG_CV_FN(RenderPipelineRelease)
MNG_CV_FN(CommandBufferRelease)

static int cv_syms_ready;
// 最近一次建画布失败的原因（mng_gpu_canvas_new 回 Err 时带出，诊断用）
static char g_cv_detail[256];
static void cv_set_detail(const char *s) {
  snprintf(g_cv_detail, sizeof g_cv_detail, "%s", s);
}
static int cv_load_syms(void) {
  if (cv_syms_ready) {
    return 1;
  }
  void *lib = mng_wgpu_lib();
  if (lib == NULL) {
    cv_set_detail("wgpu 库句柄为空（核心未就绪）");
    return 0;
  }
#define MNG_CV_LOAD(name)                                    \
  do {                                                       \
    p_wgpu##name = (WGPUProc##name)dlsym(lib, "wgpu" #name); \
    if (!p_wgpu##name) {                                     \
      cv_set_detail("缺符号 wgpu" #name);                     \
      return 0;                                              \
    }                                                        \
  } while (0)
  MNG_CV_LOAD(DeviceCreateTexture);
  MNG_CV_LOAD(DeviceCreateBuffer);
  MNG_CV_LOAD(DeviceCreateShaderModule);
  MNG_CV_LOAD(DeviceCreateRenderPipeline);
  MNG_CV_LOAD(DeviceCreateSampler);
  MNG_CV_LOAD(DeviceCreateBindGroup);
  MNG_CV_LOAD(DeviceCreateCommandEncoder);
  MNG_CV_LOAD(RenderPipelineGetBindGroupLayout);
  MNG_CV_LOAD(CommandEncoderBeginRenderPass);
  MNG_CV_LOAD(CommandEncoderCopyBufferToTexture);
  MNG_CV_LOAD(CommandEncoderCopyTextureToBuffer);
  MNG_CV_LOAD(CommandEncoderFinish);
  MNG_CV_LOAD(RenderPassEncoderSetPipeline);
  MNG_CV_LOAD(RenderPassEncoderSetBindGroup);
  MNG_CV_LOAD(RenderPassEncoderSetScissorRect);
  MNG_CV_LOAD(RenderPassEncoderSetVertexBuffer);
  MNG_CV_LOAD(RenderPassEncoderDraw);
  MNG_CV_LOAD(RenderPassEncoderEnd);
  MNG_CV_LOAD(QueueSubmit);
  MNG_CV_LOAD(QueueWriteBuffer);
  MNG_CV_LOAD(QueueWriteTexture);
  MNG_CV_LOAD(TextureCreateView);
  MNG_CV_LOAD(BufferMapAsync);
  MNG_CV_LOAD(BufferGetMappedRange);
  MNG_CV_LOAD(BufferUnmap);
  MNG_CV_LOAD(BindGroupRelease);
  MNG_CV_LOAD(BindGroupLayoutRelease);
  MNG_CV_LOAD(BufferRelease);
  MNG_CV_LOAD(TextureViewRelease);
  MNG_CV_LOAD(TextureRelease);
  MNG_CV_LOAD(SamplerRelease);
  MNG_CV_LOAD(RenderPipelineRelease);
  MNG_CV_LOAD(CommandBufferRelease);
#undef MNG_CV_LOAD
  cv_syms_ready = 1;
  return 1;
}

// 入口前向声明（new 的失败清理要调 free；free 定义在文件末）
void mng_gpu_canvas_free(int64_t h);

// ---- 每画布状态 ----
typedef struct {
  int w, h;
  WGPUTexture target;   // 离屏渲染目标（RENDER_ATTACHMENT|COPY_SRC）
  WGPUBuffer readback;  // MAP_READ|COPY_DST，w*h*4
  WGPUTexture upload;   // draw_texture_rgba 的源纹理（尺寸随输入变）
  int up_w, up_h;
  WGPUTextureView up_view;
  WGPUBindGroup tex_bind; // 采样器 + 上传视图（textured 管线用）
  WGPUBuffer vbuf;        // 顶点缓冲（每 draw 覆写，144B 上限）
  WGPUBuffer upbuf;       // 上传暂存（COPY_DST|COPY_SRC，尺寸随输入变）
  size_t upbuf_cap;
  WGPURenderPipeline pipe_tex;
  WGPURenderPipeline pipe_fill;
  WGPUSampler sampler;
  WGPUBindGroupLayout bgl_tex;
  WGPUBindGroupLayout bgl_fill;
  int alive;
} GpuCanvas;

#define MNG_CV_MAX 16
static GpuCanvas g_cv[MNG_CV_MAX];

static WGPUStringView cv_sv(const char *s) {
  WGPUStringView v;
  v.data = s;
  v.length = strlen(s);
  return v;
}

static const char CV_WGSL_TEX[] =
    "struct VOut {\n"
    "  @builtin(position) pos : vec4f,\n"
    "  @location(0) uv : vec2f,\n"
    "  @location(1) op : f32,\n"
    "}\n"
    "@group(0) @binding(1) var tx : texture_2d<f32>;\n"
    "@group(0) @binding(0) var samp : sampler;\n"
    "@vertex fn vs(@location(0) p : vec2f, @location(1) uv : vec2f, @location(2) op : f32) -> VOut {\n"
    "  var o : VOut;\n"
    "  o.pos = vec4f(p, 0.0, 1.0);\n"
    "  o.uv = uv;\n"
    "  o.op = op;\n"
    "  return o;\n"
    "}\n"
    "@fragment fn fs(in : VOut) -> @location(0) vec4f {\n"
    "  let c = textureSampleLevel(tx, samp, in.uv, 0.0);\n"
    // 直通 alpha 口径：rgb 不预乘、opacity 只乘 alpha（混合因子 SrcAlpha/
    // OneMinusSrcAlpha；rgb 再乘一次会把 opacity<1 的颜色二次压暗）
    "  return vec4f(c.rgb, c.a * in.op);\n"
    "}\n";

// solid quad：顶点属性 pos/rgba（opacity 折进顶点色 alpha）。
static const char CV_WGSL_FILL[] =
    "struct VOut {\n"
    "  @builtin(position) pos : vec4f,\n"
    "  @location(0) col : vec4f,\n"
    "}\n"
    "@vertex fn vs(@location(0) p : vec2f, @location(1) col : vec4f) -> VOut {\n"
    "  var o : VOut;\n"
    "  o.pos = vec4f(p, 0.0, 1.0);\n"
    "  o.col = col;\n"
    "  return o;\n"
    "}\n"
    "@fragment fn fs(in : VOut) -> @location(0) vec4f {\n"
    "  return in.col;\n"
    "}\n";


static WGPUBlendState cv_blend(void) {
  WGPUBlendState b;
  memset(&b, 0, sizeof b);
  b.color.srcFactor = WGPUBlendFactor_SrcAlpha;
  b.color.dstFactor = WGPUBlendFactor_OneMinusSrcAlpha;
  b.color.operation = WGPUBlendOperation_Add;
  b.alpha.srcFactor = WGPUBlendFactor_One;
  b.alpha.dstFactor = WGPUBlendFactor_OneMinusSrcAlpha;
  b.alpha.operation = WGPUBlendOperation_Add;
  return b;
}

// 画布坐标 → NDC（y 向下）
static void cv_ndc(const GpuCanvas *c, double x, double y, float *ox, float *oy) {
  *ox = (float)(x / (double)c->w * 2.0 - 1.0);
  *oy = (float)(1.0 - y / (double)c->h * 2.0);
}

// 建管线（顶点布局随管线不同：tex 三属性 stride 20 / fill 两属性 stride 24）
static WGPURenderPipeline cv_make_pipeline(const char *wgsl, int textured) {
  WGPUShaderSourceWGSL wsrc;
  memset(&wsrc, 0, sizeof wsrc);
  wsrc.chain.sType = WGPUSType_ShaderSourceWGSL;
  wsrc.code = cv_sv(wgsl);
  WGPUShaderModuleDescriptor smd;
  memset(&smd, 0, sizeof smd);
  smd.nextInChain = &wsrc.chain;
  WGPUShaderModule mod = p_wgpuDeviceCreateShaderModule(mng_wgpu_device(), &smd);
  if (mod == NULL) {
    return NULL;
  }
  WGPUVertexAttribute atts[3];
  memset(atts, 0, sizeof atts);
  size_t stride;
  size_t natts;
  if (textured) {
    atts[0].format = WGPUVertexFormat_Float32x2;
    atts[0].offset = 0;
    atts[0].shaderLocation = 0;
    atts[1].format = WGPUVertexFormat_Float32x2;
    atts[1].offset = 8;
    atts[1].shaderLocation = 1;
    atts[2].format = WGPUVertexFormat_Float32;
    atts[2].offset = 16;
    atts[2].shaderLocation = 2;
    stride = 20;
    natts = 3;
  } else {
    atts[0].format = WGPUVertexFormat_Float32x2;
    atts[0].offset = 0;
    atts[0].shaderLocation = 0;
    atts[1].format = WGPUVertexFormat_Float32x4;
    atts[1].offset = 8;
    atts[1].shaderLocation = 1;
    stride = 24;
    natts = 2;
  }
  WGPUVertexBufferLayout vbl;
  memset(&vbl, 0, sizeof vbl);
  vbl.arrayStride = stride;
  vbl.stepMode = WGPUVertexStepMode_Vertex;
  vbl.attributeCount = natts;
  vbl.attributes = atts;
  WGPUBlendState blend = cv_blend();
  WGPUColorTargetState ct;
  memset(&ct, 0, sizeof ct);
  ct.format = WGPUTextureFormat_BGRA8Unorm;
  ct.writeMask = WGPUColorWriteMask_All;
  ct.blend = &blend;
  WGPUFragmentState frag;
  memset(&frag, 0, sizeof frag);
  frag.module = mod;
  frag.entryPoint = cv_sv("fs");
  frag.targetCount = 1;
  frag.targets = &ct;
  WGPUVertexState vert;
  memset(&vert, 0, sizeof vert);
  vert.module = mod;
  vert.entryPoint = cv_sv("vs");
  vert.bufferCount = 1;
  vert.buffers = &vbl;
  WGPURenderPipelineDescriptor pd;
  memset(&pd, 0, sizeof pd);
  pd.vertex = vert;
  pd.primitive.topology = WGPUPrimitiveTopology_TriangleList;
  pd.primitive.frontFace = WGPUFrontFace_CCW;
  pd.primitive.cullMode = WGPUCullMode_None;
  pd.multisample.count = 1;
  pd.fragment = &frag;
  return p_wgpuDeviceCreateRenderPipeline(mng_wgpu_device(), &pd);
}

// 离屏目标 + 读回 buffer（尺寸变时重建）
static int cv_build_target(GpuCanvas *c) {
  WGPUTextureDescriptor td;
  memset(&td, 0, sizeof td);
  td.usage = WGPUTextureUsage_RenderAttachment | WGPUTextureUsage_CopySrc;
  td.dimension = WGPUTextureDimension_2D;
  td.size.width = (uint32_t)c->w;
  td.size.height = (uint32_t)c->h;
  td.size.depthOrArrayLayers = 1;
  td.format = WGPUTextureFormat_BGRA8Unorm;
  td.mipLevelCount = 1;
  td.sampleCount = 1;
  c->target = p_wgpuDeviceCreateTexture(mng_wgpu_device(), &td);
  if (c->target == NULL) {
    cv_set_detail("离屏目标建不出");
    return 0;
  }
  WGPUBufferDescriptor bd;
  memset(&bd, 0, sizeof bd);
  bd.usage = WGPUBufferUsage_MapRead | WGPUBufferUsage_CopyDst;
  // 读回 copy 的行距 256 对齐（与上传同规），buffer 要按垫行后大小分配
  int rbpr = ((c->w * 4 + 255) / 256) * 256;
  bd.size = (uint64_t)rbpr * (uint64_t)c->h;
  c->readback = p_wgpuDeviceCreateBuffer(mng_wgpu_device(), &bd);
  if (c->readback == NULL) {
    cv_set_detail("读回 buffer 建不出");
    return 0;
  }
  return 1;
}

// 上传纹理（draw_texture_rgba 的源；尺寸随输入变，变了才重建视图/bindgroup）
static int cv_build_upload(GpuCanvas *c, int w, int h) {
  if (c->upload != NULL && c->up_w == w && c->up_h == h) {
    return 1;
  }
  if (c->tex_bind != NULL) {
    p_wgpuBindGroupRelease(c->tex_bind);
    c->tex_bind = NULL;
  }
  if (c->up_view != NULL) {
    p_wgpuTextureViewRelease(c->up_view);
    c->up_view = NULL;
  }
  if (c->upload != NULL) {
    p_wgpuTextureRelease(c->upload);
    c->upload = NULL;
  }
  WGPUTextureDescriptor td;
  memset(&td, 0, sizeof td);
  td.usage = WGPUTextureUsage_TextureBinding | WGPUTextureUsage_CopyDst;
  td.dimension = WGPUTextureDimension_2D;
  td.size.width = (uint32_t)w;
  td.size.height = (uint32_t)h;
  td.size.depthOrArrayLayers = 1;
  // 上传源按 RGBA8Unorm：draw_texture_rgba 的入参是 RGBA 字节（trait 名与
  // @render.Bitmap::to_rgba_bytes 同口径）——存成 BGRA 会红蓝互换
  td.format = WGPUTextureFormat_RGBA8Unorm;
  td.mipLevelCount = 1;
  td.sampleCount = 1;
  c->upload = p_wgpuDeviceCreateTexture(mng_wgpu_device(), &td);
  if (c->upload == NULL) {
    return 0;
  }
  c->up_w = w;
  c->up_h = h;
  c->up_view = p_wgpuTextureCreateView(c->upload, NULL);
  if (c->up_view == NULL) {
    return 0;
  }
  WGPUBindGroupEntry es[2];
  memset(es, 0, sizeof es);
  es[0].binding = 0;
  es[0].sampler = c->sampler;
  es[1].binding = 1;
  es[1].textureView = c->up_view;
  WGPUBindGroupDescriptor bgd;
  memset(&bgd, 0, sizeof bgd);
  bgd.layout = c->bgl_tex;
  bgd.entryCount = 2;
  bgd.entries = es;
  c->tex_bind = p_wgpuDeviceCreateBindGroup(mng_wgpu_device(), &bgd);
  return c->tex_bind != NULL;
}

// 上传暂存 buffer（行距 256 对齐；尺寸随输入变）
static int cv_build_upbuf(GpuCanvas *c, size_t need) {
  if (c->upbuf != NULL && c->upbuf_cap >= need) {
    return 1;
  }
  if (c->upbuf != NULL) {
    p_wgpuBufferRelease(c->upbuf);
    c->upbuf = NULL;
    c->upbuf_cap = 0;
  }
  WGPUBufferDescriptor bd;
  memset(&bd, 0, sizeof bd);
  bd.usage = WGPUBufferUsage_CopyDst | WGPUBufferUsage_CopySrc;
  bd.size = need;
  c->upbuf = p_wgpuDeviceCreateBuffer(mng_wgpu_device(), &bd);
  if (c->upbuf == NULL) {
    return 0;
  }
  c->upbuf_cap = need;
  return 1;
}

// 一次 draw：一个 render pass（loadOp=Load 保留此前绘制），带 scissor clip。
// bind 可空（solid 管线无 bindgroup）。
static void cv_pass(GpuCanvas *c, WGPURenderPipeline pipe, WGPUBindGroup bind,
                    const void *verts, size_t vbytes, uint32_t nverts,
                    int has_clip, int cx, int cy, int cw, int ch) {
  WGPUCommandEncoder enc = p_wgpuDeviceCreateCommandEncoder(mng_wgpu_device(), NULL);
  if (enc == NULL) {
    return;
  }
  p_wgpuQueueWriteBuffer(mng_wgpu_queue(), c->vbuf, 0, verts, vbytes);
  WGPUTextureView view = p_wgpuTextureCreateView(c->target, NULL);
  if (view == NULL) {
    WGPUCommandBuffer junk = p_wgpuCommandEncoderFinish(enc, NULL);
    if (junk != NULL) {
      p_wgpuQueueSubmit(mng_wgpu_queue(), 1, &junk);
      p_wgpuCommandBufferRelease(junk);
    }
    return;
  }
  WGPURenderPassColorAttachment att;
  memset(&att, 0, sizeof att);
  att.view = view;
  att.loadOp = WGPULoadOp_Load;
  att.storeOp = WGPUStoreOp_Store;
  att.depthSlice = WGPU_DEPTH_SLICE_UNDEFINED;
  WGPURenderPassDescriptor rp;
  memset(&rp, 0, sizeof rp);
  rp.colorAttachmentCount = 1;
  rp.colorAttachments = &att;
  WGPURenderPassEncoder pass = p_wgpuCommandEncoderBeginRenderPass(enc, &rp);
  p_wgpuRenderPassEncoderSetPipeline(pass, pipe);
  p_wgpuRenderPassEncoderSetVertexBuffer(pass, 0, c->vbuf, 0, vbytes);
  if (bind != NULL) {
    p_wgpuRenderPassEncoderSetBindGroup(pass, 0, bind, 0, NULL);
  }
  if (has_clip && cx < c->w && cy < c->h) {
    if (cx < 0) cx = 0;
    if (cy < 0) cy = 0;
    if (cx + cw > c->w) cw = c->w - cx;
    if (cy + ch > c->h) ch = c->h - cy;
    if (cw > 0 && ch > 0) {
      p_wgpuRenderPassEncoderSetScissorRect(pass, (uint32_t)cx, (uint32_t)cy,
                                            (uint32_t)cw, (uint32_t)ch);
    }
  }
  p_wgpuRenderPassEncoderDraw(pass, nverts, 1, 0, 0);
  p_wgpuRenderPassEncoderEnd(pass);
  WGPUCommandBuffer cb = p_wgpuCommandEncoderFinish(enc, NULL);
  if (cb != NULL) {
    p_wgpuQueueSubmit(mng_wgpu_queue(), 1, &cb);
    p_wgpuCommandBufferRelease(cb);
  }
  p_wgpuTextureViewRelease(view);
}

// ---- mapAsync 读回（future 风格：回调 + ProcessEvents 泵） ----
static volatile int cv_map_got;
static WGPUMapAsyncStatus cv_map_status;
static void cv_on_map(WGPUMapAsyncStatus status, WGPUStringView message,
                      void *u1, void *u2) {
  (void)message;
  (void)u1;
  (void)u2;
  cv_map_status = status;
  cv_map_got = 1;
}

// ---- 对外入口（MoonBit extern） ----

// 建一块 w×h 的画布。失败回 0（没装 GPU 扩展/驱动起不来/尺寸非法）。
int64_t mng_gpu_canvas_new(int w, int h) {
  if (w < 1 || h < 1 || w > 8192 || h > 8192) {
    snprintf(g_cv_detail, sizeof g_cv_detail, "尺寸非法（%dx%d，上限 8192）", w,
             h);
    return 0;
  }
  if (!mng_wgpu_ready()) {
    char core[256];
    mng_wgpu_detail(core, (int)sizeof core);
    snprintf(g_cv_detail, sizeof g_cv_detail, "核心探测未就绪：%s", core);
    return 0;
  }
  if (!cv_load_syms()) {
    return 0; // cv_load_syms 已写 detail
  }
  int slot = -1;
  for (int i = 0; i < MNG_CV_MAX; i++) {
    if (!g_cv[i].alive) {
      slot = i;
      break;
    }
  }
  if (slot < 0) {
    cv_set_detail("画布槽位满");
    return 0;
  }
  GpuCanvas *c = &g_cv[slot];
  memset(c, 0, sizeof *c);
  c->w = w;
  c->h = h;
  c->alive = 1;
  WGPUSamplerDescriptor sd;
  memset(&sd, 0, sizeof sd);
  sd.addressModeU = WGPUAddressMode_ClampToEdge;
  sd.addressModeV = WGPUAddressMode_ClampToEdge;
  sd.addressModeW = WGPUAddressMode_ClampToEdge;
  sd.magFilter = WGPUFilterMode_Nearest;
  sd.minFilter = WGPUFilterMode_Nearest;
  // lod 钳制与各向异性：零值是验证错误（实测：wgpu-native 默认错误处理器
  // 直接 abort，core 里另挂了静默回调）
  sd.lodMinClamp = 0.0;
  sd.lodMaxClamp = 32.0;
  sd.maxAnisotropy = 1;
  c->sampler = p_wgpuDeviceCreateSampler(mng_wgpu_device(), &sd);
  WGPUBufferDescriptor bd;
  memset(&bd, 0, sizeof bd);
  // QueueWriteBuffer 要 COPY_DST（实测验证错误明说）；顶点缓冲另需 VERTEX
  bd.usage = WGPUBufferUsage_Vertex | WGPUBufferUsage_CopyDst |
             WGPUBufferUsage_CopySrc;
  bd.size = 144; // 两种顶点布局取大（fill：6×24）
  c->vbuf = p_wgpuDeviceCreateBuffer(mng_wgpu_device(), &bd);
  c->pipe_tex = cv_make_pipeline(CV_WGSL_TEX, 1);
  c->pipe_fill = cv_make_pipeline(CV_WGSL_FILL, 0);
  int built = 1;
  if (c->sampler == NULL) {
    cv_set_detail("sampler 建不出");
    built = 0;
  } else if (c->vbuf == NULL) {
    cv_set_detail("顶点缓冲建不出");
    built = 0;
  } else if (c->pipe_tex == NULL) {
    cv_set_detail("纹理管线建不出（shader/pipeline）");
    built = 0;
  } else if (c->pipe_fill == NULL) {
    cv_set_detail("纯色管线建不出（shader/pipeline）");
    built = 0;
  } else if (!cv_build_target(c)) {
    built = 0; // cv_build_target 已写 detail
  }
  if (!built) {
    mng_gpu_canvas_free((int64_t)slot + 1);
    return 0;
  }
  c->bgl_tex = p_wgpuRenderPipelineGetBindGroupLayout(c->pipe_tex, 0);
  c->bgl_fill = p_wgpuRenderPipelineGetBindGroupLayout(c->pipe_fill, 0);
  if (c->bgl_tex == NULL || c->bgl_fill == NULL) {
    cv_set_detail("bind group layout 拿不到");
    mng_gpu_canvas_free((int64_t)slot + 1);
    return 0;
  }
  return (int64_t)slot + 1;
}

// 改画布尺寸（重建离屏目标与读回 buffer；上传纹理按需重建）。
int mng_gpu_canvas_resize(int64_t h, int w, int hh) {
  if (h < 1 || h > MNG_CV_MAX || w < 1 || hh < 1 || w > 8192 || hh > 8192) {
    return 0;
  }
  GpuCanvas *c = &g_cv[h - 1];
  if (!c->alive) {
    return 0;
  }
  if (c->target != NULL) {
    p_wgpuTextureRelease(c->target);
    c->target = NULL;
  }
  if (c->readback != NULL) {
    p_wgpuBufferRelease(c->readback);
    c->readback = NULL;
  }
  c->w = w;
  c->h = hh;
  return cv_build_target(c);
}

// draw_texture_rgba：一帧 CPU RGBA（dw*dh*4，行优先）按 dst 贴出（画布坐标），
// clip 可裁，opacity 0..1。1 = 已入队；0 = 失败（调用方当没画）。
int mng_gpu_canvas_draw_texture(int64_t h, const uint8_t *data, int dw, int dh,
                                double dx, double dy, double dw2, double dh2,
                                int has_clip, double cx, double cy, double cw,
                                double ch, double opacity) {
  if (h < 1 || h > MNG_CV_MAX || data == NULL || dw < 1 || dh < 1) {
    return 0;
  }
  GpuCanvas *c = &g_cv[h - 1];
  if (!c->alive || !cv_build_upload(c, dw, dh)) {
    return 0;
  }
  // 上传：CPU → 暂存 buffer（行距 256 对齐垫行）→ 纹理
  int bpr = ((dw * 4 + 255) / 256) * 256;
  size_t need = (size_t)bpr * (size_t)dh;
  if (!cv_build_upbuf(c, need)) {
    return 0;
  }
  uint8_t *stage = (uint8_t *)malloc(need);
  if (stage == NULL) {
    return 0;
  }
  for (int y = 0; y < dh; y++) {
    memcpy(stage + (size_t)y * (size_t)bpr, data + (size_t)y * (size_t)dw * 4,
           (size_t)dw * 4);
  }
  p_wgpuQueueWriteBuffer(mng_wgpu_queue(), c->upbuf, 0, stage, need);
  free(stage);
  WGPUCommandEncoder enc = p_wgpuDeviceCreateCommandEncoder(mng_wgpu_device(), NULL);
  if (enc == NULL) {
    return 0;
  }
  WGPUTexelCopyBufferInfo src;
  memset(&src, 0, sizeof src);
  src.buffer = c->upbuf;
  src.layout.bytesPerRow = (uint32_t)bpr;
  src.layout.rowsPerImage = (uint32_t)dh;
  WGPUTexelCopyTextureInfo dst;
  memset(&dst, 0, sizeof dst);
  dst.texture = c->upload;
  dst.aspect = WGPUTextureAspect_All;
  WGPUExtent3D ext;
  ext.width = (uint32_t)dw;
  ext.height = (uint32_t)dh;
  ext.depthOrArrayLayers = 1;
  p_wgpuCommandEncoderCopyBufferToTexture(enc, &src, &dst, &ext);
  WGPUCommandBuffer cb = p_wgpuCommandEncoderFinish(enc, NULL);
  if (cb != NULL) {
    p_wgpuQueueSubmit(mng_wgpu_queue(), 1, &cb);
    p_wgpuCommandBufferRelease(cb);
  }
  // 六个顶点（两个三角形），属性 pos/uv/opacity。cv_ndc 把画布 y 向下映到
  // NDC y 向上，故 (dx,dy) 是上边、uv(0,0) 配位图首行（顶行），不翻。
  float x0, y0, x1, y1;
  cv_ndc(c, dx, dy, &x0, &y0);
  cv_ndc(c, dx + dw2, dy + dh2, &x1, &y1);
  float quad[6][5] = {
    {x0, y0, 0.0f, 0.0f, (float)opacity},
    {x1, y0, 1.0f, 0.0f, (float)opacity},
    {x0, y1, 0.0f, 1.0f, (float)opacity},
    {x1, y0, 1.0f, 0.0f, (float)opacity},
    {x1, y1, 1.0f, 1.0f, (float)opacity},
    {x0, y1, 0.0f, 1.0f, (float)opacity},
  };
  cv_pass(c, c->pipe_tex, c->tex_bind, quad, sizeof quad, 6, has_clip,
          (int)cx, (int)cy, (int)cw, (int)ch);
  return 1;
}

// fill_rect：纯色矩形（画布坐标），opacity 折进顶点色 alpha。1 = 已入队。
int mng_gpu_canvas_fill(int64_t h, double x, double y, double w, double hh,
                        double r, double g, double b, double a,
                        int has_clip, double cx, double cy, double cw,
                        double ch, double opacity) {
  if (h < 1 || h > MNG_CV_MAX) {
    return 0;
  }
  GpuCanvas *c = &g_cv[h - 1];
  if (!c->alive) {
    return 0;
  }
  float x0, y0, x1, y1;
  cv_ndc(c, x, y, &x0, &y0);
  cv_ndc(c, x + w, y + hh, &x1, &y1);
  float qa = (float)(a * opacity);
  float quad[6][6] = {
    {x0, y0, (float)r, (float)g, (float)b, qa},
    {x1, y0, (float)r, (float)g, (float)b, qa},
    {x0, y1, (float)r, (float)g, (float)b, qa},
    {x1, y0, (float)r, (float)g, (float)b, qa},
    {x1, y1, (float)r, (float)g, (float)b, qa},
    {x0, y1, (float)r, (float)g, (float)b, qa},
  };
  cv_pass(c, c->pipe_fill, NULL, quad, sizeof quad, 6, has_clip, (int)cx,
          (int)cy, (int)cw, (int)ch);
  return 1;
}

// finish：把离屏目标（BGRA8Unorm）读回成 BGRA 字节（w*h*4，行优先，与
// Bitmap 内存序同口径）写进 out（容量须 ≥ w*h*4）。1 = 成；0 = 失败。
int mng_gpu_canvas_finish(int64_t h, uint8_t *out, int cap) {
  if (h < 1 || h > MNG_CV_MAX || out == NULL) {
    return 0;
  }
  GpuCanvas *c = &g_cv[h - 1];
  if (!c->alive || c->target == NULL || c->readback == NULL) {
    return 0;
  }
  size_t need = (size_t)c->w * (size_t)c->h * 4u;
  if ((size_t)cap < need) {
    return 0;
  }
  int rbpr = ((c->w * 4 + 255) / 256) * 256;
  size_t map_bytes = (size_t)rbpr * (size_t)c->h;
  WGPUCommandEncoder enc = p_wgpuDeviceCreateCommandEncoder(mng_wgpu_device(), NULL);
  if (enc == NULL) {
    return 0;
  }
  WGPUTexelCopyTextureInfo src;
  memset(&src, 0, sizeof src);
  src.texture = c->target;
  src.aspect = WGPUTextureAspect_All;
  WGPUTexelCopyBufferInfo dst;
  memset(&dst, 0, sizeof dst);
  dst.buffer = c->readback;
  dst.layout.bytesPerRow = (uint32_t)rbpr;
  dst.layout.rowsPerImage = (uint32_t)c->h;
  WGPUExtent3D ext;
  ext.width = (uint32_t)c->w;
  ext.height = (uint32_t)c->h;
  ext.depthOrArrayLayers = 1;
  p_wgpuCommandEncoderCopyTextureToBuffer(enc, &src, &dst, &ext);
  WGPUCommandBuffer cb = p_wgpuCommandEncoderFinish(enc, NULL);
  if (cb == NULL) {
    return 0;
  }
  p_wgpuQueueSubmit(mng_wgpu_queue(), 1, &cb);
  p_wgpuCommandBufferRelease(cb);
  // mapAsync（future：回调 + ProcessEvents 泵，5s 超时）
  WGPUBufferMapCallbackInfo mcbi;
  memset(&mcbi, 0, sizeof mcbi);
  mcbi.mode = WGPUCallbackMode_AllowSpontaneous;
  mcbi.callback = cv_on_map;
  cv_map_got = 0;
  (void)p_wgpuBufferMapAsync(c->readback, WGPUMapMode_Read, 0, map_bytes, mcbi);
  int waited = 0;
  while (!cv_map_got && waited < 5000) {
    WGPUProcInstanceProcessEvents pe =
        (WGPUProcInstanceProcessEvents)dlsym(mng_wgpu_lib(),
                                             "wgpuInstanceProcessEvents");
    if (pe != NULL) {
      pe((WGPUInstance)mng_wgpu_instance());
    }
    if (cv_map_got) {
      break;
    }
    usleep(1000);
    waited += 1;
  }
  if (!cv_map_got || cv_map_status != WGPUMapAsyncStatus_Success) {
    return 0;
  }
  void *range = p_wgpuBufferGetMappedRange(c->readback, 0, map_bytes);
  if (range == NULL) {
    p_wgpuBufferUnmap(c->readback);
    return 0;
  }
  // 逐行解垫：buffer 里行距是 rbpr（256 对齐），输出要收紧到 w*4
  const unsigned char *rows = (const unsigned char *)range;
  for (int y = 0; y < c->h; y++) {
    memcpy(out + (size_t)y * (size_t)c->w * 4u,
           rows + (size_t)y * (size_t)rbpr, (size_t)c->w * 4u);
  }
  p_wgpuBufferUnmap(c->readback);
  return 1;
}


void mng_gpu_canvas_free(int64_t h) {
  if (h < 1 || h > MNG_CV_MAX) {
    return;
  }
  GpuCanvas *c = &g_cv[h - 1];
  if (!c->alive) {
    return;
  }
  if (c->tex_bind != NULL) p_wgpuBindGroupRelease(c->tex_bind);
  if (c->up_view != NULL) p_wgpuTextureViewRelease(c->up_view);
  if (c->upload != NULL) p_wgpuTextureRelease(c->upload);
  if (c->upbuf != NULL) p_wgpuBufferRelease(c->upbuf);
  if (c->vbuf != NULL) p_wgpuBufferRelease(c->vbuf);
  if (c->readback != NULL) p_wgpuBufferRelease(c->readback);
  if (c->target != NULL) p_wgpuTextureRelease(c->target);
  if (c->sampler != NULL) p_wgpuSamplerRelease(c->sampler);
  if (c->pipe_tex != NULL) p_wgpuRenderPipelineRelease(c->pipe_tex);
  if (c->pipe_fill != NULL) p_wgpuRenderPipelineRelease(c->pipe_fill);
  if (c->bgl_tex != NULL) p_wgpuBindGroupLayoutRelease(c->bgl_tex);
  if (c->bgl_fill != NULL) p_wgpuBindGroupLayoutRelease(c->bgl_fill);
  memset(c, 0, sizeof *c);
}

// 最近一次 mng_gpu_canvas_new 失败的原因（成功路径不动它；零终止串）
void mng_gpu_canvas_detail(char *out, int cap) {
  if (out == NULL || cap <= 0) {
    return;
  }
  int n = (int)strlen(g_cv_detail);
  if (n > cap - 1) {
    n = cap - 1;
  }
  memcpy(out, g_cv_detail, (size_t)n);
  out[n] = 0;
}

#else /* 没有 wgpu vendor 头：整文件退化成「不可用」桩 */

int64_t mng_gpu_canvas_new(int w, int h) {
  (void)w;
  (void)h;
  return 0;
}
int mng_gpu_canvas_resize(int64_t h, int w, int hh) {
  (void)h;
  (void)w;
  (void)hh;
  return 0;
}
int mng_gpu_canvas_draw_texture(int64_t h, const uint8_t *data, int dw, int dh,
                                double dx, double dy, double dw2, double dh2,
                                int has_clip, double cx, double cy, double cw,
                                double ch, double opacity) {
  (void)h; (void)data; (void)dw; (void)dh; (void)dx; (void)dy; (void)dw2;
  (void)dh2; (void)has_clip; (void)cx; (void)cy; (void)cw; (void)ch;
  (void)opacity;
  return 0;
}
int mng_gpu_canvas_fill(int64_t h, double x, double y, double w, double hh,
                        double r, double g, double b, double a, int has_clip,
                        double cx, double cy, double cw, double ch,
                        double opacity) {
  (void)h; (void)x; (void)y; (void)w; (void)hh; (void)r; (void)g; (void)b;
  (void)a; (void)has_clip; (void)cx; (void)cy; (void)cw; (void)ch;
  (void)opacity;
  return 0;
}
int mng_gpu_canvas_finish(int64_t h, uint8_t *out, int cap) {
  (void)h;
  (void)out;
  (void)cap;
  return 0;
}
void mng_gpu_canvas_free(int64_t h) {
  (void)h;
}
void mng_gpu_canvas_detail(char *out, int cap) {
  if (out == NULL || cap <= 0) {
    return;
  }
  const char *s = "unsupported: 没编进 wgpu vendor 头";
  int n = (int)strlen(s);
  if (n > cap - 1) {
    n = cap - 1;
  }
  memcpy(out, s, (size_t)n);
  out[n] = 0;
}

#endif /* MNG_CANVAS_REAL */
