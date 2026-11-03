// LSP 报文处理回归（无头）：握手、诊断、四档补全、hover 与退出。

///|
fn tpl_ok() -> String {
  [
    "<script setup lang=\"moonbit\">",
    "let qty : @base.Store[Int] = @base.Store::new(0)",
    "</script>",
    "<style>",
    ".card { color: var(--text_primary); }",
    "</style>",
    "<template>",
    "  <ui-col class=\"card\">",
    "    值 {{ qty }}",
    "  </ui-col>",
    "</template>",
  ].join("\n") + "\n"
}

///|
fn did_open(uri : String, text : String) -> String {
  "{\"jsonrpc\":\"2.0\",\"method\":\"textDocument/didOpen\",\"params\":{\"textDocument\":{\"uri\":\"" + uri + "\",\"languageId\":\"mng\",\"version\":1,\"text\":\"" + escape_json_t(text) + "\"}}}"
}

///|
fn escape_json_t(s : String) -> String {
  let out = StringBuilder()
  for c in s {
    if c == '"' {
      out.write_string("\\\"")
    } else if c == '\\' {
      out.write_string("\\\\")
    } else if c == '\n' {
      out.write_string("\\n")
    } else if c == '\r' {
      out.write_string("\\r")
    } else {
      out.write_char(c)
    }
  }
  out.to_string()
}

///|
fn req(id : Int, meth : String, params : String) -> String {
  "{\"jsonrpc\":\"2.0\",\"id\":" + id.to_string() + ",\"method\":\"" + meth + "\",\"params\":" + params + "}"
}

///|
fn pos_params(uri : String, line : Int, ch : Int) -> String {
  let head = "{\"textDocument\":{\"uri\":\"" + uri + "\"},\"position\":{\"line\":" + line.to_string()
  head + ",\"character\":" + ch.to_string() + "}}"
}

///|
test "LSP：握手能力、诊断坐标、四档补全与 hover" {
  let docs : Map[String, String] = Map([])
  let uri = "file:///tmp/lsp_wbtest.mng"
  // 握手
  let init = lsp_handle(docs, req(1, "initialize", "{}"))
  match init.reply {
    Some(r) => assert_true(contains_sub_l(r, "completionProvider") && contains_sub_l(r, "\"hoverProvider\":true"))
    None => assert_true(false)
  }
  // didOpen：好模板无诊断
  let open1 = lsp_handle(docs, did_open(uri, tpl_ok()))
  match open1.notify {
    Some(n) => assert_true(contains_sub_l(n, "publishDiagnostics") && contains_sub_l(n, "\"diagnostics\":[]"))
    None => assert_true(false)
  }
  // didOpen：坏模板 → 诊断带模板坐标（第 7 行 3 列的 ui-fancy）
  let bad = tpl_ok().replace(old="    值 {{ qty }}", new="    <ui-fancy text=\"x\" />\n    值 {{ qty }}")
  let open2 = lsp_handle(docs, did_open(uri, bad))
  match open2.notify {
    Some(n) =>
      assert_true(
        contains_sub_l(n, "ui-fancy") && contains_sub_l(n, "\"line\":8"),
      )
    None => assert_true(false)
  }
  // 四档补全：表达式
  let c_expr = lsp_handle(docs, req(2, "textDocument/completion", pos_params(uri, 8, 10)))
  match c_expr.reply {
    Some(r) => assert_true(contains_sub_l(r, "\"label\":\"qty\""))
    None => assert_true(false)
  }
  // 类名
  let c_class = lsp_handle(docs, req(3, "textDocument/completion", pos_params(uri, 7, 20)))
  match c_class.reply {
    Some(r) => assert_true(contains_sub_l(r, "\"label\":\"card\""))
    None => assert_true(false)
  }
  // 标签
  let c_tag = lsp_handle(docs, req(4, "textDocument/completion", pos_params(uri, 7, 4)))
  match c_tag.reply {
    Some(r) => assert_true(contains_sub_l(r, "\"label\":\"ui-text\""))
    None => assert_true(false)
  }
  // hover：`ui-col` 前段光标 → 扩到完整令牌
  let hov = lsp_handle(docs, req(5, "textDocument/hover", pos_params(uri, 7, 5)))
  match hov.reply {
    Some(r) => assert_true(contains_sub_l(r, "ui-col") && contains_sub_l(r, "参数"))
    None => assert_true(false)
  }
  // shutdown / exit
  assert_true(match lsp_handle(docs, req(6, "shutdown", "{}")).reply {
    Some(_) => true
    None => false
  })
  assert_true(lsp_handle(docs, "{\"jsonrpc\":\"2.0\",\"method\":\"exit\"}").stop)
}

///|
fn contains_sub_l(s : String, sub : String) -> Bool {
  let a : Array[Char] = []
  for c in s {
    a.push(c)
  }
  let b : Array[Char] = []
  for c in sub {
    b.push(c)
  }
  let n = a.length()
  let m = b.length()
  if m == 0 || m > n {
    return m == 0
  }
  let mut i = 0
  while i + m <= n {
    let mut ok = true
    for k in 0..<m {
      if a[i + k] != b[k] {
        ok = false
      }
    }
    if ok {
      return true
    }
    i += 1
  }
  false
}

///|
/// 造一个最小 workspace：`app/page`（模板所在包）导入 `lib/base` 与 `lib/ui`。
fn nav_fixture() -> String {
  let root = tmp_dir("mng_lsp_nav")
  for d in [
    root,
    root + "/app",
    root + "/app/page",
    root + "/lib",
    root + "/lib/base",
    root + "/lib/ui",
  ] {
    ensure_dir_p(d)
  }
  write_file_p(root + "/moon.work", "members = [\n  \"app\",\n  \"lib\",\n]\n")
  write_file_p(root + "/app/moon.mod", "name = \"demo/app\"\n")
  write_file_p(root + "/lib/moon.mod", "name = \"demo/lib\"\n")
  write_file_p(
    root + "/app/page/moon.pkg",
    "import {\n  \"demo/lib/base\",\n  \"demo/lib/ui\",\n}\n",
  )
  write_file_p(
    root + "/lib/base/pkg.generated.mbti",
    [
      "package \"demo/lib/base\"",
      "",
      "pub fn[T] Store::get(Self[T]) -> T",
      "pub fn[T] Store::new(T) -> Self[T]",
      "pub struct Store[T] {",
      "  v : T",
      "}",
    ].join("\n"),
  )
  write_file_p(
    root + "/lib/base/store.mbt",
    [
      "pub struct Store[T] {",
      "  v : T",
      "}",
      "",
      "pub fn[T] Store::new(v : T) -> Store[T] {",
      "  { v }",
      "}",
    ].join("\n"),
  )
  write_file_p(
    root + "/lib/ui/ui.mbt",
    [
      "///|",
      "/// 列容器：`children` 逐项排进去。",
      "pub fn col(children : Array[Int]) -> Int {",
      "  0",
      "}",
      "",
      "///|",
      "/// 文本：`value` 是要显示的字，`max` 是最长字符数（超出截断）。",
      "pub fn text(",
      "  value : String,",
      "  /// 占位文字，未输入时显示。",
      "  placeholder? : String = \"\",",
      "  max? : Int = 0",
      ") -> Int {",
      "  0",
      "}",
    ].join("\n"),
  )
  root
}

///|
test "LSP：外部包跳转（@包.成员 / 包入口 / 内置标签）与成员补全" {
  let root = nav_fixture()
  let docs : Map[String, String] = Map([])
  let uri = "file://" + root + "/app/page/page.mng"
  let text = [
    "<script setup lang=\"moonbit\">",
    "let qty : @base.Store[Int] = @base.Store::new(0)",
    "let z = @base.",
    "</script>",
    "<template>",
    "  <ui-col>",
    "    <ui-text value=\"x\" max=\"2\" placeholder=\"a\" />",
    "    <ui-stepper v-model=\"qty\" max=\"10\" />",
    "  </ui-col>",
    "</template>",
  ].join("\n") + "\n"
  let _ = lsp_handle(docs, did_open(uri, text))
  // `@base.Store::new` → 外部包源码的声明行
  match lsp_handle(docs, req(10, "textDocument/definition", pos_params(uri, 1, 37))).reply {
    Some(r) =>
      assert_true(
        contains_sub_l(r, "/lib/base/store.mbt") && contains_sub_l(r, "\"line\":4"),
      )
    None => assert_true(false)
  }
  // 页内 `let qty` → 模板自身声明行
  match lsp_handle(docs, req(11, "textDocument/definition", pos_params(uri, 1, 5))).reply {
    Some(r) =>
      assert_true(
        contains_sub_l(r, "page.mng") && contains_sub_l(r, "\"line\":1"),
      )
    None => assert_true(false)
  }
  // 裸 `@base` → 包入口（生成的 mbti）
  match lsp_handle(docs, req(12, "textDocument/definition", pos_params(uri, 2, 10))).reply {
    Some(r) =>
      assert_true(
        contains_sub_l(r, "/lib/base/pkg.generated.mbti") && contains_sub_l(r, "\"line\":0"),
      )
    None => assert_true(false)
  }
  // 内置标签 `<ui-text>` → `@ui.text` 的源码
  match lsp_handle(docs, req(13, "textDocument/definition", pos_params(uri, 6, 6))).reply {
    Some(r) =>
      assert_true(
        contains_sub_l(r, "/lib/ui/ui.mbt") && contains_sub_l(r, "\"line\":8"),
      )
    None => assert_true(false)
  }
  // hover 标签带声明文档；hover 属性带该参数的说明句
  match lsp_handle(docs, req(18, "textDocument/hover", pos_params(uri, 6, 6))).reply {
    Some(r) => assert_true(contains_sub_l(r, "文本："))
    None => assert_true(false)
  }
  match lsp_handle(docs, req(19, "textDocument/hover", pos_params(uri, 6, 24))).reply {
    Some(r) => assert_true(contains_sub_l(r, "最长字符数"))
    None => assert_true(false)
  }
  // 参数自带的 /// 文档优先于函数级文档
  match lsp_handle(docs, req(23, "textDocument/hover", pos_params(uri, 6, 32))).reply {
    Some(r) => assert_true(contains_sub_l(r, "占位文字"))
    None => assert_true(false)
  }
  // `@base.` → 包内公开成员（含 `::` 方法）
  match lsp_handle(docs, req(14, "textDocument/completion", pos_params(uri, 2, 14))).reply {
    Some(r) =>
      assert_true(
        contains_sub_l(r, "\"label\":\"Store\"") && contains_sub_l(r, "\"label\":\"Store::new\""),
      )
    None => assert_true(false)
  }
  // hover：成员签名原文
  match lsp_handle(docs, req(15, "textDocument/hover", pos_params(uri, 1, 37))).reply {
    Some(r) => assert_true(contains_sub_l(r, "Store::new(v : T)"))
    None => assert_true(false)
  }
  // hover 属性：给出该参数的类型与所属组件（签名里的可省参数）
  match lsp_handle(docs, req(16, "textDocument/hover", pos_params(uri, 6, 24))).reply {
    Some(r) =>
      assert_true(
        contains_sub_l(r, "max? : Int") && contains_sub_l(r, "ui-text"),
      )
    None => assert_true(false)
  }
  // 属性补全：签名全参数（不只是位置参数）
  match lsp_handle(docs, req(17, "textDocument/completion", pos_params(uri, 6, 23))).reply {
    Some(r) =>
      assert_true(
        contains_sub_l(r, "\"label\":\"max\"") &&
        contains_sub_l(r, "\"detail\":\"max? : Int = 0\""),
      )
    None => assert_true(false)
  }
}

///|
test "LSP：<style> 令牌与属性名补全、错误坐标回到模板行" {
  let docs : Map[String, String] = Map([])
  let uri = "file:///tmp/lsp_style_wbtest.mng"
  let text = [
    "<template>",
    "  <ui-col class=\"card\" />",
    "</template>",
    "<style>",
    ".card {",
    "  color: var(--tex",
    "  font-si",
    "}",
    "</style>",
  ].join("\n") + "\n"
  let _ = lsp_handle(docs, did_open(uri, text))
  // `var(--tex` → 令牌补全（已写 `--`，标签不再带前缀）
  match lsp_handle(docs, req(20, "textDocument/completion", pos_params(uri, 5, 18))).reply {
    Some(r) =>
      assert_true(
        contains_sub_l(r, "\"label\":\"text_primary\"") &&
        contains_sub_l(r, "\"kind\":21"),
      )
    None => assert_true(false)
  }
  // `var(` 裸写 → 标签带 `--`
  match lsp_handle(docs, req(21, "textDocument/completion", pos_params(uri, 5, 13))).reply {
    Some(r) => assert_true(contains_sub_l(r, "\"label\":\"--text_primary\""))
    None => assert_true(false)
  }
  // 属性名位 → kebab 名 + 整段 textEdit
  match lsp_handle(docs, req(22, "textDocument/completion", pos_params(uri, 6, 9))).reply {
    Some(r) =>
      assert_true(
        contains_sub_l(r, "\"label\":\"font-size\"") &&
        contains_sub_l(r, "\"newText\":\"font-size\""),
      )
    None => assert_true(false)
  }
}

///|
test "LSP：指令悬浮不再当组件；提示文案随 locale 中英切换" {
  let docs : Map[String, String] = Map([])
  let uri = "file:///tmp/lsp_hover_i18n.mng"
  let text = [
    "<script setup lang=\"moonbit\">",
    "let qty : @base.Store[Int] = @base.Store::new(0)",
    "</script>",
    "<template>",
    "  <ui-stepper v-model=\"qty\" max=\"10\" />",
    "</template>",
  ].join("\n") + "\n"
  let _ = lsp_handle(docs, did_open(uri, text))
  // 默认中文：v-model 是指令说明，不再报成自定义组件
  match lsp_handle(docs, req(30, "textDocument/hover", pos_params(uri, 4, 16))).reply {
    Some(r) =>
      assert_true(contains_sub_l(r, "双向绑定") && !contains_sub_l(r, "自定义组件"))
    None => assert_true(false)
  }
  // locale=en → 英文
  let _ = lsp_handle(docs, req(31, "initialize", "{\"locale\":\"en-US\"}"))
  match lsp_handle(docs, req(32, "textDocument/hover", pos_params(uri, 4, 16))).reply {
    Some(r) => assert_true(contains_sub_l(r, "two-way binding"))
    None => assert_true(false)
  }
  match lsp_handle(docs, req(33, "textDocument/hover", pos_params(uri, 4, 6))).reply {
    Some(r) =>
      assert_true(contains_sub_l(r, "ui-stepper") && contains_sub_l(r, "params:"))
    None => assert_true(false)
  }
  lsp_locale[0] = ""
}

///|
/// 从 reply 里抠 "data":[ 整数数组（测试用极简抠法）。
fn sem_wb_data(reply : String) -> Array[Int] {
  let out : Array[Int] = []
  let a = chars_of_cli(reply)
  let key = chars_of_cli("\"data\":[")
  let n = a.length()
  let m = key.length()
  let mut start = -1
  let mut i = 0
  while i + m <= n {
    let mut ok = true
    for k in 0..<m {
      if a[i + k] != key[k] {
        ok = false
      }
    }
    if ok {
      start = i + m
      break
    }
    i += 1
  }
  if start < 0 {
    return out
  }
  let mut cur = ""
  let mut j = start
  while j < n && a[j] != ']' {
    let c = a[j]
    if c == ',' {
      match parse_uint(cur) {
        Some(v) => out.push(v)
        None => ()
      }
      cur = ""
    } else {
      cur = cur + c.to_string()
    }
    j += 1
  }
  match parse_uint(cur) {
    Some(v) => out.push(v)
    None => ()
  }
  out
}

///|
/// delta 数据还原扫描：是否存在覆盖 `word` 的令牌（返回档位，无则 -1）。
fn sem_wb_ty(text : String, data : Array[Int], word : String) -> Int {
  let starts : Array[Int] = [0]
  let a = chars_of_cli(text)
  for k, c in a {
    if c == '\n' {
      starts.push(k + 1)
    }
  }
  let mut pl = 0
  let mut pc = 0
  let mut k = 0
  while k + 4 < data.length() {
    let dl = data[k]
    let line = pl + dl
    let ch = if dl == 0 { pc + data[k + 1] } else { data[k + 1] }
    let len = data[k + 2]
    let ty = data[k + 3]
    let off = starts[line] + ch
    if off + len <= a.length() && slice_cli(a, off, off + len) == word {
      return ty
    }
    pl = line
    pc = ch
    k += 5
  }
  -1
}

///|
test "LSP：semanticTokens/full 能力声明、分档与 delta 编码" {
  let docs : Map[String, String] = Map([])
  let uri = "file:///tmp/lsp_sem.mng"
  let text = tpl_ok()
  let _ = docs.set(uri, text)
  // 握手带 semanticTokensProvider 与标准 legend
  let init = lsp_handle(docs, req(1, "initialize", "{}"))
  match init.reply {
    Some(r) =>
      assert_true(
        contains_sub_l(r, "semanticTokensProvider") &&
        contains_sub_l(r, "\"parameter\"") &&
        contains_sub_l(r, "\"defaultLibrary\""),
      )
    None => assert_true(false)
  }
  let out = lsp_handle(
    docs,
    req(
      2,
      "textDocument/semanticTokens/full",
      "{\"textDocument\":{\"uri\":\"" + uri + "\"}}",
    ),
  )
  let reply = match out.reply {
    Some(r) => r
    None => ""
  }
  let data = sem_wb_data(reply)
  assert_true(data.length() > 0 && data.length() % 5 == 0)
  // let 绑定与插值里的状态名 → variable；类型 / 命名空间照档
  assert_eq(sem_wb_ty(text, data, "qty"), 8)
  assert_eq(sem_wb_ty(text, data, "Store"), 1)
  assert_eq(sem_wb_ty(text, data, "@base"), 0)
  // class 值与 CSS var 不走语义令牌（维持 TextMate）
  assert_eq(sem_wb_ty(text, data, "card"), -1)
  assert_eq(sem_wb_ty(text, data, "text_primary"), -1)
  // 未知 uri → 空 data
  let miss = lsp_handle(
    docs,
    req(
      3,
      "textDocument/semanticTokens/full",
      "{\"textDocument\":{\"uri\":\"file:///tmp/none.mng\"}}",
    ),
  )
  match miss.reply {
    Some(r) => assert_true(contains_sub_l(r, "\"data\":[]"))
    None => assert_true(false)
  }
}
