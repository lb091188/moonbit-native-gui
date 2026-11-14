# GPU 合成与 3D 路径

native-gui 从「全 CPU 光栅」走向「GPU 合成 + CPU 光栅并存」的架构决策与落地路径。

- 光栅：rasterization，把图形描述逐像素算成图的过程，CPU 光栅即纯软件逐像素画。

## 定位

**当前状态**：所有绘制走 CPU 路径——Painter 立即模式往 Bitmap 写像素，`wm_present` 拷贝到平台窗。这条路径在 1080p/典型桌面 GUI 场景每帧不到 2 ms，不是瓶颈。

**要走 GPU 的原因**：视频、地图、3D 场景、游戏这些内容类型对帧率与像素填充率有硬需求。全功能框架没有「暂不需要 GPU」这个选项——这些场景要求 GPU 在渲染主路径里，不是子视图能糊弄过去的。

## 架构方案

**两层落地 + 三级 fallback**。

### Layer 1：GPU 合成器——内部改造

- 合成器：compositor，把多层画面叠成最终一帧的组件。
- 每个窗口的最终上屏从「bitmap 拷贝到平台窗」改成「bitmap 上传纹理 + GPU 全屏四边形合成」。
  - 纹理：texture，显存里的一张图，GPU 合成的基本拼图单位。
- 普通控件继续走 Painter 到 CPU bitmap；视频/地图/3D 控件——Layer 2——把自己的渲染目标当纹理挂进合成场景。
- **对外 API 零变化**——用户代码看不见内部从 CPU 拷贝换成 GPU 合成。
- 收益：大窗缩放流畅、多层动画不抖动、省电——桌面端感知弱。

### Layer 2：控件级 GPU 绘制——协议扩展

- `Widget.on_render(Widget, RenderCtx, Rect)` 走 GPU context 提交 shader/vertex buffer。
  - shader：着色器，GPU 上运行的小程序，决定每个像素怎么画。
  - vertex buffer：顶点缓冲，喂给 GPU 的几何数据。
- `RenderCtx` 是 `@render` 包里的枚举：`Cpu(Painter)` / `Gpu(GpuCtx)` 两变体，`paint_walk` 派发时探测分派。
- **L2 协议已落**：
  - 时间：2026-11-03。
  - `pub(open) trait GpuSink`——`draw_texture_rgba` 视频 quad + `fill_rect` 简单图形，clip/opacity 随方法传——加 `GpuCtx{sink, clip, opacity}` 与 `RenderCtx::Gpu(GpuCtx)`。
    - trait：MoonBit/Rust 的接口定义，声明方法集合供各类型实现。
    - quad：四边形面片，GPU 上贴图的最简几何。
  - trait 形态让主包只定协议不养猪——实现住可选模块 `@guigpu`，主包依赖图里没有 GPU 任何东西。
    - 依据：`pub(open)` 是外部包可实现的前提，sealed trait 默认不许跨包实现。
  - 宿主经 `@widget.gpu_set_sink` 设 sink：设了且控件挂了 `on_render` 才派 Gpu 档，否则 Cpu 档原样——**现有控件一行不动**。
  - 混排合成次序 = 调用序 = 控件树序。
    - `paint_at` 新增 `clip?` 可选参，把父链累乘的有效裁剪当数据传下来。
    - 边界：重叠混排的像素正确性归 L1 present 路径，首批消费者视频 quad 是叶子件。
  - 假 sink 的无头回归钉住：sink 未设全 Cpu、设了拿 Gpu 且 clip/opacity 对、GPU 与 CPU sibling 按树序交错。

### 三级 fallback

运行时探测分派，遵循「不用 `#cfg(platform=)`」的跨平台硬规则：

```
WebGPU 可用 → GPU 合成（Layer 1+2 都开）
不可用 → Cairo 可用 → Cairo CPU 光栅（现状，Linux 主链路）
      不可用 → Pure MoonBit 光栅（现状回退档，Windows 主链路）
```

- WebGPU：新一代标准 GPU 图形接口；wgpu-native 是它的 C 语言实现库。
- Cairo：2D 矢量绘图库，Linux 桌面常用的软件光栅后端。
- Vulkan：跨平台 GPU 图形与计算 API。

## 后端选型

**WebGPU via wgpu-native**。

| 方案 | 依赖重量 | C ABI | 三平台后端 | 判定 |
|---|---|---|---|---|
| **wgpu-native** | 9.3 MB .so | ✅ 纯 C11 | D3D12 / Vulkan / Metal 单 API | **选它** |
| Dawn (Google) | 数十 MB | ❌ C++ | 同上 | 依赖过重、FFI 要包一层 |
| Skia GPU | 20 MB+ | ❌ C++ | 需 gn/depot_tools 自编译 | 依赖链过长 |
| OpenGL 子视图 | 系统自带 | ✅ | Win/Linux 稳，macOS 已 deprecated | 平台定时炸弹 |
| 裸 Vulkan | 零额外 | ✅ | 三平台各写一套 surface/present | 工作量数倍 |

- D3D12：微软 Direct3D 12 的 GPU 图形 API，Windows 现行。
- Metal：Apple 的 GPU 图形 API，macOS 现行。

**MoonBit 侧现成绑定**：`moonbit-community/wgpu-mbt`。它按 `native-stub` + `MBT_WGPU_NATIVE_LIB` dlopen + prebuild 下发链接参数的模式组织——与本仓 webview / media 模块的独立模块形态同构。

- 许可：Apache-2.0。
- 状态：2026-09 活跃，pin v29.0.1.1。
  - pin：把依赖版本钉死在指定版本。
  - dlopen：运行时按路径加载动态库的 C 接口。

**回调线程坑**：`webgpu.h` 明确警告 `WGPURequestAdapterCallback` 等回调可能在任意线程自发触发，重入是 UB。wgpu-mbt 用 C 侧 mutex 守护的静态槽 + 1 ms 轮询吃掉回调，MoonBit 侧只见 `device_poll` 之类同步外形——与本仓 `wm_hotkey_poll` 同一手法。**这层轮询必须留在 C 侧**，不做 C→MoonBit 回调。

- UB：未定义行为，C 语言里后果不可预测的非法操作。
- mutex：互斥锁，同一时刻只允许一个线程进入。

## 落地路线

**第一步**：X11 窗口里 wgpu 出三角形色块——真机肉眼验收，与 webview 首轮同形态。

- X11：Linux 传统窗口系统协议，窗口与显示由 X server 管理。

**第二步**：`wm_present` Linux 分支走纹理合成；Win / mac 后端各自跟上。

**第三步**：`RenderCtx` 开 `Gpu(GpuContext)` 变体。视频控件先切，地图 / 3D 场景控件随后续批次。

## 平台兼容档位

| 平台 | 后端 | 系统门槛 | 兼容跨度风险 |
|---|---|---|---|
| Windows | D3D12 | Win10 1809+，FL 11_0 实际要 20H2+ | 已承诺档全覆盖 |
| Linux | Vulkan | Vulkan 1.1+ 驱动 | **deepin 20 待真机复验** |
| macOS | Metal | macOS 10.15+ | 真机验证收口前不构成对外承诺 |

任一档缺时语义化降级到 CPU 合成，不阻断构建——这与 webview 引擎缺位时退占位、通知后端缺位时给 Unsupported 是同一档位口径。

## 与现有架构的接缝

- **@render** 的 `Backend` 枚举——`CairoBackend | PureBackend`——加 `GpuBackend(WebGpu)` 变体；`Painter::new` 探测顺序 WebGPU → Cairo → Pure。
- **@win** 的 `wm_present` C 桩按三分支加 GPU 上屏路径；`ChildSurface` 通道——现有 webview 嵌入机制——在 GPU 合成下语义不变。
- **@widget** 的 `paint_walk` 派发已经改到 `on_render` 优先、`on_draw` 回退。GPU 后端落地时只是往 `RenderCtx` 枚举加变体，不改派发。
- **@gui-media** 的视频解码帧已经是 RGBA `Bytes`，切 GPU 只是从「拷进 CPU Bitmap」换成「上传成纹理」，接口签名不动。

## 模块形态与三层可选

- 时间：2026-11-03 定案。

**gui-gpu 是独立模块**——`modules/gui-gpu`、独立发 mooncakes——主包 `gui` 的依赖图里没有它——应用不加依赖就不背任何 GPU 东西，GUI 库默认全 CPU 路径。可选性靠三层，与 webview / media 同一口径：

| 层 | 机制 | 落法 |
|---|---|---|
| 包级 | 独立模块独立发版，主包不依赖 | 应用 `moon.mod.json` 不引 `@guigpu` → 构建链里不存在 wgpu，一 KB 不背 |
| 构建级 | prebuild 下载失败降级 | Release 下载 wgpu-native 归档——sha256 + 双镜像、同 ffmpeg vendor 模式；失败 → 空 link_configs 保可构建 |
| 运行级 | dlopen + adapter 探测 | wgpu-mbt 本就 `MBT_WGPU_NATIVE_LIB` dlopen：.so 缺失或驱动不支持 → 探测 false → 回退 Cairo / Pure，语义化降级不崩 |

分发影响：wgpu-native .so 约 9.3MB，release-bin 随包——三平台 zip 体积 +9MB 量级——许可随归档走；开发期不装 gui-gpu 的环境一切照旧。

## 融合模型

- 时间：2026-11-03 定案。

**CPU 内容是一张纹理，每个 GPU 控件各是一张纹理，GPU 合成器按控件树把它们叠起来。**

- **Layer 1 只改最后一环**：控件照旧 Painter 画进 CPU Bitmap，`wm_present` 从「Bitmap 拷贝到平台窗」改成「Bitmap 整张上传纹理 → 全屏 quad → swapchain」；GPU 不可用回退原拷贝路径，逐像素一致。
- **Layer 2 混排一窗**：GPU 控件经 `RenderCtx::Gpu` 渲到自己的 render target，合成器按 rect + clip + opacity 与 CPU 纹理叠合成；派发口子已留——`on_render` 优先、`on_draw` 回退——两类控件互不知晓。
- **视频直纹理**：`GpuContext` 层给 hw frame 导入留接口位——只留口，不排期不实现——硬解落地后视频控件纹理从「CPU 帧上传」升「解码直导」，只是该控件的纹理来源变了，合成路径零改动。
  - hw frame：硬件解码直接产出的显存帧，不过 CPU。
- **GPU 内容画布**：`GpuContext` 原始接口暴露给应用，3D 引擎/场景图不做在库里，未来 gui-3d；webview 的 ChildSurface 是系统合成的独立面，GPU 合成下语义不变。

## 不做

- **shader 热重载 / 场景图 DSL**：本库给 `GpuContext` 原始接口，3D 引擎/场景图归独立模块，未来 `gui-3d`。
- **文字 SDF/MSDF 迁移**：GPU 合成阶段文字仍走 Pango/DirectWrite 到位图再上传纹理。SDF 路线独立评估。
  - SDF/MSDF：有向距离场文字渲染法，把字形烘成距离图，GPU 放大不糊。
  - Pango：GTK 的文本排版库；DirectWrite：Windows 的文本排版库。
- **移动端**：只做三平台桌面。

## 时间线与分批

- 时间：2026-11-03 定案排期。

- **已就位**：`RenderCtx` + `on_render` 协议口子；「参赛赛季内 GPU 不动」冻结约束解除，新赛季到来。
- **GPU 线分批**，每批验收判据随批补进本节：
  1. `modules/gui-gpu` 骨架 + **X11 wgpu 三角形验收**——真机肉眼，第一步不变
  2. L1-Linux：`wm_present` GTK X11 臂走纹理合成；fallback 探测粒度与 Wayland 会话臂随后
     - Wayland：Linux 新一代窗口显示协议，逐步替代 X11，窗口合成由显示服务器的合成器负责。
  3. L1-Win / L1-mac：D3D12 swapchain 挂 HWND / CAMetalLayer 挂 NSView，与现有 blit 的切换与回退
     - swapchain：交换链，GPU 往窗口上屏的帧缓冲队列。
     - HWND：Windows 的窗口句柄。
     - CAMetalLayer：macOS 上承接 Metal 渲染的图层类；NSView 是 macOS 的视图控件。
     - blit：块拷贝，把一张图整块搬到另一张图。
  4. L2 协议：`RenderCtx::Gpu(GpuContext)` 最小接口面——够视频 quad 与简单图形——加混排合成次序
  5. 首消费者：视频直纹理接口位——仅接口——加 GPU 内容画布 demo 页——赛季验收面
- **媒体硬解独立线并行**，不依赖上面 1–5：探针——三平台 hw_device 能建 + vendor 归档 hwaccel flags 核验——→ 实现——hwaccel + hw frame 下传现有 CPU 帧链路 + 回落软解——→ 帧输出抽象——transfer 策略位。方案细节立项调研后落 `proposals/media-hwdecode.md`。
  - 硬解/软解：硬解由 GPU 或专用芯片解码视频，软解走 CPU；hwaccel / hw_device 是对应 API 名。


架构决策与实测依据见 [roadmap.md](../docs/zh/roadmap.md)「GPU 合成与 3D 路径」小节。跟踪项见同一份 roadmap 的「已规划 · 渲染」节——⏳ GPU 合成、控件级 GPU 绘制、GPU 内容画布三条。

- 归并记录：GPU 内容画布一条 2026-11-03 由「WebGL 画布」改写归并——桌面原生语境无 WebGL。
  - WebGL：浏览器的 OpenGL 子集，桌面原生应用不存在这条路径。

**模块骨架落地**：

- 时间：2026-11-03。
- `modules/gui-gpu`：模块根 `moon.mod` + `gpu/` 包。
- `prebuild.py` 按 (系统, 机器) 取归档：Linux x86_64 / Windows x86_64-msvc / macOS x86_64·aarch64，pin `v29.0.1.1`，sha256 逐条写死，双镜像串行、单镜像 180s 总预算，校验通过才解到 `vendor/lib|include`。
  - 边界：挂住不收数据的镜像不能拖住构建。
- `gpu/probe.c` 运行期 dlopen——Win 走 LoadLibraryA——取 `wgpuCreateInstance`；`gpu.mbt` 的 `probe()` 返回 `loaded + detail`；link_configs 恒空——**故意不占链接面**，下载失败/离线就是「没装 GPU 扩展」。
- 许可读数：归档内 `wgpu-native-meta/webgpu.yml` 标 `BSD-3-Clause`；库本体许可与 `wgpu-mbt` 生成代码许可在 L1 批次随依赖引入一并归档核验。

## 落地细节

- 时间：2026-11-03 调研补全。
- 证据级别标注：实测 / 官方文档 / 推断，见各条【】注。

### 逐平台 surface 挂载

入口 `wgpuInstanceCreateSurface(instance, &WGPUSurfaceDescriptor{ label, nextInChain })`，链上按平台给 `WGPUSurfaceSourceXlibWindow{display, window}` / `WGPUSurfaceSourceWindowsHWND{hwnd, hinstance}` / `WGPUSurfaceSourceMetalLayer{layer}` / `WGPUSurfaceSourceWaylandSurface{display, surface}`，旧的 `…DescriptorFromXlibWindow` 等命名已废【官方文档：webgpu-headers `webgpu.h`、Chrome 130 改名表、wgpu-native `ffi/wgpu.h`】。X11/Wayland 还要在 instance 侧经 `WGPUInstanceExtras` 传 `WGPUXlibDisplayHandle` / `WGPUWaylandDisplayHandle`。
- **Linux**：XID 已拿得到——`gdk_x11_window_get_xid`，前提是窗口已 realize。【实测：本仓既有取用点】
  - 取证：`gui/win/stub.c:5371`/`:5417`。
  - XID：X11 窗口的数字句柄。
- **Windows**：桩内槽表的 `w->hwnd` 臂。【实测：本仓代码】
  - 取证：`gui/win/stub.c:1368`。
- **macOS**：现 `WMView` 是 `drawRect:` 非 layer-backing，要走 Metal 须补 `wantsLayer = YES` + `layerClass = CAMetalLayer`。【实测：读码；推断：改动量】
  - 取证：`gui/win/stub.c:9407`。
- **未决**：本仓拿 Xlib XID，而 pin 住的 wgpu-mbt——v29.0.1.1——目前出的是 `create_surface_xcb` 口【实测：wgpu-mbt 已出 `create_surface_xcb` / `_windows_hwnd` / `_macos_ns_view`】——Xlib 与 xcb 两条连接不能混用，要么补 Xlib 口、要么改拿 xcb 连接，第一批三角形验收前定死。
  - Xlib / xcb：X11 的两套 C 客户端库，同一窗口系统的两种连接方式，不能混用。

### fallback 探测粒度

**进程级一次**：建 instance + `request_adapter`，成功即常驻缓存——探一次几十毫秒，按窗重复探是白烧。失败分两档：`.so` 缺 / 驱动无后端 = 永久缓存不再试；surface 配置失败——未 realize、0×0——= **不入缓存**，按窗重算。Wayland 会话臂单列——不同 descriptor 与 extras；本仓 X11 直调全在 `GDK_IS_X11_DISPLAY` 守卫后，Wayland 下「不崩但静默」的口径见 wayland-native.md §2.1。落点：`gpu_backend_available()` 换真探，`Painter::new` 的探测序前置 GPU 档。

- 取证：`gpu_backend_available()` 落 `gui/render/render_ctx.mbt:47`；`Painter::new` 落 `gui/render/painter.mbt:126`。

### 生命周期：GTK 窗 ↔ wgpu surface

- 尺寸变化——`wm_on_size_allocate` `gui/win/stub.c:5082` / `WM_SIZE` / `drawableSizeWillChange`——→ 合并成「下一次 present 前重配 swapchain 一次」；0×0 即最小化时跳过重配且不 present。
- 关窗顺序固定：先释放 swapchain → 再 surface → 再销毁原生对象，反序在 D3D12/Metal 上是 use-after-free 级坑。
  - 取证：`wm_close` 三臂 `:1368`/`:5631`/`:9407`。
  - use-after-free：内存已释放仍被使用，崩溃级缺陷。
- DPI：**本仓没有窗级 logical/physical 换算**【实测：全仓检索】——GPU 档要么先补换算，要么首版限 `scale = 1` 并在能力位上如实声明。
  - 取证：全仓只有 `Image::get_scale_factor`，落 `gui/render/image.mbt:113`。
- present 与 `wm_present` **并存**，桩内分派：GPU 挂上后该 area 的 cairo 贴像素必须停手，否则两路互相覆盖。已知坑：wgpu present 到自绘容器的 `GdkWindow` 会吞掉该容器的鼠标事件【实测】——规避口径：**GPU 内容一律宿主顶层窗，交互挂 Window 级信号**，不往 GtkDrawingArea 里塞。
  - 取证：`experience/adaptation/linux.md`「NUContainer 作为 wgpu 渲染宿主收不到鼠标事件」条。

### CI 三档——无 GPU runner 的判据分层

hosted runner 规格表只列 CPU/RAM/SSD/架构，GPU 属付费 larger runners【官方文档：GitHub-hosted runners reference、GPU runners GA】。据此定三档：
1. **只编不跑**，三平台门禁：符号面与类型面——`moon check`/`moon build` + mac 腿的 `clang -fsyntax-only`。
2. **无头判据**：Linux xvfb 腿——`ci.yml:196` 已有——跑 adapter/surface 创建探针，只断言「API 通路走得通」，**不断言像素**。runner 内 lavapipe 是否可用属未核，判据现场取：`ls /usr/share/vulkan/icd.d && vulkaninfo --summary`；本机实测 `lvp_icd.json` + `libvulkan_lvp.so` 在位，可当自托管二档宿主【实测：本机】。
   - xvfb：X 虚拟帧缓冲，无显示器也能跑 X11 的工具。
   - lavapipe：Mesa 的纯软件 Vulkan 实现，无 GPU 硬件也能跑 Vulkan。
3. **真机肉眼**：出图正确性、切换与回退的观感，归用户三平台清单。
mac arm64 runner 有 Apple GPU 但 MPS 虚拟化受限、wgpu-Metal 能否出帧未验【推断】，不入门禁。

- MPS：Apple 的 GPU 加速框架，GitHub 虚拟化环境对其支持受限。

### wgpu-mbt 与许可

pin v29.0.1.1【实测：wgpu-mbt 版本口】；许可归档核对随骨架批做——下载源、sha256、双镜像与 `LICENSE.md` 落 `docs/THIRD-PARTY-NOTICES.md`。

架构决策与实测依据见 [roadmap.md](../docs/zh/roadmap.md)「GPU 合成与 3D 路径」小节。

## L1/L2 实现批的本机预实证

- 时间：2026-11-04，为下一批 de-risk。
- de-risk：先用小成本实验消掉方案里的风险点。

- **wgpu-native v29.0.1.1 运行期装载在本机——lavapipe/Vulkan——完全可用**：C 原型 dlopen `libwgpu_native.so` → `wgpuCreateInstance` → `wgpuInstanceRequestAdapter`——`WGPUBackendType_Vulkan`——拿到 adapter，status=1 Success；`wgpuDeviceCreateTexture` + `wgpuQueueWriteTexture` + `wgpuCommandEncoderCopyTextureToBuffer` 一条离屏管线走得通，设备/纹理/上传/拷贝四步实测。**离屏渲染 + 回读可作无头判据**，不需要显示服务器——CI 二档 xvfb 之外，本机无头即可验「设备+纹理+绘制+回读」。
  - 离屏渲染：画到内存里的图而不是窗口，供无显示环境的验证与回读。
- **v29 是 future 风格 API**：`wgpuAdapterRequestDevice` 返回 `WGPUFuture`，设备经回调给出——`WGPURequestAdapterCallbackInfo` + `WGPUCallbackMode_AllowSpontaneous`——C 侧要按「回调 + 自发模式」写，不能当同步函数用；surface 的 `wgpuSurfaceGetCurrentTexture` / present 同代。L1 的 wm_present 臂要按这个形态取 current texture。
- **落地边界复述**：L1 的 wgpu 代码住 `gui/win` 桩——wm_present 是内部改造、对外 API 零变化，主包不依赖 gui-gpu 的家规不变——gui-gpu 模块仍是「探测 + 应用侧 GpuContext」的位次；surface 走 `WGPUSurfaceSourceXlibWindow{display, window}`，XID 取点 `gdk_x11_window_get_xid` 已在桩内；present 与 cairo 贴像素二选一——挂上 GPU 就停 cairo 臂，否则两路互相覆盖，`experience/adaptation/linux.md` 已记的坑。
