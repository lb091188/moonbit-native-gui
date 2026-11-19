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
      @style.apply(
        glass,
        @style.merge_all([@style.style(backdrop_blur=4.0, border_radius=8.0)]),
      )
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
  // 圆角弧外的角像素不被糊晕（blur 只作用弧内）：(11,11) 在 r=8 弧外，
  // 下层是纯红
  let corner = t.pixel(11, 11)
  assert_true(
    corner.0 >= 230,
    msg="弧外角被糊（r=\{corner.0}），下层露深晕",
  )
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
      card.on_draw = Some(fn(_w, p, r) {
        // 组件经 style_for 取样式（关键帧 shown 在此盖状态桶）
        let st = @style.style_for(_w)
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

///|
/// 视图连测⑥：hover 桶的 transform 经绘制期槽刷新进槽——移入放大上浮、
/// 移出回落；放大/上浮的溢出边不被自身裁切吃掉（rect 外读到卡色）。
test "视图⑥ 悬停动态：桶值进槽、溢出可见、移出回落" {
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
      card.name = "hov"
      card.node.set_position(@yoga.Absolute)
      card.node.set_top(@yoga.fixed(10.0))
      card.node.set_left(@yoga.fixed(10.0))
      card.node.set_width(@yoga.fixed(20.0))
      card.node.set_height(@yoga.fixed(20.0))
      card.on_draw = Some(fn(_w, p, r) {
        p.set_fill_color("#0000ff")
        p.fill_rect(0.0, 0.0, r.w, r.h)
      })
      w.append_child(card)
      @style.apply(
        card,
        @style.merge_all([@style.style(transition_ms=0.0).hover(scale_x=1.2, translate_y=-4.0)]),
      )
      card_ref.val = Some(card)
      w
    }),
    40.0,
    40.0,
  )
  let card = match card_ref.val {
    Some(c) => c
    None => abort("卡片没挂上")
  }
  t.frame()
  assert_true(!(card.tr_sx != 1.0) && !(card.tr_ty != 0.0))
  // 移入：桶值经槽刷新落槽，上浮后卡顶越过自身矩形（rect 外读到卡色）
  t.root.set_hover(card.id)
  t.frame()
  assert_true(card.tr_sx != 1.0)
  assert_eq(card.tr_ty, -4.0)
  assert_eq(t.pixel(20, 7), (0, 0, 255, 255))
  // 移出：槽刷新回恒等，像素回原位（rect 外回到父层红）
  t.root.set_hover(0)
  t.frame()
  assert_eq(card.tr_sx, 1.0)
  assert_eq(card.tr_ty, 0.0)
  assert_eq(t.pixel(20, 7), (255, 0, 0, 255))
  t.finish()
}

///|
/// 视图连测⑦：关键帧轴上的 rotate 经槽刷新进槽——轴上值偏离 0，停轴回落。
test "视图⑦ 关键帧 rotate：轴上进槽、停轴回落" {
  let card_ref : Ref[@widget.Widget?] = Ref(None)
  let t = mount(
    @widget.node_of_new(fn(w) {
      w.node.set_width(@yoga.fixed(40.0))
      w.node.set_height(@yoga.fixed(40.0))
      let card = @widget.Widget::new()
      card.name = "kfr"
      card.node.set_position(@yoga.Absolute)
      card.node.set_top(@yoga.fixed(10.0))
      card.node.set_left(@yoga.fixed(10.0))
      card.node.set_width(@yoga.fixed(20.0))
      card.node.set_height(@yoga.fixed(10.0))
      w.append_child(card)
      @style.apply(card, @style.merge_all([@style.style(transition_ms=0.0)]))
      card_ref.val = Some(card)
      w
    }),
    40.0,
    40.0,
  )
  let card = match card_ref.val {
    Some(c) => c
    None => abort("卡片没挂上")
  }
  // 帧序起轴即 90°（起轴时刻 e=0 取首帧，断言不与时钟抖动纠缠）
  @style.animate(
    card,
    [
      { at_ms: 0.0, style: @style.style(rotate=90.0) },
      { at_ms: 100.0, style: @style.style(rotate=0.0) },
    ],
  )
  t.frame()
  let _ = t.rect(t.by_name("kfr"))
  assert_true(card.tr_rot > 0.0 && card.tr_rot <= 90.0)
  assert_true(card.has_transform())
  @style.stop_animating(card)
  t.frame()
  assert_eq(card.tr_rot, 0.0)
  t.finish()
}

///|
/// 视图连测⑧：变换溢出可见——40×10 横条旋转 90° 后越出自身矩形，rect 外
/// 读到卡色；原位内容随变换转走。裁的是未变换矩形，变换控件整体豁免。
test "视图⑧ 变换溢出：旋转后越出自身矩形仍可见" {
  let t = mount(
    @widget.node_of_new(fn(w) {
      w.node.set_width(@yoga.fixed(40.0))
      w.node.set_height(@yoga.fixed(40.0))
      w.on_draw = Some(fn(_w, p, r) {
        p.set_fill_color("#ff0000")
        p.fill_rect(0.0, 0.0, r.w, r.h)
      })
      let bar = @widget.Widget::new()
      bar.name = "bar"
      bar.node.set_position(@yoga.Absolute)
      bar.node.set_top(@yoga.fixed(15.0))
      bar.node.set_left(@yoga.fixed(0.0))
      bar.node.set_width(@yoga.fixed(40.0))
      bar.node.set_height(@yoga.fixed(10.0))
      bar.on_draw = Some(fn(_w, p, r) {
        p.set_fill_color("#0000ff")
        p.fill_rect(0.0, 0.0, r.w, r.h)
      })
      w.append_child(bar)
      @style.apply(bar, @style.merge_all([@style.style(rotate=90.0)]))
      w
    }),
    40.0,
    40.0,
  )
  t.frame()
  // rect (0,15)-(40,25)；转 90° 后成竖条 (15..25, 0..40)
  assert_eq(t.pixel(16, 5), (0, 0, 255, 255))
  assert_eq(t.pixel(5, 20), (255, 0, 0, 255))
  assert_eq(t.pixel(16, 20), (0, 0, 255, 255))
  t.finish()
}

///|
/// 视图连测⑨：变换控件 z 序提升——树序在前的变换卡溢出区盖住树序在后的
/// 兄弟（web transform 建 stacking context 同款：同 z 时变换排后画）。
test "视图⑨ 变换提升：旋转溢出区盖住后声明的兄弟" {
  let t = mount(
    @widget.node_of_new(fn(w) {
      w.node.set_width(@yoga.fixed(40.0))
      w.node.set_height(@yoga.fixed(40.0))
      w.on_draw = Some(fn(_w, p, r) {
        p.set_fill_color("#ff0000")
        p.fill_rect(0.0, 0.0, r.w, r.h)
      })
      // A 树序在前：横条转 90° 成竖条 (15..25, 0..40)
      let a = @widget.Widget::new()
      a.node.set_position(@yoga.Absolute)
      a.node.set_top(@yoga.fixed(15.0))
      a.node.set_left(@yoga.fixed(0.0))
      a.node.set_width(@yoga.fixed(40.0))
      a.node.set_height(@yoga.fixed(10.0))
      a.on_draw = Some(fn(_w, p, r) {
        p.set_fill_color("#0000ff")
        p.fill_rect(0.0, 0.0, r.w, r.h)
      })
      w.append_child(a)
      @style.apply(a, @style.merge_all([@style.style(rotate=90.0)]))
      // B 树序在后：8×8 红块压在 A 竖条中央——无提升时 B 后画盖住 A
      let b = @widget.Widget::new()
      b.node.set_position(@yoga.Absolute)
      b.node.set_top(@yoga.fixed(16.0))
      b.node.set_left(@yoga.fixed(16.0))
      b.node.set_width(@yoga.fixed(8.0))
      b.node.set_height(@yoga.fixed(8.0))
      b.on_draw = Some(fn(_w, p, r) {
        p.set_fill_color("#ff0000")
        p.fill_rect(0.0, 0.0, r.w, r.h)
      })
      w.append_child(b)
      w
    }),
    40.0,
    40.0,
  )
  t.frame()
  // A 提升后画：交叠区读到 A 的蓝，B 只在 A 竖条外露
  assert_eq(t.pixel(20, 20), (0, 0, 255, 255))
  assert_eq(t.pixel(19, 17), (0, 0, 255, 255))
  // B 在竖条外的部分照常可见
  assert_eq(t.pixel(26, 20), (255, 0, 0, 255))
  t.finish()
}

///|
/// 视图连测⑩：毛玻璃增量重绘稳定性——玻璃卡被局部重画时 blur 源必须是
/// 干净的（位图现状是上帧糊值，重糊会逐帧加深/跳变）。
test "视图⑩ 毛玻璃增量重绘：帧间像素稳定" {
  let glass_ref : Ref[@widget.Widget?] = Ref(None)
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
      @style.apply(
        glass,
        @style.merge_all([@style.style(backdrop_blur=4.0, border_radius=8.0)]),
      )
      glass_ref.val = Some(glass)
      w
    }),
    40.0,
    40.0,
  )
  let _ = match glass_ref.val {
    Some(g) => g
    None => abort("玻璃卡没挂上")
  }
  t.frame()
  let bm1 = match t.bitmap() {
    Some(b) => b
    None => abort("没位图")
  }
  let c1 = bm1.pixel(17, 15)
  let p1 = (c1.r, c1.g, c1.b, c1.a)
  // 模拟增量帧：保留上一帧位图，只重画玻璃卡（clip=玻璃矩形）
  let rect = match t.rect(t.by_name("glass")) {
    Some(rr) => rr
    None => abort("没矩形")
  }
  let bm2 = bm1.copy()
  let p2 = @render.Painter::new(bm2)
  t.root.paint_at(p2, 0.0, 0.0, clip=Some(rect))
  p2.end()
  let c2 = bm2.pixel(17, 15)
  let q2 = (c2.r, c2.g, c2.b, c2.a)
  // 再来一遍：三帧同值才稳定（现在重糊会逐帧加深，红通道往中间塌）
  let bm3 = bm2.copy()
  let p3 = @render.Painter::new(bm3)
  t.root.paint_at(p3, 0.0, 0.0, clip=Some(rect))
  p3.end()
  let c3 = bm3.pixel(17, 15)
  let q3 = (c3.r, c3.g, c3.b, c3.a)
  assert_true(
    (q2.0 - p1.0).abs() <= 2 &&
    (q3.0 - p1.0).abs() <= 2,
  )
  t.finish()
}
