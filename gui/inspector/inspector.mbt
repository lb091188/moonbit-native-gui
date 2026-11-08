// 内建 inspector v1(只读面板):「控件树 + 选中读数 + 帧耗时」三块。
//
// 数据源(全部现成,不碰 C 桩):
// - 控件树:`@widget.a11y_last_frame()` 帧尾语义快照(id/父/角色/名/状态/值/
//   正文/启用/窗口矩形;不可见子树整棵不在快照里,面板看到的与屏读一致);
// - 帧耗时:`@base.paint_profile_summary()` 累计账本(布局/绘制/上屏/最大帧)。
//
// 形态:表格列浏览(按父链缩进)+ 点行看读数;刷新手动或自动(自重排延时表,
// 与 tooltip/update_spinner 同一泵法)。快照是「上一帧」的只读账,面板不改树、
// 不装钩子,挂在应用任何位置都不干扰事件流。
//
// v1 边界:跨控件高亮框不做(面板嵌在内容里,浮层框会盖住自己);编辑回灌归
// v2(mngdev 通道);树不支持折叠(全展开滚动,快照本身就是扁平序)。

///|
/// 按父链算每个节点的深度(根 parent=0;父不在表里视作根;有环防护按表长截断)。
/// 返回与输入同长的深度表。纯函数,白盒用例钉住。
pub fn insp_depths(nodes : Array[@widget.A11yNode]) -> Array[Int] {
  let n = nodes.length()
  let idx : Map[Int, Int] = Map([])
  let mut i = 0
  while i < n {
    idx[nodes[i].id] = i
    i += 1
  }
  let out : Array[Int] = []
  let mut k = 0
  while k < n {
    let mut d = 0
    let mut cur = nodes[k].parent
    let mut steps = 0
    while steps < n {
      match idx.get(cur) {
        Some(pi) if pi != k => {
          d += 1
          cur = nodes[pi].parent
          steps += 1
        }
        _ => {
          steps = n
        }
      }
    }
    out.push(d)
    k += 1
  }
  out
}

///|
/// 树列的行文本:按深度缩进 + 角色 + 「名」+ #id(名空则不摆引号)。
pub fn insp_row_label(n : @widget.A11yNode, depth : Int) -> String {
  let b = StringBuilder()
  let mut i = 0
  while i < depth {
    b.write_string("  ")
    i += 1
  }
  b.write_string(n.role)
  if n.name.length() > 0 {
    b.write_string("「")
    b.write_string(n.name)
    b.write_string("」")
  }
  b.write_string(" #")
  b.write_string(n.id.to_string())
  b.to_string()
}

///|
/// 矩形读数文本(窗口坐标,取整):`x,y w×h`。
pub fn insp_rect_text(n : @widget.A11yNode) -> String {
  "\{n.x.round().to_int()},\{n.y.round().to_int()} \{n.w.round().to_int()}×\{n.h.round().to_int()}"
}

///|
/// 把快照折成表格行(列序:控件/角色/id/矩形);深度由 insp_depths 给。
/// 纯函数,白盒用例钉住。
pub fn insp_table_rows(nodes : Array[@widget.A11yNode]) -> Array[@ui.TableRow] {
  let depths = insp_depths(nodes)
  let out : Array[@ui.TableRow] = []
  let mut i = 0
  while i < nodes.length() {
    let n = nodes[i]
    out.push(
      @ui.TableRow::make([
        insp_row_label(n, depths[i]),
        n.role,
        n.id.to_string(),
        insp_rect_text(n),
      ]),
    )
    i += 1
  }
  out
}

///|
/// 选中节点的读数行(id/父/角色/名/状态/值/正文/启用/矩形);没选中给空表。
fn insp_detail_lines(n : @widget.A11yNode) -> Array[String] {
  [
    "id=\{n.id}  parent=\{n.parent}",
    "role=\{n.role}",
    if n.name.length() > 0 { "name=\{n.name}" } else { "name=(空)" },
    if n.state.length() > 0 { "state=\{n.state}" } else { "state=(无)" },
    if n.value.length() > 0 { "value=\{n.value}" } else { "value=(无)" },
    if n.text.length() > 0 { "text=\{n.text}" } else { "text=(无)" },
    if n.enabled { "enabled=true" } else { "enabled=false" },
    "rect=\{insp_rect_text(n)}",
  ]
}

///|
/// inspector v1 只读面板。`refresh_ms` 是自动刷新间隔(自动刷新关时不排表);
/// `auto` 给初始是否自动;`table_h` 是树表高度。挂在应用任何位置即可
/// (showcase 有整页演示);刷新读的是「上一帧」快照,起手先点一次「刷新」。
pub fn inspector_panel(
  refresh_ms? : Int = 500,
  auto? : Bool = false,
  table_h? : Double = 240.0,
  width? : Double = 640.0,
  class? : Array[@style.Style] = [],
) -> @widget.Node {
  // 行缓存(与表格行序一致)与选中下标(-1 = 无);快照每次刷新整表重填
  let cache : Ref[Array[@widget.A11yNode]] = Ref([])
  let selected : @base.Store[Array[Int]] = @base.Store::new([])
  let sel_tbl : @base.Store[Array[Int]] = @base.Store::new([])
  let rows : @base.Store[Array[@ui.TableRow]] = @base.Store::new([])
  let stats : @base.Store[String] = @base.Store::new(@i18n.t_or("gui.inspector.no_frame", "尚无帧快照——点「刷新」读一次"))
  fn do_refresh() -> Unit {
    let nodes = @widget.a11y_last_frame()
    cache.val = nodes
    rows.set(insp_table_rows(nodes))
    // 选中行在上一轮快照之外就清掉(树变了,旧下标不作数)
    let sel = sel_tbl.get()
    if sel.length() == 1 && sel[0] < nodes.length() {
      selected.set(sel)
    } else {
      selected.set([])
      sel_tbl.set([])
    }
    stats.set(
      @i18n.t_or("gui.inspector.stats", "节点 \{nodes.length()} · \{@base.paint_profile_summary()}"),
    )
  }
  // 自动刷新:自重排延时表(与 tooltip 同泵法);关表清延时
  let auto_on : @base.Store[Bool] = @base.Store::new(auto)
  let tid : Ref[Int] = Ref(0)
  let pump : Ref[() -> Unit] = Ref(fn() { () })
  pump.val = fn() -> Unit {
    do_refresh()
    tid.val = @shell.set_timeout(refresh_ms, pump.val)
  }
  auto_on.subscribe(fn(v : Bool) -> Unit {
    if v {
      if tid.val == 0 {
        (pump.val)()
      }
    } else if tid.val != 0 {
      @shell.clear_timeout(tid.val)
      tid.val = 0
    }
  })
  if auto_on.get() {
    // 挂载期宿主未就绪时 set_timeout 是空操作,泵在下一拍自续
    (pump.val)()
  }
  let cols : Array[@ui.TableColumn] = [
    @ui.TableColumn::make(@i18n.t_or("gui.inspector.col_widget", "控件"), 0.0, sortable=false),
    @ui.TableColumn::make(@i18n.t_or("gui.inspector.col_role", "角色"), 84.0, sortable=false),
    @ui.TableColumn::make("id", 52.0, sortable=false),
    @ui.TableColumn::make(@i18n.t_or("gui.inspector.col_rect", "矩形"), 132.0, sortable=false),
  ]
  // 「控件树」页签:v1 只读三件套(工具行/树表/选中读数)
  let tree_section = @ui.view(
    [
      @ui.row(
        [
          @ui.button(@i18n.t_or("gui.inspector.refresh", "刷新"), variant=@ui.Soft, on_click=do_refresh),
          @ui.switch(
            auto_on,
            on_text=@i18n.t_or("gui.inspector.auto_on", "自动刷新"),
            off_text=@i18n.t_or("gui.inspector.auto_off", "自动刷新"),
          ),
          @ui.button(@i18n.t_or("gui.inspector.reset_stats", "重置统计"), variant=@ui.Text, on_click=fn() {
            @base.paint_profile_reset()
            do_refresh()
          }),
        ],
        column_gap=8.0,
        align_items=@yoga.AlignItems::Center,
      ),
      @ui.bind_label(stats, fn(s) { s }),
      @ui.table_v(
        cols,
        rows,
        width=width,
        height=table_h,
        selection=sel_tbl,
        on_row_click=fn(i : Int, _r : @ui.TableRow) -> Unit {
          sel_tbl.set([i])
          selected.set([i])
        },
      ),
      @ui.text(@i18n.t_or("gui.inspector.detail_title", "选中控件"), weight=@text.SemiBold),
      @widget.bind_node(selected.signal(), fn(sel : Array[Int]) -> @widget.Node {
        match sel.get(0) {
          Some(i) if i < cache.val.length() => {
            let lines : Array[@widget.Node] = []
            for t in insp_detail_lines(cache.val[i]) {
              lines.push(@ui.text(t, font_size=12.0, class=[@style.text_secondary]))
            }
            @ui.view(
              lines,
              direction=@yoga.Column,
              row_gap=2.0,
              padding=8.0,
              background_color="bg_panel",
              border_color="border",
              corner_radius=6.0,
            )
          }
          _ =>
            @ui.text(
              @i18n.t_or("gui.inspector.no_selection", "点树里一行看读数"),
              font_size=12.0,
              color="text_secondary",
            )
        }
      }),
    ],
    direction=@yoga.Column,
    row_gap=10.0,
  )
  // 页签装配:两块都常驻(@ui.when_else 切显隐,零重建;树表的行缓存与
  // 类列表的快照各自独立),默认落在控件树。
  let tab_tree = @i18n.t_or("gui.inspector.tab_tree", "控件树")
  let tab_classes = @i18n.t_or("gui.inspector.tab_classes", "样式类")
  let tab : @base.Store[String] = @base.Store::new(tab_tree)
  let snap : Ref[Map[String, @style.Style]] = Ref(Map([]))
  let classes_section = insp_classes_section(width, (table_h * 0.7).max(140.0), snap)
  @ui.view(
    [
      @ui.segmented([tab_tree, tab_classes], tab),
      @ui.when_else(
        tab.signal(),
        tree_section,
        classes_section,
        pred=fn(t : String) -> Bool { t == tab_tree },
      ),
    ],
    direction=@yoga.Column,
    row_gap=10.0,
    class=class,
  )
}
