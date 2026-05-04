import std/[unicode, strutils, sequtils, sets]
import pkg/[vmath, bumpy]
import pkg/pixie/fonts
import ./[syntax_highlighting]
export CodeKind


type
  CodeLine* = seq[Rune]
    ## todo: looks useless

  CodeFile* = ref object
    ## todo: looks useless
    lines*: seq[CodeLine]


  SelectionMode* = enum
    LineSelection
    BlockSelection


  CodeArrangementLine* = ref object
    rect*: Rect
      ## visual rect of a line in pixels, relative to top-left courner of whole CodeArrangement
      ## .xy recalculated on updateRects

    arrangement*: Arrangement

    kinds*: seq[CodeKind]
      ## syntax highlighting for a line of code, per rune
    
    isEmpty*: bool
      ## true if line contains nothing or only spaces
    
    indentLevel*: int
      ## the ammount of logical block of indentation (space count can be diffirent per logical indentation block)
      ## recalculated on updateRects

    foldable*: bool
      ## is the line a "header" of an indented block
      ## recalculated on updateRects

    isHidden*: bool
      ## true if the line is a part of folded block
      ## recalculated on updateRects


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



proc lineHeightPixels*(font: Font): float32 =
  font.size * ((font.typeface.ascent / font.typeface.scale) + max(font.typeface.lineGap / font.typeface.scale, 0.25))



proc readCodeFile*(filename: string): CodeFile =
  new result
  result.lines = filename.readFile.splitLines.mapIt(it.toRunes)


proc writeCodeFile*(filename: string, v: CodeFile) =
  writeFile filename, v.lines.join("\n")



proc indent(line: CodeLine): int =
  for r in line:
    if r == Rune(' '): inc result
    elif r == Rune('\t'): result += 2
    else: break

proc isEmpty(line: CodeLine): bool =
  for r in line:
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
      while foldStack.len > 0 and line.indentLevel <= foldStack[^1]:
        discard foldStack.pop()

    if line.isEmpty and foldStack.len > 0:
      var nextIndent = -1
      for j in i+1 ..< arrangement.lines.len:
        if not arrangement.lines[j].isEmpty:
          nextIndent = arrangement.lines[j].indentLevel
          break
      line.isHidden = nextIndent > foldStack[^1]
    else:
      line.isHidden = foldStack.len > 0

    line.rect = rect(vec2(0, y), line.rect.wh)

    if not line.isHidden:
      y += line.arrangement.lines.len.max(1).float32 * arrangement.font.lineHeightPixels
      if i in arrangement.foldedLines and line.foldable:
        foldStack.add line.indentLevel


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


proc moveCursorLeft*(arrangement: CodeArrangement, cursorIdx: int, extend: bool = false) =
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
  elif c.line > 0:
    let prev = arrangement.prevVisibleLine(c.line)
    if prev != c.line:
      c.line = prev
      c.col = arrangement.lines[prev].arrangement.runes.len
  c.snapCol = c.col
  arrangement.cursors[cursorIdx] = c

proc moveCursorRight*(arrangement: CodeArrangement, cursorIdx: int, extend: bool = false) =
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


proc moveCursorLeft*(arrangement: CodeArrangement, extend: bool = false) =
  for i in 0..<arrangement.cursors.len:
    moveCursorLeft(arrangement, i, extend)
  arrangement.collapseDuplicatedCursors()

proc moveCursorRight*(arrangement: CodeArrangement, extend: bool = false) =
  for i in 0..<arrangement.cursors.len:
    moveCursorRight(arrangement, i, extend)
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


proc toArrangement*(cf: CodeFile, font: Font, width: float32): CodeArrangement =
  result = CodeArrangement(font: font)

  for line in cf.lines:
    var cline = CodeArrangementLine(arrangement: typeset(font, $line, bounds=vec2(width, 0)))
    cline.rect = rect(0, 0, cline.arrangement.layoutBounds.x, cline.arrangement.lines.len.max(1).float32 * font.lineHeightPixels)
    cline.kinds = parseNimCode(line, NimParseState(), line.len).segments
    cline.indentLevel = indent(line)
    cline.isEmpty = isEmpty(line)
    result.lines.add cline

  for i in 0 ..< result.lines.len:
    if result.lines[i].isEmpty: continue
    let myIndent = result.lines[i].indentLevel
    for j in i+1 ..< result.lines.len:
      if result.lines[j].isEmpty: continue
      if result.lines[j].indentLevel > myIndent:
        result.lines[i].foldable = true
      break

  result.cursors = @[CursorPos()]
  result.updateRects()

