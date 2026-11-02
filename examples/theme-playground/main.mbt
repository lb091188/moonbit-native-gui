// 主题定制工作台：主题系统的四个定制入口各占一区——
// ① `theme_from_accent` 换主色（一个颜色公式派生整套色板，图表系列色随动）；
// ② `theme_apply` 全量覆盖（内置浅/深基准整套替换）；
// ③ `follow_system_theme` 持续跟随（起窗默认已探测过一次，这里接的是轮询）；
// ④ `class` 类槽单组件覆盖（颜色写 token，换主题随动、不碰别的组件）。
// 跑法：moon run examples/theme-playground（需要显示服务；没有时打印提示退出）

///|
let accent_presets : Array[String] = [
  "#2D68C4", // 蓝（内置基准主色）
  "#2E9E5B", // 绿
  "#D9822B", // 橙
  "#8E5CC7", // 紫
  "#199FB0", // 青
  "#D64550", // 红
]

///|
fn main {
  let primary_label : @base.Signal[String] = @base.Signal::new("当前主色：#2D68C4")
  let app_box : Ref[@widget.App?] = Ref(None)
  let stop_follow : Ref[(() -> Unit)?] = Ref(None)
  let following : @base.Store[Bool] = @base.Store::new(false)
  let apply_accent = fn(hex : String) -> Unit {
    @theme.theme_apply(@theme.theme_from_accent(hex))
    primary_label.set("当前主色：" + hex)
  }
  let app = match @ui.mount_window(
    [
      @ui.col(
        [
          // ① 换主色：主色/悬停/浅底/语义色/图表色板整套随动
          @ui.card(
            [
              @ui.color_picker(
                @base.Store::new("#2D68C4"),
                colors=accent_presets,
                on_change=apply_accent,
              ),
              @ui.text_dyn(primary_label, class=[@style.text_secondary]),
            ],
            title="① 换主色 · theme_from_accent",
          ),
          // ② 全量覆盖：整套色板替换，浅/深一键切换
          @ui.card(
            [
              @ui.row(
                [
                  @ui.button("浅色基准", on_click=fn() { @theme.theme_apply(@theme.default_theme()) }),
                  @ui.button("深色基准", on_click=fn() { @theme.theme_apply(@theme.dark_theme()) }),
                ],
                column_gap=8.0,
              ),
              @ui.text("全量替换整套色板：文字/边框/底色/图表色全部回到基准档。", class=[@style.text_secondary]),
            ],
            title="② 全量覆盖 · theme_apply",
          ),
          // ③ 持续跟随：轮询系统偏好（opt-in；起窗默认已一次性探测）
          @ui.card(
            [
              @ui.row(
                [
                  @ui.switch(following, on_text="跟随中", off_text="已停", on_change=fn(on) {
                    if on {
                      match app_box.val {
                        Some(a) =>
                          stop_follow.val = Some(a.follow_system_theme(interval_ms=2000))
                        None => ()
                      }
                    } else {
                      match stop_follow.val {
                        Some(stop) => stop()
                        None => ()
                      }
                      stop_follow.val = None
                    }
                  }),
                  @ui.text("每 2s 读一次系统深浅与主色，变了整套切换。", class=[@style.text_secondary]),
                ],
                column_gap=12.0,
              ),
            ],
            title="③ 持续跟随 · follow_system_theme",
          ),
          // ④ 类槽单组件覆盖：只有挂类槽的组件消费 primary 令牌
          @ui.card(
            [
              @ui.row(
                [
                  @ui.view([], width=48.0, height=16.0),
                  @ui.view([], width=48.0, height=16.0, class=[
                    @style.style(background_color="primary", border_radius=6.0),
                  ]),
                  @ui.text("默认正文"),
                  @ui.text("主色正文", class=[@style.style(color="primary")]),
                ],
                column_gap=12.0,
              ),
              @ui.text(
                "只有挂了类槽的组件吃 primary 令牌——换主色后色块与「主色正文」随动，左边不动。",
                class=[@style.text_secondary],
                wrap=true,
              ),
            ],
            title="④ 类槽单组件覆盖 · class",
          ),
        ],
        row_gap=12.0,
        padding=16.0,
        grow=1.0,
      ),
    ],
    title="主题定制工作台",
    width=640,
    height=600,
    handle=fn(a : @widget.App) -> Unit {
      app_box.val = Some(a)
    },
  ) {
    None => {
      println("THEME-PLAYGROUND-SKIP: 本平台没有窗口后端或没有显示服务")
      return
    }
    Some(a) => a
  }
  app.run()
}
