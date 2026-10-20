// 每页「构造 / 挂载+布局 / 首帧」三档耗时判据，用来定「路由内容点开要等多久」。
//
// 现有 bench（experiment/showcase_cost_bench）只量了 mount+paint，构造期成本没被
// 单独量过——而 `node_of_new` 的 finish 闭包（`Widget::new` + `mount_children`）在
// 构造期就跑（gui/widget/node.mbt:42），thunk 化后这一步才是切页等待的大头。
//
// 无头：不开窗、不跑主循环，只建一棵挂在临时 `Widget` 根上的树 + 软件位图画一帧。
// 跑法：cd examples/showcase && moon run ./cost_bench
//
// 默认跳过构造期有真实外部副作用的页（见 SKIP），这类副作用正是「空闲预建」要
// 逐个收口的对象，不是判据要在这里触发的东西。

const W = 1280
const H = 720

// 系统 I/O 页（sysprobe：构造期跑全量探测，含读浏览器 sqlite）默认不量。
// 要一起量改成 true——它会真去读当前用户的桌面/浏览器数据。
const WITH_IO = false

///|
/// 递归数「会被画的控件」（有 on_draw 的），顺带数总控件数
fn count_widgets(w : @widget.Widget) -> (Int, Int) {
  let mut total = 1
  let mut drawn = if w.on_draw is Some(_) { 1 } else { 0 }
  let kids = w.children()
  for i = 0; i < kids.length(); i = i + 1 {
    let (t, d) = count_widgets(kids[i])
    total += t
    drawn += d
  }
  (total, drawn)
}

///|
/// 一页三档读数：构造、挂载+布局、首帧绘制
struct Bench {
  name : String
  widgets : Int
  drawn : Int
  build_ms : Int64
  mount_ms : Int64
  paint_ms : Int64
}

///|
/// 建页 → 挂进临时根 + 重排 → 软件位图画一帧，分别计时。
/// 位图分配在计时外，与 experiment/showcase_cost_bench 同口径，两个数可对照。
fn bench(
  name : String,
  app : @shared.App,
  build : (@shared.App) -> @widget.Node,
) -> Bench {
  let t0 = @win.now_ms()
  let node = build(app)
  let t1 = @win.now_ms()
  let root = @widget.Widget::new()
  root.set_size(W.to_double(), H.to_double())
  root.set_column()
  let t2 = @win.now_ms()
  let page = (node.mount)(root)
  root.relayout(W.to_double(), H.to_double())
  let t3 = @win.now_ms()
  let bm = @render.Bitmap::new(W, H)
  let p = @render.Painter::new(bm)
  let t4 = @win.now_ms()
  page.paint(p)
  let t5 = @win.now_ms()
  p.end()
  let (total, drawn) = count_widgets(page)
  {
    name,
    widgets: total,
    drawn,
    build_ms: t1 - t0,
    mount_ms: t3 - t2,
    paint_ms: t5 - t4,
  }
}

fn ms(v : Int64) -> String {
  v.to_string() + "ms"
}

///|
/// 取一行里第一段连续数字（`VmRSS:\t 1234 kB` 里的 1234）；没有数字给 -1
fn digits_value(s : String) -> Int {
  let mut acc = 0
  let mut found = false
  for c in s.iter() {
    let v = c.to_int()
    if v >= 48 && v <= 57 {
      acc = acc * 10 + (v - 48)
      found = true
    } else if found {
      return acc
    }
  }
  if found {
    acc
  } else {
    -1
  }
}

///|
/// 进程常驻集（KiB）；非 Linux 或读不到给 -1
fn vm_rss_kib() -> Int {
  let mut out = -1
  match @sys.sys_read_text_file("/proc/self/status") {
    Some(text) => {
      for line in text.split("\n") {
        let t = line.to_owned()
        if out < 0 && t.has_prefix("VmRSS:") {
          out = digits_value(t)
        }
      }
    }
    None => ()
  }
  out
}

// 回收判据轮数
const ROUNDS = 12

///|
/// A 组（对照）：建→挂→排→画→**走 remove_child 摘除**。样式侧表按控件 id 持有
/// 外观槽，丢弃钩子只挂在摘除路径上（gui/style/apply.mbt:14-25），走正规摘除
/// 应当不涨。
fn probe_remove(
  name : String,
  app : @shared.App,
  build : (@shared.App) -> @widget.Node,
) -> Unit {
  let root = @widget.Widget::new()
  root.set_size(W.to_double(), H.to_double())
  root.set_column()
  let bm = @render.Bitmap::new(W, H)
  let p = @render.Painter::new(bm)
  let style0 = @style.resolved_count()
  let rss0 = vm_rss_kib()
  for _i in 0..<ROUNDS {
    let node = build(app)
    let w = (node.mount)(root)
    root.relayout(W.to_double(), H.to_double())
    w.paint(p)
    let _ = root.remove_child(w)
  }
  p.end()
  let style1 = @style.resolved_count()
  let rss1 = vm_rss_kib()
  println("RCB-RECYCLE-A " + name + " remove_child rounds=" + ROUNDS.to_string() +
    " style_table=" + style0.to_string() + "->" + style1.to_string() +
    " delta=" + (style1 - style0).to_string() +
    " rss_kib=" + rss0.to_string() + "->" + rss1.to_string())
}

///|
/// B 组：同样建→挂→排，但**只丢引用、不摘树**（模拟「淘汰只把缓存里的 Node 清掉」
/// 的错误做法）。侧表残账应当随轮次涨——这就是淘汰必须走 remove_child 的实测根据。
fn probe_forget(
  name : String,
  app : @shared.App,
  build : (@shared.App) -> @widget.Node,
) -> Unit {
  let style0 = @style.resolved_count()
  let rss0 = vm_rss_kib()
  for _i in 0..<ROUNDS {
    let root = @widget.Widget::new()
    root.set_size(W.to_double(), H.to_double())
    root.set_column()
    let node = build(app)
    let _ = (node.mount)(root)
    root.relayout(W.to_double(), H.to_double())
  }
  let style1 = @style.resolved_count()
  let rss1 = vm_rss_kib()
  println("RCB-RECYCLE-B " + name + " forget-only rounds=" + ROUNDS.to_string() +
    " style_table=" + style0.to_string() + "->" + style1.to_string() +
    " delta=" + (style1 - style0).to_string() +
    " rss_kib=" + rss0.to_string() + "->" + rss1.to_string())
}

///|
/// 跨页共享状态：与 main.mbt 同形，但不建窗、不接 dbus、不装菜单栏
fn headless_app() -> @shared.App {
  let counter = @base.Signal::new(0)
  let visits = @base.Signal::computed(fn() {
    (counter.get() * 1601 + 12804).to_string()
  })
  let ratio = @base.Signal::computed(fn() {
    let r = 0.25 + counter.get().to_double() * 0.1
    if r > 1.0 {
      1.0
    } else {
      r
    }
  })
  {
    selected: @base.Store::new("基础组件"),
    locale: @base.Store::new("zh-CN"),
    ui_gen: @base.Store::new(0),
    toast: fn(_t : String, _k : @ui.SemanticType) -> Unit { () },
    dark_mode: @base.Store::new(false),
    accent: @base.Store::new(""),
    follow: @base.Store::new(true),
    counter,
    visits,
    ratio,
    picked_lang: @base.Signal::new(""),
    dlg_basic: @base.Store::new(false),
    dlg_form: @base.Store::new(false),
    dlg_name: @base.Store::new(""),
    dlg_result: @base.Store::new(""),
    flat: @base.Store::new(false),
    translucent: @base.Store::new(false),
    soft: @base.Store::new(false),
    host: Ref(None),
  }
}

///|
/// 预热：先建一棵极小的树挂一遍、画一帧，把主题与文本测量的一次性初始化
/// 花在计时外——否则它全落在循环里的第一页上，读数会把「首屏那页」显得比
/// 实际贵（实测：预热前基础组件 mount_layout=43ms，预热后回到个位数）。
fn warm_up() -> Unit {
  let root = @widget.Widget::new()
  root.set_size(W.to_double(), H.to_double())
  root.set_column()
  let w = (@ui.text("预热", role=@ui.Title).mount)(root)
  root.relayout(W.to_double(), H.to_double())
  let bm = @render.Bitmap::new(W, H)
  let p = @render.Painter::new(bm)
  w.paint(p)
  p.end()
}

fn main {
  warm_up()
  let app = headless_app()
  let pages : Array[(String, (@shared.App) -> @widget.Node)] = [
    ("基础组件", @pages.page_basic),
    ("表单组件", @pages.page_form),
    ("导航组件", @pages.page_nav),
    ("数据展示", @pages.page_data),
    ("图表", @pages.page_charts),
    ("代码文档", @pages.page_code),
    ("Store", @pages.page_store_demo),
    ("反馈组件", @pages.page_feedback),
    ("事件与布局", @pages.page_events),
    ("窗口", @pages.page_window),
    ("图标库", @pages.page_icons),
    ("画布与富文本", @pages.page_canvas),
    ("过渡与效果", @pages.page_anim),
  ]
  let results : Array[Bench] = []
  for item in pages {
    let (name, build) = item
    results.push(bench(name, app, build))
  }
  if WITH_IO {
    results.push(bench("系统能力探测", app, @pages.page_sysprobe))
  }
  println("RCB-CFG w=" + W.to_string() + " h=" + H.to_string() +
    " with_io=" + WITH_IO.to_string())
  // 构造期建真实托盘，无头判据不跑（pages/system.mbt:431）
  println("RCB-SKIP 系统集成=构造期建托盘(pages/system.mbt:431)")
  if !WITH_IO {
    println("RCB-SKIP 系统能力探测=构造期跑系统 I/O(pages/sysprobe.mbt:85)")
  }
  let mut total_build : Int64 = 0
  let mut worst : Int64 = 0
  let mut worst_name = ""
  let mut first_build : Int64 = 0
  for b in results {
    let click = b.build_ms + b.mount_ms + b.paint_ms
    total_build += b.build_ms
    if b.name == "基础组件" {
      first_build = b.build_ms
    }
    if click > worst {
      worst = click
      worst_name = b.name
    }
    println("RCB-PAGE " + b.name + " widgets=" + b.widgets.to_string() +
      " drawn=" + b.drawn.to_string() + " build=" + ms(b.build_ms) +
      " mount_layout=" + ms(b.mount_ms) + " paint=" + ms(b.paint_ms) +
      " click=" + ms(click))
  }
  println("RCB-SUM 全量预建构造=" + ms(total_build) +
    " 首屏构造=" + ms(first_build) +
    " 省下的=" + ms(total_build - first_build))
  // 点开一个「还没预建」的页要等的时长下界（最慢那页）
  println("RCB-CLICK 最慢点开页=" + worst_name + " " + ms(worst))
  // 淘汰回收判据：A 组走 remove_child，B 组只丢引用
  probe_remove("基础组件", app, @pages.page_basic)
  probe_forget("基础组件", app, @pages.page_basic)
  probe_remove("数据展示", app, @pages.page_data)
  probe_forget("数据展示", app, @pages.page_data)
}
