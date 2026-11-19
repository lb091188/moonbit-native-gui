# 系统能力场景

系统能力族统一 `Result` 语义，不支持的环境返回错误值；三平台支持矩阵见[系统能力总览](../capability/sys.md)。import 清单见[场景总览](index.md#公共前提)。

## 打开链接与定位文件

`@sys.open_url` 开 URL；`@sys.open_file` 把文件交系统默认程序；`@shell.reveal_in_file_manager` 在文件管理器中定位并选中。

```moonbit
@ui.col(
  [
    @ui.link("打开文档站", fn() {
      let _ = @sys.open_url("https://moonbit-native-gui.pages.dev")
    }),
    @ui.button("打开图片", on_click=fn() {
      let _ = @sys.open_file("/home/me/photo.png")
    }),
    @ui.button("在文件管理器中显示", on_click=fn() {
      match @shell.reveal_in_file_manager("/home/me/photo.png") {
        Ok(_) => ()
        Err(e) => println("定位失败：\{e}")
      }
    }),
  ],
  row_gap=8.0,
)
```

## 复制到剪贴板

`clipboard_set_text` 直写系统剪贴板，返回 `Bool`。

```moonbit
@ui.button("复制安装命令", on_click=fn() {
  if @sys.clipboard_set_text("moon add NoahLiu/native-gui") {
    toast("已复制", @ui.Success)   // toast 见[轻提示](interaction.md#轻提示)
  }
})
```

读用 `clipboard_get_text() -> String?`。输入框内部已默认接系统剪贴板。

## 桌面通知

`@shell.notify_send(应用名, 标题, 正文, ...)`，先 `notify_supported()` 探测。Linux 走 D-Bus、Windows 走托盘气泡、macOS 走 UN 中心（`notify_backend_name()` 按平台报真名）。

常用可选参：`icon?`（Linux 的主题图标名）、`timeout_ms?`（Linux 时长，Win32 自 Vista 起由系统定）、`replaces_id?`（非 0 覆盖同 id 那张）、`progress?`（0..100，Linux 画进度条、Win32 拼进正文）、`kind?`（0 信息 / 1 警告 / 2 错误）、`urgent?`（缺省 `true`，见下）。

```moonbit
@ui.button("发通知", on_click=fn() {
  if @shell.notify_supported() {
    match @shell.notify_send("我的应用", "构建完成", "3 个目标已产出") {
      Ok(_id) => toast("已发送", @ui.Info)
      Err(e) => println("通知失败：\{e}")
    }
  } else {
    println("当前环境不支持通知")
  }
})
```

`urgent?` 是**打扰档**，只有 macOS 吃：`true` 走时间敏感档，应用在前台忙时也直接出横幅；`false` 退普通档，前台忙时静默、只进通知中心。用户在系统设置里关掉「时间敏感」授权后，即便传 `true` 同样回到静默。Linux / Windows 收下忽略——Linux 的 freedesktop urgency hint 不做映射（`critical` 是常驻不消失的语义，与这一档不是一回事）。

注意：在事件回调里发。macOS 桌面横幅要求 `.app` bundle 形态运行，首次使用请求系统授权；见[体验文档](../guide/experience.md)。
