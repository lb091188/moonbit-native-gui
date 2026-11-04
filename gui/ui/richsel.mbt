// 可选中的富文本控件：`@text.AttributedText`（范围字体/颜色自带的混排段）
// + TextSel 选中链。几何三件（行盒/命中/游标）由 @text 的选中查询给出，
// 与绘制同口径（同一套对齐/折行/省略）；复制得到全文原文。

///|
/// 富文本控件（可选档）：`at` 由调用方备好样式区间，控件只管测量/绘制/
/// 选中交互。`selectable=false` 时纯展示（点不动），与直接自绘同观感。
pub fn rich_text(
  at : @text.AttributedText,
  selectable? : Bool = false,
  handle? : (@widget.Widget) -> Unit = default_handle,
) -> @widget.Node {
  let text = at.get_text()
  let sel_len = @utf8.encode(text).length()
  let st : TextSel? = if selectable && sel_len > 0 {
    let ed = @input.Editor::new()
    ed.set_text(text)
    Some(text_sel_new(ed))
  } else {
    None
  }
  @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget {
    watch_theme()
    // 尺寸三档同 mdview 富文本行的口径：定宽按定宽、min-content 1px 箱、
    // max-content 单行；行数×行高从 line_boxes 读（与选中高亮同一份几何）
    let height_of = fn(box_w : Double) -> Double {
      let boxes = at.line_boxes(box_w, 0.0)
      let mut h = 0.0
      for b in boxes {
        h += b.h
      }
      h
    }
    w.node.set_measure(fn(aw : Double?, _ah : Double?) -> (Double, Double) {
      match aw {
        Some(v) if v >= 1.0 => {
          let h = height_of(v)
          (v, h)
        }
        // min/max 探询按单行自然宽答（富文本控件不参与折行容器的内在下限
        // 计算，答单行即可，别把容器顶高）
        _ => {
          let one = at.line_boxes(0.0, 0.0)
          let mut maxw = 1.0
          let mut hsum = 0.0
          for b in one {
            // 单行档 x 是左缘；自然宽用 get_bounds_for 兜（与 draw 同源）
            let _ = b
            hsum += b.h
          }
          let nat = at.get_bounds_for(0.0, 0.0)
          if nat.width > maxw {
            maxw = nat.width
          }
          (maxw, hsum.max(nat.height))
        }
      }
    })
    w.on_draw = Some(fn(
      _self : @widget.Widget,
      p : @render.Painter,
      r : @base.Rect,
    ) -> Unit {
      // 选区底色：全文选区按行盒裁切，行内区间 = 前缘 x 差（高亮在字下）
      match st {
        Some(state) =>
          match state.range() {
            Some((a, b)) => {
              let boxes = at.line_boxes(r.w, r.h)
              for lb in boxes {
                let lo = a.max(lb.byte_start)
                let hi = b.min(lb.byte_end)
                if hi > lo {
                  let x0 = at.caret_x(lo, r.w, r.h)
                  let x1 = at.caret_x(hi, r.w, r.h)
                  match (x0, x1) {
                    (Some(c0), Some(c1)) => {
                      p.set_fill_color(@theme.theme_primary_light())
                      p.fill_rect(
                        c0,
                        lb.y,
                        (c1 - c0).max(1.0),
                        lb.h,
                      )
                    }
                    _ => ()
                  }
                }
              }
            }
            None => ()
          }
        None => ()
      }
      let _ = at.draw_at(p, 0.0, 0.0, r.w, r.h)
    })
    match st {
      Some(state) => {
        w.cursor = @widget.CURSOR_TEXT
        w.on_pointer = Some(fn(
          self : @widget.Widget,
          ev : @widget.PointerEvent,
        ) -> Bool {
          sel_pointer(self, ev, state, fn(x : Double, y : Double) -> Int {
            match at.hit(x, y, self.rect.w, self.rect.h) {
              Some(b) => b
              None => 0
            }
          })
        })
        sel_states.val.set(w.id, state)
        let give = state
        w.on_discard = Some(fn(self : @widget.Widget) -> Unit {
          let _ = sel_states.val.remove(self.id)
          @widget.text_sel_release(self.id)
          give.give_up(self.id)
        })
      }
      None => ()
    }
    handle(w)
    w
  })
}
