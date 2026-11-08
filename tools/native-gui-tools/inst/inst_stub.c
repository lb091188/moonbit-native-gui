// 单实例客户端（inst.mbt 的 C 端）。
// POSIX（Linux/macOS）：AF_UNIX connect + 全量写出 + shutdown(SHUT_WR)，
// 帧边界 = 连接关闭（与 gui/shell 单实例通道同口径）。
// Windows：WM_COPYDATA 直发首实例的隐藏消息窗口——服务端（gui/win/stub.c 的
// wm_inst_wndproc）本就吃这条消息（GUI 第二实例同款），类名口径
// `moonbit_libyue_instance_<slug>` 与魔数 0x59756549 必须与那边逐字一致；
// 改 gui 侧这两个值时本文件同批改。

#include <stdint.h>

static int32_t mnginst_err = 0;

int32_t mnginst_last_errno(void) { return mnginst_err; }

#if defined(_WIN32)

#ifndef UNICODE
#define UNICODE
#endif
#ifndef _UNICODE
#define _UNICODE
#endif
#include <windows.h>

/* FindWindowW / SendMessageTimeoutW 在 user32，而本模块没有 prebuild 下发链接参数
 * （tools 是独立模块，不挂 --moonbit-unstable-prebuild）。用 MSVC 的
 * `#pragma comment(lib, ...)` 把 /DEFAULTLIB 写进本 TU 的 `.drectve` 段：
 * 链接器抽到 inst_stub.obj 时自动带上 user32.lib，依赖方零配置、无需改链接行。
 * 与 win_gui.c 的 `#pragma comment(linker, ...)`、ffmpeg_win_dll.c 的
 * `#pragma comment(lib, "delayimp.lib")` 同一机制。 */
#pragma comment(lib, "user32.lib")

/* 与 gui/win/stub.c 的 WM_INST_MAGIC / WM_INST_CLASS_PREFIX 同值（见文件头）。 */
#define MNGINST_MAGIC 0x59756549
#define MNGINST_CLASS_PREFIX "moonbit_libyue_instance_"

/* UTF-8 slug → 宽类名（非 [A-Za-z0-9_-] 换 '_'，与 gui 侧 wm_inst_wide 同口径；
 * slug 本就是门面派生过的安全串）。 */
static void mnginst_class(const char *slug, wchar_t *out, int cap) {
  char raw[320];
  size_t pn = sizeof(MNGINST_CLASS_PREFIX) - 1;
  size_t sn = strlen(slug);
  if (pn >= sizeof(raw)) {
    pn = sizeof(raw) - 1;
  }
  if (pn + sn >= sizeof(raw)) {
    sn = sizeof(raw) - 1 - pn;
  }
  memcpy(raw, MNGINST_CLASS_PREFIX, pn);
  for (size_t i = 0; i < sn; i++) {
    unsigned char c = (unsigned char)slug[i];
    raw[pn + i] =
        ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
         (c >= '0' && c <= '9') || c == '_' || c == '-') ? (char)c : '_';
  }
  raw[pn + sn] = '\0';
  memset(out, 0, (size_t)cap * sizeof(wchar_t));
  MultiByteToWideChar(CP_UTF8, 0, raw, -1, out, cap);
}

int32_t mnginst_is_windows(void) { return 1; }

/* slug → FindWindowW → WM_COPYDATA（与 gui/win/stub.c 的 wm_inst_wake 同构：
 * 1 = 对方收下并回执，-1 = 找不到首实例窗口，-2 = 发送失败/对方挂死）。 */
int32_t mnginst_wake_win(const char *slug, const char *data, int32_t len) {
  if (slug == NULL || data == NULL || len <= 0 || len > 65536) {
    mnginst_err = ERROR_INVALID_PARAMETER;
    return -1;
  }
  wchar_t class_name[256];
  mnginst_class(slug, class_name, 256);
  HWND target = FindWindowW(class_name, NULL);
  if (target == NULL) {
    mnginst_err = ERROR_NOT_FOUND;
    return -1;
  }
  COPYDATASTRUCT cds;
  cds.dwData = MNGINST_MAGIC;
  cds.cbData = (DWORD)len;
  cds.lpData = (void *)data;
  LRESULT res = 0;
  if (!SendMessageTimeoutW(target, WM_COPYDATA, 0, (LPARAM)&cds,
                           SMTO_ABORTIFHUNG | SMTO_NORMAL, 3000, &res) ||
      !res) {
    mnginst_err = (int)GetLastError();
    return -2;
  }
  return 1;
}

/* 套接字客户端在 Windows 不可达（无 AF_UNIX 通路），占位保链接。 */
int32_t mnginst_wake(const char *path, const char *data, int32_t len) {
  (void)path;
  (void)data;
  (void)len;
  mnginst_err = ERROR_NOT_SUPPORTED;
  return -1;
}

int32_t mnginst_getuid(void) { return -1; }

#else

#include <errno.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

int32_t mnginst_is_windows(void) { return 0; }

/* 非 Windows 无 Win32 客户端，占位保链接。 */
int32_t mnginst_wake_win(const char *slug, const char *data, int32_t len) {
  (void)slug;
  (void)data;
  (void)len;
  mnginst_err = EINVAL;
  return -1;
}

int32_t mnginst_getuid(void) { return (int32_t)getuid(); }

int32_t mnginst_wake(const char *path, const char *data, int32_t len) {
  if (path == NULL) {
    mnginst_err = EINVAL;
    return -1;
  }
  struct sockaddr_un addr;
  memset(&addr, 0, sizeof(addr));
  addr.sun_family = AF_UNIX;
  size_t pl = strlen(path);
  if (pl >= sizeof(addr.sun_path)) {
    mnginst_err = ENAMETOOLONG;
    return -1;
  }
  memcpy(addr.sun_path, path, pl);
  int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) {
    mnginst_err = errno;
    return -1;
  }
  if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
    mnginst_err = errno;
    close(fd);
    return -1;
  }
  int32_t off = 0;
  while (off < len) {
    ssize_t w = write(fd, data + off, (size_t)(len - off));
    if (w <= 0) {
      mnginst_err = errno;
      close(fd);
      return -1;
    }
    off += (int32_t)w;
  }
  shutdown(fd, SHUT_WR);
  close(fd);
  return 1;
}

#endif
