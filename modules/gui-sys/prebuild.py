#!/usr/bin/env python3
"""NoahLiu/gui-sys 的链接预构建脚本（--moonbit-unstable-prebuild）。

只做一件事：给本模块 `NoahLiu/gui-sys/sys` 下发平台转发实现档的链接参数——
sys_stub.c 是纯 native-stub（拿不到 GTK 头、ObjC 那趟由 prebuild 专编），
剪贴板（Linux GTK / macOS NSPasteboard）、mac 窗口枚举/激活/关闭、mac 权限
探测与屏幕色温这几段平台实现住 `sys/sys_ext.c`，由本脚本按平台编成静态库：

- Linux：`-DWMSYS_EXT_GTK` + pkg-config gtk+-3.0 头编 `libgui_sys_ext.a`，
  链接行带 gtk+-3.0 全链（剪贴板只落 gtk/gdk/glib，不碰 pango/x11）。
- macOS：`-x objective-c -fobjc-arc -DWMSYS_EXT_MAC` 编
  `libgui_sys_ext_mac.a`，框架 Cocoa / CoreGraphics / Carbon / ApplicationServices
  （AX 一族在 ApplicationServices，Carbon 兜 HIServices 的常量）。
- Windows：sys_stub.c 的 _WIN32 分支自含 CF_UNICODETEXT 剪贴板等全部实现
  （文件对话框 IFileDialog 已随 dialog.mbt 归 gui-window 域、C 臂迁 win 桩），
  这里只下发系统库清单（COM/注册表/电源/打印/显示器/色温一族，口径承袭
  主仓 prebuild 原 SYS 条目）——native-stub 自编，无需额外归档。

迁移前这些实现住主仓 gui/win 桩（sys 经 SYS_PACKAGE 的 -lyue_win_stub 跨包
解析）；sys 拆独立模块后 gui-window 与 gui-sys 是平行兄弟、互相零依赖，
符号随消费方（本模块）走。约束：stdout 只能是 JSON；进度信息走 stderr。
"""

from __future__ import annotations

import json
import platform
import shutil
import subprocess
import sys
from pathlib import Path

MODULE_ROOT = Path(__file__).resolve().parent  # modules/gui-sys/（脚本住模块根）
BUILD_DIR = MODULE_ROOT / "build"
SYS_PACKAGE = "NoahLiu/gui-sys/sys"
SYS_EXT_SRC = MODULE_ROOT / "sys" / "sys_ext.c"

# Linux：剪贴板要的 GTK 一族经 pkg-config 取；系统库显式补（与主仓 prebuild
# 同一口径）。
LINUX_GTK = "gtk+-3.0"
LINUX_SYS_LIBS = ["-lpthread", "-ldl", "-lm", "-lstdc++", "-latomic"]

# macOS：与主仓 prebuild 的 mac 桩同一编译形态（ObjC + ARC）。框架两笔合一：
# sys_ext.c 的（NSPasteboard / CGWindowList / AX 一族）与 sys_stub.c native-stub
# 自己的（LSSharedFileList 自启、IOKit 空闲、CoreAudio 音量、CorePrint 打印、
# NSWorkspace 壁纸）——后者也要经链接行拿框架，一并在本条目下发。
MAC_OBJC_CFLAGS = ["-x", "objective-c", "-fobjc-arc"]
MAC_FRAMEWORKS = [
    "-framework", "Cocoa",               # NSPasteboard / NSWorkspace（壁纸、打开/揭示）/ NSWindow
    "-framework", "CoreGraphics",        # CGWindowList* / CGPreflight(Request)ScreenCaptureAccess / CGEventSource（空闲）
    "-framework", "Carbon",              # HIServices 的 AX 常量兜底
    "-framework", "ApplicationServices", # AXIsProcessTrusted(WithOptions) / AXUIElement* / 打印机（CorePrint）
    "-framework", "CoreServices",        # LSSharedFileList（自启动）、UTType
    "-framework", "IOKit",               # IOHIDSystem 空闲时间
    "-framework", "CoreAudio",           # 音量（AudioObject*）
]


def pkg_config(args: list[str], flag: str) -> list[str] | None:
    """探包配置：None = 包不存在；空列表 = 存在但该 flag 无输出（合法）。"""
    run = subprocess.run(["pkg-config", flag] + args, capture_output=True, text=True)
    if run.returncode != 0:
        return None
    return run.stdout.split()


def compile_ext(lib_name: str, extra_cflags: list[str]) -> str:
    """把 sys/sys_ext.c 按平台宏编成静态库，返回库路径；失败返回空串（链接
    条目随之不下发，错误在 stderr 出声）。"""
    if not SYS_EXT_SRC.exists():
        print(f"prebuild: 源文件不存在：{SYS_EXT_SRC}", file=sys.stderr)
        return ""
    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    lib = BUILD_DIR / lib_name
    if lib.exists() and lib.stat().st_mtime >= SYS_EXT_SRC.stat().st_mtime:
        return lib.as_posix()
    cc = shutil.which("cc") or shutil.which("gcc") or shutil.which("clang") or "cc"
    obj = BUILD_DIR / "gui_sys_ext.o"
    cmd = [cc, "-c", "-O2", "-fPIC", *extra_cflags, "-o", obj.as_posix(), SYS_EXT_SRC.as_posix()]
    run = subprocess.run(cmd, capture_output=True, text=True)
    if run.returncode != 0:
        print(f"prebuild: {' '.join(cmd)} 失败\n{run.stderr}", file=sys.stderr)
        return ""
    if lib.exists():
        lib.unlink()
    run = subprocess.run(["ar", "rcs", lib.as_posix(), obj.as_posix()], capture_output=True, text=True)
    if run.returncode != 0:
        print(f"prebuild: ar 打包 {lib_name} 失败\n{run.stderr}", file=sys.stderr)
        return ""
    return lib.as_posix()


def link_configs() -> dict:
    entries: list[dict] = []
    system = platform.system()
    if system == "Linux":
        cflags = pkg_config([LINUX_GTK], "--cflags")
        libs = pkg_config([LINUX_GTK], "--libs")
        if cflags is None or libs is None:
            print(f"prebuild: 缺少 {LINUX_GTK} 开发包", file=sys.stderr)
            return {"link_configs": entries}
        lib = compile_ext("libgui_sys_ext.a", ["-DWMSYS_EXT_GTK", *cflags])
        if lib:
            entries.append({
                "package": SYS_PACKAGE,
                "link_flags": f"-L{BUILD_DIR.as_posix()} -lgui_sys_ext "
                + " ".join([*libs, *LINUX_SYS_LIBS]),
            })
    elif system == "Darwin":
        lib = compile_ext("libgui_sys_ext_mac.a", [*MAC_OBJC_CFLAGS, "-DWMSYS_EXT_MAC"])
        if lib:
            entries.append({
                "package": SYS_PACKAGE,
                "link_flags": f"-L{BUILD_DIR.as_posix()} -lgui_sys_ext_mac "
                + " ".join(MAC_FRAMEWORKS),
            })
    elif system == "Windows":
        # sys_stub.c 的 _WIN32 分支由 moon native-stub 自编，这里只下发系统库
        # （口径承袭主仓 prebuild 原 SYS 条目）：COM（剪贴板/IDataObject）在
        # ole32，ShellExecuteW 在 shell32，自启动写 HKCU Run 键要 advapi32，
        # 电源方案直调要 powrprof，打印机要 winspool，显示器枚举在 user32，
        # 夜间色温 SetDeviceGammaRamp 在 gdi32，WMI 兜底要 oleaut32 与
        # wbemuuid（GUID 常量 C 模式取不到 __uuidof，只能链库取符号）。
        # 文件对话框的 IFileDialog 一族已随 dialog.mbt 归 gui-window 域。
        entries.append({
            "package": SYS_PACKAGE,
            "link_flags": "ole32.lib oleaut32.lib wbemuuid.lib shell32.lib uuid.lib user32.lib gdi32.lib advapi32.lib powrprof.lib winspool.lib",
        })
    return {"link_configs": entries}


def main() -> None:
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, OSError):
            pass
    try:
        json.load(sys.stdin)  # moon 传入构建环境，当前无需使用
    except json.JSONDecodeError:
        pass
    print(json.dumps(link_configs()))


if __name__ == "__main__":
    main()
