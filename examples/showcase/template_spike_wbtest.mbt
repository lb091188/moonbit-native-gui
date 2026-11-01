// spike 生成码（2026-11-01）：page_form.mui.html 节选的「应生成 MoonBit 版」。
// 只证生成码「可读、可编译、可无头构造」（DX 生死线 #2）；语法契约见
// proposals/native-template.md「Spike 契约」。编译器落地后本文件由真实产物替代。

///|
fn template_spike() -> @widget.Node {
  // —— script 段原文 ——
  let qty : @base.Store[Int] = @base.Store::new(3)
  let slider_val : @base.Store[Double] = @base.Store::new(30.0)
  let wifi_on : @base.Store[Bool] = @base.Store::new(true)
  let nick : @base.Store[String] = @base.Store::new("")
  let err_nick = @ui.validate(nick, @ui.all([@ui.required(), @ui.min_len(2)]))
  let passed = @base.Signal::computed(fn() {
    if err_nick.get().length() == 0 {
      1
    } else {
      0
    }
  })
  fn on_reset() {
    qty.set(3)
    nick.set("")
  }
  // —— 模板树 ——
  @shared.page([
    @shared.section("数值", "步进器 / 滑杆 / 评分", "stepper 0..10 钳制。", [
      @ui.stepper(qty, min=0, max=10, step=1),
      @ui.slider(slider_val, min=0.0, max=100.0, step=5.0, width=200.0),
      @ui.bind_label(qty, fn(v) { "当前数量：\{v}" }),
    ]),
    @shared.section("开关", "Checkbox", "开关驱动结构条件。", [
      @ui.checkbox(@shared.tx("自动开启"), wifi_on),
      @widget.bind_node(wifi_on.signal(), fn(on) {
        if on {
          @ui.text(@shared.tx("已开启"))
        } else {
          @ui.text(@shared.tx("已关闭"))
        }
      }),
      @ui.button(@shared.tx("重置"), on_click=on_reset),
    ]),
    @shared.section("表单校验", "Form", "规则即时重跑。", [
      @ui.form(@shared.tx("注册资料"), [
        @ui.form_item(@shared.tx("昵称"), @ui.input(
            nick,
            placeholder=@shared.tx("至少 2 个字符"),
            width=200.0,
          ), error=err_nick),
      ]),
      @ui.bind(passed, fn(v) { "已通过校验 \{v} 项" }),
    ]),
  ])
}

///|
test "spike 生成码：模板页可无头构造" {
  let _node = template_spike()
}
