// 空闲预建：把「什么时候构造」与「挂在哪」分开——本文件只管构造与缓存，挂载槽在
// `slot.mbt`。排队规则只有一条：从当前路径起按路由树**先序环形**扫（当前节点 → 其
// 子树 → 下一个兄弟子树 → … 补完全树），一拍建一个节点；当前选中路径不当拍就插队建完。
//
// 建完的节点只进缓存不挂载。缓存按路径索引（同父唯一 ⇒ 路径唯一）。

///|
/// 缓存里的一条：构造好的内容，加上**构造期注册的那些订阅的退订闭包**。
/// 组件在构造期就会 `follow_store`/`watch_theme` 这类订阅（`gui/ui/nav.mbt:157`），
/// 回收袋只在挂载窗口里收；预建的构造也得包一层袋子，否则淘汰时这些订阅退不掉，
/// 每次重进都往层 store 上挂一个死订阅（`gui/base/store.mbt:70` 记的正是这条）。
struct Built {
  node : @widget.Node
  offs : Array[() -> Unit]
}

///|
/// 节点没写 `load` 时用路由的默认策略。
fn load_of(r : Route, default_ : LoadPolicy) -> LoadPolicy {
  match r.load {
    Some(p) => p
    None => default_
  }
}

///|
/// 按前缀收集子树里全部叶节点的路径（先序）。
fn preorder_leaves(r : Route, prefix : String, out : Array[String]) -> Unit {
  let here = if prefix == "" { r.key } else { prefix + "/" + r.key }
  if r.is_leaf() {
    out.push(here)
  } else {
    for c in r.children {
      preorder_leaves(c, here, out)
    }
  }
}

fn all_leaves(roots : Array[Route]) -> Array[String] {
  let out : Array[String] = []
  for r in roots {
    preorder_leaves(r, "", out)
  }
  out
}

///|
/// 从 `current` 起的先序环形队列：`current` 本身排在第一位（它归插队那条路管），
/// 接着是它的子树与后续兄弟子树，最后绕回起点之前那段。
fn queue_from(roots : Array[Route], current : String) -> Array[String] {
  let all = all_leaves(roots)
  let n = all.length()
  let mut at = -1
  for i in 0..<n {
    if at < 0 && all[i] == current {
      at = i
    }
  }
  let q : Array[String] = []
  if at < 0 {
    for p in all {
      q.push(p)
    }
  } else {
    for k in 0..<n {
      q.push(all[(at + k) % n])
    }
  }
  q
}

///|
/// 路径对应的节点（各层选中值走不下去时给 None）。
fn route_by_path(roots : Array[Route], path : String) -> Route? {
  let parts : Array[String] = []
  for p in path.split("/") {
    parts.push(p.to_owned())
  }
  let mut level = roots
  let mut found : Route? = None
  let total = parts.length()
  for i in 0..<total {
    let want = parts[i]
    let mut next : Route? = None
    for r in level {
      if next is None && r.key == want {
        next = Some(r)
      }
    }
    match next {
      None => {
        return None
      }
      Some(r) =>
      if i + 1 == total {
        found = Some(r)
      } else {
        level = r.children
      }
    }
  }
  found
}

///|
/// 这一条路径是否已在缓存里。
pub fn Router::is_built(self : Router, path : String) -> Bool {
  match self.built.get(path) {
    Some(_) => true
    None => false
  }
}

///|
/// 取已构造的内容节点（没建过给 None，建的动作由 `build_now` 或 `ensure_current` 发起）。
pub fn Router::built_node(self : Router, path : String) -> @widget.Node? {
  match self.built.get(path) {
    Some(b) => Some(b.node)
    None => None
  }
}

///|
/// 丢掉这条路径及其下一切已构造内容，并把构造期那批订阅退掉。
/// 重进时走 thunk 重建：`Node::on_mount` 挂载几次跑几次（`gui/widget/node.mbt:51`），
/// 留着旧节点重挂就会把定时器/泵排成双份。
pub fn Router::purge_built(self : Router, path : String) -> Unit {
  let under : Array[String] = []
  let offs : Array[Array[() -> Unit]] = []
  for (k, b) in self.built {
    if k == path || k.has_prefix(path + "/") {
      under.push(k)
      offs.push(b.offs)
    }
  }
  for o in offs {
    @base.sub_bag_discard(o)
  }
  for k in under {
    let _ = self.built.remove(k)
  }
}

///|
/// 当场构造这一条路径的内容并进缓存；已建过的直接回缓存里的节点（thunk 只跑一次）。
/// 路径上没有 `build`（分支或非法路径）时 abort——调用方给的都是叶路径。
pub fn Router::build_now(self : Router, path : String) -> @widget.Node {
  match self.built.get(path) {
    Some(b) => b.node
    None =>
    match route_by_path(self.roots, path) {
      Some(r) =>
      match r.build {
        Some(f) => {
          @base.sub_bag_begin()
          let n = f()
          let offs = @base.sub_bag_end()
          let _ = self.built.set(path, { node: n, offs })
          n
        }
        None => @abort.abort("路由节点没有 build：" + path)
      }
      None => @abort.abort("路由表里没有这条路径：" + path)
    }
  }
}

///|
/// 当前选中路径插队建完（等深契约下这条路径必落到一个叶，浅层分支本身没有内容）。
pub fn Router::ensure_current(self : Router) -> Unit {
  let p = self.path()
  match route_by_path(self.roots, p) {
    Some(r) => if r.build is Some(_) {
      let _ = self.build_now(p)
    }
    None => ()
  }
}

///|
/// 已构造进缓存的节点数（与 `pending_count` 一起看才分得清「队列建空了」和
/// 「队列没跑起来」——两种情况 pending 都是 0）。
pub fn Router::built_count(self : Router) -> Int {
  let mut n = 0
  for (_k, _b) in self.built {
    n += 1
  }
  n
}

///|
/// 预建队列还剩多少个待建（跳过的 `Lazy` 不计）。
pub fn Router::pending_count(self : Router) -> Int {
  let mut n = 0
  let q = self.queue.val
  let i = self.queue_at.val
  if i < q.length() {
    for k in i..<q.length() {
      if !self.is_built(q[k]) {
        n += 1
      }
    }
  }
  n
}

///|
/// 建队列里的下一个节点：已在缓存里的、`Lazy` 的都跳过。返回「队列后面是否还有内容」。
pub fn Router::prefetch_step(self : Router) -> Bool {
  let q = self.queue.val
  let n = q.length()
  let mut i = self.queue_at.val
  let mut built_one = false
  while i < n && !built_one {
    let path = q[i]
    i += 1
    if !self.is_built(path) {
      match route_by_path(self.roots, path) {
        Some(r) =>
        if load_of(r, self.default_load).is_lazy() {
          ()
        } else {
          let _ = self.build_now(path)
          built_one = true
        }
        None => ()
      }
    }
  }
  self.queue_at.val = i
  i < n
}

///|
/// 重排队列到当前路径起（选中变了就重新锚定，让最近的先建）。
pub fn Router::reanchor(self : Router) -> Unit {
  self.queue.val = queue_from(self.roots, self.path())
  self.queue_at.val = 0
}

///|
/// 启动期就把标了 `Eager` 的节点建完（这些节点的效果要求启动即生效，不进空闲队列）。
pub fn Router::build_eager(self : Router) -> Unit {
  self.eager_under(self.roots, "")
}

fn Router::eager_under(self : Router, level : Array[Route], prefix : String) -> Unit {
  for r in level {
    let here = if prefix == "" { r.key } else { prefix + "/" + r.key }
    if r.build is Some(_) && load_of(r, self.default_load).is_eager() {
      let _ = self.build_now(here)
    }
    if !r.is_leaf() {
      self.eager_under(r.children, here)
    }
  }
}

///|
/// 起空闲预建：先插队建完当前路径，再每 `tick_ms` 建一个，队列建空就停（不再排拍）。
/// 任一层的选中变化都会立刻插队建完当前路径并重新锚定队列。宿主未就绪时
/// `@shell.set_timeout` 自己排队，装好钩子后按原延时补发，不会空转。
pub fn Router::start_prefetch(self : Router, tick_ms? : Int = 16) -> Unit {
  if !self.prefetch_on.val {
    self.prefetch_on.val = true
    self.ensure_current()
    self.reanchor()
    if !self.wired.val {
      self.wired.val = true
      for i in 0..<self.levels.length() {
        self.levels[i].subscribe(fn(_v : String) -> Unit {
          self.ensure_current()
          self.reanchor()
        })
      }
    }
    self.schedule_tick(tick_ms)
  }
}

fn Router::schedule_tick(self : Router, tick_ms : Int) -> Unit {
  if !self.prefetch_on.val {
    ()
  } else if self.prefetch_step() {
    self.tick_handle.val = @shell.set_timeout(tick_ms, fn() -> Unit {
      self.schedule_tick(tick_ms)
    })
  } else {
    // 建完了：停链，别留一个空转的定时器
    self.prefetch_on.val = false
    self.tick_handle.val = 0
  }
}

///|
/// 停掉空闲预建（已建好的缓存保留）。
pub fn Router::stop_prefetch(self : Router) -> Unit {
  self.prefetch_on.val = false
  let h = self.tick_handle.val
  if h != 0 {
    @shell.clear_timeout(h)
    self.tick_handle.val = 0
  }
}
