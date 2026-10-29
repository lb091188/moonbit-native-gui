#!/usr/bin/env python3
"""NoahLiu/gui-webview 的链接预构建脚本（--moonbit-unstable-prebuild）。

只做一件事：给本模块包 `NoahLiu/gui-webview/webview` 下发 webview 引擎的编译与
链接参数——G9 Batch 1 起 web 出成独立模块，WebView2 vendor 资产与 WebKitGTK
探测不再由主仓 `gui/scripts/prebuild.py` 管。

Linux：pkg-config 探 `webkit2gtk-4.1`，带 `-DWB_HAVE_WEBKIT` 把 `webkit_stub.c`
编成静态库；缺开发包不算错——native-stub 那次无宏编译已给出占位符号，
MoonBit 侧按 `webview_supported()` 探测降级。真实现分支引用主模块 win 桩的
`wm_surface_container()`，所以链接行要带上主模块编好的 `libyue_win_stub.a`——
本脚本按「workspace 兄弟目录 → 依赖缓存 → 当前工作区 _build」三处定位，
定位不到时退回占位分支（宁可不链，不给断链的 exe）。

Windows：`webview2_stub.c` 由 moon native-stub 自编（vendor 头相对路径自取），
这里只下发静态 Loader（缺失时按 sha256 从 Release 资产下载，口径与主仓原
实现逐字相同——两模块刻意各留一份，本模块要能独立发布）。

macOS：`webkit_stub.c` 的 WB_HAVE_WKWEBVIEW 分支（WKWebView，系统自带引擎，
没有 Linux 那条「缺开发包」的退路）由本脚本专编成静态库；它引用主模块 win 桩
的 `wm_surface_container`，所以还要定位 `gui/build/libyue_win_stub_mac.a` 一起
链——native-stub 在 macOS 编出的是空翻译单元，这条链不上符号就断，定位不到
时出声报错。

约束：stdout 只能是 JSON；进度信息走 stderr。
"""

from __future__ import annotations

import hashlib
import json
import os
import platform
import shutil
import subprocess
import sys
import urllib.request
from pathlib import Path

MODULE_ROOT = Path(__file__).resolve().parent  # modules/gui-webview/
PKG = "NoahLiu/gui-webview/webview"
BUILD_DIR = MODULE_ROOT / "build"

WEBKIT_PKG_CONFIG = "webkit2gtk-4.1"

# ---------------------------------------------------------------------------
# vendor 大文件走 Release 资产（口径继承主仓 2026-10-14 的决定）：WebView2
# 静态 Loader 与 SDK 头体积大且基本不更新，不入库；构建时缺失即下载并校验
# sha256，离线环境可提前手工放置（已存在不动）。镜像按序尝试、不做延迟探测，
# 单源超时 20 秒。外部源用环境变量 NATIVE_GUI_VENDOR_BASE 覆盖。
# ---------------------------------------------------------------------------
VENDOR_BASES = [
    "https://github.com/lb091188/moonbit-native-gui/releases/download/vendor-v1",
    # gitee 镜像：gitee 的用户名与 GitHub 不同（noahliu0911 / lb091188），
    # 附件下载 URL 形状两边一致（releases/download/<tag>/<文件名>）。
    "https://gitee.com/noahliu0911/moonbit-native-gui/releases/download/vendor-v1",
]

VENDOR_TIMEOUT = 20

VENDOR_FILES = [
    (
        "webview/lib/WebView2LoaderStatic.lib",
        "e66284970876a616c82e7dcda75a17fd46d04827f9de81d4299b8862d34d25d6",
    ),
    (
        "webview/include/WebView2.h",
        "dff1e3181ec7ec203a34ef6efa966590e0ef0ba1a5c3fe3b69da6508c2f8a02e",
    ),
]


def vendor_bases() -> list[str]:
    env = os.environ.get("NATIVE_GUI_VENDOR_BASE", "")
    extra = [b.strip().rstrip("/") for b in env.split(",") if b.strip()]
    return extra + VENDOR_BASES


# 默认双镜像走**并行竞速**：同时向各镜像发请求，谁先返回完整且 sha256 校验
# 通过就用谁——DNS 慢、连接慢、慢速滴流的镜像天然落后，总耗时 = 最快镜像的
# 时间（GitHub 滴流的机器上等于 gitee 的几秒，而不是串行等预算耗尽）。兜底
# 总预算仍在：所有镜像都 60 秒无产出才失败。前置教训不变：urlopen 的 timeout
# 是 socket 级，DNS 挂起与滴流要靠竞速+总预算双机制兜。
VENDOR_BUDGET = 60


def _fetch_race(bases: list[str], name: str, sha: str, socket_timeout: int) -> "bytes | None":
    import queue
    import threading
    import time

    q: "queue.Queue[tuple[str, bytes | None]]" = queue.Queue()

    def worker(base: str) -> None:
        try:
            data = urllib.request.urlopen(f"{base}/{name}", timeout=socket_timeout).read()
            q.put((base, data))
        except Exception:  # noqa: BLE001——失败也入队，主流程继续收其余镜像
            q.put((base, None))

    threads = [threading.Thread(target=worker, args=(b,), daemon=True) for b in bases]
    for t in threads:
        t.start()
    deadline = time.monotonic() + VENDOR_BUDGET
    left = len(bases)
    while left > 0:
        remain = deadline - time.monotonic()
        if remain <= 0:
            break
        try:
            base, data = q.get(timeout=min(2.0, remain))
        except queue.Empty:
            continue
        left -= 1
        if data is None:
            print(f"prebuild: 镜像失败（{base}）", file=sys.stderr)
            continue
        if hashlib.sha256(data).hexdigest() != sha:
            print(f"prebuild: {base} 上 sha256 不符，看其余镜像", file=sys.stderr)
            continue
        print(f"prebuild: 命中镜像 {base}", file=sys.stderr)
        return data
    print(f"prebuild: 全部镜像 {VENDOR_BUDGET} 秒总预算内都没给出校验通过的文件", file=sys.stderr)
    return None


def _fetch_serial(bases: list[str], name: str, sha: str, socket_timeout: int) -> "bytes | None":
    """串行按序形态（NATIVE_GUI_VENDOR_BASE 指定自定义源时用——用户指内网/
    私有镜像时不并行外网）。单源仍线程包裹总预算兜底：DNS 挂起/滴流的
    socket 级教训不因串行而失效。"""
    import threading

    for base in bases:
        url = f"{base}/{name}"
        print(f"prebuild: 取 vendor {url} ...", file=sys.stderr)
        box: dict = {}

        def run(url: str = url) -> None:
            try:
                box["data"] = urllib.request.urlopen(url, timeout=socket_timeout).read()
            except Exception:  # noqa: BLE001
                box["data"] = None

        t = threading.Thread(target=run, daemon=True)
        t.start()
        t.join(VENDOR_BUDGET)
        data = box.get("data")
        if data is not None and hashlib.sha256(data).hexdigest() == sha:
            return data
        print(f"prebuild: 镜像失败或 sha256 不符（{url}），换下一个", file=sys.stderr)
    return None


def fetch_vendor_file(name: str, sha: str) -> "bytes | None":
    bases = vendor_bases()
    if os.environ.get("NATIVE_GUI_VENDOR_BASE", "").strip():
        # 自定义源前置：串行按序，不做并行外网竞速
        return _fetch_serial(bases, name, sha, VENDOR_TIMEOUT)
    return _fetch_race(bases, name, sha, VENDOR_TIMEOUT)


def ensure_release_files() -> None:
    # 这两份 vendor 资产只有 Windows 分支消费（WebView2 Loader 与 SDK 头），
    # Linux/mac 上是纯浪费的 14MB 下载——非 Windows 直接跳过（有机器上已就位
    # 的存量文件也不动它们）。
    if platform.system() != "Windows":
        return
    for rel, sha in VENDOR_FILES:
        dest = MODULE_ROOT / rel
        if dest.exists():
            continue
        data = fetch_vendor_file(dest.name, sha)
        if data is None:
            print(
                f"prebuild: 全部镜像都没取到 {dest.name}\n"
                f"  离线环境可手工放置，或用 NATIVE_GUI_VENDOR_BASE 指到自己的源",
                file=sys.stderr,
            )
            continue
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)
        print(f"prebuild: 已就位 {dest.name}（sha256 ✓）", file=sys.stderr)


def pkg_config(args: list[str], flag: str) -> list[str] | None:
    run = subprocess.run(["pkg-config", flag] + args, capture_output=True, text=True)
    if run.returncode != 0:
        return None
    return run.stdout.split()


def find_win_stub_archive() -> Path | None:
    """定位主模块 win 桩的静态库（webkit 真实现引用其 wm_surface_container）。

    候选按构建现实排序：本仓 workspace（modules/gui-webview 与 gui 同级）→
    moon 依赖缓存里的 native-gui（registry 消费方在 workspace 外时）→
    当前工作区 _build（prebuild 产物目录里找同名归档）。"""
    home = Path(os.environ.get("MOON_HOME", str(Path.home() / ".moon")))
    candidates = [
        MODULE_ROOT.parent.parent / "gui" / "build" / "libyue_win_stub.a",
        home / "packages" / "NoahLiu" / "native-gui" / "gui" / "build" / "libyue_win_stub.a",
        home / "deps" / "NoahLiu" / "native-gui" / "gui" / "build" / "libyue_win_stub.a",
    ]
    if candidates[0].exists():
        return candidates[0]
    for base in candidates[1:]:
        if base.exists():
            return base
    # _build 兜底：cwd 或 module_root 上溯两级的 _build 里 glob（hash 目录名不猜）
    for root in (Path.cwd(), MODULE_ROOT.parent, MODULE_ROOT.parent.parent):
        blob = root / "_build" / "native"
        if not blob.is_dir():
            continue
        hits = sorted(
            blob.glob(f"*/build/prebuild/*/libyue_win_stub.a"),
            key=lambda p: p.stat().st_mtime,
            reverse=True,
        )
        if hits:
            return hits[0]
    return None


def stub_tag(src: Path) -> str:
    """源码内容指纹（sha256 前 8 位）：编进归档文件名。"""
    return hashlib.sha256(src.read_bytes()).hexdigest()[:8]


def stub_lib(dir: Path, prefix: str, tag: str) -> Path:
    return dir / f"{prefix}-{tag}.a"


def prune_stub_libs(dir: Path, prefix: str, keep: Path) -> None:
    """同前缀旧指纹的归档清掉，防堆积；无指纹旧名与 .srcsha 边车一并清
    （后两者是更早两版判据的残留）。"""
    for old in dir.glob(f"{prefix}-*.a"):
        if old != keep:
            old.unlink()
    for legacy in (dir / f"{prefix}.a", dir / f"{prefix}.a.srcsha"):
        if legacy.exists():
            legacy.unlink()


def compile_webkit_stub(win_archive: Path) -> str:
    """把 webkit_stub.c 带 -DWB_HAVE_WEBKIT 编成静态库，返回库路径；失败给空串。

    归档名带源码指纹（libgui_webview-<tag>.a）：源码变 → 名字变 → link_flags 变
    → moon 失效链接目标、exe 重链。只看 mtime 的旧判据有两层洞——被保留时间戳的
    同步方式骗过是一层；更根本的是归档内容变了而 link_flags 字符串没变，moon 不
    重链，exe 一直跑旧桩（真机踩实：归档 nm 新符号俱在、行为仍是旧代码）。"""
    cflags = pkg_config([WEBKIT_PKG_CONFIG], "--cflags")
    if cflags is None:
        print(
            f"prebuild: 缺 {WEBKIT_PKG_CONFIG}，webview 走占位实现（探测返回不可用）",
            file=sys.stderr,
        )
        return ""
    src = MODULE_ROOT / "webview" / "webkit_stub.c"
    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    tag = stub_tag(src)
    lib = stub_lib(BUILD_DIR, "libgui_webview", tag)
    if not lib.exists():
        cc = shutil.which("cc") or shutil.which("gcc") or "cc"
        obj = BUILD_DIR / "webkit_stub.o"
        cmd = [cc, "-c", "-O2", "-fPIC", "-DWB_HAVE_WEBKIT", "-o", obj.as_posix(),
               src.as_posix(), *cflags]
        run = subprocess.run(cmd, capture_output=True, text=True)
        if run.returncode != 0:
            print(f"stub: {' '.join(cmd)} 失败\n{run.stderr}", file=sys.stderr)
            return ""
        # 先删旧归档再建：`ar rcs` 对改了名的成员是追加，会留重复符号
        if lib.exists():
            lib.unlink()
        run = subprocess.run(["ar", "rcs", lib.as_posix(), obj.as_posix()],
                             capture_output=True, text=True)
        if run.returncode != 0:
            print(f"stub: ar 失败\n{run.stderr}", file=sys.stderr)
            return ""
        prune_stub_libs(BUILD_DIR, "libgui_webview", lib)
        print(f"prebuild: webkit 桩重编（指纹 {tag}）", file=sys.stderr)
    return lib.as_posix()


MAC_OBJC_CFLAGS = ["-x", "objective-c", "-fobjc-arc"]

# win 桩 mac 归档要链的框架（与主仓 scripts/prebuild.py 的 MAC_WIN_FRAMEWORKS
# 同表——本模块链的是同一份归档，缺一个框架就在用户机器上 dyld 报错）
MAC_WIN_FRAMEWORKS = [
    "-framework", "Cocoa",
    "-framework", "CoreGraphics",
    "-framework", "Carbon",
    "-framework", "IOKit",
]

MAC_WEB_FRAMEWORKS = [
    "-framework", "WebKit",          # WKWebView
    "-framework", "Cocoa",
]


def find_win_mac_stub_archive() -> Path | None:
    """定位主模块 win 桩的 macOS 归档（webkit mac 分支引用 wm_surface_container）。

    候选与 `find_win_stub_archive` 同序：workspace 兄弟目录 → 依赖缓存 →
    当前工作区 _build。"""
    home = Path(os.environ.get("MOON_HOME", str(Path.home() / ".moon")))
    name = "libyue_win_stub_mac.a"
    candidates = [
        MODULE_ROOT.parent.parent / "gui" / "build" / name,
        home / "packages" / "NoahLiu" / "native-gui" / "gui" / "build" / name,
        home / "deps" / "NoahLiu" / "native-gui" / "gui" / "build" / name,
    ]
    for base in candidates:
        if base.exists():
            return base
    for root in (Path.cwd(), MODULE_ROOT.parent, MODULE_ROOT.parent.parent):
        blob = root / "_build" / "native"
        if not blob.is_dir():
            continue
        hits = sorted(
            blob.glob(f"*/build/prebuild/*/{name}"),
            key=lambda p: p.stat().st_mtime,
            reverse=True,
        )
        if hits:
            return hits[0]
    return None


def compile_mac_webkit_stub() -> str:
    """把 webkit_stub.c 带 -DWB_HAVE_WKWEBVIEW 专编成静态库；失败给空串。

    归档名带源码指纹，机制同 Linux 分支（源码变 → 归档名变 → link_flags 变
    → moon 重链 exe）。"""
    src = MODULE_ROOT / "webview" / "webkit_stub.c"
    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    tag = stub_tag(src)
    lib = stub_lib(BUILD_DIR, "libgui_webview_mac", tag)
    if not lib.exists():
        cc = shutil.which("cc") or shutil.which("clang") or "cc"
        obj = BUILD_DIR / "webkit_stub_mac.o"
        cmd = [cc, "-c", "-O2", *MAC_OBJC_CFLAGS, "-DWB_HAVE_WKWEBVIEW",
               "-o", obj.as_posix(), src.as_posix()]
        run = subprocess.run(cmd, capture_output=True, text=True)
        if run.returncode != 0:
            print(f"stub: {' '.join(cmd)} 失败\n{run.stderr}", file=sys.stderr)
            return ""
        if lib.exists():
            lib.unlink()
        run = subprocess.run(["ar", "rcs", lib.as_posix(), obj.as_posix()],
                             capture_output=True, text=True)
        if run.returncode != 0:
            print(f"stub: ar 失败\n{run.stderr}", file=sys.stderr)
            return ""
        prune_stub_libs(BUILD_DIR, "libgui_webview_mac", lib)
        print(f"prebuild: webkit mac 桩重编（指纹 {tag}）", file=sys.stderr)
    return lib.as_posix()


def link_configs() -> dict:
    entries: list[dict] = []
    ensure_release_files()
    system = platform.system()
    if system == "Linux":
        win_archive = find_win_stub_archive()
        webkit_libs = pkg_config([WEBKIT_PKG_CONFIG], "--libs")
        if win_archive is None or webkit_libs is None:
            reason = (
                "找不到主模块 win 桩归档 gui/build/libyue_win_stub.a"
                if win_archive is None
                else f"缺 {WEBKIT_PKG_CONFIG} 开发包"
            )
            print(f"prebuild: {reason}，webview 走占位实现（探测返回不可用）", file=sys.stderr)
            return {"link_configs": entries}
        web_lib = compile_webkit_stub(win_archive)
        if not web_lib:
            return {"link_configs": entries}
        sys_libs = ["-lpthread", "-ldl", "-lm", "-lstdc++", "-latomic"]
        win_dir = win_archive.parent
        entries.append({
            "package": PKG,
            # 归档名带源码指纹（-l 名跟随实际文件名）：指纹变 → link_flags 变
            # → moon 失效链接目标，exe 必然重链新桩
            # 路径整体加双引号：撇号用户名会按 shell 词法拆碎整条 link_flags
            # （主仓 adaptation.md「同族第二条·撇号路径」教训，同口径预防）
            "link_flags": (
                f"-L{BUILD_DIR.as_posix()} -l{Path(web_lib).name[3:-2]} "
                f'-L"{win_dir.as_posix()}" -lyue_win_stub '
                + " ".join([*webkit_libs, *sys_libs])
            ),
        })
    elif system == "Windows":
        # 静态 Loader 免运行期分发 DLL（Evergreen Runtime 本机已有，探测在 C 桩做）。
        # 依赖的 win 桩符号（wm_surface_container 等）由 moon native-stub 的归档
        # 提供——主包链 win 桩，同一个 exe 链接行里符号天然可见。
        wv2_lib = MODULE_ROOT / "webview" / "lib" / "WebView2LoaderStatic.lib"
        if wv2_lib.exists():
            entries.append({
                "package": PKG,
                "link_flags": f'"{wv2_lib.as_posix()}" shlwapi.lib ole32.lib '
                "oleaut32.lib uuid.lib user32.lib gdi32.lib advapi32.lib",
            })
        else:
            print(
                "prebuild: 缺 webview/lib/WebView2LoaderStatic.lib，webview 走占位实现（探测返回不可用）",
                file=sys.stderr,
            )
    elif system == "Darwin":
        # WKWebView 分支专编（Objective-C/ARC）。native-stub 在 macOS 编本文件
        # 落不进任何分支（空翻译单元），符号全靠这份归档——win 桩 mac 归档
        # 定位不到就是断链，出声报错不静默。顺序上 -lgui_webview_mac 在前：
        # 它引用 win 桩的 wm_surface_container（与 Linux 分支同一口径）。
        win_archive = find_win_mac_stub_archive()
        if win_archive is None:
            print(
                "prebuild: 找不到主模块 win 桩归档 gui/build/libyue_win_stub_mac.a，"
                "webview 的 mac 分支没法链（native-stub 空翻译单元，符号会断）",
                file=sys.stderr,
            )
            return {"link_configs": entries}
        web_lib = compile_mac_webkit_stub()
        if not web_lib:
            return {"link_configs": entries}
        win_dir = win_archive.parent
        entries.append({
            "package": PKG,
            # 归档名带源码指纹（-l 名跟随实际文件名），机制同 Linux 分支
            # 路径整体加双引号：撇号用户名的教训同 Linux 分支
            "link_flags": (
                f"-L{BUILD_DIR.as_posix()} -l{Path(web_lib).name[3:-2]} "
                f'-L"{win_dir.as_posix()}" -lyue_win_stub_mac '
                + " ".join([*MAC_WEB_FRAMEWORKS, *MAC_WIN_FRAMEWORKS])
            ),
        })
    return {"link_configs": entries}


def main() -> None:
    # Windows 控制台常为 cp1252，stderr 打中文会 UnicodeEncodeError；转 UTF-8。
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
