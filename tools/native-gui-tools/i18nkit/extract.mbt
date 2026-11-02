// i18n 源码抽键 + 目录差集报告（纯文本入、纯数组出，不碰文件系统）。

///|
fn is_wordc(c : Char) -> Bool {
  let u = c.to_int()
  (u >= 48 && u <= 57) || (u >= 65 && u <= 90) || (u >= 97 && u <= 122) || u == 95
}

///|
fn starts_with_at(a : Array[Char], i : Int, pat : String) -> Bool {
  let p = chars(pat)
  let m = p.length()
  if i + m > a.length() {
    return false
  }
  for k in 0..<m {
    if a[i + k] != p[k] {
      return false
    }
  }
  true
}

///|
fn unique(arr : Array[String]) -> Array[String] {
  let out : Array[String] = []
  for x in arr {
    if !has(out, x) {
      out.push(x)
    }
  }
  out
}

///|
fn has(arr : Array[String], x : String) -> Bool {
  for e in arr {
    if e == x {
      return true
    }
  }
  false
}

///|
/// 扫源码文本，抓 t("…") / t_with("…") / t_count("…") 里的键。
pub fn scan_keys(src : String) -> Array[String] {
  let a = chars(src)
  let n = a.length()
  let hits : Array[String] = []
  let prefixes = ["t(", "t_with(", "t_count("]
  let mut i = 0
  while i < n {
    if a[i] == '"' {
      let mut ok = false
      for pf in prefixes {
        let l = chars(pf).length()
        let pi = i - l
        if pi >= 0 && starts_with_at(a, pi, pf) &&
           (pi == 0 || !is_wordc(a[pi - 1])) {
          ok = true
        }
      }
      if ok {
        let mut e = i + 1
        while e < n && a[e] != '"' {
          e += 1
        }
        hits.push(join(a, i + 1, e))
        i = e
      }
    }
    i += 1
  }
  unique(hits)
}

///|
/// 目录里定义的键（排除 meta.*）。
pub fn defined_keys(cat : Catalog) -> Array[String] {
  let out : Array[String] = []
  for (k, _) in cat.texts {
    if !starts_with_at(chars(k), 0, "meta.") {
      out.push(k)
    }
  }
  for (k, _) in cat.plurals {
    if !starts_with_at(chars(k), 0, "meta.") {
      out.push(k)
    }
  }
  out
}

///|
// 在 arr 里、不在 base 里的元素。
fn subtract(arr : Array[String], base : Array[String]) -> Array[String] {
  let out : Array[String] = []
  for x in arr {
    if !has(base, x) {
      out.push(x)
    }
  }
  out
}

///|
/// 缺失 = 源码用了但目录没定义；残项 = 目录定义了但源码没用。
pub fn diff(
  used : Array[String],
  defined : Array[String],
) -> (Array[String], Array[String]) {
  (subtract(used, defined), subtract(defined, used))
}
