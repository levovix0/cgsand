import pkg/[ecs]
import pkg/siwin/platforms/any/window
import pkg/sigui/[uibase, mouseArea, animations, layouts]
import pkg/toscel/[comboBox, lineEdit, button]
import ../logic/[config, pdf_renderer]
import std/[os]
import icons

type
  ToolBar* = ref object of Uiobj
    codeEditor*: Uiobj
    doc*: Property[ptr World]

registerComponent ToolBar

type
  BrowserItem = object
    display: string # То, что видит юзер
    path: string    # Реальный путь к объекту
    isDir: bool     # Флаг: папка это или нет

var browserItems: seq[BrowserItem] = @[] # Здесь храним всю скрытую логику

const startDirName = "examples"
let rootPath = absolutePath(startDirName) # Жесткая точка отсчета
var currentPath = rootPath # Переменная текущего положения, которая меняется при кликах


proc updateFileBrowser(dir: string): seq[string] =
  result = @[]
  browserItems = @[] # Очищаем старые данные
  
  if parentDir(dir) != dir:
    browserItems.add(BrowserItem(display: "..", path: parentDir(dir), isDir: true))
    
  # Списки для разделения (чтобы папки всегда были сверху)
  var folders: seq[BrowserItem] = @[]
  var files: seq[BrowserItem] = @[]
  
  # Читаем диск и проверяем типы системными средствами (kind)
  for kind, path in walkDir(dir, relative = true):
    let fullPath = dir / path
    if kind in {pcDir, pcLinkToDir}:
      folders.add(BrowserItem(display: path & "/", path: fullPath, isDir: true))
    else:
      files.add(BrowserItem(display: path, path: fullPath, isDir: false))
      
  # Собираем всё воедино в наш скрытый массив состояний
  browserItems.add(folders)
  browserItems.add(files)
  
  # Возвращаем массив строк для ComboBox
  for item in browserItems:
    result.add(item.display)

proc getCurrentRelativePath(): string =
  if currentPath == rootPath:
    return startDirName
  else:
    # Возвращает путь вида: examples/subfolder1/subfolder2
    return startDirName / relativePath(currentPath, rootPath)


proc windowControlsWidth*(this: ToolBar): float32 =
  180



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
    

    - MouseArea.new as mouse: # Закрыть
      this.fillVertical(parent)
      right = parent.right
      w = 60

      - UiRect.new:
        this.fill(parent)

        color = binding:
          if mouse.pressed[]: "#ca3e3eff".color
          elif mouse.hovered[]: "#ff5959ff".color
          else: "#00000000".color
      
        - this.color.transition(0.1's):
          easing = outSquareEasing

        - UiImage.new:
          this.centerIn(parent)
          this.w[] = 32
          this.h[] = 32
          this.image = closeIcon()
      
      on this.mouseDownAndUpInside:
        close this.parentWindow
    

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
        this.options[] = updateFileBrowser(currentPath)
        w = 300

        on this.textEdited:
          config.currentScript[] = this.text[]
        
        on this.optionSelected:
          let selectedOptionText = this.options[][this.selectedOption[]]
          
          var foundItem: BrowserItem
          for item in browserItems:
            if item.display == selectedOptionText:
              foundItem = item
              break
          
          if foundItem.isDir:
            # Смена директории
            currentPath = foundItem.path 
            
            # Обновляем список файлов для новой папки
            this.options[] = updateFileBrowser(currentPath)
            this.w[] = 300
            this.selectedOption[] = -1
            this.dropdownOpened[] = true
            
            # Выводим новый относительный путь в текстовое поле ComboBox
            this.text[] = getCurrentRelativePath() 
            
          else:
            # Выбран файл — записываем его путь в конфиг
            config.currentScript[] = startDirName / relativePath(foundItem.path, rootPath) #foundItem.path
            
            # Опционально: можно оставить имя файла в текстовом поле, 
            # чтобы пользователь видел, какой именно файл сейчас выбран
            this.text[] = startDirName / relativePath(foundItem.path, rootPath)

      - Button.new:
        text = tr"Export PDF"
        enabled = binding: root.doc[] != nil

        on this.activated:
          if root.doc[] == nil: return
          let r = PdfRenerer(doc: root.doc[])
          let filters = ["*.pdf".cstring, "*".cstring]
          let filename = "out.pdf"
          if filename != "":
            writePdf filename, r


    - MouseArea.new as mouse1: # Свернуть
      this.fillVertical(parent)
      right = parent.right-120
      w = 60

      - UiRect.new:
        this.fill(parent)

        color = binding:
          if mouse1.pressed[]: "#3a5270ff".color # Глубокий пастельный синий
          elif mouse1.hovered[]: "#5c7ca6ff".color # Мягкий джинсово-синий
          else: "#00000000".color

        - this.color.transition(0.1's):
          easing = outSquareEasing

        - UiImage.new:
          this.centerIn(parent)
          this.w[] = 32
          this.h[] = 32
          this.image = minimizeIcon()
      
      on this.mouseDownAndUpInside:
        this.parentWindow.minimized = true


    - MouseArea.new as mouse2: # Развернуть
      this.fillVertical(parent)
      right = parent.right-60
      w = 60

      - UiRect.new:
        this.fill(parent)

        color = binding:
          if mouse2.pressed[]: "#3b6146ff".color # Приглушенный хвойный
          elif mouse2.hovered[]: "#609470ff".color # Мягкий шалфейный
          else: "#00000000".color

        - this.color.transition(0.1's):
          easing = outSquareEasing
      
        - UiImage.new:
          this.centerIn(parent)
          this.w[] = 32
          this.h[] = 32
          this.image = maximizeIcon()
      on this.mouseDownAndUpInside:
        this.parentWindow.maximized = not this.parentWindow.maximized

