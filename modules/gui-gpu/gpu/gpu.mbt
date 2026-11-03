// GPU 地基（wgpu-native 运行期装载）。
//
// 本包只回答一件事：**这台机器上现在能不能用 wgpu-native**——按 vendor/ 下的
// 归档（模块根 prebuild.py 按平台拉取并校验 sha256）dlopen，取到
// `wgpuCreateInstance` 才算可用。装载走运行期、不占链接面：没装 GPU 扩展的
// 应用照常编译运行，只是 `probe().loaded` 为假、界面走纯光栅/软件合成。
//
// 后续批次（L1/L2）在这里长 `GpuContext` 与 present 合成；本批只立地基与
// 探针契约，不引入任何渲染面。

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
