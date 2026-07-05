import std/[sets]
import pkg/[vmath, chroma]
import pkg/rice/[rasterTexts, contexts, gl, primitives]
import pkg/toscel/[focus]
import pkg/sigui/[uibase, scrollArea, mouseArea]
import pkg/sigui/window
import ../logic/[config, code_editor, asyncio]
import ./[highlighted_text]


type
  CodeEditorContent* = ref object of Uiobj
    font*: Property[Font]
    breakpointBarWidth*: Property[float32] = 20'f32.property
    lineNumberBarWidth*: Property[float32] = 20'f32.property
    changesBarWidth*: Property[float32] = 5'f32.property
    arrowBarWidth*: Property[float32] = 20'f32.property

    nonFoldedArrowsVisible: Property[bool]

    arrangement: CodeArrangement
    dragingCursorI: int

    filename: string   ## path to save on disk (empty = read-only)

  CodeEditor* = ref object of Uiobj
    content*: CodeEditorContent

const MinSelectionWidth = 6'f32
const ScrollBarWidth = 5'f32


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


method drawInner*(this: CodeEditorContent, ctx: DrawContext) =
  let winRect = rect(vec2(), this.parentUiRoot.wh)
  let textOffsetX = this.textOffsetX
  let lineNumberBarOffsetX_r = this.lineNumberBarOffsetX + this.lineNumberBarWidth[]
  let arrowBarCenterX = this.arrowBarOffsetX + this.arrowBarWidth[] / 2

  let spaceW = typeset(this.font, " ").layoutBounds.x
  for i, line in this.arrangement.lines:
    if line.isHidden: continue

    if this.globalY + line.rect.y + line.rect.h < winRect.y: continue
    if this.globalY + line.rect.y > winRect.y + winRect.h: continue

    # line number
    ctx.drawRasterText(
      (this.globalXy + ctx.offset + vec2(lineNumberBarOffsetX_r, line.rect.y)).vec3(0),
      typeset(this.font, $(i + 1)),
      colorTheme.sLineNumber.vec4,
      origin=vec2(1, 0),
    )

    if line.foldable:
      let arrowChar = if i in this.arrangement.foldedLines: "▶" else: "▼"
      if i in this.arrangement.foldedLines or this.nonFoldedArrowsVisible[]:
        # fold arrow
        ctx.drawRasterText(
          (this.globalXy + ctx.offset + vec2(arrowBarCenterX, line.rect.y)).vec3(0),
          typeset(this.font, arrowChar),
          colorTheme.sLineNumber.vec4,
          origin=vec2(0.5, 0),
        )

    for offset in line.indentOffsets:
      let guideX = textOffsetX + offset.float32 * spaceW
      ctx.fillRect(
        rect(
          this.globalXy + ctx.offset + vec2(guideX, line.rect.y),
          vec2(1'f32, line.rect.h),
        ),
        color(0.3'f32, 0.3'f32, 0.3'f32),
      )

    let lineH = this.font[].lineHeightPixels
    for c_idx in 0..<this.arrangement.cursors.len:
      if this.arrangement.cursors[c_idx].isDuplicate: continue
      let sel = this.arrangement.selectionRangeForLine(c_idx, i)
      if sel.len <= 0: continue
      let arr = line.arrangement

      if arr.runes.len == 0:
        # selection rect for empty line
        ctx.fillRect(
          rect(this.globalXy + ctx.offset + vec2(textOffsetX, line.rect.y), vec2(MinSelectionWidth, lineH)),
          color(0.2'f32, 0.4'f32, 0.7'f32),
        )

      else:
        for subRowIdx, span in arr.lines:
          let rowFirst = span[0]
          let rowLast = span[1]
          if rowFirst > rowLast: continue
          if sel.a > rowLast: continue
          if sel.b <= rowFirst: continue
          let subRowY = line.rect.y + arr.selectionRects[rowFirst].y
          let leftRune = max(sel.a, rowFirst)
          let startX = arr.selectionRects[leftRune].x
          let rightRune = min(sel.b - 1, rowLast)
          let endX = arr.selectionRects[rightRune].x + arr.selectionRects[rightRune].w
          let extraW: float32 =
            if sel.b >= arr.runes.len and subRowIdx == arr.lines.high: MinSelectionWidth
            else: 0.0'f32
          let selW = max(endX - startX, 0.0'f32) + extraW
          if selW <= 0: continue

          # selection rect
          ctx.fillRect(
            rect(
              this.globalXy + ctx.offset + vec2(textOffsetX + startX, subRowY),
              vec2(selW, lineH),
            ),
            color(0.2'f32, 0.4'f32, 0.7'f32),
          )

    # the code
    drawHighlightedText(
      ctx,
      (this.globalXy + ctx.offset + vec2(textOffsetX, line.rect.y)).vec3(0),
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
            rect(this.globalXy + ctx.offset + pos, vec2(cursorW, this.font[].lineHeightPixels)),
            color(1'f32, 1'f32, 1'f32),
          )

    if line.foldable and i in this.arrangement.foldedLines:
      const lineH = 1'f32
      let rect = line.visibleRect

      # line for folded line
      ctx.fillRect(
        rect(
          this.globalXy + ctx.offset + vec2(textOffsetX + rect.x, rect.y + rect.h - lineH),
          vec2(rect.w, lineH),
        ),
        color(0.3'f32, 0.6'f32, 1.0'f32),
      )


proc saveFile(this: CodeEditorContent) =
  if this.filename.len == 0: return
  if this.arrangement == nil: return
  scheduleFileSave(this.filename, this.arrangement.fileContent())


method recieve*(this: CodeEditorContent, signal: Signal) =
  procCall this.super.recieve(signal)
  
  block:
    var n = this.Uiobj
    while n != nil:
      if n.visibility[] == collapsed: return
      n = n.parent

  if signal of WindowEvent and signal.WindowEvent.handled == false:
    if signal.WindowEvent.event of TextInputEvent:
      let e = (ref TextInputEvent)signal.WindowEvent.event
      if currentFocus[] == this and this.arrangement != nil and not e.repeated:
        this.arrangement.insert(e.text)
        this.updateHeight()
        redraw(this)
        this.saveFile()
        signal.WindowEvent.handled = true

    elif signal.WindowEvent.event of KeyEvent:
      let e = (ref KeyEvent)signal.WindowEvent.event
      if e.pressed and currentFocus[] == this and this.arrangement != nil:
        let shift = Key.lshift in e.window.keyboard.pressed or Key.rshift in e.window.keyboard.pressed
        let ctrl = Key.lcontrol in e.window.keyboard.pressed or Key.rcontrol in e.window.keyboard.pressed
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
          deleteBack(this.arrangement)
          this.updateHeight()
          redraw(this)
          this.saveFile()

        of Key.del:
          deleteForward(this.arrangement)
          this.updateHeight()
          redraw(this)
          this.saveFile()

        of Key.enter:
          insertNewline(this.arrangement)
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

        else: discard


proc setArrangement(this: CodeEditorContent, text: string) =
  # todo: if only the width changed, update arrangement instead of regenerating it
  this.arrangement = text.toArrangement(this.font[], this.w[] - this.textOffsetX)
  this.updateHeight()

  let lineNumberMaxWidth = typeset(this.font, $this.arrangement.lines.len).layoutBounds.x
  this.lineNumberBarWidth[] = lineNumberMaxWidth
  redraw(this)


method init*(this: CodeEditorContent) =
  procCall this.super.init()

  this.font{} = font_monospace.withSize(12)

  this.makeLayout:
    - MouseArea.new:
      this.fillVertical(parent)
      x = binding: parent.breakpointBarWidth[] + parent.lineNumberBarWidth[] + parent.changesBarWidth[]
      w = binding: parent.arrowBarWidth[]

      root.nonFoldedArrowsVisible[] = binding: this.hovered[]

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
        for i, line in root.arrangement.lines:
          if line.isHidden: continue
          if this.mouseY[] >= line.rect.y and this.mouseY[] < line.rect.y + line.rect.h:
            let col = line.posToCol(vec2(this.mouseX[], this.mouseY[] - line.rect.y))
            let append = Key.lalt in this.parentWindow.keyboard.pressed or Key.ralt in this.parentWindow.keyboard.pressed
            root.arrangement.setCursorPos(i, col, append)
            root.dragingCursorI = root.arrangement.cursors.high
            redraw(root)
            break

      on this.moved:
        if this.pressed[]:
          root.arrangement.selectToPos(root.dragingCursorI, this.mouseXy[])
          redraw(root)


proc updateContent(this: CodeEditor) =
  let path = currentScript[]
  try:
    this.content.filename = path
    this.content.setArrangement(readFile(path))
  except CatchableError as exc:
    this.content.filename = ""
    this.content.setArrangement("Unable to read script: " & path & "\n" & exc.msg)



method init*(this: CodeEditor) =
  procCall this.super.init()

  this.makeLayout:
    - UiRect.new:
      this.fill(parent)
      color = colorTheme.bgTextArea

    - ScrollArea.new:
      this.fill(parent)

      + this.verticalScrollbar[].UiRect:
        color = colorTheme.bgScrollBar

      + this.horizontalScrollbar[].UiRect:
        color = colorTheme.bgScrollBar

      - CodeEditorContent.new as root.content:
        w = binding: parent.w[] - ScrollBarWidth

      verticalScrollOverFit = binding: this.h[] - root.content.font[].size * 2

    root.updateContent()
    on currentScript.changed: root.updateContent()
    on this.w.changed: root.updateContent()
