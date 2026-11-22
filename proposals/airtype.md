# airtype：手机扫码投字应用

> 状态：mac 全链已合入待真机（2026-11-22 四批完工，真机清单 AT-1.1～3.2）；linux X11 臂为后续批次。
> 起因：手机往电脑打字要借聊天软件或传文件中转；做一个常驻小应用，电脑起服务出二维码，手机扫码进网页打字，发送后直接打进电脑当前聚焦的输入框。
> 决策（2026-11-22 用户拍板三项）：
> - 应用本体进本仓库新目录 `apps/airtype/`，落位判据同步加行。
> - 上屏注入不抽独立模块，收进 gui 库 `gui/sys`，与剪贴板、托盘同族——它是桌面输入领域的系统能力。
> - 平台范围：mac 先行，linux X11 随后一批；Windows 不在本期。
> - 依赖口径更新（2026-11-22 二次调查）：`moonbitlang/async` 已并入工具链自带的 `moonbitlang/core/async`，改吃 core 版免注册库依赖，签名以工具链 mbti 为准。

## 1. 可行性核账

| 环节 | 方案 | 状态 |
| --- | --- | --- |
| WebSocket 服务端 | 工具链自带 `moonbitlang/core/async`：`@http.Server` 起服务，`@websocket.Conn::from_http_server` 从 HTTP 连接升级 WS | 现成 |
| 服务嵌 GUI 帧泵 | `core/async/external_loop_integration` 的 `ExternalEventLoop` 薄适配层：`poll` 挂 `@win.wait` 加会话泵一拍，唤醒挂 `@win.wake` | 现成 |
| 二维码 | `allenli178/moon-qrcode` 纯 MoonBit 编码器，`size/get/modules` 拿点阵自绘进画布 | 现成 |
| 应用界面 | native-gui 窗口 | 现成 |
| 网页 | 内嵌静态 HTML，输入框 + WS 发送 | 小活 |
| 局域网地址 | gui/sys 网卡枚举 getifaddrs + RFC1918 过滤 + 物理网卡偏好（netif_lan_ip） | 已落 |
| 上屏注入 | gui/sys 新能力，mac 走 CGEventPost | 新平台工作 |

- WebSocket：浏览器与服务器之间的长连接通道，建一次连着不停，双向随时发消息。
- 帧泵：界面应用的事件循环，每帧顺路处理排队事务。
- CGEventPost：macOS 把合成按键事件投进系统的接口，效果等同真实键盘敲入。
- getifaddrs：枚举本机网卡地址的系统调用。
- 点阵：二维码放大后看到的黑白方块网格。

## 2. 落位与模块

- gui 库：`gui/sys` 新增文本注入 `inject.mbt` 与桩臂，照剪贴板同族模式；链接参数进 `scripts/prebuild` 钩子。
- 应用：`apps/airtype/` 独立模块 `NoahLiu/native-gui-apps-airtype`，注册进 `moon.work`。
- `experience/placement.md` 加 `apps/<name>/` 行：独立应用模块，收产品级应用，不收示例；判据同 examples——依赖隔离靠模块。
- 依赖：`NoahLiu/native-gui`、`allenli178/moon-qrcode`；异步与网络能力吃工具链自带 `moonbitlang/core/async`，零注册库依赖。

## 3. gui/sys 文本注入

- 门面一个入口：`inject_text(String) -> Result[...]`，未支持平台返回未实现错误，API 三平台一致。
- mac 臂：CGEventSource 合成键盘事件，事件挂 Unicode 字符串后投递；长文本按每片 20 个 UTF-16 单元分片。
- 权限：mac 需「辅助功能」授权；门面暴露权限查询入口，应用首启引导跳系统设置。
- 桩门禁：ci.yml gate 加 sys 桩臂语法检查，与既有清单同口径。
- linux X11 臂随后一批：XTest 合成按键加键码映射；Wayland 无全局注入标准口，列明限制。

- XTest：X11 的假按键协议，程序伪造按键事件给系统。
- UTF-16 单元：Unicode 的编码切片单位，一个 emoji 占两个单元。
- 辅助功能权限：macOS 对「能控制电脑」的应用的一次性授权开关，在系统设置里点开。

## 4. 应用设计

- 窗口：二维码 + 服务开关、端口、地址 + 连接状态 + 最近上屏记录。
- 服务：async HTTP + WS，监听 `0.0.0.0:8787` 默认端口可改；async 外部事件循环走薄适配层定案——`set_external_event_loop` 挂进 `fn init`，`poll` 调 `@win.wait` 加会话泵一拍，唤醒回调挂 `@win.wake` 纯 C 原语，`terminate` 挂关窗收口。外部循环模式下所有 MoonBit 代码都在主线程，服务回调直接调 GUI，无跨线程队列。
- 网页：内嵌 HTML，输入框 + 发送按钮 + 连接状态；WS 文本消息，服务端回执上屏成功或失败。
- 安全：URL 路径带随机 token，WS 握手校验，同网段无 token 连不上；明文 HTTP，HTTPS 不做——自签证书在手机端要手动信任，体验差。
- 二维码：编码 `http://局域网IP:端口/token`，点阵画进画布。
- 局域网 IP：`@sys.netif_lan_ip`（getifaddrs 枚举 + RFC1918 三段过滤 + 物理网卡优先）。UDP connect 出口技巧弃用——代理 TUN 接管默认路由时取 198.18.x 假地址，2026-11-22 真机踩到。

- token：一次生成的随机口令字符串，拼在网址里当门禁。
- spike：动工前的小段试错编码，只为验证一条路走不走得通。

## 5. 分批施工

- 批 1 gui 注入能力：sys 门面 + mac 桩 + 单测 + gate 行 + adaptation/mac.md 回写。
- 批 2 应用骨架：apps 模块 + placement 行 + moon.work + 窗口界面，二维码自绘与状态面板就位。
- 批 3 服务与网页：外部循环薄适配层 + core/async 服务 + WS + 内嵌页 + token + 局域网 IP。
- 批 4 端到端：扫码、输入、上屏全链 + 权限引导 + docs 中英文档 + 测试用例补录。
- 后批：linux X11 注入臂与应用 linux 适配。

## 6. 风险与开放点

- mac 密码框按系统设计不收合成事件，注入打不进，列明边界。
- core/async 签名随并入 core 有微调——`run_forever` 处理器改收 `RequestHeader`，实装以工具链 mbti 为准。
- 外部循环适配层若遇平台泵语义边角，回落既有帧泵钩子表 200ms 轮询搭车，响应略增、对外行为不变。
- 多网卡并存时取枚举序第一条物理网卡私网地址；虚拟网卡（utun 等）上的私网地址仅作兜底。
- 手机浏览器后台回收标签后需刷新重连，页面带自动重连。
