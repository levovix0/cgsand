import std/[os, algorithm, strutils, enumerate]
import pkg/sigui/[uibase, mouseArea, scrollArea, animations]
import pkg/toscel/[fonts, icons, transitions, colors]
import ../logic/[file_openers, configuration]

type
  BrowserItem = object
    name: string
    path: string
    isDir: bool

  SymbolKind = enum
    skCallable, skType, skConst, skVar

  Symbol = object
    name: string
    line: int      ## 1-based
    kind: SymbolKind
    depth: int     ## nesting level, displayed as indentation

  FileBrowser* = ref object of Uiobj
    rootPath*: Property[string]
      ## directory relative to which the breadcrumb path is displayed
    currentFile*: Property[string]
      ## file displayed in the breadcrumbs
    fileOpener* {.unprintable.}: Property[seq[FileOpener]]

    openedDir: Property[string]
      ## directory displayed in the dropdown, "" when the dropdown is closed
    showSymbols: Property[bool]
      ## whether the dropdown displays symbols of the current file
    dropdownX: Property[float32]
      ## local x coordinate of the dropdown left edge

registerComponent FileBrowser


const
  breadcrumbFontSize = 13
  breadcrumbIconSize = 13
  dropdownRowHeight = 24
  dropdownMaxHeight = 320
  symbolIndentStep = 12


proc `<`(a, b: BrowserItem): bool = a.name < b.name


proc getDirItems(dir: string): seq[BrowserItem] =
  ## items of `dir`: folders first, then files, sorted by name
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


proc breadcrumbItems(rootPath, currentFile: string): seq[BrowserItem] =
  ## segments of the breadcrumb bar: folders from `rootPath` down to the
  ## current file's directory, then the file itself (like in VSCode).
  ## when the file is not inside `rootPath`, only the file name is displayed
  result = @[]
  if currentFile.len == 0: return

  let file = currentFile.absolutePath.normalizedPath
  let root = rootPath.absolutePath.normalizedPath

  var dirs: seq[string]
  var reachedRoot = false
  var dir = file.splitFile.dir
  while dir.parentDir != dir:
    if dir == root:
      reachedRoot = true
      break
    dirs.add dir
    dir = dir.parentDir

  if reachedRoot:
    for i in countdown(dirs.high, 0):
      result.add BrowserItem(name: dirs[i].splitPath.tail, path: dirs[i], isDir: true)

  result.add BrowserItem(name: file.splitPath.tail, path: file, isDir: false)


proc fileIconColor(path: string, accent: bool): Color =
  case path.splitFile.ext
  of ".nim": (if accent: "#957347".color else: "#e2b96c".color)
  of ".md": "#6a9955".color
  of ".json", ".toml", ".cfg", ".yml": "#cbcb41".color
  else: "#808080".color

proc folderIconColor(path: string, accent: bool): Color =
  case path.splitPath.tail
  of "examples": "#57c76d".color
  else: "#808080".color


proc symbolColor(kind: SymbolKind): Color =
  case kind
  of skCallable: "#b180d7".color
  of skType: "#4ec9b0".color
  of skConst: "#b5cea8".color
  of skVar: "#569cd6".color


# ----- nim symbol parsing -----


proc declaredName(rest: string): string =
  ## name following a declaration keyword (`proc <name>(...)`, `proc \`+\`(...)`),
  ## "" when there is no name on this line (anonymous declaration or section keyword)
  var i = 0
  while i < rest.len and rest[i] == ' ': inc i
  if i >= rest.len: return ""

  if rest[i] == '`':
    let ending = rest.find('`', i + 1)
    if ending == -1: return ""
    return rest[i + 1 ..< ending]

  let start = i
  while i < rest.len and rest[i] in IdentChars: inc i
  if i == start: return ""
  rest[start ..< i]


proc sectionEntryName(content: string, requireAssign: bool): string =
  ## `Foo*[T] {.pragmas.} = object` → "Foo" — an entry of a type/var/let/const
  ## section, "" when the line does not look like a section entry
  var i = 0
  while i < content.len and content[i] in IdentStartChars: inc i
  if i == 0: return ""
  let nameEnd = i

  if i < content.len and content[i] == '*': inc i

  if i < content.len and content[i] == '[':  # generic parameters
    var nesting = 0
    while i < content.len:
      case content[i]
      of '[': inc nesting
      of ']': dec nesting
      else: discard
      inc i
      if nesting == 0: break

  if i < content.len and content[i] == '{':  # pragmas
    while i < content.len and content[i] != '}': inc i
    if i < content.len: inc i

  while i < content.len and content[i] == ' ': inc i
  if i >= content.len: return ""

  let accepted = (if requireAssign: {'='} else: {'=', ':'})
  if content[i] in accepted: content[0 ..< nameEnd] else: ""


proc parseSymbols(text: string): seq[Symbol] =
  ## top-level declarations of a nim file with indentation-based nesting,
  ## enough for navigation (does not understand all of nim syntax)

  type
    StackEntry = tuple
      indent: int
      visible: bool  ## whether it is a symbol (affects the depth of nested symbols)

  var symbols: seq[Symbol]
  var stack: seq[StackEntry]

  var
    inMultilineString = false
    sectionIndent = -1       ## indent of the open type/var/let/const section, -1 when none
    sectionEntryIndent = -1  ## indent of the entries of the open section
    sectionKind = skType

  proc popDeeperOrEqual(indent: int) =
    while stack.len > 0 and stack[^1].indent >= indent:
      discard stack.pop()

  proc visibleDepth(): int =
    for entry in stack:
      if entry.visible: inc result

  proc addSymbol(name: string, line: int, kind: SymbolKind, indent: int) =
    symbols.add Symbol(name: name, line: line, kind: kind, depth: visibleDepth())
    stack.add (indent, true)

  for lineI, line in enumerate(text.splitLines):
    # multiline strings """..."""
    var tripleQuotes = 0
    var searchFrom = 0
    while true:
      let found = line.find("\"\"\"", searchFrom)
      if found == -1: break
      inc tripleQuotes
      searchFrom = found + 3
    if tripleQuotes mod 2 == 1:
      inMultilineString = not inMultilineString
    if inMultilineString: continue

    var indent = 0
    while indent < line.len and line[indent] in {' ', '\t'}: inc indent
    let content = line[indent .. ^1]

    if content.len == 0: continue
    if content[0] == '#': continue

    if sectionIndent >= 0 and indent <= sectionIndent:
      sectionIndent = -1
      sectionEntryIndent = -1

    let spacePos = content.find(' ')
    let firstWord = if spacePos == -1: content else: content[0 ..< spacePos]

    case firstWord
    of "proc", "func", "method", "iterator", "macro", "template", "converter":
      let name = declaredName(if spacePos == -1: "" else: content[spacePos + 1 .. ^1])
      if name.len > 0:
        popDeeperOrEqual(indent)
        addSymbol(name, lineI + 1, skCallable, indent)

    of "type":
      let name = declaredName(if spacePos == -1: "" else: content[spacePos + 1 .. ^1])
      popDeeperOrEqual(indent)
      if name.len > 0:
        addSymbol(name, lineI + 1, skType, indent)
      else:  # `type` section
        sectionKind = skType
        sectionIndent = indent
        sectionEntryIndent = -1
        stack.add (indent, false)

    of "const":
      let name = declaredName(if spacePos == -1: "" else: content[spacePos + 1 .. ^1])
      popDeeperOrEqual(indent)
      if name.len > 0 and indent == 0:
        addSymbol(name, lineI + 1, skConst, indent)
      elif name.len == 0:  # `const` section
        sectionKind = skConst
        sectionIndent = indent
        sectionEntryIndent = -1
        stack.add (indent, false)

    of "var", "let":
      let name = declaredName(if spacePos == -1: "" else: content[spacePos + 1 .. ^1])
      popDeeperOrEqual(indent)
      if name.len > 0 and indent == 0:
        addSymbol(name, lineI + 1, skVar, indent)
      elif name.len == 0:  # `var`/`let` section
        sectionKind = skVar
        sectionIndent = indent
        sectionEntryIndent = -1
        stack.add (indent, false)

    else:
      # entries of the open section
      if sectionIndent >= 0 and indent > sectionIndent:
        if sectionEntryIndent == -1:
          sectionEntryIndent = indent
        if indent == sectionEntryIndent:
          let name = sectionEntryName(content, sectionKind == skType)
          if name.len > 0:
            popDeeperOrEqual(indent)
            addSymbol(name, lineI + 1, sectionKind, indent)

      elif content.endsWith(":"):
        # block statement (if/when/for/...) — nest symbols after it, but don't show it
        popDeeperOrEqual(indent)
        stack.add (indent, false)

  result = symbols


template registerDropdownAutoClose() {.dirty.} =
  ## closes the dropdown when clicking outside of it, or on escape
  this.gotSignal.connectTo this, signal:
    if signal of WindowEvent and signal.WindowEvent.event of KeyEvent:
      let e = (ref KeyEvent)(signal.WindowEvent.event)
      if e.pressed and e.key == Key.escape:
        root.closeDropdowns()

    if signal of WindowEvent and signal.WindowEvent.event of MouseButtonEvent:
      let e = (ref MouseButtonEvent)(signal.WindowEvent.event)
      if e.pressed:
        let pos = this.root.mouseState.pos - this.globalXy
        if pos.x notin 0'f32..this.w[] or pos.y notin 0'f32..this.h[]:
          root.closeDropdowns()


proc closeDropdowns(this: FileBrowser) =
  this.openedDir[] = ""
  this.showSymbols[] = false


method init(this: FileBrowser) =
  procCall this.super.init()

  when defined(debugDropdown):
    this.openedDir[] = getCurrentDir() / "examples"
  when defined(debugSymbols):
    this.showSymbols[] = true

  this.makeLayout:
    - UiRect.new:
      this.fill(parent)
      color = colorTheme.bgTextArea

    --- ScrollArea.new:  # breadcrumbs row, recreated when the current file changes
      <--- {update}: root.rootPath[]; root.currentFile[]

      this.fill(parent)

      if root.currentFile[].len > 0:
        let font = font_default.withSize(breadcrumbFontSize)
        var cursorX = 6'f32

        for segmentI, segment in breadcrumbItems(root.rootPath[], root.currentFile[]):
          let item = segment

          if segmentI > 0:
            let sepX = cursorX
            - UiText.new:
              x = sepX
              centerY = parent.center
              text = "/"
              font = font
              color = "#6e6e6e".color
            cursorX += font.layoutBounds("/").x + 8

          let segX = cursorX
          let iconW = (if item.isDir: 0'f32 else: breadcrumbIconSize.float32 + 4)
          let nameW = font.layoutBounds(item.name).x
          let segW = 4 * 2 + iconW + nameW

          - MouseArea.new:
            x = segX
            this.fillVertical(parent)
            w = segW
            cursor = pointingHand

            - UiRect.new:
              this.fill(parent)
              radius = 4
              color = binding:
                if parent.hovered[]: "#ffffff14".color
                else: "#00000000".color
              addTransition this.color

            if not item.isDir:
              - UiSvgImage.new:
                x = 4
                centerY = parent.center
                w = breadcrumbIconSize
                h = breadcrumbIconSize
                image = "file".icon.svg
                color = fileIconColor(item.path, false)

            - UiText.new:
              x = 4 + iconW
              centerY = parent.center
              text = item.name
              font = font
              color = binding:
                if parent.hovered[]: "#ffffff".color
                else:
                  if item.isDir: "#b8b8b8".color
                  else: "#cfcfcf".color
              addTransition this.color

            on this.clicked:
              # a folder opens the catalog containing it (to switch folders),
              # the catalog of the file's folder is what the file click shows
              root.dropdownX[] = segX
              root.showSymbols[] = false
              root.openedDir[] = (if item.isDir: item.path.parentDir else: item.path.splitFile.dir)

          cursorX += segW + 4

        let moreX = cursorX
        - MouseArea.new:  # opens the list of symbols of the current file
          x = moreX
          this.fillVertical(parent)
          w = font.layoutBounds(tr"go to symbol...").x + 10
          cursor = pointingHand

          - UiRect.new:
            this.fill(parent)
            radius = 4
            color = binding:
              if parent.hovered[]: "#ffffff14".color
              else: "#00000000".color
            addTransition this.color

          - UiText.new:
            centerX = parent.center
            centerY = parent.center
            text = tr"go to symbol..."
            font = font
            color = binding:
              if parent.hovered[]: "#ffffff".color
              else: "#808080".color
            addTransition this.color

          on this.clicked:
            root.dropdownX[] = moreX
            root.openedDir[] = ""
            root.showSymbols[] = true

    --- Uiobj.new:  # dropdown with the contents of openedDir, recreated when it changes
      <--- {update}: root.openedDir[]

      if root.openedDir[].len > 0 and root.openedDir[].dirExists:
        var items: seq[BrowserItem]
        try: items = getDirItems(root.openedDir[])
        except CatchableError: items = @[]

        let font = font_default.withSize(breadcrumbFontSize)
        let pad = 8'f32
        let rowH = dropdownRowHeight.float32
        let iconW = breadcrumbIconSize.float32

        var maxNameW = 0'f32
        for item in items:
          (maxNameW) = max(maxNameW, font.layoutBounds(item.name).x)

        this.w[] = pad * 2 + iconW + 6 + maxNameW
        this.x[] = root.dropdownX[].min((parent.w[] - this.w[]).max(0))
        this.y[] = parent.h[]
        this.h[] = min(items.len.float32 * rowH, dropdownMaxHeight)

        registerDropdownAutoClose()

        - UiRect.new:
          this.fill(parent)
          radius = 5
          color = "#252526".color

        - ScrollArea.new:
          this.fill(parent)
          color = "#505050".color
          radius = 5

          for itemI, item in items:
            let it = item
            let rowY = itemI.float32 * rowH
            - MouseArea.new:
              x = 0
              y = rowY
              w = parent.w[]
              h = rowH
              cursor = pointingHand
              let accent = root.currentFile[].absolutePath.startsWith(it.path)

              - UiRect.new:
                this.fill(parent)
                color = binding:
                  if accent:
                    if parent.pressed[]: color_bg_accent_button_pressed
                    elif parent.hovered[]: color_bg_accent_button_hovered
                    else: color_bg_accent_button
                  else:
                    if parent.pressed[]: color_bg_button_pressed
                    elif parent.hovered[]: color_bg_button_hovered
                    else: color_bg_button
                addTransition this.color

              - UiSvgImage.new:
                x = pad
                centerY = parent.center
                w = iconW
                h = iconW
                image = (if it.isDir: "folder".icon.svg else: "file".icon.svg)
                color = (if it.isDir: folderIconColor(it.path, accent) else: fileIconColor(it.path, accent))

              - UiText.new:
                x = pad + iconW + 6
                centerY = parent.center
                text = it.name
                font = font
                color = binding:
                  if accent: color_fg_accent
                  elif parent.pressed[] or parent.hovered[]: color_fg_active
                  else: color_fg
                addTransition this.color

              on this.clicked:
                if it.isDir:
                  root.openedDir[] = it.path  # switch the folder displayed in the list
                elif it.path != root.currentFile[].absolutePath:
                  root.fileOpener[].open(Location(path: it.path.absolutePath))
                  root.closeDropdowns()

        - UiRectBorder.new:
          layer = after parent
          this.fill(parent)
          radius = 4
          borderWidth = 1
          color = "#454545".color

    --- Uiobj.new:  # dropdown with the symbols of the current file
      <--- {update}: root.showSymbols[]; root.currentFile[]

      if root.showSymbols[] and root.currentFile[].len > 0:
        var symbols: seq[Symbol]
        try: symbols = parseSymbols(readFile(root.currentFile[]))
        except CatchableError: symbols = @[]

        let font = font_default.withSize(breadcrumbFontSize)
        let pad = 8'f32
        let rowH = dropdownRowHeight.float32
        let dotSize = 8'f32

        var maxNameW = 0'f32
        for sym in symbols:
          (maxNameW) = max(maxNameW,
            sym.depth.float32 * symbolIndentStep + dotSize + 6 + font.layoutBounds(sym.name).x)

        this.w[] = pad * 2 + dotSize + 6 + maxNameW
        this.x[] = root.dropdownX[].min((parent.w[] - this.w[]).max(0))
        this.y[] = parent.h[]
        this.h[] = min(symbols.len.float32 * rowH, dropdownMaxHeight)

        registerDropdownAutoClose()

        - UiRect.new:
          this.fill(parent)
          radius = 5
          color = "#252526".color

        - ScrollArea.new:
          this.fill(parent)
          color = "#505050".color
          radius = 5

          for symI, sym in symbols:
            let s = sym
            let rowY = symI.float32 * rowH
            let dotX = pad + s.depth.float32 * symbolIndentStep
            - MouseArea.new:
              x = 0
              y = rowY
              w = parent.w[]
              h = rowH
              cursor = pointingHand

              - UiRect.new:
                this.fill(parent)
                color = binding:
                  if parent.pressed[]: color_bg_button_pressed
                  elif parent.hovered[]: color_bg_button_hovered
                  else: color_bg_button
                addTransition this.color

              - UiRect.new:
                x = dotX
                centerY = parent.center
                w = dotSize
                h = dotSize
                radius = 3
                color = symbolColor(s.kind)

              - UiText.new:
                x = dotX + dotSize + 6
                centerY = parent.center
                text = s.name
                font = font
                color = binding:
                  if parent.pressed[] or parent.hovered[]: color_fg_active
                  else: color_fg
                addTransition this.color

              on this.clicked:
                root.fileOpener[].open(Location(
                  path: root.currentFile[].absolutePath,
                  line: s.line,
                  col: 1,
                ))
                root.closeDropdowns()

        - UiRectBorder.new:
          layer = after parent
          this.fill(parent)
          radius = 4
          borderWidth = 1
          color = "#454545".color
