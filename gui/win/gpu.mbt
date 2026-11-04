// GPU 呈现档（L1）的诊断读数：C 侧进程级探测一次，结论与回退原因如实带出。

///|
extern "c" fn wm_l1_gpu_status() -> Bytes = "wm_l1_gpu_status"

///|
/// GPU 呈现档读数：「on」= 本进程窗口呈现可挂 GPU 档（位图上传纹理 →
/// 全屏 quad → swapchain present）；其余文本为回退原因（驱动无后端 /
/// vendor 归档缺 / 未编译）。诊断与演示用——呈现路径的逐帧回退在 C 侧
/// 自理，行为分派不读它。`NATIVEGUI_GPU_LOG=1` 时 stderr 有同拍日志。
pub fn gpu_present_status() -> String {
  @utf8.decode_lossy(wm_l1_gpu_status())
}
