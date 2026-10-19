# Showcase 懒加载 + 单窗口路由机制独立成包方案

## 〇、关键事实

`examples/showcase/` 的现状：

1. **接入前「懒加载」只懒挂载，不懒构造。**
   - 当时 `main.mbt` 在启动时**逐个求值** `@pages.page_X(app)`，把每页**已建好的** `@widget.Node` 传进示例侧的 `nav_page(...)`。
   - 组件构造器一律走 `node_of_new(finish)`（`gui/widget/node.mbt:42`），`finish` 闭包（`Widget::new()` + `mount_children`）**在构造期就跑**——所以 `page_icons(app)` 一求值，整墙图标控件当场实例化。
   - 示例侧原有 `section_body`（`shared/section.mbt`）的 `Ref[Bool] mounted` + `selected.subscribe(ensure)` 懒挂载，但它只把**已构造**子树的 attach/layout/paint 推迟，**没推迟构造**；页级那份 `nav_page` 现由 `@router` 的挂载槽承担。
   - 净效果：启动即构造全部页与段的控件。作者当时也在注释里写明这个坑（`overlay.mbt:478`、`message_box.mbt:110`、`docs/zh/declarative.md:44`「page(app) 求值早于建窗」）。
     接入路由后这句只剩下一半成立：构造确实被推迟了，但「卡启动的根因」按实测是代码文档页，不是图标墙（见 §三·五）。
   - **构造大头不是图标墙（T1 实测修正）**：图标页逐个建 tooltip+icon 的说法成立
     （`pages/icons.mbt:9-27` 的 `icon_grid` 是实打实的循环），但它整页构造只花
     9ms；启动构造的大头在代码文档页（138ms，`code_view` 构造期逐 token 量化 +
     markdown 解析）。见 §三·五 读数表。

2. **MoonBit native 没有运行时 code-split / 动态 import。**
   `examples/showcase` 是 `pkgtype=executable` + `supported_targets=native`，各 `page_X` 被 `main.mbt` 静态引用，链接成**单个原生二进制**。
   所以这里的"懒加载"只能是**运行时按需构造（thunk 化）**，不是分包/动态加载。这是唯一现实模型。

3. **库内已有的"按需构造"成熟先例**（复用它，别新造）：
   - `virt_list(items, row_of : (Int,T)->Node)`（`gui/ui/virtlist.mbt:11`）：`row_of` 只对可见行调用。
   - `bind_node(sig, f : T->Node)`（`gui/widget/node.mbt:92`）：`f` 在 mount/rebuild 路径里才调用。

## 一、真正的懒加载：把构造也 thunk 化

目标：启动只构造"当前选中的一页 + 侧栏骨架"，其余页**首次选中时才构造**。

### 1.1 改 API 签名（构造推迟的根）
```
// shared/section.mbt —— content 由"已建 Node"改为"建 Node 的闭包"
- pub fn nav_page(name, selected, content : @widget.Node) -> @widget.Node
+ pub fn nav_page(name, selected, content : () -> @widget.Node) -> @widget.Node

// Section.content 同理（section.mbt:26）
  content : () -> Array[@widget.Node]   // 或 () -> @widget.Node
```

### 1.2 在已有的 mounted 守卫里调用 thunk
```
// section.mbt:92-95 的 ensure 里，首次挂载时才：
let node = content()        // ← 构造推迟到这里
node.mount_into(c)
mounted.val = true
```
懒挂载骨架（`Ref[Bool]` + subscribe）已存在，**只把"取已建 Node"换成"调 thunk 现建"**。

### 1.3 main.mbt 调用点包一层闭包
```
// main.mbt:209-223
- @shared.nav_page("图标库", selected, @pages.page_icons(app)),
+ @shared.nav_page("图标库", selected, fn() { @pages.page_icons(app) }),
```

**改动面极小且局部**：仅 `shared/section.mbt` + `main.mbt`，**不动库**。

### 1.4 收益与代价
- 启动只构造当前选中的那一页 + 侧栏；图标页只在点开「图标库」时构造。
- 代价：切页瞬间有构造开销（首次点击该页略迟）。可用 `bind_node` 的订阅复用同一机制，必要时给"下一屏预构造"留钩子（非必需）。
- **注意**：图标页整墙控件即便 thunk 化，首次打开仍要全部建一遍。若这仍慢，进一步用 `virt_list` 只渲染可视区图标——但那是页内优化，属第二优先级。

## 二、单窗口路由机制：是否独立成包

### 2.1 现状：路由"策略"已在 app 层，但没成库
- 路由状态 = 一个 `@base.Store[String]` 存当前页名（`main.mbt:103` / `app.mbt:14`）。
- 侧栏 UI = 库组件 `menu_sections(sections, selected, ...)`（`gui/ui/nav.mbt:771`）。
- 页生命周期 = **app 代码**的 `nav_page` + `section_body`（`shared/section.mbt`）。
- 库内**没有** router/Page/Route/view-stack 类型；grep 到的 `route*` 全是输入事件路由（`App::route`），与导航无关。
- `tabs(...)`（`nav.mbt:991`）是"预建所有页 + set_visible 切换"，**不是懒**（`docs/components.md:104` 佐证）。

### 2.2 可分性评估：干净，可抽包
路由逻辑只依赖三样：`@base.Store`、`@widget.Node`、`@ui.col/menu_sections`。**无 showcase 专有耦合**，具备抽成通用库的条件——每个单窗口 app 都会重造这套 Store[String]+侧栏+懒挂载。

### 2.3 定稿：`gui/router` 包，路由只认「树 / 每层选中键 / link」

落位 `gui/router`（`NoahLiu/native-gui/router`，别名 `@router`）。随主包 `NoahLiu/native-gui`
一起发布、`moon add` 后零配置；纯 MoonBit 无 C 桩 → prebuild 不动。`@shell` 在 `widget`
之下（`gui/widget/moon.pkg` 依赖它），路由要用 `@ui`/`@widget`，放 `@shell` 成环。

Router 不认识「菜单」也不认识「段」，只认三样：**路由树（任意深度）**、**每层的当前
选中键**、**link 绑定**。菜单、段条、面包屑、表格行、按钮、原生菜单项、快捷键都只是
link 的**载体**，一律走同一个绑定入口。

```
pub enum LoadPolicy { Eager Prefetch Lazy }   // 三档：建窗即建 / 空闲预建 / 点开才建
pub enum EvictPolicy { Keep Lru(Int) }        // 每层槽各自 keep-alive / 淘汰

pub struct Route {
  key : String                  // 该层短名；唯一性域=同父唯一
  children : Array[Route]       // 非叶给子表；叶节点 children 空、build 必给
  build : () -> @widget.Node    // 构造 thunk（§1）
  load? : LoadPolicy?           // None=跟随 Router 默认
  evict? : EvictPolicy?         // None=跟随 Router 默认
}

pub struct Router {
  roots : Array[Route]
  levels : Array[@base.Store[String]]   // 每层一个权威 store，长度=树深
  default_load : LoadPolicy             // 默认 Prefetch
  default_evict : EvictPolicy           // 默认 Keep（与现状「切段只切显隐、保滚动位置」同义）
}
```

三档而不是一档预加载的理由：showcase 今天「启动即出托盘」本身就发生在页构造期
（`pages/system.mbt:431`），两档（空闲预建/点开才建）下托盘的出现时机一定会变。
给「托盘」那一段单独标 `Eager`，既保住启动即出图标，又比今天省——今天整页都构造，
标 `Eager` 只构造那一段。

**构造期副作用页的口径**：`sysprobe`（构造期跑系统 I/O）、`anim`（构造期解码 GIF
并排首帧动画）、`data`（构造期起轮播自转）一律标 `Lazy`，不进空闲队列——懒加载对
它们是正确的，需要豁免的只有空闲预建。`Eager` 只给「就是要启动期生效」的节点。

对外核心面（入口层，`sidebar`/`strip` 只是便利函数、不进核心面）：

```
pub fn path(r : Router) -> String                       // 各层选中值 join("/")
pub fn goto(r : Router, path : String) -> Unit          // 归一化写多层
pub fn children_at(r : Router, depth : Int) -> Array[String]   // 当前父路径下的子键
pub fn store_at(r : Router, depth : Int) -> @base.Store[String]
pub fn on_link(r : Router, path : String) -> () -> Unit        // 任何 on_click 都能接
pub fn route_link(r : Router, path : String, node : @widget.Node) -> @widget.Node
pub fn breadcrumb(r : Router) -> @widget.Node
pub fn slot(r : Router, depth : Int) -> @widget.Node    // 每层挂载槽（显隐/淘汰在此层实现）
// 便利函数（不进核心面）：sidebar(r)、strip(r)
```

`route_link` 首参传 `r`，不把「当前路由」藏进包内全局——双窗/多路由的应用会取错句柄。
`breadcrumb` 由本包自绘（`row` + 可点文本绑 `on_link`），不复用 `@ui.breadcrumb`：库版
点击时直接 `selected.set(项名)`（`gui/ui/nav.mbt:208`），而多层路径下「点第 i 层」= 写
第 i 层 + 深层回落，两者不等价，且它不接可注入的 `on_click`。代价是与库版两份画法、
样式改动要同步；换来的是**库零改动**。

**层级键口径**（库零改动的根据）：每层 store 存的就是**该层短名**，所以
`segmented` / `menu_sections` / 面包屑显示短名天然对齐，不需要全路径键，也不需要
labels 与键分离。归一化规则：写第 i 层 → 第 i+1.. 层各自回落到**首个子节点**默认，
`goto("a/b/c")` 一次写多层。

**写入去重**：一律走 `Store::set`——`T : Eq` 时它经 [Signal::set_eq] 内建去重
（`gui/base/store.mbt:28`），各层订阅靠这条兜环。不用 `Store::map` 做层级：它是只读
派生（`gui/base/store.mbt:76`），入口组件写不回。不用 `set_always`（相同值也通知，
多层互写会成环）。

**同父重名 = 构造期失败**。唯一性域是同父唯一，跨父重名合法——实测现状即满足：跨父
重名只有「消息框」一处（`pages/system.mbt:234` 与 `pages/feedback.mbt:173`），同父
0 重名。契约由 T2 的 wbtest 钉在路由树构造处，不做全局核名与改名。

## 二·五、预建与淘汰

**排队规则只有先序一条**：从当前路径起按路由树**先序环形扫描**——当前节点 → 其子树 →
下一个兄弟子树 → … 补完全树。任意深度同一条规则，不设「页优先级/段优先级」两套。
当前选中路径**当拍插队建完**这条不变。`load=Lazy` 的节点不进空闲队列，首次选中当场建。

**淘汰挂在节点上，不挂全局**：每层槽各自 keep-alive / evict；退出深层路径要能淘汰祖先链
上任一层的子树。销毁实现走 `Widget::remove_child`（`gui/widget/widget.mbt:308`）+ 整代
`sub_bag` 退订（`gui/widget/node.mbt:99` 同款）；重挂走原 thunk 重建。注意
`Node::on_mount` 的记档（`gui/widget/node.mbt:51`）**挂载几次跑几次**——排定时器/注册
泵这类一次性启动回调若写在 `on_mount` 里，淘汰后重挂必须防双份，T5 逐条核实。

**`Lru` 只管挂载过的节点**（T1 实测定的口径）：样式侧表的丢弃钩子只在摘树时跑，
「预建好但从未挂载」的节点被丢掉时 `remove_child` 帮不上忙，会在侧表留下残账。所以
`Lru(n)` 的计数与淘汰都只作用于已挂载子树；未挂载的预建结果一旦丢弃，其残账按 §三·五
的量级（每页数十到上百条）记死在文档里，不另外开库侧批量清的口子。

**一期不做前进/后退历史栈**：核心面只有「当前路径 + link」；`breadcrumb` 与 `on_link`
已给以后接入历史留出位置。

## 三、待办（按序做，一项一提交）

- [x] **T1 判据先行（无头，不弹窗）**：判据包 `examples/showcase/cost_bench`（与
  `pages`/`shared` 同级，直接吃页函数），逐页量 `build()` 构造 / `mount_into` +
  `relayout` / 首帧 paint 三档，加样式侧表回收的 A/B 对照；读数与结论见 §三·五。
  构造期有真实副作用的页不进判据（`system` 建真托盘恒跳过，`sysprobe` 的系统 I/O
  由 `WITH_IO` 开关控制）。
- [x] **T2 `Route` 路由树 + 构造期契约**：`gui/router`（`router.mbt` + `router_wbtest.mbt`）
  落 `LoadPolicy{Eager|Prefetch|Lazy}`、`EvictPolicy{Keep|Lru(Int)}`、`Route` 与
  `route_leaf`/`route_branch`；`tree_errors` 在构造期一次报全：空键、`/` 作键、同父重名、
  空路由表、节点既无子表也无 build、分支带 build、**同父必须等深**。契约不过由
  `tree_depth`（= 层数 = `levels` 长度）abort 并带上全部违规说明。wbtest 8 项全绿。
  - **等深这条规则定成含叶混排**：同层既有叶（1 层）又有分支（>1 层）也判不齐——不齐的表
    没法给每层配一个选中键，浅的那一支在深层没有候选。showcase 的页→段两层表天然满足。
  - 跨父重名合法由 wbtest 钉住（复刻现状的「消息框」两页各一次），同父重名只报一条。
- [x] **T3 `levels` 层级状态与路径**：`levels.mbt` 落 `Router{roots,levels,default_load,
  default_evict}` + `new_router`（表不过契约 abort，每层初值取首个候选，首屏 = 首个根
  一路到首个叶）、`path` / `resolve` / `goto` / `level_count` / `children_at` /
  `store_at` / `route_at`。归一化：`goto("a")` 一次把深层各自回落到首个候选；
  自上而下逐层 `set`，相同值不通知（去重兜环）。**非法段与超深段不炸**——最坏是
  「回到该层第一项」，要严格对照用 `resolve` 自己比。wbtest 9 项（含重入不成环）全绿。
- [x] **T4 预建调度器**：`prefetch.mbt` 落缓存与队列——`built : Map[路径, Node]`（同父唯一
  ⇒ 路径唯一，缓存就按路径索引）、`build_now`（thunk 只跑一次）、`ensure_current`（当前
  路径插队建完）、`prefetch_step`（先序环形队列的下一拍，跳过 `Lazy` 与已建）、
  `reanchor`（选中变了就从新当前路径重锚）、`build_eager`（启动期把 `Eager` 节点建完）、
  `start_prefetch` / `stop_prefetch`（`@shell.set_timeout` 自排链，默认一拍 16ms，队列建空
  即停链不留空转定时器；无宿主时走 host 未就绪的排队通道，`gui/shell/loop.mbt:189`）。
  调度核心做成可手动驱动的纯步骤函数，wbtest 不起定时器就能逐拍验序。策略判等走 `match`
  不给枚举派生 `Eq`（本工具链 `derive(Eq)` 报隐式提升告警，零告警门禁过不了）。wbtest 7 项。
- [x] **T5 挂载槽与淘汰**：`slot.mbt` 落 `Router::slot(depth, prefix, candidates, bar_of)`
  与 `Router::view(bar_of)`——每层每个候选一个容器，选中者保证已挂载、其余只隐藏；
  分支的内容 = 入口载体（`SlotBar` 钩子，段条/侧栏/面包屑同一口子）+ 它的子槽，
  所以「深层候选随父层变化」发生在子槽重新构造那一刻，不在同一个槽里换候选表。
  - `Keep` 保形（切显隐不重建）；`Lru(n)` 只数**已挂载**的子树，按最新窗口的最紧那条裁，
    从最久未用开始摘，刚挂载的那个不动。
  - 淘汰一律走 `Widget::remove_child` + 退掉这一代的袋子 + `purge_built`（连同这条路径下
    的已构造内容一起丢，重进走 thunk 重建 ⇒ `on_mount` 不会被重跑出双份定时器）；
    摘一棵分支时先跑它子槽登记的重置闭包，子孙槽的挂载态一起归零。
  - **预建的构造也要包进回收袋**：组件在构造期就 `follow_store`/`watch_theme` 这类订阅
    （`gui/ui/nav.mbt:157`），回收袋原本只兜挂载窗口；所以缓存条目连着存一份构造期退订闭包
    （`struct Built{node, offs}`），淘汰时两代一起退。否则每重进一次就往层 store 上挂一个死订阅。
  - 落过程中抓到两条实现 bug（已修，wbtest 钉住）：`purge_built` 把 `sub_bag_discard` 写在
    了 `if` 外面，purge 一个节点会退掉全部节点的订阅；`under_level` 没判空后缀，分支被算进
    自己子槽那一层，`reset_all` 会递归摘到自己。
  - wbtest 7 项：选中才挂 / Keep 保形 / Lru 摘树并重建 / 整代退订 / 子孙槽归零 / 单层路由 /
    入口载体位序。全库门禁 `moon check` 零错零警告，`moon test ... router` 1067/1068
    （唯一一条失败是 `sys/launcher_wbtest.mbt:133` 的期望值还停在 `docs/zh/adaptation.md`，
    而同一批改动已把输入换成 `proposals/adaptation.md`——与路由无关，属并行会话的遗留）。
- [x] **T6 入口层 API**：`link.mbt` 落核心面 `on_link(path) -> () -> Unit`（任何
  `on_click` 直接接）、`route_link(path, node)`（给任意节点套一层「点它=导航」，认领口径照
  库内导航项：按下认领、框内抬起才算点中，`gui/ui/nav.mbt:119`）、`breadcrumb()`，再加 T3 的
  `children_at` / `store_at`；`strip_at` / `view_strip` / `sidebar` 是便利函数，不在核心面。
  - **`segmented` options 静态这条风险被递归设计消掉了**：分支的子槽只在它挂载那一刻构造，
    候选表在那一刻就定下来——「深层候选随父层变化」由子槽重新构造承担，不需要在同一个段条里
    换候选表。`bind_node` 只用在一处：面包屑（数据源 `computed(self.path())`，重画走
    `bind_node` 的整代退订 + 原位重挂，`gui/widget/node.mbt:92`）。
  - 面包屑由本包自绘（`row` + `@ui.link`），不复用 `@ui.breadcrumb`：点第 i 段要写第 i 层
    并让深层回落，库版只做 `selected.set(项名)`；末段不给点击。
  - wbtest 7 项全绿。「点段条切段」这一向要真鼠标，留在真机清单里。
- [x] **T7 showcase 接入（页级）**：`main.mbt` 的 15 个 `nav_page` 调用点换成一张路由表
  （`route_of_page` 把每页包成叶 thunk，App 还没装配就构造直接 abort），主区一个
  `nav.view(None)`，侧栏走 `nav.sidebar(groups, icons=..., width=...)`；`shared/section.mbt`
  的 `nav_page` 删除（页级显隐与按需挂载由包的槽承担），`page`/`section_body` 留在示例侧
  继续管段级懒挂。`app.selected` 就是 `nav.store_at(0)`，所以导航组件页那两个 demo
  （`segmented`/`breadcrumb` 绑同一份导航状态）照旧生效。菜单栏「导航」项改走
  `nav.on_link(name)`，单实例 Wake 改走 `nav.goto("基础组件")`。
  - 策略落位：`系统集成` 标 `Eager`（托盘要启动即出，且建窗前构造＝今天的时机），
    `系统能力探测` 标 `Lazy`（构造期的全量探测不再在启动空闲期空跑，点开才探），
    其余 13 页 `Prefetch`。
  - stdout 判据：`SHOWCASE-READY ... startup_ms=`（启动到就绪的毫秒数，和接入前对照）、
    每次切页打 `SHOWCASE-ROUTE page=… pending=… path=…`（预建进度与切页时机）。
  - 门禁：`moon check` 零错零警告、`moon build examples/showcase --target native` 过；
    真机手感与上面两个读数由用户执行（T10）。
- [ ] **T7b（待定）段级路由**：把每页的段也做成路由叶（页=分支、段=叶），需要 15 个页
  文件把 `page_X(app) -> Node` 改成返回段表、`section(...)` 的 content 改成 thunk。
  按 T1 读数，页级预建已经把「点开未预建页」压到最坏 143ms（代码文档页，且那 138ms
  集中在它其中一段的 markdown/代码高亮构造上）——段级化的边际收益主要是把这一页的
  构造摊成按段付，代价是 15 个文件的签名改动与逐页真机回归。先做页级、段级按读数再定。
- **T8 页内虚拟化：按 T1 读数不做**。最坏单页 `build+mount+layout+paint` = 143ms，
  阈值 300ms 未破；图标墙整页构造 9ms、数据展示页首帧 77ms 都不在预算外。重开条件：
  某页实测 `click` 超 300ms，或真机点开某页有可感停顿——那时才给那一页上
  `virt_list` / `table_v`（`gui/ui/virtlist.mbt:11/144`）。
- [x] **T9 门禁与文档**：`cd gui && moon check` 零错零警告；`gui/router` 的 `_wbtest.mbt`
  进三档 CI 的点名清单（Linux / Windows / macOS 的 `moon test` 与 macOS 的 `moon build`）
  与 `AGENTS.md` 的库门禁命令行；`docs/zh/roadmap.md`「组件层与前端化」加一行
  「单窗口页面路由 `@router`」三平台 🚧（已合入待真机）；坑回写 `proposals/adaptation.md`
  四条（空闲预建会真做副作用、样式侧表残账与回收袋、图标墙旧账的实测修正、
  `derive(Eq)` 与 `x? : 函数类型` 两条工具链坑）。
  - 顺带：门禁里唯一的失败是并行会话把文档引用改指 `proposals/` 时漏改的一条断言
    （`gui/sys/launcher_wbtest.mbt:133` 期望值还写着 `docs/zh/…`），单独提交修掉；
    CI 步骤名与 `AGENTS.md` 里的包数统计一并删除（数字会随并行会话漂）。
  - `TODO.md` 无本专题条目需要收口（`G10 窗口内按键路由` 是按键事件路由，与页面路由无关）。
- [ ] **T10 真机验证清单（你执行）**：全部实现项完成后一次性给出，见文末。

## 三·五、T1 实测读数（`examples/showcase/cost_bench`，无头、预热后、1280x720）

跑法：`cd examples/showcase && moon run ./cost_bench`（`WITH_IO = true` 可带上系统探测页，
它会真去读当前用户的浏览器/桌面数据；`system` 页因构造期建真托盘恒跳过）。

单位 ms，`click` = `build + mount_layout + paint`，即**点开一个还没预建的页要等的下界**：

| 页 | build | mount+layout | 首帧 paint | click |
|---|---|---|---|---|
| 代码文档 | 138 | 1 | 2 | **141** |
| 数据展示 | 23 | 2 | 77 | 102 |
| 基础组件 | 34 | 42 | 3 | 79 |
| 窗口 | 33 | 2 | 2 | 37 |
| 反馈组件 | 2 | 4 | 15 | 21 |
| 图标库 | 9 | 4 | 3 | 16 |
| 其余各页 | ≤5 | ≤4 | ≤3 | ≤10 |

- 全量预建构造 259ms，首屏页构造 34ms → thunk 化把 **225ms 构造**从启动里挪走。
- **300ms 预算：够。** 最慢点开页 141ms，且 `Lazy` 与 `Prefetch` 两条都在预算内——
  所以策略选择是按「启动省多少」和「副作用要不要提前触发」来定，不是按能不能满足阈值。
- **首帧 `paint` 预加载救不了**（数据展示 77ms 全在 paint）：预建只把 `build` 挪进空闲，
  真到那一页才挂、才画，这 77ms 必然落在切页那一刻。要压它得走页内虚拟化（T8）。
- 数值随调试/发布档不变（debug 与 `--release` 两轮同量级），文本测量与解析是构造期付的。

回收判据（样式侧表 `@style.resolved_count()`，`gui/style/apply.mbt:14-25`：外观槽按控件
id 存进程级侧表，**丢弃钩子只挂在摘除路径上**）：

| 轮次=12 | 每轮残账 |
|---|---|
| A 组：建→挂→排→画→`remove_child` 摘除（基础组件） | 33 条 |
| B 组：同样建→挂→排，只丢引用不摘树（基础组件） | 99 条 |
| A 组：数据展示 | 182 条 |
| B 组：数据展示 | 315 条 |

两条设计结论（写进 T4/T5 的实现口径）：

1. **淘汰必须走 `remove_child`**，只把缓存里的 `Node` 引用清掉等于没淘汰——摘树能回收
   已挂载子树的样式条目，只丢引用则整棵留在侧表里。
2. **构造了但从未挂载的子树，`remove_child` 也清不掉**（钩子从没被触发过）：A 组每轮仍留
   33/182 条，正是那些「预建好、还没挂」的段内容。这是**空闲预加载的真实内存代价**——
   预建一页就在侧表里留一批条目，直到它真被挂载并正规摘除。所以 `EvictPolicy` 只对
   已挂载节点有意义；淘汰一个「建好但没挂过」的节点要另给出口（库侧批量清或 Router
   不缓存未挂载结果），这一条按待定项收口。

## 四、风险

- **构造期实例化的连带**：thunk 化后，凡依赖「构造即建好」的假设要复查（跨页共享 `App`
  状态的初始化顺序、`app.host.val` 仍为 `None` 时构造——实测各页只在点击/挂载回调里读
  host，构造期不读，安全）。
- **空闲预建会把「没做的事」真的做出来**（实测构造期副作用）：
  `pages/system.mbt:431-454` 建真实托盘、`pages/sysprobe.mbt:85` 构造期跑全量系统 I/O
  （读浏览器 sqlite、进程表、自启状态）、`pages/anim.mbt:52` 构造期解码 GIF 并排第一帧
  动画、`pages/data.mbt` 大表构建 + 轮播构造期起自转链。
  收口口径：这些节点一期标 `load=Lazy`（行为与今天一致、零风险），二期逐个把副作用移进
  `on_mount` / 首次交互后摘掉标记——**懒加载对它们是安全的，需要豁免的只是空闲预建**。
- **`segmented` 的 options 是构造期静态**（`gui/ui/nav.mbt:151`，`Array[String]` 一次性
  传入），而 N 层结构下深层入口的候选集合**随父层选中值变化**（切页 → 段条整条换名）。
  复用 `bind_node(sig, f : T -> Node)`（`gui/widget/node.mbt:92`）生成段条，别新造机制；
  它的重建是**整代退订 + 重挂**（`sub_bag_discard` → `remove_child` → `sub_bag_begin` →
  重挂 → `move_child` 保位），段条每切页重挂一次，要确认重挂成本与不丢滚动态。
- **Store 订阅时序**：`ensure` 里调 `build()` 若触发二次订阅/重入，需按 `Store::subscribe`
  语义核对（快照遍历，订阅者里再 `set` 安全，但别写成无限递归，`gui/base/store.mbt:7`）。
- **包边界**：`gui/router` 进库后 API 即公开面，showcase 专有的段折叠/代码复制行等留在
  示例侧，不往公共面漏。
- **`@ui.breadcrumb` 点击语义与多层冲突**：库版面包屑点击时直接 `selected.set(项名)`
  （`gui/ui/nav.mbt:208`），而多层路径下「点第 i 层」= 写第 i 层 + 深层回落，两者不等价；
  且没有可注入的 `on_click`。本包自绘面包屑绕开它（库零改动），代价是与库版两份画法。
- 真机视觉/交互验证由用户执行（AGENTS.md 规则 6）；本方案只保证
  `moon check`/`test`/`build` 零错零警告与无头判据。

## 五、真机验证清单（T10，由用户执行并反馈）

跑法统一是 `cd examples/showcase && moon run .`，读数看终端 stdout。

1. **启动**：窗口出现前不应有可感停顿；`SHOWCASE-READY ... startup_ms=` 报出启动到就绪
   的毫秒数（无头对照量：全量构造 265ms、首屏页 33ms，接入后启动只该付首屏那份）。
2. **空闲预建真的在跑**：启动后先别动，随手点几页，看每次切页打的
   `SHOWCASE-ROUTE page=… pending=… path=…`——`pending` 应逐次变小直到 0。
3. **切页手感**：15 页逐页点一遍，判据是不出空白帧、不「先出一半再补」。重点两页：
   代码文档（构造 138ms，最慢的一页）、数据展示（首帧 paint 77ms，这一份预建搬不动）。
4. **托盘（`Eager` 口径）**：托盘图标应在启动即出现（与接入前一致），不必点开
   系统集成页；点开该页时「托盘」段应显示已建、左右键点击有反应。
5. **系统能力探测（`Lazy` 口径）**：启动后这一页不该有任何探测读数；点开才探。
   请顺带报一下「点开到出数」的大致时长——这页 T1 判据没量（它会真去读浏览器
   sqlite），若明显超过 300ms 就把它再拆段或加页内节流。
6. **段级保形（`Keep`）**：页内切段再切回，各段滚动位置应各自保留；切页再切回，
   段选中态与滚动位置都不丢。
7. **主题切换后 link 仍有效**：切深/浅色、换主色之后，侧栏、段条、页内
   `segmented`/`breadcrumb` 演示项都应继续能导航（主题重画不应把路由状态带走）。
8. **菜单栏与单实例**：原生菜单栏「导航」四项走 `on_link`，切页应与点侧栏一致；
   再开一个实例应唤起首实例并跳回基础组件 + 冒提示（`nav.goto`）。
9. **图标库/大数据页**：点开应即时（图标墙整页构造实测 9ms）。
10. **淘汰路径（`Lru`）暂不在真机清单里**：showcase 全部页面默认 `Keep`，淘汰只有
    wbtest 覆盖；要看真机淘汰手感，需要给某些页显式挂 `evict=Lru(n)`——这条等用户
    决定是否加开关，加了再补一步「反复进出同一页，动画/轮播不得变快」（变快即
    定时器排了双份）。

