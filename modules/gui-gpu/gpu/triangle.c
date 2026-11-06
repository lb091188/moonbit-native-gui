// X11 wgpu 三角形探针（GPU 线第一步，方案 gpu-architecture.md 落地路线 1）：
// 自包含 Xlib 窗 + wgpu 全链路上屏——wgpu 库与 libX11 都走 dlopen（与
// wgpu_core.c 同户型，「本模块不占链接面」原则不变）。验收：窗口里见一个
// 三色三角形，关窗或按 Esc 退出。任一步不可用（没 X 显示/没 GPU 驱动/库缺
// 符号）如实报错不崩——「没装 GPU 扩展」是降级形态，不是错误。
//
// 装载/探测（instance/adapter/device/queue）走包内共享的 wgpu_core；本文件
// 只带自己的 surface（XlibWindow）、全屏 textured quad 管线与帧循环。
//
// v29 future 风格 API（2026-11-04 本机预实证口径）：adapter/device 经回调
// 拿（core 里泵）；surface 走 WGPUSurfaceSourceXlibWindow{display, window}，
// 上屏走 wgpuSurfaceGetCurrentTexture + wgpuSurfacePresent。

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "moonbit.h"
#include "wgpu_core.h"

// vendor 头（prebuild 下载的归档里带，与 gpu/ 包目录同级）与系统 Xlib 头都
// 不强制：缺任一个本 TU 退化成「本平台桩」，构建照旧绿。
#if defined(__has_include)
#if __has_include("../vendor/include/webgpu/webgpu.h") && __has_include(<X11/Xlib.h>)
#define MNG_TRIANGLE_REAL 1
#include "../vendor/include/webgpu/webgpu.h"
#include <X11/Xlib.h>
#include <unistd.h>
#include <dlfcn.h>
#endif
#endif

#if defined(MNG_TRIANGLE_REAL)

// ---- wgpu 函数指针表（PFN typedef 取 vendor 头；装载/探测在 wgpu_core） ----
#define MNG_TRI_FN(name) static WGPUProc##name p_wgpu##name = NULL;
MNG_TRI_FN(InstanceCreateSurface)
MNG_TRI_FN(DeviceCreateShaderModule)
MNG_TRI_FN(DeviceCreateRenderPipeline)
MNG_TRI_FN(DeviceCreateSampler)
MNG_TRI_FN(DeviceCreateCommandEncoder)
MNG_TRI_FN(CommandEncoderBeginRenderPass)
MNG_TRI_FN(CommandEncoderFinish)
MNG_TRI_FN(RenderPassEncoderSetPipeline)
MNG_TRI_FN(RenderPassEncoderDraw)
MNG_TRI_FN(RenderPassEncoderEnd)
MNG_TRI_FN(QueueSubmit)
MNG_TRI_FN(TextureCreateView)
MNG_TRI_FN(RenderPipelineGetBindGroupLayout)
MNG_TRI_FN(SurfaceConfigure)
MNG_TRI_FN(SurfaceGetCurrentTexture)
MNG_TRI_FN(SurfacePresent)
MNG_TRI_FN(CommandBufferRelease)
MNG_TRI_FN(TextureViewRelease)

// libX11 导出符号（nm 核过：全是真函数，不是宏——宏不能用 dlsym 取）。
static Display *(*p_XOpenDisplay)(const char *) = NULL;
static int (*p_XCloseDisplay)(Display *) = NULL;
static Window (*p_XDefaultRootWindow)(Display *) = NULL;
static Window (*p_XCreateSimpleWindow)(Display *, Window, int, int, unsigned int, unsigned int, unsigned int, unsigned long, unsigned long) = NULL;
static int (*p_XMapWindow)(Display *, Window) = NULL;
static int (*p_XStoreName)(Display *, Window, const char *) = NULL;
static Atom (*p_XInternAtom)(Display *, const char *, Bool) = NULL;
static int (*p_XSetWMProtocols)(Display *, Window, Atom *, int) = NULL;
static int (*p_XSelectInput)(Display *, Window, long) = NULL;
static int (*p_XPending)(Display *) = NULL;
static int (*p_XNextEvent)(Display *, XEvent *) = NULL;
static int (*p_XFlush)(Display *) = NULL;

static void tri_put(uint8_t *out, int32_t cap, const char *s) {
  if (cap <= 0) {
    return;
  }
  int n = (int)strlen(s);
  if (n > cap - 1) {
    n = cap - 1;
  }
  memcpy(out, s, (size_t)n);
  out[n] = 0;
}

static void *tri_dlopen(const char *p) {
  return dlopen(p, RTLD_NOW | RTLD_LOCAL);
}

static int tri_load_syms(void) {
#define MNG_TRI_LOAD(name)                                          \
  do {                                                              \
    p_wgpu##name = (WGPUProc##name)dlsym(mng_wgpu_lib(), "wgpu" #name);  \
    if (!p_wgpu##name) {                                            \
      return 0;                                                     \
    }                                                               \
  } while (0)
  MNG_TRI_LOAD(InstanceCreateSurface);
  MNG_TRI_LOAD(DeviceCreateShaderModule);
  MNG_TRI_LOAD(DeviceCreateRenderPipeline);
  MNG_TRI_LOAD(DeviceCreateSampler);
  MNG_TRI_LOAD(DeviceCreateCommandEncoder);
  MNG_TRI_LOAD(CommandEncoderBeginRenderPass);
  MNG_TRI_LOAD(CommandEncoderFinish);
  MNG_TRI_LOAD(RenderPassEncoderSetPipeline);
  MNG_TRI_LOAD(RenderPassEncoderDraw);
  MNG_TRI_LOAD(RenderPassEncoderEnd);
  MNG_TRI_LOAD(QueueSubmit);
  MNG_TRI_LOAD(TextureCreateView);
  MNG_TRI_LOAD(RenderPipelineGetBindGroupLayout);
  MNG_TRI_LOAD(SurfaceConfigure);
  MNG_TRI_LOAD(SurfaceGetCurrentTexture);
  MNG_TRI_LOAD(SurfacePresent);
  MNG_TRI_LOAD(CommandBufferRelease);
  MNG_TRI_LOAD(TextureViewRelease);
#undef MNG_TRI_LOAD
  return 1;
}

static int tri_load_x11(void) {
  static void *lib;
  if (lib) {
    return 1;
  }
  lib = tri_dlopen("libX11.so.6");
  if (!lib) {
    lib = tri_dlopen("libX11.so");
  }
  if (!lib) {
    return 0;
  }
#define MNG_X_LOAD(name)                                      \
  do {                                                        \
    p_##name = (__typeof__(p_##name))dlsym(lib, #name);       \
    if (!p_##name) {                                          \
      return 0;                                               \
    }                                                         \
  } while (0)
  MNG_X_LOAD(XOpenDisplay);
  MNG_X_LOAD(XCloseDisplay);
  MNG_X_LOAD(XDefaultRootWindow);
  MNG_X_LOAD(XCreateSimpleWindow);
  MNG_X_LOAD(XMapWindow);
  MNG_X_LOAD(XStoreName);
  MNG_X_LOAD(XInternAtom);
  MNG_X_LOAD(XSetWMProtocols);
  MNG_X_LOAD(XSelectInput);
  MNG_X_LOAD(XPending);
  MNG_X_LOAD(XNextEvent);
  MNG_X_LOAD(XFlush);
#undef MNG_X_LOAD
  return 1;
}

static WGPUStringView tri_sv(const char *s) {
  WGPUStringView v;
  v.data = s;
  v.length = strlen(s);
  return v;
}

// 三角形 shader（wgpu 示例 canonical 版，naga 必过）。
static const char TRI_WGSL[] =
    "struct VOut {\n"
    "  @builtin(position) pos : vec4f,\n"
    "  @location(0) col : vec4f,\n"
    "}\n"
    "@vertex fn vs_main(@builtin(vertex_index) i : u32) -> VOut {\n"
    "  var p = array<vec2f, 3>(vec2f(0.0, 0.75), vec2f(-0.75, -0.75), vec2f(0.75, -0.75));\n"
    "  var c = array<vec3f, 3>(vec3f(1.0, 0.25, 0.25), vec3f(0.25, 1.0, 0.35), vec3f(0.3, 0.5, 1.0));\n"
    "  var out : VOut;\n"
    "  out.pos = vec4f(p[i], 0.0, 1.0);\n"
    "  out.col = vec4f(c[i], 1.0);\n"
    "  return out;\n"
    "}\n"
    "@fragment fn fs_main(in : VOut) -> @location(0) vec4f {\n"
    "  return in.col;\n"
    "}\n";

// 返回 0 = 正常跑完；负值 = 错误码（-1 编译期桩 / -2 库 / -3 X 显示 /
// -4 设备 / -6 surface / -7 pipeline），原因写进 out。
int32_t mng_gpu_triangle(uint8_t *out, int32_t cap, int32_t frames) {
  if (frames <= 0) {
    frames = 600;
  }
  if (frames > 100000) {
    frames = 100000;
  }
  // 装载/探测走包内共享 core（instance/adapter/device/queue）
  if (!mng_wgpu_ready()) {
    char d[192];
    mng_wgpu_detail(d, (int)sizeof d);
    char buf[256];
    snprintf(buf, sizeof buf, "wgpu 不可用：%s", d);
    tri_put(out, cap, buf);
    return -2;
  }
  if (!tri_load_syms() || !tri_load_x11()) {
    tri_put(out, cap, "wgpu/libX11 符号加载失败");
    return -2;
  }

  WGPUInstance inst = (WGPUInstance)mng_wgpu_instance();
  WGPUDevice device = (WGPUDevice)mng_wgpu_device();
  WGPUQueue queue = (WGPUQueue)mng_wgpu_queue();

  // ---- X 窗（640x480，带 WM_DELETE 协议与 Esc 退出） ----
  Display *dpy = p_XOpenDisplay(NULL);
  if (!dpy) {
    tri_put(out, cap, "XOpenDisplay 失败（没有 DISPLAY？）");
    return -3;
  }
  Window win = p_XCreateSimpleWindow(dpy, p_XDefaultRootWindow(dpy), 0, 0, 640, 480, 0, 0, 0);
  if (!win) {
    tri_put(out, cap, "XCreateSimpleWindow 失败");
    p_XCloseDisplay(dpy);
    return -3;
  }
  p_XStoreName(dpy, win, "mng-gpu triangle");
  Atom wm_delete = p_XInternAtom(dpy, "WM_DELETE_WINDOW", False);
  p_XSetWMProtocols(dpy, win, &wm_delete, 1);
  p_XSelectInput(dpy, win, ExposureMask | KeyPressMask | StructureNotifyMask);
  p_XMapWindow(dpy, win);
  p_XFlush(dpy);

  // ---- surface（XlibWindow 源） ----
  WGPUSurfaceSourceXlibWindow xsrc;
  memset(&xsrc, 0, sizeof xsrc);
  xsrc.chain.sType = WGPUSType_SurfaceSourceXlibWindow;
  xsrc.display = (void *)dpy;
  xsrc.window = (uint64_t)win;
  WGPUSurfaceDescriptor sdesc;
  memset(&sdesc, 0, sizeof sdesc);
  sdesc.nextInChain = &xsrc.chain;
  WGPUSurface surf = p_wgpuInstanceCreateSurface(inst, &sdesc);
  if (!surf) {
    tri_put(out, cap, "wgpuInstanceCreateSurface 失败（X11 后端没起来？）");
    p_XCloseDisplay(dpy);
    return -6;
  }

  // ---- shader + pipeline（无顶点缓冲，全常量顶点） ----
  WGPUShaderSourceWGSL wsrc;
  memset(&wsrc, 0, sizeof wsrc);
  wsrc.chain.sType = WGPUSType_ShaderSourceWGSL;
  wsrc.code = tri_sv(TRI_WGSL);
  WGPUShaderModuleDescriptor smd;
  memset(&smd, 0, sizeof smd);
  smd.nextInChain = &wsrc.chain;
  WGPUShaderModule mod = p_wgpuDeviceCreateShaderModule(device, &smd);
  if (!mod) {
    tri_put(out, cap, "shader module 建不出");
    p_XCloseDisplay(dpy);
    return -7;
  }
  WGPUStringView ep_vs = tri_sv("vs_main");
  WGPUStringView ep_fs = tri_sv("fs_main");
  WGPUColorTargetState ct;
  memset(&ct, 0, sizeof ct);
  ct.format = WGPUTextureFormat_BGRA8Unorm;
  ct.writeMask = WGPUColorWriteMask_All;
  WGPUFragmentState frag;
  memset(&frag, 0, sizeof frag);
  frag.module = mod;
  frag.entryPoint = ep_fs;
  frag.targetCount = 1;
  frag.targets = &ct;
  WGPUVertexState vert;
  memset(&vert, 0, sizeof vert);
  vert.module = mod;
  vert.entryPoint = ep_vs;
  WGPURenderPipelineDescriptor pd;
  memset(&pd, 0, sizeof pd);
  pd.vertex = vert;
  pd.primitive.topology = WGPUPrimitiveTopology_TriangleList;
  pd.primitive.frontFace = WGPUFrontFace_CCW;
  pd.primitive.cullMode = WGPUCullMode_None;
  pd.multisample.count = 1;
  // mask 默认 0xFFFFFFFF；memset 清零会让 draw 一条像素都不出（clear 照落）
  pd.multisample.mask = 0xFFFFFFFFu;
  pd.fragment = &frag;
  WGPURenderPipeline pipeline = p_wgpuDeviceCreateRenderPipeline(device, &pd);
  if (!pipeline) {
    tri_put(out, cap, "render pipeline 建不出（BGRA8Unorm 不被驱动支持？）");
    p_XCloseDisplay(dpy);
    return -7;
  }

  // ---- surface 配置（Fifo vsync；尺寸变了下一轮重配） ----
  int32_t w = 640;
  int32_t h = 480;
  WGPUSurfaceConfiguration cfg;
  memset(&cfg, 0, sizeof cfg);
  cfg.device = device;
  cfg.format = WGPUTextureFormat_BGRA8Unorm;
  cfg.usage = WGPUTextureUsage_RenderAttachment;
  cfg.width = (uint32_t)w;
  cfg.height = (uint32_t)h;
  cfg.alphaMode = WGPUCompositeAlphaMode_Opaque;
  cfg.presentMode = WGPUPresentMode_Fifo;
  p_wgpuSurfaceConfigure(surf, &cfg);

  // ---- 帧循环：X 事件 + 上屏 ----
  for (int32_t i = 0; i < frames; i++) {
    while (p_XPending(dpy)) {
      XEvent ev;
      p_XNextEvent(dpy, &ev);
      if (ev.type == ClientMessage && (Atom)ev.xclient.data.l[0] == wm_delete) {
        i = frames;
        break;
      }
      if (ev.type == KeyPress) {
        i = frames;
        break;
      }
      if (ev.type == ConfigureNotify) {
        int32_t nw = (int32_t)ev.xconfigure.width;
        int32_t nh = (int32_t)ev.xconfigure.height;
        if (nw > 0 && nh > 0 && (nw != w || nh != h)) {
          w = nw;
          h = nh;
          cfg.width = (uint32_t)w;
          cfg.height = (uint32_t)h;
          p_wgpuSurfaceConfigure(surf, &cfg);
        }
      }
    }
    WGPUSurfaceTexture st;
    memset(&st, 0, sizeof st);
    p_wgpuSurfaceGetCurrentTexture(surf, &st);
    if (st.status == WGPUSurfaceGetCurrentTextureStatus_Outdated) {
      cfg.width = (uint32_t)w;
      cfg.height = (uint32_t)h;
      p_wgpuSurfaceConfigure(surf, &cfg);
      continue;
    }
    if (st.status != WGPUSurfaceGetCurrentTextureStatus_SuccessOptimal || !st.texture) {
      continue; // Timeout（最小化等）：跳过这帧
    }
    WGPUTextureView view = p_wgpuTextureCreateView(st.texture, NULL);
    if (!view) {
      continue;
    }
    WGPURenderPassColorAttachment att;
    memset(&att, 0, sizeof att);
    att.view = view;
    att.loadOp = WGPULoadOp_Clear;
    att.storeOp = WGPUStoreOp_Store;
    att.depthSlice = WGPU_DEPTH_SLICE_UNDEFINED;
    att.clearValue.r = 0.08;
    att.clearValue.g = 0.09;
    att.clearValue.b = 0.11;
    att.clearValue.a = 1.0;
    WGPURenderPassDescriptor rp;
    memset(&rp, 0, sizeof rp);
    rp.colorAttachmentCount = 1;
    rp.colorAttachments = &att;
    WGPUCommandEncoder enc = p_wgpuDeviceCreateCommandEncoder(device, NULL);
    WGPURenderPassEncoder pass = p_wgpuCommandEncoderBeginRenderPass(enc, &rp);
    p_wgpuRenderPassEncoderSetPipeline(pass, pipeline);
    p_wgpuRenderPassEncoderDraw(pass, 3, 1, 0, 0);
    p_wgpuRenderPassEncoderEnd(pass);
    WGPUCommandBuffer cmdbuf = p_wgpuCommandEncoderFinish(enc, NULL);
    p_wgpuQueueSubmit(queue, 1, &cmdbuf);
    p_wgpuSurfacePresent(surf);
  }

  // 进程随即退出，wgpu/X 对象交给 OS 与驱动收拾（探针从简，不逐一 release）。
  p_XCloseDisplay(dpy);
  tri_put(out, cap, "ok");
  return 0;
}

#else /* !MNG_TRIANGLE_REAL：编译期桩（无 vendor 头或无 Xlib 头） */

static void tri_put_stub(uint8_t *out, int32_t cap, const char *s) {
  if (cap <= 0) {
    return;
  }
  int n = (int)strlen(s);
  if (n > cap - 1) {
    n = cap - 1;
  }
  memcpy(out, s, (size_t)n);
  out[n] = 0;
}

int32_t mng_gpu_triangle(uint8_t *out, int32_t cap, int32_t frames) {
  (void)frames;
  tri_put_stub(out, cap, "unsupported: 本平台没编进 wgpu vendor 头或 Xlib 头（编译期桩）");
  return -1;
}

#endif
