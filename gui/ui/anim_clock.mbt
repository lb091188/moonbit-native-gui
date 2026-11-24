// 中央动画登记表：组件动画不再各自起自续定时器链——登记表统一管生死。
//
// 动机（2026-11-22 真机归因）：构造期自续链不看可见性，预建缓存页的离树控件
// 每拍推进并置脏，invalidate_id 查不到 id 回退整窗重绘，演示板空闲即 21fps
// 全窗重绘风暴。本表把 terminal blink 的既有口径收拢为一处，组件想写错都
// 没有地方写。
//
// 三条口径：
//   - feed 即登记：组件在自己的 on_draw 里喂表，「这一帧画到了」既是登记
//     也是复活；构造期不排任何拍。
//   - 拍内只推进「本帧被画到」的登记项；本帧没画到的立即摘表——组件状态
//     在组件手里，回到视口由下一次 feed 重建，不留半截链。
//   - 表空即停：摘完没有任何登记项时不再排拍，主循环真睡到事件——空闲零
//     唤醒。
//
// 节奏保留各动画自己的间隔：拍链每拍只排到「最近的下一拍」为止，慢动画
// 不会抬高唤醒率，快动画也不被打折。
//
// 在飞拍的去重与自愈：`g_anim_wake` 记在飞拍的到期时刻。重复 feed 算出的
// 最早到期与在飞拍相同就不重排；在飞拍被丢弃（测试换钩子这类）时它的
// 时刻已成过去，下一次 feed 必然算出不同时刻、自然重排——不会卡死。

///|
priv struct AnimEntry {
  /// 登记项持控件引用：is_painted 与摘表都直接用它。摘表口径保证引用
  /// 不悬——控件一旦不画（被藏/离树/滚出视口），下一次拍就摘。
  w : @widget.Widget
  mut interval : Int32
  mut next_due : Int64
  mut tick : () -> Unit
}

///|
let g_anim_entries : Map[Int32, AnimEntry] = Map([])

///|
/// 在飞拍的到期时刻（-1 = 没有在飞拍）。
let g_anim_wake : Ref[Int64] = Ref(-1L)

///|
/// 蹭帧档的在飞标记：帧时钟已经在走时，本表不再另排定时器。
let g_anim_frame_armed : Ref[Bool] = Ref(false)

///|
/// 在飞拍排出时所处的定时器钩子代次。拍挂在钩子通道上，通道被整体换掉
/// （测试装自己的钩子队列是常态）排队拍就丢了——代次对不上即在飞标记
/// 不可信，重排自愈。
let g_anim_wake_gen : Ref[Int32] = Ref(-1)

///|
/// 喂表（在控件自己的 on_draw 里调）：确保登记存在并刷新拍间隔与推进闭包。
/// `interval_ms <= 0` 视为不动画，空操作。tick 闭包不自带重排——下一拍由
/// 本表统一排；要停就调 [anim_clock_drop]。
pub fn anim_clock_feed(
  w : @widget.Widget,
  tick : () -> Unit,
  interval_ms~ : Int32,
) -> Unit {
  if interval_ms <= 0 {
    return
  }
  let now = @shell.session_vtime_now()
  match g_anim_entries.get(w.id) {
    Some(e) => {
      e.tick = tick
      e.interval = interval_ms
    }
    None =>
      g_anim_entries.set(w.id, {
        w,
        interval: interval_ms,
        next_due: now + interval_ms.to_int64(),
        tick,
      })
  }
  anim_clock_reschedule(now)
}

///|
/// 摘除登记项：停表/暂停语义用。已在飞的一拍到点发现项没了就跳过；表空
/// 后拍链自然收口。
pub fn anim_clock_drop(id : Int32) -> Unit {
  let _ = g_anim_entries.remove(id)
}

///|
/// 当前登记项数（诊断用）。
pub fn anim_clock_count() -> Int32 {
  g_anim_entries.length()
}

///|
/// 按全表最早到期排下一拍；表空收口，与在飞拍同刻则不重排。
fn anim_clock_reschedule(now : Int64) -> Unit {
  // 顺手清账：当前绘制轮次没画到手的登记项摘表——离树/被藏的旧项不得
  // 占着最早到期卡住重排；回到视口由 on_draw 喂表重建。
  let cur = @widget.paint_epoch()
  let stale : Array[Int32] = []
  for _id, e in g_anim_entries {
    if e.w.paint_epoch != cur {
      stale.push(e.w.id)
    }
  }
  for id in stale {
    let _ = g_anim_entries.remove(id)
  }
  let mut next_wake = -1L
  for _id, e in g_anim_entries {
    if next_wake < 0L || e.next_due < next_wake {
      next_wake = e.next_due
    }
  }
  if next_wake < 0L {
    g_anim_wake.val = -1L
    return
  }
  if g_anim_wake.val == next_wake && g_anim_wake_gen.val == @shell.timer_hooks_generation() {
    return
  }
  // 本帧已经在走（滚动等场合）：蹭帧对齐，不再排定时器——帧本来就要发生，
  // 不额外抬唤醒率；空闲时照旧走自己的定时器（慢动画不抬高唤醒率的原口径）
  if @shell.frame_clock_ready() && @shell.frame_clock_pending() {
    g_anim_wake.val = next_wake
    g_anim_wake_gen.val = @shell.timer_hooks_generation()
    if !g_anim_frame_armed.val {
      g_anim_frame_armed.val = true
      @shell.frame_clock_request(fn(_now) {
        g_anim_frame_armed.val = false
        anim_clock_beat()
      })
    }
    return
  }
  let delay = (next_wake - now).to_int()
  g_anim_wake.val = next_wake
  g_anim_wake_gen.val = @shell.timer_hooks_generation()
  let _ = @shell.set_timeout(if delay < 0 { 0 } else { delay }, anim_clock_beat)
}

///|
/// 一拍：推进到期的在画项，摘掉不在画的项，再按剩表重排。
fn anim_clock_beat() -> Unit {
  g_anim_wake.val = -1L // 在飞拍此刻已被消费，末尾重排按「无在飞」判
  let now = @shell.session_vtime_now()
  // 快照遍历：tick 里可能 drop 自己或别人
  let snap : Array[AnimEntry] = []
  for _id, e in g_anim_entries {
    snap.push(e)
  }
  for e in snap {
    if g_anim_entries.get(e.w.id) is None {
      continue
    }
    if !e.w.is_painted() {
      // 本帧没画到（被藏/离树/滚出视口）：摘表——组件状态在自己手里，
      // 回到视口由 on_draw 喂表复活
      let _ = g_anim_entries.remove(e.w.id)
    } else if e.next_due <= now {
      (e.tick)()
      // tick 可能已摘掉自己（停表/暂停语义）
      match g_anim_entries.get(e.w.id) {
        Some(e2) => e2.next_due = now + e2.interval.to_int64()
        None => ()
      }
    }
  }
  anim_clock_reschedule(now)
}
