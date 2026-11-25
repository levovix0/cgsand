## hex editor: byte-level view and editing of binary files, shown in the
## editor pane instead of the code editor when an opened file looks binary
## (see logic/binary_files.nim).
##
## layout of a row: an 8-digit offset, 16 hex byte pairs (grouped 8+8) and
## the same bytes as ASCII characters (unprintable bytes as "."). Editing
## overwrites the byte under the cursor: hex digits type nibbles in the hex
## column, characters type bytes in the ASCII column; Backspace/Delete
## remove bytes. Every change is saved to disk like in the code editor.


import std/[os, strutils, sequtils, unicode]
import pkg/[vmath]
import pkg/toscel/[focus]
import pkg/sigui/[uibase, events, scrollArea, mouseArea]
import pkg/sigui/rendering/rice_backend
import ../logic/[configuration, binary_files, asyncio, file_openers, shortcuts]


type
  HexEditingArea* = enum
    ## which column of the hex view the keyboard input goes to
    haHex   ## the hex byte pairs column
    haAscii ## the ASCII characters column

  HexUndoKind* = enum
    huSet     ## a byte value was overwritten (typing a digit or a character)
    huDelete  ## a byte was removed (Backspace/Delete)

  HexUndo* = object
    kind*: HexUndoKind
    offset*: int
    byteVal*: uint8

  HexEditorContent* = ref object of Uiobj
    font*: Property[Font]
    path*: Property[string]   ## path to save on disk (if empty, nothing is opened)

    data*: seq[uint8]
      ## bytes of the opened file, edited in place

    cursor*: int      ## byte offset of the editing cursor
    nibble*: int      ## which nibble the cursor is on in the hex column: 0 = high, 1 = low
    area*: HexEditingArea
    anchor*: int      ## selection anchor byte offset, -1 = no selection

    undoHistory: seq[HexUndo]
    lastEditOffset: int   ## offset of the byte edited by the previous keystroke,
                          ## so typing both nibbles of one byte is one undo step

    modifierKeysDown: set[Key]
    errorMsg*: string     ## shown instead of the bytes when the file could not be read

    cellGridCache: Arrangement
      ## typeset of the template row, see `cellGrid`

  HexEditor* = ref object of Uiobj
    content*: HexEditorContent
    scrollArea*: ScrollArea
    openedFile*: Event[void]
      ## emitted when a file is opened in this editor (used to switch the editor pane)

  HexEditorFileOpener* = ref object of FileOpener
    editor*: HexEditor


const
  ScrollBarWidth = 5'f32
  BytesPerRow = 16
  OffsetDigits = 8
  LeftPadding = 8'f32
  CaretWidth = 1.5'f32
  HexMaxUndoHistory = 1000
  HexEditorMaxSize = 64 * 1024 * 1024
    ## files above this size are not opened in the hex editor and fall back
    ## to the code editor, which opens them as text like it always did


func buildHexRowTemplate(): string =
  ## 8-digit offset, 2 spaces, 16 hex pairs ("XX " each plus one extra space
  ## between the two 8-byte groups), 2 spaces, 16 ASCII cells
  result = "0".repeat(OffsetDigits) & "  "
  for i in 0 ..< BytesPerRow:
    if i == 8: result.add ' '
    result.add "00"
    if i < BytesPerRow - 1: result.add ' '
  result.add "  "
  result.add "0".repeat(BytesPerRow)


const
  OffsetCharI = 0                              ## first cell of the offset column
  HexCharI = OffsetDigits + 2                  ## first cell of the hex column
  AsciiCharI = HexCharI + BytesPerRow * 3 + 2  ## first cell of the ASCII column

  HexRowTemplate = buildHexRowTemplate()
    ## a row of placeholder bytes; all rows share this structure, so its
    ## typeset gives the exact position of every cell of every row


registerComponent HexEditor
registerComponent HexEditorContent


proc cellGrid(this: HexEditorContent): Arrangement =
  ## glyph positions of the template row in logical pixels. Positions cannot
  ## be derived from a single character width: fonts like AdwaitaMono have a
  ## fractional advance (7.25px at size 12) and the typesetter rounds each
  ## glyph position to whole pixels, so the accumulated offset of a long row
  ## drifts away from a uniform grid
  if this.cellGridCache == nil:
    this.cellGridCache = typeset(this.font[], HexRowTemplate)
  this.cellGridCache

proc cellX(this: HexEditorContent, charI: int): float32 =
  LeftPadding + this.cellGrid[].selectionRects[charI].x

proc cellW(this: HexEditorContent, charI: int): float32 =
  this.cellGrid[].selectionRects[charI].w

proc hexCharI(byteInRow: int): int =
  ## character cell of the byte's hex pair (its high digit)
  HexCharI + byteInRow * 3 + byteInRow div 8

proc asciiCharI(byteInRow: int): int =
  AsciiCharI + byteInRow

proc rowHeightPx(this: HexEditorContent): float32 =
  ## the same line height metric the code editor uses for its rows
  let font = this.font[]
  font.size * ((font.typeface.ascent / font.typeface.scale) +
    max(font.typeface.lineGap / font.typeface.scale, 0.25))

proc rowCount(this: HexEditorContent): int =
  max((this.data.len + BytesPerRow - 1) div BytesPerRow, 1)

proc byteCellRect*(this: HexEditorContent, byteInRow: int, area: HexEditingArea): Rect =
  ## rect of the byte's cell in the hex or ASCII column, in content coordinates
  ## (useful for tests that click on specific bytes)
  let rowH = this.rowHeightPx()
  case area
  of haHex:
    let ci = hexCharI(byteInRow)
    rect(vec2(this.cellX(ci), 0), vec2(this.cellX(ci + 1) + this.cellW(ci + 1) - this.cellX(ci), rowH))
  of haAscii:
    let ci = asciiCharI(byteInRow)
    rect(vec2(this.cellX(ci), 0), vec2(this.cellW(ci), rowH))


proc parentHexEditor(this: HexEditorContent): HexEditor =
  var obj: Uiobj = this
  while obj != nil:
    if obj of HexEditor: return HexEditor(obj)
    obj = obj.parent


proc visibleRows(this: HexEditorContent): int =
  ## how many rows fit in the editor viewport (for PageUp/PageDown)
  let editor = this.parentHexEditor()
  let h = if editor != nil and editor.scrollArea != nil: editor.scrollArea.h[] else: 600'f32
  max((h / this.rowHeightPx()).int, 1)


proc updateHeight*(this: HexEditorContent) =
  this.h[] = this.rowCount().float32 * this.rowHeightPx()


proc selectionRange*(this: HexEditorContent): Slice[int] =
  ## selected byte offsets (inclusive), an empty slice when there is none
  if this.anchor < 0 or this.anchor == this.cursor: return 1 .. 0
  result = min(this.anchor, this.cursor) .. max(this.anchor, this.cursor)


proc hasSelection*(this: HexEditorContent): bool =
  let sel = this.selectionRange()
  sel.a <= sel.b


proc pushUndo(this: HexEditorContent, u: HexUndo) =
  if this.undoHistory.len >= HexMaxUndoHistory:
    this.undoHistory.delete(0)
  this.undoHistory.add u


proc saveFile*(this: HexEditorContent) =
  ## writes the edited bytes to disk asynchronously
  if this.path[].len == 0: return
  var content = newString(this.data.len)
  if this.data.len > 0:
    copyMem(content[0].addr, this.data[0].addr, this.data.len)
  scheduleFileSave(this.path[], content)


proc setClipboardText(this: HexEditorContent, text: string) =
  ## clipboard write that survives platforms with no working clipboard
  try:
    this.root.clipboardText = text
  except NilAccessDefect:
    discard


proc copySelection(this: HexEditorContent) =
  ## copies the selected bytes as hex, or the byte under the cursor
  if this.data.len == 0: return
  let sel = this.selectionRange()
  if sel.a > sel.b:
    this.setClipboardText(toHex(this.data[this.cursor], 2))
  else:
    var text: string
    for i in sel.a .. sel.b:
      if text.len > 0: text.add ' '
      text.add toHex(this.data[i], 2)
    this.setClipboardText(text)


proc redrawNow(this: HexEditorContent) =
  this.updateHeight()
  redraw(this)


# ----- editing -----

proc setNibble(this: HexEditorContent, digit: uint8) =
  ## writes a hex digit (0..15) into the nibble under the cursor; after the
  ## low nibble the cursor advances to the next byte
  if this.data.len == 0: return
  this.cursor = this.cursor.clamp(0, this.data.high)
  if this.lastEditOffset != this.cursor:
    this.pushUndo HexUndo(kind: huSet, offset: this.cursor, byteVal: this.data[this.cursor])
    this.lastEditOffset = this.cursor
  if this.nibble == 0:
    this.data[this.cursor] = (digit shl 4) or (this.data[this.cursor] and 0x0F'u8)
    this.nibble = 1
  else:
    this.data[this.cursor] = (this.data[this.cursor] and 0xF0'u8) or digit
    if this.cursor < this.data.high:
      inc this.cursor
      this.nibble = 0
  redraw(this)
  this.saveFile()


proc setByteChar(this: HexEditorContent, value: uint8) =
  ## overwrites the byte under the cursor with a typed character and advances
  if this.data.len == 0: return
  this.cursor = this.cursor.clamp(0, this.data.high)
  if this.lastEditOffset != this.cursor:
    this.pushUndo HexUndo(kind: huSet, offset: this.cursor, byteVal: this.data[this.cursor])
    this.lastEditOffset = this.cursor
  this.data[this.cursor] = value
  if this.cursor < this.data.high:
    inc this.cursor
  redraw(this)
  this.saveFile()


proc deleteRange(this: HexEditorContent, first, last: int): bool =
  ## removes bytes first..last (inclusive), remembering each byte so undo
  ## re-inserts them in ascending order
  if first < 0 or last >= this.data.len or first > last: return false
  for i in countdown(last, first):
    this.pushUndo HexUndo(kind: huDelete, offset: i, byteVal: this.data[i])
  this.data.delete(first .. last)
  this.cursor = first.clamp(0, max(this.data.high, 0))
  result = true


proc undoLast*(this: HexEditorContent) =
  if this.undoHistory.len == 0: return
  let u = this.undoHistory.pop()
  this.lastEditOffset = -1
  case u.kind
  of huSet:
    if u.offset < this.data.len:
      this.data[u.offset] = u.byteVal
      this.cursor = u.offset
      this.nibble = 0
  of huDelete:
    if u.offset <= this.data.len:
      this.data.insert(u.byteVal, u.offset)
      this.cursor = u.offset
      this.nibble = 0
  this.anchor = -1
  this.redrawNow()
  this.saveFile()


# ----- cursor movement -----

proc moveCursor(this: HexEditorContent, newCursor: int, extend: bool, newNibble = 0) =
  ## moves the cursor, extending or clearing the selection
  if extend:
    if this.anchor < 0: this.anchor = this.cursor
  else:
    this.anchor = -1
  if this.data.len == 0:
    this.cursor = 0
  else:
    this.cursor = newCursor.clamp(0, this.data.high)
  this.nibble = newNibble
  this.lastEditOffset = -1
  redraw(this)


proc hexDigitVal(r: Rune): int =
  ## the value 0..15 of a hex digit rune, -1 for any other character
  if r.int32 >= 0x80: return -1
  let c = chr(r.int32)
  case c
  of '0'..'9': c.ord - '0'.ord
  of 'a'..'f': c.ord - 'a'.ord + 10
  of 'A'..'F': c.ord - 'A'.ord + 10
  else: -1


proc typeText(this: HexEditorContent, text: string) =
  ## a character typed by the user: a hex digit overwrites a nibble in the
  ## hex column, any character overwrites a byte in the ASCII column
  if text.len == 0: return
  let r = text.runeAt(0)
  if this.area == haHex:
    let digit = r.hexDigitVal
    if digit >= 0:
      this.setNibble(digit.uint8)
  else:
    if r.int32 >= 0x20 and r.int32 <= 0xFF:
      this.setByteChar(r.int32.uint8)


# ----- mouse mapping -----

proc byteAtPos(this: HexEditorContent, pos: Vec2): tuple[offset: int, nibble: int, area: HexEditingArea] =
  ## the byte under the mouse position, from the offset, hex or ASCII column
  let rects = this.cellGrid[].selectionRects
  let rowI = (pos.y / this.rowHeightPx()).floor.int.clamp(0, this.rowCount() - 1)
  let byteBase = rowI * BytesPerRow
  let lastByte = max(this.data.high, 0)

  # the character cell the position falls into
  var ci = rects.high
  for i, r in rects:
    if pos.x < this.cellX(i) + r.w:
      ci = i
      break

  if ci < HexCharI:
    # the offset column: jump to the row start
    result = (min(byteBase, lastByte), 0, haHex)

  elif ci < AsciiCharI:
    # hex column: bytes 0..7 occupy cells 0..23 of the column (a pair and a
    # space each), a group gap follows, then bytes 8..15
    let rel = ci - HexCharI
    var byteInRow: int
    var nibble: int
    if rel < (BytesPerRow div 2) * 3:
      byteInRow = rel div 3
      nibble = min(rel mod 3, 1)  # a space after the pair acts as its low digit
    elif rel == (BytesPerRow div 2) * 3:
      # the group gap: the end of the first group
      byteInRow = BytesPerRow div 2 - 1
      nibble = 1
    else:
      let rel2 = rel - ((BytesPerRow div 2) * 3 + 1)
      byteInRow = BytesPerRow div 2 + rel2 div 3
      nibble = min(rel2 mod 3, 1)
    result = (min(byteBase + byteInRow, lastByte), nibble, haHex)

  else:
    # ASCII column (the two gap cells before it act as its first byte)
    let byteInRow = (ci - AsciiCharI).clamp(0, BytesPerRow - 1)
    result = (min(byteBase + byteInRow, lastByte), 0, haAscii)


# ----- rendering -----

proc drawRowAsciiChar(b: uint8): char =
  (if b >= 0x20'u8 and b < 0x7F'u8: chr(b.int) else: '.')


method drawInner*(this: HexEditorContent, ctx: DrawContext) =
  let winRect = rect(vec2(), this.root.wh)
  let rowH = this.rowHeightPx()
  let hexX = this.cellX(HexCharI)
  let asciiX = this.cellX(AsciiCharI)
  # widths of one hex pair and one ascii cell on the real glyph grid
  let hexCellW = this.cellX(HexCharI + 1) + this.cellW(HexCharI + 1) - hexX
  let asciiCellW = this.cellW(AsciiCharI)

  var scaledFont = copy this.font[]
  scaledFont.size = scaledFont.size * this.root.uiScale[]

  if this.errorMsg.len > 0:
    ctx.drawRasterText_physicalScale(
      this.globalXy + vec2(LeftPadding, 0),
      typeset(scaledFont, this.errorMsg),
      colorTheme[].sError,
      origin = vec2(0, 0),
    )
    return

  let sel = this.selectionRange()
  let cursorRowI = this.cursor div BytesPerRow
  let cursorInRow = this.cursor mod BytesPerRow

  for rowI in 0 ..< this.rowCount():
    let rowY = rowI.float32 * rowH
    if this.globalY[] + rowY + rowH < winRect.y: continue
    if this.globalY[] + rowY > winRect.y + winRect.h: continue

    let firstByte = rowI * BytesPerRow

    # offset column
    ctx.drawRasterText_physicalScale(
      this.globalXy + vec2(this.cellX(OffsetCharI), rowY),
      typeset(scaledFont, toHex(firstByte, OffsetDigits)),
      colorTheme[].sLineNumber,
      origin = vec2(0, 0),
    )

    # highlight of the selected bytes and of the byte under the cursor
    for i in 0 ..< BytesPerRow:
      let ofs = firstByte + i
      if ofs >= this.data.len: break
      if ofs in sel:
        ctx.fillRect(
          rect(this.globalXy + vec2(this.cellX(hexCharI(i)), rowY), vec2(hexCellW, rowH)),
          colorTheme[].sSelection,
        )
        ctx.fillRect(
          rect(this.globalXy + vec2(this.cellX(asciiCharI(i)), rowY), vec2(asciiCellW, rowH)),
          colorTheme[].sSelection,
        )
      elif ofs == this.cursor and this.anchor < 0:
        ctx.fillRect(
          rect(this.globalXy + vec2(this.cellX(hexCharI(i)), rowY), vec2(hexCellW, rowH)),
          colorTheme[].sWordHighlight,
        )
        ctx.fillRect(
          rect(this.globalXy + vec2(this.cellX(asciiCharI(i)), rowY), vec2(asciiCellW, rowH)),
          colorTheme[].sWordHighlight,
        )

    # the hex column
    var hexStr = ""
    var asciiStr = ""
    for i in 0 ..< BytesPerRow:
      if i == 8: hexStr.add ' '  # gap between the two 8-byte groups
      let ofs = firstByte + i
      if ofs < this.data.len:
        hexStr.add toHex(this.data[ofs], 2)
        asciiStr.add drawRowAsciiChar(this.data[ofs])
      else:
        hexStr.add "  "
        asciiStr.add ' '
      if i < BytesPerRow - 1: hexStr.add ' '

    ctx.drawRasterText_physicalScale(
      this.globalXy + vec2(hexX, rowY),
      typeset(scaledFont, hexStr),
      colorTheme[].sText,
      origin = vec2(0, 0),
    )
    ctx.drawRasterText_physicalScale(
      this.globalXy + vec2(asciiX, rowY),
      typeset(scaledFont, asciiStr),
      colorTheme[].sStringLit,
      origin = vec2(0, 0),
    )

    # text cursor: a vertical line in front of the current nibble (hex
    # column) or character (ASCII column)
    if currentFocus[] == this and rowI == cursorRowI and this.data.len > 0:
      let caretX =
        if this.area == haHex: this.cellX(hexCharI(cursorInRow) + this.nibble)
        else: this.cellX(asciiCharI(cursorInRow))
      ctx.fillRect(
        rect(this.globalXy + vec2(caretX, rowY), vec2(CaretWidth, rowH)),
        colorTheme[].sText,
      )


# ----- event handling -----

proc navigationVisible(this: HexEditorContent): bool =
  var n = this.Uiobj
  while n != nil:
    if n.visibility[] == collapsed: return false
    n = n.parent
  true


method recieve*(this: HexEditorContent, signal: Signal) =
  procCall this.super.recieve(signal)

  signal.match StateBoolChangedEvent:
    if e.kind == StateBoolChangedEventKind.focus:
      # Modifier key-up events can be swallowed by Alt+Tab on Windows.
      # Start with a clean state whenever the window focus changes.
      this.modifierKeysDown = {}

  signal.match KeyEvent:
    if e.key in {Key.lshift, Key.rshift, Key.lcontrol, Key.rcontrol, Key.lalt, Key.ralt}:
      if e.pressed:
        this.modifierKeysDown.incl e.key
      else:
        this.modifierKeysDown.excl e.key

  if not this.navigationVisible(): return

  signal.match TextInputEvent:
    # shortcuts consume their keys before this, so a `handled` key must not
    # be processed here
    if currentFocus[] == this and this.errorMsg.len == 0 and not signal.handled and
        (this.modifierKeysDown * {Key.lcontrol, Key.rcontrol, Key.lalt, Key.ralt}).len == 0:
      this.typeText(e.text)
      signal.handled = true

  signal.match KeyEvent:
    if e.pressed and not signal.handled and currentFocus[] == this and this.errorMsg.len == 0:
      let shift = (this.modifierKeysDown * {Key.lshift, Key.rshift}).len > 0

      case e.key
      of Key.left:
        if this.area == haHex and this.nibble == 1:
          this.nibble = 0
          this.lastEditOffset = -1
          redraw(this)
        else:
          this.moveCursor(this.cursor - 1, extend = shift, newNibble = 1)

      of Key.right:
        if this.area == haHex and this.nibble == 0:
          this.nibble = 1
          this.lastEditOffset = -1
          redraw(this)
        else:
          this.moveCursor(this.cursor + 1, extend = shift, newNibble = 0)

      of Key.up:
        this.moveCursor(this.cursor - BytesPerRow, extend = shift)

      of Key.down:
        this.moveCursor(this.cursor + BytesPerRow, extend = shift)

      of Key.home:
        this.moveCursor(this.cursor - this.cursor mod BytesPerRow, extend = shift)

      of Key.End:
        let rowStart = this.cursor - this.cursor mod BytesPerRow
        this.moveCursor(rowStart + BytesPerRow - 1, extend = shift)

      of Key.pageUp:
        this.moveCursor(this.cursor - this.visibleRows() * BytesPerRow, extend = shift)

      of Key.pageDown:
        this.moveCursor(this.cursor + this.visibleRows() * BytesPerRow, extend = shift)

      of Key.backspace:
        let sel = this.selectionRange()
        var deleted = false
        if sel.a <= sel.b:
          deleted = this.deleteRange(sel.a, sel.b)
        elif this.cursor > 0:
          deleted = this.deleteRange(this.cursor - 1, this.cursor - 1)
        if deleted:
          this.anchor = -1
          this.lastEditOffset = -1
          this.redrawNow()
          this.saveFile()

      of Key.del:
        let sel = this.selectionRange()
        var deleted = false
        if sel.a <= sel.b:
          deleted = this.deleteRange(sel.a, sel.b)
        elif this.cursor < this.data.len:
          deleted = this.deleteRange(this.cursor, this.cursor)
        if deleted:
          this.anchor = -1
          this.lastEditOffset = -1
          this.redrawNow()
          this.saveFile()

      of Key.escape:
        if this.anchor >= 0:
          this.anchor = -1
          redraw(this)

      else: discard


# ----- opening files -----

proc open*(this: HexEditor, target: Location) =
  ## loads the bytes of `target.path` into the hex editor
  setFocus this.content

  let path = target.path.absolutePath
  if this.content.errorMsg.len == 0 and this.content.path[].absolutePath == path:
    # already open — the cursor stays where the user left it
    this.openedFile.emit()
    return

  var data: seq[uint8]
  var error = ""
  try:
    let size = getFileSize(path)
    data = newSeq[uint8](size.int)
    if size > 0:
      var file: File
      if not file.open(path, fmRead):
        raise newException(IOError, "cannot open file")
      try:
        let read = file.readBytes(data, 0, size.int)
        if read != size.int:
          raise newException(IOError, "read " & $read & " of " & $size & " bytes")
      finally:
        file.close()
  except CatchableError as exc:
    error = exc.msg

  if error.len > 0:
    this.content.path[] = ""
    this.content.data = @[]
    this.content.errorMsg = tr"Unable to read file:" & " " & path & "\n" & error
  else:
    this.content.path[] = path
    this.content.data = data
    this.content.errorMsg = ""

  this.content.cursor = 0
  this.content.nibble = 0
  this.content.area = haHex
  this.content.anchor = -1
  this.content.undoHistory.setLen(0)
  this.content.lastEditOffset = -1
  this.content.updateHeight()
  # emitted after the file is loaded, so handlers see the final content.path
  this.openedFile.emit()
  redraw(this.content)


method init*(this: HexEditorContent) =
  procCall this.super.init()

  this.font{} = font_monospace.withSize(12)

  # the cell grid is typeset for the current font, rebuild it on a font change
  this.font.changed.connectTo this:
    this.cellGridCache = nil

  this.makeLayout:
    - MouseArea.new:
      # the bytes grid: clicking moves the cursor, dragging selects a range;
      # `allowEventFallthrough` lets the ScrollArea scroll on wheel
      this.fill(parent)
      allowEventFallthrough = true

      on this.pressed[] == true:
        setFocus root
        if root.errorMsg.len == 0:
          let shift = (root.modifierKeysDown * {Key.lshift, Key.rshift}).len > 0
          let target = root.byteAtPos(this.mouseXy[])
          if shift:
            if root.anchor < 0: root.anchor = root.cursor
          else:
            root.anchor = -1
          root.cursor = target.offset
          root.nibble = target.nibble
          root.area = target.area
          root.lastEditOffset = -1
          redraw(root)

      on this.moved:
        if this.pressed[]:
          let target = root.byteAtPos(this.mouseXy[])
          if root.anchor < 0: root.anchor = root.cursor
          root.cursor = target.offset
          root.nibble = target.nibble
          root.area = target.area
          redraw(root)

    # --- editor shortcuts (active only when the hex editor is focused, also
    # listed in the "Key combinations" dialog) ---

    - (shortcut(["Ctrl+C"], "edit.copy", "Copy", context = scWidgetWithChildren)):
      on this.activated: root.copySelection()

    - (shortcut(["Ctrl+Z"], "edit.undo", "Undo", context = scWidgetWithChildren)):
      on this.activated: root.undoLast()


method init*(this: HexEditor) =
  procCall this.super.init()

  this.makeLayout:
    - UiRect.new:
      this.fill(parent)
      color = binding: colorTheme[].bgTextArea

    - ScrollArea.new as root.scrollArea:
      this.fill(parent)

      color = binding: colorTheme[].bgScrollBar

      - HexEditorContent.new as root.content:
        w = binding: parent.w[] - ScrollBarWidth


method canOpen(this: HexEditorFileOpener, target: Location): bool =
  ## accepts binary files up to `HexEditorMaxSize`; bigger files fall back
  ## to the code editor
  if not fileExists(target.path): return false
  if not looksLikeBinaryFile(target.path): return false
  try: result = getFileSize(target.path) <= HexEditorMaxSize
  except CatchableError: discard


method open(this: HexEditorFileOpener, target: Location) =
  this.editor.open(target)
