// 无头测试门面（headless-tester P1，方案 §4）：建树 → 按 name 定位 →
// 注入指针/键盘/滚轮 → 无条件重画一帧 → 读矩形/文本/像素。
// 三条硬口径：
// - `frame()` 无条件重算布局+重画（不碰 `set_repaint_hook` 进程级单例），
//   多 Tester 并行安全；
// - click 恒 Down+Up 成对，坐标取矩形中心（窗口口径经 dispatch 换算本地）；
// - 能力缺失用 `guard_text` / `guard_decode` 显式计数（打印 skip 行），
//   依赖缺失的用例名约定带 `[需文本]` / `[需解码]` 前缀；跳过率不设门禁阈值
//   （runner 机器的字体/后端与本机构成不同，阈值只会间歇红），只有一条硬判据
//   `Tester::finish()`：一次观察点都没跑即红。
//
// **虚窗 ≠ 真窗**（`test_headless` 建的宿主语义边界，写进契约）：
// - 窗口句柄是 `< 0` 的哨兵，平台桩对越界 id 全部早退——没有真实的窗口映射、
//   不会出现在任务栏/活动窗口列表，`native_handle()` / 标题 / 尺寸 / 无边框
//   这类窗口级 API 在此只走内存态；
// - 没有真实输入设备：键盘/指针由 `key` / `click` / `drag` 注入，**输入法组合串
//   （IME）、系统级快捷键、焦点跟随真实鼠标**都不在这条路上；
// - 没有平台弹窗：文件选择、通知、托盘、剪贴板监视在本档只能断言「调用发生了」，
//   落不落得到系统由真机验；
// - 时间靠 `step` / `frame` 手动推进（无头泵不真睡），墙上时钟类行为不可见；
// - Retina/HiDPI 缩放、合成器透明、字体回退观感属真机人工清单。

///|
/// 一次无头会话：一棵挂好的树 + 画帧缓冲。
pub(all) struct Tester {
  root : @widget.Widget
  wpx : Int32
  hpx : Int32
  mut bm : @render.Bitmap?
  mut frames : Int32
  // 观察点计数：找/动/看三类门面每调一次 +1，finish() 据此判「这条用例什么都没跑」
  mut ops : Int32
}

///|
/// 定位结果：`w` 为 None = 没找到（动/看方法对它全部空操作并给 None）。
pub(all) struct Target {
  root : @widget.Widget
  w : @widget.Widget?
}

///|
/// 平台能力只读量（守卫用，见 guard_text / guard_decode）。
pub(all) struct Capabilities {
  /// 文本测量可用（DirectWrite/CoreText/Pango 探针给值）
  text_measure : Bool
  /// 图片解码可用（示例 GIF 能解出帧）
  image_decode : Bool
  /// 位图可分配（纯光栅/cairo 会话）
  raster : Bool
}

///|
let skipped_text : Ref[Int32] = Ref(0)

///|
let skipped_decode : Ref[Int32] = Ref(0)

///|
/// 建树：单根节点。root 先建一个 100% 容器再挂。
pub fn mount(root : @widget.Node, width : Double, height : Double) -> Tester {
  mount_all([root], width, height)
}

///|
/// 建树：多子件平铺成一列（与既有 wbtest 的 mount_root 同口径——交叉轴
/// FlexStart，组件测量尺寸才是真值），建完立即排一版布局。
pub fn mount_all(
  children : Array[@widget.Node],
  width : Double,
  height : Double,
) -> Tester {
  let root = @widget.Widget::new()
  root.set_size(width, height)
  root.set_column()
  root.node.set_align_items(@yoga.AlignItems::FlexStart)
  @widget.mount_children(root, children)
  root.relayout(width, height)
  {
    root,
    wpx: width.round().to_int(),
    hpx: height.round().to_int(),
    bm: None,
    frames: 0,
    ops: 0,
  }
}

// ---- 找 ----

///|
/// 深度优先找第一个 `name == n` 的控件（`Node::named` / 动态文本写回的那份）。
pub fn Tester::by_name(self : Tester, n : String) -> Target {
  self.ops += 1
  { root: self.root, w: find_named(self.root, n), }
}

///|
/// 语义糖：可见文本默认进 name，按文本找等价按名找。
pub fn Tester::by_text(self : Tester, s : String) -> Target {
  self.ops += 1
  self.by_name(s)
}

///|
/// `base` 的第 i 个直接子控件（base 未命中给未命中）。
pub fn Tester::nth(self : Tester, base : Target, i : Int32) -> Target {
  self.ops += 1
  let _ = self
  match base.w {
    Some(w) =>
      if i >= 0 && i < w.kids.length() {
        { root: base.root, w: Some(w.kids[i]), }
      } else {
        { root: base.root, w: None, }
      }
    None => { root: base.root, w: None, }
  }
}

///|
/// 坐标命中（窗口口径，相对根原点）：这个点最深的那个控件。
pub fn Tester::hit(self : Tester, x : Double, y : Double) -> Target {
  self.ops += 1
  let path = self.root.hit_path(x, y)
  if path.length() == 0 {
    { root: self.root, w: None, }
  } else {
    { root: self.root, w: Some(path[path.length() - 1]), }
  }
}

///|
fn find_named(w : @widget.Widget, n : String) -> @widget.Widget? {
  if w.name == n {
    return Some(w)
  }
  for k in w.kids {
    match find_named(k, n) {
      Some(x) => return Some(x)
      None => ()
    }
  }
  None
}

// ---- 动 ----

///|
/// 点一下：Down + Up 成对封死，坐标取矩形中心。
pub fn Tester::click(self : Tester, t : Target) -> Unit {
  self.ops += 1
  ignore(self)
  match t.w {
    Some(w) => {
      let cx = w.rect.x + w.rect.w / 2.0
      let cy = w.rect.y + w.rect.h / 2.0
      let _ = t.root.dispatch_pointer({
        kind: @widget.PointerKind::Down,
        x: cx,
        y: cy,
        button: 1,
        mods: 0,
      })
      // Down + Up 成对封死；Up 的消费态即本次点击的结果
      let _ = t.root.dispatch_pointer({
        kind: @widget.PointerKind::Up,
        x: cx,
        y: cy,
        button: 1,
        mods: 0,
      })
    }
    None => ()
  }
}

///|
/// 原始指针事件注入（窗口口径，相对根原点）。返回是否被消费。
pub fn Tester::pointer(
  self : Tester,
  kind : @widget.PointerKind,
  x : Double,
  y : Double,
  button~ : Int32 = 1,
  mods~ : Int32 = 0,
) -> Bool {
  self.ops += 1
  self.root.dispatch_pointer({ kind, x, y, button, mods, })
}

///|
/// 打字：焦点定位 + IME commit 通道逐段注入（与真实输入法同一入口）。
/// 目标未命中时空操作。要求目标可聚焦（focus_id > 0）。
pub fn Tester::type_text(self : Tester, t : Target, s : String) -> Unit {
  self.ops += 1
  ignore(self)
  match t.w {
    Some(w) =>
      if w.focus_id > 0 {
        let _ = t.root.dispatch_commit(w.focus_id, s)
      }
    None => ()
  }
}

///|
/// 按键注入：按 focus_id 路由（0 = 无焦点，直接给未消费）。返回是否被消费。
pub fn Tester::key(
  self : Tester,
  focus_id : Int32,
  keysym : Int32,
  mods~ : Int32 = 0,
  press~ : Bool = true,
) -> Bool {
  self.ops += 1
  self.root.dispatch_key(focus_id, { press, keysym, mods, })
}

///|
/// 滚轮注入（dy 正 = 向下滚）。
pub fn Tester::scroll(self : Tester, t : Target, dy : Double) -> Unit {
  self.ops += 1
  ignore(self)
  match t.w {
    Some(w) => {
      let cx = w.rect.x + w.rect.w / 2.0
      let cy = w.rect.y + w.rect.h / 2.0
      let _ = t.root.dispatch_scroll({ x: cx, y: cy, dx: 0.0, dy, mods: 0, })
    }
    None => ()
  }
}

///|
/// 拖拽：Down → steps 段线性 Move → Up（窗口口径，相对根原点）。
pub fn Tester::drag(
  self : Tester,
  from : (Double, Double),
  to : (Double, Double),
  steps~ : Int32 = 10,
) -> Unit {
  self.ops += 1
  let n = if steps < 1 { 1 } else { steps }
  let _ = self.root.dispatch_pointer({
    kind: @widget.PointerKind::Down,
    x: from.0,
    y: from.1,
    button: 1,
    mods: 0,
  })
  let mut i = 1
  while i <= n {
    let k = i.to_double() / n.to_double()
    let _ = self.root.dispatch_pointer({
      kind: @widget.PointerKind::Move,
      x: from.0 + (to.0 - from.0) * k,
      y: from.1 + (to.1 - from.1) * k,
      button: 1,
      mods: 0,
    })
    i += 1
  }
  let _ = self.root.dispatch_pointer({
    kind: @widget.PointerKind::Up,
    x: to.0,
    y: to.1,
    button: 1,
    mods: 0,
  })
}

// ---- 看 ----

///|
/// 无条件重画一帧：重算布局 + 全量绘制到缓冲。**不装** repaint hook
/// （进程级单例，多 Tester 并行会互相覆盖），帧数不能省但零耦合。
pub fn Tester::frame(self : Tester) -> Unit {
  self.root.relayout(self.root.rect.w, self.root.rect.h)
  let bm = @render.Bitmap::new(self.wpx, self.hpx)
  let p = @render.Painter::new(bm)
  self.root.paint(p)
  p.end()
  self.bm = Some(bm)
  self.frames += 1
}

///|
/// 控件矩形（窗口口径，相对根原点）。
pub fn Tester::rect(self : Tester, t : Target) -> @base.Rect? {
  self.ops += 1
  match t.w {
    Some(w) => Some(w.rect)
    None => None
  }
}

///|
/// 控件文本（动态文本绑定与静态文本写回的 `label` 面；未命中或空给 None）。
pub fn Tester::text(self : Tester, t : Target) -> String? {
  self.ops += 1
  match t.w {
    Some(w) => if w.label.length() > 0 { Some(w.label) } else { None }
    None => None
  }
}

///|
/// 控件类名（组件构造/包装器写回的 `role`）。
pub fn Tester::role(self : Tester, t : Target) -> String? {
  self.ops += 1
  match t.w {
    Some(w) => Some(w.role)
    None => None
  }
}

///|
/// 像素读数（RGBA；frame() 之后才有内容）。越界给全 0。
pub fn Tester::pixel(
  self : Tester,
  x : Int32,
  y : Int32,
) -> (Int32, Int32, Int32, Int32) {
  self.ops += 1
  match self.bm {
    Some(bm) =>
      if x >= 0 && x < bm.width && y >= 0 && y < bm.height {
        let px = bm.pixel(x, y)
        (px.r, px.g, px.b, px.a)
      } else {
        (0, 0, 0, 0)
      }
    None => (0, 0, 0, 0)
  }
}

///|
/// 整帧位图（frame() 之后才有内容，否则 None）。
pub fn Tester::bitmap(self : Tester) -> @render.Bitmap? {
  self.ops += 1
  self.bm
}

///|
/// 平台能力探测（一次会话探一遍，结果与进程一致）。图片解码用示例 GIF
/// 探（测试进程 cwd 是模块根，资源在仓根 examples/ 下，两个候选都试）。
pub fn Tester::capabilities(self : Tester) -> Capabilities {
  let _ = self
  {
    text_measure: @text.measure("Ag", 13.0) is Some(_),
    image_decode: gif_probe_width() > 0.0,
    raster: probe_raster_ok(),
  }
}

///|
fn gif_probe_width() -> Double {
  for
    rel in [
      "examples/components/assets/dot.gif", "../examples/components/assets/dot.gif",
    ] {
    let w = @render.Image::new_from_file(rel).get_width()
    if w > 0.0 {
      return w
    }
  }
  0.0
}

///|
fn probe_raster_ok() -> Bool {
  let bm = @render.Bitmap::new(4, 4)
  bm.width == 4
}

///|
/// 能力守卫：文本测量缺失时打印 skip 行并计数，返回 false（用例直接 return）。
/// 依赖它的用例名约定带 `[需文本]` 前缀。
pub fn guard_text(t : Tester) -> Bool {
  if t.capabilities().text_measure {
    true
  } else {
    skipped_text.val += 1
    println("uitest: skip [需文本]（本平台无文本测量后端）")
    false
  }
}

///|
/// 能力守卫：图片解码缺失时打印 skip 行并计数，返回 false。
/// 依赖它的用例名约定带 `[需解码]` 前缀。
pub fn guard_decode(t : Tester) -> Bool {
  if t.capabilities().image_decode {
    true
  } else {
    skipped_decode.val += 1
    println("uitest: skip [需解码]（本平台无图片解码后端）")
    false
  }
}

///|
/// 本会话跑过的观察点数：找（`by_name` / `by_text` / `nth` / `hit`）、动
/// （`click` / `pointer` / `type_text` / `key` / `scroll` / `drag`）、看
/// （`rect` / `text` / `role` / `pixel` / `bitmap`）三类门面各算一次。
pub fn Tester::assertions(self : Tester) -> Int32 {
  self.ops
}

///|
/// 用例尾硬判据：**一条断言都没跑即红**。
/// 只加这一条，不设跳过率阈值——runner 机器的字体/后端与本机构成不同，阈值会
/// 间歇红；而「一次门面调用都没发生」只会是接线断（树没挂上、动也没动、看也
/// 没看就 return），那种红是真红。
pub fn Tester::finish(self : Tester) -> Unit {
  if self.ops == 0 {
    abort(
      "uitest: 本用例一次观察点都没跑（树没挂上 / 没定位 / 没动 / 没看就 return？）",
    )
  }
}

///|
/// 建一扇无头虚窗宿主（对外门面；底座 `@widget.WindowHost::test_headless` 不当
/// 1.0 契约，签名可能随宿主内部改）。用法：`let win = @uitest.test_headless(800, 600)`
/// 后照常 `win.mount([...])`，再改状态 → `win.step()` 若干拍 → 断言泵行为
/// （定时器到期、脏区合并、深浅轮询）。语义边界见本包顶部「虚窗 ≠ 真窗」。
pub fn test_headless(width : Int32, height : Int32) -> @widget.WindowHost {
  @widget.WindowHost::test_headless(width, height)
}

///|
/// 守卫计数汇总（用例尾打印一行，便于 CI grep 汇总缺口）。
pub fn guard_report() -> Unit {
  if skipped_text.val > 0 || skipped_decode.val > 0 {
    println(
      "uitest: \{skipped_text.val} 跳过依赖文本测量 / \{skipped_decode.val} 依赖图片解码",
    )
  }
}

// ---- 确定性时钟（A7）：虚拟时间整体推进 ----
//
// `test_headless` 宿主泵在无头档吃虚拟时基（墙钟 + 偏移）：`advance` 把时基
// 整体前移并按 ~16ms 补帧（定时器到期、过渡动画、宿主周期表同一时基，推多少
// ms 就是多少 ms，与机器速度无关——慢机器不会让动画「少走一段」）；`settle`
// 跑到无到期定时器且无脏窗（有界，防回调自排死循环）。两者都只动无头档，
// 真实运行档零影响。

///|
/// 虚拟时间整体前移 `ms` 毫秒，期间按 ~16ms 一拍补帧（每拍 step 一次：到期
/// 任务结算 + 逐窗绘制）。返回实际走的拍数。宿主取 `test_headless` 的那扇
/// （真实宿主不受影响——虚拟偏移只在无头泵档被消费）。
pub fn advance(win : @widget.WindowHost, ms : Int32) -> Int32 {
  let mut left = if ms < 0 { 0 } else { ms }
  // 每拍把时基钉到「起点 + 累计」，不按偏移量叠加：step 内绘制/派发走过的
  // 墙钟毫秒不计入，慢机器上「推 100ms」也不会多吃出几十毫秒（定时器误到期
  // 的根因）。起点取当前虚拟读数，与 session_vtime_reset 之后的墙钟基线一致。
  @shell.session_vtime_unpin() // 上一用例中途失败可能遗留钉位
  let start = @shell.session_vtime_now()
  let mut acc = 0
  let mut steps = 0
  while left > 0 {
    let d = if left > 16 { 16 } else { left }
    acc += d
    @shell.session_vtime_pin(start + acc.to_int64())
    let _ = win.step()
    steps += 1
    left -= d
  }
  @shell.session_vtime_unpin()
  steps
}

///|
/// 收敛：跑到「无到期定时器且无脏窗」为止（每拍 step 一次）；`max_steps`
/// 封顶防回调自排死循环（到顶就停，不是错——调用方按需断言后续状态）。
/// 返回实际走的拍数。
pub fn settle(win : @widget.WindowHost, max_steps~ : Int32 = 120) -> Int32 {
  @shell.session_vtime_unpin() // 同 advance：先解掉上一用例可能遗留的钉位
  let l = @shell.host_loop()
  let mut n = 0
  while n < max_steps {
    let due = l.due_pending(@shell.session_vtime_now())
    let dirty = win.dirty_full || win.dirty_rect is Some(_)
    if due == 0 && !dirty {
      break
    }
    let _ = win.step()
    n += 1
  }
  n
}
