// 过渡与效果页：状态桶切换的属性插值（`transition_ms`）+ 样式槽文本字段的观感对照。
//
// 参与插值的是每帧从样式槽读出的绘制期属性：三条颜色 + 边框宽 + 圆角 + 字号 + 行高
// （后两条与 CSS 同口径可动画，测量期读同一份插值值，见 `@style.transition`）。
// `opacity` 的生效点是 `apply` 落宿主字段，不插值。

///|
fn hover_card(label : String, sub : String, dur : Double) -> @widget.Node {
  @ui.view(
    [
      @ui.text(label, align=@text.Center),
      @ui.text(sub, class=[@style.text_secondary], align=@text.Center),
    ],
    width=170.0,
    height=64.0,
    row_gap=2.0,
    align_items=@yoga.AlignItems::Center,
    justify_content=@yoga.JustifyContent::Center,
    class=[
      @style.style(
        background_color="bg_panel",
        border_color="border",
        border_width=1.0,
        border_radius=4.0,
        color="text_regular",
        transition_ms=dur,
      ).hover(
        background_color="primary",
        border_color="primary_hover",
        border_width=2.0,
        border_radius=8.0,
        // 饱和主色底上的反白：token 集里没有反白档，这里的十六进制是唯一例外
        color="#ffffff",
      ),
    ],
  )
}

///|

///|
/// GIF 图源候选（moon run 可能从仓库根或 examples/ 目录起跑，逐个探测）。
fn anim_gif_path() -> String {
  for
    c in [
      "examples/components/assets/dot.gif", "assets/dot.gif", "components/assets/dot.gif",
    ] {
    if @sys.sys_path_exists(c) {
      return c
    }
  }
  "examples/components/assets/dot.gif"
}

///|
///|
/// PNG 图源候选（moon run 可能从仓库根或 examples/ 目录起跑，逐个探测）。
fn icon_path() -> String {
  for
    c in [
      "examples/components/assets/icon.png", "assets/icon.png", "components/assets/icon.png",
    ] {
    if @sys.sys_path_exists(c) {
      return c
    }
  }
  "examples/components/assets/icon.png"
}

///|
pub fn page_anim(_app : @shared.App) -> @widget.Node {
  let gif_h : @ui.GifHandle = @ui.GifHandle::make()
  // 关键帧演示：卡片句柄挂载期落袋，按钮回调拿它起/停轴
  let kf_card : Ref[@widget.Widget?] = Ref(None)
  let gif_note : @base.Store[String] = @base.Store::new(@shared.tx("自转中"))
  @shared.page([
    @shared.section(
      "属性过渡",
      "Transition 状态桶插值",
      "三块卡片只有 `transition_ms` 不同：悬停时底色/描边/圆角/字色都从当前值过渡到 hover 桶的值，离开时反向从当前帧的值续接（中途移开不跳变）。插值按真实时间推进，掉帧只少几帧、不会变快慢；每拍只给活动中的控件局部置脏，全部收敛就停表。",
      [
        @ui.row(
          [
            hover_card("0 ms", @shared.tx("直接切换"), 0.0),
            hover_card("150 ms", @shared.tx("常用反馈"), 150.0),
            hover_card("600 ms", @shared.tx("慢到看得清"), 600.0),
          ],
          column_gap=16.0,
        ),
      ],
      code=[
        "@style.style(", "  background_color=\"bg_panel\", border_radius=4.0,", "  transition_ms=150.0,          // 时长写在基块上",
        ").hover(", "  background_color=\"primary\", border_radius=8.0,", ")",
      ],
    ),
    @shared.section(
      "插值范围",
      "哪些属性会渐变",
      "左边卡片悬停时底色平滑过渡；右边卡片同时改字号——**字号也进插值集合**（13→17 在 300ms 里渐变，盒子按同一份值一起长，不会被裁）。当前集合是三条颜色 + 边框宽 + 圆角 + 字号 + 行高（与 CSS 可动画的 `<length>` 对齐）；`opacity` / `box_shadow` 仍在集合外，切换即生效。",
      [
        @ui.row(
          [
            @ui.view(
              [@ui.text(@shared.tx("底色过渡 300 ms"), align=@text.Center)],
              width=170.0,
              height=48.0,
              align_items=@yoga.AlignItems::Center,
              justify_content=@yoga.JustifyContent::Center,
              class=[
                @style.style(
                  background_color="bg_panel",
                  border_color="border",
                  transition_ms=300.0,
                ).hover(background_color="success"),
              ],
            ),
            @ui.view(
              [
                // 字号写在**文本控件自己**的槽上：状态桶按控件各算各的，父块的
                // hover 不会替子件换字号。文本铺满整块（width=170），指针在块内
                // 任意位置都命中文本，字号这一档才看得见。测量期读同一份插值
                // 字号（`@style.resolved_for_measure`），所以字长大会连着盒子一起长。
                @ui.text(@shared.tx("字号+底色"), align=@text.Center, class=[
                  @style.style(font_size=13.0, transition_ms=300.0).hover(
                    font_size=17.0,
                  ),
                ]),
              ],
              width=170.0,
              height=48.0,
              align_items=@yoga.AlignItems::Center,
              justify_content=@yoga.JustifyContent::Center,
              class=[
                @style.style(
                  background_color="bg_panel",
                  border_color="border",
                  transition_ms=300.0,
                ).hover(background_color="warning"),
              ],
            ),
          ],
          column_gap=16.0,
        ),
      ],
    ),
    @shared.section(
      "文本与效果",
      "样式槽里的文本字段",
      "`text_align` 定绘制对齐、`white_space` 定折行、`line_height` 抬高行盒、`text_decoration` 画下划线。都是绘制期属性，写进 `class` 就生效，组件不必另开参数。（投影档试过分层羽化，真机观感不过关，已整条撤掉。）",
      [
        @ui.col(
          [
            @ui.row(
              [
                @ui.view(
                  [
                    @ui.text(@shared.tx("下划线"), class=[
                      @style.style(text_decoration=@style.Underline),
                    ]),
                  ],
                  width=180.0,
                  class=[@style.style(background_color="bg_page")],
                ),
                @ui.view(
                  [
                    @ui.text(@shared.tx("右对齐（text_align）"), class=[
                      @style.style(text_align=@text.End),
                    ]),
                  ],
                  width=180.0,
                  class=[@style.style(background_color="bg_page")],
                ),
                @ui.text(@shared.tx("行高 32"), class=[
                  @style.style(line_height=32.0),
                ]),
              ],
              column_gap=12.0,
            ),
            @ui.col(
              [
                @ui.text(
                  @shared.tx(
                    "折行：这段文字开了 white_space=Normal 并限宽 300，会按词折成多行；同一句改成 NoWrap 就停在盒宽外。",
                  ),
                  max_width=300.0,
                  class=[@style.style(white_space=@style.Normal)],
                ),
                @ui.text(
                  @shared.tx(
                    "不折行：这段文字开了 white_space=NoWrap 并限宽 300，超出的部分不折行。",
                  ),
                  max_width=300.0,
                  class=[@style.style(white_space=@style.NoWrap)],
                ),
              ],
              row_gap=8.0,
              align_items=@yoga.AlignItems::FlexStart,
            ),
          ],
          row_gap=12.0,
          align_items=@yoga.AlignItems::FlexStart,
        ),
      ],
      code=[
        "@style.style(text_decoration=@style.Underline)", "@style.style(text_align=@text.End, line_height=32.0)",
        "@style.style(white_space=@style.Normal, max_width=300.0)",
      ],
    ),
    @shared.section(
      "动图",
      "GIF 动图",
      "按每帧时长自转的 GIF 组件（解码走 `render` 的动画通道，静图退回首帧）；句柄可暂停/继续、读已换帧数。",
      [
        @ui.row(
          [
            @ui.gif(anim_gif_path(), width=48.0, height=48.0, state=gif_h),
            @ui.button(@shared.tx("暂停"), variant=@ui.Soft, on_click=fn() {
              gif_h.pause()
              gif_note.set(
                @shared.tr_with(
                  "dyn.gif_paused",
                  [("r", gif_h.running.to_string())],
                  "已暂停（running=\{gif_h.running}）",
                ),
              )
            }),
            @ui.button(@shared.tx("继续"), variant=@ui.Soft, on_click=fn() {
              gif_h.play()
              gif_note.set(
                @shared.tr_with(
                  "dyn.gif_resumed",
                  [("r", gif_h.running.to_string())],
                  "已继续（running=\{gif_h.running}）",
                ),
              )
            }),
            @ui.button(@shared.tx("读帧数"), variant=@ui.Text, on_click=fn() {
              gif_note.set(
                @shared.tr_with(
                  "dyn.gif_frames",
                  [("n", gif_h.frame_count().to_string())],
                  "已换 \{gif_h.frame_count()} 帧",
                ),
              )
            }),
          ],
          column_gap=8.0,
          align_items=@yoga.AlignItems::Center,
        ),
        @ui.bind_label(
          gif_note,
          fn(s) { s },
          font_size=12.0,
          color="text_secondary",
        ),
      ],
      code=[
        "let h = @ui.GifHandle::make()", "@ui.gif(\"assets/dot.gif\", width=48.0, height=48.0, state=h)",
        "h.pause()  // 暂停自转", "h.play()   // 继续", "h.frame_count()  // 已换过的帧数",
      ],
    ),
    @shared.section(
      "transform 变换",
      "Transform",
      "绘制期变换三件：悬停放大（scale 进 hover 桶 + transition 平滑）、常驻旋转（rotate 单位度，绕控件中心）、悬停上浮（translate_y）。变换不参与布局与命中——盒子原地不动、视觉在变换；布局矩形仍是命中区，缩小的控件会有视觉在命中区外的边。",
      [
        @ui.row(
          [
            @ui.view(
              [@ui.text(@shared.tx("悬停放大 8%"), align=@text.Center)],
              width=150.0,
              height=64.0,
              align_items=@yoga.AlignItems::Center,
              justify_content=@yoga.JustifyContent::Center,
              class=[
                @style.style(
                  background_color="bg_panel",
                  border_color="border",
                  border_width=1.0,
                  border_radius=8.0,
                  transition_ms=200.0,
                ).hover(scale_x=1.08, scale_y=1.08, border_color="primary", z_index=1),
              ],
            ),
            @ui.view(
              [@ui.text(@shared.tx("常驻旋转 8°"), align=@text.Center)],
              width=150.0,
              height=64.0,
              align_items=@yoga.AlignItems::Center,
              justify_content=@yoga.JustifyContent::Center,
              class=[
                @style.style(
                  background_color="bg_panel",
                  border_color="border",
                  border_width=1.0,
                  border_radius=8.0,
                  rotate=8.0,
                ),
              ],
            ),
            @ui.view(
              [@ui.text(@shared.tx("悬停上浮 4px"), align=@text.Center)],
              width=150.0,
              height=64.0,
              align_items=@yoga.AlignItems::Center,
              justify_content=@yoga.JustifyContent::Center,
              class=[
                @style.style(
                  background_color="bg_panel",
                  border_color="border",
                  border_width=1.0,
                  border_radius=8.0,
                  transition_ms=200.0,
                ).hover(translate_y=-4.0, border_color="primary", z_index=1),
              ],
            ),
          ],
          column_gap=24.0,
        ),
      ],
      code=[
        "@style.style(background_color=\"bg_panel\", transition_ms=200.0)",
        ".hover(scale_x=1.08, scale_y=1.08)   // 悬停放大",
        "@style.style(rotate=8.0)             // 常驻旋转（度）",
      ],
    ),
    @shared.section(
      "圆角裁切",
      "Rounded clip",
      "容器声明圆角裁切后，子内容超出圆角的像素不落——方形图标裁出真圆角（弧外露底色，不是贴角贴出来的）。对照：右边同图不裁。图片这种「自绘即内容」的件也可以把裁切声明在自己身上（挂载期设旗，自绘前就裁）。",
      [
        @ui.row(
          [
            @ui.view(
              [@ui.image(icon_path(), width=72.0, height=72.0)],
              width=72.0,
              height=72.0,
              handle=fn(w) {
                w.clip_rounded = true
                w.style_clip_radius = 18.0
              },
            ),
            @ui.image(icon_path(), width=72.0, height=72.0),
          ],
          column_gap=24.0,
          align_items=@yoga.AlignItems::Center,
        ),
      ],
      code=[
        "@ui.view([@ui.image(\"assets/icon.png\")],",
        "  handle=fn(w) { w.clip_rounded = true; w.style_clip_radius = 18.0 })",
      ],
    ),
    @shared.section(
      "背景模糊（毛玻璃）",
      "Backdrop blur",
      "玻璃卡声明 backdrop_blur=8：进卡先把已画内容糊掉再铺半透明白——彩条透过来是柔化的色带；右边半透明卡没有模糊做对照（条纹锐利可辨）。模糊走 CPU 三趟盒式（控件级小半径），大半径与全窗级归 GPU 档。",
      [
        @ui.view(
          [
            @ui.row(
              [
                @ui.view([], width=24.0, height=96.0, background_color="#e5484d"),
                @ui.view([], width=24.0, height=96.0, background_color="#e0a13c"),
                @ui.view([], width=24.0, height=96.0, background_color="#34c26b"),
                @ui.view([], width=24.0, height=96.0, background_color="#3b82f6"),
                @ui.view([], width=24.0, height=96.0, background_color="#8b5cf6"),
                @ui.view([], width=24.0, height=96.0, background_color="#ec4899"),
                @ui.view([], width=24.0, height=96.0, background_color="#14b8a6"),
                @ui.view([], width=24.0, height=96.0, background_color="#f59e0b"),
              ],
              column_gap=0.0,
            ),
            @ui.view(
              [
                @ui.text(@shared.tx("毛玻璃 blur 8"), align=@text.Center, class=[
                  @style.style(color="#ffffff"),
                ]),
              ],
              width=120.0,
              height=48.0,
              align_items=@yoga.AlignItems::Center,
              justify_content=@yoga.JustifyContent::Center,
              class=[
                @style.style(
                  backdrop_blur=8.0,
                  background_color="#ffffff30",
                  border_color="#ffffff70",
                  border_width=1.0,
                  border_radius=8.0,
                  position=@yoga.Absolute,
                  top=24.0,
                  left=30.0,
                ),
              ],
            ),
            @ui.view(
              [
                @ui.text(@shared.tx("无模糊对照"), align=@text.Center, class=[
                  @style.style(color="#ffffff"),
                ]),
              ],
              width=120.0,
              height=48.0,
              align_items=@yoga.AlignItems::Center,
              justify_content=@yoga.JustifyContent::Center,
              class=[
                @style.style(
                  background_color="#ffffff30",
                  border_color="#ffffff70",
                  border_width=1.0,
                  border_radius=8.0,
                  position=@yoga.Absolute,
                  top=24.0,
                  left=170.0,
                ),
              ],
            ),
          ],
          width=310.0,
          height=96.0,
        ),
      ],
      code=[
        "@style.style(backdrop_blur=8.0, background_color=\"#ffffff30\")",
        "// 已画内容先糊掉再画自己；CPU 小半径，大半径归 GPU 档",
      ],
    ),
    @shared.section(
      "关键帧动画",
      "Keyframes",
      "多段属性时间轴：点「播放」后卡片沿关键帧序列循环——底色三色渐变 + 左右轻摆（rotate 往返），插值与过渡同一底座；点「停止」回落基块。Once 模式走完保留末帧，这里用 Loop 循环。",
      [
        @ui.row(
          [
            @ui.view(
              [@ui.text(@shared.tx("关键帧卡片"), align=@text.Center)],
              width=140.0,
              height=64.0,
              align_items=@yoga.AlignItems::Center,
              justify_content=@yoga.JustifyContent::Center,
              class=[
                @style.style(
                  background_color="primary",
                  border_radius=8.0,
                  color="#ffffff",
                ),
              ],
              handle=fn(w) { kf_card.val = Some(w) },
            ),
            @ui.col(
              [
                @ui.button(@shared.tx("播放关键帧"), on_click=fn() {
                  match kf_card.val {
                    Some(c) =>
                      @style.animate(
                        c,
                        [
                          {
                            at_ms: 0.0,
                            style: @style.style(background_color="primary", rotate=0.0),
                          },
                          {
                            at_ms: 500.0,
                            style: @style.style(background_color="#e5484d", rotate=6.0),
                          },
                          {
                            at_ms: 1000.0,
                            style: @style.style(background_color="#34c26b", rotate=-6.0),
                          },
                          {
                            at_ms: 1500.0,
                            style: @style.style(background_color="primary", rotate=0.0),
                          },
                        ],
                        mode=@style.Loop,
                      )
                    None => ()
                  }
                }),
                @ui.button(@shared.tx("停止"), variant=@ui.Soft, on_click=fn() {
                  match kf_card.val {
                    Some(c) => @style.stop_animating(c)
                    None => ()
                  }
                }),
              ],
              row_gap=8.0,
            ),
          ],
          column_gap=24.0,
          align_items=@yoga.AlignItems::Center,
        ),
      ],
      code=[
        "@style.animate(card, [",
        "  { at_ms: 0.0,    style: @style.style(background_color=\"primary\") },",
        "  { at_ms: 500.0,  style: @style.style(background_color=\"#e5484d\", rotate=6.0) },",
        "  { at_ms: 1000.0, style: @style.style(background_color=\"#34c26b\", rotate=-6.0) },",
        "], mode=@style.Loop)",
        "@style.stop_animating(card)",
      ],
    ),
  ])
}

