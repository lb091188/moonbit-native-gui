# Linux L1 窗口呈现：独立 X 子窗口方案

> 2026-11-06 定稿。给接手的实现者用；背景与实测证据在
> `experience/adaptation.md`「Linux GTK 窗口 present 被合成覆盖」节。

## 目标

Linux/X11 上恢复 L1（全窗 CPU 位图 → GPU 纹理 → 全屏 quad → present），
达到与 mac 相同的效果：present 的内容真正显示、界面随交互更新、无白屏/
冻结；GPU 不可用时逐像素回退 cairo。

**不改 CPU/GPU 混合模型**：位图上传纹理、quad 合成、present 这套代码三臂
共享，本方案只换 Linux 的「落点窗口」。

## 根因（一句话）

现在 present 到 GTK 顶层窗口的 GdkWindow；GTK 每帧把整窗合成到离屏
surface 再贴回窗口，present 的内容被这一次贴图覆盖。窗口因此永远停在
首帧（rainbow 诊断：每帧 present 成功、窗口颜色固定）。

mac 能成立是因为 `CAMetalLayer` 是视图的合成层，系统合成器保留其内容；
GTK/X11 没有等价物。给 GPU 内容一个 **GTK 不绘制** 的窗口即可。

## 方案

在 GTK 窗口客户区内创建并自管一个 **X 子窗口**（child window），Vulkan
present 到它：

- 它是顶层窗口的 X 子窗口，不是顶层窗口：无标题栏/边框/任务栏项，
  视觉上仍是同一个窗口；
- 子窗口设 **空输入形状**（X Shape 扩展），鼠标/键盘事件穿透到父窗口，
  现有事件链一行不改；
- 位置/尺寸与自绘区完全重合，由宿主布局驱动同步；
- 子窗口放在兄弟子窗口的最底层（`XLowerWindow`），原生子件（webview/
  视频）仍在它之上，不会被挡住。

## 实现步骤

全部在 `gui/win/stub.c` 的 GTK 臂（`WM_STUB_GTK` 段）内，约 200 行。

### 1. 状态与创建

`WmWindow`（GTK 臂结构，约 4930 行）加：

```c
Window l1_child;   // L1 present 子窗口（0 = 未建）
int l1_child_w;    // 已同步的物理像素尺寸
int l1_child_h;
```

创建函数：

```c
static int wm_l1_child_ensure(WmWindow *w) {
  if (w->l1_child != 0) return 1;
  GdkWindow *parent = gtk_widget_get_window(w->window);
  if (parent == NULL) return 0;            // 未 realize，下帧再试
  Display *dpy = (Display *)gdk_x11_get_default_xdisplay();
  Window pxid = (Window)gdk_x11_window_get_xid(parent);
  XWindowAttributes pa;
  if (!XGetWindowAttributes(dpy, pxid, &pa)) return 0;

  XSetWindowAttributes swa;
  memset(&swa, 0, sizeof swa);
  swa.override_redirect = True;            // 不参与 WM
  swa.event_mask = 0;                      // 不收事件（输入穿透由 shape 保证）
  Window child = XCreateWindow(
      dpy, pxid, 0, 0,
      (unsigned)w->width, (unsigned)w->height, 0,
      pa.depth, InputOutput, pa.visual,
      CWOverrideRedirect | CWEventMask, &swa);
  if (child == 0) return 0;

  // 空输入形状：点击/键盘全部落到父窗口。没有 Shape 扩展就放弃 L1。
  int ev_base, err_base;
  if (!XShapeQueryExtension(dpy, &ev_base, &err_base)) {
    XDestroyWindow(dpy, child);
    return 0;
  }
  XShapeCombineRectangles(dpy, child, ShapeInput, 0, 0, NULL, 0,
                          ShapeSet, Unsorted);

  XMapWindow(dpy, child);
  XLowerWindow(dpy, child);                // 原生子件保持在其上
  XFlush(dpy);
  w->l1_child = child;
  w->l1_child_w = w->width;
  w->l1_child_h = w->height;
  return 1;
}
```

要点：

- `w->width/height` 是后端口径的物理像素（`wm_on_size_allocate` 抄的
  allocation）。**必须与 GTK 的 scale factor 对齐**：若系统有缩放，用
  `gdk_window_get_width/height(parent)` 取真实像素，并在 `size-allocate`
  里同步；首版按 1:1，遇到 HiDPI 用 GDK 的 `gdk_window_get_scale_factor`。
- 子窗口尺寸必须 >0；0×0（最小化）时不建。
- 不要选 `ExposureMask`：我们不需要处理 expose，X 在无合成器时保留内容；
  有合成器时由合成器持有窗口内容。

### 2. 表面绑定

`wm_l1_try`（GTK 臂，约 5725 行）把 surface 源从
`gtk_widget_get_window(w->area)` 换成 `w->l1_child`：

```c
if (!wm_l1_child_ensure(w)) return 0;      // 建不出就回退 cairo
void *surf = wm_l1_surface_xlib(dpy, (uint64_t)w->l1_child);
```

`st->sw/sh` 用 `w->width/height`（与子窗口一致）。

### 3. 尺寸同步

在 `wm_on_size_allocate`（约 5250 行）或 `wm_l1_try` 每帧检查：

```c
if (w->l1_child != 0 &&
    (w->l1_child_w != w->width || w->l1_child_h != w->height)) {
  XMoveResizeWindow(dpy, w->l1_child, 0, 0,
                    (unsigned)w->width, (unsigned)w->height);
  w->l1_child_w = w->width;
  w->l1_child_h = w->height;
  XFlush(dpy);
}
```

`wm_l1_window_present` 已有的尺寸变化分支会重配 surface，不用另写。

### 4. 生命周期

- `wm_close`（GTK 臂，约 5900 行）：`if (w->l1_child) { XDestroyWindow(dpy,
  w->l1_child); w->l1_child = 0; }`（在 memset 前）。
- 窗口 hide/show：子窗口随父窗口自动隐藏（X 子窗口随父 map/unmap）。
  `wm_l1_window_drop` 仍按原逻辑释放 surface。

### 5. 恢复原始绘制路径

方案成立后，撤掉当前为「直接 present 到 GTK 窗口」临时加的补丁（当前
工作区已回退到干净状态，不需要撤）：

- `wm_on_draw`：`w->l1.on` 时 cairo 停手（原逻辑）；
- 不需要窗口 draw 拦截、after-paint、idle 上屏；
- 不需要 `gtk_widget_set_has_window(area, TRUE)`；
- `wm_present` GPU 成功即可 return（原逻辑）。

### 6. 开关与默认值

当前 master 的 GTK 臂默认回退（`NATIVEGUI_GPU_L1=1` 才开启，见
`wm_l1_try` 开头）。**本方案验收通过后**：

- 删除环境变量门，改为默认尝试；子窗口/Shape 建不出时自动回退 cairo；
- 保留 `dead` 的永久回退语义。

## 验收（真机，用户执行）

1. `moon run examples/showcase`：
   - 启动即正常界面，`NATIVEGUI_GPU_LOG=1` 有「窗口呈现挂上 GPU 档」；
   - 侧栏切页、按钮点击、输入框输入、悬停底色全部即时更新；
   - 拖动窗口、遮挡后露出、缩小再放大，内容正确、无透明洞；
2. 颜色诊断（改回后跑一次）：把 present 的 clear 换成每帧变化的颜色，
   窗口颜色必须跟着变（证明每帧 present 都可见）；
3. 多窗口：同时开两个窗口（如 showcase 的浮层弹窗），各自正常；
4. 原生子件：`examples/browser`（webview）里 GPU 窗口存在时，webview
   仍显示在 GPU 层之上、点击落在 webview；
5. 回退：临时把 wgpu 库挪走，界面照常（cairo），无崩溃；
6. 门禁：`cd gui && moon check` 零警告；`moon test gui-gpu` 3/3；
   `moon test win` 全绿。

## 回退

子窗口创建失败、Shape 扩展不可用、surface 绑定失败 → `wm_l1_try` 返回 0，
自动走 cairo；不改动 cairo 路径一行。

## 风险与开放问题

- **HiDPI/缩放**：子窗口是物理像素，GTK allocation 是逻辑像素；首版按
  scale=1，之后按 `gdk_window_get_scale_factor` 换算。
- **原生子件层级**：`XLowerWindow` 放在兄弟最底；若栈内还有其它
  `XRaiseWindow` 调用（webview 挂载），需在同批完成后重新 lower 一次。
- **合成器/无合成器**：两种情况子窗口内容都由父窗口合成；若某 WM 对
  override-redirect 子窗口有特殊处理，记为实测边界。
- **输入形状**：Shape 扩展不可用的极老环境回退 cairo；不做事件转发。
- **透明窗口**：`trans_mode`/逐像素透明仍走 cairo（Win32 臂同口径）。
- **Wayland 原生会话**：无 XID，保持永久回退（本方案只管 X11）。

## 关联

- 已落地且不要回退的修复：`pd.multisample.mask = 0xFFFFFFFF`（L1 /
  canvas / triangle）——GPU 离屏渲染出像素的前提。
- 现有开关：`NATIVEGUI_GPU_L1=1` 显式开启窗口 present（默认关）。
- 经验记录：`experience/adaptation.md` 同批新增的「Linux GTK 窗口
  present 被合成覆盖」节。
