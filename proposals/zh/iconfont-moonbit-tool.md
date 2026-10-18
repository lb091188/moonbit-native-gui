# iconfont 转化方案：MoonBit 工具 + SVG 输入 + TOML 数据

## 〇、生态可复用包（moon search 结果）

MoonBit 生态已有成熟的 SVG/XML 解析和 TOML 序列化库，无需从零造轮子：

| 能力 | 推荐包 | 下载量 | 用途 |
|------|--------|--------|------|
| **SVG path 解析** | `PerfectPan/svgo/path` | 36 | `parse` 把 `d="..."` 转成 `Segment` 数组，`apply_matrix` 做仿射变换，`stringify` 序列化回去 |
| **SVG/XML 解析** | `PerfectPan/svgo/xml` | 36 | `parse` 把 SVG 文本转成 `Document/Element` 树，`each_element` 遍历 |
| **SVG 完整解析** | `mizchi/svg` | 41,677 | 全功能 SVG 场景图 + 解析器 + 光栅化器，含 `PathCommand` 类型 |
| **XML pull 解析** | `Milky2018/xml` | 54,620 | 轻量 pull 式 XML 解析器，适合大文件流式处理 |
| **TOML 解析/序列化** | `moonbit-community/toml` | 15,121 | TOML 1.1 完整支持，`parse` / `to_string` / `TomlValue` |
| **TOML 解析（社区）** | `bobzhang/toml` | 128,077 | 同上的早期版本，下载量最大 |
| **SVG 优化** | `PerfectPan/svgo` | 36 | svgo 兼容的路径优化管线，可减小路径数据体积 |

### 推荐依赖组合

```
转化工具（开发时）：
  PerfectPan/svgo/xml    → 解析 SVG 文档，提取 <path> 元素
  PerfectPan/svgo/path   → 解析 path d="..."，坐标变换，路径优化
  moonbit-community/toml → 输出 TOML 数据文件

运行时（应用内）：
  moonbit-community/toml → 加载 TOML 图标数据
  （无其他依赖，路径绘制复用现有 fill_icon_path）
```

## 一、核心思路

**纯 MoonBit 实现，SVG 输入，TOML 输出，复用生态包**：
1. 读取 iconfont 包中的 SVG 文件（每个图标一个）
2. 用 `PerfectPan/svgo/xml` 解析 SVG，提取 `<path d="...">`
3. 用 `PerfectPan/svgo/path` 解析路径 + 仿射变换到千分定点坐标
4. 用 `moonbit-community/toml` 输出 TOML 数据文件
5. 运行时加载 TOML，用现有 `fill_icon_path` 绘制

```
iconfont 包（iconfont.cn 下载）
  ├── iconfont.svg      ← 工具读取（所有图标合并在一个 SVG）
  ├── icons/            ← 或读取单个 SVG 文件
  │   ├── home.svg
  │   ├── user.svg
  │   └── ...
  └── iconfont.json     ← 可选，读取图标名称映射

MoonBit 转化工具（gui/scripts/iconfont_convert.mbt）
  ↓
解析 SVG path → 坐标变换 → 输出 TOML

iconfont.toml（外部数据文件）
  [icons]
  home = "M0 -400 L0 400 L400 400 ..."
  user = "M0 -500 Q300 -500 300 -200 ..."

运行时加载（gui/icons/iconfont_runtime.mbt）
  ↓
读取 TOML → 解析路径 → fill_icon_path 绘制
```

## 二、SVG 路径格式分析

### 2.1 SVG path 指令
SVG 的 `<path d="...">` 使用与现有系统相似的路径指令：

| SVG 指令 | 含义 | 对应现有格式 |
|---------|------|-------------|
| `M x y` | 移动到 | `M x y` |
| `L x y` | 直线到 | `L x y` |
| `Q x1 y1 x2 y2` | 二次贝塞尔 | `Q x1 y1 x2 y2` |
| `C x1 y1 x2 y2 x3 y3` | 三次贝塞尔 | `C x1 y1 x2 y2 x3 y3` |
| `Z` | 闭合 | `Z` |
| `H x` | 水平线 | 转为 `L x y` |
| `V y` | 垂直线 | 转为 `L x y` |

### 2.2 坐标系差异
```
SVG 坐标系：
  - 原点在左上角
  - Y 轴向下
  - 单位：像素（viewBox 定义范围，如 0 0 1024 1024）

现有图标坐标系：
  - 原点在图标中心
  - Y 轴向下（与 SVG 同向）
  - 单位：千分定点（±1000）

变换公式：
  px = (x - cx) * scale
  py = (y - cy) * scale
  scale = 1000 / (viewBox_size / 2)
  cx = viewBox_size / 2
  cy = viewBox_size / 2
```

## 三、MoonBit 转化工具实现

### 3.1 依赖配置

```json
// gui/scripts/moon.pkg.json（转化工具）
{
  "import": [
    { "path": "PerfectPan/svgo/xml", "alias": "svgxml" },
    { "path": "PerfectPan/svgo/path", "alias": "svgpath" },
    { "path": "moonbit-community/toml", "alias": "toml" }
  ]
}
```

### 3.2 SVG 解析（复用 PerfectPan/svgo/xml）

```moonbit
// gui/scripts/svg_parser.mbt

/// 从 SVG 文件提取所有 <path> 元素（id + d 属性）
pub(all) struct SvgPath {
  name : String  // 图标名称（从 id 属性或文件名提取）
  data : String  // SVG path d 属性
}

pub fn parse_svg_file(content : String) -> Array[SvgPath] {
  let doc = @svgxml.parse(content)
  let paths = []
  
  // 遍历所有 <path> 元素
  @svgxml.each_element(doc, fn(elem) {
    if elem.tag == "path" {
      let d = elem.attr("d") ?? ""
      let id = elem.attr("id") ?? ("icon_" + paths.length().to_string())
      paths.push({ name: id, data: d })
    }
    // iconfont.svg 常用 <symbol id="xxx"><path d="..."/></symbol>
    if elem.tag == "symbol" {
      let id = elem.attr("id") ?? ""
      for child in elem.children {
        if child.tag == "path" {
          let d = child.attr("d") ?? ""
          paths.push({ name: id, data: d })
        }
      }
    }
  })
  
  paths
}
```

### 3.3 路径转换（复用 PerfectPan/svgo/path）

```moonbit
// gui/scripts/path_converter.mbt

/// 将 SVG path d 属性转为千分定点字符串
/// 复用 svgo/path 的 parse → 坐标变换 → stringify
pub fn svg_path_to_iconfont(
  d : String,
  viewBox : (Double, Double, Double, Double),  // (x, y, w, h)
) -> String {
  let (_, _, vw, vh) = viewBox
  
  // 1. 解析 SVG path → Segment 数组
  let segments = @svgpath.parse(d)
  
  // 2. 构造仿射变换矩阵
  //    SVG 坐标 → 千分定点坐标
  //    scale = 2000 / max(vw, vh)
  //    offset = (-cx * scale, -cy * scale)
  let side = if vw > vh { vw } else { vh }
  let scale = 2000.0 / side
  let cx = vw / 2.0
  let cy = vh / 2.0
  
  // 3. 用 svgo/path 的 apply_matrix 做仿射变换
  let matrix = @svgpath.Matrix::new(
    scale, 0.0,    // a, b
    0.0, scale,    // c, d
    -cx * scale,   // e (translate x)
    -cy * scale,   // f (translate y)
  )
  let transformed = @svgpath.apply_matrix(segments, matrix)
  
  // 4. 序列化为路径字符串
  @svgpath.stringify(transformed)
}
```

### 3.4 TOML 输出（复用 moonbit-community/toml）

```moonbit
// gui/scripts/toml_writer.mbt

/// 输出 TOML 格式图标数据
pub fn write_icon_toml(icons : Map[String, String]) -> String {
  // 构造 TomlValue
  let table = Map::new()
  let icons_table = Map::new()
  
  for (name, path) in icons {
    icons_table.set(name, TomlValue::String(path))
  }
  table.set("icons", TomlValue::Table(icons_table))
  
  TomlValue::Table(table).to_string()
}

/// 写入文件
pub fn save_icon_toml(icons : Map[String, String], path : String) -> Unit {
  let content = write_icon_toml(icons)
  @fs.write(path, content)
}
```

### 3.5 主程序

```moonbit
// gui/scripts/iconfont_convert.mbt

fn main {
  let args = @env.args()
  if args.length() < 3 {
    println("用法：moon run gui/scripts/iconfont_convert -- <input.svg> <output.toml>")
    return
  }
  
  let input_path = args[1]
  let output_path = args[2]
  
  // 1. 读取 SVG
  let svg_content = @fs.read(input_path)
  
  // 2. 解析 SVG 提取路径
  let paths = parse_svg_file(svg_content)
  
  // 3. 转换路径到千分定点
  let icons = Map::new()
  for path in paths {
    let path_str = svg_path_to_iconfont(path.data, (0.0, 0.0, 1024.0, 1024.0))
    icons.set(path.name, path_str)
  }
  
  // 4. 输出 TOML
  save_icon_toml(icons, output_path)
  
  println("转化完成：" + icons.size().to_string() + " 个图标 → " + output_path)
}
```

## 四、运行时加载器

```moonbit
// gui/icons/iconfont_runtime.mbt
// moon.pkg.json 依赖：moonbit-community/toml

/// 全局图标数据
let g_iconfont_data : Ref[Map[String, String]?] = Ref::new(None)

/// 初始化：加载 TOML 数据文件
pub fn init_iconfont(toml_path : String) -> Unit {
  match load_toml(toml_path) {
    Some(data) => g_iconfont_data.set(Some(data))
    None => println("警告：无法加载 iconfont 数据：" + toml_path)
  }
}

/// 解析 TOML 文件（复用 moonbit-community/toml）
fn load_toml(path : String) -> Map[String, String]? {
  let content = @fs.read(path)?
  let root = @toml.parse(content)?
  
  // 从 [icons] 段提取 KV
  let data = Map::new()
  match root.get("icons") {
    Some(TomlValue::Table(icons)) => {
      for (key, value) in icons {
        match value {
          TomlValue::String(path_str) => data.set(key, path_str)
          _ => ()
        }
      }
    }
    _ => return None
  }
  
  Some(data)
}

/// 绘制 iconfont 图标
pub fn draw_iconfont(
  painter : Painter,
  name : String,
  cx : Double,
  cy : Double,
  s : Double,
  color : Color,
) -> Unit {
  match !g_iconfont_data {
    Some(data) => {
      match data.get(name) {
        Some(path_str) => {
          let commands = parse_icon_path(path_str)
          fill_icon_path(painter, commands, cx, cy, s, color)
        }
        None => println("警告：未找到图标：" + name)
      }
    }
    None => println("警告：iconfont 未初始化")
  }
}

/// 解析千分定点路径串（复用现有 icons.mbt 的解析逻辑）
fn parse_icon_path(path_str : String) -> Array[IconCommand] {
  // 与 icons.mbt 的 icon_path_data 同口径
  // ...
}
```

## 五、使用示例

### 5.1 转化流程

```bash
# 1. 从 iconfont.cn 下载图标包，解压得到 iconfont.svg

# 2. 运行转化工具
cd moonbit-native-gui
moon run gui/scripts/iconfont_convert -- assets/iconfont.svg assets/iconfont.toml

# 3. 输出的 TOML 文件
cat assets/iconfont.toml
# [icons]
# home = "M0 -400 L0 400 L400 400 L400 0 ..."
# user = "M0 -500 Q300 -500 300 -200 ..."
# search = "M-100 -100 Q-100 -400 200 -400 ..."
```

### 5.2 应用中使用

```moonbit
// examples/iconfont_demo.mbt

fn main {
  // 初始化 iconfont
  @iconfont_runtime.init_iconfont("assets/iconfont.toml")
  
  // 创建窗口
  let window = @win.Window::new(800, 600, "iconfont 示例")
  
  // 绘制回调
  window.on_draw(fn(painter) {
    // 绘制内置图标
    @icons.draw_icon(painter, TreeStructure, 100.0, 100.0, 24.0, Color::black)
    
    // 绘制 iconfont 图标
    @iconfont_runtime.draw_iconfont(painter, "home", 200.0, 100.0, 24.0, Color::blue)
    @iconfont_runtime.draw_iconfont(painter, "user", 300.0, 100.0, 24.0, Color::green)
    @iconfont_runtime.draw_iconfont(painter, "search", 400.0, 100.0, 24.0, Color::red)
  })
  
  window.show()
}
```

## 六、实施计划

### 阶段一：依赖接入 + 原型验证（1 天）
- [ ] `moon add PerfectPan/svgo` 和 `moonbit-community/toml`
- [ ] 验证 `PerfectPan/svgo/xml` 能解析 iconfont.cn 导出的 SVG
- [ ] 验证 `PerfectPan/svgo/path` 的 `parse` + `apply_matrix` 坐标变换
- [ ] 验证输出的路径串能被现有 `fill_icon_path` 正确渲染

### 阶段二：转化工具（1 天）
- [ ] 实现 SVG 遍历（`<path>` + `<symbol>` 提取）
- [ ] 坐标变换：SVG viewBox → 千分定点
- [ ] TOML 输出（`[icons]` 段，KV 格式）
- [ ] 命令行入口

### 阶段三：运行时加载器（0.5 天）
- [ ] TOML 加载 + 解析（复用 `moonbit-community/toml`）
- [ ] `draw_iconfont` API
- [ ] 全局数据存储

### 阶段四：示例 + 集成（0.5 天）
- [ ] 示例程序
- [ ] 与现有 `draw_icon` 统一入口
- [ ] 文档

**总工期：约 3 天**（因为复用生态包，比原估 4-5 天缩短）

## 七、优势总结

1. **纯 MoonBit 实现**：工具链统一，无外部依赖
2. **SVG 输入**：通用矢量格式，iconfont.cn 直接导出
3. **TOML 数据**：可读性好，易于手动编辑调试
4. **运行时加载**：无需重新编译即可更新图标
5. **完全复用**：利用现有 `fill_icon_path`，零新增绘制代码
6. **动态扩展**：开发者可随时添加新图标

## 八、下一步行动

1. **原型验证**：先实现 SVG 解析器，验证路径提取
2. **样本测试**：用 iconfont.cn 示例 SVG 测试转化效果
3. **渲染验证**：生成的路径能否被 `fill_icon_path` 正确渲染
4. **性能测试**：TOML 加载和路径解析的性能
