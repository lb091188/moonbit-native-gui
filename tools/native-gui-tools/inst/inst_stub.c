// 单实例客户端（inst.mbt 的 C 端）：connect + 全量写出 + shutdown(SHUT_WR)。
// 帧边界 = 连接关闭（与 gui/shell 单实例通道同口径）。Windows 为失败桩。

#include <stdint.h>

static int32_t mnginst_err = 0;

int32_t mnginst_last_errno(void) { return mnginst_err; }

#if defined(_WIN32)

int32_t mnginst_wake(const char *path, const char *data, int32_t len) {
  (void)path;
  (void)data;
  (void)len;
  return -1;
}

int32_t mnginst_getuid(void) { return -1; }

#else

#include <errno.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

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
