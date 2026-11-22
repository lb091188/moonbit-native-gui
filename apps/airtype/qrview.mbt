// 二维码自绘：moon-qrcode 出模块矩阵，on_draw 双层循环画方块网格。
// 白底黑码是固定色不随主题——扫码对比度优先，暗色模式下整块白是预期观感。

///|
/// 静区模块数：二维码四周的留白，规范四模块。
const QR_QUIET : Int32 = 4

///|
/// 画布边长（逻辑像素）。
const QR_CANVAS : Double = 280.0

///|
/// 编码文本出二维码。失败两级回落（降纠错档再编最短串），仍失败直接中止
/// ——URL 内容不该编不出，编不出属于程序性错误。
fn make_qr(text : String) -> @qrc.QrCode {
  @qr.encode(text, ec_level=@qrc.EcLevel::M) catch {
    _ =>
      @qr.encode("airtype", ec_level=@qrc.EcLevel::L) catch {
        _ => abort("二维码编码失败")
      }
  }
}

///|
/// 二维码画布节点：矩阵启动后不变（地址与 token 一次生成），不挂 Store。
fn qr_canvas(code : @qrc.QrCode) -> @widget.Node {
  let modules = code.modules()
  let n = code.size()
  @widget.node_of_new(
    fn(w : @widget.Widget) -> @widget.Widget {
      w.node.set_width(@yoga.fixed(QR_CANVAS))
      w.node.set_height(@yoga.fixed(QR_CANVAS))
      w.on_draw = Some(
        fn(_self : @widget.Widget, p : @render.Painter, r : @base.Rect) -> Unit {
          p.set_fill_color("#FFFFFF")
          p.fill_rect(0.0, 0.0, r.w, r.h)
          let total = (n + QR_QUIET * 2).to_double()
          let cell = r.w / total
          let base = cell * QR_QUIET.to_double()
          p.set_fill_color("#000000")
          for row in 0..<n {
            for col in 0..<n {
              if modules[row * n + col] {
                p.fill_rect(
                  base + col.to_double() * cell,
                  base + row.to_double() * cell,
                  cell,
                  cell,
                )
              }
            }
          }
        },
      )
      w
    },
  )
}
