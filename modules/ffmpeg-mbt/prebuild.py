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

LIBS = ["libavformat", "libavcodec", "libswscale", "libswresample", "libavutil"]
PKG = "NoahLiu/ffmpeg-mbt/src"

# 导入库文件名（BtbN 构建无 lib 前缀）；与 LIBS 顺序对应
WIN_LIBS = ["avformat.lib", "avcodec.lib", "swscale.lib", "swresample.lib", "avutil.lib"]

# ---------------------------------------------------------------------------
# mac vendor 归档（口径与 gui-webview 的 Release 资产同族）：自编 LGPL ffmpeg
# 的动态库 + 头，打包时 id/依赖已 @rpath 化。体积不入库，缺失时下载校验 sha256，
# 双镜像按序尝试、单源超时 20 秒，NATIVE_GUI_VENDOR_BASE 覆盖，离线可提前手工
# 放置 `vendor/mac/`（已存在不动）。归档制作：scripts/make_mac_ffmpeg_vendor.sh。
# ---------------------------------------------------------------------------
MAC_VENDOR_BASES = [
    "https://github.com/lb091188/moonbit-native-gui/releases/download/vendor-v1",
    "https://gitee.com/lb091188/moonbit-native-gui/releases/download/vendor-v1",
]

MAC_VENDOR_TIMEOUT = 20

# -lavformat 等短名（macOS 与 Linux 同用 -l 短名，链接器自己补 lib 前缀/后缀）
MAC_DYLIBS = ["avformat", "avcodec", "swscale", "swresample", "avutil"]

# 按机器架构取归档名。正式归档（scripts/make_mac_ffmpeg_vendor.sh 产物）
# 上传 vendor-v1 Release 后按此格式回填条目，下载侧逐字节校验 sha256：
#   "arm64": ("ffmpeg-macos-arm64-9.0-lgpl-shared.tar.gz", "<sha256>")
# 条目缺席时本路提示「归档尚未提供」，pkg-config（brew）路不受影响。
MAC_VENDOR_TARBALLS: dict[str, tuple[str, str]] = {}


def win_vendor_dir() -> str:
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "vendor")


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
    return extra + MAC_VENDOR_BASES


def fetch_vendor_file(url: str, sha: str) -> "bytes | None":
    for base in vendor_bases():
        full = f"{base}/{url}"
        try:
            print(f"ffmpeg(prebuild): 取 vendor {full} ...", file=sys.stderr)
            data = urllib.request.urlopen(full, timeout=MAC_VENDOR_TIMEOUT).read()
        except Exception as e:  # noqa: BLE001——任何网络/URL 错误都换下一个镜像
            print(f"ffmpeg(prebuild): 镜像失败（{e}）", file=sys.stderr)
            continue
        if hashlib.sha256(data).hexdigest() != sha:
            print(
                f"ffmpeg(prebuild): {url} 在该镜像上 sha256 不符，换下一个",
                file=sys.stderr,
            )
            continue
        return data
    return None


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
    # 教训同 Windows 分支（docs/zh/adaptation.md「撇号路径让整条 link_flags
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
        # docs/zh/adaptation.md「同族第二条·撇号路径让整条 link_flags 静默消失」）。
        link_flags = " ".join(
            f'"{p}"'
            for p in (os.path.join(vendor, l).replace("\\", "/") for l in WIN_LIBS)
        )
        print(
            "ffmpeg(prebuild): Windows 走 vendor 导入库（BtbN lgpl-shared）",
            file=sys.stderr,
        )
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
