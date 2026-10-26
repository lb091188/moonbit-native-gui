// 窗口 resize 桩链探针：开窗 → 改宽 → 收事件 → 读账本。
// 预期读数（桩链健康）：RESIZED-EVENT 出现（可能多条）、SIZE-BEFORE 800、
// SIZE-AFTER 1200（或拖动后的任意新宽）。SIZE-AFTER 仍是 800 即桩账本没跟上。
fn main {
  let w = match @win.Window::new(800, 600, "resize-probe") {
    Some(w) => w
    None => {
      println("RESIZE-PROBE FAIL (窗建不出)")
      return
    }
  }
  w.show()
  // 布局层：同一棵树按两种可用宽各 relayout 一次，grow 子项的宽应跟随。
  // LAYOUT-W-1200 仍是 800 即布局引擎对宽度变化没响应（真 bug 在这层）。
  let lroot = @widget.Widget::new()
  let lchild = @widget.Widget::new()
  lchild.node.set_flex_grow(1.0)
  lroot.append_child(lchild)
  lroot.set_size(800.0, 600.0)
  lroot.relayout(800.0, 600.0)
  println("RESIZE-PROBE LAYOUT-W-800 \{lchild.rect.w}")
  lroot.set_size(1200.0, 600.0)
  lroot.relayout(1200.0, 600.0)
  println("RESIZE-PROBE LAYOUT-W-1200 \{lchild.rect.w}")
  let (w0, h0) = w.size()
  println("RESIZE-PROBE SIZE-BEFORE \{w0}x\{h0}")
  w.set_size_pixels(1200, 600)
  // 收 2 秒事件：Resized 的 code 是 2
  let mut resized_seen = 0
  let deadline = @win.now_ms() + 2000
  while @win.now_ms() < deadline {
    let _ = @win.wait(100)
    match w.poll_event() {
      @win.Resized => {
        resized_seen = resized_seen + 1
        let (cw, ch) = w.size()
        println("RESIZE-PROBE RESIZED-EVENT #\{resized_seen} size=\{cw}x\{ch}")
      }
      other => {
        let _ = other
      }
    }
  }
  let (w1, h1) = w.size()
  println("RESIZE-PROBE SIZE-AFTER \{w1}x\{h1} resized_seen=\{resized_seen}")
}
