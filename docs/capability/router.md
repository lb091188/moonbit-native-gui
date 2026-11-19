# 页面路由（@router）

单窗口多页应用：一棵任意深度的路由树 + 每层一个权威选中键。侧栏、段条、面包屑、按钮、原生菜单都只是 link 的宿主，一律走同一个绑定入口。`moon.pkg` 引入：

```
"NoahLiu/native-gui/router" @router,
```

## 三步接线

**1. 定树**：`route_leaf` 挂内容构造，`route_branch` 带子表：

```moonbit
let routes : Array[@router.Route] = [
  @router.route_branch("设置", [
    @router.route_leaf("常规", fn() { @ui.col([@ui.text("常规设置")]) }),
    @router.route_leaf("外观", fn() { @ui.col([@ui.text("外观设置")]) }),
  ]),
  @router.route_leaf("关于", fn() { @ui.col([@ui.text("关于")]) }),
]
```

**2. 建路由**：`new_router(routes)`；每层选中键读 `nav.store_at(0)`（层级 0 起始）。

**3. 接载体**：侧栏与内容区各一行：

```moonbit
let nav = @router.new_router(routes)
// 侧栏
nav.sidebar([("设置", ["常规", "外观"])], label_of=fn(k) { k })
// 主区：选中哪页挂哪页
nav.view(None)
```

放进 `mount_window` 的节点树即可。完整接线（侧栏外包滚动、原生菜单项、切换按钮）见 components 源码 `examples/components/main.mbt`。

## 键与路径

每层存该层短名，唯一性域是**同父唯一**（跨父重名合法）；路径 = 各层选中值用 `/` 连接。`nav.path()` 读当前路径，`nav.goto("设置/外观")` 跳转，`nav.resolve("设置/外观")` 拆成各层键。分支节点的选中键在未显式 goto 时取子表首个叶。

## link 绑定

载体不感知「路由」，只绑定 key：菜单项、按钮、表格行的点击回调都是 `nav.on_link(key)`（拿一个 `() -> Unit` 绑上即跳转）；给已有节点套绑定用 `nav.route_link(key, node)`。原生菜单（`@shell.MenuBar`）同样接 `nav.on_link(name)`。

- 面包屑：`nav.breadcrumb()` 直接给节点。
- 多层：`children_at(depth)` 列某层可选键，`store_at(depth)` / `route_at(depth)` 读写该层状态。

## 加载与淘汰

`LoadPolicy`：`Eager`（建窗当场构造，启动期就要效果的节点用）、`Prefetch`（空闲先序队列预建，`Router` 默认）、`Lazy`（首次选中才构造，重探测页用）。节点可逐个覆盖，不给跟随所在 `Router` 的默认值。

`EvictPolicy`：`Keep`（挂过就保形，切页只切显隐，滚动位置各自保留）、`Lru(n)`（本层槽最多保 n 棵已挂载子树，超出最久未用者淘汰）。

预建相关：`start_prefetch` / `stop_prefetch` 手动控制队列节奏，`build_now(path)` 立即构造，`purge_built` / `purge_all_built` 手动淘汰。查询：`is_built` / `built_count` / `pending_count`。

## 界面语言与路由联动

界面整体换语言时页内容要原地重挂：`nav.localize_remount()` 注册后，语言切换广播会触发重挂（见[多语言](i18n.md)）。配合 `route_leaf` 的 `build` 在挂载期执行，重挂后文案即新语言。
