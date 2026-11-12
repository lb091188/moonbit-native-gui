// ffmpeg-dll 子命令（仅 Windows）：把 ffmpeg 运行期 dll 搬到媒体示例 exe 旁
// 做 app-local 部署（发布形态）。开发期不需要——dll 延迟加载且 vendor/win/bin
// 绝对路径编进了 exe。语义与 scripts/win_ffmpeg_dll.py 一致（2026-11-12 收编）；
// exe 择新口径改为 release 优先的确定性序（py 版按 mtime）。
// 下载不归这里：ffmpeg-mbt 的 prebuild 构建时就把 dll 取到 vendor/win/bin。

///|
let ffmpeg_required_dlls : Array[String] = [
  "avcodec-63.dll", "avformat-63.dll", "avutil-61.dll", "swscale-10.dll", "swresample-7.dll",
]

///|
/// 与 REQUIRED 同版本配套，带了无害。
let ffmpeg_optional_dlls : Array[String] = [
  "avdevice-63.dll", "avfilter-12.dll",
]

///|
/// 单个 dll 的体积下限：判掉残缺/半截文件，不是精确校验。
let dll_min_bytes : Int32 = 100 * 1024

///|
/// `mng ffmpeg-dll [audio|video] [--dll-dir <dir>] [--run] [--dry-run]`
fn cmd_ffmpeg_dll(args : Array[String]) -> Int32 {
  if host_os() != "windows" {
    println(
      tmsg(
        "ffmpeg-dll 仅 Windows 需要（mac/linux 动态库走 rpath/ld 路径，无 app-local 之说）",
        "ffmpeg-dll is Windows-only (mac/linux load via rpath/ld paths)",
      ),
    )
    return 0
  }
  let mut target = ""
  let mut dll_dir = ""
  let mut do_run = false
  let mut dry = false
  for a in args {
    if a == "--run" {
      do_run = true
    } else if a == "--dry-run" {
      dry = true
    } else if a.has_prefix("--dll-dir") {
      // --dll-dir <dir> 与 --dll-dir=<dir> 两种写法都收
      if a.contains("=") {
        dll_dir = after_eq(a)
      } else {
        dll_dir = "NEED_NEXT"
      }
    } else if dll_dir == "NEED_NEXT" {
      dll_dir = a
    } else if a == "audio" || a == "video" {
      target = a
    } else {
      eprintln(tmsg("未知参数：" + a, "Unknown argument: " + a))
      usage_ffmpeg_dll()
      return 2
    }
  }
  let root = repo_root_of_cwd()
  let examples = if target.length() > 0 { [target] } else { ["audio", "video"] }
  let mut code = 0
  for ex in examples {
    let r = ffmpeg_dll_for(root, ex, dll_dir~, dry~, do_run~)
    if r != 0 {
      code = r
    }
  }
  code
}

///|
fn ffmpeg_dll_for(
  root : String,
  example : String,
  dll_dir~ : String,
  dry~ : Bool,
  do_run~ : Bool,
) -> Int32 {
  let mod_name = "native-gui-examples-" + example
  let exe = match find_example_exe(root, mod_name) {
    Some(p) => p
    None => {
      println(
        tmsg(
          "[" +
          example +
          "] 找不到构建产物 exe——先 moon build " +
          example,
          "[" +
          example +
          "] no built exe found — moon build " +
          example +
          " first",
        ),
      )
      return 1
    }
  }
  let exe_dir = dir_of_path(exe)
  let src_dir = match find_dll_dir(root, exe_dir, dll_dir~) {
    Some(d) => d
    None => {
      println(
        tmsg(
          "[" +
          example +
          "] 七路都没找到配套 ffmpeg dll（先构建一次媒体示例让 prebuild 取 vendor，或 --dll-dir 指路）",
          "[" +
          example +
          "] no matching ffmpeg dlls in any of the 7 sources (build the example once so the prebuild vendors them, or pass --dll-dir)",
        ),
      )
      return 1
    }
  }
  let mut copied = 0
  let mut missing = false
  for name in ffmpeg_required_dlls {
    let dst = exe_dir + "/" + name
    if (@fs.is_file(dst) catch { _ => false }) && dll_big_enough(dst) {
      continue
    }
    let src = src_dir + "/" + name
    if !(@fs.is_file(src) catch { _ => false }) {
      missing = true
      continue
    }
    if dry {
      println("PLAN " + src + " -> " + dst)
    } else if copy_file(src, dst) {
      println("OK " + dst)
      copied += 1
    } else {
      println(tmsg("复制失败：" + src, "copy failed: " + src))
      return 1
    }
  }
  // 同批可选：带了无害
  for name in ffmpeg_optional_dlls {
    let src = src_dir + "/" + name
    let dst = exe_dir + "/" + name
    if (@fs.is_file(src) catch { _ => false }) &&
      !(@fs.is_file(dst) catch { _ => false }) {
      if dry {
        println("PLAN " + src + " -> " + dst)
      } else {
        let _ = copy_file(src, dst)
      }
    }
  }
  if missing {
    println(
      tmsg(
        "[" + example + "] 源目录缺必需 dll：见 " + src_dir,
        "[" + example + "] source dir misses required dlls: see " + src_dir,
      ),
    )
    return 1
  }
  println(
    tmsg(
      "[" +
      example +
      "] 就绪（补 \{copied} 支）" +
      (if dry { "（dry-run 未落盘）" } else { "" }),
      "[" +
      example +
      "] ready (\{copied} copied)" +
      (if dry { " (dry-run, nothing written)" } else { "" }),
    ),
  )
  if do_run && !dry {
    match @proc.spawn(exe, [], exe_dir + "/ffmpeg_dll_run.log") {
      Ok(pid) => println(tmsg("已启动 pid=\{pid}", "started pid=\{pid}"))
      Err(e) => {
        println(tmsg("起不起来：" + e, "cannot start: " + e))
        return 1
      }
    }
  }
  0
}

///|
fn find_dll_dir(root : String, exe_dir : String, dll_dir~ : String) -> String? {
  // 1. 显式 --dll-dir（环境变量 NATIVE_GUI_FFMPEG_BIN 同级）
  let mut explicit = dll_dir
  if explicit.length() == 0 {
    match @env.get_env_var("NATIVE_GUI_FFMPEG_BIN") {
      Some(v) if v.length() > 0 => explicit = v
      _ => ()
    }
  }
  if explicit.length() > 0 {
    if dir_has_dlls(explicit) {
      return Some(explicit)
    }
    return None
  }
  // 2. exe 同目录（已齐则直接返回）
  if dir_has_required(exe_dir) {
    return Some(exe_dir)
  }
  // 3. ffmpeg-mbt 的 vendor 落点
  let vendor = root + "/modules/ffmpeg-mbt/vendor/win/bin"
  if dir_has_dlls(vendor) {
    return Some(vendor)
  }
  // 4. PATH 搜索
  match @env.get_env_var("PATH") {
    Some(path) =>
      for raw in path.split(";") {
        let d = raw.to_owned()
        if d.length() > 0 &&
          (@fs.is_file(d + "/avcodec-63.dll") catch { _ => false }) {
          return Some(d)
        }
      }
    None => ()
  }
  // 5. winget 包目录
  match @env.get_env_var("LOCALAPPDATA") {
    Some(appdata) => {
      let base = appdata + "\\Microsoft\\WinGet\\Packages"
      let entries : ArrayView[String] = @fs.read_dir(base) catch { _ => [] }
      // 名含 FFmpeg 的目录下找 current/bin
      for e in entries {
        if e.to_lower().contains("ffmpeg") {
          let cand = base + "\\" + e + "\\current\\bin"
          if dir_has_dlls(cand) {
            return Some(cand)
          }
        }
      }
    }
    None => ()
  }
  // 6. scoop
  match @env.get_env_var("USERPROFILE") {
    Some(home) => {
      let base = home + "\\scoop\\apps"
      let entries : ArrayView[String] = @fs.read_dir(base) catch { _ => [] }
      for e in entries {
        if e.has_prefix("ffmpeg") {
          let cand = base + "\\" + e + "\\current\\bin"
          if dir_has_dlls(cand) {
            return Some(cand)
          }
        }
      }
    }
    None => ()
  }
  // 7. 仓库缓存（早期下载落点，只读兼容）
  let cache = root + "/.cache/ffmpeg-win/bin"
  if dir_has_dlls(cache) {
    return Some(cache)
  }
  None
}

///|
fn dir_has_required(d : String) -> Bool {
  for name in ffmpeg_required_dlls {
    if !(@fs.is_file(d + "/" + name) catch { _ => false }) {
      return false
    }
  }
  true
}

///|
/// 目录里至少有一支 av*/sw* dll 且必需品不缺才算「可用源」；简化为
/// 必需五支逐一判存在（py 版还收可选支，这里等价——源里必需品齐才有意义）。
fn dir_has_dlls(d : String) -> Bool {
  dir_has_required(d)
}

///|
fn dll_big_enough(p : String) -> Bool {
  // x/fs 无 size 读数，读进来判长（dll 最小 100KB 判残缺，量级几十 MB 可接受）
  let b : Bytes = @fs.read_file_to_bytes(p) catch { _ => b"" }
  b.length() >= dll_min_bytes
}

///|
/// _build/native/<mode>/build/NoahLiu/<mod>/<mod>.exe；mode 取 release 优先
/// （发布形态语义），其次 debug。
fn find_example_exe(root : String, mod_name : String) -> String? {
  for mode in ["release", "debug"] {
    let cand = root +
      "/_build/native/" +
      mode +
      "/build/NoahLiu/" +
      mod_name +
      "/" +
      mod_name +
      ".exe"
    if (@fs.is_file(cand) catch { _ => false }) {
      return Some(cand)
    }
  }
  None
}

///|
fn repo_root_of_cwd() -> String {
  let mut dir = match @env.current_dir() {
    Some(d) => d
    None => "."
  }
  // 向上找 moon.work / .git 判仓库根；到根还没找到就用 cwd（ffmpeg-dll 的
  // vendor/PATH 源大多走绝对路径，根错只影响相对 vendor 一路）
  let mut depth = 0
  while depth < 32 {
    if (@fs.is_file(dir + "/moon.work") catch { _ => false }) ||
      (@fs.is_dir(dir + "/.git") catch { _ => false }) {
      return dir
    }
    let parent = dir_of_path(dir)
    if parent == dir {
      break
    }
    dir = parent
    depth += 1
  }
  dir
}

///|
fn after_eq(a : String) -> String {
  let n = a.length()
  let mut i = 0
  while i < n {
    if a[i] == '=' {
      return a[i + 1:].to_owned()
    }
    i += 1
  }
  ""
}

///|
fn usage_ffmpeg_dll() -> Unit {
  println(
    tmsg(
      "用法：\{inv_prefix[0]} ffmpeg-dll [audio|video] [--dll-dir <dir>] [--run] [--dry-run]",
      "Usage: \{inv_prefix[0]} ffmpeg-dll [audio|video] [--dll-dir <dir>] [--run] [--dry-run]",
    ),
  )
  println(
    tmsg(
      "  （仅 Windows）把 ffmpeg 运行期 dll 搬到媒体示例 exe 旁（app-local 部署，发布形态）；缺省 audio 与 video 一起补",
      "  (Windows only) Copy the ffmpeg runtime dlls next to the media examples' exe (app-local deployment for release form); audio and video by default",
    ),
  )
}
