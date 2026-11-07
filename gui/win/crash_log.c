// Windows 崩溃取证（诊断档，默认关）：设 NATIVEGUI_CRASH_LOG=1 后装一个
// 向量化异常处理器（VEH），异常发生就把「异常码 + 各栈帧所属模块与 RVA +
// 最近的面包屑」写进文件（默认 mng_crash.log，可用 NATIVEGUI_CRASH_FILE
// 改路径）。
//
// 为什么不符号化：moon 的 native 构建不产 .pdb（_build 下实测零个），
// dbghelp 拿不到函数名。面包屑是一条 64 项环形表——gui/win/stub.c 的热点
// 路径（present / WM_PAINT / 尺寸变化 / show·hide / 弹层上屏）各留一条，
// 崩溃时把「最后走到哪条路径、带什么参数」原样交出来，比无符号的地址表
// 好使得多。栈帧仍照写：模块名 + RVA 能区分是自家 exe 还是系统/第三方 dll。
//
// 只在 _WIN32 有实现；其余平台整篇编成空 TU（与 stub.c 的分支纪律一致，
// 调用点可以直接写，不用到处加宏）。

#if defined(_WIN32)

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

#define WM_CRASH_MARKS 64
#define WM_CRASH_FRAMES 24
#define WM_CRASH_MAX_DUMPS 8

typedef struct WmCrashMark {
  const char *label;
  long a;
  long b;
  DWORD tick;
} WmCrashMark;

static WmCrashMark g_marks[WM_CRASH_MARKS];
static volatile LONG g_mark_seq;
static volatile LONG g_on;
static volatile LONG g_dumping;
static volatile LONG g_dumps;

// 记一条面包屑。未开启时只有一个 load + branch（每帧几次，代价可忽略）。
void wm_crash_mark(const char *label, long a, long b) {
  if (!g_on || label == NULL) {
    return;
  }
  LONG seq = InterlockedIncrement(&g_mark_seq) - 1;
  WmCrashMark *m = &g_marks[(DWORD)seq % WM_CRASH_MARKS];
  m->label = label;
  m->a = a;
  m->b = b;
  m->tick = GetTickCount();
}

// ---- 落盘（不用 CRT：崩溃现场 stdio 不可信） ----
static HANDLE g_err; // stderr 镜像：文件写不出来时终端里也能看到现场

static void cl_write(HANDLE h, const char *s, DWORD n) {
  DWORD wrote = 0;
  WriteFile(h, s, n, &wrote, NULL);
}

static void cl_line(HANDLE h, const char *s) {
  DWORD n = (DWORD)lstrlenA(s);
  cl_write(h, s, n);
  cl_write(h, "\r\n", 2);
  if (g_err != NULL && g_err != INVALID_HANDLE_VALUE) {
    cl_write(g_err, s, n);
    cl_write(g_err, "\r\n", 2);
  }
}

// 往现场文件追加一行「过程日志」。GUI 子系统进程没有终端，stderr 常常看不见
// （PowerShell 重定向还会因为环境变量大小写重名而失败），所以 GPU 档那几条
// l1_log 也镜像到这里。只在取证档开启时写。
void wm_crash_note(const char *s) {
  if (!g_on || s == NULL || s[0] == 0) {
    return;
  }
  char path[MAX_PATH];
  DWORD n = GetEnvironmentVariableA("NATIVEGUI_CRASH_FILE", path, MAX_PATH);
  if (n == 0 || n >= MAX_PATH) {
    lstrcpynA(path, "mng_crash.log", MAX_PATH);
  }
  HANDLE h = CreateFileA(path, FILE_APPEND_DATA | GENERIC_WRITE,
                         FILE_SHARE_READ | FILE_SHARE_WRITE, NULL, OPEN_ALWAYS,
                         FILE_ATTRIBUTE_NORMAL, NULL);
  if (h == INVALID_HANDLE_VALUE) {
    return;
  }
  SetFilePointer(h, 0, NULL, FILE_END);
  char line[MAX_PATH + 96];
  wsprintfA(line, "note t=%lu %s\r\n", (unsigned long)GetTickCount(), s);
  cl_write(h, line, (DWORD)lstrlenA(line));
  CloseHandle(h);
}

// 一行「dll 全路径+偏移」：偏移按所在模块的加载基址算，ASLR 下也能对上。
static void cl_frame(HANDLE h, const char *prefix, void *addr) {
  char line[MAX_PATH + 96];
  char mod[MAX_PATH];
  mod[0] = 0;
  MEMORY_BASIC_INFORMATION mbi;
  if (VirtualQuery(addr, &mbi, sizeof mbi) == sizeof mbi &&
      mbi.AllocationBase != NULL) {
    GetModuleFileNameA((HMODULE)mbi.AllocationBase, mod, MAX_PATH);
    wsprintfA(line, "%s %s+0x%lx", prefix, mod,
              (unsigned long)((DWORD_PTR)addr - (DWORD_PTR)mbi.AllocationBase));
  } else {
    wsprintfA(line, "%s %p", prefix, addr);
  }
  cl_line(h, line);
}

static LONG CALLBACK wm_crash_veh(EXCEPTION_POINTERS *ep) {
  DWORD code = ep->ExceptionRecord->ExceptionCode;
  // 纯噪声，别刷日志、更别让它们占掉唯一一次落盘机会：
  //   0x40010006 / 0x4001000A = OutputDebugStringA/W（启动期第三方 dll 常发）
  //   0x40010005 = Ctrl+C 的 DBG_CONTROL_C
  //   0x80000003 = 断点
  //   0x406D1388 = SetThreadName（VS 远程调试常用，纯信息）
  // 0xE06D7363（MSVC C++ 异常码）**不能**跳过——Rust 的 panic 在 MSVC 目标上
  // 正是用它抛出（wgpu-native 是 Rust），跳过就等于把 GPU 侧的真实现场全漏掉。
  if (code == 0x40010006u || code == 0x4001000Au || code == 0x40010005u ||
      code == 0x80000003u || code == 0x406D1388u) {
    return EXCEPTION_CONTINUE_SEARCH;
  }
  // 允许落盘多次（上限 WM_CRASH_MAX_DUMPS）：文件是 CREATE_ALWAYS，后写的覆盖
  // 先写的，进程真死那一刻留下的就是致命的那个现场。只允许一次的话，任何一条
  // 被漏过滤的首发异常都会把真正的现场挤掉（本机实测踩过：启动期第三方 dll 的
  // 一条异常先把文件占死，真正崩在最小化时反而没写）。
  if (InterlockedExchange(&g_dumping, 1) != 0) {
    return EXCEPTION_CONTINUE_SEARCH; // 正在写盘的重入，不参与
  }
  if (InterlockedIncrement(&g_dumps) > WM_CRASH_MAX_DUMPS) {
    InterlockedExchange(&g_dumping, 0);
    return EXCEPTION_CONTINUE_SEARCH;
  }
  char path[MAX_PATH];
  DWORD n = GetEnvironmentVariableA("NATIVEGUI_CRASH_FILE", path, MAX_PATH);
  if (n == 0 || n >= MAX_PATH) {
    lstrcpynA(path, "mng_crash.log", MAX_PATH);
  }
  HANDLE h = CreateFileA(path, GENERIC_WRITE, FILE_SHARE_READ, NULL,
                         CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, NULL);
  if (h != INVALID_HANDLE_VALUE) {
    char line[256];
    wsprintfA(line, "mng-crash pid=%lu tid=%lu code=0x%08lx",
              GetCurrentProcessId(), GetCurrentThreadId(), (unsigned long)code);
    cl_line(h, line);
    cl_frame(h, "fault   ", (void *)ep->ExceptionRecord->ExceptionAddress);
    void *frames[WM_CRASH_FRAMES];
    USHORT got = RtlCaptureStackBackTrace(0, WM_CRASH_FRAMES, frames, NULL);
    for (USHORT i = 0; i < got; i++) {
      char pfx[24];
      wsprintfA(pfx, "stack[%2u]", (unsigned)i);
      cl_frame(h, pfx, frames[i]);
    }
    cl_line(h, "-- marks (newest first) --");
    LONG seq = g_mark_seq;
    int count = seq < WM_CRASH_MARKS ? (int)seq : WM_CRASH_MARKS;
    for (int i = 1; i <= count; i++) {
      LONG at = seq - i;
      WmCrashMark *m = &g_marks[(DWORD)at % WM_CRASH_MARKS];
      wsprintfA(line, "#%ld %s a=%ld b=%ld t=%lu", at, m->label, m->a, m->b,
                (unsigned long)m->tick);
      cl_line(h, line);
    }
    CloseHandle(h);
  }
  InterlockedExchange(&g_dumping, 0);
  return EXCEPTION_CONTINUE_SEARCH;
}

void wm_crash_install(void) {
  char v[8];
  DWORD n = GetEnvironmentVariableA("NATIVEGUI_CRASH_LOG", v, sizeof v);
  if (n == 0 || v[0] == '0' || v[0] == 0) {
    return;
  }
  InterlockedExchange(&g_on, 1);
  g_err = GetStdHandle(STD_ERROR_HANDLE);
  AddVectoredExceptionHandler(1, wm_crash_veh);
}

#else /* 其余平台：空实现，调用点照写 */

void wm_crash_install(void) {}

void wm_crash_note(const char *s) {
  (void)s;
}

void wm_crash_mark(const char *label, long a, long b) {
  (void)label;
  (void)a;
  (void)b;
}

#endif /* _WIN32 */
