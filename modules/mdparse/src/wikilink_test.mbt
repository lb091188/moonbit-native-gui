///|
/// WikiLink extension tests
test "wikilinks stay literal by default" {
  let inlines = parse_inlines("See [[MoonBit]]")
  @debug.debug_inspect(inlines.length(), content="1")
  match inlines[0] {
    Inline::Text(content~, ..) =>
      @debug.debug_inspect(
        content,
        content=(
          #|"See [[MoonBit]]"
        ),
      )
    _ => fail("Expected literal Text")
  }
}

///|
test "parse wikilink when enabled" {
  let inlines = parse_inlines("See [[MoonBit]]", wikilinks=true)
  @debug.debug_inspect(inlines.length(), content="2")
  match inlines[1] {
    Inline::WikiLink(target~, label~, fragment~, ..) => {
      @debug.debug_inspect(
        target,
        content=(
          #|"MoonBit"
        ),
      )
      @debug.debug_inspect(
        label,
        content=(
          #|""
        ),
      )
      @debug.debug_inspect(
        fragment,
        content=(
          #|""
        ),
      )
    }
    _ => fail("Expected WikiLink")
  }
}

///|
test "parse wikilink label and fragment" {
  let inlines = parse_inlines(
    "[[MoonBit#syntax|MoonBit syntax]]",
    wikilinks=true,
  )
  @debug.debug_inspect(inlines.length(), content="1")
  match inlines[0] {
    Inline::WikiLink(target~, label~, fragment~, ..) => {
      @debug.debug_inspect(
        target,
        content=(
          #|"MoonBit"
        ),
      )
      @debug.debug_inspect(
        label,
        content=(
          #|"MoonBit syntax"
        ),
      )
      @debug.debug_inspect(
        fragment,
        content=(
          #|"syntax"
        ),
      )
    }
    _ => fail("Expected WikiLink")
  }
}

///|
test "wikilink label and target" {
  let result = parse("[[MoonBit#syntax|MoonBit syntax]]\n", wikilinks=true)
  guard result.document.children[0] is Paragraph(children~, ..) else {
    fail("Expected paragraph")
  }
  guard children[0] is WikiLink(label~, ..) else {
    fail("Expected WikiLink")
  }
  inspect(label, content="MoonBit syntax")
}
