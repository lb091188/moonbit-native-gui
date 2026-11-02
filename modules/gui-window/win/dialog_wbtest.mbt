///|
test "FileDialog：建/配/释放（run 与取结果留真机）" {
  // 本机有显示：桩侧 gtk_init_check 初始化后真建对象（不显示、不模态）；
  // 无显示环境（CI）同一入口返回 0 句柄、全接口退化不崩。
  // get_result 只在 run_for_window 确认后合法（桩拦未确认调用），
  // 模态 run 无头跑不了，走真机复验。
  let d = FileDialog::new_open()
  if d.id > 0 {
    d.set_filters("文本:txt,md|图片:png,jpg|全部:*")
    d.set_options(FILE_OPTION_MULTI_SELECT | FILE_OPTION_SHOW_HIDDEN)
    d.set_folder("file:///tmp")
    d.destroy()
    let s = FileDialog::new_save()
    assert_true(s.id > 0)
    s.set_filename("a.txt") // set_filename 只对保存对话框合法
    s.destroy()
  } else {
    d.set_filters("*:*")
    d.destroy()
  }
}
