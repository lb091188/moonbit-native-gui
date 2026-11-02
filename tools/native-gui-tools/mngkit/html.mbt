// .mng 解析器：顶层 <script setup lang="moonbit"> + <template> 单根树。
// 手写递归下降，全程带行列坐标；不支持实体与 CDATA（v1 记档）。

///|
priv struct Cur {
  cs : Array[Char]
  mut i : Int
  starts : Array[Int]
}

///|
fn make_cur(src : String) -> Cur {
  let cs = chars_of(src)
  let starts = [0]
  for k, c in cs {
    if c == '\n' {
      starts.push(k + 1)
    }
  }
  { cs, i: 0, starts }
}

///|
fn pos_at(c : Cur, idx : Int) -> Pos {
  let mut line = 0
  while line + 1 < c.starts.length() && c.starts[line + 1] <= idx {
    line += 1
  }
  { line: line + 1, col: idx - c.starts[line] + 1 }
}

///|
fn cur_eof(c : Cur) -> Bool {
  c.i >= c.cs.length()
}

///|
fn cur_peek(c : Cur) -> Char {
  c.cs[c.i]
}

///|
fn cur_err(c : Cur, msg : String) -> String {
  "\{pos_str(pos_at(c, c.i))}：\{msg}"
}

///|
fn skip_ws(c : Cur) -> Unit {
  while !cur_eof(c) {
    let ch = cur_peek(c)
    if ch == ' ' || ch == '\t' || ch == '\n' || ch == '\r' {
      c.i += 1
    } else {
      break
    }
  }
}

///|
fn expect(c : Cur, ch : Char, what : String) -> Result[Unit, String] {
  if cur_eof(c) || cur_peek(c) != ch {
    Err(cur_err(c, "期望「\{ch}」（\{what}）"))
  } else {
    c.i += 1
    Ok(())
  }
}

///|
fn read_while(c : Cur, pred : (Char) -> Bool) -> String {
  let start = c.i
  while !cur_eof(c) && pred(cur_peek(c)) {
    c.i += 1
  }
  c.cs[start:c.i].map(fn(ch) { ch.to_string() }).join("")
}

///|
priv struct Sfc {
  script : String
  script_line0 : Int
  roots : Array[TNode]
  style : String
  style_line0 : Int
}

///|
fn read_tag_name(c : Cur) -> String {
  read_while(c, fn(ch) { is_ident_char(ch) || ch == '-' })
}

///|
fn attr_kind_of(name : String) -> (AttrKind, String) {
  if name == "v-model" {
    (Model, "")
  } else if name == "v-if" {
    (If, "")
  } else if name == "v-else-if" {
    (ElseIf, "")
  } else if name == "v-else" {
    (Else, "")
  } else if name == "v-show" {
    (Show, "")
  } else if name == "v-for" {
    (For, "")
  } else if name == "key" || name == ":key" {
    (Key, "")
  } else if name.has_prefix(":") {
    (Dyn, name[1:].to_owned())
  } else if name.has_prefix("@") {
    (Event, name[1:].to_owned())
  } else {
    (Plain, name)
  }
}

///|
fn parse_attr(c : Cur) -> Result[Attr, String] {
  let pos = pos_at(c, c.i)
  let name = read_while(c, fn(ch) { is_ident_char(ch) || ch == ':' || ch == '@' || ch == '-' })
  if name.length() == 0 {
    return Err(cur_err(c, "属性名非法"))
  }
  skip_ws(c)
  let (kind, bare) = attr_kind_of(name)
  if cur_eof(c) || cur_peek(c) != '=' {
    return Ok({ kind, name: bare, value: "", has_value: false, pos })
  }
  c.i += 1
  skip_ws(c)
  if cur_eof(c) || (cur_peek(c) != '"' && cur_peek(c) != '\'') {
    return Err(cur_err(c, "属性值要以引号包裹"))
  }
  let quote = cur_peek(c)
  c.i += 1
  // 值内允许 `\<外层引号>` 转义（原样保留反斜杠，MoonBit 侧照吃）
  let out = StringBuilder()
  while !cur_eof(c) {
    let ch = cur_peek(c)
    if ch == '\\' && c.i + 1 < c.cs.length() && c.cs[c.i + 1] == quote {
      out.write_char('\\')
      out.write_char(quote)
      c.i += 2
      continue
    }
    if ch == quote {
      break
    }
    out.write_char(ch)
    c.i += 1
  }
  if cur_eof(c) {
    return Err(cur_err(c, "属性值引号未闭合"))
  }
  let raw_value = out.to_string()
  c.i += 1
  // 表达式属性里 JS 习惯的单引号串在编译期换成双引号串（单字符 Char 不动）
  let value = match kind {
    Dyn | Event | Model | If | ElseIf | Show | For => requote_expr(raw_value)
    _ => raw_value
  }
  Ok({ kind, name: bare, value, has_value: true, pos })
}

///|
fn parse_elem(c : Cur) -> Result[TNode, String] {
  let pos = pos_at(c, c.i)
  let _ = expect(c, '<', "标签开始")
  let tag = read_tag_name(c)
  if tag.length() == 0 {
    return Err(cur_err(c, "标签名缺失"))
  }
  let attrs : Array[Attr] = []
  let mut selfclose = false
  while true {
    skip_ws(c)
    if cur_eof(c) {
      return Err(cur_err(c, "标签 <\{tag}> 未结束"))
    }
    let ch = cur_peek(c)
    if ch == '>' {
      c.i += 1
      break
    }
    if ch == '/' {
      c.i += 1
      let _ = expect(c, '>', "自闭合")
      selfclose = true
      break
    }
    match parse_attr(c) {
      Ok(a) => attrs.push(a)
      Err(e) => return Err(e)
    }
  }
  if selfclose {
    return Ok(Elem(tag, attrs, [], pos))
  }
  match parse_nodes(c, tag) {
    Ok(kids) => Ok(Elem(tag, attrs, kids, pos))
    Err(e) => Err(e)
  }
}

///|
/// 解析到 </stop> 为止；stop 为空串表示只到文件尾（不会发生：模板有闭标签）。
fn parse_nodes(c : Cur, stop : String) -> Result[Array[TNode], String] {
  let out : Array[TNode] = []
  while true {
    if cur_eof(c) {
      if stop.length() > 0 {
        return Err(cur_err(c, "缺少闭合标签 </\{stop}>"))
      }
      return Ok(out)
    }
    if cur_peek(c) == '<' {
      if c.i + 3 < c.cs.length() &&
        c.cs[c.i + 1] == '!' &&
        c.cs[c.i + 2] == '-' &&
        c.cs[c.i + 3] == '-' {
        // 注释跳过
        c.i += 4
        while !cur_eof(c) &&
          !(c.cs[c.i] == '-' && c.i + 2 < c.cs.length() && c.cs[c.i + 1] == '-' && c.cs[c.i + 2] == '>') {
          c.i += 1
        }
        if cur_eof(c) {
          return Err(cur_err(c, "注释未闭合"))
        }
        c.i += 3
        continue
      }
      if c.i + 1 < c.cs.length() && c.cs[c.i + 1] == '/' {
        c.i += 2
        let name = read_tag_name(c)
        skip_ws(c)
        let _ = expect(c, '>', "闭合标签")
        if name == stop {
          return Ok(out)
        }
        return Err(cur_err(c, "闭合标签 </\{name}> 与打开的 <\{stop}> 不匹配"))
      }
      match parse_elem(c) {
        Ok(n) => out.push(n)
        Err(e) => return Err(e)
      }
    } else {
      let start = c.i
      while !cur_eof(c) && cur_peek(c) != '<' {
        c.i += 1
      }
      let raw = c.cs[start:c.i].map(fn(ch) { ch.to_string() }).join("")
      // 纯空白的文本节点丢弃；含插值的保留（哪怕看起来是空白夹插值）。
      // 位置取首个非空白字符——映射回模板可读处，而不是上一行行尾。
      let mut meaningful = false
      let mut t = 0
      for k, ch in raw {
        if ch != ' ' && ch != '\t' && ch != '\n' && ch != '\r' {
          meaningful = true
          if t == 0 {
            t = k
          }
        }
      }
      if meaningful || has_interp(raw) {
        out.push(Text(raw, pos_at(c, start + t)))
      }
    }
  }
  // 所有出口都在循环体内 return；此处不可达
  abort("unreachable")
}

///|
/// 原文段读取（script / style）：从开标签 `>` 之后读到 `</名字`，返回内容与首行行号；
/// 调用结束时游标停在闭标签之后。
fn read_raw(c : Cur, name : String) -> Result[(String, Int), String] {
  let content_start = c.i
  let line0 = pos_at(c, c.i).line
  let nm = chars_of(name)
  let n = c.cs.length()
  let mut end = c.i
  let mut found = false
  while end + 2 + nm.length() <= n {
    if c.cs[end] == '<' && c.cs[end + 1] == '/' {
      let mut k = 0
      let mut same = true
      while k < nm.length() {
        if c.cs[end + 2 + k] != nm[k] {
          same = false
        }
        k += 1
      }
      if same {
        found = true
        break
      }
    }
    end += 1
  }
  if !found {
    return Err(cur_err(c, "缺 </\{name}>"))
  }
  let content = c.cs[content_start:end].map(fn(ch) { ch.to_string() }).join("")
  c.i = end + 2
  let _ = read_tag_name(c)
  skip_ws(c)
  match expect(c, '>', "闭标签") {
    Ok(_) => ()
    Err(e) => return Err(e)
  }
  Ok((content, line0))
}

///|
/// 顶层扫描：找出 script、template 与可选 style 三块。
fn parse_sfc(src : String) -> Result[Sfc, String] {
  let c = make_cur(src)
  let mut script = ""
  let mut script_line0 = 0
  let mut style = ""
  let mut style_line0 = 0
  let mut roots : Array[TNode] = []
  let mut got_template = false
  while true {
    skip_ws(c)
    if cur_eof(c) {
      break
    }
    let _ = expect(c, '<', "顶层标签")
    let name = read_tag_name(c)
    if name == "script" || name == "style" {
      // 吃掉属性直到 '>'
      while !cur_eof(c) && cur_peek(c) != '>' {
        c.i += 1
      }
      let _ = expect(c, '>', name + " 开标签")
      match read_raw(c, name) {
        Ok((content, ln)) => {
          if name == "script" {
            script = content
            script_line0 = ln
          } else {
            style = content
            style_line0 = ln
          }
        }
        Err(e) => return Err(e)
      }
    } else if name == "template" {
      while !cur_eof(c) && cur_peek(c) != '>' {
        c.i += 1
      }
      let _ = expect(c, '>', "template 开标签")
      match parse_nodes(c, "template") {
        Ok(r) => {
          roots = r
          got_template = true
        }
        Err(e) => return Err(e)
      }
    } else {
      return Err(cur_err(c, "顶层只允许 <script setup>、<template> 与 <style>，见到 <\{name}>"))
    }
  }
  if !got_template {
    return Err("缺 <template> 段")
  }
  Ok({ script, script_line0, roots, style, style_line0 })
}
