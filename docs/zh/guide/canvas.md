# 画布

让自绘块响应键鼠见[自绘与键鼠](custom-draw.md)。


**现场演示**：`cd examples/showcase && moon run .` 打开「画布」页——每段画法都有对应演示块，源码在 `examples/showcase/pages/canvas.mbt`。

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

键鼠交互（指针、悬停、焦点、滚轮、迷你画板）单独成篇：见[自绘与键鼠](custom-draw.md)。

## 四、离屏画布与导出 PNG

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

- 每段画法的现场效果：`cd examples/showcase && moon run .`「画布」页，源码 `examples/showcase/pages/canvas.mbt`。
- 控件拼装与状态绑定：[组件总览](../components/index.md)、[声明式与响应式](declarative.md)；尺寸与布局分配：[布局样式](layout.md)。
- 从零起步：[五分钟上手](tutorial.md)。
