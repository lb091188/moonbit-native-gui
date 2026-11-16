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

// POSIX 装载/等待的跨平台 shim（Win32 用 LoadLibrary 族 / Sleep）
#if defined(_WIN32)
#include <windows.h>
#define MNG_CV_DLSYM(h, n) ((void *)GetProcAddress((HMODULE)(h), (n)))
#define MNG_CV_SLEEP_1MS() Sleep(1)
#else
#include <unistd.h> // usleep（mapAsync 泵）
#include <dlfcn.h>  // dlsym（符号表装载与 DBG 自建 device）
#define MNG_CV_DLSYM(h, n) dlsym((h), (n))
#define MNG_CV_SLEEP_1MS() usleep(1000)
#endif

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
// 3D 帧面（方案 gpu-architecture.md「GPU 内容画布」）：索引绘制 + 资源释放 +
// 未提交 encoder 的弃置
MNG_CV_FN(RenderPassEncoderSetIndexBuffer)
MNG_CV_FN(RenderPassEncoderDrawIndexed)
MNG_CV_FN(RenderPassEncoderRelease)
MNG_CV_FN(ShaderModuleRelease)
MNG_CV_FN(CommandEncoderRelease)
// 错误范围（v29 校验失败给无效句柄不回 NULL——错误经 scope 才可感知）
MNG_CV_FN(DevicePushErrorScope)
MNG_CV_FN(DevicePopErrorScope)

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
#define MNG_CV_LOAD(name)                                            \
  do {                                                               \
    p_wgpu##name = (WGPUProc##name)MNG_CV_DLSYM(lib, "wgpu" #name);  \
    if (!p_wgpu##name) {                                             \
      cv_set_detail("缺符号 wgpu" #name);                            \
      return 0;                                                      \
    }                                                                \
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
  MNG_CV_LOAD(RenderPassEncoderSetIndexBuffer);
  MNG_CV_LOAD(RenderPassEncoderDrawIndexed);
  MNG_CV_LOAD(RenderPassEncoderRelease);
  MNG_CV_LOAD(ShaderModuleRelease);
  MNG_CV_LOAD(CommandEncoderRelease);
  MNG_CV_LOAD(DevicePushErrorScope);
  MNG_CV_LOAD(DevicePopErrorScope);
#undef MNG_CV_LOAD
  cv_syms_ready = 1;
  return 1;
}

// 入口前向声明（new 的失败清理要调 free；free 定义在文件末）
void mng_gpu_canvas_free(int64_t h);

// ---- 错误范围（v29 校验失败给无效句柄不回 NULL——错误经 scope 才可感知）----
// push/pop 包住 shader / 管线 / bind group 的创建，弹出时泵 ProcessEvents
// 等回调；有校验错误就把 wgpu 的诊断写进 canvas_detail 通道。
static volatile int g_scope_got;
static int g_scope_type; // WGPUErrorType（NoError = 干净）
static char g_scope_msg[512];
static void cv_on_scope(WGPUPopErrorScopeStatus status, WGPUErrorType type,
                        WGPUStringView message, void *u1, void *u2) {
  (void)u1;
  (void)u2;
  if (status == WGPUPopErrorScopeStatus_Success) {
    g_scope_type = (int)type;
    snprintf(g_scope_msg, sizeof g_scope_msg, "%.*s", (int)message.length,
             message.data ? message.data : "");
  } else {
    g_scope_type = (int)WGPUErrorType_Internal;
    snprintf(g_scope_msg, sizeof g_scope_msg, "error scope 弹出失败 status=%d",
             (int)status);
  }
  g_scope_got = 1;
}

static void cv_scope_push(void) {
  g_scope_got = 0;
  g_scope_type = (int)WGPUErrorType_NoError;
  g_scope_msg[0] = 0;
  p_wgpuDevicePushErrorScope(mng_wgpu_device(), WGPUErrorFilter_Validation);
}

// 弹出并等回调。1 = 范围内有校验错误（诊断在 g_scope_msg / canvas_detail）。
static int cv_scope_pop_check(void) {
  WGPUPopErrorScopeCallbackInfo ci;
  memset(&ci, 0, sizeof ci);
  ci.mode = WGPUCallbackMode_AllowSpontaneous;
  ci.callback = cv_on_scope;
  p_wgpuDevicePopErrorScope(mng_wgpu_device(), ci);
  int waited = 0;
  while (!g_scope_got && waited < 5000) {
    WGPUProcInstanceProcessEvents pe =
        (WGPUProcInstanceProcessEvents)MNG_CV_DLSYM(mng_wgpu_lib(),
                                                    "wgpuInstanceProcessEvents");
    if (pe != NULL) {
      pe((WGPUInstance)mng_wgpu_instance());
    }
    if (g_scope_got) {
      break;
    }
    MNG_CV_SLEEP_1MS();
    waited += 1;
  }
  if (!g_scope_got) {
    g_scope_type = (int)WGPUErrorType_Internal;
    snprintf(g_scope_msg, sizeof g_scope_msg, "error scope 回调超时");
  }
  if (g_scope_type != (int)WGPUErrorType_NoError) {
    cv_set_detail(g_scope_msg[0] ? g_scope_msg : "范围内有校验错误");
    return 1;
  }
  return 0;
}

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
  // 3D 帧面：深度附件 + 开帧期间的三件（pass/encoder/view）。end 时 pass
  // 结束、encoder finish+submit、view 释放；finish 对开着的帧先自动收口。
  WGPUTexture depth_tex;            // Depth24Plus（RENDER_ATTACHMENT，随目标尺寸）
  WGPUTextureView depth_view;
  WGPURenderPassEncoder frame_pass;
  WGPUCommandEncoder frame_enc;
  WGPUTextureView frame_view;
  int frame_open;
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
  // C 桩 memset 吃不到头文件默认值：mask 默认应为 0xFFFFFFFF，清零后所有
  // 样本被遮掉，draw 一条像素都不出（clear 不受影响，读回只剩底色）
  pd.multisample.mask = 0xFFFFFFFFu;
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

// 深度附件（Depth24Plus，RENDER_ATTACHMENT；尺寸随目标，resize 已丢弃重建）。
static int cv_build_depth(GpuCanvas *c) {
  if (c->depth_tex != NULL && c->depth_view != NULL) {
    return 1;
  }
  if (c->depth_view != NULL) {
    p_wgpuTextureViewRelease(c->depth_view);
    c->depth_view = NULL;
  }
  if (c->depth_tex != NULL) {
    p_wgpuTextureRelease(c->depth_tex);
    c->depth_tex = NULL;
  }
  WGPUTextureDescriptor td;
  memset(&td, 0, sizeof td);
  td.usage = WGPUTextureUsage_RenderAttachment;
  td.dimension = WGPUTextureDimension_2D;
  td.size.width = (uint32_t)c->w;
  td.size.height = (uint32_t)c->h;
  td.size.depthOrArrayLayers = 1;
  td.format = WGPUTextureFormat_Depth24Plus;
  td.mipLevelCount = 1;
  td.sampleCount = 1;
  c->depth_tex = p_wgpuDeviceCreateTexture(mng_wgpu_device(), &td);
  if (c->depth_tex == NULL) {
    cv_set_detail("深度附件建不出");
    return 0;
  }
  c->depth_view = p_wgpuTextureCreateView(c->depth_tex, NULL);
  return c->depth_view != NULL;
}

// 开帧中途弃置（resize/free 时的收场）：pass 未 End 直接释放、encoder 未
// Finish 直接释放、视图释放——已录指令一并弃掉，不上屏。
static void cv_frame_cancel(GpuCanvas *c) {
  if (c->frame_pass != NULL) {
    p_wgpuRenderPassEncoderRelease(c->frame_pass);
    c->frame_pass = NULL;
  }
  if (c->frame_enc != NULL) {
    p_wgpuCommandEncoderRelease(c->frame_enc);
    c->frame_enc = NULL;
  }
  if (c->frame_view != NULL) {
    p_wgpuTextureViewRelease(c->frame_view);
    c->frame_view = NULL;
  }
  c->frame_open = 0;
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

// ---- 3D 帧面（方案 gpu-architecture.md「GPU 内容画布」）----
// 薄壳原始接口：全部转调 wgpu_core 装好的符号，C 侧只补「结构体组装」——
// 管线描述符用 builder 增量外呼避开结构体封送；句柄一律 int64 原样透传，
// 应用可拿句柄经 GpuCanvas::lib() dlsym 自行扩展薄壳没覆盖的 webgpu.h 面。

// 管线 builder 临时态（一次一个；pipe_begin 重置）。顶点缓冲上限 8、
// 每缓冲属性上限 16——与 WebGPU 单管线默认上限同量级。
#define MNG_PB_MAX_VBL 8
#define MNG_PB_MAX_ATT 16
static WGPUShaderModule g_pb_mod;
static WGPUVertexBufferLayout g_pb_vbl[MNG_PB_MAX_VBL];
static WGPUVertexAttribute g_pb_att[MNG_PB_MAX_VBL][MNG_PB_MAX_ATT];
static int g_pb_nvbl;
static int g_pb_att_n[MNG_PB_MAX_VBL];
static int g_pb_topology, g_pb_cull, g_pb_front, g_pb_blend;
static int g_pb_depth, g_pb_depth_write, g_pb_depth_compare;

// 管线 builder 开始：建 shader module、记原始态。字符串按 (指针, 长度) 传，
// 调用方（MoonBit）给 UTF-8 Bytes 与长度。1 = shader 建成。
int mng_gpu_canvas_pipe_begin(int64_t h, const uint8_t *wgsl, int wgsl_len,
                              const char *vs_entry, int vs_len,
                              const char *fs_entry, int fs_len, int topology,
                              int cull, int front, int blend, int depth_write,
                              int depth_compare, int depth) {
  (void)h;
  memset(&g_pb_vbl, 0, sizeof g_pb_vbl);
  memset(&g_pb_att, 0, sizeof g_pb_att);
  memset(&g_pb_att_n, 0, sizeof g_pb_att_n);
  g_pb_nvbl = 0;
  g_pb_topology = topology;
  g_pb_cull = cull;
  g_pb_front = front;
  g_pb_blend = blend;
  g_pb_depth = depth;
  g_pb_depth_write = depth_write;
  g_pb_depth_compare = depth_compare;
  g_pb_mod = NULL;
  if (!mng_wgpu_ready() || !cv_load_syms()) {
    return 0;
  }
  if (wgsl == NULL || wgsl_len <= 0) {
    cv_set_detail("WGSL 为空");
    return 0;
  }
  cv_scope_push();
  WGPUShaderSourceWGSL wsrc;
  memset(&wsrc, 0, sizeof wsrc);
  wsrc.chain.sType = WGPUSType_ShaderSourceWGSL;
  wsrc.code.data = (const char *)wgsl;
  wsrc.code.length = (size_t)wgsl_len;
  WGPUShaderModuleDescriptor smd;
  memset(&smd, 0, sizeof smd);
  smd.nextInChain = &wsrc.chain;
  g_pb_mod = p_wgpuDeviceCreateShaderModule(mng_wgpu_device(), &smd);
  if (g_pb_mod == NULL) {
    cv_set_detail("shader module 建不出（WGSL 编译失败或后端不支持）");
    return 0;
  }
  (void)vs_entry;
  (void)vs_len;
  (void)fs_entry;
  (void)fs_len;
  return 1;
}

// 追加一个顶点缓冲布局（属性随后逐个 attr 追加）。回缓冲序号，-1 = 越界。
int mng_gpu_canvas_pipe_buffer(int64_t h, int64_t stride, int step_mode) {
  (void)h;
  if (g_pb_mod == NULL || g_pb_nvbl >= MNG_PB_MAX_VBL) {
    return -1;
  }
  int idx = g_pb_nvbl++;
  g_pb_vbl[idx].arrayStride = (uint64_t)stride;
  g_pb_vbl[idx].stepMode = (WGPUVertexStepMode)step_mode;
  g_pb_vbl[idx].attributeCount = 0;
  g_pb_vbl[idx].attributes = g_pb_att[idx];
  g_pb_att_n[idx] = 0;
  return idx;
}

// 向最近一个顶点缓冲布局追加属性。-1 = 没有打开的布局或越界。
int mng_gpu_canvas_pipe_attr(int64_t h, int location, int format,
                             int64_t offset) {
  (void)h;
  int idx = g_pb_nvbl - 1;
  if (g_pb_mod == NULL || idx < 0 || g_pb_att_n[idx] >= MNG_PB_MAX_ATT) {
    return -1;
  }
  int n = g_pb_att_n[idx]++;
  g_pb_att[idx][n].shaderLocation = (uint32_t)location;
  g_pb_att[idx][n].format = (WGPUVertexFormat)format;
  g_pb_att[idx][n].offset = (uint64_t)offset;
  return n;
}

// 管线 builder 收口：组描述符建管线。回句柄，0 = 建不出（builder 未开/
// 验证错误——core 挂的静默错误回调吃掉诊断，见 wgpu_core 注释）。
int64_t mng_gpu_canvas_pipe_end(int64_t h) {
  (void)h;
  if (g_pb_mod == NULL) {
    return 0;
  }
  WGPURenderPipeline pipe = NULL;
  for (int i = 0; i < g_pb_nvbl; i++) {
    g_pb_vbl[i].attributeCount = (uint32_t)g_pb_att_n[i];
  }
  WGPUBlendState blend;
  memset(&blend, 0, sizeof blend);
  WGPUPrimitiveState prim;
  memset(&prim, 0, sizeof prim);
  prim.topology = (WGPUPrimitiveTopology)g_pb_topology;
  prim.frontFace = (WGPUFrontFace)g_pb_front;
  prim.cullMode = (WGPUCullMode)g_pb_cull;
  WGPUColorTargetState ct;
  memset(&ct, 0, sizeof ct);
  ct.format = WGPUTextureFormat_BGRA8Unorm;
  ct.writeMask = WGPUColorWriteMask_All;
  if (g_pb_blend) {
    blend.color.srcFactor = WGPUBlendFactor_SrcAlpha;
    blend.color.dstFactor = WGPUBlendFactor_OneMinusSrcAlpha;
    blend.color.operation = WGPUBlendOperation_Add;
    blend.alpha.srcFactor = WGPUBlendFactor_One;
    blend.alpha.dstFactor = WGPUBlendFactor_OneMinusSrcAlpha;
    blend.alpha.operation = WGPUBlendOperation_Add;
    ct.blend = &blend;
  }
  WGPUFragmentState frag;
  memset(&frag, 0, sizeof frag);
  frag.module = g_pb_mod;
  frag.entryPoint = cv_sv("fs");
  frag.targetCount = 1;
  frag.targets = &ct;
  WGPUVertexState vert;
  memset(&vert, 0, sizeof vert);
  vert.module = g_pb_mod;
  vert.entryPoint = cv_sv("vs");
  // 空布局合法：@builtin(vertex_index) 全屏三角形这类顶点着色器不消费
  // 顶点缓冲，bufferCount=0 即可
  vert.bufferCount = (uint32_t)g_pb_nvbl;
  vert.buffers = g_pb_nvbl > 0 ? g_pb_vbl : NULL;
  WGPURenderPipelineDescriptor pd;
  memset(&pd, 0, sizeof pd);
  pd.vertex = vert;
  pd.primitive = prim;
  pd.multisample.count = 1;
  // C 桩 memset 吃不到头文件默认值：mask 默认应为 0xFFFFFFFF，清零后所有
  // 样本被遮掉，draw 一条像素都不出（canvas 内建管线同坑，实测已修）
  pd.multisample.mask = 0xFFFFFFFFu;
  WGPUDepthStencilState ds;
  memset(&ds, 0, sizeof ds);
  if (g_pb_depth) {
    ds.format = WGPUTextureFormat_Depth24Plus;
    ds.depthWriteEnabled = g_pb_depth_write ? WGPUOptionalBool_True
                                            : WGPUOptionalBool_False;
    ds.depthCompare = (WGPUCompareFunction)g_pb_depth_compare;
    pd.depthStencil = &ds;
  }
  pd.fragment = &frag;
  pipe = p_wgpuDeviceCreateRenderPipeline(mng_wgpu_device(), &pd);
  int bad = cv_scope_pop_check();
  p_wgpuShaderModuleRelease(g_pb_mod);
  g_pb_mod = NULL;
  if (bad) {
    return 0;
  }
  if (pipe == NULL) {
    cv_set_detail("管线建不出（布局/入口/验证错误，见 WGSL 与属性表）");
    return 0;
  }
  return (int64_t)(uintptr_t)pipe;
}

// bind group builder 临时态（一次一个；bind_begin 重置）。layout 不归
// builder 所有（来自 pipeline_bgl 或应用自建），收口不动它。
#define MNG_BG_MAX 8
static WGPUBindGroupLayout g_bg_layout;
static WGPUBindGroupEntry g_bg_ent[MNG_BG_MAX];
static int g_bg_n;

// bind group builder 开始：记 layout（裸句柄）。
int mng_gpu_canvas_bind_begin(int64_t h, int64_t layout) {
  (void)h;
  memset(&g_bg_ent, 0, sizeof g_bg_ent);
  g_bg_n = 0;
  g_bg_layout = NULL;
  if (!mng_wgpu_ready() || !cv_load_syms() || layout == 0) {
    return 0;
  }
  cv_scope_push();
  g_bg_layout = (WGPUBindGroupLayout)(uintptr_t)layout;
  return 1;
}

// 追加一个 buffer 条目；size 0 = WGPU_WHOLE_SIZE（整段缓冲）。
int mng_gpu_canvas_bind_buffer(int64_t h, int binding, int64_t buffer,
                               int64_t offset, int64_t size) {
  (void)h;
  if (g_bg_layout == NULL || g_bg_n >= MNG_BG_MAX || buffer == 0) {
    return 0;
  }
  int n = g_bg_n++;
  g_bg_ent[n].binding = (uint32_t)binding;
  g_bg_ent[n].buffer = (WGPUBuffer)(uintptr_t)buffer;
  g_bg_ent[n].offset = (uint64_t)offset;
  g_bg_ent[n].size = size == 0 ? (uint64_t)WGPU_WHOLE_SIZE : (uint64_t)size;
  return 1;
}

// bind group builder 收口。回句柄，0 = 建不出。
int64_t mng_gpu_canvas_bind_end(int64_t h) {
  (void)h;
  if (g_bg_layout == NULL || g_bg_n == 0) {
    g_bg_layout = NULL;
    return 0;
  }
  WGPUBindGroupDescriptor bgd;
  memset(&bgd, 0, sizeof bgd);
  bgd.layout = g_bg_layout;
  bgd.entryCount = (uint32_t)g_bg_n;
  bgd.entries = g_bg_ent;
  g_bg_layout = NULL;
  WGPUBindGroup bg = p_wgpuDeviceCreateBindGroup(mng_wgpu_device(), &bgd);
  int bad = cv_scope_pop_check();
  if (bad || bg == NULL) {
    if (!bad) {
      cv_set_detail("bind group 建不出（layout/条目不匹配）");
    }
    return 0;
  }
  return (int64_t)(uintptr_t)bg;
}

// ---- 3D 帧面的资源与句柄薄壳 ----

// 建 shader module（WGSL UTF-8）。回句柄，0 = 建不出（WGSL 解析错误经
// error scope 捕获，诊断在 canvas_detail）。
int64_t mng_gpu_canvas_shader_new(int64_t h, const uint8_t *wgsl, int len) {
  (void)h;
  if (!mng_wgpu_ready() || !cv_load_syms() || wgsl == NULL || len <= 0) {
    return 0;
  }
  cv_scope_push();
  WGPUShaderSourceWGSL wsrc;
  memset(&wsrc, 0, sizeof wsrc);
  wsrc.chain.sType = WGPUSType_ShaderSourceWGSL;
  wsrc.code.data = (const char *)wgsl;
  wsrc.code.length = (size_t)len;
  WGPUShaderModuleDescriptor smd;
  memset(&smd, 0, sizeof smd);
  smd.nextInChain = &wsrc.chain;
  WGPUShaderModule mod = p_wgpuDeviceCreateShaderModule(mng_wgpu_device(), &smd);
  int bad = cv_scope_pop_check();
  if (bad || mod == NULL) {
    return 0;
  }
  return (int64_t)(uintptr_t)mod;
}

// 建缓冲（size 字节，usage 是 WGPUBufferUsage 位值）。回句柄，0 = 建不出。
int64_t mng_gpu_canvas_buffer_new(int64_t h, int64_t size, int64_t usage) {
  (void)h;
  if (!mng_wgpu_ready() || !cv_load_syms() || size <= 0) {
    return 0;
  }
  WGPUBufferDescriptor bd;
  memset(&bd, 0, sizeof bd);
  bd.size = (uint64_t)size;
  bd.usage = (WGPUBufferUsage)usage;
  WGPUBuffer buf = p_wgpuDeviceCreateBuffer(mng_wgpu_device(), &bd);
  return (int64_t)(uintptr_t)buf;
}

// 写缓冲（QueueWriteBuffer；offset 与 len 须 4 字节对齐——WebGPU 硬规）。
int mng_gpu_canvas_buffer_write(int64_t h, int64_t buffer, int64_t offset,
                                const uint8_t *data, int len) {
  (void)h;
  if (!mng_wgpu_ready() || !cv_load_syms() || buffer == 0 || data == NULL ||
      len <= 0 || (offset % 4) != 0 || (len % 4) != 0) {
    return 0;
  }
  p_wgpuQueueWriteBuffer(mng_wgpu_queue(), (WGPUBuffer)(uintptr_t)buffer,
                         (uint64_t)offset, data, (size_t)len);
  return 1;
}

// 管线的 bind group layout（组号 group）。回句柄，0 = 拿不到。
int64_t mng_gpu_canvas_pipeline_bgl(int64_t h, int64_t pipeline, int group) {
  (void)h;
  if (!mng_wgpu_ready() || !cv_load_syms() || pipeline == 0 || group < 0) {
    return 0;
  }
  WGPUBindGroupLayout bgl = p_wgpuRenderPipelineGetBindGroupLayout(
      (WGPURenderPipeline)(uintptr_t)pipeline, (uint32_t)group);
  return (int64_t)(uintptr_t)bgl;
}

int mng_gpu_canvas_release_buffer(int64_t h, int64_t res) {
  (void)h;
  if (res == 0 || !cv_load_syms()) {
    return 0;
  }
  p_wgpuBufferRelease((WGPUBuffer)(uintptr_t)res);
  return 1;
}

int mng_gpu_canvas_release_shader(int64_t h, int64_t res) {
  (void)h;
  if (res == 0 || !cv_load_syms()) {
    return 0;
  }
  p_wgpuShaderModuleRelease((WGPUShaderModule)(uintptr_t)res);
  return 1;
}

int mng_gpu_canvas_release_pipeline(int64_t h, int64_t res) {
  (void)h;
  if (res == 0 || !cv_load_syms()) {
    return 0;
  }
  p_wgpuRenderPipelineRelease((WGPURenderPipeline)(uintptr_t)res);
  return 1;
}

int mng_gpu_canvas_release_bind_group(int64_t h, int64_t res) {
  (void)h;
  if (res == 0 || !cv_load_syms()) {
    return 0;
  }
  p_wgpuBindGroupRelease((WGPUBindGroup)(uintptr_t)res);
  return 1;
}

// ---- 3D 帧生命周期 ----

// 开帧：color loadOp = Clear（has_clear）或 Load（保留既有像素）；depth
// 时挂 Depth24Plus 附件（Clear 到 1.0，storeOp=Discard——深度只在 pass
// 内比较用，跨帧不留）。1 = 开成；0 = 失败（已开帧/画布失效/建不出）。
int mng_gpu_canvas_frame_begin(int64_t h, int has_clear, double r, double g,
                               double b, double a, int depth) {
  if (h < 1 || h > MNG_CV_MAX) {
    return 0;
  }
  GpuCanvas *c = &g_cv[h - 1];
  if (!c->alive || c->target == NULL) {
    return 0;
  }
  if (c->frame_open) {
    cv_set_detail("已有开着的帧（end 后才能再开）");
    return 0;
  }
  if (!cv_load_syms()) {
    return 0;
  }
  WGPUTextureView view = p_wgpuTextureCreateView(c->target, NULL);
  if (view == NULL) {
    cv_set_detail("目标视图建不出");
    return 0;
  }
  WGPUCommandEncoder enc = p_wgpuDeviceCreateCommandEncoder(mng_wgpu_device(), NULL);
  if (enc == NULL) {
    p_wgpuTextureViewRelease(view);
    cv_set_detail("command encoder 建不出");
    return 0;
  }
  if (depth && !cv_build_depth(c)) {
    p_wgpuCommandEncoderRelease(enc);
    p_wgpuTextureViewRelease(view);
    return 0; // cv_build_depth 已写 detail
  }
  WGPURenderPassColorAttachment att;
  memset(&att, 0, sizeof att);
  att.view = view;
  att.loadOp = has_clear ? WGPULoadOp_Clear : WGPULoadOp_Load;
  att.storeOp = WGPUStoreOp_Store;
  att.depthSlice = WGPU_DEPTH_SLICE_UNDEFINED;
  att.clearValue.r = r;
  att.clearValue.g = g;
  att.clearValue.b = b;
  att.clearValue.a = a;
  WGPURenderPassDescriptor rp;
  memset(&rp, 0, sizeof rp);
  rp.colorAttachmentCount = 1;
  rp.colorAttachments = &att;
  WGPURenderPassDepthStencilAttachment datt;
  if (depth) {
    memset(&datt, 0, sizeof datt);
    datt.view = c->depth_view;
    datt.depthLoadOp = WGPULoadOp_Clear;
    datt.depthClearValue = 1.0f;
    datt.depthReadOnly = 0;
    datt.depthStoreOp = WGPUStoreOp_Discard;
    rp.depthStencilAttachment = &datt;
  }
  WGPURenderPassEncoder pass = p_wgpuCommandEncoderBeginRenderPass(enc, &rp);
  if (pass == NULL) {
    p_wgpuCommandEncoderRelease(enc);
    p_wgpuTextureViewRelease(view);
    cv_set_detail("render pass 开不出");
    return 0;
  }
  c->frame_pass = pass;
  c->frame_enc = enc;
  c->frame_view = view;
  c->frame_open = 1;
  return 1;
}

// 开帧期间的 pass / 目标视图 / 深度视图句柄（应用经 lib() dlsym 直调
// 薄壳没覆盖的 render pass 方法时用；未开帧回 0）。
int64_t mng_gpu_canvas_frame_pass(int64_t h) {
  if (h < 1 || h > MNG_CV_MAX || !g_cv[h - 1].alive || !g_cv[h - 1].frame_open) {
    return 0;
  }
  return (int64_t)(uintptr_t)g_cv[h - 1].frame_pass;
}

int64_t mng_gpu_canvas_frame_target_view(int64_t h) {
  if (h < 1 || h > MNG_CV_MAX || !g_cv[h - 1].alive || !g_cv[h - 1].frame_open) {
    return 0;
  }
  return (int64_t)(uintptr_t)g_cv[h - 1].frame_view;
}

int64_t mng_gpu_canvas_frame_depth_view(int64_t h) {
  if (h < 1 || h > MNG_CV_MAX || !g_cv[h - 1].alive || !g_cv[h - 1].frame_open) {
    return 0;
  }
  return (int64_t)(uintptr_t)g_cv[h - 1].depth_view;
}

// 收帧：End pass + finish encoder + submit。**提交在此发生**——开帧期间
// 的 3D 指令随 end 入队，与 2D 原语（各自即时提交）按调用序排布。1 = 收成。
// 帧内绘制薄壳（全部要求开帧中；句柄 0/未开帧回 0 = 静默不画，与 2D
// 原语同一口径）。顶点/索引缓冲按整段挂（offset 0、WGPU_WHOLE_SIZE）。
int mng_gpu_canvas_frame_set_pipeline(int64_t h, int64_t pipeline) {
  if (h < 1 || h > MNG_CV_MAX || pipeline == 0) {
    return 0;
  }
  GpuCanvas *c = &g_cv[h - 1];
  if (!c->alive || !c->frame_open) {
    return 0;
  }
  p_wgpuRenderPassEncoderSetPipeline(c->frame_pass,
                                     (WGPURenderPipeline)(uintptr_t)pipeline);
  return 1;
}

int mng_gpu_canvas_frame_set_bind_group(int64_t h, int index, int64_t group) {
  if (h < 1 || h > MNG_CV_MAX || group == 0) {
    return 0;
  }
  GpuCanvas *c = &g_cv[h - 1];
  if (!c->alive || !c->frame_open) {
    return 0;
  }
  p_wgpuRenderPassEncoderSetBindGroup(c->frame_pass, (uint32_t)index,
                                      (WGPUBindGroup)(uintptr_t)group, 0, NULL);
  return 1;
}

int mng_gpu_canvas_frame_set_vertex_buffer(int64_t h, int slot, int64_t buffer) {
  if (h < 1 || h > MNG_CV_MAX || buffer == 0) {
    return 0;
  }
  GpuCanvas *c = &g_cv[h - 1];
  if (!c->alive || !c->frame_open) {
    return 0;
  }
  p_wgpuRenderPassEncoderSetVertexBuffer(c->frame_pass, (uint32_t)slot,
                                         (WGPUBuffer)(uintptr_t)buffer, 0,
                                         (uint64_t)WGPU_WHOLE_SIZE);
  return 1;
}

int mng_gpu_canvas_frame_set_index_buffer(int64_t h, int64_t buffer,
                                          int format) {
  if (h < 1 || h > MNG_CV_MAX || buffer == 0) {
    return 0;
  }
  GpuCanvas *c = &g_cv[h - 1];
  if (!c->alive || !c->frame_open) {
    return 0;
  }
  p_wgpuRenderPassEncoderSetIndexBuffer(c->frame_pass,
                                        (WGPUBuffer)(uintptr_t)buffer,
                                        (WGPUIndexFormat)format, 0,
                                        (uint64_t)WGPU_WHOLE_SIZE);
  return 1;
}

int mng_gpu_canvas_frame_draw(int64_t h, int vertices, int instances) {
  if (h < 1 || h > MNG_CV_MAX || vertices <= 0 || instances <= 0) {
    return 0;
  }
  GpuCanvas *c = &g_cv[h - 1];
  if (!c->alive || !c->frame_open) {
    return 0;
  }
  p_wgpuRenderPassEncoderDraw(c->frame_pass, (uint32_t)vertices,
                              (uint32_t)instances, 0, 0);
  return 1;
}

int mng_gpu_canvas_frame_draw_indexed(int64_t h, int indices, int instances) {
  if (h < 1 || h > MNG_CV_MAX || indices <= 0 || instances <= 0) {
    return 0;
  }
  GpuCanvas *c = &g_cv[h - 1];
  if (!c->alive || !c->frame_open) {
    return 0;
  }
  p_wgpuRenderPassEncoderDrawIndexed(c->frame_pass, (uint32_t)indices,
                                     (uint32_t)instances, 0, 0, 0);
  return 1;
}

int mng_gpu_canvas_frame_end(int64_t h) {
  if (h < 1 || h > MNG_CV_MAX || !g_cv[h - 1].alive || !g_cv[h - 1].frame_open) {
    return 0;
  }
  GpuCanvas *c = &g_cv[h - 1];
  p_wgpuRenderPassEncoderEnd(c->frame_pass);
  p_wgpuRenderPassEncoderRelease(c->frame_pass);
  c->frame_pass = NULL;
  WGPUCommandBuffer cb = p_wgpuCommandEncoderFinish(c->frame_enc, NULL);
  if (cb != NULL) {
    p_wgpuQueueSubmit(mng_wgpu_queue(), 1, &cb);
    p_wgpuCommandBufferRelease(cb);
  }
  p_wgpuCommandEncoderRelease(c->frame_enc);
  c->frame_enc = NULL;
  p_wgpuTextureViewRelease(c->frame_view);
  c->frame_view = NULL;
  c->frame_open = 0;
  return 1;
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
  if (c->frame_open) {
    cv_frame_cancel(c);
  }
  if (c->depth_view != NULL) {
    p_wgpuTextureViewRelease(c->depth_view);
    c->depth_view = NULL;
  }
  if (c->depth_tex != NULL) {
    p_wgpuTextureRelease(c->depth_tex);
    c->depth_tex = NULL;
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
// 开着的帧先自动收口（end 后读回），忘调 end 不吞帧。
int mng_gpu_canvas_finish(int64_t h, uint8_t *out, int cap) {
  if (h < 1 || h > MNG_CV_MAX || out == NULL) {
    return 0;
  }
  GpuCanvas *c = &g_cv[h - 1];
  if (!c->alive || c->target == NULL || c->readback == NULL) {
    return 0;
  }
  if (c->frame_open) {
    mng_gpu_canvas_frame_end(h);
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
    WGPUProcInstanceProcessEvents pe = (WGPUProcInstanceProcessEvents)MNG_CV_DLSYM(
        mng_wgpu_lib(), "wgpuInstanceProcessEvents");
    if (pe != NULL) {
      pe((WGPUInstance)mng_wgpu_instance());
    }
    if (cv_map_got) {
      break;
    }
    MNG_CV_SLEEP_1MS();
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
  cv_frame_cancel(c);
  if (c->depth_view != NULL) p_wgpuTextureViewRelease(c->depth_view);
  if (c->depth_tex != NULL) p_wgpuTextureRelease(c->depth_tex);
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
int64_t mng_gpu_canvas_pipe_begin(int64_t h, const uint8_t *wgsl, int wgsl_len,
                                  const char *vs_entry, int vs_len,
                                  const char *fs_entry, int fs_len,
                                  int topology, int cull, int front,
                                  int blend, int depth_write,
                                  int depth_compare, int depth) {
  (void)h; (void)wgsl; (void)wgsl_len; (void)vs_entry; (void)vs_len;
  (void)fs_entry; (void)fs_len; (void)topology; (void)cull; (void)front;
  (void)blend; (void)depth_write; (void)depth_compare; (void)depth;
  return 0;
}
int mng_gpu_canvas_pipe_buffer(int64_t h, int64_t stride, int step_mode) {
  (void)h; (void)stride; (void)step_mode;
  return -1;
}
int mng_gpu_canvas_pipe_attr(int64_t h, int location, int format,
                             int64_t offset) {
  (void)h; (void)location; (void)format; (void)offset;
  return -1;
}
int64_t mng_gpu_canvas_pipe_end(int64_t h) {
  (void)h;
  return 0;
}
int64_t mng_gpu_canvas_shader_new(int64_t h, const uint8_t *wgsl, int len) {
  (void)h; (void)wgsl; (void)len;
  return 0;
}
int64_t mng_gpu_canvas_buffer_new(int64_t h, int64_t size, int64_t usage) {
  (void)h; (void)size; (void)usage;
  return 0;
}
int mng_gpu_canvas_buffer_write(int64_t h, int64_t buffer, int64_t offset,
                                const uint8_t *data, int len) {
  (void)h; (void)buffer; (void)offset; (void)data; (void)len;
  return 0;
}
int64_t mng_gpu_canvas_pipeline_bgl(int64_t h, int64_t pipeline, int group) {
  (void)h; (void)pipeline; (void)group;
  return 0;
}
int mng_gpu_canvas_release_buffer(int64_t h, int64_t res) {
  (void)h; (void)res;
  return 0;
}
int mng_gpu_canvas_release_shader(int64_t h, int64_t res) {
  (void)h; (void)res;
  return 0;
}
int mng_gpu_canvas_release_pipeline(int64_t h, int64_t res) {
  (void)h; (void)res;
  return 0;
}
int mng_gpu_canvas_release_bind_group(int64_t h, int64_t res) {
  (void)h; (void)res;
  return 0;
}
int mng_gpu_canvas_bind_begin(int64_t h, int64_t layout) {
  (void)h; (void)layout;
  return 0;
}
int mng_gpu_canvas_bind_buffer(int64_t h, int binding, int64_t buffer,
                               int64_t offset, int64_t size) {
  (void)h; (void)binding; (void)buffer; (void)offset; (void)size;
  return 0;
}
int64_t mng_gpu_canvas_bind_end(int64_t h) {
  (void)h;
  return 0;
}
int mng_gpu_canvas_frame_begin(int64_t h, int has_clear, double r, double g,
                               double b, double a, int depth) {
  (void)h; (void)has_clear; (void)r; (void)g; (void)b; (void)a; (void)depth;
  return 0;
}
int64_t mng_gpu_canvas_frame_pass(int64_t h) {
  (void)h;
  return 0;
}
int64_t mng_gpu_canvas_frame_target_view(int64_t h) {
  (void)h;
  return 0;
}
int64_t mng_gpu_canvas_frame_depth_view(int64_t h) {
  (void)h;
  return 0;
}
int mng_gpu_canvas_frame_set_pipeline(int64_t h, int64_t pipeline) {
  (void)h; (void)pipeline;
  return 0;
}
int mng_gpu_canvas_frame_set_bind_group(int64_t h, int index, int64_t group) {
  (void)h; (void)index; (void)group;
  return 0;
}
int mng_gpu_canvas_frame_set_vertex_buffer(int64_t h, int slot, int64_t buffer) {
  (void)h; (void)slot; (void)buffer;
  return 0;
}
int mng_gpu_canvas_frame_set_index_buffer(int64_t h, int64_t buffer,
                                          int format) {
  (void)h; (void)buffer; (void)format;
  return 0;
}
int mng_gpu_canvas_frame_draw(int64_t h, int vertices, int instances) {
  (void)h; (void)vertices; (void)instances;
  return 0;
}
int mng_gpu_canvas_frame_draw_indexed(int64_t h, int indices, int instances) {
  (void)h; (void)indices; (void)instances;
  return 0;
}
int mng_gpu_canvas_frame_end(int64_t h) {
  (void)h;
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

// f32 位模式（顶点 / 均匀缓冲数据打包用；Double 入参舍入到 float）。纯 C
// 读写，不碰 wgpu——vendor 在不在都成立，故放在分支外。
int32_t mng_gpu_f32_bits(double v) {
  float f = (float)v;
  int32_t bits;
  memcpy(&bits, &f, sizeof bits);
  return bits;
}
