// 二维码自绘：moon-qrcode 出模块矩阵，on_draw 双层循环画方块网格。
// 白底黑码是固定色不随主题——扫码对比度优先，暗色模式下整块白是预期观感。

///|
/// 静区模块数：二维码四周的留白，规范四模块。
const QR_QUIET : Int32 = 4

///|
/// 画布边长（逻辑像素）。
const QR_CANVAS : Double = 280.0

///|
/// 二维码图像：行主序模块矩阵 + 边长（模块数）。
#derive(Eq)
struct QrImage {
  modules : Array[Bool]
  size : Int32
}

///|
/// 编码文本出二维码图像。失败两级回落（降纠错档再编最短串），仍失败直接
/// 中止——URL 内容不该编不出，编不出属于程序性错误。
fn qr_image_of(text : String) -> QrImage {
  let code = @qr.encode(text, ec_level=@qrc.EcLevel::M) catch {
    _ =>
      @qr.encode("airtype", ec_level=@qrc.EcLevel::L) catch {
        _ => abort("二维码编码失败")
      }
  }
  { modules: code.modules(), size: code.size() }
}

///|
/// 二维码画布节点：图像来自 Store（地址与 token 一次生成后更新一次），
/// 更新方负责随之 `@widget.invalidate()`。
fn qr_canvas(img : @base.Store[QrImage]) -> @widget.Node {
  @widget.node_of_new(
    fn(w : @widget.Widget) -> @widget.Widget {
      w.node.set_width(@yoga.fixed(QR_CANVAS))
      w.node.set_height(@yoga.fixed(QR_CANVAS))
      w.on_draw = Some(
        fn(_self : @widget.Widget, p : @render.Painter, r : @base.Rect) -> Unit {
          let cur = img.get()
          p.set_fill_color("#FFFFFF")
          p.fill_rect(0.0, 0.0, r.w, r.h)
          let n = cur.size
          let total = (n + QR_QUIET * 2).to_double()
          let cell = r.w / total
          let base = cell * QR_QUIET.to_double()
          p.set_fill_color("#000000")
          for row in 0..<n {
            for col in 0..<n {
              if cur.modules[row * n + col] {
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
