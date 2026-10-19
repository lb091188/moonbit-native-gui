// 单窗口页面路由：一棵任意深度的路由树 + 每层一个权威选中键 + link 绑定。
// 路由不认识「菜单」「段」这类载体——侧栏、段条、面包屑、表格行、按钮、原生菜单项、
// 快捷键都只是 link 的宿主，一律走同一个绑定入口（见本包的 link 面）。
//
// 键口径：每层存该层短名，唯一性域是**同父唯一**（跨父重名合法）；路径 = 各层选中值
// 用 `/` 连接。层级状态与路径归一化在 `levels.mbt`，挂载槽与预建队列在 `view.mbt`。

///|
/// 节点内容什么时候构造。默认口径由 `Router` 给，节点可逐个覆盖。
pub(all) enum LoadPolicy {
  /// 建窗当场构造，不进空闲队列（启动期就需要其构造效果的节点用它）
  Eager
  /// 空闲时按先序队列构造（`Router` 默认）
  Prefetch
  /// 首次选中才构造，永不空闲预建
  Lazy
}

///|
/// 每层槽里这一棵子树挂载过之后怎么处理。
pub(all) enum EvictPolicy {
  /// 挂过就保形：切页只切显隐，不重建，滚动位置各自保留
  Keep
  /// 本层槽最多保 `n` 棵已挂载子树，超出的最久未用者淘汰
  Lru(Int)
}

///|
/// 路由树的一个节点。`key` 是该层短名；`children` 非空即分支（叶的 `build` 必给，
/// 分支不给），`load`/`evict` 为 `None` 时跟随所在 `Router` 的默认值。
pub struct Route {
  key : String
  children : Array[Route]
  build : (() -> @widget.Node)?
  load : LoadPolicy?
  evict : EvictPolicy?
}

///|
/// 叶节点：内容到首次挂载（或按策略提前构造）时才由 `build` 建出来。
pub fn route_leaf(
  key : String,
  build : () -> @widget.Node,
  load? : LoadPolicy,
  evict? : EvictPolicy,
) -> Route {
  { key, children: [], build: Some(build), load, evict }
}

///|
/// 分支节点：只带子表，自己不构造内容。子表至少要有一个节点。
pub fn route_branch(
  key : String,
  children : Array[Route],
  load? : LoadPolicy,
  evict? : EvictPolicy,
) -> Route {
  { key, children, build: None, load, evict }
}

///|
/// 策略判定走 `match`，不给枚举派生 `Eq`：本工具链里 `derive(Eq)` 会把 impl 方法
/// 隐式升成普通方法并告警（`gui/widget/drag.mbt:60` 同条记档）。
fn LoadPolicy::is_lazy(self : LoadPolicy) -> Bool {
  match self {
    Lazy => true
    _ => false
  }
}

fn LoadPolicy::is_eager(self : LoadPolicy) -> Bool {
  match self {
    Eager => true
    _ => false
  }
}

///|
/// 叶节点判定。
pub fn Route::is_leaf(self : Route) -> Bool {
  self.children.length() == 0
}

///|
/// 子树深度：叶为 1，分支为 1 + 子表最大深度。
pub fn Route::depth(self : Route) -> Int {
  if self.is_leaf() {
    1
  } else {
    let mut best = 0
    for c in self.children {
      let d = c.depth()
      if d > best {
        best = d
      }
    }
    best + 1
  }
}

///|
/// 同父重名表（返回「父路径 / 重名」说明，空数组=通过）。唯一性域是同父唯一，
/// 所以只比同一 parent 下的兄弟，跨父重名不报。逐层由 `check_level` 调用，
/// 本函数自己不递归。
fn dup_keys_at(parent_path : String, siblings : Array[Route], out : Array[String]) -> Unit {
  let seen : Map[String, Int] = Map([])
  let order : Array[String] = []
  for r in siblings {
    let n = seen.get_or_default(r.key, 0)
    if n == 0 {
      order.push(r.key)
    }
    let _ = seen.set(r.key, n + 1)
  }
  for k in order {
    let n = seen.get_or_default(k, 0)
    if n > 1 {
      out.push("同父重名：" + parent_path + " 下的「" + k + "」出现 " + n.to_string() + " 次")
    }
  }
}

///|
/// 路由树构造期契约检查：空键、同父重名、分支空子表、叶缺 `build`、分支带 `build`、
/// 同父兄弟深度不齐。返回全部违规说明，空数组=通过。
fn tree_errors(roots : Array[Route]) -> Array[String] {
  let out : Array[String] = []
  if roots.length() == 0 {
    out.push("路由表为空")
  }
  check_level("", roots, out)
  out
}

fn check_level(path : String, level : Array[Route], out : Array[String]) -> Unit {
  let mut depth = -1
  let mut first_key = ""
  for r in level {
    let here = join_path(path, r.key)
    if r.key == "" {
      out.push("键为空：" + path + " 之下")
    }
    if r.key == "/" {
      out.push("键不能是分隔符：" + here)
    }
    // 同父必须等深：叶算 1 层，所以「同层既有叶又有分支」也算不齐——
    // 不齐的表没法给每层配一个选中键（浅的那支在深层没有候选）。
    let d = r.depth()
    if depth < 0 {
      depth = d
      first_key = r.key
    } else if d != depth {
      out.push(
        "同父深度不齐：" + path + " 下的「" + first_key + "」深 " + depth.to_string() +
          " 而「" + r.key + "」深 " + d.to_string(),
      )
    }
    if r.is_leaf() {
      match r.build {
        None => out.push("空节点：既无子表也无 build：" + here)
        Some(_) => ()
      }
    } else {
      match r.build {
        Some(_) => out.push("分支节点不该带 build：" + here)
        None => ()
      }
      check_level(here, r.children, out)
    }
  }
  dup_keys_at(path, level, out)
}

fn join_path(parent : String, key : String) -> String {
  if parent == "" {
    key
  } else {
    parent + "/" + key
  }
}

///|
/// 路由表的层数（= `Router.levels` 长度）。契约不过的直接 abort，键与深度问题
/// 都是写表时的手误，留到运行期只会变成「切不过去」。
pub fn tree_depth(roots : Array[Route]) -> Int {
  let errs = tree_errors(roots)
  if errs.length() > 0 {
    @abort.abort("路由表不合法：" + errs.join("；"))
  }
  let mut best = 0
  for r in roots {
    let d = r.depth()
    if d > best {
      best = d
    }
  }
  best
}
