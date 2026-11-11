// new 子命令的 CLI 渲染层：脚手架内核在 @scaffold（模板构造与落盘），
// 这里把内核事件渲染成终端文案——与内核化之前的输出逐行一致。

///|
fn scaf_render(e : @scaffold.ScafEvent) -> Unit {
  match e {
    InvalidName(raw) =>
      println(
        tmsg(
          "工程名非法（字母/数字/下划线/连字符）：\{raw}",
          "Invalid project name (letters/digits/underscore/hyphen): \{raw}",
        ),
      )
    DirExists(dir) =>
      println(
        tmsg(
          "目录已存在，不覆盖：" + dir,
          "Directory already exists, not overwriting: " + dir,
        ),
      )
    MkdirFail(dir) =>
      println(
        tmsg("建不出目录：" + dir, "Cannot create directory: " + dir),
      )
    FilesWriteFail(dir) =>
      println(
        tmsg(
          "工程文件写失败（目录已删除）：" + dir,
          "Failed writing project files (directory removed): " + dir,
        ),
      )
    CompileFail(err) =>
      println(
        tmsg(
          "首页模板编译失败（脚手架缺陷，请回报）：\{err}",
          "Home template compile failed (scaffold bug, please report): \{err}",
        ),
      )
    GenWriteFail(path) =>
      println(
        tmsg(
          "生成码写失败：" + path,
          "Failed writing generated code: " + path,
        ),
      )
    PageWriteFail(path) =>
      println(tmsg("写不出文件：" + path, "Cannot write file: " + path))
    AppDone(dir~, name~) => {
      println("OK " + dir)
      println(
        tmsg(
          "下一步：cd \{name} && moon run .   （热更：mng dev）",
          "Next: cd \{name} && moon run .   (hot reload: mng dev)",
        ),
      )
    }
    PageDone(path~, fn_name~) =>
      println(
        tmsg(
          "OK \{path}（生成函数名 \{fn_name}；把生成码接进包内即可编译）",
          "OK \{path} (generated function name \{fn_name}; wire it into the package to compile)",
        ),
      )
  }
}

///|
/// 工程脚手架 CLI 入口：在 `parent/` 下建工程（wbtest 与命令面共用签名）。
fn scaffold_app_at(parent : String, raw_name : String) -> Int32 {
  @scaffold.app_at(parent~, raw_name~, on_event=scaf_render)
}

///|
/// 单页样板 CLI 入口：写 `<路径>.mng`（父目录不存在现建）。
fn new_page(raw : String) -> Int32 {
  @scaffold.page(raw~, on_event=scaf_render)
}
