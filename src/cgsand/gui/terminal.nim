import pkg/[vmath, chroma]
import pkg/rice/[contexts, gl, primitives]
import pkg/toscel/[focus]
import pkg/sigui/[uibase, scrollArea, mouseArea]
import pkg/sigui/window
import ../logic/[config, code_editor]
import ./[highlighted_text]


type
  TerminalContent* = ref object of Uiobj
    font*: Property[Font]

    arrangement: CodeArrangement
    dragingCursorI: int

  Terminal* = ref object of Uiobj
    content*: TerminalContent
    text*: Property[string]

    m_outputChannel*: Channel[string]

const MinSelectionWidth = 6'f32
const ScrollBarWidth = 5'f32


registerComponent Terminal
registerComponent TerminalContent



template outputChannel*(this: Terminal): var Channel[string] = this.m_outputChannel



proc updateHeight(this: TerminalContent) =
  if this.arrangement == nil:
    this.h[] = 0
    return
  this.h[] = this.arrangement.visibleHeight()


method drawInner*(this: TerminalContent, ctx: DrawContext) =
  let textOffsetX = 0'f32

  for i, line in this.arrangement.lines:
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


proc setArrangement(this: TerminalContent, text: string) =
  # todo: if only the width changed, update arrangement instead of regenerating it
  this.arrangement = text.toArrangement(this.font[], this.w[])
  this.updateHeight()
  redraw(this)


method init*(this: TerminalContent) =
  procCall this.super.init()

  this.font{} = font_monospace.withSize(12)

  this.makeLayout:
    - MouseArea.new:
      this.fillVertical(parent)
      w = binding: parent.w[]

      allowEventFallthrough = true

      on this.mouseButton:
        if e.button == MouseButton.left and e.pressed:
          setFocus root
          for i, line in root.arrangement.lines:
            if line.isHidden: continue
            if this.mouseY[] >= line.rect.y and this.mouseY[] < line.rect.y + line.rect.h:
              let col = line.posToCol(vec2(this.mouseX[], this.mouseY[] - line.rect.y))
              let append = Key.lalt in e.window.keyboard.pressed or Key.ralt in e.window.keyboard.pressed
              root.arrangement.setCursorPos(i, col, append)
              root.dragingCursorI = root.arrangement.cursors.high
              redraw(root)
              break

      on this.moved:
        if this.pressed[]:
          root.arrangement.selectToPos(root.dragingCursorI, this.mouseXy[])
          redraw(root)


proc updateContent(this: Terminal) =
  this.content.setArrangement(this.text[])



method init*(this: Terminal) =
  procCall this.super.init()

  this.m_outputChannel.open()

  this.parentUiRoot.onTick.connectTo this:
    # drain terminal output
    var chunk = ""
    while true:
      let (ok, text) = this.m_outputChannel.tryRecv()
      if not ok: break
      chunk.add text
    if chunk.len > 0:
      this.text[] = this.text[] & chunk

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

      - TerminalContent.new as root.content:
        w = binding: parent.w[] - ScrollBarWidth

      verticalScrollOverFit = binding: this.h[] - root.content.font[].size * 2

    root.updateContent()
    on this.text.changed: root.updateContent()
    on this.w.changed: root.updateContent()
