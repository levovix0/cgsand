import std/[os, math]
import pkg/[ecs]
import pkg/siwin
import pkg/sigui/[uibase, window, mouseArea]
import ./cgsand/gui/[code_editor, document_view, tool_bar, terminal, splitter]
import ./cgsand/logic/[config, scripts]

globalLocale[0] = systemLocale()

when defined(useX11):
  let win = newSiwinGlobals(x11).newOpenglWindow(size = ivec2(currentConfig.windowW.int32, currentConfig.windowH.int32), title = "cgsand", frameless = true, transparent = true).newUiWindow
else:
  let win = newUiWindow(size = ivec2(currentConfig.windowW.int32, currentConfig.windowH.int32), title = "cgsand", frameless = true, transparent = true)


var codeEditorPortion: Property[float]
var previewPortion: Property[float]
var terminalPortion: Property[float]
autosaveProperty codeEditorPortion
autosaveProperty previewPortion
autosaveProperty terminalPortion


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
  on this.w.changed:
    onWindowResize()
    if not win.siwinWindow.minimized:
      currentConfig.windowW = this.w[].int
      save(currentConfig)
  on this.h.changed:
    onWindowResize()
    if not win.siwinWindow.minimized:
      currentConfig.windowH = this.h[].int
      save(currentConfig)

  proc normalizePortions =
    let scale = codeEditorPortion[] + previewPortion[] + terminalPortion[]
    if not scale.almostEqual(1):
      codeEditorPortion{} /= scale
      previewPortion{} /= scale
      terminalPortion{} /= scale
      codeEditorPortion.changed.emit()
      previewPortion.changed.emit()
      terminalPortion.changed.emit()

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


    - DocumentView.new as documentView:
      this.left = binding:
        if codeEditor.visibility[] == collapsed: parent.left
        else: codeEditor.right
      this.right = binding:
        if terminal.visibility[] == collapsed: parent.right
        else: terminal.left
      top = toolBar.bottom
      bottom = parent.bottom

    - CodeEditor.new as codeEditor:
      w = binding: round(parent.w[] * codeEditorPortion[] / (codeEditorPortion[] + previewPortion[] + terminalPortion[]))
      this.fillVertical(parent)
      top = toolBar.bottom
      bottom = parent.bottom
      visibility = if currentConfig.codeEditorVisible: Visibility.visible else: Visibility.collapsed
      on this.visibility.changed:
        currentConfig.codeEditorVisible = this.visibility[] == visible
        save(currentConfig)

    - Terminal.new as terminal:
      w = binding: round(parent.w[] * terminalPortion[] / (codeEditorPortion[] + previewPortion[] + terminalPortion[]))
      right = parent.right
      top = toolBar.bottom
      bottom = parent.bottom


    documentView.outputChannel[] = terminal.outputChannel

    on documentView.scriptStage.changed:
      if documentView.scriptStage[] == Compiling:
        terminal.clear()

    - ToolBar(codeEditor: codeEditor) as toolBar:
      this.fillHorizontal(parent)
      h = 60

      doc = binding:
        if documentView.scriptStage[] == Idle and documentView.script[] != nil:
          documentView.script[].world
        else: nil
    

    - Splitter.new:  # (codeEditor / document view)
      this.achor = codeEditor.right
      anchorGlobalX = binding: codeEditor.globalX[]

      on this.resized:
        codeEditorPortion[] = max(e, 0) / contentArea.w[]
        normalizePortions()
    
    - Splitter.new:  # (document view / terminal)
      this.achor = terminal.left
      anchorGlobalX = binding: terminal.globalX[] + terminal.w[]

      on this.resized:
        terminalPortion[] = max(-e, 0) / contentArea.w[]
        normalizePortions()

run win


when isMainModule:
  static: storeTypeids(currentSourcePath().parentDir / "cgsand/lib/typeids.txt")
  updateTranslations()

