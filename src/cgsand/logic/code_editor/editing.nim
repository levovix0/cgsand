## high-level operations for editing code arrangements

import std/[unicode, algorithm, strutils]
import ./[arrangements, selection, editbase]


# --- selection deletion ---

proc deleteSelectionOf(arr: CodeArrangement, cursorI: int) =
  ## Delete cursor cursorI's selection. Move cursor to selection start. Clear hasSelection.
  if not arr.cursors[cursorI].hasSelection: return
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


# --- integrated editing procs ---

proc insert*(arr: CodeArrangement, text: string) =
  ## Insert text at every active cursor.
  # Windows puts CRLF in the clipboard. Internally each CodeArrangementLine is
  # newline-free, so normalize all external line endings before splitting.
  let runes = text.replace("\r\n", "\n").replace("\r", "\n").toRunes
  if runes.len == 0: return
  for cursorI in arr.sortedCursorIndices():
    deleteSelectionOf(arr, cursorI)
    let c = arr.cursors[cursorI]
    arr.insertAt(c.line, c.col, runes)
    arr.cursors[cursorI].snapCol = arr.cursors[cursorI].col
  arr.collapseDuplicatedCursors()


proc duplicateSelectionsOrLines*(arr: CodeArrangement) =
  ## With selections, duplicate every selected fragment immediately after
  ## itself and keep the copies selected. Without selections, duplicate every
  ## unique line containing a cursor and move those cursors to the copies.
  var hasSelections = false
  for cursor in arr.cursors:
    if not cursor.isDuplicate and cursor.hasSelection:
      hasSelections = true
      break

  if hasSelections:
    var order: seq[tuple[line, col, cursorI: int]]
    for cursorI, cursor in arr.cursors:
      if cursor.isDuplicate or not cursor.hasSelection: continue
      let (_, _, endLine, endCol) = selectionBounds(cursor, arr.selectionMode)
      order.add (endLine, endCol, cursorI)
    order.sort(SortOrder.Descending)

    for item in order:
      let text = arr.selectedText(item.cursorI)
      let runes = text.toRunes
      if runes.len == 0: continue
      let (_, _, endLine, endCol) = selectionBounds(arr.cursors[item.cursorI], arr.selectionMode)

      var copyEndLine = endLine
      var copyEndCol = endCol
      for r in runes:
        if r == Rune('\n'):
          inc copyEndLine
          copyEndCol = 0
        else:
          inc copyEndCol

      arr.insertAt(endLine, endCol, runes)
      arr.setSelection(item.cursorI, endLine, endCol, copyEndLine, copyEndCol)

  else:
    var targetLines: seq[int]
    for cursor in arr.cursors:
      if not cursor.isDuplicate and cursor.line notin targetLines:
        targetLines.add cursor.line
    targetLines.sort(SortOrder.Descending)

    for lineI in targetLines:
      if lineI < 0 or lineI >= arr.lines.len: continue
      let content = arr.lines[lineI].runes
      var affected: seq[tuple[cursorI, col: int]]
      for cursorI, cursor in arr.cursors:
        if cursor.line == lineI:
          affected.add (cursorI, cursor.col)

      arr.insertAt(lineI, content.len, @[Rune('\n')] & content)
      for item in affected:
        let col = min(item.col, content.len)
        arr.setSelection(item.cursorI, lineI + 1, col, lineI + 1, col)

  arr.collapseDuplicatedCursors()


proc deleteBack*(arr: CodeArrangement) =
  ## Backspace: delete char before cursor or selection.
  for cursorI in arr.sortedCursorIndices():
    let c = arr.cursors[cursorI]
    if c.hasSelection:
      arr.deleteSelectionOf(cursorI)
    elif c.col > 0:
      arr.deleteAt(c.line, c.col - 1, c.line, c.col)
    elif c.line > 0:
      arr.deleteAt(c.line - 1, arr.lines[c.line - 1].runes.len, c.line, 0)
  arr.collapseDuplicatedCursors()


proc deleteForward*(arr: CodeArrangement) =
  ## Delete key: delete char after cursor or selection.
  for cursorI in arr.sortedCursorIndices():
    let c = arr.cursors[cursorI]
    if c.hasSelection:
      arr.deleteSelectionOf(cursorI)
    else:
      let lineLen = arr.lines[c.line].runes.len
      if c.col < lineLen:
        arr.deleteAt(c.line, c.col, c.line, c.col + 1)
      elif c.line < arr.lines.len - 1:
        arr.deleteAt(c.line, lineLen, c.line + 1, 0)
  arr.collapseDuplicatedCursors()


proc insertNewline*(arr: CodeArrangement) =
  ## Enter: split current line at cursor, auto-indent to match current line.
  for cursorI in arr.sortedCursorIndices():
    arr.deleteSelectionOf(cursorI)
    let c = arr.cursors[cursorI]
    var indentRunes: seq[Rune]
    for r in arr.lines[c.line].runes:
      if r == Rune(' ') or r == Rune('\t'): indentRunes.add r
      else: break
    arr.insertAt(c.line, c.col, @[Rune('\n')] & indentRunes)
    arr.cursors[cursorI].line = c.line + 1
    arr.cursors[cursorI].col = indentRunes.len
    arr.cursors[cursorI].snapCol = arr.cursors[cursorI].col
    arr.cursors[cursorI].hasSelection = false
  arr.collapseDuplicatedCursors()


proc allSelectedLineNumbers(arr: CodeArrangement): seq[int] =
  var lines: seq[int]
  for cursor in arr.cursors:
    let selr = cursor.selectionBounds(arr.selectionMode)
    for lineI in selr.sl..selr.el:
      if lineI notin lines: lines.add lineI
  lines

proc indent*(arr: CodeArrangement) =
  for lineI in arr.allSelectedLineNumbers:
    arr.insertAt(lineI, 0, "  ".toRunes)  # todo: use indentation space count
  arr.collapseDuplicatedCursors()

proc dedent*(arr: CodeArrangement) =
  for lineI in arr.allSelectedLineNumbers:
    let toRemove = min(arr.lines[lineI].indent, 2)  # todo: use indentation space count
    arr.deleteAt(lineI, 0, lineI, toRemove)
  arr.collapseDuplicatedCursors()
