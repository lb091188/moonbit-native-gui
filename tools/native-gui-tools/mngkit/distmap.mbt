// 模板 source map（v1）的**正向索引**：模板源位置 → 生成码位置。
//
// 生成器写出的是「生成行 → 源坐标」的反向表（gen.mbt 的 g_emit），真实类型
// hover 需要的却是反向查询——编辑器里光标在 .mng 上，`moon ide hover` 要的是
// `.gen.mbt` 的位置。本文件只做纯文本解析与换算，不碰文件系统（便于用例钉）。
//
// 表格式（mng source map v1）：
//   # mng source map v1
//   source <文件名>
//   <gen_line>\t<src_line>\t<src_col>      （均为 1 基）

///|
fn dm_atoi(s : String) -> Int32? {
  let cs = s.to_array()
  if cs.length() == 0 {
    return None
  }
  let mut v = 0
  for c in cs {
    let d = c.to_int()
    if d < 48 || d > 57 {
      return None
    }
    v = v * 10 + (d - 48)
  }
  Some(v)
}

///|
/// 解析一行 `gen\tsrc_line\tsrc_col`；表头/空行/坏行给 None。
fn dm_entry(line : String) -> (Int32, Int32, Int32)? {
  let trimmed = line.trim(chars=" \t\r").to_owned()
  if trimmed.length() == 0 ||
    trimmed.has_prefix("#") ||
    trimmed.has_prefix("source") {
    return None
  }
  let parts = trimmed.split("\t").to_array()
  if parts.length() < 3 {
    return None
  }
  let g = dm_atoi(parts[0].to_owned())
  let sl = dm_atoi(parts[1].to_owned())
  let sc = dm_atoi(parts[2].to_owned())
  match (g, sl, sc) {
    (Some(g1), Some(l1), Some(c1)) => Some((g1, l1, c1))
    _ => None
  }
}

///|
/// 源位置 → 生成码位置（1 基行列）。取「源坐标 ≤ 目标」里最靠后的那条记录；
/// 生成列按「同一条记录起点的列差」估：生成码里该语句的起始缩进与源不同，
/// 精确列做不到（map 只记语句起点），读出 hover 通常只要行对、列落在语句内即可。
pub fn src_to_gen(
  map_text : String,
  src_line : Int32,
  src_col : Int32,
) -> (Int32, Int32)? {
  let mut best : (Int32, Int32, Int32)? = None
  for line in map_text.split("\n") {
    match dm_entry(line.to_owned()) {
      Some((gl, sl, sc)) => {
        let before = sl < src_line || (sl == src_line && sc <= src_col)
        if before {
          match best {
            Some((_, bl, bc)) =>
              if sl > bl || (sl == bl && sc > bc) {
                best = Some((gl, sl, sc))
              }
            None => best = Some((gl, sl, sc))
          }
        }
      }
      None => ()
    }
  }
  match best {
    Some((gl, _sl, sc)) => Some((gl, (src_col - sc).max(0) + 1))
    None => None
  }
}

///|
/// 生成码行 → 源位置（诊断回投用；取该生成行上最后一条记录）。
pub fn gen_to_src(map_text : String, gen_line : Int32) -> (Int32, Int32)? {
  let mut best : (Int32, Int32)? = None
  for line in map_text.split("\n") {
    match dm_entry(line.to_owned()) {
      Some((gl, sl, sc)) => if gl == gen_line { best = Some((sl, sc)) }
      None => ()
    }
  }
  best
}
