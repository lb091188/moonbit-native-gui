// 探针输出的纯解析函数（wbtest 钉口径）。

///|
/// 首行（去行尾 \r）。
pub fn first_line(s : String) -> String {
  let mut end = s.length()
  for i, c in s {
    if c == '\n' {
      end = i
      break
    }
  }
  let line = s[0:end].to_owned()
  let mut stop = line.length()
  while stop > 0 && line[stop - 1] == '\r' {
    stop -= 1
  }
  line[0:stop].to_owned()
}

///|
/// 解析 `Python 3.15.0` 首行的主次版本；主次任一缺失或格式认不出返回 None。
pub fn parse_python_version(line~ : String) -> (Int32, Int32)? {
  let prefix = "Python "
  if !line.has_prefix(prefix) {
    return None
  }
  let rest = line[prefix.length():]
  let mut major : Int32? = None
  let mut minor : Int32? = None
  let mut seg = 0
  let cur : Ref[Int32] = { val: 0, }
  let mut seen_digit = false
  for c in rest {
    if c == '.' {
      if seg == 0 {
        major = Some(cur.val)
      } else if seg == 1 {
        minor = Some(cur.val)
      } else {
        break
      }
      if !seen_digit {
        return None
      }
      seg += 1
      cur.val = 0
      seen_digit = false
    } else if c is ('0'..<='9') {
      cur.val = cur.val * 10 + (c.to_int() - 48)
      seen_digit = true
    } else {
      break
    }
  }
  if seg == 1 && seen_digit {
    minor = Some(cur.val)
  } else if seg == 0 && seen_digit {
    major = Some(cur.val)
  }
  match (major, minor) {
    (Some(ma), Some(mi)) => Some((ma, mi))
    _ => None
  }
}

///|
/// Python 版本是否满足 prebuild 的 ≥3.7 口径。
pub fn python_ok(major~ : Int32, minor~ : Int32) -> Bool {
  major > 3 || (major == 3 && minor >= 7)
}
