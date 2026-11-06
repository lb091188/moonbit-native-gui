// X11 wgpu 三角形探针的跑法（GPU 线第一步，方案 gpu-architecture.md 落地
// 路线 1 的真机肉眼验收面）：先 probe 报告库装载形态，再跑 run_triangle——
// 窗口里见一个三色三角形，关窗或按 Esc 退出。
// 跑法：moon run experiment/gpu_triangle
// 没有 X 显示 / 没装 GPU 扩展（vendor 归档没下载）时如实报错退出，不崩
// ——「没装 GPU 扩展」是降级形态，不是错误。

fn main {
  // 先跑再说：triangle.c 的加载器带仓库布局候选（从 cwd 逐级向上找
  // modules/gui-gpu/vendor），从仓库任意目录起都找得到库；probe() 三平台
  // 同口径带同一份候选，失败时它的 detail 可直接当装载诊断面读。
  match @guigpu.run_triangle(frames=600) {
    Ok(_) =>
      println("gpu: 三角形探针跑完——窗口里见过三色三角形才算过（肉眼归真机验收）")
    Err(e) => {
      let p = @guigpu.probe()
      println("gpu: 三角形探针失败：\{e}")
      println("gpu: probe loaded=\{p.loaded} detail=\{p.detail}")
      abort("gpu: 三角形探针失败（详见上一行）")
    }
  }
}
