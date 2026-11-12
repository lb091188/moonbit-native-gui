#!/usr/bin/env python3
# 示例体积基线测量(A5 体积门禁):对 hello / components 跑 release+strip 构建,
# 从 moon 的 Artifacts 输出抓可执行路径、记字节数,合并进 tools/size-baseline.json。
#
# 用法:
#   python3 scripts/size_baseline.py            # 只量本平台,打印读数
#   python3 scripts/size_baseline.py --update   # 量完把本平台条目合并写回基线
#
# 平台键与 CI 矩阵一致:darwin-aarch64 / windows-x86_64 / linux-x86_64。
# CI(size-gate.yml)的 gate 腿拿同一份 JSON 对基线出 diff:
# 超过 max(5%, 128KB) 即红线。基线更新走人工:跑 --update 后把 diff 提交。
import json
import os
import re
import subprocess
import sys

# Windows 控制台默认 cp1252：读数/错误行是中文，直接 print 会抛
# UnicodeEncodeError（与读 moon 输出同一类问题，读写两头都显式 UTF-8）。
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, OSError):
        pass

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BASELINE = os.path.join(ROOT, "tools", "size-baseline.json")
EXAMPLES = ["hello", "components"]


def host_platform():
    if sys.platform == "darwin":
        return "darwin-aarch64"
    if sys.platform == "win32" or sys.platform == "cygwin":
        return "windows-x86_64"
    return "linux-x86_64"


def build_exe(module_dir):
    """在示例目录跑 release+strip 构建,返回本模块可执行绝对路径。

    workspace 构建的 Artifacts 段把全部成员的产物都列出来,必须按模块名
    `NoahLiu/native-gui-examples-<目录>` 过滤(与 mng 的 artifact_of_log 同口径)。
    """
    module = f"NoahLiu/native-gui-examples-{module_dir}"
    # 显式 UTF-8：moon 输出中文进度/Artifacts，Windows 默认按 cp1252 解码会
    # 在读取线程里抛 UnicodeDecodeError（stdout 变 None，后续拼接再炸一次）。
    r = subprocess.run(
        ["moon", "build", "--target", "native", "--release", "--strip"],
        cwd=os.path.join(ROOT, "examples", module_dir),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    out = r.stdout + r.stderr
    if r.returncode != 0:
        sys.stderr.write(out[-2000:])
        raise SystemExit(f"{module_dir}: moon build 失败(退出码 {r.returncode})")
    # Artifacts 段:每行 "  <模块/包> <产物路径>";抓本模块的(末段即可执行)
    lines = out.splitlines()
    grab = False
    for line in lines:
        t = line.strip()
        if t == "Artifacts:":
            grab = True
            continue
        if grab:
            if not line.startswith("  ") or not t:
                grab = False
                continue
            parts = t.split()
            if len(parts) >= 2 and parts[0].startswith(module) and os.path.isfile(parts[-1]):
                return os.path.abspath(parts[-1])
    raise SystemExit(f"{module_dir}: Artifacts 输出里没抓到 {module} 的可执行\n{out[-1500:]}")


def main():
    update = "--update" in sys.argv
    plat = host_platform()
    sizes = {}
    for name in EXAMPLES:
        exe = build_exe(name)
        n = os.path.getsize(exe)
        sizes[name] = n
        print(f"{plat} {name}: {n} bytes  ({exe})")
    if not update:
        return
    # CI 档:SIZE_BASELINE_OUT 指向临时文件时只把本平台读数写那里(不改仓库
    # 基线,汇总腿自己拿读数对仓库基线出 diff);本地档(--update 无该变量)
    # 才合并写回 tools/size-baseline.json。
    out_path = os.environ.get("SIZE_BASELINE_OUT", "")
    if out_path:
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump({plat: sizes}, f, indent=2, sort_keys=True)
            f.write("\n")
        print(f"读数已写 {out_path}(CI 档,不动仓库基线)")
        return
    data = {}
    if os.path.isfile(BASELINE):
        with open(BASELINE, "r", encoding="utf-8") as f:
            data = json.load(f)
    data[plat] = sizes
    os.makedirs(os.path.dirname(BASELINE), exist_ok=True)
    with open(BASELINE, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, sort_keys=True)
        f.write("\n")
    print(f"基线已更新:{BASELINE} 的 {plat} 条目(记得把 diff 提交)")


if __name__ == "__main__":
    main()
