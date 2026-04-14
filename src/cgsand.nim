import std/[os]
import pkg/[vmath, ecs]
import pkg/siwin
import pkg/sigui/uibase
import ./cgsand/gui/[code_editor, document_view, tool_bar]
import ./cgsand/logic/[config]

globalLocale[0] = systemLocale()

when defined(useX11):
  let win = newSiwinGlobals(x11).newOpenglWindow(title = "cgsand", frameless = true, transparent = true).newUiWindow
else:
  let win = newUiWindow(title = "cgsand", frameless = true, transparent = true)



win.makeLayout:
  this.clearColor = "#00000000".color
  
  proc onWindowResize =
    when defined(windows):
      win.siwinWindow.setTitleRegion(toolBar.globalXy, vec2(toolBar.w[] - toolBar.windowControlsWidth, toolBar.h[]))
    else:
      win.siwinWindow.setTitleRegion(toolBar.globalXy, toolBar.wh)
    win.siwinWindow.setBorderWidth(10, 0, 40)

  defer: onWindowResize()
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

    this.onSignal.connectTo this, e:
      type Ev = ref StateBoolChangedEvent
      if e of WindowEvent and e.WindowEvent.event of Ev and e.WindowEvent.event.Ev.kind == maximized:
        if e.WindowEvent.event.Ev.value:
          this.fill(parent, 0)
          this.radius[] = 0
        else:
          this.fill(parent, 10)
          this.radius[] = 7.5
  
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
      this.left = binding:
        if codeEditor.visibility[] == collapsed: parent.left
        else: codeEditor.right
      right = parent.right
      top = toolBar.bottom
      bottom = parent.bottom

    - ToolBar(codeEditor: codeEditor) as toolBar:
      this.fillHorizontal(parent)
      h = 60

run win


when isMainModule:
  static: storeTypeids(currentSourcePath().parentDir / "cgsand/lib/typeids.txt")
  updateTranslations()

