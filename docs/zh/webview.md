# 内嵌 webview

`NoahLiu/gui-webview` 把系统 WebView 作为原生子件嵌进自绘界面。定位是「**浏览器的表现力 + 原生能力配合**」：用网页写富内容与交互，用 binding 把原生能力交给页面；不追求完整浏览器复刻——书签、历史、多标签、扩展管理与权限管理面板属于浏览器产品面，不在本模块职责内。

## 能力面

- **导航**：`load_url` / `load_html` / 后退 / 前进 / 重载 / 停止；标题、URL、开始、提交、完成、失败、跳转（重定向）事件。
- **互操作**：`execute_javascript` 求值（按序号配对回包）、DOM 抓取（正文 / 链接 / meta / 结构）、raw binding（页面调原生，回包走 `on_invoke`）。
- **策略**：新窗（拦下 / 放行）、下载（拦下 / 放行；mac 放行档弹系统保存对话框）。
- **其他**：Cookie 查询、自定义协议（`register_protocol`，文件根目录形态）、持久化探测、渲染进程终止事件。

事件统一经 per-view 队列上报（`on_event`），队列满丢最旧：事件是提示，不是账本。

## 权限请求与签名

`Permission` 事件 + `set_permission_mode` + `respond_permission(allow)` 这套接口**保留**，三平台实现：

- **Linux（WebKitGTK）**：`permission-request` 信号，覆盖定位 / 媒体等。
- **Windows（WebView2）**：`PermissionRequested` + deferral。
- **macOS（WKWebView）**：只有媒体采集回调（`requestMediaCapturePermissionForOrigin`，macOS 12+；定位在公开 `WKUIDelegate` 里没有回调）。

**mac 上这条回调要求应用正确打包并签名**（含 `NSCameraUsageDescription` / `NSMicrophoneUsageDescription`）。未签名 / 裸二进制形态下 WebKit 枚举不到采集设备，页面 `getUserMedia` 会挂起、回调不会触发——这不是桩的问题，是引擎侧的既成行为（实测记录见 `proposals/adaptation.md` 与 `experiment/webkit_media_probe/`）。因此本仓示例不做权限演示；事件到达时默认拒绝并记一行事件流水，不让请求挂在引擎里。

## 平台差异简表

| 平台 | 引擎 | 典型差异 |
|---|---|---|
| Linux | WebKitGTK | 需要发行版的 WebKitGTK 开发包；下载 / 权限 / 新窗 / 进程终止都有公开信号 |
| Windows | WebView2 | Loader 与 SDK 头由 prebuild 下载；下载 / 权限 / 新窗走公开 COM 事件 |
| macOS | WKWebView | 下载走 `WKDownload`（macOS 11.3+，保存落点用 `NSSavePanel`）；权限仅媒体且需签名；按目录持久化要 bundle id，裸二进制如实报不可持久 |
