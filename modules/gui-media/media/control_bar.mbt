// 播放器控制条（`video` 与 `audio` 共用），参照成熟播放器的通行排法：
// 左组起播类真按钮（悬停浅底、Tab 可达、焦点环由 `ui` 画），右组收尾类——
// 进度轨 + 时间一块弹性自绘，随后静音键、音量条、全屏键依次排开
// （静音与音量成组、全屏贴最右）。
//
// 三条口径：
// ① 分区判据只有一份——绘制与命中都读 `BAR_*`，改一处不会漏另一处；显示区之外
//    的按键都是独立控件，不参与像素分区；
// ② 倍速与缩放用**文字按钮**显示当前档（图标说不清「1.25x」和「铺满」），
//    并按最宽档钉住按钮宽——切档只换字不挪邻位；
// ③ 进度抬手才 seek（真 seek 要回退到关键帧，每步都发就是一场风暴），音量每步
//    生效（它不触发解码，边拖边听才是预期）。

///|
/// 控制条高度与显示区分区常量。
const BAR_H : Double = 34.0
const BAR_VOL_W : Double = 80.0
const BAR_TIME_W : Double = 150.0
const BAR_GAP : Double = 8.0

///|
/// 文字档位键的钉宽（按最宽档 + 左右 12px 内边距取值）：倍速最宽「1.25x」、
/// 缩放最宽「适配」。窄档被 `min_width` 抬到同宽，档位切换按钮不横跳。
const BAR_SPEED_W : Double = 60.0
const BAR_ZOOM_W : Double = 52.0

///|
/// 全屏观感：多少拍（33ms/拍）无指针活动就收条 + 藏指针（约 2.5 秒）。
const BAR_IDLE_TICKS : Int = 75

///|
/// 全屏观感的计拍步进（纯函数，组件 tick 每拍调一次）：全屏且指针停在画面上
/// 才累计，到 `BAR_IDLE_TICKS` 拍给出「收条 + 藏指针」指令；其余状态一律归零。
/// 返回 (新计拍, 是否收起)。
pub fn bar_idle_step(
  fullscreen : Bool,
  pointer_on_stage : Bool,
  idle : Int,
) -> (Int, Bool) {
  if !(fullscreen && pointer_on_stage) {
    (0, false)
  } else {
    let n = idle + 1
    (n, n >= BAR_IDLE_TICKS)
  }
}

///|
/// 倍速档位（点一次走一档，转回 1x）。放在表里而不是就地加减，
/// 是为了让「浮点累加会不会漂出档位」这个问题不存在。
let bar_speeds : ReadOnlyArray[Double] = [1.0, 1.25, 1.5, 2.0, 0.75]

///|
/// 第 i 次点击对应的档位（i 可任意增长，含负数）。
pub fn bar_speed_at(i : Int) -> Double {
  let n = bar_speeds.length()
  let k = i % n
  bar_speeds[if k < 0 { k + n } else { k }]
}

///|
/// 倍速标签（档位表里给短写法，表外一律两位小数加 x）。
pub fn vp_fmt_speed(v : Double) -> String {
  if v == 1.0 {
    "1x"
  } else if v == 1.25 {
    "1.25x"
  } else if v == 1.5 {
    "1.5x"
  } else if v == 2.0 {
    "2x"
  } else if v == 0.75 {
    "0.75x"
  } else {
    v.to_string() + "x"
  }
}

///|
/// 缩放档位标签（0 等比适配 / 1 铺满裁切 / 2 原始像素）。
pub fn vp_zoom_label(mode : Int) -> String {
  match mode {
    1 => "铺满"
    2 => "1:1"
    _ => "适配"
  }
}

///|
/// 歌词行的纵向落位：与字幕同屏时歌词让到字幕上方，独占时贴底（与 audio
/// 舞台歌词同一 26px 底边距口径）。
pub fn vp_lyric_y(has_sub : Bool, h : Double) -> Double {
  if has_sub {
    h - 48.0
  } else {
    h - 26.0
  }
}

///|
/// 画面在控件矩形里的落位：适配取小边、铺满取大边（超出由控件裁剪）、
/// 1:1 用原始像素，三者都居中。尺寸非法给零矩形（不画）。
pub fn vp_fit_rect(
  vw : Double,
  vh : Double,
  rw : Double,
  rh : Double,
  mode : Int,
) -> (Double, Double, Double, Double) {
  if vw <= 0.0 || vh <= 0.0 || rw <= 0.0 || rh <= 0.0 {
    (0.0, 0.0, 0.0, 0.0)
  } else {
    let fit = rw / vw
    let fill = rh / vh
    let s =
      match mode {
        1 => if fit > fill { fit } else { fill }
        2 => 1.0
        _ => if fit < fill { fit } else { fill }
      }
    let dw = vw * s
    let dh = vh * s
    ((rw - dw) / 2.0, (rh - dh) / 2.0, dw, dh)
  }
}

///|
/// 进度轨宽度（时间文字左侧留一档 `BAR_GAP`；窄到 40px 以下就不再缩，
/// 否则拖动没有分辨率可言。音量条是右侧独立控件，窄时由布局压它让位）。
fn bar_track_w(w : Double) -> Double {
  let t = w - BAR_TIME_W - BAR_GAP
  if t < 40.0 { 40.0 } else { t }
}

fn bar_clamp01(f : Double) -> Double {
  if f < 0.0 { 0.0 } else if f > 1.0 { 1.0 } else { f }
}

///|
/// 静音开关的状态机（纯函数，组件层语义）：开静音 → 记住当前音量、有效音量
/// 归零；关静音 → 恢复记住的音量。返回 (新静音态, 新有效音量, 新记住值)。
pub fn bar_mute_toggle(
  muted : Bool,
  cur : Double,
  last : Double,
) -> (Bool, Double, Double) {
  if muted {
    (false, last, last)
  } else {
    (true, 0.0, cur)
  }
}

///|
/// 音量落点（拖动条与 `↑`/`↓` 键共用，纯函数）：落到非零即解除静音并刷新
/// 记住值；落 0 不动静音态与记住值（静音中拖 0 仍是静音，恢复值不丢）。
/// 返回值同 `bar_mute_toggle`。
pub fn bar_vol_apply(
  muted : Bool,
  v : Double,
  last : Double,
) -> (Bool, Double, Double) {
  if v > 0.0 {
    (false, v, v)
  } else {
    (muted, 0.0, last)
  }
}

///|
/// 进度区的命中分区：`x` 是进度区本地横坐标。返回 (分区名, 比例 0..1)，
/// 分区名是 `"seek"|""`（空串=右侧时间文字，不响应；音量条是右侧独立
/// 控件，命中就是自身宽内的比例，不在这条判据里）。纯函数，独立于绘制
/// 与事件投递，方便无头断言。
pub fn bar_hit(x : Double, w : Double) -> (String, Double) {
  if w <= 0.0 {
    ("", 0.0)
  } else if x > w - BAR_TIME_W {
    ("", 0.0)
  } else {
    ("seek", bar_clamp01(x / bar_track_w(w)))
  }
}

///|
/// 打不开媒体时的说明板（两个组件共用）：铺满底色、红字写原因，不抛异常
/// ——探测 + 降级不静默。
fn media_error_board(
  msg : String,
  width : Double,
  height : Double,
  handle : (@widget.Widget) -> Unit,
) -> @widget.Node {
  let w = @widget.Widget::new()
  w.set_size(width, height)
  w.on_draw = Some(fn(
    _w : @widget.Widget,
    p : @render.Painter,
    r : @base.Rect,
  ) -> Unit {
    p.set_fill_color(@theme.theme_bg_page())
    p.fill_rect(0.0, 0.0, r.w, r.h)
    p.flush()
    let _ = @text.draw_text_at(
      p,
      8.0,
      8.0,
      msg,
      13.0,
      @theme.theme_danger(),
    )
  })
  handle(w)
  @widget.node_of(w)
}

///|
/// 切当前窗全屏。控件层拿不到窗口，走进程级宿主单槽（`App::set_fullscreen`
/// 的门面注释同条口径）；没有宿主（无头测试）返回 false，调用方据此不动
/// 自己的档位状态。
fn player_set_fullscreen(on : Bool) -> Bool {
  match @widget.host_active() {
    Some(app) => {
      app.set_fullscreen(on)
      true
    }
    None => false
  }
}

///|
/// 进度区：进度轨 + 时间文字（弹性伸展，静音/音量在它右侧）。读数与动作都经
/// 闭包取，两个组件共用同一份绘制与命中判据。`dragging` 由调用方的时钟读
/// ——拖动期间即使暂停也要重绘，抬手才落 seek。
fn player_seek(
  pos : () -> Double,
  dur : () -> Double,
  seek_to : (Double) -> Unit,
  dragging : Ref[Bool],
) -> @widget.Widget {
  let w = @widget.Widget::new()
  w.node.set_flex_grow(1.0)
  w.node.set_height(@yoga.fixed(BAR_H))
  // 窄到只剩时间文字时轨道就点不着了，给个下限让布局去挤音量条而不是挤轨道
  w.node.set_min_width(@yoga.fixed(200.0))
  let drag_frac : Ref[Double] = Ref(0.0)
  let bar_w : Ref[Double] = Ref(0.0)
  w.on_draw = Some(fn(
    _w : @widget.Widget,
    p : @render.Painter,
    r : @base.Rect,
  ) -> Unit {
    bar_w.val = r.w
    p.set_fill_color(@theme.theme_bg_panel())
    p.fill_rect(0.0, 0.0, r.w, r.h)
    let duration = dur()
    let t = if dragging.val { drag_frac.val * duration } else { pos() }
    let frac = vp_pct(t, duration)
    p.set_fill_color(@theme.theme_border())
    p.fill_rect(0.0, 15.0, bar_track_w(r.w), 4.0)
    p.set_fill_color(@theme.theme_primary())
    p.fill_rect(0.0, 15.0, bar_track_w(r.w) * frac, 4.0)
    p.flush()
    let _ = @text.draw_text_at(
      p,
      r.w - BAR_TIME_W + 8.0,
      9.0,
      vp_fmt_time(t) + " / " + vp_fmt_time(duration),
      12.0,
      @theme.theme_text_secondary(),
    )
  })
  w.on_pointer = Some(fn(
    _w : @widget.Widget,
    ev : @widget.PointerEvent,
  ) -> Bool {
    match ev.kind {
      @widget.PointerKind::Down => {
        let hit = bar_hit(ev.x, bar_w.val)
        if hit.0 == "seek" {
          dragging.val = true
          drag_frac.val = hit.1
          @widget.invalidate()
        }
        true
      }
      @widget.PointerKind::Move => {
        if dragging.val {
          let hit = bar_hit(ev.x, bar_w.val)
          drag_frac.val = hit.1
          @widget.invalidate()
        }
        dragging.val
      }
      @widget.PointerKind::Up => {
        if dragging.val {
          dragging.val = false
          seek_to(drag_frac.val * dur())
          @widget.invalidate()
        }
        true
      }
      @widget.PointerKind::Leave => dragging.val
    }
  })
  w
}

///|
/// 音量条：贴在静音键右侧的固定宽自绘轨（宽时 80px；窄窗由布局压缩让它位，
/// 下限 40px 保拖动分辨率）。每步生效（音量不触发解码，边拖边听才是预期）。
fn player_volume(
  vol : () -> Double,
  set_vol : (Double) -> Unit,
) -> @widget.Widget {
  let w = @widget.Widget::new()
  w.node.set_width(@yoga.fixed(BAR_VOL_W))
  w.node.set_height(@yoga.fixed(BAR_H))
  w.node.set_min_width(@yoga.fixed(40.0))
  let vol_w : Ref[Double] = Ref(BAR_VOL_W)
  w.on_draw = Some(fn(
    _w : @widget.Widget,
    p : @render.Painter,
    r : @base.Rect,
  ) -> Unit {
    vol_w.val = r.w
    p.set_fill_color(@theme.theme_bg_panel())
    p.fill_rect(0.0, 0.0, r.w, r.h)
    p.set_fill_color(@theme.theme_border())
    p.fill_rect(0.0, 15.0, r.w, 4.0)
    p.set_fill_color(@theme.theme_text_secondary())
    p.fill_rect(0.0, 15.0, r.w * bar_clamp01(vol()), 4.0)
  })
  w.on_pointer = Some(fn(
    _w : @widget.Widget,
    ev : @widget.PointerEvent,
  ) -> Bool {
    match ev.kind {
      @widget.PointerKind::Down => {
        set_vol(bar_clamp01(ev.x / vol_w.val))
        @widget.invalidate()
        true
      }
      @widget.PointerKind::Move => {
        // 只在按住拖动时生效：悬停划过不改音量
        if _w.pressed {
          set_vol(bar_clamp01(ev.x / vol_w.val))
          @widget.invalidate()
        }
        _w.pressed
      }
      @widget.PointerKind::Up => true
      @widget.PointerKind::Leave => _w.pressed
    }
  })
  w
}

///|
/// 把播放器快捷键挂到当前窗的**按键兜底通道**上（`App::add_key_fallthrough`）：
/// 空格播放/暂停、回车全屏、`←`/`→` 后退/前进、`↑`/`↓` 音量、`M` 静音、
/// `L` 循环、`Esc` 退全屏。
/// 三条口径：① 不点窗口也能用，但焦点在输入框里时按键被编辑器吃掉，播放器
/// 不抢字；② 通道没有反注册口，所以每次按键先问 `watch`（本组件根控件）
/// 「还在被画吗」——换载摘掉的播放器不再吃键，同窗多台时注册序在前的先接；
/// ③ 没有宿主（无头测试）时什么都不挂。
fn player_bind_keys(
  watch : @widget.Widget,
  on_toggle : () -> Unit,
  on_back : () -> Unit,
  on_fwd : () -> Unit,
  on_full : () -> Unit,
  on_vol : (Double) -> Unit,
  on_mute : () -> Unit,
  on_loop : () -> Unit,
  is_full : () -> Bool,
) -> Unit {
  match @widget.host_active() {
    None => ()
    Some(app) => app.add_key_fallthrough(fn(
      ev : @widget.KeyEvent,
    ) -> Bool {
      if !watch.is_painted() {
        false
      } else if ev.keysym == @base.KS_SPACE {
        on_toggle()
        true
      } else if ev.keysym == @base.KS_RETURN {
        on_full()
        true
      } else if ev.keysym == @base.KS_LEFT {
        on_back()
        true
      } else if ev.keysym == @base.KS_RIGHT {
        on_fwd()
        true
      } else if ev.keysym == @base.KS_UP {
        on_vol(0.05)
        true
      } else if ev.keysym == @base.KS_DOWN {
        on_vol(0.0 - 0.05)
        true
      } else if ev.keysym == 0x6D {
        // 'm'（本栈 keysym 与 X11 同源：可打印字符 = 其 Latin-1 码位）
        on_mute()
        true
      } else if ev.keysym == 0x6C {
        // 'l'
        on_loop()
        true
      } else if ev.keysym == @base.KS_ESCAPE && is_full() {
        // 只在真处于全屏时接管：窗口态的 Esc 还有别的用途
        on_full()
        true
      } else {
        false
      }
    })
  }
}

///|
/// 整条控制条，排法照成熟播放器：左组「播放 → 跳转 → 循环 → 档位」，右组
/// 「进度+时间 → 静音 → 音量 → 全屏」——静音与音量成组、全屏收尾。
/// `zoom` 给 `None` 时不画缩放键（音频没有画面可缩）。
fn player_bar(
  playing : @base.Store[Bool],
  speed : @base.Store[Double],
  full : @base.Store[Bool],
  muted : @base.Store[Bool],
  looping : @base.Store[Bool],
  zoom : @base.Store[Int]?,
  back_icon : @icons.IconKind,
  fwd_icon : @icons.IconKind,
  on_toggle : () -> Unit,
  on_back : () -> Unit,
  on_fwd : () -> Unit,
  on_speed : () -> Unit,
  on_mute : () -> Unit,
  on_loop : () -> Unit,
  on_full : () -> Unit,
  on_zoom : () -> Unit,
  seek : @widget.Widget,
  volume : @widget.Widget,
) -> @widget.Node {
  let kids : Array[@widget.Node] = [
    @widget.bind_node(playing.signal(), fn(p : Bool) -> @widget.Node {
      @ui.icon_button(
        if p { @icons.VideoPause } else { @icons.VideoPlay },
        on_click=on_toggle,
        icon_size=16.0,
        box_size=28.0,
      )
    }),
    @ui.icon_button(
      back_icon,
      on_click=on_back,
      icon_size=16.0,
      box_size=28.0,
    ),
    @ui.icon_button(
      fwd_icon,
      on_click=on_fwd,
      icon_size=16.0,
      box_size=28.0,
    ),
    // 循环开关：图标恒 `Sync`，开着用主题色点亮（无独立关态字形）
    @widget.bind_node(looping.signal(), fn(l : Bool) -> @widget.Node {
      @ui.icon_button(
        @icons.Sync,
        on_click=on_loop,
        icon_size=16.0,
        box_size=28.0,
        color=if l { "primary" } else { "" },
      )
    }),
    @widget.bind_node(speed.signal(), fn(v : Double) -> @widget.Node {
      @ui.button(
        vp_fmt_speed(v),
        on_click=on_speed,
        variant=@ui.Text,
        font_size=12.0,
        min_width=BAR_SPEED_W,
      )
    }),
  ]
  match zoom {
    Some(z) => kids.push(
      @widget.bind_node(z.signal(), fn(m : Int) -> @widget.Node {
        @ui.button(
          vp_zoom_label(m),
          on_click=on_zoom,
          variant=@ui.Text,
          font_size=12.0,
          min_width=BAR_ZOOM_W,
        )
      }),
    )
    None => ()
  }
  kids.push(@widget.node_of(seek))
  // 静音与音量成组（成熟播放器通行排法）：静音键贴音量条左沿
  kids.push(@widget.bind_node(muted.signal(), fn(m : Bool) -> @widget.Node {
    @ui.icon_button(
      if m { @icons.Hide } else { @icons.Sound },
      on_click=on_mute,
      icon_size=16.0,
      box_size=28.0,
    )
  }))
  kids.push(@widget.node_of(volume))
  kids.push(@widget.bind_node(full.signal(), fn(f : Bool) -> @widget.Node {
    @ui.icon_button(
      if f { @icons.FullscreenExit } else { @icons.Fullscreen },
      on_click=on_full,
      icon_size=16.0,
      box_size=28.0,
    )
  }))
  @ui.row(
    kids,
    column_gap=2.0,
    height=BAR_H,
    padding=2.0,
    background_color="bg_panel",
    align_items=@yoga.AlignItems::Center,
  )
}
