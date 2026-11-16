/* inspector 客户端桩（mnginsp_call）：一次性连接——发一行命令、收完整响应。
 * POSIX 走 AF_UNIX：connect + 写全量 + shutdown(SHUT_WR)（服务端据此判请求
 * 完）+ 读到 EOF（服务端 respond 后 shutdown）。收发都带超时
 * （SO_SNDTIMEO / SO_RCVTIMEO），卡死的应用不拖死 CLI。
 * Windows 走命名管道（\\.\pipe\moonbit-inspect-<slug>）：CreateFile 连接 +
 * WriteFile 长度前缀帧 + ReadFile 响应头与载荷 + CloseHandle。
 * 返回响应字节数；失败回负数（绝对值是 errno / GetLastError）。 */

#include <stdint.h>
#include <string.h>
#include <errno.h>

#if defined(_WIN32)

#include <windows.h>

static void mnginsp_wide(const char *prefix, const char *slug, wchar_t *out, int cap) {
  char raw[320];
  size_t pn = strlen(prefix);
  size_t sn = strlen(slug);
  if (pn >= sizeof(raw)) { pn = sizeof(raw) - 1; }
  if (pn + sn >= sizeof(raw)) { sn = sizeof(raw) - 1 - pn; }
  memcpy(raw, prefix, pn);
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

int32_t mnginsp_getuid(void) { return 0; }

int32_t mnginsp_call(const char *path, const char *slug, const char *req,
                     int32_t req_len, uint8_t *out, int32_t cap,
                     int32_t timeout_ms) {
  (void)path;
  if (slug == NULL || req == NULL || req_len <= 0 || out == NULL || cap <= 0) {
    return -EINVAL;
  }
  wchar_t pname[256];
  mnginsp_wide("\\\\.\\pipe\\moonbit-inspect-", slug, pname, 256);
  HANDLE h = CreateFileW(pname, GENERIC_READ | GENERIC_WRITE, 0, NULL,
                         OPEN_EXISTING, 0, NULL);
  if (h == INVALID_HANDLE_VALUE) {
    return -(int32_t)GetLastError();
  }
  DWORD mode = PIPE_READMODE_BYTE;
  SetNamedPipeHandleState(h, &mode, NULL, NULL);
  /* 长度前缀帧：[len:i32 LE][payload] */
  unsigned char head[4];
  head[0] = (unsigned char)(req_len & 255);
  head[1] = (unsigned char)((req_len >> 8) & 255);
  head[2] = (unsigned char)((req_len >> 16) & 255);
  head[3] = (unsigned char)((req_len >> 24) & 255);
  DWORD put = 0;
  if (!WriteFile(h, head, 4, &put, NULL) || put != 4) {
    DWORD e = GetLastError();
    CloseHandle(h);
    return -(int32_t)(e != 0 ? e : EIO);
  }
  int32_t off = 0;
  while (off < req_len) {
    if (!WriteFile(h, req + off, (DWORD)(req_len - off), &put, NULL) || put == 0) {
      DWORD e = GetLastError();
      CloseHandle(h);
      return -(int32_t)(e != 0 ? e : EIO);
    }
    off += (int32_t)put;
  }
  FlushFileBuffers(h);
  /* 读响应：4 字节长度 + 载荷 */
  DWORD got = 0;
  unsigned char rhead[4];
  int32_t have = 0;
  while (have < 4) {
    if (!ReadFile(h, rhead + have, 4 - have, &got, NULL) || got == 0) {
      CloseHandle(h);
      return -(int32_t)(GetLastError() != 0 ? (int32_t)GetLastError() : EIO);
    }
    have += (int32_t)got;
  }
  int32_t rlen = (int32_t)rhead[0] | ((int32_t)rhead[1] << 8) |
                 ((int32_t)rhead[2] << 16) | ((int32_t)rhead[3] << 24);
  if (rlen < 0 || rlen > cap) {
    CloseHandle(h);
    return -EMSGSIZE;
  }
  int32_t roff = 0;
  while (roff < rlen) {
    if (!ReadFile(h, out + roff, (DWORD)(rlen - roff), &got, NULL) || got == 0) {
      CloseHandle(h);
      return -(int32_t)(GetLastError() != 0 ? (int32_t)GetLastError() : EIO);
    }
    roff += (int32_t)got;
  }
  (void)timeout_ms; /* 管道同步读写：服务端响应即回，超时档留给信号中断 */
  CloseHandle(h);
  return rlen;
}

#else

#include <fcntl.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <time.h>
#include <unistd.h>

int32_t mnginsp_getuid(void) { return (int32_t)getuid(); }

static int mnginsp_deadline_ms(int32_t timeout_ms) {
  return timeout_ms > 0 ? timeout_ms : 5000;
}

/* 剩余毫秒（到期回 0）。 */
static int mnginsp_left_ms(const struct timespec *t0, int32_t timeout_ms) {
  struct timespec now;
  clock_gettime(CLOCK_MONOTONIC, &now);
  int elapsed = (int)((now.tv_sec - t0->tv_sec) * 1000 +
                      (now.tv_nsec - t0->tv_nsec) / 1000000);
  int left = mnginsp_deadline_ms(timeout_ms) - elapsed;
  return left > 0 ? left : 0;
}

int32_t mnginsp_call(const char *path, const char *slug, const char *req,
                     int32_t req_len, uint8_t *out, int32_t cap,
                     int32_t timeout_ms) {
  (void)slug;
  if (path == NULL || req == NULL || req_len <= 0 || out == NULL || cap <= 0) {
    return -EINVAL;
  }
  if (strlen(path) >= 104) {
    return -ENAMETOOLONG;
  }
  int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) {
    return -errno;
  }
  struct timeval tv;
  int tms = mnginsp_deadline_ms(timeout_ms);
  tv.tv_sec = tms / 1000;
  tv.tv_usec = (tms % 1000) * 1000;
  setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, sizeof(tv));
  setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, sizeof(tv));
  struct sockaddr_un addr;
  memset(&addr, 0, sizeof(addr));
  addr.sun_family = AF_UNIX;
  memcpy(addr.sun_path, path, strlen(path));
  if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
    int e = errno;
    close(fd);
    return -e;
  }
  struct timespec t0;
  clock_gettime(CLOCK_MONOTONIC, &t0);
  /* 请求全量写出（阻塞口 + 超时档；EINTR 重试） */
  int32_t off = 0;
  while (off < req_len) {
    ssize_t w = write(fd, req + off, (size_t)(req_len - off));
    if (w > 0) {
      off += (int32_t)w;
      continue;
    }
    if (w < 0 && errno == EINTR &&
        mnginsp_left_ms(&t0, timeout_ms) > 0) {
      continue;
    }
    int e = errno;
    close(fd);
    return -e;
  }
  shutdown(fd, SHUT_WR); /* 服务端据此判请求读完 */
  /* 读到 EOF = 响应完 */
  int32_t n = 0;
  while (n < cap) {
    ssize_t r = read(fd, out + n, (size_t)(cap - n));
    if (r > 0) {
      n += (int32_t)r;
      continue;
    }
    if (r == 0) {
      break; /* 服务端 shutdown：响应完 */
    }
    if (errno == EINTR && mnginsp_left_ms(&t0, timeout_ms) > 0) {
      continue;
    }
    int e = errno;
    close(fd);
    return -e;
  }
  close(fd);
  return n;
}

#endif

/* ---- 非阻塞调用（GUI 检查器）：工作线程跑一次阻塞收发 ----
 * 主线程 begin 发起即返回，每拍 poll 只看完成标记；响应缓冲由本文件持有，
 * take 时拷出并回收线程。单进程同时只允许一个在途请求（检查器窗口是
 * 单实例语义），再发回 -EBUSY。工作线程只走纯 C，不碰 MoonBit 运行时。 */

#include <stdlib.h>

#if !defined(_WIN32)
#include <pthread.h>
#endif

static volatile int g_ai_state = 0; /* 0=空闲 1=在途 2=完成待取 */
static int32_t g_ai_ret = 0;
static unsigned char *g_ai_buf = NULL;
static int32_t g_ai_buf_cap = 0;
static char *g_ai_req = NULL;
static int32_t g_ai_req_len = 0;
static char g_ai_path[128];
static char g_ai_slug[128];
static int32_t g_ai_timeout = 5000;

#if defined(_WIN32)
static HANDLE g_ai_thread = NULL;
#define MNG_AI_FENCE() MemoryBarrier()

static DWORD WINAPI mnginsp_worker(LPVOID arg) {
  (void)arg;
  int32_t r = mnginsp_call(g_ai_path, g_ai_slug, g_ai_req, g_ai_req_len,
                           g_ai_buf, g_ai_buf_cap, g_ai_timeout);
  g_ai_ret = r;
  MNG_AI_FENCE();
  g_ai_state = 2;
  return 0;
}

static int32_t mnginsp_thread_start(void) {
  g_ai_thread = CreateThread(NULL, 0, mnginsp_worker, NULL, 0, NULL);
  return g_ai_thread != NULL ? 0 : -(int32_t)GetLastError();
}

static void mnginsp_thread_join(void) {
  if (g_ai_thread != NULL) {
    WaitForSingleObject(g_ai_thread, INFINITE);
    CloseHandle(g_ai_thread);
    g_ai_thread = NULL;
  }
}
#else
static pthread_t g_ai_thread;
static int g_ai_thread_live = 0;
#define MNG_AI_FENCE() __sync_synchronize()

static void *mnginsp_worker(void *arg) {
  (void)arg;
  int32_t r = mnginsp_call(g_ai_path, g_ai_slug, g_ai_req, g_ai_req_len,
                           g_ai_buf, g_ai_buf_cap, g_ai_timeout);
  g_ai_ret = r;
  MNG_AI_FENCE();
  g_ai_state = 2;
  return NULL;
}

static int32_t mnginsp_thread_start(void) {
  if (pthread_create(&g_ai_thread, NULL, mnginsp_worker, NULL) != 0) {
    return -(int32_t)EAGAIN;
  }
  g_ai_thread_live = 1;
  return 0;
}

static void mnginsp_thread_join(void) {
  if (g_ai_thread_live) {
    pthread_join(g_ai_thread, NULL);
    g_ai_thread_live = 0;
  }
}
#endif

int32_t mnginsp_begin(const char *path, const char *slug, const char *req,
                      int32_t req_len, int32_t cap, int32_t timeout_ms) {
  if (path == NULL || slug == NULL || req == NULL || req_len <= 0 || cap <= 0) {
    return -EINVAL;
  }
  if (strlen(path) >= sizeof(g_ai_path) || strlen(slug) >= sizeof(g_ai_slug)) {
    return -ENAMETOOLONG;
  }
  if (g_ai_state != 0) {
    return -EBUSY;
  }
  if (g_ai_buf == NULL || g_ai_buf_cap < cap) {
    free(g_ai_buf);
    g_ai_buf = (unsigned char *)malloc((size_t)cap);
    if (g_ai_buf == NULL) {
      g_ai_buf_cap = 0;
      return -ENOMEM;
    }
    g_ai_buf_cap = cap;
  }
  free(g_ai_req);
  g_ai_req = (char *)malloc((size_t)req_len);
  if (g_ai_req == NULL) {
    return -ENOMEM;
  }
  memcpy(g_ai_req, req, (size_t)req_len);
  g_ai_req_len = req_len;
  memcpy(g_ai_path, path, strlen(path) + 1);
  memcpy(g_ai_slug, slug, strlen(slug) + 1);
  g_ai_timeout = timeout_ms > 0 ? timeout_ms : 5000;
  g_ai_ret = 0;
  g_ai_state = 1;
  MNG_AI_FENCE();
  int32_t rc = mnginsp_thread_start();
  if (rc != 0) {
    g_ai_state = 0;
    return rc;
  }
  return 0;
}

int32_t mnginsp_poll(void) {
  if (g_ai_state != 2) {
    return 0;
  }
  MNG_AI_FENCE();
  return 1;
}

int32_t mnginsp_take(uint8_t *out, int32_t cap) {
  if (g_ai_state != 2) {
    return -EAGAIN;
  }
  MNG_AI_FENCE();
  mnginsp_thread_join();
  int32_t r = g_ai_ret;
  g_ai_state = 0;
  free(g_ai_req);
  g_ai_req = NULL;
  g_ai_req_len = 0;
  if (r > 0) {
    if (out == NULL || cap <= 0) {
      return -EINVAL;
    }
    int32_t n = r < cap ? r : cap;
    memcpy(out, g_ai_buf, (size_t)n);
    return n;
  }
  return r;
}

void mnginsp_abort(void) {
  mnginsp_thread_join(); /* 空闲时无线程可收，join 是空操作 */
  g_ai_state = 0;
  g_ai_ret = 0;
  free(g_ai_req);
  g_ai_req = NULL;
  g_ai_req_len = 0;
}
