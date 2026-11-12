// 基础组件页：Store/Signal 驱动的主题组件演示。共享状态（counter 计数、
// picked_lang 最近操作）在 App；页内状态用页内 Store，展示端用
// `@ui.bind` 直连，无手动 subscribe 接线。勾选类在表单组件页，右键菜单
// 在导航组件页。
//

///|
/// 字体演示的自绘块：左右两盒同一段文字，右盒把末尾「28」设成 28px 区间字体——
/// 行盒必须按混排口径抬起来（盒高取 `AttributedText::line_height`），否则大字被裁；
/// 下方一行演示族名回退（不存在的族退到 monospace）。
fn font_mix_widget() -> @widget.Node {
  @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget {
    w.node.set_width(@yoga.percent(100.0))
    w.node.set_height(@yoga.fixed(96.0))
    w.on_draw = Some(fn(
      _w : @widget.Widget,
      p : @render.Painter,
      r : @base.Rect,
    ) -> Unit {
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

///|
pub fn page_basic(app : @shared.App) -> @widget.Node {
  // 两个悬停/光标组各配一个文本框状态
  let box_a : @base.Store[String] = @base.Store::new(@shared.tx("组内输入框"))
  let box_b : @base.Store[String] = @base.Store::new(@shared.tx("组内输入框"))
  // 富文本两个格式开关与两个演示对象（页内状态，不进 App）
  let rt_wrap : Ref[Bool] = Ref(true)
  let rt_ellipsis : Ref[Bool] = Ref(false)
  let rt = @text.AttributedText::new(
    @shared.tx("MoonBit 富文本：这段文字有范围着色与粗体。"),
    wrap=rt_wrap.val,
    ellipsis=rt_ellipsis.val,
  )
  rt.set_font(@text.Font::new("", 20.0, weight=@text.Bold))
  rt.set_font_for(@text.Font::new("", 24.0, weight=@text.Black), 0, 6)
  rt.set_color("#356AA0")
  rt.set_color_for("#E5534B", 8, 11)
  // 可选档演示对象：同样式区间，折行跟随容器宽
  let rt_sel = @text.AttributedText::new(
    @shared.tx(
      "MoonBit 富文本 selectable：这段混排文本可以按住拖选、双击选词，然后 Ctrl/Cmd+C 复制，范围颜色与字体随选中高亮一起保留。",
    ),
    wrap=true,
  )
  rt_sel.set_font(@text.Font::new("", 16.0, weight=@text.Bold))
  rt_sel.set_font_for(@text.Font::new("", 20.0, weight=@text.Black), 0, 6)
  rt_sel.set_color("#356AA0")
  rt_sel.set_color_for("#E5534B", 8, 11)
  @shared.page([
    @shared.section(
      "主题",
      "主题色板",
      "选一个主色，整套色板（hover/浅底/语义色）按 HSL 公式即时派生，切换深浅沿用当前主色；「跟随系统」读系统主色调，读不到回落内置。手动选色会先关掉跟随开关（否则下一次轮询就把它盖回去）。",
      [
        @ui.row(
          [
            @ui.button(@shared.tx("跟随系统"), variant=@ui.Solid, on_click=fn() {
              app.follow.set(true)
            }),
            @ui.button(@shared.tx("默认蓝"), on_click=fn() {
              app.follow.set(false)
              app.accent.set("")
            }),
            @ui.button(@shared.tx("青"), on_click=fn() {
              app.follow.set(false)
              app.accent.set("#009688")
            }),
            @ui.button(@shared.tx("绿"), on_click=fn() {
              app.follow.set(false)
              app.accent.set("#2E9E5B")
            }),
            @ui.button(@shared.tx("紫"), on_click=fn() {
              app.follow.set(false)
              app.accent.set("#9141AC")
            }),
            @ui.button(@shared.tx("红"), on_click=fn() {
              app.follow.set(false)
              app.accent.set("#D64550")
            }),
          ],
          column_gap=8.0,
        ),
        @ui.bind(app.accent.signal(), fn(s) {
          if s == "" {
            @shared.tx("当前主色：内置默认")
          } else {
            @shared.tr_with("dyn.accent_now", [("c", s)], "当前主色：\{s}")
          }
        }),
      ],
      code=[
        "let dark = @win.sys_color_scheme() == \"dark\"",
        "let accent = @win.sys_accent()",
        "if accent != \"\" {",
        "  @theme.theme_apply(@theme.theme_from_accent(accent, dark=dark))",
        "} else {",
        "  @theme.theme_apply(if dark { @theme.dark_theme() } else { @theme.default_theme() })",
        "}",
      ],
    ),
    @shared.section(
      "字体排版",
      "各语言的行首方向",
      "每一行都占满整行宽度，所以中文、英文从左缘起笔，阿拉伯语、波斯语、希伯来语、乌尔都语这类从右往左落笔的文字右端贴右缘——对齐只给文本自身的 `align=End`，方向另给 `direction=Rtl`。行内数字与拉丁段在 bidi 里仍按 LTR 走，不反写。字体按平台回退，缺相应字形时显示方框属系统字体集问题，不是排版错位。",
      [
        @ui.col(
          [
            @ui.text(@shared.tx("简体中文 — 你好，世界"), font_size=16.0),
            @ui.text("English — Hello, world", font_size=16.0),
            @ui.text(
              @shared.tx("العربية — 阿拉伯语：مرحبا بالعالم"),
              font_size=16.0,
              align=@text.End,
              class=[@style.style().set_direction(Some(@style.Rtl))],
            ),
            @ui.text(
              @shared.tx("فارسی — 波斯语：سلام دنیا"),
              font_size=16.0,
              align=@text.End,
              class=[@style.style().set_direction(Some(@style.Rtl))],
            ),
            @ui.text(
              @shared.tx("עברית — 希伯来语：שלום עולם"),
              font_size=16.0,
              align=@text.End,
              class=[@style.style().set_direction(Some(@style.Rtl))],
            ),
            @ui.text(
              @shared.tx("اردو — 乌尔都语：دنیا کو سلام"),
              font_size=16.0,
              align=@text.End,
              class=[@style.style().set_direction(Some(@style.Rtl))],
            ),
            @ui.text(
              @shared.tx("RTL 行里的 1234 / ABC 保持原序不反写"),
              font_size=14.0,
              align=@text.End,
              class=[@style.style().set_direction(Some(@style.Rtl))],
            ),
          ],
          row_gap=8.0,
        ),
      ],
      code=[
        "@ui.col([",
        "  @ui.text(\"English — Hello, world\", font_size=16.0),",
        "  @ui.text(\"العربية — مرحبا بالعالم\",",
        "    font_size=16.0, align=@text.End,",
        "    class=[@style.style().set_direction(Some(@style.Rtl))]),",
        "], row_gap=8.0)",
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
            @ui.text(@shared.tx("字距 0：MoonBit GUI 字距对照")),
            @ui.text(
              @shared.tx("字距 4：MoonBit GUI 字距对照"),
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
      "按钮",
      "Button 按钮",
      "四变体；「主要操作」联动数据页访问量/进度条（信号）。",
      [
        @ui.row(
          [
            @ui.button(@shared.tx("主要操作"), variant=@ui.Solid),
            @ui.button(@shared.tx("次要操作"), variant=@ui.Soft),
            @ui.button(@shared.tx("文字按钮"), variant=@ui.Text),
            @ui.button(@shared.tx("危险操作"), variant=@ui.Danger),
          ],
          column_gap=8.0,
        ),
        @ui.row(
          [
            @ui.button(@shared.tx("主要操作"), disabled=true, variant=@ui.Solid),
            @ui.button(@shared.tx("次要操作"), disabled=true, variant=@ui.Soft),
            @ui.button(@shared.tx("文字按钮"), disabled=true, variant=@ui.Text),
            @ui.button(@shared.tx("危险操作"), disabled=true, variant=@ui.Danger),
          ],
          column_gap=8.0,
        ),
      ],
      code=[
        "@ui.row([",
        "  @ui.button(\"主要操作\", variant=@ui.Solid, on_click=fn() { }),",
        "  @ui.button(\"次要操作\", variant=@ui.Soft),",
        "  @ui.button(\"文字按钮\", variant=@ui.Text),",
        "  @ui.button(\"危险操作\", variant=@ui.Danger),",
        "], column_gap=8.0)",
      ],
    ),
    @shared.section(
      "文字链接",
      "Label 与 Link",
      "五级字阶预设（class=@style.text_*），字号字重颜色走主题字阶令牌，正文为缺省档不挂；Link 主题色文字悬停下划线，最近点击信号回显；`selectable=true` 的文本可用鼠标选中复制（只读、不进 Tab 链）。",
      [
        @ui.text(@shared.tx("标题文字（Title）"), class=[@style.text_heading]),
        @ui.text(@shared.tx("小节标题（Section）"), class=[@style.text_title]),
        @ui.text(@shared.tx("正文文字（Body）")),
        @ui.text(@shared.tx("辅助文字（Secondary）"), class=[@style.text_secondary]),
        @ui.text(@shared.tx("强调文字（Accent）"), class=[@style.text_accent]),
        @ui.text(
          @shared.tx("选中试试：拖选这一行、双击选词、Shift+点击扩选，然后按 Ctrl/Cmd+C。"),
          selectable=true,
          class=[@style.text_secondary],
        ),
        @ui.row(
          [
            @ui.link(@shared.tx("打开文档"), fn() { app.picked_lang.set("docs") }),
            @ui.link(@shared.tx("帮助中心"), fn() { app.picked_lang.set("help") }),
            @ui.text(@shared.tx("最近点击：")),
            @ui.bind(app.picked_lang, fn(s) { s }),
          ],
          column_gap=8.0,
        ),
      ],
      code=[
        "@ui.text(\"标题文字\", class=[@style.text_heading])",
        "@ui.text(\"小节标题\", class=[@style.text_title])",
        "@ui.text(\"正文文字\")",
        "@ui.text(\"辅助文字\", class=[@style.text_secondary])",
        "@ui.text(\"强调文字\", class=[@style.text_accent])",
        "@ui.link(\"打开文档\", fn() { app.picked_lang.set(\"docs\") })",
        "// 可选中复制的静态文本（只读）",
        "@ui.text(\"……\", selectable=true)",
      ],
    ),
    @shared.section(
      "富文本",
      "富文本 AttributedText",
      "范围字体/颜色（0-6 号 24px Black、8-11 号红色）+ 换行/省略号开关 + 文本改写（属性保留）；下面那块是可选档 `@ui.rich_text`——混排文本可拖选/双击选词，Ctrl/Cmd+C 复制，选中高亮跟着范围样式走。",
      [
        @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget {
          w.node.set_width(@yoga.percent(100.0))
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
        @ui.rich_text(rt_sel, selectable=true),
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
      "分隔提示",
      "Divider 与 Tooltip",
      "水平（默认）/竖直 1px 主题边框色；tooltip 给任意节点包原生悬浮提示（系统样式，主题化气泡见反馈页 Popover）。容器描边的线形走样式槽 `border_style`：solid/dashed/dotted 三档，虚线周期由 `border_width` 派生（与 CSS 同口径），卡片、面板、滚动视口这类读描边槽的容器都吃这条。",
      [
        @ui.text(@shared.tx("上方内容")),
        @ui.divider(),
        @ui.text(@shared.tx("下方内容")),
        @ui.row(
          [
            @ui.tooltip(@ui.button(@shared.tx("悬停看提示")), @shared.tx("原生 tooltip：系统样式")),
            @ui.tooltip(@ui.button(@shared.tx("再来一个"), variant=@ui.Soft), @shared.tx("第二个提示")),
          ],
          column_gap=8.0,
        ),
        @ui.row(
          [
            @ui.card(
              [@ui.text(@shared.tx("dashed：实 3 空 2"), class=[@style.text_secondary])],
              padding=12.0,
              class=[@style.style(border_style=@style.Dashed)],
            ),
            @ui.card(
              [@ui.text(@shared.tx("dotted：圆头点"), class=[@style.text_secondary])],
              padding=12.0,
              class=[@style.style(border_style=@style.Dotted, border_width=2.0)],
            ),
          ],
          column_gap=8.0,
        ),
      ],
      code=[
        "@ui.divider()",
        "@ui.divider(vertical=true)",
        "@ui.tooltip(@ui.button(\"悬停看提示\"), \"原生 tooltip：系统样式\")",
        "@ui.card([..], class=[@style.style(border_style=@style.Dashed)])",
        "@ui.card([..], class=[@style.style(border_style=@style.Dotted, border_width=2.0)])",
      ],
    ),
    @shared.section(
      "悬停光标",
      "HoverGroup 悬停组与 CursorGroup 光标组",
      "上：组内任意位置（含子控件）悬停即整组进入 hover 态——把指针移到卡片里的按钮或输入框上，整张卡片同样高亮。悬停态是父链语义，既不排定时器也不查指针。下：父设子随——指针落在组内任意位置（含输入框、按钮等子控件）都保持手型，移出恢复默认。光标是窗口级的一层，宿主按悬停路径取「最深的那个请求」，所以组只设自己一处即可。",
      [
        @ui.hover_group(
          [
            @ui.text(@shared.tx("组标题：悬停我，或下面的子控件"), class=[@style.text_title]),
            @ui.row(
              [@ui.input(box_a, width=200.0), @ui.button(@shared.tx("组内按钮"))],
              column_gap=8.0,
            ),
            @ui.text(@shared.tx("子控件触发的事件同样改变组的样式"), class=[@style.text_secondary]),
          ],
          padding=12.0,
          row_gap=8.0,
        ),
        @ui.cursor_group(
          [
            @ui.text(@shared.tx("整组都是手型：移入试试，或移到子控件上"), class=[@style.text_title]),
            @ui.row(
              [@ui.input(box_b, width=200.0), @ui.button(@shared.tx("组内按钮"))],
              column_gap=8.0,
            ),
          ],
          padding=12.0,
          row_gap=8.0,
        ),
      ],
      code=[
        "@ui.hover_group(",
        "  [",
        "    @ui.text(\"组标题\", class=[@style.text_title]),",
        "    @ui.row([@ui.input(box, width=200.0), @ui.button(\"组内按钮\")], column_gap=8.0),",
        "  ],",
        "  padding=12.0,",
        "  row_gap=8.0,",
        ")",
        "@ui.cursor_group(",
        "  [",
        "    @ui.text(\"整组都是手型\", class=[@style.text_title]),",
        "    @ui.input(box, width=200.0),",
        "    @ui.button(\"组内按钮\"),",
        "  ],",
        "  padding=12.0,",
        ")",
      ],
    ),
  ])
}
