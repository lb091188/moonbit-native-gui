// CPU 视觉能力批的无头视图连测：五件新能力各走一道「mount → frame → 像素/读数」
// 的完整视图链路，防「白盒单测各自绿、视图链路断线」的假绿。样式块一律先过
// merge_all 再 apply（组件 fold_style 同款归并路径），防「单块直 apply 绕过
// merge 字段表」的假绿。判据与演示页（components「过渡与效果」新增四段）同源。

///|
/// 视图连测①：aspect_ratio——定高一端由引擎解出宽（布局在真实挂载链路生效）。
test "视图① aspect_ratio：定高 30 比率 2 挂载后量得宽 60" {
  let t = mount(
    @widget.node_of_new(fn(w) {
      w.node.set_width(@yoga.fixed(120.0))
      w.node.set_height(@yoga.fixed(120.0))
      let kid = @widget.Widget::new()
      kid.name = "ar"
      w.append_child(kid)
      @style.apply(kid, @style.merge_all([@style.style(height=30.0, aspect_ratio=2.0)]))
      w
    }),
    120.0,
    120.0,
  )
  t.frame()
  let r = t.rect(t.by_name("ar"))
  match r {
    Some(rr) => {
      assert_eq(rr.h, 30.0)
      assert_eq(rr.w, 60.0)
    }
    None => abort("aspect_ratio 控件没挂上")
  }
  t.finish()
}

///|
/// 视图连测②：transform——20×10 蓝块绕中心转 90°，像素随变换落位。
test "视图② transform：旋转 90° 后像素换位" {
  let t = mount(
    @widget.node_of_new(fn(w) {
      w.node.set_width(@yoga.fixed(40.0))
      w.node.set_height(@yoga.fixed(40.0))
      w.on_draw = Some(fn(_w, p, r) {
        p.set_fill_color("#ff0000")
        p.fill_rect(0.0, 0.0, r.w, r.h)
      })
      let kid = @widget.Widget::new()
      kid.name = "rot"
      w.append_child(kid)
      @style.apply(kid, @style.merge_all([@style.style(rotate=90.0)]))
      kid.node.set_position(@yoga.Absolute)
      kid.node.set_top(@yoga.fixed(15.0))
      kid.node.set_left(@yoga.fixed(10.0))
      kid.node.set_width(@yoga.fixed(20.0))
      kid.node.set_height(@yoga.fixed(10.0))
      kid.on_draw = Some(fn(_w, p, r) {
        p.set_fill_color("#0000ff")
        p.fill_rect(0.0, 0.0, r.w, r.h)
      })
      w
    }),
    40.0,
    40.0,
  )
  t.frame()
  // 旋转后蓝区 (15..25, 10..30)：弧内蓝、原区域弧外红
  assert_eq(t.pixel(17, 12), (0, 0, 255, 255))
  assert_eq(t.pixel(12, 17), (255, 0, 0, 255))
  assert_eq(t.pixel(20, 20), (0, 0, 255, 255))
  t.finish()
}

///|
/// 视图连测③：clip_rounded——挂载期设旗自绘前就裁，方角子件被裁进圆角。
test "视图③ 圆角裁切：弧外露父层底色" {
  let t = mount(
    @widget.node_of_new(fn(w) {
      w.node.set_width(@yoga.fixed(40.0))
      w.node.set_height(@yoga.fixed(40.0))
      w.on_draw = Some(fn(_w, p, r) {
        p.set_fill_color("#ff0000")
        p.fill_rect(0.0, 0.0, r.w, r.h)
      })
      let card = @widget.Widget::new()
      card.name = "card"
      card.node.set_position(@yoga.Absolute)
      card.node.set_top(@yoga.fixed(10.0))
      card.node.set_left(@yoga.fixed(10.0))
      card.node.set_width(@yoga.fixed(20.0))
      card.node.set_height(@yoga.fixed(20.0))
      card.clip_rounded = true
      card.style_clip_radius = 6.0
      w.append_child(card)
      let kid = @widget.Widget::new()
      kid.node.set_position(@yoga.Absolute)
      kid.node.set_top(@yoga.fixed(0.0))
      kid.node.set_left(@yoga.fixed(0.0))
      kid.node.set_width(@yoga.fixed(20.0))
      kid.node.set_height(@yoga.fixed(20.0))
      kid.on_draw = Some(fn(_w, p, r) {
        p.set_fill_color("#0000ff")
        p.fill_rect(0.0, 0.0, r.w, r.h)
      })
      card.append_child(kid)
      w
    }),
    40.0,
    40.0,
  )
  t.frame()
  // 卡片 (10,10)-(30,30) 圆角 6：正中蓝、角上父层红
  assert_eq(t.pixel(20, 20), (0, 0, 255, 255))
  assert_eq(t.pixel(10, 10), (255, 0, 0, 255))
  assert_eq(t.pixel(29, 29), (255, 0, 0, 255))
  t.finish()
}

///|
/// 视图连测④：backdrop_blur——玻璃件下已画内容的红黑分界被糊开。
test "视图④ 毛玻璃：分界像素红黑混合" {
  let t = mount(
    @widget.node_of_new(fn(w) {
      w.node.set_width(@yoga.fixed(40.0))
      w.node.set_height(@yoga.fixed(40.0))
      w.on_draw = Some(fn(_w, p, r) {
        p.set_fill_color("#ff0000")
        p.fill_rect(0.0, 0.0, 20.0, r.h)
        p.set_fill_color("#000000")
        p.fill_rect(20.0, 0.0, r.w - 20.0, r.h)
      })
      let glass = @widget.Widget::new()
      glass.name = "glass"
      glass.node.set_position(@yoga.Absolute)
      glass.node.set_top(@yoga.fixed(10.0))
      glass.node.set_left(@yoga.fixed(10.0))
      glass.node.set_width(@yoga.fixed(20.0))
      glass.node.set_height(@yoga.fixed(20.0))
      w.append_child(glass)
      @style.apply(glass, @style.merge_all([@style.style(backdrop_blur=4.0)]))
      w
    }),
    40.0,
    40.0,
  )
  t.frame()
  // 玻璃区内跨分界取点：红黑混出中间值（无模糊时是纯端值）；两色蓝通道
  // 都是 0，蓝通道全程贴地只作配方佐证
  let c = t.pixel(20, 15)
  assert_true(c.0 > 30 && c.0 < 220)
  assert_true(c.2 < 30)
  t.finish()
}

///|
/// 视图连测⑤：keyframes——起轴后首帧值经 style_for 落到像素。
test "视图⑤ 关键帧：起轴即画首帧近白" {
  let card_ref : Ref[@widget.Widget?] = Ref(None)
  let t = mount(
    @widget.node_of_new(fn(w) {
      w.node.set_width(@yoga.fixed(40.0))
      w.node.set_height(@yoga.fixed(40.0))
      w.on_draw = Some(fn(_w, p, r) {
        p.set_fill_color("#ff0000")
        p.fill_rect(0.0, 0.0, r.w, r.h)
      })
      let card = @widget.Widget::new()
      card.name = "kf"
      card.node.set_position(@yoga.Absolute)
      card.node.set_top(@yoga.fixed(10.0))
      card.node.set_left(@yoga.fixed(10.0))
      card.node.set_width(@yoga.fixed(20.0))
      card.node.set_height(@yoga.fixed(20.0))
      w.append_child(card)
      card_ref.val = Some(card)
      card.on_draw = Some(fn(cw, p, r) {
        // 组件经 style_for 取样式（关键帧 shown 在此盖状态桶）
        let st = @style.style_for(cw)
        p.set_fill_color(@style.color_of(st.background_color, "#ff0000"))
        p.fill_rect(0.0, 0.0, r.w, r.h)
      })
      w
    }),
    40.0,
    40.0,
  )
  let card = match card_ref.val {
    Some(c) => c
    None => abort("卡片没挂上")
  }
  assert_true(!@style.kf_running(card.id))
  @style.animate(
    card,
    [
      { at_ms: 0.0, style: @style.style(background_color="#ffffff") },
      { at_ms: 500.0, style: @style.style(background_color="#000000") },
    ],
  )
  assert_true(@style.kf_running(card.id))
  t.frame()
  // 首帧近白（真实时钟下起轴到出帧会走几毫秒）
  let c = t.pixel(20, 20)
  assert_true(c.0 >= 0xf0 && c.1 >= 0xf0 && c.2 >= 0xf0)
  @style.stop_animating(card)
  t.finish()
}
