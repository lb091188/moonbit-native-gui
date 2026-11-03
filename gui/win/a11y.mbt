// 语义快照通道（无障碍）：MoonBit 每帧把整棵树的语义面摊成一段 TSV 推给平台臂。
//
// 通道形态：TSV 一行一个控件，字段顺序
//   id \t parent \t enabled \t role \t name \t state \t value \t text \t x \t y \t w \t h
// C 侧只做存储（wm_a11y_publish），平台臂按需读（mac 的 accessibilityChildren、
// Windows UIA / Linux AT-SPI 同读这一份）。换帧整体替换，不做增量补丁——一屏
// 几十个控件，重建比维护「谁删了」便宜，也根除幽灵控件。

///|
#borrow(blob)
extern "c" fn wm_a11y_publish(blob : Bytes, len : Int, count : Int) -> Unit = "wm_a11y_publish"

///|
extern "c" fn wm_a11y_count() -> Int = "wm_a11y_count"

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
