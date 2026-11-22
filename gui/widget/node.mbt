// 声明式地基：`Node` 是「未挂载的 UI 片段」，构造器只建树、`mount` 才实例化
// 控件并挂到父控件（闭包字段是存在类型，兄弟节点天然异构）。
//
// 挂载目标是本栈自绘的 `Widget`（`mount : (Widget) -> Widget`）。
//
// 重挂（relink）形态三条：
// ① **原位替换**而不是「清空再追加」——新一代先挂到尾部、再挪回旧一代原先的
//    位置，兄弟项的顺序与坐标不受被换掉的这项影响（布局引擎为此加了
//    `insert_child` / `remove_child_at`）；
// ② 不需要「推迟一拍」或「重挂后整窗重算」这类规避：命中矩形每帧从布局结果
//    重取（`WindowHost::paint_frame` → `relayout` → `collect_abs`），remove+add 之后不会
//    留下旧矩形；
// ③ 每一代子树的订阅进**回收袋**，重建前整袋退订——死订阅不随重建次数累积。

///|
/// 未挂载的 UI 片段：`mount` 把自己实例化、挂进 parent，返回自己的控件句柄。
pub(all) struct Node {
  mount : (Widget) -> Widget
}

///|
/// 把节点挂进 parent，返回该节点的控件句柄。
pub fn Node::mount_into(self : Node, parent : Widget) -> Widget {
  (self.mount)(parent)
}

///|
/// 已有控件包成节点（挂上去即成为 parent 的直接子项）。
pub fn node_of(w : Widget) -> Node {
  {
    mount: fn(parent : Widget) -> Widget {
      parent.append_child(w)
      w
    },
  }
}

///|
/// 新建一个控件、交给 `finish` 配置并拿到它（等价于「先 new 再 node_of」，
/// 少一行临时变量；组件层与示例都用它）。`finish` 返回要挂出去的控件，
/// 允许在里面再建子控件。
pub fn node_of_new(finish : (Widget) -> Widget) -> Node {
  node_of(finish(Widget::new()))
}

///|
/// 包一层「挂进父控件**之后**跑一次 `f`」的节点：`node_of_new` 的 `finish`、
/// `view` 的 `handle` 都是**构造期**就执行的（页面函数是 `mount_window` 的实参、
/// 求值早于建窗），在那些回调里排 `set_timeout`/读宿主都是「没有宿主」形态
/// （空操作）；真正的挂载时机由使用方的 `mount_into` 驱动（如惰性挂载在首次
/// 选中时才挂），本方法把回调推迟到那一刻。挂载几次跑几次——重挂会重跑，
/// 一次性启动类回调要由调用方保证只挂一次。
pub fn Node::on_mount(self : Node, f : () -> Unit) -> Node {
  {
    mount: fn(parent : Widget) -> Widget {
      let w = (self.mount)(parent)
      f()
      w
    },
  }
}

///|
/// 一组节点按顺序挂进 parent。
pub fn mount_children(parent : Widget, children : Array[Node]) -> Unit {
  for n in children {
    let _ = (n.mount)(parent)
  }
}

// ---- 重绘请求：内容变了要让宿主再画一帧 ----

///|
let repaint_hook : Ref[() -> Unit] = Ref(fn() { () })

///|
/// 安装「请求重绘」回调。宿主装的是 `host_repaint_all`，于是信号回调里的
/// `invalidate()` 就是「所有在窗置脏 + 唤醒平台泵」：一个 Store/信号同时影响
/// 两扇窗时两边都重画，被多余置脏的那扇只多一帧，不会画错。
/// 无宿主（无头测试）时是空操作。
pub fn set_repaint_hook(f : () -> Unit) -> Unit {
  repaint_hook.val = f
}

///|
/// 内容变了、需要重画一帧。没有宿主（无头测试）时是空操作。
pub fn invalidate() -> Unit {
  (repaint_hook.val)()
}

// ---- 滚动重绘：视口局部脏区 + 条带快路径 ----

///|
/// 进程级滚动重绘钩子：`(viewport_id, dy, extent)`。`dy` 是内容位移
/// （正 = 内容向下走），`extent` 是视口内最高的行/块高（条带修复余量）。
/// 宿主装了它就是「视口局部置脏」，没装就回退整窗 invalidate。
let scroll_hook : Ref[((Int32, Double, Double) -> Unit)?] = Ref(None)

///|
pub fn set_scroll_hook(f : (Int32, Double, Double) -> Unit) -> Unit {
  scroll_hook.val = Some(f)
}

///|
/// 滚动偏移变化后的重绘请求（由 `ScrollState::set_offset` 调用）。
pub fn scroll_repaint(viewport_id : Int32, dy : Double, extent : Double) -> Unit {
  match scroll_hook.val {
    Some(f) => f(viewport_id, dy, extent)
    None => invalidate()
  }
}

///|
/// 动画中的滚动视口「本次滚轮已接住、不需要立刻重绘」的标记：惯性/回弹在跑的
/// 事件只更新弹簧目标，下一拍自己会局部置脏；宿主据此跳过整窗兜底（否则每个
/// 输入事件都会触发一帧整窗重绘，动画再顺也会被打回原形）。
let scroll_touch_hook : Ref[((Int32) -> Unit)?] = Ref(None)

///|
pub fn set_scroll_touch_hook(f : (Int32) -> Unit) -> Unit {
  scroll_touch_hook.val = Some(f)
}

///|
pub fn scroll_touch(viewport_id : Int32) -> Unit {
  if viewport_id == 0 {
    return ()
  }
  match scroll_touch_hook.val {
    Some(f) => f(viewport_id)
    None => ()
  }
}

///|
/// 信号变化时重挂子树：值 v → 子树 `f(v)`，**原位**替换上一代。
/// 适合低频换整块视图（随状态换图标、换面板）；高频改属性请让控件自己
/// 订阅并就地更新（文本绑定那类），别每变一次重建一棵树。
pub fn[T] bind_node(sig : Signal[T], f : (T) -> Node) -> Node {
  {
    mount: fn(parent : Widget) -> Widget {
      let current : Ref[Widget?] = Ref(None)
      // 本代子树注册的退订闭包（重建前整袋退订）
      let gen : Ref[Array[() -> Unit]] = Ref([])
      fn rebuild(v : T) -> Unit {
        sub_bag_discard(gen.val)
        let old = current.val
        let at = match old {
          Some(o) => parent.index_of(o)
          None => -1
        }
        match old {
          Some(o) => {
            let _ = parent.remove_child(o)
          }
          None => ()
        }
        sub_bag_begin()
        let w = (f(v).mount)(parent)
        gen.val = sub_bag_end()
        current.val = Some(w)
        if at >= 0 && parent.index_of(w) != at {
          parent.move_child(parent.index_of(w), at)
        }
        invalidate()
      }
      rebuild(sig.get())
      ignore(sig.subscribe(rebuild))
      match current.val {
        Some(w) => w
        None => Widget::new()
      }
    },
  }
}

///|
/// 两态切换：a/b 两棵都预建，按布尔信号显隐，不销毁也不重建。
/// 与 `bind_node` 的取舍：切换频繁用这个（零重建、代价是两棵常驻），
/// 切换稀疏或两态结构差很大用 `bind_node`。
pub fn swap_node(sig : Signal[Bool], a : Node, b : Node) -> Node {
  {
    mount: fn(parent : Widget) -> Widget {
      let va = (a.mount)(parent)
      let vb = (b.mount)(parent)
      fn apply(v : Bool) -> Unit {
        va.set_visible(!v)
        vb.set_visible(v)
        invalidate()
      }
      apply(sig.get())
      ignore(sig.subscribe(apply))
      va
    },
  }
}

///|
/// 语义名包装器：挂载后把控件 `name` 写成本名（测试定位用，`@uitest.by_name`
/// 按它找；将来无障碍复用同一对字段）。纯增量——不动任何既有构造器签名。
pub fn Node::named(self : Node, name : String) -> Node {
  {
    mount: fn(parent : Widget) -> Widget {
      let w = (self.mount)(parent)
      w.name = name
      w
    },
  }
}

///|
/// 控件类名包装器：挂载后写 `role`（如 "button"），测试断言与将来无障碍共用。
pub fn Node::with_role(self : Node, role : String) -> Node {
  {
    mount: fn(parent : Widget) -> Widget {
      let w = (self.mount)(parent)
      w.role = role
      w
    },
  }
}

///|
/// 组件类型名包装器：挂载后写 `kind`（如 "Button"），inspector 树与 dump
/// 的类型列。组件构造已自带类型名，这条给调用方覆盖（包装层、动态建树）。
pub fn Node::with_kind(self : Node, kind : String) -> Node {
  {
    mount: fn(parent : Widget) -> Widget {
      let w = (self.mount)(parent)
      w.kind = kind
      w
    },
  }
}

///|
/// 模板组件标记包装器：挂载后写 `comp`（模板标签原文）并同步 `kind`。
/// mngkit 在每个模板标签调用点包一层——内置组件 kind 本就一致，自定义
/// 组件根借此拿到标签名。检查器组件视图与读屏组节点认 `comp`。
pub fn Node::with_comp(self : Node, comp : String) -> Node {
  {
    mount: fn(parent : Widget) -> Widget {
      let w = (self.mount)(parent)
      w.comp = comp
      w.kind = comp
      w
    },
  }
}
