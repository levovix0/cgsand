## file tree panel like in VSCode: shows the directory tree of the workspace
## root, folders are expanded/collapsed by click, files are opened by click

import std/[os, algorithm]
import pkg/sigui/[uibase, mouseArea, scrollArea, animations]
import pkg/toscel/[fonts, icons, transitions, colors, label]
import ../logic/[configuration, file_openers]
import ./breadcrumbs

type
  TreeEntry = object
    name: string
    path: string
    isDir: bool
    depth: int
    expanded: bool

  FileTree* = ref object of Uiobj
    rootPath*: Property[string]
      ## directory the tree displays
    currentFile*: Property[string]
      ## file highlighted as opened
    fileOpener* {.unprintable.}: Property[seq[FileOpener]]

    expandedDirs: Property[seq[string]]

registerComponent FileTree


const
  treeFontSize = 13'f32
  treeIconSize = 13'f32
  treeRowHeight = 24'f32
  treeIndentStep = 16'f32
    # indent per nesting level; files reserve the same space for the chevron
    # as folders do, so icons of different rows stay aligned
  treeChevronSpace = 4 + treeIconSize + 4


proc `<`(a, b: TreeEntry): bool = a.name < b.name


proc visibleEntries(dir: string, depth: int, expandedDirs: seq[string], result: var seq[TreeEntry]) =
  ## entries of `dir`, descending into each expanded folder right after
  ## the folder itself, so children appear directly under it
  var folders: seq[TreeEntry] = @[]
  var files: seq[TreeEntry] = @[]

  for kind, path in walkDir(dir):
    # the default `expandedDirs` contains plain dir names, clicks add full paths
    let expanded = (path in expandedDirs or path.splitPath.tail in expandedDirs)
    if kind in {pcDir, pcLinkToDir}:
      folders.add(TreeEntry(name: path.splitPath.tail, path: path, isDir: true, depth: depth,
        expanded: expanded))
    else:
      files.add(TreeEntry(name: path.splitPath.tail, path: path, isDir: false, depth: depth))

  for folder in sorted folders:
    result.add folder
    if folder.expanded:
      visibleEntries(folder.path, depth + 1, expandedDirs, result)

  result.add sorted files


method init(this: FileTree) =
  procCall this.super.init()

  # default: show the examples folder expanded
  this.expandedDirs = @["examples"].property

  this.makeLayout:
    - UiRect.new:
      this.fill(parent)
      color = binding: colorTheme[].bgExplorer

    - Label.new:
      left = parent.left + 10
      centerY = parent.top + 16
      text = tr"Files"
      fontSize = 13
      color = binding: colorTheme[].fgMuted

    --- ScrollArea.new:  # the tree, recreated when the root, opened file, folders or language change
      <--- {update}: root.rootPath[]; root.currentFile[]; root.expandedDirs[]; config.language[]

      left = parent.left
      right = parent.right
      top = parent.top + 32
      bottom = parent.bottom

      var entries: seq[TreeEntry]
      try:
        visibleEntries(root.rootPath[], 0, root.expandedDirs[], entries)
      except CatchableError:
        discard

      var rowY = 0'f32
      for entryI, entry in entries:
        var entry = entry
        let entryPath = entry.path.absolutePath
        let isCurrent = root.currentFile[].absolutePath == entryPath
        let indent = entry.depth.float32 * treeIndentStep

        - MouseArea.new:
          x = entry.depth.float32 * treeIndentStep
          y = rowY
          this.fillHorizontal(parent)
          h = treeRowHeight
          cursor = pointingHand

          - UiRect.new:
            this.fill(parent)
            color = binding:
              if isCurrent:
                if parent.pressed[]: color_bg_accent_button_pressed[]
                elif parent.hovered[]: color_bg_accent_button_hovered[]
                else: color_bg_accent_button[]
              else:
                if parent.pressed[]: color_bg_button_pressed[]
                elif parent.hovered[]: color_bg_button_hovered[]
                else: color_bg_button[]

            addTransition this.color

          if entry.isDir:
            - UiSvgImage.new:
              x = 4 + indent
              centerY = parent.center
              w = treeIconSize
              h = treeIconSize
              image = (if entry.expanded: "arrow-down".icon.svg else: "arrow-right".icon.svg)
              color = binding: colorTheme[].fgMuted

          - UiSvgImage.new:
            x = treeChevronSpace + indent
            centerY = parent.center
            w = treeIconSize
            h = treeIconSize
            image = (if entry.isDir: "folder".icon.svg else: "file".icon.svg)
            color = (if entry.isDir: folderIconColor(entry.path, false) else: fileIconColor(entry.path, false))

          - UiText.new:
            x = treeChevronSpace + treeIconSize + 6 + indent
            centerY = parent.center
            text = entry.name
            font = font_default.withSize(treeFontSize)
            color = binding:
              if isCurrent: color_fg_accent[]
              elif parent.pressed[] or parent.hovered[]: color_fg_active[]
              else: color_fg[]

            addTransition this.color

          on this.clicked:
            if entry.isDir:
              var dirs = root.expandedDirs[]
              if entry.path in dirs:
                dirs.delete(dirs.find(entry.path))
              else:
                dirs.add entry.path
              root.expandedDirs[] = dirs
            else:
              root.fileOpener[].open(Location(path: entry.path.absolutePath))

        rowY += treeRowHeight
