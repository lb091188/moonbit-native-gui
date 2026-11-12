// 窗口功能演示段（迁自 components 窗口页）：纵向排在 mng 入门页与基本窗口
// 示例之后，八段全量搬入——窗口 API / 全局快捷键 / 拖放 / 多窗口 / 透明度 /
// 层级 / 显隐驻留 / 状态记忆。三条口径沿用原页：
// ① 窗口段只放后端真写得通的按钮；取窗口经宿主 `WindowHost::window()`
//    （`set_fullscreen` 收在宿主上；标题/尺寸/无边框/最大化这类窗口级动作
//    由上层直调 `@win.Window`）；
// ② 全局快捷键走 `@shell.hotkey_*` 门面：注册收 `Result`，命中经
//    `hotkey_poll` 抽（id→加速串回查表在门面里，段内只记注册返回的句柄用于
//    注销）；轮询表挂宿主 200ms 一拍，命中写回显行（原页的 toast 在 hello
//    没有全局层，统一落状态行）；
// ③ 拖放分两段：应用内那条三平台同构；系统级拖入 / 拖出（mac 的系统级两档
//    待接，未接机器自动回落应用内会话）。
// 展示形态按 hello 定位从简：段容器只有标题 + 说明 + 内容（无 code 展示区），
// 文案直写中文（hello 不接 i18n）。

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
/// 热键错误 → 可读串（门面的两档：没后端 / 有后端但这次没成）。
fn hotkey_err_text(e : @shell.HotkeyError) -> String {
  match e {
    @shell.HotkeyError::Unsupported =>
      "本平台没有全局快捷键后端（Wayland 会话）"
    @shell.HotkeyError::Failed(why) => "注册失败：\{why}"
  }
}

///|
/// 拖出回报 → 可读串：成交档给效果，没走成时给原因（后端未接会自动回落应用内拖放）。
fn drag_send_text(r : Result[@widget.DragEffect, @widget.DragError]) -> String {
  match r {
    Ok(e) =>
      match e {
        @widget.DragEffect::Copy => "已复制出去"
        @widget.DragEffect::Move => "已移动出去"
        @widget.DragEffect::Link => "已建立链接"
        @widget.DragEffect::Rejected => "取消或落点不收"
      }
    Err(@widget.DragError::Unsupported) =>
      "本机没有系统级拖出后端（已回落应用内拖放）"
    Err(@widget.DragError::Failed(why)) =>
      "这趟没走成：\{why}（已回落应用内拖放）"
  }
}

///|
/// 快捷键轮询表：挂上就跑，200ms 一拍自重排（宿主停/退出后 timer 自然不再响）。
/// 命中即累计 + 状态行回显（键名由门面回查表给，调用方不持第二张表）。
/// 段内容随主窗一次挂载，但宿主句柄在挂载回调里才就绪，故本表由段内一个
/// 零尺寸挂载钩子启动——首拍必须挂真·挂载时机（Node::on_mount）：
/// node_of_new 的 finish 是构造期执行、那时宿主还没建好，timer 是空通道，
/// 表会当场死掉不再重排（与图表页推点同一条坑）。
fn hotkey_poll_loop(
  host : Ref[@widget.WindowHost?],
  status : @base.Store[String],
  hits : @base.Store[Int32],
) -> Unit {
  let tick : Ref[() -> Unit] = Ref(fn() { () })
  tick.val = fn() -> Unit {
    match @shell.hotkey_poll() {
      Some(hk) => {
        hits.update(fn(n) { n + 1 })
        status.set("快捷键触发：\{hk.spec}")
      }
      None => ()
    }
    match host.val {
      Some(a) => ignore(a.timer(200, tick.val))
      None => ()
    }
  }
  (tick.val)()
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
/// 层级探针窗：层级讲的是「这扇窗在桌面上占哪一层」。在主窗上切，等于把整页
/// 丢到桌面层 / 面板档里去——验完还得切回来，中途整页自己都不见了。所以单开
/// 一扇小窗，五档全施加在它身上，主窗保持普通档。
fn open_layer_probe(
  host : Ref[@widget.WindowHost?],
  slot : Ref[@widget.WindowHost?],
  out : @base.Store[String],
) -> Unit {
  match slot.val {
    Some(_) =>
      out.set("层级探针窗已经开着（下面五档切的就是它）")
    None =>
      match host.val {
        Some(a) =>
          match a.open_window(320, 180, "层级探针窗") {
            Some(child) => {
              child.mount([
                @ui.col(
                  [
                    @ui.text("层级作用在我这扇窗上", class=[
                      @style.text_heading,
                    ]),
                    @ui.text(
                      "主窗保持普通档：切「图标下 / Dock」时只有我掉层，整页不会跟着消失。",
                      wrap=true,
                    ),
                  ],
                  row_gap=8.0,
                  padding=20.0,
                ),
              ])
              slot.val = Some(child)
              out.set("已开层级探针窗：下面五档都切这一扇")
            }
            None =>
              out.set("这台机器开不了第二扇窗（无窗口后端）")
          }
        None => out.set("宿主还没就绪")
      }
  }
}

///|
/// 驻留探针窗：`hide` 之后整页不能跟着一起消失，否则没有按钮能把它唤回来。
/// 本窗固定落到 (160, 160) 再记原点，"唤回" 时读 `origin()` 就能证明是回到原地
/// 而不是居中重开。窗里另带两样：显隐事件回显（`App::on_hidden` / `App::on_shown`
/// 计数）与「2 秒后自动隐藏」开关——勾上后点进输入框打拼音（组合串在屏、焦点
/// 不动），到点本窗 hide，唤回后组合串应已清（隐藏清组合串的真机验法）。
fn open_resident_probe(
  host : Ref[@widget.WindowHost?],
  slot : Ref[@widget.WindowHost?],
  out : @base.Store[String],
) -> Unit {
  match slot.val {
    Some(_) => out.set("驻留探针窗已经开着")
    None =>
      match host.val {
        Some(a) =>
          match a.open_window(380, 330, "驻留探针窗") {
            Some(child) => {
              let w = child.window()
              w.move_to(160, 160)
              let hidden_n = Ref(0)
              let shown_n = Ref(0)
              let hits : @base.Store[String] = @base.Store::new(
                "（还没有显隐事件）",
              )
              let note = fn() -> Unit {
                hits.set(
                  "已隐藏 \{hidden_n.val} 次 · 已显示 \{shown_n.val} 次",
                )
              }
              child.on_hidden(fn() -> Unit {
                hidden_n.val = hidden_n.val + 1
                note()
              })
              child.on_shown(fn() -> Unit {
                shown_n.val = shown_n.val + 1
                note()
              })
              // 自动隐藏：勾选起一次性 2 秒延时，取消即停表（验法见窗内说明）
              let auto : @base.Store[Bool] = @base.Store::new(false)
              let timer_id : Ref[Int32] = Ref(-1)
              let _ = auto
                .signal()
                .subscribe(fn(on : Bool) -> Unit {
                  if on {
                    timer_id.val = child.timer(2000, fn() -> Unit { w.hide() })
                  } else if timer_id.val >= 0 {
                    let _ = child.cancel_timer(timer_id.val)
                    timer_id.val = -1
                  }
                })
              let demo : @base.Store[String] = @base.Store::new("")
              child.mount([
                @ui.col(
                  [
                    @ui.text("显隐驻留", class=[@style.text_heading]),
                    @ui.text(
                      "点下面这颗后本窗 hide；主窗的「唤回」把它 show 回来。",
                      wrap=true,
                    ),
                    @ui.button("隐藏我自己", variant=@ui.Soft, on_click=fn() {
                      w.hide()
                    }),
                    @ui.checkbox("2 秒后自动隐藏", auto),
                    @ui.text(
                      "验隐藏清组合串：勾上 → 点输入框打拼音（别提交）→ 到点本窗 hide → 主窗唤回，组合串应已清。",
                      wrap=true,
                    ),
                    @ui.input(
                      demo,
                      placeholder="在这里打拼音",
                      width=320.0,
                    ),
                    @ui.bind_label(hits, fn(s : String) { s }),
                    @ui.text("固定落在 (160, 160)"),
                  ],
                  row_gap=8.0,
                  padding=20.0,
                ),
              ])
              slot.val = Some(child)
              out.set("已开驻留探针窗，落在 (160, 160)")
            }
            None =>
              out.set("这台机器开不了第二扇窗（无窗口后端）")
          }
        None => out.set("宿主还没就绪")
      }
  }
}

///|
/// 窗口功能八段。段内私有状态（回显/热键句柄/两个切换态）不进 main。
fn window_sections(host : Ref[@widget.WindowHost?]) -> Array[@widget.Node] {
  let last_op : @base.Store[String] = @base.Store::new("（尚无操作）")
  // 两个切换态由按钮自己翻（窗口层没有 is_fullscreen/is_borderless 之外的
  // 读回通道，态以按钮点击为准）
  let fs : Ref[Bool] = Ref(false)
  let bl : Ref[Bool] = Ref(false)
  let sz : Ref[Int32] = Ref(1280)
  let max_out : @base.Store[String] = @base.Store::new("（未读过）")
  // 快捷键：门面回查表在 shell 里，段内只记自己注册过的句柄（注销用）
  let hotkeys : Ref[Array[@shell.Hotkey]] = Ref([])
  let hk_status : @base.Store[String] = @base.Store::new("（未注册）")
  let hk_hits : @base.Store[Int32] = @base.Store::new(0)
  // 拖放回显
  let dnd : @base.Store[String] = @base.Store::new("（还没投过）")
  let ext : @base.Store[String] = @base.Store::new("（外部还没投过）")
  let out : @base.Store[String] = @base.Store::new("（还没往外拖过）")
  let multiwin_out : @base.Store[String] = @base.Store::new(
    "（还没开过子窗）",
  )
  let layer_out : @base.Store[String] = @base.Store::new("（尚无操作）")
  let transparent_on : Ref[Bool] = Ref(false)
  let tw_out : @base.Store[String] = @base.Store::new(
    "（还没开过透明测试窗）",
  )
  // 多开窗口的两个探针：层级与显隐都作用在独立小窗上，主窗不动
  let layer_probe : Ref[@widget.WindowHost?] = Ref(None)
  let resident_probe : Ref[@widget.WindowHost?] = Ref(None)
  let resident_out : @base.Store[String] = @base.Store::new(
    "（还没开驻留探针窗）",
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
  fn win_set_layer(layer : @win.WindowLayer) -> Unit {
    match layer_probe.val {
      Some(child) => {
        child.window().set_layer(layer)
        let tag = match layer {
          Normal => "普通"
          Desktop => "桌面层（图标下·壁纸场景，事件归桌面）"
          DesktopWidget => "桌面小部件（图标上·本窗可交互）"
          AlwaysOnTop => "置顶"
          Dock => "Dock 面板档"
        }
        layer_out.set("探针窗层级已切到：\{tag}")
      }
      None =>
        layer_out.set(
          "先点「开层级探针窗」，层级施加在它身上而不是主窗",
        )
    }
  }
  [
    // —— 窗口 API ——
    hello_section(
      "窗口 API",
      "运行期操作窗口：改标题 / 全屏 / 尺寸切换（1280×720 ↔ 960×540）/ 无边框 / 最大化与还原。系统标题栏自带的「最大化」按钮三平台本来就有，`set_maximized` / `is_maximized` 补的是无边框自绘标题栏里自己放这个键的能力；`is_maximized` 现问平台不读缓存，所以你手点系统按钮之后它读出来的也是对的。「置顶」走下面的窗口层级档。",
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
    // —— 全局快捷键 ——
    hello_section(
      "全局快捷键",
      "应用外生效的系统快捷键：统一写 CmdOrCtrl+Alt+C，macOS 落 Cmd、Windows/Linux 落 Ctrl（Wayland 会话注册返回 Unsupported）。门面持有 id→键名回查表，轮询命中直接给 Hotkey，键名是平台规范名（mac 上显示 Cmd+Alt+C）。命中与本段状态行回显。",
      [
        // 零尺寸挂载钩子：主窗挂载时启动轮询表（见 hotkey_poll_loop）
        @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget { w }).on_mount(fn() -> Unit {
            hotkey_poll_loop(host, hk_status, hk_hits)
          },
        ),
        @ui.row(
          [
            @ui.button("注册 CmdOrCtrl+Alt+C", on_click=fn() {
              match @shell.hotkey_register("CmdOrCtrl+Alt+C") {
                Ok(hk) => {
                  hotkeys.val.push(hk)
                  hk_status.set("已注册（切到别的窗口按一下）")
                }
                Err(e) => hk_status.set(hotkey_err_text(e))
              }
            }),
            @ui.button("注销全部", variant=@ui.Soft, on_click=fn() {
              for hk in hotkeys.val {
                ignore(@shell.hotkey_unregister(hk))
              }
              hotkeys.val = []
              hk_status.set("已全部注销")
            }),
          ],
          column_gap=8.0,
        ),
        @ui.row(
          [
            @ui.text("状态："),
            @ui.bind_label(hk_status, fn(s) { s }),
            @ui.bind_label(hk_hits, fn(n) { "命中 \{n} 次" }),
          ],
          column_gap=6.0,
        ),
      ],
    ),
    // —— 拖放 ——
    hello_section(
      "拖放",
      "按住左边色块拖出 4px 即开拖，拖到右边面板上会描主色边，松手成交——这条三平台同构，同一棵树上能连着拖多少次都行。系统级**拖入**（从文件管理器拖文件、从编辑器拖文本进窗口）三平台已接：外部事件每拍喂进同一条会话，落点命中、悬停描边、`accept` 判据全部复用，不收的落点系统光标直接显示禁止。系统级**拖出**（三平台）也走通：`drag_source(external=true)` 在过阈值那一刻把这趟交给系统，对方程序拿到标准的复制/移动/链接语义（Ctrl/Shift/Alt 定夺），本机没这条后端时自动回落到上面那条应用内会话。",
      [
        @ui.row(
          [
            @ui.drag_source(
              @ui.view(
                [@ui.text("拖我")],
                background_color="primary_light",
                border_color="primary",
                width=120.0,
                height=64.0,
                padding=8.0,
              ),
              payload=fn() {
                Some(@widget.DragData::Text("你好窗口的拖放演示"))
              },
            ),
            @ui.text("拖到右边 →"),
            @ui.drop_target(
              @ui.view(
                [@ui.text("投放区（松手成交）")],
                background_color="bg_panel",
                border_color="border",
                width=220.0,
                height=64.0,
                padding=8.0,
                class=[@style.style(border_radius=6.0)],
              ),
              on_drop=fn(
                d : @widget.DragData,
                _x : Double,
                _y : Double,
              ) -> Unit {
                match d {
                  @widget.DragData::Text(t) => dnd.set("收到文本：\{t}")
                  @widget.DragData::Paths(ps) => {
                    let joined = ps.join(" ; ")
                    dnd.set(
                      "应用内投进 \{ps.length()} 个路径：\{joined}",
                    )
                  }
                  _ => dnd.set("收到了别的载荷")
                }
              },
            ),
          ],
          column_gap=12.0,
          align_items=@yoga.AlignItems::Center,
        ),
        @ui.row(
          [
            @ui.drop_target(
              @ui.view(
                [@ui.text("只收文件（从资源管理器拖进来）")],
                background_color="bg_panel",
                border_color="border",
                width=220.0,
                height=64.0,
                padding=8.0,
                class=[@style.style(border_radius=6.0)],
              ),
              accept=fn(d : @widget.DragData) -> Bool {
                d.kind() == @widget.DataKind::FilePaths
              },
              on_drop=fn(
                d : @widget.DragData,
                _x : Double,
                _y : Double,
              ) -> Unit {
                match d {
                  @widget.DragData::Paths(ps) => {
                    let joined = ps.join(" ; ")
                    ext.set("外部投进 \{ps.length()} 个：\{joined}")
                  }
                  _ => ext.set("不该投到这里")
                }
              },
            ),
            @ui.text(
              if @widget.drag_external_supported() {
                "系统级拖入：本机可用（试试从资源管理器拖文件）"
              } else {
                "系统级拖入：本机后端未接（拖放仍限应用内）"
              },
            ),
          ],
          column_gap=12.0,
          align_items=@yoga.AlignItems::Center,
        ),
        @ui.row(
          [
            @ui.drag_source(
              @ui.view(
                [@ui.text("拖我出去\n（浏览器/编辑器）")],
                background_color="primary_light",
                border_color="primary",
                width=120.0,
                height=64.0,
                padding=8.0,
              ),
              payload=fn() {
                Some(@widget.DragData::Text("你好窗口的拖放演示"))
              },
              external=true,
              on_external=fn(r) {
                out.set("文本拖出：\{drag_send_text(r)}")
              },
            ),
            @ui.drag_source(
              @ui.view(
                [@ui.text("拖文件出去\n（桌面/资源管理器）")],
                background_color="bg_panel",
                border_color="primary",
                width=150.0,
                height=64.0,
                padding=8.0,
              ),
              // 相对路径由后端按进程 CWD 绝对化（标准启动 `cd examples/hello &&
              // moon run .`，CWD 在本模块目录），必须指到**真实存在**的文件——
              // 不存在的路径三平台都按死条目跳过，全空则本机拖出失败、回落应用内
              payload=fn() {
                Some(
                  @widget.DragData::Paths([
                    "../../README.md", "../../experience/adaptation.md",
                  ]),
                )
              },
              external=true,
              on_external=fn(r) {
                out.set("文件拖出：\{drag_send_text(r)}")
              },
            ),
            @ui.text(
              if @widget.drag_external_send_supported() {
                "系统级拖出：本机可用（Ctrl 复制 / Shift 移动 / Alt 链接）"
              } else {
                "系统级拖出：本机后端未接（自动回落应用内拖放）"
              },
            ),
          ],
          column_gap=12.0,
          align_items=@yoga.AlignItems::Center,
        ),
        @ui.row(
          [
            @ui.text("投放回显："),
            @ui.bind_label(dnd, fn(s) { s }),
            @ui.text("外部回显："),
            @ui.bind_label(ext, fn(s) { s }),
          ],
          column_gap=6.0,
        ),
        @ui.row(
          [@ui.text("拖出回显："), @ui.bind_label(out, fn(s) { s })],
          column_gap=6.0,
        ),
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
      "两件不同的事。`set_opacity` 是**整窗 alpha**（0–255）——连同文字与控件一起变淡，需要合成器，没有就静默无效。`set_transparent_bg` 是**背景透视**——控件没铺到的像素留成透明，桌面从那些洞透出来，铺了底色的控件照旧不透明（Windows 上要无边框才成立，带边框的窗自动退回不透视）；**要经 `App::set_transparent_bg` 开**——宿主默认页面底会铺满整窗，直调窗口层摘不掉它。主窗看不了后者的效果：这一页整片铺满底色，没有「没铺到的像素」；点下面的「开透明测试窗」单开一扇无边框窗，里面只放几块卡片来验。",
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
            @ui.button("背景穿透", variant=@ui.Text, on_click=fn() {
              transparent_on.val = !transparent_on.val
              let on = transparent_on.val
              match host.val {
                Some(a) => {
                  a.set_transparent_bg(on)
                  layer_out.set(
                    if on {
                      "背景穿透：开（本页铺满底色，看得见的只有 alpha 的变化；要点下面的测试窗才看得见透视）"
                    } else {
                      "背景穿透：关"
                    },
                  )
                }
                None => ()
              }
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
    // —— 窗口层级 ——
    hello_section(
      "窗口层级",
      "`Window::set_layer` 换窗口层级。层级说的是「这扇窗在桌面上占哪一层」，所以演示不拿主窗开刀：点「开层级探针窗」单起一扇小窗，五档全切它，主窗留在普通档——切「图标下 / Dock」时不会连整页一起掉层。面板三档（图标下 / 图标上 / Dock）承诺的是同一件事：不进任务栏与窗口列表、不进窗口循环、跨工作区常驻，Dock 另带压顶；**边框与标题栏不在承诺内**，外观照系统窗口设置走。",
      [
        @ui.row(
          [
            @ui.button("开层级探针窗", variant=@ui.Solid, on_click=fn() {
              open_layer_probe(host, layer_probe, layer_out)
            }),
            @ui.button("关探针窗", variant=@ui.Text, on_click=fn() {
              match layer_probe.val {
                Some(child) => {
                  child.close_window()
                  layer_probe.val = None
                  layer_out.set("探针窗已关")
                }
                None => layer_out.set("探针窗本来就没开")
              }
            }),
          ],
          column_gap=8.0,
        ),
        @ui.row(
          [
            @ui.button("普通", on_click=fn() {
              win_set_layer(@win.WindowLayer::Normal)
            }),
            @ui.button("图标下", variant=@ui.Soft, on_click=fn() {
              win_set_layer(@win.WindowLayer::Desktop)
            }),
            @ui.button("图标上", variant=@ui.Soft, on_click=fn() {
              win_set_layer(@win.WindowLayer::DesktopWidget)
            }),
            @ui.button("置顶", variant=@ui.Soft, on_click=fn() {
              win_set_layer(@win.WindowLayer::AlwaysOnTop)
            }),
            @ui.button("Dock", variant=@ui.Text, on_click=fn() {
              win_set_layer(@win.WindowLayer::Dock)
            }),
          ],
          column_gap=8.0,
        ),
        @ui.bind_label(layer_out, fn(s) { s }),
      ],
    ),
    // —— 显隐驻留 ——
    hello_section(
      "显隐驻留",
      "`hide` 把窗收起来、`show` 再放回来，回来的是 **hide 前的屏幕原点**，不是居中重开。这一条也没法拿主窗验：一 hide 整页就没了，没有按钮能唤回。所以单开一扇「驻留探针窗」，固定落在 (160, 160)（用 `move_to` 定死，免得 WM 归位干扰判断）；窗里自带「隐藏我自己」，主窗这颗「唤回」负责 `show`，再点「读窗位置」核对坐标是否还是 (160, 160)。",
      [
        @ui.row(
          [
            @ui.button("开驻留探针窗", on_click=fn() {
              open_resident_probe(host, resident_probe, resident_out)
            }),
            @ui.button("隐藏", variant=@ui.Soft, on_click=fn() {
              match resident_probe.val {
                Some(child) => {
                  child.window().hide()
                  resident_out.set(
                    "已 hide：探针窗应当从屏幕上消失",
                  )
                }
                None => resident_out.set("先点「开驻留探针窗」")
              }
            }),
            @ui.button("唤回", variant=@ui.Soft, on_click=fn() {
              match resident_probe.val {
                Some(child) => {
                  child.window().show()
                  resident_out.set(
                    "已 show：应当回到 hide 前的原点，不是居中重开",
                  )
                }
                None => resident_out.set("先点「开驻留探针窗」")
              }
            }),
            @ui.button("读窗位置", variant=@ui.Text, on_click=fn() {
              match resident_probe.val {
                Some(child) => {
                  let (x, y) = child.window().origin()
                  let hidden = child.window().is_hidden()
                  let hs = if hidden { "true" } else { "false" }
                  resident_out.set(
                    "探针窗位置 (\{x}, \{y})，is_hidden=\{hs}",
                  )
                }
                None => resident_out.set("先点「开驻留探针窗」")
              }
            }),
          ],
          column_gap=8.0,
        ),
        @ui.bind_label(resident_out, fn(s) { s }),
      ],
    ),
    // —— 状态记忆 ——
    hello_section(
      "状态记忆",
      "`remember_geometry(app_id)` 一行接上：开窗后先恢复上次的位置/尺寸/最大化档（文件在才恢复，首次运行不动窗口），关窗或退出时自动写回。演示对主窗做——点「开始记住本窗」后挪一挪、缩一缩甚至最大化，关掉窗口再 `moon run .`：窗口应当回到上次的样子（再点一次按钮取消记忆，回到默认居中开）。落盘位置按平台：macOS `~/Library/Application Support/libyue.hello/`、Linux `$XDG_STATE_HOME`（或 `~/.local/state`）/libyue.hello/、Windows `%APPDATA%\\libyue.hello\\`，文件都是 window-state.json——怪位置（比如拔了外接显示器后落在屏外）删掉它就回默认。v1 边界：恢复不做屏幕钳位；多窗应用对同一 id 只记一份，各窗分开记就换不同的 id 后缀。",
      [
        @ui.row(
          [
            @ui.button("开始记住本窗", on_click=fn() {
              match host.val {
                Some(a) => {
                  a.remember_geometry("libyue.hello")
                  last_op.set(
                    "已开始记忆：挪窗/缩放/最大化后退出，下次启动回到该样子（文件 window-state.json）",
                  )
                }
                None => ()
              }
            }),
            @ui.button("取消记忆", variant=@ui.Text, on_click=fn() {
              match host.val {
                Some(a) => {
                  a.remember_id = ""
                  last_op.set(
                    "已取消：下次启动按默认开（旧状态文件留在原地，不主动删）",
                  )
                }
                None => ()
              }
            }),
            @ui.text(
              "对主窗生效；关窗与退出都会自动写回",
              wrap=true,
            ),
          ],
          column_gap=8.0,
          align_items=@yoga.AlignItems::Center,
        ),
        @ui.bind_label(last_op, fn(s) { s }),
      ],
    ),
  ]
}
