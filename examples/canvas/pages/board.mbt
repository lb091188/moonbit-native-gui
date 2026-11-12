// 交互画板段：Pointer 手绘 × Keyboard 画线。
//
// 四条口径：
// ① 指针：on_pointer 一颗回调吃全部指针事件，Down 起笔、Move 采点、Up/Leave
//    收笔——坐标投递前已换算成本地坐标，直接进笔画点列；
// ② 键盘：控件声明 focus_id（>0 即入 Tab 链）即可拿焦点，on_key 吃方向键移
//    虚拟光标（每次按键事件 1 像素），Enter/空格 落点。长按自驱重复：按下
//    登记进按住表并挂宿主 33ms 一拍的重复泵（系统自动重复的 keydown 只
//    刷新修饰、不重复步进，节奏自己定，不吃系统首延），松开/Escape 收；
//    修饰改步长（可叠加相乘）：Shift ×16（兼从光标画直线）、Ctrl ×4、
//    Alt ×0.25（亚像素微调）；
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
  // 键盘长按重复：按住的方向键表 + 最近修饰快照 + 泵在跑标记
  let held : Array[Int32] = []
  let last_mods : Ref[Int32] = Ref(0)
  let pump_on : Ref[Bool] = Ref(false)
  // 修饰步长（可叠加相乘）：Shift ×16（兼从光标画直线）、Ctrl ×4、Alt ×0.25
  fn step_move(ks : Int32, mods : Int32) -> Unit {
    let mut step = 1.0
    if (mods & @base.MOD_SHIFT) != 0 {
      step *= 16.0
    }
    if (mods & @base.MOD_CTRL) != 0 {
      step *= 4.0
    }
    if (mods & @base.MOD_ALT) != 0 {
      step *= 0.25
    }
    let (cx, cy) = cursor.val
    let nx = if ks == @base.KS_LEFT {
      cx - step
    } else if ks == @base.KS_RIGHT {
      cx + step
    } else {
      cx
    }
    let ny = if ks == @base.KS_UP {
      cy - step
    } else if ks == @base.KS_DOWN {
      cy + step
    } else {
      cy
    }
    if (mods & @base.MOD_SHIFT) != 0 {
      // Shift+方向：从光标到新位置一条直线（长按时逐拍短线段连成线）
      strokes.val.push({
        pts: [(cx, cy), (nx, ny)],
        color: colors[color_idx.val],
        width: widths[width_idx.val],
      })
    }
    cursor.val = (nx, ny)
    @widget.invalidate()
  }

  fn release_key(ks : Int32) -> Unit {
    for i in 0..<held.length() {
      if held[i] == ks {
        let _ = held.remove(i)
        return
      }
    }
  }

  /// 重复泵：33ms 一拍对每个按住键各步进一次（约 30 步/s）；按住表空即停。
  fn start_pump() -> Unit {
    if pump_on.val {
      return
    }
    pump_on.val = true
    fn tick() -> Unit {
      if held.length() == 0 {
        pump_on.val = false
        return
      }
      let snapshot : Array[Int32] = []
      for ks in held {
        snapshot.push(ks)
      }
      for ks in snapshot {
        step_move(ks, last_mods.val)
      }
      for h in @widget.host_windows() {
        let _ = h.timer(33, tick)
        break
      }
    }
    for h in @widget.host_windows() {
      let _ = h.timer(33, tick)
      break
    }
  }

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
      // 修饰快照随任何按键刷新（长按方向键时按/松修饰也能实时改步长）
      last_mods.val = ev.mods
      let is_arrow = ev.keysym == @base.KS_LEFT ||
        ev.keysym == @base.KS_RIGHT ||
        ev.keysym == @base.KS_UP ||
        ev.keysym == @base.KS_DOWN
      if is_arrow {
        if ev.press {
          // 首次按下才步进+登记；系统自动重复的 keydown（键已在表里）只
          // 刷新了修饰，步进节奏归 33ms 重复泵
          if !held.contains(ev.keysym) {
            held.push(ev.keysym)
            step_move(ev.keysym, ev.mods)
            start_pump()
          }
        } else {
          release_key(ev.keysym)
        }
        return true
      }
      if !ev.press {
        return false
      }
      if ev.keysym == @base.KS_RETURN || ev.keysym == @base.KS_SPACE {
        // 落点：光标处一个实心圆
        let (cx, cy) = cursor.val
        strokes.val.push({
          pts: [(cx, cy)],
          color: colors[color_idx.val],
          width: widths[width_idx.val],
        })
        @widget.invalidate()
        true
      } else if ev.keysym == @base.KS_ESCAPE {
        // 兜底收尾：焦点被抢走收不到 keyUp 时，Esc 清掉按住表停泵
        held.clear()
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
    "on_pointer 一颗回调吃全部指针事件：按住左键手绘（Down 起笔 / Move 采点 / Up、Leave 收笔），坐标已换算成本地坐标。键盘：控件声明 focus_id 即入 Tab 链，Tab 或点击画板拿到焦点后，方向键移虚拟光标（每次按键 1 像素），按住不放连续移动（33ms 一拍的自驱重复泵，系统重复事件只刷新修饰不重复步进），Enter/空格 落点；修饰改步长可叠加：Shift ×16（兼从光标画直线）、Ctrl ×4、Alt ×0.25（亚像素微调），Esc 收掉按住表。笔画是纯数据（点列 + 颜色 + 线宽），on_draw 全量重放，改动后 invalidate() 请求一帧。",
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
      "  // 方向键：首次按下步进 1px 并登记按住表，33ms 泵接管长按",
      "  // 系统重复的 keydown 只刷新修饰，不重复步进",
      "  // 步长 = 1px × Shift16 × Ctrl4 × Alt0.25（可叠加）",
      "  if ev.keysym == @base.KS_LEFT { … }",
      "  // Shift+方向 = 快速移动并从光标画直线",
      "  (ev.mods & @base.MOD_SHIFT) != 0",
      "})",
      "@widget.invalidate()  // 改完数据请求一帧",
    ],
  )
}
