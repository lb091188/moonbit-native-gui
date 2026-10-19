# Showcase 懒加载 + 单窗口路由机制独立成包方案

## 〇、关键事实

`examples/showcase/` 的现状：

1. **当前"懒加载"只懒挂载，不懒构造。**
   - `main.mbt:209-223` 在启动时**逐个求值** `@pages.page_X(app)`，把每页**已建好的** `@widget.Node` 传进 `nav_page(...)`。
   - 组件构造器一律走 `node_of_new(finish)`（`gui/widget/node.mbt:42`），`finish` 闭包（`Widget::new()` + `mount_children`）**在构造期就跑**——所以 `page_icons(app)` 一求值，整墙图标控件当场实例化。
   - `nav_page`（`shared/section.mbt:84`）+ `section_body`（`section.mbt:110`）确有 `Ref[Bool] mounted` + `selected.subscribe(ensure)` 的懒挂载，但它只是把**已构造**子树的 attach/layout/paint 推迟，**没推迟构造**。
   - 净效果：启动即构造全部页与段的控件，这就是卡启动的根因。作者也在注释里写明这个坑（`overlay.mbt:478`、`message_box.mbt:110`、`docs/zh/declarative.md:44`「page(app) 求值早于建窗」）。

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

### 2.3 建议包形态
```
gui/router/  （或 gui/shell/pages）
  Page       : { name, title, icon?, build : () -> Node }   // build 即 §1 的 thunk
  Router     : { store : Store[String], pages : Array[Page] }
  router_view(router, sidebar_props?) -> Node   // 侧栏(menu_sections) + 右详情 + 懒构造挂载
  // 可选：hash/深链式 push/pop、面包屑、前进后退栈（单窗口内导航历史）
```
- 把 `section.mbt` 的 `nav_page`/`section_body` 上移进包，showcase 改为**消费**该包。
- 包只吃 `Store[String]` + `() -> Node`，与懒加载方案 §1 天然一致：**包的 build 字段就是 thunk**，一次解决两件事。

### 2.4 分层取舍
| 方案 | 优点 | 缺点 | 建议 |
|---|---|---|---|
| A. 只改 showcase（§1） | 改动最小、见效快 | 每个 app 重造轮子 | 先做（M1） |
| B. 抽 `gui/router` 包 | 单窗口 app 复用、机制统一 | 需设计稳定 API、进库门禁 | §1 做完再抽（M2/M3） |

推荐 A→B：先在 showcase 内把构造 thunk 化验证收益与手感，再把沉淀好的 `nav_page`/`section_body` 提为 `gui/router`。

## 三、分期实施

- [ ] **M1 懒构造（showcase 内）**：`nav_page`/`Section.content` 改 thunk；`main.mbt` 包闭包；跑 `moon run examples/showcase` 对比启动构造量。**不动库**。
- [ ] **M2 图标页页内虚拟化**（若 M1 后打开图标页仍慢）：`pages/icons.mbt` 的 icon_grid 走 `virt_list` 只渲染可视区。
- [ ] **M3 抽 `gui/router` 包**：`Page{build:()->Node}` + `Router(Store[String])` + `router_view`；showcase 切换为消费包；补 `gui/router` 包门禁（`moon check` + wbtest）。
- [ ] **M4 文档/路线图**：`docs/zh/roadmap.md` 增"单窗口路由/懒加载"小节；坑（构造期实例化、native 无 code-split）回写 `proposals/adaptation.md`（AGENTS.md 规则 7）。

## 四、风险
- **构造期实例化的连带**：thunk 化后，凡依赖"构造即建好"的假设要复查（如跨页共享 `App` 状态的初始化顺序）。
- **Store 订阅时序**：`ensure` 里调 `content()` 若触发二次订阅/重入，需按现有 `subscribe` 语义核对。
- **包边界**：`gui/router` 若要进库，API 需稳定，别把 showcase 专有段（section 折叠等）漏进公共面。
- 真机视觉/交互验证由用户执行（AGENTS.md 规则 6）；本方案只保证 `moon check`/`test`/`build` 零错零警告。
