import pkg/[ecs]
import pkg/siwin/platforms/any/window
import pkg/sigui/[uibase, mouseArea, animations, layouts]
import pkg/toscel/[colors, comboBox, lineEdit, button]
import ../logic/[config, pdf_renderer]
import std/[os]
import icons

const startDirName = "examples"

type
  BrowserItem = object
    display: string # Displayed name
    path: string    # Real path to object
    isDir: bool     # Is this folder or not

  ToolBar* = ref object of Uiobj
    codeEditor*: Uiobj
    doc*: Property[ptr World]
    browserItems: seq[BrowserItem] # Component state for hidden logic
    rootPath: string               # Hardcoded root reference path
    currentPath: string            # Current directory path that changes on click

  TitleButton = ref object of Uiobj
    pressedColor: Property[Color]
    hoveredColor: Property[Color]
    icon: Property[Image]
    activated: Event[void]

registerComponent ToolBar
registerComponent TitleButton

proc updateFileBrowser(this: ToolBar, dir: string): seq[string] =
  result = @[]
  this.browserItems = @[] # Clear old data
  
  if parentDir(dir) != dir:
    this.browserItems.add(BrowserItem(display: "..", path: parentDir(dir), isDir: true))
    
  # Separate lists to keep folders on top
  var folders: seq[BrowserItem] = @[]
  var files: seq[BrowserItem] = @[]
  
  # Read disk and check types using system tools
  for kind, path in walkDir(dir, relative = true):
    let fullPath = dir / path
    if kind in {pcDir, pcLinkToDir}:
      folders.add(BrowserItem(display: path & "/", path: fullPath, isDir: true))
    else:
      files.add(BrowserItem(display: path, path: fullPath, isDir: false))
      
  # Combine everything into the internal state array
  this.browserItems.add(folders)
  this.browserItems.add(files)
  
  # Return an array of strings for the ComboBox
  for item in this.browserItems:
    result.add(item.display)

proc getCurrentRelativePath(this: ToolBar): string =
  if this.currentPath == this.rootPath:
    return startDirName
  else:
    # Returns a path like: examples/subfolder1/subfolder2
    return startDirName / relativePath(this.currentPath, this.rootPath)

proc windowControlsWidth*(this: ToolBar): float32 =
  180

method init(this: TitleButton) =
  procCall this.super.init()

  this.makeLayout:
    - MouseArea.new as mouse:
      this.fill(parent)

      - UiRect.new:
        this.fill(parent)

        color = binding:
          if mouse.pressed[]: root.pressedColor[]
          elif mouse.hovered[]: root.hoveredColor[]
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

method init*(this: ToolBar) =
  procCall this.super.init()

  # Initialize state fields
  this.rootPath = absolutePath(startDirName)
  this.currentPath = this.rootPath
  this.browserItems = @[]

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

      - ComboBox.new:
        text = binding: config.currentScript[]
        this.options[] = root.updateFileBrowser(root.currentPath)
        w = 300
        fitOptionsWidth = false

        # Disconnecting valid binding and making it always true
        disconnect this.binding_valid
        this.valid[] = true

        on this.textEdited:
          config.currentScript[] = this.text[]
        
        proc fileChangeConfirmHandler(selectedOptionText: string) =
          var foundItem: BrowserItem
          for item in root.browserItems:
            if item.display == selectedOptionText:
              foundItem = item
              break
          
          if foundItem.isDir:
            # Changing directory
            root.currentPath = foundItem.path
            
            # Updating file list for new folder
            this.options[] = root.updateFileBrowser(root.currentPath)
            this.selectedOption[] = -1
            this.dropdownOpened[] = true

            # Changing accent color to default (folder)
            this.lineEdit.border.color[] = color_border_lineEdit
            
            # Display new relative path in ComboBox text field.
            this.text[] = root.getCurrentRelativePath()
          else:
            # If file is selected - we write its path to the config
            config.currentScript[] = startDirName / relativePath(foundItem.path, root.rootPath)
            
            # Changing border color to accent (valid file)
            this.lineEdit.border.color[] = color_border_accent_lineEdit

            # Optional: You can leave the file name in the text field,
            # so the user can see which file is currently selected
            this.text[] = startDirName / relativePath(foundItem.path, root.rootPath)

        this.onSignal.connectTo this, signal:
          if signal of WindowEvent and signal.WindowEvent.event of KeyEvent:
            let e = (ref KeyEvent)(signal.WindowEvent.event)
            if e.pressed:
              if this.lineEdit.textArea.active[] and not signal.WindowEvent.handled:
                if e.key == Key.enter:
                  fileChangeConfirmHandler(this.text[])
        this.optionSelected.connectTo this, e:
          let selectedOptionText = this.options[][this.selectedOption[]]
          if e == ClickSelection:
            fileChangeConfirmHandler(selectedOptionText)
          else:
            this.lineEdit.border.color[] = color_border_lineEdit

      - Button.new:
        text = tr"Export PDF"
        enabled = binding: root.doc[] != nil

        on this.activated:
          if root.doc[] == nil: return
          let r = PdfRenerer(doc: root.doc[][])
          let filters = ["*.pdf".cstring, "*".cstring]
          let filename = "out.pdf"
          if filename != "":
            writePdf filename, r

    # --- Window header buttons ---

    - TitleButton.new: # Close
      this.fillVertical(parent)
      right = parent.right
      w = 60

      pressedColor = "#ca3e3eff".color
      hoveredColor = "#ff5959ff".color
      icon = closeIcon()

      on this.activated:
        close this.parentWindow

    - TitleButton.new: # Minimize 
      this.fillVertical(parent)
      right = parent.right - 120
      w = 60

      pressedColor = "#3a5270ff".color # Deep pastel blue
      hoveredColor = "#5c7ca6ff".color # Soft denim blue
      icon = minimizeIcon()

      on this.activated:
        this.parentWindow.minimized = true

    - TitleButton.new: # Maximize 
      this.fillVertical(parent)
      right = parent.right - 60
      w = 60

      pressedColor = "#3b6146ff".color # Muted pine
      hoveredColor = "#609470ff".color # Soft sage
      icon = maximizeIcon()

      on this.activated:
        this.parentWindow.maximized = not this.parentWindow.maximized