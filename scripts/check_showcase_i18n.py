#!/usr/bin/env python3
"""演示板本地化覆盖率门禁：页面上每个取译口都必须能在内嵌英文目录里查到。

口径（四条取译通道，一条漏了就静默显示中文——这正是「点了地球页面不动」的根因）：
① `@shared.tx("中文")` / `tx("中文")`：键 = 中文原文（顶层键）；
② `@shared.section("段名", …)`：键 = `seg.` + 段名（`page()` 的 label_of 出口）；
③ `@shared.nav_label`：键 = `nav.` + 侧栏页名（main 的路由表）；
④ `@shared.tr_with("dyn.x", vars, zh)`：带插值的状态/回显串，模板里 `{名}` 由 tr_with 填。

目录本体是 `examples/showcase/shared/i18n_data.mbt` 里的 MoonBit 串拼接常量，
这里按它落成的 TOML 文本行反解：顶层键 = 中文原文，`[段]` 头之后的键带段前缀。

跑法：python3 scripts/check_showcase_i18n.py（非零退出 = 有漏网的显示串）
"""

import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
SHOW = ROOT / "examples" / "showcase"


def unescape_moon(s):
    """MoonBit 源串解一层转义：`\\n`(源) → 真换行，`\\\\n`(源) → 反斜杠+n 两字符。"""
    out, i = [], 0
    tbl = {"n": "\n", "t": "\t", "r": "\r", '"': '"', "\\": "\\", "{": "{"}
    while i < len(s):
        if s[i] == "\\" and i + 1 < len(s) and s[i + 1] in tbl:
            out.append(tbl[s[i + 1]])
            i += 2
            continue
        out.append(s[i])
        i += 1
    return "".join(out)


def catalog_keys():
    """反解 EN_CATALOG：返回 {带前缀的键} 集合，并顺带查 `[meta]` 是否在最后。"""
    text = (SHOW / "shared" / "i18n_data.mbt").read_text(encoding="utf-8")
    # 注释行里也有引号（`键="desc§"+标题`），不先摘掉会把首条字面量截错
    body = "\n".join(
        ln for ln in text.splitlines() if not ln.strip().startswith("//")
    )
    # 拼出来的 TOML 文本 = 各 `"…"` 字面量段解一层转义后的串联
    parts = re.findall(r'"((?:[^"\\]|\\.)*)"', body)
    toml = "".join(unescape_moon(p) for p in parts)
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


def src(p):
    """读源并把换行折成空格：取译口常跨行写，按单行正则会漏。"""
    return p.read_text(encoding="utf-8").replace("\\\n", "").replace("\n", " ")


def tx_keys():
    """①正文取译口的键集合。"""
    got = set()
    for p in list((SHOW / "pages").glob("*.mbt")) + list((SHOW / "shared").glob("*.mbt")):
        for m in re.finditer(r'@shared\.tx\(\s*"([^"\\]+)"\)|\btx\(\s*"([^"\\]+)"\)', src(p)):
            got.add(m.group(1) or m.group(2))
    return got


def seg_keys():
    """②段名通道（无汉字的段名如 `Markdown` 本来就不需要译，不计）。"""
    got = set()
    for p in (SHOW / "pages").glob("*.mbt"):
        for m in re.finditer(r'@shared\.section\(\s*"((?:[^"\\]|\\.)*)"', src(p)):
            if re.search(r"[一-鿿]", m.group(1)):
                got.add("seg." + m.group(1))
    return got


def nav_keys():
    """③侧栏页名通道：路由表里 `route_of_page(box, "页名", …)` 的第二个实参。"""
    main = src(SHOW / "main.mbt")
    return {
        "nav." + m.group(1) for m in re.finditer(r'route_of_page\(box,\s*"([^"]+)"', main)
    }


def dyn_keys():
    """④状态/回显类插值串：`@shared.tr_with("dyn.x", …)` 的键。"""
    got = set()
    for p in (SHOW / "pages").glob("*.mbt"):
        got |= set(re.findall(r'tr_with\(\s*"([^"]+)"', src(p)))
    return got


def tr_keys():
    """⑤显式键取译：`@shared.tr("x.y", 中文回落)`——带换行等不便当键的串走这条。"""
    got = set()
    for p in list(SHOW.glob("pages/*.mbt")) + list(SHOW.glob("shared/*.mbt")):
        got |= set(re.findall(r'@shared\.tr\(\s*"([^"]+)"', src(p)))
    return got


CJK = re.compile(r"[一-鿿]")


def section_keys():
    """⑥段标题与段描述：`section(name, title, desc)` 出口取译，键 = title /
    `desc§` + title。只查三段都是单条字面量的段（拼接的 desc 交给人工）。"""
    titles, descs = set(), set()
    for p in (SHOW / "pages").glob("*.mbt"):
        for m in re.finditer(
            r'@shared\.section\(\s*"(?:[^"\\]|\\.)*",\s*"((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)"\s*[,)]',
            src(p),
        ):
            title, desc = m.group(1), m.group(2)
            if CJK.search(title):
                titles.add(title)
            if CJK.search(desc):
                descs.add("desc§" + title)
    return titles, descs


def lib_keys():
    """⑦库内建 chrome：gui/ 里 `t_or("gui.x", 中文)` 用到的键。

    动态拼前缀的（`"gui.ui.datepicker.wd."` + 号）按展开后的 7 条星期名查。
    """
    got = set()
    for p in (ROOT / "gui").rglob("*.mbt"):
        if p.name.endswith("_wbtest.mbt"):
            continue
        for k in re.findall(r'"(gui\.[a-z_.0-9]+)"', src(p)):
            got.add(k)
    if any(k.endswith(".wd.") for k in got):
        got = {k for k in got if not k.endswith(".wd.")}
        got |= {"gui.ui.datepicker.wd." + str(i) for i in range(7)}
    return got


def main():
    keys, _ = catalog_keys()
    bad = []
    sec_titles, sec_descs = section_keys()
    for label, want in (
        ("正文 tx", tx_keys()),
        ("段名 seg", seg_keys()),
        ("侧栏 nav", nav_keys()),
        ("插值 dyn", dyn_keys() | tr_keys()),
        ("段标题 title", sec_titles),
        ("段描述 desc§", sec_descs),
        ("库 chrome", lib_keys()),
    ):
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
