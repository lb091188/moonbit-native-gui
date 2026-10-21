#!/usr/bin/env python3
"""把 ffmpeg 运行期 dll 放到媒体示例的 exe 同目录（Windows，发布/分发时用）。

audio / video 示例经 ffmpeg-mbt 的动态导入库链接，运行期需要下列 5 个 dll。
**开发期跑示例不需要本脚本**：这 5 个 dll 已被声明为延迟加载，且
`vendor/win/bin` 的绝对路径编进了 exe，`ffmpeg_supported()` 首次调用时从那里
加载（`moon add` 的工程走 `.mooncakes` 里那份）。本脚本做的是**发布形态**——
把 dll 复制到 exe 旁做 app-local 部署，这样 exe 拷到别的机器上也能跑。

  avcodec-63.dll  avformat-63.dll  avutil-61.dll  swscale-10.dll  swresample-7.dll

本脚本按下列顺序找一份可用的 ffmpeg bin 目录，把其中的 av*/sw* dll 复制到
exe 所在目录（app-local 部署，加载器第一顺位就找 exe 同目录）：

  1. `--dll-dir` / 环境变量 NATIVE_GUI_FFMPEG_BIN
  2. exe 同目录（已齐则直接返回）
  3. `modules/ffmpeg-mbt/vendor/win/bin`（ffmpeg-mbt 的 prebuild 构建时自动取的
     落点，与导入库同源；缺它就先构建一次）
  4. PATH 中能搜到 avcodec-63.dll 的目录
  5. winget 包目录 %LOCALAPPDATA%\\Microsoft\\WinGet\\Packages\\*FFmpeg*
  6. scoop %USERPROFILE%\\scoop\\apps\\ffmpeg*\\current\\bin
  7. 仓库缓存 .cache/ffmpeg-win/bin（早期版本下载的落点，只读兼容）

下载不归本脚本：`ffmpeg-mbt` 的 prebuild 在 Windows 构建时就会把 dll 取到
`vendor/win/bin`，本脚本只负责把它搬到 exe 旁边。

用法（仓库根）：

    python scripts/win_ffmpeg_dll.py                  # audio 与 video 一起补齐
    python scripts/win_ffmpeg_dll.py audio            # 只补 audio
    python scripts/win_ffmpeg_dll.py video --run      # 补齐后直接启动
    python scripts/win_ffmpeg_dll.py --dll-dir D:\\ffmpeg\\bin
    python scripts/win_ffmpeg_dll.py --dry-run        # 只打印计划，不落盘

dll 只在 `moon clean` 清掉 _build 之后需要重跑一次。
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

# 与 modules/ffmpeg-mbt/vendor/*.lib 同源（BtbN win64-lgpl-shared 9.0）的导入库
# 所指向的 dll；名字里的大版本号即校验依据——版本不符会链接期/加载期直接报错。
REQUIRED_DLLS = [
    "avcodec-63.dll",
    "avformat-63.dll",
    "avutil-61.dll",
    "swscale-10.dll",
    "swresample-7.dll",
]
# 同批可选：与上面同版本配套，带了无害，方便后续包直接用。
OPTIONAL_DLLS = ["avdevice-63.dll", "avfilter-12.dll"]

DLL_PATTERN = re.compile(r"^(av|sw)[a-z]+-\d+\.dll$", re.IGNORECASE)

# 单个 dll 的体积下限：判掉残缺/半截文件，不是精确校验。
DLL_MIN_BYTES = 100 * 1024

EXAMPLES = ["audio", "video"]


def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def module_name(example: str) -> str:
    return f"native-gui-examples-{example}"


def find_exe(example: str) -> Path | None:
    """按构建产物口径找最新的 exe：_build/native/<mode>/build/NoahLiu/<mod>/<mod>.exe"""
    root = repo_root() / "_build" / "native"
    mod = module_name(example)
    hits = [
        p
        for p in root.glob(f"*/build/NoahLiu/{mod}/*.exe")
        if p.is_file()
    ]
    if not hits:
        return None
    return max(hits, key=lambda p: p.stat().st_mtime)


def ffmpeg_dlls(dirpath: Path) -> dict[str, Path]:
    """dirpath 下与本仓 vendor 版本配套的 dll（名 -> 路径）。"""
    got: dict[str, Path] = {}
    if not dirpath.is_dir():
        return got
    for p in dirpath.iterdir():
        if p.is_file() and DLL_PATTERN.match(p.name):
            got[p.name] = p
    return got


def missing(dlls: dict[str, Path]) -> list[str]:
    return [n for n in REQUIRED_DLLS if n not in dlls]


def path_dirs() -> list[Path]:
    out: list[Path] = []
    for raw in os.environ.get("PATH", "").split(os.pathsep):
        if raw.strip():
            out.append(Path(raw))
    return out


def winget_dirs() -> list[Path]:
    """winget 的 portable 包目录；找不到就交下一路。"""
    local = os.environ.get("LOCALAPPDATA")
    if not local:
        return []
    base = Path(local) / "Microsoft" / "WinGet" / "Packages"
    if not base.is_dir():
        return []
    hits: list[Path] = []
    for pkg in base.iterdir():
        if not pkg.is_dir() or "ffmpeg" not in pkg.name.lower():
            continue
        # 包内层级通常 1~3 层（<pkg>/<归档名>/bin），限制深度别漫游整棵树
        for pattern in ("bin", "*/bin", "*/*/bin", "*/*/*/bin"):
            hits.extend(p for p in pkg.glob(pattern) if p.is_dir())
    return hits


def scoop_dirs() -> list[Path]:
    home = os.environ.get("USERPROFILE") or str(Path.home())
    apps = Path(home) / "scoop" / "apps"
    if not apps.is_dir():
        return []
    return [p for p in apps.glob("ffmpeg*/current/bin") if p.is_dir()]


def prebuild_dll_dir() -> Path:
    """ffmpeg-mbt 的 prebuild 在 Windows 构建时取 dll 的落点（与导入库同源）。"""
    return repo_root() / "modules" / "ffmpeg-mbt" / "vendor" / "win" / "bin"


def cache_dir() -> Path:
    """早期版本本脚本自己的下载落点，只读兼容。"""
    return repo_root() / ".cache" / "ffmpeg-win" / "bin"


def resolve_source(explicit: str | None, exe_dir: Path) -> tuple[Path | None, str]:
    """按优先级找 dll 来源，返回 (目录, 来源说明)。"""
    tried: list[str] = []

    def probe(d: Path, label: str) -> tuple[Path | None, str] | None:
        got = ffmpeg_dlls(d)
        if got and not missing(got):
            return d, label
        if got:
            tried.append(f"{label}（缺 {' '.join(missing(got))}）")
        return None

    if explicit:
        cand = probe(Path(explicit), f"--dll-dir {explicit}")
        if cand:
            return cand
        print(f"win-ffmpeg-dll: {explicit} 里没有齐全的 dll", file=sys.stderr)
        return None, ""

    cand = probe(exe_dir, "exe 同目录")
    if cand:
        return cand

    cand = probe(prebuild_dll_dir(), f"prebuild 落点 {prebuild_dll_dir()}")
    if cand:
        return cand

    for d in path_dirs():
        cand = probe(d, f"PATH {d}")
        if cand:
            return cand

    for d in winget_dirs():
        cand = probe(d, f"winget {d}")
        if cand:
            return cand

    for d in scoop_dirs():
        cand = probe(d, f"scoop {d}")
        if cand:
            return cand

    cand = probe(cache_dir(), f"缓存 {cache_dir()}")
    if cand:
        return cand

    for d in tried:
        print(f"win-ffmpeg-dll: 跳过 {d}", file=sys.stderr)
    return None, ""


def build_example(example: str) -> bool:
    """exe 还不在时先构建（moon build examples/<name>，走 workspace 相对路径）。"""
    cmd = ["moon", "build", f"examples/{example}"]
    print(f"win-ffmpeg-dll: 先构建 {' '.join(cmd)}", file=sys.stderr)
    try:
        run = subprocess.run(cmd, cwd=str(repo_root()))
    except FileNotFoundError:
        print("win-ffmpeg-dll: PATH 里没有 moon", file=sys.stderr)
        return False
    return run.returncode == 0


def ensure(example: str, explicit: str | None, dry_run: bool, auto_build: bool = True) -> bool:
    exe = find_exe(example)
    if exe is None and auto_build and not dry_run:
        if not build_example(example):
            print(f"win-ffmpeg-dll: examples/{example} 构建失败", file=sys.stderr)
            return False
        exe = find_exe(example)
    if exe is None:
        print(
            f"win-ffmpeg-dll: 找不到 examples/{example} 的 exe，"
            f"先跑 `moon build examples/{example}`",
            file=sys.stderr,
        )
        return False
    exe_dir = exe.parent
    have = ffmpeg_dlls(exe_dir)
    if not missing(have):
        print(f"win-ffmpeg-dll: {example} 已就位（{exe_dir}）")
        return True

    src, label = resolve_source(explicit, exe_dir)
    if src is None:
        print(
            f"win-ffmpeg-dll: {example} 未补齐（缺 {' '.join(missing(have))}）",
            file=sys.stderr,
        )
        return False

    to_copy = sorted(p for n, p in ffmpeg_dlls(src).items())
    if dry_run:
        print(f"win-ffmpeg-dll: [dry-run] {example} ← {label}")
        for p in to_copy:
            print(f"    {p.name} → {exe_dir}")
        return True

    for p in to_copy:
        shutil.copy2(p, exe_dir / p.name)
    print(f"win-ffmpeg-dll: {example} 补齐（来源 {label}）→ {exe_dir}")
    for name in REQUIRED_DLLS:
        print(f"    {name}")
    return True


def run_example(example: str) -> int:
    exe = find_exe(example)
    if exe is None:
        print(f"win-ffmpeg-dll: 找不到 examples/{example} 的 exe", file=sys.stderr)
        return 1
    print(f"win-ffmpeg-dll: 启动 {exe}")
    subprocess.Popen([str(exe)], cwd=str(repo_root()))
    return 0


def main() -> int:
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, OSError):
            pass

    ap = argparse.ArgumentParser(
        description="把 ffmpeg 运行期 dll 放到媒体示例 exe 同目录（Windows）"
    )
    ap.add_argument("examples", nargs="*",
                    help=f"示例名，可多个；省略则 {', '.join(EXAMPLES)} 全做")
    ap.add_argument("--dll-dir", default=None, help="自带 ffmpeg bin 目录")
    ap.add_argument("--run", action="store_true", help="补齐后启动示例")
    ap.add_argument("--no-build", action="store_true", help="缺 exe 时不自动 moon build")
    ap.add_argument("--dry-run", action="store_true", help="只打印计划不落盘（非 Windows 可跑）")
    args = ap.parse_args()

    targets = args.examples or EXAMPLES
    unknown = [e for e in targets if e not in EXAMPLES]
    if unknown:
        print(f"win-ffmpeg-dll: 未知示例 {unknown}（可选 {EXAMPLES}）", file=sys.stderr)
        return 2

    if os.name != "nt" and not args.dry_run:
        print(
            "win-ffmpeg-dll: 本脚本只给 Windows 用——Linux 走系统 libav*-dev，"
            "macOS 走 brew/vendor 归档，都不需要搬运 dll",
            file=sys.stderr,
        )
        return 0

    results = [ensure(e, args.dll_dir, args.dry_run, not args.no_build) for e in targets]
    ok = all(results)
    if not ok:
        print(
            "win-ffmpeg-dll: 没取到与 vendor 导入库配套的 ffmpeg 运行库 dll。\n"
            "  dll 由 ffmpeg-mbt 的 prebuild 在构建时取到 "
            "modules/ffmpeg-mbt/vendor/win/bin，先跑一次 `moon build examples/audio`；"
            "构建时没下成（网络）可用 NATIVE_GUI_FFMPEG_ZIP=<本地 zip> 重试，\n"
            "  或手工把 bin 目录指过来："
            "python scripts/win_ffmpeg_dll.py --dll-dir <那个 bin>。\n"
            "  dll 须与 modules/ffmpeg-mbt/vendor/*.lib 同一大版本（9.0 系列）。",
            file=sys.stderr,
        )
        return 1
    if args.run and not args.dry_run:
        for e in targets:
            code = run_example(e)
            if code:
                return code
    return 0


if __name__ == "__main__":
    sys.exit(main())
