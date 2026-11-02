// iconkit 内核往返测试：解析→归一化→变换→序列化，钉死与 fill_icon_path 同口径的产出。

test "M/L/Z 精确目标串" {
  let (s, w) = convert_path("M0,0 L10,0 L10,10 Z", 0.0, 0.0, 20.0, 20.0)
  assert_eq(s, "M-1000,-1000L0,-1000L0,0Z")
  assert_eq(w.length(), 0)
}

test "Q 折成 C：一个 M + 一个 C（6 参数）" {
  let (segs, _) = parse_path("M0,0 Q10,0 10,10")
  assert_eq(segs.length(), 2)
  assert_eq(segs[1].cmd, 'C')
  assert_eq(segs[1].args.length(), 6)
}

test "H/V 折成 L：沿用当前点补全另一轴" {
  let (segs, _) = parse_path("M0,0 H10 V10")
  assert_eq(segs.length(), 3)
  assert_eq(segs[1].cmd, 'L')
  assert_eq(segs[2].args[0], 10.0)
  assert_eq(segs[2].args[1], 10.0)
}

test "相对命令解析成绝对" {
  // m 5,5 相对起点(0,0) → 绝对 M5,5；再 l 5,0 → L10,5
  let (segs, _) = parse_path("M0,0 m5,5 l5,0")
  assert_eq(segs.length(), 3)
  assert_eq(segs[1].args[0], 5.0)
  assert_eq(segs[2].args[0], 10.0)
  assert_eq(segs[2].args[1], 5.0)
}

test "圆弧 v1 记告警不产段" {
  let (segs, w) = parse_path("M0,0 A5 5 0 0 1 10 10")
  assert_eq(segs.length(), 1)
  assert_eq(w.length(), 1)
}

test "to_toml 精确形态" {
  let toml = to_toml([("home", "M-1000,-1000L0,0Z")])
  assert_eq(
    toml,
    "# iconfont 图标数据（自动生成，勿手改）\n[icons]\n\"home\" = \"M-1000,-1000L0,0Z\"\n",
  )
}
