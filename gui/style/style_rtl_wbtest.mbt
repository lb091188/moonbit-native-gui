// RTL 布局镜像映射的纯函数回归（yoga 枚举无 Eq，用 match 归约成 Bool）。

fn is_rowreverse(v : @yoga.FlexDirection) -> Bool {
  match v {
    @yoga.FlexDirection::RowReverse => true
    _ => false
  }
}

fn is_row(v : @yoga.FlexDirection) -> Bool {
  match v {
    @yoga.FlexDirection::Row => true
    _ => false
  }
}

fn is_column(v : @yoga.FlexDirection) -> Bool {
  match v {
    @yoga.FlexDirection::Column => true
    _ => false
  }
}

fn is_flexend_j(v : @yoga.JustifyContent) -> Bool {
  match v {
    @yoga.JustifyContent::FlexEnd => true
    _ => false
  }
}

fn is_center_j(v : @yoga.JustifyContent) -> Bool {
  match v {
    @yoga.JustifyContent::Center => true
    _ => false
  }
}

fn is_flexstart_a(v : @yoga.AlignItems) -> Bool {
  match v {
    @yoga.AlignItems::FlexStart => true
    _ => false
  }
}

fn is_stretch_a(v : @yoga.AlignItems) -> Bool {
  match v {
    @yoga.AlignItems::Stretch => true
    _ => false
  }
}

test "mirror_flex：row 翻列不翻，rtl=false 原样" {
  assert_eq(is_rowreverse(mirror_flex(@yoga.FlexDirection::Row, true)), true)
  assert_eq(is_row(mirror_flex(@yoga.FlexDirection::RowReverse, true)), true)
  assert_eq(is_column(mirror_flex(@yoga.FlexDirection::Column, true)), true)
  assert_eq(is_row(mirror_flex(@yoga.FlexDirection::Row, false)), true)
}

test "mirror_justify / mirror_align：起终互换，其它不动" {
  assert_eq(is_flexend_j(mirror_justify(@yoga.JustifyContent::FlexStart, true)), true)
  assert_eq(is_center_j(mirror_justify(@yoga.JustifyContent::Center, true)), true)
  assert_eq(is_flexstart_a(mirror_align(@yoga.AlignItems::FlexEnd, true)), true)
  assert_eq(is_stretch_a(mirror_align(@yoga.AlignItems::Stretch, false)), true)
}
