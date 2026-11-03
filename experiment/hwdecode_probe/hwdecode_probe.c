// H0 硬解探针（方案见 proposals/media-hwdecode.md §六）：三平台各建一次
// hw_device_ctx，并读一遍该设备能给的下行像素格式。
//
//   cc -O2 hwdecode_probe.c $(pkg-config --cflags --libs libavcodec libavutil) -o /tmp/hwprobe
//   ./hwprobe
//
// 输出一行一台设备：`HWPROBE platform=<win|mac|linux> type=<vaapi|d3d11va|videotoolbox> open=<ok|fail:原因> frames=<ok|fail:原因> transfer=<fmt,ftm,...|none>`
// 判据（§七）：设备建得起来且 transfer 列表非空 = 这条腿可用；驱动缺/无设备
// 也必须如实打印 fail 原因，不假装成功。

#include <stdio.h>
#include <string.h>
#include <libavutil/hwcontext.h>
#include <libavutil/pixdesc.h>
#include <libavutil/mem.h>

static const char *plat_name(void) {
#if defined(_WIN32)
  return "win";
#elif defined(__APPLE__)
  return "mac";
#else
  return "linux";
#endif
}

static const char *type_name(enum AVHWDeviceType t) {
  const char *n = av_hwdevice_get_type_name(t);
  return n ? n : "?";
}

// 读「硬件帧能转成哪些软件像素格式」（下行 transfer 的能力面）。
static void print_transfer(AVBufferRef *frames) {
  enum AVPixelFormat *fmts = NULL;
  int n = av_hwframe_transfer_get_formats(frames, AV_HWFRAME_TRANSFER_DIRECTION_FROM,
                                          &fmts, 0);
  if (n <= 0) {
    printf(" transfer=none");
    return;
  }
  printf(" transfer=");
  for (int i = 0; i < n; i++) {
    const char *nm = av_get_pix_fmt_name(fmts[i]);
    printf("%s%s", i ? "," : "", nm ? nm : "?");
  }
  av_free(fmts);
}

int main(void) {
  printf("# ffmpeg hw device probe (platform=%s)\n", plat_name());
  enum AVHWDeviceType t = AV_HWDEVICE_TYPE_NONE;
  int any_ok = 0;
  while ((t = av_hwdevice_iterate_types(t)) != AV_HWDEVICE_TYPE_NONE) {
    printf("HWPROBE platform=%s type=%s", plat_name(), type_name(t));
    AVBufferRef *dev = NULL;
    int rc = av_hwdevice_ctx_create(&dev, t, NULL, NULL, 0);
    if (rc < 0) {
      char err[256];
      av_strerror(rc, err, sizeof err);
      printf(" open=fail:%s\n", err);
      continue;
    }
    printf(" open=ok");
    // 建一次 frames 上下文：设备的真实可用性在这一步也会暴露
    AVBufferRef *frames = av_hwframe_ctx_alloc(dev);
    if (!frames) {
      printf(" frames=fail:alloc frames=none\n");
      av_buffer_unref(&dev);
      continue;
    }
    AVHWFramesContext *fc = (AVHWFramesContext *)frames->data;
    // 硬件像素格式不能瞎填：问设备要它的合法 hw 格式（VAAPI=vaapi、D3D11=d3d11 …）
    const AVHWFramesConstraints *cons = av_hwdevice_get_hwframe_constraints(dev, NULL);
    if (cons && cons->valid_hw_formats && cons->valid_hw_formats[0] != AV_PIX_FMT_NONE) {
      fc->format = cons->valid_hw_formats[0];
    } else {
      fc->format = AV_PIX_FMT_NONE;
    }
    fc->sw_format = AV_PIX_FMT_YUV420P;
    fc->width = 128;
    fc->height = 128;
    int frc = av_hwframe_ctx_init(frames);
    if (frc < 0) {
      char err[256];
      av_strerror(frc, err, sizeof err);
      printf(" frames=fail:%s\n", err);
      av_buffer_unref(&frames);
      av_buffer_unref(&dev);
      continue;
    }
    const char *hw = av_get_pix_fmt_name(fc->format);
    printf(" frames=ok pix=%s", hw ? hw : "?");
    print_transfer(frames);
    printf("\n");
    any_ok = 1;
    av_buffer_unref(&frames);
    av_buffer_unref(&dev);
  }
  printf("# result=%s\n", any_ok ? "usable" : "none-usable");
  return any_ok ? 0 : 1;
}
