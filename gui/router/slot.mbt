// 挂载槽：把构造缓存里的内容挂进本层容器、按该层选中键切显隐，并按节点的
// `EvictPolicy` 淘汰已挂载子树。槽只管「挂」和「摘」，什么时候构造由 `prefetch.mbt` 定。
//
// 摘树一律走 `Widget::remove_child`（`gui/widget/widget.mbt:308`）：样式侧表的丢弃钩子
// 只在这条路径上跑（`gui/style/apply.mbt:14`），只丢引用等于没回收。摘的同时退掉这一代
// 登记的订阅、并把这条路径及其下面的已构造内容一起丢掉——重进走 thunk 重建，
// `Node::on_mount`「挂载几次跑几次」（`gui/widget/node.mbt:51`）就不会把定时器排成双份。

///|
/// 一棵挂载中的子树：挂在哪个容器、挂进去的控件、挂载这一代登记的订阅。
struct Mounted {
  holder : @widget.Widget
  widget : @widget.Widget
  offs : Array[() -> Unit]
}

///|
/// 本层入口载体的构造钩子：`(路由, 层号, 父路径, 候选)` → 一个节点。段条、侧栏、
/// 面包屑都走这一个口子（见 `nav.mbt`）；不给就没有入口，分支只挂它的子槽。
pub type SlotBar = (Router, Int, String, Array[Route]) -> @widget.Node

fn evict_of(r : Route, default_ : EvictPolicy) -> EvictPolicy {
  match r.evict {
    Some(p) => p
    None => default_
  }
}

///|
/// `Lru(n)` 的窗口大小；`Keep` 不参与淘汰，给 None。`n` 不足 1 按 1 算。
fn EvictPolicy::lru_cap(self : EvictPolicy) -> Int? {
  match self {
    Keep => None
    Lru(n) => Some(if n < 1 { 1 } else { n })
  }
}

///|
/// `path` 是不是 `prefix` 那一层的直接候选路径（根槽的 prefix 是空串）。
fn under_level(prefix : String, path : String) -> Bool {
  let rest = if prefix == "" {
    path
  } else if path.has_prefix(prefix + "/") {
    path[(prefix.length() + 1):].to_owned()
  } else {
    ""
  }
  let segs : Array[String] = []
  for s in rest.split("/") {
    segs.push(s.to_owned())
  }
  // 空后缀是这一层自己，不是它的候选
  rest.length() > 0 && segs.length() == 1
}

///|
/// 建好但从未挂载的节点不算淘汰对象：样式侧表的丢弃钩子只在摘树时跑，
/// 丢了它反而留残账。所以 `Lru` 只数已挂载的子树。
fn Router::is_mounted(self : Router, path : String) -> Bool {
  match self.mounted.get(path) {
    Some(_) => true
    None => false
  }
}

///|
/// 挂载先后序（最久未用在头），只含本层那一组的。
fn Router::mounted_at(self : Router, prefix : String) -> Array[String] {
  let out : Array[String] = []
  for k in self.mount_order.val {
    if under_level(prefix, k) {
      out.push(k)
    }
  }
  out
}

///|
/// 把一棵子树挂进它的容器：内容在这一步才构造/取缓存，构造与挂载都落在同一个
/// 回收袋窗口里，摘的时候整代一起退订。
fn Router::mount_into_holder(
  self : Router,
  path : String,
  holder : @widget.Widget,
  make_content : () -> @widget.Node,
) -> Unit {
  @base.sub_bag_begin()
  let w = (make_content()).mount_into(holder)
  let offs = @base.sub_bag_end()
  let _ = self.mounted.set(path, { holder, widget: w, offs })
  self.mount_order.val.push(path)
  holder.set_visible(true)
  @widget.invalidate()
}

///|
/// 摘掉一棵子树：先归零它内部各子槽的挂载态（它们各自记着自己挂过），再退订、
/// 摘树、丢内容缓存。
fn Router::unmount(self : Router, path : String) -> Unit {
  match self.mounted.get(path) {
    None => ()
    Some(m) => {
      match self.slot_resets.get(path) {
        Some(f) => {
          let _ = self.slot_resets.remove(path)
          f()
        }
        None => ()
      }
      @base.sub_bag_discard(m.offs)
      let _ = m.holder.remove_child(m.widget)
      let _ = self.mounted.remove(path)
      let keep : Array[String] = []
      for k in self.mount_order.val {
        if k != path {
          keep.push(k)
        }
      }
      self.mount_order.val = keep
      self.purge_built(path)
      @widget.invalidate()
    }
  }
}

///|
/// 本层挂载槽：每个候选一个容器，选中者保证已挂载、其余隐藏。候选集在槽内是静态的
/// ——分支的子槽只在它被挂起来时才建，所以「深层候选随父层变化」这件事发生在子槽的
/// 重新构造上，不需要在同一个槽里换候选表。
pub fn Router::slot(
  self : Router,
  depth : Int,
  prefix : String,
  candidates : Array[Route],
  bar_of : SlotBar?,
) -> @widget.Node {
  let holders : Map[String, @widget.Widget] = Map([])
  let cols : Array[@widget.Node] = []
  for r in candidates {
    let key = r.key
    cols.push(@ui.col([], grow=1.0, handle=fn(w : @widget.Widget) -> Unit {
      let _ = holders.set(key, w)
    }))
  }
  // 这一层里某个候选的淘汰窗口（Keep 给 None）
  fn cap_at(key : String) -> Int? {
    let mut out : Int? = None
    for r in candidates {
      if r.key == key {
        out = evict_of(r, self.default_evict).lru_cap()
      }
    }
    out
  }
  // 挂载窗口：只算 Lru 候选，谁的最新窗口最紧就按谁裁，裁掉最久未用的
  fn trim(fresh : String) -> Unit {
    let lru : Array[String] = []
    for k in self.mounted_at(prefix) {
      let key = if prefix == "" { k } else { k[(prefix.length() + 1):].to_owned() }
      if cap_at(key) is Some(_) {
        lru.push(k)
      }
    }
    let cnt = lru.length()
    let mut need = 0
    for k in lru {
      let key = if prefix == "" { k } else { k[(prefix.length() + 1):].to_owned() }
      match cap_at(key) {
        Some(c) => if cnt - c > need {
          need = cnt - c
        }
        None => ()
      }
    }
    let mut done = 0
    let mut i = 0
    while done < need && i < lru.length() {
      if lru[i] != fresh {
        self.unmount(lru[i])
        done += 1
      }
      i += 1
    }
  }
  fn content_of(r : Route, here : String) -> @widget.Node {
    if r.is_leaf() {
      self.build_now(here)
    } else {
      let parts : Array[@widget.Node] = []
      match bar_of {
        Some(b) => parts.push(b(self, depth + 1, here, r.children))
        None => ()
      }
      parts.push(self.slot(depth + 1, here, r.children, bar_of))
      if parts.length() == 1 {
        parts[0]
      } else {
        @ui.col(parts, grow=1.0)
      }
    }
  }
  fn apply(key : String) -> Unit {
    for r in candidates {
      match holders.get(r.key) {
        None => ()
        Some(h) => {
          let on = r.key == key
          let here = join_path(prefix, r.key)
          if on && !self.is_mounted(here) {
            let rr = r
            self.mount_into_holder(here, h, fn() -> @widget.Node { content_of(rr, here) })
            trim(here)
          }
          h.set_visible(on)
        }
      }
    }
  }
  @ui.col(
    cols,
    grow=1.0,
    handle=fn(_w : @widget.Widget) -> Unit {
      let reset_all : () -> Unit = fn() -> Unit {
        for k in self.mounted_at(prefix) {
          self.unmount(k)
        }
      }
      let _ = self.slot_resets.set(prefix, reset_all)
      apply(self.levels[depth].get())
      self.levels[depth].subscribe(fn(k : String) -> Unit {
        apply(k)
      })
    },
  )
}

///|
/// 整棵路由的视图（从第 0 层起）。挂进窗口根之后，各层选中键就驱动显隐与按需挂载。
pub fn Router::view(self : Router, bar_of : SlotBar?) -> @widget.Node {
  self.slot(0, "", self.roots, bar_of)
}
