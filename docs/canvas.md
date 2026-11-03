# Canvas & custom drawing

This page covers usage: mounting a draw area, common drawing, redrawing on change, keyboard & mouse interaction, and offscreen export.

**Live demo**: `cd examples/showcase && moon run .` and open the "Canvas" page — every technique on this page has a matching demo block; the source is `examples/showcase/pages/canvas.mbt`.

## Prerequisites

`moon.pkg` imports for this page (take what you need):

```
import {
  "NoahLiu/yoga-mbt/src" @yoga,
  "NoahLiu/native-gui/base" @base,
  "NoahLiu/native-gui/widget" @widget,
  "NoahLiu/native-gui/render" @render,
  "NoahLiu/native-gui/text" @text,
  "NoahLiu/native-gui/ui",
}
```

## 1. Mount a custom-draw area

Three steps: `node_of_new` creates a widget, set its size, attach the `on_draw` callback. Coordinates inside the callback are **local to the area** (top-left is `(0,0)`); draw against `r.w` / `r.h` and the block survives window resizing without distortion.

A complete runnable minimal program:

```moonbit
fn main {
  let app = match @ui.mount_window(
    [
      @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget {
        w.node.set_width(@yoga.fixed(320.0))
        w.node.set_height(@yoga.fixed(160.0))
        w.on_draw = Some(
          fn(_w : @widget.Widget, p : @render.Painter, r : @base.Rect) -> Unit {
            p.set_fill_color("#20242C")
            p.fill_rect(0.0, 0.0, r.w, r.h)
            p.set_fill_color("#E8B34B")
            p.arc(r.w / 2.0, r.h / 2.0, 48.0, 0.0, 6.28318)
            p.fill()
          },
        )
        w
      }),
    ],
    title="Canvas",
    width=360,
    height=220,
  ) {
    None => return
    Some(a) => a
  }
  app.run()
}
```

Notes:

- **The node must resolve to a size**: set `set_width` / `set_height` explicitly, or let the parent layout assign it (`grow` etc., see [Layout & styling](layout.md)). No size = no area = nothing gets drawn.
- `on_draw` runs on every repaint — **don't do heavy work inside** (reading files, decoding large images, building big objects); prepare assets outside the callback and only put pixels down inside.
- Colors take `#RRGGBB` strings directly; to follow the system light/dark theme, use the semantic colors from `@theme`.

## 2. Common drawing

The `p` below is the `Painter` from the `on_draw` callback.

**Shapes**:

```moonbit
p.fill_rect(x, y, w, h)                  // rectangle
p.fill_round_rect(x, y, w, h, radius)    // rounded rectangle (true arcs, no aliasing steps)
p.arc(cx, cy, radius, 0.0, 6.28318)      // circle / arc
p.fill()                                 // fill the current path
```

**Stroking**:

```moonbit
p.set_stroke_color("#4A5060")
p.set_line_width(2.0)
p.stroke_rect(x, y, w, h)
p.begin_path()
p.move_to(0.0, 0.0)
p.line_to(100.0, 40.0)
p.stroke()
p.set_line_cap(@render.LineCap::Round)      // caps: Butt / Round / Square
p.set_line_join(@render.LineJoin::Bevel)    // joins: Miter / Round / Bevel
p.set_dashes([10.0, 6.0], offset=8.0)       // dashes: on/off lengths + phase; [] restores solid
```

**Path objects** (record once, replay once — good for reusable polylines/curves):

```moonbit
let path = @render.Path::new()
path.move_to(0.0, 0.0)
path.line_to(40.0, 20.0)
path.bezier_curve_to(60.0, 0.0, 80.0, 40.0, 100.0, 20.0)
path.close()
p.draw_path(path)
```

**Linear gradient**:

```moonbit
let g = @render.Gradient::linear(0.0, 0.0, r.w, r.h)
g.add_stop(0.0, "#E8B34B")
g.add_stop(1.0, "#4BE888")
p.set_fill_gradient(g)
```

**Whole-layer opacity** (multiplied at draw time; overlaps darken naturally):

```moonbit
p.set_global_alpha(0.35)
p.arc(cx, cy, 34.0, 0.0, 6.28318)
p.fill()
p.set_global_alpha(1.0)
```

**Clipping & transforms** (must be wrapped in `save` / `restore`, or everything drawn afterwards goes crooked too):

```moonbit
p.save()
p.clip_rect(20.0, 20.0, 120.0, 120.0)  // what you draw now only lands in this block
p.fill_rect(0.0, 0.0, 400.0, 400.0)
p.restore()

p.save()
p.translate(100.0, 50.0)
p.rotate(0.349)                          // radians
p.fill_round_rect(-40.0, -12.0, 80.0, 24.0, 6.0)
p.restore()
```

**Bitmaps**:

```moonbit
let img = @render.Image::new_from_file("assets/logo.png")
if img.is_empty() { /* image missing: draw a placeholder frame, don't crash */ }
p.draw_image(img, x, y, w, h)                                // scale into the target rect
p.draw_image_from_rect(img, sx, sy, sw, sh, dx, dy, dw, dh)  // draw a slice of the source
```

**Text inside custom drawing** (text goes through `@text`'s own session; flush the painter once before alternating):

```moonbit
p.flush()
let _ = @text.draw_text_at(p, x, y, "custom text", 14.0, "#F0F0F0")
let _ = @text.draw_box_at(
  p, x, y, w, h, "Title", @text.Font::new("", 18.0), "#F0F0F0",
  align=@text.Center, valign=@text.Center,
)
```

Notes:

- `save` / `restore` come in pairs; `clip` and `translate` / `rotate` / `scale` all mutate painter state — pop them or the rest of the frame inherits it.
- `draw_image_from_rect` argument order is **source rect first, target rect second** (a real bug from the showcase where reversing it sent the image flying).
- Image decoding happens only in `new_from_file`; `draw_image` just scales and places, so it can live in the callback.
- The `draw_box_at` family returns measurements such as the occupied height; discard with `let _ =` when you don't need them.

## 3. Content changed: request a redraw

A custom-drawn area is **imperative**: keep state in a `Ref`, and after changing it call `@widget.invalidate()` to request one repaint frame.

```moonbit
let hue : Ref[Int] = Ref(0)

// inside a button callback:
hue.val = (hue.val + 1) % 3
@widget.invalidate()   // repaint one frame; a no-op with no host (e.g. tests)
```

Notes:

- Custom-drawn content does **not** participate in reactive bindings — changing a `Store` will not repaint the block; call `invalidate` yourself after the change.
- `invalidate` repaints one frame for the whole window; everyday custom drawing can just use it, no need to build your own frame loop.

## 4. Make the area respond to keyboard & mouse

By default a custom block only draws and does not respond. Wiring up interaction means attaching the matching callback fields, which combined with `invalidate` from the previous section forms the "event mutates state → repaint" loop. State maintenance for pointer, hover, cursor and focus is entirely handled by the host — no enter/leave handlers, no capture logic.

### Pointer: one `on_pointer` covers press/move/release/leave

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

### Hover / pressed / focused states: read the fields, draw the feedback

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

Reading the flags is the way for **custom blocks**. Ready-made widgets (`view` / `button` — the ones that go through the style system) don't read flags: declare the `@style.style(hover=...)` style slot instead, see [How-to guides](howto.md) §3.2. A custom block lays down every pixel itself and no default painter consumes style slots on its behalf, so it reads the host-maintained flags directly.

### Keyboard: declare `focus_id` first, then attach `on_key`

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

### Scroll wheel

```moonbit
w.on_scroll = Some(fn(ev : @widget.ScrollEvent) -> Bool {
  // ev.dx / ev.dy are the scroll amounts — the entry point for canvas zoom and pan
  true
})
```

### Putting it together: a mini sketchpad

Drag to draw lines, click to focus, Backspace undoes a stroke, Delete clears — the skeleton of paint programs / whiteboards / node editors is just these pieces (state outside the callbacks, events mutate state then `invalidate`, drawing repaints everything):

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

Drop it into the window skeleton from section 1 and it runs. Live demos for pointer/hover/cursor/keyboard: the showcase "Events & layout" page (source `examples/showcase/pages/events.mbt`).

## 5. Offscreen canvas & PNG export

A canvas that never enters the UI: `Canvas` creates an offscreen canvas, `get_painter` hands you the same kind of brush, and when you're done `end()` returns the session before exporting. The chart widget's PNG export is exactly this path.

```moonbit
let cv = @render.Canvas::new(800.0, 600.0)
let p = @render.Canvas::get_painter(cv)
p.set_fill_color("#20242C")
p.fill_rect(0.0, 0.0, 800.0, 600.0)
// ……same as "Common drawing"
p.end()                                  // must end when done (session slots are limited)
let _ = cv.write_to_file("out.png")      // only "png" for now; returns false on failure
```

## Next steps

- Live results for every technique: `cd examples/showcase && moon run .`, the "Canvas" page, source `examples/showcase/pages/canvas.mbt`; live keyboard & mouse interaction on the "Events & layout" page, source `examples/showcase/pages/events.mbt`.
- Widget assembly and state binding: [Components](components.md), [Declarative & reactivity](declarative.md); sizing and layout assignment: [Layout & styling](layout.md).
- Starting from zero: the [five-minute start](tutorial.md).
