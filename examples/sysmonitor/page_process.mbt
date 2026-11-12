// 进程页（U3）：table_v 虚拟表格（千行级）+ 搜索过滤 + 列头排序 +
// 选中 kill（结束 / 强制结束），1Hz 增量刷新。
// 选择按 pid 重映射：每次刷新把旧选中行号经 pid 数组映射到新行号，
// 排序变化（CPU% 实时变动）不会让选中漂到别的进程。数据来自 main.mbt
// 的 1Hz sample_once 写入的 app.procs。
// 表格随手窗尺寸重挂：宽 = 右栏宽 − 页内边距（最小 700，超宽横向滚动），
// 高 = 窗口高 − 顶栏/消息/内外边距（最小 160），内部仍虚拟滚动。

///|
/// 进程排序列（列头索引经 sort_of_col 映射；状态与命令行列不参与排序）。
pub(all) enum ProcSort {
  ByPid
  ByName
  ByCpu
  ByMem
  ByThreads
}

///|
/// 一位小数（CPU% 显示）。
fn fmt1(v : Double) -> String {
  let scaled = (v * 10.0).round().to_int()
  "\{scaled / 10}.\{scaled % 10}"
}

///|
/// 搜索过滤：query 命中 pid 十进制 / 进程名 / 命令行（大小写不敏感）；
/// 空 query 全收。返回新数组，不改入参。
pub fn filter_procs(procs : Array[ProcInfo], query : String) -> Array[ProcInfo] {
  let q = query.trim().to_lower()
  if q == "" {
    let all : Array[ProcInfo] = []
    for p in procs {
      all.push(p)
    }
    return all
  }
  let out : Array[ProcInfo] = []
  for p in procs {
    let hay = "\{p.pid} \{p.name} \{p.cmd}".to_lower()
    if hay.contains(q) {
      out.push(p)
    }
  }
  out
}

///|
/// 按列排序（asc 升序 / false 降序），返回新数组。
pub fn sort_procs(
  procs : Array[ProcInfo],
  by : ProcSort,
  asc : Bool,
) -> Array[ProcInfo] {
  let out : Array[ProcInfo] = []
  for p in procs {
    out.push(p)
  }
  fn key_of(p : ProcInfo, by : ProcSort) -> Double {
    match by {
      ByPid => p.pid.to_double()
      ByName => 0.0
      ByCpu => p.cpu_pct
      ByMem => p.rss_kb.to_double()
      ByThreads => p.threads.to_double()
    }
  }

  if by is ByName {
    // 名称列按字符串比较（大小写不敏感）
    out
    .mut_view()
    .sort_by(fn(a, b) {
      let ka = a.name.to_lower()
      let kb = b.name.to_lower()
      let c = if ka < kb { -1 } else if ka > kb { 1 } else { 0 }
      if asc {
        c
      } else {
        -c
      }
    })
  } else {
    out
    .mut_view()
    .sort_by(fn(a, b) {
      let ka = key_of(a, by)
      let kb = key_of(b, by)
      let c = if ka < kb { -1 } else if ka > kb { 1 } else { 0 }
      if asc {
        c
      } else {
        -c
      }
    })
  }
  out
}

///|
/// 进程行 → 表格行（列序：PID / 进程名 / 状态 / CPU% / 内存 / 线程 /
/// 命令行；与 columns 定义一致）。状态显示中文文字，不露内核字符。
pub fn proc_row(p : ProcInfo) -> @ui.TableRow {
  @ui.TableRow::make([
    "\{p.pid}",
    p.name,
    proc_state_text(p.state),
    fmt1(p.cpu_pct),
    fmt_kb(p.rss_kb),
    "\{p.threads}",
    p.cmd,
  ])
}

///|
/// 列头索引 → 排序列（状态 / 命令行列返回 None）。
fn sort_of_col(j : Int) -> ProcSort? {
  match j {
    0 => Some(ByPid)
    1 => Some(ByName)
    3 => Some(ByCpu)
    4 => Some(ByMem)
    5 => Some(ByThreads)
    _ => None
  }
}

///|
/// 页面状态：派生表格数据 + 过滤 / 排序条件 + 操作消息。
/// 排序条件走 @ui.TableSort Store（表头点击由 table_v 组件内切换，
/// 本页订阅后重建数据），箭头显示与点击切换因此对组件透明。
struct ProcPage {
  rows : @base.Store[Array[@ui.TableRow]]
  sel : @base.Store[Array[Int]]
  msg : @base.Store[String]
  status : @base.Store[String]
  sort : @base.Store[@ui.TableSort]
  mut pids : Array[Int]
  mut query : String
}

///|
/// 重建派生数据：过滤 + 排序 → rows；选择按 pid 重映射到新行号。
fn ProcPage::rebuild(self : ProcPage, procs : Array[ProcInfo]) -> Unit {
  // 旧选中行号 → pid（刷新前先取，避免排序变化后漂移）
  let old = self.sel.get()
  let sel_pids : Array[Int] = []
  for i in old {
    if i >= 0 && i < self.pids.length() {
      sel_pids.push(self.pids[i])
    }
  }
  let filtered = filter_procs(procs, self.query)
  let st = self.sort.get()
  let sorted = match sort_of_col(st.column) {
    None => filtered
    Some(by) => sort_procs(filtered, by, st.asc)
  }
  let rows : Array[@ui.TableRow] = []
  let pids : Array[Int] = []
  for p in sorted {
    rows.push(proc_row(p))
    pids.push(p.pid)
  }
  self.pids = pids
  self.rows.set(rows)
  // 重映射选择：pid 仍存在才保留
  let new_sel : Array[Int] = []
  for pid in sel_pids {
    for i in 0..<pids.length() {
      if pids[i] == pid {
        new_sel.push(i)
        break
      }
    }
  }
  self.sel.set(new_sel)
  let base = if pids.length() == procs.length() {
    "进程总数 \{procs.length()}"
  } else {
    "进程总数 \{procs.length()}（筛选 \{pids.length()}）"
  }
  self.status.set(
    if new_sel.length() > 0 {
      "\{base} · 选中 \{new_sel.length()}"
    } else {
      base
    },
  )
}

///|
/// 当前选中行对应的 pid 列表。
fn ProcPage::selected_pids(self : ProcPage) -> Array[Int] {
  let out : Array[Int] = []
  for i in self.sel.get() {
    if i >= 0 && i < self.pids.length() {
      out.push(self.pids[i])
    }
  }
  out
}

///|
/// 对选中进程发信号（结束 / 强杀），逐个报告结果。
fn ProcPage::signal_selected(
  self : ProcPage,
  sig : Int,
  label : String,
) -> Unit {
  let pids = self.selected_pids()
  if pids.length() == 0 {
    self.msg.set("先选中进程")
    return
  }
  let mut ok = 0
  let mut fail = ""
  for pid in pids {
    match kill_signal(pid, sig) {
      Ok(_) => ok += 1
      Err(e) => fail = "\{fail},[\{pid}]\{e}"
    }
  }
  self.msg.set(
    if fail == "" {
      "已\{label} \{ok} 个进程"
    } else {
      "\{label}:\{ok} 个成功\{fail}"
    },
  )
}

///|
/// "WxH" → (宽, 高)；解析失败按窗口默认尺寸兜底。
fn parse_size_key(key : String) -> (Double, Double) {
  match key.split_once("x") {
    Some((a, b)) => {
      let w = match parse_i64(a.trim()) {
        Some(v) => v.to_double()
        None => 1240.0
      }
      let h = match parse_i64(b.trim()) {
        Some(v) => v.to_double()
        None => 840.0
      }
      (w, h)
    }
    None => (1240.0, 840.0)
  }
}

///|
/// 进程页：顶栏（搜索 + 结束按钮 + 进程总数）+ 消息行 + 填满剩余空间的
/// 表格（随窗口尺寸重挂）。
fn page_process(app : App) -> @widget.Node {
  // 平台化文案：Windows kill 一律 TerminateProcess 一档，Linux 两档
  let platform : String = if on_windows() { "windows" } else { "linux" }
  let (end_label, force_label) = kill_button_labels(platform)
  let page : ProcPage = {
    rows: @base.Store::new([]),
    sel: @base.Store::new([]),
    msg: @base.Store::new(""),
    status: @base.Store::new("采样中…"),
    // 初始排序：CPU% 降序（列 3）
    sort: @base.Store::new(@ui.TableSort::{ column: 3, asc: false, }),
    pids: [],
    query: "",
  }
  // 初始数据 + 订阅 1Hz 刷新（增量：只重算派生数据，不重建视图树）
  page.rebuild(app.procs.get())
  app.procs.subscribe(fn(procs) { page.rebuild(procs) })
  // 表头排序点击（table_v 组件内切换 Store）→ 重建数据
  page.sort.subscribe(fn(_s) { page.rebuild(app.procs.get()) })

  let query_store : @base.Store[String] = @base.Store::new("")
  let tools : Array[@widget.Node] = [
    @ui.input(
      query_store,
      placeholder="进程名 / pid",
      width=240.0,
      on_change=fn(s) {
        page.query = s
        page.rebuild(app.procs.get())
      },
    ),
  ]
  match force_label {
    None =>
      // Windows：一律立即终止，单按钮
      tools.push(
        @ui.button(end_label, variant=@ui.Danger, on_click=fn() {
          page.signal_selected(SIGKILL, "强制结束")
        }),
      )
    Some(fl) => {
      // Linux：温和结束（SIGTERM）+ 强制结束（SIGKILL 兜底）两档
      tools.push(
        @ui.button(end_label, variant=@ui.Soft, on_click=fn() {
          page.signal_selected(SIGTERM, "结束")
        }),
      )
      tools.push(
        @ui.button(fl, variant=@ui.Danger, on_click=fn() {
          page.signal_selected(SIGKILL, "强制结束")
        }),
      )
    }
  }
  // 进程总数/选中数贴右（工具行剩余宽全给它）
  tools.push(
    @ui.text_dyn(
      page.status.signal(),
      font_size=12.0,
      color="text_secondary",
      align=@text.End,
      wrap=false,
      handle=fn(w) { w.node.set_flex_grow(1.0) },
    ),
  )

  let columns = [
    @ui.TableColumn::make("PID", 86.0, align=@text.End),
    @ui.TableColumn::make("进程名", 150.0),
    @ui.TableColumn::make("状态", 80.0, align=@text.Center, sortable=false),
    @ui.TableColumn::make("CPU%", 72.0, align=@text.End),
    @ui.TableColumn::make("内存", 96.0, align=@text.End),
    @ui.TableColumn::make("线程", 56.0, align=@text.End),
    @ui.TableColumn::make("命令行", 0.0, sortable=false),
  ]
  let table_area = @widget.bind_node(app.size_key.signal(), fn(key) {
    let (win_w, win_h) = parse_size_key(key)
    // 右栏宽 = 窗口 − 外壳 padding(6×2) − 左栏；夹 400 下限后扣页内边距
    let right_w = (win_w - 12.0 - LEFT_PANE_W).max(400.0)
    let tw = (right_w - 24.0).max(700.0)
    let th = (win_h - 98.0).max(160.0)
    let table = @ui.table_v(
      columns,
      page.rows,
      width=tw,
      height=th,
      row_height=30.0,
      selection=page.sel,
      sort=page.sort,
    )
    // 表格宽超视口时横向滚动（列拖窄/拖宽在同一总宽内此消彼长）
    @ui.scroll_view(
      [table],
      @ui.ScrollState::new(),
      height=th,
      hscroll=true,
      vscroll=false,
      handle=fn(v) {
        v.node.set_width(@yoga.percent(100.0))
        v.node.set_flex_grow(1.0)
      },
    )
  })
  @ui.col(
    [
      // 工具栏：搜索 + 操作 + 总数
      @ui.row(tools, column_gap=8.0, class=[@style.style(min_width=0.0)]),
      // 操作消息（固定一行高，空串时不占额外结构）
      @ui.view(
        [@ui.text_dyn(page.msg.signal(), font_size=12.0, color="text_secondary", wrap=false)],
        height=18.0,
      ),
      table_area,
    ],
    padding=12.0,
    row_gap=6.0,
    handle=fn(c) {
      c.node.set_width(@yoga.percent(100.0))
      c.node.set_height(@yoga.percent(100.0))
      c.node.set_min_width(@yoga.fixed(0.0))
      c.node.set_min_height(@yoga.fixed(0.0))
    },
  )
}
