import std/[unicode, terminal, times, strutils]
import pkg/[vmath, chroma]
import pkg/pixie/[fonts]
import pkg/rice/[rasterTexts, contexts, gl, primitives]
import pkg/toscel/[focus]
import pkg/sigui/[uibase, mouseArea]
import pkg/sigui/window
import ../logic/[config, terminal, file_openers]


const
  CursorBlinkPeriod = 1.2'f32
  CursorSolidAfterActivity = 0.8'f32  # the cursor does not blink right after output/input

  WheelScrollLines = 3  # history lines / arrow keys per wheel notch

  DoubleClickTime = 0.4'f32  # max seconds between clicks counted as one multi-click
  DoubleClickRadius = 6'f32
  SelectionAutoscrollPeriod = 0.05'f32  # min seconds between autoscroll steps


type
  SelectionMode = enum
    smNone
    smChar  # a character range dragged with the mouse
    smWord  # double click: whole words
    smLine  # triple click: whole lines

  TerminalContent* = ref object of Uiobj
    ## the terminal "screen": renders a TerminalArrangement and forwards
    ## keyboard input to the attached terminal backend
    font*: Property[Font]

    terminal: Terminal

    arrangement: TerminalArrangement
    pendingOutput: string  ## unparsed tail of output (an incomplete escape sequence)
    lastActivity: float    ## epochTime of the last output/input, for cursor blinking

    # mouse text selection, in absolute cell coordinates (see logic/terminal/emulator)
    selectionMode: SelectionMode
    selectionAnchor: IVec2  ## the cell where the selection started
    selectionHead: IVec2    ## the cell under the mouse
    selectDragging: bool
    mouseDownCount: int   ## rapid clicks in place: 2 = word select, 3 = line select
    lastMouseDown: float
    lastMouseDownPos: Vec2
    lastMousePos: Vec2    ## for autoscrolling a drag past the top/bottom edge
    lastAutoScroll: float

    # clickable file paths: hovered ones are underlined, ctrl+click opens them
    mouseArea: MouseArea
    hoveredLink: TerminalLink
    hoveredLinkValid: bool
    linkCursorShown: bool  ## whether the mouse cursor is currently a hand

  Terminal* = ref object of Uiobj
    content*: TerminalContent

    fileOpener*: seq[FileOpener]

    backend: TerminalBackend
    m_outputChannel: Channel[string]
    m_exitReported: bool


registerComponent Terminal
registerComponent TerminalContent



proc outputChannel*(this: Terminal): ptr Channel[string] =
  ## print into this terminal from any thread
  ## (compilation logs, backend output, ...)
  this.m_outputChannel.addr


proc sendInput*(this: Terminal, s: string) =
  ## send user input to the terminal backend
  if this.backend != nil:
    this.backend.sendInput(s)


# --- mouse text selection --------------------------------------------------


proc clearSelection*(this: TerminalContent) =
  if this.selectionMode != smNone:
    this.selectionMode = smNone
    redraw this


proc clear*(this: Terminal) =
  this.content.arrangement.clear()
  this.content.arrangement.clearScrollback()
  this.content.clearSelection()
  redraw this.content



proc cellSize*(this: TerminalContent): Vec2 =
  ## assumes this.font is monospace
  this.font.typeset("T").selectionRects[0].wh


proc feed*(this: TerminalContent, text: string) =
  ## print `text` to the terminal screen, interpreting escape sequences
  if this.arrangement == nil: return
  let wasAltScreen = this.arrangement.usingAltScreen
  let scrollbackBase = this.arrangement.scrollbackBase()
  this.pendingOutput.add text

  var i = 0
  this.arrangement.handleInput(this.pendingOutput, i)
  if i > 0:
    this.pendingOutput = this.pendingOutput[i .. ^1]

  # forward replies to terminal queries (DA1, cursor position, ...) back to the backend
  if this.arrangement.pendingResponses.len > 0:
    if this.terminal != nil:
      this.terminal.sendInput(this.arrangement.pendingResponses)
    this.arrangement.pendingResponses = ""

  if this.arrangement.usingAltScreen != wasAltScreen:
    this.clearSelection()  # the other screen buffer is different content
  else:
    # every line evicted from the scrollback shifts absolute rows down by one
    let evicted = this.arrangement.scrollbackBase() - scrollbackBase
    if evicted > 0:
      this.selectionAnchor.y = max(0, this.selectionAnchor.y - evicted.int32)
      this.selectionHead.y = max(0, this.selectionHead.y - evicted.int32)

  this.lastActivity = epochTime()
  redraw this


proc updateGridSize(this: TerminalContent) =
  if this.arrangement == nil: return
  let cell = this.cellSize
  if cell.x <= 0 or cell.y <= 0: return
  # skip intermediate layouts where the widget has no sensible size yet
  if this.w[] < cell.x * 2 or this.h[] < cell.y * 2: return

  let cols = max(1, (this.w[] / cell.x).int)
  let rows = max(1, (this.h[] / cell.y).int)
  if cols != this.arrangement.size.x or rows != this.arrangement.size.y:
    this.arrangement.resize ivec2(cols.int32, rows.int32)
    this.clearSelection()  # the resize re-flow invalidates cell coordinates
    if this.terminal != nil and this.terminal.backend != nil:
      this.terminal.backend.resize(cols, rows)
    redraw this


proc posToCell(this: TerminalContent, pos: Vec2): IVec2 =
  ## the cell at widget-local position `pos`, clamped into the grid
  ## (x = column, y = absolute row)
  let arr = this.arrangement
  let cell = this.cellSize
  if arr == nil or cell.x <= 0 or cell.y <= 0: return
  let col = (pos.x / cell.x).int.clamp(0, arr.size.x - 1)
  let viewRow = (pos.y / cell.y).int.clamp(0, arr.size.y - 1)
  ivec2(col.int32, arr.absViewRow(viewRow).int32)


proc selectionRange(this: TerminalContent): tuple[a, b: IVec2] =
  ## the selection as an ordered cell range, expanded to whole words/lines
  let arr = this.arrangement
  if arr == nil or this.selectionMode == smNone: return
  let anchor = this.selectionAnchor
  let head = this.selectionHead
  case this.selectionMode
  of smChar:
    if anchor <= head: (anchor, head) else: (head, anchor)
  of smWord:
    let aw = arr.wordRangeAt(anchor)
    let hw = arr.wordRangeAt(head)
    if anchor <= head:
      (ivec2(aw.colStart.int32, anchor.y), ivec2(hw.colEnd.int32, head.y))
    else:
      (ivec2(hw.colStart.int32, head.y), ivec2(aw.colEnd.int32, anchor.y))
  else:  # smLine
    (ivec2(0, min(anchor.y, head.y)), ivec2(arr.size.x - 1, max(anchor.y, head.y)))


proc selectionPressed(this: TerminalContent, pos: Vec2) =
  this.selectDragging = true
  this.lastMousePos = pos

  # rapid presses in place count as multi-clicks and cycle 1 -> 2 -> 3 -> 1
  let now = epochTime()
  if now - this.lastMouseDown < DoubleClickTime and (pos - this.lastMouseDownPos).length < DoubleClickRadius:
    this.mouseDownCount = this.mouseDownCount mod 3 + 1
  else:
    this.mouseDownCount = 1
  this.lastMouseDown = now
  this.lastMouseDownPos = pos

  this.selectionAnchor = this.posToCell(pos)
  this.selectionHead = this.selectionAnchor
  this.selectionMode = case this.mouseDownCount
    of 2: smWord
    of 3: smLine
    else: smNone  # a character selection appears once the mouse is dragged
  redraw this


proc selectionMoved(this: TerminalContent, pos: Vec2) =
  this.lastMousePos = pos
  if not this.selectDragging: return
  let cell = this.posToCell(pos)
  if this.selectionMode == smNone and cell != this.selectionAnchor:
    this.selectionMode = smChar
  this.selectionHead = cell
  redraw this


proc selectionAutoScroll(this: TerminalContent) =
  ## while a drag is held past the top/bottom edge, scroll the view with it
  if not this.selectDragging or this.selectionMode == smNone: return
  let arr = this.arrangement
  if arr == nil or arr.usingAltScreen: return
  let cell = this.cellSize
  if cell.y <= 0: return

  let overTop = (-this.lastMousePos.y / cell.y).int
  let overBottom = ((this.lastMousePos.y - this.h[]) / cell.y).int
  if overTop <= 0 and overBottom <= 0: return
  if epochTime() - this.lastAutoScroll < SelectionAutoscrollPeriod: return
  this.lastAutoScroll = epochTime()

  if overTop > 0:
    arr.scrollView(1 + overTop div 3)  # back in history, the view follows the mouse up
    this.selectionHead = this.posToCell(vec2(this.lastMousePos.x, 0))
  else:
    arr.scrollView(-(1 + overBottom div 3))
    this.selectionHead = this.posToCell(vec2(this.lastMousePos.x, this.h[]))
  redraw this


proc selectedText*(this: TerminalContent): string =
  if this.arrangement == nil or this.selectionMode == smNone: return
  let (a, b) = this.selectionRange()
  this.arrangement.textBetween(a, b)


proc copySelection*(this: TerminalContent) =
  let text = this.selectedText()
  if text.len > 0:
    this.parentWindow.clipboard.text = text


proc pasteClipboard*(this: TerminalContent) =
  if this.terminal == nil: return
  var src = this.parentWindow.clipboard.text
  if src.len == 0: return
  # a paste goes to the shell as if typed: \r acts as Enter, and control
  # characters other than \t would trigger shell shortcuts
  src = src.replace("\r\n", "\n").replace("\r", "\n")
  var text = ""
  for r in src.runes:
    if r.uint32 == 10: text.add "\r"
    elif r == "\t".runeAt(0): text.add "\t"
    elif r.uint32 >= 32 and r.uint32 != 127: text.add r
  if text.len > 0:
    this.terminal.sendInput(text)
    this.arrangement.scrollToBottom()
    this.lastActivity = epochTime()


# --- clickable file paths ---------------------------------------------------


proc updateHoveredLink(this: TerminalContent, pos: Vec2) =
  ## underline the file path under the mouse, if any
  var link = TerminalLink()
  var found = false
  if this.arrangement != nil:
    let l = this.arrangement.fileLinkAt(this.posToCell(pos))
    link = l.link
    found = l.found

  if found != this.hoveredLinkValid or (found and link != this.hoveredLink):
    this.hoveredLink = link
    this.hoveredLinkValid = found
    redraw this

  # the hand cursor marks the path as clickable
  if this.mouseArea != nil and this.linkCursorShown != found:
    this.linkCursorShown = found
    this.mouseArea.cursor[] = if found: BuiltinCursor.pointingHand else: BuiltinCursor.text


proc clearHoveredLink(this: TerminalContent) =
  if this.hoveredLinkValid:
    this.hoveredLinkValid = false
    redraw this
  if this.linkCursorShown:
    this.linkCursorShown = false
    if this.mouseArea != nil:
      this.mouseArea.cursor[] = BuiltinCursor.text


proc openHoveredLink(this: TerminalContent) =
  if not this.hoveredLinkValid or this.terminal == nil: return
  this.terminal.fileOpener.open(this.hoveredLink.target)


proc effectiveColors(cell: TerminalCell): tuple[fg, bg: Color] =
  result = (cell.flags.fg, cell.flags.bg)
  if styleReverse in cell.flags.style:
    swap result.fg, result.bg
  if styleBright in cell.flags.style:
    let c = result.fg
    result.fg = color(c.r + (1 - c.r) * 0.35, c.g + (1 - c.g) * 0.35, c.b + (1 - c.b) * 0.35)
  if styleDim in cell.flags.style:
    let c = result.fg
    result.fg = color(c.r * 0.55, c.g * 0.55, c.b * 0.55)


method drawInner*(this: TerminalContent, ctx: DrawContext) =
  let arr = this.arrangement
  if arr == nil or arr.size.x <= 0 or arr.size.y <= 0: return

  let cell = this.cellSize
  let origin = this.globalXy + ctx.offset
  let spaceRune = " ".runeAt(0)

  # backgrounds and decorations
  for y in 0 ..< arr.size.y:
    let rowY = y.float32 * cell.y
    for x in 0 ..< arr.size.x:
      let c = arr.viewCell(x, y)
      let (fg, bg) = c.effectiveColors

      if bg != ColorDimBlack:
        ctx.fillRect(rect(origin + vec2(x.float32 * cell.x, rowY), cell), bg)

      if styleUnderscore in c.flags.style:
        ctx.fillRect(
          rect(origin + vec2(x.float32 * cell.x, rowY + cell.y - 1.5'f32), vec2(cell.x, 1.5'f32)),
          fg,
        )

      if styleStrikethrough in c.flags.style:
        ctx.fillRect(
          rect(origin + vec2(x.float32 * cell.x, rowY + cell.y / 2), vec2(cell.x, 1'f32)),
          fg,
        )

  # mouse selection (over the cell backgrounds, under the text)
  if this.selectionMode != smNone:
    let (sa, sb) = this.selectionRange()
    let topRow = sa.y.int
    let botRow = sb.y.int
    for y in 0 ..< arr.size.y:
      let r = arr.absViewRow(y)
      if r < topRow or r > botRow: continue
      let x0 = (if r == topRow: sa.x.int else: 0).max(0)
      let x1 = (if r == botRow: sb.x.int else: arr.size.x.int - 1).min(arr.size.x.int - 1)
      if x1 < x0: continue
      ctx.fillRect(
        rect(
          origin + vec2(x0.float32 * cell.x, y.float32 * cell.y),
          vec2((x1 - x0 + 1).float32 * cell.x, cell.y),
        ),
        colorTheme.bgSelection,
      )

  # hovered file path: underlined like a link (ctrl+click opens it)
  if this.hoveredLinkValid:
    let link = this.hoveredLink
    let viewTop = arr.absViewRow(0)
    for r in link.a.y .. link.b.y:
      let y = r.int - viewTop
      if y notin 0 ..< arr.size.y.int: continue
      let x0 = (if r == link.a.y: link.a.x.int else: 0).max(0)
      let x1 = (if r == link.b.y: link.b.x.int else: arr.size.x.int - 1).min(arr.size.x.int - 1)
      for x in x0 .. x1:
        let c = arr.viewCell(x, y)
        ctx.fillRect(
          rect(origin + vec2(x.float32 * cell.x, y.float32 * cell.y + cell.y - 1.5'f32), vec2(cell.x, 1.5'f32)),
          c.effectiveColors.fg,
        )

  # terminal cursor (it lives on the live screen, not in the scrolled-back view)
  if arr.cursorVisible and not arr.scrolledBack and currentFocus[] == this:
    let idle = epochTime() - this.lastActivity
    let blinkOn = idle < CursorSolidAfterActivity or
      (idle - CursorSolidAfterActivity) mod CursorBlinkPeriod < CursorBlinkPeriod / 2
    if blinkOn:
      ctx.fillRect(
        rect(origin + vec2(arr.cursor.x.float32 * cell.x, arr.cursor.y.float32 * cell.y), cell),
        color(1'f32, 1'f32, 1'f32, 0.3'f32),
      )

  # text
  # note: rune quads take a position in gl coordinates, unlike fillRect
  var textCtx = ctx.startRasterTextDrawing(this.font[])
  for y in 0 ..< arr.size.y:
    let rowY = y.float32 * cell.y
    for x in 0 ..< arr.size.x:
      let c = arr.viewCell(x, y)
      if c.rune == spaceRune: continue

      let (fg, _) = c.effectiveColors
      textCtx.color.uniform = fg.vec4
      let glPos = ctx.viewportToGlMatrix * (origin + vec2(x.float32 * cell.x, rowY)).vec3(0)
      ctx.fastRasterDrawRune(c.rune, rect(glPos.xy, cell), textCtx)

  ctx.endRasterTextDrawing()


proc keyToSequence(e: KeyEvent): string =
  ## what to send to the shell when a key is pressed
  let kb = e.window.keyboard
  let ctrl = kb.modifiers.contains(control)
  let alt = kb.modifiers.contains(alt)
  let shift = kb.modifiers.contains(shift)

  case e.key
  of Key.enter: "\r"
  of Key.backspace: "\x7f"
  of Key.tab:
    if shift: "\x1b[Z"
    else: "\t"
  of Key.escape: "\x1b"
  of Key.up: "\x1b[A"
  of Key.down: "\x1b[B"
  of Key.right: "\x1b[C"
  of Key.left: "\x1b[D"
  of Key.home: "\x1b[H"
  of Key.End: "\x1b[F"
  of Key.del: "\x1b[3~"
  of Key.pageUp: "\x1b[5~"
  of Key.pageDown: "\x1b[6~"
  of Key.insert: "\x1b[2~"
  of Key.a .. Key.z:
    if ctrl: $chr(ord(e.key))  # ^A .. ^Z
    elif alt: "\x1b" & $e.key   # meta prefix
    else: ""  # printable input arrives as TextInputEvent
  else: ""


method recieve*(this: TerminalContent, signal: Signal) =
  procCall this.super.recieve(signal)

  block:
    var n = this.Uiobj
    while n != nil:
      if n.visibility[] == collapsed: return
      n = n.parent

  signal.match TextInputEvent:
    if currentFocus[] == this and this.terminal != nil:
      # control characters (enter, tab, ...) arrive as KeyEvent instead
      var text = ""
      for r in e.text.runes:
        if r.uint32 >= 32 and r.uint32 != 127:
          text.add r

      if text.len > 0:
        this.terminal.sendInput(text)
        this.arrangement.scrollToBottom()
        this.lastActivity = epochTime()
        signal.handled = true

  signal.match KeyEvent:
    if e.pressed and currentFocus[] == this and this.terminal != nil:
      # terminal-local clipboard shortcuts; they must not reach the shell
      let kb = e.window.keyboard
      let ctrl = kb.modifiers.contains(control)
      let shift = kb.modifiers.contains(shift)

      if ctrl and shift and e.key == Key.c:
        this.copySelection()
        signal.handled = true
      elif ctrl and shift and e.key == Key.v:
        this.pasteClipboard()
        signal.handled = true
      elif e.key == Key.insert and (ctrl xor shift):
        if ctrl: this.copySelection() else: this.pasteClipboard()
        signal.handled = true
      else:
        let seq = keyToSequence(e[])
        if seq.len > 0:
          this.terminal.sendInput(seq)
          this.arrangement.scrollToBottom()
          this.lastActivity = epochTime()
          signal.handled = true


method init*(this: TerminalContent) =
  procCall this.super.init()

  this.font{} = font_monospace.withSize(11)
  this.arrangement = newTerminalArrangement(scrollbackLines = currentConfig.terminalScrollbackLines)

  this.makeLayout:
    this.parentUiRoot.onTick.connectTo this:
      this.selectionAutoScroll()

    - MouseArea.new as root.mouseArea:
      this.fill(parent)
      cursor = BuiltinCursor.text

      # re-evaluate the link under the mouse every frame: the content under a
      # still mouse can change (new output, scrolling)
      this.parentUiRoot.onTick.connectTo this:
        if this.hovered[]:
          root.updateHoveredLink(this.mouseXy[])
        else:
          root.clearHoveredLink()

      on this.pressed[] == true:
        setFocus root
        if root.hoveredLinkValid and this.parentWindow.keyboard.modifiers.contains(control):
          root.openHoveredLink()
        else:
          root.selectionPressed(this.mouseXy[])

      on this.pressed[] == false:
        root.selectDragging = false

      this.moved.connectTo root:
        root.selectionMoved(this.mouseXy[])
        root.updateHoveredLink(this.mouseXy[])

      this.scrolled.connectTo root, delta:
        let arr = root.arrangement
        if arr == nil: return
        
        let delta = if this.parentWindow.keyboard.modifiers.contains(shift): vec2(delta.y, delta.x) else: delta

        if delta.x != 0 and root.terminal != nil:
          # send left/right arrow keys
          let cols = max(1, (WheelScrollLines.float32 * abs(delta.x)).round.int)
          for i in 0 ..< cols:
            root.terminal.sendInput(if delta.x < 0: "\x1b[D" else: "\x1b[C")

        if delta.y != 0:
          let lines = max(1, (WheelScrollLines.float32 * abs(delta.y)).round.int)

          if arr.usingAltScreen:
            # send up/down arrow keys
            if root.terminal != nil:
              for i in 0 ..< lines:
                root.terminal.sendInput(if delta.y < 0: "\x1b[A" else: "\x1b[B")
          else:
            # scroll through the history
            arr.scrollView(if delta.y < 0: lines else: -lines)
            redraw root


proc drainOutput(this: Terminal) =
  var chunk = ""
  while true:
    let (ok, text) = this.m_outputChannel.tryRecv()
    if not ok: break
    chunk.add text
  if chunk.len > 0:
    this.content.feed(chunk)

  if this.backend != nil and not this.m_exitReported and this.backend.status == backendFinished:
    this.m_exitReported = true
    this.content.feed("\r\n\x1b[90m" & tr"[process exited]" & "\x1b[0m\r\n")


method init*(this: Terminal) =
  procCall this.super.init()

  this.m_outputChannel.open()

  try:
    this.backend = newExternalShellBackend(this.m_outputChannel.addr, getShellCommand())
  except CatchableError:
    this.backend = nil  # the terminal is still usable for compilation logs

  this.parentUiRoot.onTick.connectTo this:
    this.drainOutput()

  this.makeLayout:
    - UiRect.new:
      this.fill(parent)
      color = colorTheme.bgTextArea

    - TerminalContent.new as root.content:
      this.fill(parent, 4)

    root.content.terminal = root

    # colors reported to the shell in OSC 10/11 queries (e.g. for fish light/dark syntax themes)
    root.content.arrangement.queryForegroundColor = colorTheme.sText
    root.content.arrangement.queryBackgroundColor = colorTheme.bgTextArea

    root.content.updateGridSize()
    on this.w.changed: root.content.updateGridSize()
    on this.h.changed: root.content.updateGridSize()
