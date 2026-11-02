// 主题 JSON 加载：字段名白名单 = `Theme` 字段（20 颜色 + chart_palette），
// 只承载固定字段名的值映射，不引属性名解析器。未知字段报错；颜色值必须
// 可解析 hex（`#rgb` / `#rrggbb` / `#rrggbbaa`）；允许部分缺省，缺省项
// 回落 base。应用自行决定加载时机与文件来源。

///|
let theme_color_keys : Array[String] = [
  "primary", "primary_light", "primary_hover", "danger_hover",
  "success", "success_light", "warning", "warning_light",
  "danger", "danger_light", "info", "info_light",
  "text_primary", "text_regular", "text_secondary",
  "border", "fill_hover", "fill_zebra", "bg_page", "bg_panel",
]

///|
/// 单个颜色字段取值：字符串且可解析 hex 才收。
fn theme_json_color(name : String, v : @sys.VscJson) -> Result[String, String] {
  match v {
    @sys.VscJStr(s) =>
      match parse_hex(s) {
        Some(_) => Ok(s)
        None => Err("\{name}: 非法颜色值「\{s}」（需 #rgb / #rrggbb / #rrggbbaa）")
      }
    _ => Err("\{name}: 必须是颜色字符串")
  }
}

///|
/// 从 JSON 文本加载整套主题。顶层必须是对象；未知字段、类型不符、颜色值
/// 非法均报错（错误信息带字段名）。未出现的字段取 `base` 对应值（暗色基底
/// 传 `base=dark_theme()`）；`chart_palette` 缺省同样回落 base，显式空数组
/// 合法（绘制期回落主色）。
pub fn from_json(
  src : String,
  base? : Theme = default_theme(),
) -> Result[Theme, String] {
  let j = match @sys.vsc_json_parse(src) {
    Some(j) => j
    None => return Err("JSON 解析失败")
  }
  let pairs = match j {
    @sys.VscJObj(pairs) => pairs
    _ => return Err("主题 JSON 顶层必须是对象")
  }
  let vals : Map[String, String] = Map([])
  let mut palette : Array[String]? = None
  for kv in pairs {
    let k = kv.0
    let v = kv.1
    if k == "chart_palette" {
      match v {
        @sys.VscJArr(xs) => {
          let cs : Array[String] = []
          for x in xs {
            match theme_json_color("chart_palette", x) {
              Ok(c) => cs.push(c)
              Err(e) => return Err(e)
            }
          }
          palette = Some(cs)
        }
        _ => return Err("chart_palette: 必须是颜色字符串数组")
      }
      continue
    }
    let mut known = false
    for key in theme_color_keys {
      if key == k {
        known = true
        break
      }
    }
    if !known {
      return Err("未知字段：" + k)
    }
    match theme_json_color(k, v) {
      Ok(c) => vals.set(k, c)
      Err(e) => return Err(e)
    }
  }
  Ok({
    primary: vals.get_or_default("primary", base.primary),
    primary_light: vals.get_or_default("primary_light", base.primary_light),
    primary_hover: vals.get_or_default("primary_hover", base.primary_hover),
    danger_hover: vals.get_or_default("danger_hover", base.danger_hover),
    success: vals.get_or_default("success", base.success),
    success_light: vals.get_or_default("success_light", base.success_light),
    warning: vals.get_or_default("warning", base.warning),
    warning_light: vals.get_or_default("warning_light", base.warning_light),
    danger: vals.get_or_default("danger", base.danger),
    danger_light: vals.get_or_default("danger_light", base.danger_light),
    info: vals.get_or_default("info", base.info),
    info_light: vals.get_or_default("info_light", base.info_light),
    text_primary: vals.get_or_default("text_primary", base.text_primary),
    text_regular: vals.get_or_default("text_regular", base.text_regular),
    text_secondary: vals.get_or_default("text_secondary", base.text_secondary),
    border: vals.get_or_default("border", base.border),
    fill_hover: vals.get_or_default("fill_hover", base.fill_hover),
    fill_zebra: vals.get_or_default("fill_zebra", base.fill_zebra),
    bg_page: vals.get_or_default("bg_page", base.bg_page),
    bg_panel: vals.get_or_default("bg_panel", base.bg_panel),
    chart_palette: match palette {
      Some(p) => p
      None => base.chart_palette
    },
  })
}
