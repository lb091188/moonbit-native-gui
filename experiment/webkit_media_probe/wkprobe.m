// WKWebView 媒体采集探针（macOS，2026-10-29 实测）：证明「未签名/未打包
// 形态下页面 getUserMedia 根本发不出授权请求」，与 webview 桩的实现无关。
//
// 跑法：clang -fobjc-arc -framework Cocoa -framework WebKit -o wkprobe wkprobe.m && ./wkprobe
//
// 实测结果（macOS 26 / Xcode 26.6 SDK）：
// - enumerateDevices() 回空列表（devs=）；
// - getUserMedia({audio:true}) 的 Promise 既不 resolve 也不 reject（挂起）；
// - UIDelegate 的 requestMediaCapturePermissionForOrigin 一次都不触发；
// - 同一 delegate 的 runJavaScriptAlertPanelWithMessage 正常触发（接线有效）；
// - 直接跑裸二进制 / 放进带 NSMicrophoneUsageDescription 的 .app /
//   经 LaunchServices `open` 启动 / 加 WebKit 私有偏好
//   （_setMediaDevicesEnabled: 等，respondsToSelector 均存在）——四种形态结果相同。
// 结论：WebKit 在拿不到采集设备（TCC/签名身份缺位）时不会发起页面级授权请求，
// 「扣住 decisionHandler + 上层弹框」的路径只在正确打包签名的 .app 里可验。
#import <Cocoa/Cocoa.h>
#import <WebKit/WebKit.h>
#import <objc/message.h>

static int g_media = 0;

@interface Probe : NSObject <WKNavigationDelegate, WKUIDelegate>
@property(nonatomic, strong) WKWebView *wv;
@end

@implementation Probe
- (void)webView:(WKWebView *)webView
    requestMediaCapturePermissionForOrigin:(WKSecurityOrigin *)origin
                          initiatedByFrame:(WKFrameInfo *)frame
                                      type:(WKMediaCaptureType)type
                           decisionHandler:
                               (void (^)(WKPermissionDecision))decisionHandler {
  (void)webView; (void)origin; (void)frame;
  g_media = (int)type + 1;
  printf("PROBE: media-delegate called type=%d\n", (int)type);
  fflush(stdout);
  decisionHandler(WKPermissionDecisionDeny);
}

- (void)webView:(WKWebView *)webView
    runJavaScriptAlertPanelWithMessage:(NSString *)message
                      initiatedByFrame:(WKFrameInfo *)frame
                     completionHandler:(void (^)(void))completionHandler {
  (void)webView; (void)frame;
  printf("PROBE: alert-delegate called msg=%s\n", [message UTF8String]);
  fflush(stdout);
  completionHandler();
}

- (void)webView:(WKWebView *)webView didFinishNavigation:(WKNavigation *)navigation {
  (void)navigation;
  printf("PROBE: nav finished\n");
  fflush(stdout);
  // alert 先走一遍证明 UIDelegate 接线有效；随后枚举设备 + 发起 getUserMedia，
  // 结果写进 document.title 轮询读回（Promise 挂起时 title 不变即为挂起证据）
  NSString *js =
      @"(function(){alert('probe-alert');"
       "if(!(navigator.mediaDevices&&navigator.mediaDevices.getUserMedia))"
       "{document.title='NO-MEDIADEVICES';return 1;}"
       "navigator.mediaDevices.enumerateDevices().then(function(l){"
       "document.title='devs='+l.map(function(d){return d.kind}).join(',');"
       "}).catch(function(e){document.title='ENUM-ERR '+e.name;});"
       "navigator.mediaDevices.getUserMedia({audio:true}).then(function(s){"
       "document.title='GETUSERMEDIA-OK';s.getTracks().forEach(function(t){t.stop()});"
       "}).catch(function(e){document.title='GETUSERMEDIA-ERR '+e.name;});"
       "return 1;})()";
  [webView evaluateJavaScript:js completionHandler:^(id r, NSError *e) {
    (void)r; (void)e;
  }];
}
@end

int main(void) {
  @autoreleasepool {
    [NSApplication sharedApplication];
    NSWindow *win = [[NSWindow alloc]
        initWithContentRect:NSMakeRect(0, 0, 480, 320)
                  styleMask:NSWindowStyleMaskBorderless
                    backing:NSBackingStoreBuffered
                      defer:NO];
    Probe *p = [[Probe alloc] init];
    WKWebViewConfiguration *cfg = [[WKWebViewConfiguration alloc] init];
    if (getenv("PROBE_SPI") != NULL) {
      // 附加变量：私有偏好全开是否解除挂起（实测不解除，留作复现）
      id prefs = cfg.preferences;
      const char *spis[] = {"_setMediaDevicesEnabled:", "_setMediaStreamEnabled:",
                            "_setAVFoundationEnabled:", "_setMediaSourceEnabled:"};
      for (int i = 0; i < 4; i++) {
        SEL s = NSSelectorFromString([NSString stringWithUTF8String:spis[i]]);
        if ([prefs respondsToSelector:s]) {
          ((void (*)(id, SEL, BOOL))objc_msgSend)(prefs, s, YES);
          printf("PROBE: spi %s = YES\n", spis[i]);
        } else {
          printf("PROBE: spi %s absent\n", spis[i]);
        }
      }
      fflush(stdout);
    }
    WKWebView *wv = [[WKWebView alloc]
        initWithFrame:NSMakeRect(0, 0, 480, 320)
        configuration:cfg];
    wv.navigationDelegate = p;
    wv.UIDelegate = p;
    [win.contentView addSubview:wv];
    p.wv = wv;
    [win makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [wv loadRequest:[NSURLRequest
                        requestWithURL:[NSURL URLWithString:@"https://example.com"]]];
    NSDate *end = [NSDate dateWithTimeIntervalSinceNow:8.0];
    NSString *last = @"";
    int ticks = 0;
    while ([end timeIntervalSinceNow] > 0.0) {
      [[NSRunLoop currentRunLoop]
          runMode:NSDefaultRunLoopMode
          beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.2]];
      ticks++;
      if (ticks % 5 == 0) {
        [wv evaluateJavaScript:@"document.title"
             completionHandler:^(id t, NSError *e) {
               NSString *s = t != nil ? [t description] : @"?";
               if (![s isEqualToString:last]) {
                 last = s;
                 printf("PROBE: title=%s%s\n", [s UTF8String],
                        e != nil ? " (err)" : "");
                 fflush(stdout);
               }
             }];
      }
    }
    printf("PROBE: done mediaCalled=%d\n", g_media);
    fflush(stdout);
  }
  return 0;
}
