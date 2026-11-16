/* inspector 服务端桩（只读检查通道）。
 * 四符号 yi_insp_listen / yi_insp_poll / yi_insp_take / yi_insp_respond：
 * 应用进程内监听一个套接字，mng（inspect / mcp）连上来发一行命令、收回一段
 * TSV 响应。请求-响应走同一条连接：poll 收请求读到 EOF 置就绪（连接保留），
 * respond 把响应写回同一条连接再关。与单实例通道 yi_inst_* 互不复用——那边
 * 是单槽收完即关，这边写回后关；符号族分开，监听 fd 也各是各的。
 * 路径规则与单实例同目录、不同前缀：moonbit-inspect-<slug>.<uid>.sock。
 * Windows 命名管道臂在 gui/win/stub.c 的 _WIN32 分支（同符号族），本文件
 * 在 _WIN32 下为空——每个平台恰好一份定义。
 * 返回值约定同 shell 桩：>0 成功语义 / 0 无事件 / <0 失败，原因取 last_errno。
 */

#ifndef _WIN32

#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <unistd.h>

#define YI_INSP_CAP 4096     /* 单条请求上限（单行命令足够） */
#define YI_INSP_WRITE_MS 2000 /* 写回响应的单拍等待 */

static int yi_insp_listen_fd = -1;
static int yi_insp_conn_fd = -1; /* 请求收完保持打开，等 respond 写回 */
static char yi_insp_path[512];
static char yi_insp_buf[YI_INSP_CAP];
static int yi_insp_buf_len = 0;
static int yi_insp_ready = 0;
static int yi_insp_err = 0;

static int yi_insp_set_nonblock(int fd) {
  int fl = fcntl(fd, F_GETFL, 0);
  if (fl < 0) {
    yi_insp_err = errno;
    return -1;
  }
  if (fcntl(fd, F_SETFL, fl | O_NONBLOCK) < 0) {
    yi_insp_err = errno;
    return -1;
  }
  fcntl(fd, F_SETFD, FD_CLOEXEC);
  return 0;
}

static int yi_insp_fill_addr(const char *path, struct sockaddr_un *addr) {
  size_t n = strlen(path);
  if (n == 0 || n >= sizeof(addr->sun_path)) {
    yi_insp_err = ENAMETOOLONG;
    return -1;
  }
  memset(addr, 0, sizeof(*addr));
  addr->sun_family = AF_UNIX;
  memcpy(addr->sun_path, path, n);
  return 0;
}

/* 丢弃在途连接（上一请求未响应 / 残留）：连接是易失资源，保新弃旧 */
static void yi_insp_drop_conn(void) {
  if (yi_insp_conn_fd >= 0) {
    close(yi_insp_conn_fd);
    yi_insp_conn_fd = -1;
  }
  yi_insp_buf_len = 0;
  yi_insp_ready = 0;
}

int32_t yi_insp_listen(const char *path) {
  if (path == NULL) {
    yi_insp_err = EINVAL;
    return -1;
  }
  if (yi_insp_listen_fd >= 0) {
    return 1; /* 已在听：幂等，不覆盖旧通道 */
  }
  struct sockaddr_un addr;
  if (yi_insp_fill_addr(path, &addr) < 0) {
    return -1;
  }
  /* 先探活：connect 一下区分「对面真有人听」与「残桩」。应用被 kill -9
   * （dev 的 COLD 重启就这么干）不会 unlink 套接字文件，残桩会让 bind
   * 误报被占用、静默降级——probe 连得上才是真被占，连不上先清残桩。
   * 本地 AF_UNIX 的阻塞 connect 立即返回（成功 / ECONNREFUSED / ENOENT），
   * 无阻塞风险。 */
  int probe = socket(AF_UNIX, SOCK_STREAM, 0);
  if (probe >= 0) {
    if (connect(probe, (struct sockaddr *)&addr, sizeof(addr)) == 0) {
      close(probe);
      return 2; /* 对面有人在听：本进程让位，调用方按非 1 静默降级 */
    }
    close(probe);
  }
  unlink(path); /* 没人听：上个实例崩/被杀留下的残桩，清掉再 bind */
  int fd = socket(AF_UNIX, SOCK_STREAM, 0);
  if (fd < 0) {
    yi_insp_err = errno;
    return -1;
  }
  if (bind(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
    int saved = errno;
    close(fd);
    yi_insp_err = saved;
    /* 抢输了一档（罕见竞态）：调用方按非 1 静默降级不监听 */
    return (saved == EADDRINUSE) ? 2 : -1;
  }
  if (chmod(path, 0600) != 0) { /* 只让本用户连（文件名带 uid 是双保险） */
    int saved = errno;
    close(fd);
    unlink(path);
    yi_insp_err = saved;
    return -1;
  }
  if (listen(fd, 4) != 0 || yi_insp_set_nonblock(fd) < 0) {
    int saved = errno;
    close(fd);
    unlink(path);
    yi_insp_err = saved;
    return -1;
  }
  strncpy(yi_insp_path, path, sizeof(yi_insp_path) - 1);
  yi_insp_path[sizeof(yi_insp_path) - 1] = '\0';
  yi_insp_listen_fd = fd;
  return 1;
}

int32_t yi_insp_poll(void) {
  if (yi_insp_ready) {
    return 1;
  }
  if (yi_insp_listen_fd < 0) {
    return 0;
  }
  if (yi_insp_conn_fd >= 0) {
    yi_insp_drop_conn(); /* 上一请求没等到响应就来了新拍：保新弃旧 */
  }
  struct pollfd lp;
  lp.fd = yi_insp_listen_fd;
  lp.events = POLLIN;
  lp.revents = 0;
  if (poll(&lp, 1, 0) <= 0) {
    return 0;
  }
  int cfd = accept(yi_insp_listen_fd, NULL, NULL);
  if (cfd < 0) {
    return 0;
  }
  if (yi_insp_set_nonblock(cfd) < 0) {
    close(cfd);
    return 0;
  }
  yi_insp_conn_fd = cfd;
  yi_insp_buf_len = 0;
  for (;;) {
    int32_t room = YI_INSP_CAP - yi_insp_buf_len;
    if (room <= 0) { /* 超请求上限：整条丢掉 */
      yi_insp_err = E2BIG;
      yi_insp_drop_conn();
      return -1;
    }
    ssize_t n = read(yi_insp_conn_fd, yi_insp_buf + yi_insp_buf_len, (size_t)room);
    if (n > 0) {
      yi_insp_buf_len += (int)n;
      continue;
    }
    if (n == 0) { /* 对端 shutdown(SHUT_WR)：请求读完，连接留着写回响应 */
      if (yi_insp_buf_len == 0) {
        yi_insp_drop_conn(); /* 空连接：探活在测，不算请求 */
        return 0;
      }
      yi_insp_err = 0;
      yi_insp_ready = 1;
      return 1;
    }
    if (errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR) {
      return 0; /* 还没发完，下一拍继续读 */
    }
    yi_insp_err = errno;
    yi_insp_drop_conn();
    return -1;
  }
}

int32_t yi_insp_take(char *out, int32_t cap) {
  if (!yi_insp_ready) {
    return 0;
  }
  yi_insp_ready = 0;
  if (out == NULL || cap <= 0 || yi_insp_buf_len == 0) {
    return 0;
  }
  int n = yi_insp_buf_len < cap ? yi_insp_buf_len : cap;
  memcpy(out, yi_insp_buf, (size_t)n);
  yi_insp_buf_len = 0;
  return n;
}

int32_t yi_insp_respond(const char *data, int32_t len) {
  if (yi_insp_conn_fd < 0) {
    yi_insp_err = EINVAL;
    return -1;
  }
  int fd = yi_insp_conn_fd;
  yi_insp_conn_fd = -1;
  yi_insp_buf_len = 0;
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
      if (poll(&p, 1, YI_INSP_WRITE_MS) <= 0) {
        yi_insp_err = ETIMEDOUT;
        close(fd);
        return -2;
      }
      continue;
    }
    yi_insp_err = errno;
    close(fd);
    return -2; /* 客户端先走了：响应丢弃，不重试 */
  }
  shutdown(fd, SHUT_WR); /* 客户端据此判响应读完 */
  close(fd);
  return 1;
}

int32_t yi_insp_last_errno(void) { return yi_insp_err; }

int32_t yi_insp_getuid(void) { return (int32_t)getuid(); }

#endif /* !_WIN32 */
