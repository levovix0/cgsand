import std/[os, algorithm, sequtils]
import pkg/[ecs]
import pkg/siwin/platforms/any/window
import pkg/sigui/[uibase, mouseArea, animations, layouts]
import pkg/toscel/[colors, comboBox, lineEdit, button, panel, label, listWidget]
import ../logic/[config, file_openers]
import ../logic/world_view/[pdf_renderer]
import ./icons

type
  BrowserItem = object
    name: string
    path: string
    isDir: bool

  FileBrowser = ref object of ComboBox
    items: seq[BrowserItem]
    currentPath: string
    fileOpener: Property[seq[FileOpener]]


  ToolBar* = ref object of Uiobj
    codeEditor*: Uiobj
    doc*: Property[ptr World]
    fileOpener*: Property[seq[FileOpener]]

    saveFileDialogOpened: Property[bool]

    fileBrowser: FileBrowser


  TitleButton = ref object of Uiobj
    pressedColor: Property[Color]
    hoveredColor: Property[Color]
    icon: Property[Image]
    activated: Event[void]

    mouseArea: MouseArea


registerComponent ToolBar
registerComponent TitleButton


proc `<`(a, b: BrowserItem): bool = a.name < b.name


proc windowControlsWidth*(this: ToolBar): float32 =
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
          this.image = binding: root.icon[]
      
      on this.mouseDownAndUpInside:
        root.activated.emit()


proc setCurrentPath(this: FileBrowser, dir: string) =
  this.currentPath = dir
  this.items = @[]
  
  if parentDir(dir) != dir:
    this.items.add(BrowserItem(name: "..", path: parentDir(dir.absolutePath).relativePath(getCurrentDir()), isDir: true))
    
  var folders: seq[BrowserItem] = @[]
  var files: seq[BrowserItem] = @[]
  
  for kind, path in walkDir(dir):
    if kind in {pcDir, pcLinkToDir}:
      folders.add(BrowserItem(name: path.splitPath.tail & "/", path: path, isDir: true))
    else:
      files.add(BrowserItem(name: path.splitPath.tail, path: path, isDir: false))
      
  this.items.add sorted folders
  this.items.add sorted files
  
  this.options[] = this.items.mapIt(it.name)


method init(this: FileBrowser) =
  procCall this.super.init()

  this.makeLayout:
    text = binding: config.currentScript[]
    w = 300
    fitOptionsWidth = false

    # Disconnecting valid binding and making it always true
    disconnect this.binding_valid
    this.valid[] = true

    on this.textEdited:
      root.fileOpener[].open(Location(path: this.text[]))
    
    proc fileChangeConfirmHandler(selectedOptionText: string) =
      var foundItem: BrowserItem
      for item in root.items:
        if item.name == selectedOptionText:
          foundItem = item
          break
      
      if foundItem.isDir:
        root.setCurrentPath(foundItem.path)
        this.selectedOption[] = -1
        this.dropdownOpened[] = true

        this.lineEdit.border.color[] = color_border_lineEdit
        this.text[] = root.currentPath
        
      else:
        # If file is selected - we write its path to the config
        let path = foundItem.path
        root.fileOpener[].open(Location(path: path.absolutePath))
        
        this.lineEdit.border.color[] = color_border_accent_lineEdit
        this.text[] = path

    on KeyEvent:
      if e.pressed:
        if this.lineEdit.textArea.active[] and not signal.handled:
          if e.key == Key.enter:
            fileChangeConfirmHandler(this.text[])
    
    this.optionSelected.connectTo this, kind:
      let selectedOptionText = this.options[][this.selectedOption[]]
      if kind == ClickSelection:
        fileChangeConfirmHandler(selectedOptionText)
      else:
        this.lineEdit.border.color[] = color_border_lineEdit


method init*(this: ToolBar) =
  procCall this.super.init()

  this.makeLayout:
    - UiRect.new:
      this.fill(parent)
      color = "#303030".color

    - MouseArea.new:
      this.fill(parent)

      this.clicked.connectTo this, e:
        if e.double:
          this.parentWindow.maximized = not this.parentWindow.maximized

    - Layout.row:
      centerY = parent.center
      left = parent.left + 10
      gap = 10

      - Button.new:
        text = tr"Code"
        accent = binding: root.codeEditor.visibility[] == visible

        on this.activated:
          root.codeEditor.visibility[] = (if root.codeEditor.visibility[] == visible: collapsed else: visible)

      - FileBrowser.new as root.fileBrowser:
        w = 300
        this.setCurrentPath("examples")
        fileOpener = binding: root.fileOpener[]

      - Button.new:
        text = tr"Export PDF"
        # enabled = binding: root.doc[] != nil

        on this.activated:
          
          root.saveFileDialogOpened[] = not root.saveFileDialogOpened[]
          

        --- UiObj.new:
          <--- UiObj.new: root.saveFileDialogOpened[]
          
          if root.saveFileDialogOpened[]:
            - Panel.new:
              x = 0
              y = 60
              w = 500
              h = 400

              - MouseArea.new:
                this.fill parent.border

              + this.background:
                color = "#303030".color

              - Label.new:
                left = parent.left
                centerY = parent.top + 2
                text = "Сохранить как PDF"
                fontSize = 18
              
              - Label.new:
                right = parent.right
                centerY = parent.top + 2
                text = "Выберите расположение"
                color = "#8c8c8c".color
                fontSize = 14
              
              - ListWidget.new as file_list:
                  left = parent.border.left + 1
                  right = parent.border.right - 1
                  top = parent.top + 24
                  bottom = parent.bottom - 100

                  items = root.fileBrowser.items.mapIt(it.name)

              - Label.new as title_label:
                left = parent.left
                centerY = file_list.bottom + 32
                text = "Имя:"
                fontSize = 14
              
              - ComboBox.new as file_type:
                right = parent.right
                centerY = file_list.bottom + 32
                w = 100
                otherTextCanBeEntered = false
                fitOptionsWidth = false
                options = @["Portable Document Format, *.pdf", "All Files"]

              - LineEdit.new as filename:
                right = file_type.left - 10
                left = title_label.right + 10
                centerY = file_list.bottom + 32

              - Label.new as fullpath:
                left = parent.left
                centerY = file_type.bottom + 32
                text = binding:
                  root.fileBrowser.currentPath & "/" & filename.text[] & ".pdf"
                color = "#8c8c8c".color
                fontSize = 14
              
              - Button.new as save_button:
                right = parent.right
                centerY = file_type.bottom + 32
                text = "Сохранить"
                accent = true

                on this.activated:
                  if root.doc[] == nil or root.doc[][] == nil: return
                  let r = PdfRenerer(doc: root.doc[])
                  # let filters = ["*.pdf".cstring, "*".cstring]
                  let filename = fullpath.text[]
                  if filename != "":
                    writePdf filename, r
                    root.saveFileDialogOpened[] = false

              
              - Button.new as cancel_button:
                right = save_button.left - 10
                centerY = file_type.bottom + 32
                text = "Отмена"

                on this.activated:
                  root.saveFileDialogOpened[] = false
    
    # --- Window header buttons ---

    - TitleButton.new:  # Close
      this.fillVertical(parent)
      right = parent.right
      w = 60

      pressedColor = "#ca3e3eff".color
      hoveredColor = "#ff5959ff".color
      icon = closeIcon()

      on this.activated:
        close this.parentWindow

    - TitleButton.new:  # Minimize
      this.fillVertical(parent)
      right = parent.right - 120
      w = 60

      pressedColor = "#3a5270ff".color # Deep pastel blue
      hoveredColor = "#5c7ca6ff".color # Soft denim blue
      icon = minimizeIcon()

      on this.activated:
        this.parentWindow.minimized = true

    - TitleButton.new:  # Maximize
      this.fillVertical(parent)
      right = parent.right - 60
      w = 60

      pressedColor = "#3b6146ff".color # Muted pine
      hoveredColor = "#609470ff".color # Soft sage
      icon = maximizeIcon()

      on this.activated:
        this.parentWindow.maximized = not this.parentWindow.maximized
