import std/[os]
import pkg/[ecs]
import pkg/siwin
import pkg/sigui/[uibase, window, mouseArea, animations]
import pkg/toscel/[transitions]
import ./cgsand/gui/[code_editor, document_view, tool_bar]
import ./cgsand/logic/[config, scripts]

globalLocale[0] = systemLocale()

when defined(useX11):
  let win = newSiwinGlobals(x11).newOpenglWindow(title = "cgsand", frameless = true, transparent = true).newUiWindow
else:
  let win = newUiWindow(title = "cgsand", frameless = true, transparent = true)


var codeEditorPortion = 0.5.property
autosaveProperty codeEditorPortion


win.makeLayout:
  this.clearColor = "#00000000".color

  this.onSignal.connectTo this, e:
    type Ev = ref DropEvent
    if e of WindowEvent and e.WindowEvent.event of Ev:
      let files = win.siwinWindow.dragndropClipboard.files
      if files.len > 0:
        currentScript[] = files[0]

  proc onWindowResize =
    when defined(windows):
      win.siwinWindow.setTitleRegion(toolBar.globalXy + vec2(400,0), vec2(toolBar.w[] - toolBar.windowControlsWidth, toolBar.h[]) -  vec2(400,0))
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

  - ClipRect.new as contentArea:
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
      w = binding: round(parent.w[] * codeEditorPortion[])
      this.fillVertical(parent)
      top = toolBar.bottom
      bottom = parent.bottom

    - DocumentView.new as documentView:
      this.left = binding:
        if codeEditor.visibility[] == collapsed: parent.left
        else: codeEditor.right
      right = parent.right
      top = toolBar.bottom
      bottom = parent.bottom

    - ToolBar(codeEditor: codeEditor) as toolBar:
      this.fillHorizontal(parent)
      h = 60
      doc = binding:
        if documentView.scriptStage[] == Idle and documentView.script[] != nil:
          documentView.script[].world
        else: nil
    
    - MouseArea.new:  # splitter (codeEditor / document view)
      this.fillVertical(codeEditor)
      left = codeEditor.right - 2
      right = codeEditor.right + 2
      visibility = binding: codeEditor.visibility

      - UiRect.new:
        this.fill(parent)

        color = binding:
          if parent.hovered[] or parent.grabbed[]: "#0E77D2".color
          else: "#0E77D200".color
        addTransition this.color

      globalTransform = true

      on this.moved:
        if this.grabbed[]:
          let w = (this.mouseX[] + this.globalX[]) - codeEditor.globalX[]
          codeEditorPortion[] = w / contentArea.w[]

run win


when isMainModule:
  static: storeTypeids(currentSourcePath().parentDir / "cgsand/lib/typeids.txt")
  updateTranslations()

