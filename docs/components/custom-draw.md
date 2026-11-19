# 自绘与键鼠

画法本身（形状、路径、渐变、位图、文字）见[画布](canvas.md)。自绘块响应键鼠：挂回调字段，配合 `invalidate` 形成「事件改状态 → 重绘」的循环；指针、悬停、光标、焦点的状态维护全由宿主接管，不写 enter/leave、不写捕获逻辑。

## 指针：一个 `on_pointer` 走完按下/移动/抬起/离开

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

## 悬停 / 按下 / 焦点态：读字段画反馈

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

读标志是**自绘块**的写法。现成控件（`view` / `button` 这类走样式系统的）不用读——用 `@style.style(hover=...)` 样式槽声明即可，见[样式与主题场景](../cookbook/theme.md#给控件交互样式)；自绘块的像素全由 `on_draw` 自己落，没有默认绘制替你消费样式槽，所以直接读宿主维护好的标志。

## 键盘：先声明 `focus_id`，再挂 `on_key`

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

## 滚轮

```moonbit
w.on_scroll = Some(fn(ev : @widget.ScrollEvent) -> Bool {
  // ev.dx / ev.dy 是滚量——画布缩放、平移的入口
  true
})
```

## 组起来：迷你画板

拖拽画线、点击聚焦、Backspace 撤销一笔、Delete 清空。状态放回调外，事件改完 `invalidate`，绘制全量重画；窗口骨架用[画布](canvas.md#一、挂一块自绘区域)的最小程序：

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

指针/悬停/光标/键盘的现场演示：components「事件与布局」页（源码 `examples/components/pages/events.mbt`）。
