// env_stub.c —— native-env 采集桩
//
// 一个文件三平台真分支 + 互斥占位：所有 envx_* 符号在所有平台都有定义，
// MoonBit 侧 extern 声明不分平台；非本平台函数返回「信号缺失」值（空串 / 0）。
// 链接零注入：Windows 的 user32 / advapi32 / dxgi 走 LoadLibraryW 运行期
// 装载，macOS 的 Metal 走 dlopen 运行期装载——装载失败按信号缺失处理；
// __cpuid 是编译器内建、sysctlbyname 在 libSystem，都不需要链接参数。
// Linux 零系统库调用，纯文件探测。
//
// 判据出处见 experience/environment-detection.md；本文件只采集不判定，
// 关键词、品牌表与结论聚合全在 MoonBit 侧（离线可测）。

#include <moonbit.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#if defined(_WIN32)
  #define ENVX_OS_WINDOWS 1
#elif defined(__APPLE__)
  #define ENVX_OS_MACOS 1
#elif defined(__linux__)
  #define ENVX_OS_LINUX 1
#endif

// -----
// 公共：C 字符串转 MoonBit Bytes

static moonbit_bytes_t envx_bytes_from(const char *s) {
  size_t n = strlen(s);
  moonbit_bytes_t b = moonbit_make_bytes((int32_t)n, 0);
  if (n > 0) {
    memcpy(b, s, n);
  }
  return b;
}

#ifdef ENVX_OS_WINDOWS
// -----
// Windows

#include <windows.h>
#include <intrin.h>

MOONBIT_FFI_EXPORT
moonbit_bytes_t envx_platform(void) {
  return envx_bytes_from("windows");
}

// CPUID 两行：`hv=<0|1>` 与 `sig=<12 字节 hypervisor 签名串>`。签名串可能带
// 尾随空格（如 "bhyve bhyve "），截断交给 MoonBit 侧 trim。签名串含尾部 NUL
// 前的全部字节——12 字节固定长度，snprintf 以 %s 打印会在首个 NUL 截断，
// 虚拟化厂商标定串中间无 NUL，实测可读（出处 systemd virt.c 同款读法）。
MOONBIT_FFI_EXPORT
moonbit_bytes_t envx_win_cpuid(void) {
  int regs[4];
  __cpuid(regs, 1);
  int hv = (regs[2] & (1 << 31)) != 0;
  char sig[13];
  memset(sig, 0, sizeof sig);
  if (hv) {
    __cpuid(regs, 0x40000000);
    memcpy(sig, &regs[1], 4);
    memcpy(sig + 4, &regs[2], 4);
    memcpy(sig + 8, &regs[3], 4);
    sig[12] = '\0';
  }
  char out[128];
  snprintf(out, sizeof out, "hv=%d\nsig=%s", hv, hv ? sig : "");
  return envx_bytes_from(out);
}

// 贴桌面的显示适配器名，一行一个（DISPLAY_DEVICE_ACTIVE 过滤——只列参与
// 桌面的适配器；状态位出处 windows.md 的 mon_list 经验）。
typedef BOOL (WINAPI *envx_fn_enum_display_devices_w)(LPCWSTR, DWORD, DISPLAY_DEVICEW *, DWORD);

MOONBIT_FFI_EXPORT
moonbit_bytes_t envx_win_adapters(void) {
  HMODULE user32 = LoadLibraryW(L"user32.dll");
  if (user32 == NULL) {
    return envx_bytes_from("");
  }
  envx_fn_enum_display_devices_w enum_dd =
    (envx_fn_enum_display_devices_w)(void *)GetProcAddress(user32, "EnumDisplayDevicesW");
  if (enum_dd == NULL) {
    return envx_bytes_from("");
  }
  char out[8192];
  size_t off = 0;
  for (DWORD i = 0;; i++) {
    DISPLAY_DEVICEW dd;
    memset(&dd, 0, sizeof dd);
    dd.cb = sizeof dd;
    if (!enum_dd(NULL, i, &dd, 0)) {
      break;
    }
    if ((dd.StateFlags & DISPLAY_DEVICE_ACTIVE) == 0) {
      continue;
    }
    char narrow[256];
    narrow[0] = '\0';
    WideCharToMultiByte(CP_UTF8, 0, dd.DeviceString, -1, narrow, (int)sizeof narrow, NULL, NULL);
    int w = snprintf(out + off, sizeof out - off, "%s\n", narrow);
    if (w < 0 || (size_t)w >= sizeof out - off) {
      break;
    }
    off += (size_t)w;
  }
  return envx_bytes_from(out);
}

// SMBIOS 注册表镜像两行加宿主标记一行：`man=` / `prod=` / `hvhost=`。
// 注册表镜像在 QEMU/SeaBIOS 这类固件上整个是空的（键在、值零个，实测见
// windows.md 2026-10-28）——空是常态不是错误。hvhost 标记宿主装了 Hyper-V
// 角色：此时 CPUID hypervisor 位与 Microsoft Hv 签名串在裸机上也会置位，
// 是裸机误报的头号来源，MoonBit 侧据此特判（出处 VMAware HYPERV_ARTIFACT）。
typedef LSTATUS (WINAPI *envx_fn_reg_get_value_w)(HKEY, LPCWSTR, LPCWSTR, DWORD, LPDWORD, PVOID, LPDWORD);
typedef LSTATUS (WINAPI *envx_fn_reg_open_key_w)(HKEY, LPCWSTR, PHKEY);
typedef LSTATUS (WINAPI *envx_fn_reg_close_key)(HKEY);

static void *envx_advapi_proc(const char *name) {
  HMODULE adv = LoadLibraryW(L"advapi32.dll");
  if (adv == NULL) {
    return NULL;
  }
  return (void *)GetProcAddress(adv, name);
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t envx_win_smbios(void) {
  char man[512] = "";
  char prod[512] = "";
  char hvhost[4] = "0";
  envx_fn_reg_get_value_w getv = (envx_fn_reg_get_value_w)envx_advapi_proc("RegGetValueW");
  envx_fn_reg_open_key_w openk = (envx_fn_reg_open_key_w)envx_advapi_proc("RegOpenKeyW");
  envx_fn_reg_close_key closek = (envx_fn_reg_close_key)envx_advapi_proc("RegCloseKey");
  if (getv != NULL) {
    DWORD cb = (DWORD)sizeof man;
    getv(HKEY_LOCAL_MACHINE, L"HARDWARE\\DESCRIPTION\\System\\BIOS", L"SystemManufacturer",
         RRF_RT_REG_SZ, NULL, man, &cb);
    if (getv(HKEY_LOCAL_MACHINE, L"HARDWARE\\DESCRIPTION\\System\\BIOS", L"SystemProductName",
             RRF_RT_REG_SZ, NULL, prod, &cb) != ERROR_SUCCESS) {
      prod[0] = '\0';
      cb = (DWORD)sizeof prod;
      getv(HKEY_LOCAL_MACHINE, L"HARDWARE\\DESCRIPTION\\System\\BIOS", L"SystemProductName",
           RRF_RT_REG_SZ, NULL, prod, &cb);
    }
  }
  if (openk != NULL) {
    HKEY k;
    if (openk(HKEY_LOCAL_MACHINE, L"SOFTWARE\\Microsoft\\Hyper-V", &k) == ERROR_SUCCESS) {
      if (closek != NULL) {
        closek(k);
      }
      memcpy(hvhost, "1", 2);
    }
  }
  char out[1200];
  snprintf(out, sizeof out, "man=%s\nprod=%s\nhvhost=%s", man, prod, hvhost);
  return envx_bytes_from(out);
}

// DXGI 首适配器的软件旗标：1 即 Microsoft 基本渲染（WARP）——系统显式标注
// 的软渲染，比适配器名关键词更硬的信号。dxgi.dll 运行期装载，COM 虚表手工
// 调用：IDXGIFactory1 第 12 槽 EnumAdapters1，IDXGIAdapter1 第 7 槽
// GetDesc1，旗标位 DXGI_ADAPTER_FLAG_SOFTWARE = 2（出处微软文档）。
typedef long HRESULT;
typedef const struct {
  unsigned long d1;
  unsigned short d2, d3;
  unsigned char d4[8];
} envx_guid;
typedef HRESULT (WINAPI *envx_fn_create_dxgi_factory1)(const envx_guid *, void **);
typedef HRESULT (WINAPI *envx_fn_enum_adapters1)(void *, unsigned int, void **);
typedef HRESULT (WINAPI *envx_fn_get_desc1)(void *, void *);
typedef unsigned long (WINAPI *envx_fn_com_release)(void *);

MOONBIT_FFI_EXPORT
int envx_win_dxgi_soft(void) {
  HMODULE dxgi = LoadLibraryW(L"dxgi.dll");
  if (dxgi == NULL) {
    return 0;
  }
  envx_fn_create_dxgi_factory1 create =
    (envx_fn_create_dxgi_factory1)(void *)GetProcAddress(dxgi, "CreateDXGIFactory1");
  if (create == NULL) {
    return 0;
  }
  static const envx_guid iid_factory1 =
    {0x770aae78UL, 0xf26c, 0x4b6a, {0x8f, 0x76, 0x5c, 0x15, 0xd7, 0x02, 0xd0, 0x74}};
  void *factory = NULL;
  if (FAILED(create(&iid_factory1, &factory)) || factory == NULL) {
    return 0;
  }
  envx_fn_com_release release = (envx_fn_com_release)((void ***)factory)[0][2];
  int soft = 0;
  void *adapter = NULL;
  envx_fn_enum_adapters1 enum_adapters1 = (envx_fn_enum_adapters1)((void ***)factory)[0][12];
  if (enum_adapters1 != NULL && SUCCEEDED(enum_adapters1(factory, 0, &adapter)) && adapter != NULL) {
    envx_fn_get_desc1 get_desc1 = (envx_fn_get_desc1)((void ***)adapter)[0][7];
    if (get_desc1 != NULL) {
      // 手抄 DXGI_ADAPTER_DESC1 布局：Description[128] + 五个 32 位 + 三个
      // SIZE_T + LUID(8 字节) + Flags(4 字节)，末成员只取 Flags。
      struct {
        wchar_t description[128];
        unsigned int vendor_id, device_id, sub_sys_id, revision;
        size_t dedicated_video, dedicated_system, shared_system;
        unsigned long long luid;
        unsigned int flags;
      } desc;
      memset(&desc, 0, sizeof desc);
      if (SUCCEEDED(get_desc1(adapter, &desc))) {
        soft = (desc.flags & 2u) != 0;
      }
    }
    ((envx_fn_com_release)((void ***)adapter)[0][2])(adapter);
  }
  release(factory);
  return soft;
}

// 远程桌面会话：GetSystemMetrics(SM_REMOTESESSION) 非 0 即挂在 Terminal
// Services 客户会话上——远程会话里硬件加速通路受限，进 GPU detail。
MOONBIT_FFI_EXPORT
int envx_win_remote(void) {
  HMODULE user32 = LoadLibraryW(L"user32.dll");
  if (user32 == NULL) {
    return 0;
  }
  typedef int (WINAPI *envx_fn_get_system_metrics)(int);
  envx_fn_get_system_metrics gsm =
    (envx_fn_get_system_metrics)(void *)GetProcAddress(user32, "GetSystemMetrics");
  if (gsm == NULL) {
    return 0;
  }
  return gsm(0x1000) != 0; // SM_REMOTESESSION
}

// -----
// Windows 占位：其它平台的 envx_win_* 空实现

#else /* !ENVX_OS_WINDOWS */

MOONBIT_FFI_EXPORT
moonbit_bytes_t envx_platform(void) {
#if defined(ENVX_OS_MACOS)
  return envx_bytes_from("macos");
#elif defined(ENVX_OS_LINUX)
  return envx_bytes_from("linux");
#else
  return envx_bytes_from("");
#endif
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t envx_win_cpuid(void) {
  return envx_bytes_from("");
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t envx_win_adapters(void) {
  return envx_bytes_from("");
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t envx_win_smbios(void) {
  return envx_bytes_from("");
}

MOONBIT_FFI_EXPORT
int envx_win_dxgi_soft(void) {
  return 0;
}

MOONBIT_FFI_EXPORT
int envx_win_remote(void) {
  return 0;
}

#endif /* ENVX_OS_WINDOWS */

#ifdef ENVX_OS_MACOS
// -----
// macOS

#include <sys/sysctl.h>
#include <dlfcn.h>

// hw.model：真机串含 "Mac"（如 MacBookPro16,1）；虚拟机是 VMware7,1 之类，
// Apple Virtualization 客户机是 MacVirtualMachine,1——判 VM 看两个信号：
// 不含 Mac 或含 VirtualMachine（出处 VMAware HWMODEL / Checkpoint macOS 页）。
MOONBIT_FFI_EXPORT
moonbit_bytes_t envx_mac_model(void) {
  char buf[256];
  memset(buf, 0, sizeof buf);
  size_t sz = sizeof buf;
  if (sysctlbyname("hw.model", buf, &sz, NULL, 0) != 0) {
    buf[0] = '\0';
  }
  return envx_bytes_from(buf);
}

// kern.hv_vmm_present：运行在 hypervisor 管理下时非 0——Apple Silicon 虚拟
// 机 hw.model 可能仍含 Mac，靠这个兜住。
MOONBIT_FFI_EXPORT
int envx_mac_hvvmm(void) {
  int v = 0;
  size_t sz = sizeof v;
  if (sysctlbyname("kern.hv_vmm_present", &v, &sz, NULL, 0) != 0) {
    return 0;
  }
  return v != 0;
}

// Metal 默认设备存在性：dlopen Metal 框架运行期装载，取不到设备即无 GPU
// 通路（headless 虚拟机常见）。设备对象按 Cocoa 约定 autoreleased，进程级
// 探测一次，不追释放。
MOONBIT_FFI_EXPORT
int envx_mac_metal(void) {
  void *m = dlopen("/System/Library/Frameworks/Metal.framework/Metal", RTLD_LAZY);
  if (m == NULL) {
    return 0;
  }
  void *(*create_default)(void) = (void *(*)(void))dlsym(m, "MTLCreateSystemDefaultDevice");
  if (create_default == NULL) {
    return 0;
  }
  return create_default() != NULL;
}

#else /* !ENVX_OS_MACOS */

MOONBIT_FFI_EXPORT
moonbit_bytes_t envx_mac_model(void) {
  return envx_bytes_from("");
}

MOONBIT_FFI_EXPORT
int envx_mac_hvvmm(void) {
  return 0;
}

MOONBIT_FFI_EXPORT
int envx_mac_metal(void) {
  return 0;
}

#endif /* ENVX_OS_MACOS */

#ifdef ENVX_OS_LINUX
// -----
// Linux：纯文件探测，零系统库

#include <fcntl.h>
#include <unistd.h>

// 路径存在性（F_OK）。
MOONBIT_FFI_EXPORT
int envx_linux_exists(const char *path) {
  return access(path, F_OK) == 0;
}

// 读小文件全文：/proc 与 /sys 都是即时生成的小文件，环形读上限 64 KB；
// 打不开给空串——读不到当信号缺失，不是错误。
static void envx_linux_read_into(const char *path, char *buf, size_t cap) {
  buf[0] = '\0';
  int fd = open(path, O_RDONLY);
  if (fd < 0) {
    return;
  }
  size_t off = 0;
  while (off + 1 < cap) {
    ssize_t n = read(fd, buf + off, cap - 1 - off);
    if (n <= 0) {
      break;
    }
    off += (size_t)n;
  }
  close(fd);
  buf[off] = '\0';
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t envx_linux_read_file(const char *path) {
  char buf[65537];
  envx_linux_read_into(path, buf, sizeof buf);
  return envx_bytes_from(buf);
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t envx_linux_read_link(const char *path) {
  char buf[512];
  memset(buf, 0, sizeof buf);
  ssize_t n = readlink(path, buf, sizeof buf - 1);
  if (n < 0) {
    n = 0;
  }
  buf[n] = '\0';
  return envx_bytes_from(buf);
}

// 渲染节点探测四行：`open=`（/dev/dri/renderD128 可打开）/ `vendor=`（渲染
// 节点对应 sysfs 的 PCI vendor，形如 0x1af4）/ `driver=`（uevent 的 DRIVER=
// 值）/ `dxg=`（/dev/dxg 存在——WSL2 GPU 半虚拟化通路）。固定探测首个渲染
// 节点 renderD128：多卡场景取主卡，P2 再扩全枚举。
MOONBIT_FFI_EXPORT
moonbit_bytes_t envx_linux_render(void) {
  int open_ok = 0;
  int fd = open("/dev/dri/renderD128", O_RDWR);
  if (fd >= 0) {
    close(fd);
    open_ok = 1;
  }
  char vendor[64];
  envx_linux_read_into("/sys/class/drm/renderD128/device/vendor", vendor, sizeof vendor);
  char uevent[512];
  envx_linux_read_into("/sys/class/drm/renderD128/device/uevent", uevent, sizeof uevent);
  char driver[64] = "";
  char *p = strstr(uevent, "DRIVER=");
  if (p != NULL) {
    if (sscanf(p + 7, "%63s", driver) != 1) {
      driver[0] = '\0';
    }
  }
  int dxg = access("/dev/dxg", F_OK) == 0;
  char out[256];
  snprintf(out, sizeof out, "open=%d\nvendor=%s\ndriver=%s\ndxg=%d",
           open_ok, vendor, driver, dxg);
  return envx_bytes_from(out);
}

// 网卡 MAC 候选列表，一行一个：/sys/class/net/*/address。目录枚举走
// opendir——sysfs 每网卡一个目录，读出全部非回环地址交 MoonBit 侧认前缀。
#include <dirent.h>

MOONBIT_FFI_EXPORT
moonbit_bytes_t envx_linux_net_macs(void) {
  DIR *d = opendir("/sys/class/net");
  if (d == NULL) {
    return envx_bytes_from("");
  }
  char out[4096];
  size_t off = 0;
  struct dirent *ent;
  while ((ent = readdir(d)) != NULL) {
    if (strcmp(ent->d_name, ".") == 0 || strcmp(ent->d_name, "..") == 0) {
      continue;
    }
    if (strcmp(ent->d_name, "lo") == 0) {
      continue;
    }
    char path[512];
    snprintf(path, sizeof path, "/sys/class/net/%s/address", ent->d_name);
    char addr[64];
    envx_linux_read_into(path, addr, sizeof addr);
    int w = snprintf(out + off, sizeof out - off, "%s", addr);
    if (w < 0 || (size_t)w >= sizeof out - off) {
      break;
    }
    off += (size_t)w;
  }
  closedir(d);
  return envx_bytes_from(out);
}

#else /* !ENVX_OS_LINUX */

MOONBIT_FFI_EXPORT
int envx_linux_exists(const char *path) {
  (void)path;
  return 0;
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t envx_linux_read_file(const char *path) {
  (void)path;
  return envx_bytes_from("");
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t envx_linux_read_link(const char *path) {
  (void)path;
  return envx_bytes_from("");
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t envx_linux_render(void) {
  return envx_bytes_from("");
}

MOONBIT_FFI_EXPORT
moonbit_bytes_t envx_linux_net_macs(void) {
  return envx_bytes_from("");
}

#endif /* ENVX_OS_LINUX */
