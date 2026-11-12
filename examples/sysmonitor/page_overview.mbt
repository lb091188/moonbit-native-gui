// 应用壳 + 六项资源菜单（U1/U2）：Mission Center 式双栏布局。
// 左栏固定六项（处理器 / 内存 / 网络 / 磁盘 / 显卡 / 进程），每项
// 50×50 图标 + 加粗标题 + 左 label / 右右对齐值的属性行；名称类信息
// （CPU 型号、内存品牌/频率、显卡名）不带 label 直接显示。点击切换右栏，
// 选中项主题色描边。右栏 = 全部详情页一次性挂载、只切可见性，选中态 /
// 滚动位置 / 表格选择不丢。
// 数据来自 main.mbt 的 1Hz sample_once；菜单数值只改文本。

///|
/// 右栏视图（与左栏六项一一对应）。
pub(all) enum ViewId {
  VCpu
  VMem
  VDisk
  VNet
  VGpu
  VProc
}

///|
/// 视图 → 序号（枚举比较经序号，全库同款做法）。
fn view_index(v : ViewId) -> Int32 {
  match v {
    VCpu => 0
    VMem => 1
    VDisk => 2
    VNet => 3
    VGpu => 4
    VProc => 5
  }
}

///|
/// 左栏固定宽度（进程页算表格宽也用它）。
pub const LEFT_PANE_W : Double = 320.0

///|
/// 菜单文字列宽度（320 − 外边距 20 − 项内边距 24 − 图标 50 − 间距 10）。
const MENU_TEXT_W : Double = 216.0

///|
/// 菜单项外壳：50×50 图标钉左上，右侧一列（加粗标题 + 属性行）。
/// 点击切到 target；选中项主题色描边 + 浅底，悬停由 cursor_group 给手型。
fn menu_item(
  icon : @icons.IconKind,
  title : String,
  rows : Array[@widget.Node],
  view : @base.Store[ViewId],
  target : ViewId,
) -> @widget.Node {
  @ui.row(
    [
      @ui.icon(icon, size=50.0),
      @ui.col(
        [@ui.text(title, font_size=15.0, weight=@text.Bold, wrap=false)] + rows,
        grow=1.0,
        row_gap=4.0,
        class=[@style.style(min_width=0.0)],
      ),
    ],
    column_gap=10.0,
    padding=12.0,
    align_items=@yoga.AlignItems::FlexStart,
    handle=fn(c) {
      // 覆盖 container 的默认底色绘制：选中态主题色描边 + 浅底
      c.on_draw = Some(fn(
        _s : @widget.Widget,
        p : @render.Painter,
        r : @base.Rect,
      ) -> Unit {
        let t = @theme.theme_current()
        let act = view_index(view.get()) == view_index(target)
        p.set_fill_color(if act { t.fill_hover } else { t.bg_panel })
        p.fill_rect(0.0, 0.0, r.w, r.h)
        p.set_stroke_color(if act { t.primary } else { t.border })
        p.set_line_width(1.0)
        p.stroke_rect(0.0, 0.0, r.w, r.h)
      })
      ignore(@theme.on_theme_change(fn() { @widget.invalidate() }))
      view.subscribe(fn(_v) { @widget.invalidate() })
      c.on_pointer = Some(fn(
        _s : @widget.Widget,
        ev : @widget.PointerEvent,
      ) -> Bool {
        match ev.kind {
          @widget.PointerKind::Down =>
            if ev.button == 1 {
              view.set_always(target)
              true
            } else {
              false
            }
          _ => false
        }
      })
      c.cursor = @widget.CURSOR_HAND
    },
  )
}

///|
/// 带 label 的属性行：label 固定宽、值吃满余量并右对齐。
fn menu_row(label : String, value : @base.Store[String]) -> @widget.Node {
  @ui.row(
    [
      @ui.view(
        [@ui.text(label, font_size=12.0, color="text_secondary", wrap=false)],
        width=72.0,
      ),
      @ui.text_dyn(
        value.signal(),
        font_size=12.0,
        color="text_primary",
        align=@text.End,
        wrap=false,
        handle=fn(w) { w.node.set_flex_grow(1.0) },
      ),
    ],
    column_gap=6.0,
    class=[@style.style(min_width=0.0)],
  )
}

///|
/// 无 label 的名称/信息行：值占满整行，左对齐，超长省略。
fn menu_value(value : String) -> @widget.Node {
  @ui.text(
    value,
    font_size=12.0,
    color="text_secondary",
    wrap=false,
    ellipsis=true,
    max_width=MENU_TEXT_W,
  )
}

///|
/// 磁盘项：一个图标 + 聚合速率行 + 每个物理分区一行（挂载点 / 使用率）。
/// 分区集合变化时整块重挂（数量少，重建便宜）。
fn disk_rows(app : App) -> @widget.Node {
  @widget.bind_node(app.disk_rows_ver.signal(), fn(_v) {
    let rows : Array[@widget.Node] = []
    for r in app.disk_rows.val {
      let (mount, usage) = r
      rows.push(
        @ui.row(
          [
            @ui.view(
              [
                @ui.text(
                  mount,
                  font_size=12.0,
                  color="text_secondary",
                  wrap=false,
                  ellipsis=true,
                ),
              ],
              width=72.0,
            ),
            @ui.text(
              usage,
              font_size=12.0,
              color="text_primary",
              align=@text.End,
              wrap=false,
              handle=fn(w) { w.node.set_flex_grow(1.0) },
            ),
          ],
          column_gap=6.0,
          class=[@style.style(min_width=0.0)],
        ),
      )
    }
    @ui.col(rows, row_gap=4.0, class=[@style.style(min_width=0.0)])
  })
}

///|
/// 左栏：固定六项资源菜单（超高滚动）。
fn left_pane(app : App, view : @base.Store[ViewId]) -> @widget.Node {
  let items : Array[@widget.Node] = []
  // 处理器：名称（无 label）+ 利用率 + 最高主频
  items.push(
    menu_item(
      @icons.Cpu,
      "处理器",
      [
        menu_value(app.cpu_model),
        menu_row("利用率", app.cpu_usage),
        menu_row("最高主频", @base.Store::new(app.cpu_max)),
      ],
      view,
      VCpu,
    ),
  )
  // 内存：品牌/频率（无 label）+ 利用率 + 物理内存 + SWAP
  let mem_brand = if app.mem_brand == "" { "—" } else { app.mem_brand }
  let mem_mhz = if app.mem_mhz <= 0 { "—" } else { "\{app.mem_mhz}MHz" }
  items.push(
    menu_item(
      @icons.Database,
      "内存",
      [
        menu_value(mem_brand),
        menu_value(mem_mhz),
        menu_row("利用率", app.mem_usage),
        menu_row("物理内存", app.mem_pair),
        menu_row("SWAP", app.swap_pair),
      ],
      view,
      VMem,
    ),
  )
  // 网络：物理网卡聚合的上行/下行
  items.push(
    menu_item(
      @icons.Wifi,
      "网络",
      [menu_row("上行", app.net_up), menu_row("下行", app.net_down)],
      view,
      VNet,
    ),
  )
  // 磁盘：单图标，聚合速率 + 每个物理分区一行
  items.push(
    menu_item(
      @icons.Sever,
      "磁盘",
      [menu_row("速率", app.disk_rate), disk_rows(app)],
      view,
      VDisk,
    ),
  )
  // 显卡：每块卡一小组（名称无 label + 利用率 + 显存）
  let gpu_rows : Array[@widget.Node] = []
  let gpus = app.gpus.get()
  if gpus.length() == 0 {
    gpu_rows.push(menu_value("未检测到显卡"))
  } else {
    for i, g in gpus {
      if i >= app.gpu_usage.length() {
        break
      }
      let name = if g.model == "" { "\{g.vendor} \{g.device}" } else { g.model }
      let block : Array[@widget.Node] = [
        menu_value(name),
        menu_row("利用率", app.gpu_usage[i]),
        menu_row("显存", app.gpu_vram[i]),
      ]
      gpu_rows.push(
        @ui.col(block, row_gap=4.0, class=[@style.style(min_width=0.0)]),
      )
    }
  }
  items.push(menu_item(@icons.Monitor, "显卡", gpu_rows, view, VGpu))
  // 进程
  items.push(
    menu_item(
      @icons.TableIcon,
      "进程",
      [menu_row("进程数", app.proc_count)],
      view,
      VProc,
    ),
  )
  @ui.scroll_view(
    [@ui.col(items, padding=10.0, row_gap=8.0)],
    @ui.ScrollState::new(),
    width=LEFT_PANE_W,
    handle=fn(w) {
      // 固定宽侧栏不参与收缩：窗口变窄时由右栏缩视口并在内部横滚
      w.node.set_flex_shrink(0.0)
      w.node.set_align_self(Some(@yoga.AlignItems::Stretch))
    },
  )
}

///|
/// 右栏：全部详情页一次性挂载，按 view 切可见性；最小内容宽 400，
/// 窗口更窄时整块横向滚动（页内纵向滚动归各页自己的 scroll_view）。
fn view_area(app : App, view : @base.Store[ViewId]) -> @widget.Node {
  let items : Array[(ViewId, @widget.Node)] = [
    (VCpu, page_cpu_detail(app)),
    (VMem, page_mem_detail(app)),
    (VDisk, page_disk(app)),
    (VNet, page_net(app)),
    (VGpu, page_sensors(app)),
    (VProc, page_process(app)),
  ]
  let host = @ui.col(
    [],
    grow=1.0,
    class=[@style.style(min_width=0.0, min_height=0.0)],
    handle=fn(h) {
      h.node.set_width(@yoga.percent(100.0))
      h.node.set_height(@yoga.percent(100.0))
      let boxes : Array[@widget.Widget] = []
      for item in items {
        let (_, node) = item
        let pc = @widget.Widget::new()
        pc.node.set_flex_direction(@yoga.Column)
        pc.node.set_flex_grow(1.0)
        pc.node.set_width(@yoga.percent(100.0))
        pc.node.set_height(@yoga.percent(100.0))
        pc.node.set_min_width(@yoga.fixed(0.0))
        pc.node.set_min_height(@yoga.fixed(0.0))
        pc.set_visible(view_index(item.0) == view_index(view.get()))
        // 每页自己的纵向滚动视口（进程页例外：它内部表格自己滚）
        if item.0 is VProc {
          let _ = node.mount_into(pc)
        } else {
          let sc = @ui.scroll_view([node], @ui.ScrollState::new(), handle=fn(
            v,
          ) {
            v.node.set_flex_grow(1.0)
            v.node.set_align_self(Some(@yoga.AlignItems::Stretch))
          })
          let _ = sc.mount_into(pc)
        }
        h.append_child(pc)
        boxes.push(pc)
      }
      view.subscribe(fn(cur) {
        for j in 0..<boxes.length() {
          boxes[j].set_visible(view_index(items[j].0) == view_index(cur))
        }
        @widget.invalidate()
      })
    },
  )
  @ui.scroll_view(
    [host],
    @ui.ScrollState::new(),
    hscroll=true,
    min_content_width=400.0,
    vscroll=false,
    handle=fn(v) {
      v.node.set_flex_grow(1.0)
      v.node.set_align_self(Some(@yoga.AlignItems::Stretch))
    },
  )
}

///|
/// 处理器详情：总利用率全宽曲线 + 各逻辑核小图（超宽换行、超高整页滚动）。
/// 各核卡随右栏宽重挂：行宽容得下 4 张用 4 张，否则 3 张；卡宽按行宽均分
/// 精确铺满（floor − 0.5 防折行，行尾缺的不足 1px 不可见），没有缺位。
fn page_cpu_detail(app : App) -> @widget.Node {
  @widget.bind_node(app.size_key.signal(), fn(key) {
    let (win_w, _win_h) = parse_size_key(key)
    // 右栏宽 = 窗口 − 外壳 padding(6×2) − 左栏，夹 400 下限；行宽再扣页 padding(12×2)
    let right_w = (win_w - 12.0 - LEFT_PANE_W).max(400.0)
    let row_w = (right_w - 24.0).max(300.0)
    let per_row : Int = if row_w >= 4.0 * 240.0 + 3.0 * 12.0 {
      4
    } else {
      3
    }
    let card_w = ((row_w - (per_row - 1).to_double() * 12.0) /
                  per_row.to_double()).floor() - 0.5
    let cards : Array[@widget.Node] = []
    for i in 0..<app.core_hists.length() {
      cards.push(
        @ui.col(
          [
            @ui.row(
              [
                @ui.text(
                  "核心 \{i}",
                  font_size=12.0,
                  color="text_secondary",
                  wrap=false,
                ),
                @ui.text_dyn(
                  app.core_pct[i].signal(),
                  font_size=12.0,
                  color="text_primary",
                  align=@text.End,
                  wrap=false,
                  handle=fn(w) { w.node.set_flex_grow(1.0) },
                ),
              ],
              column_gap=6.0,
            ),
            @charts.line_chart_t(
              app.core_hists[i],
              width=card_w,
              height=96.0,
              y_range=Some((0.0, 100.0)),
              area=true,
              show_last=false,
            ),
          ],
          width=card_w,
          row_gap=4.0,
        ),
      )
    }
    @ui.col(
      [
        @ui.text("总利用率（%）", class=[@style.text_title]),
        @charts.line_chart_t(
          app.cpu_hist,
          height=180.0,
          y_range=Some((0.0, 100.0)),
          area=true,
        ),
        @ui.text("各逻辑核（%）", class=[@style.text_title]),
        @ui.row(
          cards,
          column_gap=12.0,
          align_items=@yoga.AlignItems::FlexStart,
          class=[@style.style(flex_wrap=@yoga.Wrap, row_gap=12.0, min_width=0.0)],
          handle=fn(w) { w.node.set_width(@yoga.percent(100.0)) },
        ),
      ],
      padding=12.0,
      row_gap=12.0,
      class=[@style.style(min_width=0.0)],
    )
  })
}

///|
/// 内存详情：物理内存曲线 + swap 曲线（自适应轴看细节）。
fn page_mem_detail(app : App) -> @widget.Node {
  @ui.col(
    [
      @ui.text("物理内存（GB）", class=[@style.text_title]),
      @charts.line_chart_t(app.mem_hist, height=200.0, area=true),
      @ui.text("swap（GB）", class=[@style.text_title]),
      @charts.line_chart_t(app.swap_hist, height=200.0, area=true),
    ],
    padding=12.0,
    row_gap=8.0,
    class=[@style.style(min_width=0.0)],
  )
}

///|
/// 双栏应用壳：左栏六项菜单 + 右栏详情页。手型光标套 cursor_group，
/// 组内任意位置（含菜单子控件）都是手型。
fn app_shell(app : App) -> @widget.Node {
  let view : @base.Store[ViewId] = @base.Store::new(VCpu)
  // 壳必须自己撑满窗口：主轴靠 flex_grow、交叉轴靠 align_self（外层 hbox
  // 默认 Center，不补这句会缩在窗口左上角）。
  @ui.cursor_group(
    [
      @ui.row(
        [left_pane(app, view), view_area(app, view)],
        grow=1.0,
        align_items=@yoga.AlignItems::Stretch,
      ),
    ],
    handle=fn(w : @widget.Widget) -> Unit {
      w.node.set_flex_grow(1.0)
      w.node.set_align_self(Some(@yoga.AlignItems::Stretch))
    },
  )
}
