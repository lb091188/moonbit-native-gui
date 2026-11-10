// 应用自更新 v1(全量):清单检查 → 下载 → SHA256 校验 → 原子替换 → relaunch。
// 信任模型 v1 = HTTPS + SHA256(防损坏不防源沦陷;Ed25519 进 v1.5,清单
// signature/sig_alg 字段由发布侧预留,本端暂不校验);本地测试链路可在
// update_check 显式 allow_http 放行明文;方案见
// proposals/package-update.md §四。产物口径与 mng package 对齐:
// mac/win 下载 zip、linux 下载 AppImage,安装包(dmg/setup/deb)不是载体。
// 组合既有件:pr_run(curl/校验命令/解压)、autostart_exe_path(自身路径)、
// spawn_detached(relaunch)。平台分支全部走 sys_platform() 运行期判定。

// ---------------------------------------------------------------------------
// 数据与纯逻辑(白盒测试覆盖)
// ---------------------------------------------------------------------------

///|
/// 单平台更新载体:下载地址、字节数、SHA256(小写 hex)。
pub(all) struct UpdateAsset {
  url : String
  size : Int64
  sha256 : String
}

///|
/// update.json 清单(mng package / release-app CI 生成的形态)。
pub(all) struct UpdateManifest {
  version : String
  notes : String
  pub_date : String
  assets : Array[(String, UpdateAsset)] // target id → 载体
}

///|
/// semver 三段解析(a.b.c,每段纯数字);不合法给 None。
fn upd_semver_parse(v : String) -> (Int, Int, Int)? {
  let parts : Array[String] = []
  for raw in v.split(".") {
    parts.push(raw.to_owned())
  }
  if parts.length() != 3 {
    return None
  }
  let out : Array[Int] = [0, 0, 0]
  let mut i = 0
  while i < 3 {
    let p = parts[i]
    if p.length() == 0 {
      return None
    }
    let mut n = 0
    for c in p {
      if c < '0' || c > '9' {
        return None
      }
      n = n * 10 + (c.to_int() - 48)
    }
    out[i] = n
    i += 1
  }
  Some((out[0], out[1], out[2]))
}

///|
/// 版本比较:-1(a<b)/ 0(相等)/ 1(a>b);任一段不合法按「不可比」返回 0
/// 并由调用方以字符串不等兜底(宁可提示更新,不静默跳过)。
pub fn update_version_cmp(a : String, b : String) -> Int {
  match (upd_semver_parse(a), upd_semver_parse(b)) {
    (Some(x), Some(y)) =>
      if x.0 != y.0 {
        if x.0 > y.0 { 1 } else { -1 }
      } else if x.1 != y.1 {
        if x.1 > y.1 { 1 } else { -1 }
      } else if x.2 != y.2 {
        if x.2 > y.2 { 1 } else { -1 }
      } else {
        0
      }
    _ => if a == b { 0 } else { 1 }
  }
}

///|
/// 远端版本是否比本地新(严格大于)。
pub fn update_is_newer(remote : String, current : String) -> Bool {
  update_version_cmp(remote, current) > 0
}

///|
/// 本机更新 target id:与打包/CI 产物命名同源
/// (macos→darwin-aarch64、windows→windows-x86_64、linux→linux-x86_64;
/// mac 只 Apple Silicon、linux 当前只出 x86_64,均与支持面一致)。
pub fn update_target_id() -> String {
  match sys_platform() {
    "macos" => "darwin-aarch64"
    "windows" => "windows-x86_64"
    _ => "linux-x86_64"
  }
}

///|
/// 清单文本 → UpdateManifest;字段缺失/类型不符/JSON 不合法给 None。
/// platforms 之外的顶层键(含 v1.5/v2 预留的 signature/sig_alg/deltas)忽略。
pub fn update_parse_manifest(text : String) -> UpdateManifest? {
  let root = match vsc_json_parse(text) {
    Some(r) => r
    None => return None
  }
  let version = match vsc_json_str(vsc_json_get(root, "version")) {
    Some(v) => v
    None => return None
  }
  let notes = match vsc_json_str(vsc_json_get(root, "notes")) {
    Some(s) => s
    None => ""
  }
  let pub_date = match vsc_json_str(vsc_json_get(root, "pub_date")) {
    Some(s) => s
    None => ""
  }
  let platforms = vsc_json_get(root, "platforms")
  let assets : Array[(String, UpdateAsset)] = []
  match platforms {
    Some(VscJObj(entries)) =>
      for pair in entries {
        let (target, obj) = pair
        let url = vsc_json_str(vsc_json_get(obj, "url"))
        let sha = vsc_json_str(vsc_json_get(obj, "sha256"))
        match (url, sha) {
          (Some(u), Some(s)) =>
            assets.push(
              (
                target,
                {
                  url: u,
                  size: match vsc_json_int64(vsc_json_get(obj, "size")) {
                    Some(n) => n
                    None => 0L
                  },
                  sha256: s,
                },
              ),
            )
          _ => ()
        }
      }
    _ => ()
  }
  Some(
    {
      version,
      notes,
      pub_date,
      assets,
    },
  )
}

///|
/// 清单里取本机 target 的载体;没有(发布面未覆盖本平台)给 None。
pub fn update_manifest_asset(m : UpdateManifest, target : String) -> UpdateAsset? {
  for pair in m.assets {
    let (t, a) = pair
    if t == target {
      return Some(a)
    }
  }
  None
}

///|
/// 从校验命令输出里提取 SHA256(posix「hex  路径」行、certutil 多行块都吃):
/// 扫描第一段长度恰为 64 的十六进制串。
fn upd_extract_sha256(text : String) -> String? {
  let mut seg = ""
  for c in text {
    let hex = (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f')
    if hex {
      seg = seg + c.to_string()
    } else {
      if seg.length() == 64 {
        return Some(seg)
      }
      seg = ""
    }
  }
  if seg.length() == 64 {
    return Some(seg)
  }
  None
}

// ---------------------------------------------------------------------------
// IO 组合(检查/下载/校验/替换/重启;真机行为归用户验证)
// ---------------------------------------------------------------------------

///|
/// 拉清单并判断有无新版:Ok(None) = 已是最新;Err 带可读原因
/// (网络失败/清单不合法/本平台无载体)。HTTPS 强制——http:// 明文直接拒;
/// 本地更新服务(测试链路用)可显式 allow_http=true 放行明文。
pub fn update_check(
  manifest_url : String,
  current_version : String,
  timeout_ms? : Int = 15000,
  allow_http? : Bool = false,
) -> Result[UpdateManifest?, String] {
  if !allow_http && manifest_url.has_prefix("http://") {
    return Err("更新清单必须走 HTTPS:\{manifest_url}")
  }
  let out = match pr_run("curl", ["-fsSL", manifest_url], timeout_ms~) {
    Ok(o) => o
    Err(e) => return Err("拉取清单失败:\{e}")
  }
  if out.exit_code != 0 {
    return Err("拉取清单失败(退出码 \{out.exit_code})")
  }
  let m = match update_parse_manifest(out.stdout) {
    Some(m) => m
    None => return Err("清单不合法(update.json)")
  }
  if !update_is_newer(m.version, current_version) {
    return Ok(None)
  }
  match update_manifest_asset(m, update_target_id()) {
    None =>
      return Err("有新版 \{m.version},但清单没有本平台(\{update_target_id()})的载体")
    Some(_) => ()
  }
  Ok(Some(m))
}

///|
/// 算文件 SHA256(小写 hex);走平台自带命令,拿不到给 None。
fn upd_sha256_file(path : String) -> String? {
  let out = match sys_platform() {
    "macos" => pr_run("shasum", ["-a", "256", path], timeout_ms=120000)
    "windows" => pr_run("certutil", ["-hashfile", path, "SHA256"], timeout_ms=120000)
    _ => pr_run("sha256sum", [path], timeout_ms=120000)
  }
  match out {
    Ok(o) if o.exit_code == 0 => upd_extract_sha256(o.stdout)
    _ => None
  }
}

///|
/// url 末段当落盘文件名(去查询串);末段为空回退 "update-download"。
fn upd_basename_of_url(url : String) -> String {
  let mut last = url
  for raw in url.split("/") {
    last = raw.to_owned()
  }
  let mut cut = last
  for raw in last.split("?") {
    cut = raw.to_owned()
    break
  }
  if cut.length() == 0 {
    "update-download"
  } else {
    cut
  }
}

///|
/// 下载更新载体到 dest_dir(临时名 .mng-update-download,校验过才转正名):
/// 返回最终路径;SHA256 不符/下载失败给 Err。超时默认 10 分钟。
pub fn update_download(
  asset : UpdateAsset,
  dest_dir : String,
  timeout_ms? : Int = 600000,
) -> Result[String, String] {
  if !sys_make_dirs(dest_dir) {
    return Err("建不了下载目录:\{dest_dir}")
  }
  let tmp = dest_dir + "/.mng-update-download"
  let out = match pr_run("curl", ["-fL", "--retry", "3", "-o", tmp, asset.url], timeout_ms~) {
    Ok(o) => o
    Err(e) => {
      ignore(sys_remove_file(tmp))
      return Err("下载失败:\{e}")
    }
  }
  if out.exit_code != 0 {
    ignore(sys_remove_file(tmp))
    return Err("下载失败(退出码 \{out.exit_code})")
  }
  match upd_sha256_file(tmp) {
    Some(got) if got == asset.sha256 => {
      let final_path = dest_dir + "/" + upd_basename_of_url(asset.url)
      // 同名旧载体先挪走再落地,避免跨平台覆盖语义差异
      ignore(sys_remove_file(final_path))
      match upd_move(tmp, final_path) {
        Ok(_) => Ok(final_path)
        Err(e) => {
          ignore(sys_remove_file(tmp))
          Err(e)
        }
      }
    }
    Some(got) => {
      ignore(sys_remove_file(tmp))
      Err("SHA256 不符(期望 \{asset.sha256},实得 \{got})")
    }
    None => {
      ignore(sys_remove_file(tmp))
      Err("算不出 SHA256,拒装")
    }
  }
}

///|
/// 文件搬移:POSIX 走 mv;Windows 走 cmd move(跨目录时 move 带复制语义,同盘足够)。
fn upd_move(src : String, dst : String) -> Result[Unit, String] {
  let r = match sys_platform() {
    "windows" => pr_run("cmd", ["/c", "move", "/y", src, dst], timeout_ms=60000)
    _ => pr_run("mv", ["-f", src, dst], timeout_ms=60000)
  }
  match r {
    Ok(o) if o.exit_code == 0 => Ok(())
    _ => Err("搬移失败:\{src} → \{dst}")
  }
}

///|
/// 目录级删除(cleanup 撤 .mng-old 残留用):POSIX rm -rf;Windows rd /s /q。
fn upd_remove_tree(path : String) -> Bool {
  let r = match sys_platform() {
    "windows" => pr_run("cmd", ["/c", "rd", "/s", "/q", path], timeout_ms=60000)
    _ => pr_run("rm", ["-rf", path], timeout_ms=60000)
  }
  match r {
    Ok(o) => o.exit_code == 0
    _ => false
  }
}

///|
/// dirname:末个 / (或 Windows 反斜杠)之前的整段;无分隔给 "."。
fn upd_dirname(p : String) -> String {
  let mut cut = -1
  let mut i = 0
  let n = p.length()
  while i < n {
    let c = p[i]
    if c == '/' || c == '\\' {
      cut = i
    }
    i += 1
  }
  if cut < 0 {
    return "."
  }
  if cut == 0 {
    return "/"
  }
  p[:cut].to_owned()
}

///|
/// 应用更新载体(v1 全量替换;失败尽量回滚):
/// - linux:载体即新 AppImage——旧文件挪 .mng-old、载体落原名、补可执行位;
/// - mac:zip 内含 <Name>.app——旧 .app 挪 .mng-old、unzip 到 .app 所在目录;
/// - win:zip 内含裸 exe 与同目录文件——解到临时目录,非 exe 文件逐个覆盖,
///   旧 exe 挪 .exe.mng-old、新 exe 落原名(运行中 exe 只能换名不能覆盖)。
/// 成功后调 update_relaunch 重启;残留 .mng-old 由新进程启动时 update_cleanup 清。
pub fn update_apply_carrier(carrier_path : String) -> Result[Unit, String] {
  let exe = match autostart_exe_path() {
    Some(p) => p
    None => return Err("拿不到自身可执行路径")
  }
  match sys_platform() {
    "linux" => {
      let old = exe + ".mng-old"
      ignore(sys_remove_file(old))
      match upd_move(exe, old) {
        Ok(_) =>
          match upd_move(carrier_path, exe) {
            Ok(_) => {
              match pr_run("chmod", ["+x", exe], timeout_ms=10000) {
                _ => ()
              }
              Ok(())
            }
            Err(e) => {
              ignore(upd_move(old, exe))
              Err("落位新 AppImage 失败(已回滚):\{e}")
            }
          }
        Err(e) => Err("挪走旧 AppImage 失败:\{e}")
      }
    }
    "macos" => {
      // exe = <App>.app/Contents/MacOS/<bin>;app 根 = dirname 三级
      let app_root = upd_dirname(upd_dirname(upd_dirname(exe)))
      let parent = upd_dirname(app_root)
      // 位置先探可写:直接从 DMG 卷里跑的应用替换必败,给可读指引而不是 unzip 退出码
      let probe = parent + "/.mng-probe"
      if !sys_make_dirs(probe) {
        return Err(
          "应用所在位置不可写(只读卷或无权限;直接从 DMG 里运行就是这种)——把 .app 拖进「应用程序」后再检查更新",
        )
      }
      ignore(upd_remove_tree(probe))
      // 挪旧装新:旧 .app 整树挪 .mng-old(运行中可改名),再解压新的;解压失败回滚
      let old = app_root + ".mng-old"
      ignore(upd_remove_tree(old))
      match upd_move(app_root, old) {
        Err(e) => return Err("挪走旧 .app 失败:\{e}")
        Ok(_) => ()
      }
      let unzip = pr_run("unzip", ["-q", "-o", carrier_path, "-d", parent], timeout_ms=300000)
      match unzip {
        Ok(o) if o.exit_code != 0 => {
          // 解压不成:撤半截新树,旧 .app 搬回来,应用保持可用
          ignore(upd_remove_tree(app_root))
          ignore(upd_move(old, app_root))
          return Err("解压载体失败(退出码 \{o.exit_code},已回滚)")
        }
        Err(e) => {
          ignore(upd_remove_tree(app_root))
          ignore(upd_move(old, app_root))
          return Err("解压载体失败:\{e}(已回滚)")
        }
        _ => ()
      }
      // 残留 .mng-old(旧整树)由新进程启动时 update_cleanup 清
      Ok(())
    }
    _ => {
      // windows:解到 exe 同级临时目录,再逐文件落位
      let dir = upd_dirname(exe)
      let tmpdir = dir + "/.mng-update-unpack"
      ignore(upd_remove_tree(tmpdir))
      if !sys_make_dirs(tmpdir) {
        return Err("建解压目录失败:\{tmpdir}")
      }
      let tar = pr_run("tar", ["-xf", carrier_path, "-C", tmpdir], timeout_ms=300000)
      match tar {
        Ok(o) if o.exit_code != 0 => {
          ignore(upd_remove_tree(tmpdir))
          return Err("解压载体失败(退出码 \{o.exit_code})")
        }
        Err(e) => {
          ignore(upd_remove_tree(tmpdir))
          return Err("解压载体失败:\{e}")
        }
        _ => ()
      }
      let exe_name = match exe.contains("/") || exe.contains("\\") {
          true => {
            let mut last = exe
            for raw in exe.split("/") {
              last = raw.to_owned()
            }
            for raw in last.split("\\") {
              last = raw.to_owned()
            }
            last
          }
          false => exe
        }
      // 非 exe 文件逐个覆盖(同名直接 move /y)
      match fsx_list_dir(tmpdir) {
        Ok(names) =>
          for name in names {
            if name != exe_name {
              ignore(upd_move(tmpdir + "/" + name, dir + "/" + name))
            }
          }
        Err(_) => ()
      }
      // exe 换名落位(运行中 exe 不能覆盖写)
      let old = exe + ".mng-old"
      ignore(sys_remove_file(old))
      match upd_move(exe, old) {
        Ok(_) =>
          match upd_move(tmpdir + "/" + exe_name, exe) {
            Ok(_) => {
              ignore(upd_remove_tree(tmpdir))
              Ok(())
            }
            Err(e) => {
              ignore(upd_move(old, exe))
              ignore(upd_remove_tree(tmpdir))
              Err("落位新 exe 失败(已回滚):\{e}")
            }
          }
        Err(e) => {
          ignore(upd_remove_tree(tmpdir))
          Err("挪走旧 exe 失败:\{e}")
        }
      }
    }
  }
}

///|
/// 分离重启自身(起得来给 true;退出应用由调用方决定时机)。
pub fn update_relaunch() -> Bool {
  match autostart_exe_path() {
    Some(exe) =>
      match spawn_detached(exe, "") {
        Ok(_) => true
        Err(_) => false
      }
    None => false
  }
}

///|
/// 启动早期清更新残留:自身路径旁的 *.mng-old(文件与目录)。
pub fn update_cleanup() -> Unit {
  let exe = match autostart_exe_path() {
    Some(p) => p
    None => return
  }
  let dir = upd_dirname(exe)
  match fsx_list_dir(dir) {
    Ok(names) =>
      for name in names {
        if name.has_suffix(".mng-old") {
          let full = dir + "/" + name
          if sys_path_exists(full) {
            ignore(upd_remove_tree(full))
          }
        }
      }
    Err(_) => ()
  }
}
