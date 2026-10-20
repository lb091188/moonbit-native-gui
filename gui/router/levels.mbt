// 层级状态与路径：每层一个权威 `Store[String]`（存该层短名），路径 = 各层值用
// `/` 连接。写某一层时，它下面的层各自回落到本层候选的首个键——link 只需要给出
// 要写到的那一层，深层不用调用方操心。

///|
/// 单窗口页面路由：一棵路由树 + 每层一个选中键 + 两个默认策略。
/// 可变的构造缓存与队列都是堆上的（`Map`/`Ref`），复制 `Router` 不会把它们分家。
pub struct Router {
  roots : Array[Route]
  levels : Array[@base.Store[String]]
  default_load : LoadPolicy
  default_evict : EvictPolicy
  built : Map[String, Built]
  queue : Ref[Array[String]]
  queue_at : Ref[Int]
  prefetch_on : Ref[Bool]
  wired : Ref[Bool]
  tick_handle : Ref[Int]
  // 挂载登记（slot.mbt）：路径 → 挂在哪个容器、挂进去的控件、这一代的退订袋
  mounted : Map[String, Mounted]
  mount_order : Ref[Array[String]]
  // 每个分支的子槽登记一条重置闭包，淘汰祖先链时用它把子孙槽的挂载态一起归零
  slot_resets : Map[String, () -> Unit]
  // 语言广播句柄（remount.mbt）：0=未登记随语言重挂
  locale_hook : Ref[Int]
}

///|
/// 路由表在某一层里的候选节点（按当前各层选中值往下走）。
fn find_child(level : Array[Route], key : String) -> Route? {
  let mut found : Route? = None
  for r in level {
    if found is None && r.key == key {
      found = Some(r)
    }
  }
  found
}

fn child_keys(level : Array[Route]) -> Array[String] {
  let keys : Array[String] = []
  for r in level {
    keys.push(r.key)
  }
  keys
}

///|
/// 建路由：表不过契约直接 abort（重名、空键、深度不齐都是写表时的手误）；
/// 每层的初始值取该层候选的首个键，即首屏路径 = 首个根一路走到首个叶。
pub fn new_router(
  roots : Array[Route],
  default_load? : LoadPolicy = Prefetch,
  default_evict? : EvictPolicy = Keep,
) -> Router {
  let errs = tree_errors(roots)
  if errs.length() > 0 {
    @abort.abort("路由表不合法：" + errs.join("；"))
  }
  let depth = tree_depth(roots)
  let levels : Array[@base.Store[String]] = []
  let mut level = roots
  for _i in 0..<depth {
    let first = level[0]
    levels.push(@base.Store::new(first.key))
    level = first.children
  }
  {
    roots,
    levels,
    default_load,
    default_evict,
    built: Map([]),
    queue: Ref([]),
    queue_at: Ref(0),
    prefetch_on: Ref(false),
    wired: Ref(false),
    tick_handle: Ref(0),
    mounted: Map([]),
    mount_order: Ref([]),
    slot_resets: Map([]),
    locale_hook: Ref(0),
  }
}

///|
/// 层数。
pub fn Router::level_count(self : Router) -> Int {
  self.levels.length()
}

///|
/// 当前路径（各层选中值连接）。
pub fn Router::path(self : Router) -> String {
  let mut out = ""
  for s in self.levels {
    let v = s.get()
    out = if out == "" { v } else { out + "/" + v }
  }
  out
}

///|
/// 把路径解析成每层的键，段数不足或某段在当前父路径下找不到时，该层回落首个候选键；
/// 超出层数的段忽略。返回长度恒等于层数，不随输入炸——非法路径最坏是「回到该层第一项」。
pub fn Router::resolve(self : Router, path : String) -> Array[String] {
  let parts : Array[String] = []
  for p in path.split("/") {
    parts.push(p.to_owned())
  }
  let keys : Array[String] = []
  let mut level = self.roots
  for i in 0..<self.levels.length() {
    let want = if i < parts.length() { parts[i] } else { "" }
    let chosen = match find_child(level, want) {
      Some(r) => r
      None => level[0]
    }
    keys.push(chosen.key)
    level = chosen.children
  }
  keys
}

///|
/// 按路径导航：一次写多层，自上而下逐层 `set`（`Store::set` 对相同值不通知，
/// 层间互写不会成环）。
pub fn Router::goto(self : Router, path : String) -> Unit {
  let keys = self.resolve(path)
  for i in 0..<self.levels.length() {
    self.levels[i].set(keys[i])
  }
}

///|
/// 该层的候选短名（`depth` 从 0 起）；越界给空数组。
pub fn Router::children_at(self : Router, depth : Int) -> Array[String] {
  let n = self.levels.length()
  if depth < 0 || depth >= n {
    []
  } else {
    let mut level = self.roots
    let mut ok = true
    for i in 0..<depth {
      match find_child(level, self.levels[i].get()) {
        Some(r) => level = r.children
        None => ok = false
      }
    }
    if ok {
      child_keys(level)
    } else {
      []
    }
  }
}

///|
/// 该层的权威选中键，供任意 link 载体绑定；越界 abort。
pub fn Router::store_at(self : Router, depth : Int) -> @base.Store[String] {
  if depth < 0 || depth >= self.levels.length() {
    @abort.abort(
      "取层越界：" + depth.to_string() + "，本路由共 " +
        self.levels.length().to_string() + " 层",
    )
  }
  self.levels[depth]
}

///|
/// 当前路径上该层的节点（策略与 `build` 都挂在节点上）；越界或走不通给 None。
pub fn Router::route_at(self : Router, depth : Int) -> Route? {
  let n = self.levels.length()
  if depth < 0 || depth >= n {
    None
  } else {
    let mut level = self.roots
    let mut found : Route? = None
    for i in 0..=depth {
      match find_child(level, self.levels[i].get()) {
        Some(r) => {
          level = r.children
          if i == depth {
            found = Some(r)
          }
        }
        None => {
          return None
        }
      }
    }
    found
  }
}
