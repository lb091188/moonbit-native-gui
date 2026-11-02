// gui-sys 的平台转发实现档：sys_stub.c 是纯 native-stub（拿不到 GTK 头、
// ObjC 那趟由模块自己的 prebuild 专编），剪贴板（Linux GTK / macOS
// NSPasteboard）、mac 窗口枚举/激活/关闭、mac 权限探测与屏幕色温这几段
// 平台实现住这里，prebuild 按平台宏编成静态库经 link_configs 下发。
//
//   WMSYS_EXT_GTK → Linux 真实现（pkg-config gtk+-3.0 头，prebuild 带宏编）
//   WMSYS_EXT_MAC → macOS 真实现（-x objective-c -fobjc-arc，prebuild 专编）
//   其余          → 空翻译单元（Windows 的剪贴板/对话框/权限占位全在
//                    sys_stub.c 自己的分支里，本档不参与，防双定义）
//
// 分支顺序有讲究：macOS 上 native-stub 也会编译本文件（不带宏），必须让它
// 编出空翻译单元——否则与 prebuild 的 .a 双定义（与主仓 win 桩同一铁律）。
//
// 符号沿用 wm_ 前缀：dialog.mbt / clipboard.mbt 的 extern 名不改，本档实现
// 自主仓 gui/win 桩迁出（sys 拆独立模块后与 gui-window 平行、零依赖，符号
// 随消费方走）。

// MoonBit 运行时：造一个 Bytes 对象。必须显式声明——本文件由 prebuild 直接
// 编，拿不到 moon 的 moonbit.h 包含路径；不声明就是隐式声明，cc 按「返回
// int」假定，x86-64 下指针被截成 32 位（实测 SIGSEGV，见主仓 win 桩同款注释）。
extern void *moonbit_make_bytes(int size, int value);

#if defined(WMSYS_EXT_GTK)
#include <gtk/gtk.h>

/* ---------- 剪贴板（clipboard.mbt 的 Linux 落点）----------
 * GtkClipboard 直接用。没跑过 gtk_init 的纯命令行消费者（无头测试）探测给
 * 0，MoonBit 侧退回命令线 xclip——不在这里替宿主 gdk_init。 */
int wm_clipboard_available(void) {
  return gdk_display_get_default() != NULL ? 1 : 0;
}

// 读剪贴板文本（UTF-8）：没有显示服务或没有文本时 *ok=0、给空 Bytes。
void *wm_clipboard_get_text(int32_t *ok) {
  *ok = 0;
  if (!wm_clipboard_available()) {
    return moonbit_make_bytes(0, 0);
  }
  GtkClipboard *cb = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
  gchar *t = gtk_clipboard_wait_for_text(cb);
  if (t == NULL) {
    // 首问常输给选区属主握手（Cinnamon 的剪贴板管理器接管后尤甚）：
    // 把已就绪的事件跑一轮再问一次，第二次必中的真机症状由此收掉。
    while (g_main_context_pending(NULL)) {
      g_main_context_iteration(NULL, FALSE);
    }
    t = gtk_clipboard_wait_for_text(cb);
  }
  if (t == NULL) {
    return moonbit_make_bytes(0, 0);
  }
  size_t len = strlen(t);
  void *out = moonbit_make_bytes((int)len, 0);
  if (len > 0) {
    memcpy(out, t, len);
  }
  g_free(t);
  *ok = 1;
  return out;
}

// 写剪贴板。set_text 只登记本进程为选区主人，所以紧跟一次 store 把内容
// 交给会话里的剪贴板管理器——少了它，应用退出后别处就再也读不到。
int wm_clipboard_set_text(const char *text) {
  if (text == NULL || !wm_clipboard_available()) {
    return 0;
  }
  GtkClipboard *cb = gtk_clipboard_get(GDK_SELECTION_CLIPBOARD);
  gtk_clipboard_set_text(cb, text, -1);
  gtk_clipboard_store(cb);
  return 1;
}

#elif defined(WMSYS_EXT_MAC)
#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Carbon/Carbon.h>
#import <ApplicationServices/ApplicationServices.h>

// UTF-8 字节 → moonbit 的 Bytes 对象（返回给 MoonBit 的文本都走这条）。
static void *sys_ext_bytes(const char *s) {
  size_t len = s != NULL ? strlen(s) : 0;
  void *out = moonbit_make_bytes((int)len, 0);
  if (len > 0 && out != NULL) {
    memcpy(out, s, len);
  }
  return out;
}

static NSString *sys_ext_str(const char *s) {
  if (s == NULL) {
    return nil;
  }
  return [[NSString alloc] initWithBytes:s
                                  length:strlen(s)
                                encoding:NSUTF8StringEncoding];
}

// ---- 剪贴板（clipboard.mbt 的 mac 落点）：NSPasteboard 真实现 ----


int wm_clipboard_available(void) {
  @autoreleasepool {
    return [NSPasteboard generalPasteboard] != nil ? 1 : 0;
  }
}

void *wm_clipboard_get_text(int32_t *ok) {
  @autoreleasepool {
    if (ok != NULL) {
      *ok = 0;
    }
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    if (pb == nil) {
      return sys_ext_bytes(NULL);
    }
    NSString *t = [pb stringForType:NSPasteboardTypeString];
    if (t == nil) {
      return sys_ext_bytes(NULL);
    }
    if (ok != NULL) {
      *ok = 1;
    }
    return sys_ext_bytes([t UTF8String]);
  }
}

int wm_clipboard_set_text(const char *text) {
  @autoreleasepool {
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    if (pb == nil || text == NULL) {
      return 0;
    }
    NSString *t = sys_ext_str(text);
    if (t == nil) {
      return 0;
    }
    [pb clearContents];
    return [pb setString:t forType:NSPasteboardTypeString] ? 1 : 0;
  }
}

// ---- 权限探测/请求（mac）：辅助功能与屏幕录制两档 ----
// 探测走公开口（AXIsProcessTrusted / CGPreflightScreenCaptureAccess），请求
// 走系统自带引导框——引导归系统，不替用户点任何东西。状态语义只有「当前
// 已授/未授」两态：TCC 的未请求与拒绝在公开 API 层不可区分。

int wm_permission_probe(int kind, int32_t *ok) {
  @autoreleasepool {
    if (ok != NULL) {
      *ok = 1;
    }
    if (kind == 0) {
      return AXIsProcessTrusted() ? 1 : 0;
    }
    if (kind == 1) {
      if (@available(macOS 10.15, *)) {
        return CGPreflightScreenCaptureAccess() ? 1 : 0;
      }
      return 1; // 10.15 前没有屏幕录制权限概念
    }
    if (ok != NULL) {
      *ok = 0; // 未知 kind
    }
    return -1;
  }
}

void wm_permission_request(int kind) {
  @autoreleasepool {
    if (kind == 0) {
      NSDictionary *opts = @{
        (__bridge NSString *)kAXTrustedCheckOptionPrompt : @YES
      };
      AXIsProcessTrustedWithOptions(
          (__bridge CFDictionaryRef)opts); // 弹系统引导对话框
    } else if (kind == 1) {
      if (@available(macOS 10.15, *)) {
        CGRequestScreenCaptureAccess(); // 弹系统引导对话框
      }
    }
  }
}

// ---- 窗口管理（windowctl 的 mac 后端）----
// 列表走 CGWindowList（免权限；标题要屏幕录制权限，未授权时按行跳过）。
// 激活按归属应用（NSRunningApplication.activate，免授权）。关闭走 AX（辅助
// 功能权限，缺失时 ok=2 让门面报语义化权限错误）。
// ok 出参约定：1 = 成功；0 = 找不到/失败；2 = 权限缺失（辅助功能）。

static pid_t sys_ext_win_pid_for(const char *id_or_title) {
  if (id_or_title == NULL || id_or_title[0] == '\0') {
    return 0;
  }
  CFArrayRef wins = CGWindowListCopyWindowInfo(
      kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
      kCGNullWindowID);
  if (wins == NULL) {
    return 0;
  }
  pid_t found = 0;
  int by_id = id_or_title[0] == '0' &&
              (id_or_title[1] == 'x' || id_or_title[1] == 'X');
  unsigned long long wid = by_id ? strtoull(id_or_title + 2, NULL, 16) : 0;
  for (NSDictionary *w in (__bridge NSArray *)wins) {
    NSNumber *num = w[(__bridge NSString *)kCGWindowNumber];
    if (num == nil) {
      continue;
    }
    if (by_id) {
      if (num.unsignedLongLongValue == wid) {
        NSNumber *pid = w[(__bridge NSString *)kCGWindowOwnerPID];
        found = pid != nil ? pid.intValue : 0;
        break;
      }
    } else {
      NSString *name = w[(__bridge NSString *)kCGWindowName];
      if (name == nil || [name length] == 0) {
        continue;
      }
      NSString *needle = [NSString stringWithUTF8String:id_or_title];
      NSRange r = [name rangeOfString:needle
                              options:NSCaseInsensitiveSearch];
      if (r.location != NSNotFound) {
        NSNumber *pid = w[(__bridge NSString *)kCGWindowOwnerPID];
        found = pid != nil ? pid.intValue : 0;
        break;
      }
    }
  }
  CFRelease(wins);
  return found;
}

void *wm_win_list_mac(int32_t *ok) {
  @autoreleasepool {
    *ok = 0;
    CFArrayRef wins = CGWindowListCopyWindowInfo(
        kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements,
        kCGNullWindowID);
    if (wins == NULL) {
      return moonbit_make_bytes(0, 0);
    }
    NSMutableString *blob = [NSMutableString new];
    for (NSDictionary *w in (__bridge NSArray *)wins) {
      NSNumber *num = w[(__bridge NSString *)kCGWindowNumber];
      NSString *name = w[(__bridge NSString *)kCGWindowName];
      if (num == nil || name == nil || [name length] == 0) {
        continue;
      }
      [blob appendFormat:@"0x%llx\t-1\t%@\n",
                         num.unsignedLongLongValue, name];
    }
    CFRelease(wins);
    const char *utf8 = [blob UTF8String];
    int len = (int)strlen(utf8);
    void *out = moonbit_make_bytes(len, 0);
    if (out != NULL) {
      memcpy(out, utf8, (size_t)len);
      *ok = 1;
    }
    return out;
  }
}

int32_t wm_win_activate_mac(const char *id_or_title, int32_t *ok) {
  @autoreleasepool {
    *ok = 0;
    pid_t pid = sys_ext_win_pid_for(id_or_title);
    if (pid == 0) {
      return 0;
    }
    NSRunningApplication *app =
        [NSRunningApplication runningApplicationWithProcessIdentifier:pid];
    if (app == nil) {
      return 0;
    }
    if ([app activateWithOptions:NSApplicationActivateAllWindows]) {
      *ok = 1;
    }
    return 0;
  }
}

int32_t wm_win_close_mac(const char *title, int32_t *ok) {
  @autoreleasepool {
    *ok = 0;
    // 关闭要按到别的应用的关闭按钮：辅助功能权限缺失时给语义化权限错误
    NSDictionary *trustOpts = @{
      (__bridge NSString *)kAXTrustedCheckOptionPrompt : @NO
    };
    if (!AXIsProcessTrustedWithOptions(
            (__bridge CFDictionaryRef)trustOpts)) {
      *ok = 2;
      return 0;
    }
    pid_t pid = sys_ext_win_pid_for(title);
    if (pid == 0) {
      return 0;
    }
    AXUIElementRef app = AXUIElementCreateApplication(pid);
    if (app == nil) {
      return 0;
    }
    CFArrayRef windows = NULL;
    AXUIElementCopyAttributeValue(app, kAXWindowsAttribute,
                                  (CFTypeRef *)&windows);
    int32_t done = 0;
    if (windows != NULL) {
      NSString *needle = [NSString stringWithUTF8String:title];
      for (id w in (__bridge NSArray *)windows) {
        AXUIElementRef win = (__bridge AXUIElementRef)w;
        CFTypeRef t = NULL;
        if (AXUIElementCopyAttributeValue(win, kAXTitleAttribute,
                                          &t) == kAXErrorSuccess &&
            t != NULL) {
          NSString *axTitle =
              CFBridgingRelease(t); // t 为 CFStringRef
          NSRange r = [axTitle rangeOfString:needle
                                     options:NSCaseInsensitiveSearch];
          if (r.location != NSNotFound) {
            CFTypeRef closeBtn = NULL;
            if (AXUIElementCopyAttributeValue(win, kAXCloseButtonAttribute,
                                              &closeBtn) ==
                    kAXErrorSuccess &&
                closeBtn != NULL) {
              AXError pr = AXUIElementPerformAction(
                  (AXUIElementRef)closeBtn, kAXPressAction);
              if (pr == kAXErrorSuccess) {
                done = 1;
              }
              CFRelease(closeBtn);
            }
          }
        }
        if (done) {
          break;
        }
      }
      CFRelease(windows);
    }
    CFRelease(app);
    if (done) {
      *ok = 1;
    }
    return 0;
  }
}

// ---- 夜间色温（mac）：全屏点击穿透暖色覆盖层 ----
// Night Shift 无公开控制口——覆盖层是 f.lux 同款替代机制：每屏一扇置顶窗，
// 跨空间常驻、点击穿透，暖色 alpha 按 percent 换算（0 = 最暖、100 = 中性
// 不盖）。level 取 CGShieldingWindowLevel：色温要盖一切（菜单/dock/全屏）。

static NSMutableArray *sys_ext_tint_windows = nil;

void wm_screen_tint_apply(int32_t percent, int32_t *ok) {
  @autoreleasepool {
    *ok = 0;
    if (sys_ext_tint_windows == nil) {
      sys_ext_tint_windows = [NSMutableArray new];
    }
    for (NSWindow *w in sys_ext_tint_windows) {
      [w orderOut:nil];
    }
    [sys_ext_tint_windows removeAllObjects];
    int32_t warmth =
        100 - (percent < 0 ? 0 : percent > 100 ? 100 : percent);
    if (warmth <= 0) {
      *ok = 1; // 中性：不盖
      return;
    }
    double alpha = warmth / 100.0 * 0.22;
    for (NSScreen *screen in [NSScreen screens]) {
      NSWindow *w = [[NSWindow alloc]
          initWithContentRect:[screen frame]
                    styleMask:NSWindowStyleMaskBorderless
                      backing:NSBackingStoreBuffered
                        defer:NO];
      [w setLevel:CGShieldingWindowLevel()];
      [w setOpaque:NO];
      [w setHasShadow:NO];
      [w setBackgroundColor:
              [NSColor colorWithCalibratedRed:1.0
                                        green:0.55
                                         blue:0.0
                                        alpha:alpha]];
      [w setIgnoresMouseEvents:YES];
      [w setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces |
                               NSWindowCollectionBehaviorStationary |
                               NSWindowCollectionBehaviorFullScreenAuxiliary];
      [w orderFrontRegardless];
      [sys_ext_tint_windows addObject:w];
    }
    *ok = 1;
  }
}

#endif
