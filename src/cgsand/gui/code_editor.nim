import std/[sets, os, times]
import pkg/[vmath, chroma]
import pkg/toscel/[focus]
import pkg/sigui/[uibase, scrollArea, mouseArea]
import ../logic/[configuration, code_editor, asyncio, file_openers]
import ./[highlighted_text]


type
  CodeEditorContent* = ref object of Uiobj
    font*: Property[Font]
    breakpointBarWidth*: Property[float32] = 20'f32.property
    lineNumberBarWidth*: Property[float32] = 20'f32.property
    changesBarWidth*: Property[float32] = 5'f32.property
    arrowBarWidth*: Property[float32] = 20'f32.property

    path*: Property[string]   ## path to save on disk (if empty, read-only/no_file)

    nonFoldedArrowsVisible: Property[bool]

    arrangement: CodeArrangement
    dragingCursorI: int
    modifierKeysDown: set[Key]
    mouseDownCount: int
    lastMouseDown: float
    lastMouseDownPos: Vec2
    cursorActivityAt: float
    cursorWordHighlightsVisible: bool
    undoHistory: seq[CodeArrangementSnapshot]

  CodeEditor* = ref object of Uiobj
    content*: CodeEditorContent
    scrollArea: ScrollArea

  CodeEditorFileOpener* = ref object of FileOpener
    editor*: CodeEditor

const MinSelectionWidth = 6'f32
const ScrollBarWidth = 5'f32
const MultiClickTime = 0.4'f32
const MultiClickRadius = 6'f32
const CursorWordHighlightDelay = 0.5'f32
const MaxUndoHistory = 15


registerComponent CodeEditor
registerComponent CodeEditorContent



proc textOffsetX(this: CodeEditorContent): float32 =
  this.breakpointBarWidth[] + this.lineNumberBarWidth[] + this.changesBarWidth[] + this.arrowBarWidth[]

proc lineNumberBarOffsetX(this: CodeEditorContent): float32 =
  this.breakpointBarWidth[]

proc arrowBarOffsetX(this: CodeEditorContent): float32 =
  this.breakpointBarWidth[] + this.lineNumberBarWidth[] + this.changesBarWidth[]




proc updateHeight(this: CodeEditorContent) =
  if this.arrangement == nil:
    this.h[] = 0
    return
  this.h[] = this.arrangement.visibleHeight()


proc markCursorActivity(this: CodeEditorContent) =
  this.cursorActivityAt = epochTime()
  this.cursorWordHighlightsVisible = false


proc pushUndoSnapshot(this: CodeEditorContent) =
  if this.arrangement == nil: return
  if this.undoHistory.len >= MaxUndoHistory:
    this.undoHistory.delete(0)
  this.undoHistory.add this.arrangement.snapshot()


proc discardUnchangedUndoSnapshot(this: CodeEditorContent) =
  if this.undoHistory.len > 0 and this.arrangement != nil and
      this.undoHistory[^1].text == this.arrangement.fileContent():
    this.undoHistory.setLen(this.undoHistory.len - 1)


proc drawSelectionRange(
  this: CodeEditorContent,
  ctx: DrawContext,
  line: CodeArrangementLine,
  selection: Slice[int],
  fill: Color,
) =
  if selection.len <= 0: return
  let textOffsetX = this.textOffsetX
  let lineH = this.font[].lineHeightPixels
  let text = line.arrangement

  if text.runes.len == 0:
    ctx.fillRect(
      rect(this.globalXy + vec2(textOffsetX, line.rect.y), vec2(MinSelectionWidth, lineH)),
      fill,
    )
    return

  for subRowIdx, span in text.lines:
    let rowFirst = span[0]
    let rowLast = span[1]
    if rowFirst > rowLast: continue
    if selection.a > rowLast: continue
    if selection.b <= rowFirst: continue
    let subRowY = line.rect.y + text.selectionRects[rowFirst].y
    let leftRune = max(selection.a, rowFirst)
    let startX = text.selectionRects[leftRune].x
    let rightRune = min(selection.b - 1, rowLast)
    let endX = text.selectionRects[rightRune].x + text.selectionRects[rightRune].w
    let extraW: float32 =
      if selection.b >= text.runes.len and subRowIdx == text.lines.high: MinSelectionWidth
      else: 0.0'f32
    let selectionW = max(endX - startX, 0.0'f32) + extraW
    if selectionW <= 0: continue

    ctx.fillRect(
      rect(
        this.globalXy + vec2(textOffsetX + startX, subRowY),
        vec2(selectionW, lineH),
      ),
      fill,
    )


method drawInner*(this: CodeEditorContent, ctx: DrawContext) =
  let winRect = rect(vec2(), this.root.wh)
  let textOffsetX = this.textOffsetX
  let lineNumberBarOffsetX_r = this.lineNumberBarOffsetX + this.lineNumberBarWidth[]
  let arrowBarCenterX = this.arrowBarOffsetX + this.arrowBarWidth[] / 2

  var matchingSelections: seq[CursorPos]
  if this.arrangement.cursors.len > 0:
    let selected = this.arrangement.selectedText(0)
    if selected.len > 0:
      matchingSelections = this.arrangement.matchingSelections(selected)
    elif this.cursorWordHighlightsVisible and this.arrangement.cursors.len == 1:
      let word = this.arrangement.wordAtCursor(0)
      if word.len > 0:
        matchingSelections = this.arrangement.matchingSelections(word, wholeWord = true)

  let spaceW = typeset(this.font[], " ").layoutBounds.x
  for i, line in this.arrangement.lines:
    if line.isHidden: continue

    if this.globalY[] + line.rect.y + line.rect.h < winRect.y: continue
    if this.globalY[] + line.rect.y > winRect.y + winRect.h: continue

    # line number
    ctx.drawRasterText(
      this.globalXy + vec2(lineNumberBarOffsetX_r, line.rect.y),
      typeset(this.font[], $(i + 1)),
      colorTheme.sLineNumber,
      origin=vec2(1, 0),
    )

    if line.foldable:
      let arrowChar = if i in this.arrangement.foldedLines: "▶" else: "▼"
      if i in this.arrangement.foldedLines or this.nonFoldedArrowsVisible[]:
        # fold arrow
        ctx.drawRasterText(
          this.globalXy + vec2(arrowBarCenterX, line.rect.y),
          typeset(this.font[], arrowChar),
          colorTheme.sLineNumber,
          origin=vec2(0.5, 0),
        )

    for offset in line.indentOffsets:
      let guideX = textOffsetX + offset.float32 * spaceW
      ctx.fillRect(
        rect(this.globalXy + vec2(guideX, line.rect.y), vec2(1'f32, line.rect.h)),
        color(0.3'f32, 0.3'f32, 0.3'f32),
      )

    for matchSelection in matchingSelections:
      this.drawSelectionRange(
        ctx,
        line,
        this.arrangement.selectionRangeForLine(matchSelection, i),
        color(0.24'f32, 0.30'f32, 0.38'f32),
      )

    for c_idx in 0..<this.arrangement.cursors.len:
      if this.arrangement.cursors[c_idx].isDuplicate: continue
      this.drawSelectionRange(
        ctx,
        line,
        this.arrangement.selectionRangeForLine(c_idx, i),
        color(0.2'f32, 0.4'f32, 0.7'f32),
      )

    # the code
    drawHighlightedText(
      ctx,
      this.globalXy + vec2(textOffsetX, line.rect.y),
      line.arrangement,
      line.kinds,
    )

    if currentFocus[] == this:
      for cursor in this.arrangement.cursors:
        if cursor.line == i:
          const cursorW = 1.5'f32
          let pos = vec2(textOffsetX, line.rect.y) + line.colToPos(cursor.col)
          # text cursor
          ctx.fillRect(
            rect(this.globalXy + pos, vec2(cursorW, this.font[].lineHeightPixels)),
            color(1'f32, 1'f32, 1'f32),
          )

    if line.foldable and i in this.arrangement.foldedLines:
      const lineH = 1'f32
      let rect = line.visibleRect

      # line for folded line
      ctx.fillRect(
        rect(
          this.globalXy + vec2(textOffsetX + rect.x, rect.y + rect.h - lineH),
          vec2(rect.w, lineH),
        ),
        color(0.3'f32, 0.6'f32, 1.0'f32),
      )


proc saveFile(this: CodeEditorContent) =
  if this.path[].len == 0: return
  if this.arrangement == nil: return
  scheduleFileSave(this.path[], this.arrangement.fileContent())


proc undo(this: CodeEditorContent): bool =
  if this.undoHistory.len == 0: return
  let previous = this.undoHistory.pop()
  this.arrangement = previous.toArrangement(this.font[], this.w[] - this.textOffsetX)
  this.markCursorActivity()
  this.updateHeight()
  let lineNumberMaxWidth = typeset(this.font[], $this.arrangement.lines.len).layoutBounds.x
  this.lineNumberBarWidth[] = lineNumberMaxWidth
  redraw(this)
  this.saveFile()
  result = true

proc scrollToLine(this: CodeEditor, line: int) =
  if this.content.arrangement.lines.len == 0:
    this.scrollArea.targetY[] = 0
  else:
    let line = line.clamp(0, this.content.arrangement.lines.high)
    let y = this.content.arrangement.lines[line].rect.y
    if this.scrollArea != nil:
      this.scrollArea.targetY[] = max(0'f32, y - this.scrollArea.h[] / 3)


method recieve*(this: CodeEditorContent, signal: Signal) =
  procCall this.super.recieve(signal)

  signal.match StateBoolChangedEvent:
    if e.kind == StateBoolChangedEventKind.focus:
      # Modifier key-up events can be swallowed by Alt+Tab on Windows.
      # Start with a clean state whenever the window focus changes.
      this.modifierKeysDown = {}
      this.markCursorActivity()

  signal.match KeyEvent:
    if e.key in {Key.lshift, Key.rshift, Key.lcontrol, Key.rcontrol, Key.lalt, Key.ralt}:
      if e.pressed:
        this.modifierKeysDown.incl e.key
      else:
        this.modifierKeysDown.excl e.key
  
  block:
    var n = this.Uiobj
    while n != nil:
      if n.visibility[] == collapsed: return
      n = n.parent

  signal.match TextInputEvent:
    if currentFocus[] == this and this.arrangement != nil and not e.repeated:
      this.markCursorActivity()
      this.pushUndoSnapshot()
      this.arrangement.insert(e.text)
      this.discardUnchangedUndoSnapshot()
      this.updateHeight()
      redraw(this)
      this.saveFile()
      signal.handled = true

  signal.match KeyEvent:
    if e.pressed and currentFocus[] == this and this.arrangement != nil:
      this.markCursorActivity()
      let shift = (this.modifierKeysDown * {Key.lshift, Key.rshift}).len > 0
      let ctrl = (this.modifierKeysDown * {Key.lcontrol, Key.rcontrol}).len > 0
      let alt = (this.modifierKeysDown * {Key.lalt, Key.ralt}).len > 0
      
      case e.key
      of Key.left:
        this.arrangement.moveCursorLeft(extend = shift, prevWord = ctrl)
        redraw(this)

      of Key.right:
        this.arrangement.moveCursorRight(extend = shift, nextWord = ctrl)
        redraw(this)

      of Key.up:
        this.arrangement.moveCursorUp(extend = shift)
        redraw(this)

      of Key.down:
        this.arrangement.moveCursorDown(extend = shift)
        redraw(this)

      of Key.backspace:
        this.pushUndoSnapshot()
        deleteBack(this.arrangement)
        this.discardUnchangedUndoSnapshot()
        this.updateHeight()
        redraw(this)
        this.saveFile()

      of Key.del:
        this.pushUndoSnapshot()
        deleteForward(this.arrangement)
        this.discardUnchangedUndoSnapshot()
        this.updateHeight()
        redraw(this)
        this.saveFile()

      of Key.enter:
        this.pushUndoSnapshot()
        insertNewline(this.arrangement)
        this.discardUnchangedUndoSnapshot()
        this.updateHeight()
        redraw(this)
        this.saveFile()

      of Key.escape:
        if this.arrangement.cursors.len > 1:
          this.arrangement.cursors = @[this.arrangement.cursors[0]]
          redraw(this)

      of Key.b:
        if ctrl:
          this.arrangement.selectionMode = case this.arrangement.selectionMode
            of LineSelection: BlockSelection
            of BlockSelection: LineSelection
          redraw(this)

      of Key.c:
        if ctrl:
          let text = this.arrangement.selectedText()
          if text.len > 0:
            this.root.clipboardText = text
          signal.handled = true

      of Key.v:
        if ctrl:
          let text = this.root.clipboardText
          if text.len > 0:
            this.pushUndoSnapshot()
            this.arrangement.insert(text)
            this.discardUnchangedUndoSnapshot()
            this.updateHeight()
            redraw(this)
            this.saveFile()
          signal.handled = true

      of Key.d:
        if ctrl and alt:
          if this.arrangement.addSelectionToNextMatch():
            redraw(this)
          signal.handled = true
        elif ctrl:
          this.pushUndoSnapshot()
          this.arrangement.duplicateSelectionsOrLines()
          this.discardUnchangedUndoSnapshot()
          this.updateHeight()
          redraw(this)
          this.saveFile()
          signal.handled = true

      of Key.z:
        if ctrl:
          discard this.undo()
          signal.handled = true

      else: discard


proc setArrangement(this: CodeEditorContent, text: string) =
  # todo: if only the width changed, update arrangement instead of regenerating it
  this.arrangement = text.toArrangement(this.font[], this.w[] - this.textOffsetX)
  this.markCursorActivity()
  this.updateHeight()

  let lineNumberMaxWidth = typeset(this.font[], $this.arrangement.lines.len).layoutBounds.x
  this.lineNumberBarWidth[] = lineNumberMaxWidth
  redraw(this)


proc rearrange(this: CodeEditorContent) =
  ## todo
  this.setArrangement(this.arrangement.fileContent())


method init*(this: CodeEditorContent) =
  procCall this.super.init()

  this.font{} = font_monospace.withSize(12)
  this.markCursorActivity()

  this.root.onTick.connectTo this:
    if currentFocus[] == this and this.arrangement != nil and
        this.arrangement.cursors.len == 1 and
        not this.arrangement.cursors[0].hasSelection and
        not this.cursorWordHighlightsVisible and
        epochTime() - this.cursorActivityAt >= CursorWordHighlightDelay:
      this.cursorWordHighlightsVisible = true
      redraw(this)

  this.makeLayout:
    - MouseArea.new:
      this.fillVertical(parent)
      x = binding: parent.breakpointBarWidth[] + parent.lineNumberBarWidth[] + parent.changesBarWidth[]
      w = binding: parent.arrowBarWidth[]

      root.nonFoldedArrowsVisible[] = binding: this.hovered[]

      on this.pressed[] == true:
        setFocus root
        root.markCursorActivity()

      on this.clicked:
        let clickY = this.mouseY[]
        for i, line in root.arrangement.lines:
          if line.isHidden: continue
          if clickY >= line.rect.y and clickY < line.rect.y + line.rect.h:
            if line.foldable:
              root.arrangement.toggleFold(i)
              root.updateHeight()
              redraw(root)
            break

    - MouseArea.new:
      this.fillVertical(parent)
      x = binding: parent.textOffsetX
      w = binding: parent.w[] - parent.textOffsetX

      allowEventFallthrough = true

      on this.pressed[] == true:
        setFocus root
        root.markCursorActivity()
        for i, line in root.arrangement.lines:
          if line.isHidden: continue
          if this.mouseY[] >= line.rect.y and this.mouseY[] < line.rect.y + line.rect.h:
            let col = line.posToCol(vec2(this.mouseX[], this.mouseY[] - line.rect.y))
            let append = (root.modifierKeysDown * {Key.lalt, Key.ralt}).len > 0
            let extend = (root.modifierKeysDown * {Key.lshift, Key.rshift}).len > 0

            let clickPos = this.mouseXy[]
            let now = epochTime()
            if not append and not extend and
                now - root.lastMouseDown < MultiClickTime and
                (clickPos - root.lastMouseDownPos).length < MultiClickRadius:
              root.mouseDownCount = root.mouseDownCount mod 3 + 1
            else:
              root.mouseDownCount = 1
            root.lastMouseDown = now
            root.lastMouseDownPos = clickPos

            if extend and not append and root.arrangement.cursors.len > 0:
              # Shift+click extends the primary selection from its original
              # anchor. A regular click still replaces all extra cursors.
              let cursor = root.arrangement.cursors[0]
              let anchorLine = if cursor.hasSelection: cursor.anchorLine else: cursor.line
              let anchorCol = if cursor.hasSelection: cursor.anchorCol else: cursor.col
              root.arrangement.cursors.setLen(1)
              root.arrangement.setSelection(0, anchorLine, anchorCol, i, col)
              root.dragingCursorI = 0
            elif not append and root.mouseDownCount == 2:
              root.arrangement.cursors.setLen(1)
              root.arrangement.selectWordAt(0, i, col)
              root.dragingCursorI = -1
            elif not append and root.mouseDownCount == 3:
              root.arrangement.cursors.setLen(1)
              root.arrangement.selectLineAt(0, i)
              root.dragingCursorI = -1
            else:
              root.arrangement.setCursorPos(i, col, append)
              root.dragingCursorI = root.arrangement.cursors.high
            redraw(root)
            break

      on this.moved:
        if this.pressed[] and root.dragingCursorI >= 0:
          root.markCursorActivity()
          root.arrangement.selectToPos(root.dragingCursorI, this.mouseXy[])
          redraw(root)

proc open*(this: CodeEditor, target: Location) =
  setFocus this.content
  this.content.undoHistory.setLen(0)
  try:
    this.content.path[] = target.path
    this.content.setArrangement(readFile(target.path))
    this.content.arrangement.setCursorPos(target.line, target.col)
    this.scrollToLine(target.line)
  except CatchableError as exc:
    this.content.path[] = ""
    this.content.setArrangement("Unable to read file: " & target.path & "\n" & exc.msg)


method canOpen(this: CodeEditorFileOpener, target: Location): bool =
  fileExists(target.path)


method open(this: CodeEditorFileOpener, target: Location) =
  this.editor.open(target)


method init*(this: CodeEditor) =
  procCall this.super.init()

  this.makeLayout:
    - UiRect.new:
      this.fill(parent)
      color = colorTheme.bgTextArea

    - ScrollArea.new as root.scrollArea:
      this.fill(parent)

      color = colorTheme.bgScrollBar

      - CodeEditorContent.new as root.content:
        w = binding: parent.w[] - ScrollBarWidth

      verticalScrollOverFit = binding: this.h[] - root.content.font[].size * 2

    root.open(Location(path: config.scriptFile[]))
    on this.w.changed: root.content.rearrange()
