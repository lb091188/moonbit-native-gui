# gui-gpu

native-gui 的 GPU 扩展模块（模块级可选）。

## 现在有什么

- `gpu/probe.c` + `gpu/gpu.mbt`：**wgpu-native 运行期装载探测**——按
  `MNG_WGPU_LIB` → `vendor/lib/…` → 系统库名依次 dlopen，取到
  `wgpuCreateInstance` 才算可用；结果是一句可打印的 `detail`
  （`loaded(vendor/lib/libwgpu_native.so)` 或 `not-found: 原因`）。
- `prebuild 钩子`：按平台拉 wgpu-native 归档（`v29.0.1.1`，sha256 校验，双镜像），
  解到 `vendor/lib|include`；**下载失败/离线照常输出空 link_configs**——本模块
  不占链接面，没装就是没装，应用照常走纯光栅路径。
- `gpu/gpu.mbt` 的 `GpuCanvas`：**@render.GpuSink 的实现**（GPU 线首消费者）——
  离屏 BGRA 目标 + `draw_texture_rgba` / `fill_rect` 两条 2D 原语 + `finish`
  读回；控件经 `RenderCtx::Gpu` 派发、宿主 `@widget.gpu_set_sink` 设进程级
  sink（见 `GpuCanvas::install`）。
- `gpu/frame.mbt`：**GPU 内容画布的 3D 帧面**（薄壳原始接口）——
  `begin_frame(clear~, depth~)` 帧生命周期带 Depth24Plus 深度附件；
  `create_shader_module` / `create_buffer` / `write_buffer` /
  `create_bind_group` / `create_render_pipeline` 资源薄壳；`GpuFrame` 的
  set/draw 帧内直通；`lib()` 透出 dlopen 句柄，薄壳没覆盖的 webgpu.h 面
  应用 dlsym 直调。枚举常量（拓扑 / 剔除 / 深度比较 / 顶点格式 / 缓冲旗标）
  与 pin 住的 vendor `webgpu.h` 同源。

## 边界

- 3D 引擎与场景图不做在本模块，归未来 gui-3d（见
  [proposals/gpu-architecture.md](../../proposals/gpu-architecture.md)）。
- `vendor/` 不入库（`.gitignore`），由 prebuild 按需下载。
- 无头判据：`moon test gpu` 六用例（2D 原语 / 3D 深度序 / 帧语义 / uniform
  全链），装了 vendor 归档与可用驱动的环境真跑，没装按「降级不是错误」跳过。
