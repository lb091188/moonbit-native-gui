// iconkit SVG 抽取与端到端测试。

test "svg→toml 端到端（方框铺满 ±1000）" {
  let svg = "<svg viewBox=\"0 0 20 20\"><symbol id=\"sq\"><path d=\"M0,0 L10,0 L10,10 L0,10 Z\"/></symbol></svg>"
  let (toml, w) = convert_svg(svg)
  assert_eq(w.length(), 0)
  assert_eq(
    toml,
    "# iconfont 图标数据（自动生成，勿手改）\n[icons]\n\"sq\" = \"M-1000,-1000L0,-1000L0,0L-1000,0Z\"\n",
  )
}

test "抽取多个 symbol + viewBox" {
  let svg = "<svg viewBox=\"0 0 20 20\"><defs><symbol id=\"a\"><path d=\"M0,0 L10,10\"/></symbol><symbol id=\"b\"><path d=\"M5,5 Z\"/></symbol></defs></svg>"
  let doc = parse_svg(svg)
  assert_eq(doc.paths.length(), 2)
  assert_eq(doc.paths[0].0, "a")
  assert_eq(doc.paths[1].0, "b")
  assert_eq(doc.viewbox.2, 20.0)
  assert_eq(doc.viewbox.3, 20.0)
}

test "顶层 path 无名走 auto" {
  let doc = parse_svg("<svg viewBox=\"0 0 10 10\"><path d=\"M1,1 L9,9\"/><path d=\"M2,2\"/></svg>")
  assert_eq(doc.paths.length(), 2)
  assert_eq(doc.paths[0].0, "icon_0")
  assert_eq(doc.paths[1].0, "icon_1")
}

test "无 viewBox 退默认 1024" {
  let doc = parse_svg("<svg><symbol id=\"x\"><path d=\"M0,0\"/></symbol></svg>")
  assert_eq(doc.viewbox.2, 1024.0)
}

test "svg_to_entries keep 子集筛选" {
  let svg = "<svg viewBox=\"0 0 20 20\"><symbol id=\"a\"><path d=\"M0,0 L10,10\"/></symbol><symbol id=\"b\"><path d=\"M2,2 L8,8\"/></symbol></svg>"
  let (all, _) = svg_to_entries(svg, None)
  assert_eq(all.length(), 2)
  let (sub, _) = svg_to_entries(svg, Some("b"))
  assert_eq(sub.length(), 1)
  assert_eq(sub[0].0, "b")
}

test "Q 折 C 换算数值正确" {
  // M0,10 Q5,-2 10,10 @ viewBox 0 0 20 20：中心(10,10)、scale100
  let (s, w) = convert_path("M0,10 Q5,-2 10,10 Z", 0.0, 0.0, 20.0, 20.0)
  assert_eq(w.length(), 0)
  assert_eq(s, "M-1000,0C-667,-800,-333,-800,0,0Z")
}
