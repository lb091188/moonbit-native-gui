
///|
test "prt Windows 读数环：winspool 枚举 + 默认打印机语义" {
  if sys_platform() != "windows" {
    println("prt: skip (windows-only 读数环)")
    return
  }
  match prt_list() {
    Ok(printers) =>
      for p in printers {
        assert_true(p.name != "")
      }
    Err(e) => {
      println("prt_list failed: \{e}")
      assert_true(false)
    }
  }
  // 未装打印机的机器 prt_list 合法为空；默认打印机缺省是 ParseFailed 语义
  match prt_default() {
    Ok(_) => println("prt: default ok")
    Err(PrtParseFailed(_)) => println("prt: no default (合法)")
    Err(e) => {
      println("prt_default failed: \{e}")
      assert_true(false)
    }
  }
}

///|
test "prt_parse_destinations：lpstat -e 的目标名一行一个" {
  let infos = prt_parse_destinations(
    "EPSON_L3250_Series\n\n  PDF  \nlpstat: 未添加目的位置。\n",
  )
  assert_eq(infos.length(), 2)
  assert_eq(infos[0].name, "EPSON_L3250_Series")
  // -e 不带状态：如实给 Unknown（可送纸判定按可用处理，见 prt_status_available）
  assert_eq(infos[0].status.to_string(), "PrinterStatus::Unknown")
  assert_eq(infos[1].name, "PDF")
  assert_eq(prt_parse_destinations("").length(), 0)
}
