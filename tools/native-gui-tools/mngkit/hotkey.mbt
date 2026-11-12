// 动态槽/条件槽的稳定键：表达式内容哈希，不含模板坐标。
// 结构增删挪不换键——应用侧注册表（dev 档 codegen）与补丁 IR 据此对齐。

///|
fn hotkey_hex8(h : Int32) -> String {
  let digits : Array[String] = [
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f",
  ]
  let out = StringBuilder()
  let mut i = 7
  while i >= 0 {
    out.write_string(digits[(h >> (i * 4)) & 15])
    i = i - 1
  }
  out.to_string()
}

///|
fn hotkey_hash(s : String, seed : Int32) -> Int32 {
  let mut h = seed
  for c in s.to_array() {
    h = ((h << 5) + h + c.to_int()) & 0x7FFF_FFFF
  }
  h
}

///|
/// 键形如 `t:<16 位十六进制>`（动态文本/参数）或 `c:<…>`（条件）。
/// 取表达式原文去首尾空白后的双哈希，同文同键、异文几乎不撞。
fn bind_key(kind : String, text : String) -> String {
  let s = text.trim().to_owned()
  kind +
  ":" +
  hotkey_hex8(hotkey_hash(s, 5381)) +
  hotkey_hex8(hotkey_hash(s, 52711))
}
