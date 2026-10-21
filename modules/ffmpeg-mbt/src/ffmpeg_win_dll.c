//! Windows 运行期 dll 的查找路径：等价于 macOS 那边 link_flags 里的 `-rpath`。
//!
//! 构建期 prebuild.py 按需注入两个宏：
//! - `NG_FFMPEG_DELAYLOAD`：让 vendor 导入库对应的 5 个 dll **延迟加载**，exe 启动
//!   时不再要求它们就位；
//! - `NG_FFMPEG_BIN="<目录>"`：构建机上 `vendor/win/bin` 的绝对路径。
//!
//! `vf_rt_ready()` 在第一次用到 ffmpeg 前把这 5 个 dll 显式加载：先按系统默认顺序
//! （exe 同目录 / 系统目录 / PATH，发布时自带的 dll 走这里），找不到再到构建期记下
//! 的目录里找（`moon add` 的工程里 dll 就在 `.mooncakes` 下）。显式加载成功后，
//! 延迟加载的解析会命中已加载的模块，因此调用方不需要把 dll 复制到 exe 旁。
//!
//! 非 Windows 平台本文件只留一个恒真的 `vf_rt_ready()`，保持三平台同一份调用。

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#pragma comment(lib, "delayimp.lib")

#ifdef NG_FFMPEG_DELAYLOAD
#pragma comment(linker, "/DELAYLOAD:avformat-63.dll")
#pragma comment(linker, "/DELAYLOAD:avcodec-63.dll")
#pragma comment(linker, "/DELAYLOAD:swscale-10.dll")
#pragma comment(linker, "/DELAYLOAD:swresample-7.dll")
#pragma comment(linker, "/DELAYLOAD:avutil-61.dll")
#endif

#ifndef NG_FFMPEG_BIN
#define NG_FFMPEG_BIN ""
#endif

// 与 prebuild.py 的 WIN_LIBS 一一对应（同一份 BtbN win64-lgpl-shared 9.0 归档）。
static const char *const vf_dll_names[] = {
  "avformat-63.dll", "avcodec-63.dll", "swscale-10.dll",
  "swresample-7.dll", "avutil-61.dll",
};

#endif /* _WIN32 */

//! 运行期 dll 是否齐备（Windows 上会真的加载它们；其余平台恒为 1）。
//!
//! 返回 0 表示这台机器上找不到 ffmpeg 运行库，调用方应据此把 ffmpeg 后端判为
//! 不可用，而不是等到解码时才炸。
int vf_rt_ready(void) {
#ifdef _WIN32
  int n = (int)(sizeof(vf_dll_names) / sizeof(vf_dll_names[0]));
  for (int i = 0; i < n; i++) {
    HMODULE mod = LoadLibraryA(vf_dll_names[i]);
    if (mod == NULL && NG_FFMPEG_BIN[0] != '\0') {
      // 构建期记下的 vendor 目录：只在默认搜索失败时临时加进搜索路径，
      // 免得盖过用户自己放在 exe 旁的 dll（那才是发布时的正确形态）。
      SetDllDirectoryA(NG_FFMPEG_BIN);
      mod = LoadLibraryA(vf_dll_names[i]);
      SetDllDirectoryA(NULL);
    }
    if (mod == NULL) {
      return 0;
    }
  }
  return 1;
#else
  return 1;
#endif
}
