// 语义快照通道（无障碍）：MoonBit 每帧把整棵树的语义面摊成一段 TSV 推给平台臂。
//
// 通道形态：TSV 一行一个控件，字段顺序
//   id \t parent \t enabled \t role \t name \t state \t value \t text \t x \t y \t w \t h
// C 侧只做存储（wm_a11y_publish），平台臂按需读（mac 的 accessibilityChildren、
// Windows UIA / Linux AT-SPI 同读这一份）。换帧整体替换，不做增量补丁——一屏
// 几十个控件，重建比维护「谁删了」便宜，也根除幽灵控件。
//
// 同 file 的三条伴生通道：动作队列（provider 的动作侧压、MoonBit 每帧抽）、
// 焦点 id（MoonBit 每帧报、平台臂答「焦点元素是谁」）、变更通知（快照内容
// 变了/焦点换了，平台臂把「该重新读了」发给读屏——mac 发 AX 通知，
// Win/GTK 无对位物只记计数）。

///|
#borrow(blob)
extern "c" fn wm_a11y_publish(blob : Bytes, len : Int, count : Int) -> Unit = "wm_a11y_publish"

///|
extern "c" fn wm_a11y_count() -> Int = "wm_a11y_count"

///|
/// 抽一个读屏动作（Windows UIA 的 Invoke/Toggle/Expand 等压进的动作队列）：
/// 编码 `(widget_id << 3) | action`，0 = 无待办。非 Windows 后端没有
/// provider，恒 0（队列符号在 stub.c 的实现 TU 段，全平台都要能链）。
extern "c" fn wm_uia_action_poll() -> Int64 = "wm_uia_action_poll"

///|
/// 读屏动作码：在控件中心合成一次点击（Down+Up 走与真实点击同一条
/// `route_pointer`，组件闭包里的 Store/Editor 由点击链路自己驱动）。
pub const A11Y_ACT_CLICK : Int = 1

///|
/// 推一帧语义快照（`blob` 为 TSV，`count` 为行数）。
pub fn a11y_publish(blob : Bytes, count : Int) -> Unit {
  wm_a11y_publish(blob, blob.length(), count)
}

///|
/// 平台侧当前持有的快照行数（用例/诊断观察面；也证明发布链路真的落地了）。
pub fn a11y_published_count() -> Int {
  wm_a11y_count()
}

///|
/// 快照行数（平台臂与纯 MoonBit 桥的读出面）。
extern "c" fn wm_a11y_row_count() -> Int = "wm_a11y_count"

///|
/// 把快照行 `i` 摊成发布时同一格式的 TSV（字段序见文件头）；行不存在给
/// None。AT-SPI 桥（住 shell 层，不依赖 widget 包）与诊断共用这一读出口。
///|
#borrow(out)
extern "c" fn wm_a11y_row_tsv(
  i : Int,
  out : Bytes,
  cap : Int,
) -> Int = "wm_a11y_row_tsv"

///|
/// 窗口客户区原点（物理像素）：MoonBit 每帧报，AT-SPI 的 Component 屏幕
/// 坐标 = 原点 + 快照矩形（窗口坐标）。
extern "c" fn wm_a11y_set_window_origin(x : Double, y : Double) -> Unit = "wm_a11y_set_window_origin"

///|
/// 平台侧记录的窗口原点 x（诊断观察面）。
extern "c" fn wm_a11y_window_origin_x() -> Double = "wm_a11y_window_origin_x"

///|
/// 平台侧记录的窗口原点 y（诊断观察面）。
extern "c" fn wm_a11y_window_origin_y() -> Double = "wm_a11y_window_origin_y"

///|
/// 快照行数。
pub fn a11y_row_count() -> Int {
  wm_a11y_row_count()
}

///|
/// 读一行快照的 TSV（行不存在 None）。
pub fn a11y_row_tsv(i : Int) -> String? {
  // 最坏行 ≈1000B（C 侧 name[256]+text[512]+role/state/value+4 个 double），
  // 取 4096 留 4 倍余量：C 侧字段加宽时这里不用跟着猜，放不下 C 侧回 -1
  // （本函数当 None，该行从读屏树里静默消失——余量就是防这个）。
  let cap = 4096
  let buf = Bytes::from_array(FixedArray::make(cap, b'\x00'))
  let n = wm_a11y_row_tsv(i, buf, cap)
  if n <= 0 {
    None
  } else {
    Some(@utf8.decode_lossy(buf[:n]))
  }
}

///|
/// 报窗口客户区原点（宿主每帧调；AT-SPI 屏幕坐标用）。
pub fn a11y_set_window_origin(x : Double, y : Double) -> Unit {
  wm_a11y_set_window_origin(x, y)
}

///|
/// 平台侧记录的窗口原点。
pub fn a11y_window_origin() -> (Double, Double) {
  (wm_a11y_window_origin_x(), wm_a11y_window_origin_y())
}

///|
/// 压一个读屏动作进跨平台队列（MoonBit 侧入口：AT-SPI 的 DoAction 等；
/// Windows UIA 与 macOS AX 的动作由各自 C 侧压同一份队列）。
extern "c" fn wm_a11y_action_push(id : Int, act : Int) -> Unit = "wm_a11y_action_push"

///|
/// MoonBit 侧压「点一下这个控件」进读屏动作队列（宿主每帧抽走派发）。
pub fn a11y_action_push(id : Int, act : Int) -> Unit {
  wm_a11y_action_push(id, act)
}

///|
/// 抽一个待办的读屏动作：None = 队列空。
pub fn a11y_action_poll() -> (Int, Int)? {
  let v = wm_uia_action_poll()
  if v <= 0 {
    None
  } else {
    Some(((v >> 3).to_int(), (v & 7).to_int()))
  }
}

///|
/// 报当前焦点控件 id（0 = 无焦点）：平台臂据此答「焦点元素是谁」。
extern "c" fn wm_a11y_set_focus(id : Int) -> Unit = "wm_a11y_set_focus"

///|
/// 读平台侧记录的焦点 id（诊断与用例观察面）。
extern "c" fn wm_a11y_focus() -> Int = "wm_a11y_focus"

///|
/// 通知读屏「快照内容变了，该重新读」（mac 发 AX LayoutChanged；Win/GTK 无
/// 对位物，只把计数记下来供用例观察链路真的走过）。
extern "c" fn wm_a11y_notify_layout_changed() -> Unit = "wm_a11y_notify_layout_changed"

///|
/// 通知读屏「焦点换了」（mac 发 AX FocusedUIElementChanged）。
extern "c" fn wm_a11y_notify_focus_changed() -> Unit = "wm_a11y_notify_focus_changed"

///|
/// 累计 layout 通知次数（纯读；通知本身不返回读数）。
extern "c" fn wm_a11y_layout_notify_count() -> Int = "wm_a11y_layout_notify_count"

///|
/// 累计 focus 通知次数（纯读）。
extern "c" fn wm_a11y_focus_notify_count() -> Int = "wm_a11y_focus_notify_count"

///|
/// 报焦点控件 id（宿主每帧调；0 = 无焦点）。
pub fn a11y_set_focus(id : Int) -> Unit {
  wm_a11y_set_focus(id)
}

///|
/// 平台侧记录的焦点 id。
pub fn a11y_focus() -> Int {
  wm_a11y_focus()
}

///|
/// 通知读屏「快照内容变了」。
pub fn a11y_notify_layout_changed() -> Unit {
  wm_a11y_notify_layout_changed()
}

///|
/// 通知读屏「焦点换了」。
pub fn a11y_notify_focus_changed() -> Unit {
  wm_a11y_notify_focus_changed()
}

///|
/// 累计 layout 通知次数（诊断与用例观察面）。
pub fn a11y_layout_notify_count() -> Int {
  wm_a11y_layout_notify_count()
}

///|
/// 累计 focus 通知次数（诊断与用例观察面）。
pub fn a11y_focus_notify_count() -> Int {
  wm_a11y_focus_notify_count()
}
