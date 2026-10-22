// 单实例的 POSIX 套接字臂（`shell/instance.mbt` 的 socket 后端）：一个 AF_UNIX
// 流式套接字同时充当「进程唯一」判据与「唤起已有实例」的通道。
//   listen：先试 connect——连得上就是已有实例在听；连不上就清残桩、bind + listen
//           成为首实例。bind 撞 EADDRINUSE（并发起第二家抢到了）按已有实例算。
//   wake  ：connect + 全量写出 + shutdown(SHUT_WR) 后收尾。帧边界 = 连接关闭，
//           收端读到 EOF 即拿到完整载荷。不等回执：回执得由首实例的泵来发，
//           同一拍里唤起方自己不会泵，同进程自测时更是自等。
//   poll  ：每拍抽一次；监听 fd 有可读就 accept，连接上的字节攒进静态缓冲。
// 只用标准头，故直接走 moon 的 native-stub；链接参数按 AGENTS 规则 1 由
// scripts/prebuild.py 托管（本桩无新增）。Windows 臂（命名互斥体 + WM_COPYDATA）
// 在 win/stub.c，这里对 _WIN32 编译失败桩。
// 返回值约定：>0 成功语义 / 0 无事件 / <0 失败，原因取 yi_inst_last_errno。

#include <errno.h>
#include <stdint.h>
#include <string.h>

#if defined(_WIN32)

int32_t yi_inst_listen(const char *path) {
  (void)path;
  return -1;
}

int32_t yi_inst_wake(const char *path, const char *data, int32_t len) {
  (void)path;
  (void)data;
  (void)len;
  return -1;
}

int32_t yi_inst_poll(void) { return -1; }

int32_t yi_inst_take(char *out, int32_t cap) {
  (void)out;
  (void)cap;
  return 0;
}

int32_t yi_inst_last_errno(void) { return 0; }

int32_t yi_inst_getuid(void) { return -1; }

#else

#include <fcntl.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <sys/stat.h>
#include <unistd.h>

#define YI_INST_CAP 65536      // 单帧载荷上限（与门面常量同值）
#define YI_INST_CONNECT_MS 1000
#define YI_INST_WRITE_MS 2000

static int yi_listen_fd = -1;
static int yi_conn_fd = -1;
static char yi_path[512];
static char yi_buf[YI_INST_CAP];
static int yi_buf_len = 0;
static int yi_ready = 0;
static int yi_errno = 0;

// 非阻塞 + 执行时关闭：macOS 没有 SOCK_NONBLOCK/SOCK_CLOEXEC，两条都靠 fcntl 补，
// 因此本桩不使用那两个创建标志（Linux 也一样走 fcntl，同一份代码两平台可编）。
static int yi_set_nonblock(int fd) {
  int fl = fcntl(fd, F_GETFL, 0);
  if (fl < 0) {
    yi_errno = errno;
    return -1;
  }
  if (fcntl(fd, F_SETFL, fl | O_NONBLOCK) < 0) {
    yi_errno = errno;
    return -1;
  }
  fcntl(fd, F_SETFD, FD_CLOEXEC);
  return 0;
}

// 填 sockaddr_un（路径长度按 sun_path 容量校验）。给 0 表示可用。
static int yi_fill_addr(const char *path, struct sockaddr_un *addr) {
  size_t n = strlen(path);
  if (n == 0 || n >= sizeof(addr->sun_path)) {
    yi_errno = ENAMETOOLONG;
    return -1;
  }
  memset(addr, 0, sizeof(*addr));
  addr->sun_family = AF_UNIX;
  memcpy(addr->sun_path, path, n);
  return 0;
}

// 连到套接字文件。>=0 是已连上的 fd，<0 表示对面没有活的首实例。
static int yi_make_client(const char *path, struct sockaddr_un *addr) {
  int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) {
    yi_errno = errno;
    return -1;
  }
  if (yi_set_nonblock(fd) < 0 ||
      connect(fd, (struct sockaddr *)addr, sizeof(*addr)) != 0) {
    int saved = errno;
    if (saved != EINTR && saved != EAGAIN && saved != EALREADY &&
        saved != EINPROGRESS) {
      yi_errno = saved;
      close(fd);
      return -1;
    }
    struct pollfd p;
    p.fd = fd;
    p.events = POLLOUT;
    p.revents = 0;
    int r = poll(&p, 1, YI_INST_CONNECT_MS);
    int err = 0;
    if (r > 0) {
      socklen_t l = sizeof(err);
      getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &l);
    }
    if (r <= 0 || err != 0) {
      yi_errno = (r == 0) ? ETIMEDOUT : (err != 0 ? err : errno);
      close(fd);
      return -1;
    }
  }
  return fd;
}

int32_t yi_inst_listen(const char *path) {
  if (path == NULL) {
    yi_errno = EINVAL;
    return -1;
  }
  // 同进程对同一套接字重复声称：已经是首实例，幂等。
  if (yi_listen_fd >= 0 && strncmp(yi_path, path, sizeof(yi_path)) == 0) {
    return 1;
  }
  struct sockaddr_un addr;
  if (yi_fill_addr(path, &addr) < 0) {
    return -1;
  }
  int probe = yi_make_client(path, &addr);
  if (probe >= 0) {
    close(probe);
    return 2; // 对面有人：本进程不是首实例
  }
  unlink(path); // 上个首实例崩在这儿留下的残桩
  int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) {
    yi_errno = errno;
    return -1;
  }
  if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
    int saved = errno;
    close(fd);
    yi_errno = saved;
    return (saved == EADDRINUSE) ? 2 : -1; // 抢输了一档，按已有实例算
  }
  chmod(path, 0600); // 只让本用户连（文件名里还带了 uid，这层是双保险）
  if (listen(fd, 16) != 0 || yi_set_nonblock(fd) < 0) {
    int saved = errno;
    close(fd);
    unlink(path);
    yi_errno = saved;
    return -1;
  }
  yi_listen_fd = fd;
  strncpy(yi_path, path, sizeof(yi_path) - 1);
  yi_path[sizeof(yi_path) - 1] = '\0';
  return 1;
}

int32_t yi_inst_wake(const char *path, const char *data, int32_t len) {
  if (path == NULL || data == NULL || len < 0 || len > YI_INST_CAP) {
    yi_errno = EINVAL;
    return -1;
  }
  struct sockaddr_un addr;
  if (yi_fill_addr(path, &addr) < 0) {
    return -1;
  }
  int fd = yi_make_client(path, &addr);
  if (fd < 0) {
    return -1; // 连不上：没有可唤起的首实例
  }
  int32_t off = 0;
  while (off < len) {
    ssize_t w = write(fd, data + off, (size_t)(len - off));
    if (w > 0) {
      off += (int32_t)w;
      continue;
    }
    if (w < 0 && (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR)) {
      struct pollfd p;
      p.fd = fd;
      p.events = POLLOUT;
      p.revents = 0;
      if (poll(&p, 1, YI_INST_WRITE_MS) <= 0) {
        yi_errno = ETIMEDOUT;
        close(fd);
        return -2;
      }
      continue;
    }
    yi_errno = errno;
    close(fd);
    return -2;
  }
  shutdown(fd, SHUT_WR); // 收端据此判定帧读完
  close(fd);
  return 1;
}

int32_t yi_inst_poll(void) {
  if (yi_ready) {
    return 1;
  }
  // 先接新连接（一拍一条），再当场把字节读完：写完即关的帧要在同一拍出结果
  if (yi_listen_fd >= 0 && yi_conn_fd < 0) {
    struct pollfd lp;
    lp.fd = yi_listen_fd;
    lp.events = POLLIN;
    lp.revents = 0;
    if (poll(&lp, 1, 0) > 0) {
      int cfd = accept(yi_listen_fd, NULL, NULL);
      if (cfd >= 0) {
        if (yi_set_nonblock(cfd) < 0) {
          close(cfd);
        } else {
          yi_conn_fd = cfd;
          yi_buf_len = 0;
        }
      }
    }
  }
  if (yi_conn_fd < 0) {
    return 0;
  }
  for (;;) {
    int32_t room = YI_INST_CAP - yi_buf_len;
    if (room <= 0) { // 超帧长上限：整条丢掉，别让半条帧冒充一次唤起
      yi_errno = E2BIG;
      close(yi_conn_fd);
      yi_conn_fd = -1;
      yi_buf_len = 0;
      return -1;
    }
    ssize_t n = read(yi_conn_fd, yi_buf + yi_buf_len, (size_t)room);
    if (n > 0) {
      yi_buf_len += (int)n;
      continue;
    }
    if (n == 0) { // 对端已 shutdown(SHUT_WR)：帧完整
      yi_errno = 0;
      close(yi_conn_fd);
      yi_conn_fd = -1;
      yi_ready = 1;
      return 1;
    }
    if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) {
      return 0;
    }
    yi_errno = errno;
    close(yi_conn_fd);
    yi_conn_fd = -1;
    yi_buf_len = 0;
    return -1;
  }
}

int32_t yi_inst_take(char *out, int32_t cap) {
  if (!yi_ready || out == NULL || cap <= 0 || yi_buf_len == 0) {
    return 0;
  }
  int n = yi_buf_len < cap ? yi_buf_len : cap;
  memcpy(out, yi_buf, (size_t)n);
  yi_ready = 0;
  yi_buf_len = 0;
  return n;
}

int32_t yi_inst_last_errno(void) { return yi_errno; }

int32_t yi_inst_getuid(void) { return (int32_t)getuid(); }

#endif
