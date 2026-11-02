# gui-dbus（`NoahLiu/gui-dbus`）

native-gui 的 D-Bus 单件（能力模块拆分之一，见 `proposals/module-split.md`）：**纯 MoonBit 线路实现** + 会话/系统总线连接——不挂 glib fd 监视、不依赖 GUI 层，入站数据由宿主周期调 `dbus_pump` 取走，断线自愈延迟重连走 `dbus_set_post_delayed` 注入通道。只依赖 `NoahLiu/gui-sys`。

## 能力清单

| 族 | 内容 |
|---|---|
| 线路 | D-Bus wire 格式编解码、方法调用、属性读写 |
| 托盘 SNI | StatusNotifierItem Linux 半边（Win32 半边在 gui-window，统一门面在 gui-shell） |
| 通知 | org.freedesktop.Notifications |
| 媒体 | MPRIS |
| 电源 | UPower |
| 网络 | NetworkManager 监视 |
| 会话 | logind（空闲/锁屏） |
| 单实例 | D-Bus 臂的实例互斥与唤起 |
| 其他 | 屏幕保护/抑制（inhibit）、文件管理器交互、屏幕读取 |

## 用法

```json
// moon.mod
{
  "import": ["NoahLiu/gui-dbus@0.1.0"]
}
```

## 平台

D-Bus 是 Linux 桌面协议：Windows/macOS 上桩为空实现，能力如实 `Unsupported`（门面出声，不崩溃）。

## 构建

`dbus_stub.c` 只用标准头，走 moon native-stub；无 prebuild、无额外链接参数。
