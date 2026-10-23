# 无头测试门面：从白盒 wbtest 到对外 `uitest`

> **状态**：方案稿（2026-10-19），未动代码
> **跟踪**：待立项
> **起因**：与 mygo 的 `ui.NewTester` 对照后核账，结论是本仓不缺无头能力，缺的是**对外门面**与**应用泵的无头路径**。

## 1. 先把账核清：缺的不是「无头测试」

仓里已有大量无头交互测试，能力上并不落后：

| 事实 | 数字 |
| --- | --- |
| `_wbtest.mbt` 总量 | 28310 行（ui 20 个文件 193 条、widget 18 个文件 104 条） |
| 真跑布局（`mount_children` + `relayout`）的文件 | 21 / 38 |
| 合成指针事件（`dispatch_pointer`）的文件 | 17 / 38 |
| 读内存位图断言配色的文件 | 17 / 38 |
| `gui/widget` 的黑盒测试（`_test.mbt`） | **0** |

`gui/ui/basic_wbtest.mbt` 开头就写着「全程无头（内存位图 + 手工投递事件）」，`form_wbtest.mbt` 的复选框用例是完整的「点一下 → 断言 `Store` 翻转 → 松开落在控件外不算操作」。

所以差异在另外两处：

1. **全在白盒侧**。文件名 `_wbtest` 决定它只能在同一包内用私有符号；`mount_root` / `kid` / `click` 这些助手是包内私有函数。**使用者拿不走**，没法在自己的 app 模块里测自己的界面。
2. **应用泵没有无头路径**。`pub fn test_app(s : @shell.Session)`（`app.mbt:235`）看着像入口，但：
   - 它要一个真 `Session`，而 `Session` 只能由 `session_open` 造，后者先过 `@win.init_backend()`；
   - `Session.window` 的方法全走 FFI。用假句柄（`{ id: 999999, width: 0, height: 0 }`，`taskbar_wbtest.mbt:33` 的写法）时 `wm_size` 把宽高写回 0，`paint_frame` 在 `if w < 1` 处直接 `return`，一帧都画不出来；
   - `App::step` 头一行是 `@shell.session_pump_advance()`，那是有真实等待的泵。
   
   结论：定时器、脏区合并、主题轮询、浮层三帧收框，目前**只能靠真机人工看**。

## 2. 判据一句话

> **能在没有显示服务的机器上，用使用者写代码的方式（`test-import` + 公开 API）断言「点了这个按钮，界面就变成那样」。**

只在包内可写、只断言内部状态的，叫内部回归，不叫门面。按这条判据，本期只做两件事：把能力搬到公开侧，把泵搬到内存里。

## 3. 两层能力，分两期

| | P1 控件层 | P2 应用泵层 |
| --- | --- | --- |
| 被测对象 | `Node` 树 → `Widget` 树 | `App`（`step` / 定时器 / 脏区 / 上屏） |
| 依赖 | `widget` + `render`（零 FFI） | 还要 `shell` + `win` 的虚窗分支 |
| 今天能否落地 | 能，纯 MoonBit | 要动 `win` 的窗口方法 |
| 拿到什么 | 点击/输入/滚动/拖拽/像素/几何 | 事件循环、帧调度、主题跟随、浮层收框 |
| 拿不到什么 | 泵、定时器、上屏 | 真实平台窗口与输入法引擎（仍归人工） |

P1 先做，P2 单独立项。两者都不能替代 `测试文档/测试用例.md`——真机人工验的口径不变。

## 4. P1：公开包 `gui/uitest`

### 4.1 落位与导入

- 新包 `gui/uitest`，包名 `NoahLiu/native-gui/uitest`，`supported_targets = "native"`。
- 依赖只有 `base`（`Store`/`Signal` 断言用）、`widget`、`render`、`yoga`。**不依赖 `ui`**——否则使用者只测底层控件也得拖进整套组件库，且 `ui` 的测试若反向依赖会成环。
- 不进主链路的 `import` 段；使用者在自己的 `moon.pkg` 里写 `test-import`。工具链已支持（`moon 0.1.20261012` 的 `MoonPkgJSON` 有 `test_import` / `wbtest_import` 字段），仓内目前零使用。

```
// 使用者模块的 moon.pkg
test-import {
  "NoahLiu/native-gui/uitest" @uitest,
}
```

### 4.2 API 草案

```moonbit
// ---- 建 ----
pub fn mount(root : @widget.Node, width : Double, height : Double) -> Tester
pub fn mount_all(children : Array[@widget.Node], width : Double, height : Double) -> Tester

// ---- 找 ----
pub fn by_name(n : String) -> Target
pub fn by_text(s : String) -> Target          // 语义糖，等价 by_name
pub fn nth(t : Target, i : Int) -> Target
pub fn hit(x : Double, y : Double) -> Target                   // 兜底：这个坐标命中谁

// ---- 动 ----
pub fn Tester::click(self : Tester, t : Target) -> Unit        // Down + Up 成对，坐标取矩形中心
pub fn Tester::pointer(self : Tester, kind : @widget.PointerKind, x : Double, y : Double,
                        button? : Int = 1, mods? : Int = 0) -> Bool
pub fn Tester::type_text(self : Tester, t : Target, s : String) -> Unit
pub fn Tester::key(self : Tester, keysym : Int, mods? : Int = 0, press? : Bool = true) -> Bool
pub fn Tester::scroll(self : Tester, t : Target, dy : Double) -> Unit
pub fn Tester::drag(self : Tester, from : (Double, Double), to : (Double, Double),
                    steps? : Int = 10) -> Unit

// ---- 看 ----
pub fn Tester::frame(self : Tester) -> Unit                    // 重算布局 + 重画一帧
pub fn Tester::rect(self : Tester, t : Target) -> Rect?
pub fn Tester::text(self : Tester, t : Target) -> String?
pub fn Tester::pixel(self : Tester, x : Int, y : Int) -> (Int, Int, Int, Int)
pub fn Tester::bitmap(self : Tester) -> @render.Bitmap
pub fn Tester::capabilities(self : Tester) -> Capabilities
```

用例（`test-import` 视角，模拟外部使用者）：

```moonbit
test "计数器：点一下加一" {
  let n = @base.Store::new(0)
  let t = @uitest.mount_all([
    @ui.bind_label(n, fn(v) { v.to_string() }).named("count"),
    @ui.button("加一", on_click=fn() { n.set(n.get() + 1) }).named("inc"),
  ], 200.0, 100.0)
  assert_eq(t.text(@uitest.by_name("count")), Some("0"))
  t.click(@uitest.by_name("inc"))
  t.frame()
  assert_eq(t.text(@uitest.by_name("count")), Some("1"))
}
```

### 4.3 定位靠 name，不靠下标

现状是 `kid(root, 0)`——控件顺序一调，测试全错，且读者看不出那 0 是哪个按钮。

- `Widget` 加两个字段：`mut name : String`（语义名）、`mut role : String`（控件类名，如 `"button"`）。
- 组件在构造时写 `role`；可见文本默认进 `name`（后续小批，不阻塞 P1 主体）。
- 不逐一给构造器加 `name?` 参数（那是几十处签名变更），改用**包装器**，落在 `gui/widget/node.mbt`（不是 `uitest`——否则产品代码用 `.named` 就得把测试包拖进正式依赖）：

```moonbit
pub fn Node::named(self : Node, name : String) -> Node {
  { mount: fn(parent : Widget) -> Widget {
      let w = (self.mount)(parent)
      w.name = name
      w
    } }
}
```

纯增量：不动任何一个既有构造器的签名，`Node` 结构也不必加字段。

> 与无障碍的关系：`name` / `role` 正是读屏要的那对数据，但 roadmap 的无障碍是 ❌，本期**只留字段，不做 ATK/UIA/NSAccessibility**。

### 4.4 画一帧：不要碰全局 repaint hook

`@widget.set_repaint_hook` 是**进程级单例**（`node.mbt`）。`moon test` 的 `max-concurrent-tests` 默认并行，多个 `Tester` 会互相覆盖 hook，先建的那个在 `Store.set` 之后不置脏，断言随机失败。

P1 的口径：**`Tester::frame()` 无条件重算**（`relayout` + `paint`），不装 hook、不读脏区。代价是帧数不能省，好处是与全局状态零耦合、并行安全。

### 4.5 能力守卫要显式，不要 `println("skip")`

现有写法是 `ui_text_guard()` / `ui_decode_guard()` 打印一行然后 `if` 包住断言。问题是：**跳过的测试在 CI 汇总里等于通过**，覆盖缺口被静默吞掉。

`Capabilities` 给三个只读量：`text_measure`（`@text.measure("Ag", 13.0)` 是否给值）、`image_decode`（能否解出示例 GIF）、`raster`（位图能否分配）。约定：

- 依赖能力缺失的断言，**必须在用例名里带 `[需文本]` / `[需解码]` 前缀**，并由 `uitest` 计数，`moon test` 结束时打印 `uitest: 12 跳过 / 3 依赖文本测量`；
- 不追求真正的 `skip` 语义——工具链没有，硬造只会误导。

### 4.6 迁移策略：新测试用新门面，旧测试不动

28310 行不重写。规矩：

1. 之后新增的 UI 测试一律走 `@uitest`（这是本次要换的口径）；
2. 挑 `gui/ui/form_wbtest.mbt` 做示范迁移：删掉私有 `click`，改用 `Tester::click`；其余 37 个文件保留现状；
3. 示范迁移后，`PointerKind::Down` / `Up` 的手写点从 48 / 35 处开始下降，作为可量的收敛指标；
4. `uitest` 自己的测试用**黑盒**（`gui/uitest/uitest_test.mbt`）写，验证「包外可用」这件事本身。

## 5. P2：给 `win` 一个虚窗哨兵

### 5.1 阻断点

`@win.Window` 是 `pub(all) struct { mut id : Int64, mut width : Int, mut height : Int }`，字面量可造；但 `size()` / `present()` / `poll_event()` 全走 FFI，假 id 拿到的是 0 和空事件，`paint_frame` 因此早退。

### 5.2 方案：`id < 0` 即虚窗

不引编译指令，用运行时哨兵：

- `pub fn Window::virtual_(width : Int, height : Int) -> Window`，`id = -1`；
- 六个方法加一支：`size` 回字段、`present` 把 RGBA 拷进进程内快照缓冲、`poll_event` 从内存队列取、`show`/`hide`/`request_focus` 空操作；
- C 桩一行不改，真句柄语义零变化；
- `pub fn App::test_headless(width : Int, height : Int) -> App`：造虚窗 `Session` 并注册，走 `host_add_app`；
- `session_pump_advance()` 在虚窗模式下 `wait(0)`，不真睡。

### 5.3 拿到什么

- `App::step()` 可无头驱动：定时器到期、脏区合并、`follow_system_theme` 的轮询、`overlay_fit_pass` 的「最多三帧收框」；
- 这些现在全是人工清单里的「看着对不对」，变成可断言的数字。

### 5.4 仍然拿不到

真实平台窗口映射、FFI 行为、输入法引擎、Retina 观感、窗管交互。真机人工验的分工不变：**这部分照样由真机人工验，不由助手代跑**。

## 6. 预估的坑

1. **`set_repaint_hook` 全局单例**：见 §4.4。P2 同样受影响——`App::step` 里 `invalidate()` 走的是全局 hook，虚窗模式要让它指向当前 `App`。
2. **`Widget` 加字段**：`pub(all) struct`，外部用字面量构造会编译失败。仓内只有 `Widget::new()` 一处构造点，风险可控；对外属于破坏性变更，发版说明要写。
3. **`bind_label` 的动态文本**：`text()` 读 `name`，而绑定更新只重写绘制与尺寸，不写字符串。不补这一步，`text()` 永远读到初值。修法是在绑定更新路径把当前串写回 `w.name`。
4. **坐标口径**：`dispatch_pointer` 吃**窗口坐标**，控件矩形是绝对矩形——`Tester::click` 要按 `rect` 中心换算，别让使用者自己加偏移（现在 `form_wbtest` 的注释就在教这件事）。
5. **点击必须 Down + Up 成对**：只投 Down 不改状态；`Up` 落在控件外按「取消」处理。封进 `click`，别外泄。
6. **文本测量缺失时几何会飘**：Windows 侧 DirectWrite 未接、mac 图片解码桩未实装时，依赖宽高的断言不可比。靠 §4.5 的 `Capabilities` 显式标注，不静默通过。
7. **`test-import` 会自引用**：moon 会提示「自动把当前包也加为依赖」。`uitest` 因此**不能**反向依赖 `ui`，只依赖 `widget`；否则成环。
8. **P2 的虚窗分支别伸进 C**：`id < 0` 判断只放 MoonBit 侧，C 桩不认哨兵，否则真机路径也走一遍新分支。

## 7. 验收

P1：

- `cd gui && moon check --deny-warn` 零错误零警告；
- `moon test uitest` 全绿；
- 一条 `test-import` 视角的黑盒用例通过（证明包外可用）；
- `form_wbtest.mbt` 示范迁移后原有断言条数不变、私有 `click` 删除；
- 三个平台 `moon check` 全过（`uitest` 不碰 FFI，应天然跨平台）。

P2：

- Linux CI 的 `DISPLAY` 去掉后，一条 `App::step` 驱动的定时器用例仍通过；
- 真机冒烟与既有 examples 行为零变化（虚窗是新增分支，不改既有路径）。

## 8. 开放问题

1. `Capabilities` 的跳过计数要不要进 CI 门禁（超过阈值即红）？先观察，不设阈值。
2. P2 的 `App::test_headless` 对外公开，还是只给库内测试用？对外公开就成了契约，要连同「虚窗不等于真窗」的语义边界一起写进文档。
3. 要不要做像素快照基线（PNG + 容差）？`moon test` 没有快照机制，得自带基线目录与比对器，工作量远大于 P1 主体，建议单独立项。
4. `name` / `role` 现在只服务测试定位，将来接无障碍时是否复用同一套字段？倾向复用，但本期不承诺。

## 9. 与 mygo `NewTester` 的差别

| | mygo | 本方案 P1 |
| --- | --- | --- |
| 建 | `NewTester(view, w, h)` | `mount(node, w, h)` |
| 找 | 文本 | `name`（可显式命名） |
| 动 | `Click("Go")` | `click(by_name("inc"))` |
| 画 | 内置 | 显式 `frame()` |
| 覆盖 | view 函数 | Node 树 + `Store`/`Signal` 响应链 |

多出来的 `frame()` 不是退步：我们的响应式是**订阅式局部更新**，不给「何时结算」一个明确点，就测不出「改了 Store，这帧有没有生效」。mygo 的立即模式每帧重建，天然没有这个歧义。
