// icons 子命令：应用图标派生。源 PNG → icns（mac，sips 十档 + iconutil）、
// ico（全平台，纯 MoonBit 合成）与 iconset 十档 PNG。派生逻辑与 package 同源
// （scaffold 的 icon_step 只落源 PNG + mng.toml 声明，各档派生归这里与 package）。

///|
/// icons 子命令：`mng icons <source.png> [-o <outdir>]`。
/// 缺省输出到源文件同目录；icns 仅 macOS（sips/iconutil），ico 全平台。
fn cmd_icons(args : Array[String]) -> Int32 {
  let mut src = ""
  let mut outdir = ""
  let mut k = 0
  while k < args.length() {
    let a = args[k]
    if (a == "-o" || a == "--out") && k + 1 < args.length() {
      outdir = args[k + 1]
      k += 2
    } else if a.has_prefix("-") {
      eprintln(tmsg("未知参数：" + a, "Unknown argument: " + a))
      usage_icons()
      return 2
    } else {
      src = a
      k += 1
    }
  }
  if src.length() == 0 {
    usage_icons()
    return 2
  }
  if !(@fs.is_file(src) catch { _ => false }) {
    println(tmsg("读不到源图：" + src, "cannot read source image: " + src))
    return 1
  }
  let abssrc = abs_path(src)
  let dir = if outdir.length() > 0 {
    if !mkdir_p(outdir) {
      println(tmsg("建不了输出目录：" + outdir, "cannot create output dir: " + outdir))
      return 1
    }
    abs_path(outdir)
  } else {
    dir_of_path(abssrc)
  }
  let stem = stem_of(abssrc)
  let mut ok = true
  // ico：纯 MoonBit 字节合成，全平台可出
  let png : Bytes = @fs.read_file_to_bytes(src) catch {
    _ => {
      println(tmsg("读不到源图：" + src, "cannot read source image: " + src))
      return 1
    }
  }
  match ico_of_png(png) {
    Some(ico) => {
      let out = dir + "/" + stem + ".ico"
      if spit_bytes(out, ico) {
        println("OK " + out)
      } else {
        println(tmsg("写不出：" + out, "cannot write: " + out))
        ok = false
      }
    }
    None => {
      println(
        tmsg(
          "ico 合成失败：源不是有效 PNG（" + src + "）",
          "ico synthesis failed: not a valid PNG (" + src + ")",
        ),
      )
      ok = false
    }
  }
  // icns：sips 十档 + iconutil，macOS 专属工具链
  let host = host_os()
  if host == "macos" {
    let iconset = dir + "/" + stem + ".iconset"
    if !mkdir_p(iconset) {
      println(tmsg("建不了 iconset 目录", "cannot create iconset dir"))
      return 1
    }
    let mut derived = true
    for pair in iconset_sizes {
      let (fname, n) = pair
      let dim = n.to_string()
      match
        run_logged(
          "sips -z \{dim} \{dim} " + sq(abssrc) + " --out " + sq(iconset + "/" + fname),
          dir + "/mng-icons.log",
          60000,
        ) {
        Ok(_) => ()
        Err(e) => {
          println(tmsg("icns 派生失败(sips):", "icns derivation failed (sips): ") + e)
          derived = false
          break
        }
      }
    }
    if derived {
      match
        run_logged(
          "iconutil -c icns " + sq(iconset) + " -o " + sq(dir + "/" + stem + ".icns"),
          dir + "/mng-icons.log",
          60000,
        ) {
        Ok(_) => println("OK " + dir + "/" + stem + ".icns")
        Err(e) => {
          println(tmsg("icns 合成失败(iconutil):", "icns build failed (iconutil): ") + e)
          ok = false
        }
      }
    } else {
      ok = false
    }
  } else {
    println(
      tmsg(
        "icns 仅 macOS 可派生（sips/iconutil）；本机（" + host + "）跳过",
        "icns requires macOS (sips/iconutil); skipped on " + host,
      ),
    )
  }
  if ok {
    0
  } else {
    1
  }
}

///|
fn usage_icons() -> Unit {
  println(
    tmsg(
      "用法：\{inv_prefix[0]} icons <source.png> [-o <outdir>]",
      "Usage: \{inv_prefix[0]} icons <source.png> [-o <outdir>]",
    ),
  )
  println(
    tmsg(
      "  从源 PNG 派生应用图标：ico（全平台，纯 MoonBit）+ icns 与 iconset 十档 PNG（仅 macOS）；缺省输出到源图同目录",
      "  Derive app icons from a source PNG: ico (all platforms, pure MoonBit) + icns and the 10-step iconset PNGs (macOS only); defaults to the source directory",
    ),
  )
}

///|
fn host_os() -> String {
  match @env.get_env_var("MNG_HOST_OS") {
    Some(v) if v.length() > 0 => return v
    _ => ()
  }
  // mng 不依赖 GUI 库，无现成宿主读数——windows 判 OS 环境变量、mac 判
  // 系统文件、其余按 linux（ doctor 的平台分支同口径）
  let is_win = match @env.get_env_var("OS") {
    Some(v) => v == "Windows_NT"
    None => false
  }
  if is_win {
    return "windows"
  }
  let is_mac = @fs.is_file("/System/Library/CoreServices/SystemVersion.plist") catch {
    _ => false
  }
  if is_mac {
    "macos"
  } else {
    "linux"
  }
}

///|
fn abs_path(p : String) -> String {
  if p.has_prefix("/") {
    return p
  }
  match @env.current_dir() {
    Some(d) => d + "/" + p
    None => p
  }
}

///|
fn dir_of_path(p : String) -> String {
  let mut last = -1
  let n = p.length()
  let mut i = 0
  while i < n {
    if p[i] == '/' {
      last = i
    }
    i += 1
  }
  if last <= 0 {
    p
  } else {
    p[0:last].to_owned()
  }
}

///|
fn stem_of(p : String) -> String {
  // 先取 basename（路径目录里可能有点号），再去最后一个扩展名
  let mut start = 0
  let n = p.length()
  let mut i = 0
  while i < n {
    if p[i] == '/' {
      start = i + 1
    }
    i += 1
  }
  let mut end = n
  let mut j = n
  while j > start {
    if p[j - 1] == '.' {
      end = j - 1
      break
    }
    j -= 1
  }
  if end <= start {
    p[start:].to_owned()
  } else {
    p[start:end].to_owned()
  }
}

///|
fn spit_bytes(p : String, b : Bytes) -> Bool {
  @fs.write_bytes_to_file(p, b) catch {
    _ => return false
  }
  true
}
