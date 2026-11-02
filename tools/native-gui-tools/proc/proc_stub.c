// 工具侧进程原语（proc.mbt 的 C 端）。只用标准头：POSIX 走 fork/execvp +
// setpgid 成组；Windows 走 CreateProcessW。不解析引号——argv 由 MoonBit 侧拼成
// `\0` 分隔的 blob。

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

static int32_t mngpr_err = 0;

int32_t mngpr_last_errno(void) { return mngpr_err; }

#if defined(_WIN32)

#include <windows.h>
#include <wchar.h>

static wchar_t *mngpr_wide(const char *s) {
  if (s == NULL) {
    return NULL;
  }
  int n = MultiByteToWideChar(CP_UTF8, 0, s, -1, NULL, 0);
  if (n <= 0) {
    return NULL;
  }
  wchar_t *w = (wchar_t *)calloc((size_t)n, sizeof(wchar_t));
  MultiByteToWideChar(CP_UTF8, 0, s, -1, w, n);
  return w;
}

// blob → 一条命令行：各参数按 Windows 规则加引号（内嵌引号转义）。
// blob → 一条命令行：参数按空白分隔加双引号（内嵌引号不转义——工具侧参数
// 来自本进程命令行，不含引号的约定记在包注释）。
static wchar_t *mngpr_cmdline(const char *file, const char *blob, int32_t len) {
  const size_t cap = 16384;
  wchar_t *out = (wchar_t *)calloc(cap, sizeof(wchar_t));
  if (out == NULL) {
    return NULL;
  }
  wchar_t *wf = mngpr_wide(file);
  if (wf == NULL) {
    free(out);
    return NULL;
  }
  size_t used = wcslen(wf);
  wcscpy(out, wf);
  free(wf);
  int32_t i = 0;
  while (i < len) {
    int32_t seg0 = i;
    while (i < len && blob[i] != '\0') {
      i++;
    }
    if (i > seg0) {
      char *seg = (char *)malloc((size_t)(i - seg0) + 1);
      if (seg != NULL) {
        memcpy(seg, blob + seg0, (size_t)(i - seg0));
        seg[i - seg0] = '\0';
        wchar_t *w = mngpr_wide(seg);
        free(seg);
        if (w != NULL) {
          size_t wl = wcslen(w);
          if (used + wl + 4 < cap) {
            out[used++] = L' ';
            out[used++] = L'"';
            wcscpy(out + used, w);
            used += wl;
            out[used++] = L'"';
            out[used] = 0;
          }
          free(w);
        }
      }
    }
    i++;
  }
  return out;
}

int32_t mngpr_run_wait(const char *file, const char *blob, int32_t len,
                       int32_t timeout_ms) {
  wchar_t *cmd = mngpr_cmdline(file, blob, len);
  if (cmd == NULL) {
    mngpr_err = (int32_t)GetLastError();
    return -1;
  }
  STARTUPINFOW si;
  PROCESS_INFORMATION pi;
  memset(&si, 0, sizeof(si));
  si.cb = sizeof(si);
  memset(&pi, 0, sizeof(pi));
  if (!CreateProcessW(NULL, cmd, NULL, NULL, TRUE, CREATE_NEW_PROCESS_GROUP,
                      NULL, NULL, &si, &pi)) {
    mngpr_err = (int32_t)GetLastError();
    free(cmd);
    return -1;
  }
  free(cmd);
  DWORD w = WaitForSingleObject(pi.hProcess, (DWORD)timeout_ms);
  if (w == WAIT_TIMEOUT) {
    TerminateProcess(pi.hProcess, 1);
    WaitForSingleObject(pi.hProcess, 5000);
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    return -2;
  }
  DWORD code = 0;
  GetExitCodeProcess(pi.hProcess, &code);
  CloseHandle(pi.hThread);
  CloseHandle(pi.hProcess);
  return (int32_t)code;
}

int32_t mngpr_spawn(const char *file, const char *blob, int32_t len,
                    const char *out_path) {
  wchar_t *cmd = mngpr_cmdline(file, blob, len);
  if (cmd == NULL) {
    mngpr_err = (int32_t)GetLastError();
    return -1;
  }
  STARTUPINFOW si;
  PROCESS_INFORMATION pi;
  memset(&si, 0, sizeof(si));
  si.cb = sizeof(si);
  HANDLE hout = INVALID_HANDLE_VALUE;
  if (out_path != NULL && out_path[0] != '\0') {
    wchar_t *w = mngpr_wide(out_path);
    if (w != NULL) {
      hout = CreateFileW(w, FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE,
                         NULL, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
      free(w);
      if (hout != INVALID_HANDLE_VALUE) {
        si.dwFlags |= STARTF_USESTDHANDLES;
        si.hStdOutput = hout;
        si.hStdError = hout;
        si.hStdInput = GetStdHandle(STD_INPUT_HANDLE);
      }
    }
  }
  memset(&pi, 0, sizeof(pi));
  BOOL ok = CreateProcessW(NULL, cmd, NULL, NULL, TRUE, 0, NULL, NULL, &si, &pi);
  mngpr_err = ok ? 0 : (int32_t)GetLastError();
  free(cmd);
  if (hout != INVALID_HANDLE_VALUE) {
    CloseHandle(hout);
  }
  if (!ok) {
    return -1;
  }
  int32_t pid = (int32_t)pi.dwProcessId;
  CloseHandle(pi.hThread);
  CloseHandle(pi.hProcess);
  return pid;
}

int32_t mngpr_alive(int32_t pid) {
  if (pid <= 0) {
    return 0;
  }
  HANDLE h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, (DWORD)pid);
  if (h == NULL) {
    return 0;
  }
  DWORD code = 0;
  int32_t rc = 0;
  if (GetExitCodeProcess(h, &code) && code == STILL_ACTIVE) {
    rc = 1;
  }
  CloseHandle(h);
  return rc;
}

int32_t mngpr_kill(int32_t pid) {
  if (pid <= 0) {
    return 0;
  }
  HANDLE h = OpenProcess(PROCESS_TERMINATE, FALSE, (DWORD)pid);
  if (h == NULL) {
    mngpr_err = (int32_t)GetLastError();
    return 0;
  }
  BOOL ok = TerminateProcess(h, 1);
  CloseHandle(h);
  mngpr_err = ok ? 0 : (int32_t)GetLastError();
  return ok ? 1 : 0;
}

void mngpr_sleep_ms(int32_t ms) {
  if (ms > 0) {
    Sleep((DWORD)ms);
  }
}

#else

#include <unistd.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <signal.h>
#include <fcntl.h>

// blob → argv（条目指向 blob 内部，不拷贝；空条目跳过）。
static char **mngpr_argv(const char *file, const char *blob, int32_t len, int32_t *argc) {
  int32_t n = 0;
  for (int32_t i = 0; i < len; i++) {
    if (blob[i] == '\0') {
      n++;
    }
  }
  char **v = (char **)calloc((size_t)n + 3, sizeof(char *));
  if (v == NULL) {
    *argc = 0;
    return NULL;
  }
  int32_t k = 1;
  v[0] = (char *)file;
  int32_t start = 0;
  for (int32_t i = 0; i < len; i++) {
    if (blob[i] == '\0') {
      if (i > start) {
        v[k++] = (char *)(blob + start);
      }
      start = i + 1;
    }
  }
  v[k] = NULL;
  *argc = k;
  return v;
}

int32_t mngpr_run_wait(const char *file, const char *blob, int32_t len,
                       int32_t timeout_ms) {
  if (file == NULL || file[0] == '\0') {
    mngpr_err = EINVAL;
    return -1;
  }
  if (access(file, X_OK) != 0) {
    mngpr_err = errno;
    return -1;
  }
  int32_t argc = 0;
  char **argv = mngpr_argv(file, blob, len, &argc);
  if (argv == NULL) {
    mngpr_err = ENOMEM;
    return -1;
  }
  pid_t pid = fork();
  if (pid < 0) {
    mngpr_err = errno;
    free(argv);
    return -1;
  }
  if (pid == 0) {
    setpgid(0, 0);
    execvp(file, argv);
    _exit(127);
  }
  free(argv);
  int status = 0;
  int waited = 0;
  while (1) {
    pid_t r = waitpid(pid, &status, WNOHANG);
    if (r == pid) {
      break;
    }
    if (timeout_ms > 0 && waited >= timeout_ms) {
      kill(-pid, SIGTERM);
      kill(pid, SIGTERM);
      int soft = 0;
      while (soft < 1000) {
        pid_t r2 = waitpid(pid, &status, WNOHANG);
        if (r2 == pid) {
          return -2;
        }
        usleep(20000);
        soft += 20;
      }
      kill(-pid, SIGKILL);
      kill(pid, SIGKILL);
      waitpid(pid, &status, 0);
      return -2;
    }
    usleep(20000);
    waited += 20;
  }
  if (WIFEXITED(status)) {
    return WEXITSTATUS(status);
  }
  if (WIFSIGNALED(status)) {
    return 128 + WTERMSIG(status);
  }
  return -1;
}

int32_t mngpr_spawn(const char *file, const char *blob, int32_t len,
                    const char *out_path) {
  if (file == NULL || file[0] == '\0') {
    mngpr_err = EINVAL;
    return -1;
  }
  int32_t argc = 0;
  char **argv = mngpr_argv(file, blob, len, &argc);
  if (argv == NULL) {
    mngpr_err = ENOMEM;
    return -1;
  }
  pid_t pid = fork();
  if (pid < 0) {
    mngpr_err = errno;
    free(argv);
    return -1;
  }
  if (pid == 0) {
    setpgid(0, 0);
    if (out_path != NULL && out_path[0] != '\0') {
      int fd = open(out_path, O_WRONLY | O_CREAT | O_APPEND, 0644);
      if (fd >= 0) {
        dup2(fd, 1);
        dup2(fd, 2);
        close(fd);
      }
    }
    execvp(file, argv);
    _exit(127);
  }
  free(argv);
  return (int32_t)pid;
}

int32_t mngpr_alive(int32_t pid) {
  if (pid <= 0) {
    return 0;
  }
  int status = 0;
  pid_t r = waitpid((pid_t)pid, &status, WNOHANG);
  if (r == (pid_t)pid) {
    return 0; // 已退出（顺带收尸）
  }
  if (r == 0) {
    return 1;
  }
  // 不是本进程的子进程（ECHILD）：用 kill(0) 探活
  return kill((pid_t)pid, 0) == 0 ? 1 : 0;
}

int32_t mngpr_kill(int32_t pid) {
  if (pid <= 0) {
    return 0;
  }
  int a = kill(-(pid_t)pid, SIGTERM);
  int b = kill((pid_t)pid, SIGTERM);
  if (a != 0 && b != 0) {
    mngpr_err = errno;
    return 0;
  }
  return 1;
}

void mngpr_sleep_ms(int32_t ms) {
  if (ms > 0) {
    usleep((useconds_t)ms * 1000);
  }
}

#endif
