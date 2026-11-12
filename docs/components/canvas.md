# Canvas

Keyboard & mouse interaction for custom blocks: [Custom draw & input](custom-draw.md).

**Live demo**: `cd examples/canvas && moon run .` opens the "Drawing board" window — every drawing technique (custom draw / line styles / dashes / clipping / corners / bitmaps) has a matching demo block; the source is `examples/canvas/pages/canvas.mbt`; the interactive board (mouse freehand + keyboard lines) is in `examples/canvas/pages/board.mbt`; rich text and fonts live on the "Basics" page of `examples/components` (source `examples/components/pages/basic.mbt`).

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

- **The node must resolve to a size**: set `set_width` / `set_height` explicitly, or let the parent layout assign it (`grow` etc., see [Layout & styling](../guide/layout.md)). No size = no area = nothing gets drawn.
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

## 4. Offscreen canvas & PNG export

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

- Live results for every technique: `cd examples/canvas && moon run .`, the "Drawing board" window, source `examples/canvas/pages/canvas.mbt`; rich text & fonts: the "Basics" page in `examples/components`; live keyboard & mouse interaction on the "Events & layout" page in `examples/components` (source `examples/components/pages/events.mbt`).
- Widget assembly and state binding: [Components overview](index.md), [Declarative & reactivity](../guide/declarative.md); sizing and layout assignment: [Layout & styling](../guide/layout.md).
- Starting from zero: [Getting started](../guide/tutorial.md).
