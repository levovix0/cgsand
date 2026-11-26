## primitives for editing code arrangements

import std/[unicode, sequtils, sets]
import pkg/[vmath]
import ./[arrangements]



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
    if c.line == splitLine and c.col >= splitCol:
      c.line += 1; c.col -= splitCol
    elif c.line > splitLine:
      c.line += 1
    if c.hasSelection:
      if c.anchorLine == splitLine and c.anchorCol >= splitCol:
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
  arr.changed_minLine = min(arr.changed_minLine, line)
  for i in 0..runes.len:
    let atNl = i < runes.len and runes[i] == Rune('\n')
    if atNl or i == runes.len:
      if i > chunkStart:
        let chunk = runes[chunkStart..<i]
        let lr = arr.lines[lineI].runes
        arr.lines[lineI].runes = lr[0..<colI] & chunk & lr[colI..<lr.len]
        arr.lines[lineI].syntaxValid = false
        adjustCursorsAfterInsert(arr, lineI, colI, chunk.len)
        colI += chunk.len
      if atNl:
        let lr = arr.lines[lineI].runes
        arr.lines[lineI].runes = lr[0..<colI]
        arr.lines[lineI].syntaxValid = false
        arr.lines.insert(CodeArrangementLine(runes: lr[colI..<lr.len]), lineI + 1)
        shiftFoldedLines(arr, lineI + 1, 1)
        adjustCursorsAfterLineSplit(arr, lineI, colI)
        lineI += 1
        colI = 0
      chunkStart = i + 1


proc deleteAt*(arr: CodeArrangement, sl, sc, el, ec: int) =
  ## Delete from (sl, sc) to (el, ec). Adjusts all cursors.
  if sl > el or (sl == el and sc >= ec): return
  arr.changed_minLine = min(arr.changed_minLine, sl)
  if sl == el:
    arr.lines[sl].runes.delete(sc..ec - 1)
    arr.lines[sl].syntaxValid = false
    adjustCursorsAfterDelete(arr, sl, sc, ec - sc)
  else:
    let kept = arr.lines[sl].runes[0..<sc] & arr.lines[el].runes[ec..<arr.lines[el].runes.len]
    arr.lines[sl].runes = kept
    arr.lines[sl].syntaxValid = false
    arr.lines.delete(sl + 1..el)
    shiftFoldedLines(arr, sl + 1, -(el - sl))
    adjustCursorsAfterMultiLineDeletion(arr, sl, sc, el, ec)


proc finishEdit*(arr: CodeArrangement) =
  ## call this at the end of ALL change operations to prepare arrangement for presenting
  let lo = arr.changed_minLine
  let hi = arr.lines.len - 1
  if lo > hi: return
  for i in lo..hi:
    refreshArrangementLine(arr, i)
  updateSyntaxFrom(arr, lo)
  updateIndentOffsets(arr)
  updateFoldable(arr)
  arr.updateRects()
  arr.changed_minLine = arr.lines.len
