#!/usr/bin/env python3
"""品牌图标导出器:assets/brand 的 SVG → 各平台 PNG 档。

用法:
  python3 scripts/gen_brand_icons.py [--out <目录>] [--master <svg>] [--mono <svg>]

产物(默认 <repo>/.brand-dist/,gitignore 排除;落位各消费点用 cp):
  master/app-icon-<边长>.png              1024/512/256/128/64/48/32/16
  macos/icon_<Apple iconset 命名>.png      十档,mng package 的 sips+iconutil 直接可用
  windows/icon-<边长>.png                  256/128/48/32/16(ICO 源)
  linux/icon-<边长>.png                    512/256/128/64/48/32/16
  web/favicon-<边长>.png + apple-touch-icon.png   16/32/48 + 180
  mono/app-icon-mono-<边长>.png            1024/64/48/32/16(托盘 / themed icon 预留)

渲染口径:qlmanage -t -s 1024 一次出 1024 PNG(Quick Look 的 WebKit 管线:
透明底保留、圆角如实;输出名固定为 <原名>.svg.png),再 sips -z 缩档。
仅 macOS 可用(依赖 /usr/bin/qlmanage 与 /usr/bin/sips)。
"""

import argparse
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent

MASTER_SIZES = [1024, 512, 256, 128, 64, 48, 32, 16]
ICONSET = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]
WINDOWS_SIZES = [256, 128, 48, 32, 16]
LINUX_SIZES = [512, 256, 128, 64, 48, 32, 16]
WEB = [(16, "favicon-16.png"), (32, "favicon-32.png"), (48, "favicon-48.png"), (180, "apple-touch-icon.png")]
MONO_SIZES = [1024, 64, 48, 32, 16]


def run(cmd):
    subprocess.run(cmd, check=True, capture_output=True, text=True)


def render_1024(svg: Path, out_png: Path) -> None:
    """qlmanage 渲染 1024 PNG(输出名固定 <原名>.svg.png,先落临时目录再挪)。"""
    out_png.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory() as tmp:
        run(["qlmanage", "-t", "-s", "1024", "-o", tmp, str(svg)])
        produced = Path(tmp) / (svg.name + ".png")
        if not produced.exists():
            sys.exit(f"qlmanage 未产出 {produced}")
        shutil.move(produced, out_png)


def scale(png_1024: Path, size: int, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    run(["sips", "-z", str(size), str(size), str(png_1024), "--out", str(dst)],
        )


def export_family(png_1024: Path, root: Path, jobs) -> None:
    """jobs: [(size, 相对文件名)]"""
    for size, rel in jobs:
        scale(png_1024, size, root / rel)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=str(REPO / ".brand-dist"))
    ap.add_argument("--master", default=str(REPO / "assets/brand/app-icon.svg"))
    ap.add_argument("--mono", default=str(REPO / "assets/brand/app-icon-mono.svg"))
    args = ap.parse_args()

    master_svg, mono_svg, out = Path(args.master), Path(args.mono), Path(args.out)
    for tool in ("qlmanage", "sips"):
        if shutil.which(tool) is None:
            sys.exit(f"缺少 {tool}:本脚本仅在 macOS 上可用")
    if not master_svg.exists():
        sys.exit(f"缺 master SVG:{master_svg}")

    out.mkdir(parents=True, exist_ok=True)

    master_1024 = out / "master" / "app-icon-1024.png"
    render_1024(master_svg, master_1024)
    export_family(master_1024, out / "master", [(s, f"app-icon-{s}.png") for s in MASTER_SIZES])
    export_family(master_1024, out / "macos", [(s, name) for s, name in ICONSET])
    export_family(master_1024, out / "windows", [(s, f"icon-{s}.png") for s in WINDOWS_SIZES])
    export_family(master_1024, out / "linux", [(s, f"icon-{s}.png") for s in LINUX_SIZES])
    export_family(master_1024, out / "web", WEB)

    if mono_svg.exists():
        mono_1024 = out / "mono" / "app-icon-mono-1024.png"
        render_1024(mono_svg, mono_1024)
        export_family(mono_1024, out / "mono", [(s, f"app-icon-mono-{s}.png") for s in MONO_SIZES])

    print(f"完成 → {out}")


if __name__ == "__main__":
    main()
