// 虚拟列表与虚拟表格：只挂载可见区间（±overscan）的行，滚轮与滚动条都驱动
// 同一个 `ScrollState`（与 `scroll_view` 同款，共用 `scroll_bar`）。
//
// 两档行高：
// - 固定档（`row_height > 0`）：下标乘行高直接定位，零测量成本；`table_v` 走这档。
// - 可变档（`row_height <= 0`）：先按 `row_height_estimate` 预估排版，行挂载后
//   从布局实测回写高度，前缀和重算窗口；估高与实测差超 1px 才多排一帧，收敛即停。

///|
/// 二分定位：最大的 `i` 使 `prefix[i] <= offset`（`prefix[0] = 0`）。
fn virt_window_index(prefix : Array[Double], offset : Double) -> Int32 {
  let n = prefix.length() - 1
  if n <= 0 {
    return 0
  }
  let mut lo = 0
  let mut hi = n - 1
  while lo < hi {
    let mid = (lo + hi + 1) / 2
    if prefix[mid] <= offset {
      lo = mid
    } else {
      hi = mid - 1
    }
  }
  lo
}

///|
/// 虚拟列表：`items` 变、窗口滚过一行边界、视口尺寸变化都会重挂可见区间。
/// `row_of(i, item)` 造第 i 行的节点（`i` 是**源下标**，排序/过滤由调用方决定顺序）。
/// 行高固定走 `row_height`；行高可变传 `row_height = 0` 并用 `row_height_estimate`
/// 给估高（缺省 30），挂载后自动实测收敛。
pub fn[T] virt_list(
  items : @base.Store[Array[T]],
  height : Double,
  row_height : Double,
  row_of : (Int32, T) -> @widget.Node,
  width~ : Double = 0.0,
  overscan~ : Int32 = 2,
  row_height_estimate~ : Double = 0.0,
  rev? : @base.Store[Int32],
  class~ : Array[@style.Style] = [],
  handle~ : (@widget.Widget) -> Unit = default_handle,
) -> @widget.Node {
  let fixed = row_height > 0.0
  let rh = if fixed {
    row_height
  } else if row_height_estimate > 0.0 {
    row_height_estimate
  } else {
    30.0
  }
  @widget.node_of_new(fn(viewport : @widget.Widget) -> @widget.Widget {
    watch_theme()
    viewport.kind = "ui-virt-list"
    let lay = @style.empty_style()
    lay.flex_direction = Some(@yoga.Column)
    // 视口显式 overflow:hidden：控件层默认不裁，滚出视口的行不落
    lay.overflow = Some(@style.Hidden)
    if width > 0.0 {
      lay.width = Some(width)
    }
    lay.height = Some(height)
    @style.apply(viewport, @style.merge_all([lay, @style.merge_all(class)]))
    let state = ScrollState::new()
    let inner = @widget.Widget::new()
    // 检查器树行可读：内容容器报自己的类型名（role 留空，纯布局壳不进语义树）
    inner.kind = "ui-virt-list-content"
    inner.node.set_flex_direction(@yoga.Column)
    inner.node.set_width(@yoga.percent(100.0))
    // 整块跟着偏移平移（与 `scroll_view` 同一套相对定位）：上占位只补「窗口第一行
    // 到内容原点」的差额，真偏移量由 top 承担——少了这步，占位会把可见行越推越下，
    // 视口上沿先空、随后整屏空白。
    inner.node.set_position(@yoga.Relative)
    inner.node.set_flex_shrink(0.0)
    inner.node.set_top(@yoga.fixed(0.0 - state.offset))
    viewport.append_child(inner)
    // 当前窗口（源下标区间）与窗口重建
    let win_first : Ref[Int32] = Ref(-1)
    let win_last : Ref[Int32] = Ref(-1)
    let total : Ref[Int32] = Ref(0)
    // 可变档状态：实测行高（0 = 未测）与前缀和（prefix[0] = 0，长度 count + 1）
    let heights : Ref[Array[Double]] = Ref(Array::make(0, 0.0))
    let prefix : Ref[Array[Double]] = Ref(Array::make(1, 0.0))
    let mounted : Ref[Array[(Int32, @widget.Widget)]] = Ref([])
    let eff_h = fn(i : Int32) -> Double {
      let hs = heights.val
      if i >= 0 && i < hs.length() && hs[i] > 0.0 {
        hs[i]
      } else {
        rh
      }
    }
    let rebuild_prefix = fn() -> Unit {
      if fixed {
        return
      }
      let n = total.val
      let p = Array::make(n + 1, 0.0)
      let mut i = 0
      while i < n {
        p[i + 1] = p[i] + eff_h(i)
        i = i + 1
      }
      prefix.val = p
    }
    let sync_heights = fn(count : Int32) -> Unit {
      if heights.val.length() == count {
        return
      }
      let old = heights.val
      let nh = Array::make(count, 0.0)
      let keep = if old.length() < count { old.length() } else { count }
      let mut i = 0
      while i < keep {
        nh[i] = old[i]
        i = i + 1
      }
      heights.val = nh
      rebuild_prefix()
    }
    let content_height = fn(count : Int32) -> Double {
      if fixed {
        count.to_double() * rh
      } else {
        prefix.val[count]
      }
    }
    let render_window = fn(force : Bool) -> Unit {
      // 偏移先落布局：窗口区间没变但偏移在行内变化（半行滚动）时也要跟手
      inner.node.set_top(@yoga.fixed(0.0 - state.offset))
      let count = items.get().length()
      total.val = count
      sync_heights(count)
      // 可变档：上一帧已布局的行就是实测来源——先回写再算窗口，零定时器
      if !fixed && mounted.val.length() > 0 {
        let mut changed = false
        for pair in mounted.val {
          let idx = pair.0
          let h = pair.1.rect.h
          if idx >= 0 && idx < count {
            let cur = heights.val[idx]
            if h > 0.5 && (cur <= 0.0 || (h - cur) > 1.0 || (cur - h) > 1.0) {
              heights.val[idx] = h
              changed = true
            }
          }
        }
        if changed {
          rebuild_prefix()
        }
      }
      state.content_h = content_height(count)
      // 视口高优先用已同步的真实值；首帧还没同步过就用声明的 height
      // （on_draw 里不能重建窗口——绘制遍历正在读 kids，改动子控件会踩迭代）
      let vh = if state.view_h > 0.0 { state.view_h } else { height }
      let first = if fixed {
        ((state.offset / rh).to_int() - overscan).max(0)
      } else {
        (virt_window_index(prefix.val, state.offset) - overscan).max(0)
      }
      let last = if fixed {
        (((state.offset + vh) / rh).ceil().to_int() + overscan).min(count)
      } else {
        (virt_window_index(prefix.val, state.offset + vh) + 1 + overscan).min(
          count,
        )
      }
      if !force && first == win_first.val && last == win_last.val {
        return
      }
      win_first.val = first
      win_last.val = last
      inner.clear_children()
      let rows : Array[(Int32, @widget.Widget)] = []
      // 上占位：让第一行落在正确的滚动位置
      if first > 0 {
        let sp = @widget.Widget::new()
        let top_h = if fixed {
          first.to_double() * rh
        } else {
          prefix.val[first]
        }
        sp.node.set_height(@yoga.fixed(top_h))
        inner.append_child(sp)
      }
      let data = items.get()
      for i = first; i < last; i = i + 1 {
        let node = row_of(i, data[i])
        let w = node.mount_into(inner)
        if !fixed {
          rows.push((i, w))
        }
      }
      // 下占位：撑起剩余高度（滚动条比例与越界夹取吃 content_h，这里只是让
      // 内层高度与内容一致，避免「挂了几行就只高几行」）
      let rest_h = if fixed {
        (count - last).to_double() * rh
      } else {
        prefix.val[count] - prefix.val[last]
      }
      if rest_h > 0.0 {
        let sp = @widget.Widget::new()
        sp.node.set_height(@yoga.fixed(rest_h))
        inner.append_child(sp)
      }
      mounted.val = rows
      @widget.invalidate()
    }

    state.apply.val = fn() -> Unit { render_window(false) }
    @style.apply(
      viewport,
      @style.merge_all([
        @style.style(border_color="border", border_width=1.0),
        paint_subset(class),
      ]),
    )
    viewport.on_draw = Some(fn(
      self : @widget.Widget,
      p : @render.Painter,
      r : @base.Rect,
    ) -> Unit {
      // 只同步几何（滚动条比例与夹取吃它），不在绘制里改子控件树
      let vh_changed = (r.h - state.view_h) > 0.5 || (state.view_h - r.h) > 0.5
      state.view_h = r.h
      if fixed {
        state.content_h = total.val.to_double() * rh
      } else {
        state.content_h = content_height(total.val)
      }
      if vh_changed && @shell.timer_channel_ready() {
        // 视口高变了要重算窗口（多挂/少挂行）：绘制中不能改组树，下一帧补；
        // is_painted 守卫保证迟到节拍（已卸载/换页）空操作。无宿主泵的纯控件
        // 测试不排节拍，避免待发定时器漏进后续用例
        let _ = @shell.set_timeout(0, fn() {
          if viewport.is_painted() {
            render_window(true)
          }
        })
      }
      if state.content_h > state.view_h {
        let st = @style.style_for(self)
        p.set_stroke_color(
          @style.color_of(st.border_color, @theme.theme_border()),
        )
        p.set_line_width(@style.number_of(st.border_width, 1.0))
        p.stroke_rect(0.0, 0.0, r.w, r.h)
      }
    })
    viewport.on_scroll = Some(fn(ev : @widget.ScrollEvent) -> Bool {
      let before = state.offset
      state.scroll_by(0.0 - ev.dy * 30.0)
      state.offset != before
    })
    match rev {
      Some(r) => {
        // 外部改列宽等「行内容要重建」的变更：给一个 rev，变了就整窗重挂
        let rsid = r
          .signal()
          .subscribe(fn(_v : Int32) -> Unit { render_window(true) })
        @base.sub_bag_register(fn() { r.signal().remove(rsid) })
      }
      None => ()
    }
    let sid = items
      .signal()
      .subscribe(fn(_v : Array[T]) -> Unit {
        // 数据变短时先把偏移拉回上界，再重挂窗口
        let count = items.get().length()
        sync_heights(count)
        if !fixed {
          rebuild_prefix()
        }
        state.content_h = content_height(count)
        if state.offset > state.max() {
          state.set_offset(state.max())
        } else {
          render_window(true)
        }
      })
    @base.sub_bag_register(fn() { items.signal().remove(sid) })
    viewport.append_child(scroll_bar(state))
    scroll_bar_hover(viewport, state)
    render_window(true)
    handle(viewport)
    viewport
  })
}

///|
/// 虚拟表格（`table` 的万行级形态）：表头固定不滚，数据行走 `virt_list`，
/// 单元格画法与 `table` 完全一致（同一份 `table_row_widget`）。
pub fn table_v(
  columns : Array[TableColumn],
  rows : @base.Store[Array[TableRow]],
  width~ : Double = 560.0,
  height~ : Double = 360.0,
  row_height~ : Double = 32.0,
  selection? : @base.Store[Array[Int32]],
  sort? : @base.Store[TableSort],
  on_row_click~ : (Int32, TableRow) -> Unit = fn(
    _i : Int32,
    _r : TableRow,
  ) -> Unit {
    ()
  },
  class~ : Array[@style.Style] = [],
  handle~ : (@widget.Widget) -> Unit = default_handle,
) -> @widget.Node {
  let head_h = 40.0
  @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget {
    watch_theme()
    w.kind = "ui-table-v"
    match selection {
      Some(s) => follow_store(s)
      None => ()
    }
    match sort {
      Some(s) => follow_store(s)
      None => ()
    }

    w.node.set_flex_direction(@yoga.Column)
    // 宽 0 = 跟容器（percent 100，配合弹性列让 split 分栏拖动时表格跟宽）；
    // 定宽档照旧。表头列宽扣掉滚动条（8px）与左右边框，数据行与表头一致
    if width > 0.0 {
      w.node.set_width(@yoga.fixed(width))
    } else {
      w.node.set_width(@yoga.percent(100.0))
      w.node.set_min_width(@yoga.fixed(0.0))
    }
    let widths : Ref[Array[Double]] = Ref(table_widths(columns, width - 10.0))
    let rev = @base.Store::new(0)
    @style.apply(
      w,
      @style.merge_all([
        @style.style(
          background_color="bg_panel",
          border_color="border",
          border_width=1.0,
        ),
        @style.merge_all(class),
      ]),
    )
    w.on_draw = Some(fn(
      self : @widget.Widget,
      p : @render.Painter,
      r : @base.Rect,
    ) -> Unit {
      let st = @style.style_for(self)
      let rad = @style.number_of(st.border_radius, @theme.radius_card())
      self.clip_rounded = rad > 0.0
      self.style_clip_radius = rad
      p.set_fill_color(
        @style.color_of(st.background_color, @theme.theme_bg_panel()),
      )
      if rad > 0.0 {
        p.fill_round_rect(0.0, 0.0, r.w, r.h, rad)
      } else {
        p.fill_rect(0.0, 0.0, r.w, r.h)
      }
      p.set_stroke_color(
        @style.color_of(st.border_color, @theme.theme_border()),
      )
      p.set_line_width(@style.number_of(st.border_width, 1.0))
      if rad > 0.0 {
        p.round_rect_path(0.5, 0.5, r.w - 1.0, r.h - 1.0, rad)
        p.stroke()
      } else {
        p.stroke_rect(0.0, 0.0, r.w, r.h)
      }
    })
    let head = table_header(
      columns,
      widths,
      sort,
      head_h,
      skin=paint_subset(class),
      on_resize=Some(fn(_j : Int32, _nw : Double) -> Unit {
        // 虚拟表只管表头两格；数据行靠 rev 整窗重挂（可见行才十来个，重建便宜）
        rev.set(rev.get() + 1)
      }),
    )
    head.node.set_flex_shrink(0.0)
    w.append_child(head)
    let list = virt_list(
      rows,
      height,
      row_height,
      fn(src : Int32, row : TableRow) -> @widget.Node {
        @widget.node_of(
          table_row_widget(
            columns,
            widths.val,
            row,
            src,
            row_height,
            selection,
            on_row_click,
            skin=paint_subset(class),
          ),
        )
      },
      width=width - 2.0,
      rev~,
      class~,
    )
    let _ = list.mount_into(w)
    handle(w)
    w
  })
}

///|
/// 粘性列表的状态：滚动偏移 + 当前吸顶的分组（组件在每帧布局后写入，
/// 调用方与测试直接读 `cur_group`）。
pub(all) struct StickyList {
  scroll : ScrollState
  mut cur_group : String
  mut cur_start : Double
}

///|
pub fn StickyList::new() -> StickyList {
  { scroll: ScrollState::new(), cur_group: "", cur_start: 0.0, }
}

///|
/// 粘性列表：分组标题在滚动时吸顶（悬浮在视口顶部的那一条始终显示「当前组」的
/// 标题，滚过组边界就换文字），组内行照常滚走。
///
/// 实现口径：吸顶标题是视口里的一个**绝对定位悬浮条**，内容整块跟着偏移走
/// （与 `scroll_view` 同一套相对定位平移）；「当前组」不是靠滚动位置硬算，而是每帧
/// 布局后读各组控件的矩形反推——组高由内容决定（行数/换行都可能变），读布局结果
/// 比事先累加高度稳。
pub fn sticky_list(
  groups : Array[(String, Array[@widget.Node])],
  st : StickyList,
  width~ : Double = 0.0,
  height~ : Double = 0.0,
  head_h~ : Double = 28.0,
  class~ : Array[@style.Style] = [],
  handle~ : (@widget.Widget) -> Unit = default_handle,
) -> @widget.Node {
  let state = st.scroll
  let hh = head_h
  @widget.node_of_new(fn(viewport : @widget.Widget) -> @widget.Widget {
    watch_theme()
    viewport.kind = "ui-sticky-list"
    let lay = @style.empty_style()
    lay.flex_direction = Some(@yoga.Column)
    // 视口显式 overflow:hidden：滚出视口的行不落
    lay.overflow = Some(@style.Hidden)
    if width > 0.0 {
      lay.width = Some(width)
    }
    if height > 0.0 {
      lay.height = Some(height)
    }
    @style.apply(viewport, @style.merge_all([lay, @style.merge_all(class)]))
    // 内容：整块跟着偏移平移（相对定位偏移只改落位、不改流内占位）
    let content = @widget.Widget::new()
    content.node.set_flex_direction(@yoga.Column)
    content.node.set_width(@yoga.percent(100.0))
    content.node.set_position(@yoga.Relative)
    content.node.set_flex_shrink(0.0)
    content.node.set_top(@yoga.fixed(0.0 - state.offset))
    let group_widgets : Array[@widget.Widget] = []
    for g in groups {
      let title = g.0
      let rows = g.1
      let gw = @widget.Widget::new()
      gw.node.set_flex_direction(@yoga.Column)
      gw.node.set_width(@yoga.percent(100.0))
      // 组标题（滚走的那一条，静态头）
      let head = @widget.Widget::new()
      head.node.set_height(@yoga.fixed(hh))
      head.node.set_width(@yoga.percent(100.0))
      @style.apply(
        head,
        @style.merge_all([
          @style.style(background_color="fill_zebra", color="text_secondary"),
          paint_subset(class),
        ]),
      )
      head.on_draw = Some(fn(
        self : @widget.Widget,
        p : @render.Painter,
        r : @base.Rect,
      ) -> Unit {
        let hs = @style.style_for(self)
        p.set_fill_color(
          @style.color_of(hs.background_color, @theme.theme_fill_zebra()),
        )
        p.fill_rect(0.0, 0.0, r.w, r.h)
        let f = @text.Font::new("", 12.0, weight=@text.SemiBold)
        let _ = @text.draw_box_at(
          p,
          8.0,
          0.0,
          (r.w - 12.0).max(1.0),
          r.h,
          title,
          f,
          @style.color_of(hs.color, @theme.theme_text_secondary()),
          align=@text.Start,
          valign=@text.Center,
        )
      })
      gw.append_child(head)
      @widget.mount_children(gw, rows)
      content.append_child(gw)
      group_widgets.push(gw)
    }
    viewport.append_child(content)
    // 吸顶悬浮条
    let sticky_bar = @widget.Widget::new()
    sticky_bar.node.set_position(@yoga.Absolute)
    sticky_bar.node.set_top(@yoga.fixed(0.0))
    sticky_bar.node.set_left(@yoga.fixed(0.0))
    sticky_bar.node.set_right(@yoga.fixed(0.0))
    sticky_bar.node.set_height(@yoga.fixed(hh))
    @style.apply(
      sticky_bar,
      @style.merge_all([
        @style.style(
          background_color="bg_panel",
          border_color="border",
          color="text_primary",
        ),
        paint_subset(class),
      ]),
    )
    sticky_bar.on_draw = Some(fn(
      self : @widget.Widget,
      p : @render.Painter,
      r : @base.Rect,
    ) -> Unit {
      let bs = @style.style_for(self)
      p.set_fill_color(
        @style.color_of(bs.background_color, @theme.theme_bg_panel()),
      )
      p.fill_rect(0.0, 0.0, r.w, r.h)
      p.set_fill_color(@style.color_of(bs.border_color, @theme.theme_border()))
      p.fill_rect(0.0, r.h - 1.0, r.w, 1.0)
      let f = @text.Font::new("", 12.0, weight=@text.SemiBold)
      let _ = @text.draw_box_at(
        p,
        8.0,
        0.0,
        (r.w - 12.0).max(1.0),
        r.h,
        st.cur_group,
        f,
        @style.color_of(bs.color, @theme.theme_text_primary()),
        align=@text.Start,
        valign=@text.Center,
      )
    })
    viewport.append_child(sticky_bar)
    // 每帧布局后按「各组的实际矩形」反推当前组
    viewport.on_draw = Some(fn(
      _s : @widget.Widget,
      _p : @render.Painter,
      r : @base.Rect,
    ) -> Unit {
      st.scroll.view_h = r.h
      st.scroll.content_h = content.rect.h
      let top = state.offset
      let mut idx = 0
      for i = 0; i < group_widgets.length(); i = i + 1 {
        let gy = group_widgets[i].rect.y - content.rect.y
        if gy <= top + 0.5 {
          idx = i
        }
      }
      if group_widgets.length() > 0 {
        st.cur_group = groups[idx].0
        st.cur_start = group_widgets[idx].rect.y - content.rect.y
      }
    })
    st.scroll.apply.val = fn() -> Unit {
      content.node.set_top(@yoga.fixed(0.0 - state.offset))
      @widget.invalidate()
    }
    viewport.on_scroll = Some(fn(ev : @widget.ScrollEvent) -> Bool {
      let before = state.offset
      state.scroll_by(0.0 - ev.dy * 30.0)
      state.offset != before
    })
    viewport.append_child(scroll_bar(state))
    scroll_bar_hover(viewport, state)
    handle(viewport)
    viewport
  })
}
