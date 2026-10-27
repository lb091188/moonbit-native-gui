// iconfont 预览 GUI 入口。用法：moon run tools/icon_tool_ui -- <iconfont.toml>

fn slurp(p : String) -> String? {
  let s = @fs.read_file_to_string(p) catch { _ => return None }
  Some(s)
}

// 每格：图标 + 下方名字
fn tile(name : String) -> @widget.Node {
  @ui.col(
    [
      @ui.iconfont(name, size=32.0),
      @ui.text(name, class=[@style.text_secondary]),
    ],
    row_gap=2.0,
    width=110.0,
  )
}

fn main {
  let raw = @env.args()
  if raw.length() < 2 {
    println("用法：moon run tools/icon_tool_ui -- <iconfont.toml>")
    return
  }
  let path = raw[1]
  match slurp(path) {
    None => {
      println("读取失败：" + path)
      return
    }
    Some(text) => {
      let _n = @icons.iconfont_load(text)
    }
  }
  let names = @icons.iconfont_names()
  // 网格：每行 5 格
  let rows : Array[@widget.Node] = []
  let mut i = 0
  while i < names.length() {
    let cells : Array[@widget.Node] = []
    let mut j = 0
    while j < 5 && i + j < names.length() {
      cells.push(tile(names[i + j]))
      j += 1
    }
    rows.push(@ui.row(cells, column_gap=8.0))
    i += 5
  }
  let header =
    "iconfont 预览 · " + names.length().to_string() + " 个（来源：" + path + "）"
  let root = @ui.col(
    [
      @ui.text(header),
      @ui.scroll_view(
        [@ui.col(rows, row_gap=10.0)],
        @ui.ScrollState::new(),
        handle=fn(v : @widget.Widget) { v.node.set_flex_grow(1.0) },
      ),
    ],
    row_gap=8.0,
    padding=12.0,
  )
  let mounted = @ui.mount_window(
    [root],
    title="iconfont 预览",
    width=720,
    height=560,
    handle=fn(_a : @widget.App) { () },
  )
  match mounted {
    None => println("本平台无窗口后端或无显示服务")
    Some(host) => host.run()
  }
}
