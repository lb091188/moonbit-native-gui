// wgpu-native 运行期核心（gui-gpu 包内共享）：dlopen 装载 + 进程级探测
// （instance/adapter/device/queue，v29 future 风格 API 经回调拿）。
//
// 本文件只回答「这台机器上 wgpu 能不能用、设备是什么」——装载走运行期、
// 不占链接面（没装 GPU 扩展 = 探测失败，上层照常走纯光栅/软件路径）。
// triangle.c（X11 三角形探针）与 canvas.c（GpuSink 实现）共用这一份；
// 各自只带自己的 surface/管线/上屏逻辑。gui/win/stub.c 的 L1 核心是
// 跨模块的第二份（主包不依赖本模块的家规），按本仓「跨模块 C 各写一份、
// 注释互引」纪律处理。
//
// vendor 头经 __has_include 相对取（与 gpu/ 包目录同级：modules/gui-gpu/
// vendor/）——缺归档本文件退化成「不可用」桩，构建照旧绿。

#ifndef MNG_WGPU_CORE_H
#define MNG_WGPU_CORE_H

// 探测一次（进程内幂等）。1 = 可用；0 = 不可用（.so 缺/驱动无后端）。
int mng_wgpu_ready(void);

// 探测详情（装载路径或失败原因，原样可打印；未探测时为空串）。
void mng_wgpu_detail(char *out, int cap);

// 库句柄（ready 之后非空）：消费者按自己的符号表 dlsym（core 只装探测
// 必需的那几个，各消费者的渲染面符号自己取）。
void *mng_wgpu_lib(void);

// 进程级对象（ready 之后才非空；跨消费者复用——设备/队列建一次）。
void *mng_wgpu_instance(void);
void *mng_wgpu_adapter(void);
void *mng_wgpu_device(void);
void *mng_wgpu_queue(void);

#endif /* MNG_WGPU_CORE_H */
