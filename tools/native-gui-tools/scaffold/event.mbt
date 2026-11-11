// 脚手架进度事件：内核只报事实，CLI 与向导各自渲染。

///|
pub(all) enum ScafEvent {
  InvalidName(String) // 原始工程名非法
  DirExists(String) // 目标目录已存在（不覆盖）
  MkdirFail(String) // 建不出的目录
  FilesWriteFail(String) // 工程文件写失败（目录已删除）
  CompileFail(String) // 首页模板编译失败原因
  GenWriteFail(String) // 生成码写失败路径
  PageWriteFail(String) // 单页样板写失败路径
  AppDone(dir~ : String, name~ : String) // 工程就绪（目录 + 工程名）
  PageDone(path~ : String, fn_name~ : String) // 单页样板就绪
}
