import std/[os, math]
import pkg/[ecs]
import pkg/siwin
import pkg/sigui/[uibase, window, mouseArea, animations, windowCreation]
import ./cgsand/gui/[code_editor, document_view, tool_bar, terminal, splitter]
import ./cgsand/logic/[configuration, scripts, file_openers]
import ./cgsand/logic/world_view/[renderer]

when defined(inspector):
  import pkg/sigui/inspector


globalLocale[0] = systemLocale()

when defined(useX11):
  let win = newSiwinGlobals(x11).newOpenglWindow(
    size = ivec2(config.window.w[].int32, config.window.h[].int32),
    title = "cgsand",
    frameless = true,
    transparent = true,
  ).newUiWindow
else:
  let win = newUiWindow(
    size = ivec2(config.window.w[].int32, config.window.h[].int32),
    title = "cgsand",
    frameless = true,
    transparent = true,
  )
win.siwinWindow.maximized = config.window.maximized[]


scripts.scriptEntityBounds = renderer.entityBoundsCallback
scripts.scriptWorldBounds = renderer.worldBoundsCallback
scripts.scriptTextSize = renderer.textSizeCallback


win.makeLayout:
  this.clearColor = "#00000000".color

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
      config.window.w[] = this.w[].int
  on this.h.changed:
    onWindowResize()
    if not win.siwinWindow.minimized:
      config.window.h[] = this.h[].int

  proc normalizePortions =
    let scale = config.codeEditorPortion[] + config.previewPortion[] + config.terminalPortion[]
    if not scale.almostEqual(1):
      config.codeEditorPortion{} /= scale
      config.previewPortion{} /= scale
      config.terminalPortion{} /= scale
      config.codeEditorPortion.changed.emit()
      config.previewPortion.changed.emit()
      config.terminalPortion.changed.emit()


  - RectShadow.new:
    this.fill(parent)
    radius = 7.5
    blurRadius = 10
    color = "#00000060".color


  - ClipRect.new as contentArea:
    this.fill(parent, 10)
    radius = 7.5

    on StateBoolChangedEvent:
      if e.kind == maximized:
        config.window.maximized[] = e.value
    
    radius = binding:
      if config.window.maximized[]: 0'f32
      else: 7.5
    
    binding:
      if config.window.maximized[]:
        this.fill(parent, 0)
      else:
        this.fill(parent, 10)
  

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
      w = binding: round(
        parent.w[] * config.codeEditorPortion[] /
        (config.codeEditorPortion[] + config.previewPortion[] + config.terminalPortion[])
      )
      this.fillVertical(parent)
      top = toolBar.bottom
      bottom = parent.bottom
      visibility = if config.codeEditorVisible[]: Visibility.visible else: Visibility.collapsed
      
      on this.visibility.changed:
        config.codeEditorVisible[] = this.visibility[] == visible
        save(config)
      
      on this.content.path.changed:
        config.scriptFile[] = this.content.path[]


    - Terminal.new as terminal:
      w = binding: round(
        parent.w[] * config.terminalPortion[] /
        (config.codeEditorPortion[] + config.previewPortion[] + config.terminalPortion[])
      )
      right = parent.right
      top = toolBar.bottom
      bottom = parent.bottom
      visibility = if config.terminalVisible[]: Visibility.visible else: Visibility.collapsed

      on this.visibility.changed:
        config.terminalVisible[] = this.visibility[] == visible


    - ToolBar(codeEditor: codeEditor, terminal: terminal) as toolBar:
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
        config.codeEditorPortion[] = max(e, 0) / contentArea.w[]
        normalizePortions()
    

    - Splitter.new:  # (document view / terminal)
      this.achor = terminal.left
      anchorGlobalX = binding: terminal.globalX[] + terminal.w[]

      on this.resized:
        config.terminalPortion[] = max(-e, 0) / contentArea.w[]
        normalizePortions()


  documentView.outputChannel[] = terminal.outputChannel


  let fileOpener = @[FileOpener CodeEditorFileOpener(editor: codeEditor)]
    
  toolBar.fileOpener[] = fileOpener
  terminal.fileOpener = fileOpener


  on DropEvent:
    let files = win.siwinWindow.dragndropClipboard.files
    if files.len > 0:
      fileOpener.open(Location(path: files[0]))

when defined(inspector):
  openInspector win
run win


when isMainModule:
  static: storeTypeids(currentSourcePath().parentDir / "cgsand/lib/typeids.txt")
  updateTranslations()

