# Custom draw & input

Drawing itself (shapes, paths, gradients, bitmaps, text): [Canvas](canvas.md). A custom block responds to keyboard & mouse through its callback fields, which with `invalidate` form the "event mutates state → repaint" loop. State maintenance for pointer, hover, cursor and focus is entirely handled by the host — no enter/leave handlers, no capture logic.

## Pointer: one `on_pointer` covers press/move/release/leave

```moonbit
w.on_pointer = Some(
  fn(self : @widget.Widget, ev : @widget.PointerEvent) -> Bool {
    match ev.kind {
      @widget.PointerKind::Down => { /* record the start point */ true }
      @widget.PointerKind::Move => { /* collect points while dragging */ true }
      @widget.PointerKind::Up => { /* end the stroke */ true }
      @widget.PointerKind::Leave => false
    }
  },
)
```

Key points (all done for you by the host):

- `ev.x` / `ev.y` are converted to **local coordinates** before delivery (`Leave` keeps window coordinates).
- **Hit means capture**: between press and release, all Move/Up events go to the pressed widget, even after the pointer leaves its rectangle (coordinates may go negative) — drag handles and rubber-band selection need no capture code.
- Returning `true` = the event is consumed (bubbling up the ancestor chain stops); `false` = it keeps bubbling.
- Double/triple clicks have their own `on_double_click` / `on_triple_click` (400 ms / 4 px thresholds) and coexist with `on_pointer`.

## Hover / pressed / focused states: read the fields, draw the feedback

`hovered` / `pressed` / `focused` are maintained by the host; read them in `on_draw` and draw accordingly:

```moonbit
w.on_draw = Some(
  fn(self : @widget.Widget, p : @render.Painter, r : @base.Rect) -> Unit {
    p.set_fill_color(if self.hovered { "#2A303C" } else { "#20242C" })
    p.fill_rect(0.0, 0.0, r.w, r.h)
    p.set_stroke_color(if self.focused { "#E8B34B" } else { "#4A5060" })
    p.stroke_rect(0.0, 0.0, r.w, r.h)   // focus ring is your job
  },
)
```

Attach `on_hover_change(w, hovered)` for side effects such as starting/stopping timers; `on_focus_change(w, focused)` for commit-on-blur widgets. The cursor shape is a one-line declaration: `w.cursor = @widget.CURSOR_HAND` (full set: `CURSOR_DEFAULT / HAND / TEXT / RESIZE_H / RESIZE_V / HIDDEN / GRAB / GRABBING / NOT_ALLOWED`; the host takes the deepest non-zero request on the hover path).

Reading the flags is the way for **custom blocks**. Ready-made widgets (`view` / `button` — the ones that go through the style system) don't read flags: declare the `@style.style(hover=...)` style slot instead, see [Theme recipes](../cookbook/theme.md#giving-widgets-interactive-styles). A custom block lays down every pixel itself and no default painter consumes style slots on its behalf, so it reads the host-maintained flags directly.

## Keyboard: declare `focus_id` first, then attach `on_key`

```moonbit
w.focus_id = 1   // >0 makes it focusable; tree order is Tab order, maintained by the host; clicking focuses it
w.on_key = Some(fn(ev : @widget.KeyEvent) -> Bool {
  if ev.keysym == @base.KS_DELETE {
    true            // returning true = consumed
  } else {
    false
  }
})
```

Key points:

- Keys go only to the **currently focused widget** (and its ancestors that carry `on_key`); the host delivers presses only — for "hold to do, release to stop" components attach `on_key_release` (the only channel that receives releases).
- `ev.keysym` is the platform virtual key code: named keys use the `KS_*` constants from `@base` (`KS_RETURN` / `KS_LEFT` / `KS_ESCAPE`…); printable characters sit in the 32–126 range and convert via `keysym.to_char()`.
- Modifiers are the bitmask `ev.mods`: test with bitwise-and against `@base.MOD_SHIFT / MOD_CTRL / MOD_ALT / MOD_META`.
- Window-wide shortcuts (that must fire regardless of focus) go through the host fallback channel: `app.add_key_fallthrough(...)` (`app` is what `mount_window` returns); it only sees keys nobody in the focus chain consumed.

## Scroll wheel

```moonbit
w.on_scroll = Some(fn(ev : @widget.ScrollEvent) -> Bool {
  // ev.dx / ev.dy are the scroll amounts — the entry point for canvas zoom and pan
  true
})
```

## Putting it together: a mini sketchpad

Drag to draw lines, click to focus, Backspace undoes a stroke, Delete clears. State lives outside the callbacks; events mutate state then `invalidate`, and drawing repaints everything. Use the minimal window skeleton from [Canvas](canvas.md#_1-mount-a-custom-draw-area):

```moonbit
let strokes : Ref[Array[Array[(Double, Double)]]] = Ref([])
let drawing : Ref[Bool] = Ref(false)

let board = @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget {
  w.node.set_width(@yoga.percent(100.0))
  w.node.set_height(@yoga.fixed(220.0))
  w.focus_id = 1
  w.on_pointer = Some(
    fn(_self : @widget.Widget, ev : @widget.PointerEvent) -> Bool {
      match ev.kind {
        @widget.PointerKind::Down => {
          strokes.val.push([(ev.x, ev.y)])
          drawing.val = true
          @widget.invalidate()
          true
        }
        @widget.PointerKind::Move =>
          if drawing.val {
            strokes.val[strokes.val.length() - 1].push((ev.x, ev.y))
            @widget.invalidate()
            true
          } else {
            false
          }
        @widget.PointerKind::Up => {
          drawing.val = false
          true
        }
        @widget.PointerKind::Leave => false
      }
    },
  )
  w.on_key = Some(fn(ev : @widget.KeyEvent) -> Bool {
    if ev.keysym == @base.KS_BACKSPACE && strokes.val.length() > 0 {
      let _ = strokes.val.pop()   // undo one stroke
      @widget.invalidate()
      true
    } else if ev.keysym == @base.KS_DELETE {
      strokes.val.clear()         // clear all
      @widget.invalidate()
      true
    } else {
      false
    }
  })
  w.on_draw = Some(
    fn(self : @widget.Widget, p : @render.Painter, r : @base.Rect) -> Unit {
      p.set_fill_color("#20242C")
      p.fill_rect(0.0, 0.0, r.w, r.h)
      p.set_stroke_color(if self.focused { "#E8B34B" } else { "#4A5060" })
      p.set_line_width(1.0)
      p.stroke_rect(0.0, 0.0, r.w, r.h)   // focus ring
      p.set_stroke_color("#4B8BE8")
      p.set_line_width(2.0)
      p.set_line_cap(@render.LineCap::Round)
      p.set_line_join(@render.LineJoin::Round)
      for s in strokes.val {
        if s.length() == 1 {
          p.arc(s[0].0, s[0].1, 1.5, 0.0, 6.28318)   // a single point still draws
          p.fill()
        } else {
          p.begin_path()
          p.move_to(s[0].0, s[0].1)
          for i in 1..<s.length() {
            p.line_to(s[i].0, s[i].1)
          }
          p.stroke()
        }
      }
    },
  )
  w
})
```

Live demos for pointer/hover/cursor/keyboard: the showcase "Events & layout" page (source `examples/showcase/pages/events.mbt`).
