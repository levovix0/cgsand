import std/[unicode]
import pkg/[vmath]
import pkg/rice/texts
import pkg/toscel/[fonts, colors]
import pkg/sigui/[uibase, scrollArea]
import ../logic/[config, code_editor]


type
  Colorscheme* = object
    textColor*: Color = color_fg
    lineNumberColor*: Color = "#606070".color

  CodeEditorContent* = ref object of Uiobj
    file*: Property[CodeFile]
    font*: Property[Font]
    colorscheme*: Property[Colorscheme]
    
    breakpointBarWidth*: Property[float32] = 20'f32.property
    lineNumberBarWidth*: Property[float32] = 20'f32.property
    changesBarWidth*: Property[float32] = 5'f32.property
    arrowBarWidth*: Property[float32] = 20'f32.property

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


method draw*(this: CodeEditorContent, ctx: DrawContext) =
  this.drawBefore(ctx)

  let winRect = rect(vec2(), this.parentUiRoot.wh)
  let textOffsetX = this.textOffsetX
  let lineNumberBarOffsetX_r = this.lineNumberBarOffsetX + this.lineNumberBarWidth[]

  if this.visibility[] == visible:
    for i, line in this.arrangement.lines:
      if this.globalY + line.rect.y + line.rect.h < winRect.y: continue
      if this.globalY + line.rect.y > winRect.y + winRect.h: continue
      
      ctx.drawText(
        (this.globalXy + ctx.offset + line.rect.xy + vec2(lineNumberBarOffsetX_r, 0)).vec3(0),
        typeset(this.font, $(i + 1)),
        this.colorscheme{}.lineNumberColor.vec4,
        origin=vec2(1, 0),
      )
      
      ctx.drawText(
        (this.globalXy + ctx.offset + line.rect.xy + vec2(textOffsetX, 0)).vec3(0),
        line.arrangement,
        this.colorscheme{}.textColor.vec4,
      )

  this.drawAfter(ctx)


proc updateArrangement(this: CodeEditorContent) =
  let lineNumberMaxWidth = typeset(this.font, $this.file[].lines.len).layoutBounds.x
  this.lineNumberBarWidth[] = lineNumberMaxWidth

  this.arrangement = this.file[].toArrangement(this.font[], this.w[] - this.textOffsetX)
  if this.arrangement.lines.len == 0:
    this.h[] = 0
  this.h[] = this.arrangement.lines[^1].rect.y + this.arrangement.lines[^1].rect.h


method init*(this: CodeEditorContent) =
  procCall this.super.init()

  this.font{} = findSystemFont(@["firacode", "monospace"] & @["roboto", "ubuntu", "notosans", "arial", "adwaitasans"]).withSize(12)
  this.colorscheme{} = Colorscheme()




proc updateContent(this: CodeEditor) =
  try:
    this.content.file[] = readCodeFile(currentScript[])
    this.content.colorscheme{}.textColor = color_fg
  except CatchableError as exc:
    this.content.file[] = CodeFile(lines: @[("Unable to read script: " & currentScript[] & "\n" & exc.msg).toRunes])
    this.content.colorscheme{}.textColor = "#f06060".color



method init*(this: CodeEditor) =
  procCall this.super.init()

  this.makeLayout:
    - UiRect.new:
      this.fill(parent)
      color = "#202020".color

    - ScrollArea.new:
      this.fill(parent)

      + this.verticalScrollbar[].UiRect:
        color = "#808080".color

      + this.horizontalScrollbar[].UiRect:
        color = "#808080".color

      - CodeEditorContent.new as root.content:
        w = binding: parent.w[]
  
    root.updateContent()
    on currentScript.changed: root.updateContent()
    on this.w.changed: root.updateContent()
