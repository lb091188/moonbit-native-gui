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
