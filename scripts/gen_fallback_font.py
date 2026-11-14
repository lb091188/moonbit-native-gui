#!/usr/bin/env python3
"""生成内嵌回退字体子集（gui/text/assets/fallback-cjk.ttf）。

无字体环境（最小安装 Linux、容器）里 Pango 匹配不到任何族：量宽为 0、
画豆腐块。text/stub.c 的 pt_ensure_fallback_font 在探到系统零字体时把
本子集注册进 fontconfig 的应用字体表——ASCII + GB2312 一级常用汉字 +
常用中英标点，真量真画；子集外字符（生僻字/emoji）仍走各后端自带回退。

再生成方式：
    python3 scripts/gen_fallback_font.py <源字体> [输出路径]
源字体用 Noto Sans SC（SIL OFL 1.1 授权，授权文件随子集同目录提交），
如 noto-cjk 仓库的 Sans/SubsetOTF/SC/NotoSansSC-Regular.otf。
依赖 fonttools；brew 装的 fonttools 是隔离环境（import 不到），要带
PYTHONPATH，如：
    PYTHONPATH=$(find /opt/homebrew/Cellar/fonttools -type d -name site-packages | head -1) \
        python3 scripts/gen_fallback_font.py <源字体>
"""

import sys
from pathlib import Path

from fontTools import subset


def charset() -> str:
    """目标字符集：ASCII + GB2312 一级汉字 + 常用标点。"""
    chars = [chr(c) for c in range(0x20, 0x7F)]  # ASCII 可见字符
    # GB2312 一级汉字：16-55 区（区位码 B0A1..D7F9），3755 个
    for hi in range(0xB0, 0xD8):
        for lo in range(0xA1, 0xFF):
            try:
                chars.append(bytes([hi, lo]).decode("gb2312"))
            except UnicodeDecodeError:
                pass
    # CJK 标点（全角空格、顿号、书名号等）与通用标点（引号、破折、省略）
    chars += [chr(c) for c in range(0x3000, 0x3020)]
    for cp in (0x2013, 0x2014, 0x2018, 0x2019, 0x201C, 0x201D, 0x2026):
        chars.append(chr(cp))
    return "".join(chars)


def main() -> None:
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    src = Path(sys.argv[1])
    out = Path(sys.argv[2]) if len(sys.argv) > 2 else Path(
        __file__).resolve().parent.parent / "gui/text/assets/fallback-cjk.ttf"
    opts = subset.Options()
    opts.name_IDs = ["*"]  # 保留命名表（fontconfig 按族名匹配）
    opts.notdef_outline = True  # 缺字形兜 .notdef，别让子集外字符悬空
    opts.recalc_bounds = True
    font = subset.load_font(str(src), opts)
    subsetter = subset.Subsetter(options=opts)
    subsetter.populate(text=charset())
    subsetter.subset(font)
    out.parent.mkdir(parents=True, exist_ok=True)
    subset.save_font(font, str(out), opts)
    print(f"子集已生成: {out} ({out.stat().st_size} 字节)")


if __name__ == "__main__":
    main()
