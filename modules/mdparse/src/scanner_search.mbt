///| Stateless string-search primitives used by the Markdown scanners.

///|
#inline
fn find_line_end_scalar(source : String, start : Int, end : Int) -> Int {
  for pos in start..<end {
    let c = source.unsafe_get(pos)
    if c == '\n' || c == '\r' {
      break pos
    }
  } nobreak {
    end
  }
}

///|
/// 查找行尾：从 start 起逐个 UTF-16 单元找 CR/LF，找不到返回 end。
#inline
fn find_line_end(source : String, start : Int, end : Int) -> Int {
  find_line_end_scalar(source, start, end)
}

///| Find a substring at or after `start`, returning its absolute start offset.

///|
/// `StringView::find` uses MoonBit core's SIMD scanner for linear-memory
/// targets, while keeping the JavaScript fallback optimized for that backend.
#inline
fn find_exact_from(text : String, start : Int, needle : StringView) -> Int? {
  guard start >= 0 && start <= text.length() else { return None }
  match text[start:].find(needle) {
    Some(relative) => Some(start + relative)
    None => None
  }
}

///|
/// Find a substring and return its absolute end offset.
#inline
fn find_exact_end_from(text : String, start : Int, needle : StringView) -> Int? {
  match find_exact_from(text, start, needle) {
    Some(found) => Some(found + needle.length())
    None => None
  }
}
