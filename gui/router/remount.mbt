///|
/// 原地重挂整棵路由：卸掉所有在挂子树与内容缓存，再按当前各级选中键重新挂载。
/// 给「内容文本换了但树形结构不变」的整树重刷用（切语言、换皮肤）——
/// 比 `goto` 切走再切回少一拍闪动，也不依赖候选表顺序。
pub fn Router::remount_all(self : Router) -> Unit {
  let keys : Array[String] = []
  for k in self.mounted {
    keys.push(k.0)
  }
  for k in keys {
    self.unmount(k)
  }
  // 兜底：父槽 reset 回调清掉子树后，子槽表项可能残留，再扫一遍直到表空
  let leftovers : Array[String] = []
  for k in self.mounted {
    leftovers.push(k.0)
  }
  for k in leftovers {
    self.unmount(k)
  }
  // 缓存里还剩「预建过、没点开过」的页——它们不在挂载表里，上面的 unmount 碰不到，
  // 不一起丢就会在下次点开时把旧语言的节点直接复用出去。
  self.purge_all_built()
  // 队列回到起点：预建过的页刚被清空，让它们按新文案在空闲里重建回来
  self.reanchor()
  for st in self.levels {
    st.set_always(st.get())
  }
}

///|
/// 登记「随语言重挂」：i18n 广播（换目录）时对本路由做一次 `remount_all`。
/// 与 `@widget.set_menu_bar_localized` 同一条链——页面与原生菜单都从注册表
/// 领更新，调用方只在建树时登记一次。重复登记以最后一次为准。
pub fn Router::localize_remount(self : Router) -> Unit {
  if self.locale_hook.val != 0 {
    @i18n.off_locale_change(self.locale_hook.val)
  }
  let h = @i18n.on_locale_change(fn(_loc : String) -> Unit {
    self.remount_all()
    @widget.invalidate()
  })
  self.locale_hook.val = h
}
