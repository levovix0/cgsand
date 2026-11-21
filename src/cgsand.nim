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


scripts.scriptEntityBounds = renderer.entityBoundsCallback
scripts.scriptWorldBounds = renderer.worldBoundsCallback
scripts.scriptTextSize = renderer.textSizeCallback


type
  CgsandApp* = ref object
    window*: UiWindow
    documentView*: DocumentView
    codeEditor*: CodeEditor
    fileTree*: FileTree
    breadcrumbs*: Breadcrumbs
    settingsWindow*: SettingsWindow
    terminal*: Terminal
    titleBar*: TitleBar


proc setupApp*(win: UiWindow): CgsandApp =
  ## builds the whole application UI inside an already created window `win`:
  ## document view, code editor, file tree, breadcrumbs, terminal and title bar
  ##
  ## does not create a window and does not run the event loop, so it can be
  ## used with a headless window (sigui/testutils) to test the app without
  ## showing anything on screen:
  ##
  ## .. code-block:: nim
  ##   import sigui/testutils, cgsand
  ##   let win = newHeadlessUiWindow(size = ivec2(1280, 800))
  ##   let app = setupApp(win)
  ##   win.frame()
  ##   app.codeEditor.open(Location(path: "examples/tutorial_use.nim"))
  ##   win.frame()
  var app = CgsandApp(window: win)
  result = app

  win.makeLayout:
    this.clearColor = "#00000000".color

    proc onWindowResize =
      # siwin window title/border regions are in device pixels (see windowPartAt)
      let uiScale = win.uiScale[]
      when defined(windows):
        let titleStartX = app.titleBar.titleRegionStartX[]
        let titleEndX = app.titleBar.w[] - app.titleBar.windowControlsWidth
        win.siwinWindow.setTitleRegion(
          (app.titleBar.globalXy + vec2(titleStartX, 0)) * uiScale,
          vec2(max(titleEndX - titleStartX, 0), app.titleBar.h[]) * uiScale,
        )
      else:
        win.siwinWindow.setTitleRegion(app.titleBar.globalXy * uiScale, app.titleBar.wh * uiScale)
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


      - DocumentView.new as app.documentView:
        this.left = binding:
          if app.codeEditor.visibility[] == collapsed: parent.left
          else: app.codeEditor.right
        this.right = binding:
          if app.terminal.visibility[] == collapsed: parent.right
          else: app.terminal.left
        top = app.titleBar.bottom
        bottom = parent.bottom


      - FileTree.new as app.fileTree:
        this.left = parent.left
        top = app.titleBar.bottom
        bottom = parent.bottom
        w = binding:
          (if config.fileTreeVisible[]: 220'f32 else: 0'f32)
        visibility = binding:
          if config.fileTreeVisible[] and app.codeEditor.visibility[] == Visibility.visible:
            Visibility.visible
          else: Visibility.collapsed

        rootPath = getCurrentDir()
        currentFile = binding: config.scriptFile[]


      - CodeEditor.new as app.codeEditor:
        w = binding: round(
          parent.w[] * config.codeEditorPortion[] /
          (config.codeEditorPortion[] + config.previewPortion[] + config.terminalPortion[])
        ) - (if config.fileTreeVisible[]: app.fileTree.w[] else: 0'f32)
        this.left = binding:
          (if config.fileTreeVisible[]: parent.left + app.fileTree.w[] else: parent.left)
        this.fillVertical(parent)
        top = app.titleBar.bottom + 24
        bottom = parent.bottom
        visibility = if config.codeEditorVisible[]: Visibility.visible else: Visibility.collapsed

        on this.visibility.changed:
          config.codeEditorVisible[] = this.visibility[] == visible
          save(config)

        on this.content.path.changed:
          config.scriptFile[] = this.content.path[]

      - Breadcrumbs(fillHorizontal(app.codeEditor)) as app.breadcrumbs:
        top = app.titleBar.bottom
        bottom = app.codeEditor.top
        visibility = binding:
          if app.codeEditor.visibility[] == Visibility.visible: Visibility.visible
          else: Visibility.collapsed
        rootPath = getCurrentDir()
        currentFile = binding: config.scriptFile[]


      - Terminal.new as app.terminal:
        w = binding: round(
          parent.w[] * config.terminalPortion[] /
          (config.codeEditorPortion[] + config.previewPortion[] + config.terminalPortion[])
        )
        right = parent.right
        top = app.titleBar.bottom
        bottom = parent.bottom
        visibility = if config.terminalVisible[]: Visibility.visible else: Visibility.collapsed

        on this.visibility.changed:
          config.terminalVisible[] = this.visibility[] == visible


      - TitleBar(codeEditor: app.codeEditor, terminal: app.terminal) as app.titleBar:
        this.fillHorizontal(parent)
        h = 40

        doc = binding:
          if app.documentView.scriptStage[] == Idle and app.documentView.script[] != nil:
            app.documentView.script[].world
          else: nil

        currentFile = binding: config.scriptFile[]

        on this.titleRegionStartX.changed:
          onWindowResize()


      # --- application shortcuts (also listed in the "Key combinations" dialog
      # and shown as hints in the menubar) ---

      - (shortcut(["Ctrl+O"], "file.open", "Open")):
        on this.activated:
          app.titleBar.openScript()

      - (shortcut(["Ctrl+S"], "file.save", "Save")):
        on this.activated:
          app.titleBar.saveScript()

      - (shortcut(["Ctrl+Shift+S"], "file.saveAs", "Save as")):
        on this.activated:
          app.titleBar.saveScriptAs()

      - (shortcut(["F5"], "app.recompile", "Recompile")):
        on this.activated:
          app.documentView.recompileScript()


      - Splitter.new:  # (codeEditor / document view)
        this.achor = app.codeEditor.right
        anchorGlobalX = binding: app.codeEditor.globalX[]

        on this.resized:
          config.codeEditorPortion[] = max(e, 0) / contentArea.w[]
          normalizePortions()


      - Splitter.new:  # (document view / terminal)
        this.achor = app.terminal.left
        anchorGlobalX = binding: app.terminal.globalX[] + app.terminal.w[]

        on this.resized:
          config.terminalPortion[] = max(-e, 0) / contentArea.w[]
          normalizePortions()


      # --- settings window, created last so that it is above everything ---

      - SettingsWindow.new as app.settingsWindow:
        visibility = binding:
          if app.settingsWindow.opened[]: Visibility.visible else: Visibility.collapsed

      app.titleBar.settingsOverlay = app.settingsWindow


    app.documentView.outputChannel[] = app.terminal.outputChannel


    let fileOpener = @[FileOpener CodeEditorFileOpener(editor: app.codeEditor)]

    app.titleBar.fileOpener[] = fileOpener
    app.terminal.fileOpener = fileOpener
    app.breadcrumbs.fileOpener[] = fileOpener
    app.fileTree.fileOpener[] = fileOpener


    on DropEvent:
      let files = win.siwinWindow.dragndropClipboard.files
      if files.len > 0:
        fileOpener.open(Location(path: files[0]))


when isMainModule:
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

  discard setupApp(win)

  when defined(inspector):
    openInspector win
  run win


when isMainModule:
  static: storeTypeids(currentSourcePath().parentDir / "cgsand/lib/typeids.txt")
  updateTranslations()
