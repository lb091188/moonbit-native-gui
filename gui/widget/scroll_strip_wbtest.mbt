// 滚动条带重绘回归：本帧唯一脏区是滚动视口且位移为整数时，按「平移复用上一帧
// + 只重绘新露条带」出画——视口外像素必须不动、平移内容必须对位、条带必须更新；
// 不满足快路径条件（非白名单 kind / 非整数位移）时回退视口整块重绘，像素同样要对。

///|
fn strip_host(w : Int32, h : Int32) -> WindowHost {
  let root = Widget::new()
  root.set_size(w.to_double(), h.to_double())
  let a : WindowHost = {
    session: @shell.fake_session(900, @shell.host_new_wid(), false, w, h),
    root,
    focus: FocusStack::new(),
    host: make_overlay_host(root),
    closed: false,
    canvas: None,
    key_fallthrough: [],
    dirty_rect: None,
    dirty_full: false,
    scroll_pending: None,
    scroll_touch: false,
    system_keys: true,
    hidden_cbs: [],
    shown_cbs: [],
    close_cbs: [],
    page_fill: false,
    remember_id: "",
    painted_once: false,
    first_retry_left: 0,
    frame_untracked: false,
  }
  host_add_app(a)
  a
}

///|
fn strip_row(h : Double, color : String) -> Widget {
  let row = Widget::new()
  row.node.set_width(@yoga.percent(100.0))
  row.node.set_height(@yoga.fixed(h))
  row.on_draw = Some(fn(
    _w : Widget,
    p : @render.Painter,
    r : Rect,
  ) -> Unit {
    p.set_fill_color(color)
    p.fill_rect(0.0, 0.0, r.w, r.h)
  })
  row
}

///|
fn strip_frame(a : WindowHost) -> @render.Bitmap {
  a.paint_frame()
  match last_frame_bitmap() {
    (Some(bm), _) => bm
    _ => abort("没有最近帧")
  }
}

///|
fn strip_rgb(bm : @render.Bitmap, x : Int32, y : Int32) -> (Int32, Int32, Int32) {
  let c = bm.pixel(x, y)
  (c.r, c.g, c.b)
}

///|
/// 建一扇 300×200 假窗：左上角一块 20×20 红标记，右下 200×120 滚动视口
/// （12 行 × 20 高，行色按 红/绿/蓝 循环）。`kind` 决定视口与内容容器的
/// kind，结构满足条带白名单（内容 + 纵向滚动条）。
fn strip_scene(kind : String) -> (WindowHost, Widget, Widget) {
  let a = strip_host(300, 200)
  let root = a.root
  let marker = Widget::new()
  marker.node.set_position(@yoga.Absolute)
  marker.node.set_left(@yoga.fixed(5.0))
  marker.node.set_top(@yoga.fixed(5.0))
  marker.node.set_width(@yoga.fixed(20.0))
  marker.node.set_height(@yoga.fixed(20.0))
  marker.on_draw = Some(fn(
    _w : Widget,
    p : @render.Painter,
    r : Rect,
  ) -> Unit {
    p.set_fill_color("#FF0000")
    p.fill_rect(0.0, 0.0, r.w, r.h)
  })
  root.append_child(marker)
  let vp = Widget::new()
  vp.kind = kind
  vp.clip_content = true
  vp.node.set_position(@yoga.Absolute)
  vp.node.set_left(@yoga.fixed(40.0))
  vp.node.set_top(@yoga.fixed(30.0))
  vp.node.set_width(@yoga.fixed(200.0))
  vp.node.set_height(@yoga.fixed(120.0))
  vp.node.set_flex_direction(@yoga.Column)
  let inner = Widget::new()
  inner.kind = if kind == "ui-virt-list" {
    "ui-virt-list-content"
  } else {
    "ui-scroll-content"
  }
  inner.node.set_position(@yoga.Relative)
  inner.node.set_flex_direction(@yoga.Column)
  inner.node.set_flex_shrink(0.0)
  inner.node.set_width(@yoga.percent(100.0))
  inner.node.set_top(@yoga.fixed(0.0))
  vp.append_child(inner)
  let colors = ["#FF0000", "#00FF00", "#0000FF"]
  for i = 0; i < 12; i = i + 1 {
    inner.append_child(strip_row(20.0, colors[i % 3]))
  }
  // 纵向滚动条占位：结构白名单要求内容之外只有这一条（kind 带标记）
  let bar = Widget::new()
  bar.kind = "ui-scroll-bar"
  bar.node.set_position(@yoga.Absolute)
  bar.node.set_top(@yoga.fixed(0.0))
  bar.node.set_right(@yoga.fixed(0.0))
  bar.node.set_width(@yoga.fixed(8.0))
  bar.node.set_height(@yoga.fixed(120.0))
  bar.on_draw = Some(fn(
    _w : Widget,
    p : @render.Painter,
    r : Rect,
  ) -> Unit {
    p.set_fill_color("#FFFF00")
    p.fill_rect(0.0, 0.0, r.w, r.h)
  })
  vp.append_child(bar)
  root.append_child(vp)
  (a, vp, inner)
}

///|
test "滚动条带快路径：视口外不动、内容平移对位、新露条带重绘" {
  host_reset()
  let (a, vp, inner) = strip_scene("ui-virt-list")
  strip_hits.val = 0
  let bm1 = strip_frame(a)
  // 基线：标记红、视口顶行（行 0）红
  assert_eq(strip_rgb(bm1, 8, 8), (255, 0, 0))
  assert_eq(strip_rgb(bm1, 50, 35), (255, 0, 0))
  // 滚动 20px（内容上移）：行 1（绿）应到视口顶，底部新露行 6（红）
  inner.node.set_top(@yoga.fixed(-20.0))
  a.session.dirty = true
  a.dirty_rect = Some(vp.rect)
  a.scroll_pending = Some((vp.id, 0.0 - 20.0, 20.0))
  let bm2 = strip_frame(a)
  assert_eq(strip_hits.val, 1)
  assert_eq(strip_rgb(bm2, 8, 8), (255, 0, 0)) // 视口外标记未被平移覆盖
  assert_eq(strip_rgb(bm2, 50, 35), (0, 255, 0)) // 平移对位：行 1 到顶
  assert_eq(strip_rgb(bm2, 50, 145), (255, 0, 0)) // 底部新露行 6 已重绘
  // 滚动条列整列重画：拇指占位仍是黄色
  assert_eq(strip_rgb(bm2, 236, 60), (255, 255, 0))
}

///|
test "滚动条带快路径：普通滚动容器（ui-scroll-view）同样命中" {
  host_reset()
  let (a, vp, inner) = strip_scene("ui-scroll-view")
  strip_hits.val = 0
  let bm1 = strip_frame(a)
  assert_eq(strip_rgb(bm1, 50, 35), (255, 0, 0))
  inner.node.set_top(@yoga.fixed(-20.0))
  a.session.dirty = true
  a.dirty_rect = Some(vp.rect)
  // 普通滚动容器没有虚拟行余量：余量 0，条带只需盖住新露的 20px
  a.scroll_pending = Some((vp.id, 0.0 - 20.0, 0.0))
  let bm2 = strip_frame(a)
  assert_eq(strip_hits.val, 1)
  assert_eq(strip_rgb(bm2, 8, 8), (255, 0, 0))
  assert_eq(strip_rgb(bm2, 50, 35), (0, 255, 0))
  assert_eq(strip_rgb(bm2, 50, 145), (255, 0, 0))
}

///|
test "滚动条带快路径：视口里多了外来子件就退回普通重绘" {
  host_reset()
  let (a, vp, inner) = strip_scene("ui-scroll-view")
  // 模拟调用方往视口挂浮层：结构白名单不认，条带宽高比整块平移更安全
  let extra = Widget::new()
  extra.kind = "ui-foreign-overlay"
  extra.node.set_position(@yoga.Absolute)
  extra.node.set_left(@yoga.fixed(0.0))
  extra.node.set_top(@yoga.fixed(0.0))
  vp.append_child(extra)
  strip_hits.val = 0
  let _ = strip_frame(a)
  inner.node.set_top(@yoga.fixed(-20.0))
  a.session.dirty = true
  a.dirty_rect = Some(vp.rect)
  a.scroll_pending = Some((vp.id, 0.0 - 20.0, 0.0))
  let bm2 = strip_frame(a)
  assert_eq(strip_hits.val, 0)
  // 回退路径像素同样正确
  assert_eq(strip_rgb(bm2, 8, 8), (255, 0, 0))
  assert_eq(strip_rgb(bm2, 50, 35), (0, 255, 0))
  assert_eq(strip_rgb(bm2, 50, 145), (255, 0, 0))
}
