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

## 边界

- 本批只有探测：`GpuContext`、present 合成、视频直纹理都在后续批次
  （见 [proposals/gpu-architecture.md](../../proposals/gpu-architecture.md)）。
- `vendor/` 不入库（`.gitignore`），由 prebuild 按需下载。
