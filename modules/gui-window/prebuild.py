#!/usr/bin/env python3
"""NoahLiu/gui-window 的链接预构建脚本（--moonbit-unstable-prebuild）。

只做一件事：给本模块 `NoahLiu/gui-window/win` 下发窗口后端桩的编译与链接
参数——stub.c 一个文件四条平台分支（形态与口径承袭主仓 prebuild 原 WIN 条目，
自 gui/scripts/prebuild.py 迁入）：

- Linux：native-stub 拿不到 GTK 头（link_configs 只有链接期字段，G0 实测），
  本脚本带 `-DWM_STUB_GTK` + pkg-config gtk+-3.0 / x11 头把 stub.c 编成
  `libyue_win_stub.a`，链接行带 GTK/X11 全链；全局热键 XGrabKey 与 XWithdraw
  都落在 X11（x11 的 cflags/libs 由此下发）。
- Windows：stub.c 的 _WIN32 分支由 moon native-stub 自编（windows.h 走 MSVC
  自带 SDK 路径），这里只下发系统库（MSVC 口径位置参数直拼 .lib 名，GNU 的
  -L/-l 会报 D9002）。
- macOS：`-x objective-c -fobjc-arc -DWM_STUB_MAC` 编
  `libyue_win_stub_mac.a`，框架 Cocoa / CoreGraphics / Carbon / IOKit /
  UserNotifications（逐条按「哪一个能力要它」注释在清单处）。

gui 侧（facade）不再管 win：render/text 的桩与链接参数仍由主仓
gui/scripts/prebuild.py 按各自包名下发。约束：stdout 只能是 JSON；进度走
stderr。
"""

from __future__ import annotations

import json
import platform
import shutil
import subprocess
import sys
from pathlib import Path

MODULE_ROOT = Path(__file__).resolve().parent  # modules/gui-window/（脚本住模块根）
BUILD_DIR = MODULE_ROOT / "build"
WIN_PACKAGE = "NoahLiu/gui-window/win"
STUB_SRC = MODULE_ROOT / "win" / "stub.c"

# macOS ObjC 编译形态（承袭主仓注释：桩文件是 .c，靠 -x objective-c 按 ObjC
# 编；ARC 开着的理由——对象生命周期跟着 NSWindow/NSView 走，手写
# retain/release 在这种形态里几乎必错）。
MAC_OBJC_CFLAGS = ["-x", "objective-c", "-fobjc-arc"]


# Linux 系统库显式补（与主仓 prebuild 同一口径）。
LINUX_SYS_LIBS = ["-lpthread", "-ldl", "-lm", "-lstdc++", "-latomic"]

# macOS 各框架逐条按「哪一个能力要它」写清楚（承袭主仓注释）：
MAC_WIN_FRAMEWORKS = [
    "-framework", "Cocoa",           # NSApplication/NSWindow/NSMenu/NSAlert/NSPasteboard
    "-framework", "CoreGraphics",    # CGContext 贴像素、CGImage 造图标
    "-framework", "Carbon",          # RegisterEventHotKey 一族（全局快捷键）
    "-framework", "IOKit",           # 电源/显示器相关的读数
    "-framework", "UserNotifications",  # 通知中心（UNUserNotificationCenter，mac 通知正路）
]


def pkg_config(args: list[str], flag: str) -> list[str] | None:
    """探包配置：None = 包不存在；空列表 = 存在但该 flag 无输出（合法）。"""
    run = subprocess.run(["pkg-config", flag] + args, capture_output=True, text=True)
    if run.returncode != 0:
        return None
    return run.stdout.split()


def compile_stub(extra_cflags: list[str], lib_name: str, obj_prefix: str) -> str:
    """把 stub.c 编成静态库，返回库路径；失败返回空串（链接条目随之不下发，
    错误在 stderr 出声）。obj 前缀防多模块同名 .o 互踩。"""
    if not STUB_SRC.exists():
        print(f"prebuild: 源文件不存在：{STUB_SRC}", file=sys.stderr)
        return ""
    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    lib = BUILD_DIR / lib_name
    if lib.exists() and lib.stat().st_mtime >= STUB_SRC.stat().st_mtime:
        return lib.as_posix()
    cc = shutil.which("cc") or shutil.which("gcc") or shutil.which("clang") or "cc"
    obj = BUILD_DIR / f"{obj_prefix}_stub.o"
    cmd = [cc, "-c", "-O2", "-fPIC", *extra_cflags, "-o", obj.as_posix(), STUB_SRC.as_posix()]
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
        pkgs = ["gtk+-3.0", "x11"]  # 窗口/GTK 一族 + 全局热键与 hide 的 X11
        cflags: list[str] = []
        libs: list[str] = []
        for name in pkgs:
            got_c = pkg_config([name], "--cflags")
            got_l = pkg_config([name], "--libs")
            if got_c is None or got_l is None:
                print(f"prebuild: 缺少 {name} 开发包", file=sys.stderr)
                return {"link_configs": entries}
            cflags.extend(got_c)
            libs.extend(got_l)
        lib = compile_stub(["-DWM_STUB_GTK", *cflags], "libyue_win_stub.a", "gui_window_gtk")
        if lib:
            entries.append({
                "package": WIN_PACKAGE,
                "link_flags": f"-L{BUILD_DIR.as_posix()} -lyue_win_stub "
                + " ".join([*libs, *LINUX_SYS_LIBS]),
            })
    elif system == "Windows":
        # Win32 桩由 native-stub 自编，只下发系统库（MSVC 口径位置参数直拼）：
        # user32/gdi32 建窗贴屏，imm32 随 IME 线（W6），advapi32 供深浅/主色
        # 注册表读；W20f 图标加载要 WIC（windowscodecs.lib）与 COM 初始化
        # （ole32）；W20c 托盘要 Shell_NotifyIconW（shell32）；任务栏进度与
        # 文件对话框的 GUID 常量从 uuid.lib 链接期取符号。
        # （文件对话框 wm_file_* 的 Linux/mac 臂也在本桩——dialog.mbt 已随拆包
        # 归本模块，Windows 臂实现同批自 gui-sys 桩迁入。）
        entries.append({
            "package": WIN_PACKAGE,
            "link_flags": "user32.lib gdi32.lib imm32.lib advapi32.lib "
            "windowscodecs.lib ole32.lib shell32.lib uuid.lib",
        })
    elif system == "Darwin":
        lib = compile_stub(
            [*MAC_OBJC_CFLAGS, "-DWM_STUB_MAC"], "libyue_win_stub_mac.a", "gui_window_mac"
        )
        if lib:
            entries.append({
                "package": WIN_PACKAGE,
                "link_flags": f"-L{BUILD_DIR.as_posix()} -lyue_win_stub_mac "
                + " ".join(MAC_WIN_FRAMEWORKS),
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
