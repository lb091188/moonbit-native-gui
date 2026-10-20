// link 面：路由只回答「点了往哪儿走」，载体爱是谁就是谁——菜单项、段条、面包屑、
// 表格行、按钮、原生菜单项、快捷键都接这一个口子。

///|
/// 点击导航闭包：任何组件的 `on_click` 都能直接接。
pub fn Router::on_link(self : Router, path : String) -> () -> Unit {
  fn() -> Unit { self.goto(path) }
}

///|
/// 给任意节点套一层「点它 = 导航」：不动外观，只在套壳容器上接指针。认领口径与库内
/// 导航项一致：按下认领、在框内抬起才算点中（`gui/ui/nav.mbt:119`）。
pub fn Router::route_link(self : Router, path : String, node : @widget.Node) -> @widget.Node {
  let work = self.on_link(path)
  @ui.col(
    [node],
    handle=fn(w : @widget.Widget) -> Unit {
      w.on_pointer = Some(fn(
        self_w : @widget.Widget,
        ev : @widget.PointerEvent,
      ) -> Bool {
        match ev.kind {
          @widget.PointerKind::Down => true
          @widget.PointerKind::Up => {
            let inside = ev.x >= 0.0 && ev.x <= self_w.rect.w &&
              ev.y >= 0.0 && ev.y <= self_w.rect.h
            if inside {
              work()
              @widget.invalidate()
            }
            false
          }
          _ => false
        }
      })
    },
  )
}

///|
/// 路径前 i 段（面包屑每段要导航到的那条路径）。
fn join_upto(parts : Array[String], i : Int) -> String {
  let mut out = ""
  for k in 0..<i {
    let p = parts[k]
    out = if out == "" { p } else { out + "/" + p }
  }
  out
}

///|
/// 面包屑的一行：逐段可点，点第 i 段 = 走到那一段（深层自动回落到各自首项）；
/// 末段是当前项，不给点击。
fn Router::crumb_row(self : Router, p : String) -> @widget.Node {
  let parts : Array[String] = []
  for s in p.split("/") {
    parts.push(s.to_owned())
  }
  let items : Array[@widget.Node] = []
  let n = parts.length()
  for i in 0..<n {
    if i > 0 {
      items.push(@ui.text(" / ", role=@ui.Secondary))
    }
    let seg = parts[i]
    let target = join_upto(parts, i + 1)
    items.push(if i + 1 == n {
      @ui.text(seg, role=@ui.Body)
    } else {
      @ui.link(seg, self.on_link(target))
    })
  }
  @ui.row(items, column_gap=4.0)
}

///|
/// 面包屑（随当前路径重画）：数据源就是一个 `computed(self.path())`，重挂复用
/// `@widget.bind_node`——它每次重建走整代退订再挂（`gui/widget/node.mbt:92`），
/// 不在本包里另造一套刷新机制。
pub fn Router::breadcrumb(self : Router) -> @widget.Node {
  let crumb = @base.Signal::computed(fn() -> String { self.path() })
  @widget.bind_node(crumb, fn(p : String) -> @widget.Node { self.crumb_row(p) })
}

///|
/// 段条形态的入口载体：这一层候选一条 `segmented`，写这一层的选中键。
/// 候选集在分支自己的子槽里是静态的（子槽随分支挂载才构造），所以不需要
/// 「随父层换候选表」——那件事由子槽重新构造承担。
/// `label_of` 只改显示（本地化路由名），键仍是 `selected` 槽里的取值。
pub fn Router::strip_at(
  self : Router,
  depth : Int,
  candidates : Array[Route],
  label_of? : (String) -> String = fn(k) { k },
) -> @widget.Node {
  let names : Array[String] = []
  for r in candidates {
    names.push(r.key)
  }
  @ui.segmented(names, self.store_at(depth), label_of=label_of)
}

///|
/// 带段条的整棵视图：分支内容前面放这一层的 `segmented`。
pub fn Router::view_strip(self : Router) -> @widget.Node {
  self.view(Some(fn(
    ro : Router,
    d : Int,
    _p : String,
    cs : Array[Route],
  ) -> @widget.Node { ro.strip_at(d, cs) }))
}

///|
/// 侧栏便利函数（不在核心面上）：把第 0 层的候选按分组交给 `@ui.menu_sections`，
/// 绑的就是 `store_at(0)`，所以侧栏与段条、面包屑共享同一份导航状态。
pub fn Router::sidebar(
  self : Router,
  groups : Array[(String, Array[String])],
  icons? : Array[(String, @icons.IconKind)] = [],
  labels? : Array[(String, String)] = [],
  label_of? : (String) -> String = fn(_k) { "" },
  width? : Double = 180.0,
) -> @widget.Node {
  @ui.menu_sections(
    groups,
    self.store_at(0),
    icons=icons,
    labels=labels,
    label_of=label_of,
    width=width,
  )
}
