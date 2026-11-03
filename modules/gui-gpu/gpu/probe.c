// wgpu-native 运行期装载探测：只 dlopen / LoadLibrary，不静态链接。
// 装载成功且能取到 wgpuCreateInstance 才算可用；失败把原因原样交回 MoonBit，
// 上层据此走纯光栅路径（下载没成/没装 GPU 扩展都不是错误，是降级形态）。

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "moonbit.h"

#if defined(_WIN32)
#include <windows.h>
static void *g_lib = NULL;
static const char *dl_open(const char *p) {
    g_lib = (void *)LoadLibraryA(p);
    return g_lib ? NULL : "LoadLibrary failed";
}
static void *dl_sym(const char *n) {
    return g_lib ? (void *)GetProcAddress((HMODULE)g_lib, n) : NULL;
}
#else
#include <dlfcn.h>
static void *g_lib = NULL;
static const char *dl_open(const char *p) {
    g_lib = dlopen(p, RTLD_NOW | RTLD_LOCAL);
    return g_lib ? NULL : dlerror();
}
static void *dl_sym(const char *n) {
    return g_lib ? dlsym(g_lib, n) : NULL;
}
#endif

static void put(uint8_t *out, int32_t cap, const char *s) {
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

// 1 = 装载成功且符号在；0 = 不可用（详情写进 out）。
int32_t mng_gpu_probe(uint8_t *out, int32_t cap) {
    if (g_lib) {
        put(out, cap, "loaded");
        return 1;
    }
    const char *cands[] = {
#if defined(_WIN32)
        "vendor/lib/wgpu_native.dll",
        "vendor/wgpu_native.dll",
        "wgpu_native.dll",
#elif defined(__APPLE__)
        "vendor/lib/libwgpu_native.dylib",
        "vendor/libwgpu_native.dylib",
        "libwgpu_native.dylib",
#else
        "vendor/lib/libwgpu_native.so",
        "vendor/libwgpu_native.so",
        "libwgpu_native.so",
#endif
        NULL,
    };
    // 环境变量优先：应用可把库放在任意位置（发行包形态）
    const char *env = getenv("MNG_WGPU_LIB");
    const char *err = "no candidate";
    if (env && env[0]) {
        err = dl_open(env);
        if (!err) {
            if (dl_sym("wgpuCreateInstance")) {
                put(out, cap, "loaded(env)");
                return 1;
            }
            put(out, cap, "env-lib 缺 wgpuCreateInstance");
            return 0;
        }
    }
    for (int i = 0; cands[i]; i++) {
        err = dl_open(cands[i]);
        if (!err) {
            if (dl_sym("wgpuCreateInstance")) {
                char buf[256];
                snprintf(buf, sizeof buf, "loaded(%s)", cands[i]);
                put(out, cap, buf);
                return 1;
            }
            put(out, cap, "库在但缺 wgpuCreateInstance");
            return 0;
        }
    }
    char buf[256];
    snprintf(buf, sizeof buf, "not-found: %s", err ? err : "?");
    put(out, cap, buf);
    return 0;
}
