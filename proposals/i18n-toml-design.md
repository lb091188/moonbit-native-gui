# 国际化（i18n）方案：TOML 翻译文件 + 运行时加载

## 前置：全库字符串审计与改造范围（代码核实）

选定范围为「全库组件改造」。据此对 `gui/` 全树做了中文字面量审计（排除 `*_wbtest.mbt`），
共 **257 处中文串 / 64 文件**。但逐类核对后，**真正该走 i18n 的用户文案只占极少数**，
机械地把每个 `"中文"` 包进 `t()` 是错的。必须按四类分流处理：

| 类别 | 典型文件（命中数） | 是否 i18n | 正确处置 |
|------|------|:---:|------|
| **A. 中文注释/文档串** | `dbus/bus.mbt`(18)、`sni.mbt`(11)、大量 `chart/*.mbt`、`*.c` | ❌ | 项目约定注释用中文（AGENTS.md 规则 10），**不碰** |
| **B. OS 读来的数据** | `sys/volume.mbt`(15)、`printer.mbt`(13)、`wallpaper.mbt`(20)、`autostart.mbt`(13) | ❌ | 设备名/应用名/卷名由**操作系统本地化**，不是翻译键，**不碰** |
| **C. 语言相关格式化** | `ui/datepicker.mbt`(7)、`datetime.mbt`(2) 的月名/星期 | ⚠️ | 属**日期本地化**，交给 date 库按 locale 出，**不是 t(key)** |
| **D. 框架自有 UI 文案** | `ui/message_box.mbt`(1)、`overlay.mbt`(2)、`display.mbt`(1)、`shell/menu.mbt`(7)、按钮/菜单角色 | ✅ | **这才是 i18n 的真正目标** |

**诚实结论**：`ui/` 目录（框架用户可见文案主战场）实际只有 **13 处**中文串，且大半是
datepicker 月名（归 C 类）。所以「全库改造」的实际可翻译面很小——改造的价值不在量大，
而在于**建一套正确机制 + 把边界划清**（A/B/C 绝不进 t()，只有 D 类进）。
`examples/` 与未来应用层才是 t(key) 的主用量方，框架负责提供机制与示范。

### 审计工具（区分四类，防误包）
```
scan → 对每处中文字面量分类：
  - 在注释//// 行内         → A，跳过
  - 变量名含 device/app/url  → B，跳过
  - 月名/星期/日期          → C，标记走 date 库
  - 赋值给 label/text/title 或作函数返回值给用户 → D，纳入 t()
产物：D 类清单 = 待抽取为翻译键的**准确集合**
```

---

## 〇、生态可复用包（moon search 结果）

MoonBit 生态已有成熟的 i18n 库，可直接复用或参考：

| 能力 | 推荐包 | 下载量 | 用途 |
|------|--------|--------|------|
| **完整 i18n 框架** | `lampclaw/i18n` | 172 | MF2 格式化、XLIFF 导入导出、类型安全绑定生成 |
| **轻量 i18n** | `wzzc-dev/moui_i18n` | 155 | 内存 Catalog、复数形式、命名插值、locale 回退 |
| **应用级 i18n** | `zlhahaha/moonlocale` | 22 | ICU 消息、复数/序数、数字/货币/日期格式化、伪本地化 |
| **系统 locale 探测** | `justjavac/sys_locale` | 51 | 读取系统 locale（环境变量、LC_ALL、LANG） |

### 推荐依赖组合

```
运行时（应用内）：
  moonbit-community/toml  → 加载 TOML 翻译文件
  justjavac/sys_locale    → 探测系统语言偏好
  （可选）lampclaw/i18n   → MF2 格式化、复数形式
  
转化工具（开发时）：
  （可选）lampclaw/i18n/generator → 从翻译文件生成类型安全绑定
```

## 一、核心设计

**TOML 翻译文件，按 locale 分文件存储，运行时加载**：

```
项目结构：
  locales/
    ├── en.toml          ← 英语翻译
    ├── zh-CN.toml       ← 简体中文
    ├── zh-TW.toml       ← 繁体中文
    ├── ja.toml          ← 日语
    ├── ko.toml          ← 韩语
    └── ar.toml          ← 阿拉伯语（RTL）

运行时：
  1. 探测系统 locale（justjavac/sys_locale）
  2. 加载对应 TOML 文件（moonbit-community/toml）
  3. 构建翻译 Catalog
  4. UI 层调用 t("key") 获取翻译
  5. 支持热重载（切换语言时刷新）
```

## 二、TOML 翻译文件格式

### 2.1 基础格式（KV 结构）

```toml
# locales/zh-CN.toml

[meta]
locale = "zh-CN"
version = "1.0.0"

[common]
ok = "确定"
cancel = "取消"
save = "保存"
delete = "删除"
close = "关闭"

[menu]
file = "文件"
edit = "编辑"
view = "视图"
help = "帮助"

[menu.file]
new = "新建"
open = "打开..."
save = "保存"
save_as = "另存为..."
exit = "退出"

[dialog]
confirm_delete = "确定要删除吗？"
unsaved_changes = "有未保存的更改，是否保存？"

[error]
file_not_found = "文件不存在：{path}"
network_error = "网络错误：{message}"
```

### 2.2 复数形式

```toml
# locales/en.toml

[items]
# 英语：one/other 两种形式
count = { one = "{n} item", other = "{n} items" }

[files]
# 带命名插值的复数
selected = { one = "{count} file selected", other = "{count} files selected" }

# locales/zh-CN.toml
# 中文：无复数变化
[items]
count = "{n} 个项目"

[files]
selected = "已选择 {count} 个文件"

# locales/ja.toml
# 日语：无复数变化
[items]
count = "{n} 個のアイテム"

# locales/ar.toml
# 阿拉伯语：zero/one/two/few/many/other 六种形式
[items]
count = { 
  zero = "لا عناصر",
  one = "عنصر واحد",
  two = "عنصران",
  few = "{n} عناصر",
  many = "{n} عنصراً",
  other = "{n} عنصر"
}
```

### 2.3 嵌套结构（按模块组织）

```toml
# locales/zh-CN.toml

[meta]
locale = "zh-CN"
version = "1.0.0"

# 通用按钮
[common]
ok = "确定"
cancel = "取消"

# 菜单栏
[menu]
file = "文件"
edit = "编辑"

[menu.file]
new = "新建"
open = "打开..."

# 对话框
[dialog.confirm]
title = "确认"
message = "你确定要执行此操作吗？"

[dialog.error]
title = "错误"
file_not_found = "文件不存在：{path}"
```

## 三、MoonBit 运行时实现

### 3.1 依赖配置

```json
// gui/i18n/moon.pkg.json
{
  "import": [
    { "path": "moonbit-community/toml", "alias": "toml" },
    { "path": "justjavac/sys_locale", "alias": "sys_locale" }
  ]
}
```

### 3.2 Locale 类型

```moonbit
// gui/i18n/locale.mbt

/// BCP 47 语言标签
pub(all) struct Locale {
  language : String  // "zh", "en", "ja"
  region : String?   // "CN", "TW", "US"
}

/// 解析 locale 字符串
pub fn Locale::parse(tag : String) -> Locale {
  let parts = tag.split("-")
  match parts.length() {
    0 => { language: "en", region: None }
    1 => { language: parts[0], region: None }
    _ => { language: parts[0], region: Some(parts[1]) }
  }
}

/// 转为字符串
pub fn Locale::to_string(self : Locale) -> String {
  match self.region {
    Some(r) => self.language + "-" + r
    None => self.language
  }
}

/// 获取系统 locale
pub fn system_locale() -> Locale {
  let tag = @sys_locale.current()
  Locale::parse(tag)
}
```

### 3.3 翻译 Catalog

```moonbit
// gui/i18n/catalog.mbt

/// 翻译条目
pub(all) enum Message {
  Simple(String)                                    // 简单文本
  Plural(Map[String, String])                       // 复数形式
}

/// 翻译目录
pub(all) struct Catalog {
  locale : Locale
  messages : Map[String, Message]
}

/// 从 TOML 文件加载
pub fn Catalog::from_toml(path : String) -> Catalog? {
  let content = @fs.read(path)?
  let root = @toml.parse(content)?
  
  let locale = match root.get("meta") {
    Some(TomlValue::Table(meta)) => {
      match meta.get("locale") {
        Some(TomlValue::String(tag)) => Locale::parse(tag)
        None => return None
      }
    }
    None => return None
  }
  
  let messages = Map::new()
  
  // 递归遍历所有段
  fn flatten_table(table : Map[String, TomlValue], prefix : String) -> Unit {
    for (key, value) in table {
      let full_key = if prefix.length() > 0 { prefix + "." + key } else { key }
      
      match value {
        TomlValue::String(s) => {
          messages.set(full_key, Message::Simple(s))
        }
        TomlValue::Table(t) => {
          // 检查是否是复数形式（包含 one/other/many 等键）
          if is_plural_table(t) {
            let plural_map = Map::new()
            for (k, v) in t {
              match v {
                TomlValue::String(s) => plural_map.set(k, s)
                _ => ()
              }
            }
            messages.set(full_key, Message::Plural(plural_map))
          } else {
            // 递归展开
            flatten_table(t, full_key)
          }
        }
        _ => ()
      }
    }
  }
  
  flatten_table(root, "")
  
  Some({ locale, messages })
}

/// 检查是否是复数表
fn is_plural_table(table : Map[String, TomlValue]) -> Bool {
  let plural_keys = ["zero", "one", "two", "few", "many", "other"]
  for key in plural_keys {
    if table.contains(key) {
      return true
    }
  }
  false
}
```

### 3.4 翻译函数

```moonbit
// gui/i18n/translator.mbt

/// 全局翻译器
let g_catalog : Ref[Catalog?] = Ref::new(None)
let g_fallback : Ref[Catalog?] = Ref::new(None)

/// 初始化翻译器
pub fn init_i18n(locales_dir : String, preferred : Locale?) -> Unit {
  let locale = match preferred {
    Some(l) => l
    None => system_locale()
  }
  
  // 加载首选 locale
  let path = locales_dir + "/" + locale.to_string() + ".toml"
  match Catalog::from_toml(path) {
    Some(catalog) => g_catalog.set(Some(catalog))
    None => println("警告：无法加载翻译文件：" + path)
  }
  
  // 加载回退 locale（英语）
  if locale.language != "en" {
    let fallback_path = locales_dir + "/en.toml"
    match Catalog::from_toml(fallback_path) {
      Some(catalog) => g_fallback.set(Some(catalog))
      None => ()
    }
  }
}

/// 翻译函数（简单文本）
pub fn t(key : String) -> String {
  match !g_catalog {
    Some(catalog) => {
      match catalog.messages.get(key) {
        Some(Message::Simple(s)) => s
        Some(Message::Plural(_)) => key  // 复数形式需要 t_count
        None => {
          // 尝试回退 locale
          match !g_fallback {
            Some(fb) => {
              match fb.messages.get(key) {
                Some(Message::Simple(s)) => s
                _ => key
              }
            }
            None => key
          }
        }
      }
    }
    None => key
  }
}

/// 翻译函数（带插值）
pub fn t_with(key : String, vars : Map[String, String]) -> String {
  let template = t(key)
  let mut result = template
  for (name, value) in vars {
    result = result.replace("{" + name + "}", value)
  }
  result
}

/// 翻译函数（复数形式）
pub fn t_count(key : String, count : Int) -> String {
  match !g_catalog {
    Some(catalog) => {
      match catalog.messages.get(key) {
        Some(Message::Plural(plural_map)) => {
          // 选择复数形式（简化版：只支持 one/other）
          let form = if count == 1 { "one" } else { "other" }
          match plural_map.get(form) {
            Some(template) => {
              template.replace("{n}", count.to_string())
                      .replace("{count}", count.to_string())
            }
            None => key
          }
        }
        _ => key
      }
    }
    None => key
  }
}

/// 切换语言（热重载）
pub fn switch_locale(locales_dir : String, locale : Locale) -> Unit {
  init_i18n(locales_dir, Some(locale))
}
```

### 3.5 使用示例

```moonbit
// examples/i18n_demo.mbt

fn main {
  // 初始化 i18n
  @i18n.init_i18n("locales", None)  // None = 使用系统 locale
  
  // 简单翻译
  println(@i18n.t("common.ok"))  // "确定" 或 "OK"
  
  // 带插值
  let vars = Map::new()
  vars.set("path", "/tmp/test.txt")
  println(@i18n.t_with("error.file_not_found", vars))
  // "文件不存在：/tmp/test.txt"
  
  // 复数形式
  println(@i18n.t_count("items.count", 1))   // "1 个项目"
  println(@i18n.t_count("items.count", 5))   // "5 个项目"
  
  // 切换语言
  @i18n.switch_locale("locales", Locale::parse("en"))
  println(@i18n.t("common.ok"))  // "OK"
}
```

## 四、与 GUI 集成

### 4.1 组件层使用

```moonbit
// gui/ui/button.mbt

pub(all) struct Button {
  text : String
  on_click : () -> Unit
}

/// 创建按钮（自动翻译）
pub fn Button::new(key : String, on_click : () -> Unit) -> Button {
  { text: @i18n.t(key), on_click }
}

// 使用
let btn = Button::new("common.ok", fn() { /* ... */ })
```

### 4.2 语言切换时刷新 UI

```moonbit
// gui/app.mbt

pub struct App {
  window : Window
  // ...
}

/// 切换语言
pub fn App::switch_language(self : App, locale : Locale) -> Unit {
  // 1. 切换 i18n
  @i18n.switch_locale("locales", locale)
  
  // 2. 刷新所有组件
  self.window.invalidate()  // 触发重绘
  
  // 3. 重新构建 UI 树（如果需要）
  self.rebuild_ui()
}
```

## 五、开发者工作流

### 5.1 添加翻译

```bash
# 1. 编辑翻译文件
vim locales/zh-CN.toml

# 2. 应用自动加载（热重载）或重启
```

### 5.2 检查翻译完整性

```moonbit
// scripts/check_translations.mbt

fn main {
  let locales_dir = "locales"
  let files = @fs.list_dir(locales_dir)
  
  // 加载所有 locale
  let catalogs = Map::new()
  for file in files {
    if file.ends_with(".toml") {
      let path = locales_dir + "/" + file
      match Catalog::from_toml(path) {
        Some(catalog) => catalogs.set(catalog.locale.to_string(), catalog)
        None => println("无法加载：" + path)
      }
    }
  }
  
  // 收集所有 key
  let all_keys = Set::new()
  for (_, catalog) in catalogs {
    for (key, _) in catalog.messages {
      all_keys.add(key)
    }
  }
  
  // 检查每个 locale 是否缺少 key
  for (locale, catalog) in catalogs {
    let mut missing = []
    for key in all_keys {
      if not catalog.messages.contains(key) {
        missing.push(key)
      }
    }
    if missing.length() > 0 {
      println(locale + " 缺少 " + missing.length().to_string() + " 个翻译：")
      for key in missing {
        println("  - " + key)
      }
    }
  }
}
```

### 5.3 导出翻译模板

```moonbit
// scripts/export_template.mbt

fn main {
  // 从源代码提取所有 t("...") 调用
  let keys = extract_translation_keys("gui/")
  
  // 生成模板 TOML
  let mut template = "[meta]\nlocale = \"en\"\nversion = \"1.0.0\"\n\n"
  for key in keys {
    template = template + key + " = \"\"\n"
  }
  
  @fs.write("locales/en.template.toml", template)
  println("模板已生成：locales/en.template.toml")
}
```

## 六、高级特性

### 6.1 复数规则（CLDR）

```moonbit
// gui/i18n/plural_rules.mbt

/// CLDR 复数类别
pub(all) enum PluralCategory {
  Zero
  One
  Two
  Few
  Many
  Other
}

/// 根据 locale 和数量选择复数形式
pub fn select_plural(locale : Locale, count : Int) -> PluralCategory {
  match locale.language {
    "en" | "de" | "es" | "it" | "pt" | "nl" => {
      // 日耳曼/罗曼语族：one/other
      if count == 1 { One } else { Other }
    }
    "zh" | "ja" | "ko" | "vi" => {
      // 东亚语言：无复数
      Other
    }
    "ar" => {
      // 阿拉伯语：6 种形式
      if count == 0 { Zero }
      else if count == 1 { One }
      else if count == 2 { Two }
      else {
        let mod100 = count % 100
        if mod100 >= 3 && mod100 <= 10 { Few }
        else if mod100 >= 11 && mod100 <= 99 { Many }
        else { Other }
      }
    }
    "ru" | "uk" | "pl" => {
      // 斯拉夫语族：复杂规则
      let mod10 = count % 10
      let mod100 = count % 100
      if mod10 == 1 && mod100 != 11 { One }
      else if mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14) { Few }
      else { Other }
    }
    _ => if count == 1 { One } else { Other }
  }
}

/// 复数类别转字符串
pub fn plural_category_to_string(cat : PluralCategory) -> String {
  match cat {
    Zero => "zero"
    One => "one"
    Two => "two"
    Few => "few"
    Many => "many"
    Other => "other"
  }
}
```

### 6.2 日期/时间/数字格式化

```moonbit
// gui/i18n/format.mbt

/// 数字格式化
pub fn format_number(n : Double, locale : Locale) -> String {
  match locale.language {
    "en" | "zh" | "ja" | "ko" => {
      // 1,234.56
      format_number_with(n, ",", ".")
    }
    "de" | "es" | "it" | "pt" => {
      // 1.234,56
      format_number_with(n, ".", ",")
    }
    "fr" => {
      // 1 234,56（空格分隔）
      format_number_with(n, " ", ",")
    }
    _ => n.to_string()
  }
}

/// 日期格式化
pub fn format_date(date : Date, locale : Locale) -> String {
  match locale.language {
    "en" => format_date_mdy(date)     // 10/19/2026
    "zh" | "ja" => format_date_ymd(date)  // 2026年10月19日
    "de" => format_date_dmy(date)      // 19.10.2026
    "fr" => format_date_dmy(date)      // 19/10/2026
    _ => format_date_iso(date)         // 2026-10-19
  }
}

/// 货币格式化
pub fn format_currency(amount : Double, currency : String, locale : Locale) -> String {
  let symbol = currency_symbol(currency)
  match locale.language {
    "en" => symbol + " " + format_number(amount, locale)  // $ 1,234.56
    "zh" => symbol + format_number(amount, locale)        // ¥1,234.56
    "de" => format_number(amount, locale) + " " + symbol  // 1.234,56 €
    _ => symbol + format_number(amount, locale)
  }
}
```

### 6.3 RTL 文本方向

```moonbit
// gui/i18n/bidi.mbt

/// 文本方向
pub(all) enum TextDirection {
  LTR  // 从左到右
  RTL  // 从右到左
}

/// 获取 locale 的文本方向
pub fn text_direction(locale : Locale) -> TextDirection {
  match locale.language {
    "ar" | "he" | "fa" | "ur" => RTL
    _ => LTR
  }
}

/// 调整对齐方式（RTL 时左右互换）
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

## 七、实施计划

### 阶段一：基础框架（1-2 天）
- [ ] Locale 类型 + 系统 locale 探测
- [ ] Catalog 加载（TOML 解析）
- [ ] `t(key)` 翻译函数
- [ ] 测试：加载 zh-CN.toml 和 en.toml

### 阶段二：插值 + 复数（1 天）
- [ ] `t_with(key, vars)` 命名插值
- [ ] `t_count(key, count)` 复数形式
- [ ] CLDR 复数规则（简化版）

### 阶段三：GUI 集成（1 天）
- [ ] 组件层使用示例
- [ ] 语言切换 + UI 刷新
- [ ] 热重载支持

### 阶段四：高级特性（可选，2-3 天）
- [ ] 日期/时间/数字格式化
- [ ] RTL 文本方向
- [ ] 翻译完整性检查工具
- [ ] 从源代码提取翻译 key

**总工期：约 3-4 天**

## 八、与桌面软件的对标

| 特性 | Qt (gettext) | Electron (i18next) | Flutter (intl) | 本方案 |
|------|-------------|-------------------|---------------|--------|
| 文件格式 | .po/.mo | JSON | ARB | TOML |
| 分文件存储 | ✅ | ✅ | ✅ | ✅ |
| 复数形式 | ✅ | ✅ | ✅ | ✅ |
| 插值 | ✅ | ✅ | ✅ | ✅ |
| 热重载 | ❌ | ✅ | ✅ | ✅ |
| 类型安全 | ❌ | ❌ | ❌ | （可选）✅ |
| 回退机制 | ✅ | ✅ | ✅ | ✅ |
| CLDR 规则 | ✅ | ✅ | ✅ | ✅ |

## 九、下一步行动

1. **原型验证**：先实现 `t(key)` 基础功能
2. **样本数据**：创建 zh-CN.toml 和 en.toml 示例
3. **集成测试**：在 examples/ 中演示 i18n 用法
4. **文档**：编写翻译文件编写指南

## 十、全库组件改造（选定范围）的落地设计

前文「阶段一~四」是**机制层**建设。本节是**改造层**——把框架自有 UI 文案（审计 D 类）
系统性地接入 t(key)，并解决随之而来的分层与分发问题。

### 10.1 分层原则：机制在框架，目录在应用

框架是**库**（`moon add` 后零配置），不该把某个具体应用的译文编进库。正确切分：
```
gui/i18n/            ← 框架提供「机制」：Locale / Catalog / t() / 加载 / 切换 / 复数 / RTL
locales/*.toml       ← 「目录」属于应用；框架只自带一份 D 类文案的最小英/中目录
                       供框架自绘 chrome（对话框默认按钮、菜单角色、错误文案）使用
```
框架 chrome 文案（D 类，约 10+ 条）随库附带一套；应用可扩展/覆盖同名键。

### 10.2 键命名空间
```
gui.<module>.<component>.<field>
例：
  gui.ui.message_box.ok
  gui.ui.message_box.cancel
  gui.shell.menu.role.copy
  gui.shell.menu.role.paste
  gui.ui.datepicker.month.jan      ← 若走 C 类则改由 date 库，不入此表
```
审计出的 D 类每条一个稳定键；键随代码演进，删除时同步清理目录（见检查工具 5.2）。

### 10.3 迁移分期（按审计 D 类，非 257 全量）

- [ ] **M1**：机制层落地（阶段一~三），提供 `t()` + 加载 + 切换。
- [ ] **M2**：`ui/message_box.mbt`、`ui/overlay.mbt`、`ui/display.mbt` 的 D 类串抽键，
      默认值改为 `t(...)`，随库附带 `locales/{en,zh-CN}.toml`。
- [ ] **M3**：`shell/menu.mbt`(7)、`shell/tray.mbt`、`shell/notify.mbt` 菜单角色/系统通知文案。
- [ ] **M4**：`ui/datepicker.mbt`、`datetime.mbt` → 判为 **C 类**，改接日期库按 locale 出月名/星期，
      **不进 t()**（这是最容易误包的一类，单列确认）。
- [ ] **M5**：审计工具固化（§前置），在门禁里跑「D 类未接 t()」与「目录缺键」两项检查。
- [ ] **M6**：examples/ 加多语言演示；切换语言 → `invalidate` 全窗重绘验证。

> A 类注释、B 类 OS 数据 **明确不碰**；工具若把某串分类错误，按 §前置的四类判据手工纠正并回写判据。

### 10.4 目录分发与跨平台资源路径（真实约束）

外部 TOML 要在运行时被找到，三平台资源根不同：
```
macOS   : .app 内 Contents/Resources/locales/*.toml   （裸可执行无 bundle 时找不到资源）
Linux   : $XDG_DATA_HOME/<app>/locales/  或安装前缀 share/<app>/locales/
Windows :  exe 同目录 locales\
```
- 框架提供 `resolve_locales_dir()`：按平台 + 环境变量（`GUI_LOCALES_DIR`）+ 可执行路径推导。
- **打包/安装**：prebuild 或分发脚本负责把 `locales/` 放进上述位置（macOS 必须进 .app bundle）。
- **降级**：目录缺失时 t() 返回键名并告警，不崩溃（与现有失败降级风格一致）。

### 10.5 与现有绘制的契合点
- 文本绘制已支持任意 UTF-8（`pt_measure`/`pt_draw` 走 Pango），中文/多语言文案无需改绘制层。
- RTL 需要布局层配合：Yoga `set_direction` + `resolve_alignment`(§6.3)，改造期只在有 RTL 需求时接线。
- 字体回退（中文/阿语需相应字体）由 `text/family.mbt` 的 `resolve_family` 承担，属既有能力。

### 10.6 风险
| 风险 | 说明 | 缓解 |
|------|------|------|
| 误包 A/B/C 类 | 注释、设备名、月名被塞进 t() | 审计工具四类判据 + 分期 M4 单列确认 |
| macOS 找不到资源 | 无 bundle 时相对路径失效 | resolve_locales_dir + .app 打包 |
| 性能 | 每帧大量 t() 查表 | Catalog 用 §文本缓存同款哈希（见 text/cache.mbt），命中零开销 |
| 键漂移 | 代码删了但目录留残键 / 反之 | 门禁双向检查（5.2 + M5） |
