import std/[unicode, sets]
import pkg/[vmath, chroma]
import pkg/rice/[texts, contexts, gl, primitives]
import pkg/toscel/fonts
import pkg/sigui/[uibase, scrollArea, mouseArea]
import ../logic/[config, code_editor]


type
  CodeEditorContent* = ref object of Uiobj
    file*: Property[CodeFile]
    font*: Property[Font]

    breakpointBarWidth*: Property[float32] = 20'f32.property
    lineNumberBarWidth*: Property[float32] = 20'f32.property
    changesBarWidth*: Property[float32] = 5'f32.property
    arrowBarWidth*: Property[float32] = 20'f32.property

    nonFoldedArrowsVisible: Property[bool]

    arrangement: CodeArrangement

  CodeEditor* = ref object of Uiobj
    content*: CodeEditorContent


proc updateArrangement(this: CodeEditorContent)

addFirstHandHandler CodeEditorContent, "file":
  updateArrangement(this)
  autoredraw(this)

registerComponent CodeEditor
registerComponent CodeEditorContent



proc textOffsetX(this: CodeEditorContent): float32 =
  this.breakpointBarWidth[] + this.lineNumberBarWidth[] + this.changesBarWidth[] + this.arrowBarWidth[]

proc lineNumberBarOffsetX(this: CodeEditorContent): float32 =
  this.breakpointBarWidth[]

proc arrowBarOffsetX(this: CodeEditorContent): float32 =
  this.breakpointBarWidth[] + this.lineNumberBarWidth[] + this.changesBarWidth[]


proc drawHighlightedText*(
  ctx: DrawContext,
  pos: Vec3,
  arrangement: Arrangement,
  kinds: openArray[CodeKind],
  origin: Vec2 = vec2(0, 0),
  exactBoundaries = false,
  transform = mat4(),
) =
  if arrangement == nil or arrangement.fonts.len == 0:
    return

  var context = ctx.startTextDrawing(arrangement.fonts[0])

  let pos = ctx.viewportToGlMatrix * transform * pos
  let box = arrangement.computeBounds()

  let offset =
    if exactBoundaries: vec2(box.x, -box.y) * ctx.px + vec2(box.w, -box.h) * origin * ctx.px
    else: vec2(box.w + box.x, -(box.h + box.y)) * origin * ctx.px

  for i, rune in arrangement.runes:
    var rect = arrangement.selectionRects[i]
    rect.wh = rect.wh + vec2(2, 2)

    context.color.uniform = kinds[i].color.vec4
    ctx.fastDrawRune(rune, rect(pos.xy + vec2(rect.x, -rect.y) * ctx.px - offset, rect.wh), context)

  ctx.endTextDrawing()


proc updateHeight(this: CodeEditorContent) =
  if this.arrangement == nil:
    this.h[] = 0
    return
  this.h[] = this.arrangement.visibleHeight()


method draw*(this: CodeEditorContent, ctx: DrawContext) =
  this.drawBefore(ctx)

  let winRect = rect(vec2(), this.parentUiRoot.wh)
  let textOffsetX = this.textOffsetX
  let lineNumberBarOffsetX_r = this.lineNumberBarOffsetX + this.lineNumberBarWidth[]
  let arrowBarCenterX = this.arrowBarOffsetX + this.arrowBarWidth[] / 2

  if this.visibility[] == visible:
    for i, line in this.arrangement.lines:
      if line.isHidden: continue

      if this.globalY + line.rect.y + line.lineHeight < winRect.y: continue
      if this.globalY + line.rect.y > winRect.y + winRect.h: continue

      ctx.drawText(
        (this.globalXy + ctx.offset + vec2(lineNumberBarOffsetX_r, line.rect.y)).vec3(0),
        typeset(this.font, $(i + 1)),
        colorTheme.sLineNumber.vec4,
        origin=vec2(1, 0),
      )

      if line.foldable:
        let arrowChar = if i in this.arrangement.foldedLines: "▶" else: "▼"
        if i in this.arrangement.foldedLines or this.nonFoldedArrowsVisible[]:
          ctx.drawText(
            (this.globalXy + ctx.offset + vec2(arrowBarCenterX, line.rect.y)).vec3(0),
            typeset(this.font, arrowChar),
            colorTheme.sLineNumber.vec4,
            origin=vec2(0.5, 0),
          )

      drawHighlightedText(
        ctx,
        (this.globalXy + ctx.offset + vec2(textOffsetX, line.rect.y)).vec3(0),
        line.arrangement,
        line.kinds,
      )

      if line.foldable and i in this.arrangement.foldedLines:
        const lineH = 1'f32
        let rect = line.visibleRect
        
        ctx.fillRect(
          rect(
            this.globalXy + ctx.offset + vec2(textOffsetX + rect.x, rect.y + rect.h - lineH),
            vec2(rect.w, lineH),
          ),
          color(0.3'f32, 0.6'f32, 1.0'f32),
        )

  this.drawAfter(ctx)


proc updateArrangement(this: CodeEditorContent) =
  let lineNumberMaxWidth = typeset(this.font, $this.file[].lines.len).layoutBounds.x
  this.lineNumberBarWidth[] = lineNumberMaxWidth

  this.arrangement = this.file[].toArrangement(this.font[], this.w[] - this.textOffsetX)
  this.updateHeight()


method init*(this: CodeEditorContent) =
  procCall this.super.init()

  this.font{} = findSystemFont(@["firacode", "monospace"] & @["roboto", "ubuntu", "notosans", "arial", "adwaitasans"]).withSize(12)

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
          if clickY >= line.rect.y and clickY < line.rect.y + line.lineHeight:
            if line.foldable:
              root.arrangement.toggleFold(i)
              root.updateHeight()
              redraw(root)
            break




proc updateContent(this: CodeEditor) =
  try:
    this.content.file[] = readCodeFile(currentScript[])
  except CatchableError as exc:
    this.content.file[] = CodeFile(lines: @[("Unable to read script: " & currentScript[] & "\n" & exc.msg).toRunes])



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
        w = binding: parent.w[]

      verticalScrollOverFit = binding: this.h[] - root.content.font[].size * 2

    root.updateContent()
    on currentScript.changed: root.updateContent()
    on this.w.changed: root.updateContent()
