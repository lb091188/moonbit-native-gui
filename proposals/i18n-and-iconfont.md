# 国际化与图标字体支持方案

## 一、现状分析

### 1.1 文本系统现状
- **文本渲染**：Linux 使用 Pango，Windows 使用 DirectWrite，macOS 使用 Core Text
- **字体管理**：支持系统字体族名 + 字号 + 字重 + 字形，通过 `text/font.mbt` 管理
- **字体回退**：`text/family.mbt` 提供系统可用字体枚举和候选族名解析
- **度量缓存**：`text/cache.mbt` 实现 FNV-1a 哈希的度量缓存，避免重复 FFI 调用
- **当前限制**：仅支持系统已安装字体，不支持应用内加载自定义字体文件（TTF/OTF）

### 1.2 图标系统现状
- **矢量图标**：`icons/icons.mbt` 以千分定点路径数据存图标轮廓
- **绘制方式**：全库统一矢量自绘，不依赖字体字形（避免 Windows 渲染发虚、跨平台不一致）
- **窗口图标**：`win/icon.mbt` 支持从文件/内存/像素加载窗口图标（ICO/BMP/PNG/JPEG/GIF）
- **当前限制**：不支持开发者自定义图标字体（如 iconfont）

## 二、国际化（i18n）方案

### 2.1 核心需求
1. **文本翻译**：UI 字符串多语言支持
2. **日期/时间/数字格式**：按地区习惯格式化
3. **文本方向**：LTR/RTL 支持（阿拉伯语、希伯来语）
4. **字体回退**：不同语言使用合适字体（中文用思源黑体、日文用 Noto Sans JP 等）

### 2.2 方案设计

#### 层级一：字符串资源管理
```moonbit
// gui/i18n/locale.mbt
pub(all) enum Locale {
  EnUS  // 英语（美国）
  ZhCN  // 简体中文
  ZhTW  // 繁体中文
  JaJP  // 日语
  KoKR  // 韩语
  // ... 更多地区
}

// 字符串资源表
pub(all) struct LocaleStrings {
  locale : Locale
  strings : Map[String, String]  // key -> 翻译文本
}

// 全局当前语言
let g_locale : Ref[Locale] = Ref::new(ZhCN)

// 翻译函数
pub fn t(key : String) -> String {
  let locale = !g_locale
  match get_string(locale, key) {
    Some(s) => s
    None => key  // 未找到翻译，返回键名
  }
}
```

#### 层级二：资源文件加载
```moonbit
// 从 JSON 文件加载翻译
pub fn load_locale_file(path : String) -> LocaleStrings? {
  let json = @json.parse(@fs.read(path)?)?
  let locale = parse_locale(json["locale"]?)?
  let strings = parse_strings(json["strings"]?)?
  Some({ locale, strings })
}

// 示例：locales/zh-CN.json
{
  "locale": "zh-CN",
  "strings": {
    "button.ok": "确定",
    "button.cancel": "取消",
    "menu.file": "文件",
    "menu.edit": "编辑"
  }
}
```

#### 层级三：格式化
```moonbit
// gui/i18n/format.mbt
pub fn format_number(n : Double, locale : Locale) -> String {
  match locale {
    EnUS => format_number_us(n)  // 1,234.56
    ZhCN => format_number_cn(n)  // 1,234.56
    DeDE => format_number_de(n)  // 1.234,56
    _ => format_number_default(n)
  }
}

pub fn format_date(date : Date, locale : Locale) -> String {
  match locale {
    EnUS => format_date_us(date)  // 10/19/2026
    ZhCN => format_date_cn(date)  // 2026年10月19日
    JaJP => format_date_jp(date)  // 2026年10月19日
    _ => format_date_iso(date)    // 2026-10-19
  }
}
```

#### 层级四：文本方向（RTL）
```moonbit
// gui/i18n/bidi.mbt
pub(all) enum TextDirection {
  LTR  // 从左到右
  RTL  // 从右到左
}

pub fn text_direction(locale : Locale) -> TextDirection {
  match locale {
    ArSA | HeIL => RTL
    _ => LTR
  }
}

// 布局层根据方向调整对齐
pub fn resolve_alignment(base : Alignment, dir : TextDirection) -> Alignment {
  match (base, dir) {
    (Start, LTR) => Left
    (Start, RTL) => Right
    (End, LTR) => Right
    (End, RTL) => Left
    _ => base
  }
}
```

### 2.3 实现优先级
1. **P0**：字符串资源管理 + 翻译函数（最小可用）
2. **P1**：资源文件加载 + 数字/日期格式化
3. **P2**：RTL 文本方向支持
4. **P3**：复数形式、性别等复杂语法处理

## 三、图标字体（iconfont）支持方案

### 3.1 核心需求
1. **加载自定义字体文件**：应用内加载开发者下载的 TTF/OTF 字体
2. **图标映射**：将 Unicode 码点映射到图标名称
3. **绘制集成**：在文本渲染流程中支持图标字体

### 3.2 方案设计

#### 层级一：自定义字体加载
```moonbit
// gui/text/custom_font.mbt

/// 从文件加载自定义字体（TTF/OTF）
/// Linux: Pango + Fontconfig 的 FcConfigAppFontAddFile
/// Windows: DirectWrite 的 IDWriteFontFileLoader
/// macOS: CTFontManagerRegisterFontsForURL
pub fn load_font_file(path : String) -> FontFamily? {
  let data = @fs.read_bytes(path)?
  load_font_bytes(data)
}

/// 从内存加载自定义字体
pub fn load_font_bytes(data : Bytes) -> FontFamily? {
  let handle = pt_font_load(data, data.length())
  if handle > 0 {
    Some({ handle })
  } else {
    None
  }
}

/// 字体族信息
pub(all) struct FontFamily {
  handle : Int
  name : String  // 字体族名（从字体文件读取）
}

extern "c" fn pt_font_load(data : Bytes, len : Int) -> Int = "pt_font_load"
```

#### C 层实现要点（Linux/Pango）
```c
// gui/text/stub.c
int pt_font_load(const uint8_t *data, int len) {
  // 1. 写入临时文件（Fontconfig 需要文件路径）
  char path[256];
  snprintf(path, sizeof(path), "/tmp/gui_font_%d.ttf", getpid());
  FILE *f = fopen(path, "wb");
  fwrite(data, 1, len, f);
  fclose(f);
  
  // 2. 添加到 Fontconfig
  FcConfig *config = FcConfigGetCurrent();
  if (!FcConfigAppFontAddFile(config, (const FcChar8 *)path)) {
    unlink(path);
    return 0;
  }
  
  // 3. 刷新字体映射
  PangoFontMap *fm = pango_cairo_font_map_get_default();
  pango_cairo_font_map_set_default((PangoCairoFontMap *)fm);
  
  // 4. 读取字体族名
  // ... 使用 FreeType 或 Fontconfig 读取 name 表
  
  unlink(path);
  return 1;  // 成功
}
```

#### 层级二：图标字体映射
```moonbit
// gui/icons/iconfont.mbt

/// 图标字体配置
pub(all) struct IconFont {
  family : String  // 字体族名（如 "iconfont"）
  glyphs : Map[String, Int]  // 图标名 -> Unicode 码点
}

/// 从 iconfont 配置文件加载
/// 示例：iconfont.json（从 iconfont.cn 下载）
pub fn load_iconfont_config(path : String) -> IconFont? {
  let json = @json.parse(@fs.read(path)?)?
  let family = json["font_family"]?
  let glyphs = parse_glyphs(json["glyphs"]?)?
  Some({ family, glyphs })
}

/// 绘制图标字体
pub fn draw_iconfont(
  painter : Painter,
  icon_name : String,
  x : Double,
  y : Double,
  size : Double,
  color : Color,
) -> Unit {
  match g_iconfont {
    Some(config) => {
      match config.glyphs.get(icon_name) {
        Some(codepoint) => {
          let text = String::from_codepoint(codepoint)
          painter.draw_text(
            text,
            x, y,
            size=size,
            family=config.family,
            color=color,
          )
        }
        None => ()  // 图标名不存在
      }
    }
    None => ()  // 未加载图标字体
  }
}
```

#### 层级三：iconfont.css 解析
```moonbit
// gui/icons/iconfont_css.mbt

/// 解析 iconfont.css 提取 Unicode 码点
/// 示例：
/// .icon-home:before { content: "\e600"; }
pub fn parse_iconfont_css(css : String) -> Map[String, Int] {
  let glyphs = Map::new()
  let regex = Regex::new(r"\.icon-([a-z0-9-]+):before\s*\{\s*content:\s*\"\\([0-9a-f]+)\"")
  
  for match in regex.find_all(css) {
    let name = match.group(1)
    let codepoint = Int::from_hex(match.group(2))
    glyphs.set(name, codepoint)
  }
  
  glyphs
}

/// 从 iconfont.cn 下载的完整包加载
pub fn load_iconfont_package(dir : String) -> IconFont? {
  let css_path = dir + "/iconfont.css"
  let ttf_path = dir + "/iconfont.ttf"
  
  // 1. 加载字体文件
  load_font_file(ttf_path)?
  
  // 2. 解析 CSS 提取映射
  let css = @fs.read(css_path)?
  let glyphs = parse_iconfont_css(css)
  
  // 3. 读取字体族名（从 CSS 的 @font-face）
  let family = parse_font_family(css)
  
  Some({ family, glyphs })
}
```

### 3.3 与现有系统集成

#### 方案 A：扩展 Font 结构
```moonbit
// gui/text/font.mbt
pub(all) struct Font {
  name : String
  size : Double
  weight : FontWeight
  style : FontStyle
  is_custom : Bool  // 新增：是否为自定义字体
}

// 绘制时根据 is_custom 选择字体来源
```

#### 方案 B：独立图标组件
```moonbit
// gui/icons/icon_font_widget.mbt
pub(all) struct IconFontWidget {
  icon_name : String
  size : Double
  color : Color
}

// 在声明式层使用
IconFontWidget(
  icon_name="home",
  size=24.0,
  color=Color::black,
)
```

### 3.4 iconfont 兼容流程

```
开发者下载 iconfont 包（iconfont.cn）
  ├── iconfont.ttf      → 加载到 Pango/DirectWrite/CoreText
  ├── iconfont.css      → 解析提取 Unicode 映射
  ├── iconfont.json     → 可选，结构化配置
  └── iconfont.svg      → 忽略（已有矢量图标系统）

应用启动时
  1. load_iconfont_package("assets/iconfont")
  2. 注册字体到系统字体管理器
  3. 解析 CSS 提取 {图标名 -> Unicode} 映射
  4. 存储到全局 g_iconfont

UI 绘制时
  draw_iconfont(painter, "home", x, y, size, color)
  → 查找 Unicode 码点（如 0xe600）
  → 调用 painter.draw_text(text="\ue600", family="iconfont")
  → Pango/DirectWrite 使用加载的自定义字体渲染
```

## 四、实施计划

### 阶段一：自定义字体加载（1-2 周）
- [ ] Linux/Pango：`FcConfigAppFontAddFile` 实现
- [ ] Windows/DirectWrite：`IDWriteFontFileLoader` 实现
- [ ] macOS/CoreText：`CTFontManagerRegisterFontsForURL` 实现
- [ ] MoonBit 层 API：`load_font_file` / `load_font_bytes`
- [ ] 测试用例：加载 Noto Sans CJK 验证中文渲染

### 阶段二：iconfont 支持（1 周）
- [ ] CSS 解析器：提取 `.icon-xxx:before { content: "\e600" }`
- [ ] JSON 配置加载：支持 iconfont.cn 导出的 iconfont.json
- [ ] 图标绘制 API：`draw_iconfont(painter, name, x, y, size, color)`
- [ ] 示例：加载 iconfont 包并绘制图标

### 阶段三：国际化基础（2-3 周）
- [ ] Locale 枚举 + 全局语言设置
- [ ] 字符串资源表 + `t(key)` 翻译函数
- [ ] JSON 资源文件加载
- [ ] 数字/日期格式化
- [ ] 示例：多语言 UI

### 阶段四：高级特性（可选）
- [ ] RTL 文本方向支持
- [ ] 复数形式处理
- [ ] 字体回退策略优化（按语言选择字体）
- [ ] 热重载：语言切换时刷新 UI

## 五、技术要点

### 5.1 自定义字体加载的平台差异

| 平台 | API | 注意事项 |
|------|-----|----------|
| Linux | `FcConfigAppFontAddFile` | 需要写入临时文件，Fontconfig 不支持内存加载 |
| Windows | `IDWriteFontFileLoader` | 支持内存加载，需实现自定义 Loader 接口 |
| macOS | `CTFontManagerRegisterFontsForURL` | 支持文件 URL，内存加载需 `CTFontManagerRegisterGraphicsFont` |

### 5.2 iconfont 的 Unicode 私有区
- iconfont 通常使用 Unicode 私有区（PUA）：U+E000 ~ U+F8FF
- 码点映射必须从 CSS/JSON 提取，不能硬编码
- 不同 iconfont 项目的码点可能冲突

### 5.3 与现有矢量图标的关系
- **矢量图标**（icons.mbt）：内置、轻量、跨平台一致，适合通用图标
- **图标字体**（iconfont）：开发者自定义、丰富选择、但依赖字体渲染质量
- **共存策略**：优先使用矢量图标，iconfont 作为补充（开发者特定需求）

### 5.4 国际化与文本渲染的交互
- 不同语言可能需要不同字体（中文用 Noto Sans CJK、日文用 Noto Sans JP）
- `text/family.mbt` 的 `resolve_family` 需要扩展：按语言选择候选字体
- RTL 语言需要布局层支持（Yoga 的 `set_direction`）

## 六、参考实现

### 6.1 其他 GUI 框架的做法
- **Electron**：使用 Chromium 的字体加载 + ICU 国际化
- **Flutter**：`pubspec.yaml` 声明字体文件，`intl` 包处理 i18n
- **Qt**：`QFontDatabase::addApplicationFont` + `QTranslator`
- **GTK**：`pango_fc_font_map_add_application_font` + `gettext`

### 6.2 MoonBit 生态
- JSON 解析：`@json` 包（已内置）
- 文件读取：`@fs` 包（已内置）
- 正则表达式：需要 `@regex` 包（或手写解析器）

## 七、风险与挑战

1. **字体渲染一致性**：不同平台的字体渲染引擎差异，iconfont 可能在 Windows 发虚
2. **内存管理**：自定义字体需要正确释放，避免内存泄漏
3. **性能**：字体加载是昂贵操作，需要缓存和懒加载
4. **测试覆盖**：i18n 需要多语言测试数据，RTL 需要特殊测试环境
5. **包体积**：内置多语言资源会增加分发体积，需要按需加载

## 八、下一步行动

1. **原型验证**：先在 Linux/Pango 实现自定义字体加载原型
2. **iconfont 调研**：收集 iconfont.cn 的 CSS/JSON 样本，验证解析逻辑
3. **i18n 需求收集**：确定首批支持的语言和翻译范围
4. **性能基准**：测量字体加载和文本渲染的性能影响
