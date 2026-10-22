// 窗口页：窗口 API × 全局快捷键 × 拖放（应用内 + 系统级拖入 / 拖出）。
//
// 三条口径：
// ① 窗口段只放后端真写得通的按钮；改尺寸用 `set_size_pixels`；取窗口经宿主
//    `App::window()`（控件层拿不到窗口，`set_fullscreen` 收在宿主上；标题/
//    尺寸/无边框/最大化这类窗口级动作由上层直调 `@win.Window`）；
// ② 全局快捷键走 `@shell.hotkey_*` 门面（W22）：注册收 `Result`，命中经
//    `hotkey_poll` 抽（id→加速串回查表在门面里，页内只记注册返回的句柄用于
//    注销）；轮询表挂宿主 200ms 一拍；
// ③ 拖放分两段：应用内那条三平台同构；系统级两档 Windows/Linux 已接——拖入走
//    `widget/drag.mbt` 的 `drag_external_*`（一条 `on_drop` + 悬停期一次 `accept`
//    查询），拖出走 `drag_external_send`（`drag_source` 的 `external=true`，
//    本机没后端时自动回落应用内）。mac 的系统级两档待接。
//    本页三段都演示：`drag_source`/`drop_target` 两个声明式钩子 + 从资源管理器
//    拖文件进「只收文件」那块 + 两块往外拖（文本、文件）。

///|
/// 热键错误 → 可读串（门面的两档：没后端 / 有backend但这次没成）。
fn hotkey_err_text(e : @shell.HotkeyError) -> String {
  match e {
    @shell.HotkeyError::Unsupported => @shared.tx("本平台没有全局快捷键后端（当前仅 Windows）")
    @shell.HotkeyError::Failed(why) => "注册失败：\{why}"
  }
}

///|
/// 拖出回报 → 可读串：成交档给效果，没走成时给原因（后端未接会自动回落应用内）。
fn drag_send_text(r : Result[@widget.DragEffect, @widget.DragError]) -> String {
  match r {
    Ok(e) => match e {
      @widget.DragEffect::Copy => @shared.tx("已复制出去")
      @widget.DragEffect::Move => @shared.tx("已移动出去")
      @widget.DragEffect::Link => @shared.tx("已建立链接")
      @widget.DragEffect::Rejected => @shared.tx("取消或落点不收")
    }
    Err(@widget.DragError::Unsupported) => @shared.tx("本机没有系统级拖出后端（已回落应用内拖放）")
    Err(@widget.DragError::Failed(why)) => "这趟没走成：\{why}（已回落应用内拖放）"
  }
}

///|
/// 快捷键轮询表：挂上就跑，200ms 一拍自重排（宿主停/退出后 timer 自然不再响）。
/// 命中即累计 + toast——加速串由门面回查表给，调用方不持第二张表。
/// 页内容惰性挂载，故本表由段内一个零尺寸挂载钩子启动（页函数体跑完时宿主
/// 还没就绪，`app.host` 那时还是 None）。
fn hotkey_poll_loop(app : @shared.App, hits : @base.Store[Int]) -> Unit {
  let tick : Ref[() -> Unit] = Ref(fn() { () })
  tick.val = fn() -> Unit {
    match @shell.hotkey_poll() {
      Some(hk) => {
        hits.update(fn(n) { n + 1 })
        app.toast_push("快捷键触发：\{hk.spec}", @ui.Success)
      }
      None => ()
    }
    match app.host.val {
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
  app : @shared.App,
  last_op : @base.Store[String],
  text : String,
  act : (@win.Window) -> Unit,
  variant? : @ui.ButtonVariant = @ui.Soft,
) -> @widget.Node {
  @ui.button(text, variant=variant, on_click=fn() {
    match app.host.val {
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
fn open_transparent_demo(app : @shared.App, out : @base.Store[String]) -> Unit {
  fn card(title : String, body : String) -> @widget.Node {
    @ui.view(
      [@ui.text(title, role=@ui.Title), @ui.text(body, role=@ui.Body)],
      background_color="bg_panel",
      border_color="primary",
      padding=12.0,
      row_gap=4.0,
      corner_radius=10.0,
    )
  }

  match app.host.val {
    Some(a) =>
      match a.open_window(380, 280, @shared.tx("透明窗测试")) {
        Some(child) => {
          let w = child.window()
          // 先无边框再开透视：标题栏那块归系统画，留着它就不跟透视走
          w.set_borderless(true)
          w.set_transparent_bg(true)
          child.mount([
            @ui.col(
              [
                card(@shared.tx("这块不透明"), @shared.tx("卡片之外那圈像素应当是透明的，能看到桌面。")),
                @ui.text(
                  @shared.tx("这行字直接落在透明底上：字不透明，字后面的像素透明。"),
                  role=@ui.Secondary,
                ),
                @ui.view(
                  [@ui.button(@shared.tx("关掉本窗"), variant=@ui.Danger, on_click=fn() {
                    child.close_window()
                  })],
                  background_color="bg_panel",
                  padding=10.0,
                  corner_radius=10.0,
                ),
              ],
              row_gap=12.0,
              padding=16.0,
            ),
          ])
          out.set(@shared.tx("已开透明测试窗：无边框 + 背景透视，卡片外应透出桌面"))
        }
        None => out.set(@shared.tx("这台机器开不了第二扇窗（无窗口后端）"))
      }
    None => out.set(@shared.tx("宿主还没就绪"))
  }
}

///|
/// 窗口页。页内私有状态（回显/热键句柄/两个切换态）不进共享 App。
pub fn page_window(app : @shared.App) -> @widget.Node {
  let last_op : @base.Store[String] = @base.Store::new(@shared.tx("（尚无操作）"))
  // 两个切换态由按钮自己翻（窗口层没有 is_fullscreen/is_borderless 之外的
  // 读回通道，态以按钮点击为准）
  let fs : Ref[Bool] = Ref(false)
  let bl : Ref[Bool] = Ref(false)
  let sz : Ref[Int] = Ref(1280)
  let max_out : @base.Store[String] = @base.Store::new(@shared.tx("（未读过）"))
  // 快捷键：门面回查表在 shell 里，页内只记自己注册过的句柄（注销用）
  let hotkeys : Ref[Array[@shell.Hotkey]] = Ref([])
  let hk_status : @base.Store[String] = @base.Store::new(@shared.tx("（未注册）"))
  let hk_hits : @base.Store[Int] = @base.Store::new(0)
  // 拖放回显
  let dnd : @base.Store[String] = @base.Store::new(@shared.tx("（还没投过）"))
  let ext : @base.Store[String] = @base.Store::new(@shared.tx("（外部还没投过）"))
  let out : @base.Store[String] = @base.Store::new(@shared.tx("（还没往外拖过）"))
  // W30/W33/W34 新段的回显与状态
  let multiwin_out : @base.Store[String] = @base.Store::new(@shared.tx("（还没开过子窗）"))
  let layer_out : @base.Store[String] = @base.Store::new(@shared.tx("（尚无操作）"))
  let transparent_on : Ref[Bool] = Ref(false)
  let tw_out : @base.Store[String] = @base.Store::new(@shared.tx("（还没开过透明测试窗）"))
  fn win_set_opacity(alpha : Int) -> Unit {
    match app.host.val {
      Some(a) => {
        a.window().set_opacity(alpha)
        layer_out.set(@shared.tr_with("dyn.alpha_set", [("a", alpha.to_string())], "窗口 alpha 已置 \{alpha.to_string()}（/255）"))
      }
      None => ()
    }
  }
  fn win_set_layer(layer : @win.WindowLayer) -> Unit {
    match app.host.val {
      Some(a) => {
        a.window().set_layer(layer)
        let tag = match layer {
          Normal => @shared.tx("普通")
          Desktop => @shared.tx("桌面层（图标下·壁纸场景，事件归桌面）")
          DesktopWidget => @shared.tx("桌面小部件（图标上·本窗可交互）")
          AlwaysOnTop => @shared.tx("置顶")
          Dock => @shared.tx("Dock 面板档")
        }
        layer_out.set(@shared.tr_with("dyn.layer_set", [("t", tag)], "窗口层级已切到：\{tag}"))
      }
      None => ()
    }
  }
  @shared.page([
    @shared.section(
      "窗口",
      "窗口 API",
      "运行期操作窗口：改标题 / 全屏 / 尺寸切换（1280×720 ↔ 960×540）/ 无边框 / 最大化与还原。系统标题栏自带的「最大化」按钮三平台本来就有，`set_maximized` / `is_maximized` 补的是无边框自绘标题栏里自己放这个键的能力；`is_maximized` 现问平台不读缓存，所以你手点系统按钮之后它读出来的也是对的。「置顶」走下面的窗口层级档。",
      [
        @ui.row(
          [
            win_button(app, last_op, @shared.tx("改标题"), fn(_w : @win.Window) -> Unit {
              // 改名也登记进语言口（后登记者为准）：之后切语言续着这个标题换译文，
              // 不会被默认标题盖回去。
              @widget.set_window_title_localized(fn(_) {
                @shared.tx("组件库演示板 · 标题已改")
              })
            }),
            win_button(app, last_op, @shared.tx("全屏切换"), fn(w : @win.Window) -> Unit {
              fs.val = !fs.val
              w.set_fullscreen(fs.val)
            }),
            win_button(app, last_op, @shared.tx("尺寸切换"), fn(w : @win.Window) -> Unit {
              // 定死一个目标值会看着「没用」——启动尺寸就是它；两档来回切才看得见
              sz.val = if sz.val == 1280 { 960 } else { 1280 }
              let h = (sz.val.to_double() * 9.0 / 16.0).round().to_int()
              w.set_size_pixels(sz.val, h)
            }),
            win_button(app, last_op, @shared.tx("无边框切换"), fn(w : @win.Window) -> Unit {
              bl.val = !bl.val
              w.set_borderless(bl.val)
            }),
          ],
          column_gap=8.0,
        ),
        @ui.row(
          [
            win_button(app, last_op, @shared.tx("最大化"), fn(w : @win.Window) -> Unit {
              w.set_maximized(true)
              max_out.set(
                if w.is_maximized() {
                  @shared.tx("最大化态读回：true")
                } else {
                  @shared.tx("最大化态读回：false（这台机器没兑现）")
                },
              )
            }),
            win_button(app, last_op, @shared.tx("还原"), fn(w : @win.Window) -> Unit {
              w.set_maximized(false)
              max_out.set(
                if w.is_maximized() {
                  @shared.tx("最大化态读回：true（还原没兑现）")
                } else {
                  @shared.tx("最大化态读回：false")
                },
              )
            }),
            @ui.button(@shared.tx("读最大化态"), variant=@ui.Text, on_click=fn() {
              match app.host.val {
                Some(a) => {
                  last_op.set(@shared.tx("读最大化态"))
                  max_out.set(
                    if a.window().is_maximized() {
                      @shared.tx("最大化态读回：true（手点系统按钮也读得对）")
                    } else {
                      @shared.tx("最大化态读回：false")
                    },
                  )
                }
                None => ()
              }
            }),
            @ui.text(@shared.tx("先点「最大化」再点「读最大化态」，也可手点系统按钮后回来读"), role=@ui.Secondary),
          ],
          column_gap=8.0,
          align_items=@yoga.AlignItems::Center,
        ),
        @ui.row(
          [
            @ui.text(@shared.tx("最近操作："), role=@ui.Secondary),
            @ui.bind_label(last_op, fn(s) { s }),
          ],
          column_gap=6.0,
        ),
        @ui.bind_label(max_out, fn(s) { s }),
      ],
      code=[
        "// 宿主句柄挂载时由 main 的 handle 回调填入；窗口门面经它取",
        "match app.host.val {",
        "  Some(a) => {",
        "    let w = a.window()",
        "    w.set_title(\"组件库演示板 · 标题已改\")",
        "    w.set_fullscreen(true)",
        "    w.set_size_pixels(1280, 720)",
        "    w.set_borderless(true)",
        "    w.set_maximized(true)      // 最大化",
        "    if w.is_maximized() { }    // 现问平台，不读缓存布尔",
        "    w.set_maximized(false)     // 还原",
        "  }",
        "  None => ()",
        "}",
      ],
    ),
    @shared.section(
      "快捷键",
      "全局快捷键",
      "应用外生效的系统快捷键（Ctrl+Alt+C，仅 Windows；别的平台注册即返回 Unsupported）。门面持有 id→加速串回查表，轮询命中直接给 Hotkey。",
      [
        // 零尺寸挂载钩子：段首次选中时启动轮询表（见 hotkey_poll_loop）。
        // 首拍必须挂真·挂载时机（Node::on_mount）——node_of_new 的 finish 是
        // 构造期执行、那时宿主还没建好，timer 是空通道，表会当场死掉不再重排
        // （与图表页推点同一条坑，见 charts.mbt 头注释）。
        @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget { w }).on_mount(
          fn() -> Unit { hotkey_poll_loop(app, hk_hits) },
        ),
        @ui.row(
          [
            @ui.button(@shared.tx("注册 Ctrl+Alt+C"), on_click=fn() {
              match @shell.hotkey_register("Ctrl+Alt+C") {
                Ok(hk) => {
                  hotkeys.val.push(hk)
                  hk_status.set(@shared.tx("已注册（切到别的窗口按一下）"))
                }
                Err(e) => hk_status.set(hotkey_err_text(e))
              }
            }),
            @ui.button(@shared.tx("注销全部"), variant=@ui.Soft, on_click=fn() {
              for hk in hotkeys.val {
                ignore(@shell.hotkey_unregister(hk))
              }
              hotkeys.val = []
              hk_status.set(@shared.tx("已全部注销"))
            }),
          ],
          column_gap=8.0,
        ),
        @ui.row(
          [
            @ui.text(@shared.tx("状态："), role=@ui.Secondary),
            @ui.bind_label(hk_status, fn(s) { s }),
            @ui.bind_label(hk_hits, fn(n) { @shared.tr_with("dyn.hits", [("n", n.to_string())], "命中 \{n} 次") }),
          ],
          column_gap=6.0,
        ),
      ],
      code=[
        "match @shell.hotkey_register(\"Ctrl+Alt+C\") {",
        "  Ok(hk) => // hk.id / hk.spec（回查表门面自持）",
        "  Err(Unsupported) => // 非 Windows",
        "  Err(Failed(why)) => // 组合被占用 / 表满",
        "}",
        "// 宿主每拍抽一次（本页 200ms 表；native-app 每帧）",
        "match @shell.hotkey_poll() {",
        "  Some(hk) => println(\"触发：\\{hk.spec}\")",
        "  None => ()",
        "}",
        "@shell.hotkey_unregister(hk)",
      ],
    ),
    @shared.section(
      "拖放",
      "应用内拖放 + 系统级拖入 / 拖出",
      "按住左边色块拖出 4px 即开拖，拖到右边面板上会描主色边，松手成交——这条三平台同构，同一棵树上能连着拖多少次都行。系统级**拖入**（从文件管理器拖文件、从编辑器拖文本进窗口）三平台已接：外部事件每拍喂进同一条会话，落点命中、悬停描边、`accept` 判据全部复用，不收的落点系统光标直接显示禁止。系统级**拖出**（三平台）也走通：`drag_source(external=true)` 在过阈值那一刻把这趟交给系统，对方程序拿到标准的复制/移动/链接语义（Ctrl/Shift/Alt 定夺），本机没这条后端时自动回落到上面那条应用内会话。",
      [
        @ui.row(
          [
            @ui.drag_source(
              @ui.view(
                [@ui.text(@shared.tx("拖我"), role=@ui.Body)],
                background_color="primary_light",
                border_color="primary",
                width=120.0,
                height=64.0,
                padding=8.0,
              ),
              payload=fn() { Some(@widget.DragData::Text(@shared.tx("窗口页的拖放演示"))) },
            ),
            @ui.text(@shared.tx("拖到右边 →"), role=@ui.Secondary),
            @ui.drop_target(
              @ui.view(
                [@ui.text(@shared.tx("投放区（松手成交）"), role=@ui.Secondary)],
                background_color="bg_panel",
                border_color="border",
                width=220.0,
                height=64.0,
                padding=8.0,
                class=[@style.style(border_radius=6.0)],
              ),
              on_drop=fn(d : @widget.DragData, _x : Double, _y : Double) -> Unit {
                match d {
                  @widget.DragData::Text(t) => dnd.set("收到文本：\{t}")
                  @widget.DragData::Paths(ps) => {
                    let joined = ps.join(" ; ")
                    dnd.set("应用内投进 \{ps.length()} 个路径：\{joined}")
                  }
                  _ => dnd.set(@shared.tx("收到了别的载荷"))
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
                [@ui.text(@shared.tx("只收文件（从资源管理器拖进来）"), role=@ui.Secondary)],
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
              on_drop=fn(d : @widget.DragData, _x : Double, _y : Double) -> Unit {
                match d {
                  @widget.DragData::Paths(ps) => {
                    let joined = ps.join(" ; ")
                    ext.set("外部投进 \{ps.length()} 个：\{joined}")
                  }
                  _ => ext.set(@shared.tx("不该投到这里"))
                }
              },
            ),
            @ui.text(
              if @widget.drag_external_supported() {
                @shared.tx("系统级拖入：本机可用（试试从资源管理器拖文件）")
              } else {
                @shared.tx("系统级拖入：本机后端未接（拖放仍限应用内）")
              },
              role=@ui.Secondary,
            ),
          ],
          column_gap=12.0,
          align_items=@yoga.AlignItems::Center,
        ),
        @ui.row(
          [
            @ui.drag_source(
              @ui.view(
                [@ui.text(@shared.tr("drag.out.text", "拖我出去\n（浏览器/编辑器）"), role=@ui.Body)],
                background_color="primary_light",
                border_color="primary",
                width=120.0,
                height=64.0,
                padding=8.0,
              ),
              payload=fn() { Some(@widget.DragData::Text(@shared.tx("窗口页的拖放演示"))) },
              external=true,
              on_external=fn(r) { out.set("文本拖出：\{drag_send_text(r)}") },
            ),
            @ui.drag_source(
              @ui.view(
                [@ui.text(@shared.tr("drag.out.files", "拖文件出去\n（桌面/资源管理器）"), role=@ui.Body)],
                background_color="bg_panel",
                border_color="primary",
                width=150.0,
                height=64.0,
                padding=8.0,
              ),
              // 相对路径由后端绝对化（对方程序拿到的是完整位置）
              payload=fn() {
                Some(@widget.DragData::Paths([ "README.md", "proposals/adaptation.md" ]))
              },
              external=true,
              on_external=fn(r) { out.set("文件拖出：\{drag_send_text(r)}") },
            ),
            @ui.text(
              if @widget.drag_external_send_supported() {
                @shared.tx("系统级拖出：本机可用（Ctrl 复制 / Shift 移动 / Alt 链接）")
              } else {
                @shared.tx("系统级拖出：本机后端未接（自动回落应用内拖放）")
              },
              role=@ui.Secondary,
            ),
          ],
          column_gap=12.0,
          align_items=@yoga.AlignItems::Center,
        ),
        @ui.row(
          [
            @ui.text(@shared.tx("投放回显："), role=@ui.Secondary),
            @ui.bind_label(dnd, fn(s) { s }),
            @ui.text(@shared.tx("外部回显："), role=@ui.Secondary),
            @ui.bind_label(ext, fn(s) { s }),
          ],
          column_gap=6.0,
        ),
        @ui.row(
          [@ui.text(@shared.tx("拖出回显："), role=@ui.Secondary), @ui.bind_label(out, fn(s) {
            s
          })],
          column_gap=6.0,
        ),
      ],
      code=[
        "// 拖源：过 4px 阈值才开拖，payload 取数（None 当普通点击）",
        "@ui.drag_source(",
        "  tile,",
        "  payload=fn() { Some(@widget.DragData::Text(\"窗口页的拖放演示\")) },",
        ")",
        "// 投放目标：悬停描主色边（读 drag_hover 自判，无 enter/leave 三回调）",
        "@ui.drop_target(",
        "  panel,",
        "  accept=fn(d) { d.kind() == @widget.DataKind::FilePaths }, // 不收时系统光标显示禁止",
        "  on_drop=fn(d, _x, _y) {",
        "    match d {",
        "      @widget.DragData::Paths(ps) => ...",
        "      _ => ...",
        "    }",
        "  },",
        ")",
        "// 系统级拖入（三平台）：建窗自动挂投放目标，宿主每拍抽事件喂进同一条",
        "// 会话；运行时探测决定这台机器能不能用",
        "if @widget.drag_external_supported() { ... }",
        "// 系统级拖出（三平台）：过阈值那一刻把这趟交给系统，阻塞到松手/取消；",
        "// 本机后端没接或这趟起不来时自动回落到应用内会话",
        "@ui.drag_source(",
        "  tile,",
        "  payload=fn() { Some(@widget.DragData::Paths([ \"README.md\" ])) }, // 相对路径会被绝对化",
        "  external=true,",
        "  on_external=fn(r) { ... }, // Ok(效果)=成交/取消，Err=没走成（已回落）",
        ")",
      ],
    ),

    @shared.section(
      "多窗口",
      "开子窗 / 列窗 / 关子窗",
      "宿主注册表是进程级的：`App::open_window` 开第二扇窗、`App::window_count` 数窗、`App::active_window` 取当前活动窗、`close_window` 关自己那窗。关从窗不退出应用，只有主窗关或全关完才整体退出。每扇窗内容各自挂自己的 Node 树，事件路由与上屏逐窗走。",
      [
        @ui.row(
          [
            @ui.button(@shared.tx("开子窗"), on_click=fn() {
              match app.host.val {
                Some(a) =>
                  match a.open_window(360, 240, @shared.tx("showcase 子窗")) {
                    Some(child) => {
                      child.mount([
                        @ui.col(
                          [
                            @ui.text(@shared.tx("这是第二扇窗"), role=@ui.Title),
                            @ui.text(@shared.tx("主窗与子窗事件各自独立；关本窗不退出应用。"), role=@ui.Secondary),
                            @ui.button(@shared.tx("关掉我自己"), variant=@ui.Danger, on_click=fn() {
                              child.close_window()
                            }),
                          ],
                          row_gap=12.0,
                          padding=24.0,
                        ),
                      ])
                      multiwin_out.set(@shared.tr_with("dyn.child_opened", [("n", a.window_count().to_string())], "已开子窗，当前共 \{a.window_count().to_string()} 扇"))
                    }
                    None => multiwin_out.set(@shared.tx("这台机器开不了第二扇窗（无窗口后端）"))
                  }
                None => multiwin_out.set(@shared.tx("宿主还没就绪"))
              }
            }),
            @ui.button(@shared.tx("列窗数"), variant=@ui.Soft, on_click=fn() {
              match app.host.val {
                Some(a) => multiwin_out.set(@shared.tr_with("dyn.window_count", [("n", a.window_count().to_string())], "当前共 \{a.window_count().to_string()} 扇窗"))
                None => ()
              }
            }),
            @ui.button(@shared.tx("关最近一扇子窗"), variant=@ui.Text, on_click=fn() {
              match app.host.val {
                Some(a) =>
                  match a.active_window() {
                    Some(act) =>
                      if act.is_primary() {
                        multiwin_out.set(@shared.tx("当前活动窗是主窗，不关它"))
                      } else {
                        act.close_window()
                        multiwin_out.set(@shared.tr_with("dyn.child_closed", [("n", a.window_count().to_string())], "已关一扇子窗，剩 \{a.window_count().to_string()} 扇"))
                      }
                    None => multiwin_out.set(@shared.tx("没有活动窗"))
                  }
                None => ()
              }
            }),
          ],
          column_gap=8.0,
        ),
        @ui.bind_label(multiwin_out, fn(s) { s }),
      ],
      code=[
        "match app.host.val {",
        "  Some(a) => {",
        "    let child = a.open_window(360, 240, \"子窗\")",
        "    child.mount([ ... ])        // 子窗内容自己挂",
        "    let n = a.window_count()    // 进程级注册表",
        "    let act = a.active_window() // 当前活动窗",
        "    act.close_window()          // 关自己那窗，不退出应用",
        "  }",
        "  None => ()",
        "}",
      ],
    ),

    @shared.section(
      "透明度",
      "窗口透明与背景穿透",
      "两件不同的事。`set_opacity` 是**整窗 alpha**（0–255）——连同文字与控件一起变淡，需要合成器，没有就静默无效。`set_transparent_bg` 是**背景透视**——控件没铺到的像素留成透明，桌面从那些洞透出来，铺了底色的控件照旧不透明（Windows 上要无边框才成立，带边框的窗自动退回不透视）。主窗看不了后者的效果：这一页整片铺满底色，没有「没铺到的像素」；点下面的「开透明测试窗」单开一扇无边框窗，里面只放几块卡片来验。",
      [
        @ui.row(
          [
            @ui.button("100%", on_click=fn() { win_set_opacity(255) }),
            @ui.button("80%", variant=@ui.Soft, on_click=fn() { win_set_opacity(204) }),
            @ui.button("50%", variant=@ui.Soft, on_click=fn() { win_set_opacity(128) }),
            @ui.button("25%", variant=@ui.Soft, on_click=fn() { win_set_opacity(64) }),
            @ui.button(@shared.tx("背景穿透"), variant=@ui.Text, on_click=fn() {
              transparent_on.val = !transparent_on.val
              let on = transparent_on.val
              match app.host.val {
                Some(a) => {
                  a.window().set_transparent_bg(on)
                  layer_out.set(
                    if on {
                      @shared.tx("背景穿透：开（本页铺满底色，看得见的只有 alpha 的变化；要点下面的测试窗才看得见透视）")
                    } else {
                      @shared.tx("背景穿透：关")
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
            @ui.button(@shared.tx("开透明测试窗"), on_click=fn() {
              open_transparent_demo(app, tw_out)
            }),
            @ui.text(
              @shared.tx("测试窗：无边框 + 背景透视，卡片外那圈应当是桌面；窗内自带「关掉本窗」"),
              role=@ui.Secondary,
            ),
          ],
          column_gap=8.0,
          align_items=@yoga.AlignItems::Center,
        ),
        @ui.bind_label(tw_out, fn(s) { s }),
        @ui.bind_label(layer_out, fn(s) { s }),
      ],
      code=[
        "// 整窗 alpha（0–255）：连字一起淡，需合成器",
        "app.window().set_opacity(128) // 50%",
        "// 背景透视：控件没铺到的像素留透明，桌面从洞里透出",
        "app.window().set_transparent_bg(true)",
        "// 要看得见，得有一扇「根不铺底」的窗：单开一扇，只放不透明卡片",
        "match app.open_window(380, 280, \"透明窗测试\") {",
        "  Some(child) => {",
        "    child.window().set_borderless(true)",
        "    child.window().set_transparent_bg(true)",
        "    child.mount([@ui.col([card1, card2], padding=16.0)]) // 根容器不给底色",
        "  }",
        "  None => ()",
        "}",
      ],
    ),

    @shared.section(
      "层级",
      "窗口层级嵌入",
      "`Window::set_layer` 换窗口层级。面板三档（图标下 / 图标上 / Dock）承诺的是同一件事：不进任务栏与窗口列表、不进窗口循环、跨工作区常驻，Dock 另带压顶；**边框与标题栏不在承诺内**，外观照你给的 styleMask 与系统窗口设置走。兑现手段各不同：Linux 显式发 `_NET_WM_STATE_ABOVE/SKIP_TASKBAR/SKIP_PAGER/STICKY`（不再换窗口类型，换 TYPE_DOCK 会让 WM 顺手摘装饰、逐出焦点列表），macOS 配 `CanJoinAllSpaces|Stationary|IgnoresCycle`、Dock 档再叠 `FullScreenAuxiliary` 取 Dock 层盖全屏 Space，Win32 用 `WS_EX_TOOLWINDOW` 管任务栏与 Alt+Tab、`SetWindowPos` 管叠放，「图标下」另把本窗挂进 Explorer 的壁纸 WorkerW——那是 Win32 上唯一压得住桌面图标的落点，代价是随 `WS_CHILD` 摘掉装饰、不再拿键盘焦点（这一档本就「事件归桌面」）。三平台都没有「预留工作区」的公共通道（Windows AppBar 未接、macOS 无 API），目标层最终由 WM/Shell/AppKit 定。",      [
        @ui.row(
          [
            @ui.button(@shared.tx("普通"), on_click=fn() { win_set_layer(@win.WindowLayer::Normal) }),
            @ui.button(@shared.tx("图标下"), variant=@ui.Soft, on_click=fn() {
              win_set_layer(@win.WindowLayer::Desktop)
            }),
            @ui.button(@shared.tx("图标上"), variant=@ui.Soft, on_click=fn() {
              win_set_layer(@win.WindowLayer::DesktopWidget)
            }),
            @ui.button(@shared.tx("置顶"), variant=@ui.Soft, on_click=fn() {
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
      code=[
        "app.window().set_layer(@win.WindowLayer::AlwaysOnTop)   // 置顶",
        "app.window().set_layer(@win.WindowLayer::Desktop)       // 图标下：壁纸场景",
        "app.window().set_layer(@win.WindowLayer::DesktopWidget) // 图标上：小部件，可交互",
        "app.window().set_layer(@win.WindowLayer::Dock)          // 面板档",
        "app.window().set_layer(@win.WindowLayer::Normal)        // 复位",
      ],
    ),
  ])
}
