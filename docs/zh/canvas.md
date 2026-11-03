# 画布与自绘

本篇讲怎么用：挂区域、常用画法、内容变了重绘、键鼠交互、离屏导出。


**现场演示**：`cd examples/showcase && moon run .` 打开「画布」页——本篇每段画法都有对应演示块，源码在 `examples/showcase/pages/canvas.mbt`。

## 公共前提

`moon.pkg` 的 import 用这一份（按需取舍）：

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

## 一、挂一块自绘区域

三步：`node_of_new` 给一个控件、设尺寸、挂 `on_draw` 回调。回调拿到的坐标是**区域本地坐标**（左上角 `(0,0)`），按 `r.w` / `r.h` 画，窗口缩放不变形。

完整可跑的最小程序：

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
    title="画布",
    width=360,
    height=220,
  ) {
    None => return
    Some(a) => a
  }
  app.run()
}
```

注意：

- **节点必须能算出尺寸**：显式 `set_width` / `set_height`，或交给父级布局分配（`grow` 等，见[布局样式](layout.md)）。没尺寸 = 没面积 = 什么都画不出来。
- `on_draw` 每次重绘都会调，**别在里面做重活**（读文件、解码大图、建大对象）；素材在回调外建好，回调里只落笔。
- 颜色直接给 `#RRGGBB` 字符串；要跟系统深浅走就用 `@theme` 的语义色。

## 二、常用画法

以下 `p` 均为 `on_draw` 回调里的 `Painter`。

**形状**：

```moonbit
p.fill_rect(x, y, w, h)                  // 矩形
p.fill_round_rect(x, y, w, h, radius)    // 圆角矩形（真圆弧，抗锯齿无台阶）
p.arc(cx, cy, radius, 0.0, 6.28318)      // 圆 / 圆弧
p.fill()                                 // 把当前路径填色
```

**描边**：

```moonbit
p.set_stroke_color("#4A5060")
p.set_line_width(2.0)
p.stroke_rect(x, y, w, h)
p.begin_path()
p.move_to(0.0, 0.0)
p.line_to(100.0, 40.0)
p.stroke()
p.set_line_cap(@render.LineCap::Round)      // 端点：Butt / Round / Square
p.set_line_join(@render.LineJoin::Bevel)    // 拐角：Miter / Round / Bevel
p.set_dashes([10.0, 6.0], offset=8.0)       // 虚线：on/off 段长 + 相位；[] 回实线
```

**路径对象**（先记录、一次回放，适合复用的折线/曲线）：

```moonbit
let path = @render.Path::new()
path.move_to(0.0, 0.0)
path.line_to(40.0, 20.0)
path.bezier_curve_to(60.0, 0.0, 80.0, 40.0, 100.0, 20.0)
path.close()
p.draw_path(path)
```

**线性渐变**：

```moonbit
let g = @render.Gradient::linear(0.0, 0.0, r.w, r.h)
g.add_stop(0.0, "#E8B34B")
g.add_stop(1.0, "#4BE888")
p.set_fill_gradient(g)
```

**整层透明**（绘制期乘算，重叠处自然叠深）：

```moonbit
p.set_global_alpha(0.35)
p.arc(cx, cy, 34.0, 0.0, 6.28318)
p.fill()
p.set_global_alpha(1.0)
```

**裁剪与变换**（必须包在 `save` / `restore` 里，否则后面的绘制全跟着歪）：

```moonbit
p.save()
p.clip_rect(20.0, 20.0, 120.0, 120.0)  // 之后画的只落进这块
p.fill_rect(0.0, 0.0, 400.0, 400.0)
p.restore()

p.save()
p.translate(100.0, 50.0)
p.rotate(0.349)                          // 弧度
p.fill_round_rect(-40.0, -12.0, 80.0, 24.0, 6.0)
p.restore()
```

**位图**：

```moonbit
let img = @render.Image::new_from_file("assets/logo.png")
if img.is_empty() { /* 图不在位：画个占位框，不崩 */ }
p.draw_image(img, x, y, w, h)                                // 缩放到目标矩形
p.draw_image_from_rect(img, sx, sy, sw, sh, dx, dy, dw, dh)  // 取源图一块来画
```

**自绘里写文字**（文字走 `@text` 自己的会话，与画笔交替前先 `flush` 一次）：

```moonbit
p.flush()
let _ = @text.draw_text_at(p, x, y, "自绘文本", 14.0, "#F0F0F0")
let _ = @text.draw_box_at(
  p, x, y, w, h, "标题", @text.Font::new("", 18.0), "#F0F0F0",
  align=@text.Center, valign=@text.Center,
)
```

注意：

- `save` / `restore` 成对出现；`clip` 与 `translate` / `rotate` / `scale` 都改画笔状态，出栈才不影响后续。
- `draw_image_from_rect` 参数序是**源矩形在前、目标矩形在后**（showcase 里真踩过写反把图画飞的坑）。
- 图片解码只发生在 `new_from_file`；`draw_image` 只做缩放落位，可以放在回调里。
- `draw_box_at` 一族返回实际占用高度等读数，用不到就 `let _ =` 收掉。

## 三、内容变了：请求重绘

自绘区域是**命令式语义**：状态放 `Ref`，改完调 `@widget.invalidate()` 请求重画一帧。

```moonbit
let hue : Ref[Int] = Ref(0)

// 按钮回调里：
hue.val = (hue.val + 1) % 3
@widget.invalidate()   // 重画一帧；无宿主（如测试环境）时是空操作
```

注意：

- 自绘内容**不进响应式绑定**——`Store` 改了不会自动重画自绘块，改完自己 `invalidate`。
- `invalidate` 是全窗重画一帧，常规自绘场景直接用，不必自己攒帧循环。

## 四、让自绘区域响应键鼠

自绘块默认只画不响应；接交互就是给控件挂对应的回调字段，配合上一节的 `invalidate` 形成「事件改状态 → 重绘」的循环。指针、悬停、光标、焦点的状态维护全由宿主接管，不写 enter/leave、不写捕获逻辑。

### 指针：一个 `on_pointer` 走完按下/移动/抬起/离开

```moonbit
w.on_pointer = Some(
  fn(self : @widget.Widget, ev : @widget.PointerEvent) -> Bool {
    match ev.kind {
      @widget.PointerKind::Down => { /* 记起点 */ true }
      @widget.PointerKind::Move => { /* 拖拽中采点 */ true }
      @widget.PointerKind::Up => { /* 收笔 */ true }
      @widget.PointerKind::Leave => false
    }
  },
)
```

要点（全是宿主替你做掉的）：

- `ev.x` / `ev.y` 投递前已换算成**本地坐标**（`Leave` 保持窗口坐标）。
- **命中即捕获**：按下到松开之间的 Move/Up 全投给被按下的控件，指针移出矩形也不丢（坐标可为负）——拖拽手柄、框选不用自己写捕获。
- 返回 `true` = 消费该事件（祖先链停止冒泡）；`false` = 继续往祖先传。
- 双击/三击另挂 `on_double_click` / `on_triple_click`（400 ms / 4 px 阈值判定），与 `on_pointer` 共存。

### 悬停 / 按下 / 焦点态：读字段画反馈

`hovered` / `pressed` / `focused` 三个标志由宿主维护，在 `on_draw` 里现读现画：

```moonbit
w.on_draw = Some(
  fn(self : @widget.Widget, p : @render.Painter, r : @base.Rect) -> Unit {
    p.set_fill_color(if self.hovered { "#2A303C" } else { "#20242C" })
    p.fill_rect(0.0, 0.0, r.w, r.h)
    p.set_stroke_color(if self.focused { "#E8B34B" } else { "#4A5060" })
    p.stroke_rect(0.0, 0.0, r.w, r.h)   // 焦点环自己画
  },
)
```

悬停要起停定时器这类副作用的挂 `on_hover_change(w, hovered)`；「失焦即提交」类挂 `on_focus_change(w, focused)`。光标形状一行声明：`w.cursor = @widget.CURSOR_HAND`（全表 `CURSOR_DEFAULT / HAND / TEXT / RESIZE_H / RESIZE_V / HIDDEN / GRAB / GRABBING / NOT_ALLOWED`，宿主取悬停路径最深的非零请求）。

读标志是**自绘块**的写法。现成控件（`view` / `button` 这类走样式系统的）不用读——用 `@style.style(hover=...)` 样式槽声明即可，见[场景教程](howto.md) §3.2；自绘块的像素全由 `on_draw` 自己落，没有默认绘制替你消费样式槽，所以直接读宿主维护好的标志。

### 键盘：先声明 `focus_id`，再挂 `on_key`

```moonbit
w.focus_id = 1   // >0 才可聚焦；树序即 Tab 序，宿主自动维护；点击即聚焦
w.on_key = Some(fn(ev : @widget.KeyEvent) -> Bool {
  if ev.keysym == @base.KS_DELETE {
    true            // 返回 true = 消费
  } else {
    false
  }
})
```

要点：

- 键只投给**当前焦点控件**（及其带 `on_key` 的祖先链）；宿主只投按下，「按住…松手停」形态的组件挂 `on_key_release`（抬起只投这条）。
- `ev.keysym` 是平台虚拟键码：命名键用 `@base` 的 `KS_*` 常量（`KS_RETURN` / `KS_LEFT` / `KS_ESCAPE`…），可打印字符在 32–126 区间直接 `keysym.to_char()`。
- 修饰键是位掩码 `ev.mods`：`@base.MOD_SHIFT / MOD_CTRL / MOD_ALT / MOD_META` 按位与判断。
- 全窗快捷键（焦点在哪都要响应的）走宿主兜底通道：`app.add_key_fallthrough(...)`（`app` 是 `mount_window` 的返回值），焦点链没人消费才轮到它。

### 滚轮

```moonbit
w.on_scroll = Some(fn(ev : @widget.ScrollEvent) -> Bool {
  // ev.dx / ev.dy 是滚量——画布缩放、平移的入口
  true
})
```

### 组起来：迷你画板

拖拽画线、点击聚焦、Backspace 撤销一笔、Delete 清空——画板/白板/节点编辑器这类软件的骨架就这几段（状态放回调外，事件改完 `invalidate`，绘制全量重画）：

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
      let _ = strokes.val.pop()   // 撤销一笔
      @widget.invalidate()
      true
    } else if ev.keysym == @base.KS_DELETE {
      strokes.val.clear()         // 清空
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
      p.stroke_rect(0.0, 0.0, r.w, r.h)   // 聚焦环
      p.set_stroke_color("#4B8BE8")
      p.set_line_width(2.0)
      p.set_line_cap(@render.LineCap::Round)
      p.set_line_join(@render.LineJoin::Round)
      for s in strokes.val {
        if s.length() == 1 {
          p.arc(s[0].0, s[0].1, 1.5, 0.0, 6.28318)   // 单点也落墨
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

放进第一节「挂一块自绘区域」的窗口骨架里即可跑。指针/悬停/光标/键盘的现场演示：showcase「事件与布局」页（源码 `examples/showcase/pages/events.mbt`）。

## 五、离屏画布与导出 PNG

不进界面的画布：`Canvas` 建离屏画布，`get_painter` 拿同一支画笔，画完 `end()` 交还会话、再导出。图表控件的 PNG 导出就是这条路。

```moonbit
let cv = @render.Canvas::new(800.0, 600.0)
let p = @render.Canvas::get_painter(cv)
p.set_fill_color("#20242C")
p.fill_rect(0.0, 0.0, 800.0, 600.0)
// ……「常用画法」同款
p.end()                                  // 用完必须 end（会话槽有限）
let _ = cv.write_to_file("out.png")      // 目前只支持 "png"，失败返回 false
```

## 下一步

- 每段画法的现场效果：`cd examples/showcase && moon run .`「画布」页，源码 `examples/showcase/pages/canvas.mbt`；键鼠交互的现场效果在「事件与布局」页，源码 `examples/showcase/pages/events.mbt`。
- 控件拼装与状态绑定：[组件速查](components.md)、[声明式与响应式](declarative.md)；尺寸与布局分配：[布局样式](layout.md)。
- 从零起步：[五分钟上手](tutorial.md)。
