// mcp 协议处理纯函数用例：三方法响应形态与 tools/call 参数校验。
// 不起真服务（tools/call 的连接错误档本身就是断言对象）。

///|
test "mcp_handle：initialize 回协议版本与 serverInfo" {
  let resp = mcp_handle(
    "libyue.demo",
    "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{}}",
  )
  let s = match resp {
    Some(s) => s
    None => fail("initialize 应有响应")
  }
  assert_true(s.contains("\"protocolVersion\""))
  assert_true(s.contains("\"serverInfo\""))
  assert_true(s.contains("\"id\":1"))
}

///|
test "mcp_handle：tools/list 三工具齐全" {
  let resp = mcp_handle(
    "libyue.demo",
    "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"tools/list\"}",
  )
  let s = match resp {
    Some(s) => s
    None => fail("tools/list 应有响应")
  }
  assert_true(s.contains("inspector_tree"))
  assert_true(s.contains("inspector_style"))
  assert_true(s.contains("inspector_shot"))
}

///|
test "mcp_handle：通知不回、未知方法回 -32601、坏 JSON 回 -32700" {
  assert_true(
    mcp_handle(
      "libyue.demo",
      "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}",
    ) is None,
  )
  let miss = mcp_handle(
    "libyue.demo",
    "{\"jsonrpc\":\"2.0\",\"id\":3,\"method\":\"no/such\"}",
  )
  let miss_hit = match miss {
    Some(s) => s.contains("-32601")
    None => false
  }
  assert_true(miss_hit)
  let bad = mcp_handle("libyue.demo", "{not json")
  let bad_hit = match bad {
    Some(s) => s.contains("-32700")
    None => false
  }
  assert_true(bad_hit)
}

///|
test "mcp_handle：tools/call 缺 id 回 isError 文本（服务不在场也不挂）" {
  let resp = mcp_handle(
    "libyue.demo",
    "{\"jsonrpc\":\"2.0\",\"id\":4,\"method\":\"tools/call\",\"params\":{\"name\":\"inspector_style\",\"arguments\":{}}}",
  )
  let s = match resp {
    Some(s) => s
    None => fail("tools/call 应有响应")
  }
  assert_true(s.contains("\"isError\":true"))
  assert_true(s.contains("id"))
}
