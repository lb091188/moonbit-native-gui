// 单实例的双进程探针（不起窗口，只验进程存活 + 退出行为 + 读数行，AGENTS 规则 6）。
// 三条通道（Linux dbus 知名名 / POSIX 套接字 / Win32 互斥体 + WM_COPYDATA）都经
// `@shell` 门面，所以一支探针覆盖三档。
//
// 跑法（两个终端，或用下面那条一键双进程）：
//   moon run experiment/instance_probe -- hold com.example.probe 10
//   moon run experiment/instance_probe -- wake com.example.probe 第二个实例的参数
// 期望读数：
//   hold 端：`INSTANCE-PROBE: claim primary arm=<dbus|socket|win32>`，收到唤起时
//            `INSTANCE-PROBE: wake #1 args=[...]`，退出前 `done wakes=1`；
//   wake 端：`INSTANCE-PROBE: claim existing arm=...`（**防多开判定成立**）、
//            `INSTANCE-PROBE: sent ok`、退出码 0。
// 单进程自环（只验送达，验不了防多开）：
//   moon run experiment/instance_probe -- self com.example.probe

///|
/// 读一条命令行参数（越界给默认值）。
fn arg_at(argv : Array[String], i : Int, dflt : String) -> String {
  if i < argv.length() { argv[i] } else { dflt }
}

///|
/// 秒数入参：只认连续数字，认不出给默认 10 秒。
fn parse_secs(s : String, dflt : Int) -> Int {
  let mut n = 0
  let mut seen = 0
  for c in s.to_array() {
    if c < '0' || c > '9' {
      break
    }
    n = n * 10 + (c.to_int() - 48)
    seen = seen + 1
  }
  if seen == 0 { dflt } else { n }
}

///|
/// 打一行读数。
fn note(line : String) -> Unit {
  println("INSTANCE-PROBE: " + line)
}

///|
/// 睡一小会儿：POSIX 走 `sleep`，Windows 走 `ping` 的往返延迟（本栈没有 sleep 口，
/// 探针不起窗口，用子进程等一拍最省事）。
fn nap() -> Unit {
  let _ =
    if @sys.sys_platform() == "windows" {
      @sys.pr_run("cmd", ["/c", "ping", "-n", "2", "127.0.0.1"], timeout_ms=3000)
    } else {
      @sys.pr_run("sh", ["-c", "sleep 0.2"], timeout_ms=3000)
    }
}

///|
/// 后端读数串（档位 + 本进程累计唤起）。
fn arm_text(app_id : String) -> String {
  let b = match @shell.instance_arm(app_id) {
    Some(v) => @shell.instance_backend_name(v)
    None => "-"
  }
  "\{b} wakes=\{@shell.instance_wake_count()}"
}

///|
/// 首实例档：声称成功后按拍抽唤起，直到秒数走完。
fn hold(app_id : String, secs : Int) -> Unit {
  match @shell.instance_claim(app_id) {
    Ok(@shell.Primary) => {
        note("claim primary arm=" + arm_text(app_id))
        @shell.on_instance_wake(fn(args : Array[String]) -> Unit {
          let parts : Array[String] = []
          for a in args {
            parts.push(a)
          }
          note("wake #" + @shell.instance_wake_count().to_string() + " args=[" +
            parts.join(", ") + "]")
        })
        let deadline = secs * 5
        let mut ticks = 0
        while ticks < deadline {
          let _ = @shell.dispatch_instance_wake()
          nap()
          ticks = ticks + 1
        }
        note("done wakes=" + @shell.instance_wake_count().to_string())
    }
    Ok(@shell.Existing) => note("claim existing（已有首实例在跑）arm=" + arm_text(app_id))
    Err(e) => note("claim err " + e.to_string())
  }
}

///|
/// 第二进程档：声称应当拿到 `Existing`（防多开判定），随后唤起首实例并退出。
fn wake(app_id : String, args : Array[String]) -> Unit {
  match @shell.instance_claim(app_id) {
    Ok(@shell.Existing) => {
      note("claim existing（防多开判定成立）")
      match @shell.instance_wake(app_id, args) {
        Ok(_) => note("sent ok args=[" + args.join(", ") + "]")
        Err(e) => note("sent err " + e.to_string())
      }
    }
    Ok(@shell.Primary) => note("claim primary —— 没有别的实例在跑，请先起 hold 端")
    Err(e) => note("claim err " + e.to_string())
  }
}

fn main {
  let argv = @env.args()
  let mode = arg_at(argv, 1, "self")
  let app_id = arg_at(argv, 2, "io.moonbitlibyue.instanceprobe")
  match mode {
    "hold" => hold(app_id, parse_secs(arg_at(argv, 3, "10"), 10))
    "wake" => {
      let rest : Array[String] = []
      for i = 3; i < argv.length(); i = i + 1 {
        rest.push(argv[i])
      }
      wake(app_id, rest)
    }
    _ => {
      // 自环：声称 → 给自己发一条 → 抽一拍看是否送达
      match @shell.instance_claim(app_id) {
        Ok(@shell.Primary) => {
          note("claim primary arm=" + arm_text(app_id))
          let mut got = ""
          @shell.on_instance_wake(fn(args : Array[String]) -> Unit {
            got = args.join(",")
          })
          match @shell.instance_wake(app_id, ["self", app_id]) {
            Ok(_) => note("sent ok")
            Err(e) => note("sent err " + e.to_string())
          }
          let _ = @shell.dispatch_instance_wake()
          note("delivered=" + (if got == "" { "no" } else { got }) + " wakes=" +
            @shell.instance_wake_count().to_string())
        }
        Ok(@shell.Existing) => note("claim existing arm=" + arm_text(app_id))
        Err(e) => note("claim err " + e.to_string())
      }
    }
  }
}
