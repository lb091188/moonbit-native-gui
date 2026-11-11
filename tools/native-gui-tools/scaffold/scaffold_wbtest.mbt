// 脚手架内核白盒：图标步与 mng.toml 行替换口径。

///|
test "replace_icon_line 只替第一处 icon 行且尾行对齐" {
  let toml = "[dev]\ntemplates = [\".\"]\n\n[package]\nicon = \"\"\nname = \"\"\n"
  let out = replace_icon_line(toml, "assets/icon.png")
  assert_true(out.contains("icon = \"assets/icon.png\""))
  assert_false(out.contains("icon = \"\""))
  assert_true(out.contains("name = \"\"\n"))
  // 尾部不带多余空行
  assert_false(out.has_suffix("\n\n"))
  // 原 icon 已有值也替
  let out2 = replace_icon_line(
    "[package]\nicon = \"old.png\"\n", "assets/icon.png",
  )
  assert_true(out2.contains("icon = \"assets/icon.png\""))
  assert_false(out2.contains("old.png"))
}

///|
test "icon_step：源缺失给 Err、全链过写 assets 并接线 mng.toml" {
  let root = tmp_dir("scaf_icon")
  rm_rf(root)
  let _ = mkdir_p(root)
  // 源缺失
  inspect(
    icon_step(dir=root, png="/nonexistent/icon.png") is Err(_),
    content="true",
  )
  // 全链：先脚手架一个工程再设图标
  assert_eq(app_at(parent=root, raw_name="ico_app", on_event=fn(_e) { () }), 0)
  let png = root + "/src.png"
  // 1x1 PNG（最小合法文件头 + IDAT 用 zlib 存根即可——这里直接拷真字节：
  // 用固定 81 字节的 1x1 透明 PNG）
  let png_bytes : Bytes = b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\nIDATx\x9cc\x00\x01\x00\x00\x05\x00\x01\r\n-\xb4\x00\x00\x00\x00IEND\xaeB`\x82"
  @fs.write_bytes_to_file(png, png_bytes) catch {
    _ => abort("写源 png 失败")
  }
  let dir = root + "/ico_app"
  match icon_step(dir~, png~) {
    Err(e) => abort("icon_step 失败：\{e}")
    Ok(rel) => inspect(rel, content="assets/icon.png")
  }
  let copied = @fs.read_file_to_bytes(dir + "/assets/icon.png") catch {
    _ => abort("拷贝件缺")
  }
  assert_eq(copied.length(), png_bytes.length())
  let toml = @fs.read_file_to_string(dir + "/mng.toml") catch {
    _ => abort("mng.toml 缺")
  }
  assert_true(toml.contains("icon = \"assets/icon.png\""))
}

///|
/// 测试残留清理：递归删目录。
fn tmp_dir(tag : String) -> String {
  ".scaf-wbtest-" + tag
}

///|
fn rm_rf(root : String) -> Unit {
  if !@fs.path_exists(root) {
    return
  }
  let dirs : Ref[Array[String]] = { val: [root], }
  let victims : Array[String] = []
  while dirs.val.length() > 0 {
    let d = dirs.val[dirs.val.length() - 1]
    let _ = dirs.val.remove(dirs.val.length() - 1)
    if d != root {
      victims.push(d)
    }
    let entries = @fs.read_dir(d) catch { _ => [] }
    for e in entries {
      let p = d + "/" + e.to_string()
      let isdir = @fs.is_dir(p) catch { _ => false }
      if isdir {
        dirs.val.push(p)
      } else {
        victims.push(p)
      }
    }
  }
  let mut k = victims.length() - 1
  while k >= 0 {
    let _ = @fs.remove_file(victims[k]) catch { _ => () }
    let _ = @fs.remove_dir(victims[k]) catch { _ => () }
    k -= 1
  }
  let _ = @fs.remove_dir(root) catch { _ => () }
}
