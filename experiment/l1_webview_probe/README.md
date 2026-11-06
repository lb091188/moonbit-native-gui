# L1 × webview 共存探针

窗口自绘走 L1（GPU present）时，原生子件（WebKitGTK 的 webview）是否还能出像素。
2026-11-06 的修复（挂原生子件的窗回 cairo）由此探针取证，判据是**窗口外的像素读数**。

## 跑法

```sh
moon run experiment/l1_webview_probe        # 保持窗口不退出
```

另开一个终端取窗口中心像素（X11）：

```sh
W=$(xdotool search --name "L1WV-PROBE" | head -1)
X=$(xwininfo -id $W | awk '/Absolute upper-left X/{print $4}')
Y=$(xwininfo -id $W | awk '/Absolute upper-left Y/{print $4}')
# XGetImage 取根窗 ($X+260, $Y+180) 的像素值
```

## 判据

- 页面底色是 `#ff00ff`（洋红），窗口中心取到 `#ff00ff` = **网页出像素**。
- 取到应用主题底色（本机 `#f5f6f7`）= 网页被 L1 承载子窗口盖住。
