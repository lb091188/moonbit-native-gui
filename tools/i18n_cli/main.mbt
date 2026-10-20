// i18n 预处理 CLI。子命令：extract <src_dir>；check <locales_dir> <locale> <src_dir>。

fn usage() -> Unit {
  println("用法：moon run tools/i18n_cli -- <子命令> ...")
  println("  extract <src_dir>                       打印源码用到的所有 t() 键（每行一个）")
  println("  check <locales_dir> <locale> <src_dir>  比对源码用量与目录定义，报缺失/残项")
  println("  缺失非空时退出码为 1（供 CI 门禁）。")
}

fn chars_of(s : String) -> Array[Char] {
  let a : Array[Char] = []
  for c in s {
    a.push(c)
  }
  a
}

fn ends_with(s : String, suf : String) -> Bool {
  let a = chars_of(s)
  let b = chars_of(suf)
  let n = a.length()
  let m = b.length()
  if m > n {
    false
  } else {
    let mut ok = true
    for k in 0..<m {
      if a[n - m + k] != b[k] {
        ok = false
      }
    }
    ok
  }
}

fn slurp(p : String) -> String? {
  let s = @fs.read_file_to_string(p) catch { _ => return None }
  Some(s)
}

fn walk(dir : String, acc : Array[String]) -> Unit {
  let names = @fs.read_dir(dir) catch { _ => return }
  for name in names {
    let p = dir + "/" + name
    let isdir = @fs.is_dir(p) catch { _ => false }
    if isdir {
      walk(p, acc)
    } else if ends_with(p, ".mbt") {
      acc.push(p)
    }
  }
}

fn collect_used(src_dir : String) -> Array[String] {
  let files : Array[String] = []
  walk(src_dir, files)
  let all : Array[String] = []
  for f in files {
    match slurp(f) {
      Some(text) => {
        for k in @i18nkit.scan_keys(text) {
          all.push(k)
        }
      }
      None => ()
    }
  }
  // 去重（与 i18nkit.unique 同效，本地一份避免依赖私有）
  let out : Array[String] = []
  for x in all {
    let mut seen = false
    for y in out {
      if y == x {
        seen = true
      }
    }
    if !seen {
      out.push(x)
    }
  }
  out
}

fn main {
  let raw = @env.args()
  let args : Array[String] = []
  let mut k = 1
  while k < raw.length() {
    args.push(raw[k])
    k += 1
  }
  if args.length() == 0 {
    usage()
    @sys.exit(2)
  }
  let cmd = args[0]
  if cmd == "-h" || cmd == "--help" {
    usage()
    @sys.exit(0)
  } else if cmd == "extract" {
    if args.length() < 2 {
      usage()
      @sys.exit(2)
    }
    for key in collect_used(args[1]) {
      println(key)
    }
  } else if cmd == "check" {
    if args.length() < 4 {
      usage()
      @sys.exit(2)
    }
    let locales_dir = args[1]
    let locale = args[2]
    let src_dir = args[3]
    let cat_path = locales_dir + "/" + locale + ".toml"
    let cat = match slurp(cat_path) {
      Some(text) => @i18nkit.parse_catalog(text)
      None => {
        println("读取目录失败：\{cat_path}")
        @sys.exit(3)
        @i18nkit.parse_catalog("")
      }
    }
    let used = collect_used(src_dir)
    let defined = @i18nkit.defined_keys(cat)
    let (missing, unused) = @i18nkit.diff(used, defined)
    for m in missing {
      println("MISSING\t\{m}")
    }
    for u in unused {
      println("UNUSED\t\{u}")
    }
    println("SUMMARY\tused=\{used.length()}\tdefined=\{defined.length()}\tmissing=\{missing.length()}\tunused=\{unused.length()}")
    if missing.length() > 0 {
      @sys.exit(1)
    }
  } else {
    usage()
    @sys.exit(2)
  }
}
