// W36 无头播放示例：不建窗口、不挂组件树，纯代码驱动解码+输出。
//
// 与 audio/video 两个 UI 示例对照：那两条是组件形态（挂进 Node 树、走 App 时钟）；
// 本示例走 HeadlessAudio，用注入的 `schedule` 通道自驱动 pump——同样能播、同样
// 能调音量/倍速/跳转，区别只在没有窗口。
//
// 跑法：moon run examples/headless-audio
//       （默认资产 examples/assets/1.mp3，播 6 秒后退出）

///|
/// 默认资产的稳健解析：从当前目录逐级向上找 `examples/assets/<name>` 或
/// `assets/<name>`，moon run 无论从仓库根还是模块目录起跑都能命中。
fn resolve_asset(name : String) -> String? {
  let cwd = @sys.current_dir()
  let dirs : Array[String] = [cwd]
  for i = 1; i < cwd.length(); i = i + 1 {
    let ch = cwd[i]
    if ch == '/' || ch == '\\' {
      dirs.push(cwd[0:i].to_owned())
    }
  }
  for d in dirs {
    for sub in ["examples/assets", "assets"] {
      let c = d + "/" + sub + "/" + name
      if @sys.sys_path_exists(c) {
        return Some(c)
      }
    }
  }
  None
}

///|
fn main {
  let path = match resolve_asset("1.mp3") {
    Some(p) => p
    None => {
      println("HEADLESS: 找不到 assets/1.mp3（候选 examples/assets/）")
      return
    }
  }
  // 注入式 schedule：GUI 场景给 `@shell.set_timeout`；纯后台这里用一张
  // 「待执行回调」表 + 主循环自己拍（见下），也可换成任意线程/协程调度器。
  let pending : Ref[() -> Unit] = Ref(fn() { () })
  let schedule = fn(_ms : Int, f : () -> Unit) -> Int {
    pending.val = f
    1
  }
  let player = match @media.HeadlessAudio::open(
    path,
    schedule,
    on_complete=fn() { println("HEADLESS: 播放完成") },
  ) {
    Some(p) => p
    None => {
      println("HEADLESS: 解码引擎打开失败（ffmpeg 不在位？）")
      return
    }
  }
  player.set_volume(0.6)
  player.play()
  println("HEADLESS: 开始播放 " + path)
  // 主循环：每 20ms 跑一拍注入的 schedule 回调 + 打一次进度。
  // sleep 用子进程凑（无 UI 环境没有定时器回落，示例层面最小化）。
  let t0 = @shell.now_ms()
  while @shell.now_ms() - t0 < 6000L {
    (pending.val)()
    if @shell.now_ms() - t0 > 3000L && @shell.now_ms() - t0 < 3050L {
      player.set_volume(0.2)
      println("HEADLESS: 音量调到 0.2")
    }
    let _ = @sys.pr_run("sleep", ["0.02"])
  }
  println(
    "HEADLESS: 退出 t=" +
    player.current().to_string() +
    "s / 总长 " +
    player.duration().to_string() +
    "s",
  )
  player.close(fn(_id) { () })
}
