// 归一化后的 M/L/C/Z 段 → 千分定点整数 → 目标格式串 + [icons] TOML。
// 口径锁定：坐标以 viewBox 中心为原点、长边半幅铺满 ±1000；逐坐标四舍五入为整数；
// 序列化为「命令字母 + 逗号分隔整数」，无空格——与 gui/icons 的 fill_icon_path/path_num 同口径。

///|
fn round_i(v : Double) -> Int {
  if v >= 0.0 { (v + 0.5).to_int() } else { (v - 0.5).to_int() }
}

///|
/// viewBox 中心→原点、缩放长边到 ±1000、逐坐标取整。
pub fn transform(
  segs : Array[Seg],
  minx : Double,
  miny : Double,
  w : Double,
  h : Double,
) -> Array[Seg] {
  let side = if w > h { w } else { h }
  let scale = if side == 0.0 { 1.0 } else { 2000.0 / side }
  let ox = minx + w / 2.0
  let oy = miny + h / 2.0
  let out : Array[Seg] = []
  for s in segs {
    let a = s.args
    let m = a.length()
    let mapped : Array[Double] = []
    let mut k = 0
    while k < m {
      mapped.push(Double::from_int(round_i((a[k] - ox) * scale)))
      mapped.push(Double::from_int(round_i((a[k + 1] - oy) * scale)))
      k += 2
    }
    out.push({ cmd: s.cmd, args: mapped })
  }
  out
}

///|
/// 序列化：`M-200,-733L...C...Z`，整数、逗号、无空格。
pub fn serialize(segs : Array[Seg]) -> String {
  let mut acc = ""
  for s in segs {
    acc = acc + s.cmd.to_string()
    let a = s.args
    let m = a.length()
    let mut k = 0
    while k < m {
      if k > 0 {
        acc = acc + ","
      }
      acc = acc + a[k].to_int().to_string()
      k += 1
    }
  }
  acc
}

///|
/// 端到端：单个 path d + viewBox → 目标格式串（附解析告警）。
pub fn convert_path(
  d : String,
  minx : Double,
  miny : Double,
  w : Double,
  h : Double,
) -> (String, Array[String]) {
  let (segs, warns) = parse_path(d)
  let t = transform(segs, minx, miny, w, h)
  (serialize(t), warns)
}

///|
// TOML 值转义（路径串只含数字/字母/逗号/减号；名只可能是字母数字-/ _）。
fn esc(s : String) -> String {
  let mut out = ""
  for c in s {
    if c == '"' {
      out = out + "\\\""
    } else if c == '\\' {
      out = out + "\\\\"
    } else {
      out = out + c.to_string()
    }
  }
  out
}

///|
/// 产出 `[icons]` 段 TOML（key = "path"），键按传入顺序写。
pub fn to_toml(entries : Array[(String, String)]) -> String {
  let mut out = "# iconfont 图标数据（自动生成，勿手改）\n[icons]\n"
  for e in entries {
    out = out + "\"" + esc(e.0) + "\" = \"" + esc(e.1) + "\"\n"
  }
  out
}

///|
fn in_list(arr : Array[String], x : String) -> Bool {
  for e in arr {
    if e == x {
      return true
    }
  }
  false
}

///|
// 逗号分隔名单 → 数组；忽略空格与空项。
fn split_csv(s : String) -> Array[String] {
  let out : Array[String] = []
  let mut cur = ""
  for c in s {
    if c == ',' {
      if cur.length() > 0 {
        out.push(cur)
      }
      cur = ""
    } else if c == ' ' {
      ()
    } else {
      cur = cur + c.to_string()
    }
  }
  if cur.length() > 0 {
    out.push(cur)
  }
  out
}

///|
/// SVG 文本 → 图标条目 (name, path)，keep=Some(逗号分隔名) 时只保留命中的。
pub fn svg_to_entries(
  text : String,
  keep : String?,
) -> (Array[(String, String)], Array[String]) {
  let doc = parse_svg(text)
  let (minx, miny, w, h) = doc.viewbox
  let has_keep = match keep {
    Some(_) => true
    None => false
  }
  let keep_list = match keep {
    Some(k) => split_csv(k)
    None => []
  }
  let entries : Array[(String, String)] = []
  let warns : Array[String] = []
  for (name, d) in doc.paths {
    let want = if has_keep { in_list(keep_list, name) } else { true }
    if want {
      let (s, ws) = convert_path(d, minx, miny, w, h)
      entries.push((name, s))
      for x in ws {
        warns.push(name + ": " + x)
      }
    }
  }
  (entries, warns)
}

///|
/// 整个 SVG 文本 → [icons] TOML 串；返回（toml, 合并告警）。
pub fn convert_svg(text : String) -> (String, Array[String]) {
  let (entries, warns) = svg_to_entries(text, None)
  (to_toml(entries), warns)
}
