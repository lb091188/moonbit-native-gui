// wgpu-native 运行期核心（gui-gpu 包内共享）——实现见 wgpu_core.h 的纪律说明。
// 候选路径与探测口径和 gui/win/stub.c 的 L1 核心逐字一致（跨模块第二份，
// 注释互引）：环境变量 MNG_WGPU_LIB 优先 → 仓库布局逐级向上 → 系统名；
// 探测进程级一次、永久缓存（.so 缺/驱动无后端不再试）。

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "moonbit.h"
#include "wgpu_core.h"

#if defined(__has_include)
#if __has_include("../vendor/include/webgpu/webgpu.h")
#define MNG_CORE_REAL 1
#include "../vendor/include/webgpu/webgpu.h"
#endif
#endif

#if defined(MNG_CORE_REAL)

// ---- 函数指针表（PFN typedef 取 vendor 头，不手抄签名） ----
#define MNG_CORE_FN(name) static WGPUProc##name p_wgpu##name = NULL;
MNG_CORE_FN(CreateInstance)
MNG_CORE_FN(InstanceRequestAdapter)
MNG_CORE_FN(InstanceProcessEvents)
MNG_CORE_FN(AdapterRequestDevice)
MNG_CORE_FN(DeviceGetQueue)

static void *g_core_lib;
static int g_core_probed;
static int g_core_ok;
static WGPUInstance g_core_inst;
static WGPUAdapter g_core_adapter;
static WGPUDevice g_core_device;
static WGPUQueue g_core_queue;
static char g_core_detail[256];

// ---- dlopen 层（POSIX dlopen / Win32 LoadLibrary） ----
#if defined(_WIN32)
static void *core_dlopen(const char *p) {
  return (void *)LoadLibraryA(p);
}
static void *core_dlsym(void *h, const char *n) {
  return (void *)GetProcAddress((HMODULE)h, n);
}
#else
#include <dlfcn.h>
#include <unistd.h>
static void *core_dlopen(const char *p) {
  return dlopen(p, RTLD_NOW | RTLD_LOCAL);
}
static void *core_dlsym(void *h, const char *n) {
  return dlsym(h, n);
}
#endif

// 库名按平台取 vendor 归档的实际产物：Linux .so / mac .dylib（与 probe.c、
// gui/win/stub.c 的 L1 核心同口径；漏了这条 mac 上全部候选落空）
#if defined(__APPLE__)
#define MNG_WGPU_LIB_BASE "libwgpu_native.dylib"
#else
#define MNG_WGPU_LIB_BASE "libwgpu_native.so"
#endif

static int core_load_lib(void) {
  if (g_core_lib) {
    return 1;
  }
  const char *env = getenv("MNG_WGPU_LIB");
  if (env && env[0]) {
    g_core_lib = core_dlopen(env);
  }
#if !defined(_WIN32)
  // DBG：相对候选放最前——与 probe.c 同串，避免 glibc 按路径串加载两份实例
  if (!g_core_lib) {
    g_core_lib = core_dlopen("vendor/lib/" MNG_WGPU_LIB_BASE);
  }
  if (!g_core_lib) {
    g_core_lib = core_dlopen("vendor/" MNG_WGPU_LIB_BASE);
  }
  if (!g_core_lib) {
    char anc[1024];
    if (getcwd(anc, sizeof anc)) {
      for (int hop = 0; hop < 16 && !g_core_lib; hop++) {
        char cand[1200];
        snprintf(cand, sizeof cand, "%s/vendor/lib/%s", anc,
                 MNG_WGPU_LIB_BASE);
        g_core_lib = core_dlopen(cand);
        if (!g_core_lib) {
          snprintf(cand, sizeof cand, "%s/modules/gui-gpu/vendor/lib/%s", anc,
                   MNG_WGPU_LIB_BASE);
          g_core_lib = core_dlopen(cand);
        }
        char *slash = strrchr(anc, '/');
        if (!slash || slash == anc) {
          break;
        }
        *slash = 0;
      }
    }
  }
  if (!g_core_lib) {
    g_core_lib = core_dlopen(MNG_WGPU_LIB_BASE);
  }
#else
  if (!g_core_lib) {
    g_core_lib = core_dlopen("wgpu_native.dll");
  }
#endif
  if (!g_core_lib) {
    snprintf(g_core_detail, sizeof g_core_detail, "not-found: wgpu 库装载失败");
    return 0;
  }
  snprintf(g_core_detail, sizeof g_core_detail, "loaded");
  return 1;
}

static int core_load_syms(void) {
#define MNG_CORE_LOAD(name)                                          \
  do {                                                               \
    p_wgpu##name = (WGPUProc##name)core_dlsym(g_core_lib, "wgpu" #name); \
    if (!p_wgpu##name) {                                             \
      snprintf(g_core_detail, sizeof g_core_detail,                  \
               "库在但缺符号 wgpu" #name);                            \
      return 0;                                                      \
    }                                                                \
  } while (0)
  MNG_CORE_LOAD(CreateInstance);
  MNG_CORE_LOAD(InstanceRequestAdapter);
  MNG_CORE_LOAD(InstanceProcessEvents);
  MNG_CORE_LOAD(AdapterRequestDevice);
  MNG_CORE_LOAD(DeviceGetQueue);
#undef MNG_CORE_LOAD
  return 1;
}

// ---- future 风格回调（AllowSpontaneous：ProcessEvents 里触发） ----
static volatile int core_ad_got;
static WGPURequestAdapterStatus core_ad_status;
static WGPUAdapter core_adapter_cb;
static void core_on_adapter(WGPURequestAdapterStatus status, WGPUAdapter adapter,
                            WGPUStringView message, void *u1, void *u2) {
  (void)message;
  (void)u1;
  (void)u2;
  core_ad_status = status;
  core_adapter_cb = adapter;
  core_ad_got = 1;
}

// 未捕获错误回调：wgpu-native 的默认处理器是 panic→abort——库的口径是
// 「降级不崩」，这里改成落 stderr 一句（调用方照旧从对象建不出/探测失败
// 感知，不让验证错误把宿主应用带走）。
static void core_on_error(WGPUDevice const *device, WGPUErrorType type,
                          WGPUStringView message, void *u1, void *u2) {
  (void)device;
  (void)u1;
  (void)u2;
  fprintf(stderr, "mng-gpu: wgpu 未捕获错误 type=%d msg=%.*s\n", (int)type,
          (int)message.length, message.data ? message.data : "");
}

static volatile int core_dev_got;
static WGPURequestDeviceStatus core_dev_status;
static WGPUDevice core_device_cb;
static void core_on_device(WGPURequestDeviceStatus status, WGPUDevice device,
                           WGPUStringView message, void *u1, void *u2) {
  (void)message;
  (void)u1;
  (void)u2;
  core_dev_status = status;
  core_device_cb = device;
  core_dev_got = 1;
}

// 轮询泵：自发回调只在 ProcessEvents 里触发，1ms 步进等到置位或超时。
static int core_pump(WGPUInstance inst, volatile int *flag, int max_ms) {
  int waited = 0;
  while (!*flag && waited < max_ms) {
    p_wgpuInstanceProcessEvents(inst);
    if (*flag) {
      return 1;
    }
#if defined(_WIN32)
    Sleep(1);
#else
    usleep(1000);
#endif
    waited += 1;
  }
  return *flag ? 1 : 0;
}

static void core_probe(void) {
  if (g_core_probed) {
    return;
  }
  g_core_probed = 1;
  g_core_ok = 0;
  if (!core_load_lib() || !core_load_syms()) {
    return;
  }
  WGPUInstanceDescriptor idesc;
  memset(&idesc, 0, sizeof idesc);
  g_core_inst = p_wgpuCreateInstance(&idesc);
  if (g_core_inst == NULL) {
    snprintf(g_core_detail, sizeof g_core_detail, "wgpuCreateInstance 失败");
    return;
  }
  WGPURequestAdapterCallbackInfo acb;
  memset(&acb, 0, sizeof acb);
  acb.mode = WGPUCallbackMode_AllowSpontaneous;
  acb.callback = core_on_adapter;
  WGPURequestAdapterOptions aopt;
  memset(&aopt, 0, sizeof aopt);
  // 后端交给 wgpu 自选 primary（Linux=Vulkan / mac=Metal / Win=D3D12）：
  // 显式 Vulkan 是 2026-11-04 预实证原型的遗留，在 mac/Windows 上没有
  // Vulkan 后端会直接拿不到 adapter（真机「画布建不出」的根因）
  aopt.backendType = WGPUBackendType_Undefined;
  core_ad_got = 0;
  (void)p_wgpuInstanceRequestAdapter(g_core_inst, &aopt, acb);
  if (!core_pump(g_core_inst, &core_ad_got, 5000) ||
      core_ad_status != WGPURequestAdapterStatus_Success ||
      core_adapter_cb == NULL) {
    snprintf(g_core_detail, sizeof g_core_detail, "adapter 拿不到（status=%d）",
             (int)core_ad_status);
    return;
  }
  g_core_adapter = core_adapter_cb;
  WGPURequestDeviceCallbackInfo dcb;
  memset(&dcb, 0, sizeof dcb);
  dcb.mode = WGPUCallbackMode_AllowSpontaneous;
  dcb.callback = core_on_device;
  WGPUDeviceDescriptor ddesc;
  memset(&ddesc, 0, sizeof ddesc);
  ddesc.uncapturedErrorCallbackInfo.callback = core_on_error;
  core_dev_got = 0;
  (void)p_wgpuAdapterRequestDevice(g_core_adapter, &ddesc, dcb);
  if (!core_pump(g_core_inst, &core_dev_got, 5000) ||
      core_dev_status != WGPURequestDeviceStatus_Success ||
      core_device_cb == NULL) {
    snprintf(g_core_detail, sizeof g_core_detail, "device 拿不到（status=%d）",
             (int)core_dev_status);
    return;
  }
  g_core_device = core_device_cb;
  g_core_queue = p_wgpuDeviceGetQueue(g_core_device);
  if (g_core_queue == NULL) {
    snprintf(g_core_detail, sizeof g_core_detail, "wgpuDeviceGetQueue 失败");
    return;
  }
  g_core_ok = 1;
}

int mng_wgpu_ready(void) {
  core_probe();
  return g_core_ok;
}

void mng_wgpu_detail(char *out, int cap) {
  core_probe();
  if (out == NULL || cap <= 0) {
    return;
  }
  int n = (int)strlen(g_core_detail);
  if (n > cap - 1) {
    n = cap - 1;
  }
  memcpy(out, g_core_detail, (size_t)n);
  out[n] = 0;
}

void *mng_wgpu_lib(void) {
  return g_core_lib;
}

void *mng_wgpu_instance(void) {
  return (void *)g_core_inst;
}

void *mng_wgpu_adapter(void) {
  return (void *)g_core_adapter;
}

void *mng_wgpu_device(void) {
  return (void *)g_core_device;
}

void *mng_wgpu_queue(void) {
  return (void *)g_core_queue;
}

#else /* 没有 wgpu vendor 头：整文件退化成「不可用」桩 */

int mng_wgpu_ready(void) {
  return 0;
}

void mng_wgpu_detail(char *out, int cap) {
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

void *mng_wgpu_lib(void) {
  return NULL;
}
void *mng_wgpu_instance(void) {
  return NULL;
}
void *mng_wgpu_adapter(void) {
  return NULL;
}
void *mng_wgpu_device(void) {
  return NULL;
}
void *mng_wgpu_queue(void) {
  return NULL;
}

#endif /* MNG_CORE_REAL */
