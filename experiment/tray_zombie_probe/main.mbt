// 临时探针：托盘僵尸注册项的退出路径读数（只建托盘项，不开窗口）。
// 跑法：moon run experiment/tray_zombie_probe
//   PROBE_MODE=async → 用 Tray::remove（发完就走的注销）后立即退进程
//   其它            → 用 remove_all_trays（等到 watcher 应答）后立即退进程
//   PROBE_MODE=hold  → 挂着 3 秒等外部发信号

///|
fn main {
  let mode = match @sys.sys_getenv("PROBE_MODE") {
    Some(m) => m
    None => "sync"
  }
  match @shell.Tray::new("libyue-tray-zombie-probe") {
    Ok(t) => {
      t.set_tooltip("libyue 探针", "僵尸注册项复现")
      println("PROBE-REGISTERED mode=\{mode} name=\{@dbus.dbus_unique_name()}")
      if mode == "hold" {
        let mut ticks = 0
        while ticks < 30 {
          @dbus.dbus_pump(timeout_ms=100)
          if @shell.quit_requested() {
            println("PROBE-SIGNAL ticks=\{ticks}")
            break
          }
          ticks = ticks + 1
        }
        @shell.remove_all_trays()
        println("PROBE-EXIT how=hold")
      } else if mode == "async" {
        t.remove()
        println("PROBE-EXIT how=async")
      } else {
        @shell.remove_all_trays()
        println("PROBE-EXIT how=sync")
      }
    }
    Err(e) => println("PROBE-ERR \{e}")
  }
}
