#!/usr/bin/env python3
"""NoahLiu/gui-gpu 的预构建脚本（--moonbit-unstable-prebuild）。

做一件事：按平台把 wgpu-native 的 release 归档拉到 `vendor/` 并校验 sha256，
解出 `lib/`（动态库）与 `include/`（wgpu.h）。**不向链接面注入任何库**——
本模块只做运行期 dlopen 探测（见 gpu/probe.c），所以 link_configs 恒为空；
下载失败/离线同样是空 link_configs（= 没装 GPU 扩展的降级形态，不是错误）。

口径与 `modules/gui-media/prebuild.py` 同源：串行按序、sha256 过了才落盘、
多个镜像对同一 sha 验证；stdout 只打 JSON，进度走 stderr。
"""

from __future__ import annotations

import hashlib
import json
import os
import platform
import sys
import urllib.request
import zipfile
from pathlib import Path

PKG = "NoahLiu/gui-gpu/gpu"
TAG = "v29.0.1.1"

# (系统, 机器) → (归档名, sha256)
ASSETS = {
    ("linux", "amd64"): (
        "wgpu-linux-x86_64-release.zip",
        "95a4d90c071005a98d03eab348beaa6b07e16eb00d1dcdb9f8348f75eb97ec5a",
    ),
    ("windows", "amd64"): (
        "wgpu-windows-x86_64-msvc-release.zip",
        "7e67d7445c42aeb85e30f88930fd8d7d83ee769e3390aeb1ada75ebf3cf78132",
    ),
    ("darwin", "x86_64"): (
        "wgpu-macos-x86_64-release.zip",
        "8e2f7378548ddd0e2cf21e7d864dda46e953f0af724855a33778b85ead206d41",
    ),
    ("darwin", "arm64"): (
        "wgpu-macos-aarch64-release.zip",
        "a5797a37b1adf720bcd5dcffb291edbbd5b7b14be0a3874c28e6393a655a7a3e",
    ),
}

# 双镜像：官方 Release 优先，镜像同 sha（任一通过都算数）
MIRRORS = [
    "https://github.com/gfx-rs/wgpu-native/releases/download/{tag}/{name}",
    "https://ghfast.top/https://github.com/gfx-rs/wgpu-native/releases/download/{tag}/{name}",
]

ROOT = Path(__file__).resolve().parent
VENDOR = ROOT / "vendor"
MARKER = VENDOR / ".ok"


def out_json() -> None:
    # 永远空 link_configs：本模块只做运行期 dlopen，不占用链接面
    print(json.dumps({"link_configs": []}))


def key():
    sysname = platform.system().lower()
    machine = platform.machine().lower()
    return (sysname, "amd64" if machine in ("amd64", "x86_64") else machine)


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def fetch(url: str, dest: Path, budget_s: int = 180) -> bool:
    """流式下载并带**总预算**：单次 socket 超时管不住「挂住不收数据」的镜像，
    超过预算就放弃这条镜像（构建不能被人肉等网络卡死）。"""
    import time

    start = time.monotonic()
    try:
        with urllib.request.urlopen(url, timeout=20) as r, dest.open("wb") as f:
            while True:
                if time.monotonic() - start > budget_s:
                    raise TimeoutError(f"download budget {budget_s}s exceeded")
                chunk = r.read(1 << 16)
                if not chunk:
                    break
                f.write(chunk)
        return dest.stat().st_size > 0
    except Exception as e:  # noqa: BLE001 —— 任何网络问题都当「这条镜像不行」
        print(f"[gui-gpu] mirror failed {url}: {e}", file=sys.stderr)
        dest.unlink(missing_ok=True)
        return False


def main() -> None:
    k = key()
    spec = ASSETS.get(k)
    if not spec:
        print(f"[gui-gpu] no wgpu-native asset for {k} —— degrade", file=sys.stderr)
        out_json()
        return
    name, sha = spec
    if MARKER.exists():
        out_json()
        return
    VENDOR.mkdir(parents=True, exist_ok=True)
    tmp = VENDOR / name
    for mirror in MIRRORS:
        url = mirror.format(tag=TAG, name=name)
        if not fetch(url, tmp):
            continue
        got = sha256_of(tmp)
        if got != sha:
            print(f"[gui-gpu] sha256 mismatch from {url}", file=sys.stderr)
            continue
        try:
            with zipfile.ZipFile(tmp) as z:
                z.extractall(VENDOR)
        except Exception as e:  # noqa: BLE001
            print(f"[gui-gpu] unzip failed: {e}", file=sys.stderr)
            continue
        tmp.unlink(missing_ok=True)
        MARKER.write_text(f"{TAG}\n{name}\n{sha}\n", encoding="utf-8")
        print(f"[gui-gpu] wgpu-native {TAG} ready ({name})", file=sys.stderr)
        out_json()
        return
    print("[gui-gpu] wgpu-native unavailable —— degrade to software path", file=sys.stderr)
    tmp.unlink(missing_ok=True)
    out_json()


if __name__ == "__main__":
    main()
