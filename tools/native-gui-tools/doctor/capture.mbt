// 宿主判定、用户目录与命令输出捕获（proc 的 spawn_wait 落日志文件后读回）。

///|
/// 宿主平台：与 mng 打包腿同判定——Windows 环境变量 OS=Windows_NT，mac 认
/// 工具链存在，其余（POSIX 且非 mac）按 linux 腿走。
pub fn host() -> String {
  match @env.get_env_var("OS") {
    Some("Windows_NT") => return "win"
    _ => ()
  }
  if @fs.path_exists("/usr/bin/iconutil") && @fs.path_exists("/usr/bin/hdiutil") {
    return "mac"
  }
  "linux"
}

///|
/// 用户主目录：win 优先 USERPROFILE（原生路径；Git Bash 的 HOME 是 `/c/…`
/// 形态，原生 fs 与子进程都不认）；POSIX 走 HOME → USERPROFILE → 空串
/// （ready 与日志落到相对 .mng/ 下）。
pub fn home_dir() -> String {
  if host() == "win" {
    match @env.get_env_var("USERPROFILE") {
      Some(h) if h.length() > 0 => h
      _ =>
        match @env.get_env_var("HOME") {
          Some(h) if h.length() > 0 => h
          _ => ""
        }
    }
  } else {
    match @env.get_env_var("HOME") {
      Some(h) if h.length() > 0 => h
      _ =>
        match @env.get_env_var("USERPROFILE") {
          Some(h) if h.length() > 0 => h
          _ => ""
        }
    }
  }
}

///|
/// 单级目录不存在则建（已存在不报错）。
fn mkdir_if_absent(dir : String) -> Unit {
  let have = @fs.is_dir(dir) catch { _ => false }
  if !have {
    @fs.create_dir(dir) catch {
      _ => ()
    }
  }
}

///|
/// 递归建目录：`@fs.create_dir` 不递归，父目录缺席会失败——探针日志与 ready
/// 都要落到可能尚不存在的 `~/.mng/` 下。绝对路径认两种形态：`/` 开头与
/// Windows 盘符（`C:/Users/…`——盘符段钉在盘根，拼成 `./C:/…` 会建不出来）。
fn ensure_dir(path : String) -> Unit {
  let ok = @fs.is_dir(path) catch { _ => false }
  if ok {
    return
  }
  // Windows 盘符判定：第二码元是 ':' 且首码元是 ASCII 字母
  let is_drive = path.length() >= 2 &&
    path[1] == ':' &&
    ((path[0] >= 'a' && path[0] <= 'z') || (path[0] >= 'A' && path[0] <= 'Z'))
  let mut acc = ""
  let mut start = 0
  if path.has_prefix("/") {
    acc = ""
  } else if is_drive {
    acc = path[0:2].to_owned()
    start = 2
  } else {
    acc = "."
  }
  let n = path.length()
  let mut i = start
  while i < n {
    if path[i] == '/' {
      if i > start {
        acc = acc + "/" + path[start:i].to_owned()
        mkdir_if_absent(acc)
      }
      start = i + 1
    }
    i += 1
  }
  if start < n {
    acc = acc + "/" + path[start:n].to_owned()
    mkdir_if_absent(acc)
  }
}

///|
/// 跑一条命令并把 stdout/stderr 落 `log_dir/<id>.log` 读回。
/// 返回 (退出码, 输出全文)；起不来或超时返回 Err（错误文案含原因）。
fn capture(
  log_dir : String,
  id : String,
  file : String,
  args : Array[String],
  timeout_ms~ : Int32 = 15000,
) -> Result[(Int32, String), String] {
  ensure_dir(log_dir)
  let log = log_dir + "/" + id + ".log"
  if @fs.path_exists(log) {
    @fs.remove_file(log) catch {
      _ => ()
    }
  }
  match @proc.spawn_wait(file, args, log, timeout_ms) {
    Err(e) => Err(e)
    Ok(code) => {
      let out = @fs.read_file_to_string(log) catch { _ => "" }
      Ok((code, out.trim().to_owned()))
    }
  }
}
