# webkit_media_probe

macOS 上 WKWebView 媒体采集的取证探针（只有一个 ObjC 文件，不是 moon 模块，
不进 `moon.work`）。

```sh
cd experiment/webkit_media_probe
clang -fobjc-arc -framework Cocoa -framework WebKit -o wkprobe wkprobe.m
./wkprobe            # 常规探测
PROBE_SPI=1 ./wkprobe  # 附加：WebKit 私有偏好全开是否解除挂起
```

结论与判据见文件头注释，对应 `proposals/adaptation.md` 的 webview 一节。
