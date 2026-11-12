// 浮层的原生档：所在窗里有已挂载的原生子件（网页区）时，浮层必须
// 换成**真窗口**——自绘像素永远画在原生子件之下，图层再高也盖不住网页（§4.5）。
//
// 三条机制：
// ① **档位判定**只看一件事：本窗有没有挂着的子件（`Window::has_child_surfaces()`）。
//    没有网页就不必多开一扇窗，继续走 `overlay.mbt` 的图层；
// ② **先开框、量完再收**：弹层大小要的是内容的实际尺寸，而尺寸要挂载并布局一次
//    才知道，所以开一个临时框、挂内容、首帧后按实测矩形 `set_size_pixels` 收到
//    贴合大小（最多三次，避免布局回环）；
// ③ **点外收起靠 owner 侧手势**：菜单/下拉类弹层不激活（键盘归 owner 触发件），
//    弹层窗从来收不到失焦，所以「用户点了别处」由 owner 窗的按下事件判定——
//    本 owner 的收起型弹层开着时，owner 上任何按下都视为点外：收起最上层，且
//    **本次手势整段吞掉**（Down/Up 都不再派发给 owner 内容）——不吞的话，点触发
//    按钮会「收起又重开闪一下」（真机症状）。对话框（want_focus）仍走失焦收起。
// ④ **Esc 收起**：菜单类弹层不抢焦点后，Esc 走 owner 触发件的按键处理（dropdown
//    等组件自己的 on_key）；这里保留弹层窗的按键兜底通道给拿焦点的对话框用，
//    收起经 0ms 延时挪出按键派发现场再关窗。

///|
/// 已开的原生档浮层：句柄 → 弹层宿主窗。表在进程级，不进 `OverlayHost`
/// （宿主归 WindowHost，宿主再持它就是引用环）。
let g_native : Ref[Map[Int32, WindowHost]] = Ref(Map([]))

///|
let g_native_passes : Ref[Map[Int32, Int32]] = Ref(Map([]))

///|
/// 收起型（点外收起）标志：cid → 是否点外收起。对话框类 false。
let g_native_dismiss : Ref[Map[Int32, Bool]] = Ref(Map([]))

///|
/// 弹层所属 owner 宿主的 wid：cid → owner_wid（点外收判定按窗隔离）。
let g_native_owner : Ref[Map[Int32, Int32]] = Ref(Map([]))

///|
/// 本次指针手势已因「点外收起」被吞：Down 起、Up 终（Move 一并吞）。
let g_swallow_pointer : Ref[Bool] = Ref(false)

///|
/// 最近一次向窗口申请的尺寸（收框放大分支的地板）。窗口实读在 WM 慢拍时
/// 还停在初框值，拿它当地板会把已经收窄的申请反向钉回初框宽（KDE X11 真机
/// 弹层右侧恒留一条 320−内容宽的死边，即此成因）。
let g_native_req : Ref[Map[Int32, (Int32, Int32)]] = Ref(Map([]))

///|
/// 该不该走原生档：当前窗有已挂载的原生子件就走。无宿主/无窗一律走图层。
pub fn overlay_native_tier() -> Bool {
  match host_active() {
    Some(a) => a.window().has_child_surfaces()
    None => false
  }
}

///|
/// 弹层探针（真机诊断用，默认关）：开着时把每层的开框请求/初框尺寸与逐拍
/// 收框读数（实测内容 vs 当前窗）交给探针口——用来分辨「弹层被压住」与
/// 「收框收坏」。默认口是 stdout；`moon run` 下子进程 stdout 可能被缓冲看不到，
/// 调用方可换 `overlay_native_probe_to` 把读数接进自己的界面。
let g_native_probe : Ref[(String) -> Unit] = Ref(fn(_s : String) { () })

///|
let g_native_probe_on : Ref[Bool] = Ref(false)

///|
pub fn overlay_native_probe(on : Bool) -> Unit {
  g_native_probe_on.val = on
  g_native_probe.val = if on {
    fn(s : String) { println(s) }
  } else {
    fn(_s : String) { () }
  }
}

///|
/// 探针读数改走自定义出口（开着才有人构串调它）。
pub fn overlay_native_probe_to(sink : (String) -> Unit) -> Unit {
  g_native_probe_on.val = true
  g_native_probe.val = sink
}

///|
/// 开一扇弹层窗装 `content`。返回 false = 开不出来（调用方退回图层档）。
/// `want_focus`：菜单/下拉类 false（不激活，键盘归 owner 触发件；点外收起走
/// `overlay_pointer_prelude`）；对话框类 true。`dismiss` 记点外收起标志。
fn overlay_native_open(
  cid : Int32,
  content : Node,
  x : Double,
  y : Double,
  w : Double,
  h : Double,
  want_focus : Bool,
  dismiss : Bool,
) -> Bool {
  match host_active() {
    None => false
    Some(a) => {
      let iw = if w < 80.0 { 320 } else { w.round().to_int() }
      let ih = if h < 40.0 { 200 } else { h.round().to_int() }
      if g_native_probe_on.val {
        let o = a.session.window.origin()
        (g_native_probe.val)(
          "POPUP-OPEN cid=\{cid} req=(\{x.round().to_int()},\{y.round().to_int()}) init=(\{iw},\{ih}) owner=(\{o.0},\{o.1}) pos=(\{o.0 + x.round().to_int()},\{o.1 + y.round().to_int()})",
        )
      }
      match
        a.open_popup(
          x.round().to_int(),
          y.round().to_int(),
          iw,
          ih,
          want_focus~,
        ) {
        None => false
        Some(pop) => {
          pop.mount([content])
          // mount 完显式请一帧：开窗时内容还没挂上，首帧画的是空框；不补这
          // 一下，弹层重开要等鼠标移动才出内容（mac 真机症状）
          pop.session.window.request_redraw()
          g_native.val.set(cid, pop)
          g_native_passes.val.set(cid, 0)
          g_native_req.val.set(cid, (iw, ih))
          g_native_dismiss.val.set(cid, dismiss)
          g_native_owner.val.set(cid, a.session.wid)
          // Esc 收起：挂在弹层自己窗的按键兜底通道上，焦点链先问
          // 完才轮到它，菜单项等不吃 Esc 就落到这里。关窗挪到 0ms 延时里做，
          // 不在按键派发中途拆派发所在的窗。
          pop.add_key_fallthrough(fn(ev : KeyEvent) -> Bool {
            if ev.press && ev.keysym == @base.KS_ESCAPE {
              let _ = @shell.set_timeout(0, fn() -> Unit {
                let _ = overlay_native_close(cid)
                invalidate()
              })
              true
            } else {
              false
            }
          })
          true
        }
      }
    }
  }
}

///|
/// 收起一个原生档浮层（窗已自己关过时只清表）。返回是否命中原生档。
fn overlay_native_close(cid : Int32) -> Bool {
  match g_native.val.get(cid) {
    None => false
    Some(pop) => {
      let _ = g_native.val.remove(cid)
      let _ = g_native_passes.val.remove(cid)
      let _ = g_native_req.val.remove(cid)
      let _ = g_native_dismiss.val.remove(cid)
      let _ = g_native_owner.val.remove(cid)
      if !pop.closed {
        pop.close_window()
      }
      true
    }
  }
}

///|
/// 最新开的原生档浮层句柄（没有给 0）。
fn overlay_native_top() -> Int32 {
  let mut top = 0
  for cid, _ in g_native.val {
    top = if cid > top { cid } else { top }
  }
  top
}

///|
/// 原生档在开数（诊断与 `overlay_count` 用）。
pub fn overlay_native_count() -> Int32 {
  g_native.val.length()
}

///|
/// 指定句柄是不是还开着的原生档浮层：`overlay_alive` 必须认这一档——图层栈里
/// 没有原生层的条目，只查栈会让组件以为「没开着」而再叠一扇（Linux 真机
/// 弹层逐次累积、屏上留旧窗的成因之一）。
pub fn overlay_native_opened(id : Int32) -> Bool {
  match g_native.val.get(id) {
    Some(_) => true
    None => false
  }
}

///|
/// 量内容实际尺寸：弹层根控件的可见子项矩形并集（隐藏项矩形已被清零，天然排除）。
fn overlay_content_size(app : WindowHost) -> (Int32, Int32) {
  let mut w = 0.0
  let mut h = 0.0
  for k in app.root.children() {
    if k.visible && k.rect.w > w {
      w = k.rect.w
    }
    if k.visible && k.rect.y + k.rect.h > h {
      h = k.rect.y + k.rect.h
    }
  }
  (w.ceil().to_int(), h.ceil().to_int())
}

///|
/// 首帧后收框：宿主每拍调一次，同一浮层最多试三帧（布局可能因宽度变化再长高）。
/// 三帧用尽后仍放行**放大**——内容后来长宽了（例如顶部轻提示又推来一条更宽的），
/// 框子不跟着长就会把多出来的内容切掉；放大的地板是**最近一次申请的尺寸**
/// `g_native_req`，不是窗口实读（WM 慢拍时实读停在初框，会把窄申请反向顶回
/// 初框宽）；收缩仍受三帧限制，避免宽度回环里来回改尺寸。
pub fn overlay_fit_pass(app : WindowHost) -> Unit {
  let hits : Array[Int32] = []
  for cid, pop in g_native.val {
    if pop.session.wid == app.session.wid {
      hits.push(cid)
    }
  }
  for cid in hits {
    let passes = match g_native_passes.val.get(cid) {
      Some(n) => n
      None => 0
    }
    match g_native.val.get(cid) {
      None => ()
      Some(pop) => {
        let (cw, ch) = pop.session.window.size()
        // 量尺那一拍把「可用高度」与**根自身的固定高**一起解掉：paint_frame 每帧
        // 把根钉成当前窗尺寸，只传 None 可用高没用——根的 fixed 高就是天花板，
        // 弹性收缩仍把面板压成视口高，meas 恒等 cur（真机两轮复测：只解可用高
        // 不够，kids 仍是 [208x200]）。量完立刻钉回去，paint 每帧照常重设。
        pop.root.node.set_height(@yoga.undefined())
        @yoga.calculate_layout(pop.root.node, Some(cw.to_double()), None)
        pop.root.collect_abs(0.0, 0.0)
        pop.root.node.set_height(@yoga.fixed(ch.to_double()))
        let (w, h) = overlay_content_size(pop)
        if g_native_probe_on.val && (passes < 3 || w != cw || h != ch) {
          let (ox, oy) = pop.session.window.origin()
          let req_txt = match g_native_req.val.get(cid) {
            Some((rw, rh)) => "(\{rw},\{rh})"
            None => "-"
          }
          let kids : Array[String] = []
          for k in pop.root.children() {
            if kids.length() < 4 {
              let vis = if k.visible { "" } else { "(h)" }
              kids.push(
                "\{k.rect.w.round().to_int()}x\{k.rect.h.round().to_int()}\{vis}",
              )
            }
          }
          (g_native_probe.val)(
            "POPUP-FIT cid=\{cid} meas=(\{w},\{h}) cur=(\{cw},\{ch}) req=\{req_txt} at=(\{ox},\{oy}) passes=\{passes} kids=[\{kids.join(" ")}]",
          )
        }
        let (rw, rh) = match g_native_req.val.get(cid) {
          Some(r) => r
          None => (cw, ch)
        }
        if passes >= 3 {
          if w > rw || h > rh {
            let nw = w.max(rw)
            let nh = h.max(rh)
            g_native_req.val.set(cid, (nw, nh))
            pop.session.window.set_size_pixels(nw, nh)
          }
          continue
        }
        g_native_passes.val.set(cid, passes + 1)
        if w > 1 && h > 1 && (w != cw || h != ch) {
          g_native_req.val.set(cid, (w, h))
          pop.session.window.set_size_pixels(w, h)
        }
      }
    }
  }
}

///|
/// 「失焦即收起」的开关，**默认开**。判据是下面 `overlay_on_lost_focus` 里的
/// 「拿到过焦点才算」：真窗口早期实测的「弹层开出来约两秒自关」是映射期 focus-out
/// 误触发，没拿到过焦点的失焦现在被这条判据挡掉（对照实验见 adaptation.md）。
let g_dismiss_on_blur : Ref[Bool] = Ref(true)

///|
pub fn overlay_set_dismiss_on_blur(on : Bool) -> Unit {
  g_dismiss_on_blur.val = on
}

///|
pub fn overlay_dismiss_on_blur() -> Bool {
  g_dismiss_on_blur.val
}

///|
/// owner 窗指针事件的「原生弹层」前置判定。返回 true = 本次事件已被吞掉
/// （点外收起手势的一部分），宿主不要再派发给内容。
///
/// 语义：收起型（`g_native_dismiss`）原生浮层开着时，owner 上的任何按下都是
/// 「点外」——弹层是独立窗，落在弹层内的点不会到 owner。收起最上层并吞掉
/// 整段手势（Down/Up 都不再派发）：不吞的话，点触发按钮会先失焦/点外收起、
/// 紧接的 click 又把它打开（「关了再开闪一下」的真机成因）。
pub fn overlay_pointer_prelude(app : WindowHost, ev : PointerEvent) -> Bool {
  match ev.kind {
    Down => {
      g_swallow_pointer.val = false
      if g_native.val.length() == 0 {
        return false
      }
      // 只收本 owner 的开层：多窗口应用里点 A 窗不该收 B 窗的弹层
      let mut top = 0
      for cid, _ in g_native.val {
        let dismiss = match g_native_dismiss.val.get(cid) {
          Some(d) => d
          None => false
        }
        let owner = match g_native_owner.val.get(cid) {
          Some(w) => w
          None => -1
        }
        if dismiss && owner == app.session.wid && cid > top {
          top = cid
        }
      }
      if top == 0 {
        return false
      }
      let _ = overlay_native_close(top)
      g_swallow_pointer.val = true
      invalidate()
      true
    }
    Up =>
      if g_swallow_pointer.val {
        g_swallow_pointer.val = false
        true
      } else {
        false
      }
    Move => g_swallow_pointer.val
    Leave => false
  }
}

///|
/// 弹层窗失去键盘焦点 = 用户点了别处 → 收起最上面那层（图层档的「点外收起」
/// 靠命中，原生档的对话框靠这条）。开关见上。
pub fn overlay_on_lost_focus(app : WindowHost) -> Unit {
  if !g_dismiss_on_blur.val {
    return
  }
  // 武装判据：这扇弹层窗从没拿到过键盘焦点的失焦 = 映射期噪声，不收
  if !app.session.window.had_focus() {
    return
  }
  let mut top = 0
  for cid, pop in g_native.val {
    if pop.session.wid == app.session.wid {
      top = if cid > top { cid } else { top }
    }
  }
  if top != 0 {
    let _ = overlay_native_close(top)
    invalidate()
  }
}

///|
/// 拆掉所有原生档浮层（宿主退出时调，避免主窗退了而弹层还留在屏上）。
pub fn overlay_close_all_native() -> Unit {
  let ids : Array[Int32] = []
  for cid, _ in g_native.val {
    ids.push(cid)
  }
  for cid in ids {
    let _ = overlay_native_close(cid)
  }
}
