import std/[unicode]
import pkg/[vmath]
import pkg/rice/texts
import pkg/toscel/[fonts, colors]
import pkg/sigui/[uibase, scrollArea]
import ../logic/[config, code_editor]


type
  Colorscheme* = object
    textColor*: Color = color_fg

  CodeEditorContent* = ref object of Uiobj
    file*: Property[CodeFile]
    font*: Property[Font]
    colorscheme*: Property[Colorscheme]

    arrangement*: CodeArrangement

  CodeEditor* = ref object of Uiobj
    content*: CodeEditorContent

proc updateArrangement(this: CodeEditorContent)

addFirstHandHandler CodeEditorContent, "file":
  updateArrangement(this)
  autoredraw(this)

registerComponent CodeEditor
registerComponent CodeEditorContent


method draw*(this: CodeEditorContent, ctx: DrawContext) =
  this.drawBefore(ctx)

  let winRect = rect(vec2(), this.parentUiRoot.wh)

  if this.visibility[] == visible:
    for line in this.arrangement.lines:
      if this.globaly + line.rect.y + line.rect.h < winRect.y: continue
      if this.globaly + line.rect.y > winRect.y + winRect.h: continue
      ctx.drawText((this.globalXy + ctx.offset + line.rect.xy).vec3(0), line.arrangement, this.colorscheme{}.textColor.vec4)

  this.drawAfter(ctx)


proc updateArrangement(this: CodeEditorContent) =
  this.arrangement = this.file[].toArrangement(this.font[], this.w[])
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
      this.fill(parent, 10)

      + this.verticalScrollbar[].UiRect:
        color = "#808080".color

      + this.horizontalScrollbar[].UiRect:
        color = "#808080".color

      - CodeEditorContent.new as root.content:
        w = binding: parent.w[]
  
    root.updateContent()
    on currentScript.changed: root.updateContent()
