// ~/.mng/ready 读写：内容为 mng 版本行，版本不符视为不存在（触发重检）。

///|
/// ready 文件内容行：`mng <版本>`。
pub fn ready_line(version~ : String) -> String {
  "mng \{version}"
}

///|
/// ready 落点：`<home>/.mng/ready`。
pub fn ready_path(home~ : String) -> String {
  home + "/.mng/ready"
}

///|
/// ready 是否有效：文件存在且首行与当前版本行一致。
pub fn ready_valid(path~ : String, version~ : String) -> Bool {
  let content = @fs.read_file_to_string(path) catch { _ => return false }
  first_line(content) == ready_line(version~)
}

///|
/// 写 ready（父目录一起建）；成功返回 true。
pub fn ready_write(home~ : String, version~ : String) -> Bool {
  ensure_dir(home + "/.mng")
  @fs.write_string_to_file(ready_path(home~), ready_line(version~) + "\n") catch {
    _ => return false
  }
  true
}

///|
/// 删 ready（环境型错误后失效重检用）；文件不存在也算成功。
pub fn ready_clear(home~ : String) -> Bool {
  let path = ready_path(home~)
  if @fs.path_exists(path) {
    @fs.remove_file(path) catch {
      _ => return false
    }
  }
  true
}
