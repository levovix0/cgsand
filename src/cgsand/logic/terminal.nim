import std/[unicode, terminal, strutils]
import pkg/[vmath, chroma]

const
  ColorDimBlack      = parseHtmlHex("#202223")
  ColorDimRed        = parseHtmlHex("#ED1515")
  ColorDimGreen      = parseHtmlHex("#11D116")
  ColorDimYellow     = parseHtmlHex("#F67400")
  ColorDimBlue       = parseHtmlHex("#1D99F3")
  ColorDimMagenta    = parseHtmlHex("#9B59B6")
  ColorDimCyan       = parseHtmlHex("#1ABC9C")
  ColorDimWhite      = parseHtmlHex("#FCFCFC")
  
  ColorBrightBlack   = parseHtmlHex("#7F8C8D")
  ColorBrightRed     = parseHtmlHex("#C0392B")
  ColorBrightGreen   = parseHtmlHex("#1CDC9A")
  ColorBrightYellow  = parseHtmlHex("#FDBC4B")
  ColorBrightBlue    = parseHtmlHex("#3DAEE9")
  ColorBrightMagenta = parseHtmlHex("#D87DFF")
  ColorBrightCyan    = parseHtmlHex("#19B898")
  ColorBrightWhite   = parseHtmlHex("#FFFFFF")

  AnsiDimColors* = [
    ColorDimBlack, ColorDimRed, ColorDimGreen, ColorDimYellow,
    ColorDimBlue, ColorDimMagenta, ColorDimCyan, ColorDimWhite,
  ]

  AnsiBrightColors* = [
    ColorBrightBlack, ColorBrightRed, ColorBrightGreen, ColorBrightYellow,
    ColorBrightBlue, ColorBrightMagenta, ColorBrightCyan, ColorBrightWhite,
  ]


type
  TerminalCursor* = IVec2

  CellFlags = object
    style*: set[Style]
    fg*: Color = ColorDimWhite
    bg*: Color = ColorDimBlack

  TerminalCell* = object
    rune*: Rune = " ".runeAt(0)
    flags*: CellFlags

  TerminalArrangement* = ref object
    size*: IVec2
    data*: seq[TerminalCell]  # y * size.x + x  ->  character at row y, col x
    cursor*: TerminalCursor
    cursorFlags*: CellFlags


const MaxTerminalSize = ivec2(10000)  # in characters
const TabWidth = 8



proc `[]`*(this: TerminalArrangement, pos: IVec2): var TerminalCell =
  this.data[pos.y * this.size.x + pos.x]

proc `[]`*(this: TerminalArrangement, x, y: int): var TerminalCell =
  this.data[y * this.size.x + x]


proc `[]=`*(this: TerminalArrangement, pos: IVec2, v: TerminalCell) =
  (this[pos]) = v

proc `[]=`*(this: TerminalArrangement, x, y: int, v: TerminalCell) =
  (this[x, y]) = v


proc clear*(this: TerminalArrangement, to = TerminalCell()) =
  for x in this.data.mitems: x = to

proc resize*(this: TerminalArrangement, v: IVec2) =
  let v = ivec2(v.x.clamp(1, MaxTerminalSize.x), v.y.clamp(1, MaxTerminalSize.y))

  let prevData = move this.data
  this.data = newSeqUninit[TerminalCell](v.x * v.y)
  clear this

  for y in 0..<min(this.size.y, v.y):
    for x in 0..<min(this.size.x, v.x):
      this.data[y * v.x + x] = prevData[y * this.size.x + x]

  this.size = v
  this.cursor = ivec2(this.cursor.x.clamp(0, this.size.x - 1), this.cursor.y.clamp(0, this.size.y - 1))


proc scrollDown*(this: TerminalArrangement, ammount = 1) =
  if ammount >= this.size.y:
    clear this
    return
  
  moveMem(this.data[0].addr, this.data[ammount * this.size.x].addr, sizeof(TerminalCell) * (this.size.y - ammount) * this.size.x)
  for i in ((this.size.y - ammount) * this.size.x)..<(this.size.y * this.size.x):
    this.data[i] = TerminalCell()


proc incCursorPos*(this: TerminalArrangement) =
  inc this.cursor.x

  if this.cursor.x >= this.size.x:
    this.cursor.x = 0
    inc this.cursor.y

  if this.cursor.y >= this.size.y:
    this.scrollDown(this.size.y - this.cursor.y + 1)
    this.cursor.y = this.size.y - 1


proc newline*(this: TerminalArrangement) =
  inc this.cursor.y
  if this.cursor.y >= this.size.y:
    this.scrollDown(this.cursor.y - this.size.y + 1)
    this.cursor.y = this.size.y - 1


proc ansiColor256(n: int): Color =
  ## xterm 256-color palette
  if n < 0 or n > 255: ColorDimWhite
  elif n < 8: AnsiDimColors[n]
  elif n < 16: AnsiBrightColors[n - 8]
  elif n < 232:
    const CubeLevels = [0'f32, 95, 135, 175, 215, 255]
    let i = n - 16
    color(
      CubeLevels[i div 36] / 255,
      CubeLevels[i div 6 mod 6] / 255,
      CubeLevels[i mod 6] / 255,
    )
  else:
    let v = (8 + 10 * (n - 232)).float32 / 255
    color(v, v, v)


proc sgrRgbColor(r, g, b: int): Color =
  color(
    r.clamp(0, 255).float32 / 255,
    g.clamp(0, 255).float32 / 255,
    b.clamp(0, 255).float32 / 255,
  )


proc parseSgrParams(s: string, first, last: int): seq[int] =
  ## [first, last) split on ';' (':' subparameters treated the same), missing/invalid -> 0
  var cur = ""
  for i in first ..< last:
    if s[i] in {';', ':'}:
      result.add (try: parseInt(cur) except: 0)
      cur.setLen 0
    else:
      cur.add s[i]
  result.add (try: parseInt(cur) except: 0)


proc applySgr(this: TerminalArrangement, params: openArray[int]) =
  var i = 0
  while i < params.len:
    let p = params[i]

    case p
    of 0: this.cursorFlags = CellFlags()
    of 1: this.cursorFlags.style.incl styleBright
    of 2: this.cursorFlags.style.incl styleDim
    of 3: this.cursorFlags.style.incl styleItalic
    of 4: this.cursorFlags.style.incl styleUnderscore
    of 5: this.cursorFlags.style.incl styleBlink
    of 6: this.cursorFlags.style.incl styleBlinkRapid
    of 7: this.cursorFlags.style.incl styleReverse
    of 8: this.cursorFlags.style.incl styleHidden
    of 9: this.cursorFlags.style.incl styleStrikethrough

    of 21: discard  # doubly underscored, there is no such style yet
    of 22: this.cursorFlags.style.excl {styleBright, styleDim}
    of 23: this.cursorFlags.style.excl styleItalic
    of 24: this.cursorFlags.style.excl styleUnderscore
    of 25: this.cursorFlags.style.excl {styleBlink, styleBlinkRapid}
    of 27: this.cursorFlags.style.excl styleReverse
    of 28: this.cursorFlags.style.excl styleHidden
    of 29: this.cursorFlags.style.excl styleStrikethrough

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


proc handleInput*(this: TerminalArrangement, s: string, i: var int) =
  ## Consumes as much of `s` starting at ``i`` as possible.
  ## `i` is advanced past everything consumed.
  ## if `s` ends in the middle of an escape sequence or a rune, ``i`` is left at its start,
  ## so the caller can prepend the unconsumed tail to the next chunk.
  while i < s.len:
    if s[i] == '\27':
      if i + 1 >= s.len: return

      case s[i + 1]
      of '[':
        # CSI: parameter bytes (0x20..0x3F), then a final byte (0x40..0x7E)
        var j = i + 2
        while j < s.len and s[j].byte in 0x20'u8..0x3F'u8: inc j
        if j >= s.len: return

        if s[j].byte in 0x40'u8..0x7E'u8:
          if s[j] == 'm': this.applySgr(parseSgrParams(s, i + 2, j))
          # other sequences (cursor movement, erasing, ...) are skipped
          i = j + 1
        else:
          inc i  # malformed, drop just the escape byte

      of ']', 'P', 'X', '^', '_':
        # OSC / DCS / SOS / PM / APC, terminated by BEL or ESC \
        var j = i + 2
        while true:
          if j >= s.len: return
          if s[j] == '\7':
            inc j
            break
          if s[j] == '\27':
            if j + 1 >= s.len: return
            inc j, 2
            break
          inc j
        i = j

      of '(', ')', '#', '%':
        # charset selection: ESC ( <char>
        if i + 2 >= s.len: return
        inc i, 3

      else:
        inc i, 2

    elif s[i] < ' ' or s[i] == '\127':
      case s[i]
      of '\l':
        this.cursor.x = 0
        this.newline()
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
        this.cursor.x = 0
        this.newline()

      this[this.cursor] = TerminalCell(rune: s.runeAt(i), flags: this.cursorFlags)
      inc this.cursor.x  # may reach size.x, wrapped lazily by the next rune
      i += rl


