// 文本族辅助：按宽量高。
//
// 排版角色已收编为 @style 字阶预设（TextRole 退役），本入口直接收 Font。

///|
/// 量一段文本在指定宽度下的自然渲染高（`width` 传 0 按不换行量）。
/// 运行期长高的标签用显式高度绕开「测量口径不一致」的老坑：容器问到的
/// 自然高与绘制时按盒宽折行算出的高可能不是一回事，显式设高最稳。
pub fn measure_text_height(
  text : String,
  font? : @text.Font = @text.Font::new(
    @theme.default_font_family(),
    @theme.font_size_body,
  ),
  width? : Double = 0.0,
) -> Double {
  let box_w = if width > 0.0 { width.floor().to_int() } else { 0 }
  match @text.measure_font(text, font, max_width=box_w, wrap=box_w > 0) {
    Some(m) => m.height.to_double()
    None => 0.0
  }
}
