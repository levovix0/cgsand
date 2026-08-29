import std/[unicode, terminal, strutils]
import pkg/[vmath, chroma]


const
  ColorDimBlack*      = parseHtmlHex("#202223")
  ColorDimRed         = parseHtmlHex("#ED1515")
  ColorDimGreen       = parseHtmlHex("#11D116")
  ColorDimYellow      = parseHtmlHex("#F67400")
  ColorDimBlue        = parseHtmlHex("#1D99F3")
  ColorDimMagenta     = parseHtmlHex("#9B59B6")
  ColorDimCyan        = parseHtmlHex("#1ABC9C")
  ColorDimWhite       = parseHtmlHex("#FCFCFC")

  ColorBrightBlack    = parseHtmlHex("#7F8C8D")
  ColorBrightRed      = parseHtmlHex("#C0392B")
  ColorBrightGreen    = parseHtmlHex("#1CDC9A")
  ColorBrightYellow   = parseHtmlHex("#FDBC4B")
  ColorBrightBlue     = parseHtmlHex("#3DAEE9")
  ColorBrightMagenta  = parseHtmlHex("#D87DFF")
  ColorBrightCyan     = parseHtmlHex("#19B898")
  ColorBrightWhite    = parseHtmlHex("#FFFFFF")

  AnsiDimColors = [
    ColorDimBlack, ColorDimRed, ColorDimGreen, ColorDimYellow,
    ColorDimBlue, ColorDimMagenta, ColorDimCyan, ColorDimWhite,
  ]

  AnsiBrightColors = [
    ColorBrightBlack, ColorBrightRed, ColorBrightGreen, ColorBrightYellow,
    ColorBrightBlue, ColorBrightMagenta, ColorBrightCyan, ColorBrightWhite,
  ]

  spaceRune = " ".runeAt(0)

  TabWidth = 8
  DefaultScrollbackLines* = 1000
  MaxScrollbackLineLen = 1000


type
  CellFlags = object
    style*: set[Style]
    fg*: Color = ColorDimWhite
    bg*: Color = ColorDimBlack

  TerminalCell* = object
    rune*: Rune = spaceRune
    flags*: CellFlags

  CellLine = seq[TerminalCell]
    ## a line that ended by explicit newline character (when it was created)

  ScrollbackHistory = object
    lines: seq[CellLine]
    segs: seq[int]  # the ring parallel to `lines`: visual rows the line takes at `width`
    first: int      # slot of the oldest stored line
    len: int        # number of stored lines, <= lines.len
    width: int      # the terminal width `segs`/`view` was built for
    view: seq[tuple[line, start: int]]  # visual row -> absolute line index, its first cell
    viewHead: int
    firstLine: int  # absolute index of the oldest stored line
    linesTotal: int # absolute number of lines ever pushed

  TerminalArrangement* = ref object
    size*: IVec2
    data*: seq[TerminalCell]  # y * size.x + x  ->  character at row y, col x

    cursor*: IVec2
    cursorFlags*: CellFlags
    cursorVisible*: bool = true

    ## replies to terminal queries from the program (DA1, background color, cursor position, ...).
    ## The caller drains this after `handleInput` and forwards it to the backend
    pendingResponses*: string

    ## colors reported to the program in OSC 10/11 (text foreground/background) queries
    queryForegroundColor*: Color = ColorDimWhite
    queryBackgroundColor*: Color = ColorDimBlack

    ## the inactive screen buffer, swapped with `data` on a switch to/from
    ## the alternate screen (CSI ?47/?1047/?1049, used by vim, nano, ...)
    altData: seq[TerminalCell]
    usingAltScreen*: bool

    ## scrollback history of the main screen, the alternate screen has none
    history: ScrollbackHistory

    ## whether each main screen row continues the logical line of the row above
    ## it (a wrap), so that rows can be joined back into `\n`-separated lines
    ## for the history and for the resize re-flow. The main screen only
    rowWrapped: seq[bool]

    ## the view is scrolled back by this many lines: 0 shows the live screen,
    ## larger values reach into `history` (see `viewCell` and `scrollView`)
    viewOffset: int

    savedCursor: tuple[main, alt: (IVec2, CellFlags)]  # for saving the cursor when switching between the main and alt screen buffers

    ## the scrolling region [scrollTop, scrollBottom] rows, 0-based, inclusive.
    ## scrollBottom < 0 means the last row of the screen (DECSTBM, CSI r)
    scrollTop: int32 = 0
    scrollBottom: int32 = -1

    originMode: bool = false  # DECOM: cursor addressing is relative to the scrolling region
    wrapAround: bool = true  # DECAWM: wrap to the next line at the right edge


proc `[]`*(this: TerminalArrangement, x, y: int): var TerminalCell =
  this.data[y * this.size.x + x]


proc `[]=`*(this: TerminalArrangement, x, y: int, v: TerminalCell) =
  this.data[y * this.size.x + x] = v


proc clear*(this: TerminalArrangement) =
  for c in this.data.mitems: c = TerminalCell()
  if not this.usingAltScreen:
    for y in this.rowWrapped.mitems: y = false


proc isBlank(c: TerminalCell): bool =
  ## carries no visible marks: can be dropped from the end of a logical line
  c.rune == spaceRune and c.flags.style == {} and c.flags.bg == ColorDimBlack


proc trimmedLen(cells: openArray[TerminalCell], keep = 0): int =
  ## the length of `cells` with trailing blank cells dropped, but at least `keep`
  result = cells.len
  while result > keep and cells[result - 1].isBlank: dec result


proc slot(this: ScrollbackHistory, i: int): int =
  ## the ring slot of the i-th oldest line
  (this.first + i) mod this.lines.len


proc extendView(this: var ScrollbackHistory, slot, absLine: int) =
  ## grows `segs`/`view` until the line occupies all the visual rows it needs at `width`
  let needed = max(1, (this.lines[slot].len + this.width - 1) div this.width)
  while this.segs[slot] < needed:
    this.view.add (absLine, this.segs[slot] * this.width)
    inc this.segs[slot]
  # compact away the rows of evicted lines when they pile up
  if this.viewHead > 0 and this.viewHead * 2 >= this.view.len:
    let live = this.view.len - this.viewHead
    if live > 0:
      moveMem(addr this.view[0], addr this.view[this.viewHead], live * sizeof(this.view[0]))
    this.view.setLen live
    this.viewHead = 0


proc pushOwned(this: var ScrollbackHistory, cells: sink CellLine, continuation: bool) =
  ## appends `cells` to the history
  if this.lines.len == 0: return

  if continuation and this.len > 0:
    let s = this.slot(this.len - 1)
    if this.lines[s].len + cells.len <= MaxScrollbackLineLen:
      # the segment extends the newest line, its visual rows may grow too
      var line = move this.lines[s]
      line.add cells
      this.lines[s] = line
      this.extendView(s, this.firstLine + this.len - 1)
      return
    # the line hit the length cap: force a split so memory stays bounded

  let s = (this.first + this.len) mod this.lines.len
  if this.len == this.lines.len:
    # the oldest line is overwritten: retire its visual rows first
    this.viewHead += this.segs[this.first]
    inc this.firstLine
    this.first = (this.first + 1) mod this.lines.len
  else:
    inc this.len

  this.lines[s] = cells
  this.segs[s] = 0
  inc this.linesTotal
  this.extendView(s, this.linesTotal - 1)


proc visualLen(this: ScrollbackHistory): int =
  ## the number of visual rows the stored lines take at the current width
  this.view.len - this.viewHead


proc cellAt(this: var ScrollbackHistory, row, x: int): TerminalCell =
  ## the cell at column `x` of the `row`-th visual row of the history (0 = the oldest)
  let e = this.view[this.viewHead + row]
  let line = this.lines[this.slot(e.line - this.firstLine)]
  let pos = e.start + x
  if pos < line.len: line[pos] else: TerminalCell()


proc clear(this: var ScrollbackHistory) =
  for r in this.lines.mitems: r.setLen(0)
  this.first = 0
  this.len = 0
  this.viewHead = 0
  this.view.setLen(0)
  this.firstLine = 0
  this.linesTotal = 0


proc resize(src: var seq[TerminalCell], oldSize, newSize: IVec2, skipTop: int32) =
  var res = newSeq[TerminalCell](newSize.x * newSize.y)
  for y in 0 ..< min(oldSize.y - skipTop, newSize.y):
    for x in 0 ..< min(oldSize.x, newSize.x):
      res[y * newSize.x + x] = src[(y + skipTop) * oldSize.x + x]
  src = ensureMove res


proc reflow(this: TerminalArrangement, v: IVec2) =
  ## rebuild the main screen and its history for the new size `v` the way a text editor re-flows (re-wraps) text
  let w1 = this.size.x.int
  let h1 = this.size.y.int
  let w2 = v.x.int
  let h2 = v.y.int

  # rows above the view top: the scrolled-back view stays anchored to them
  let anchorAbove = this.history.visualLen - this.viewOffset

  # collect the logical lines
  var lines: seq[CellLine]
  for i in 0 ..< this.history.len:
    lines.add move this.history.lines[this.history.slot(i)]

  var lastRow = h1 - 1
  while lastRow > this.cursor.y.int:
    var blank = not this.rowWrapped[lastRow]  # a continuation row is never dropped
    for x in lastRow * w1 ..< (lastRow + 1) * w1:
      if not this.data[x].isBlank: blank = false; break
    if not blank: break
    dec lastRow

  var cursorLine = -1   # the cursor's logical line index in `lines`
  var cursorOffset = 0  # its cell offset within the line
  var y = 0
  while y <= lastRow:
    let start = y
    var line: CellLine
    while true:
      # only the last row of a logical line may drop its trailing blanks:
      # middle rows keep their width or the re-wrap would shift columns.
      # The cursor row keeps its cells up to the cursor (the cell under it is
      # the next write position, not content)
      var n = w1
      if not (y + 1 <= lastRow and this.rowWrapped[y + 1]):
        n = trimmedLen(
          this.data.toOpenArray(y * w1, (y + 1) * w1 - 1),
          keep = if y == this.cursor.y.int: min(this.cursor.x.int, w1) else: 0,
        )
      if n > 0:
        line.add this.data.toOpenArray(y * w1, y * w1 + n - 1)
      inc y
      if y > lastRow or not this.rowWrapped[y]: break
    let cursorHere = this.cursor.y.int in start ..< y
    if start == 0 and lines.len > 0 and this.rowWrapped[0]:
      # the screen continues the last history line: a wrapped line scrolled
      # partially into the history (or a previous re-flow split it)
      let prevLen = lines[^1].len
      lines[^1].add line
      if cursorHere:
        cursorLine = lines.len - 1
        cursorOffset = prevLen + (this.cursor.y.int - start) * w1 + this.cursor.x.int
    else:
      if cursorHere:
        cursorLine = lines.len
        cursorOffset = (this.cursor.y.int - start) * w1 + this.cursor.x.int
      lines.add line

  # the visual rows every line takes at the new width
  var rows = newSeq[int](lines.len)
  var total = 0
  for i in 0 ..< lines.len:
    rows[i] = max(1, (lines[i].len + w2 - 1) div w2)
    total += rows[i]

  # the cursor's place in the new layout
  var cursorRow = 0
  var cursorCol = 0
  if cursorLine >= 0:
    var base = 0
    for i in 0 ..< cursorLine: base += rows[i]
    let line = lines[cursorLine]
    let off = min(cursorOffset, line.len)
    cursorRow = base + off div w2
    cursorCol = off mod w2
    if off == line.len and line.len > 0 and line.len mod w2 == 0:
      # the cursor exactly past the end of a full-width line: the deferred-wrap
      # state, one column past the last (resolved lazily by the next rune)
      dec cursorRow
      cursorCol = w2

  # the screen shows the last h2 rows
  # if the cursor would fall above them, the window moves up to keep it visible
  var screenStart = max(0, total - h2)
  if cursorRow < screenStart: screenStart = cursorRow

  this.history.clear()
  this.history.width = w2

  var
    newScreen = newSeq[TerminalCell](w2 * h2)
    newRowWrapped = newSeq[bool](h2)
    screenRow = 0
    covered = 0  # visual rows placed so far
    i = 0

  # write a logical line (starting from its cell `startCell`) onto the screen rows
  template putLine(line: CellLine, startCell: int) =
    let segs = max(1, (line.len - startCell + w2 - 1) div w2)
    for j in 0 ..< segs:
      if screenRow >= h2: break
      if j > 0: newRowWrapped[screenRow] = true  # a wrapped continuation row
      let a = startCell + j * w2
      let b = min(a + w2, line.len)
      if b > a:
        copyMem(addr newScreen[screenRow * w2], addr line[a], (b - a) * sizeof(TerminalCell))
      inc screenRow

  while i < lines.len and covered + rows[i] <= screenStart:
    this.history.pushOwned(move lines[i], continuation = false)
    covered += rows[i]
    inc i

  if i < lines.len and covered < screenStart:
    # the split line: the cells above the window stay in the history, the rest
    # become the top screen rows, a wrap continuation of the history part
    let cut = (screenStart - covered) * w2
    this.history.pushOwned(lines[i][0 ..< min(cut, lines[i].len)], continuation = false)
    newRowWrapped[0] = true
    putLine(lines[i], cut)
    inc i

  while i < lines.len:
    putLine(lines[i], 0)
    inc i

  this.data = newScreen
  this.rowWrapped = newRowWrapped
  
  if this.viewOffset > 0:
    this.viewOffset = (this.history.visualLen - anchorAbove).clamp(0, this.history.visualLen)
  else:
    this.viewOffset = 0
  
  this.cursor = ivec2(cursorCol.int32, (cursorRow - screenStart).clamp(0, h2 - 1).int32)


proc resize*(this: TerminalArrangement, v: IVec2) =
  if v == this.size: return

  if this.usingAltScreen: swap this.data, this.altData

  let removedRows = max(0, this.size.y - v.y).int
  let skipAlt = if this.usingAltScreen: min(removedRows, this.cursor.y.int) else: removedRows
  this.altData.resize(this.size, v, skipAlt.int32)

  this.reflow(v)

  this.size = v
  
  this.scrollTop = 0
  this.scrollBottom = -1

  if this.usingAltScreen: swap this.data, this.altData


proc newTerminalArrangement*(
  size = ivec2(80, 24), scrollbackLines = DefaultScrollbackLines
): TerminalArrangement =
  ## `scrollbackLines` limits the history of the main screen: the number of
  ## logical lines the ring buffer keeps, 0 disables the history
  let cap = scrollbackLines.max(0)
  new result
  result.history.lines = newSeq[CellLine](cap)
  result.history.segs = newSeq[int](cap)
  result.resize size


proc bottomMargin(this: TerminalArrangement): int32 =
  if this.scrollBottom < 0: this.size.y - 1 else: this.scrollBottom


proc clearRegion(this: TerminalArrangement, top, bottom: int) =
  ## fills the scrolling region rows with blank cells
  let w = this.size.x.int
  for i in top * w ..< (bottom + 1) * w:
    this.data[i] = TerminalCell()
  if not this.usingAltScreen:
    for y in top .. bottom:
      this.rowWrapped[y] = false


proc scrollDown(this: TerminalArrangement, amount = 1) =
  ## scroll the scrolling region up by `amount` lines:
  ## the content moves up, blank lines appear at the bottom of the region
  let top = this.scrollTop.int
  let bottom = this.bottomMargin.int
  let w = this.size.x.int

  # rows leaving the top of the main screen are kept in the scrollback history
  # (a partial scrolling region does not touch the screen top, its rows are lost)
  let leaving = min(amount, bottom - top + 1)
  if top == 0 and leaving > 0 and not this.usingAltScreen:
    let visualBefore = this.history.visualLen
    for y in 0 ..< leaving:
      let continuation = this.rowWrapped[y]
      var n = w
      if y + 1 < this.size.y and not this.rowWrapped[y + 1]:
        # the row ends its logical line: its trailing blanks would become
        # phantom rows after a re-wrap, drop them
        n = trimmedLen(this.data.toOpenArray(y * w, (y + 1) * w - 1))
      if n == 0:
        if not continuation:
          this.history.pushOwned(@[], continuation = false)  # a fully blank line
        continue
      this.history.pushOwned(@(this.data.toOpenArray(y * w, y * w + n - 1)), continuation)
    if this.viewOffset > 0:
      # keep the scrolled-back view anchored to the same content
      this.viewOffset = min(
        this.viewOffset + this.history.visualLen - visualBefore,
        this.history.visualLen,
      )

  if amount >= bottom - top + 1:
    this.clearRegion(top, bottom)
    return

  moveMem(
    this.data[top * w].addr,
    this.data[(top + amount) * w].addr,
    sizeof(TerminalCell) * (bottom - top + 1 - amount) * w,
  )
  for i in (bottom + 1 - amount) * w ..< (bottom + 1) * w:
    this.data[i] = TerminalCell()

  if not this.usingAltScreen:
    # the wrap-continuation flags move together with the rows
    moveMem(
      this.rowWrapped[top].addr,
      this.rowWrapped[top + amount].addr,
      bottom - top + 1 - amount,
    )
    for y in bottom + 1 - amount .. bottom:
      this.rowWrapped[y] = false


proc scrollUp(this: TerminalArrangement, amount = 1) =
  ## scroll the scrolling region down by `amount` lines:
  ## the content moves down, blank lines appear at the top of the region
  let top = this.scrollTop.int
  let bottom = this.bottomMargin.int
  let w = this.size.x.int

  if amount >= bottom - top + 1:
    this.clearRegion(top, bottom)
    return

  moveMem(
    addr this.data[(top + amount) * w],
    addr this.data[top * w],
    sizeof(TerminalCell) * (bottom - top + 1 - amount) * w,
  )
  for i in top * w ..< (top + amount) * w:
    this.data[i] = TerminalCell()

  if not this.usingAltScreen:
    moveMem(
      addr this.rowWrapped[top + amount],
      addr this.rowWrapped[top],
      bottom - top + 1 - amount,
    )
    for y in top ..< top + amount:
      this.rowWrapped[y] = false


proc clampCursor(this: TerminalArrangement) =
  this.cursor = ivec2(
    this.cursor.x.clamp(0, this.size.x - 1),
    this.cursor.y.clamp(0, this.size.y - 1),
  )


proc newline(this: TerminalArrangement) =
  if this.cursor.y == this.bottomMargin():
    this.scrollDown(1)
  elif this.cursor.y < this.size.y - 1:
    inc this.cursor.y


proc markLineStart(this: TerminalArrangement) =
  ## the cursor's row starts a new logical line (a line feed or an explicit
  ## positioning brought the cursor there), not a wrap continuation
  if not this.usingAltScreen:
    this.rowWrapped[this.cursor.y] = false


proc saveTo(this: TerminalArrangement, slot: var (IVec2, CellFlags)) =
  slot = (this.cursor, this.cursorFlags)

proc restoreFrom(this: TerminalArrangement, slot: var (IVec2, CellFlags)) =
  this.cursor = slot[0]
  this.clampCursor()
  this.cursorFlags = slot[1]

proc currentSavedCursor(this: TerminalArrangement): var (IVec2, CellFlags) =
  (if this.usingAltScreen: this.savedCursor.alt.addr else: this.savedCursor.main.addr)[]


proc switchScreen(this: TerminalArrangement, alt: bool) =
  if alt == this.usingAltScreen: return
  this.usingAltScreen = alt
  this.viewOffset = 0  # the alternate screen always shows live content
  swap this.data, this.altData


proc viewCell*(this: TerminalArrangement, x, y: int): TerminalCell =
  ## the visible cell at column `x` of view row `y` (0 = the top)
  let offset = this.viewOffset
  let histRows = this.history.visualLen
  if offset <= 0 or this.usingAltScreen or histRows == 0:
    return this[x, y]

  # the view is a size.y-rows window over [history visual rows, screen rows],
  # shifted `offset` rows up from the bottom
  let start = max(0, histRows - offset)
  let rowIdx = start + y
  if rowIdx < histRows:
    this.history.cellAt(rowIdx, x)
  else:
    this[x, rowIdx - histRows]


proc scrollView*(this: TerminalArrangement, lines: int) =
  if this.usingAltScreen: return
  this.viewOffset = (this.viewOffset + lines).clamp(0, this.history.visualLen)

proc scrollToBottom*(this: TerminalArrangement) =
  this.viewOffset = 0

proc scrolledBack*(this: TerminalArrangement): bool =
  this.viewOffset > 0 and not this.usingAltScreen


proc clearScrollback*(this: TerminalArrangement) =
  this.history.clear()
  this.viewOffset = 0


proc ansiColor256(n: int): Color =
  ## xterm 256-color palette
  if n notin 0 .. 255: ColorDimWhite
  elif n < 8: AnsiDimColors[n]
  elif n < 16: AnsiBrightColors[n - 8]
  elif n < 232:
    const CubeLevels = [0'u8, 95, 135, 175, 215, 255]
    let i = n - 16
    rgb(CubeLevels[i div 36], CubeLevels[i div 6 mod 6], CubeLevels[i mod 6]).asColor
  else:
    let v = (8 + 10 * (n - 232)).uint8
    rgb(v, v, v).asColor


proc sgrRgbColor(r, g, b: int): Color =
  rgb(r.clamp(0, 255).uint8, g.clamp(0, 255).uint8, b.clamp(0, 255).uint8).asColor


proc parseSgrParams(s: string, first, last: int): seq[int] =
  ## [first, last) split on ';' (':' subparameters treated the same), missing/invalid -> 0
  for part in s[first ..< last].split({';', ':'}):
    result.add (try: parseInt(part) except: 0)
  if result.len == 0: result.add 0  # a bare "CSI m" is SGR 0


const
  ## SGR 1-9 turn styles on (italic shares its bit with underscore, as in std/terminal)
  SgrStyleOn: array[1 .. 9, set[Style]] = [
    {styleBright}, {styleDim}, {styleItalic}, {styleUnderscore}, {styleBlink},
    {styleBlinkRapid}, {styleReverse}, {styleHidden}, {styleStrikethrough},
  ]
  ## SGR 22-29 turn them off (21 = doubly underscored and 26 carry no style bit)
  SgrStyleOff: array[22 .. 29, set[Style]] = [
    {styleBright, styleDim}, {styleItalic}, {styleUnderscore}, {styleBlink, styleBlinkRapid},
    {}, {styleReverse}, {styleHidden}, {styleStrikethrough},
  ]


proc applySgr(this: TerminalArrangement, params: openArray[int]) =
  var i = 0
  while i < params.len:
    let p = params[i]

    case p
    of 0: this.cursorFlags = CellFlags()
    of 1 .. 9: this.cursorFlags.style.incl SgrStyleOn[p]
    of 22 .. 29: this.cursorFlags.style.excl SgrStyleOff[p]

    of 30..37: this.cursorFlags.fg = AnsiDimColors[p - 30]
    of 38, 48:
      # 38/48;5;n -> 256-color, 38/48;2;r;g;b -> rgb
      if i + 2 < params.len and params[i + 1] == 5:
        let c = ansiColor256(params[i + 2])
        if p == 38: this.cursorFlags.fg = c
        else: this.cursorFlags.bg = c
        inc i, 2
      elif i + 4 < params.len and params[i + 1] == 2:
        let c = sgrRgbColor(params[i + 2], params[i + 3], params[i + 4])
        if p == 38: this.cursorFlags.fg = c
        else: this.cursorFlags.bg = c
        inc i, 4
    of 39: this.cursorFlags.fg = ColorDimWhite
    of 40..47: this.cursorFlags.bg = AnsiDimColors[p - 40]
    of 49: this.cursorFlags.bg = ColorDimBlack
    of 90..97: this.cursorFlags.fg = AnsiBrightColors[p - 90]
    of 100..107: this.cursorFlags.bg = AnsiBrightColors[p - 100]
    else: discard

    inc i


proc erasedCell(this: TerminalArrangement): TerminalCell =
  ## erasing fills with the current background (background color erase)
  TerminalCell(flags: CellFlags(bg: this.cursorFlags.bg))


proc eraseInLine(this: TerminalArrangement, mode: int) =
  case mode
  of 0:  # cursor to end of line
    for x in this.cursor.x.min(this.size.x - 1) ..< this.size.x:
      this[x, this.cursor.y] = this.erasedCell()
  of 1:  # start of line to cursor
    for x in 0 .. this.cursor.x.min(this.size.x - 1):
      this[x, this.cursor.y] = this.erasedCell()
  of 2:  # whole line
    for x in 0 ..< this.size.x:
      this[x, this.cursor.y] = this.erasedCell()
    this.markLineStart()  # a blank row is no continuation
  else: discard


proc eraseInDisplay(this: TerminalArrangement, mode: int) =
  template clearRows(a, b: int) =
    for y in a ..< b:
      for x in 0 ..< this.size.x:
        this[x, y] = this.erasedCell()
      if not this.usingAltScreen: this.rowWrapped[y] = false

  case mode
  of 0:  # cursor to end of screen
    this.eraseInLine(0)
    clearRows(this.cursor.y + 1, this.size.y)
  of 1:  # start of screen to cursor
    this.eraseInLine(1)
    clearRows(0, this.cursor.y)
  of 2:  # whole screen
    clearRows(0, this.size.y)
  of 3:  # the saved lines only: the scrollback history (xterm's CSI 3 J)
    this.clearScrollback()
  else: discard


proc applyCsi(this: TerminalArrangement, paramsStr: string, final: char) =
  let isPrivate = paramsStr.len > 0 and paramsStr[0] == '?'
  # an empty parameter list means 0 (so a bare "CSI m" is a reset)
  let params = parseSgrParams(paramsStr, if isPrivate: 1 else: 0, paramsStr.len)

  template n(idx, def: int): int =
    if params.len > idx and params[idx] > 0: params[idx] else: def

  template m(idx: int): int =
    if params.len > idx: params[idx] else: 0

  if isPrivate:
    case final
    of 'h', 'l':
      let isAlt = final == 'h'
      for p in params:
        case p
        of 25:
          this.cursorVisible = isAlt
        of 6:  # DECOM, origin mode
          this.originMode = isAlt
          this.cursor = ivec2(0, if isAlt: this.scrollTop else: 0)
        of 7:
          this.wrapAround = isAlt  # DECAWM
        of 47:
          this.switchScreen isAlt
        of 1047:
          # like 47, but the alternate screen is cleared when leaving it
          if not isAlt and this.usingAltScreen: this.clear()
          this.switchScreen isAlt
        of 1048:
          if isAlt: this.saveTo(this.savedCursor.main)
          else: this.restoreFrom(this.savedCursor.main)
        of 1049:
          if isAlt:
            this.saveTo(this.savedCursor.main)
            this.switchScreen(alt=true)
            this.clear()
          else:
            this.switchScreen(alt=false)
            this.restoreFrom(this.savedCursor.main)
        else: discard  # 2004 bracketed paste, 1000..1006 mouse reporting, ...: ignored
    of 'u':
      if paramsStr == "?":  # kitty keyboard protocol query -> not supported
        this.pendingResponses.add "\x1b[?0u"
    else: discard

  elif paramsStr.len > 0 and paramsStr[0] == '>':
    case final
    of 'c':  # DA2, identify as a generic xterm-like terminal
      this.pendingResponses.add "\x1b[>0;276;0c"
    of 'q':  # XTVERSION
      this.pendingResponses.add "\x1bP>|cgsand\x1b\\"
    else: discard

  elif paramsStr.len > 0 and paramsStr[0] in {'=', '<'}:
    # kitty keyboard protocol set (CSI = flags ; mode u) / pop (CSI < u), DA3 (CSI = c): not supported
    discard

  else:
    case final
    of 'A':
      # stops at the top margin when the cursor starts at or below it
      let limit = if this.cursor.y >= this.scrollTop: this.scrollTop else: 0
      this.cursor.y = max(this.cursor.y.int - n(0, 1), limit.int).int32
    of 'B':
      # stops at the bottom margin when the cursor starts at or above it
      let limit = if this.cursor.y <= this.bottomMargin(): this.bottomMargin() else: this.size.y - 1
      this.cursor.y = min(this.cursor.y.int + n(0, 1), limit.int).int32
    of 'C': this.cursor.x = min(this.cursor.x.int + n(0, 1), this.size.x - 1).int32
    of 'D': this.cursor.x = max(this.cursor.x.int - n(0, 1), 0).int32
    of 'E':
      this.cursor.x = 0
      this.cursor.y = min(this.cursor.y.int + n(0, 1), this.size.y - 1).int32
      this.markLineStart()
    of 'F':
      this.cursor.x = 0
      this.cursor.y = max(this.cursor.y.int - n(0, 1), 0).int32
      this.markLineStart()
    of 'G': this.cursor.x = (n(0, 1) - 1).clamp(0, this.size.x - 1).int32
    of 'H', 'f':
      # in origin mode addressing is relative to the scrolling region
      let top = if this.originMode: this.scrollTop else: 0
      let bottom = if this.originMode: this.bottomMargin() else: this.size.y - 1
      this.cursor.y = (top + n(0, 1) - 1).clamp(top.int, bottom.int).int32
      this.cursor.x = (n(1, 1) - 1).clamp(0, this.size.x - 1).int32
      this.markLineStart()
    of 'd':
      let top = if this.originMode: this.scrollTop else: 0
      let bottom = if this.originMode: this.bottomMargin() else: this.size.y - 1
      this.cursor.y = (top + n(0, 1) - 1).clamp(top.int, bottom.int).int32
      this.markLineStart()
    of 'J': this.eraseInDisplay(m(0))
    of 'K': this.eraseInLine(m(0))
    of 'S': this.scrollDown(n(0, 1))
    of 'T': this.scrollUp(n(0, 1))
    of 'r':
      # DECSTBM: the scrolling region [top; bottom], 1-based inclusive
      let top = n(0, 1) - 1
      let bottom = n(1, this.size.y) - 1
      if top in 0 ..< this.size.y.int and bottom in 0 ..< this.size.y.int and top < bottom:
        this.scrollTop = top.int32
        this.scrollBottom = bottom.int32
        # the cursor homes, to the region top in origin mode
        this.cursor = ivec2(0, if this.originMode: top.int32 else: 0'i32)
        this.markLineStart()
    of 'm': this.applySgr(params)
    of 'c':  # DA1, Primary Device Attributes -> plain VT102
      this.pendingResponses.add "\x1b[?6c"
    of 'n':  # DSR, Cursor Position Report
      if m(0) == 6:
        let x = min(this.cursor.x, this.size.x - 1)
        this.pendingResponses.add "\x1b[" & $(this.cursor.y + 1) & ";" & $(x + 1) & "R"
    of 's': this.saveTo(this.currentSavedCursor)
    of 'u': this.restoreFrom(this.currentSavedCursor)
    else: discard  # unsupported sequences are ignored


proc rgbQueryColor(c: Color): string =
  ## "rr/gg/bb" color as used in OSC color responses
  proc h(v: float32): string = (v * 255).round.int.toHex(2).toLowerAscii
  h(c.r) & "/" & h(c.g) & "/" & h(c.b)


proc handleStringSequence(this: TerminalArrangement, kind: char, payload: string) =
  ## handles terminated string escape sequences (OSC / DCS / ...) we respond to
  if kind == ']':
    # OSC color queries: fish uses the background color to pick light/dark syntax colors
    if payload.startsWith "10;?":
      this.pendingResponses.add "\x1b]10;rgb:" & this.queryForegroundColor.rgbQueryColor & "\x1b\\"
    elif payload.startsWith "11;?":
      this.pendingResponses.add "\x1b]11;rgb:" & this.queryBackgroundColor.rgbQueryColor & "\x1b\\"

  elif kind == 'P':
    # XTGETTCAP: report every queried terminfo capability as not found
    if payload.startsWith "+q":
      this.pendingResponses.add "\x1bP0+r\x1b\\"


proc handleInput*(this: TerminalArrangement, s: string, i: var int) =
  ## Consumes as much of `s` starting at ``i`` as possible.
  ## `i` is advanced past everything consumed.
  ## if `s` ends in the middle of an escape sequence or a rune, `i` is left at its start,
  ## so the caller can prepend the unconsumed tail to the next chunk.
  while i < s.len:
    if s[i] == '\27':
      if i + 1 >= s.len: return

      case s[i + 1]
      of '[':
        # CSI: parameter bytes (0x30..0x3F), optional intermediate bytes (0x20..0x2F), final byte (0x40..0x7E)
        var j = i + 2
        while j < s.len and s[j].byte in 0x30'u8..0x3F'u8: inc j
        let paramsEnd = j
        while j < s.len and s[j].byte in 0x20'u8..0x2F'u8: inc j
        if j >= s.len: return

        if s[j].byte in 0x40'u8..0x7E'u8:
          this.applyCsi(s[i + 2 ..< paramsEnd], s[j])
          i = j + 1
        else:
          inc i  # malformed, drop just the escape byte

      of ']', 'P', 'X', '^', '_':
        # OSC / DCS / SOS / PM / APC, terminated by BEL or ESC \
        var j = i + 2
        while true:
          if j >= s.len: return
          if s[j] == '\7':
            this.handleStringSequence(s[i + 1], s[i + 2 ..< j])
            inc j
            break
          if s[j] == '\27':
            if j + 1 >= s.len: return
            this.handleStringSequence(s[i + 1], s[i + 2 ..< j])
            inc j, 2
            break
          inc j
        i = j

      of '(', ')', '#', '%':
        # charset selection: ESC ( <char>
        if i + 2 >= s.len: return
        inc i, 3

      of '7':  # DECSC save cursor
        this.saveTo(this.currentSavedCursor)
        inc i, 2

      of '8':  # DECRC restore cursor
        this.restoreFrom(this.currentSavedCursor)
        inc i, 2

      of 'D':  # IND, index: one line down, scrolls the region at its bottom
        this.newline()
        this.markLineStart()
        inc i, 2

      of 'E':  # NEL, next line
        this.cursor.x = 0
        this.newline()
        this.markLineStart()
        inc i, 2

      of 'M':  # RI, reverse index: one line up, scrolls the region at its top
        if this.cursor.y == this.scrollTop:
          this.scrollUp(1)
        elif this.cursor.y > 0:
          dec this.cursor.y
        inc i, 2

      else:
        inc i, 2

    elif s[i] < ' ' or s[i] == '\127':
      case s[i]
      of '\l':
        this.cursor.x = 0
        this.newline()
        this.markLineStart()
      of '\c': this.cursor.x = 0
      of '\t': this.cursor.x = min(this.cursor.x + (TabWidth - this.cursor.x mod TabWidth), this.size.x - 1)
      of '\8': this.cursor.x = max(this.cursor.x - 1, 0)
      else: discard  # bell and other control chars
      inc i

    else:
      let rl = s.runeLenAt(i)
      if i + rl > s.len: return  # truncated rune

      if this.cursor.x >= this.size.x:
        # deferred wrap: the line exactly filled the last column
        if this.wrapAround:
          this.cursor.x = 0
          this.newline()
          if not this.usingAltScreen:
            this.rowWrapped[this.cursor.y] = true
        else:
          this.cursor.x = this.size.x - 1

      this[this.cursor.x.int, this.cursor.y.int] = TerminalCell(rune: s.runeAt(i), flags: this.cursorFlags)
      inc this.cursor.x  # may reach size.x, wrapped lazily by the next rune
      i += rl
