// 体检探针：每项产出一个 DItem；修复文案与 docs/zh/guide/build.md 的安装清单同源。

///|
fn bi(zh : String, en : String) -> DBi {
  { zh, en, }
}

///|
fn ditem(
  id~ : String,
  title~ : DBi,
  status~ : DStatus,
  detail~ : DBi,
  fix~ : DBi? = None,
  optional~ : Bool = false,
) -> DItem {
  { id, title, status, detail, fix, optional, }
}

///|
/// moon 安装命令（与 build.md §1 同源）。
fn fix_moon_install(platform : String) -> DBi {
  let cmd = if platform == "win" {
    "irm https://cli.moonbitlang.com/install/powershell.ps1 | iex"
  } else {
    "curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash"
  }
  bi(cmd, cmd)
}

///|
fn check_moon(platform : String, log_dir : String) -> DItem {
  let title = bi("MoonBit 工具链", "MoonBit toolchain")
  match capture(log_dir, "moon", "moon", ["version", "--all"]) {
    Err(_) =>
      ditem(
        id="moon",
        title~,
        status=Fail,
        detail=bi("未找到 moon 命令", "moon command not found"),
        fix=Some(fix_moon_install(platform)),
      )
    Ok((0, out)) =>
      ditem(
        id="moon",
        title~,
        status=Ok,
        detail=bi(first_line(out), first_line(out)),
      )
    Ok((code, _)) =>
      ditem(
        id="moon",
        title~,
        status=Fail,
        detail=bi(
          "moon version --all 退出码 \{code}",
          "moon version --all exited with \{code}",
        ),
      )
  }
}

///|
/// 单条 python 命令的版本判定。
/// Some(结论项) 给出状态与文案；None 表示命令不在位（调用方决定是否算失败）。
fn probe_python(log_dir : String, id : String, cmd : String) -> DItem? {
  match capture(log_dir, id, cmd, ["-V"]) {
    Err(_) => None
    Ok((0, out)) => {
      let line = first_line(out)
      match parse_python_version(line~) {
        Some((major, minor)) =>
          if python_ok(major~, minor~) {
            Some(
              ditem(
                id~,
                title=bi(
                  "Python 3（prebuild 必需）", "Python 3 (required by prebuild)",
                ),
                status=Ok,
                detail=bi(line, line),
              ),
            )
          } else {
            Some(
              ditem(
                id~,
                title=bi(
                  "Python 3（prebuild 必需）", "Python 3 (required by prebuild)",
                ),
                status=Fail,
                detail=bi("\{line}，低于 3.7", "\{line}, below 3.7"),
                fix=Some(
                  bi(
                    "升级 Python 3（winget install Python.Python.3.12 或包管理器）",
                    "Upgrade Python 3 (winget install Python.Python.3.12 or your package manager)",
                  ),
                ),
              ),
            )
          }
        None =>
          Some(
            ditem(
              id~,
              title=bi(
                "Python 3（prebuild 必需）", "Python 3 (required by prebuild)",
              ),
              status=Warn,
              detail=bi(
                "在位但版本认不出：\{line}",
                "present but version unreadable: \{line}",
              ),
            ),
          )
      }
    }
    Ok((code, _)) =>
      Some(
        ditem(
          id~,
          title=bi(
            "Python 3（prebuild 必需）", "Python 3 (required by prebuild)",
          ),
          status=Warn,
          detail=bi(
            "\{cmd} -V 退出码 \{code}",
            "\{cmd} -V exited with \{code}",
          ),
        ),
      )
  }
}

///|
fn python_item(
  id : String,
  status : DStatus,
  detail : DBi,
  fix? : DBi,
) -> DItem {
  ditem(
    id~,
    title=bi("Python 3（prebuild 必需）", "Python 3 (required by prebuild)"),
    status~,
    detail~,
    fix~,
  )
}

///|
fn check_python(platform : String, log_dir : String) -> DItem {
  // Windows 上 python3.exe 只是应用商店别名、不可靠，判 python
  if platform == "win" {
    return match probe_python(log_dir, "python", "python") {
      Some(it) => it
      None =>
        python_item(
          "python",
          Fail,
          bi("未找到 python 命令", "python command not found"),
          fix=bi(
            "winget install Python.Python.3.12（无 winget 时从 python.org/downloads 装安装器）",
            "winget install Python.Python.3.12 (or install from python.org/downloads when winget is absent)",
          ),
        )
    }
  }
  match capture(log_dir, "python3", "python3", ["-V"]) {
    Err(_) => {
      let hint = if platform == "mac" {
        "xcode-select --install"
      } else {
        "sudo apt install python3"
      }
      python_item(
        "python3",
        Fail,
        bi("未找到 python3 命令", "python3 command not found"),
        fix=bi(hint, hint),
      )
    }
    Ok((0, out)) => {
      let line = first_line(out)
      match parse_python_version(line~) {
        None =>
          python_item(
            "python3",
            Warn,
            bi(
              "在位但版本认不出：\{line}",
              "present but version unreadable: \{line}",
            ),
          )
        Some((major, minor)) =>
          if !python_ok(major~, minor~) {
            python_item(
              "python3",
              Fail,
              bi("\{line}，低于 3.7", "\{line}, below 3.7"),
              fix=bi(
                "升级 Python 3（≥3.7）后重跑 mng doctor", "Upgrade Python 3 (>=3.7) and re-run mng doctor",
              ),
            )
          } else {
            // python3 达标；POSIX 上 moon 优先拿 python 跑 prebuild——
            // 别名缺席不算失败（会回落 python3），存在且低于 3 才拦
            match capture(log_dir, "python-alias", "python", ["-V"]) {
              Err(_) => python_item("python3", Ok, bi(line, line))
              Ok((0, alias_out)) =>
                match parse_python_version(line=first_line(alias_out)) {
                  Some((amaj, amin)) =>
                    if python_ok(major=amaj, minor=amin) {
                      python_item(
                        "python3",
                        Ok,
                        bi(
                          "\{line}（python 别名 \{amaj}.\{amin}）",
                          "\{line} (python alias \{amaj}.\{amin})",
                        ),
                      )
                    } else {
                      python_item(
                        "python3",
                        Fail,
                        bi(
                          "python 别名是 \{amaj}.\{amin}——moon 优先拿它跑 prebuild，2.x 会整次构建起手就红",
                          "python alias is \{amaj}.\{amin}; moon prefers it for prebuild and 2.x breaks the build",
                        ),
                        fix=bi(
                          "把 python 指向 python3（docs/zh/guide/build.md §6 第一行）",
                          "Point python to python3 (build guide, section 6 first row)",
                        ),
                      )
                    }
                  None => python_item("python3", Ok, bi(line, line))
                }
              Ok(_) => python_item("python3", Ok, bi(line, line))
            }
          }
      }
    }
    Ok((code, _)) =>
      python_item(
        "python3",
        Fail,
        bi("python3 -V 退出码 \{code}", "python3 -V exited with \{code}"),
      )
  }
}

///|
fn check_cc(platform : String, log_dir : String) -> DItem {
  let title = bi("C/C++ 编译器", "C/C++ compiler")
  let cc_ok = capture(log_dir, "cc", "cc", ["--version"]) is Ok((0, _))
  let gxx_ok = capture(log_dir, "gxx", "g++", ["--version"]) is Ok((0, _))
  let clt_hint = "xcode-select --install"
  let apt_hint = "sudo apt install build-essential"
  let install_hint = bi(
    if platform == "mac" {
      clt_hint
    } else {
      apt_hint
    },
    if platform == "mac" {
      clt_hint
    } else {
      apt_hint
    },
  )
  if cc_ok && gxx_ok {
    return ditem(
      id="cc",
      title~,
      status=Ok,
      detail=bi("cc 与 g++ 在位", "cc and g++ present"),
    )
  }
  let detail = if !cc_ok && !gxx_ok {
    bi("未找到 cc 与 g++", "cc and g++ not found")
  } else if !gxx_ok {
    bi(
      "缺 g++——dwrite_text.cpp 每个平台都要过一遍 C++ 编译", "g++ missing; dwrite_text.cpp needs a C++ compiler on every platform",
    )
  } else {
    bi("缺 cc", "cc missing")
  }
  let fix = if !gxx_ok && cc_ok && platform != "mac" {
    bi("sudo apt install g++", "sudo apt install g++")
  } else {
    install_hint
  }
  ditem(id="cc", title~, status=Fail, detail~, fix=Some(fix))
}

///|
/// pkg-config --modversion 一项；Ok(版本行) / Err（包不在位或 pkg-config 缺席）。
fn pkg_modversion(
  log_dir : String,
  id : String,
  lib : String,
) -> Result[String, String] {
  match capture(log_dir, id, "pkg-config", ["--modversion", lib]) {
    Err(e) => Err(e)
    Ok((0, out)) => Ok(first_line(out))
    Ok((_, _)) => Err("")
  }
}

///|
fn check_gtk(log_dir : String) -> DItem {
  let title = bi(
    "GTK3 / Pango / FontConfig / X11 开发包", "GTK3 / Pango / FontConfig / X11 dev packages",
  )
  let libs = ["gtk+-3.0", "pangoft2", "pangocairo", "fontconfig", "x11", "xext"]
  let missing : Array[String] = []
  let first_ver : Ref[String] = { val: "", }
  for lib in libs {
    match pkg_modversion(log_dir, "pkg-\{lib}", lib) {
      Ok(v) => if first_ver.val == "" { first_ver.val = "\{lib} \{v}" }
      Err(_) => missing.push(lib)
    }
  }
  if missing.is_empty() {
    return ditem(
      id="gtk",
      title~,
      status=Ok,
      detail=bi(first_ver.val, first_ver.val),
    )
  }
  ditem(
    id="gtk",
    title~,
    status=Fail,
    detail=bi("缺 \{missing.join(", ")}", "missing \{missing.join(", ")}"),
    fix=Some(
      bi(
        "sudo apt install pkg-config libgtk-3-dev libpango1.0-dev libfontconfig1-dev libx11-dev libxext-dev",
        "sudo apt install pkg-config libgtk-3-dev libpango1.0-dev libfontconfig1-dev libx11-dev libxext-dev",
      ),
    ),
  )
}

///|
/// 可选开发库（WebView / 媒体）：不在位只 Warn，不拦 ready。
fn check_pkg_lib(
  log_dir : String,
  id~ : String,
  lib~ : String,
  title~ : DBi,
  why~ : DBi,
  fix~ : String,
) -> DItem {
  match pkg_modversion(log_dir, id, lib) {
    Ok(v) =>
      ditem(
        id~,
        title~,
        status=Ok,
        detail=bi("\{lib} \{v}", "\{lib} \{v}"),
        optional=true,
      )
    Err(_) =>
      ditem(
        id~,
        title~,
        status=Warn,
        detail=why,
        fix=Some(bi(fix, fix)),
        optional=true,
      )
  }
}

///|
fn check_ffmpeg_mac(log_dir : String) -> DItem {
  let title = bi("ffmpeg（可选）", "ffmpeg (optional)")
  match capture(log_dir, "ffmpeg", "ffmpeg", ["-version"]) {
    Ok((0, out)) =>
      ditem(
        id="ffmpeg",
        title~,
        status=Ok,
        detail=bi(first_line(out), first_line(out)),
        optional=true,
      )
    _ =>
      ditem(
        id="ffmpeg",
        title~,
        status=Warn,
        detail=bi(
          "未找到 ffmpeg——媒体模块另需（或让 prebuild 从 Release 拉自编归档）",
          "ffmpeg not found; required by the media module (or let prebuild fetch the prebuilt archive)",
        ),
        fix=Some(bi("brew install ffmpeg", "brew install ffmpeg")),
        optional=true,
      )
  }
}

///|
fn probe_write(p : String, body : String) -> Bool {
  @fs.write_string_to_file(p, body) catch {
    _ => return false
  }
  true
}

///|
/// VS BuildTools 安装指引（winget 缺席的机器走官方安装器直链）。
fn fix_msvc_install() -> DBi {
  bi(
    "winget install Microsoft.VisualStudio.2022.BuildTools -e --override \"--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended\"（无 winget 时从 https://visualstudio.microsoft.com/visual-cpp-build-tools/ 下安装器，勾选「使用 C++ 的桌面开发」）",
    "winget install Microsoft.VisualStudio.2022.BuildTools -e --override \"--quiet --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --includeRecommended\" (or grab the installer at https://visualstudio.microsoft.com/visual-cpp-build-tools/ and select the C++ desktop workload when winget is absent)",
  )
}

///|
/// moon native 构建探针：`~/.mng/doctor/probe/` 落最小 hello 工程，真跑一次
/// `moon build --target native`，以成败为判据（build.md §3 的 Windows 口径，
/// 与 prebuild「以链接成败为判据」同源）。失败时日志留在同目录供排查。
fn native_probe(log_dir : String, home : String) -> DItem {
  let title = bi("moon native 构建探针", "moon native build probe")
  let pdir = home + "/.mng/doctor/probe"
  ensure_dir(pdir)
  let ok = probe_write(
      pdir + "/moon.mod",
      "name = \"mng/doctor-probe\"\n\nversion = \"0.1.0\"\n\npreferred_target = \"native\"\n",
    ) &&
    probe_write(pdir + "/moon.pkg", "pkgtype(kind: \"executable\")\n") &&
    probe_write(
      pdir + "/main.mbt",
      "fn main {\n  println(\"doctor probe\")\n}\n",
    )
  if !ok {
    return ditem(
      id="probe",
      title~,
      status=Fail,
      detail=bi(
        "探针工程写盘失败（\{pdir} 建不出来：目录权限或路径形态问题）",
        "failed writing probe project (cannot create \{pdir}: permissions or path form)",
      ),
    )
  }
  let log = log_dir + "/native-probe.log"
  if @fs.path_exists(log) {
    @fs.remove_file(log) catch {
      _ => ()
    }
  }
  // 冷构建含 runtime 编译，给足余量；ready 门保证一台机器只跑一次量级
  match
    @proc.spawn_wait(
      "moon",
      ["-C", pdir, "build", "--target", "native"],
      log,
      240000,
    ) {
    Err(e) => ditem(id="probe", title~, status=Fail, detail=bi(e, e))
    Ok(0) =>
      ditem(
        id="probe",
        title~,
        status=Ok,
        detail=bi(
          "hello 工程编译链接通过", "hello project compiled and linked",
        ),
      )
    Ok(code) =>
      ditem(
        id="probe",
        title~,
        status=Fail,
        detail=bi(
          "探针构建退出码 \{code}，日志：\{log}",
          "probe build exited with \{code}, log: \{log}",
        ),
        fix=Some(fix_msvc_install()),
      )
  }
}

///|
/// Windows 的 MSVC 判定：vswhere 查到 VCTools 只是快路（免探针直接过）；
/// 查不到/没有 vswhere 一律落构建探针以成败为准——组件 id 对不上的安装
/// 形态（全量 VS / 异版 BuildTools / 免安装器）不该误报红（2026-11-11
/// win 真机反馈：能编译的机器被 vswhere 判缺）。
fn check_msvc(log_dir : String, home : String) -> DItem {
  let title = bi(
    "MSVC C++ 工具链（构建探针判定）", "MSVC C++ toolchain (build-probe verdict)",
  )
  let vswhere = match @env.get_env_var("ProgramFiles(x86)") {
    Some(p) if p.length() > 0 =>
      p + "/Microsoft Visual Studio/Installer/vswhere.exe"
    _ => "C:/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe"
  }
  if @fs.path_exists(vswhere) {
    match
      capture(log_dir, "vswhere", vswhere, [
        "-products", "*", "-requires", "Microsoft.VisualStudio.Component.VC.Tools.x86.x64",
        "-property", "installationPath",
      ]) {
      Ok((0, out)) =>
        if out.length() > 0 {
          return ditem(
            id="msvc",
            title~,
            status=Ok,
            detail=bi(first_line(out), first_line(out)),
          )
        }
      _ => ()
    }
  }
  // vswhere 快路未命中：探针说了算
  let p = native_probe(log_dir, home)
  { ..p, id: "msvc", title, }
}
