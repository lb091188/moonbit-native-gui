# 静态文本选中与屏读语义

「静态文本选中与复制」与「屏读语义」两件事合一份规划：**两个消费者、一块公共地基**——文本偏移映射、Widget 语义字段、焦点链。

- 屏读：screen reader，读屏，把屏幕内容朗读或转点字给视障用户的辅助软件。
- 文本偏移映射：字符偏移↔屏幕矩形。
- Widget 语义字段：name/role。
- 焦点链：已有。

2026-11-03 拍板：屏读语义**做**，走自建桥、不借原生控件白拿；`gui/README.md`「Explicit non-goals: accessibility APIs」的旧口径随批修正为上述表述。拆分待办见 TODO「文本选择与屏读语义」节，状态流转见 [roadmap.md](../docs/zh/roadmap.md)「输入与浮层」「可访问性」两节。

## 定位

- **为什么合一份**：静态文本选中要的命中测试、选区矩形、折行重排稳定性，恰好就是屏读 Text 接口要的「偏移↔矩形」映射表；name/role 字段是 uitest P1 已定的既定计划，见 [headless-tester.md](headless-tester.md)，读屏复用同一对字段。分开做会各修一遍地基。
- **为什么选中在前**：小、独立、不碰平台桥、真机好验；读屏是月级工程，另期分阶段落。
- **总览**：

| 期 | 交付 | 消费的地基 |
|---|---|---|
| 第一期 | `TextLayout` 抽取 + 静态文本 `selectable` 档 + code_view 选中 | 偏移映射，本批抽出 |
| 第二期 | 屏读语义：mac → Linux → Windows 三平台桥 | 偏移映射 + name/role/enabled + 焦点链 |

## 公共地基

### 文本偏移映射：TextLayout，落 gui/input

**现状**：全仓「字符偏移↔屏幕几何」只有一处成形实现——textarea 的显示行模型，算法纯、挂法不纯：

- `TextLine{start, end, width}`，全文以 UTF-8 字节下标计量，见 `gui/ui/textarea.mbt:15-19`；`layout_lines` 按 `\n` 断逻辑行再按盒宽贪心折行，textarea.mbt:25-65；`line_of_caret` 字节下标折行号，textarea.mbt:148-162——三者已是 `pub fn`。
  - UTF-8 字节下标：文本按 UTF-8 编码后的字节序号，一个中文字占 3 字节，光标与选区都以它定位。
- `byte_at`，像素→字节，与 `caret_x_in`/`caret_y_in` 是构造闭包，捕获 `pad`/`line_h`/滚动偏移/`font`，textarea.mbt:237-291——**这是与可复用形态之间唯一的距离**。
- entry 单行档另有 `prefix_width`/`byte_at_x`/`word_range`，gui/ui/entry.mbt:28-92；密码框按遮罩串量宽，entry.mbt:16-28；textarea 已复用 `word_range`，textarea.mbt:523。
- 编辑内核 `@input.Editor` 有意零几何——「内核不碰平台……能在无显示环境下测试」，gui/input/editor.mbt:8-9；选区只是归一化字节区间，editor.mbt:126-138。
- **其余文本件全无映射**：`text`/`text_dyn` 走 Pango 整体排版，测量面 `attach_text_measure` 见 gui/ui/base.mbt:126-189、绘制面 `draw_text_in`→`@text.draw_box_at` 见 base.mbt:193-226，MoonBit 侧不掌握行内几何；`@text` 包无 offset↔position API；code_view 预排版表只到 token 级 x/宽，gui/ui/codeview.mbt:429-454；mdview 自成 span 级行模型，gui/mdview/markdown.mbt:954-965。
  - Pango：GTK 的文本排版库，量宽与折行都在它那边。
  - token：词法单元，代码按语法切出的词。
  - span：带样式的一段文本。

**抽取方案**：

```
TextLayout {
  text : String          // 权威文本（字节下标的参照系）
  font : @text.Font
  lines : Array[TextLine]
  pad : Double           // 文本起点内边距
  line_h : Double
  offset_y : Double      // 垂直滚动偏移（无滚动传 0）
}
```

- 入口，示意：`build(text, width, font, pad?, line_h?, offset_y?)`、`hit(x, y) -> Int`、`rects(start, end) -> Array[Rect]`、`caret_x(at)`/`caret_y(at)`、`line_of(at)`。
  - `rects(start, end)`：选区高亮矩形——把 textarea.mbt:323-337 的画法改成算出来而不是画出来。
- **测宽函数作参数注入**——缺省为 `@text.measure_font` 前缀宽，即原 `seg_width`——与 Editor「内核不碰平台」同一哲学，`gui/input` 维持零平台依赖可无头测试；entry 的遮罩量宽、mdview 的混排联合量宽各自注入自己的量宽器。
- **落 `gui/input`**，与 Editor 同包，编辑内核 = 状态半边 + 几何半边；`layout_lines`/`wrap_units`/`line_of_caret`/`TextLine` 迁走，仓内使用者只有 textarea 与其 wbtest，全仓 grep 证据，无外部破坏，`pkg.generated.mbti` 随生成更新。备选是留在 `@ui`，mdview 已依赖 `@ui`、不构成约束，但按「屏读是第二个消费者」**放低不放高**。
  - wbtest：MoonBit 的白盒测试文件，可直测包内私有函数。
- 这层 API 面就是屏读 Text 接口要的原语，命名与口径一次定对，读屏接入时不再改形态。

### Widget 语义字段：name / role / enabled + 值回调

- `Widget` 是 `pub(all) struct`，见 gui/widget/widget.mbt:80-198，现无语义字段。落 `mut name : String` / `mut role : String`——headless-tester P1 已定，proposals/headless-tester.md:116-117——**另加 `mut enabled : Bool`，缺省 true**——组件的禁用判定在闭包私有，即 `enabled_cell`，gui/ui/form.mbt:64，桥拿不到，而禁用是三平台都必报的属性；超出 uitest「两个字段」口径，但属 a11y 批自加字段，不阻塞 uitest P1。
  - a11y：无障碍，accessibility 的缩写，读屏等辅助功能的统称。
- **role 的单一事实源是字符串**；`widget` 包另立 `pub(all) enum ARole` + `parse`/`to_string` 作桥的解析视图——uitest 消费字符串、桥内部消费枚举，避免「测试一套 role、读屏一套 role」的双源。`Node::named` 包装器写 `name`，headless-tester.md:121-128，a11y 不另起包装器。
- 值回调仿 `im_cursor` 形态——回调首参控件本身、不捕控件进闭包，widget.mbt:150——`mut a11y_state : Option[(Widget) -> (String, String)?]` 与 `mut a11y_text : Option[(Widget) -> String?]`，首批组件各自在构造处挂。
  - `a11y_state` 回调：语义状态串 + 值串。
  - `a11y_text` 回调：文本内容。
- `bind_label` 动态文本不回写 `w.name` 是 headless-tester 已记的坑，§6.3；uitest 修时 a11y 同批受益——与第一期「文本变化清选区」是**同一个钩子点，一次改两处**。
- headless-tester 开放问题「将来接无障碍时是否复用同一套字段（倾向复用）」见 headless-tester.md:214，**就此收口：复用**。
- **破坏性变更**：`pub(all) struct` 加字段会破字面量构造，仓内仅 `Widget::new()` 一处构造点，widget.mbt:204-248，风险可控；字段与 uitest P1 **一次加齐**，即 name/role/enabled/a11y 回调，避免两次破坏，发版说明记录。

### 焦点链，已有不新做

`FocusStack` 全套，gui/base/focus.mbt:13-169；`App::move_focus`/`focus_by_id`，gui/widget/app.mbt:629-674；Tab 序 = 控件树序，widget.mbt:574；焦点翻转回调 `on_focus_change`，widget.mbt:141——第二期的焦点事件上行直接消费，不新增采集点。

## 第一期：静态文本选中与复制

### 交互定案

- **选区状态**：每件自己的只读 Editor，roadmap 拍板；偏移为唯一状态，行矩形每帧按当前 layout 现算。Editor 是独立对象，注册表/菜单闭包只准捕 Editor/thunk、不准捕 Widget——回调禁捕铁律，widget.mbt:96-98。
  - thunk：一小段延迟执行的闭包，取文本时才调用。
- **互斥**：`@widget` 加窗口级**选区持有者注册表**，单 owner，记 widget id + 取文本 thunk；先例是拖拽的进程级 `drag_hover()`，gui/widget/drag.mbt:255。展示件之间起拖即覆盖 owner，折叠为空即清；编辑件不进注册表——焦点唯一性已保证同时只有一个编辑选区。陈旧 owner，即控件已摘除，最多复制出一份旧文本，无害，记档。
- **焦点口径：不进 Tab 链，`focus_id=0`，悬停不选、点击即选**。理由：① `focus_id` 非 0 即进 Tab 链且无跳过机制，widget.mbt:574、app.mbt:629-634，可选文本海量，全进 Tab 链键盘环绕即不可用；② 点击不可聚焦区已有 blur 语义，app.mbt:782-799，点文本让输入框失焦，与 Web/原生桌面行为一致。
  - Tab 链：按 Tab 键在可交互控件间循环移动焦点的顺序链，本栈即 `focus_id` 非 0 的控件声明序。
  - blur：控件失去焦点。
- **键盘与复制**：焦点链给不了静态文本按键，Ctrl+C 走宿主内建支——App 的 Key 分支在 fallthrough 前后加一支：owner 非空且 primary+C 时调 owner 的复制 thunk，写剪贴板经 `Editor::copy`→`clip_publish`，gui/input/editor.mbt:400-409。不选「每件注册 fallthrough」：注册无反注册通道，app.mbt:55-57，海量文本件会永久堆积闭包。Ctrl+A 记开放点——无焦点编辑件时放行给 owner 是合理档，可后补。
  - fallthrough：按键没被控件消费时下放给宿主继续分发的机制。
  - **已知限制，记档**：焦点在输入框且其 Editor 无选区时，primary+c 仍被编辑内核消费——editor.mbt:548-550 无条件 handled——此时展示件选区复制不了。P1 接受，行为=「复制焦点件」；要放开需 entry/textarea 前置「无选区放行复制键」，一处小改可同批或后补。
- **指针交互**：

| 交互 | 定案 | 依据 |
|---|---|---|
| 单击 | 折叠定位到命中偏移，走 `TextLayout::hit` | textarea.mbt:521-528 模板 |
| 双击 | 选词，复用 `word_range`，非 ASCII 连续整段算词内 | entry.mbt:71-92、textarea.mbt:522-525 |
| 三击 | P1 不承诺；宿主 `on_triple_click` 已留，widget.mbt:111，选整段逻辑行后续再开 | — |
| 拖选 | Down 记 anchor，Move 经按下捕获持续更新，出件不丢 | textarea.mbt:532-539、widget.mbt:673-680 |
| Shift+点击 | 扩展选区，anchor 保留、终点取命中。**新增能力**：entry/textarea 现状都没有，在共享指针逻辑里一次做对 | PointerEvent 带 mods，widget.mbt:624-630 |
| 右键 | `show_edit_menu(ed, can_edit=false, can_copy=true)`；祖先 `context_menu_for` 优先，包了自定义菜单时让位 | gui/ui/clipboard.mbt:33-96、gui/ui/overlay.mbt:1002-1055 |

- 菜单档位：静态文本 = `can_edit=false, can_copy=true`，介于只读框与密码框之间，密码框为 `can_copy=!ro && !mask`，entry.mbt:346；静态文本无遮罩概念。文案走 `gui.ui.edit.*` 既有表。
- **I-beam 光标**：selectable 档设 `w.cursor = CURSOR_TEXT`，textarea.mbt:232 同款；mdview 档用 `cursor_fn` 动态判「链接段手型、其余 I-beam」，`hit_url` 现成，markdown.mbt:1135-1175。拖选中光标随捕获停在起手档，宿主行为，组件不处理。
  - I-beam：文本区常见的工字形鼠标指针。
- **动态文本选中期间变了**：选区清空。`relabel` 路径，base.mbt:281-285，同步 `ed.set_text(新串)`——`set_text` 清 anchor/选区有内核先例，editor.mbt:236-249。**不做偏移迁移**，即 diff/锚点补偿：整段换内容场景迁移收益不抵复杂度。
- **折行重排稳定**：按字符偏移锚定，不引入锚点+偏移量。layout 以 `(text, 盒宽)` 为缓存键重折，textarea.mbt:210-221，矩形现算现画，偏移不需补偿；`Editor::selection()` 已归一化为无方向区间，editor.mbt:126-138。mdview 侧 `fold_at` 只在单元边界断行、超长单元硬切保拼接序，markdown.mbt:998-1023，全局偏移可重建。

### 范围

- **首批，本条主体**：① `gui/input` 抽 `TextLayout`，textarea/entry 改用，等价重构、既有 wbtest 钉住；② `text`/`text_dyn` 加 `selectable? : Bool = false` 档，可选参数纯增量，文本件单一入口已定案见 gui/ui/basic.mbt:343-350，不开并列入口——只读 Editor + 高亮 + 单击/双击/拖选/Shift+点击 + Ctrl+C 宿主支 + 右键菜单；**测量面与绘制面同步切 TextLayout**，见坑 1；③ code_view 选中：预排版表加字节偏移列，逐 token x/宽已有见 codeview.mbt:429-454，行号列排除在选区外——`num_off` 已隔离，codeview.mbt:424-428——复制按行拼 `\n`，横滚坐标经控件矩形平移天然正确。

**落地注记**

- 时间：2026-11-03，markdown 段落选中已合入。

- 复用面开在 @ui：`text_sel_new` / `TextSel::pointer(hit)` / `range` / `sync` / `give_up`——混排件自带几何，只把「坐标→字节偏移」的 `hit` 交给它，交互链与 selectable 文本同一条，不再复制第二份。
  - 交互链：单击/双击选词/拖选/Shift 扩选/右键复制/系统槽。
- mdview 侧的逐字几何口径：**段界取联合排版**——`line_geo` 的 xs/ws，即真正绘制用的 AttributedText 量的那份——**段内按逐字宽线性分摊到该段联合宽**——既不退回顾忌逐段单独量宽，mac 真机累加比联合窄 11px 的老坑，也不逐字建绘制对象，一行几十次 C 排版会话。`cx`/`cidx` 首次用到才建、按行备忘。
- 字节计量：`ltext` = spans 文本拼接，软折行不插换行，所以复制出来是这段原话；`char2byte` 一次建表，Editor / AttributedText / 命中都按字节。折行时给每个渲染段记 `lstart`，即该段首字在原文里的字符下标，命中结果就是原文下标，不受「同风格单元被合并」影响。
- 与链接的分工没变：Down 先问 `hit_url`，命中就是打开链接；落空才进选中链。悬浮光标在链接上是手型、其余是 I 梁。
- 用例判据，无头可跑：单击落点=第 3 字左半 → caret 9 字节；拖到第 6 字右半 → 选区 `[9,18]`；混排段 240 定宽折多行后拖到末行 → 末端越过前 20 字且过半。同点 400ms 内连击算双击，即选中词，夹具里别连按同一点。
- 缺省档 `selectable=false` 没装选中态、不建逐字表——用例断言 `md_sel_states` 里没有它。

- **次批，同条延续不混批**：markdown 段落。`md_rich_label` 已有独立行模型与链接交互面，逐字命中要按字节前缀做混排联合量宽——`joint_w` 成本模式，markdown.mbt:910-920——并处理混排字体边界，markdown.mbt:830-848 的坑；等首批的注册表/菜单/复制在纯文本上闭环再接。
- ~~**缓批（单独立项）**：`AttributedText` 逐字选中~~ **已解决，2026-11-04**：缓批前提「`@text` 无逐字几何 API 要先动三平台 C 桩」被证伪——`measure_font(前缀)` 就是该前缀在给定字体下的精确 shaping 宽，三平台 measure 路径早就通了，entry 光标 `TextLayout::caret_x` 一直用这个口径。markdown 选中改为「段界取联合排版 + 段内逐字边缘取前缀实测量」，联合排版即跨段 kerning 一起算；旧口径按比例分摊的 shaping 误差本机实测 19px，已消除。多字体逐字，即 AT-SPI Text 的 GetCharacterExtents 等，仍待消费者出现时开 `rt_*` 逐字游标。
  - shaping：把一串字符按字体规则排成字形并量出宽度的过程。
  - kerning：相邻字符对的字距微调。
  - AT-SPI：Linux 的无障碍服务协议，读屏 Orca 经它读应用。

### 风险与坑

1. **测量面与绘制面必须同源，最大坑**：`text()` 现在折行由 Pango 在 `draw_box_at` 里做，`layout_lines` 是 MoonBit 贪心折行——**两者断点是否逐行一致没有对比数据，未量化**。selectable 档必须整套切换，测量答高、绘制画行、命中映射全走 TextLayout，只切绘制不切测量必出「行数不符→裁字/留白」。缺省档一行不动，风险被 `selectable` 开关隔离。
2. **对齐与省略**：`layout_lines` 无 align/ellipsis/max_lines。居中/居右档命中与高亮 x 要补对齐偏移，「只挪字不挪光标」教训见 entry.mbt:178-189；省略档口径定**所见即所得**——选中与复制都钳制到省略号前的显示范围，与浏览器「复制 DOM 全文」不同，记档差异；max_lines 同理按截断点钳。
3. **前缀量宽 O(n²)**：命中与高亮逐前缀调 `measure_font`；mdview 已踩过并给对策——单元缓存 markdown.mbt:829、惰性建行 745-747。P1 文本件尺度可接受；code_view 走预排版表零增量。
4. **双击判定别造第三套**：组件手工 400ms/4px，textarea.mbt:514-516，与宿主 tracker，widget.mbt:107-113，已并存两套，共享逻辑沿用模板一套。
5. **主修饰键平台差**：mac 是 Cmd，editor.mbt:504-509；宿主内建支与菜单快捷词走 `CmdOrCtrl` 同源词表，app.mbt:63-66。
6. **回收与引用环**：注册表与菜单闭包只捕 Editor/thunk，禁捕 Widget——widget.mbt:96-98 铁律；owner 陈旧无害。
7. **浮层菜单边界**：右键菜单是自绘浮层、无键盘导航——沿现状，不在本条扩。
   - 浮层：叠在主窗口之上的独立小窗，如菜单、下拉候选。
8. **系统剪贴板降级**：探测不可用自动降内部槽，clipboard.mbt:1-3、17-26，测试用 `use_system_clipboard(false)`——既有档位，真机清单覆盖。

### 验收口径

- **门禁**：`cd gui && moon check --deny-warn` 零错误零警告；`moon test ui input widget` 全绿；entry/textarea/editor 既有 wbtest 断言条数不减，改用 TextLayout 属等价重构，由既有用例钉住：点击定位/双击选词/拖选/只读/遮罩定位——entry_wbtest.mbt:172/188/205/252/399、textarea_wbtest.mbt:98/137。
- **新 wbtest，无头可断言**：命中偏移——合成指针事件后断言 `Editor::selection()`，textarea_wbtest.mbt:137 先例；双击选词区间；`TextLayout` 纯函数直调，build/hit/rects，textarea_wbtest.mbt:48-95 先例；复制文本——`use_system_clipboard(false)` + 合成 Ctrl/Cmd+C + `Editor::clip_text()`，entry_wbtest.mbt:230-231 先例；文本变化清选区；resize 重折后同一偏移的矩形仍落正确行；码点边界，中文字上命中不劈半字。未来 `gui/uitest` 以 name 定位复跑同款。
  - 无头：不开窗口、纯后台跑测试。
- **真机人工**，视觉与系统交互，助手不下结论：高亮色深浅主题可辨；I-beam 出没时机；双击/拖选手感；右键菜单浮层收框；系统剪贴板互通，即 xclip / clip.exe / pbcopy；bind_label 变化后选区消失不残留；resize 后高亮跟新折行；code_view 横滚下选中不串行。条目按平台补进 `测试文档/测试用例.md`。
- **流转**：动工前进 TODO；完成后 roadmap 条目移「已实现」按平台标状态；showcase 补 selectable 档与 code_view 选中的演示段落。

**落地注记**

- 时间：2026-11-03，TextLayout 地基已合入。

- 形态：`gui/input/text_layout.mbt` —— `TextLine` / `wrap_units` / `layout_lines` / `line_of_caret` 从 `@ui` 迁来，0.x 破坏，外部使用者全仓 grep 只有 textarea 与其 wbtest；新增 `TextLayout{text, lines, pad, line_h, offset_y, measure}` 与 `build` / `line_of` / `caret_x` / `caret_y` / `hit`；测宽器 `(String, Int, Int) -> Double` 是**必填参**，不给缺省，`gui/input` 因此仍只依赖 utf8 + base，零平台桥。
- `rects(start,end)` **本批不做**：没有消费者即死字段，`letter_spacing` 的教训；随 selectable 档一起落，届时绘制面从「画出来」切「算出来」。
- textarea 改用后行为零变化：`moon test base shell widget ui render text theme icons sys input win dbus chart mdview style router` 1227/1227，其中 input 包新增 8 条假测宽器用例——折行、pad 扣宽、单段超宽不拆词、命中不劈半字、滚动平移、空文本也给一行。
- selectable 档已落，2026-11-03 同批：`rects` 随首个消费者落地，即 `gui/ui/textsel.mbt` 的选区高亮，没有先塞孤儿 API。落地面收在三处——`text`/`text_dyn` 各加一个 `selectable? : Bool = false`、内核 `text_node_of` 多一个参数并在挂载闭包里二选一，`if selectable { sel_setup + 本档 on_draw } else { 原两行 }`，缺省档因此物理上不可能被碰到；测量面 `attach_sel_measure` 与绘制面 `draw_sel_text` 共用 `sel_layout`，即同一份行模型，装饰线抽成 `draw_text_deco` 两档共用。
  - 定案外取舍一：折行块内不逐行对齐，整块按 `align` 偏移，块内各行贴块左缘。
  - 定案外取舍二：`max_lines`/省略复用 `@text.clamp_lines`，升为 pub → 选中范围=可见范围。
  - 定案外取舍三：`relabel` 按控件 id 查「变化收尾口」`sel_hooks`，有则走本档——重设测量标脏 + Editor 换文清选区 + 让出持有——无则原路 `attach_text_measure`。
  - 钩子共用：动态文本、`bind`/`bind_label` 与注册表共用同一个钩子点，一次改两处。
  - 宿主复制支插在焦点链吃掉之后、`fire_key_fallthrough` 之前，即 `App::fire_selection_copy`，于是「焦点输入框自己有选区时复制焦点件」这条已知限制自动成立。
- entry **已切**，同批收尾：单行档前缀宽与像素→字节改成走 `@input.TextLayout`，滚动/居中的 origin 计算与 y 方向一律不动——单行档的 y 不参与定行。既有 entry_wbtest 断言条数不减、246/246 全绿，点击定位、遮罩定位、拖选、只读各条同批复跑。
  - `entry_layout` 口径：一个量不到的宽 = 一行。
  - 测宽器按遮罩档量「原文前缀的显示宽」，`prefix_width = caret_x`、`byte_at_x = hit`，`pad=文本起点` 复原「前缀 + 起点 ≤ x」的旧式。

## 第二期：屏读语义

### 桥的既有模子，新桥照哪个模子挂

- `gui/win/stub.c` 三平台分段，Win32 :33 起、GTK3/Linux :4797 起、macOS Cocoa :8056 起。两条硬纪律写在文件头：**循环归 MoonBit**、**不做 C→MoonBit 回调**——stub.c:22-23，蹦床坑记 `experience/adaptation/common.md`「MoonBit ↔ C ABI」节——本方案不破例。
  - 蹦床：C 反向调 MoonBit 函数的技术，易踩栈与生命周期坑，故被禁。
- 消费式轮询槽已成体系：`wm_tray_poll`/`wm_hotkey_poll`/`wm_menu_poll`/`wm_inst_poll`/`wm_dragdnd_poll`，stub.c:1941/3680/3867/4764/2588，extern 声明全在 gui/win/ffi.mbt。
  - 轮询槽：MoonBit 每帧主动来 C 侧拉一次数据的固定接口。
- **Win32 纯 C 模式 COM 先例完整**：跨进程拖放自建 `IDropTarget`，静态 vtbl，stub.c:2127/2531/2560；`IDataObject`/`IEnumFORMATETC` 全套，stub.c:2800-3067；`CoCreateInstance(CLSID_TaskbarList)`，stub.c:3432-3440；WIC，stub.c:4083-4095。C 模式取 GUID 走链接期 uuid.lib 符号、不能用 `__uuidof` 的坑已有注释，stub.c:61-68。
  - COM：Windows 的组件对象模型，跨语言二进制接口，靠 vtable 分发方法。
  - vtbl：虚函数表，COM 对象的方法指针表。
  - GUID：全局唯一标识符，COM 类与接口的 128 位编号。
  - WIC：Windows Imaging Component，系统的图像编解码组件。
- **mac 挂点现成**：`WMView : NSView <NSTextInputClient>`，stub.c:8128——输入法通道就在这个类上，NSAccessibility 协议挂同一个类；每窗状态槽 `WMState`，stub.c:8151；槽表 `wm_windows`，stub.c:8205。
  - NSAccessibility：macOS 的无障碍协议，读屏 VoiceOver 经它读应用。
- **gui/dbus 是纯 MoonBit D-Bus 栈且已有 service 端能力**：入站方法调用分发 `CallReq` 与回包，bus.mbt:66-116；`dbus_emit_signal_session`，bus.mbt:975；`dbus_pump` 非阻塞收包，bus.mbt:234；SNI 托盘就是完整服务端先例——导出对象、应答 Properties Get/GetAll/Set，sni.mbt:690-757；Introspect XML，sni.mbt:600/677；复杂签名 `(ia{sv}av)` 编解码。dbus 泵已挂进 `App::step`，gui/shell/instance.mbt:448-458，a11y 连接并入同一泵，不新开线程。
  - D-Bus：Linux 桌面通用的进程间消息总线。
  - SNI：StatusNotifierItem，Linux 现行托盘图标协议。
  - Introspect：D-Bus 的自描述接口，列出对象的方法与信号。

### 语义模型与首批控件

- **首批最小可信控件集，八类**：`button` / `checkbox` / `switch` / `radio` / `textbox`——单行/多行/密码同 role，密码加保护态——`slider` / `combobox` / `label`，静态文本只读。前七类三平台 API 都有直接对位的 role/pattern；静态文本不进清单则「窗口里有什么」念不出来，且 Text 接口的逐字朗读消费者就是它。`group`/`list`/`tree` 容器降噪类不进首批，随「键盘可达性」条目一起。
  - role：控件在无障碍语义里的角色名，如按钮、复选框。
  - pattern：UIA 里按角色挂的能力接口族，如可调用、可切换。
- **state 不进 Widget 字段，推送时现算**：聚焦——宿主每帧同步，widget.mbt:735-747——可聚焦即 `focus_id != 0`、屏显即 rect 与 is_painted 推导，均由桥现算；唯一例外是 `enabled`，进字段，见公共地基节。
- **name 缺省规则**，显式 `named()` 优先，否则按序取第一个非空：button/checkbox/link 取可见文本；radio 取本项 option 文本；switch 取 `on_text`/`off_text`、皆空退本地化「开关」；input/textarea 取 placeholder、再退「编辑框」；slider 无文本退「滑杆」，靠 role+value 朗读；select 取当前值或 placeholder；label 取自身文本，随 bind_label 回写。
  - placeholder：输入框的占位提示文字。

### 桥架构

三个候选的取舍：

- 候选 a：MoonBit 建语义树快照、C 桩代理回查——查询下行要 C→MoonBit 回调，撞死纪律，否。
- 候选 b：语义全在 C 桩——控件状态活在 MoonBit，draw 时读 Store，C 桩平行树必然漂移，否。
- 候选 c，**定案**：「属性下行直调 + 查询下行 C 侧自答 + 语义脏帧尾对账」：

- **语义槽表，C 侧**：每个在树控件一条记录，含 id、role 码、name、state 位、value 串、rect、文本摘要。MoonBit 经普通 extern 直调 `wm_a11y_set(...)`/`wm_a11y_remove(...)` 写表——与 `wm_present` 同形态，高频数据下行直调，ffi.mbt:56-62，不需要任何 C→MoonBit 通道。
- **查询下行自答**：读屏查 role/name/state/矩形时，C 桩从本地槽表应答，不经 MoonBit、不进渲染路径；整树枚举风暴被槽表挡在 C 侧。
- **事件上行 = MoonBit 推、C 桩转平台**：MoonBit 在语义变化点调 `wm_a11y_event(...)`，C 桩发平台事件，mac `NSAccessibility.post`、Win `UiaRaiseAutomationEvent`、AT-SPI 信号。方向与托盘轮询槽相反——那边 C 产事件 MoonBit 拉——但通道同为朴素 extern 直调；推而非拉是因为变化时机只有 MoonBit 知道。
  - 语义变化点：焦点翻转 `on_focus_change`、挂摘钩子 `widget_mount_hook`/`widget_discard_hook`，widget.mbt:277/307，以及帧尾对账发现的值变化。
- **帧尾对账代替逐点追踪**：组件状态翻转点分散，闭包内写 Store，逐点埋推送必漏。口径：`App::step` 在 `paint_frame` 之后、`present` 之前对挂了 a11y 回调的控件重读值，与槽表比对，变了才推；rect 同帧取 `collect_abs` 结果，widget.mbt:453-467，不推旧矩形。对账范围是一屏几十个交互控件，成本可忽略——与 uitest「`frame()` 无条件重算」同哲学，拿不确定性换简单性。
- **定位句柄**：槽表 key 用 `Widget.id`，widget.mbt:82；平台运行时 id——AX 元素指针 / UIA GetRuntimeId / AT-SPI 对象路径 `/app/win/widget/<id>`——由 C 桩派生，映射单向无循环依赖。
  - UIA：UI Automation，Windows 现行无障碍框架。
  - AX：macOS 无障碍对象的简称，源于 accessibility。

### 三平台最小实现面

**macOS，桥面最薄**：`WMView` 加 NSAccessibility 协议——`isAccessibilityElement`/`accessibilityRole`/`accessibilityLabel`/`accessibilityValue`/`accessibilityFocused`；子件遍历用 `accessibilityChildren` 返回轻量元素数组，每控件一个轻量对象，只持槽 id，属性 getter 现查槽表；焦点元素走 `accessibilityFocusedUIElement`；事件上行 `NSAccessibility.post(element:notification:)`。浮层是独立 NSWindow，各窗各挂一棵 AX 子树，与 overlay 体系天然对齐。**暴露自身控件不需要辅助功能授权**——`AXIsProcessTrusted` 那套是读别人用的，stub.c:11328 现行用法。无 IPC、无握手、无 COM。
  - IPC：进程间通信。

**Windows，UIA provider，MSAA 不做**：窗口过程 `wm_wndproc`——stub.c:546，现无 `WM_GETOBJECT` 分支——加 `WM_GETOBJECT` → `UiaReturnRawElementProvider`。每控件一个 provider 实现 `IRawElementProviderSimple`，HWND 宿主经 `UiaHostProviderFromHwnd`；`IRawElementProviderFragment`，Navigate/GetRuntimeId/BoundingRectangle/SetFocus；加根节点 FragmentRoot。pattern 按角色挂：`IInvokeProvider` 按钮用、`IToggleProvider` 勾选/开关/单选用、`IValueProvider` 输入框/下拉用、`IRangeValueProvider` 滑杆用、`IExpandCollapseProvider` 下拉弹出用。provider 对象只持槽 id、vtbl 共享静态表——**与 `IDropTarget` 现行形态完全同款**，生命周期由槽表管，stub.c:2446-2448 口径。选 UIA 不选 MSAA：读屏如 NVDA 优先 UIA、缺了才回退；自绘无 HWND 子件走 MSAA 反而要 windowless IAccessible/IAccessible2 这类第三方协议面。
  - MSAA：Microsoft Active Accessibility，Windows 旧无障碍协议。
  - NVDA：Windows 上常用的开源读屏。
  - HWND：Windows 的窗口句柄。

**Linux，AT-SPI，应用是被读的 service 端**：链路——从会话总线 `org.a11y.Bus` 取 `GetAddress`，读屏活跃态看 `IsEnabled`；→ 连 a11y 总线；→ 以 `org.a11y.atspi.Socket.Embed` 向 registryd 注册，registryd 即 `org.a11y.atspi.Registry`；→ 导出对象树：每控件一条对象路径，实现 `org.a11y.atspi.Accessible` + `Component`，GetExtents/GetAccessibleAtPoint；+ 按角色的 `Text`/`Action`/`Value`/`Selection`。事件上行在控件路径发 `org.a11y.atspi.Event.Object` 信号，事件体签名 `(siv)`。**现成度**：CallReq 分发回包、发信号、Properties 应答、Introspect、复杂签名编解码、每拍泵全部复用。**差距三条**：① Conn 硬编码两条总线，bus.mbt:13-16，扩第三条任意地址连接是局部改动；② `Socket.Embed` 握手与 registryd 交互是新代码，协议面小；③ AT-SPI 其余签名，`ai`/`as`/`a(so)` 等，按 wire.mbt 现状推测能吃，**需 wbtest 逐个钉，未核**。
  - a11y 总线：Linux 上无障碍专用的 D-Bus 总线，地址由 org.a11y.Bus 提供。
  - registryd：AT-SPI 的注册中心守护进程，应用在此登记自己的控件树。
  - service 端：D-Bus 上提供接口、应答调用的一方；本应用对读屏是 service 端。

### Text 接口

消费一期 TextLayout 的对外形态，偏移一律 UTF-8 字节、与 Editor 全栈口径一致：

```
pub fn Widget::a11y_text_in_range(self, start : Int, end : Int) -> String?   // 文本区间
pub fn Widget::a11y_offset_rect(self, byte_offset : Int) -> Rect?            // 偏移→屏幕矩形
pub fn Widget::a11y_rect_offset(self, x : Double, y : Double) -> Int?        // 屏幕点→偏移
pub fn Widget::a11y_caret(self) -> Int?                                      // 光标偏移
```

平台对位：AT-SPI `Text` 的 GetStringAtOffset/GetCharacterExtents/GetOffsetAtPoint/CaretOffset；UIA `ITextProvider` range 查询，最小实现可先只报 Value + BoundingRectangle、字符粒度降级——分期内的取舍点；mac `accessibilityStringForRange:` 等。编辑框内容由 `Editor::get_text_in_range` 直接支撑，editor.mbt:175。**桥出口换算责任在 MoonBit 侧换算表**：三平台偏移单位不同，AT-SPI 字符、UIA 文本单元、mac UTF-16 单元，单测钉住——本节最大的坑。
  - UTF-16 单元：macOS 文本偏移以 16 位编码单元计，与 UTF-8 字节不是一回事。

### 阶段排序

**公共地基 → macOS → Linux → Windows。**

| 阶段 | 内容 | 理由 |
|---|---|---|
| 0 | Widget 加 name/role/enabled + a11y 回调面；ARole 枚举；C 侧语义槽表；帧尾对账；gui/README.md 口径修正随批 | 与 uitest P1 同批落字段，破坏性变更一次做掉；槽表与对账是三平台共用件，无平台风险 |
| 1 | macOS 最小实现面 + VoiceOver 验收 | 桥面三者最薄：ObjC 方法直调、无 IPC、无注册握手、无授权；挂点现成。最快端到端验证阶段 0 的槽表/推送/对账 |
| 2 | Linux AT-SPI + Orca 验收 | dbus 底子厚，SNI 服务端完整先例，但要补第三总线、Embed 握手、逐控件对象树四接口——协议面最繁琐；桌面矩阵 XFCE/deepin 实测成本也在此期 |
| 3 | Windows UIA provider + NVDA / Accessibility Insights 验收 | COM 接口族最重，每控件 provider + 五 pattern；有 IDropTarget 同款先例但接口数量与调试生态决定它最慢；放最后时槽表已稳定，纯增量 |

- VoiceOver：macOS 内置读屏。
- Orca：Linux 桌面常用读屏。
- ObjC：Objective-C，macOS 原生开发语言。
- Accessibility Insights：微软的 Windows 无障碍检查工具。

每期平台内再切四批：静态树暴露 → 状态与值 → 事件上行 → Text 接口。整体月级：阶段 0 约 1–2 周、1 约 2–3 周、2 约 3–4 周、3 约 4–5 周。

- 性质：估计值，按 pattern 接口族与真机调试量折算。

### 风险与坑

1. **C→MoonBit 回调纪律的边界**：本方案不破例——查询全由 C 桩槽表应答。若 spike 发现槽表应答不了的查询形态，宁可 MoonBit 推更全的快照，不加重蹦床，见 `experience/adaptation/common.md`「MoonBit ↔ C ABI」节。
2. **语义槽与控件树对账**：挂摘已有钩子，widget.mbt:277/307，登记/注销接同一对；**不清账 = C 侧幽灵控件**，即读屏读到已删控件，与样式 resolved 侧表泄漏坑同型，widget.mbt:301-306。
3. **绘制态 ≠ 语义态的时差**：组件 draw 时读 Store，帧尾对账在 paint_frame 后，理论窗口内查询可能读到上一帧值——读屏查询频率下可接受，不加锁；对账必须排 present 前，否则推的是旧 rect。
4. **UIA 的 COM 面新坑**，2026-11-03 定案：CLSID/IID 取法=SDK 头声明 + 链接期取 `uiautomationcore.lib` 符号，确为 WIC 套路，C 模式用不了 `__uuidof`；**pattern 对象的 COM 布局坑**——vtable 指针必须是结构体首成员、QI 对 IUnknown 与主接口同回主接口指针，否则方法收到的 `self` 偏移错位直接读崩，本批实测踩到，写法钉在 uia_provider.c 头注；另：BSTR 是 UTF-16，快照 UTF-8 字段必须 `MultiByteToWideChar` 转换，首批的 `SysAllocStringByteLen` 直拷会让中文名乱码。provider 的 `Navigate` 方向逻辑易错，Accessibility Insights 树形视图当回归镜。
  - CLSID/IID：COM 的类 ID 与接口 ID。
  - BSTR：Windows 的 UTF-16 计长字符串类型。
5. **AT-SPI 未定项**，2026-11-04 全部实证回填，见 experience/adaptation/linux.md：`Socket.Embed` 在 2.52 是 `(so)→(so)`、**旧 `RegisterApplication` 已废**，Registry 只剩 RegisterEvent 族；Text 偏移单位是**字符**，即码点；XFCE/deepin 的 a11y bus 启用状态仍待桌面矩阵实测，S 系列 spike。
6. **mac 弹层窗的 AX 树**：无边框弹层默认不能成为 key window，stub.c:8146，菜单/下拉候选是独立窗各挂各的；VoiceOver 对多窗 app 的焦点切换行为待真机验。
  - key window：macOS 里接收键盘输入的当前窗口。
7. **焦点语义差**：本栈焦点是控件级，平台焦点是窗级——窗内控件焦点变化平台无感知，三平台 focus 事件全靠手工上行，漏发 = 读屏停在旧控件。
8. **密码框**：value 不外泄明文，报保护态——UIA `IsPassword`、AT-SPI 状态位、mac 走 value 置空 + role 不变；读屏读圆点由读屏侧自理。
9. **性能**：查询风暴被 C 侧槽表挡住，零渲染路径接触；MoonBit 侧推送增量，变了才推，一屏几十控件量级每帧对账 <1ms，估计值，阶段 0 落地用现有分段账本 app.mbt:1067-1068 实测；Linux 侧 Orca 遍历走 `dbus_pump` 非阻塞泵，不卡 `App::step`。

### 验收口径，真机读屏最小清单

真机由用户执行，助手给操作步骤：

- **macOS / VoiceOver**，Cmd+F5 开关：①Tab 遍历 showcase 表单页，每控件朗读「名字， 角色」；②Space 切 checkbox/switch，朗读「已勾选/未勾选」翻转；③输入框聚焦后逐字输入，VoiceOver 逐字符朗读；④对按钮/勾选用 VoiceOver 默认 press，动作真实触发且不双触发。
- **Windows / NVDA**：①Tab + 方向键遍历同一页，朗读 role/name/状态；②Accessibility Insights for Windows 打开，树里可见完整控件层级，选中滑杆看 RangeValue 随拖动更新；③对按钮/勾选/下拉调用读屏的 Invoke/Toggle/Expand，动作应真实触发且不与应用自己的点击双触发；④中文名不乱码。
- **Linux / Orca**：①Tab 遍历朗读按钮/勾选/开关；②Orca flat-review 逐行读窗口内容，静态文本全部可读；③对按钮用 Orca 默认 press，动作真实触发且不双触发；④中文名与逐字偏移按字符不走字节。
  - flat-review：Orca 的平铺审阅模式，不管控件结构、按屏幕行逐行读。
- **通用回归**：未开读屏时启动、帧账本读数与既有 examples 行为零变化；三平台 `moon check` / `moon test` 零错误零警告照常门禁。

## 不做

- **MSAA / windowless IAccessible**：选 UIA provider 一条路，不双轨。
- **静态文本进 Tab 链 / 焦点环**：可选文本海量，进链键盘环绕即不可用；键盘可达性条目是全量控件 Tab 序扫描，静态文本不在其中。
- **跨件连选 / 键盘方向键移动展示件选区**：单件单区间；无焦点即无键。
  - 依据：浏览器同款。
- **选区偏移迁移**，即 diff/锚点补偿：动态文本变化即清选区。
- **group/list/tree 容器降噪 role**：随「键盘可达性」条目一批。
- **C→MoonBit 回调破例**：查询一律 C 侧槽表自答。

## 未核项清单，开工前先回证

1. `layout_lines` 与 Pango 折行的断点差异幅度——无对比数据，方案以「同源切换」规避而非假设一致。
2. UIA 头文件/GUID 在 MSVC 纯 C 模式的取法——**已回证**，2026-11-03：SDK 头声明 + 链接期符号，即 uiautomationcore.lib，与 WIC/uuid.lib 同套路；本机无 MSVC，用「最小 Windows 头桩 + gcc -fsyntax-only」对 Win32 分支做语法与 vtable 项数校验，顺手抓到 snprintf 缺 <stdio.h> 与 COM 偏移两处真问题。
   - MSVC：微软的 C/C++ 编译器。
3. NVDA 对「单 HWND 全自绘」provider 树的遍历质量——阶段 3 真机确认。
4. AT-SPI `Socket.Embed` 与旧 `RegisterApplication` 的版本兼容细节——阶段 2 spike。
5. AT-SPI Text 偏移单位是字符还是字节的 spec 原文——阶段 2 spike。
6. XFCE/deepin 的 a11y bus 实际启用状态——随桌面矩阵实测。
7. VoiceOver 对多窗 app 含浮层窗的焦点切换行为——阶段 1 真机。
8. 帧尾对账与整树快照成本——阶段 0 落地用分段账本实测。
9. 宿主内建复制支与 mac `fire_system_keys` 的先后无冲突——代码阅读判断，Cmd+C 不在系统加速键表 app.mbt:855，未真机验证。

## 九、进度快照

- 时间：2026-11-06 归档；容后，恢复时按本节继续。

**状态**：容后——三平台桥与静态文本选中均已落地，剩余项全部是真机读屏清单与两处语义挂载缺口；2026-11-06 用户决定暂停，当前优先基建与 DX，TODO 同名条目已撤回，本节为唯一进度台账，与 roadmap「屏读语义」条目互指。**暂停不影响其他功能**：无障碍是只读旁路，每帧快照对账 + 查询应答，不开读屏时 AT-SPI tick 只是一次状态判断、UIA 只在系统查询时响应，键盘/鼠标/绘制链路无依赖。

**已落**：

- **公共地基**：静态文本选中与复制——`text`/`text_dyn` 的 `selectable`、`code_view`/`markdown_view` 跨行选中、`rich_text` 行盒选中。
  - 行盒：一行文本在排版里占的矩形盒。
  - 状态：真机验收通过，2026-11-05。
- **阶段 0**：`Widget` 语义字段面——`role`/`name`/`enabled`/`a11y_state`/`a11y_text`；帧尾整树语义快照——`a11y_last_frame()`，删控件不产幽灵、不可见子树不进树；首批组件语义挂载——button/checkbox/switch/slider/progress/input/textarea/select/text。
- **阶段 1，mac**：NSAccessibility 桥——AX 元素按 widget id 稳定缓存、press 动作走合成点击、焦点 id 通道、hitTest、事件上行。
  - 状态：VO 真机首轮通过，2026-11-05，控件朗读/焦点跟随。
- **阶段 2，Linux**：AT-SPI 桥——第三总线 Socket.Embed 注册、四接口 + Action + 事件上行、断线自愈重连、TSV 解析两处缺陷修复。
  - 状态：本机真总线端到端验过。
  - TSV：制表符分隔的数据格式。
- **阶段 2，Windows**：UIA provider——窗根 provider、快照行惰性摊成 COM 树、五 pattern 按角色挂、动作压队列合成点击、GUID/头的链接期口径收口。
  - 状态：实现与门禁全绿，真机读屏未验。

**剩余**，恢复时从这里接：

- **Orca 真机清单**，Linux AT-SPI：Tab 遍历朗读 / flat-review 逐行读 / 读屏 press 不双触 / 中文名与逐字偏移。
  - 取证：测试用例附录 F。
- **NVDA + Accessibility Insights 清单**，Windows UIA：role/name/状态朗读、树层级与 RangeValue 实时性、Invoke/Toggle/Expand 触发不双触、中文名、单窗边界。
  - 边界：多窗快照表是进程级单表，已知边界。
- **语义挂载缺口**：mdview 富文本段与 `code_view` 代码行的语义面未挂。
  - 范围：另批。
- **VO 复确认遗留**：长描述段语义树携带全文。
  - 记录：roadmap「屏读语义」条已记。
