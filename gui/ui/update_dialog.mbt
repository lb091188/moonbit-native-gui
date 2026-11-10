// 应用更新对话框(v1):「检查 → 有新版 → 下载 → 安装重启」的现成状态机 UI,
// 与 `dialog` / `message_box` 同住浮层图层(遮罩 + 居中面板,临开临建)。
//
// 分工口径(方案见 proposals/package-update.md §五):
// - 本组件只管**状态机与视图**:视图按钮先标状态(同步装配下 Loading 至少先画
//   出来)再触发动作,动作结果由装配方经 `report_*` 口喂回;
// - 网络/磁盘动作由调用方以 `UpdateActions` 闭包注入——sys 的 `pr_run` 是同步
//   阻塞的,「怎么跑」(直接跑 / 错一拍 / 后台线程)由装配方决定,组件不硬塞。
//   库侧另给 `sys_update_actions` 直连装配(动作错一拍再跑,见其注释)。
//
// v1 边界:无 Esc/点外收起(只走按钮,Installing 态不给出口);下载无进度
// 百分比(sys 无文件尺寸原语)也无取消(curl 同步跑,取消随异步执行器批)。

///|
/// 失败后的可重试步:重试钮按它回到对应动作;`RetryNone` 不给重试钮。
pub(all) enum UpdateRetry {
  RetryNone
  RetryCheck
  RetryDownload
}

///|
/// 更新流程状态:Idle(待检查)/ Checking / UpToDate(已是最新)/
/// Available(有新版:版本号 + 更新说明)/ Downloading / Ready(下载完成待安装)/
/// Installing(替换文件 + 重启中,成功即随进程退出,是终态)/ Failed(原因 + 可重试步)。
pub(all) enum UpdateState {
  Idle
  Checking
  UpToDate
  Available(String, String)
  Downloading
  Ready
  Installing
  Failed(String, UpdateRetry)
}

///|
/// 更新流程账本:状态 Store 驱动视图;`found` 记检查命中的清单(下载动作用),
/// `carrier` 记下载产物路径(安装动作用)——都在报告口收,动作闭包构造时捕获
/// 同一本账本即可拿到。
pub(all) struct UpdateFlow {
  state : @base.Store[UpdateState]
  mut found : @sys.UpdateManifest?
  mut carrier : String
}

///|
/// 建账本(初始 Idle)。
pub fn make_update_flow() -> UpdateFlow {
  { state: @base.Store::new(Idle), found: None, carrier: "" }
}

///|
/// 标记「检查中」并清上一轮结果(视图的「检查更新/重新检查」钮先调它,
/// 再触发 `actions.check`)。
pub fn UpdateFlow::begin_check(self : UpdateFlow) -> Unit {
  self.found = None
  self.carrier = ""
  self.state.set_always(Checking)
}

///|
/// 检查结果:`Ok(None)` 已是最新;`Ok(Some(m))` 有新版(记下清单);`Err` 失败
/// (可重检查)。
pub fn UpdateFlow::report_check(
  self : UpdateFlow,
  r : Result[@sys.UpdateManifest?, String],
) -> Unit {
  match r {
    Ok(None) => self.state.set_always(UpToDate)
    Ok(Some(m)) => {
      self.found = Some(m)
      self.state.set_always(Available(m.version, m.notes))
    }
    Err(e) => self.state.set_always(Failed(e, RetryCheck))
  }
}

///|
/// 标记「下载中」(「立即更新」钮先调它,再触发 `actions.download`)。
pub fn UpdateFlow::begin_download(self : UpdateFlow) -> Unit {
  self.state.set_always(Downloading)
}

///|
/// 下载结果:`Ok(p)` 载体路径(记下,安装动作用);`Err` 失败(可重下载)。
pub fn UpdateFlow::report_download(
  self : UpdateFlow,
  r : Result[String, String],
) -> Unit {
  match r {
    Ok(p) => {
      self.carrier = p
      self.state.set_always(Ready)
    }
    Err(e) => self.state.set_always(Failed(e, RetryDownload))
  }
}

///|
/// 标记「安装中」(「重启并安装」钮先调它,再触发 `actions.install`;
/// 成功路径是 relaunch + 退出,态停在 Installing 即终态)。
pub fn UpdateFlow::begin_install(self : UpdateFlow) -> Unit {
  self.state.set_always(Installing)
}

///|
/// 安装结果:失败回 `Failed`(不给重试钮——替换失败多半要人工看残留);
/// 成功不走这里(进程已重启)。
pub fn UpdateFlow::report_install(
  self : UpdateFlow,
  r : Result[Unit, String],
) -> Unit {
  match r {
    Ok(_) => ()
    Err(e) => self.state.set_always(Failed(e, RetryNone))
  }
}

///|
/// 回初始(重开框从头走;不调则重开时保留上一轮结果)。
pub fn UpdateFlow::reset(self : UpdateFlow) -> Unit {
  self.found = None
  self.carrier = ""
  self.state.set_always(Idle)
}

///|
/// 动作注入:三个闭包分别对应「检查 / 下载 / 安装」,由装配方实现(直连 sys
// 或包一层调度);闭包内完成后把结果喂回同一本账本的 `report_*` 口。
pub(all) struct UpdateActions {
  check : () -> Unit
  download : () -> Unit
  install : () -> Unit
}

///|
/// 不定态指示(旋转弧):相位 Store + 自重排延时表驱动;状态区每次重建都换新
/// 弧,旧表的停表闭包随本代回收袋退订,不累积。
fn update_spinner(size : Double) -> @widget.Node {
  let phase : @base.Store[Double] = @base.Store::new(0.0)
  let tid : Ref[Int] = Ref(0)
  let tick : Ref[() -> Unit] = Ref(fn() { () })
  tick.val = fn() -> Unit {
    phase.update_always(fn(p) { p + 0.125 })
    tid.val = @shell.set_timeout(90, tick.val)
  }
  @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget {
    watch_theme()
    follow_store(phase)
    w.node.set_width(@yoga.fixed(size))
    w.node.set_height(@yoga.fixed(size))
    w.on_draw = Some(fn(
      _s : @widget.Widget,
      p : @render.Painter,
      r : @base.Rect,
    ) -> Unit {
      // 相位 0..1 → 起角,画 3/4 圈的弧(首尾留缺口才有「在转」的读数)
      let a = phase.get() - (phase.get() / 1.0).floor()
      let start = a * 2.0 * 3.14159265358979
      p.set_stroke_color(@theme.theme_primary())
      p.set_line_width(2.0)
      p.set_line_cap(@render.Round)
      p.begin_path()
      p.arc(
        r.w / 2.0,
        r.h / 2.0,
        ((size / 2.0) - 2.0).max(1.0),
        start,
        start + 4.71238898038469,
      )
      p.stroke()
    })
    // bind_node 的 build 在回收袋内跑,这里注册的停表闭包随本代整体退订
    (tick.val)()
    @base.sub_bag_register(fn() {
      if tid.val != 0 {
        @shell.clear_timeout(tid.val)
      }
    })
    w
  })
}

///|
/// 状态区的「图标 + 文字」行(成功/失败两态的读数用)。
fn update_state_line(
  icon : @icons.IconKind,
  color : String,
  main : String,
  sub : String,
  inner_w : Double,
) -> @widget.Node {
  view(
    [
      upd_icon(icon, 22.0, color),
      view(
        [
          text(main, wrap=true, max_width=inner_w - 34.0),
          text(sub, font_size=12.0, color="text_secondary", wrap=true, max_width=inner_w - 34.0),
        ],
        direction=@yoga.Column,
        row_gap=2.0,
      ),
    ],
    direction=@yoga.Row,
    column_gap=10.0,
    align_items=@yoga.AlignItems::Center,
  )
}

///|
/// `@icons.icon` 的本包直呼(省一层别名噪音)。
fn upd_icon(kind : @icons.IconKind, size : Double, color : String) -> @widget.Node {
  icon(kind, size=size, color=color)
}

///|
/// 单态视图:按 `st` 出内容 + 按钮行(主钮在左、与 message_box 的默认钮口径一致;
/// Installing/Downloading 无出口按钮)。`close` 收框,重试按 `UpdateRetry` 回
/// 对应动作。
fn update_state_view(
  st : UpdateState,
  flow : UpdateFlow,
  actions : UpdateActions,
  close : () -> Unit,
  current_version : String,
  inner_w : Double,
) -> @widget.Node {
  // 按钮行的公共骨架:主钮(Solid)在前、次钮(Border)在后
  fn buttons(primary : (String, () -> Unit), secondary : (String, () -> Unit)?) -> @widget.Node {
    let items : Array[@widget.Node] = [
      button(primary.0, variant=Solid, on_click=primary.1, focus_id=auto_focus_id(0))
    ]
    match secondary {
      Some((t, act)) => items.push(
        button(t, variant=Border, on_click=act, focus_id=auto_focus_id(0)),
      )
      None => ()
    }
    view(
      items,
      direction=@yoga.Row,
      column_gap=8.0,
      justify_content=@yoga.JustifyContent::FlexEnd,
    )
  }
  fn found_version() -> String {
    match flow.found {
      Some(m) => m.version
      None => ""
    }
  }
  let do_check = fn() {
    flow.begin_check()
    (actions.check)()
  }
  let do_download = fn() {
    flow.begin_download()
    (actions.download)()
  }
  let do_install = fn() {
    flow.begin_install()
    (actions.install)()
  }
  match st {
    Idle =>
      view(
        [
          text(
            @i18n.t_or("gui.ui.update.idle_hint", "检查是否有新版本,下载并安装。"),
            wrap=true,
            max_width=inner_w,
          ),
          buttons(
            (@i18n.t_or("gui.ui.update.check", "检查更新"), do_check),
            None,
          ),
        ],
        direction=@yoga.Column,
        row_gap=14.0,
      )
    Checking =>
      view(
        [
          view(
            [
              update_spinner(18.0),
              text(@i18n.t_or("gui.ui.update.checking", "正在检查更新…")),
            ],
            direction=@yoga.Row,
            column_gap=10.0,
            align_items=@yoga.AlignItems::Center,
          ),
        ],
        direction=@yoga.Column,
        row_gap=14.0,
      )
    UpToDate =>
      view(
        [
          update_state_line(
            @icons.CheckCircleFill,
            @theme.theme_success(),
            @i18n.t_or("gui.ui.update.uptodate", "已是最新版本"),
            if current_version.length() > 0 {
              @i18n.t_or("gui.ui.update.current", "当前版本:\{current_version}")
            } else {
              ""
            },
            inner_w,
          ),
          buttons(
            (@i18n.t_or("gui.ui.update.recheck", "重新检查"), do_check),
            Some((@i18n.t_or("gui.ui.update.close", "关闭"), close)),
          ),
        ],
        direction=@yoga.Column,
        row_gap=14.0,
      )
    Available(v, notes) =>
      view(
        [
          view(
            [
              upd_icon(@icons.CloudDownload, 22.0, @theme.theme_primary()),
              view(
                [
                  text(
                    @i18n.t_or("gui.ui.update.available", "发现新版本 \{v}"),
                    weight=@text.SemiBold,
                    wrap=true,
                    max_width=inner_w - 34.0,
                  ),
                  text(
                    notes,
                    font_size=12.0,
                    color="text_secondary",
                    wrap=true,
                    max_width=inner_w - 34.0,
                  ),
                ],
                direction=@yoga.Column,
                row_gap=2.0,
              ),
            ],
            direction=@yoga.Row,
            column_gap=10.0,
            align_items=@yoga.AlignItems::Center,
          ),
          buttons(
            (@i18n.t_or("gui.ui.update.install_now", "立即更新"), do_download),
            Some((@i18n.t_or("gui.ui.update.later", "暂不"), close)),
          ),
        ],
        direction=@yoga.Column,
        row_gap=14.0,
      )
    Downloading =>
      view(
        [
          view(
            [
              update_spinner(18.0),
              text(
                @i18n.t_or("gui.ui.update.downloading", "正在下载 \{found_version()}…"),
              ),
            ],
            direction=@yoga.Row,
            column_gap=10.0,
            align_items=@yoga.AlignItems::Center,
          ),
        ],
        direction=@yoga.Column,
        row_gap=14.0,
      )
    Ready =>
      view(
        [
          update_state_line(
            @icons.CheckCircleFill,
            @theme.theme_success(),
            @i18n.t_or("gui.ui.update.ready", "新版本已下载完成"),
            @i18n.t_or("gui.ui.update.ready_sub", "重启应用完成安装。"),
            inner_w,
          ),
          buttons(
            (@i18n.t_or("gui.ui.update.restart", "重启并安装"), do_install),
            Some((@i18n.t_or("gui.ui.update.later2", "稍后"), close)),
          ),
        ],
        direction=@yoga.Column,
        row_gap=14.0,
      )
    Installing =>
      view(
        [
          view(
            [
              update_spinner(18.0),
              text(@i18n.t_or("gui.ui.update.installing", "正在安装,应用即将重启…")),
            ],
            direction=@yoga.Row,
            column_gap=10.0,
            align_items=@yoga.AlignItems::Center,
          ),
        ],
        direction=@yoga.Column,
        row_gap=14.0,
      )
    Failed(msg, retry) => {
      let secondary : (String, () -> Unit)? = Some(
        (@i18n.t_or("gui.ui.update.close", "关闭"), close),
      )
      // 无可重试步时只剩一个「关闭」钮(不重复摆两个)
      let btns = match retry {
        RetryCheck =>
          buttons(
            (@i18n.t_or("gui.ui.update.retry", "重试"), do_check),
            secondary,
          )
        RetryDownload =>
          buttons(
            (@i18n.t_or("gui.ui.update.retry", "重试"), do_download),
            secondary,
          )
        RetryNone => buttons((@i18n.t_or("gui.ui.update.close", "关闭"), close), None)
      }
      view(
        [
          update_state_line(
            @icons.CloseCircleFill,
            @theme.theme_danger(),
            @i18n.t_or("gui.ui.update.failed", "更新失败"),
            msg,
            inner_w,
          ),
          btns,
        ],
        direction=@yoga.Column,
        row_gap=14.0,
      )
    }
  }
}

///|
/// 应用更新对话框:`visible` 驱动弹/收(与 `dialog` 同口径),内容按 `flow.state`
/// 重建。面板 = 标题 + 当前版本副行 + 状态区;遮罩吃点击(不穿透、点外不收,
/// Installing 态没有出口是刻意的——替换进行到一半关框没有意义)。
pub fn update_dialog(
  visible : @base.Store[Bool],
  flow : UpdateFlow,
  actions : UpdateActions,
  current_version? : String = "",
  title? : String = @i18n.t_or("gui.ui.update.title", "软件更新"),
  width? : Double = 400.0,
  class? : Array[@style.Style] = [],
  handle? : (@widget.Widget) -> Unit = default_handle,
) -> @widget.Node {
  {
    mount: fn(parent : @widget.Widget) -> @widget.Widget {
      let anchor = @widget.Widget::new()
      anchor.node.set_height(@yoga.fixed(0.0))
      let open_id : Ref[Int] = Ref(0)
      let close = fn() -> Unit { visible.set(false) }
      let inner_w = width - 40.0
      fn open() -> Unit {
        if open_id.val != 0 {
          return
        }
        // 面板:标题 + 当前版本副行 + 状态区(按账本现值建,变化原位重建)
        let panel = view(
          [
            view(
              [
                text(title, font_size=16.0, weight=@text.SemiBold),
                text(
                  if current_version.length() > 0 {
                    @i18n.t_or("gui.ui.update.current", "当前版本:\{current_version}")
                  } else {
                    ""
                  },
                  font_size=12.0,
                  color="text_secondary",
                ),
              ],
              direction=@yoga.Column,
              row_gap=2.0,
            ),
            @widget.bind_node(
              flow.state.signal(),
              fn(st : UpdateState) -> @widget.Node {
                update_state_view(st, flow, actions, close, current_version, inner_w)
              },
            ),
          ],
          direction=@yoga.Column,
          row_gap=16.0,
          padding=20.0,
          width=width,
          background_color="bg_panel",
          border_color="border",
          corner_radius=@theme.radius_card(),
          class=class,
        )
        let scrim = @widget.node_of_new(fn(s : @widget.Widget) -> @widget.Widget {
          watch_theme()
          s.node.set_width(@yoga.percent(100.0))
          s.node.set_height(@yoga.percent(100.0))
          s.node.set_justify_content(@yoga.JustifyContent::Center)
          s.node.set_align_items(@yoga.AlignItems::Center)
          // 遮罩只吃点击不收框(收框走按钮;Installing 无出口)
          s.on_pointer = Some(fn(
            _self : @widget.Widget,
            ev : @widget.PointerEvent,
          ) -> Bool {
            match ev.kind {
              @widget.PointerKind::Down | @widget.PointerKind::Up => true
              _ => false
            }
          })
          s.on_draw = Some(fn(
            _s : @widget.Widget,
            p : @render.Painter,
            r : @base.Rect,
          ) -> Unit {
            p.set_fill_color("#000000")
            p.set_global_alpha(0.5)
            p.fill_rect(0.0, 0.0, r.w, r.h)
            p.set_global_alpha(1.0)
          })
          let _ = panel.mount_into(s)
          s
        })
        open_id.val = @widget.overlay_show_full(scrim)
      }
      fn teardown() -> Unit {
        if open_id.val != 0 {
          @widget.overlay_hide(open_id.val)
          open_id.val = 0
        }
      }
      let sig = visible.signal()
      let sid = sig.subscribe(fn(v : Bool) -> Unit {
        if v {
          open()
        } else {
          teardown()
        }
      })
      @base.sub_bag_register(fn() { sig.remove(sid) })
      if visible.get() {
        open()
      }
      parent.append_child(anchor)
      fold_style(anchor, @style.empty_style(), @style.empty_style(), class)
      handle(anchor)
      anchor
    },
  }
}

///|
/// 默认下载落盘目录:系统临时目录(win 认 TEMP,POSIX 认 TMPDIR,都有回退)。
fn update_tmp_dir() -> String {
  fn env_or(name : String, fallback : String) -> String {
    match @sys.sys_getenv(name) {
      Some(d) => if d.length() > 0 { d } else { fallback }
      None => fallback
    }
  }
  match @sys.sys_platform() {
    "windows" => env_or("TEMP", "C:\\Windows\\Temp")
    _ => env_or("TMPDIR", "/tmp")
  }
}

///|
/// sys 直连装配:三个动作闭包直接调 `@sys.update_*`(真更新链路的最短接法)。
///
/// 同步取舍:sys 走 `pr_run` 阻塞宿主线程,这里用 `set_timeout(0)` 把动作错一拍
/// ——点击回调先返回,「检查中/下载中」至少画得出来;但大文件下载期间界面停摆
/// 是 v1 已知代价(异步执行器随平台线程批,届时只换本函数,组件面不动)。
/// `quit` 在安装成功时调(relaunch 已发起,应用该立刻退,把现场让给新进程)。
/// `allow_http` 透传 `@sys.update_check`(本地更新服务测试链路用)。
pub fn sys_update_actions(
  flow : UpdateFlow,
  manifest_url : String,
  current_version : String,
  quit : () -> Unit,
  allow_http? : Bool = false,
) -> UpdateActions {
  {
    check: fn() {
      let _ = @shell.set_timeout(0, fn() {
        flow.report_check(
          @sys.update_check(manifest_url, current_version, allow_http~),
        )
      })
    },
    download: fn() {
      let _ = @shell.set_timeout(0, fn() {
        match flow.found {
          Some(m) =>
            match @sys.update_manifest_asset(m, @sys.update_target_id()) {
              Some(a) => flow.report_download(
                @sys.update_download(a, update_tmp_dir()),
              )
              None => flow.report_download(Err("清单没有本平台的更新载体"))
            }
          None => flow.report_download(Err("没有可下载的更新信息"))
        }
      })
    },
    install: fn() {
      let _ = @shell.set_timeout(0, fn() {
        match @sys.update_apply_carrier(flow.carrier) {
          Ok(_) => {
            let _ = @sys.update_relaunch()
            quit()
          }
          Err(e) => flow.report_install(Err(e))
        }
      })
    },
  }
}
