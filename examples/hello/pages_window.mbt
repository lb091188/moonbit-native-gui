// 窗口功能演示段（迁自 components 窗口页后瘦身）：纵向排在 mng 入门页与
// 基本窗口示例之后，保留最直观的三段——窗口 API / 多窗口 / 透明度
// （全局快捷键、拖放、窗口层级、显隐驻留、状态记忆已退出示例矩阵，库功能
// 不受影响）。两条口径沿用原页：
// ① 窗口段只放后端真写得通的按钮；取窗口经宿主 `WindowHost::window()`
//    （标题/尺寸/无边框/最大化这类窗口级动作由上层直调 `@win.Window`）；
// ② 展示形态按 hello 定位从简：段容器只有标题 + 说明 + 内容（无 code
//    展示区），文案直写中文（hello 不接 i18n）。

///|
/// 段容器：标题 + 说明 + 内容（demo 页纵向分块的最小形态）。
fn hello_section(
  title : String,
  desc : String,
  nodes : Array[@widget.Node],
) -> @widget.Node {
  @ui.col(
    [@ui.text(title, class=[@style.text_title]), @ui.text(desc, wrap=true)] +
    nodes,
    padding=20.0,
    row_gap=8.0,
  )
}

///|
/// 窗口动作按钮：点下去经宿主取窗口门面执行 `act`，按钮名写回显行。
/// 宿主未就绪时（理论上是点不到的）静默跳过。
fn win_button(
  host : Ref[@widget.WindowHost?],
  last_op : @base.Store[String],
  text : String,
  act : (@win.Window) -> Unit,
  variant~ : @ui.ButtonVariant = @ui.Soft,
) -> @widget.Node {
  @ui.button(text, variant~, on_click=fn() {
    match host.val {
      Some(a) => {
        act(a.window())
        last_op.set(text)
      }
      None => ()
    }
  })
}

///|
/// 透明测试窗：单开一扇**无边框**窗，开背景透视后只放几块不透明的卡片。
/// 主窗看不了这个效果——整页铺满底色，没有「没铺到的像素」；本窗根容器不铺底，
/// 卡片之外那圈像素就是透明的，桌面从那里透出来。字直接落在透明底上时，
/// 字形不透明、字后面的像素透明，抗锯齿边缘按半透明合成。
fn open_transparent_demo(
  host : Ref[@widget.WindowHost?],
  out : @base.Store[String],
) -> Unit {
  fn card(title : String, body : String) -> @widget.Node {
    @ui.view(
      [@ui.text(title, class=[@style.text_heading]), @ui.text(body)],
      background_color="bg_panel",
      border_color="primary",
      padding=12.0,
      row_gap=4.0,
      corner_radius=10.0,
    )
  }

  match host.val {
    Some(a) =>
      match a.open_window(380, 280, "透明窗测试") {
        Some(child) => {
          let w = child.window()
          // 先无边框再开透视：标题栏那块归系统画，留着它就不跟透视走。
          // 透视必须走 App::set_transparent_bg——宿主默认页面底会铺满整窗，
          // 直调窗口层摘不掉它，卡片外那圈就不是真透明（实测踩过）
          w.set_borderless(true)
          child.set_transparent_bg(true)
          child.mount([
            @ui.col(
              [
                card(
                  "这块不透明", "卡片之外那圈像素应当是透明的，能看到桌面。",
                ),
                @ui.text(
                  "这行字直接落在透明底上：字不透明，字后面的像素透明。",
                ),
                @ui.view(
                  [
                    @ui.button("关掉本窗", variant=@ui.Danger, on_click=fn() {
                      child.close_window()
                    }),
                  ],
                  background_color="bg_panel",
                  padding=10.0,
                  corner_radius=10.0,
                ),
              ],
              row_gap=12.0,
              padding=16.0,
            ),
          ])
          out.set(
            "已开透明测试窗：无边框 + 背景透视，卡片外应透出桌面",
          )
        }
        None =>
          out.set("这台机器开不了第二扇窗（无窗口后端）")
      }
    None => out.set("宿主还没就绪")
  }
}

///|
/// 窗口功能三段。段内私有状态（回显/两个切换态）不进 main。
fn window_sections(host : Ref[@widget.WindowHost?]) -> Array[@widget.Node] {
  let last_op : @base.Store[String] = @base.Store::new("（尚无操作）")
  // 两个切换态由按钮自己翻（窗口层没有 is_fullscreen/is_borderless 之外的
  // 读回通道，态以按钮点击为准）
  let fs : Ref[Bool] = Ref(false)
  let bl : Ref[Bool] = Ref(false)
  let sz : Ref[Int32] = Ref(1280)
  let max_out : @base.Store[String] = @base.Store::new("（未读过）")
  let multiwin_out : @base.Store[String] = @base.Store::new(
    "（还没开过子窗）",
  )
  // alpha 与背景穿透共用一条回显行
  let layer_out : @base.Store[String] = @base.Store::new("（尚无操作）")
  let tw_out : @base.Store[String] = @base.Store::new(
    "（还没开过透明测试窗）",
  )
  fn win_set_opacity(alpha : Int32) -> Unit {
    match host.val {
      Some(a) => {
        a.window().set_opacity(alpha)
        layer_out.set("窗口 alpha 已置 \{alpha}（/255）")
      }
      None => ()
    }
  }
  [
    // —— 窗口 API ——
    hello_section(
      "窗口 API",
      "运行期操作窗口：改标题 / 全屏 / 尺寸切换（1280×720 ↔ 960×540）/ 无边框 / 最大化与还原。系统标题栏自带的「最大化」按钮三平台本来就有，`set_maximized` / `is_maximized` 补的是无边框自绘标题栏里自己放这个键的能力；`is_maximized` 现问平台不读缓存，所以你手点系统按钮之后它读出来的也是对的。",
      [
        @ui.row(
          [
            win_button(host, last_op, "改标题", fn(
              _w : @win.Window,
            ) -> Unit {
              // 改名也登记进标题口：之后窗口标题沿用这条回显文案
              @widget.set_window_title_localized(fn(_) {
                "你好，MoonBit · 标题已改"
              })
            }),
            win_button(host, last_op, "全屏切换", fn(
              w : @win.Window,
            ) -> Unit {
              fs.val = !fs.val
              w.set_fullscreen(fs.val)
            }),
            win_button(host, last_op, "尺寸切换", fn(
              w : @win.Window,
            ) -> Unit {
              // 定死一个目标值会看着「没用」——启动尺寸就是它；两档来回切才看得见
              sz.val = if sz.val == 1280 { 960 } else { 1280 }
              let h = (sz.val.to_double() * 9.0 / 16.0).round().to_int()
              w.set_size_pixels(sz.val, h)
            }),
            win_button(host, last_op, "无边框切换", fn(
              w : @win.Window,
            ) -> Unit {
              bl.val = !bl.val
              w.set_borderless(bl.val)
            }),
          ],
          column_gap=8.0,
        ),
        @ui.row(
          [
            win_button(host, last_op, "最大化", fn(w : @win.Window) -> Unit {
              w.set_maximized(true)
              max_out.set(
                if w.is_maximized() {
                  "最大化态读回：true"
                } else {
                  "最大化态读回：false（这台机器没兑现）"
                },
              )
            }),
            win_button(host, last_op, "还原", fn(w : @win.Window) -> Unit {
              w.set_maximized(false)
              max_out.set(
                if w.is_maximized() {
                  "最大化态读回：true（还原没兑现）"
                } else {
                  "最大化态读回：false"
                },
              )
            }),
            @ui.button("读最大化态", variant=@ui.Text, on_click=fn() {
              match host.val {
                Some(a) => {
                  last_op.set("读最大化态")
                  max_out.set(
                    if a.window().is_maximized() {
                      "最大化态读回：true（手点系统按钮也读得对）"
                    } else {
                      "最大化态读回：false"
                    },
                  )
                }
                None => ()
              }
            }),
            @ui.text(
              "先点「最大化」再点「读最大化态」，也可手点系统按钮后回来读",
            ),
          ],
          column_gap=8.0,
          align_items=@yoga.AlignItems::Center,
        ),
        @ui.row(
          [@ui.text("最近操作："), @ui.bind_label(last_op, fn(s) { s })],
          column_gap=6.0,
        ),
        @ui.bind_label(max_out, fn(s) { s }),
      ],
    ),
    // —— 多窗口 ——
    hello_section(
      "多窗口",
      "宿主注册表是进程级的：`App::open_window` 开第二扇窗、`App::window_count` 数窗、`App::active_window` 取当前活动窗、`close_window` 关自己那窗。关从窗不退出应用，只有主窗关或全关完才整体退出。每扇窗内容各自挂自己的 Node 树，事件路由与上屏逐窗走。",
      [
        @ui.row(
          [
            @ui.button("开子窗", on_click=fn() {
              match host.val {
                Some(a) =>
                  match a.open_window(360, 240, "你好窗口子窗") {
                    Some(child) => {
                      child.mount([
                        @ui.col(
                          [
                            @ui.text("这是第二扇窗", class=[
                              @style.text_heading,
                            ]),
                            @ui.text(
                              "主窗与子窗事件各自独立；关本窗不退出应用。",
                              wrap=true,
                            ),
                            @ui.button("关掉我自己", variant=@ui.Danger, on_click=fn() {
                              child.close_window()
                            }),
                          ],
                          row_gap=12.0,
                          padding=24.0,
                        ),
                      ])
                      multiwin_out.set(
                        "已开子窗，当前共 \{a.window_count()} 扇",
                      )
                    }
                    None =>
                      multiwin_out.set(
                        "这台机器开不了第二扇窗（无窗口后端）",
                      )
                  }
                None => multiwin_out.set("宿主还没就绪")
              }
            }),
            @ui.button("列窗数", variant=@ui.Soft, on_click=fn() {
              match host.val {
                Some(a) =>
                  multiwin_out.set("当前共 \{a.window_count()} 扇窗")
                None => ()
              }
            }),
            @ui.button("关最近一扇子窗", variant=@ui.Text, on_click=fn() {
              match host.val {
                Some(a) =>
                  match a.active_window() {
                    Some(act) =>
                      if act.is_primary() {
                        multiwin_out.set("当前活动窗是主窗，不关它")
                      } else {
                        act.close_window()
                        multiwin_out.set(
                          "已关一扇子窗，剩 \{a.window_count()} 扇",
                        )
                      }
                    None => multiwin_out.set("没有活动窗")
                  }
                None => ()
              }
            }),
          ],
          column_gap=8.0,
        ),
        @ui.bind_label(multiwin_out, fn(s) { s }),
      ],
    ),
    // —— 透明度 ——
    hello_section(
      "透明度",
      "两件不同的事。`set_opacity` 是**整窗 alpha**（0–255）——连同文字与控件一起变淡，需要合成器，没有就静默无效，对主窗生效。`set_transparent_bg` 是**背景透视**——控件没铺到的像素留成透明，桌面从那些洞透出来（Windows 上要无边框才成立；**要经 `App::set_transparent_bg` 开**，宿主默认页面底会铺满整窗，直调窗口层摘不掉它）。主窗整片铺满底色、没有「没铺到的像素」，透视验不了也**不该在主窗开**；点「开透明测试窗」单开一扇无边框窗，根容器不铺底，只放几块不透明卡片来验。",
      [
        @ui.row(
          [
            @ui.button("100%", on_click=fn() { win_set_opacity(255) }),
            @ui.button("80%", variant=@ui.Soft, on_click=fn() {
              win_set_opacity(204)
            }),
            @ui.button("50%", variant=@ui.Soft, on_click=fn() {
              win_set_opacity(128)
            }),
            @ui.button("25%", variant=@ui.Soft, on_click=fn() {
              win_set_opacity(64)
            }),
          ],
          column_gap=8.0,
        ),
        @ui.row(
          [
            @ui.button("开透明测试窗", on_click=fn() {
              open_transparent_demo(host, tw_out)
            }),
            @ui.text(
              "测试窗：无边框 + 背景透视，卡片外那圈应当是桌面；窗内自带「关掉本窗」",
              wrap=true,
            ),
          ],
          column_gap=8.0,
          align_items=@yoga.AlignItems::Center,
        ),
        @ui.bind_label(tw_out, fn(s) { s }),
        @ui.bind_label(layer_out, fn(s) { s }),
      ],
    ),
  ]
}
