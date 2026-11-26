## high-level selection utilities for code arrangements

import std/[unicode, sets]
import pkg/[vmath, bumpy]
import pkg/sigui/[rendering]
import ./[unicodeutils, arrangements]


proc selectionBounds*(c: CursorPos, mode: SelectionMode): tuple[sl, sc, el, ec: int] =
  if not c.hasSelection: return (c.line, c.col, c.line, c.col)
  case mode
  of LineSelection:
    if c.anchorLine < c.line or (c.anchorLine == c.line and c.anchorCol <= c.col):
      (c.anchorLine, c.anchorCol, c.line, c.col)
    else:
      (c.line, c.col, c.anchorLine, c.anchorCol)
  of BlockSelection:
    (min(c.line, c.anchorLine), min(c.col, c.anchorCol),
     max(c.line, c.anchorLine), max(c.col, c.anchorCol))


proc selectionRangeForLine*(arrangement: CodeArrangement, c: CursorPos, lineI: int): Slice[int] =
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


proc selectionRangeForLine*(arrangement: CodeArrangement, cursorI: int, lineI: int): Slice[int] =
  arrangement.selectionRangeForLine(arrangement.cursors[cursorI], lineI)


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


proc wordRunAt*(arrangement: CodeArrangement, lineI, col: int): Slice[int] =
  ## Bounds of the word-like run under col: identifier-like runes extend the
  ## run, any other rune is a run of its own. `.a` is the index of the first
  ## rune of the run and `.b` the index of the last one. Empty range when col
  ## is past the line end.
  if lineI < 0 or lineI >= arrangement.lines.len: return 0..<0
  let runes = arrangement.lines[lineI].runes
  if col < 0 or col >= runes.len: return 0..<0

  if not runes[col].isWordRune:
    return col..<min(col + 1, runes.len)

  var first = col
  var last = col + 1
  while first > 0 and runes[first - 1].isWordRune: dec first
  while last < runes.len and runes[last].isWordRune: inc last
  first..<last


proc selectWordAt*(arrangement: CodeArrangement, cursorI, lineI, col: int) =
  ## Select the identifier-like word under col. Punctuation and whitespace are
  ## selected one rune at a time; clicking past the line end clears selection.
  if cursorI < 0 or cursorI >= arrangement.cursors.len: return
  if lineI < 0 or lineI >= arrangement.lines.len: return

  let runes = arrangement.lines[lineI].runes
  if col < 0 or col >= runes.len:
    arrangement.setSelection(cursorI, lineI, runes.len, lineI, runes.len)
    return

  let run = arrangement.wordRunAt(lineI, col)
  arrangement.setSelection(cursorI, lineI, run.a, lineI, run.b + 1)


proc selectLineAt*(arrangement: CodeArrangement, cursorI, lineI: int) =
  ## Select the whole logical line, including its newline when one follows.
  if cursorI < 0 or cursorI >= arrangement.cursors.len: return
  if lineI < 0 or lineI >= arrangement.lines.len: return

  if lineI < arrangement.lines.high:
    arrangement.setSelection(cursorI, lineI, 0, lineI + 1, 0)
  else:
    arrangement.setSelection(cursorI, lineI, 0, lineI, arrangement.lines[lineI].runes.len)


proc cellAt*(arrangement: CodeArrangement, mouseXy: Vec2): tuple[line, col: int] =
  ## The line and column under the mouse position, skipping hidden lines.
  ## line is -1 when there are no visible lines.
  var firstVisible = -1
  var lastVisible = -1
  for i, line in arrangement.lines:
    if line.isHidden: continue
    if firstVisible == -1: firstVisible = i
    lastVisible = i
    if mouseXy.y >= line.rect.y and mouseXy.y < line.rect.y + line.rect.h:
      let col = line.posToCol(vec2(mouseXy.x, mouseXy.y - line.rect.y))
      return (i, col)

  if firstVisible == -1: return (-1, 0)
  if mouseXy.y < arrangement.lines[firstVisible].rect.y:
    return (firstVisible, 0)
  result = (lastVisible, arrangement.lines[lastVisible].arrangement.runes.len)


proc selectToPos*(arrangement: CodeArrangement, cursorI: int, mouseXy: Vec2) =
  if cursorI < 0 or cursorI >= arrangement.cursors.len: return

  let (foundLine, foundCol) = arrangement.cellAt(mouseXy)
  if foundLine != -1:
    arrangement.setSelection(
      cursorI,
      arrangement.cursors[cursorI].anchorLine, arrangement.cursors[cursorI].anchorCol,
      foundLine, foundCol,
    )


proc selectWordsToPos*(
  arrangement: CodeArrangement, cursorI: int, mouseXy: Vec2,
  wordLine, wordFirst, wordLast: int,
) =
  ## Extend the cursor's selection by whole words towards the mouse position
  ## (double-click + drag). The word selected by the double click
  ## (wordLine, wordFirst ..< wordLast) stays inside the selection when the
  ## drag direction changes.
  if cursorI < 0 or cursorI >= arrangement.cursors.len: return
  let (lineI, col) = arrangement.cellAt(mouseXy)
  if lineI == -1: return

  let runes = arrangement.lines[lineI].runes
  if lineI > wordLine or (lineI == wordLine and col >= wordFirst):
    # dragging forward: end the selection after the word under the mouse
    let endCol =
      if col >= runes.len: runes.len
      else: arrangement.wordRunAt(lineI, col).b + 1
    arrangement.setSelection(cursorI, wordLine, wordFirst, lineI, endCol)
  else:
    # dragging backward: start the selection at the beginning of the word under the mouse
    let startCol =
      if col >= runes.len: runes.len
      else: arrangement.wordRunAt(lineI, col).a
    arrangement.setSelection(cursorI, lineI, startCol, wordLine, wordLast)


proc selectLinesToPos*(arrangement: CodeArrangement, cursorI: int, mouseXy: Vec2, line: int) =
  ## Extend the cursor's selection by whole lines towards the mouse position
  ## (triple-click + drag).
  if cursorI < 0 or cursorI >= arrangement.cursors.len: return
  let (lineI, _) = arrangement.cellAt(mouseXy)
  if lineI == -1: return

  if lineI >= line:
    if lineI < arrangement.lines.high:
      arrangement.setSelection(cursorI, line, 0, lineI + 1, 0)
    else:
      arrangement.setSelection(cursorI, line, 0, lineI, arrangement.lines[lineI].runes.len)
  else:
    if line < arrangement.lines.high:
      arrangement.setSelection(cursorI, lineI, 0, line + 1, 0)
    else:
      arrangement.setSelection(cursorI, lineI, 0, line, arrangement.lines[line].runes.len)


proc selectedText*(arr: CodeArrangement, cursorI: int): string =
  let cursor = arr.cursors[cursorI]
  if not cursor.hasSelection: return

  let (sl, sc, el, ec) = selectionBounds(cursor, arr.selectionMode)

  template addSlice(lineI, firstCol, lastCol: int) =
    let line = arr.lines[lineI].runes
    let first = firstCol.clamp(0, line.len)
    let last = lastCol.clamp(0, line.len)
    if first < last:
      result.add $line[first..<last]

  case arr.selectionMode
  of LineSelection:
    if sl == el:
      addSlice(sl, sc, ec)
    else:
      addSlice(sl, sc, arr.lines[sl].runes.len)
      for lineI in sl + 1..el:
        result.add '\n'
        addSlice(lineI, 0, if lineI == el: ec else: arr.lines[lineI].runes.len)

  of BlockSelection:
    for lineI in sl..el:
      if lineI != sl: result.add '\n'
      addSlice(lineI, sc, ec)


proc selectedText*(arr: CodeArrangement): string =
  ## Return selections in document order. Multiple cursor selections are
  ## separated by a newline, matching the editor's multi-cursor model.
  let order = arr.sortedCursorIndices()
  for i in countdown(order.high, 0):
    let text = arr.selectedText(order[i])
    if text.len == 0: continue
    if result.len > 0: result.add '\n'
    result.add text


proc wordAtCursor*(arr: CodeArrangement, cursorI: int): string =
  ## Return the identifier-like word touching the cursor. At the end of a word,
  ## the rune on the left is used, matching common code-editor behaviour.
  if cursorI < 0 or cursorI >= arr.cursors.len: return
  let cursor = arr.cursors[cursorI]
  if cursor.line < 0 or cursor.line >= arr.lines.len: return
  let runes = arr.lines[cursor.line].runes
  if runes.len == 0: return

  var at = cursor.col
  if at < 0: return
  if at >= runes.len or not runes[at].isWordRune:
    if at == 0 or at - 1 >= runes.len or not runes[at - 1].isWordRune: return
    dec at

  var first = at
  var last = at + 1
  while first > 0 and runes[first - 1].isWordRune: dec first
  while last < runes.len and runes[last].isWordRune: inc last
  result = $runes[first..<last]


proc selectWordAtCursor*(arr: CodeArrangement, cursorI: int): bool =
  if cursorI < 0 or cursorI >= arr.cursors.len: return
  let cursor = arr.cursors[cursorI]
  let word = arr.wordAtCursor(cursorI)
  if word.len == 0: return

  let wordLen = word.runeLen
  let runes = arr.lines[cursor.line].runes
  var at = cursor.col
  if at >= runes.len or not runes[at].isWordRune: dec at
  var first = at
  while first > 0 and runes[first - 1].isWordRune: dec first
  arr.setSelection(cursorI, cursor.line, first, cursor.line, first + wordLen)
  result = true
