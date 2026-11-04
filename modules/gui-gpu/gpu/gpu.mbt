// GPU 地基（wgpu-native 运行期装载）。
//
// 本包回答两件事：**这台机器上现在能不能用 wgpu-native**（`probe()`：按
// vendor/ 下的归档（模块根 prebuild.py 按平台拉取并校验 sha256）dlopen，
// 取到 `wgpuCreateInstance` 才算可用），以及**整条链路上不上得去屏**
// （`run_triangle()`：X11 wgpu 三角形探针，GPU 线第一步真机验收面）。
// 装载走运行期、不占链接面：没装 GPU 扩展的应用照常编译运行，只是
// `probe().loaded` 为假、界面走纯光栅/软件合成。
//
// 后续批次（L1/L2）在这里长 `GpuSink` 实现与 present 合成；本批只有地基、
// 探针契约与三角形探针。

///|
#borrow(out)
extern "c" fn mng_gpu_probe(out : Bytes, cap : Int) -> Int = "mng_gpu_probe"

///|
/// 探测结果：`loaded` 可用性 + `detail`（装载路径或失败原因，原样可打印）。
pub(all) struct GpuProbe {
  loaded : Bool
  detail : String
}

///|
/// 探测一次（进程内幂等：库装过一次就直接答 loaded）。
/// 候选路径依次是 `MNG_WGPU_LIB` 环境变量、`vendor/lib/…`、`vendor/…`、
/// 系统搜索路径上的库名；都没成就报 not-found，不抛错。
pub fn probe() -> GpuProbe {
  let cap = 256
  // 同一份 Bytes 既喂给 C 又用来读回：from_array 是拷贝，先后各造一次就读不到写入了
  let bytes = Bytes::from_array(FixedArray::make(cap, b'\x00'))
  let ok = mng_gpu_probe(bytes, cap)
  let mut n = 0
  while n < cap && bytes[n] != b'\x00' {
    n += 1
  }
  let detail = if n == 0 {
    ""
  } else {
    @utf8.decode_lossy(bytes[:n])
  }
  { loaded: ok == 1, detail }
}

///|
/// 跑一次 X11 wgpu 三角形探针（GPU 线第一步，真机肉眼验收面）：自开一个
/// Xlib 窗，wgpu 全链路（instance→surface→adapter→device→pipeline）上屏
/// 一个三色三角形，关窗或按 Esc 退出。`frames` 是帧数上限（≤0 取 600）。
/// 不可用（没装 GPU 扩展/没有 X 显示/驱动起不来）如实回 Err，不抛错——
/// 与 `probe()` 同一套「降级不是错误」口径。wgpu 库与 libX11 都 dlopen，
/// 本模块不占链接面；vendor 归档或 Xlib 头缺失的平台是编译期桩，同样回 Err。
#borrow(out)
extern "c" fn mng_gpu_triangle(out : Bytes, cap : Int, frames : Int) -> Int = "mng_gpu_triangle"

///|
pub fn run_triangle(frames~ : Int = 600) -> Result[Unit, String] {
  let cap = 320
  let bytes = Bytes::from_array(FixedArray::make(cap, b'\x00'))
  let rc = mng_gpu_triangle(bytes, cap, frames)
  if rc == 0 {
    Ok(())
  } else {
    let mut n = 0
    while n < cap && bytes[n] != b'\x00' {
      n += 1
    }
    let detail = if n == 0 {
      "未知原因（rc=\{rc}）"
    } else {
      @utf8.decode_lossy(bytes[:n])
    }
    Err(detail)
  }
}
