// mng publish:本地发布器(D6 的本地半边)。`mng package` 之后跑,把
// `.mng/dist/` 里的产物算出 SHA256/体积,生成 update.json(载体进 platforms、
// 安装包只随 Release 分发),经 gh CLI 探测目标 Release(draft)并上传。
//
// 与 CI(release-app.yml 汇总腿)的分工:CI 按标签一次性出三平台全量清单;
// 本命令给「CI 不可用 / 只要本平台」的场景——每次生成**当时 dist 里**的条目
// (跨平台拼清单:把别处出的产物拷进 .mng/dist/ 一起发,解析器按文件名全收),
// update.json 以 --clobber 覆盖远端同名。
//
// 口径与库侧更新器(gui/sys/update.mbt)对齐:载体 = mac/win 的 zip、linux 的
// AppImage;清单 signature/sig_alg/deltas 为预留位恒 null(v1.5/v2 再启)。
// pub_date 留空串:发布时间以 Release 页为准,本地不猜时钟。

///|
/// 一个待发布产物:解析自文件名(slug-版本-target.ext)。
pub(all) struct PubArt {
  file : String // 文件名(不含目录)
  slug : String
  version : String
  target : String
  ext : String
}

///|
/// 字符串里某字符最后出现的下标(没有给 -1):解析产物名用,标准库没有现成的。
fn pub_last_ch(s : String, c : Char) -> Int {
  let a = chars_of(s)
  let mut at = -1
  let mut i = 0
  while i < a.length() {
    if a[i] == c {
      at = i
    }
    i += 1
  }
  at
}

///|
/// 解析产物文件名:`<slug>-<semver>-<target>.<ext>`;target 认三平台固定串,
/// ext 认五件(dmg/zip/exe/deb/AppImage);版本不是三段 semver 给 None。
/// 与 release-app.yml 汇总腿的正则同口径。
fn pub_parse_artifact(name : String) -> PubArt? {
  let dot = pub_last_ch(name, '.')
  if dot <= 0 {
    return None
  }
  let ext = name[dot + 1:].to_owned()
  let ok_ext = ext == "dmg" ||
    ext == "zip" ||
    ext == "exe" ||
    ext == "deb" ||
    ext == "AppImage"
  if !ok_ext {
    return None
  }
  let stem = name[:dot].to_owned()
  let targets = ["darwin-aarch64", "windows-x86_64", "linux-x86_64"]
  for t in targets {
    let suffix = "-" + t
    if stem.has_suffix(suffix) {
      let head = stem[:stem.length() - suffix.length()].to_owned()
      let dash = pub_last_ch(head, '-')
      if dash <= 0 {
        return None
      }
      let ver = head[dash + 1:].to_owned()
      if !semver_ok(ver) {
        return None
      }
      let slug = head[:dash].to_owned()
      if slug.length() == 0 {
        return None
      }
      return Some({ file: name, slug, version: ver, target: t, ext })
    }
  }
  None
}

///|
/// 是否更新载体(进 update.json 的 platforms):mac/win 吃 zip、linux 吃
/// AppImage;安装包(dmg/exe/deb)只随 Release 分发不是载体(D2)。
fn pub_is_carrier(target : String, ext : String) -> Bool {
  if target == "darwin-aarch64" || target == "windows-x86_64" {
    ext == "zip"
  } else if target == "linux-x86_64" {
    ext == "AppImage"
  } else {
    false
  }
}

///|
/// JSON 串转义(双引号/反斜杠/控制字符;notes 这类自由文本要过这道)。
fn pub_json_escape(s : String) -> String {
  let b = StringBuilder()
  for c in s {
    if c == '"' {
      b.write_string("\\\"")
    } else if c == '\\' {
      b.write_string("\\\\")
    } else if c == '\n' {
      b.write_string("\\n")
    } else if c == '\r' {
      b.write_string("\\r")
    } else if c == '\t' {
      b.write_string("\\t")
    } else {
      b.write_char(c)
    }
  }
  b.to_string()
}

///|
/// 清单文本(载体条目已算好 sha/size):platforms 按传入次序,URL 拼
/// releases/download/<tag>/<file>;预留位恒 null。
fn pub_manifest_text(
  version : String,
  notes : String,
  repo : String,
  tag : String,
  carriers : Array[PubArt],
  shas : Array[String],
  sizes : Array[Int64],
) -> String {
  let b = StringBuilder()
  b.write_string("{\n")
  b.write_string("  \"version\": \"\{version}\",\n")
  b.write_string("  \"notes\": \"\{pub_json_escape(notes)}\",\n")
  b.write_string("  \"pub_date\": \"\",\n")
  b.write_string("  \"platforms\": {")
  if carriers.length() == 0 {
    b.write_string("},\n")
  } else {
    b.write_char('\n')
    let mut i = 0
    while i < carriers.length() {
      let a = carriers[i]
      let comma = if i + 1 < carriers.length() { "," } else { "" }
      b.write_string(
        "    \"\{a.target}\": {\"url\": \"https://github.com/\{repo}/releases/download/\{tag}/\{a.file}\", \"size\": \{sizes[i]}, \"sha256\": \"\{shas[i]}\"}\{comma}\n",
      )
      i += 1
    }
    b.write_string("  },\n")
  }
  b.write_string("  \"signature\": null,\n")
  b.write_string("  \"sig_alg\": null,\n")
  b.write_string("  \"deltas\": null\n")
  b.write_string("}\n")
  b.to_string()
}

///|
/// 从校验命令输出提取 SHA256(posix「hex  路径」/ certutil 块):第一段长度
/// 恰为 64 的小写十六进制串。与库侧 upd_extract_sha256 同口径(工具侧副本)。
fn pub_extract_sha(text : String) -> String? {
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
    Some(seg)
  } else {
    None
  }
}

///|
/// 算一个文件的 SHA256:走平台自带命令,输出落 log 再读;拿不到给 Err。
fn pub_sha256_file(path : String, log : String) -> Result[String, String] {
  let host = host_pkg()
  let (file, args) = if host == "mac" {
      ("shasum", ["-a", "256", path])
    } else if host == "win" {
      ("certutil", ["-hashfile", path, "SHA256"])
    } else {
      ("sha256sum", [path])
    }
  let _ = @fs.remove_file(log) catch { _ => () }
  match @proc.spawn(file, args, log) {
    Err(e) => return Err("\{file} 起不来:\{e}")
    Ok(pid) => {
      let mut waited = 0
      while waited < 120000 {
        if !@proc.alive(pid) {
          break
        }
        @proc.sleep_ms(200)
        waited += 200
      }
    }
  }
  match slurp(log) {
    Some(t) =>
      match pub_extract_sha(t) {
        Some(h) => Ok(h)
        None => Err(tmsg("SHA256 输出里找不到 64 位十六进制段:", "no 64-hex segment in sha output: ") + t)
      }
    None => Err("sha log unreadable: " + log)
  }
}

///|
/// 文件字节数(读进内存取长度;产物几十 MB 一次性,工具进程可接受)。
fn pub_file_size(path : String) -> Int64 {
  try {
    let bs = @fs.read_file_to_bytes(path)
    bs.length().to_int64()
  } catch {
    _ => 0L
  }
}

///|
/// gh 探测目标仓库:`gh repo view --json nameWithOwner`,输出落 log 读回。
fn pub_gh_repo(log : String) -> String? {
  let _ = @fs.remove_file(log) catch { _ => () }
  match @proc.spawn("gh", ["repo", "view", "--json", "nameWithOwner"], log) {
    Err(_) => None
    Ok(pid) => {
      let mut waited = 0
      while waited < 30000 {
        if !@proc.alive(pid) {
          break
        }
        @proc.sleep_ms(100)
        waited += 100
      }
      match slurp(log) {
        Some(t) =>
          match json_parse(t) {
            Ok(j) =>
              match jget(j, "nameWithOwner") {
                Some(v) => json_str(v)
                None => None
              }
            Err(_) => None
          }
        None => None
      }
    }
  }
}

///|
/// gh 跑一条命令(spawn 落 log + 等退出;成败由调用方按 log/后续探测判定)。
fn pub_gh_run(args : Array[String], log : String, timeout_ms : Int) -> Result[Unit, String] {
  let _ = @fs.remove_file(log) catch { _ => () }
  match @proc.spawn("gh", args, log) {
    Err(e) => Err("gh 起不来:\{e}")
    Ok(pid) => {
      let mut waited = 0
      let mut running = true
      while waited < timeout_ms {
        if !@proc.alive(pid) {
          running = false
          break
        }
        @proc.sleep_ms(300)
        waited += 300
      }
      if running {
        ignore(@proc.kill(pid))
        Err("gh 超时(\{timeout_ms}ms)")
      } else {
        Ok(())
      }
    }
  }
}

///|
/// 探 Release 是否已存在(`gh release view <tag>` 落 log;失败即不存在)。
fn pub_release_exists(tag : String, repo : String, log : String) -> Bool {
  match pub_gh_run(["release", "view", tag, "-R", repo], log, 30000) {
    Ok(_) =>
      match slurp(log) {
        // gh 失败信息也落同一份 log(如 not found),认「输出里有 tag 才算在」
        Some(t) => t.contains(tag) || t.contains("\"name\"")
        None => false
      }
    Err(_) => false
  }
}

///|
/// `mng publish` 入口。参数:--tag <tag>(默认 app-v<版本>)、--repo <owner/name>
/// (默认 gh 探测)、--notes <文本>(默认 "Release <版本>")、--no-upload(只生成
/// update.json 落 dist,不碰 gh)。
fn cmd_publish(args : Array[String]) -> Int {
  let cwd = match @env.current_dir() {
    Some(d) => d
    None => "."
  }
  let (root, kind) = match find_project_root(cwd) {
    Some(x) => x
    None =>
      return fail_pkg(tmsg("没找到 mng.toml(向上找过了)——先 mng init", "mng.toml not found (walked up) — run mng init first"))
  }
  if kind != "mng.toml" {
    return fail_pkg(tmsg("项目根是按 moon.mod 定位的,没有 mng.toml", "project root is a moon.mod without mng.toml"))
  }
  let text = match fs_read(root + "/mng.toml") {
    Some(t) => t
    None => return fail_pkg("mng.toml unreadable")
  }
  let conf = parse_package_toml(text)
  match pkg_validate(conf) {
    Some(e) => return fail_pkg(e)
    None => ()
  }
  // 参数
  let mut tag = "app-v" + conf.version
  let mut repo = ""
  let mut notes = "Release " + conf.version
  let mut upload = true
  let mut i = 0
  while i < args.length() {
    if args[i] == "--tag" && i + 1 < args.length() {
      tag = args[i + 1]
      i += 2
      continue
    }
    if args[i] == "--repo" && i + 1 < args.length() {
      repo = args[i + 1]
      i += 2
      continue
    }
    if args[i] == "--notes" && i + 1 < args.length() {
      notes = args[i + 1]
      i += 2
      continue
    }
    if args[i] == "--no-upload" {
      upload = false
    }
    i += 1
  }
  // 收产物:dist 里可解析且版本一致的;版本不符跳过并提示
  let dist = root + "/.mng/dist"
  let names : Array[String] = []
  let entries = @fs.read_dir(dist) catch {
    _ => return fail_pkg(tmsg(".mng/dist 不在——先跑 package", ".mng/dist missing — run package first"))
  }
  for e in entries {
    names.push(e.to_string())
  }
  let arts : Array[PubArt] = []
  for n in names {
    if n == "build.log" ||
      n == "dpkg-deb.log" ||
      n == "appimagetool.log" ||
      n == "sha.log" ||
      n.has_prefix("gh-") ||
      n == "update.json" {
      continue
    }
    match pub_parse_artifact(n) {
      Some(a) =>
        if a.version == conf.version {
          arts.push(a)
        } else {
          println(tmsg("跳过版本不符的产物:", "skip artifact with wrong version: ") + n)
        }
      None => ()
    }
  }
  if arts.length() == 0 {
    return fail_pkg(
      tmsg(
        ".mng/dist 里没有 \{conf.version} 的产物——先跑 package",
        "no \{conf.version} artifacts in .mng/dist — run package first",
      ),
    )
  }
  // 仓库:--repo 优先,否则 gh 探测
  let gh_log = dist + "/gh-probe.log"
  if repo.length() == 0 {
    if !upload {
      return fail_pkg(tmsg("--no-upload 也要 --repo(update.json 里的下载 URL 要仓库名)", "--no-upload still needs --repo (download URLs embed the repo)"))
    }
    match pub_gh_repo(gh_log) {
      Some(r) => repo = r
      None =>
        return fail_pkg(
          tmsg(
            "gh 探测不到仓库——装 gh 并 gh auth login,或 --repo owner/name 显式给",
            "gh cannot resolve the repo — install gh & gh auth login, or pass --repo owner/name",
          ),
        )
    }
  }
  // 载体算 sha/size;清单只收载体
  let carriers : Array[PubArt] = []
  for a in arts {
    if pub_is_carrier(a.target, a.ext) {
      carriers.push(a)
    }
  }
  let shas : Array[String] = []
  let sizes : Array[Int64] = []
  for a in carriers {
    let full = dist + "/" + a.file
    println(tmsg("算 SHA256:", "hashing: ") + a.file)
    match pub_sha256_file(full, dist + "/sha.log") {
      Ok(h) => shas.push(h)
      Err(e) => return fail_pkg(e)
    }
    sizes.push(pub_file_size(full))
  }
  let manifest = pub_manifest_text(conf.version, notes, repo, tag, carriers, shas, sizes)
  let manifest_path = dist + "/update.json"
  let wrote = try {
    @fs.write_string_to_file(manifest_path, manifest)
    true
  } catch {
    _ => false
  }
  if !wrote {
    return fail_pkg("update.json 写不进:" + manifest_path)
  }
  println(tmsg("清单已生成:", "manifest written: ") + manifest_path)
  if carriers.length() == 0 {
    println(tmsg("(dist 里没有更新载体——清单 platforms 为空,安装包仍随 Release 分发)", "(no update carriers in dist — platforms is empty; installers still ship with the Release)"))
  }
  if !upload {
    println(tmsg("按 --no-upload 只生成清单,未上传", "--no-upload: manifest only, nothing uploaded"))
    return 0
  }
  // 上传:Release 不存在就建 draft;产物 + update.json 一起 --clobber
  let up_log = dist + "/gh-upload.log"
  let files : Array[String] = []
  for a in arts {
    files.push(dist + "/" + a.file)
  }
  files.push(manifest_path)
  let mut up_args : Array[String] = []
  if pub_release_exists(tag, repo, gh_log) {
    println(tmsg("Release \{tag} 已在,补传产物(--clobber):", "Release \{tag} exists, uploading artifacts (--clobber):"))
    up_args = ["release", "upload", tag]
    for f in files {
      up_args.push(f)
    }
    up_args.push("--clobber")
    up_args.push("-R")
    up_args.push(repo)
  } else {
    println(tmsg("建 draft Release \{tag} 并上传:", "creating draft Release \{tag} and uploading:"))
    up_args = ["release", "create", tag, "--draft", "--title", "App " + conf.version, "--notes", notes]
    for f in files {
      up_args.push(f)
    }
    up_args.push("-R")
    up_args.push(repo)
  }
  match pub_gh_run(up_args, up_log, 600000) {
    Ok(_) => ()
    Err(e) => return fail_pkg("gh 上传失败:" + e)
  }
  // 验:release view 拿得到才算成(gh 对部分失败也退 0 的场景兜住)
  if !pub_release_exists(tag, repo, gh_log) {
    print_log_tail(up_log)
    return fail_pkg(tmsg("上传后探不到 Release \{tag}——看上面日志", "Release \{tag} not visible after upload — see log above"))
  }
  for a in arts {
    println("  " + a.file)
  }
  println("  update.json")
  println(tmsg("完成:\{repo} 的 draft \{tag}(发前人工核一遍再 publish)", "done: draft \{tag} on \{repo} (review, then publish)"))
  0
}
