// ffmpeg 动态链 FFI 的薄 stub：只做句柄/字符串转换，无业务逻辑。
// 依赖 libavformat/libavcodec/libswscale/libswresample/libavutil（动态链）。
//
// 平台口径（由本模块 prebuild 钩子 下发参数）：
// - Linux：pkg-config 探测系统 dev 包，头与链接参数随构建注入；
// - Windows：dev 内容 vendor 进仓库（vendor/include + vendor/*.lib，
//   BtbN win64-lgpl-shared 构建），头文件路径经 moon.pkg 的
//   stub-cc-flags `-I${build.FFMPEG_INC}` 注入，导入库走 link_flags；
//   运行期 dll 不进仓库，与 exe 同目录或放 PATH。
// 三个平台的实现同源（ffmpeg 的 API 本身跨平台），本文件不再有
// 平台条件编译。

#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "moonbit.h"


#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libswscale/swscale.h>
#include <libswresample/swresample.h>
#include <libavutil/imgutils.h>
#include <libavutil/log.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include "moonbit.h"

typedef struct VfFmt {
    AVFormatContext *fmt;
    int vstream; // 视频流索引，-1 无
    int astream; // 音频流索引，-1 无
    int sstream; // 字幕流索引，-1 无
} VfFmt;

typedef struct VfDec {
    AVFormatContext *fmt;
    AVCodecContext *codec;
    AVFrame *frame;
    AVPacket *pkt;
    struct SwsContext *sws;
    int vstream;
    int width;
    int height;
    double last_pts; // 最近一次 vf_decode_next 成功帧的 pts（秒）；-1=未知
    // —— 硬解（定案见 proposals/media-hwdecode.md §八）——
    AVBufferRef *hwdev; // hw_device_ctx；软解为 NULL
    AVFrame *swf;       // 硬件帧的下行宿主（transfer_data 落这里再 sws）
    int hw_status;      // 0=软解 1=硬解 2=已回落
    enum AVCodecID codec_id;
    char hw_reason[160]; // 回落原因（状态行原样打印）
    // —— 帧输出策略位（H2，方案 §五）——
    int transfer; // 0=SwScale（唯一已落地档）1=DirectTexture（GPU 线落地才收）
} VfDec;

/* 音频解码器：swr 统一重采样输出 s16 交错 */
typedef struct VfADec {
    AVFormatContext *fmt;
    AVCodecContext *codec;
    AVFrame *frame;
    AVPacket *pkt;
    struct SwrContext *swr;
    int astream;
    int out_ch;
    int out_rate;
} VfADec;

/* 字幕解码器：整条读成「起始秒 + 文本」，文本按 rect 原样拼接 */
typedef struct VfSDec {
    AVFormatContext *fmt;
    AVCodecContext *codec;
    AVSubtitle sub;
    AVPacket *pkt;
    int sstream;
    double last_pts; // 最近一条的起始秒；-1=未知
    double last_end; // 最近一条的结束秒（起始 + end_display_time）
} VfSDec;

/* 版本（构建期链接确认 + 运行时探测） */
int32_t vf_version(void) {
    return (int32_t)avformat_version();
}

/* 解码器日志压到 ERROR 档：aac 等解码器逐帧吐 warning（如
 * "Could not update timestamps for discarded samples"），会刷满
 * 宿主终端；ERROR 以下与 GUI 无关，真错误仍保留。 */
static void vf_quiet_logs(void) {
    av_log_set_level(AV_LOG_ERROR);
}

/* 打开容器并定位媒体流。失败不返回 NULL：返回哑句柄（fmt=NULL），
 * 由 vf_ok 探测——FFI 侧避免 NULL/Option 语义不确定。 */
VfFmt *vf_open(const char *path) {
    vf_quiet_logs();
    VfFmt *f = (VfFmt *)malloc(sizeof(VfFmt));
    f->vstream = -1;
    f->astream = -1;
    f->sstream = -1;
    f->fmt = NULL;
    if (avformat_open_input(&f->fmt, path, NULL, NULL) == 0) {
        if (avformat_find_stream_info(f->fmt, NULL) >= 0) {
            f->vstream = av_find_best_stream(f->fmt, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);
            f->astream = av_find_best_stream(f->fmt, AVMEDIA_TYPE_AUDIO, -1, -1, NULL, 0);
            f->sstream = av_find_best_stream(f->fmt, AVMEDIA_TYPE_SUBTITLE, -1, -1, NULL, 0);
        }
    }
    return f;
}

/* 打开是否成功（fmt 有效） */
int32_t vf_ok(VfFmt *f) {
    return f && f->fmt ? 1 : 0;
}

void vf_close(VfFmt *f) {
    if (f) {
        avformat_close_input(&f->fmt);
        free(f);
    }
}

int32_t vf_video_stream(VfFmt *f) {
    return f ? f->vstream : -1;
}

/* 音频流索引（-1 无） */
int32_t vf_audio_stream(VfFmt *f) {
    return f ? f->astream : -1;
}

/* 字幕流索引（-1 无） */
int32_t vf_subtitle_stream(VfFmt *f) {
    return f ? f->sstream : -1;
}

/* 未开解码器的哑句柄（NULL）：惰性开解码器时作 Demuxer 字段占位 */
VfDec *vf_no_decoder(void) {
    return NULL;
}

VfADec *vf_no_audio_decoder(void) {
    return NULL;
}

/* 视频流原生尺寸 */
int32_t vf_stream_width(VfFmt *f) {
    if (f && f->vstream >= 0) {
        return f->fmt->streams[f->vstream]->codecpar->width;
    }
    return 0;
}

int32_t vf_stream_height(VfFmt *f) {
    if (f && f->vstream >= 0) {
        return f->fmt->streams[f->vstream]->codecpar->height;
    }
    return 0;
}

/* 时长（秒，AV_TIME_BASE 分之 duration）；未知给 0 */
double vf_duration_s(VfFmt *f) {
    if (f && f->fmt->duration != AV_NOPTS_VALUE) {
        return (double)f->fmt->duration / (double)AV_TIME_BASE;
    }
    return 0.0;
}

/* —— 硬解：设备类型与「本进程内 codec+分辨率 一次失败即永久回落」表 —— */
static enum AVHWDeviceType vf_hw_type(void) {
#if defined(__APPLE__)
    return AV_HWDEVICE_TYPE_VIDEOTOOLBOX;
#elif defined(_WIN32)
    return AV_HWDEVICE_TYPE_D3D11VA;
#else
    return AV_HWDEVICE_TYPE_VAAPI;
#endif
}

#define VF_HW_FAIL_MAX 32
static struct {
    enum AVCodecID id;
    int w, h;
} g_hw_fail[VF_HW_FAIL_MAX];
static int g_hw_fail_n = 0;

static int hw_fail_find(enum AVCodecID id, int w, int h) {
    for (int i = 0; i < g_hw_fail_n; i++) {
        if (g_hw_fail[i].id == id && g_hw_fail[i].w == w && g_hw_fail[i].h == h) {
            return 1;
        }
    }
    return 0;
}

static void hw_fail_add(enum AVCodecID id, int w, int h) {
    if (g_hw_fail_n < VF_HW_FAIL_MAX && !hw_fail_find(id, w, h)) {
        g_hw_fail[g_hw_fail_n].id = id;
        g_hw_fail[g_hw_fail_n].w = w;
        g_hw_fail[g_hw_fail_n].h = h;
        g_hw_fail_n++;
    }
}

/* 换回软解：丢弃 hw 上下文与 sws，按源流参数重开一个纯软件解码器 */
static void vf_drop_to_soft(VfDec *d) {
    if (d->sws) {
        sws_freeContext(d->sws);
        d->sws = NULL;
    }
    if (d->codec) {
        avcodec_free_context(&d->codec);
    }
    if (d->hwdev) {
        av_buffer_unref(&d->hwdev);
    }
    if (d->swf) {
        av_frame_free(&d->swf);
    }
    AVStream *st = d->fmt->streams[d->vstream];
    const AVCodec *codec = avcodec_find_decoder(st->codecpar->codec_id);
    d->codec = avcodec_alloc_context3(codec);
    if (!d->codec) {
        return;
    }
    if (avcodec_parameters_to_context(d->codec, st->codecpar) < 0 ||
        avcodec_open2(d->codec, codec, NULL) < 0) {
        avcodec_free_context(&d->codec);
        d->codec = NULL;
    }
}

/* 打开视频解码器（含 RGBA 输出的 sws 上下文）；失败 NULL */
void vf_close_decoder(VfDec *d);

VfDec *vf_open_video_decoder_hw(VfFmt *f, int32_t out_w, int32_t out_h, int32_t hw);

/* 软解入口（旧行为原样）：hw=0 */
VfDec *vf_open_video_decoder(VfFmt *f, int32_t out_w, int32_t out_h) {
    return vf_open_video_decoder_hw(f, out_w, out_h, 0);
}

/* 硬解入口：hw=1 时先建 hw_device_ctx 再开解码器；建不出来就按软解继续并
 * 记一次回落（hw_status=2 + 原因 + 永久回落表），不改变上层调用形态。 */
VfDec *vf_open_video_decoder_hw(VfFmt *f, int32_t out_w, int32_t out_h, int32_t hw) {
    if (!f || f->vstream < 0) {
        return NULL;
    }
    AVStream *st = f->fmt->streams[f->vstream];
    const AVCodec *codec = avcodec_find_decoder(st->codecpar->codec_id);
    if (!codec) {
        return NULL;
    }
    VfDec *d = (VfDec *)malloc(sizeof(VfDec));
    d->fmt = f->fmt;
    d->vstream = f->vstream;
    d->codec = NULL;
    d->frame = NULL;
    d->pkt = NULL;
    d->sws = NULL;
    d->width = 0;
    d->height = 0;
    d->last_pts = -1.0;
    d->hwdev = NULL;
    d->swf = NULL;
    d->hw_status = 0;
    d->codec_id = st->codecpar->codec_id;
    d->hw_reason[0] = 0;
    d->transfer = 0; // SwScale：解码帧怎么变成 RGBA 当前只有这一档
    d->codec = avcodec_alloc_context3(codec);
    if (avcodec_parameters_to_context(d->codec, st->codecpar) < 0) {
        avcodec_free_context(&d->codec);
        d->codec = NULL;
        return d;
    }
    // 硬解：请求了、且这一组 codec+分辨率没被打进永久回落表，才建 hw_device_ctx
    if (hw) {
        if (hw_fail_find(d->codec_id, st->codecpar->width, st->codecpar->height)) {
            d->hw_status = 2;
            snprintf(d->hw_reason, sizeof d->hw_reason,
                     "本进程内该 codec+分辨率已回落（不重试）");
        } else {
            const char *dev = getenv("VF_HW_DEVICE"); // Linux 可指定 renderD128；其余平台忽略
            int hrc = av_hwdevice_ctx_create(&d->hwdev, vf_hw_type(), dev, NULL, 0);
            if (hrc < 0) {
                char err[96] = {0};
                av_strerror(hrc, err, sizeof err - 1);
                d->hw_status = 2;
                snprintf(d->hw_reason, sizeof d->hw_reason, "建 hw 设备失败：%s", err);
                hw_fail_add(d->codec_id, st->codecpar->width, st->codecpar->height);
                av_buffer_unref(&d->hwdev);
            } else {
                d->codec->hw_device_ctx = av_buffer_ref(d->hwdev);
                d->hw_status = 1;
            }
        }
    }
    if (avcodec_open2(d->codec, codec, NULL) < 0) {
        if (d->hwdev) {
            av_buffer_unref(&d->hwdev);
        }
        avcodec_free_context(&d->codec);
        d->codec = NULL;
        return d;
    }
    d->width = out_w > 0 ? out_w : d->codec->width;
    d->height = out_h > 0 ? out_h : d->codec->height;
    // 单边指定时另一边按源宽高比补齐(ffmpeg -1 语义):否则 480 宽+
    // 源高会把 16:9 视频解码成竖长拉伸帧,后续 letterbox 无从校正
    if (out_w > 0 && out_h <= 0 && d->codec->width > 0) {
        d->height = (int)((double)d->codec->height * out_w / d->codec->width + 0.5);
    } else if (out_h > 0 && out_w <= 0 && d->codec->height > 0) {
        d->width = (int)((double)d->codec->width * out_h / d->codec->height + 0.5);
    }
    if (d->width < 1) {
        d->width = 1;
    }
    if (d->height < 1) {
        d->height = 1;
    }
    d->frame = av_frame_alloc();
    d->pkt = av_packet_alloc();
    // sws 懒建：硬解帧的软件格式（NV12 居多）要 transfer 之后才知道；
    // 软解也统一走这条，避免 open 期猜 codec->pix_fmt
    if (!d->frame || !d->pkt) {
        vf_close_decoder(d);
        d = (VfDec *)malloc(sizeof(VfDec));
        d->fmt = f->fmt;
        d->vstream = f->vstream;
        d->codec = NULL;
        d->frame = NULL;
        d->pkt = NULL;
        d->sws = NULL;
        d->width = 0;
        d->height = 0;
        d->last_pts = -1.0;
        d->hwdev = NULL;
        d->swf = NULL;
        d->hw_status = 0;
        d->codec_id = st->codecpar->codec_id;
        d->hw_reason[0] = 0;
        return d;
    }
    return d;
}

void vf_close_decoder(VfDec *d) {
    if (d) {
        if (d->sws) {
            sws_freeContext(d->sws);
        }
        if (d->frame) {
            av_frame_free(&d->frame);
        }
        if (d->pkt) {
            av_packet_free(&d->pkt);
        }
        if (d->codec) {
            avcodec_free_context(&d->codec);
        }
        if (d->hwdev) {
            av_buffer_unref(&d->hwdev);
        }
        if (d->swf) {
            av_frame_free(&d->swf);
        }
        free(d);
    }
}

/* 硬解状态：0=软解 1=硬解 2=已回落（三档如实报，不许把回落报成硬解） */
int32_t vf_hw_status(VfDec *d) {
    return d ? d->hw_status : 0;
}

/* 回落原因写进 out（NUL 结尾，返回写入长度；没有原因给 0） */
int32_t vf_hw_reason(VfDec *d, uint8_t *out, int32_t cap) {
    if (!d || cap <= 1 || d->hw_reason[0] == 0) {
        return 0;
    }
    int n = (int)strlen(d->hw_reason);
    if (n > cap - 1) {
        n = cap - 1;
    }
    memcpy(out, d->hw_reason, (size_t)n);
    out[n] = 0;
    return n;
}

int32_t vf_dec_width(VfDec *d) {
    return d ? d->width : 0;
}

int32_t vf_dec_height(VfDec *d) {
    return d ? d->height : 0;
}

/* 帧输出策略位（H2，方案 §五）：解码帧怎么变成 RGBA 收敛到这一个函数。
 * 现在只有 SwScale 一档（srcf 可能是硬件帧经 transfer_data 下行的宿主）；
 * GPU 线落地时加 DirectTexture 一档——只动这里一行，解码端（hwdevice 建立、
 * 回落、计数）零改动。 */
#define VF_TRANSFER_SWSCALE 0
#define VF_TRANSFER_DIRECT_TEXTURE 1

static int vf_frame_output(VfDec *d, AVFrame *srcf, uint8_t *out) {
    if (d->transfer == VF_TRANSFER_DIRECT_TEXTURE) {
        return -1; // 直纹理档未落地（GPU 线的首消费者，见 gpu-architecture.md）
    }
    if (!d->sws) {
        d->sws = sws_getContext(
            srcf->width, srcf->height, srcf->format,
            d->width, d->height, AV_PIX_FMT_RGBA,
            SWS_BILINEAR, NULL, NULL, NULL);
        if (!d->sws) {
            return -1;
        }
    }
    uint8_t *dst[4] = { out, NULL, NULL, NULL };
    int dst_linesize[4] = { d->width * 4, 0, 0, 0 };
    sws_scale(d->sws, (const uint8_t *const *)srcf->data, srcf->linesize,
              0, srcf->height, dst, dst_linesize);
    return 0;
}

/* 帧输出策略位读数：0=SwScale（当前唯一档）。 */
int32_t vf_transfer_mode(VfDec *d) {
    return d ? d->transfer : -1;
}

/* 帧输出策略位设置（H2 接线，方案 §五）：MoonBit 侧已限 0/1；直纹理档
 * 未落地时输出端 vf_frame_output 如实报 -1（不出帧），解码端零改动。 */
void vf_set_transfer_mode(VfDec *d, int32_t mode) {
    if (d) {
        d->transfer = (int)mode;
    }
}

/* 解码下一帧为 RGBA 写进 out（容量须 >= w*h*4）。
 * 返回：1=拿到一帧；0=流结束；-1=错误 */
int32_t vf_decode_next(VfDec *d, uint8_t *out, int32_t out_len) {
    if (!d) {
        return -1;
    }
    while (1) {
        int ret = av_read_frame(d->fmt, d->pkt);
        if (ret == AVERROR_EOF) {
            return 0;
        }
        if (ret < 0) {
            return -1;
        }
        if (d->pkt->stream_index != d->vstream) {
            av_packet_unref(d->pkt);
            continue;
        }
        if (avcodec_send_packet(d->codec, d->pkt) < 0) {
            av_packet_unref(d->pkt);
            return -1;
        }
        av_packet_unref(d->pkt);
        ret = avcodec_receive_frame(d->codec, d->frame);
        if (ret == AVERROR(EAGAIN)) {
            continue;
        }
        if (ret == AVERROR_EOF) {
            return 0;
        }
        if (ret < 0) {
            return -1;
        }
        // 硬解帧先下行到软件帧：失败即永久回落（记表 + 换软解码器），本帧丢弃
        AVFrame *srcf = d->frame;
        if (d->hw_status == 1 && d->frame->format != AV_PIX_FMT_NONE) {
            const AVPixFmtDescriptor *fd = av_pix_fmt_desc_get(d->frame->format);
            if (!fd || !(fd->flags & AV_PIX_FMT_FLAG_HWACCEL)) {
                // 设备建起来了、实际出的却是软件帧（驱动/容器不真加速）——如实回落，
                // 绝不把这种情况报成硬解
                d->hw_status = 2;
                snprintf(d->hw_reason, sizeof d->hw_reason,
                         "解码器输出软件帧（硬件未生效）");
                hw_fail_add(d->codec_id, d->codec->width, d->codec->height);
            }
        }
        if (d->hw_status == 1 && d->codec->hw_device_ctx &&
            d->frame->format != AV_PIX_FMT_NONE) {
            const AVPixFmtDescriptor *fd = av_pix_fmt_desc_get(d->frame->format);
            if (fd && (fd->flags & AV_PIX_FMT_FLAG_HWACCEL)) {
                if (!d->swf) {
                    d->swf = av_frame_alloc();
                }
                if (!d->swf || av_hwframe_transfer_data(d->swf, d->frame, 0) < 0) {
                    d->hw_status = 2;
                    snprintf(d->hw_reason, sizeof d->hw_reason,
                             "硬件帧下行失败（transfer_data）");
                    hw_fail_add(d->codec_id, d->codec->width, d->codec->height);
                    av_frame_unref(d->frame);
                    vf_drop_to_soft(d);
                    return -1; // 本帧作废；下一帧起按软解走
                }
                srcf = d->swf;
            }
        }
        if (vf_frame_output(d, srcf, out) < 0) {
            av_frame_unref(d->frame);
            return -1;
        }
        // 帧时间戳（秒）：best_effort 优先（容错丢 pts 的包），流时间基换算
        int64_t ts = d->frame->best_effort_timestamp;
        if (ts == AV_NOPTS_VALUE) {
            ts = d->frame->pts;
        }
        AVStream *st = d->fmt->streams[d->vstream];
        d->last_pts = ts == AV_NOPTS_VALUE
                          ? -1.0
                          : (double)ts * av_q2d(st->time_base);
        av_frame_unref(d->frame);
        return 1;
    }
}

/* 最近一次 vf_decode_next 成功帧的 pts（秒）；未解/未知 -1 */
double vf_frame_pts_s(VfDec *d) {
    return d ? d->last_pts : -1.0;
}

/* 视频流帧率（avg_frame_rate 优先，r_frame_rate 回退；未知 0） */
double vf_stream_fps(VfFmt *f) {
    if (!f || f->vstream < 0) {
        return 0.0;
    }
    AVStream *st = f->fmt->streams[f->vstream];
    AVRational r = st->avg_frame_rate;
    if (r.num <= 0 || r.den <= 0) {
        r = st->r_frame_rate;
    }
    if (r.num <= 0 || r.den <= 0) {
        return 0.0;
    }
    return av_q2d(r);
}

/* 跳转到指定秒（视频流时间基）；0 成功 / -1 失败 */
int32_t vf_seek_s(VfDec *d, double t_s) {
    if (!d) {
        return -1;
    }
    AVStream *st = d->fmt->streams[d->vstream];
    int64_t ts = (int64_t)(t_s * (double)st->time_base.den / (double)st->time_base.num);
    if (avformat_seek_file(d->fmt, d->vstream, INT64_MIN, ts, ts, 0) < 0) {
        return -1;
    }
    avcodec_flush_buffers(d->codec);
    d->last_pts = -1.0; // 旧位置的 pts 不得误导下一帧的时间轴判断
    return 0;
}

/* -------------------------------------------------------------------------
 * 音频解码器（swr 统一输出 s16 交错，采样率/声道保持源）
 * ------------------------------------------------------------------------- */

void vf_close_audio_decoder(VfADec *d) {
    if (d) {
        if (d->swr) {
            swr_free(&d->swr);
        }
        if (d->frame) {
            av_frame_free(&d->frame);
        }
        if (d->pkt) {
            av_packet_free(&d->pkt);
        }
        if (d->codec) {
            avcodec_free_context(&d->codec);
        }
        free(d);
    }
}

/* 打开音频解码器；失败返回 NULL（MoonBit 侧以 vf_adec_channels<=0 探测） */
VfADec *vf_open_audio_decoder(VfFmt *f) {
    if (!f || f->astream < 0) {
        return NULL;
    }
    AVStream *st = f->fmt->streams[f->astream];
    const AVCodec *codec = avcodec_find_decoder(st->codecpar->codec_id);
    if (!codec) {
        return NULL;
    }
    VfADec *d = (VfADec *)calloc(1, sizeof(VfADec));
    d->fmt = f->fmt;
    d->astream = f->astream;
    d->codec = avcodec_alloc_context3(codec);
    if (!d->codec ||
        avcodec_parameters_to_context(d->codec, st->codecpar) < 0 ||
        avcodec_open2(d->codec, codec, NULL) < 0) {
        vf_close_audio_decoder(d);
        return NULL;
    }
    d->out_ch = d->codec->ch_layout.nb_channels;
    d->out_rate = d->codec->sample_rate;
    d->frame = av_frame_alloc();
    d->pkt = av_packet_alloc();
    if (swr_alloc_set_opts2(&d->swr,
                            &d->codec->ch_layout, AV_SAMPLE_FMT_S16, d->out_rate,
                            &d->codec->ch_layout, d->codec->sample_fmt, d->out_rate,
                            0, NULL) < 0 ||
        !d->frame || !d->pkt || !d->swr || swr_init(d->swr) < 0) {
        vf_close_audio_decoder(d);
        return NULL;
    }
    return d;
}

int32_t vf_adec_channels(VfADec *d) {
    return d ? d->out_ch : 0;
}

int32_t vf_adec_rate(VfADec *d) {
    return d ? d->out_rate : 0;
}

/* 把当前解码帧转 s16 交错写进 out；返回写入 PCM 帧数（0=转换失败） */
static int32_t vf_aconvert(VfADec *d, uint8_t *out, int32_t out_len) {
    int dst_frames = out_len / (d->out_ch * 2);
    if (dst_frames <= 0) {
        return 0;
    }
    int got = swr_convert(d->swr, &out, dst_frames,
                          (const uint8_t **)d->frame->extended_data,
                          d->frame->nb_samples);
    return got > 0 ? got : 0;
}

/* 解码下一段 PCM（s16 交错）写进 out。
 * 返回：>0 = 写入帧数；0 = 流结束；-1 = 错误 */
int32_t vf_decode_pcm(VfADec *d, uint8_t *out, int32_t out_len) {
    if (!d || !d->codec) {
        return -1;
    }
    while (1) {
        int ret = avcodec_receive_frame(d->codec, d->frame);
        if (ret == 0) {
            int32_t frames = vf_aconvert(d, out, out_len);
            av_frame_unref(d->frame);
            if (frames > 0) {
                return frames;
            }
            continue;
        }
        if (ret == AVERROR(EAGAIN)) {
            ret = av_read_frame(d->fmt, d->pkt);
            if (ret == AVERROR_EOF) {
                // 尾部：冲刷解码器取残留帧（send 返回值忽略，重复冲刷无害）
                avcodec_send_packet(d->codec, NULL);
                continue;
            }
            if (ret < 0) {
                return -1;
            }
            if (d->pkt->stream_index != d->astream) {
                av_packet_unref(d->pkt);
                continue;
            }
            if (avcodec_send_packet(d->codec, d->pkt) < 0) {
                av_packet_unref(d->pkt);
                return -1;
            }
            av_packet_unref(d->pkt);
            continue;
        }
        if (ret == AVERROR_EOF) {
            return 0; // 冲刷完毕
        }
        if (ret < 0) {
            return -1;
        }
    }
}

/* 跳转到指定秒（音频流时间基）；0 成功 / -1 失败。
 * swr 重初始化以丢弃旧位置的重采样缓存，避免 seek 后残音。 */
int32_t vf_aseek_s(VfADec *d, double t_s) {
    if (!d || !d->codec) {
        return -1;
    }
    AVStream *st = d->fmt->streams[d->astream];
    int64_t ts = (int64_t)(t_s * (double)st->time_base.den / (double)st->time_base.num);
    if (avformat_seek_file(d->fmt, d->astream, INT64_MIN, ts, ts, 0) < 0) {
        return -1;
    }
    avcodec_flush_buffers(d->codec);
    if (d->swr) {
        swr_init(d->swr);
    }
    return 0;
}

/* -------------------------------------------------------------------------
 * 字幕解码（把整条字幕流读成「起始秒 + 文本」列表）
 *
 * 三条口径：
 * ① **另开一份容器读**——与视频/音频解码器共用 AVFormatContext 会互相推进读
 *    位置，把主时间轴搅乱；字幕是稀疏的、一次读完，重开一份最省事也最安全。
 * ② 文本按 rect 原样拼接（多条以 '\n' 分隔），**不清洗** ASS 的 {\an8} 与
 *    <c.xxx> 这类标记——语义处理归 MoonBit 层，C 只做搬运。
 * ③ 图形字幕（无 text 的 rect）与空条目直接跳过，不报成一条空字幕。
 * ------------------------------------------------------------------------- */

void vf_sub_close(VfSDec *d) {
    if (d) {
        avsubtitle_free(&d->sub);
        if (d->pkt) {
            av_packet_free(&d->pkt);
        }
        if (d->codec) {
            avcodec_free_context(&d->codec);
        }
        if (d->fmt) {
            avformat_close_input(&d->fmt);
        }
        free(d);
    }
}

/* 另开一份容器并定位字幕流、开解码器。没有字幕流或打不开时 NULL。 */
VfSDec *vf_sub_open(const char *path) {
    AVFormatContext *fmt = NULL;
    if (avformat_open_input(&fmt, path, NULL, NULL) < 0) {
        return NULL;
    }
    if (avformat_find_stream_info(fmt, NULL) < 0) {
        avformat_close_input(&fmt);
        return NULL;
    }
    int sstream = av_find_best_stream(fmt, AVMEDIA_TYPE_SUBTITLE, -1, -1, NULL, 0);
    if (sstream < 0) {
        avformat_close_input(&fmt);
        return NULL;
    }
    AVStream *st = fmt->streams[sstream];
    const AVCodec *codec = avcodec_find_decoder(st->codecpar->codec_id);
    if (!codec) {
        avformat_close_input(&fmt);
        return NULL;
    }
    VfSDec *d = (VfSDec *)calloc(1, sizeof(VfSDec));
    d->fmt = fmt;
    d->sstream = sstream;
    d->pkt = av_packet_alloc();
    d->last_pts = -1.0;
    d->last_end = -1.0;
    d->codec = avcodec_alloc_context3(codec);
    if (!d->pkt || !d->codec ||
        avcodec_parameters_to_context(d->codec, st->codecpar) < 0 ||
        avcodec_open2(d->codec, codec, NULL) < 0) {
        vf_sub_close(d);
        return NULL;
    }
    return d;
}

/* 打开是否成功（NULL = 没有字幕流 / 解码器缺失 / 文件打不开） */
int32_t vf_sub_ok(VfSDec *d) {
    return d ? 1 : 0;
}

/* 解下一条字幕：文本写进 out（UTF-8，带尾零），返回写出的字节数（不含尾零）；
 * 0 = 流结束；-1 = 错误。起始秒随后用 vf_sub_pts_s 取（与 vf_frame_pts_s 同形）。 */
int32_t vf_sub_next(VfSDec *d, char *out, int32_t out_len) {
    if (!d || !d->codec || out == NULL || out_len < 1) {
        return -1;
    }
    out[0] = '\0';
    while (1) {
        int ret = av_read_frame(d->fmt, d->pkt);
        if (ret == AVERROR_EOF) {
            return 0;
        }
        if (ret < 0) {
            return -1;
        }
        if (d->pkt->stream_index != d->sstream) {
            av_packet_unref(d->pkt);
            continue;
        }
        AVStream *st = d->fmt->streams[d->sstream];
        double base = d->pkt->pts == AV_NOPTS_VALUE
                          ? 0.0
                          : (double)d->pkt->pts * av_q2d(st->time_base);
        // 包时长要在 unref 之前取（unref 会把 duration 清掉）
        double dur_pkt = d->pkt->duration > 0
                             ? (double)d->pkt->duration * av_q2d(st->time_base)
                             : 0.0;
        int got = 0;
        ret = avcodec_decode_subtitle2(d->codec, &d->sub, &got, d->pkt);
        av_packet_unref(d->pkt);
        if (ret < 0) {
            return -1;
        }
        if (!got) {
            continue;
        }
        int at = 0;
        for (int i = 0; i < d->sub.num_rects; i++) {
            AVSubtitleRect *r = d->sub.rects[i];
            // 有些文本字幕解码器（mov_text 即其一）只填 ass 字段、text 留空；
            // ass 是整行 ASS 对话（前九个逗号字段 + 文本），原样带出去，
            // 剥前缀与清洗标记归 MoonBit 层
            const char *txt = (r != NULL && r->text != NULL && r->text[0] != '\0')
                                  ? r->text
                                  : (r != NULL ? r->ass : NULL);
            if (txt == NULL || txt[0] == '\0') {
                continue;
            }
            int n = snprintf(out + at, out_len - at, at == 0 ? "%s" : "\n%s",
                             txt);
            if (n < 0 || n >= out_len - at) {
                break;
            }
            at += n;
        }
        // 起止时间 = 包 pts + 该条目的 start_display_time；时长取「包时长」与
        // 「end_display_time」里较短的那个——部分解码器（mov_text 即其一）不填
        // 条目时长、恒给 2000ms 默认值，照它读会让一条字幕压住下一条。
        d->last_pts = base + (double)d->sub.start_display_time / 1000.0;
        double dur_sub = (double)d->sub.end_display_time / 1000.0;
        double dur = dur_sub;
        if (dur_pkt > 0.0 && (dur_sub <= 0.0 || dur_pkt < dur_sub)) {
            dur = dur_pkt;
        }
        d->last_end = d->last_pts + (dur > 0.0 ? dur : 0.0);
        avsubtitle_free(&d->sub);
        if (at == 0) {
            continue; // 图形字幕或被截断成空的条目不算一条
        }
        return at;
    }
}

/* 最近一条字幕的起始秒；未读/未知 -1 */
double vf_sub_pts_s(VfSDec *d) {
    return d ? d->last_pts : -1.0;
}

/* 最近一条字幕的结束秒；未读/未知 -1（个别流不填时长，此时与起始同刻） */
double vf_sub_end_s(VfSDec *d) {
    return d ? d->last_end : -1.0;
}
