// Phase 0 探针跑法：moon run experiment/ir_probe
// 验收线：单次「摘 + 建 + 挂」远低于 1000 ms（亚秒线）；换完代后 set 一次
// 只应由现役代渲染（>1 次即旧代订阅残留，IR 通道整体不发生）。

///|
fn main {
  let qty = @base.Store::new(3)
  let level = @base.Store::new(30.0)
  let wifi = @base.Store::new(true)
  let fires = Ref(0)
  let reg = make_registry(qty, level, wifi, fires)
  let holder = @widget.Widget::new()
  let _ = holder.set_column()
  let mut gen = mount_gen(holder, ir_v1(), reg)
  let sc0 = qty.signal().sub_count()
  // 热替换 200 次（v1↔v2 结构交替），整段计时
  let t0 = @env.now()
  for i = 0; i < 200; i = i + 1 {
    unmount_gen(holder, gen)
    gen = mount_gen(holder, if i % 2 == 0 { ir_v2() } else { ir_v1() }, reg)
  }
  let dt = @env.now() - t0
  println(
    "PROBE-SWAP = \{dt} ms / 200 次（均 \{dt * 5} µs/次；验收线：单次 ≪ 1000 ms）",
  )
  // 泄漏检查：换完代后 set 一次，只有现役代渲染
  let before = fires.val
  qty.set(97)
  println(
    "PROBE-LEAK = set 一次渲染 \{fires.val - before} 次（应为 1；>1 即旧代订阅残留）",
  )
  println(
    "PROBE-INT-SUB = qty 订阅数 \{qty.signal().sub_count()}（初代 \{sc0}；相等即不累积——含 bind_label 与 stepper 受控订阅各一条）",
  )
}
