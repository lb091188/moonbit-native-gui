#!/usr/bin/env python3
"""内置矢量图标「裁减」生成器：从 gui/icons/icons.mbt 里按 keep 名单，
产出一个自包含（含绘图引擎）的子集 icons 模块，供单个 app 只带用到的图标。

用法:
  python3 scripts/subset_icons.py --keep <list> [--out <file>] [--in <icons.mbt>]
  <list>: 逗号或换行分隔的 IconKind 变体名或 font_class 名（两种都认）。
  默认 --in gui/icons/icons.mbt；默认 --out stdout。

不改动库全量 icons.mbt（那会打断 showcase 等既有引用）；app 把产出的子集
模块 vendor 进自己的包即可，二进制只含选中的图标。
"""

import argparse
import re
import sys
import os

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_ICONS = os.path.join(REPO, "gui/icons/icons.mbt")

# —— 绘图引擎模板（与 gui/icons/icons.mbt 的 path_num/fill_icon_path 逐字同口径）——
ENGINE = '''// 自动生成：内置图标子集（含绘图引擎）。用 scripts/subset_icons.py 产出，勿手改。

///|
fn path_num(d : String, i : Int) -> (Double, Int) {
  let n = d.length()
  let mut j = i
  let mut neg = false
  while j < n {
    let c = d.unsafe_get(j).to_int()
    if c == 44 {
      j += 1 // ','
    } else if c == 45 {
      neg = true // '-'
      j += 1
      break
    } else {
      break
    }
  }
  let mut v = 0.0
  while j < n {
    let c = d.unsafe_get(j).to_int()
    if c >= 48 && c <= 57 {
      v = v * 10.0 + Double::from_int(c - 48)
      j += 1
    } else {
      break
    }
  }
  (if neg { -v } else { v }, j)
}

///|
fn fill_icon_path(
  p : @render.Painter,
  d : String,
  cx : Double,
  cy : Double,
  s : Double,
) -> Unit {
  let u = s * 0.88 / 1000.0
  let n = d.length()
  let mut i = 0
  p.begin_path()
  while i < n {
    let c = d.unsafe_get(i).to_int()
    i += 1
    if c == 90 {
      p.close_path()
    } else if c == 77 {
      let (x, i2) = path_num(d, i)
      i = i2
      let (y, i3) = path_num(d, i)
      i = i3
      p.move_to(cx + x * u, cy + y * u)
    } else if c == 76 {
      let (x, i2) = path_num(d, i)
      i = i2
      let (y, i3) = path_num(d, i)
      i = i3
      p.line_to(cx + x * u, cy + y * u)
    } else if c == 67 {
      let (x1, i2) = path_num(d, i)
      i = i2
      let (y1, i3) = path_num(d, i)
      i = i3
      let (x2, i4) = path_num(d, i)
      i = i4
      let (y2, i5) = path_num(d, i)
      i = i5
      let (px, i6) = path_num(d, i)
      i = i6
      let (py, i7) = path_num(d, i)
      i = i7
      p.bezier_curve_to(
        cx + x1 * u,
        cy + y1 * u,
        cx + x2 * u,
        cy + y2 * u,
        cx + px * u,
        cy + py * u,
      )
    } else {
      ()
    }
  }
  p.fill()
}
'''

DRAW = '''///|
/// 统一图标绘制入口（子集）：中心 (cx,cy)，s 为内容半径，color 十六进制。
pub fn draw_icon(
  p : @render.Painter,
  kind : IconKind,
  cx : Double,
  cy : Double,
  s : Double,
  color : String,
) -> Unit {
  p.set_stroke_color(color)
  p.set_fill_color(color)
  fill_icon_path(p, icon_path_data[kind_index(kind)], cx, cy, s)
}
'''


def extract(src):
    """返回 variant→(path, fc)，保留源顺序：[variant,...] + dict。"""
    # icon_path_data 数组里的字符串（按出现顺序）
    dm = re.search(
        r"let icon_path_data : Array\[String\] = \[(.*?)\n\]", src, re.S)
    if not dm:
        raise SystemExit("icon_path_data block not found")
    paths = re.findall(r'"([^"]*)"', dm.group(1))

    # kind_index: Variant => N
    im = re.search(r"fn kind_index\(kind : IconKind\) -> Int \{(.*?)\n\}", src, re.S)
    if not im:
        raise SystemExit("kind_index block not found")
    pairs = re.findall(r"\n\s*(\w+) => (\d+)", im.group(1))
    variant_order = [v for v, _ in pairs]
    variant_idx = {v: int(i) for v, i in pairs}

    # icon_name: Variant => "fc"
    nm = re.search(r"pub fn icon_name\(kind : IconKind\) -> String \{.*?\n\s*match kind \{(.*?)\n  \}", src, re.S)
    fc_map = {}
    if nm:
        for v, fc in re.findall(r"\n\s*(\w+) => \"([^\"]+)\"", nm.group(1)):
            fc_map[v] = fc

    out = []
    for v in variant_order:
        idx = variant_idx[v]
        if idx >= len(paths):
            raise SystemExit("index out of range for " + v)
        out.append((v, paths[idx], fc_map.get(v, v)))
    return out


def load_keep(arg):
    """从文件路径或逗号串取名单。"""
    raw = ""
    if os.path.exists(arg):
        raw = open(arg).read()
    else:
        raw = arg
    names = set()
    for line in re.split(r"[,\n\r]+", raw):
        line = line.strip()
        if line and not line.startswith("#"):
            names.add(line)
    return names


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--keep", required=True)
    ap.add_argument("--out", default="")
    ap.add_argument("--in", dest="src", default=DEFAULT_ICONS)
    a = ap.parse_args()

    all_items = extract(open(a.src).read())
    keep = load_keep(a.keep)
    # keep 认变体名或 font_class 名
    sel = [(v, p, fc) for (v, p, fc) in all_items if v in keep or fc in keep]
    if not sel:
        raise SystemExit("keep 名单没有命中任何图标")
    unknown = keep - set(v for _, _, v in [])  # 仅提示
    # 断言：选中路径与源逐字一致（extract 已保证，这里双保险再比一次）
    src_by_variant = {v: p for v, p, _ in all_items}
    for v, p, _ in sel:
        assert p == src_by_variant[v], "path drift for " + v

    enum_body = "\n".join("  {} // {}".format(v, fc) for v, _, fc in sel)
    data_body = "\n".join('  "{}",'.format(p) for _, p, _ in sel)
    idx_body = "\n".join("    {} => {}".format(v, i) for i, (v, _, _) in enumerate(sel))
    name_body = "\n".join('    {} => "{}"'.format(v, fc) for v, _, fc in sel)
    all_body = "\n".join("    {},".format(v) for v, _, _ in sel)

    module = (
        ENGINE + "\n"
        + "///|\npub(all) enum IconKind {\n" + enum_body + "\n} derive(Eq, Debug)\n\n"
        + "pub extend IconKind with Eq::{equal, not_equal}\n"
        + "pub extend IconKind with Debug::{to_repr}\n\n"
        + "///| 子集图标路径数据（千分定点串），与 kind_index/all_icons 同序。\n"
        + "let icon_path_data : Array[String] = [\n" + data_body + "\n]\n\n"
        + "///| 变体 → 子集下标。\n"
        + "fn kind_index(kind : IconKind) -> Int {\n  match kind {\n"
        + idx_body + "\n  }\n}\n\n"
        + "///| 子集图标清单。\n"
        + "pub fn all_icons() -> Array[IconKind] {\n  [\n" + all_body + "\n  ]\n}\n\n"
        + "///| 变体 → font_class 名。\n"
        + "pub fn icon_name(kind : IconKind) -> String {\n  match kind {\n"
        + name_body + "\n  }\n}\n\n"
        + DRAW
    )

    if a.out:
        open(a.out, "w").write(module)
        print("生成子集图标 {} 个 → {}".format(len(sel), a.out))
    else:
        sys.stdout.write(module)


if __name__ == "__main__":
    main()
