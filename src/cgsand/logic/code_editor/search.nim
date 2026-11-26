## searching and replacing

import std/[re, unicode, strutils, sequtils]
import ./[unicodeutils, arrangements, selection, editbase]

type
  SearchOption* = enum
    soCaseSensitive
      ## match case exactly instead of ignoring case
    soWholeWord
      ## match only whole words (ignored in regex mode)
    soRegex
      ## the query is a regular expression
      ## (any proc that uses regex may raise ValueError for maformed regex)

  SearchOptions* = set[SearchOption]


proc searchOptions*(caseSensitive, wholeWord, regex: bool): SearchOptions =
  var r: SearchOptions
  if caseSensitive: r.incl soCaseSensitive
  if wholeWord: r.incl soWholeWord
  if regex: r.incl soRegex
  r


proc compileRegex(query: string, options: SearchOptions): Regex =
  if soCaseSensitive in options:
    query.re({reStudy})
  else:
    query.re({reStudy, reIgnoreCase})


proc regexMatches(arr: CodeArrangement, pattern: Regex): tuple[
    positions: seq[CursorPos], texts: seq[string], captures: seq[seq[string]]] =
  ## find all non-overlapping regex matches over the whole text. Regex matches
  ## bytes of the UTF-8 encoded text, so for every rune its byte offset and
  ## (line, col) position are recorded to map byte ranges back onto the lines.
  var text: string
  var runeOffsets: seq[int]
  var boundaries: seq[CursorPos]
  for lineI, line in arr.lines:
    for col, r in line.runes:
      boundaries.add CursorPos(line: lineI, col: col)
      runeOffsets.add text.len
      let utf8 = r.toUtf8
      text.add utf8
    if lineI < arr.lines.high:
      boundaries.add CursorPos(line: lineI, col: line.runes.len)
      runeOffsets.add text.len
      text.add "\n"
  boundaries.add CursorPos(line: arr.lines.high, col: arr.lines[^1].runes.len)
  runeOffsets.add text.len  # end-of-text sentinel

  var captures: array[10, string]
  var pos = 0
  var startRuneI = 0
  var endRuneI = 0
  while pos <= text.len:
    for c in captures.mitems: c = ""  # pcre only overwrites the groups it matches
    let bounds = findBounds(text, pattern, captures, start = pos)
    if bounds.first < 0: break
    let matchEndB = bounds.last + 1
    if matchEndB <= bounds.first:
      # zero-length match — skipped, like findBounds would loop over it forever
      pos = bounds.first + 1
      continue

    # map byte offsets to rune indices; matches align to rune boundaries,
    # matches come in order so the pointers only move forward
    while endRuneI < runeOffsets.len and runeOffsets[endRuneI] < matchEndB: inc endRuneI
    while startRuneI < endRuneI and runeOffsets[startRuneI] < bounds.first: inc startRuneI

    let first = boundaries[startRuneI]
    let last = boundaries[min(endRuneI, boundaries.high)]
    result.positions.add CursorPos(
      line: last.line,
      col: last.col,
      snapCol: last.col,
      hasSelection: true,
      anchorLine: first.line,
      anchorCol: first.col,
    )
    result.texts.add text[bounds.first ..< matchEndB]
    result.captures.add @captures

    pos = matchEndB
    startRuneI = endRuneI


proc findMatches*(arr: CodeArrangement, query: string, options: SearchOptions): seq[CursorPos] =
  ## find non-overlapping matches of `query` in the whole text and return them as forward selections.
  ## Newlines are included, so a multiline query works.
  if arr.lines.len == 0 or query.len == 0: return

  if soRegex in options:
    result = arr.regexMatches(compileRegex(query, options)).positions

  else:
    let normalizedQuery = query.replace("\r\n", "\n").replace("\r", "\n")
    var queryRunes = normalizedQuery.toRunes
    if soCaseSensitive notin options:
      queryRunes = queryRunes.mapIt(it.toLower)
    if queryRunes.len == 0: return

    var textRunes: seq[Rune]
    var boundaries: seq[CursorPos]
    for lineI, line in arr.lines:
      for col, r in line.runes:
        boundaries.add CursorPos(line: lineI, col: col)
        textRunes.add (if soCaseSensitive in options: r else: r.toLower)
      if lineI < arr.lines.high:
        boundaries.add CursorPos(line: lineI, col: line.runes.len)
        textRunes.add Rune('\n')
    boundaries.add CursorPos(line: arr.lines.high, col: arr.lines[^1].runes.len)

    var i = 0
    while i + queryRunes.len <= textRunes.len:
      var matches = true
      for queryI, r in queryRunes:
        if textRunes[i + queryI] != r:
          matches = false
          break

      if matches and soWholeWord in options:
        if i > 0 and textRunes[i - 1].isWordRune: matches = false
        let after = i + queryRunes.len
        if after < textRunes.len and textRunes[after].isWordRune: matches = false

      if matches:
        let first = boundaries[i]
        let last = boundaries[i + queryRunes.len]
        result.add CursorPos(
          line: last.line,
          col: last.col,
          snapCol: last.col,
          hasSelection: true,
          anchorLine: first.line,
          anchorCol: first.col,
        )
        i += queryRunes.len
      else:
        inc i


proc expandRegexReplacement*(tmpl, wholeMatch: string, captures: openArray[string]): string =
  ## expands $0..$9 and $$ in a replacement template using the whole match and
  ## its capture groups ($0 is the whole match, $1 is the first group);
  ## references to missing groups expand to nothing
  var i = 0
  while i < tmpl.len:
    if tmpl[i] != '$':
      result.add tmpl[i]
      inc i
    elif i + 1 < tmpl.len and tmpl[i + 1] == '$':
      result.add '$'
      i += 2
    elif i + 1 < tmpl.len and tmpl[i + 1] in {'0' .. '9'}:
      let groupI = ord(tmpl[i + 1]) - ord('0')
      if groupI == 0:
        result.add wholeMatch
      elif groupI <= captures.len:
        result.add captures[groupI - 1]
      i += 2
    else:
      result.add '$'
      inc i


proc replaceRanges*(arr: CodeArrangement, matches: seq[CursorPos], replacements: seq[string]) =
  ## replaces every match (a forward selection) with the corresponding
  ## replacement text, applying back-to-front so the positions of the matches
  ## that are not applied yet stay valid. Leaves a single cursor at the end of
  ## the last replaced fragment. Returns the first affected line, -1 if
  ## nothing changed. Does not call finishEdit when nothing was replaced.
  let count = min(matches.len, replacements.len)
  if count == 0: return

  var cursorLine, cursorCol: int
  for i in countdown(count - 1, 0):
    let m = matches[i]
    let (sl, sc, el, ec) = selectionBounds(m, LineSelection)
    arr.deleteAt(sl, sc, el, ec)
    let rep = replacements[i].replace("\r\n", "\n").replace("\r", "\n").toRunes
    if rep.len > 0:
      arr.insertAt(sl, sc, rep)

    # the earliest match (i == 0) is edited last, so its own final position is
    # not shifted by any later edit — a good place for the resulting cursor
    if i == 0:
      cursorLine = sl
      cursorCol = sc
      for r in rep:
        if r == Rune('\n'):
          inc cursorLine
          cursorCol = 0
        else:
          inc cursorCol

  arr.cursors = @[CursorPos(line: cursorLine, col: cursorCol, snapCol: cursorCol)]


proc replaceAllMatches*(arr: CodeArrangement, query: string, options: SearchOptions, tmpl: string): bool =
  ## replaces every match of `query` with `tmpl`
  ## ($0..$9 group references are expanded in regex mode, plain mode uses `tmpl` literally).
  ## Returns false if there were no matches.
  result = true
  if soRegex in options:
    let regex = compileRegex(query, options)
    let matches = arr.findMatches(query, options)
    if matches.len == 0: return false
    let found = arr.regexMatches(regex)
    var replacements: seq[string]
    for i in 0 ..< matches.len:
      replacements.add expandRegexReplacement(tmpl, found.texts[i], found.captures[i])
    arr.replaceRanges(matches, replacements)
  else:
    let matches = arr.findMatches(query, options)
    if matches.len == 0: return false
    arr.replaceRanges(matches, newSeqWith(matches.len, tmpl))


proc matchingSelections*(arr: CodeArrangement, query: string, wholeWord = false): seq[CursorPos] =
  ## Find non-overlapping case-insensitive matches and return them as forward
  ## selections. Newlines are included, so a selected multiline fragment works.
  var options: SearchOptions = if wholeWord: {soWholeWord} else: {}
  result = arr.findMatches(query, options)


proc sameSelection*(a, b: CursorPos): bool =
  let aForward = a.anchorLine < a.line or
    (a.anchorLine == a.line and a.anchorCol <= a.col)
  let bForward = b.anchorLine < b.line or
    (b.anchorLine == b.line and b.anchorCol <= b.col)
  let aStart = if aForward: (a.anchorLine, a.anchorCol) else: (a.line, a.col)
  let aEnd = if aForward: (a.line, a.col) else: (a.anchorLine, a.anchorCol)
  let bStart = if bForward: (b.anchorLine, b.anchorCol) else: (b.line, b.col)
  let bEnd = if bForward: (b.line, b.col) else: (b.anchorLine, b.anchorCol)
  aStart == bStart and aEnd == bEnd


proc addSelectionToNextMatch*(arr: CodeArrangement): bool =
  ## VS Code-like Ctrl+D: first select the word at a bare cursor, then append
  ## the next case-insensitive occurrence, wrapping at the end of the document.
  if arr.cursors.len == 0 or arr.selectionMode != LineSelection: return
  if not arr.cursors[0].hasSelection:
    return arr.selectWordAtCursor(0)

  let query = arr.selectedText(0)
  if query.len == 0: return
  let matches = arr.matchingSelections(query)
  if matches.len == 0: return

  let current = arr.cursors[^1]
  var currentEnd = (current.line, current.col)
  if (current.anchorLine, current.anchorCol) > currentEnd:
    currentEnd = (current.anchorLine, current.anchorCol)

  proc alreadySelected(candidate: CursorPos): bool =
    for cursor in arr.cursors:
      if cursor.sameSelection(candidate): return true

  for candidate in matches:
    let candidateStart = (candidate.anchorLine, candidate.anchorCol)
    if candidateStart >= currentEnd and not alreadySelected(candidate):
      arr.cursors.add candidate
      return true

  for candidate in matches:
    if not alreadySelected(candidate):
      arr.cursors.add candidate
      return true
