# 混合 DPI 动态缩放：窗口、样式、帧位图三处口径统一

> **状态**：已规划（2026-11-21），本批实施。
> **起因**：TODO.md「混合 DPI 动态缩放」——Windows 125% / 150% 缩放档下界面物理尺寸不随缩放变化而偏小；窗口拖到另一缩放档显示器后不重排。
> **决策**（本批定案）：
> - MoonBit 层与 C 桩账本统一逻辑单位；帧位图与上屏恒物理像素；两套口径由窗级缩放因子连接。
> - 缩放因子每帧现读，不缓存、不广播，不新增 DPI 变化事件。
> - mac / win / linux 三平台同批切换；Linux X11 无缩放档环境下因子恒 1，行为零变化。

- DPI：屏幕像素密度，决定界面缩放倍率。
- 逻辑单位：与设备无关的布局单位，Windows 叫 DIP，macOS 叫点，GTK 用逻辑像素；100% 缩放档下 1 逻辑单位 = 1 物理像素。
- 物理像素：屏幕或位图上真实的最小成像格子。
- 缩放因子：1 逻辑单位折合多少物理像素，mac Retina 为 2.0，Windows 125% 档为 1.25。

## 1. 现状核账

| 面 | 现状 | 证据 |
| --- | --- | --- |
| 窗口尺寸 | 三平台账本不一——win/mac 存物理像素，GTK 存逻辑单位 | gui/win/stub.c `wm_size` 三分支 |
| 样式尺寸 | token 裸数直进 yoga，单位与窗口账本同源，无缩放乘除 | gui/theme/theme.mbt、gui/style/tokens.mbt |
| 帧位图 | 位图 = 窗口账本尺寸，1:1 上屏 | gui/widget/app.mbt `paint_frame` |
| 事件坐标 | win/mac 物理像素，GTK 逻辑 | gui/win/stub.c `pushPointer` 等 |
| 缩放因子读数 | 全仓无出口——mac 有私有 helper 不导出，win 从不读，GTK 不存在 | gui/win/stub.c `wm_scale_of` |
| 缩放变化处理 | 无——win `WM_DPICHANGED` 只按系统建议矩形重摆；mac 无跨屏代理 | gui/win/stub.c |
| mac 入参语义 | 建窗入参被当物理像素除以因子，Retina 上窗口点数只有入参一半 | gui/win/stub.c `wm_window_new` |

- 125% 界面偏小的根因：样式 token 是裸数，进布局后 1 数 = 1 物理像素，缩放档越高物理格子越小，界面越小。
- 跨屏不重排的根因：账本只在 resize 回调更新，缩放档变化不触发任何回调，MoonBit 拿不到新因子。

## 2. 口径定案

| 面 | 口径 | 改动 |
| --- | --- | --- |
| 窗口尺寸账本 | 逻辑单位——`Window::new` 入参、`size()`、`Resized` 事件、`origin()`、`move_to`、`set_min_size` 全部按逻辑语义 | C 桩账本与 MoonBit 契约同步 |
| 样式与布局 | 逻辑单位——token 裸数语义即逻辑，零改动 | 无 |
| 事件坐标 | 逻辑单位——C 桩入栈前换算 | win 除以因子；mac 去掉乘因子；GTK 不动 |
| 帧位图 | 物理像素——尺寸 = 逻辑尺寸 × 因子，`present` 传位图物理尺寸 | `paint_frame` 分配口径改 |
| 绘制坐标 | Painter 全局 CTM 放大因子——整树绘制代码零改动 | `paint_frame` 设一次变换 |
| 文本 | 字号逻辑值直传；win / mac 光栅臂在离屏内按字号 × 因子光栅真字形，拒绝插值放大 | gui/text 内部乘因子 |
| a11y 快照矩形 | 逻辑单位出栈，平台臂各自换算 | mac 去掉除因子；win UIA 乘因子 |

- CTM：坐标变换矩阵，Painter 里所有绘制坐标先过它再落到位图像素；已有控件级 transform 在用。
- 上屏：把帧位图贴到屏幕窗口；位图与窗口客户区物理像素 1:1，不缩放。

## 3. 缩放因子来源与变化感知

- 出口：`Window::scale()` 读窗级因子，`gui/win/ffi.mbt` 加 `wm_scale` extern。
- mac：`[NSScreen backingScaleFactor]`，沿用现有私有 helper 改导出。
- win：`GetDpiForWindow(hwnd) / 96.0`，动态取；老系统无该导出时退 `GetDeviceCaps(LOGPIXELSX) / 96.0`。
- GTK：`gtk_widget_get_scale_factor`；X11 无缩放档时恒 1。
- 无头虚窗：恒 1.0，全部既有测试不受影响。
- 变化感知：`paint_frame` 每帧现读因子，位图复用判据按物理尺寸，因子一变位图自动重建、CTM 自动取新值、relayout 每帧照跑自动重排——不需要新增事件类型。
- 平台侧补钩子：
  - mac：窗口代理补 `windowDidChangeBackingProperties` 与 `windowDidChangeScreen`，触发既有 `syncSize` 重报账本并唤醒泵。
  - win：`WM_DPICHANGED` 在按建议矩形重摆之外，主动重算逻辑账本并唤醒泵。

## 4. 改动清单

### 4.1 MoonBit 面

- `gui/win/ffi.mbt`：加 `wm_scale` extern；`gui/win/window.mbt` 加 `Window::scale()`。
- `gui/widget/app.mbt` `paint_frame`：
  - 读因子，位图按逻辑 × 因子分配，复用判据比物理尺寸。
  - `Painter::new` 后设全局缩放变换，裁剪框、控件树绘制、条带快路径全部继续用逻辑坐标。
- `gui/text`：`draw_box_raster` 与各平台 `pt_draw_box` 离屏尺寸、字号、内部坐标乘因子；Windows 文本批的批项坐标与并集矩形随离屏口径走。
- 弹层、拖放、IME、原生子件的矩形出口在 MoonBit 侧零改动——传逻辑值，桩内换算。

### 4.2 C 桩面

- win 桩乘因子 7 处：IM 光标、拖放命中矩形、原生子件、`wm_window_move`、`wm_window_origin` 反向除、最小尺寸、`WM_NCHITTEST`；`uia_provider.c` 快照矩形乘因子；事件与 `WM_SIZE` 账本除因子。
- mac 桩去换算 6 处：IM 光标、子件、`wm_window_move`、`wm_window_origin`、最小尺寸、AX 快照矩形；建窗去掉除因子、`pushPointer` 去掉乘因子、`syncSize` 去掉乘因子——点即逻辑直通。
- GTK 桩：加因子出口；CPU 上屏路径位图（物理）画进逻辑画布前 `cairo_scale`。
- GPU 档 L1：surface 与纹理恒物理口径不变；bind 入参从逻辑账本折算物理。

### 4.3 行为变化预告

- mac Retina 上既有示例的窗口从「入参一半点数」变「入参原值点数」，观感变大一倍——与 win / Linux 对齐，属修正不是回归。
- 逻辑坐标是整数（Int32），125% 档下取整丢半像素精度，命中与文本光标可能有 1 物理像素抖动——行业普遍接受，如实记录。

## 5. 施工分批

- 批 1 口径切换：因子出口 + 三平台桩换算 + `paint_frame` 位图与 CTM + 文本因子 + a11y / IME / 子件 / 弹层换算——一次提交。
- 批 2 收尾：`window_state` 几何记忆口径核对、裸位图直绘族调用方核对、条带快路径在变换下的源目标口径核对。

## 6. 验证

- 编译面：`moon check` / `moon test` / 三平台 `moon build` 零错误零警告；无头测试虚窗因子恒 1 全绿。
- 真机（用户执行）：
  - Windows 125% / 150% 各起一次 hello——窗口逻辑尺寸与 100% 一致，文字、命中、弹层不偏。
  - Windows 125% 档窗口拖到 100% 档屏——重排重采样，不糊不偏。
  - mac 在 1x / 2x 屏之间拖动同一窗口——同上。
  - Linux X11 例行冒烟——行为应零变化。

## 7. 风险与开放点

- `window_state.json` 几何记忆存的是旧口径物理坐标，切换后读回偏移——首版照读不迁移，几何记忆本就是尽力而为。
- `draw_to` / `draw_font` 裸位图直绘族坐标不经变换，实施时逐个核对调用方。
- GTK Pango 在放大变换下的字形清晰度待真机确认。
- 滚轮 delta 除因子后出现小数，事件坐标整数截断可忍，若真机观感差再单独处理滚动精度。
