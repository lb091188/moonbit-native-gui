// 子进程执行 helper：统一「spawn → 限时回收 → 临时文件捕获 stdout/stderr」
// 的命令行工具调用封装，供音量/显示器/壁纸/窗口/打印机/电源计划等需要
// 调系统命令的模块共用。原生 spawn/wait 由 sys 桩提供（POSIX 分支 Linux 与
// macOS 共用：fork + setsid 自成进程组 + execvpe/execvp；Windows 分支
// CreateProcessW + CREATE_NO_WINDOW 不闪控制台），Linux 子进程环境钉
// `LC_MESSAGES=C`（英文文案可解析）而字符集 `LC_CTYPE` 随会话（钉成 ASCII 会
// 把中文路径变成问号，见 pr_locale_vars），Windows 传空环境块＝继承父进程环境；
// 退出码 0 归一为 Ok，非零退出归一为 Err 并携带 stderr，调用方无需判码。
// 平台差异（记档于 proposals/adaptation.md）：命令不存在在 Unix 惯例下由子
// 进程以退出码 127 呈现（NonZeroExit），Windows 下 CreateProcessW 直接失败
// （SpawnFailed 带错误码）。

///|
/// 子进程执行结果：stdout 为捕获的标准输出文本，exit_code 为退出码
/// （[pr_run] 成功时为 0）。
pub(all) struct ProcOutput {
  stdout : String
  exit_code : Int
}

///|
pub impl Show for ProcOutput with fn output(self, logger) {
  logger.write_string("ProcOutput { stdout: ")
  logger.write_string(self.stdout)
  logger.write_string(", exit_code: ")
  logger.write_string(self.exit_code.to_string())
  logger.write_string(" }")
}

///|
pub extend ProcOutput with Show::{to_string, output}

///|
pub(all) enum ProcError {
  /// 当前平台不支持子进程执行（Linux / macOS / Windows 之外）
  Unsupported
  /// 父侧启动失败（POSIX 的 fork、Windows 的 CreateProcessW 失败），带命令
  /// 与错误码；Unix 下命令不存在由子进程以退出码 127 呈现（归入非零退出），
  /// Windows 下命令不存在就是这里的失败
  SpawnFailed(String)
  /// 超时（超过 timeout_ms 未退出，进程已被强制终止），带命令与预算
  Timeout(String)
  /// 非零退出码，带退出码与捕获到的 stderr（可能为空串）
  NonZeroExit(Int, String)
  /// 进程被信号终止，带信号编号（仅 POSIX 呈现，Windows 无此档）
  Signaled(Int)
}

///|
pub impl Show for ProcError with fn output(self, logger) {
  match self {
    Unsupported => logger.write_string("ProcError::Unsupported")
    SpawnFailed(m) => logger.write_string("ProcError::SpawnFailed(\{m})")
    Timeout(m) => logger.write_string("ProcError::Timeout(\{m})")
    NonZeroExit(code, err) =>
      logger.write_string("ProcError::NonZeroExit(\{code}, \{err})")
    Signaled(sig) => logger.write_string("ProcError::Signaled(\{sig})")
  }
}

///|
pub extend ProcError with Show::{to_string, output}

// ---------------------------------------------------------------------------
// FFI（桩：sys_stub.c 的 proc_spawn / proc_wait / proc_getpid）
// ---------------------------------------------------------------------------

///|
#borrow(file, args, cwd, out_path, err_path, env)
extern "c" fn ffi_proc_spawn(
  file : Bytes,
  args : Bytes,
  cwd : Bytes,
  out_path : Bytes,
  err_path : Bytes,
  env : Bytes,
) -> Int = "yue_sys_proc_spawn"

///|
#borrow(status, code)
extern "c" fn ffi_proc_wait(
  pid : Int,
  timeout_ms : Int,
  status : Ref[Int],
  code : Ref[Int],
) -> Int = "yue_sys_proc_wait"

///|
extern "c" fn ffi_proc_getpid() -> Int = "yue_sys_proc_getpid"

// ---------------------------------------------------------------------------
// 子进程执行层（桩：spawn → 限时回收 → 临时文件读回）
// ---------------------------------------------------------------------------

///|
/// 临时文件名自增序号（与进程 pid 联合保证并发内唯一）。
let pr_tmp_counter : Ref[Int] = Ref(0)

///|
/// 临时输出文件路径：Windows 读 %TEMP%（回退当前目录、分隔符 `\`），其余
/// 读 $TMPDIR（回退 /tmp、分隔符 /）。桩只回 pid 不留句柄，所以文件名里的
/// 进程号取自 proc_getpid。
fn pr_tmp_path(tag : String) -> String {
  pr_tmp_counter.val = pr_tmp_counter.val + 1
  let win = sys_platform() == "windows"
  let dir =
    if win {
      match sys_getenv("TEMP") {
        Some(d) => if d != "" { d } else { "." }
        None => "."
      }
    } else {
      match sys_getenv("TMPDIR") {
        Some(d) => if d != "" { d } else { "/tmp" }
        None => "/tmp"
      }
    }
  let sep = if win { "\\" } else { "/" }
  "\{dir}\{sep}yue-pr-\{ffi_proc_getpid()}-\{pr_tmp_counter.val}.\{tag}"
}

///|
/// 参数表编码为「NUL 分隔条目 + 空条目收尾」的字节串（桩的 spawn 参数协议：
/// 条目指针直接指向这块内存，fork 前就绑好，子进程里不再分配）。
fn pr_args_blob(args : Array[String]) -> Bytes {
  let buf = StringBuilder()
  for a in args {
    buf.write_string(a)
    buf.write_char('\u{0}')
  }
  buf.write_char('\u{0}')
  @utf8.encode(buf.to_string())
}

///|
/// 挑子进程的字符集名：`LC_CTYPE` 优先，其次 `LANG`；空串与 `C`/`POSIX`
/// 都是 ASCII 字符集（等于没挑到），一律算无效。
fn pr_pick_ctype(ctype : String?, lang : String?) -> String? {
  fn usable(v : String?) -> String? {
    match v {
      Some(s) => {
        let t = s.trim(chars=" \t\n\r").to_owned()
        if t == "" || t == "C" || t == "POSIX" { None } else { Some(t) }
      }
      None => None
    }
  }
  match usable(ctype) {
    Some(c) => Some(c)
    None => usable(lang)
  }
}

///|
/// 子进程的 locale 变量对：字符集 + 消息语言。
/// **不再用一条 `LC_ALL=C` 打天下**：LC_ALL 覆盖所有类别，把字符集也钉成
/// ASCII，于是 gsettings 这类「按 locale 字符集转一遍再输出」的工具把中文路径
/// 就地打成问号（真机 Cinnamon 读数 `壁纸: /home/lkyh/??/?????.jpg`）。解析
/// 真正依赖的只是**英文文案**（pactl 的「音量:」/xrandr 的 "connected"），那归
/// `LC_MESSAGES` 一件事；字符集必须跟着会话走，两头都不让步。
/// 其余类别（LC_NUMERIC/LC_TIME/LC_COLLATE）不设置＝保持 C，数字与时间格式
/// 不因转发 LANG 而变；`LANGUAGE` 不透传（GLib 的消息翻译优先看它，透传会把
/// 文案带回本地化）。
fn pr_locale_vars(ctype : String?, lang : String?) -> Array[(String, String)] {
  let cs = match pr_pick_ctype(ctype, lang) {
    Some(c) => c
    None => "C.UTF-8"
  }
  [("LC_CTYPE", cs), ("LC_MESSAGES", "C")]
}

///|
/// POSIX 最小环境：逐个转发名单内的变量，末尾固定 locale 对（字符集随会话、
/// 消息恒定英文，见 [pr_locale_vars]）。
fn pr_env_posix(buf : StringBuilder, names : Array[String]) -> Unit {
  for name in names {
    match sys_getenv(name) {
      Some(v) => {
        buf.write_string(name)
        buf.write_char('=')
        buf.write_string(v)
        buf.write_char('\u{0}')
      }
      None => ()
    }
  }
  for (k, v) in pr_locale_vars(sys_getenv("LC_CTYPE"), sys_getenv("LANG")) {
    buf.write_string(k)
    buf.write_char('=')
    buf.write_string(v)
    buf.write_char('\u{0}')
  }
}

///|
/// 传给子进程的环境编码（同 args 的协议）：Linux 给 PATH（命令名解析）、
/// XDG_RUNTIME_DIR（会话服务套接字）、HOME，加上 X11/桌面会话与 DBus 总线
/// 变量（DISPLAY/XAUTHORITY/WAYLAND_DISPLAY/DBUS_SESSION_BUS_ADDRESS——
/// xrandr、xfconf-query、gsettings 这类桌面侧命令没有它们就直接非零退出）；
/// macOS 同走 execvp，必须自带 PATH，没有 XDG_RUNTIME_DIR；Windows 传空块
/// ＝继承父进程环境（那边无 locale 语义，且 SystemRoot/TEMP 这类变量自己拼
/// 容易漏）。
fn pr_env_blob() -> Bytes {
  let buf = StringBuilder()
  match sys_platform() {
    "linux" => pr_env_posix(
        buf,
        [
          "PATH",
          "XDG_RUNTIME_DIR",
          "HOME",
          "DISPLAY",
          "XAUTHORITY",
          "WAYLAND_DISPLAY",
          "DBUS_SESSION_BUS_ADDRESS",
        ],
      )
    "macos" => pr_env_posix(buf, ["PATH", "HOME"])
    _ => ()
  }
  buf.write_char('\u{0}')
  @utf8.encode(buf.to_string())
}

///|
/// 读回临时文件文本（读不到为空串）。
fn pr_slurp(path : String) -> String {
  match sys_read_text_file(path) {
    Some(t) => t
    None => ""
  }
}

// ---------------------------------------------------------------------------
// 公开 API
// ---------------------------------------------------------------------------

///|
/// 当前平台是否支持子进程执行（Linux / macOS / Windows）。基于 [pr_run] 的
/// 模块可用它做平台门；每次调用真实判断，高频场景请调用方自行缓存结果。
pub fn pr_available() -> Bool {
  match sys_platform() {
    "linux" | "macos" | "windows" => true
    _ => false
  }
}

///|
/// 运行命令并按退出码归一结果：命令名按 PATH 解析；退出码 0 →
/// Ok(stdout)，非零退出 → Err(NonZeroExit(退出码, stderr))，启动失败 /
/// 超时 / 被信号终止 / 平台不支持为对应 Err；超时进程会被强制终止。
///
/// 用法：
///   match pr_run("wpctl", ["get-volume", "@DEFAULT_SINK@"]) {
///     Ok(out) => println(out.stdout)
///     Err(NonZeroExit(_, err)) => println("失败：\{err}")
///     Err(e) => println(e)
///   }
pub fn pr_run(
  cmd : String,
  args : Array[String],
  timeout_ms? : Int = 5000,
) -> Result[ProcOutput, ProcError] {
  if !pr_available() {
    return Err(Unsupported)
  }
  let out_path = pr_tmp_path("out")
  let err_path = pr_tmp_path("err")
  // Windows 用空 cwd 表示继承父进程工作目录；POSIX 显式给 "/"
  let cwd = if sys_platform() == "windows" { "" } else { "/" }
  let pid = ffi_proc_spawn(
    @utf8.encode(cmd),
    pr_args_blob(args),
    @utf8.encode(cwd),
    @utf8.encode(out_path),
    @utf8.encode(err_path),
    pr_env_blob(),
  )
  let ans : Result[ProcOutput, ProcError] = if pid < 0 {
    Err(
      SpawnFailed(
        "\{cmd}: spawn 失败（错误码 \{-pid}，Windows 下含命令不存在）",
      ),
    )
  } else {
    let status = Ref(-1)
    let code = Ref(0)
    let wr = ffi_proc_wait(pid, timeout_ms, status, code)
    if wr != 0 {
      Err(SpawnFailed("\{cmd}: wait 失败（错误码 \{wr}）"))
    } else if status.val == 1 {
      Err(Timeout("\{cmd}: 超时（\{timeout_ms}ms）"))
    } else if status.val == 2 {
      Err(Signaled(code.val))
    } else if code.val == 0 {
      Ok({ stdout: pr_slurp(out_path), exit_code: 0, })
    } else {
      Err(NonZeroExit(code.val, pr_slurp(err_path)))
    }
  }
  // 清理临时文件（无论成败）
  let _ = sys_remove_file(out_path)
  let _ = sys_remove_file(err_path)
  ans
}
