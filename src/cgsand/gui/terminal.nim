import std/[unicode, terminal, times]
import pkg/[vmath, chroma]
import pkg/pixie/[fonts]
import pkg/rice/[rasterTexts, contexts, gl, primitives]
import pkg/toscel/[focus]
import pkg/sigui/[uibase, mouseArea]
import pkg/sigui/window
import ../logic/[config, terminal, terminal_external_shells]


const
  CursorBlinkPeriod = 1.2'f32
  CursorSolidAfterActivity = 0.8'f32  # the cursor does not blink right after output/input

type
  TerminalContent* = ref object of Uiobj
    ## the terminal "screen": renders a TerminalArrangement and forwards
    ## keyboard input to the attached terminal backend
    font*: Property[Font]

    terminal: Terminal

    arrangement: TerminalArrangement
    pendingOutput: string  ## unparsed tail of output (an incomplete escape sequence)
    lastActivity: float    ## epochTime of the last output/input, for cursor blinking

  Terminal* = ref object of Uiobj
    content*: TerminalContent

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


proc clear*(this: Terminal) =
  this.content.arrangement.clear()
  redraw this.content



proc cellSize*(this: TerminalContent): Vec2 =
  ## assumes this.font is monospace
  this.font.typeset("T").selectionRects[0].wh


proc feed*(this: TerminalContent, text: string) =
  ## print `text` to the terminal screen, interpreting escape sequences
  if this.arrangement == nil: return
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
    if this.terminal != nil and this.terminal.backend != nil:
      this.terminal.backend.resize(cols, rows)
    redraw this


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
      let c = arr[x, y]
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

  # terminal cursor
  if arr.cursorVisible and currentFocus[] == this:
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
      let c = arr[x, y]
      if c.rune == spaceRune: continue

      let (fg, _) = c.effectiveColors
      textCtx.color.uniform = fg.vec4
      let glPos = ctx.viewportToGlMatrix * (origin + vec2(x.float32 * cell.x, rowY)).vec3(0)
      ctx.fastRasterDrawRune(c.rune, rect(glPos.xy, cell), textCtx)

  ctx.endRasterTextDrawing()


proc keyToSequence(e: KeyEvent): string =
  ## what to send to the shell when a key is pressed
  let kb = e.window.keyboard
  let ctrl = Key.lcontrol in kb.pressed or Key.rcontrol in kb.pressed
  let alt = Key.lalt in kb.pressed or Key.ralt in kb.pressed
  let shift = containsShift kb.pressed

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

  if signal of WindowEvent and signal.WindowEvent.handled == false:
    let we = signal.WindowEvent

    if we.event of TextInputEvent:
      let e = (ref TextInputEvent)we.event
      if currentFocus[] == this and this.terminal != nil:
        # control characters (enter, tab, ...) arrive as KeyEvent instead
        var text = ""
        for r in e.text.runes:
          if r.uint32 >= 32 and r.uint32 != 127:
            text.add r

        if text.len > 0:
          this.terminal.sendInput(text)
          this.lastActivity = epochTime()
          we.handled = true

    elif we.event of KeyEvent:
      let e = (ref KeyEvent)we.event
      if e.pressed and currentFocus[] == this and this.terminal != nil:
        let seq = keyToSequence(e[])
        if seq.len > 0:
          this.terminal.sendInput(seq)
          this.lastActivity = epochTime()
          we.handled = true


method init*(this: TerminalContent) =
  procCall this.super.init()

  this.font{} = font_monospace.withSize(11)
  this.arrangement = newTerminalArrangement()

  this.makeLayout:
    - MouseArea.new:
      this.fill(parent)
      # allowEventFallthrough = true

      on this.pressed[] == true:
        setFocus root


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
