// 垂直滚动容器：视口裁剪 + 内容整块平移 + 浮层滚动条（滚轮、拖动、点条跳转）。
//
// 平移用布局引擎的相对定位（`position: relative` + `top: -offset`）而不是在
// 控件层另记一套偏移：相对偏移只改落位、不改常规流占位，正是滚动要的语义，
// 于是绘制与命中都跟着布局结果走（宿主每帧从 `collect_abs` 取绝对矩形），
// 组件层不需要第二份坐标换算。
//
// 滚动条是视口的**绝对定位子控件**（贴在右缘、覆盖在内容之上），不是画在视口
// 底色上——这样它才是命中路径上最深的那个控件，按下与拖动不会被内容里的按钮抢走。

///|
/// 滚动状态（引用语义）：偏移、内容高、视口高，以及组件挂上的「应用偏移」回调。
/// 调用方可以直接改它（`set_offset`/`scroll_to_bottom`），组件每帧按它现取。
pub(all) struct ScrollState {
  mut offset : Double
  mut content_h : Double
  mut view_h : Double
  /// 滚动条的「显形」位：指针在本视口内（含全部子项）或正按住拇指时为真，拇指
  /// 画满色；否则画淡档。由视口的悬停回调写入（见 `scroll_bar_hover`）。
  mut bar_hot : Bool
  /// 组件在挂载时写入：把当前 `offset` 落到内容节点的 `top` 并请求重绘。
  apply : Ref[() -> Unit]
  /// 横向档（`hscroll=true` 才启用）：横偏移与内容/视口宽，语义同纵向三件。
  mut offset_x : Double
  mut content_w : Double
  mut view_w : Double
  /// 横向版的「应用偏移」：把 `offset_x` 落到内容节点 `left` 并请求重绘。
  apply_x : Ref[() -> Unit]
}

///|
pub fn ScrollState::new() -> ScrollState {
  {
    offset: 0.0,
    content_h: 0.0,
    view_h: 0.0,
    bar_hot: false,
    apply: Ref(fn() { () }),
    offset_x: 0.0,
    content_w: 0.0,
    view_w: 0.0,
    apply_x: Ref(fn() { () }),
  }
}

///|
/// 可滚的最大横偏移（内容宽 - 视口宽，不足时为 0）。
pub fn ScrollState::max_x(self : ScrollState) -> Double {
  (self.content_w - self.view_w).max(0.0)
}

///|
/// 设横偏移：越界夹到 `[0, max_x]`，随后落布局并请求重绘。
pub fn ScrollState::set_offset_x(self : ScrollState, v : Double) -> Unit {
  let m = self.max_x()
  let nv = if v < 0.0 {
    0.0
  } else if v > m {
    m
  } else {
    v
  }
  if nv != self.offset_x {
    self.offset_x = nv
    (self.apply_x.val)()
  }
}

///|
/// 可滚的最大偏移（内容高 - 视口高，不足一屏时为 0）。
pub fn ScrollState::max(self : ScrollState) -> Double {
  (self.content_h - self.view_h).max(0.0)
}

///|
/// 当前偏移（已夹过的值）。
pub fn ScrollState::offset_y(self : ScrollState) -> Double {
  self.offset
}

///|
/// 设偏移：越界一律夹到 `[0, max]`，随后把新值落到布局上并请求重绘。
pub fn ScrollState::set_offset(self : ScrollState, v : Double) -> Unit {
  let m = self.max()
  let nv = if v < 0.0 {
    0.0
  } else if v > m {
    m
  } else {
    v
  }
  if nv != self.offset {
    self.offset = nv
    (self.apply.val)()
  }
}

///|
/// 相对滚动（`dy` 正=向下）。
pub fn ScrollState::scroll_by(self : ScrollState, dy : Double) -> Unit {
  self.set_offset(self.offset + dy)
}

///|
/// 滚到底（内容变化后调用可以把已越界的偏移拉回来）。
pub fn ScrollState::scroll_to_bottom(self : ScrollState) -> Unit {
  self.set_offset(self.max())
}

///|
/// 是否已滚到底部（容差 1px，避免浮点抖动）。
pub fn ScrollState::at_bottom(self : ScrollState) -> Bool {
  self.offset >= self.max() - 1.0
}

///|
/// 滚动条宽度（拇指宽；浮层档不画轨道）。
const SCROLL_BAR_W : Double = 8.0

///|
/// 拇指淡档不透明度：平时留一点痕迹便于定位，又不压住内容右缘。
const SCROLL_BAR_IDLE_ALPHA : Double = 0.15

///|
/// 浮层滚动条的显形接线：视口悬停（含全部子项，宿主按祖先链派发悬停态）时把
/// `state.bar_hot` 抬起，拇指画满色，离开落回淡档。`scroll_view` / `virt_list` /
/// 多行框建视口时各接一次。
pub fn scroll_bar_hover(viewport : @widget.Widget, state : ScrollState) -> Unit {
  viewport.on_hover_change = Some(fn(_w : @widget.Widget, on : Bool) -> Unit {
    if state.bar_hot != on {
      state.bar_hot = on
      @widget.invalidate()
    }
  })
}

///|
/// 滚动条控件（浮层档：绝对贴在视口右缘、与视口同高，只画拇指）：拇指长度按
/// 视口/内容比例、下限 16px 便于抓，点条跳转、按住拖动（拇指中心跟随指针）、松手即止。
/// `scroll_view` 与 `virt_list` 共用。
fn scroll_bar(state : ScrollState) -> @widget.Widget {
  let bar = @widget.Widget::new()
  bar.node.set_position(@yoga.Absolute)
  bar.node.set_top(@yoga.fixed(0.0))
  bar.node.set_bottom(@yoga.fixed(0.0))
  bar.node.set_right(@yoga.fixed(0.0))
  bar.node.set_width(@yoga.fixed(SCROLL_BAR_W))
  let dragging = Ref(false)
  bar.on_draw = Some(fn(
    _self : @widget.Widget,
    p : @render.Painter,
    r : @base.Rect,
  ) -> Unit {
    let vh = state.view_h
    let ch = state.content_h
    // 只在真能滚的时候画（拇指长度按视口/内容比例）
    if ch > vh && vh > 0.0 {
      // 轨道不画（那条整高的灰带会压住内容右缘），拇指按显形位分两档：
      // 悬停/拖动满色，平时淡到 `SCROLL_BAR_IDLE_ALPHA`
      let hot = state.bar_hot || dragging.val
      p.set_global_alpha(if hot { 1.0 } else { SCROLL_BAR_IDLE_ALPHA })
      let thumb = (r.h * vh / ch).max(16.0)
      let travel = (r.h - thumb).max(0.0)
      let ratio = state.offset / (ch - vh)
      p.set_fill_color(@theme.theme_border())
      // 拇指胶囊形（几何取圆，不随圆角开关变方）
      p.fill_round_rect(1.0, ratio * travel, r.w - 2.0, thumb, (r.w - 2.0) / 2.0)
      p.set_global_alpha(1.0)
    }
  })
  bar.on_pointer = Some(fn(
    self : @widget.Widget,
    ev : @widget.PointerEvent,
  ) -> Bool {
    let vh = self.rect.h
    let m = state.max()
    let thumb = (vh * vh / state.content_h).max(16.0)
    let travel = (vh - thumb).max(0.0)
    // 把指针 y 换算成偏移：拇指中心跟随指针（写成闭包值，块中段不放裸 fn 声明）
    let y_to_offset : (Double) -> Double = fn(y : Double) -> Double {
      if travel <= 0.0 {
        0.0
      } else {
        ((y - thumb / 2.0) / travel).clamp(min=0.0, max=1.0) * m
      }
    }

    match ev.kind {
      @widget.PointerKind::Down => {
        dragging.val = true
        state.set_offset(y_to_offset(ev.y))
        true
      }
      @widget.PointerKind::Move => {
        if dragging.val {
          state.set_offset(y_to_offset(ev.y))
        }
        true
      }
      @widget.PointerKind::Up => {
        dragging.val = false
        true
      }
      @widget.PointerKind::Leave => false
    }
  })
  bar
}

///|
/// 横向滚动条（浮层档：绝对贴在视口底缘、与视口同宽，只画拇指）：几何与交互
/// 全部按纵向条的横轴镜像。
fn scroll_bar_h(state : ScrollState) -> @widget.Widget {
  let bar = @widget.Widget::new()
  bar.node.set_position(@yoga.Absolute)
  bar.node.set_left(@yoga.fixed(0.0))
  bar.node.set_right(@yoga.fixed(0.0))
  bar.node.set_bottom(@yoga.fixed(0.0))
  bar.node.set_height(@yoga.fixed(SCROLL_BAR_W))
  let dragging = Ref(false)
  bar.on_draw = Some(fn(
    _self : @widget.Widget,
    p : @render.Painter,
    r : @base.Rect,
  ) -> Unit {
    let vw = state.view_w
    let cw = state.content_w
    if cw > vw && vw > 0.0 {
      let hot = state.bar_hot || dragging.val
      p.set_global_alpha(if hot { 1.0 } else { SCROLL_BAR_IDLE_ALPHA })
      let thumb = (r.w * vw / cw).max(16.0)
      let travel = (r.w - thumb).max(0.0)
      let ratio = state.offset_x / (cw - vw)
      p.set_fill_color(@theme.theme_border())
      p.fill_round_rect(ratio * travel, 1.0, thumb, r.h - 2.0, (r.h - 2.0) / 2.0)
      p.set_global_alpha(1.0)
    }
  })
  bar.on_pointer = Some(fn(
    self : @widget.Widget,
    ev : @widget.PointerEvent,
  ) -> Bool {
    let vw = self.rect.w
    let m = state.max_x()
    let thumb = (vw * vw / state.content_w).max(16.0)
    let travel = (vw - thumb).max(0.0)
    let x_to_offset : (Double) -> Double = fn(x : Double) -> Double {
      if travel <= 0.0 {
        0.0
      } else {
        ((x - thumb / 2.0) / travel).clamp(min=0.0, max=1.0) * m
      }
    }
    match ev.kind {
      @widget.PointerKind::Down => {
        dragging.val = true
        state.set_offset_x(x_to_offset(ev.x))
        true
      }
      @widget.PointerKind::Move => {
        if dragging.val {
          state.set_offset_x(x_to_offset(ev.x))
        }
        true
      }
      @widget.PointerKind::Up => {
        dragging.val = false
        true
      }
      @widget.PointerKind::Leave => false
    }
  })
  bar
}

///|
/// 垂直滚动容器：`height` 是视口高（0 = 由父容器给），内容按自然高度排布并可
/// 超出视口；超出部分被裁剪，滚动条画在右缘。
/// `hscroll=true` 开横向档，内容宽有两档：
/// - 缺省（`min_content_width=0`）= 自然宽档：`max(子项自然宽, 视口宽)`，给
///   代码长行/表格这类不可折内容用；
/// - 给了 `min_content_width` = 下限档：`max(min_content_width, 视口宽)`，
///   **不取子项自然宽**——子项更宽时由它自己的滚动负责，这个 min-width 才是
///   唯一说了算的数。
pub fn scroll_view(
  children : Array[@widget.Node],
  state : ScrollState,
  width? : Double = 0.0,
  height? : Double = 0.0,
  hscroll? : Bool = false,
  min_content_width? : Double = 0.0,
  class? : Array[@style.Style] = [],
  handle? : (@widget.Widget) -> Unit = default_handle,
) -> @widget.Node {
  @widget.node_of_new(fn(viewport : @widget.Widget) -> @widget.Widget {
    watch_theme()
    viewport.node.set_flex_direction(@yoga.Column)
    // 视口必须能缩到父给的尺寸：Yoga 的 flex 子项默认 min-size 为 auto，不写这两条
    // 视口会被内容顶到自然高（内容多高它就多高），`max()` 恒为 0——真机表现就是
    // 「内容超出窗口却滚不动」。
    viewport.node.set_min_height(@yoga.fixed(0.0))
    viewport.node.set_min_width(@yoga.fixed(0.0))
    // 散参数折进匿名块（class 在后即覆盖，§1.5 唯一去向）。内置描边必须
    // **折进同一趟合并**——曾经 fold 之后又无条件 apply 一次内置描边，后写
    // 赢，把 class 给的 border_color 冲掉（class 覆盖语义被组件内后置 apply
    // 破坏，virtlist_wbtest「class 覆盖视口描边」抓红即此因）。
    let lay = @style.empty_style()
    if width > 0.0 {
      lay.width = Some(width)
    }
    if height > 0.0 {
      lay.height = Some(height)
    }
    fold_style(
      viewport,
      @style.merge_all([
        @style.style(border_color="border", border_width=1.0),
        lay,
      ]),
      class,
    )
    let content = @widget.Widget::new()
    content.node.set_flex_direction(@yoga.Column)
    content.node.set_position(@yoga.Relative)
    // 不收缩：内容必须按自然高度撑开，超出视口的部分才谈得上滚动
    content.node.set_flex_shrink(0.0)
    if hscroll {
      // 横向档：`align_self FlexStart` 退掉交叉轴 stretch，让内容可比视口宽
      content.node.set_align_self(Some(@yoga.AlignItems::FlexStart))
      content.node.set_left(@yoga.fixed(0.0 - state.offset_x))
      if min_content_width > 0.0 {
        // 下限档：内容宽 = max(min_content_width, 视口宽)，不看子项自然宽
        content.node.set_width(@yoga.percent(100.0))
        content.node.set_min_width(@yoga.fixed(min_content_width))
      } else {
        // 自然宽档：内容宽 = max(自然宽, 视口宽)——缺视口下限时内部 percent
        // 子项（表格等分列）没有确定参照（真机 markdown 表格 resize 不重排）
        content.node.set_min_width(@yoga.percent(100.0))
      }
    } else {
      content.node.set_width(@yoga.percent(100.0))
    }
    content.node.set_top(@yoga.fixed(0.0 - state.offset))
    @widget.mount_children(content, children)
    viewport.append_child(content)
    state.apply.val = fn() -> Unit {
      content.node.set_top(@yoga.fixed(0.0 - state.offset))
      @widget.invalidate()
    }
    state.apply_x.val = fn() -> Unit {
      content.node.set_left(@yoga.fixed(0.0 - state.offset_x))
      @widget.invalidate()
    }

    viewport.append_child(scroll_bar(state))
    if hscroll {
      viewport.append_child(scroll_bar_h(state))
    }
    scroll_bar_hover(viewport, state)
    viewport.on_draw = Some(fn(
      self : @widget.Widget,
      p : @render.Painter,
      r : @base.Rect,
    ) -> Unit {
      // 布局已定：把几何抄给状态（滚动条比例与夹取都用它），再画一层描边
      state.view_h = r.h
      state.content_h = content.rect.h
      state.view_w = r.w
      state.content_w = content.rect.w
      if state.content_h > state.view_h {
        let st = @style.style_for(self)
        p.set_stroke_color(@style.color_of(st.border_color, @theme.theme_border()))
        p.set_line_width(@style.number_of(st.border_width, 1.0))
        p.stroke_rect(0.0, 0.0, r.w, r.h)
      }
    })
    viewport.on_scroll = Some(fn(ev : @widget.ScrollEvent) -> Bool {
      // 横向分量(触控板横滑/滚轮 dx)先走;有横滚余量时消费掉,不混进纵向
      if hscroll && ev.dx != 0.0 && state.max_x() > 0.0 {
        let bx = state.offset_x
        state.set_offset_x(bx - ev.dx * 30.0)
        if state.offset_x != bx {
          return true
        }
      }
      let before = state.offset
      // 一格滚 3 行（与常见桌面滚动量同量级），dy 正=向上滚
      state.scroll_by(0.0 - ev.dy * 30.0)
      state.offset != before
    })
    handle(viewport)
    viewport
  })
}
