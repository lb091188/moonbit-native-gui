// 画布与富文本页：Painter 自绘 × AttributedText 富文本。
//
// 四条口径：
// ① 自绘画布用 `@widget.node_of_new` 挂 on_draw + yoga 尺寸参数；
// ② 重绘走进程级 `@widget.invalidate()`（宿主装的是 host_repaint_all：所有在窗
//    置脏 + 唤醒平台泵）；
// ③ 「系统语义色」一行演示两个真实存在的系统读数——深浅（sys_color_scheme，
//    即共享 App 的 dark_mode 来源）与主色（sys_accent，即 accent 来源），
//    且走 bind 直连共享状态，跟随开关开着时系统配色一变它也变；
// ④ 富文本段演示「渐变」（Painter.set_fill_gradient）。

///|
/// 画布页。页内私有状态（色相偏移/渐变开关/富文本两个格式开关）不进共享 App。

///|
/// 字体演示的自绘块：左右两盒同一段文字，右盒把末尾「28」设成 28px 区间字体——
/// 行盒必须按混排口径抬起来（盒高取 `AttributedText::line_height`），否则大字被裁；
/// 下方一行演示族名回退（不存在的族退到 monospace）。
fn font_mix_widget() -> @widget.Node {
  @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget {
    w.node.set_width(@yoga.fixed(400.0))
    w.node.set_height(@yoga.fixed(96.0))
    w.on_draw = Some(fn(_w : @widget.Widget, p : @render.Painter, r : @base.Rect) -> Unit {
      p.set_fill_color(@theme.theme_bg_panel())
      p.fill_rect(0.0, 0.0, r.w, r.h)
      let base = @text.AttributedText::new(@shared.tx("基准 Base 28"))
      let mixed = @text.AttributedText::new(@shared.tx("基准 Base 28"))
      // 「28」是末尾两字节起、长 2 字节（字节下标口径，与编辑内核同源）
      let nb = @utf8.encode(@shared.tx("基准 Base 28"))
      let at = nb.length() - 2
      mixed.set_font_for(@text.Font::new("", 28.0), at, nb.length())
      let lh_base = match base.line_height() {
        Some(v) => v.to_double()
        None => 20.0
      }
      let lh_mixed = match mixed.line_height() {
        Some(v) => v.to_double()
        None => 20.0
      }
      // 两个盒子的边框：右盒没被抬起来就是行高口径错了
      p.set_stroke_color(@theme.theme_border())
      p.set_line_width(1.0)
      p.stroke_rect(0.0, 0.0, 190.0, lh_base)
      p.stroke_rect(198.0, 0.0, 190.0, lh_mixed)
      p.flush()
      let _ = base.draw_at(p, 4.0, 0.0, 186.0, lh_base)
      let _ = mixed.draw_at(p, 202.0, 0.0, 186.0, lh_mixed)
      let fam = @text.resolve_family(["绝对没有的族 Qzz", "monospace"])
      let fam_count = match @text.families() {
        Some(a) => a.length()
        None => 0
      }
      let _ = @text.draw_text_at(
        p,
        4.0,
        72.0,
        @shared.tr_with(
          "dyn.fallback_family",
          [("f", fam), ("n", fam_count.to_string())],
          "回退族名：\{fam}（可用字体族 \{fam_count} 个）",
        ),
        12.0,
        @theme.theme_text_secondary(),
      )
    })
    w
  })
}

pub fn page_canvas(app : @shared.App) -> @widget.Node {
  let hue : Ref[Int] = Ref(0)
  let grad_on : Ref[Bool] = Ref(false)
  // 富文本两个格式开关
  let rt_wrap : Ref[Bool] = Ref(true)
  let rt_ellipsis : Ref[Bool] = Ref(false)
  // 自绘场景（命令式语义：Ref + invalidate，不做响应式包装）
  let draw_scene = fn(p : @render.Painter, r : @base.Rect) -> Unit {
    p.set_fill_color("#20242C")
    p.fill_rect(0.0, 0.0, r.w, r.h)
    let colors = ["#E8B34B", "#4B8BE8", "#4BE888"]
    for i in 0..<3 {
      if grad_on.val && i == 1 {
        let g = @render.Gradient::linear(0.0, 0.0, r.w, r.h)
        g.add_stop(0.0, colors[(i + hue.val) % 3])
        g.add_stop(1.0, "#4BE888")
        p.set_fill_gradient(g)
      } else {
        p.set_fill_color(colors[(i + hue.val) % 3])
      }
      p.arc(
        r.w * (0.25 + 0.25 * i.to_double()),
        r.h * 0.43,
        60.0,
        0.0,
        6.28318,
      )
      p.fill()
    }
    p.set_stroke_color("#4A5060")
    p.set_line_width(1.0)
    for k in 0..<9 {
      p.stroke_rect(24.0, r.h * 0.68 + k.to_double() * 10.0, r.w - 48.0, 1.0)
    }
    // 文本走 text 自己的会话，与 Painter 会话交替前刷一次
    p.flush()
    let _ = @text.draw_box_at(
      p,
      24.0,
      r.h - 44.0,
      r.w - 48.0,
      30.0,
      "MoonBit × libyue 自绘文本",
      @text.Font::new("", 18.0),
      "#F0F0F0",
      align=@text.Center,
      valign=@text.Center,
      wrap=false,
    )
  }
  // 富文本对象：整段粗体 + 前 6 字 24px Black + 8..11 号红
  let rt = @text.AttributedText::new(
    "MoonBit 富文本：这段文字有范围着色与粗体。",
    wrap=rt_wrap.val,
    ellipsis=rt_ellipsis.val,
  )
  rt.set_font(@text.Font::new("", 20.0, weight=@text.Bold))
  rt.set_font_for(@text.Font::new("", 24.0, weight=@text.Black), 0, 6)
  rt.set_color("#356AA0")
  rt.set_color_for("#E5534B", 8, 11)
  @shared.page([
    @shared.section(
      "自绘",
      "Painter 自绘",
      "fill_rect / arc / fill / stroke_rect / draw_text 基础绘制 + 线性渐变填充。场景按控件实际尺寸画（缩放窗口不变形）；「旋转色相」循环三种主色，「渐变」给中间圆上线性渐变。",
      [
        @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget {
          w.node.set_width(@yoga.fixed(640.0))
          w.node.set_height(@yoga.fixed(300.0))
          w.on_draw = Some(fn(
            _self : @widget.Widget,
            p : @render.Painter,
            r : @base.Rect,
          ) -> Unit {
            draw_scene(p, r)
          })
          w
        }),
        @ui.row(
          [
            @ui.button(@shared.tx("旋转色相"), on_click=fn() {
              hue.val = (hue.val + 1) % 3
              @widget.invalidate()
            }),
            @ui.button(@shared.tx("渐变开关"), variant=@ui.Soft, on_click=fn() {
              grad_on.val = !grad_on.val
              @widget.invalidate()
            }),
          ],
          column_gap=8.0,
        ),
      ],
      code=[
        "let draw = fn(p : @render.Painter, r : @base.Rect) -> Unit {",
        "  p.set_fill_color(\"#20242C\")",
        "  p.fill_rect(0.0, 0.0, r.w, r.h)",
        "  p.arc(r.w * 0.25, r.h * 0.43, 60.0, 0.0, 6.28318)",
        "  p.fill()",
        "  p.set_stroke_color(\"#4A5060\")",
        "  p.stroke_rect(24.0, 200.0, r.w - 48.0, 1.0)",
        "  p.flush() // 切 text 会话前刷一次",
        "  let _ = @text.draw_box_at(p, 24.0, r.h - 44.0, r.w - 48.0, 30.0,",
        "    \"自绘文本\", font, \"#F0F0F0\", align=@text.Center)",
        "}",
        "@widget.node_of_new(fn(w) {",
        "  w.node.set_width(@yoga.fixed(640.0))",
        "  w.on_draw = Some(fn(_s, p, r) { draw(p, r) })",
        "  w",
        "})",
        "// 内容变了请求重画一帧（无宿主时是空操作）",
        "@widget.invalidate()",
      ],
    ),
    @shared.section(
      "富文本",
      "富文本 AttributedText",
      "范围字体/颜色（0-6 号 24px Black、8-11 号红色）+ 换行/省略号开关 + 文本改写（属性保留）。",
      [
        @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget {
          w.node.set_width(@yoga.fixed(640.0))
          w.node.set_height(@yoga.fixed(120.0))
          w.on_draw = Some(fn(
            _self : @widget.Widget,
            p : @render.Painter,
            r : @base.Rect,
          ) -> Unit {
            p.set_fill_color(@theme.theme_bg_panel())
            p.fill_rect(0.0, 0.0, r.w, r.h)
            p.set_stroke_color(@theme.theme_border())
            p.set_line_width(1.0)
            p.stroke_rect(0.0, 0.0, r.w, r.h)
            p.flush()
            let _ = rt.draw_at(p, 10.0, 20.0, r.w - 20.0, r.h - 30.0)
          })
          w
        }),
        @ui.row(
          [
            @ui.button(@shared.tx("换行开关"), on_click=fn() {
              rt_wrap.val = !rt_wrap.val
              rt.set_format({
                align: @text.Start,
                valign: @text.Start,
                wrap: rt_wrap.val,
                ellipsis: rt_ellipsis.val,
              })
              @widget.invalidate()
            }),
            @ui.button(@shared.tx("省略号开关"), variant=@ui.Soft, on_click=fn() {
              rt_ellipsis.val = !rt_ellipsis.val
              rt.set_format({
                align: @text.Start,
                valign: @text.Start,
                wrap: true,
                ellipsis: rt_ellipsis.val,
              })
              @widget.invalidate()
            }),
            @ui.button(@shared.tx("改写文本"), variant=@ui.Solid, on_click=fn() {
              rt.set_text(@shared.tx("文本已替换 ✓（范围属性保留）"))
              @widget.invalidate()
            }),
          ],
          column_gap=8.0,
        ),
        // 系统读数走共享状态：dark_mode 的来源是 sys_color_scheme、
        // accent 的来源是 sys_accent（跟随开关开时每 2 秒被 main 的 tick 刷新）
        @ui.row(
          [
            @ui.bind_label(app.dark_mode, fn(d) {
              if d {
                @shared.tx("系统深浅：深色")
              } else {
                @shared.tx("系统深浅：浅色")
              }
            }),
            @ui.bind_label(app.accent, fn(a) {
              if a.length() == 0 {
                @shared.tx("系统主色：（无，回落内置）")
              } else {
                "系统主色：\{a}"
              }
            }),
          ],
          column_gap=16.0,
        ),
      ],
      code=[
        "let rt = @text.AttributedText::new(",
        "  \"MoonBit 富文本：这段文字有范围着色与粗体。\", wrap=true)",
        "rt.set_font(@text.Font::new(\"\", 20.0, weight=@text.Bold))",
        "rt.set_font_for(@text.Font::new(\"\", 24.0, weight=@text.Black), 0, 6)",
        "rt.set_color(\"#356AA0\")",
        "rt.set_color_for(\"#E5534B\", 8, 11)",
        "rt.set_format({",
        "  align: @text.Start, valign: @text.Start,",
        "  wrap: false, ellipsis: true,",
        "})",
        "rt.set_text(\"文本已替换 ✓（范围属性保留）\")",
        "// 画：Painter 会话里直接落位",
        "let _ = rt.draw_at(p, 10.0, 20.0, 600.0, 90.0)",
      ],
    ),

    @shared.section(
      "字体",
      "字体回退与混排行高",
      "左盒只有基准字体，右盒把末尾「28」换成 28px——两个盒子的盒高都取 `line_height()` 的混排口径，右盒必须被抬起来；不存在的族名经 `resolve_family` 回退（CSS 列表口径）。",
      [
        @ui.view([font_mix_widget()], background_color="bg_panel", border_color="border", padding=8.0, class=[@style.style(border_radius=6.0)]),
        // 字距：同一句话两档 `letter_spacing`，量宽与绘制同源（只吃在字符之间）
        @ui.row(
          [
            @ui.text(@shared.tx("字距 0：MoonBit GUI 字距对照"), role=@ui.Body),
            @ui.text(
              @shared.tx("字距 4：MoonBit GUI 字距对照"),
              role=@ui.Body,
              class=[@style.style(letter_spacing=4.0)],
            ),
          ],
          column_gap=24.0,
          align_items=@yoga.AlignItems::Center,
        ),
      ],
      code=[
        "let mixed = @text.AttributedText::new(\"基准 Base 28\")",
        "// 区间属性：字节下标口径，后设覆盖先设",
        "mixed.set_font_for(@text.Font::new(\"\", 28.0), at, at + 2)",
        "mixed.line_height()  // 基准与区间字体一起算，行盒 = max ascent + max descent",
        "@text.resolve_family([\"没有的族\", \"monospace\"])  // 回退",
      ],
    ),

    @shared.section(
      "线型与路径",
      "端点/拐角与 Path 对象直通",
      "W35 补的 Painter 门面：`set_line_cap(Butt/Round/Square)` 与 `set_line_join(Miter/Round/Bevel)` 走 Cairo 直连；`draw_path(Path)` 把预先记录的 move_to/line_to/曲线序列一次回放进画笔。上排看端点、下排看拐角，右侧是用 Path 对象画的锯齿折线。纯软栅后端暂不吃端点/拐角扩展（描边框仍在，参数只存 state）。",
      [
        @ui.view(
          [line_style_widget()],
          background_color="bg_panel",
          border_color="border",
          padding=8.0,
          class=[@style.style(border_radius=6.0)],
        ),
      ],
      code=[
        "p.set_line_cap(@render.LineCap::Round)   // 端点：Butt/Round/Square",
        "p.set_line_join(@render.LineJoin::Bevel) // 拐角：Miter/Round/Bevel",
        "",
        "// Path 对象直通：先记录，一次回放",
        "let path = @render.Path::new()",
        "path.move_to(0.0, 0.0)",
        "path.line_to(40.0, 20.0)",
        "path.bezier_curve_to(60.0, 0.0, 80.0, 40.0, 100.0, 20.0)",
        "path.close()",
        "p.draw_path(path)",
      ],
    ),

    @shared.section(
      "虚线",
      "set_dashes 图案与相位",
      "`set_dashes(图案, 相位)`：数组是 on/off 交替的段长（逻辑像素，跟缩放走），相位是图案的起笔偏移；`set_dashes([])` 回实线。三行分别是 `[10, 6]`、同图案 `offset=8`、清空回实线——第二行整条往后错 8px，段数不变。虚线进 `save/restore`，嵌套绘制不会串到下一条线。纯光栅后端只存 state（描边框仍在），Cairo 档才是真断段。",
      [
        @ui.view(
          [dash_widget()],
          background_color="bg_panel",
          border_color="border",
          padding=8.0,
          class=[@style.style(border_radius=6.0)],
        ),
      ],
      code=[
        "p.set_line_width(2.0)",
        "p.set_dashes([10.0, 6.0])          // 10 实 6 空",
        "p.stroke_rect(20.0, 20.0, 460.0, 1.0)",
        "p.set_dashes([10.0, 6.0], offset=8.0) // 相位后移 8px",
        "p.set_dashes([])                   // 回实线",
      ],
    ),

    @shared.section(
      "裁剪与变换",
      "clip_rect / translate / rotate / scale",
      "左块先 `clip_rect` 再画一串越界的圆与横线——超出矩形的部分被切掉，只留 120×120 那块；右块用 `translate` 挪原点、`rotate` 转 20°、`scale` 放大 1.6 倍各画一个圆角块。三者都改当前变换矩阵，必须包在 `save` / `restore` 里，否则后面的绘制全跟着歪。",
      [
        @ui.view(
          [clip_transform_widget()],
          background_color="bg_panel",
          border_color="border",
          padding=8.0,
          class=[@style.style(border_radius=6.0)],
        ),
      ],
      code=[
        "p.save()",
        "p.clip_rect(20.0, 20.0, 120.0, 120.0)  // 之后画的都只在这块里",
        "p.fill_rect(0.0, 0.0, 400.0, 400.0)",
        "p.restore()                            // 裁剪跟着出栈",
        "",
        "p.save()",
        "p.translate(380.0, 60.0)",
        "p.rotate(0.349)                        // 20°",
        "p.fill_round_rect(-60.0, -24.0, 120.0, 48.0, 8.0)",
        "p.restore()",
        "p.save()",
        "p.translate(380.0, 170.0)",
        "p.scale(1.6, 1.6)",
        "p.fill_round_rect(-40.0, -12.0, 80.0, 24.0, 6.0)",
        "p.restore()",
      ],
    ),

    @shared.section(
      "圆角与合成",
      "圆角半径、抗锯齿与整层 alpha",
      "上排三个同尺寸块只有圆角不同（0 / 8 / 24）：圆弧走真圆弧 + 1px 抗锯齿，斜边不出现台阶；圆角关掉（侧栏那个圆角开关）时退直角。下排是 `set_global_alpha`：同样三个圆叠着画，右边那次整层 35% —— alpha 是**绘制期乘算**，不是把颜色调淡，所以重叠处会自己叠深。",
      [
        @ui.view(
          [round_alpha_widget()],
          background_color="bg_panel",
          border_color="border",
          padding=8.0,
          class=[@style.style(border_radius=6.0)],
        ),
      ],
      code=[
        "// 半径：0 / 8 / 24，同一个 96×56 块",
        "p.fill_round_rect(x, y, 96.0, 56.0, 8.0)",
        "p.stroke_round_rect(x, y, 96.0, 56.0, 8.0)",
        "",
        "// 整层 alpha：绘制期乘算，重叠处自然叠深",
        "p.set_global_alpha(0.35)",
        "p.arc(cx, cy, 34.0, 0.0, 6.28318)",
        "p.fill()",
        "p.set_global_alpha(1.0)",
      ],
    ),

    @shared.section(
      "位图",
      "PNG / JPEG / GIF 首帧与缩放",
      "`Image::new_from_file` 解 PNG / JPEG / GIF（动图只取首帧，动图播放见「过渡与效果」页），`draw_image` 缩放到目标矩形。下面同一张 PNG 画三档尺寸、再画 GIF 的首帧：放大靠双线性，图的宽高比按目标矩形走。",
      [
        @ui.view(
          [image_widget()],
          background_color="bg_panel",
          border_color="border",
          padding=8.0,
          class=[@style.style(border_radius=6.0)],
        ),
      ],
      code=[
        "let img = @render.Image::new_from_file(\"assets/icon.png\")",
        "if img.is_empty() { /* 图不在位：跳过，不崩 */ }",
        "p.draw_image(img, 24.0, 24.0, 64.0, 64.0)    // 缩到 64",
        "p.draw_image(img, 120.0, 24.0, 128.0, 128.0) // 缩到 128",
        "p.draw_image_from_rect(img, 280.0, 24.0, 120.0, 120.0, 0.0, 0.0, 40.0, 40.0)",
      ],
    ),
  ])
}

///|
/// 线型演示块：三行端点、三行拐角、右侧一条 Path 折线。
fn line_style_widget() -> @widget.Node {
  @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget {
    w.node.set_width(@yoga.fixed(520.0))
    w.node.set_height(@yoga.fixed(220.0))
    w.on_draw = Some(fn(_w : @widget.Widget, p : @render.Painter, r : @base.Rect) -> Unit {
      p.set_fill_color(@theme.theme_bg_panel())
      p.fill_rect(0.0, 0.0, r.w, r.h)
      p.set_stroke_color(@theme.theme_primary())
      p.set_line_width(14.0)
      // 端点：三条同样宽的短横线
      let caps : Array[@render.LineCap] = [
        @render.LineCap::Butt,
        @render.LineCap::Round,
        @render.LineCap::Square,
      ]
      p.set_line_join(@render.LineJoin::Miter)
      for i in 0..<3 {
        p.set_line_cap(caps[i])
        p.begin_path()
        p.move_to(20.0, 30.0 + i.to_double() * 28.0)
        p.line_to(180.0, 30.0 + i.to_double() * 28.0)
        p.stroke()
      }
      // 拐角：三个 V 形
      let joins : Array[@render.LineJoin] = [
        @render.LineJoin::Miter,
        @render.LineJoin::Round,
        @render.LineJoin::Bevel,
      ]
      p.set_line_cap(@render.LineCap::Butt)
      for i in 0..<3 {
        p.set_line_join(joins[i])
        let y = 130.0 + i.to_double() * 28.0
        p.begin_path()
        p.move_to(20.0, y)
        p.line_to(50.0, y + 18.0)
        p.line_to(80.0, y)
        p.stroke()
      }
      // Path 对象：用记录序列画右侧锯齿
      let path = @render.Path::new()
      path.move_to(230.0, 30.0)
      for i in 1..<9 {
        let x = 230.0 + i.to_double() * 28.0
        let y = if i % 2 == 0 { 30.0 } else { 90.0 }
        path.line_to(x, y)
      }
      p.set_line_join(@render.LineJoin::Round)
      p.set_line_width(3.0)
      p.draw_path(path)
      p.stroke()
    })
    w
  })
}

///|
/// 示例资源路径候选（`moon run` 可能从仓库根或 `examples/` 起跑，逐个探测）。
fn canvas_asset(name : String) -> String {
  for c in [
    "examples/showcase/assets/" + name,
    "assets/" + name,
    "showcase/assets/" + name,
  ] {
    if @sys.sys_path_exists(c) {
      return c
    }
  }
  "examples/showcase/assets/" + name
}

///|
/// 虚线演示块：三行同一条横线，只有图案/相位不同。
fn dash_widget() -> @widget.Node {
  @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget {
    w.node.set_width(@yoga.fixed(520.0))
    w.node.set_height(@yoga.fixed(170.0))
    w.on_draw = Some(fn(_w : @widget.Widget, p : @render.Painter, r : @base.Rect) -> Unit {
      p.set_fill_color(@theme.theme_bg_panel())
      p.fill_rect(0.0, 0.0, r.w, r.h)
      p.set_stroke_color(@theme.theme_primary())
      p.set_line_width(2.0)
      // 三行：默认图案 / 相位后移 / 清空回实线
      let rows : Array[(Array[Double], Double)] = [
        ([10.0, 6.0], 0.0),
        ([10.0, 6.0], 8.0),
        ([], 0.0),
      ]
      for i in 0..<3 {
        let (pat, off) = rows[i]
        p.set_dashes(pat, offset=off)
        p.begin_path()
        p.move_to(24.0, 46.0 + i.to_double() * 44.0)
        p.line_to(496.0, 46.0 + i.to_double() * 44.0)
        p.stroke()
      }
      p.set_dashes([])
      p.flush()
      let notes : Array[String] = [
        @shared.tx("set_dashes([10, 6])"),
        @shared.tx("同一图案，offset = 8"),
        @shared.tx("set_dashes([]) 回实线"),
      ]
      for i in 0..<3 {
        let _ = @text.draw_text_at(
          p,
          24.0,
          14.0 + i.to_double() * 44.0,
          notes[i],
          11.0,
          @theme.theme_text_secondary(),
        )
      }
    })
    w
  })
}

///|
/// 裁剪与变换演示块：左边裁一块、右边转一个、放大一个。
fn clip_transform_widget() -> @widget.Node {
  @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget {
    w.node.set_width(@yoga.fixed(520.0))
    w.node.set_height(@yoga.fixed(240.0))
    w.on_draw = Some(fn(_w : @widget.Widget, p : @render.Painter, r : @base.Rect) -> Unit {
      p.set_fill_color(@theme.theme_bg_panel())
      p.fill_rect(0.0, 0.0, r.w, r.h)
      // 左：裁剪框
      p.save()
      p.clip_rect(24.0, 40.0, 140.0, 140.0)
      p.set_fill_color(@theme.theme_primary_light())
      p.fill_rect(0.0, 0.0, 300.0, 240.0)
      p.set_fill_color(@theme.theme_primary())
      for i in 0..<5 {
        p.arc(40.0 + i.to_double() * 44.0, 110.0, 40.0, 0.0, 6.28318)
        p.fill()
      }
      p.restore()
      // 裁剪框边界（画在裁剪外面，看清切口）
      p.set_stroke_color(@theme.theme_border())
      p.set_line_width(1.0)
      p.stroke_rect(24.0, 40.0, 140.0, 140.0)
      // 右：变换三连
      p.set_fill_color(@theme.theme_primary())
      p.save()
      p.translate(330.0, 90.0)
      p.rotate(0.349)
      p.fill_round_rect(-70.0, -28.0, 140.0, 56.0, 8.0)
      p.restore()
      p.save()
      p.translate(330.0, 186.0)
      p.scale(1.6, 1.6)
      p.set_fill_color(@theme.theme_success())
      p.fill_round_rect(-46.0, -14.0, 92.0, 28.0, 6.0)
      p.restore()
      p.flush()
      let _ = @text.draw_text_at(
        p,
        24.0,
        14.0,
        @shared.tx("clip_rect(24, 40, 140, 140)"),
        11.0,
        @theme.theme_text_secondary(),
      )
      let _ = @text.draw_text_at(
        p,
        250.0,
        14.0,
        @shared.tx("translate + rotate(20°) / scale(1.6)"),
        11.0,
        @theme.theme_text_secondary(),
      )
    })
    w
  })
}

///|
/// 圆角与整层 alpha：上排三档半径，下排叠圆（右半 35% alpha）。
fn round_alpha_widget() -> @widget.Node {
  @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget {
    w.node.set_width(@yoga.fixed(520.0))
    w.node.set_height(@yoga.fixed(220.0))
    w.on_draw = Some(fn(_w : @widget.Widget, p : @render.Painter, r : @base.Rect) -> Unit {
      p.set_fill_color(@theme.theme_bg_panel())
      p.fill_rect(0.0, 0.0, r.w, r.h)
      // 上排：半径 0 / 8 / 24
      let radii : Array[Double] = [0.0, 8.0, 24.0]
      for i in 0..<3 {
        let x = 24.0 + i.to_double() * 160.0
        p.set_fill_color(@theme.theme_primary_light())
        p.fill_round_rect(x, 34.0, 140.0, 56.0, radii[i])
        p.set_stroke_color(@theme.theme_primary())
        p.set_line_width(1.0)
        p.stroke_round_rect(x, 34.0, 140.0, 56.0, radii[i])
      }
      // 下排：三个圆，前两个不透明、后两个叠 35%
      p.set_fill_color(@theme.theme_primary())
      p.set_global_alpha(1.0)
      for i in 0..<2 {
        p.arc(90.0 + i.to_double() * 50.0, 158.0, 34.0, 0.0, 6.28318)
        p.fill()
      }
      p.set_global_alpha(0.35)
      for i in 0..<2 {
        p.arc(240.0 + i.to_double() * 50.0, 158.0, 34.0, 0.0, 6.28318)
        p.fill()
      }
      p.set_global_alpha(1.0)
      p.flush()
      let _ = @text.draw_text_at(
        p,
        24.0,
        14.0,
        @shared.tx("圆角 0 / 8 / 24（真圆弧 + 1px 抗锯齿）"),
        11.0,
        @theme.theme_text_secondary(),
      )
      let _ = @text.draw_text_at(
        p,
        200.0,
        122.0,
        @shared.tx("右边两个：set_global_alpha(0.35)"),
        11.0,
        @theme.theme_text_secondary(),
      )
    })
    w
  })
}

///|
/// 位图：同一张 PNG 三档缩放 + GIF 首帧；图不在位时只画占位框，不崩。
fn image_widget() -> @widget.Node {
  @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget {
    w.node.set_width(@yoga.fixed(520.0))
    w.node.set_height(@yoga.fixed(200.0))
    w.on_draw = Some(fn(_w : @widget.Widget, p : @render.Painter, r : @base.Rect) -> Unit {
      p.set_fill_color(@theme.theme_bg_panel())
      p.fill_rect(0.0, 0.0, r.w, r.h)
      let png = @render.Image::new_from_file(canvas_asset("tray_moon_full.png"))
      let gif = @render.Image::new_from_file(canvas_asset("dot.gif"))
      if png.is_empty() {
        p.set_stroke_color(@theme.theme_border())
        p.set_line_width(1.0)
        p.stroke_rect(24.0, 34.0, 64.0, 64.0)
      } else {
        p.draw_image(png, 24.0, 34.0, 64.0, 64.0)
        p.draw_image(png, 108.0, 34.0, 128.0, 128.0)
      }
      if !gif.is_empty() {
        // 源图 40×40 里只取左上 20×20，放大到 80×80（draw_image_from_rect）
        p.draw_image_from_rect(gif, 260.0, 34.0, 80.0, 80.0, 0.0, 0.0, 20.0, 20.0)
      }
      p.flush()
      let _ = @text.draw_text_at(
        p,
        24.0,
        14.0,
        @shared.tx("PNG 64×64 / 128×128，GIF 首帧取左上 20×20 放大到 80"),
        11.0,
        @theme.theme_text_secondary(),
      )
      let _ = @text.draw_text_at(
        p,
        360.0,
        60.0,
        @shared.tx("缩放不糊边"),
        11.0,
        @theme.theme_text_secondary(),
      )
    })
    w
  })
}
