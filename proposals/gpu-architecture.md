# GPU 合成与 3D 路径

native-gui 从「全 CPU 光栅」走向「GPU 合成 + CPU 光栅并存」的架构决策与落地路径。

## 定位

**当前状态**：所有绘制走 CPU 路径——Painter 立即模式往 Bitmap 写像素，`wm_present` 拷贝到平台窗。这条路径在 1080p/典型桌面 GUI 场景每帧不到 2 ms，不是瓶颈。

**要走 GPU 的原因**：视频、地图、3D 场景、游戏这些内容类型对帧率与像素填充率有硬需求。全功能框架没有「暂不需要 GPU」这个选项——这些场景要求 GPU 在渲染主路径里，不是子视图能糊弄过去的。

## 架构方案

**两层落地 + 三级 fallback**。

### Layer 1：GPU 合成器（内部改造）

- 每个窗口的最终上屏从「bitmap 拷贝到平台窗」改成「bitmap 上传纹理 + GPU 全屏四边形合成」。
- 普通控件继续走 Painter 到 CPU bitmap；视频/地图/3D 控件（Layer 2）把自己的渲染目标当纹理挂进合成场景。
- **对外 API 零变化**——用户代码看不见内部从 CPU 拷贝换成 GPU 合成。
- 收益：大窗缩放流畅、多层动画不抖动、省电（桌面端感知弱）。

### Layer 2：控件级 GPU 绘制（协议扩展）

- `Widget.on_render(Widget, RenderCtx, Rect)` 走 GPU context 提交 shader/vertex buffer。
- `RenderCtx` 是 `@render` 包里的枚举：当前只有 `Cpu(Painter)` 变体；WebGPU 落地时新增 `Gpu(GpuContext)` 变体，`paint_walk` 派发时探测分派。
- **口子已留**：`Widget.on_render` 字段与 `RenderCtx` 枚举已在协议层就位；现有控件走 `on_draw` 不受影响。

### 三级 fallback

运行时探测分派，遵循「不用 `#cfg(platform=)`」的跨平台硬规则：

```
WebGPU 可用 → GPU 合成（Layer 1+2 都开）
不可用 → Cairo 可用 → Cairo CPU 光栅（现状，Linux 主链路）
      不可用 → Pure MoonBit 光栅（现状回退档，Windows 主链路）
```

## 后端选型

**WebGPU via wgpu-native**。

| 方案 | 依赖重量 | C ABI | 三平台后端 | 判定 |
|---|---|---|---|---|
| **wgpu-native** | 9.3 MB .so | ✅ 纯 C11 | D3D12 / Vulkan / Metal 单 API | **选它** |
| Dawn (Google) | 数十 MB | ❌ C++ | 同上 | 依赖过重、FFI 要包一层 |
| Skia GPU | 20 MB+ | ❌ C++ | 需 gn/depot_tools 自编译 | 依赖链过长 |
| OpenGL 子视图 | 系统自带 | ✅ | Win/Linux 稳，macOS 已 deprecated | 平台定时炸弹 |
| 裸 Vulkan | 零额外 | ✅ | 三平台各写一套 surface/present | 工作量数倍 |

**MoonBit 侧现成绑定**：`moonbit-community/wgpu-mbt`（Apache-2.0，2026-09 活跃，pin v29.0.1.1）。它按 `native-stub` + `MBT_WGPU_NATIVE_LIB` dlopen + prebuild 下发链接参数的模式组织——与本仓 webview / media 模块的独立模块形态同构。

**回调线程坑**：`webgpu.h` 明确警告 `WGPURequestAdapterCallback` 等回调可能在任意线程自发触发，重入是 UB。wgpu-mbt 用 C 侧 mutex 守护的静态槽 + 1 ms 轮询吃掉回调，MoonBit 侧只见 `device_poll` 之类同步外形——与本仓 `wm_hotkey_poll` 同一手法。**这层轮询必须留在 C 侧**，不做 C→MoonBit 回调。

## 落地路线

**第一步**：X11 窗口里 wgpu 出三角形色块（真机肉眼验收，与 webview 首轮同形态）。

**第二步**：`wm_present` Linux 分支走纹理合成；Win / mac 后端各自跟上。

**第三步**：`RenderCtx` 开 `Gpu(GpuContext)` 变体。视频控件先切，地图 / 3D 场景控件随后续批次。

## 平台兼容档位

| 平台 | 后端 | 系统门槛 | 兼容跨度风险 |
|---|---|---|---|
| Windows | D3D12 | Win10 1809+（FL 11_0 实际要 20H2+） | 已承诺档全覆盖 |
| Linux | Vulkan | Vulkan 1.1+ 驱动 | **deepin 20 待真机复验** |
| macOS | Metal | macOS 10.15+ | 真机验证收口前不构成对外承诺 |

任一档缺时语义化降级到 CPU 合成，不阻断构建——这与 webview 引擎缺位时退占位、通知后端缺位时给 Unsupported 是同一档位口径。

## 与现有架构的接缝

- **@render** 的 `Backend` 枚举（`CairoBackend | PureBackend`）加 `GpuBackend(WebGpu)` 变体；`Painter::new` 探测顺序 WebGPU → Cairo → Pure。
- **@win** 的 `wm_present` C 桩按三分支加 GPU 上屏路径；`ChildSurface` 通道（现有 webview 嵌入机制）在 GPU 合成下语义不变。
- **@widget** 的 `paint_walk` 派发已经改到 `on_render` 优先、`on_draw` 回退。GPU 后端落地时只是往 `RenderCtx` 枚举加变体，不改派发。
- **@gui-media** 的视频解码帧已经是 RGBA `Bytes`，切 GPU 只是从「拷进 CPU Bitmap」换成「上传成纹理」，接口签名不动。

## 模块形态与三层可选（2026-11-03 定案）

**gui-gpu 是独立模块**（`modules/gui-gpu`，独立发 mooncakes），主包 `gui` 的依赖图里没有它——应用不加依赖就不背任何 GPU 东西，GUI 库默认全 CPU 路径。可选性靠三层，与 webview / media 同一口径：

| 层 | 机制 | 落法 |
|---|---|---|
| 包级 | 独立模块独立发版，主包不依赖 | 应用 `moon.mod.json` 不引 `@guigpu` → 构建链里不存在 wgpu，一 KB 不背 |
| 构建级 | prebuild 下载失败降级 | Release 下载 wgpu-native 归档（sha256 + 双镜像，同 ffmpeg vendor 模式）；失败 → 空 link_configs 保可构建 |
| 运行级 | dlopen + adapter 探测 | wgpu-mbt 本就 `MBT_WGPU_NATIVE_LIB` dlopen：.so 缺失或驱动不支持 → 探测 false → 回退 Cairo / Pure，语义化降级不崩 |

分发影响：wgpu-native .so 约 9.3MB，release-bin 随包（三平台 zip 体积 +9MB 量级），许可随归档走；开发期不装 gui-gpu 的环境一切照旧。

## 融合模型（2026-11-03 定案）

**CPU 内容是一张纹理，每个 GPU 控件各是一张纹理，GPU 合成器按控件树把它们叠起来。**

- **Layer 1 只改最后一环**：控件照旧 Painter 画进 CPU Bitmap，`wm_present` 从「Bitmap 拷贝到平台窗」改成「Bitmap 整张上传纹理 → 全屏 quad → swapchain」；GPU 不可用回退原拷贝路径，逐像素一致。
- **Layer 2 混排一窗**：GPU 控件经 `RenderCtx::Gpu` 渲到自己的 render target，合成器按 rect + clip + opacity 与 CPU 纹理叠合成；派发口子已留（`on_render` 优先、`on_draw` 回退），两类控件互不知晓。
- **视频直纹理**：`GpuContext` 层给 hw frame 导入留接口位（只留口，不排期不实现）——硬解落地后视频控件纹理从「CPU 帧上传」升「解码直导」，只是该控件的纹理来源变了，合成路径零改动。
- **GPU 内容画布**：`GpuContext` 原始接口暴露给应用，3D 引擎/场景图不做在库里（未来 gui-3d）；webview 的 ChildSurface 是系统合成的独立面，GPU 合成下语义不变。

## 不做

- **shader 热重载 / 场景图 DSL**：本库给 `GpuContext` 原始接口，3D 引擎/场景图归独立模块（未来 `gui-3d`）。
- **文字 SDF/MSDF 迁移**：GPU 合成阶段文字仍走 Pango/DirectWrite 到位图再上传纹理。SDF 路线独立评估。
- **移动端**：只做三平台桌面。

## 时间线与分批（2026-11-03 定案排期）

- **已就位**：`RenderCtx` + `on_render` 协议口子；「参赛赛季内 GPU 不动」冻结约束解除（新赛季到来）。
- **GPU 线分批**（每批验收判据随批补进本节）：
  1. `modules/gui-gpu` 骨架 + **X11 wgpu 三角形验收**（真机肉眼，第一步不变）
  2. L1-Linux：`wm_present` GTK X11 臂走纹理合成；fallback 探测粒度与 Wayland 会话臂随后
  3. L1-Win / L1-mac：D3D12 swapchain 挂 HWND / CAMetalLayer 挂 NSView，与现有 blit 的切换与回退
  4. L2 协议：`RenderCtx::Gpu(GpuContext)` 最小接口面（够视频 quad 与简单图形）+ 混排合成次序
  5. 首消费者：视频直纹理接口位（仅接口）+ GPU 内容画布 demo 页（赛季验收面）
- **媒体硬解独立线并行**（不依赖上面 1–5）：探针（三平台 hw_device 能建 + vendor 归档 hwaccel flags 核验）→ 实现（hwaccel + hw frame 下传现有 CPU 帧链路 + 回落软解）→ 帧输出抽象（transfer 策略位）。方案细节立项调研后落 `proposals/media-hwdecode.md`。
- **待细化（调研补全后进本方案）**：逐平台 surface/present 改造点与回退点、fallback 探测粒度（进程/窗口级）、GTK 窗与 wgpu surface 的生命周期（resize/最小化/多窗）、CI 无 GPU runner 档位、wgpu-mbt pin 版本与许可归档核对。

架构决策与实测依据见 [roadmap.md](../docs/zh/roadmap.md)「GPU 合成与 3D 路径」小节。跟踪项见同一份 roadmap 的「已规划 · 渲染」节（⏳ GPU 合成、控件级 GPU 绘制、GPU 内容画布三条——最后一条 2026-11-03 由「WebGL 画布」改写归并：桌面原生语境无 WebGL）。
