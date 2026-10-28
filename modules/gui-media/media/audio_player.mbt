// 音频播放组件：引擎是 `AudioPlayer`（ffmpeg 解码 + miniaudio 设备直出），
// 控制条与 `video` 共用同一套分区常量，差别只在没有画面。
//
// 三条口径：
// ① 纯音频专用——带视频轨的文件走 `video`，两者不互相代打：本组件的位置
//    读数是设备已消费字节，`video` 的是墙钟 + 帧时间戳，塞进同一个组件
//    等于让两条时钟互相冒充；
// ② 时钟在引擎里，UI 每 tick 调一次 `pump` 推进队列并重绘，排期走
//    `@shell.set_timeout`，组件不起线程；
// ③ seek 防抖同 `video`：拖动期间只挪显示位置，抬手才真 seek；音量相反，
//    每步都生效（它不触发解码，没有关键帧代价）。

///|
/// 快退/快进落点：当前位置加偏移，钳在 `[0, 时长]`；时长未知（容器无时长头）
/// 时只钳下界，否则 `vp_clamp_t` 会把未知时长的落点打回 0。
pub fn ap_skip(cur : Double, duration_s : Double, delta : Double) -> Double {
  let t = cur + delta
  if duration_s <= 0.0 {
    if t < 0.0 { 0.0 } else { t }
  } else {
    vp_clamp_t(t, duration_s)
  }
}

///|
/// 快退/快进键的步长（秒）。
let ap_skip_step : Double = 5.0

///|
/// 频谱条的透明度：半透明融进面板底色，注意力让给歌词文字。
let ap_spectrum_alpha : Double = 0.4

///|
/// 音频播放控件。`width`/`height` 是整块控件尺寸（默认只有一条控制条高）；
/// 组件被外层撑高时，多出来的高度归上方舞台区（歌词写在这块底部，无输出设备
/// 的降级说明也写在这块，频谱动画落在这块）。`lyric` 传**已读好的 LRC 文本**
/// （外部文件的读取归调用方，本组件不碰使用者的磁盘路径）。打不开时不抛异常
/// ——画说明板并把原因经 `on_error` 交出去（探测 + 降级不静默）。
pub fn audio(
  path : String,
  lyric? : String = "",
  width? : Double = 560.0,
  height? : Double = 34.0,
  auto_play? : Bool = false,
  volume? : Double = 0.8,
  looping? : Bool = false,
  /// 舞台区画不画实时频谱条（关掉就是纯文字舞台，解码旁路也不再喂分析器）。
  spectrum? : Bool = true,
  /// 每 tick 的观测口（位置秒 / 是否在播）：示例与回证靠它证明时钟在走。
  on_tick? : (Double, Bool) -> Unit = fn(
    _t : Double,
    _playing : Bool,
  ) -> Unit { () },
  /// 倍速档位变化的观测口（控制条点倍速键时回调）。
  on_speed? : (Double) -> Unit = fn(_v : Double) -> Unit { () },
  /// 歌词来源的观测口（行数），打开时回调一次：调用方要区分「没配上歌词」与
  /// 「配上了但还没唱」，不必去猜引擎状态。
  on_lyric? : (Int) -> Unit = fn(_n : Int) -> Unit { () },
  on_error? : (String) -> Unit = fn(_s : String) -> Unit { () },
  handle? : (@widget.Widget) -> Unit = fn(_w : @widget.Widget) -> Unit { () },
) -> @widget.Node {
  let sp = Spectrum::make()
  let engine = match AudioPlayer::make(
    path,
    volume~,
    looping~,
    pcm_tap=fn(b : Bytes, ch : Int) -> Unit {
      if spectrum {
        sp.feed(b, ch)
      }
    },
  ) {
    Ok(p) => p
    Err(e) => {
      on_error(e)
      return media_error_board("打不开音频：" + e, width, height, handle)
    }
  }
  let lrc = lrc_parse(lyric)
  on_lyric(lrc.cues.length())
  let dragging : Ref[Bool] = Ref(false)
  let speed_i : Ref[Int] = Ref(0)
  // 按钮行是真控件，档位/态变了要重挂，所以读数走 Store（等值不重发）
  let playing : @base.Store[Bool] = @base.Store::new(false)
  let speed_st : @base.Store[Double] = @base.Store::new(1.0)
  let full_st : @base.Store[Bool] = @base.Store::new(false)
  let muted : @base.Store[Bool] = @base.Store::new(false)
  let looping_st : @base.Store[Bool] = @base.Store::new(looping)
  let last_vol : Ref[Double] = Ref(volume)
  // 全屏观感三件套：指针停画面上不活动约 2.5s 收条 + 藏指针，任何指针活动即恢复
  let bar_vis : @base.Store[Bool] = @base.Store::new(true)
  let cursor_hide : @base.Store[Bool] = @base.Store::new(false)
  let pointer_on_stage : Ref[Bool] = Ref(false)
  let idle : Ref[Int] = Ref(0)
  fn activity() -> Unit {
    idle.val = 0
    if !bar_vis.get() {
      bar_vis.set(true)
    }
    if cursor_hide.get() {
      cursor_hide.set(false)
    }
  }
  if auto_play {
    engine.play()
  }
  playing.set(engine.is_playing())
  fn toggle() -> Unit {
    if engine.is_playing() {
      engine.pause()
    } else {
      engine.play()
    }
    playing.set(engine.is_playing())
    @widget.invalidate()
  }
  fn skip_by(delta : Double) -> Unit {
    engine.seek(ap_skip(engine.current(), engine.duration(), delta))
    sp.reset()
    @widget.invalidate()
  }
  fn cycle_speed() -> Unit {
    speed_i.val = speed_i.val + 1
    let v = bar_speed_at(speed_i.val)
    engine.set_speed(v)
    speed_st.set(v)
    on_speed(v)
    @widget.invalidate()
  }
  fn toggle_full() -> Unit {
    let on = !full_st.get()
    if player_set_fullscreen(on) {
      full_st.set(on)
      if !on {
        activity()
      }
      @widget.invalidate()
    }
  }
  fn toggle_loop() -> Unit {
    let on = !looping_st.get()
    engine.set_looping(on)
    looping_st.set(on)
    @widget.invalidate()
  }
  fn toggle_mute() -> Unit {
    let (m, v, lv) = bar_mute_toggle(muted.get(), engine.get_volume(), last_vol.val)
    muted.set(m)
    engine.set_volume(v)
    last_vol.val = lv
    @widget.invalidate()
  }
  fn apply_vol(v : Double) -> Unit {
    let (m, eff, lv) = bar_vol_apply(muted.get(), v, last_vol.val)
    muted.set(m)
    engine.set_volume(eff)
    last_vol.val = lv
    @widget.invalidate()
  }
  fn bump_vol(d : Double) -> Unit {
    apply_vol(bar_clamp01(engine.get_volume() + d))
  }
  // 舞台区：撑高时占住多出来的高度，歌词写在底部，无输出设备的降级说明写在中间。
  let stage = @widget.Widget::new()
  stage.node.set_flex_grow(1.0)
  stage.node.set_min_height(@yoga.fixed(0.0))
  stage.on_draw = Some(fn(
    _w : @widget.Widget,
    p : @render.Painter,
    r : @base.Rect,
  ) -> Unit {
    if r.h <= 0.0 {
      return
    }
    p.set_fill_color(@theme.theme_bg_panel())
    p.fill_rect(0.0, 0.0, r.w, r.h)
    // 频谱条：底部对齐、等宽槽位，电平来自「回看队列深度」那一窗样本
    let line = lrc_at(lrc, engine.current())
    // 歌词独占底部条带（44px），柱子只画条带以上的区域，两者不叠在同一块抢注意力
    let strip = if line.length() > 0 { 44.0 } else { 0.0 }
    let bars_h = r.h - strip
    if spectrum && bars_h > 12.0 {
      let lv = sp.levels(engine.queued_frames(), engine.sample_rate())
      let n = lv.length()
      let slot = r.w / n.to_double()
      let bw = slot * 0.62
      p.set_global_alpha(ap_spectrum_alpha)
      p.set_fill_color(@theme.theme_primary())
      for b = 0; b < n; b = b + 1 {
        let h = lv[b] * (bars_h - 6.0)
        if h > 0.5 {
          p.fill_round_rect(
            b.to_double() * slot + (slot - bw) / 2.0,
            bars_h - h,
            bw,
            h,
            2.0,
          )
        }
      }
      p.set_global_alpha(1.0)
    }
    if line.length() > 0 {
      p.flush()
      let txt = line.replace(old="\n", new=" ")
      // 歌词加粗主题色，配系统黑体族；居中前按粗体量宽
      let font = @text.Font::new("", 15.0, weight=@text.Bold)
      let x = match @text.measure_font(txt, font) {
        Some(m) =>
          if m.width.to_double() < r.w - 16.0 {
            (r.w - m.width.to_double()) / 2.0
          } else {
            8.0
          }
        None => 8.0
      }
      let _ = @text.draw_at(p, x, r.h - 26.0, txt, font, @theme.theme_primary())
    }
    if engine.is_muted() {
      p.flush()
      let _ = @text.draw_text_at(
        p,
        8.0,
        (r.h - 13.0) / 2.0,
        "没有可用输出设备：按静音推进，状态机照常走",
        13.0,
        @theme.theme_text_secondary(),
      )
    }
  })
  stage.on_pointer = Some(fn(
    _w : @widget.Widget,
    ev : @widget.PointerEvent,
  ) -> Bool {
    match ev.kind {
      @widget.PointerKind::Leave => pointer_on_stage.val = false
      _ => {
        pointer_on_stage.val = true
        activity()
      }
    }
    false
  })
  stage.on_double_click = Some(fn(
    _w : @widget.Widget,
    _ev : @widget.PointerEvent,
  ) -> Unit {
    toggle_full()
  })
  stage.cursor_fn = Some(fn(_w : @widget.Widget) -> Int {
    if cursor_hide.get() {
      @widget.CURSOR_HIDDEN
    } else {
      @widget.CURSOR_DEFAULT
    }
  })
  let display = player_display(
    fn() -> Double { engine.current() },
    fn() -> Double { engine.duration() },
    fn() -> Double { engine.get_volume() },
    fn(v : Double) -> Unit { apply_vol(v) },
    fn(t : Double) -> Unit {
      engine.seek(t)
      sp.reset()
      @widget.invalidate()
    },
    dragging,
  )
  let root = @widget.Widget::new()
  root.node.set_flex_direction(@yoga.Column)
  root.node.set_width(@yoga.fixed(width))
  root.node.set_height(@yoga.fixed(height))
  root.append_child(stage)
  let _ = @widget.bind_node(bar_vis.signal(), fn(show : Bool) -> @widget.Node {
    if show {
      player_bar(
        playing,
        speed_st,
        full_st,
        muted,
        looping_st,
        None,
        @icons.DArrowLeft,
        @icons.DArrowRight,
        toggle,
        fn() -> Unit { skip_by(0.0 - ap_skip_step) },
        fn() -> Unit { skip_by(ap_skip_step) },
        cycle_speed,
        toggle_mute,
        toggle_loop,
        toggle_full,
        fn() -> Unit { () },
        display,
      )
    } else {
      @widget.node_of_new(fn(w : @widget.Widget) -> @widget.Widget {
        w.node.set_height(@yoga.fixed(0.0))
        w
      })
    }
  }).mount_into(root)
  player_bind_keys(
    root,
    toggle,
    fn() -> Unit { skip_by(0.0 - ap_skip_step) },
    fn() -> Unit { skip_by(ap_skip_step) },
    toggle_full,
    bump_vol,
    toggle_mute,
    toggle_loop,
    fn() -> Bool { full_st.get() },
  )
  // 丢弃即停摆：组件被换树摘下时外层拿不到闭包里的引擎，没人 free 的话
  // 定时器链继续解码喂设备——换载后旧音频继续播就是这么来的。on_discard
  // 里停引擎，tick 链看到 dead 直接终止（不排下一拍）。
  let dead : Ref[Bool] = Ref(false)
  root.on_discard = Some(fn(_w) {
    dead.val = true
    engine.free()
  })
  let tick : Ref[() -> Unit] = Ref(fn() { () })
  tick.val = fn() -> Unit {
    if dead.val {
      return
    }
    engine.pump()
    playing.set(engine.is_playing())
    on_tick(engine.current(), engine.is_playing())
    if engine.is_playing() || dragging.val {
      @widget.invalidate()
    }
    let (idle_n, collapse) = bar_idle_step(
      full_st.get(),
      pointer_on_stage.val,
      idle.val,
    )
    idle.val = idle_n
    if collapse {
      bar_vis.set(false)
      cursor_hide.set(true)
    }
    let _ = @shell.set_timeout(ap_tick_ms, tick.val)
  }
  let _ = @shell.set_timeout(ap_tick_ms, tick.val)
  handle(root)
  @widget.node_of(root)
}
