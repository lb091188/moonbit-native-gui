# iconfont 转化方案：字体图标 → 矢量路径数据

## 一、核心思路

**不引入字体加载，而是离线转化**：把 iconfont 的 TTF/OTF 字体文件中的字形轮廓提取出来，转化成现有 `icons/icons.mbt` 的千分定点路径格式，完全复用已有的矢量绘制系统。

```
开发者下载 iconfont.ttf
  ↓
运行转化脚本（Python/Node.js）
  ↓
提取字形轮廓（FreeType/opentype.js）
  ↓
输出 MoonBit 代码（icon_path_data 格式）
  ↓
编译进二进制，用 fill_icon_path 绘制
```

## 二、现有系统分析

### 2.1 icons.mbt 的数据结构
```moonbit
// 千分定点串：坐标 × 1000 取整，用字符编码
// 指令集：M(移动) L(直线) Q(二次贝塞尔) C(三次贝塞尔) Z(闭合)
pub(all) let icon_path_data : Map[IconKind, String] = {
  TreeStructure: "M500 0 L1000 500 L500 1000 L0 500 Z",
  Hide: "M200 300 Q500 100 800 300 ...",
  // ... 803 个图标
}

// 绘制时解析路径串，调用 Painter 的 fill 方法
pub fn draw_icon(
  painter : Painter,
  kind : IconKind,
  cx : Double,  // 中心 x
  cy : Double,  // 中心 y
  s : Double,   // 内容半径（半边长）
  color : Color,
) -> Unit {
  match icon_path_data.get(kind) {
    Some(path_str) => {
      let commands = parse_path(path_str)
      fill_icon_path(painter, commands, cx, cy, s, color)
    }
    None => ()
  }
}
```

### 2.2 路径格式规范
- **坐标系**：原点 (0,0) 在图标中心，范围 [-1000, 1000] × [-1000, 1000]
- **单位**：千分定点（1.0 = 1000 单位）
- **指令**：
  - `M x y`：移动到 (x, y)
  - `L x y`：直线到 (x, y)
  - `Q x1 y1 x2 y2`：二次贝塞尔（控制点 → 终点）
  - `C x1 y1 x2 y2 x3 y3`：三次贝塞尔（控制点1 → 控制点2 → 终点）
  - `Z`：闭合路径
- **示例**：`"M500 0 L1000 500 L500 1000 L0 500 Z"` 表示一个菱形

## 三、转化方案设计

### 3.1 转化流程

```
1. 读取 TTF/OTF 文件
   └─ 使用 FreeType（Python）或 opentype.js（Node.js）

2. 提取字形轮廓
   └─ 获取每个 Unicode 码点的路径数据
   └─ 路径格式：TrueType 轮廓（二次贝塞尔）或 Type1/CFF（三次贝塞尔）

3. 坐标变换
   └─ 字体坐标系（em 方框，通常 1000 或 2048 单位）→ 千分定点（±1000）
   └─ Y 轴翻转（字体 Y 向上，GUI Y 向下）
   └─ 居中对齐（字形原点 → 图标中心）

4. 路径简化
   └─ 合并共线线段
   └─ 移除冗余控制点
   └─ 优化贝塞尔曲线

5. 输出 MoonBit 代码
   └─ 生成 icon_path_data 条目
   └─ 生成 IconKind 枚举扩展
   └─ 或输出 JSON 数据文件（运行时加载）
```

### 3.2 转化脚本实现（Python + FreeType）

```python
#!/usr/bin/env python3
# scripts/convert_iconfont.py

import sys
import freetype
from pathlib import Path

def extract_glyph_path(face, glyph_name, units_per_em=1000):
    """提取单个字形的路径数据"""
    glyph_index = face.get_name_index(glyph_name.encode())
    if glyph_index == 0:
        return None
    
    face.load_glyph(glyph_index, freetype.FT_LOAD_NO_HINTING)
    glyph = face.glyph
    outline = glyph.outline
    
    # 坐标变换：字体坐标系 → 千分定点
    scale = 1000.0 / units_per_em
    points = []
    
    start = 0
    for end in outline.contours:
        contour = outline.points[start:end+1]
        tags = outline.tags[start:end+1]
        
        # TrueType 轮廓：tag 位 0 = 控制点，位 1 = 线上点
        path_points = []
        for i, ((x, y), tag) in enumerate(zip(contour, tags)):
            # Y 轴翻转 + 缩放 + 居中
            px = int(x * scale)
            py = int(-y * scale)  # 翻转 Y
            path_points.append((px, py, tag))
        
        points.append(path_points)
        start = end + 1
    
    return points

def path_to_moonbit(points):
    """将路径点转为 MoonBit 路径串"""
    commands = []
    
    for contour in points:
        if not contour:
            continue
        
        # 第一个点：移动
        x0, y0, _ = contour[0]
        commands.append(f"M{x0} {y0}")
        
        # 后续点：直线或贝塞尔
        i = 1
        while i < len(contour):
            x, y, tag = contour[i]
            
            if tag & 1:  # 线上点
                commands.append(f"L{x} {y}")
                i += 1
            else:  # 控制点
                # 二次贝塞尔：控制点 + 终点
                if i + 1 < len(contour):
                    x1, y1, _ = contour[i]
                    x2, y2, tag2 = contour[i + 1]
                    commands.append(f"Q{x1} {y1} {x2} {y2}")
                    i += 2
                else:
                    # 最后一个点是控制点，闭合到起点
                    commands.append(f"Q{x} {y} {x0} {y0}")
                    i += 1
        
        commands.append("Z")
    
    return " ".join(commands)

def convert_iconfont(ttf_path, output_path):
    """转化整个 iconfont 文件"""
    face = freetype.Face(ttf_path)
    units_per_em = face.units_per_EM
    
    # 读取 iconfont.json（如果有）获取图标名称映射
    json_path = Path(ttf_path).with_suffix('.json')
    name_map = {}
    if json_path.exists():
        import json
        with open(json_path) as f:
            data = json.load(f)
            for glyph in data.get('glyphs', []):
                unicode = int(glyph['unicode'], 16)
                name = glyph['font_class']
                name_map[unicode] = name
    
    # 提取所有字形
    results = []
    face.set_char_size(0, units_per_em * 64, 72, 72)
    
    for unicode, name in name_map.items():
        face.load_char(unicode, freetype.FT_LOAD_NO_HINTING)
        glyph = face.glyph
        outline = glyph.outline
        
        # 提取路径
        scale = 1000.0 / units_per_em
        path_commands = []
        
        start = 0
        for end in outline.contours:
            contour = list(zip(outline.points[start:end+1], 
                              outline.tags[start:end+1]))
            
            if not contour:
                start = end + 1
                continue
            
            # 第一个点
            (x0, y0), tag0 = contour[0]
            px0, py0 = int(x0 * scale), int(-y0 * scale)
            path_commands.append(f"M{px0} {py0}")
            
            # 后续点
            i = 1
            while i < len(contour):
                (x, y), tag = contour[i]
                px, py = int(x * scale), int(-y * scale)
                
                if tag & 1:  # 线上点
                    path_commands.append(f"L{px} {py}")
                    i += 1
                else:  # 控制点
                    if i + 1 < len(contour):
                        (x1, y1), _ = contour[i]
                        (x2, y2), tag2 = contour[i + 1]
                        px1, py1 = int(x1 * scale), int(-y1 * scale)
                        px2, py2 = int(x2 * scale), int(-y2 * scale)
                        path_commands.append(f"Q{px1} {py1} {px2} {py2}")
                        i += 2
                    else:
                        path_commands.append(f"Q{px} {py} {px0} {py0}")
                        i += 1
            
            path_commands.append("Z")
            start = end + 1
        
        path_str = " ".join(path_commands)
        results.append((name, path_str))
    
    # 输出 MoonBit 代码
    with open(output_path, 'w') as f:
        f.write("// 自动生成的 iconfont 图标数据\n")
        f.write("// 源文件：" + ttf_path + "\n\n")
        
        for name, path_str in results:
            # 生成枚举名（首字母大写）
            enum_name = ''.join(word.capitalize() for word in name.split('-'))
            f.write(f"  {enum_name} // {name}\n")
        
        f.write("\n// 路径数据\n")
        f.write("pub(all) let iconfont_path_data : Map[String, String] = {\n")
        for name, path_str in results:
            enum_name = ''.join(word.capitalize() for word in name.split('-'))
            f.write(f'  "{enum_name}": "{path_str}",\n')
        f.write("}\n")
    
    print(f"转化完成：{len(results)} 个图标 → {output_path}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("用法：python convert_iconfont.py <iconfont.ttf> [output.mbt]")
        sys.exit(1)
    
    ttf_path = sys.argv[1]
    output_path = sys.argv[2] if len(sys.argv) > 2 else "iconfont_generated.mbt"
    convert_iconfont(ttf_path, output_path)
```

### 3.3 转化脚本实现（Node.js + opentype.js）

```javascript
#!/usr/bin/env node
// scripts/convert_iconfont.js

const fs = require('fs');
const opentype = require('opentype.js');

function convertIconFont(ttfPath, outputPath) {
    const font = opentype.loadSync(ttfPath);
    const unitsPerEm = font.unitsPerEm;
    const scale = 1000 / unitsPerEm;
    
    // 读取 iconfont.json（如果有）
    const jsonPath = ttfPath.replace(/\.ttf$/, '.json');
    let nameMap = {};
    
    if (fs.existsSync(jsonPath)) {
        const data = JSON.parse(fs.readFileSync(jsonPath, 'utf-8'));
        for (const glyph of data.glyphs || []) {
            const unicode = parseInt(glyph.unicode, 16);
            nameMap[unicode] = glyph.font_class;
        }
    } else {
        // 没有 JSON，使用字形的 PostScript 名称
        for (let i = 0; i < font.numGlyphs; i++) {
            const glyph = font.glyphs.get(i);
            if (glyph.unicode && glyph.name) {
                nameMap[glyph.unicode] = glyph.name;
            }
        }
    }
    
    const results = [];
    
    // 提取每个字形
    for (const [unicode, name] of Object.entries(nameMap)) {
        const glyph = font.charToGlyph(String.fromCharCode(unicode));
        if (!glyph || glyph.index === 0) continue;
        
        const path = glyph.getPath();
        const commands = [];
        
        for (const cmd of path.commands) {
            switch (cmd.type) {
                case 'M':
                    commands.push(`M${Math.round(cmd.x * scale)} ${Math.round(-cmd.y * scale)}`);
                    break;
                case 'L':
                    commands.push(`L${Math.round(cmd.x * scale)} ${Math.round(-cmd.y * scale)}`);
                    break;
                case 'Q':
                    commands.push(`Q${Math.round(cmd.x1 * scale)} ${Math.round(-cmd.y1 * scale)} ${Math.round(cmd.x * scale)} ${Math.round(-cmd.y * scale)}`);
                    break;
                case 'C':
                    commands.push(`C${Math.round(cmd.x1 * scale)} ${Math.round(-cmd.y1 * scale)} ${Math.round(cmd.x2 * scale)} ${Math.round(-cmd.y2 * scale)} ${Math.round(cmd.x * scale)} ${Math.round(-cmd.y * scale)}`);
                    break;
                case 'Z':
                    commands.push('Z');
                    break;
            }
        }
        
        if (commands.length > 0) {
            results.push({ name, path: commands.join(' ') });
        }
    }
    
    // 输出 MoonBit 代码
    let output = '// 自动生成的 iconfont 图标数据\n';
    output += `// 源文件：${ttfPath}\n\n`;
    
    output += 'pub(all) let iconfont_path_data : Map[String, String] = {\n';
    for (const { name, path } of results) {
        const enumName = name.split('-').map(w => w[0].toUpperCase() + w.slice(1)).join('');
        output += `  "${enumName}": "${path}",\n`;
    }
    output += '}\n';
    
    fs.writeFileSync(outputPath, output);
    console.log(`转化完成：${results.length} 个图标 → ${outputPath}`);
}

if (process.argv.length < 3) {
    console.log('用法：node convert_iconfont.js <iconfont.ttf> [output.mbt]');
    process.exit(1);
}

convertIconFont(process.argv[2], process.argv[3] || 'iconfont_generated.mbt');
```

## 四、使用流程

### 4.1 开发者工作流

```bash
# 1. 从 iconfont.cn 下载图标包
#    得到：iconfont.ttf, iconfont.css, iconfont.json, iconfont.svg

# 2. 运行转化脚本
python3 scripts/convert_iconfont.py iconfont.ttf gui/icons/iconfont_generated.mbt

# 或
node scripts/convert_iconfont.js iconfont.ttf gui/icons/iconfont_generated.mbt

# 3. 生成的代码自动包含在构建中
#    gui/icons/iconfont_generated.mbt 会被 moon build 编译

# 4. 在代码中使用
let icon = IconKind::Home  // 生成的枚举
draw_icon(painter, icon, cx, cy, size, color)
```

### 4.2 生成的代码示例

```moonbit
// gui/icons/iconfont_generated.mbt
// 自动生成的 iconfont 图标数据
// 源文件：iconfont.ttf

pub(all) let iconfont_path_data : Map[String, String] = {
  "Home": "M0 -400 L0 400 L400 400 L400 0 L200 -200 L0 -200 L0 -400 Z M-200 -200 L-200 400 L-400 400 L-400 -200 Z",
  "User": "M0 -500 Q300 -500 300 -200 Q300 0 0 0 Q-300 0 -300 -200 Q-300 -500 0 -500 Z M-500 200 L500 200 L500 600 L-500 600 Z",
  "Search": "M-100 -100 Q-100 -400 200 -400 Q500 -400 500 -100 Q500 200 200 200 Q-100 200 -100 -100 Z M300 300 L600 600",
  // ... 更多图标
}

// 绘制函数
pub fn draw_iconfont(
  painter : Painter,
  name : String,
  cx : Double,
  cy : Double,
  s : Double,
  color : Color,
) -> Unit {
  match iconfont_path_data.get(name) {
    Some(path_str) => {
      let commands = parse_icon_path(path_str)
      fill_icon_path(painter, commands, cx, cy, s, color)
    }
    None => ()
  }
}
```

## 五、高级特性

### 5.1 多色图标支持
iconfont 支持多色图标（SVG 格式），可以扩展转化脚本提取颜色信息：

```moonbit
pub(all) struct ColoredIcon {
  paths : Array[(String, Color)]  // (路径, 颜色)
}

pub fn draw_colored_iconfont(
  painter : Painter,
  name : String,
  cx : Double,
  cy : Double,
  s : Double,
) -> Unit {
  match iconfont_colored_data.get(name) {
    Some(icon) => {
      for (path_str, color) in icon.paths {
        let commands = parse_icon_path(path_str)
        fill_icon_path(painter, commands, cx, cy, s, color)
      }
    }
    None => ()
  }
}
```

### 5.2 动态图标库
如果不想编译进二进制，可以输出 JSON 数据文件，运行时加载：

```moonbit
// gui/icons/iconfont_runtime.mbt
pub fn load_iconfont_data(path : String) -> Map[String, String]? {
  let json = @json.parse(@fs.read(path)?)?
  let data = Map::new()
  for (key, value) in json.entries() {
    data.set(key, value.to_string())
  }
  Some(data)
}

let g_iconfont_data : Ref[Map[String, String]?] = Ref::new(None)

pub fn init_iconfont(path : String) -> Unit {
  g_iconfont_data.set(load_iconfont_data(path))
}

pub fn draw_iconfont(name : String, ...) -> Unit {
  match !g_iconfont_data {
    Some(data) => {
      match data.get(name) {
        Some(path_str) => { /* 绘制 */ }
        None => ()
      }
    }
    None => ()
  }
}
```

### 5.3 图标字体子集化
如果只需要部分图标，可以用 fonttools 子集化字体，减小体积：

```bash
# 安装 fonttools
pip install fonttools brotli

# 子集化：只保留需要的 Unicode 码点
pyftsubset iconfont.ttf --unicodes=U+E600,U+E601,U+E602 --output-file=iconfont_subset.ttf

# 再运行转化脚本
python3 scripts/convert_iconfont.py iconfont_subset.ttf output.mbt
```

## 六、与现有系统的集成

### 6.1 扩展 IconKind 枚举
```moonbit
// gui/icons/icons.mbt
pub(all) enum IconKind {
  // 现有 803 个图标
  TreeStructure
  Hide
  // ...
  
  // iconfont 转化的图标（自动追加）
  IconfontHome
  IconfontUser
  IconfontSearch
  // ...
}
```

### 6.2 统一绘制入口
```moonbit
// gui/icons/icons.mbt
pub fn draw_icon(
  painter : Painter,
  kind : IconKind,
  cx : Double,
  cy : Double,
  s : Double,
  color : Color,
) -> Unit {
  // 先查内置图标
  match builtin_icon_path_data.get(kind) {
    Some(path_str) => {
      let commands = parse_icon_path(path_str)
      fill_icon_path(painter, commands, cx, cy, s, color)
    }
    None => {
      // 再查 iconfont 图标
      let name = icon_kind_to_name(kind)
      draw_iconfont(painter, name, cx, cy, s, color)
    }
  }
}
```

## 七、实施计划

### 阶段一：转化脚本原型（1-2 天）
- [ ] Python 版本：使用 FreeType 提取 TrueType 轮廓
- [ ] 测试：转化 iconfont.cn 示例文件
- [ ] 验证：生成的路径串能被 `fill_icon_path` 正确渲染

### 阶段二：路径优化（2-3 天）
- [ ] 坐标简化：合并共线线段
- [ ] 曲线优化：减少贝塞尔控制点
- [ ] 边界框计算：自动居中图标

### 阶段三：Node.js 版本（1 天）
- [ ] 使用 opentype.js 实现同等功能
- [ ] 支持 CFF/Type1 轮廓（三次贝塞尔）
- [ ] 跨平台测试（Windows/macOS/Linux）

### 阶段四：集成到构建流程（1 天）
- [ ] prebuild 脚本自动调用转化脚本
- [ ] 检测 iconfont 文件变化，增量生成
- [ ] 生成的代码自动包含在 `moon build`

## 八、技术要点

### 8.1 TrueType vs CFF 轮廓
- **TrueType（.ttf）**：二次贝塞尔曲线，tag 位标识控制点
- **CFF/Type1（.otf）**：三次贝塞尔曲线，路径命令更复杂
- 转化脚本需要同时支持两种格式

### 8.2 坐标变换细节
```
字体坐标系：
  - 原点在基线（baseline）
  - Y 轴向上
  - 单位：em 方框（通常 1000 或 2048）

GUI 坐标系：
  - 原点在图标中心
  - Y 轴向下
  - 单位：千分定点（±1000）

变换公式：
  px = (x - origin_x) * scale
  py = -(y - origin_y) * scale  // 翻转 Y
  scale = 1000 / units_per_em
```

### 8.3 字形度量
- **advanceWidth**：字形宽度（含间距）
- **lsb（leftSideBearing）**：左间距
- **bounds**：边界框 [xMin, yMin, xMax, yMax]
- 转化时需要居中：`offset_x = (advanceWidth - (xMax - xMin)) / 2`

## 九、优势总结

1. **零运行时依赖**：不需要加载字体文件，图标数据编译进二进制
2. **跨平台一致**：使用现有矢量绘制系统，避免字体渲染差异
3. **性能优异**：矢量路径直接绘制，无需字体 shaping
4. **体积可控**：只转化需要的图标，支持子集化
5. **工具链简单**：一次性转化脚本，开发者友好
6. **完全复用**：利用现有 `fill_icon_path`，无需新增绘制代码

## 十、下一步行动

1. **收集样本**：从 iconfont.cn 下载 2-3 个典型图标包
2. **原型验证**：用 Python + FreeType 提取路径，手动验证渲染效果
3. **路径优化**：研究路径简化算法，减小数据体积
4. **自动化**：集成到 prebuild 流程，实现一键转化
