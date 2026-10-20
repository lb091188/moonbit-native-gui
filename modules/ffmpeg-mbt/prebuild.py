#!/usr/bin/env python3
"""NoahLiu/ffmpeg-mbt 的链接预构建脚本（--moonbit-unstable-prebuild）。

给 ffmpeg FFI 桩下发编译/链接参数，按平台分三路：

- Linux：pkg-config 探测 libavformat/libavcodec/libswscale/libswresample/
  libavutil（系统 dev 包），输出 link_flags 传播给所有依赖本包的 main 包。
  缺 dev 包时给出行级安装提示并以非零退出。
- Windows：dev 内容 vendor 进仓库（`vendor/include` 头 + `vendor/*.lib`
  导入库，取自 BtbN win64-lgpl-shared 构建，LGPLv3，见 vendor/FFMPEG-LICENSE.txt）。
  输出 `vars.FFMPEG_INC`（供 moon.pkg 的 stub-cc-flags 引用 `-I${build.FFMPEG_INC}`）
  和 link_flags（导入库绝对路径）。运行期 dll 不进仓库：本地把
  avcodec-63.dll 等与 exe 同目录或放 PATH（口径见 README）。
- macOS：先走与 Linux 同一路——pkg-config 探测系统 ffmpeg（`brew install
  ffmpeg`），头与链接参数随构建注入；探不到时回退 **Release 下载的预编译
  dev 归档**（LGPL 自编、动态链 .dylib、id/依赖全部 @rpath 化，与本仓 webview
  Loader 的 vendor 口径同族：sha256 校验、双镜像按序尝试、NATIVE_GUI_VENDOR_BASE
  可覆盖、离线可手工放置到 `vendor/mac/`）。归档里的 dylib 互相用 @rpath 引用，
  link_flags 里下发 `-Wl,-rpath,<vendor lib 绝对路径>` 让 dyld 在构建机上找得到；
  两路都拿不到才非零退出（媒体线要求真给得出 ffmpeg，不静默造假可用）。

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
import tarfile
import urllib.request
import zipfile

LIBS = ["libavformat", "libavcodec", "libswscale", "libswresample", "libavutil"]
PKG = "NoahLiu/ffmpeg-mbt/src"

# 导入库文件名（BtbN 构建无 lib 前缀）；与 LIBS 顺序对应
WIN_LIBS = ["avformat.lib", "avcodec.lib", "swscale.lib", "swresample.lib", "avutil.lib"]

# 运行期 dll（同一份 BtbN win64-lgpl-shared 9.0 归档的 bin/）。约 150MB，不入库：
# 构建时缺失就从归档取一份放到 vendor/win/bin/，运行期由使用方放到 exe 同目录
# 或 PATH（口径见 README）。
WIN_RUNTIME_DLLS = [
    "avcodec-63.dll",
    "avformat-63.dll",
    "avutil-61.dll",
    "swscale-10.dll",
    "swresample-7.dll",
    "avdevice-63.dll",
    "avfilter-12.dll",
]

WIN_DLL_URL = (
    "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/"
    "ffmpeg-n9.0-latest-win64-lgpl-shared-9.0.zip"
)

# 本仓 vendor-v1 Release 的 Windows 归档（win-ffmpeg-vendor workflow 产物，与
# mac 归档、miniaudio.h、WebView2 同处一档）。sha256 回填后这一路优先于上游
# BtbN；空串表示尚未上传/未回填，直接走上游那一路。
WIN_VENDOR_ARCHIVE: tuple[str, str] = (
    "ffmpeg-windows-x64-9.0-lgpl-shared.zip",
    "",
)

# 单个 dll 的体积下限：用来判掉残缺/半截文件，不是精确校验。
WIN_DLL_MIN_BYTES = 100 * 1024

# ---------------------------------------------------------------------------
# vendor 归档（mac 的 dylib 与 Windows 的运行期 dll 同一套口径，与 gui-webview 的
# Release 资产同族）：体积不入库，缺失时下载校验 sha256，双镜像按序尝试、单源
# 超时 20 秒，NATIVE_GUI_VENDOR_BASE 覆盖，离线可提前手工放置（已存在不动）。
# ---------------------------------------------------------------------------
VENDOR_BASES = [
    "https://github.com/lb091188/moonbit-native-gui/releases/download/vendor-v1",
    # gitee 镜像：gitee 的用户名与 GitHub 不同（noahliu0911 / lb091188），
    # 附件下载 URL 形状两边一致（releases/download/<tag>/<文件名>）。
    "https://gitee.com/noahliu0911/moonbit-native-gui/releases/download/vendor-v1",
]

MAC_VENDOR_TIMEOUT = 20

# -lavformat 等短名（macOS 与 Linux 同用 -l 短名，链接器自己补 lib 前缀/后缀）
MAC_DYLIBS = ["avformat", "avcodec", "swscale", "swresample", "avutil"]

# 按机器架构取归档名（CI 的 mac-ffmpeg-vendor workflow 产物，上传 vendor-v1
# Release 后按此表下载并逐字节校验 sha256）：
#   "arm64": ("ffmpeg-macos-arm64-9.0.2-lgpl-shared.tar.gz", "<sha256>")
# 条目缺席时本路提示「归档尚未提供」，pkg-config（brew）路不受影响。
MAC_VENDOR_TARBALLS: dict[str, tuple[str, str]] = {
    "arm64": (
        "ffmpeg-macos-arm64-9.0.2-lgpl-shared.tar.gz",
        "809a07df51184884a9e326936ef580b35294057f0ddcae0d7ecae6edaebb923d",
    ),
}


def win_vendor_dir() -> str:
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "vendor")


def win_runtime_dir() -> str:
    """运行期 dll 的构建期落点（与 mac 的 vendor/mac 对称，同样不进仓库）。"""
    return os.path.join(win_vendor_dir(), "win", "bin")


def win_runtime_ready(bin_dir: str) -> bool:
    for name in WIN_RUNTIME_DLLS:
        p = os.path.join(bin_dir, name)
        if not os.path.isfile(p) or os.path.getsize(p) < WIN_DLL_MIN_BYTES:
            return False
    return True


def _download(url: str, dest: str) -> bool:
    try:
        with urllib.request.urlopen(url, timeout=30) as resp, open(dest, "wb") as fh:
            total = int(resp.headers.get("Content-Length") or 0)
            done = 0
            last = -5
            while True:
                chunk = resp.read(1 << 20)
                if not chunk:
                    break
                fh.write(chunk)
                done += len(chunk)
                if total:
                    pct = done * 100 // total
                    if pct >= last + 5:
                        last = pct
                        print(
                            f"ffmpeg(prebuild): {pct}% "
                            f"({done // (1 << 20)}/{total // (1 << 20)} MB)",
                            file=sys.stderr,
                        )
    except Exception as e:  # noqa: BLE001——网络失败返回 False，由调用方给手工步骤
        print(f"ffmpeg(prebuild): 下载失败（{e}）", file=sys.stderr)
        return False
    return True


def _install_win_zip(data: bytes, bin_dir: str) -> bool:
    """把归档里的 bin/*.dll 解到 bin_dir（只取 WIN_RUNTIME_DLLS 那 7 个）。"""
    import io

    try:
        with zipfile.ZipFile(io.BytesIO(data)) as zf:
            wanted = {
                n.rsplit("/", 1)[-1]: n
                for n in zf.namelist()
                if "/bin/" in n and n.rsplit("/", 1)[-1] in WIN_RUNTIME_DLLS
            }
            if len(wanted) < len(WIN_RUNTIME_DLLS):
                print(
                    f"ffmpeg(prebuild): 归档里 dll 不全"
                    f"（{len(wanted)}/{len(WIN_RUNTIME_DLLS)}）",
                    file=sys.stderr,
                )
                return False
            for name, member in wanted.items():
                with zf.open(member) as f, open(os.path.join(bin_dir, name), "wb") as out:
                    shutil.copyfileobj(f, out)
    except (zipfile.BadZipFile, OSError) as e:
        print(f"ffmpeg(prebuild): 解包失败（{e}）", file=sys.stderr)
        return False
    return win_runtime_ready(bin_dir)


def ensure_win_runtime_dlls() -> bool:
    """构建期把运行期 dll 备到 vendor/win/bin/；就位返回 True。

    两级：先取本仓 vendor-v1 Release 的归档（sha256 校验 + 双镜像，与 mac 同族），
    拿不到再退 BtbN 上游（滚动资产，没有可固定的 sha）。失败只提示不中断——导入
    库链接照旧可用，只是运行期得自行放 dll。CI 已自备 dll 时用
    NATIVE_GUI_SKIP_VENDOR=1 跳过这次下载。
    """
    if os.environ.get("NATIVE_GUI_SKIP_VENDOR", "").strip().lower() in ("1", "true", "yes"):
        print("ffmpeg(prebuild): NATIVE_GUI_SKIP_VENDOR 已设，跳过运行期 dll 准备", file=sys.stderr)
        return False
    bin_dir = win_runtime_dir()
    if win_runtime_ready(bin_dir):
        return True
    os.makedirs(bin_dir, exist_ok=True)

    name, sha = WIN_VENDOR_ARCHIVE
    if sha:
        print(f"ffmpeg(prebuild): 取运行期 dll {name}（vendor 归档）", file=sys.stderr)
        data = fetch_vendor_file(name, sha)
        if data is not None and _install_win_zip(data, bin_dir):
            print(
                f"ffmpeg(prebuild): 运行期 dll 已就位 {bin_dir}（vendor 归档，sha256 通过）\n"
                "  运行前把它们放到 exe 同目录（native-gui 仓库可跑 "
                "python scripts/win_ffmpeg_dll.py 代劳）",
                file=sys.stderr,
            )
            return True
        print("ffmpeg(prebuild): vendor 归档没取到或校验不过，退 BtbN 上游", file=sys.stderr)

    src = os.environ.get("NATIVE_GUI_FFMPEG_ZIP", "").strip()
    if src and os.path.isfile(src):
        print(f"ffmpeg(prebuild): 用本地归档 {src}", file=sys.stderr)
        try:
            with open(src, "rb") as fh:
                data = fh.read()
        except OSError as e:
            print(f"ffmpeg(prebuild): 读本地归档失败（{e}）", file=sys.stderr)
            return False
        ok = _install_win_zip(data, bin_dir)
    else:
        url = src or WIN_DLL_URL
        print(f"ffmpeg(prebuild): 取运行期 dll {url}", file=sys.stderr)
        zip_path = os.path.join(win_vendor_dir(), "win", url.rsplit("/", 1)[-1])
        if not _download(url, zip_path):
            print(
                "ffmpeg(prebuild): 运行期 dll 未就位——构建仍可完成，但运行前要自备\n"
                "  avcodec-63.dll 等与 exe 同目录（或 PATH）；离线可用 "
                "NATIVE_GUI_FFMPEG_ZIP 指本地归档",
                file=sys.stderr,
            )
            return False
        try:
            with open(zip_path, "rb") as fh:
                data = fh.read()
        finally:
            try:
                os.remove(zip_path)
            except OSError:
                pass
        ok = _install_win_zip(data, bin_dir)

    if ok:
        print(
            f"ffmpeg(prebuild): 运行期 dll 已就位 {bin_dir}\n"
            "  运行前把它们放到 exe 同目录（native-gui 仓库可跑 "
            "python scripts/win_ffmpeg_dll.py 代劳）",
            file=sys.stderr,
        )
    else:
        print("ffmpeg(prebuild): 归档里没找齐 7 个运行期 dll", file=sys.stderr)
    return ok


def mac_vendor_dir() -> str:
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "vendor", "mac")


def mac_vendor_ready(libdir: str) -> str | None:
    """vendor/mac 的可用判据：头树齐 + 五个库都解得开 -l 短名（要 symlink）。
    就位返回 include 目录，否则 None。"""
    inc = os.path.join(mac_vendor_dir(), "include")
    if not os.path.isfile(os.path.join(inc, "libavformat", "avformat.h")):
        return None
    for stem in MAC_DYLIBS:
        if not os.path.isfile(os.path.join(libdir, f"lib{stem}.dylib")):
            return None
    return inc


def mac_vendor_tarball() -> tuple[str, str] | None:
    arch = platform.machine()
    return MAC_VENDOR_TARBALLS.get(arch)


def vendor_bases() -> list[str]:
    env = os.environ.get("NATIVE_GUI_VENDOR_BASE", "")
    extra = [b.strip().rstrip("/") for b in env.split(",") if b.strip()]
    return extra + VENDOR_BASES


# 默认双镜像走**并行竞速**：同时向各镜像发请求，谁先返回完整且 sha256 校验
# 通过就用谁——DNS 慢、连接慢、慢速滴流的镜像天然落后，总耗时 = 最快镜像的
# 时间（GitHub 滴流的机器上等于 gitee 的几秒，而不是串行等预算耗尽）。兜底
# 总预算仍在：所有镜像都 60 秒无产出才失败。前置教训不变：urlopen 的 timeout
# 是 socket 级，DNS 挂起与滴流要靠竞速+总预算双机制兜。
MAC_VENDOR_BUDGET = 60


def _fetch_race(bases: list[str], url_name: str, sha: str, socket_timeout: int) -> "bytes | None":
    import queue
    import threading
    import time

    q: "queue.Queue[tuple[str, bytes | None]]" = queue.Queue()

    def worker(base: str) -> None:
        try:
            data = urllib.request.urlopen(
                f"{base}/{url_name}", timeout=socket_timeout
            ).read()
            q.put((base, data))
        except Exception:  # noqa: BLE001——失败也入队，主流程继续收其余镜像
            q.put((base, None))

    threads = [threading.Thread(target=worker, args=(b,), daemon=True) for b in bases]
    for t in threads:
        t.start()
    deadline = time.monotonic() + MAC_VENDOR_BUDGET
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
            print(f"ffmpeg(prebuild): 镜像失败（{base}）", file=sys.stderr)
            continue
        if hashlib.sha256(data).hexdigest() != sha:
            print(f"ffmpeg(prebuild): {base} 上 sha256 不符，看其余镜像", file=sys.stderr)
            continue
        print(f"ffmpeg(prebuild): 命中镜像 {base}", file=sys.stderr)
        return data
    print(
        f"ffmpeg(prebuild): 全部镜像 {MAC_VENDOR_BUDGET} 秒总预算内都没给出"
        "校验通过的文件",
        file=sys.stderr,
    )
    return None


def _fetch_serial(bases: list[str], url_name: str, sha: str, socket_timeout: int) -> "bytes | None":
    """串行按序形态（NATIVE_GUI_VENDOR_BASE 指定自定义源时用——用户指内网/
    私有镜像时不并行外网）。单源仍线程包裹总预算兜底：DNS 挂起/滴流的
    socket 级教训不因串行而失效。"""
    import threading

    for base in bases:
        full = f"{base}/{url_name}"
        print(f"ffmpeg(prebuild): 取 vendor {full} ...", file=sys.stderr)
        box: dict = {}

        def run(base: str = base) -> None:
            try:
                box["data"] = urllib.request.urlopen(full, timeout=socket_timeout).read()
            except Exception:  # noqa: BLE001
                box["data"] = None

        t = threading.Thread(target=run, daemon=True)
        t.start()
        t.join(MAC_VENDOR_BUDGET)
        data = box.get("data")
        if data is not None and hashlib.sha256(data).hexdigest() == sha:
            return data
        print(f"ffmpeg(prebuild): 镜像失败或 sha256 不符（{full}），换下一个", file=sys.stderr)
    return None


def fetch_vendor_file(url: str, sha: str) -> "bytes | None":
    bases = vendor_bases()
    if os.environ.get("NATIVE_GUI_VENDOR_BASE", "").strip():
        # 自定义源前置：串行按序，不做并行外网竞速
        return _fetch_serial(bases, url, sha, MAC_VENDOR_TIMEOUT)
    return _fetch_race(bases, url, sha, MAC_VENDOR_TIMEOUT)


def ensure_mac_vendor() -> bool:
    """vendor/mac 缺失时从 Release 下载归档并解开；就位返回 True。
    解完对 lib/*.dylib 补 0755（dyld 映射执行段要求 x 位，tar 解包在某些
    umask/归档头缺失下会掉）。"""
    libdir = os.path.join(mac_vendor_dir(), "lib")
    if mac_vendor_ready(libdir):
        return True
    got = mac_vendor_tarball()
    if got is None:
        print(
            f"ffmpeg(prebuild): 架构 {platform.machine()} 的 mac 归档尚未提供"
            "（brew install ffmpeg 走 pkg-config 路不受影响）",
            file=sys.stderr,
        )
        return False
    name, sha = got
    data = fetch_vendor_file(name, sha)
    if data is None:
        print(
            f"ffmpeg(prebuild): 全部镜像都没取到 {name}\n"
            "  离线环境可手工解开到 vendor/mac/（include/ + lib/），"
            "或用 NATIVE_GUI_VENDOR_BASE 指到自己的源",
            file=sys.stderr,
        )
        return False
    import io
    import tempfile

    base = os.path.dirname(mac_vendor_dir())
    os.makedirs(base, exist_ok=True)
    with tempfile.TemporaryDirectory(dir=base) as tmp:
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as tar:
            try:
                tar.extractall(tmp, filter="tar")  # noqa: S202——内容经 sha256 校验
            except TypeError:  # Python < 3.12 没有 filter 形参
                tar.extractall(tmp)
        # 归档顶层统一是 ffmpeg-macos-*/，找到它再整棵搬进 vendor/mac
        entries = [e for e in os.listdir(tmp) if e != "." and not e.startswith(".")]
        if len(entries) != 1:
            print(
                f"ffmpeg(prebuild): 归档顶层结构意外（{entries}），放弃安装",
                file=sys.stderr,
            )
            return False
        src_root = os.path.join(tmp, entries[0])
        dst = mac_vendor_dir()
        if os.path.exists(dst):
            shutil.rmtree(dst)
        shutil.move(src_root, dst)
    for fn in os.listdir(libdir):
        if fn.endswith(".dylib"):
            os.chmod(os.path.join(libdir, fn), 0o755)
    print(f"ffmpeg(prebuild): 已就位 {mac_vendor_dir()}（sha256 校验通过）", file=sys.stderr)
    return mac_vendor_ready(libdir) is not None


def mac_pkg_config_route() -> int:
    """pkg-config 一路：探 brew 的 ffmpeg 并下发 -I/-L/-l。成功 0，失败 -1
    （pkg-config 命令缺失也算这一路失败，交给 vendor 路）。"""
    if shutil.which("pkg-config") is None:
        return -1
    env = mac_env()
    flags: list[str] = []
    for lib in LIBS:
        out = pkg_config(["--libs", lib], env)
        if not out:
            return -1
        flags.extend(out.split())
    inc = mac_includedir(BREW_PREFIXES[0] + "/include")
    # brew 的 .pc 一般已在 Libs 里展开过 -L，这里再问一次 libdir 兜底
    # （Apple Silicon 是 /opt/homebrew/lib、Intel 是 /usr/local/lib，写死任
    # 一个都会在另一类机器上链不到）。
    libdir = pkg_config(["--variable=libdir", "libavformat"], env) or os.path.join(
        os.path.dirname(inc), "lib"
    )
    print(
        f"ffmpeg(prebuild): macOS 走 brew 的 ffmpeg（include={inc} lib={libdir}）",
        file=sys.stderr,
    )
    emit(
        {
            "vars": {
                "FFMPEG_INC": inc,
                "FFMPEG_STUB_CC": "-finput-charset=UTF-8",
            },
            "link_configs": [
                {
                    "package": PKG,
                    "link_flags": f"-L{libdir} " + " ".join(flags),
                }
            ],
        }
    )
    return 0


def mac_vendor_route() -> int:
    """vendor 归档一路：就位后下发 -L/-l/-rpath。成功 0，失败 -1（由调用方
    汇总成退出码）。"""
    if not ensure_mac_vendor():
        return -1
    vdir = mac_vendor_dir()
    inc = mac_vendor_ready(os.path.join(vdir, "lib"))
    if inc is None:
        return -1
    libdir = os.path.join(vdir, "lib")
    # 每个路径参数单独双引号：link_flags 按 shell 词法拆分，撇号用户名的
    # 教训同 Windows 分支（proposals/adaptation.md「撇号路径让整条 link_flags
    # 静默消失」）；-Wl,-rpath 指向绝对路径，dyld 据此加载 @rpath 依赖。
    q = lambda p: '"' + p + '"'  # noqa: E731
    link_flags = (
        f"{q('-L' + libdir)} "
        + " ".join(f"-l{s}" for s in MAC_DYLIBS)
        + f" {q('-Wl,-rpath,' + libdir)}"
    )
    print(
        f"ffmpeg(prebuild): macOS 走 vendor 归档（include={inc} lib={libdir}）",
        file=sys.stderr,
    )
    emit(
        {
            "vars": {
                "FFMPEG_INC": inc,
                "FFMPEG_STUB_CC": "-finput-charset=UTF-8",
            },
            "link_configs": [{"package": PKG, "link_flags": link_flags}],
        }
    )
    return 0


# brew 的两个前缀（Apple Silicon / Intel）。GUI 环境里 PKG_CONFIG_PATH 与
# /usr/local、/opt/homebrew 都不在默认搜索路径上，探测前显式拼进去。
BREW_PREFIXES = ["/opt/homebrew", "/usr/local"]


def mac_env() -> dict:
    parts = [os.path.join(p, "lib", "pkgconfig") for p in BREW_PREFIXES]
    cur = os.environ.get("PKG_CONFIG_PATH", "")
    if cur:
        parts.insert(0, cur)
    return dict(os.environ, PKG_CONFIG_PATH=":".join(parts))


def pkg_config(args: list[str], env: dict | None = None) -> str:
    """跑一次 pkg-config，成功给 stdout（按空白切分），失败给空串。"""
    run = subprocess.run(
        ["pkg-config", *args], capture_output=True, text=True, env=env
    )
    return " ".join(run.stdout.split()) if run.returncode == 0 else ""


def mac_includedir(fallback: str) -> str:
    """ffmpeg 头所在目录：先问 pkg-config 的 includedir，问不到就扫 brew 前缀
    （存在 libavformat/avformat.h 的那一个），再不行给占位值让后面报同一个错。"""
    got = pkg_config(["--cflags-only-I", "libavformat"])
    for tok in got.split():
        if tok.startswith("-I"):
            cand = tok[2:]
            if os.path.isfile(os.path.join(cand, "libavformat", "avformat.h")):
                return cand
    for p in BREW_PREFIXES:
        cand = os.path.join(p, "include")
        if os.path.isfile(os.path.join(cand, "libavformat", "avformat.h")):
            return cand
    return fallback


def emit(payload: dict) -> None:
    print(json.dumps(payload))


def main() -> int:
    system = platform.system()

    if system == "Windows":
        vendor = win_vendor_dir()
        inc = os.path.join(vendor, "include")
        missing = [l for l in WIN_LIBS if not os.path.isfile(os.path.join(vendor, l))]
        has_headers = os.path.isfile(os.path.join(inc, "libavformat", "avformat.h"))
        if not has_headers or missing:
            # vendor 内容缺失：降级为空 link_configs 保可构建（与 macOS 同口径）
            print(
                "ffmpeg(prebuild): vendor dev 内容缺失"
                f"（{'缺头文件' if not has_headers else ''}"
                f"{' 缺 ' + ' '.join(missing) if missing else ''}），"
                "ffmpeg 后端降级——请按 README 恢复 vendor/",
                file=sys.stderr,
            )
            emit({"vars": {"FFMPEG_INC": ".", "FFMPEG_STUB_CC": "/utf-8"}, "link_configs": []})
            return 0
        # 路径一律正斜杠（cl 对两种都接受，还免去 JSON 转义）
        inc_norm = inc.replace("\\", "/")
        # 各库路径单独加双引号：link_flags 会被按 shell 词法拆分，而用户名含
        # 单引号的机器（如 noah'liu）里路径自带未配对引号，整条 link_flags 会被
        # 静默丢弃（与 webview 桩原 WEB_PACKAGE 同一个坑，根因与判据见
        # proposals/adaptation.md「同族第二条·撇号路径让整条 link_flags 静默消失」）。
        link_flags = " ".join(
            f'"{p}"'
            for p in (os.path.join(vendor, l).replace("\\", "/") for l in WIN_LIBS)
        )
        print(
            "ffmpeg(prebuild): Windows 走 vendor 导入库（BtbN lgpl-shared）",
            file=sys.stderr,
        )
        ensure_win_runtime_dlls()
        emit(
            {
                "vars": {"FFMPEG_INC": inc_norm, "FFMPEG_STUB_CC": "/utf-8"},
                "link_configs": [{"package": PKG, "link_flags": link_flags}],
            }
        )
        return 0

    if system == "Darwin":
        # 两级：pkg-config 探系统 ffmpeg（brew 的构建给得出 .pc）→ 退 Release
        # 下载的 vendor 归档（免 brew 机器的通路，@rpath 动态链）。两路都断
        # 才非零退出——媒体线要求真给得出 ffmpeg，静默编一支「看着能链、
        # 跑起来没解码器」的桩更坏。
        code = mac_pkg_config_route()
        if code == 0:
            return 0
        if mac_vendor_route() == 0:
            return 0
        print(
            "ffmpeg(prebuild): macOS 两路都拿不到 ffmpeg"
            "（brew install pkg-config ffmpeg，或按 README 手工放置 vendor/mac/），"
            "ffmpeg 后端不可用",
            file=sys.stderr,
        )
        return 1

    if system != "Linux":
        print(
            "ffmpeg(prebuild): 其余平台降级为空 link_configs（Linux/Windows/macOS 之外的目标）",
            file=sys.stderr,
        )
        emit({"vars": {"FFMPEG_INC": ".", "FFMPEG_STUB_CC": "-finput-charset=UTF-8"}, "link_configs": []})
        return 0

    if shutil.which("pkg-config") is None:
        print("ffmpeg(prebuild): 缺少 pkg-config，请先安装", file=sys.stderr)
        return 1
    flags: list[str] = []
    for lib in LIBS:
        probe = subprocess.run(
            ["pkg-config", "--libs", lib], capture_output=True, text=True
        )
        if probe.returncode != 0:
            print(
                f"ffmpeg(prebuild): 缺少 {lib} 开发包"
                f"（Ubuntu: sudo apt install -y {' '.join(l + '-dev' for l in LIBS)}）",
                file=sys.stderr,
            )
            return 1
        flags.extend(probe.stdout.split())
    emit(
        {
            "vars": {
                "FFMPEG_INC": "/usr/include",
                # gcc/clang 默认按 UTF-8 读源，显式声明与 Windows 的 /utf-8 同义
                "FFMPEG_STUB_CC": "-finput-charset=UTF-8",
            },
            "link_configs": [{"package": PKG, "link_flags": " ".join(flags)}],
        }
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
