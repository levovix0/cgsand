import std/[unicode, strutils, sequtils, sets]
import pkg/[vmath, bumpy]
import pkg/pixie/fonts
import ./[syntax_highlighting]
export CodeKind


type
  CodeLine* = seq[Rune]

  CodeFile* = ref object
    lines*: seq[CodeLine]


  CodeArrangementLine* = ref object
    rect*: Rect
    arrangement*: Arrangement
    kinds*: seq[CodeKind]
    indentLevel*: int
    isEmpty*: bool
    foldable*: bool
    isHidden*: bool
    lineHeight*: float32

  CodeArrangement* = ref object
    lines*: seq[CodeArrangementLine]
    foldedLines*: HashSet[int]



proc readCodeFile*(filename: string): CodeFile =
  new result
  result.lines = filename.readFile.splitLines.mapIt(it.toRunes)


proc writeCodeFile*(filename: string, v: CodeFile) =
  writeFile filename, v.lines.join("\n")



proc lineIndent(line: CodeLine): int =
  for r in line:
    if r == Rune(' '): inc result
    elif r == Rune('\t'): result += 2
    else: break

proc lineIsEmpty(line: CodeLine): bool =
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

    if not line.isHidden:
      line.rect = rect(vec2(0, y), line.rect.wh)
      y += line.lineHeight
      if i in arrangement.foldedLines and line.foldable:
        foldStack.add line.indentLevel


proc visibleHeight*(arrangement: CodeArrangement): float32 =
  for line in arrangement.lines:
    if not line.isHidden:
      result += line.lineHeight


proc toggleFold*(arrangement: CodeArrangement, lineIdx: int) =
  if lineIdx >= arrangement.lines.len: return
  if not arrangement.lines[lineIdx].foldable: return
  if lineIdx in arrangement.foldedLines:
    arrangement.foldedLines.excl lineIdx
  else:
    arrangement.foldedLines.incl lineIdx
  arrangement.updateRects()


proc toArrangement*(cf: CodeFile, font: Font, width: float32): CodeArrangement =
  new result

  for line in cf.lines:
    var cline = CodeArrangementLine(arrangement: typeset(font, $line, bounds=vec2(width, 0)))
    cline.rect = rect(vec2(0, 0), cline.arrangement.layoutBounds)
    cline.kinds = parseNimCode(line, NimParseState(), line.len).segments
    cline.indentLevel = lineIndent(line)
    cline.isEmpty = lineIsEmpty(line)
    let lineCount = max(cline.arrangement.lines.len.float32, 1)
    cline.lineHeight = lineCount * font.size * (font.typeface.ascent / font.typeface.scale + max(font.typeface.lineGap / font.typeface.scale, 0.25))
    result.lines.add cline

  for i in 0 ..< result.lines.len:
    if result.lines[i].isEmpty: continue
    let myIndent = result.lines[i].indentLevel
    for j in i+1 ..< result.lines.len:
      if result.lines[j].isEmpty: continue
      if result.lines[j].indentLevel > myIndent:
        result.lines[i].foldable = true
      break

  result.updateRects()
