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
/// 观感对齐设计基准：bg_panel 卡片底 + 1px 描边 + 圆角 6，间距取刻度档。
fn hello_section(
  title : String,
  desc : String,
  nodes : Array[@widget.Node],
) -> @widget.Node {
  @ui.col(
    [@ui.text(title, class=[@style.text_title]), @ui.text(desc, wrap=true)] +
    nodes,
    padding=24.0,
    row_gap=8.0,
    class=[
      @style.style(
        margin=16.0,
        background_color="bg_panel",
        border_color="border",
        border_width=1.0,
        border_radius=6.0,
      ),
    ],
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
/// 桌面便签（背景透视的贴近样例）：单开一扇**无边框**窗，开背景透视后
/// 只放一张不透明的便签卡片——卡片外那圈像素就是透明的，桌面从那里
/// 透出来，观感就是一张浮在桌面上的便签。主窗看不了这个效果——整页
/// 铺满底色，没有「没铺到的像素」。字直接落在透明底上时，字形不透明、
/// 字后面的像素透明，抗锯齿边缘按半透明合成。
fn open_transparent_demo(
  host : Ref[@widget.WindowHost?],
  out : @base.Store[String],
  ct_host : Ref[@widget.WindowHost?],
) -> Unit {
  match host.val {
    Some(a) =>
      match a.open_window(300, 190, "桌面便签") {
        Some(child) => {
          let w = child.window()
          // 先无边框再开透视：标题栏那块归系统画，留着它就不跟透视走。
          // 透视必须走 App::set_transparent_bg——宿主默认页面底会铺满整窗，
          // 直调窗口层摘不掉它，卡片外那圈就不是真透明（实测踩过）
          w.set_borderless(true)
          child.set_transparent_bg(true)
          // 置顶：便签本就该浮在别的窗上面
          w.set_layer(@win.WindowLayer::AlwaysOnTop)
          child.mount([
            @ui.view(
              [
                @ui.text("桌面便签", class=[@style.text_title]),
                @ui.text(
                  "我浮在桌面上，卡片外那圈就是真实的桌面。",
                  wrap=true,
                ),
                @ui.col([], grow=1.0),
                @ui.row(
                  [
                    @ui.col([], grow=1.0),
                    @ui.button("收起便签", variant=@ui.Soft, on_click=fn() {
                      child.close_window()
                    }),
                  ],
                ),
              ],
              background_color="bg_panel",
              border_color="border",
              padding=16.0,
              row_gap=8.0,
              corner_radius=8.0,
              grow=1.0,
            ),
          ])
          ct_host.val = Some(child)
          out.set(
            "便签已开：卡片外透出桌面",
          )
        }
        None => {
          ct_host.val = None
          out.set("这台设备开不了第二扇窗")
        }
      }
    None => out.set("宿主还没就绪")
  }
}

///|
/// 窗口功能三段。段内私有状态（回显/两个切换态）不进 main。
fn window_sections(host : Ref[@widget.WindowHost?]) -> Array[@widget.Node] {
  let last_op : @base.Store[String] = @base.Store::new("还没操作")
  // 两个切换态由按钮自己翻（窗口层没有 is_fullscreen/is_borderless 之外的
  // 读回通道，态以按钮点击为准）
  let fs : Ref[Bool] = Ref(false)
  let bl : Ref[Bool] = Ref(false)
  let sz : Ref[Int32] = Ref(1280)
  let max_out : @base.Store[String] = @base.Store::new("（未读过）")
  let multiwin_out : @base.Store[String] = @base.Store::new(
    "还没有子窗",
  )
  // alpha 与背景穿透共用一条回显行
  let layer_out : @base.Store[String] = @base.Store::new("还没操作")
  // 点击穿透的靶窗（透明测试窗）与开关态：控制权留在主窗，测试窗开了穿透
  // 之后自己点不到自己，只能从这里关
  let ct_host : Ref[@widget.WindowHost?] = Ref(None)
  let ct_on : Ref[Bool] = Ref(false)
  let tw_out : @base.Store[String] = @base.Store::new(
    "便签没开",
  )
  fn win_set_opacity(alpha : Int32) -> Unit {
    match host.val {
      Some(a) => {
        a.window().set_opacity(alpha)
        layer_out.set("透明度已调：\{alpha}/255")
      }
      None => ()
    }
  }
  // 透明度两件事：set_opacity 整窗 alpha（要合成器，没有就静默无效）；
  // set_transparent_bg 背景透视（Windows 要无边框；必须经 App 开，
  // 宿主默认页面底铺满整窗，直调窗口层摘不掉）。主窗没有「没铺到的
  // 像素」，透视只能开测试窗验——细节见 open_transparent_demo 注释。
  [
    // —— 窗口 API ——
    hello_section(
      "窗口 API",
      "运行期也能改变窗口：改标题、切全屏、调尺寸、去边框、最大化与还原。",
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
              // is_maximized 现问平台不读缓存：手点系统标题栏按钮后读回的也是对的
              w.set_maximized(true)
              max_out.set(
                if w.is_maximized() {
                  "最大化：已开"
                } else {
                  "最大化：未开（这台设备没兑现）"
                },
              )
            }),
            win_button(host, last_op, "还原", fn(w : @win.Window) -> Unit {
              w.set_maximized(false)
              max_out.set(
                if w.is_maximized() {
                  "最大化：仍在（还原没兑现）"
                } else {
                  "最大化：已还原"
                },
              )
            }),
            @ui.button("读最大化态", variant=@ui.Text, on_click=fn() {
              match host.val {
                Some(a) => {
                  last_op.set("读最大化态")
                  max_out.set(
                    if a.window().is_maximized() {
                      "最大化：已开"
                    } else {
                      "最大化：未开"
                    },
                  )
                }
                None => ()
              }
            }),
            @ui.text("先点「最大化」，再读它的状态"),
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
      "再开几扇窗试试：关掉子窗不影响应用，关掉主窗才退出。",
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
                              "关掉本窗不影响应用。",
                              wrap=true,
                            ),
                            @ui.button("关闭本窗", variant=@ui.Soft, on_click=fn() {
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
                        "这台设备开不了第二扇窗",
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
      "让整窗变淡，或单开一扇窗让背景透出来。",
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
            @ui.button("开桌面便签", on_click=fn() {
              open_transparent_demo(host, tw_out, ct_host)
            }),
            @ui.button("便签点穿", variant=@ui.Text, on_click=fn() {
              match ct_host.val {
                Some(child) => {
                  ct_on.val = !ct_on.val
                  let on = ct_on.val
                  match child.window().set_click_through(on) {
                    Ok(_) =>
                      layer_out.set(
                        if on {
                          "穿透已开：再点一次关闭"
                        } else {
                          "穿透已关"
                        },
                      )
                    Err(Unsupported) =>
                      layer_out.set(
                        "这台设备不支持点击穿透",
                      )
                    Err(Failed(e)) =>
                      layer_out.set("没切成穿透：\{e}，便签可能已关，重开再试")
                  }
                }
                None => layer_out.set("先开桌面便签")
              }
            }),
            @ui.text(
              "便签卡片外透出桌面，可以点穿",
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
