#!/usr/bin/env python3
"""演示板本地化覆盖率门禁：页面上每个取译口都必须能在内嵌英文目录里查到。

口径（三条取译通道，一条漏了就静默显示中文——这正是「点了地球页面不动」的根因）：
① `@shared.tx("中文")` / `tx("中文")`：键 = 中文原文（顶层键）；
② `@shared.section("段名", …)`：键 = `seg.` + 段名（`page()` 的 label_of 出口）；
③ `@shared.nav_label`：键 = `nav.` + 侧栏页名（main 的路由表）。

目录本体是 `examples/showcase/shared/i18n_data.mbt` 里的 MoonBit 串拼接常量，
这里按它落成的 TOML 文本行反解：顶层键 = 中文原文，`[段]` 头之后的键带段前缀。

跑法：python3 scripts/check_showcase_i18n.py（非零退出 = 有漏网的显示串）
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SHOW = ROOT / "examples" / "showcase"


def catalog_keys():
    """反解 EN_CATALOG：返回 {带前缀的键} 集合，并顺带查 `[meta]` 是否在最后。"""
    text = (SHOW / "shared" / "i18n_data.mbt").read_text(encoding="utf-8")
    # 拼出来的 TOML 文本 = 各 `"…"` 字面量段，把 `\"` 还原后按行拆
    parts = re.findall(r'"((?:[^"\\]|\\.)*)"', text)
    toml = "".join(p.replace('\\"', '"').replace("\\n", "\n") for p in parts)
    keys, prefix, meta_at, lines = set(), "", None, toml.splitlines()
    for n, line in enumerate(lines):
        s = line.strip()
        if not s or s[0] == "#":
            continue
        if s[0] == "[":
            prefix = s[1 : s.index("]")] + "."
            if prefix == "meta.":
                meta_at = n
            continue
        m = re.match(r'"([^"]+)"\s*=\s*"(.*)"$', s) or re.match(r"([^=]+?)\s*=\s*\"(.*)\"$", s)
        if m:
            keys.add(prefix + m.group(1))
    top_after_meta = [
        k for k in keys if "." not in k.replace("meta.", "") and not k.startswith("meta.")
    ]
    if meta_at is not None:
        for line in lines[meta_at + 1 :]:
            s = line.strip()
            if s and s[0] != "[" and s[0] != "#" and "=" in s and not s.startswith("locale"):
                print("!! `[meta]` 之后还有顶层键，整表会静默查不到：", s)
                sys.exit(1)
    return keys, top_after_meta


def tx_keys():
    """①正文取译口的键集合。"""
    got = set()
    for p in list((SHOW / "pages").glob("*.mbt")) + list((SHOW / "shared").glob("*.mbt")):
        for m in re.finditer(r'@shared\.tx\("([^"\\]+)"\)|\btx\("([^"\\]+)"\)', p.read_text(encoding="utf-8")):
            got.add(m.group(1) or m.group(2))
    return got


def seg_keys():
    """②段名通道（无汉字的段名如 `Markdown` 本来就不需要译，不计）。"""
    got = set()
    for p in (SHOW / "pages").glob("*.mbt"):
        s = p.read_text(encoding="utf-8")
        for m in re.finditer(r"@shared\.section\(\s*\n?\s*\"((?:[^\"\\]|\\.)*)\"", s):
            if re.search(r"[一-鿿]", m.group(1)):
                got.add("seg." + m.group(1))
    return got


def nav_keys():
    """③侧栏页名通道：路由表里 `route_of_page(box, "页名", …)` 的第二个实参。"""
    main = (SHOW / "main.mbt").read_text(encoding="utf-8")
    return {
        "nav." + m.group(1) for m in re.finditer(r'route_of_page\(box,\s*"([^"]+)"', main)
    }


def main():
    keys, _ = catalog_keys()
    bad = []
    for label, want in (("正文 tx", tx_keys()), ("段名 seg", seg_keys()), ("侧栏 nav", nav_keys())):
        miss = sorted(k for k in want if k not in keys)
        print(f"{label}: 取译口 {len(want)}，目录缺 {len(miss)}")
        bad += miss
    if bad:
        print("\n英文目录里查不到的键（英文态会回落中文）：")
        for k in bad:
            print("  ", k)
        sys.exit(1)
    print("覆盖完整。目录条目", len(keys))


if __name__ == "__main__":
    main()
