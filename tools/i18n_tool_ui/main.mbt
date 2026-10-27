// i18n 目录查看器入口。用法：moon run tools/i18n_tool_ui -- <locale.toml>

fn slurp(p : String) -> String? {
  let s = @fs.read_file_to_string(p) catch { _ => return None }
  Some(s)
}

fn main {
  let raw = @env.args()
  if raw.length() < 2 {
    println("用法：moon run tools/i18n_tool_ui -- <locale.toml>")
    return
  }
  let path = raw[1]
  let cat = match slurp(path) {
    None => {
      println("读取失败：" + path)
      return
    }
    Some(text) => @i18nkit.parse_catalog(text)
  }

  let rows : Array[@widget.Node] = []
  for (k, v) in cat.texts {
    let shown = if v.length() > 0 { v } else { "（空/缺译）" }
    rows.push(
      @ui.row(
        [
          @ui.text(k, class=[@style.text_secondary]),
          @ui.text(shown),
        ],
        column_gap=16.0,
      ),
    )
  }
  for (k, forms) in cat.plurals {
    rows.push(@ui.text(k + "  {复数 " + forms.length().to_string() + " 式}"))
  }

  let header = "i18n 目录 · locale=" + cat.locale + " · " + cat.texts.length().to_string() + " 键（" + path + "）"
  let root = @ui.col(
    [
      @ui.text(header),
      @ui.scroll_view(
        [@ui.col(rows, row_gap=6.0)],
        @ui.ScrollState::new(),
        handle=fn(v : @widget.Widget) { v.node.set_flex_grow(1.0) },
      ),
    ],
    row_gap=8.0,
    padding=12.0,
  )
  let mounted = @ui.mount_window(
    [root],
    title="i18n 目录查看器",
    width=720,
    height=560,
    handle=fn(_a : @widget.App) { () },
  )
  match mounted {
    None => println("本平台无窗口后端或无显示服务")
    Some(host) => host.run()
  }
}
