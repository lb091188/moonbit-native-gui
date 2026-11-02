// 极简 SVG 文本抽取：零外部 XML 依赖，只够从 iconfont 精灵图里取出 viewBox
// 与每个 `<symbol id="…"><path d="…"/>` 或顶层 `<path id/d>`。
// v1 限制：一个 symbol 仅取首条 path 名（多色多 path 会共用名，交给上层去重）。

///|
pub(all) struct SvgDoc {
  viewbox : (Double, Double, Double, Double)
  paths : Array[(String, String)]
}

///|
fn ascii_from(cs : Array[Int], a : Int, b : Int) -> String {
  let mut s = ""
  let mut i = a
  while i < b {
    s = s + cs[i].unsafe_to_char().to_string()
    i += 1
  }
  s
}

///|
fn match_at(cs : Array[Int], i : Int, pat : String) -> Bool {
  let p = codes(pat)
  let m = p.length()
  if i + m > cs.length() {
    return false
  }
  for k in 0..<m {
    if cs[i + k] != p[k] {
      return false
    }
  }
  true
}

///|
fn is_ws(c : Int) -> Bool {
  c == 32 || c == 44 || c == 9 || c == 10 || c == 13
}

///|
fn is_word(c : Int) -> Bool {
  (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 45 || c == 95
}

///|
// 从 <a..b) 标签体里取属性 key 的值；无则空串。
fn extract_attr(cs : Array[Int], a : Int, b : Int, key : String) -> String {
  let k = codes(key)
  let kl = k.length()
  let mut p = a
  while p + kl < b {
    let hit = match_at(cs, p, key) && (p == a || !is_word(cs[p - 1]))
    if hit {
      let mut q = p + kl
      while q < b && is_ws(cs[q]) {
        q += 1
      }
      if q < b && cs[q] == 61 {
        q += 1
        while q < b && is_ws(cs[q]) {
          q += 1
        }
        if q < b && cs[q] == 34 {
          let start = q + 1
          let mut e = start
          while e < b && cs[e] != 34 {
            e += 1
          }
          return ascii_from(cs, start, e)
        }
      }
    }
    p += 1
  }
  ""
}

///|
fn find_gt(cs : Array[Int], i : Int) -> Int {
  let n = cs.length()
  let mut j = i
  while j < n && cs[j] != 62 {
    j += 1
  }
  j
}

///|
fn viewbox_of(cs : Array[Int]) -> (Double, Double, Double, Double)? {
  let n = cs.length()
  let mut i = 0
  while i < n {
    if match_at(cs, i, "viewBox") {
      let mut q = i + 7
      while q < n && cs[q] != 34 {
        q += 1
      }
      if q < n && cs[q] == 34 {
        let s = q + 1
        let (x0, s2) = readnum(cs, s)
        let (y0, s3) = readnum(cs, s2)
        let (w0, s4) = readnum(cs, s3)
        let (h0, _) = readnum(cs, s4)
        return Some((x0, y0, w0, h0))
      }
      i += 7
    } else {
      i += 1
    }
  }
  None
}

///|
/// 解析 SVG 文本，抽取 viewBox 与 path 列表。
pub fn parse_svg(text : String) -> SvgDoc {
  let cs = codes(text)
  let vb = match viewbox_of(cs) {
    Some(v) => v
    None => (0.0, 0.0, 1024.0, 1024.0)
  }
  let paths : Array[(String, String)] = []
  let mut cur_id = ""
  let mut auto = 0
  let n = cs.length()
  let mut i = 0
  while i < n {
    if cs[i] == 60 {
      if match_at(cs, i, "<symbol") {
        let te = find_gt(cs, i)
        cur_id = extract_attr(cs, i, te, "id")
      } else if match_at(cs, i, "</symbol") {
        cur_id = ""
      } else if match_at(cs, i, "<path") {
        let te = find_gt(cs, i)
        let d = extract_attr(cs, i, te, "d")
        if d.length() > 0 {
          let name =
            if cur_id.length() > 0 {
              cur_id
            } else {
              let nm = "icon_" + auto.to_string()
              auto += 1
              nm
            }
          paths.push((name, d))
        }
      }
    }
    i += 1
  }
  { viewbox: vb, paths }
}
