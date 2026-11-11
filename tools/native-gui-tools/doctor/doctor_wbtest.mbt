// doctor 内核白盒：解析纯函数、ready 内容口径与判据逻辑。

///|
test "first_line 去首行与行尾 \\r" {
  inspect(first_line("a\nb"), content="a")
  inspect(first_line("a\r\nb"), content="a")
  inspect(first_line("abc"), content="abc")
  inspect(first_line(""), content="")
}

///|
test "parse_python_version 主次版本" {
  debug_inspect(
    parse_python_version(line="Python 3.15.0"),
    content="Some((3, 15))",
  )
  debug_inspect(
    parse_python_version(line="Python 3.7.3"),
    content="Some((3, 7))",
  )
  debug_inspect(
    parse_python_version(line="Python 2.7.16"),
    content="Some((2, 7))",
  )
  debug_inspect(parse_python_version(line="Python 3"), content="None")
  debug_inspect(parse_python_version(line="python 3.11"), content="None")
  debug_inspect(parse_python_version(line="3.11.4"), content="None")
}

///|
test "python_ok 按 ≥3.7 判" {
  inspect(python_ok(major=3, minor=7), content="true")
  inspect(python_ok(major=3, minor=6), content="false")
  inspect(python_ok(major=2, minor=9), content="false")
  inspect(python_ok(major=4, minor=0), content="true")
}

///|
test "required_ok：可选项失败不拦、必选项失败拦" {
  let ok_req = {
    id: "moon",
    optional: false,
    status: Ok,
    title: { zh: "", en: "", },
    detail: { zh: "", en: "", },
    fix: None,
  }
  let fail_opt = {
    id: "ffmpeg",
    optional: true,
    status: Fail,
    title: { zh: "", en: "", },
    detail: { zh: "", en: "", },
    fix: None,
  }
  let warn_req = { ..ok_req, status: Warn, }
  let fail_req = { ..ok_req, id: "gtk", status: Fail, }
  inspect(required_ok([ok_req, fail_opt]), content="true")
  inspect(required_ok([ok_req, warn_req]), content="true")
  inspect(required_ok([ok_req, fail_req]), content="false")
}

///|
test "ready 内容行与有效性判定" {
  inspect(ready_line(version="0.2.11"), content="mng 0.2.11")
  let tmp = ".doctor-ready-wbtest"
  @fs.write_string_to_file(tmp, ready_line(version="0.2.11") + "\n") catch {
    _ => fail("写临时文件失败")
  }
  inspect(ready_valid(path=tmp, version="0.2.11"), content="true")
  // 版本不符视为无效（触发重检）
  inspect(ready_valid(path=tmp, version="0.3.0"), content="false")
  @fs.remove_file(tmp) catch {
    _ => ()
  }
  inspect(ready_valid(path=tmp, version="0.2.11"), content="false")
}

///|
test "run_all 冒烟：moon 项必须在位且 id 唯一" {
  let items = run_all()
  let seen : Array[String] = []
  for it in items {
    if seen.contains(it.id) {
      fail("体检项 id 重复：\{it.id}")
    }
    seen.push(it.id)
  }
  let mut moon_ok = false
  for it in items {
    if it.id == "moon" && it.status is Ok {
      moon_ok = true
    }
  }
  inspect(moon_ok, content="true")
}
