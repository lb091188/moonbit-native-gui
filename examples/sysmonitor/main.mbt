// 系统监视器（sysmonitor）：Ubuntu/Mission Center 式进程管理
// 与硬件信息查看。数据层纯 MoonBit 读 /proc、/sys（sysdata/sysproc/syshw），
// 唯一的系统调用经应用自有 native-stub（stub/sysmon.c，sysffi.mbt）；
// 单一 1Hz 定时器驱动全部采样，各页经 Store 订阅刷新——数值卡只改文本，
// 曲线只进程级 invalidate 重绘画布，不重建视图树。主题深浅启动跟随系统
// 并实时联动（App::follow_system_theme）。左栏资源卡片即菜单，右栏全部
// 详情页一次性挂载、按 view 切可见性（选中态 / 滚动位置 / 表格选择不丢）。
//
// 四条口径：
//   - 样式走组件的具名参数（padding/row_gap/grow/width），没有样式字符串列表。
//   - 自绘容器重绘走「Store.subscribe + @widget.invalidate()」（进程级
//     host_repaint_all）；主题切换同样走 invalidate（on_draw 每次实时读
//     theme_current）。
//   - 手型光标用 cursor_group（宿主取悬停路径最深的非零请求，组内一处即可
//     盖住全部）。
//   - 面积图用 `area=true`；表格 table_v 的固定 width 参数按右栏实际宽度传入。

///|
/// kB 转人类可读（/proc/meminfo 单位为 kB）。
fn fmt_kb(kb : Int64) -> String {
  fmt_bytes(kb * 1024)
}

///|
/// 字节数人类可读：多级单位动态换挡（B / KB / MB / GB），值超 10 后
/// 只留整数档，小数值最多一位小数——保持字符串短，卡片与表格列内
/// 不换行。
fn fmt_bytes(b : Int64) -> String {
  let gb = b.to_double() / 1073741824.0
  if gb >= 1.0 {
    return "\{fmt_scale(gb)} GB"
  }
  let mb = b.to_double() / 1048576.0
  if mb >= 1.0 {
    return "\{fmt_scale(mb)} MB"
  }
  let kb = b.to_double() / 1024.0
  if kb >= 1.0 {
    return "\{fmt_scale(kb)} KB"
  }
  "\{b} B"
}

///|
/// 速率人类可读：B/s → KB/s → MB/s → GB/s，与 fmt_bytes 同档规则。
fn fmt_rate(bps : Double) -> String {
  if bps >= 1073741824.0 {
    "\{fmt_scale(bps / 1073741824.0)} GB/s"
  } else if bps >= 1048576.0 {
    "\{fmt_scale(bps / 1048576.0)} MB/s"
  } else if bps >= 1024.0 {
    "\{fmt_scale(bps / 1024.0)} KB/s"
  } else {
    "\{bps.to_int()} B/s"
  }
}

///|
/// 字节数 → 容量串（G 档；左栏「9.0G/16.0G」用）。
fn fmt_gb(b : Double) -> String {
  "\{fmt_scale(b / 1073741824.0)}G"
}

///|
/// 速率 B/s → 比特速率（网络口径 Mb/s，运营商同款）。
fn fmt_mbps(bps : Double) -> String {
  let mb = bps * 8.0 / 1000000.0
  if mb >= 100.0 {
    "\{mb.to_int()}Mb/s"
  } else {
    "\{fmt_scale(mb)}Mb/s"
  }
}

///|
/// 缩放数值：≥10 或恰为整数时只出整数档，否则一位小数——保持字符串短。
fn fmt_scale(v : Double) -> String {
  let scaled = (v * 10.0).round().to_int()
  if scaled % 10 == 0 {
    "\{scaled / 10}"
  } else {
    "\{scaled / 10}.\{scaled % 10}"
  }
}

///|
fn pct(v : Double) -> String {
  "\{(v * 100.0).to_int()}%"
}

///|
/// 应用状态：各采样器（持差值前样本）+ 跨页共享 Store。页面函数以 app
/// 单参取用；页内私有状态不进 App。
struct App {
  cpu : CpuMonitor
  proc : ProcMonitor
  disk : DiskMonitor
  net : NetMonitor
  // GPU：占用来源优先级（nvidia-smi > sysfs gpu_busy_percent > DRM
  // fdinfo 聚合）与 fdinfo 前样本差值状态
  gpu : GpuMonitor
  // 左栏固定信息（启动取一次）
  cpu_model : String
  cpu_max : String
  mem_brand : String
  mem_mhz : Int
  // 左栏六项菜单的值
  cpu_usage : @base.Store[String]
  mem_usage : @base.Store[String]
  mem_pair : @base.Store[String]
  swap_pair : @base.Store[String]
  net_up : @base.Store[String]
  net_down : @base.Store[String]
  disk_rate : @base.Store[String]
  disk_rows_ver : @base.Store[Int]
  disk_rows : Ref[Array[(String, String)]]
  disk_rows_sig : Ref[String]
  proc_count : @base.Store[String]
  gpu_usage : Array[@base.Store[String]]
  gpu_vram : Array[@base.Store[String]]
  // 各页曲线（定长滚动窗口 120 点 = 2 分钟 @1Hz）
  cpu_hist : @base.Store[Array[@charts.LineSeries]]
  core_hists : Array[@base.Store[Array[@charts.LineSeries]]]
  core_pct : Array[@base.Store[String]]
  mem_hist : @base.Store[Array[@charts.LineSeries]]
  swap_hist : @base.Store[Array[@charts.LineSeries]]
  // 网络：物理网卡集合变化时重建页面卡片，历史/实时值按网卡名保留
  net_names_key : @base.Store[String]
  net_hists : Map[String, @base.Store[Array[@charts.LineSeries]]]
  net_speed : Map[String, @base.Store[String]]
  // GPU 详情页：每块物理卡一套（数量取启动枚举结果，热插拔不重建）
  gpu_busy_hists : Array[@base.Store[Array[@charts.LineSeries]]]
  gpu_vram_hists : Array[@base.Store[Array[@charts.LineSeries]]]
  // 其余页数据源（进程 / 磁盘 / 网络页订阅）
  procs : @base.Store[Array[ProcInfo]]
  gpus : @base.Store[Array[GpuInfo]]
  disks : @base.Store[Array[DiskInfo]]
  nets : @base.Store[Array[NetInfo]]
  // 进程表随窗口尺寸重挂（250ms 轮询写入，"WxH"）
  size_key : @base.Store[String]
}

///|
/// 网络页/左栏按名字取曲线 Store（新网卡首次出现时现建）。
fn net_hist_of(app : App, name : String) -> @base.Store[Array[@charts.LineSeries]] {
  match app.net_hists.get(name) {
    Some(s) => s
    None => {
      let s : @base.Store[Array[@charts.LineSeries]] = @base.Store::new([
        @charts.LineSeries::make("接收", max_points=120),
        @charts.LineSeries::make("发送", max_points=120),
      ])
      app.net_hists.set(name, s)
      s
    }
  }
}

///|
/// 网络页/左栏按名字取实时速率文本 Store。
fn net_speed_of(app : App, name : String) -> @base.Store[String] {
  match app.net_speed.get(name) {
    Some(s) => s
    None => {
      let s : @base.Store[String] = @base.Store::new("—")
      app.net_speed.set(name, s)
      s
    }
  }
}

///|
/// 一次全量采样：全部监视器 tick 后写入对应 Store。单个来源读取失败
/// （平台不支持 / 瞬时竞态）只跳过该项，不影响其余菜单项。
fn sample_once(app : App) -> Unit {
  match app.cpu.tick() {
    None => ()
    Some((usage, per_core)) => {
      app.cpu_usage.set(pct(usage))
      @charts.series_push(app.cpu_hist, 0, usage * 100.0)
      for i, u in per_core {
        if i < app.core_hists.length() {
          @charts.series_push(app.core_hists[i], 0, u * 100.0)
          app.core_pct[i].set(pct(u))
        }
      }
    }
  }
  match mem_info() {
    None => ()
    Some(mem) => {
      let used_gb = mem.used_kb().to_double() / 1048576.0
      let swap_used = mem.swap_total_kb - mem.swap_free_kb
      let swap_gb = swap_used.to_double() / 1048576.0
      app.mem_usage.set(pct(mem.usage()))
      app.mem_pair.set(
        "\{fmt_gb(mem.used_kb().to_double() * 1024.0)}/\{fmt_gb(mem.total_kb.to_double() * 1024.0)}",
      )
      app.swap_pair.set(
        "\{fmt_gb(swap_used.to_double() * 1024.0)}/\{fmt_gb(mem.swap_total_kb.to_double() * 1024.0)}",
      )
      @charts.series_push(app.mem_hist, 0, used_gb)
      @charts.series_push(app.swap_hist, 0, swap_gb)
    }
  }
  match app.proc.tick() {
    None => ()
    Some(procs) => {
      app.procs.set_always(procs)
      app.proc_count.set("\{procs.length()}")
    }
  }
  match app.gpu.tick() {
    None => ()
    Some(gpus) => {
      app.gpus.set_always(gpus)
      // 数量以启动枚举为准，超界（极端热插拔）只跳过，不重建视图
      for i, g in gpus {
        if i >= app.gpu_busy_hists.length() {
          break
        }
        match g.busy {
          Some(b) => {
            @charts.series_push(app.gpu_busy_hists[i], 0, b)
            app.gpu_usage[i].set("\{b.to_int()}%")
          }
          None => app.gpu_usage[i].set("—")
        }
        match g.vram_used {
          Some(v) =>
            @charts.series_push(app.gpu_vram_hists[i], 0, v / 1073741824.0)
          None => ()
        }
        let vram = match (g.vram_used, g.vram_total) {
          (Some(u), Some(t)) => "\{fmt_gb(u)}/\{fmt_gb(t)}"
          _ => "—"
        }
        app.gpu_vram[i].set(vram)
      }
    }
  }
  match app.disk.tick() {
    None => ()
    Some(disks) => {
      app.disks.set_always(disks)
      let mut read = 0.0
      let mut write = 0.0
      let mut any_rate = false
      let rows : Array[(String, String)] = []
      let sig : Array[String] = []
      for d in disks {
        match d.read_bps {
          Some(v) => {
            read += v
            any_rate = true
          }
          None => ()
        }
        match d.write_bps {
          Some(v) => {
            write += v
            any_rate = true
          }
          None => ()
        }
        rows.push((d.mount, pct(d.usage())))
        sig.push("\{d.mount}:\{pct(d.usage())}")
      }
      let key = sig.join("|")
      if key != app.disk_rows_sig.val {
        app.disk_rows_sig.val = key
        app.disk_rows.val = rows
        app.disk_rows_ver.set(app.disk_rows_ver.get() + 1)
      }
      app.disk_rate.set(
        if any_rate {
          "↓\{fmt_rate(read)} ↑\{fmt_rate(write)}"
        } else {
          "↓— ↑—"
        },
      )
    }
  }
  match app.net.tick() {
    None => ()
    Some(nets) => {
      app.nets.set_always(nets)
      let mut rx = 0.0
      let mut tx = 0.0
      let names : Array[String] = []
      for n in nets {
        if n.physical {
          rx += n.rx_bps
          tx += n.tx_bps
          names.push(n.name)
          @charts.series_push(net_hist_of(app, n.name), 0, n.rx_bps)
          @charts.series_push(net_hist_of(app, n.name), 1, n.tx_bps)
          net_speed_of(app, n.name).set(
            "↓\{fmt_mbps(n.rx_bps)} ↑\{fmt_mbps(n.tx_bps)}",
          )
        }
      }
      app.net_up.set(fmt_mbps(tx))
      app.net_down.set(fmt_mbps(rx))
      names
      .mut_view()
      .sort_by(fn(a, b) {
        if a < b { -1 } else if a > b { 1 } else { 0 }
      })
      let key = names.join(",")
      if key != app.net_names_key.get() {
        app.net_names_key.set(key)
      }
    }
  }
}

///|
/// MHz → 主频串（≥1GHz 用 GHz 一位小数；0 = 来源不可用）。
fn fmt_ghz(mhz : Double) -> String {
  if mhz <= 0.0 {
    "—"
  } else if mhz >= 1000.0 {
    "\{fmt_scale(mhz / 1000.0)}GHz"
  } else {
    "\{mhz.to_int()}MHz"
  }
}

///|
const MON_TITLE : String = "系统监视器"

///|
fn main {
  let info = cpu_info().unwrap_or({ model: "(未知)", mhz: 0.0, max_mhz: 0.0, cores: 1, })
  let (mem_brand, mem_mhz) = mem_hw_info()
  let core_n = if info.cores < 1 { 1 } else { info.cores }
  // 磁盘与 GPU 数量取启动枚举结果，卡与曲线按块预建（热插拔不重建视图）
  let disk_mon = DiskMonitor::new()
  let gpu_mon = GpuMonitor::new()
  let gpus0 : Array[GpuInfo] = match gpu_mon.tick() {
    Some(g) => g
    None => []
  }
  // 各核小图按启动核数预建（核数固定，热插拔不重建）
  let core_hists : Array[@base.Store[Array[@charts.LineSeries]]] = []
  let core_pct : Array[@base.Store[String]] = []
  for _ in 0..<core_n {
    core_hists.push(
      @base.Store::new([@charts.LineSeries::make("核心", max_points=120)]),
    )
    core_pct.push(@base.Store::new("—"))
  }

  let app : App = {
    cpu: CpuMonitor::new(),
    proc: ProcMonitor::new(info.cores),
    disk: disk_mon,
    net: NetMonitor::new(),
    gpu: gpu_mon,
    cpu_model: info.model,
    cpu_max: fmt_ghz(info.max_mhz),
    mem_brand: mem_brand,
    mem_mhz: mem_mhz,
    cpu_usage: @base.Store::new("—"),
    mem_usage: @base.Store::new("—"),
    mem_pair: @base.Store::new("—"),
    swap_pair: @base.Store::new("—"),
    net_up: @base.Store::new("—"),
    net_down: @base.Store::new("—"),
    disk_rate: @base.Store::new("—"),
    disk_rows_ver: @base.Store::new(0),
    disk_rows: Ref([]),
    disk_rows_sig: Ref(""),
    proc_count: @base.Store::new("—"),
    gpu_usage: gpus0.map(fn(_g) { @base.Store::new("—") }),
    gpu_vram: gpus0.map(fn(_g) { @base.Store::new("—") }),
    cpu_hist: @base.Store::new([@charts.LineSeries::make("CPU", max_points=120)]),
    core_hists: core_hists,
    core_pct: core_pct,
    mem_hist: @base.Store::new([@charts.LineSeries::make("内存", max_points=120)]),
    swap_hist: @base.Store::new([@charts.LineSeries::make("swap", max_points=120)]),
    net_names_key: @base.Store::new(""),
    net_hists: Map([]),
    net_speed: Map([]),
    gpu_busy_hists: gpus0.map(fn(_g) {
      @base.Store::new([@charts.LineSeries::make("占用", max_points=120)])
    }),
    gpu_vram_hists: gpus0.map(fn(_g) {
      @base.Store::new([@charts.LineSeries::make("显存", max_points=120)])
    }),
    procs: @base.Store::new([]),
    gpus: @base.Store::new([]),
    disks: @base.Store::new([]),
    nets: @base.Store::new([]),
    size_key: @base.Store::new("1240x840"),
  }
  // 首帧立即采一次（第二帧起差值速率才有值）；定时与主题跟随在挂载后接
  sample_once(app)
  // 输入框的 Ctrl+C/X/V 接系统剪贴板；要在建 UI 前开（开关只影响此后新建的
  // 输入框，见 gui/ui/clipboard.mbt）
  @ui.use_system_clipboard(true)
  let mounted = @ui.mount_window(
    [@ui.row([app_shell(app)], grow=1.0, padding=6.0)],
    title=MON_TITLE,
    width=1240,
    height=840,
    handle=fn(a : @widget.WindowHost) {
      println("SYSMON-READY cores=\{info.cores}")
      // 深浅与主色启动跟随系统并实时联动（1s 轮询，指纹变了才 apply）
      ignore(a.follow_system_theme())
      // 窗口尺寸轮询：进程页表格按右栏实际宽高重挂（250ms，尺寸变化才写）
      let size_tick : Ref[() -> Unit] = Ref(fn() { () })
      size_tick.val = fn() -> Unit {
        let win : @win.Window = a.window()
        let (w, h) = win.size()
        let key = "\{w}x\{h}"
        if key != app.size_key.get() {
          app.size_key.set(key)
        }
        let _ = a.timer(250, size_tick.val)
      }
      (size_tick.val)()
      // 单一 1Hz 定时器驱动全部采样
      let tick : Ref[() -> Unit] = Ref(fn() { () })
      tick.val = fn() -> Unit {
        sample_once(app)
        let _ = a.timer(1000, tick.val)
      }
      let _ = a.timer(1000, tick.val)
    },
  )
  match mounted {
    Some(a) => {
      a.run()
      println("SYSMON-DONE")
    }
    None => println("SYSMON-SKIP: 本平台没有窗口后端或没有显示服务")
  }
}
