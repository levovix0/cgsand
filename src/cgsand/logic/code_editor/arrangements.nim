import std/[unicode, sequtils, sets, strutils, algorithm]
import pkg/[vmath, bumpy]
import pkg/sigui/[rendering]
import ./[syntax_highlighting]


type
  SelectionMode* = enum
    LineSelection
    BlockSelection


  CodeArrangementLine* = ref object
    rect*: Rect
      ## visual rect of a line in pixels, relative to top-left courner of whole CodeArrangement
      ## .xy recalculated on updateRects

    runes*: seq[Rune]
      ## actual text of this line of the file

    arrangement*: Arrangement

    kinds*: seq[CodeKind]
      ## syntax highlighting for a line of code, per rune

    syntaxValid*: bool
      ## false for a newly inserted line until updateSyntaxFrom processes it

    indentOffsets*: seq[int]
      ## virtual-column positions of each indent-level boundary inside this line (e.g. [2, 4, 8])
      ## recalculated on updateIndentOffsets

    foldable*: bool
      ## is the line a "header" of an indented block
      ## recalculated on updateRects

    isHidden*: bool
      ## true if the line is a part of folded block
      ## recalculated on updateRects

    parseEndState*: NimParseState
      ## parse state at end of this line
      ## used to derive next line's start state for incremental highlighting


  CursorPos* = object
    line*, col*: int

    snapCol*: int
      ## when cursor is at end of the line, then moved up to a smaller line, then moved again to same size line,
      ## cursor will be at the end of the line (at snapCol), instead of at [prev line len]-th position
      ## snapCol is preserved on vertical movement, reset on horizontal movement

    isDuplicate*: bool
      ## when, for example, multiple cursors moved to the empty line
      ## if cursor isDuplicate, it should not participate in text editing, but still be available if cursors is then moved
      ## recalculated on collapseDuplicatedCursors

    hasSelection*: bool
    anchorLine*, anchorCol*: int
      ## the start of the selection (end is at regular line:col)


  CodeArrangement* = ref object
    lines*: seq[CodeArrangementLine]
    foldedLines*: HashSet[int]
    cursors*: seq[CursorPos]
    font*: Font
    selectionMode*: SelectionMode
    width*: float32

    # changed since last finishEdit
    changed_minLine*: int

  CodeArrangementSnapshot* = object
    text*: string
    cursors*: seq[CursorPos]
    foldedLines*: seq[int]
    selectionMode*: SelectionMode



proc lineHeightPixels*(font: Font): float32 =
  font.size * ((font.typeface.ascent / font.typeface.scale) + max(font.typeface.lineGap / font.typeface.scale, 0.25))



proc fileContent*(cf: CodeArrangement): string =
  for i, line in cf.lines:
    if i != 0: result.add "\n"
    result.add $line.runes


proc snapshot*(arrangement: CodeArrangement): CodeArrangementSnapshot =
  result.text = arrangement.fileContent()
  result.selectionMode = arrangement.selectionMode
  for cursor in arrangement.cursors:
    result.cursors.add cursor
  for lineI in arrangement.foldedLines:
    result.foldedLines.add lineI

proc writeCodeFile*(filename: string, v: CodeArrangement) =
  writeFile filename, v.fileContent



proc indent*(line: CodeArrangementLine): int =
  ## returns number of spaces in indent of the line
  for r in line.runes:
    if r == Rune(' '): inc result
    elif r == Rune('\t'): result += 2
    else: break

proc isEmpty*(line: CodeArrangementLine): bool =
  ## returns true if line contains only whitespace
  for r in line.runes:
    if not r.isWhiteSpace: return false
  return true


proc visibleRect*(line: CodeArrangementLine): Rect =
  var minX = float32.high
  var maxX = float32.low
  for i, r in line.arrangement.runes:
    if not r.isWhiteSpace:
      minX = min(minX, line.arrangement.selectionRects[i].x)
      maxX = max(maxX, line.arrangement.selectionRects[i].x + line.arrangement.selectionRects[i].w)
  if minX == float32.high: return line.rect
  rect(minX, line.rect.y, maxX - minX, line.rect.h)



proc updateRects*(arrangement: CodeArrangement) =
  var foldStack: seq[int] = @[]
  var y = 0'f32

  for i, line in arrangement.lines:
    if not line.isEmpty:
      while foldStack.len > 0 and line.indentOffsets.len <= foldStack[^1]:
        discard foldStack.pop()

    if line.isEmpty and foldStack.len > 0:
      var nextIndent = -1
      for j in i+1 ..< arrangement.lines.len:
        if not arrangement.lines[j].isEmpty:
          nextIndent = arrangement.lines[j].indentOffsets.len
          break
      line.isHidden = nextIndent > foldStack[^1]
    else:
      line.isHidden = foldStack.len > 0

    line.rect = rect(vec2(0, y), line.rect.wh)

    if not line.isHidden:
      y += line.arrangement.lines.len.max(1).float32 * arrangement.font.lineHeightPixels
      if i in arrangement.foldedLines and line.foldable:
        foldStack.add line.indentOffsets.len


proc visibleHeight*(arrangement: CodeArrangement): float32 =
  for line in arrangement.lines:
    if not line.isHidden:
      result += line.arrangement.lines.len.max(1).float32 * arrangement.font.lineHeightPixels


proc toggleFold*(arrangement: CodeArrangement, lineI: int) =
  if lineI >= arrangement.lines.len: return
  if not arrangement.lines[lineI].foldable: return
  if lineI in arrangement.foldedLines:
    arrangement.foldedLines.excl lineI
  else:
    arrangement.foldedLines.incl lineI
  arrangement.updateRects()


proc colToPos*(line: CodeArrangementLine, col: int): Vec2 =
  if line.arrangement.selectionRects.len == 0:
    vec2()
  elif col < line.arrangement.selectionRects.len:
    line.arrangement.selectionRects[col].xy
  else:
    line.arrangement.selectionRects[^1].xy + vec2(line.arrangement.selectionRects[^1].w, 0)

proc posToCol*(line: CodeArrangementLine, pos: Vec2): int =
  for lineI, span in line.arrangement.lines:
    for i in span[0]..span[1]:
      let r = line.arrangement.selectionRects[i]
      if (
        (lineI == 0 or pos.y >= r.y) and
        (lineI == line.arrangement.lines.high or pos.y <= (r.y + r.h)) and
        pos.x < r.x + r.w / 2
      ): return i
  return line.arrangement.selectionRects.len


proc prevVisibleLine*(arrangement: CodeArrangement, lineI: int): int =
  result = lineI
  for i in countdown(lineI - 1, 0):
    if not arrangement.lines[i].isHidden: return i

proc nextVisibleLine*(arrangement: CodeArrangement, lineI: int): int =
  result = lineI
  for i in lineI + 1 ..< arrangement.lines.len:
    if not arrangement.lines[i].isHidden: return i


proc collapseDuplicatedCursors*(arrangement: CodeArrangement) =
  arrangement.cursors = deduplicate arrangement.cursors
  var positions: HashSet[tuple[line, col: int]]
  for c in arrangement.cursors.mitems:
    c.isDuplicate = (c.line, c.col) in positions
    positions.incl (c.line, c.col)



proc sortedCursorIndices*(arr: CodeArrangement): seq[int] =
  var order: seq[tuple[line, col, idx: int]]
  for i, c in arr.cursors:
    if not c.isDuplicate:
      order.add (c.line, c.col, i)
  order.sort(SortOrder.Descending)
  result = order.mapIt(it.idx)


proc prepareExtend(arrangement: CodeArrangement, c: var CursorPos, extend: bool) =
  if extend:
    if not c.hasSelection:
      c.anchorLine = c.line
      c.anchorCol = c.col
      c.hasSelection = true
  else:
    c.hasSelection = false

proc moveCursorLeft*(arrangement: CodeArrangement, cursorIdx: int, extend: bool = false, prevWord: bool = false) =
  var c = arrangement.cursors[cursorIdx]
  prepareExtend(arrangement, c, extend)
  
  if c.col > 0:
    dec c.col
    if prevWord:
      while c.col > 0 and not arrangement.lines[c.line].arrangement.runes[c.col - 1].isWhiteSpace:
        dec c.col
  elif c.line > 0:
    let prev = arrangement.prevVisibleLine(c.line)
    if prev != c.line:
      c.line = prev
      c.col = arrangement.lines[prev].arrangement.runes.len
  c.snapCol = c.col
  arrangement.cursors[cursorIdx] = c

proc moveCursorRight*(arrangement: CodeArrangement, cursorIdx: int, extend: bool = false, nextWord: bool = false) =
  var c = arrangement.cursors[cursorIdx]
  prepareExtend(arrangement, c, extend)

  let lineLen = arrangement.lines[c.line].arrangement.runes.len
  if c.col < lineLen:
    inc c.col
    if nextWord:
      while c.col < lineLen and not arrangement.lines[c.line].arrangement.runes[c.col].isWhiteSpace:
        inc c.col
  else:
    let next = arrangement.nextVisibleLine(c.line)
    if next != c.line:
      c.line = next
      c.col = 0
  c.snapCol = c.col
  arrangement.cursors[cursorIdx] = c

proc moveCursorUp*(arrangement: CodeArrangement, cursorIdx: int, extend: bool = false) =
  var c = arrangement.cursors[cursorIdx]
  prepareExtend(arrangement, c, extend)

  let prev = arrangement.prevVisibleLine(c.line)
  if prev != c.line:
    let prevLineLen = arrangement.lines[prev].arrangement.runes.len
    c.line = prev
    c.col = min(c.snapCol, prevLineLen)
  arrangement.cursors[cursorIdx] = c

proc moveCursorDown*(arrangement: CodeArrangement, cursorIdx: int, extend: bool = false) =
  var c = arrangement.cursors[cursorIdx]
  prepareExtend(arrangement, c, extend)

  let next = arrangement.nextVisibleLine(c.line)
  if next != c.line:
    let nextLineLen = arrangement.lines[next].arrangement.runes.len
    c.line = next
    c.col = min(c.snapCol, nextLineLen)
  arrangement.cursors[cursorIdx] = c

proc moveCursorHome*(arrangement: CodeArrangement, cursorIdx: int, extend: bool = false) =
  var c = arrangement.cursors[cursorIdx]
  prepareExtend(arrangement, c, extend)

  var indentEnd = 0
  for c in arrangement.lines[c.line].runes:
    if c.isWhiteSpace():
      inc indentEnd
    else: break
  
  if c.col > indentEnd:
    c.col = indentEnd
  else:
    c.col = 0
  
  arrangement.cursors[cursorIdx] = c

proc moveCursorEnd*(arrangement: CodeArrangement, cursorIdx: int, extend: bool = false) =
  var c = arrangement.cursors[cursorIdx]
  prepareExtend(arrangement, c, extend)

  c.col = arrangement.lines[c.line].arrangement.runes.len
  arrangement.cursors[cursorIdx] = c


proc moveCursorLeft*(arrangement: CodeArrangement, extend: bool = false, prevWord: bool = false) =
  for i in 0..<arrangement.cursors.len:
    moveCursorLeft(arrangement, i, extend, prevWord)
  arrangement.collapseDuplicatedCursors()

proc moveCursorRight*(arrangement: CodeArrangement, extend: bool = false, nextWord: bool = false) =
  for i in 0..<arrangement.cursors.len:
    moveCursorRight(arrangement, i, extend, nextWord)
  arrangement.collapseDuplicatedCursors()

proc moveCursorUp*(arrangement: CodeArrangement, extend: bool = false) =
  for i in 0..<arrangement.cursors.len:
    moveCursorUp(arrangement, i, extend)
  arrangement.collapseDuplicatedCursors()

proc moveCursorDown*(arrangement: CodeArrangement, extend: bool = false) =
  for i in 0..<arrangement.cursors.len:
    moveCursorDown(arrangement, i, extend)
  arrangement.collapseDuplicatedCursors()

proc moveCursorHome*(arrangement: CodeArrangement, extend: bool = false) =
  for i in 0..<arrangement.cursors.len:
    moveCursorHome(arrangement, i, extend)
  arrangement.collapseDuplicatedCursors()

proc moveCursorEnd*(arrangement: CodeArrangement, extend: bool = false) =
  for i in 0..<arrangement.cursors.len:
    moveCursorEnd(arrangement, i, extend)
  arrangement.collapseDuplicatedCursors()


proc setCursorPos*(arrangement: CodeArrangement, line, col: int, append = false) =
  if append:
    var i = arrangement.cursors.findIt(it.line == line and it.col == col)
    if i == -1:
      arrangement.cursors.add CursorPos(line: line, col: col, snapCol: col, anchorLine: line, anchorCol: col)
    else:
      while i != -1:
        arrangement.cursors.delete i
        i = arrangement.cursors.findIt(it.line == line and it.col == col)

  else:
    arrangement.cursors = @[CursorPos(line: line, col: col, snapCol: col, anchorLine: line, anchorCol: col)]


# --- incremental arrangement update ---

proc typesetWithIndent*(font: Font, width: float32, line: CodeArrangementLine) =
  ## Typeset line.runes with hanging-indent wrapping:
  ## measures the leading-whitespace pixel width (indentX), then re-typesets
  ## at (width - indentX) and shifts all continuation rows right by indentX
  ## so wrapped content aligns with the line's own indent level.
  var indentRunes = 0
  for r in line.runes:
    if r == Rune(' ') or r == Rune('\t'): inc indentRunes
    else: break

  line.arrangement = typeset(font, $line.runes, bounds = vec2(width, 0))

  if line.arrangement.lines.len <= 1 or indentRunes == 0 or
      indentRunes >= line.runes.len:
    return

  let sr = line.arrangement.selectionRects
  let indentX = sr[indentRunes - 1].x + sr[indentRunes - 1].w

  line.arrangement = typeset(font, $line.runes, bounds = vec2((width - indentX).max(1'f32), 0))

  for rowIdx in 1 ..< line.arrangement.lines.len:
    let span = line.arrangement.lines[rowIdx]
    for i in span[0] .. span[1]:
      line.arrangement.selectionRects[i].x += indentX


proc refreshArrangementLine*(arr: CodeArrangement, lineI: int) =
  ## Rebuild typeset and basic metadata for a single line in-place
  let line = arr.lines[lineI]
  typesetWithIndent(arr.font, arr.width, line)
  let rowCount = line.arrangement.lines.len.max(1)
  line.rect = rect(
    0, line.rect.y, line.arrangement.layoutBounds.x,
    rowCount.float32 * arr.font.lineHeightPixels
  )


proc updateSyntaxFrom*(arr: CodeArrangement, startLineI: int) =
  ## Incrementally re-highlight from startLineI forward. Structural edits can
  ## introduce new lines with no previous syntax data; those lines must all be
  ## processed before the stable-state early exit is allowed.
  var lastInvalidLine = startLineI
  for i in countdown(arr.lines.high, startLineI):
    if not arr.lines[i].syntaxValid:
      lastInvalidLine = i
      break

  for i in startLineI ..< arr.lines.len:
    let startState =
      if i == 0: NimParseState()
      else: nextLineParseState(arr.lines[i - 1].parseEndState)

    let line = arr.lines[i]
    let wasSyntaxValid = line.syntaxValid
    let oldEndState = line.parseEndState
    let res = parseNimCode(line.runes, startState, line.runes.len)
    line.kinds = res.segments
    line.parseEndState = res.state
    line.syntaxValid = true

    if i > startLineI and i >= lastInvalidLine and wasSyntaxValid and
        nextLineParseState(res.state) == nextLineParseState(oldEndState):
      break


proc updateFoldable*(arr: CodeArrangement) =
  ## Recompute foldable flags for all lines
  for i in 0 ..< arr.lines.len:
    arr.lines[i].foldable = false
    if arr.lines[i].isEmpty: continue
    let myIndent = arr.lines[i].indentOffsets.len
    for j in i + 1 ..< arr.lines.len:
      if arr.lines[j].isEmpty: continue
      if arr.lines[j].indentOffsets.len > myIndent:
        arr.lines[i].foldable = true
      break


proc updateIndentOffsets*(arr: CodeArrangement) =
  ## Rebuild indentOffsets for every line using a virtual-column indent stack.
  ## Each entry is the LEFT edge of an indent block (= column where the parent
  ## level's content starts), so guide lines appear on the left side of the indent.
  ## Empty lines initially inherit the stack; a second pass trims guides that
  ## belong to blocks that have already closed before the empty line.
  var stack: seq[int] = @[0]
  for line in arr.lines:
    if not line.isEmpty:
      let vi = indent(line)
      if vi > stack[^1]:
        stack.add vi
      elif vi < stack[^1]:
        while stack.len > 1 and stack[^1] > vi:
          discard stack.pop()
        if stack[^1] != vi:
          stack.add vi
    line.indentOffsets = if stack.len > 1: stack[0 .. stack.high - 1] else: @[]

  for i, line in arr.lines:
    if not line.isEmpty: continue
    var nextLen = 0
    for j in i + 1 ..< arr.lines.len:
      if not arr.lines[j].isEmpty:
        nextLen = arr.lines[j].indentOffsets.len
        break
    if nextLen < line.indentOffsets.len:
      line.indentOffsets = line.indentOffsets[0 ..< nextLen]


# --- constructor ---

proc toArrangement*(text: string, font: Font, width: float32): CodeArrangement =
  result = CodeArrangement(font: font, width: width)

  var parseState = NimParseState()
  for line in text.splitLines:
    var cline = CodeArrangementLine()
    let parsed = parseNimCode(line.toRunes, parseState, line.runeLen)
    cline.runes = line.toRunes
    cline.kinds = parsed.segments
    cline.parseEndState = parsed.state
    cline.syntaxValid = true
    typesetWithIndent(font, width, cline)
    cline.rect = rect(0, 0, cline.arrangement.layoutBounds.x, cline.arrangement.lines.len.max(1).float32 * font.lineHeightPixels)
    parseState = nextLineParseState(parsed.state)
    result.lines.add cline

  result.updateIndentOffsets()
  result.updateFoldable()
  result.cursors = @[CursorPos()]
  result.updateRects()


proc toArrangement*(snapshot: CodeArrangementSnapshot, font: Font, width: float32): CodeArrangement =
  result = snapshot.text.toArrangement(font, width)
  result.selectionMode = snapshot.selectionMode
  result.cursors.setLen(0)
  for cursor in snapshot.cursors:
    result.cursors.add cursor
  if result.cursors.len == 0:
    result.cursors.add CursorPos()
  for lineI in snapshot.foldedLines:
    if lineI >= 0 and lineI < result.lines.len:
      result.foldedLines.incl lineI
  result.updateRects()
