// iconfont 转化 CLI 入口。用法见 print_usage。

fn print_usage() -> Unit {
  println("用法：moon run tools/icon_convert -- <input.svg> [output.toml] [--subset 名1,名2] [--keep-file list.txt]")
  println("  不给 output.toml 时把 TOML 打到 stdout（可用 > out.toml 重定向）。")
  println("  --subset 逗号分隔名 / --keep-file 名单文件（换行或逗号分隔），只保留命中的（对接构建期裁剪）。")
}

fn slurp(p : String) -> String? {
  let s = @fs.read_file_to_string(p) catch { _ => return None }
  Some(s)
}

fn spit(p : String, s : String) -> Bool {
  @fs.write_string_to_file(p, s) catch { _ => return false }
  true
}

fn main {
  // native 下 @env.args() 含 argv[0]（可执行名），丢弃只留用户参数
  let raw = @env.args()
  let args : Array[String] = []
  let mut k = 1
  while k < raw.length() {
    args.push(raw[k])
    k += 1
  }
  let files : Array[String] = []
  let mut keep : String? = None
  let mut i = 0
  while i < args.length() {
    let a = args[i]
    if a == "--subset" {
      if i + 1 < args.length() {
        keep = Some(args[i + 1])
        i += 2
      } else {
        print_usage()
        @sys.exit(2)
      }
    } else if a == "--keep-file" {
      if i + 1 < args.length() {
        match slurp(args[i + 1]) {
          Some(text) => keep = Some(text)
          None => keep = Some("")
        }
        i += 2
      } else {
        print_usage()
        @sys.exit(2)
      }
    } else if a == "-h" || a == "--help" {
      print_usage()
      @sys.exit(0)
    } else if a == "--" {
      i += 1
    } else {
      files.push(a)
      i += 1
    }
  }

  if files.length() == 0 {
    print_usage()
    @sys.exit(2)
  }
  let in_path = files[0]
  let text = match slurp(in_path) {
    Some(t) => t
    None => {
      println("读取失败：\{in_path}")
      @sys.exit(3)
      ""
    }
  }

  let (entries, warns) = @iconkit.svg_to_entries(text, keep)
  let toml = @iconkit.to_toml(entries)

  if files.length() >= 2 {
    let out_path = files[1]
    if !spit(out_path, toml) {
      println("写入失败：\{out_path}")
      @sys.exit(3)
    }
    println("转化完成：\{entries.length()} 个图标 → \{out_path}")
  } else {
    println(toml)
  }
  for w in warns {
    println("警告：\{w}")
  }
}
