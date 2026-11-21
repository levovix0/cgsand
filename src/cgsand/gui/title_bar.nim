import std/[os, algorithm, sequtils, strutils]
import pkg/[ecs]
import pkg/siwin/platforms/any/window
import pkg/pixie/images
import pkg/sigui/[uibase, mouseArea, animations, scrollArea, windowCreation]
import pkg/toscel/[colors, fonts, comboBox, lineEdit, button, panel, label, listWidget, menuBar, modalOverlay, dialogs]
import ../logic/[configuration, file_openers, shortcuts, appinfo]
import ../logic/world_view/[pdf_renderer]
import ./[icons, code_editor]

type
  BrowserItem = object
    name: string
    path: string
    isDir: bool

  TitleButton = ref object of Uiobj
    pressedColor: Property[Color]
    hoveredColor: Property[Color]
    icon: Property[Image]
    activated: Event[void]

    mouseArea: MouseArea


  TitleBar* = ref object of Uiobj
    codeEditor*: CodeEditor
    terminal*: Uiobj
    currentFile*: Property[string]
    doc*: Property[ptr World]
    fileOpener* {.unprintable.}: Property[seq[FileOpener]]
    settingsOverlay* {.unprintable.}: ModalOverlay
      ## opened by the "Options" menu entry, the overlay itself is created in cgsand.nim
    titleRegionStartX*: Property[float32]
      ## Local X coordinate after the interactive titlebar controls. On Windows
      ## the custom title region must start here so it does not steal clicks.

    menuBar: MenuBar

    saveFileDialogOpened: Property[bool]
    shortcutsDialogOpened: Property[bool]
    aboutDialogOpened: Property[bool]


registerComponent TitleButton
registerComponent TitleBar


proc `<`(a, b: BrowserItem): bool = a.name < b.name


proc windowControlsWidth*(this: TitleBar): float32 =
  180


method init(this: TitleButton) =
  procCall this.super.init()

  this.makeLayout:
    - MouseArea.new as root.mouseArea:
      this.fill(parent)

      - UiRect.new:
        this.fill(parent)

        color = binding:
          if root.mouseArea.pressed[]: root.pressedColor[]
          elif root.mouseArea.hovered[]: root.hoveredColor[]
          else: "#00000000".color

        - this.color.transition(0.1's):
          easing = outSquareEasing

        - UiImage.new:
          this.centerIn(parent)
          this.w[] = 32
          this.h[] = 32
          this.image = binding:
            if root.icon[] != nil:
              root.root.ctx.imageFromBuffer(ivec2(root.icon[].width.int32, root.icon[].height.int32), root.icon[].data[0].addr)
            else:
              nil

      on this.clicked:
        root.activated.emit()


proc getDirItems*(dir: string): seq[BrowserItem] =
  result = @[]

  var folders: seq[BrowserItem] = @[]
  var files: seq[BrowserItem] = @[]

  for kind, path in walkDir(dir):
    if kind in {pcDir, pcLinkToDir}:
      folders.add(BrowserItem(name: path.splitPath.tail & "/", path: path, isDir: true))
    else:
      files.add(BrowserItem(name: path.splitPath.tail, path: path, isDir: false))

  result.add sorted folders
  result.add sorted files


proc shortcutGroups(): seq[(string, seq[int])] =
  ## all registered shortcuts grouped by the prefix of their id ("file.open"
  ## -> group "file"); groups are sorted by category name
  for i, s in appShortcuts:
    let category = s.id.split('.', 1)[0]
    var found = false
    for g in result.mitems:
      if g[0] == category:
        g[1].add i
        found = true
        break
    if not found:
      result.add (category, @[i])

  result.sort(proc(a, b: (string, seq[int])): int = cmp(a[0], b[0]))


proc categoryTitle(category: string): string =
  case category
  of "app": tr"Application"
  of "edit": tr"Edit"
  of "file": tr"File"
  of "terminal": tr"Terminal"
  else: category.capitalizeAscii()


# ----- menu actions -----

proc openScript*(this: TitleBar) =
  openFilePanel(tr"Open file", getCurrentDir(),
    proc(path: string) =
      this.fileOpener[].open(Location(path: path)),
  )


proc saveScriptAs*(this: TitleBar) =
  let editor = this.codeEditor
  if editor == nil: return

  let defaultPath =
    if editor.content.path[].len > 0: editor.content.path[]
    else: getCurrentDir() / "document.nim"

  saveFilePanel(tr"Save file as", defaultPath,
    proc(path: string) =
      editor.content.path[] = path
      editor.content.saveFile(),
  )


proc saveScript*(this: TitleBar) =
  let editor = this.codeEditor
  if editor == nil: return

  if editor.content.path[].len == 0:
    this.saveScriptAs()
  else:
    editor.content.saveFile()


proc rebuildMenuBar(this: TitleBar) =
  ## (re)creates all menus; called on init and on language change
  let menuBar = this.menuBar
  menuBar.clearMenus()

  menuBar.addMenu(tr"File", @[
    MenuEntry(
      text: tr"Open",
      shortcut: shortcutDisplay("file.open"),
      action: proc() = this.openScript(),
    ),
    MenuEntry(
      text: tr"Save",
      shortcut: shortcutDisplay("file.save"),
      action: proc() = this.saveScript(),
    ),
    MenuEntry(
      text: tr"Save as",
      shortcut: shortcutDisplay("file.saveAs"),
      action: proc() = this.saveScriptAs(),
    ),
    menuSeparator(),
    MenuEntry(
      text: tr"Export PDF",
      disabled: proc(): bool = this.doc[] == nil,
      action: proc() = this.saveFileDialogOpened[] = true,
    ),
    menuSeparator(),
    MenuEntry(
      text: tr"Options",
      action: proc() = this.settingsOverlay.opened[] = true,
    ),
    MenuEntry(
      text: tr"Exit",
      action: proc() = close(this.parentWindow),
    ),
  ])

  menuBar.addMenu(tr"View", @[
    MenuEntry(
      text: tr"Code",
      checkable: true,
      checked: proc(): bool = config.codeEditorVisible[],
      action: proc() =
        this.codeEditor.visibility[] =
          (if config.codeEditorVisible[]: Visibility.collapsed else: Visibility.visible),
    ),
    MenuEntry(
      text: tr"Terminal",
      checkable: true,
      checked: proc(): bool = config.terminalVisible[],
      action: proc() =
        this.terminal.visibility[] =
          (if config.terminalVisible[]: Visibility.collapsed else: Visibility.visible),
    ),
    MenuEntry(
      text: tr"File tree",
      checkable: true,
      checked: proc(): bool = config.fileTreeVisible[],
      action: proc() = config.fileTreeVisible[] = not config.fileTreeVisible[],
    ),
  ])

  menuBar.addMenu(tr"Help", @[
    MenuEntry(
      text: tr"Key combinations",
      action: proc() = this.shortcutsDialogOpened[] = true,
    ),
    MenuEntry(
      text: tr"About",
      action: proc() = this.aboutDialogOpened[] = true,
    ),
  ])


method init*(this: TitleBar) =
  procCall this.super.init()

  this.makeLayout:
    - UiRect.new:
      this.fill(parent)
      color = binding: colorTheme[].bgTitleBar

    - MouseArea.new:
      this.fill(parent)

      on ClickEvent:
        if this.hovered[] and e.double:
          this.root.UiWindow.siwinWindow.maximized = not this.root.UiWindow.siwinWindow.maximized

    # --- Menubar ---

    - MenuBar.new as root.menuBar:
      this.left = parent.left + 8
      this.centerY = parent.center
      h = 30

    titleRegionStartX = binding: root.menuBar.x[] + root.menuBar.w[] + 10

    config.language.changed.connectTo root.eventHandler:
      root.rebuildMenuBar()

    root.rebuildMenuBar()


    # --- Export PDF dialog ---

    - ModalOverlay.new as pdfDialog:
      opened = binding: root.saveFileDialogOpened[]

      # same sync back as the shortcuts dialog (closing via escape or a click
      # outside of the content does not go through the flag)
      on pdfDialog.opened.changed:
        if not pdfDialog.opened[]:
          root.saveFileDialogOpened[] = false

      pdfDialog.content.w[] = 500
      pdfDialog.content.h[] = 400

      --- Uiobj.new:  # recreated on language change
        <--- {update}: config.language[]

        this.fill(parent.content)

        - UiRect.new:
          this.fill(parent)
          radius = 8
          color = binding: colorTheme[].bgOverlay

        - UiRectBorder.new:
          layer = after parent
          this.fill(parent)
          radius = 8
          borderWidth = 1
          color = binding: colorTheme[].borderOverlay

        if root.doc[] != nil:
          var currentExportDir = getCurrentDir()
          var currentExportItems = getDirItems(currentExportDir)

          - Label.new:
            left = parent.left + 14
            centerY = parent.top + 26
            text = tr"Save as PDF"
            fontSize = 18

          - Label.new:
            right = parent.right - 14
            centerY = parent.top + 26
            text = tr"Select location"
            color = binding: colorTheme[].fgMuted
            fontSize = 14

          - ListWidget.new as file_list:
              left = parent.left + 14
              right = parent.right - 14
              top = parent.top + 50
              bottom = parent.bottom - 100

              items = currentExportItems.mapIt(it.name)

          - Label.new as title_label:
            left = parent.left + 14
            centerY = file_list.bottom + 32
            text = tr"Name:"
            fontSize = 14

          - ComboBox.new as file_type:
            right = parent.right - 14
            centerY = file_list.bottom + 32
            w = 100
            otherTextCanBeEntered = false
            fitOptionsWidth = false
            options = @["Portable Document Format, *.pdf", "All Files"]
            selectedOption = 0

          file_list.itemSelected.connectTo file_list, kind:
            let idx = file_list.selectedItem[]
            if idx >= 0 and idx < currentExportItems.len:
              let item = currentExportItems[idx]
              if item.isDir:
                currentExportDir = item.path
                currentExportItems = getDirItems(currentExportDir)
                file_list.items[] = currentExportItems.mapIt(it.name)
                file_list.selectedItem[] = -1
              else:
                filename.text[] = item.name.changeFileExt("")

          - LineEdit.new as filename:
            right = file_type.left - 10
            left = title_label.right + 10
            centerY = file_list.bottom + 32
            text = "document" # Default name

          - Label.new as fullpath:
            left = parent.left + 14
            centerY = file_type.bottom + 32
            text = binding:
              root.currentFile[].parentDir / (filename.text[] & ".pdf")
            color = binding: colorTheme[].fgMuted
            fontSize = 14

          - Button.new as save_button:
            right = parent.right - 14
            centerY = file_type.bottom + 32
            text = tr"Save"
            accent = true

            on this.activated:
              if root.doc[] == nil or root.doc[][] == nil: return
              let r = PdfRenerer(doc: root.doc[])
              let targetPath = fullpath.text[]
              if targetPath != "":
                writePdf targetPath, r
                root.saveFileDialogOpened[] = false


          - Button.new as cancel_button:
            right = save_button.left - 10
            centerY = file_type.bottom + 32
            text = tr"Cancel"

            on this.activated:
              root.saveFileDialogOpened[] = false


    # --- Key combinations dialog ---

    - ModalOverlay.new as shortcutsDialog:
      opened = binding: root.shortcutsDialogOpened[]

      # the overlay closes itself (escape or a click outside of the content);
      # sync the flag back, otherwise it stays `true` and the next menu click
      # does not change it, so the binding above never opens the dialog again
      on shortcutsDialog.opened.changed:
        if not shortcutsDialog.opened[]:
          root.shortcutsDialogOpened[] = false

      shortcutsDialog.content.w[] = 520

      --- Uiobj.new:  # recreated on language change and on open, so the list
        # always shows the currently registered shortcuts
        <--- {update}: config.language[]; root.shortcutsDialogOpened[]

        let groups = shortcutGroups()
        let listH = groups.len.float32 * 30 + appShortcuts.len.float32 * 34
        parent.content.h[] = min(56 + listH + 14, 620).max(120)

        this.fill(parent.content)

        - UiRect.new:
          this.fill(parent)
          radius = 8
          color = binding: colorTheme[].bgOverlay

        - UiRectBorder.new:
          layer = after parent
          this.fill(parent)
          radius = 8
          borderWidth = 1
          color = binding: colorTheme[].borderOverlay

        - Label.new:
          left = parent.left + 14
          centerY = parent.top + 26
          text = tr"Key combinations"
          color = binding: colorTheme[].sText
          fontSize = 18

        - ScrollArea.new:
          left = parent.left + 14
          right = parent.right - 14
          top = parent.top + 56
          bottom = parent.bottom - 14

          - Uiobj.new:  # shortcut rows, height known in advance so scrolling works
            w = binding: parent.w[] - 10
            h = listH

            var rowY = 0'f32
            for group in groups:
              let category = group[0]
              let indexes = group[1]

              - UiText.new:
                left = parent.left
                top = parent.top + rowY
                text = categoryTitle(category)
                font = font_default.withSize(13)
                color = binding: colorTheme[].fgMuted

              rowY += 30

              for i in indexes:
                - UiText.new:
                  left = parent.left
                  centerY = parent.top + rowY + 12
                  text = shortcutTitle(appShortcuts[i].id)
                  font = font_default.withSize(14)
                  color = binding: colorTheme[].sText

                - UiText.new:
                  right = parent.right
                  centerY = parent.top + rowY + 12
                  text = sequencesDisplay(appShortcuts[i].keys)
                  font = font_default.withSize(14)
                  color = binding: colorTheme[].fgMuted

                rowY += 34


    # --- About dialog ---

    - ModalOverlay.new as aboutDialog:
      opened = binding: root.aboutDialogOpened[]

      # same sync back as the shortcuts dialog
      on aboutDialog.opened.changed:
        if not aboutDialog.opened[]:
          root.aboutDialogOpened[] = false

      aboutDialog.content.w[] = 480
      aboutDialog.content.h[] = 320

      --- Uiobj.new:  # recreated on language change
        <--- {update}: config.language[]

        this.fill(parent.content)

        - UiRect.new:
          this.fill(parent)
          radius = 8
          color = binding: colorTheme[].bgOverlay

        - UiRectBorder.new:
          layer = after parent
          this.fill(parent)
          radius = 8
          borderWidth = 1
          color = binding: colorTheme[].borderOverlay

        - Label.new:
          left = parent.left + 14
          centerY = parent.top + 26
          text = "cgsand"
          fontSize = 22
          color = binding: colorTheme[].sText

        - Label.new:
          right = parent.right - 14
          centerY = parent.top + 30
          text = appVersion
          fontSize = 14
          color = binding: colorTheme[].fgMuted

        - UiText.new:
          left = parent.left + 14
          centerY = parent.top + 74
          text = tr"Maintainers:"
          font = font_default.withSize(14)
          color = binding: colorTheme[].fgMuted

        - UiText.new:
          left = parent.left + 14
          centerY = parent.top + 100
          text = maintainers
          font = font_default.withSize(14)
          color = binding: colorTheme[].sText

        - UiText.new:
          left = parent.left + 14
          centerY = parent.top + 140
          text = tr"Libraries:"
          font = font_default.withSize(14)
          color = binding: colorTheme[].fgMuted

        - ScrollArea.new:
          left = parent.left + 14
          right = parent.right - 14
          top = parent.top + 166
          bottom = parent.bottom - 14

          - UiText.new:
            this.left = parent.left
            text = librariesInfo()
            font = font_default.withSize(12)
            color = binding: colorTheme[].sText

    # --- Window header buttons ---

    - TitleButton.new:  # Close
      this.fillVertical(parent)
      right = parent.right
      w = 60

      pressedColor = "#ca3e3eff".color
      hoveredColor = "#ff5959ff".color
      icon = binding: closeIcon(this.root.uiScale[])

      on this.activated:
        close this.parentWindow

    - TitleButton.new:  # Minimize
      this.fillVertical(parent)
      right = parent.right - 120
      w = 60

      pressedColor = "#3a5270ff".color # Deep pastel blue
      hoveredColor = "#5c7ca6ff".color # Soft denim blue
      icon = binding: minimizeIcon(this.root.uiScale[])

      on this.activated:
        this.parentWindow.minimized = true

    - TitleButton.new:  # Maximize
      this.fillVertical(parent)
      right = parent.right - 60
      w = 60

      pressedColor = "#3b6146ff".color # Muted pine
      hoveredColor = "#609470ff".color # Soft sage
      icon = binding: maximizeIcon(this.root.uiScale[])

      on this.activated:
        this.parentWindow.maximized = not this.parentWindow.maximized
