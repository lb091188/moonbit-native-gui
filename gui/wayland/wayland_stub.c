/* Wayland 客户端的最小系统调用面（只用标准头）：Unix 流式套接字连接、
 * 读写、poll、close。fd 辅助数据（SCM_RIGHTS）本批不需要——data-control 的
 * receive 通道等协议客户落地时随 C 助手补。
 *
 * Windows 没有 Wayland：全桩返 -2（不可用），调用方按 Err 处理。
 */

#include <stdint.h>

#if defined(_WIN32)

int32_t yue_wl_unix_connect(const char *path) {
  (void)path;
  return -2;
}

int32_t yue_wl_read(int32_t fd, void *buf, int32_t off, int32_t len) {
  (void)fd;
  (void)buf;
  (void)off;
  (void)len;
  return -2;
}

int32_t yue_wl_write(int32_t fd, const void *buf, int32_t off, int32_t len) {
  (void)fd;
  (void)buf;
  (void)off;
  (void)len;
  return -2;
}

int32_t yue_wl_poll(int32_t fd, int32_t events, int32_t timeout_ms) {
  (void)fd;
  (void)events;
  (void)timeout_ms;
  return -2;
}

void yue_wl_close(int32_t fd) {
  (void)fd;
}

#else

#include <errno.h>
#include <poll.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

int32_t yue_wl_unix_connect(const char *path) {
  if (path == NULL) {
    return -2;
  }
  int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) {
    return -1;
  }
  struct sockaddr_un addr;
  memset(&addr, 0, sizeof addr);
  addr.sun_family = AF_UNIX;
  size_t n = strlen(path);
  if (n >= sizeof addr.sun_path) {
    close(fd);
    return -2;
  }
  memcpy(addr.sun_path, path, n);
  if (connect(fd, (struct sockaddr *)&addr, sizeof addr) < 0) {
    close(fd);
    return -1;
  }
  return (int32_t)fd;
}

int32_t yue_wl_read(int32_t fd, void *buf, int32_t off, int32_t len) {
  if (fd < 0 || buf == NULL || len <= 0) {
    return -2;
  }
  ssize_t n = read(fd, (char *)buf + off, (size_t)len);
  if (n > 0) {
    return (int32_t)n;
  }
  if (n == 0) {
    return 0; // EOF：对端关了
  }
  if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) {
    return -1; // 暂无数据/被打断
  }
  return -3; // 真错误
}

int32_t yue_wl_write(int32_t fd, const void *buf, int32_t off, int32_t len) {
  if (fd < 0 || buf == NULL || len <= 0) {
    return -2;
  }
  ssize_t n = write(fd, (const char *)buf + off, (size_t)len);
  if (n >= 0) {
    return (int32_t)n;
  }
  if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) {
    return -1;
  }
  return -3;
}

int32_t yue_wl_poll(int32_t fd, int32_t events, int32_t timeout_ms) {
  if (fd < 0) {
    return -2;
  }
  struct pollfd pfd;
  pfd.fd = fd;
  pfd.events = (short)events;
  pfd.revents = 0;
  int r = poll(&pfd, 1, timeout_ms);
  if (r <= 0) {
    return r;
  }
  return (int32_t)pfd.revents;
}

void yue_wl_close(int32_t fd) {
  if (fd >= 0) {
    close(fd);
  }
}

#endif
