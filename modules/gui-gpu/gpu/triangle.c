// X11 wgpu 三角形探针（GPU 线第一步，方案 proposals/gpu-architecture.md
// 落地路线 1）：自包含 Xlib 窗 + wgpu 全链路上屏——wgpu 库与 libX11 都走
// dlopen（与 probe.c 同户型，「本模块不占链接面」原则不变，vendor 归档没
// 下载时本 TU 退化成编译期桩）。验收：窗口里见一个三色三角形，关窗或按
// Esc 退出。任一步不可用（没 X 显示/没 GPU 驱动/库缺符号）如实报错不崩
// ——「没装 GPU 扩展」是降级形态，不是错误。
//
// v29 future 风格 API 口径（2026-11-04 本机预实证）：adapter/device 都经
// 回调拿（WGPUCallbackMode_AllowSpontaneous + wgpuInstanceProcessEvents
// 泵），不能当同步函数用；surface 走 WGPUSurfaceSourceXlibWindow{display,
// window}，上屏走 wgpuSurfaceGetCurrentTexture + wgpuSurfacePresent。

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "moonbit.h"

// vendor 头（prebuild 下载的归档里带，与 gpu/ 包目录同级：modules/gui-gpu/
// vendor/）与系统 Xlib 头都不强制：缺任一个本 TU 退化成「本平台桩」，
// 构建照旧绿（__has_include 是 GCC/Clang/MSVC 都支持的老特性）。
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

// ---------- dlopen 层 ----------
// wgpu 候选序与 probe.c 逐字一致（环境变量 MNG_WGPU_LIB 优先 → vendor →
// 系统名）；libX11 两个常用 soname。
static void *g_wgpu = NULL;
static void *g_x11 = NULL;

static void *tri_dlopen(const char *p) {
    return dlopen(p, RTLD_NOW | RTLD_LOCAL);
}

// ---------- wgpu 函数指针表（PFN typedef 用 vendor 头的，不手抄签名） ----------
#define MNG_WGPU_FN(name) static WGPUProc##name p_wgpu##name = NULL;
MNG_WGPU_FN(CreateInstance)
MNG_WGPU_FN(InstanceCreateSurface)
MNG_WGPU_FN(InstanceRequestAdapter)
MNG_WGPU_FN(InstanceProcessEvents)
MNG_WGPU_FN(AdapterRequestDevice)
MNG_WGPU_FN(DeviceGetQueue)
MNG_WGPU_FN(DeviceCreateCommandEncoder)
MNG_WGPU_FN(DeviceCreateShaderModule)
MNG_WGPU_FN(DeviceCreateRenderPipeline)
MNG_WGPU_FN(CommandEncoderBeginRenderPass)
MNG_WGPU_FN(CommandEncoderFinish)
MNG_WGPU_FN(RenderPassEncoderSetPipeline)
MNG_WGPU_FN(RenderPassEncoderDraw)
MNG_WGPU_FN(RenderPassEncoderEnd)
MNG_WGPU_FN(QueueSubmit)
MNG_WGPU_FN(TextureCreateView)
MNG_WGPU_FN(SurfaceConfigure)
MNG_WGPU_FN(SurfaceGetCurrentTexture)
MNG_WGPU_FN(SurfacePresent)

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

// 缺符号时把名字记下来，错误详情给人看（与 probe.c 的 put 同户型；小
// 工具函数按本仓「宏/小桩不跨 TU」纪律各写一份）。
static char g_tri_missing[128];
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

static int tri_load_wgpu(void) {
    if (g_wgpu) {
        return 1;
    }
    const char *env = getenv("MNG_WGPU_LIB");
    if (env && env[0]) {
        g_wgpu = tri_dlopen(env);
    }
    // 仓库布局候选：从 cwd 逐级向上，每级试 <anc>/vendor/lib/…（模块根
    // 形态）与 <anc>/modules/gui-gpu/vendor/lib/…（仓库根形态）——本探针
    // 从仓库任意目录跑都找得到 vendor 归档（候选原先是相对 cwd 的，只有
    // 模块根下才中；dlopen 试错，不需要 stat）。发行的应用走不到这两级，
    // 落系统名/环境变量。
    if (!g_wgpu) {
        char anc[1024];
        if (getcwd(anc, sizeof anc)) {
            for (int hop = 0; hop < 16 && !g_wgpu; hop++) {
                char cand[1200];
                snprintf(cand, sizeof cand, "%s/vendor/lib/libwgpu_native.so", anc);
                g_wgpu = tri_dlopen(cand);
                if (!g_wgpu) {
                    snprintf(cand, sizeof cand, "%s/modules/gui-gpu/vendor/lib/libwgpu_native.so", anc);
                    g_wgpu = tri_dlopen(cand);
                }
                char *slash = strrchr(anc, '/');
                if (!slash || slash == anc) {
                    break;
                }
                *slash = 0;
            }
        }
    }
    if (!g_wgpu) {
        g_wgpu = tri_dlopen("libwgpu_native.so");
    }
    if (!g_wgpu) {
        snprintf(g_tri_missing, sizeof g_tri_missing, "wgpu 库装载失败（MNG_WGPU_LIB/vendor 都没有）");
        return 0;
    }
#define MNG_WGPU_LOAD(name)                                            \
    do {                                                               \
        p_wgpu##name = (WGPUProc##name)dlsym(g_wgpu, "wgpu" #name);    \
        if (!p_wgpu##name) {                                           \
            snprintf(g_tri_missing, sizeof g_tri_missing,              \
                     "wgpu 库缺符号 wgpu" #name);                      \
            return 0;                                                  \
        }                                                              \
    } while (0)
    MNG_WGPU_LOAD(CreateInstance);
    MNG_WGPU_LOAD(InstanceCreateSurface);
    MNG_WGPU_LOAD(InstanceRequestAdapter);
    MNG_WGPU_LOAD(InstanceProcessEvents);
    MNG_WGPU_LOAD(AdapterRequestDevice);
    MNG_WGPU_LOAD(DeviceGetQueue);
    MNG_WGPU_LOAD(DeviceCreateCommandEncoder);
    MNG_WGPU_LOAD(DeviceCreateShaderModule);
    MNG_WGPU_LOAD(DeviceCreateRenderPipeline);
    MNG_WGPU_LOAD(CommandEncoderBeginRenderPass);
    MNG_WGPU_LOAD(CommandEncoderFinish);
    MNG_WGPU_LOAD(RenderPassEncoderSetPipeline);
    MNG_WGPU_LOAD(RenderPassEncoderDraw);
    MNG_WGPU_LOAD(RenderPassEncoderEnd);
    MNG_WGPU_LOAD(QueueSubmit);
    MNG_WGPU_LOAD(TextureCreateView);
    MNG_WGPU_LOAD(SurfaceConfigure);
    MNG_WGPU_LOAD(SurfaceGetCurrentTexture);
    MNG_WGPU_LOAD(SurfacePresent);
#undef MNG_WGPU_LOAD
    return 1;
}

static int tri_load_x11(void) {
    if (g_x11) {
        return 1;
    }
    g_x11 = tri_dlopen("libX11.so.6");
    if (!g_x11) {
        g_x11 = tri_dlopen("libX11.so");
    }
    if (!g_x11) {
        snprintf(g_tri_missing, sizeof g_tri_missing, "libX11 装载失败（没装 libX11？）");
        return 0;
    }
#define MNG_X_LOAD(name)                                          \
    do {                                                          \
        p_##name = (__typeof__(p_##name))dlsym(g_x11, #name);     \
        if (!p_##name) {                                          \
            snprintf(g_tri_missing, sizeof g_tri_missing,         \
                     "libX11 缺符号 " #name);                     \
            return 0;                                             \
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

// ---------- future 风格回调（AllowSpontaneous：ProcessEvents 里触发） ----------
static volatile int g_ad_got;
static WGPURequestAdapterStatus g_ad_status;
static WGPUAdapter g_adapter;
static char g_ad_msg[256];
static void tri_on_adapter(WGPURequestAdapterStatus status, WGPUAdapter adapter, WGPUStringView message, void *u1, void *u2) {
    (void)u1;
    (void)u2;
    g_ad_status = status;
    g_adapter = adapter;
    size_t n = message.length;
    if (n > sizeof(g_ad_msg) - 1) {
        n = sizeof(g_ad_msg) - 1;
    }
    if (message.data && n) {
        memcpy(g_ad_msg, message.data, n);
    }
    g_ad_msg[n] = 0;
    g_ad_got = 1;
}

static volatile int g_dev_got;
static WGPURequestDeviceStatus g_dev_status;
static WGPUDevice g_device;
static void tri_on_device(WGPURequestDeviceStatus status, WGPUDevice device, WGPUStringView message, void *u1, void *u2) {
    (void)message;
    (void)u1;
    (void)u2;
    g_dev_status = status;
    g_device = device;
    g_dev_got = 1;
}

// 轮询泵：自发回调只在 ProcessEvents 里触发，1ms 步进等到置位或超时。
static int tri_pump(WGPUInstance inst, volatile int *flag, int max_ms) {
    int waited = 0;
    while (!*flag && waited < max_ms) {
        p_wgpuInstanceProcessEvents(inst);
        if (*flag) {
            return 1;
        }
        usleep(1000);
        waited += 1;
    }
    return *flag ? 1 : 0;
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
// -4 adapter / -5 device / -6 surface / -7 pipeline），原因写进 out。
int32_t mng_gpu_triangle(uint8_t *out, int32_t cap, int32_t frames) {
    if (frames <= 0) {
        frames = 600;
    }
    if (frames > 100000) {
        frames = 100000;
    }
    if (!tri_load_wgpu()) {
        tri_put(out, cap, g_tri_missing);
        return -2;
    }
    if (!tri_load_x11()) {
        tri_put(out, cap, g_tri_missing);
        return -2;
    }

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

    // ---- instance + surface（XlibWindow 源） ----
    WGPUInstanceDescriptor idesc;
    memset(&idesc, 0, sizeof idesc);
    WGPUInstance inst = p_wgpuCreateInstance(&idesc);
    if (!inst) {
        tri_put(out, cap, "wgpuCreateInstance 失败");
        p_XCloseDisplay(dpy);
        return -6;
    }
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

    // ---- adapter（future：回调 + 泵） ----
    WGPURequestAdapterCallbackInfo acb;
    memset(&acb, 0, sizeof acb);
    acb.mode = WGPUCallbackMode_AllowSpontaneous;
    acb.callback = tri_on_adapter;
    WGPURequestAdapterOptions aopt;
    memset(&aopt, 0, sizeof aopt);
    aopt.compatibleSurface = surf;
    g_ad_got = 0;
    g_ad_msg[0] = 0;
    (void)p_wgpuInstanceRequestAdapter(inst, &aopt, acb);
    if (!tri_pump(inst, &g_ad_got, 5000) ||
        g_ad_status != WGPURequestAdapterStatus_Success || !g_adapter) {
        char buf[300];
        snprintf(buf, sizeof buf, "adapter 拿不到（status=%d）：%s", (int)g_ad_status, g_ad_msg);
        tri_put(out, cap, buf);
        p_XCloseDisplay(dpy);
        return -4;
    }

    // ---- device（future 同款） ----
    WGPURequestDeviceCallbackInfo dcb;
    memset(&dcb, 0, sizeof dcb);
    dcb.mode = WGPUCallbackMode_AllowSpontaneous;
    dcb.callback = tri_on_device;
    WGPUDeviceDescriptor ddesc;
    memset(&ddesc, 0, sizeof ddesc);
    g_dev_got = 0;
    (void)p_wgpuAdapterRequestDevice(g_adapter, &ddesc, dcb);
    if (!tri_pump(inst, &g_dev_got, 5000) ||
        g_dev_status != WGPURequestDeviceStatus_Success || !g_device) {
        char buf[128];
        snprintf(buf, sizeof buf, "device 拿不到（status=%d）", (int)g_dev_status);
        tri_put(out, cap, buf);
        p_XCloseDisplay(dpy);
        return -5;
    }
    WGPUQueue queue = p_wgpuDeviceGetQueue(g_device);
    if (!queue) {
        tri_put(out, cap, "wgpuDeviceGetQueue 失败");
        p_XCloseDisplay(dpy);
        return -5;
    }

    // ---- shader + pipeline（无顶点缓冲，全常量顶点） ----
    WGPUShaderSourceWGSL wsrc;
    memset(&wsrc, 0, sizeof wsrc);
    wsrc.chain.sType = WGPUSType_ShaderSourceWGSL;
    wsrc.code.data = TRI_WGSL;
    wsrc.code.length = sizeof(TRI_WGSL) - 1;
    WGPUShaderModuleDescriptor smd;
    memset(&smd, 0, sizeof smd);
    smd.nextInChain = &wsrc.chain;
    WGPUShaderModule mod = p_wgpuDeviceCreateShaderModule(g_device, &smd);
    if (!mod) {
        tri_put(out, cap, "shader module 建不出");
        p_XCloseDisplay(dpy);
        return -7;
    }
    WGPUStringView ep_vs;
    ep_vs.data = "vs_main";
    ep_vs.length = 7;
    WGPUStringView ep_fs;
    ep_fs.data = "fs_main";
    ep_fs.length = 7;
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
    pd.fragment = &frag;
    WGPURenderPipeline pipeline = p_wgpuDeviceCreateRenderPipeline(g_device, &pd);
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
    cfg.device = g_device;
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
        WGPUCommandEncoder enc = p_wgpuDeviceCreateCommandEncoder(g_device, NULL);
        WGPURenderPassEncoder pass = p_wgpuCommandEncoderBeginRenderPass(enc, &rp);
        p_wgpuRenderPassEncoderSetPipeline(pass, pipeline);
        p_wgpuRenderPassEncoderDraw(pass, 3, 1, 0, 0);
        p_wgpuRenderPassEncoderEnd(pass);
        WGPUCommandBuffer cmdbuf = p_wgpuCommandEncoderFinish(enc, NULL);
        p_wgpuQueueSubmit(queue, 1, &cmdbuf);
        p_wgpuSurfacePresent(surf);
        p_wgpuInstanceProcessEvents(inst);
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
