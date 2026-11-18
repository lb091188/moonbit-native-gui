// 关键帧动画：多段属性时间轴，循环形态三档。插值复用 transition 的
// lerp_style（同一插值集合：颜色/边框/圆角/字号/行高/transform 族/背景模糊），
// 帧驱动复用 transition 的节拍形态（16ms 一拍标脏，全停停表）。
// 消费点在 style_for 尾部：时间轴进行中把 shown 值盖到状态桶样式上——
// 没写的时间轴字段回落基块。布局字段（宽高/边距）不在插值集合，时间轴
// 不触发重排，动尺寸请走绘制期字段（transform scale）或改用绑定重挂。

///|
/// 一帧关键帧：时间点（相对时间轴起点的毫秒）+ 该时刻的属性值块。
pub(all) struct Keyframe {
  at_ms : Double
  style : Style
}

///|
/// 循环形态：单次（结束保留末帧，等价 fill:forwards）/ 循环 / 往返。
pub(all) enum KfLoop {
  Once
  Loop
  PingPong
}

///|
priv struct Timeline {
  frames : Array[Keyframe]
  dur : Double
  mode : KfLoop
  start : Int64
  mut finished : Bool
}

///|
let timelines : Map[Int32, Timeline] = Map([])

///|
let kf_ticking : Ref[Bool] = Ref(false)

///|
let kf_tick_ms : Int32 = 16

///|
/// 启动（或替换）控件的关键帧时间轴。帧按 at_ms 升序整理；不足两帧或
/// 总时长为 0 视为无操作。同控件重复调用即换轴，时钟重起。
pub fn animate(
  w : @widget.Widget,
  frames : Array[Keyframe],
  mode~ : KfLoop = Once,
) -> Unit {
  install_drop_hook()
  // 升序整理（插入排序，帧数是个位数量级）
  let fs : Array[Keyframe] = []
  for f in frames {
    let mut i = fs.length()
    while i > 0 && fs[i - 1].at_ms > f.at_ms {
      i = i - 1
    }
    fs.insert(i, f)
  }
  if fs.length() < 2 {
    return
  }
  let dur = fs[fs.length() - 1].at_ms
  if dur <= 0.0 {
    return
  }
  timelines.set(w.id, { frames: fs, dur, mode, start: @shell.now_ms(), finished: false })
  // 轴涉及的 transform 字段置「样式管过」位：停轴/回落时槽刷新才把槽回恒等，
  // 否则槽卡在最后一帧的值上（样式基块没写这些字段、style_for 出 None 不回落）
  let mut mask = w.tr_style_mask
  for f in fs {
    match f.style.translate_x {
      Some(_) => mask = mask | 1
      None => ()
    }
    match f.style.translate_y {
      Some(_) => mask = mask | 2
      None => ()
    }
    match f.style.scale_x {
      Some(_) => mask = mask | 4
      None => ()
    }
    match f.style.scale_y {
      Some(_) => mask = mask | 8
      None => ()
    }
    match f.style.rotate {
      Some(_) => mask = mask | 16
      None => ()
    }
    match f.style.backdrop_blur {
      Some(_) => mask = mask | 32
      None => ()
    }
  }
  w.tr_style_mask = mask
  @widget.invalidate_id(w.id)
  ensure_kf_ticking()
}

///|
/// 停止并清轴：样式回落基块（下一次 style_for 起不再覆盖）。
pub fn stop_animating(w : @widget.Widget) -> Unit {
  if timelines.contains(w.id) {
    let _ = timelines.remove(w.id)
    @widget.invalidate_id(w.id)
  }
}

///|
/// 这条控件的关键帧时间轴进行中吗（Once 落定后为 false，但末帧仍在盖）。
pub fn kf_running(id : Int32) -> Bool {
  match timelines.get(id) {
    Some(t) => !t.finished
    None => false
  }
}

///|
/// 给定时刻的显示值块（纯计算；now 由调用方给，测试可喂假时钟）。
fn kf_progress(tl : Timeline, now : Int64) -> Style {
  let fs = tl.frames
  let last = fs.length() - 1
  let mut e = (now - tl.start).to_double()
  if e < 0.0 {
    e = 0.0
  }
  match tl.mode {
    Once => if e > tl.dur {
      e = tl.dur
    }
    Loop => e = e % tl.dur
    PingPong => {
      let c = e % (tl.dur * 2.0)
      e = if c <= tl.dur { c } else { tl.dur * 2.0 - c }
    }
  }
  if e <= fs[0].at_ms {
    return fs[0].style
  }
  if e >= fs[last].at_ms {
    return fs[last].style
  }
  for i = 0; i < last; i = i + 1 {
    if e >= fs[i].at_ms && e <= fs[i + 1].at_ms {
      let span = fs[i + 1].at_ms - fs[i].at_ms
      let t = if span <= 0.0 { 1.0 } else { (e - fs[i].at_ms) / span }
      return lerp_style(fs[i].style, fs[i + 1].style, ease(t))
    }
  }
  fs[last].style
}

///|
/// style_for 尾部的消费口：时间轴在场就给 shown（Once 已落定给末帧），
/// 不在场给 None（回落基块）。
fn kf_step(id : Int32, now : Int64) -> Style? {
  match timelines.get(id) {
    Some(tl) => {
      if tl.mode is Once && !tl.finished {
        let e = (now - tl.start).to_double()
        if e >= tl.dur {
          tl.finished = true
        }
      }
      Some(kf_progress(tl, now))
    }
    None => None
  }
}

///|
/// 一拍：进行中的轴各自标脏（动到字号/行高走整窗——测量会变，矩形会长大）。
/// Once 全落定、无 Loop/PingPong 在跑就停表。
fn kf_tick() -> Unit {
  let now = @shell.now_ms()
  let mut live = 0
  for id, tl in timelines {
    if tl.finished {
      continue
    }
    let shown = kf_progress(tl, now)
    if shown.font_size is Some(_) || shown.line_height is Some(_) {
      @widget.invalidate()
    } else {
      @widget.invalidate_id(id)
    }
    if tl.mode is Once && (now - tl.start).to_double() >= tl.dur {
      tl.finished = true
    } else {
      live += 1
    }
  }
  if live > 0 {
    let _ = @shell.set_timeout(kf_tick_ms, kf_tick)
  } else {
    kf_ticking.val = false
  }
}

///|
/// 起表（幂等），形态同 transition。
fn ensure_kf_ticking() -> Unit {
  if !kf_ticking.val {
    kf_ticking.val = true
    let _ = @shell.set_timeout(kf_tick_ms, kf_tick)
  }
}
