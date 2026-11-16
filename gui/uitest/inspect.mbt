// 无头检查直调（inspector 服务化批）：dump_tree / shot 不经 socket——
// 测试进程内直接取帧尾快照与位图，与服务端（gui/inspector 的 tree / shot
// 命令）同一份数据源、同一套列序，断言口径与真机 mng inspect 一致。

///|
/// 整树 dump：先做一次帧尾语义对账（快照新鲜），再按服务端 `tree` 命令的
/// 同一列序摊 TSV（首行列头，一行一控件）。无头测试断言控件树用。
pub fn Tester::dump_tree(self : Tester) -> String {
  self.ops += 1
  let _ = @widget.a11y_frame_sync(self.root)
  let sb = StringBuilder()
  sb.write_string(
    "#kind\trole\tname\tid\tparent\tx\ty\tw\th\tstate\tvalue\ttext\tenabled\n",
  )
  for n in @widget.a11y_last_frame() {
    sb.write_string(n.kind)
    sb.write_string("\t")
    sb.write_string(n.role)
    sb.write_string("\t")
    sb.write_string(n.name)
    sb.write_string("\t")
    sb.write_string(n.id.to_string())
    sb.write_string("\t")
    sb.write_string(n.parent.to_string())
    sb.write_string("\t")
    sb.write_string(n.x.to_string())
    sb.write_string("\t")
    sb.write_string(n.y.to_string())
    sb.write_string("\t")
    sb.write_string(n.w.to_string())
    sb.write_string("\t")
    sb.write_string(n.h.to_string())
    sb.write_string("\t")
    sb.write_string(n.state)
    sb.write_string("\t")
    sb.write_string(n.value)
    sb.write_string("\t")
    sb.write_string(n.text)
    sb.write_string("\t")
    sb.write_string(if n.enabled { "1" } else { "0" })
    sb.write_string("\n")
  }
  sb.to_string()
}

///|
/// 整帧位图落盘 PNG（frame() 之后才有内容）：`true` 写出成功。
/// 与服务端 `shot` 命令同一编码口（`png_write_bitmap`）。
pub fn Tester::shot(self : Tester, path : String) -> Bool {
  self.ops += 1
  match self.bm {
    Some(bm) => @render.png_write_bitmap(bm, path)
    None => false
  }
}

///|
/// 控件组件类型名（构造自带，`with_kind` 可覆盖）。
pub fn Tester::kind(self : Tester, t : Target) -> String? {
  self.ops += 1
  match t.w {
    Some(w) => Some(w.kind)
    None => None
  }
}
