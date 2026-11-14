// 声明式层 L1 构造器：让页面与示例「调用点不变、只换实现」的那一层。
//
// 新栈的组件本身就返回 `@widget.Node`，所以与组件**同名**的构造器（`label` /
// `button` / `input` / `checkbox` / `container` / `group` / `separator` /
// `image` / `icon` / `radio_group` / `slider` / `progress`）不再另包一层——
// 直接用组件即可。这里只补三类东西：
// ① 别名构造器（`vbox`/`hbox`/`text_edit`/`select`/`scroll`/`tab`/`date_picker`）；
// ② 声明式入口（`mount_window`）与文本绑定（`bind_label`/`bind`）；
// ③ `hover_group`（悬停组）。
//
// 三条机制口径：
// - `hover_group`：宿主的悬停态是父链语义（指针在子项上时父项也算悬停），读
//   `hovered` 即可，没有定时器也没有轮询。
// - `overlay_scroll` 就是 `scroll_view`：滚动条是视口的绝对定位子控件、覆盖在
//   内容之上，不需要第二套形态。
// - `cursor_group`：光标是窗口级的一层，宿主按悬停路径取「最深的那个请求」，组
//   只设自己一处，子孙没提请求时自然回退到它。
//
// §2「事件参数统一 on_*」审计口径（P2-b）：组件库全部**事件**回调参数已是
// `on_*` 形态（on_click/on_change/on_enter/on_pick/on_response/on_dismiss/
// on_link/on_drop…）；`handle?` 保留为句柄逃生舱（不是事件）。非事件函数参数
// 只剩谓词/能力型五个：drag 的 `payload`/`accept`、输入框的 `caret_on`、
// shell 定时器钩子的 `cancel`，不进 on_* 改名。

///|
/// 垂直布局容器（`container` 的 Column 形态）。
pub fn col(
  /// 装进容器的子节点，按主轴方向依次排。
  children : Array[@widget.Node],
  /// 拉开纵向相邻子节点的间隙。
  row_gap~ : Double = 0.0,
  /// 内缩四边同宽的内边距。
  padding~ : Double = 0.0,
  /// 定死宽度，0 = 按内容测量。
  width~ : Double = 0.0,
  /// 定死高度，0 = 按内容测量。
  height~ : Double = 0.0,
  /// 按父容器主轴余量占位，0 = 不参与分配。
  grow~ : Double = 0.0,
  /// 画底色（主题色名或 `#rrggbb`），空串不画。
  background_color~ : String = "",
  /// 描一圈边色，空串不描边。
  border_color~ : String = "",
  /// 让子节点在交叉轴上按此对齐。
  align_items~ : @yoga.AlignItems = @yoga.AlignItems::Stretch,
  /// 挂命名样式类（`class_of([...])`）；类排在散参数之后，覆盖散参数。
  class~ : Array[@style.Style] = [],
  /// 挂载后把宿主 Widget 句柄交给调用方（逃生舱）。
  handle~ : (@widget.Widget) -> Unit = default_handle,
) -> @widget.Node {
  view(
    children,
    direction=@yoga.Column,
    row_gap~,
    padding~,
    width~,
    height~,
    grow~,
    background_color~,
    border_color~,
    align_items~,
    class~,
    handle~,
  )
}

///|
/// 水平布局容器（`container` 的 Row 形态）。
pub fn row(
  /// 装进容器的子节点，按主轴方向依次排。
  children : Array[@widget.Node],
  /// 拉开横向相邻子节点的间隙。
  column_gap~ : Double = 0.0,
  /// 内缩四边同宽的内边距。
  padding~ : Double = 0.0,
  /// 定死宽度，0 = 按内容测量。
  width~ : Double = 0.0,
  /// 定死高度，0 = 按内容测量。
  height~ : Double = 0.0,
  /// 按父容器主轴余量占位，0 = 不参与分配。
  grow~ : Double = 0.0,
  /// 画底色（主题色名或 `#rrggbb`），空串不画。
  background_color~ : String = "",
  /// 描一圈边色，空串不描边。
  border_color~ : String = "",
  /// 让子节点在交叉轴上按此对齐，缺省 Stretch——子项撑满行高。
  align_items~ : @yoga.AlignItems = @yoga.AlignItems::Stretch,
  /// 挂命名样式类（`class_of([...])`）；类排在散参数之后，覆盖散参数。
  class~ : Array[@style.Style] = [],
  /// 挂载后把宿主 Widget 句柄交给调用方（逃生舱）。
  handle~ : (@widget.Widget) -> Unit = default_handle,
) -> @widget.Node {
  view(
    children,
    direction=@yoga.Row,
    column_gap~,
    padding~,
    width~,
    height~,
    grow~,
    background_color~,
    border_color~,
    align_items~,
    class~,
    handle~,
  )
}

///|
/// §2 合并:`text_edit` 就是真身(原声明式包装删除,调用点直接用 `@ui.textarea`)。

///|
/// §2 合并:`select`/`combo` 旧入口消失,选择器唯一入口是 `select`（可输入走 `editable=true`）。

///|
/// §2 合并:`scroll` 旧包装删除——滚动容器唯一入口就是 `ui/scroll.mbt` 的 `scroll_view`。

///|
/// §2 合并：`tab` 旧入口消失，页签唯一入口是 `tabs`。

///|
/// §2 合并:`date_picker` 就是真身(原声明式包装删除,调用点直接用 `@ui.date_picker`)。

///|
/// 声明式文本绑定：初值 `f(store.get())`，之后每次 `set` 就地更新文本并重测
/// （只重算这一条链，不重建子树）。文本恒单行（`wrap=false`）：自动换行在
/// 横向容器里会被压成两行。
pub fn[A] bind_label(
  store : @base.Store[A],
  f : (A) -> String,
  font_size~ : Double = 13.0,
  color~ : String = "",
  class~ : Array[@style.Style] = [],
  handle~ : (@widget.Widget) -> Unit = default_handle,
) -> @widget.Node {
  bind(store.signal(), f, font_size~, color~, class~, handle~)
}

///|
/// 声明式文本绑定（信号版）：源信号或 `computed` 派生信号都能直接喂。
pub fn[A] bind(
  sig : @base.Signal[A],
  f : (A) -> String,
  font_size~ : Double = 13.0,
  color~ : String = "",
  class~ : Array[@style.Style] = [],
  handle~ : (@widget.Widget) -> Unit = default_handle,
) -> @widget.Node {
  let src = text_source(
    f(sig.get()),
    font_size~,
    color~,
    wrap=false,
    ellipsis=true,
  )
  @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget {
    watch_theme()
    if class.length() > 0 {
      fold_style(w, @style.empty_style(), @style.empty_style(), class)
    }
    // 单行档口径（同 text_dyn 的 wrap=false）：下限归 0，挤不过兄弟件时
    // 收缩、末端出省略号。
    w.node.set_min_width(@yoga.fixed(0.0))
    // 初值文本进 label（文本面，定位面 name 归 .named；relabel 同步写回）
    w.label = src.text
    attach_text_measure(w, src)
    w.on_draw = Some(fn(
      _s : @widget.Widget,
      p : @render.Painter,
      _r : @base.Rect,
    ) -> Unit {
      let _ = draw_text_in(w, p, src)
    })
    let sid = sig.subscribe(fn(v : A) -> Unit { relabel(w, src, f(v)) })
    @base.sub_bag_register(fn() { sig.remove(sid) })
    handle(w)
    w
  })
}

///|
/// 悬停组：组内任意位置（含全部子控件）悬停即整组进入悬停态并换底色，
/// 点击（按下后松开仍在组内）触发 `on_click`。
///
/// 宿主的悬停态本身就是父链语义，所以这里既不排定时器也不查指针。
pub fn hover_group(
  children : Array[@widget.Node],
  on_click~ : () -> Unit = fn() -> Unit { () },
  padding~ : Double = 8.0,
  row_gap~ : Double = 4.0,
  width~ : Double = 0.0,
  background_color~ : String = "",
  hover_bg~ : String = "",
  class~ : Array[@style.Style] = [],
  handle~ : (@widget.Widget) -> Unit = default_handle,
) -> @widget.Node {
  let base_bg = background_color
  let lit_bg = hover_bg
  // 对外的布局散参数折进属性层（class / style 能盖过它们）；0 视为没给
  let attrs = @style.empty_style()
  if row_gap > 0.0 {
    attrs.row_gap = Some(row_gap)
  }
  if padding > 0.0 {
    attrs.padding_left = Some(padding)
    attrs.padding_right = Some(padding)
    attrs.padding_top = Some(padding)
    attrs.padding_bottom = Some(padding)
  }
  if width > 0.0 {
    attrs.width = Some(width)
  }
  @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget {
    watch_theme()
    // 内部布局，不对外样式化：列方向与「子件按内容起排」是组件形态本身
    w.node.set_flex_direction(@yoga.Column)
    w.node.set_align_items(@yoga.AlignItems::FlexStart)
    w.cursor = @widget.CURSOR_HAND
    w.on_draw = Some(fn(
      self : @widget.Widget,
      p : @render.Painter,
      r : @base.Rect,
    ) -> Unit {
      let fill = if self.hovered {
        if lit_bg.length() > 0 {
          lit_bg
        } else {
          @theme.theme_fill_hover()
        }
      } else if base_bg.length() > 0 {
        base_bg
      } else {
        @theme.theme_bg_panel()
      }
      p.set_fill_color(fill)
      let rad = @theme.radius_card()
      if rad > 0.0 {
        p.fill_round_rect(0.0, 0.0, r.w, r.h, rad)
      } else {
        p.fill_rect(0.0, 0.0, r.w, r.h)
      }
      p.set_stroke_color(@theme.theme_border())
      p.set_line_width(1.0)
      if rad > 0.0 {
        p.round_rect_path(0.5, 0.5, r.w - 1.0, r.h - 1.0, rad)
        p.stroke()
      } else {
        p.stroke_rect(0.0, 0.0, r.w, r.h)
      }
    })
    w.on_pointer = Some(fn(
      self : @widget.Widget,
      ev : @widget.PointerEvent,
    ) -> Bool {
      match ev.kind {
        @widget.PointerKind::Down => true
        @widget.PointerKind::Up => {
          if ev.x >= 0.0 &&
            ev.x <= self.rect.w &&
            ev.y >= 0.0 &&
            ev.y <= self.rect.h {
            on_click()
          }
          false
        }
        _ => false
      }
    })
    @widget.mount_children(w, children)
    fold_style(w, @style.empty_style(), attrs, class)
    handle(w)
    w
  })
}

///|
/// 声明一棵 UI 树并装进窗口：建宿主（窗口 + 事件循环 + 浮层图层 + 输入法通道
/// 都在 `WindowHost::new` 里就位）、挂载子节点、把宿主交给调用方 `run`。
/// 无显示服务时返回 None（调用方打印提示即可，与 `WindowHost::new` 同口径）。
///
/// 窗口居中由 WM 决定、关闭只把宿主循环停下，故不提供 `center` / `on_close`，
/// 退出后的收尾写在调用方 `run()` 之后。
///
/// 主题默认接线：进程内首次挂窗自动探测一次系统深浅与主色并应用；此前
/// 显式 `theme_apply` 过（含已接 `follow_system_theme`）则不覆盖。持续跟随
/// 仍是 opt-in（`WindowHost::follow_system_theme`）。
pub fn mount_window(
  children : Array[@widget.Node],
  title~ : String = "",
  width~ : Int32 = 800,
  height~ : Int32 = 600,
  handle~ : (@widget.WindowHost) -> Unit = fn(_a : @widget.WindowHost) -> Unit {
    ()
  },
) -> @widget.WindowHost? {
  let _ = @widget.theme_apply_system_once()
  match @widget.WindowHost::new(width, height, title) {
    None => None
    Some(app) => {
      app.mount(children)
      handle(app)
      // 单实例唤起泵（库级）：应用 claim 过实例就自动抽件——mac 套接字臂 /
      // Win32 臂的唤醒参数靠它落地，第二实例唤首实例（生产特性）与 dev 的
      // --mng-hot/page/theme 通道共用。没 claim 的应用不排此泵，零开销；
      // claim 需在挂载前完成（入口惯例）。
      if @shell.instance_armed() {
        let wake_pump : Ref[() -> Unit] = Ref(fn() { () })
        wake_pump.val = fn() -> Unit {
          if @shell.instance_armed() {
            let _ = @shell.dispatch_instance_wake()
            let _ = app.timer(200, wake_pump.val)
          }
        }
        (wake_pump.val)()
      }
      Some(app)
    }
  }
}

///|
/// 挂载一扇窗（**render 槽**形态，design.md §4.0 与静态节点数组二选一）：
/// `render` 在挂载时调用**一次**建首帧，此后框架不再重跑它——响应全靠树里
/// 收 Signal 的入口自订阅自差分（`for_list` 管列表差分、`when` 管显隐、
/// `*_dyn` 管展示文本），整棵换内容才走 `bind_node`。
pub fn mount_window_render(
  render : () -> Array[@widget.Node],
  title~ : String = "",
  width~ : Int32 = 800,
  height~ : Int32 = 600,
  handle~ : (@widget.WindowHost) -> Unit = fn(_a : @widget.WindowHost) -> Unit {
    ()
  },
) -> @widget.WindowHost? {
  mount_window(render(), title~, width~, height~, handle~)
}

///|
/// 光标组：组内任意位置都用 `cursor` 指定的形状（默认手型）。
/// 宿主取的是悬停路径上**最深的那个非零请求**，所以组内某个子件自己提了形状
/// （比如卡片里那颗按钮）时以它为准，其余位置回退到组的形状。
pub fn cursor_group(
  children : Array[@widget.Node],
  direction~ : @yoga.FlexDirection = @yoga.Column,
  row_gap~ : Double = 0.0,
  column_gap~ : Double = 0.0,
  padding~ : Double = 0.0,
  width~ : Double = 0.0,
  cursor~ : Int32 = @widget.CURSOR_HAND,
  handle~ : (@widget.Widget) -> Unit = default_handle,
) -> @widget.Node {
  view(children, direction~, row_gap~, column_gap~, padding~, width~, handle=fn(
    w : @widget.Widget,
  ) -> Unit {
    w.cursor = cursor
    handle(w)
  })
}
