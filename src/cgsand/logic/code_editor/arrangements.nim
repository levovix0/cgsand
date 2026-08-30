import std/[unicode, sequtils, sets, algorithm, strutils]
import pkg/[vmath, bumpy]
import pkg/pixie/fonts
import ./[syntax_highlighting]
export CodeKind


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



proc lineHeightPixels*(font: Font): float32 =
  font.size * ((font.typeface.ascent / font.typeface.scale) + max(font.typeface.lineGap / font.typeface.scale, 0.25))



proc fileContent*(cf: CodeArrangement): string =
  for i, line in cf.lines:
    if i != 0: result.add "\n"
    result.add $line.runes

proc writeCodeFile*(filename: string, v: CodeArrangement) =
  writeFile filename, v.fileContent



proc indent(line: CodeArrangementLine): int =
  for r in line.runes:
    if r == Rune(' '): inc result
    elif r == Rune('\t'): result += 2
    else: break

proc isEmpty(line: CodeArrangementLine): bool =
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


proc selectionRangeForLine*(arrangement: CodeArrangement, cursorI: int, lineI: int): Slice[int] =
  let c = arrangement.cursors[cursorI]
  if not c.hasSelection: return 0..<0
  if lineI < 0 or lineI >= arrangement.lines.len: return 0..<0

  let lineLen = arrangement.lines[lineI].arrangement.runes.len
  let al = c.anchorLine
  let ac = c.anchorCol
  let cl = c.line
  let cc = c.col

  case arrangement.selectionMode
  of LineSelection:
    let minL = min(al, cl)
    let maxL = max(al, cl)
    if lineI < minL or lineI > maxL: return 0..<0
    if al == cl:
      min(ac, cc)..max(ac, cc)
    elif al < cl:
      if lineI == al:
        ac..lineLen
      elif lineI == cl:
        0..cc
      else:
        0..lineLen
    else:
      if lineI == cl:
        cc..lineLen
      elif lineI == al:
        0..ac
      else:
        0..lineLen

  of BlockSelection:
    if lineI < min(al, cl) or lineI > max(al, cl): return 0..<0
    min(ac, cc)..max(ac, cc)


proc setSelection*(arrangement: CodeArrangement, cursorI: int, anchorLine, anchorCol, cursorLine, cursorCol: int) =
  if cursorI < 0 or cursorI >= arrangement.cursors.len: return
  var c = arrangement.cursors[cursorI]
  c.anchorLine = anchorLine
  c.anchorCol = anchorCol
  c.line = cursorLine
  c.col = cursorCol
  c.snapCol = cursorCol
  c.hasSelection = anchorLine != cursorLine or anchorCol != cursorCol
  arrangement.cursors[cursorI] = c


proc selectToPos*(arrangement: CodeArrangement, cursorI: int, mouseXy: Vec2) =
  if cursorI < 0 or cursorI >= arrangement.cursors.len: return

  var foundLine = -1
  var foundCol = 0
  var firstVisible = -1
  var lastVisible = -1

  for i, line in arrangement.lines:
    if line.isHidden: continue
    if firstVisible == -1: firstVisible = i
    lastVisible = i
    if mouseXy.y >= line.rect.y and mouseXy.y < line.rect.y + line.rect.h:
      foundLine = i
      foundCol = line.posToCol(vec2(mouseXy.x, mouseXy.y - line.rect.y))
      break

  if foundLine == -1 and firstVisible != -1:
    if mouseXy.y < arrangement.lines[firstVisible].rect.y:
      foundLine = firstVisible
      foundCol = 0
    else:
      foundLine = lastVisible
      foundCol = arrangement.lines[lastVisible].arrangement.runes.len

  if foundLine != -1 and cursorI < arrangement.cursors.len:
    arrangement.setSelection(
      cursorI,
      arrangement.cursors[cursorI].anchorLine, arrangement.cursors[cursorI].anchorCol,
      foundLine, foundCol,
    )


proc moveCursorLeft*(arrangement: CodeArrangement, cursorIdx: int, extend: bool = false, prevWord: bool = false) =
  var c = arrangement.cursors[cursorIdx]
  if extend:
    if not c.hasSelection:
      c.anchorLine = c.line
      c.anchorCol = c.col
      c.hasSelection = true
  else:
    c.hasSelection = false
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
  if extend:
    if not c.hasSelection:
      c.anchorLine = c.line
      c.anchorCol = c.col
      c.hasSelection = true
  else:
    c.hasSelection = false

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
  if extend:
    if not c.hasSelection:
      c.anchorLine = c.line
      c.anchorCol = c.col
      c.hasSelection = true
  else:
    c.hasSelection = false

  let prev = arrangement.prevVisibleLine(c.line)
  if prev != c.line:
    let prevLineLen = arrangement.lines[prev].arrangement.runes.len
    c.line = prev
    c.col = min(c.snapCol, prevLineLen)
  arrangement.cursors[cursorIdx] = c

proc moveCursorDown*(arrangement: CodeArrangement, cursorIdx: int, extend: bool = false) =
  var c = arrangement.cursors[cursorIdx]
  if extend:
    if not c.hasSelection:
      c.anchorLine = c.line
      c.anchorCol = c.col
      c.hasSelection = true
  else:
    c.hasSelection = false

  let next = arrangement.nextVisibleLine(c.line)
  if next != c.line:
    let nextLineLen = arrangement.lines[next].arrangement.runes.len
    c.line = next
    c.col = min(c.snapCol, nextLineLen)
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
  ## Incrementally re-highlight from startLineI forward.
  ## Stops early when the cross-line parse state no longer changes.
  for i in startLineI ..< arr.lines.len:
    let startState =
      if i == 0: NimParseState()
      else: nextLineParseState(arr.lines[i - 1].parseEndState)

    let line = arr.lines[i]
    let oldEndState = line.parseEndState
    let res = parseNimCode(line.runes, startState, line.runes.len)
    line.kinds = res.segments
    line.parseEndState = res.state

    if i > startLineI and nextLineParseState(res.state) == nextLineParseState(oldEndState):
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


proc shiftFoldedLines(arr: CodeArrangement, fromLine, delta: int) =
  ## Shift foldedLines entries: entries >= fromLine are shifted by delta
  var newFolded: HashSet[int]
  for lineI in arr.foldedLines:
    if lineI < fromLine: newFolded.incl lineI
    elif lineI + delta >= 0: newFolded.incl lineI + delta
  arr.foldedLines = newFolded


# --- cursor adjustment helpers ---

proc adjustCursorPoint(line, col: var int, editLine, editCol, colDelta: int) =
  if line == editLine and col >= editCol:
    col += colDelta

proc adjustCursorsAfterInsert(arr: CodeArrangement, editLine, editCol, insertedCols: int) =
  for i in 0 ..< arr.cursors.len:
    adjustCursorPoint(arr.cursors[i].line, arr.cursors[i].col, editLine, editCol, insertedCols)
    adjustCursorPoint(arr.cursors[i].anchorLine, arr.cursors[i].anchorCol, editLine, editCol, insertedCols)
    arr.cursors[i].snapCol = arr.cursors[i].col

proc adjustCursorsAfterDelete(arr: CodeArrangement, editLine, editCol, deletedCols: int) =
  for i in 0 ..< arr.cursors.len:
    var c = arr.cursors[i]
    if c.line == editLine:
      if c.col > editCol + deletedCols: c.col -= deletedCols
      elif c.col > editCol: c.col = editCol
    if c.hasSelection and c.anchorLine == editLine:
      if c.anchorCol > editCol + deletedCols: c.anchorCol -= deletedCols
      elif c.anchorCol > editCol: c.anchorCol = editCol
    c.snapCol = c.col
    arr.cursors[i] = c

proc adjustCursorsAfterLineSplit(arr: CodeArrangement, splitLine, splitCol: int) =
  for i in 0 ..< arr.cursors.len:
    var c = arr.cursors[i]
    if c.line == splitLine and c.col > splitCol:
      c.line += 1; c.col -= splitCol
    elif c.line > splitLine:
      c.line += 1
    if c.hasSelection:
      if c.anchorLine == splitLine and c.anchorCol > splitCol:
        c.anchorLine += 1; c.anchorCol -= splitCol
      elif c.anchorLine > splitLine:
        c.anchorLine += 1
    c.snapCol = c.col
    arr.cursors[i] = c

proc adjustCursorsAfterMultiLineDeletion(arr: CodeArrangement, startLine, startCol, endLine, endCol: int) =
  let mergedLen = startCol
  for i in 0 ..< arr.cursors.len:
    var c = arr.cursors[i]

    proc fixPoint(ln: var int, col: var int) =
      if ln > endLine:
        ln -= endLine - startLine
      elif ln == endLine:
        col = if col >= endCol: mergedLen + (col - endCol) else: mergedLen
        ln = startLine
      elif ln > startLine:
        ln = startLine; col = mergedLen

    fixPoint(c.line, c.col)
    if c.hasSelection: fixPoint(c.anchorLine, c.anchorCol)
    c.snapCol = c.col
    arr.cursors[i] = c


# --- editing primitives ---

proc insertAt*(arr: CodeArrangement, line, col: int, runes: seq[Rune]) =
  ## Insert runes at (line, col). '\n' in runes splits lines. Adjusts all cursors.
  var lineI = line
  var colI = col
  var chunkStart = 0
  for i in 0..runes.len:
    let atNl = i < runes.len and runes[i] == Rune('\n')
    if atNl or i == runes.len:
      if i > chunkStart:
        let chunk = runes[chunkStart..<i]
        let lr = arr.lines[lineI].runes
        arr.lines[lineI].runes = lr[0..<colI] & chunk & lr[colI..<lr.len]
        adjustCursorsAfterInsert(arr, lineI, colI, chunk.len)
        colI += chunk.len
      if atNl:
        let lr = arr.lines[lineI].runes
        arr.lines[lineI].runes = lr[0..<colI]
        arr.lines.insert(CodeArrangementLine(runes: lr[colI..<lr.len]), lineI + 1)
        shiftFoldedLines(arr, lineI + 1, 1)
        adjustCursorsAfterLineSplit(arr, lineI, colI)
        lineI += 1
        colI = 0
      chunkStart = i + 1


proc deleteAt*(arr: CodeArrangement, sl, sc, el, ec: int) =
  ## Delete from (sl, sc) to (el, ec). Adjusts all cursors.
  if sl > el or (sl == el and sc >= ec): return
  if sl == el:
    arr.lines[sl].runes.delete(sc..ec - 1)
    adjustCursorsAfterDelete(arr, sl, sc, ec - sc)
  else:
    let kept = arr.lines[sl].runes[0..<sc] & arr.lines[el].runes[ec..<arr.lines[el].runes.len]
    arr.lines[sl].runes = kept
    arr.lines.delete(sl + 1..el)
    shiftFoldedLines(arr, sl + 1, -(el - sl))
    adjustCursorsAfterMultiLineDeletion(arr, sl, sc, el, ec)


# --- selection deletion ---

proc selectionBounds(c: CursorPos, mode: SelectionMode): tuple[sl, sc, el, ec: int] =
  case mode
  of LineSelection:
    if c.anchorLine < c.line or (c.anchorLine == c.line and c.anchorCol <= c.col):
      (c.anchorLine, c.anchorCol, c.line, c.col)
    else:
      (c.line, c.col, c.anchorLine, c.anchorCol)
  of BlockSelection:
    (min(c.line, c.anchorLine), min(c.col, c.anchorCol),
     max(c.line, c.anchorLine), max(c.col, c.anchorCol))


proc deleteSelectionOf(arr: CodeArrangement, cursorI: int): int =
  ## Delete cursor cursorI's selection. Move cursor to selection start. Clear hasSelection.
  ## Returns first affected line.
  if not arr.cursors[cursorI].hasSelection:
    return arr.cursors[cursorI].line
  let (sl, sc, el, ec) = selectionBounds(arr.cursors[cursorI], arr.selectionMode)
  case arr.selectionMode
  of LineSelection:
    arr.deleteAt(sl, sc, el, ec)
  of BlockSelection:
    for lineI in countdown(el, sl):
      let a = min(sc, arr.lines[lineI].runes.len)
      let b = min(ec, arr.lines[lineI].runes.len)
      if a < b: arr.deleteAt(lineI, a, lineI, b)
  arr.cursors[cursorI].line = sl
  arr.cursors[cursorI].col = min(sc, arr.lines[sl].runes.len)
  arr.cursors[cursorI].snapCol = arr.cursors[cursorI].col
  arr.cursors[cursorI].hasSelection = false
  return sl


# --- helpers ---

proc finishEdit(arr: CodeArrangement, minLine: int) =
  let lo = max(0, minLine)
  let hi = arr.lines.len - 1
  if lo > hi: return
  for i in lo..hi:
    refreshArrangementLine(arr, i)
  updateSyntaxFrom(arr, lo)
  updateIndentOffsets(arr)
  updateFoldable(arr)
  arr.updateRects()


proc sortedCursorIndices(arr: CodeArrangement): seq[int] =
  var order: seq[tuple[line, col, idx: int]]
  for i, c in arr.cursors:
    if not c.isDuplicate:
      order.add (c.line, c.col, i)
  order.sort(SortOrder.Descending)
  result = order.mapIt(it.idx)


# --- integrated editing procs ---

proc insert*(arr: CodeArrangement, text: string) =
  ## Insert text at every active cursor.
  let runes = text.toRunes
  if runes.len == 0: return
  var minLine = int.high
  for cursorI in arr.sortedCursorIndices():
    minLine = min(minLine, deleteSelectionOf(arr, cursorI))
    let c = arr.cursors[cursorI]
    arr.insertAt(c.line, c.col, runes)
    arr.cursors[cursorI].snapCol = arr.cursors[cursorI].col
    minLine = min(minLine, c.line)
  arr.collapseDuplicatedCursors()
  finishEdit(arr, minLine)


proc deleteBack*(arr: CodeArrangement) =
  ## Backspace: delete char before cursor or selection.
  var minLine = int.high
  for cursorI in arr.sortedCursorIndices():
    let c = arr.cursors[cursorI]
    if c.hasSelection:
      minLine = min(minLine, deleteSelectionOf(arr, cursorI))
    elif c.col > 0:
      arr.deleteAt(c.line, c.col - 1, c.line, c.col)
      minLine = min(minLine, c.line)
    elif c.line > 0:
      arr.deleteAt(c.line - 1, arr.lines[c.line - 1].runes.len, c.line, 0)
      minLine = min(minLine, c.line - 1)
  arr.collapseDuplicatedCursors()
  finishEdit(arr, minLine)


proc deleteForward*(arr: CodeArrangement) =
  ## Delete key: delete char after cursor or selection.
  var minLine = int.high
  for cursorI in arr.sortedCursorIndices():
    let c = arr.cursors[cursorI]
    if c.hasSelection:
      minLine = min(minLine, deleteSelectionOf(arr, cursorI))
    else:
      let lineLen = arr.lines[c.line].runes.len
      if c.col < lineLen:
        arr.deleteAt(c.line, c.col, c.line, c.col + 1)
        minLine = min(minLine, c.line)
      elif c.line < arr.lines.len - 1:
        arr.deleteAt(c.line, lineLen, c.line + 1, 0)
        minLine = min(minLine, c.line)
  arr.collapseDuplicatedCursors()
  finishEdit(arr, minLine)


proc insertNewline*(arr: CodeArrangement) =
  ## Enter: split current line at cursor, auto-indent to match current line.
  var minLine = int.high
  for cursorI in arr.sortedCursorIndices():
    discard deleteSelectionOf(arr, cursorI)
    let c = arr.cursors[cursorI]
    var indentRunes: seq[Rune]
    for r in arr.lines[c.line].runes:
      if r == Rune(' ') or r == Rune('\t'): indentRunes.add r
      else: break
    arr.insertAt(c.line, c.col, @[Rune('\n')] & indentRunes)
    arr.cursors[cursorI].line = c.line + 1
    arr.cursors[cursorI].col = indentRunes.len
    arr.cursors[cursorI].snapCol = indentRunes.len
    arr.cursors[cursorI].hasSelection = false
    minLine = min(minLine, c.line)
  arr.collapseDuplicatedCursors()
  finishEdit(arr, minLine)


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
    typesetWithIndent(font, width, cline)
    cline.rect = rect(0, 0, cline.arrangement.layoutBounds.x, cline.arrangement.lines.len.max(1).float32 * font.lineHeightPixels)
    parseState = nextLineParseState(parsed.state)
    result.lines.add cline

  result.updateIndentOffsets()
  result.updateFoldable()
  result.cursors = @[CursorPos()]
  result.updateRects()
