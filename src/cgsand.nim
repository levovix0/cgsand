import std/[os, math]
import pkg/[ecs]
import pkg/siwin
import pkg/sigui/[uibase, window, mouseArea, animations, windowCreation]
import pkg/toscel/dialogs
import ./cgsand/gui/[code_editor, document_view, title_bar, terminal, splitter, breadcrumbs, file_tree, settings]
import ./cgsand/logic/[configuration, scripts, file_openers, shortcuts]
import ./cgsand/logic/world_view/[renderer]

when defined(inspector):
  import pkg/sigui/inspector


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

# results of system file dialogs (opened from the menu) are delivered on tick
win.installFileDialogPolling()


scripts.scriptEntityBounds = renderer.entityBoundsCallback
scripts.scriptWorldBounds = renderer.worldBoundsCallback
scripts.scriptTextSize = renderer.textSizeCallback


win.makeLayout:
  this.clearColor = "#00000000".color

  proc onWindowResize =
    # siwin window title/border regions are in device pixels (see windowPartAt)
    let uiScale = win.uiScale[]
    when defined(windows):
      let titleStartX = titleBar.titleRegionStartX[]
      let titleEndX = titleBar.w[] - titleBar.windowControlsWidth
      win.siwinWindow.setTitleRegion(
        (titleBar.globalXy + vec2(titleStartX, 0)) * uiScale,
        vec2(max(titleEndX - titleStartX, 0), titleBar.h[]) * uiScale,
      )
    else:
      win.siwinWindow.setTitleRegion(titleBar.globalXy * uiScale, titleBar.wh * uiScale)
    win.siwinWindow.setBorderWidth(10 * uiScale, 0, 40 * uiScale)

  defer: onWindowResize()
  on this.w.changed:
    onWindowResize()
    if not win.siwinWindow.minimized:
      config.window.w[] = this.w[].int
  on this.h.changed:
    onWindowResize()
    if not win.siwinWindow.minimized:
      config.window.h[] = this.h[].int
  on ResizeEvent:
    # also fired when only the UI scale changes (e.g. monitor change on Wayland),
    # in which case w/h properties do not change
    onWindowResize()

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
      color = binding: colorTheme[].bgTextArea


    - DocumentView.new as documentView:
      this.left = binding:
        if codeEditor.visibility[] == collapsed: parent.left
        else: codeEditor.right
      this.right = binding:
        if terminal.visibility[] == collapsed: parent.right
        else: terminal.left
      top = titleBar.bottom
      bottom = parent.bottom


    - FileTree.new as fileTree:
      this.left = parent.left
      top = titleBar.bottom
      bottom = parent.bottom
      w = binding:
        (if config.fileTreeVisible[]: 220'f32 else: 0'f32)
      visibility = binding:
        if config.fileTreeVisible[] and codeEditor.visibility[] == Visibility.visible:
          Visibility.visible
        else: Visibility.collapsed

      rootPath = getCurrentDir()
      currentFile = binding: config.scriptFile[]


    - CodeEditor.new as codeEditor:
      w = binding: round(
        parent.w[] * config.codeEditorPortion[] /
        (config.codeEditorPortion[] + config.previewPortion[] + config.terminalPortion[])
      ) - (if config.fileTreeVisible[]: fileTree.w[] else: 0'f32)
      this.left = binding:
        (if config.fileTreeVisible[]: parent.left + fileTree.w[] else: parent.left)
      this.fillVertical(parent)
      top = titleBar.bottom + 24
      bottom = parent.bottom
      visibility = if config.codeEditorVisible[]: Visibility.visible else: Visibility.collapsed

      on this.visibility.changed:
        config.codeEditorVisible[] = this.visibility[] == visible
        save(config)

      on this.content.path.changed:
        config.scriptFile[] = this.content.path[]

    - Breadcrumbs(fillHorizontal(codeEditor)) as breadcrumbs:
      top = titleBar.bottom
      bottom = codeEditor.top
      visibility = binding:
        if codeEditor.visibility[] == Visibility.visible: Visibility.visible
        else: Visibility.collapsed
      rootPath = getCurrentDir()
      currentFile = binding: config.scriptFile[]


    - Terminal.new as terminal:
      w = binding: round(
        parent.w[] * config.terminalPortion[] /
        (config.codeEditorPortion[] + config.previewPortion[] + config.terminalPortion[])
      )
      right = parent.right
      top = titleBar.bottom
      bottom = parent.bottom
      visibility = if config.terminalVisible[]: Visibility.visible else: Visibility.collapsed

      on this.visibility.changed:
        config.terminalVisible[] = this.visibility[] == visible


    - TitleBar(codeEditor: codeEditor, terminal: terminal) as titleBar:
      this.fillHorizontal(parent)
      h = 40

      doc = binding:
        if documentView.scriptStage[] == Idle and documentView.script[] != nil:
          documentView.script[].world
        else: nil

      currentFile = binding: config.scriptFile[]

    on titleBar.titleRegionStartX.changed:
      onWindowResize()


    # --- application shortcuts (also listed in the "Key combinations" dialog
    # and shown as hints in the menubar) ---

    - (shortcut(["Ctrl+O"], "file.open", "Open")):
      on this.activated:
        titleBar.openScript()

    - (shortcut(["Ctrl+S"], "file.save", "Save")):
      on this.activated:
        titleBar.saveScript()

    - (shortcut(["Ctrl+Shift+S"], "file.saveAs", "Save as")):
      on this.activated:
        titleBar.saveScriptAs()

    - (shortcut(["F5"], "app.recompile", "Recompile")):
      on this.activated:
        documentView.recompileScript()


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


    # --- settings window, created last so that it is above everything ---

    - SettingsWindow.new as settingsWindow:
      visibility = binding:
        if settingsWindow.opened[]: Visibility.visible else: Visibility.collapsed

    titleBar.settingsOverlay = settingsWindow


  documentView.outputChannel[] = terminal.outputChannel


  let fileOpener = @[FileOpener CodeEditorFileOpener(editor: codeEditor)]

  titleBar.fileOpener[] = fileOpener
  terminal.fileOpener = fileOpener
  breadcrumbs.fileOpener[] = fileOpener
  fileTree.fileOpener[] = fileOpener


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

