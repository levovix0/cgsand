import std/[os]
import pkg/[vmath, ecs]
import pkg/siwin
import pkg/sigui/uibase
import ./cgsand/gui/[code_editor, document_view, tool_bar]

when defined(useX11):
  let win = newSiwinGlobals(x11).newOpenglWindow(title = "cgsand", frameless = true, transparent = true).newUiWindow
else:
  let win = newUiWindow(title = "cgsand", frameless = true, transparent = true)

proc onWindowResize =
  win.siwinWindow.setTitleRegion(vec2(10, 10), vec2(float32 win.siwinWindow.size.x - 10*2, 60))


win.makeLayout:
  this.clearColor = "#00000000".color
  
  onWindowResize()
  on this.w.changed: onWindowResize()
  on this.h.changed: onWindowResize()

  - RectShadow.new:
    this.fill(parent)
    radius = 7.5
    blurRadius = 10
    color = "#00000060".color

  - ClipRect.new:
    this.fill(parent, 10)
    radius = 7.5
  
    - UiRect.new:
      this.fill(parent)
      color = "#202020".color

    - CodeEditor.new as codeEditor:
      w = binding: parent.w[] / 2
      this.fillVertical(parent)
      top = toolBar.bottom
      bottom = parent.bottom

    - DocumentView.new as documentView:
      w = binding: parent.w[] / 2
      left = codeEditor.right
      right = parent.right
      top = toolBar.bottom
      bottom = parent.bottom

    - ToolBar.new as toolBar:
      this.fillHorizontal(parent)
      h = 60

run win


when isMainModule:
  static: storeTypeids(currentSourcePath().parentDir / "cgsand/lib/typeids.txt")

