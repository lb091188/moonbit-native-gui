// 代码文档页 · 终端段：Terminal 模型 + ANSI 演示。
// 本页没有 PTY：键盘输入经 on_input 进输入行，回车把整行喂回终端——
// 演示的正是将来接 PTY 时的同一条缝（on_input 出口）。

///|
fn code_terminal_section() -> @shared.Section {
  let term = @ui.Terminal::new(cols=80, rows=12, scrollback=1000)
  let counter : @base.Store[Int] = @base.Store::new(0)
  let percent : Ref[Int] = Ref(0)
  let input_line : @base.Store[String] = @base.Store::new("")
  let note : @base.Store[String] = @base.Store::new(
    @shared.tx("聚焦终端直接打字/方向键，看输入行回显；按回车把输入喂进终端"),
  )
  term.feed("\u{1b}[1;36m== terminal ==\u{1b}[0m 喂文本即可用：日志 / REPL 输出 / 构建着色\n")
  term.feed(
    "\u{1b}[31mred \u{1b}[32mgreen \u{1b}[33myellow \u{1b}[34mblue \u{1b}[35mmagenta \u{1b}[36mcyan \u{1b}[91mbright red\u{1b}[0m\n",
  )
  term.feed(
    "\u{1b}[38;5;196m256 色 196\u{1b}[0m · \u{1b}[38;2;255;128;0mtruecolor #ff8000\u{1b}[0m · \u{1b}[1m粗体 \u{1b}[3m斜体 \u{1b}[4m下划线\u{1b}[0m\n",
  )
  term.feed("CJK 对齐：中文与 ASCII 同走等宽网格，宽字符占两格\n")
  term.feed(
    "超长行自动折行：这一行远超网格宽度会自动换行继续显示，滚轮或 Shift+PageUp 看回看区，拖选后 Ctrl/Cmd+C 可复制。\n",
  )
  term.feed("\u{1b}[44m反显/底色：\u{1b}[0m \u{1b}[7mreverse video\u{1b}[0m\n")
  @shared.section(
    "终端",
    "Terminal 终端",
    "等宽网格 + ANSI CSI/SGR 子集：16/256/truecolor、粗斜/下划线/反显、光标、自动折行与回看滚动（滚轮 / Shift+PageUp/Down / 滚动条）；拖选后 Ctrl/Cmd+C 复制（裸 Ctrl+C 是 \\x03 进输入，不当复制吃掉）、Cmd/Ctrl+Shift+V 粘贴；按键全部经 on_input 出口交给应用——本页没有 PTY，输入行回显、回车把整行喂回终端演示同一条缝。",
    [
      @ui.row(
        [
          @ui.button(@shared.tx("喂一行"), on_click=fn() {
            let n2 = counter.get() + 1
            counter.set(n2)
            term.feed(
              "\u{1b}[32m[\u{1b}[0m行 \{n2}\u{1b}[32m]\u{1b}[0m 新的一行日志，颜色随计数轮换\n",
            )
          }),
          @ui.button(@shared.tx("进度重画"), on_click=fn() {
            let p2 = percent.val + 20
            percent.val = if p2 > 100 { 0 } else { p2 }
            term.feed("\r构建进度: \{percent.val}%   ")
            if percent.val == 0 {
              term.feed("\u{1b}[32mdone\u{1b}[0m\n")
            }
          }),
          @ui.button(@shared.tx("长输出 50 行"), on_click=fn() {
            for i in 1..=50 {
              term.feed(
                "log line \{i}: the quick brown fox jumps over the lazy dog 0123456789\n",
              )
            }
          }),
          @ui.button(@shared.tx("清屏"), on_click=fn() { term.clear() }),
        ],
        column_gap=8.0,
      ),
      @ui.bind_label(note, fn(s) { s }),
      @ui.terminal(term, height=240.0, on_input=fn(s : String) -> Unit {
        // 逐字符消费：回车喂回终端、退格删输入行、可打印进输入行、其余忽略
        for ch in s {
          match ch {
            '\r' | '\n' => {
              term.feed(
                "\u{1b}[33myou>\u{1b}[0m " + input_line.get() + "\n",
              )
              input_line.set("")
            }
            '\u{7f}' => {
              let cur = input_line.get()
              let chars : Array[Char] = []
              for c2 in cur {
                chars.push(c2)
              }
              if chars.length() > 0 {
                let sb = StringBuilder()
                for i in 0..<(chars.length() - 1) {
                  sb.write_char(chars[i])
                }
                input_line.set(sb.to_string())
              }
            }
            c if c.to_int() >= 32 =>
              input_line.set(input_line.get() + c.to_string())
            _ => ()
          }
        }
      }),
      @ui.bind_label(input_line, fn(s) {
        @shared.tr_with("dyn.terminal_input", [("s", s)], "输入> \{s}")
      }),
    ],
    code=[
      "let term = @ui.Terminal::new(cols=80, rows=12)",
      "term.feed(\"\\u{1b}[31mred\\u{1b}[0m plain\\n\")",
      "@ui.terminal(term, height=240.0, on_input=fn(s) { … })",
    ],
  )
}
