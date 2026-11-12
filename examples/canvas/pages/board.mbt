// 交互画板段：Pointer 手绘 × Keyboard 画线。
//
// 四条口径：
// ① 指针：on_pointer 一颗回调吃全部指针事件，Down 起笔、Move 采点、Up/Leave
//    收笔——坐标投递前已换算成本地坐标，直接进笔画点列；
// ② 键盘：控件声明 focus_id（>0 即入 Tab 链）即可拿焦点，on_key 吃方向键移
//    虚拟光标，Enter/空格 落点，Shift+方向键从光标画直线（修饰键位取 base 的
//    MOD_SHIFT 位掩码）；
// ③ 数据与重绘：笔画是纯数据（点列 + 颜色 + 线宽），on_draw 全量重放，改动后
//    @widget.invalidate() 请求一帧（进程级重画，宿主装的是 host_repaint_all）；
// ④ 事件消费：on_pointer/on_key 返回 true = 已消费（不再外传）；没吃到的事件
//    一律返回 false，Tab 导航与外层手势不受影响。

///|
/// 一条笔画：手绘是采点序列，键盘直线是两点，落点是单点。
priv struct Stroke {
  pts : Array[(Double, Double)]
  color : String
  width : Double
}

///|
/// 画板段：工具条 + 画布；作为页面第一段挂进 `page_canvas`。
pub fn board_section() -> @shared.Section {
  let colors : Array[String] = ["#E5534B", "#4B8BE8", "#3AA76D", "#E8B34B"]
  let widths : Array[Double] = [1.5, 3.0, 6.0, 10.0]
  let color_idx : Ref[Int] = Ref(0)
  let width_idx : Ref[Int] = Ref(1)
  let strokes : Ref[Array[Stroke]] = Ref([])
  let current : Ref[Stroke?] = Ref(None)
  let cursor : Ref[(Double, Double)] = Ref((320.0, 200.0))
  let board = @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget {
    w.node.set_width(@yoga.percent(100.0))
    w.node.set_height(@yoga.fixed(400.0))
    // >0 即入 Tab 链（宿主按树序对齐焦点栈）；9xx 段页内唯一
    w.focus_id = 930
    w.on_draw = Some(fn(
      _self : @widget.Widget,
      p : @render.Painter,
      r : @base.Rect,
    ) -> Unit {
      p.set_fill_color(@theme.theme_bg_panel())
      p.fill_rect(0.0, 0.0, r.w, r.h)
      // 已完成笔画 + 进行中的一笔，全量重放
      let all : Array[Stroke] = []
      for s in strokes.val {
        all.push(s)
      }
      match current.val {
        Some(s) => all.push(s)
        None => ()
      }
      for s in all {
        if s.pts.length() == 1 {
          // 落点：单点画成实心圆
          let (x, y) = s.pts[0]
          p.set_fill_color(s.color)
          p.arc(x, y, s.width * 1.5, 0.0, 6.28318)
          p.fill()
        } else {
          p.set_stroke_color(s.color)
          p.set_line_width(s.width)
          p.set_line_cap(@render.LineCap::Round)
          p.set_line_join(@render.LineJoin::Round)
          p.begin_path()
          for k in 0..<s.pts.length() {
            let (x, y) = s.pts[k]
            if k == 0 {
              p.move_to(x, y)
            } else {
              p.line_to(x, y)
            }
          }
          p.stroke()
        }
      }
      // 键盘光标：十字准星
      let (cx, cy) = cursor.val
      p.set_stroke_color(@theme.theme_text_secondary())
      p.set_line_width(1.0)
      p.begin_path()
      p.move_to(cx - 10.0, cy)
      p.line_to(cx + 10.0, cy)
      p.move_to(cx, cy - 10.0)
      p.line_to(cx, cy + 10.0)
      p.stroke()
      p.flush()
    })
    w.on_pointer = Some(fn(
      _self : @widget.Widget,
      ev : @widget.PointerEvent,
    ) -> Bool {
      match ev.kind {
        @widget.PointerKind::Down => {
          current.val = Some({
            pts: [(ev.x, ev.y)],
            color: colors[color_idx.val],
            width: widths[width_idx.val],
          })
          true
        }
        @widget.PointerKind::Move =>
          match current.val {
            Some(s) => {
              s.pts.push((ev.x, ev.y))
              @widget.invalidate()
              true
            }
            None => false
          }
        _ =>
          // Up / Leave（或其余收尾语义）：收笔入列表
          match current.val {
            Some(s) => {
              strokes.val.push(s)
              current.val = None
              @widget.invalidate()
              true
            }
            None => false
          }
      }
    })
    w.on_key = Some(fn(ev : @widget.KeyEvent) -> Bool {
      if !ev.press {
        return false
      }
      let step = 16.0
      let (cx, cy) = cursor.val
      let shift = (ev.mods & @base.MOD_SHIFT) != 0
      if ev.keysym == @base.KS_LEFT || ev.keysym == @base.KS_RIGHT ||
        ev.keysym == @base.KS_UP || ev.keysym == @base.KS_DOWN {
        let nx = if ev.keysym == @base.KS_LEFT {
          cx - step
        } else if ev.keysym == @base.KS_RIGHT {
          cx + step
        } else {
          cx
        }
        let ny = if ev.keysym == @base.KS_UP {
          cy - step
        } else if ev.keysym == @base.KS_DOWN {
          cy + step
        } else {
          cy
        }
        if shift {
          // Shift+方向：从光标到新位置一条直线
          strokes.val.push({
            pts: [(cx, cy), (nx, ny)],
            color: colors[color_idx.val],
            width: widths[width_idx.val],
          })
        }
        cursor.val = (nx, ny)
        @widget.invalidate()
        true
      } else if ev.keysym == @base.KS_RETURN || ev.keysym == @base.KS_SPACE {
        // 落点：光标处一个实心圆
        strokes.val.push({
          pts: [(cx, cy)],
          color: colors[color_idx.val],
          width: widths[width_idx.val],
        })
        @widget.invalidate()
        true
      } else {
        false
      }
    })
    w
  })
  let toolbar = @ui.row(
    [
      @ui.button("换色", variant=@ui.Soft, on_click=fn() {
        color_idx.val = (color_idx.val + 1) % colors.length()
        @widget.invalidate()
      }),
      @ui.button("线宽", variant=@ui.Soft, on_click=fn() {
        width_idx.val = (width_idx.val + 1) % widths.length()
        @widget.invalidate()
      }),
      @ui.button("清空画板", variant=@ui.Solid, on_click=fn() {
        strokes.val = []
        current.val = None
        @widget.invalidate()
      }),
    ],
    column_gap=8.0,
  )
  @shared.section(
    "画板",
    "交互画板：Pointer × Keyboard",
    "on_pointer 一颗回调吃全部指针事件：按住左键手绘（Down 起笔 / Move 采点 / Up、Leave 收笔），坐标已换算成本地坐标。键盘：控件声明 focus_id 即入 Tab 链，Tab 或点击画板拿到焦点后，方向键移虚拟光标，Enter/空格 落点，Shift+方向键从光标画直线（修饰键位取 MOD_SHIFT 位掩码）。笔画是纯数据（点列 + 颜色 + 线宽），on_draw 全量重放，改动后 invalidate() 请求一帧。",
    [toolbar, board],
    code=[
      "w.focus_id = 930              // >0 即入 Tab 链，可点击/Tab 聚焦",
      "w.on_pointer = Some(fn(_self, ev) {",
      "  match ev.kind {",
      "    Down => { 新建笔画记第一个点; true }",
      "    Move => { 追加采点 + invalidate(); true }",
      "    _    => { 收笔入列表; true }",
      "  }",
      "})",
      "w.on_key = Some(fn(ev) {",
      "  // 方向键移虚拟光标；Enter 落点",
      "  if ev.keysym == @base.KS_LEFT { … }",
      "  // Shift+方向 = 从光标到新位置画直线",
      "  (ev.mods & @base.MOD_SHIFT) != 0",
      "})",
      "@widget.invalidate()  // 改完数据请求一帧",
    ],
  )
}
