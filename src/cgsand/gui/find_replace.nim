import std/[math, unicode]
import pkg/toscel/[focus, lineEdit, button]
import pkg/sigui/[uibase, mouseArea]
import ../logic/[configuration, code_editor, shortcuts]
import ./[code_editor]


type
  FindReplacePanel* = ref object of MouseArea
    ## a VS Code-like find & replace panel floating at the top right corner of
    ## the code editor. Created by connectFindReplace, shown and hidden by
    ## toggling editor.content.search.active, reacts to the editor
    ## find/replace shortcuts.
    editor: CodeEditor

    replaceRowVisible*: Property[bool]

    findEdit*: LineEdit
    replaceEdit*: LineEdit


const
  PanelPad = 6'f32
  PanelGap = 4'f32  ## vertical spacing between rows and around fields
  PanelBtnGap = 6'f32  ## spacing between buttons of the same group
  PanelGroupGap = 12'f32  ## spacing between button groups (toggle/field/chips/arrows)
  PanelRowH = 32'f32  ## LineEdit default height
  PanelStatusH = 18'f32
  PanelMaxW = 420'f32
  PanelFieldMinW = 100'f32


registerComponent FindReplacePanel


proc selectedQuery(editor: CodeEditor): string =
  ## single-line selection of the editor to prefill the find field with
  let arr = editor.content.arrangement
  if arr == nil or arr.cursors.len == 0: return ""
  let sel = arr.selectedText(0)
  if '\n' in sel or '\r' in sel: return ""
  result = sel


proc searchOptionsOf(content: CodeEditorContent): SearchOptions =
  searchOptions(
    content.search.caseSensitive[],
    content.search.wholeWord[],
    content.search.regex[],
  )


proc gotoCurrentMatch(this: FindReplacePanel) =
  ## selects the current search match (editor cursors collapse to it) and
  ## scrolls the editor to it; does nothing when there is no current match
  let content = this.editor.content
  if not content.search.active[] or content.arrangement == nil: return
  if content.search.currentI < 0 or content.search.currentI >= content.search.matches.len: return
  let m = content.search.matches[content.search.currentI]
  content.arrangement.cursors.setLen(1)
  content.arrangement.setSelection(0, m.anchorLine, m.anchorCol, m.line, m.col)
  this.editor.scrollToLine(m.anchorLine)
  redraw(content)


proc performSearch*(this: FindReplacePanel) =
  ## recomputes matches after the query or the search options changed and
  ## jumps to the match nearest to the cursor
  let content = this.editor.content
  content.recomputeSearch()
  this.gotoCurrentMatch()
  redraw(content)


proc gotoMatch*(this: FindReplacePanel, backwards: bool) =
  ## selects the next (or previous, wrapping at the ends) match
  let content = this.editor.content
  let matches = content.search.matches
  if not content.search.active[] or matches.len == 0: return
  if content.search.currentI < 0:
    content.search.currentI = 0
  else:
    let step = if backwards: -1 else: 1
    content.search.currentI =
      (content.search.currentI + step + matches.len) mod matches.len
  content.search.status[] = $(content.search.currentI + 1) & "/" & $matches.len
  this.gotoCurrentMatch()


proc openFind(this: FindReplacePanel, withReplace: bool) =
  ## opens the panel (or updates it when already open) and focuses the find
  ## field, prefilled with the editor selection when there is one
  let content = this.editor.content
  if content.arrangement == nil: return

  if withReplace:
    this.replaceRowVisible[] = true

  let sel = this.editor.selectedQuery()
  if sel.len > 0:
    content.search.query[] = sel

  content.search.active[] = true
  content.search.dirty = true
  this.performSearch()

  setFocus this.findEdit
  # select the whole query for quick retyping (VS Code behavior)
  this.findEdit.textArea.selectionStart[] = 0
  this.findEdit.textArea.selectionEnd[] = this.findEdit.text[].runeLen


proc replaceCurrent*(this: FindReplacePanel) =
  ## replaces the current match with the replacement text and moves to the
  ## next match
  let content = this.editor.content
  if content.arrangement == nil: return
  if content.search.dirty:
    content.recomputeSearch()
  let matches = content.search.matches
  if not content.search.active[] or content.search.currentI < 0 or matches.len == 0: return
  let m = matches[content.search.currentI]

  content.pushUndoSnapshot()
  content.arrangement.cursors.setLen(1)
  content.arrangement.setSelection(0, m.anchorLine, m.anchorCol, m.line, m.col)
  content.arrangement.insert(content.search.replaceQuery[])
  content.discardUnchangedUndoSnapshot()
  content.updateHeight()
  content.saveFile()

  # the replaced match is gone; select the next one — the cursor is now at the
  # end of the replacement, so the nearest match after the cursor is the right one
  this.performSearch()


proc replaceAll*(this: FindReplacePanel) =
  ## replaces all matches with the replacement text in a single undo step
  let content = this.editor.content
  if content.arrangement == nil: return
  let query = content.search.query[]
  if query.len == 0: return

  content.pushUndoSnapshot()
  let options = content.searchOptionsOf()
  let hadMatches =
    try:
      content.arrangement.replaceAllMatches(query, options, content.search.replaceQuery[])
    except ValueError:  # invalid regex — reported by recomputeSearch below
      false

  if hadMatches:
    # nothing was replaced (no matches or an invalid regex) — drop the snapshot
    content.discardUnchangedUndoSnapshot()
    content.recomputeSearch()
    redraw(content)
    return

  content.search.dirty = true
  content.recomputeSearch()
  this.gotoCurrentMatch()
  content.updateHeight()
  redraw(content)
  content.saveFile()


proc closeFind(this: FindReplacePanel) =
  this.editor.content.closeSearch()


proc connectFindReplace*(editor: CodeEditor): FindReplacePanel =
  ## creates the find & replace panel, adds it into `editor` and connects it
  ## to the editor find/replace shortcuts
  let panel = FindReplacePanel.new()
  panel.editor = editor
  editor.addChild(panel)
  initIfNeeded(panel)

  panel.makeLayout:
    y = PanelPad
    h = binding:
      PanelPad + PanelRowH + PanelGap +
      (if root.replaceRowVisible[]: PanelRowH + PanelGap else: 0'f32) +
      PanelStatusH + PanelPad
    # hug the buttons cluster when the editor is too narrow for the full panel
    w = binding: min(PanelMaxW, max(
      PanelPad * 2 + PanelFieldMinW +
      PanelGap + PanelGroupGap * 3 + PanelBtnGap * 4 +
      toggleReplaceBtn.w[] + caseSensitiveBtn.w[] + wholeWordBtn.w[] +
      regexBtn.w[] + prevMatchBtn.w[] + nextMatchBtn.w[] + closeBtn.w[],
      parent.w[] - 16))
    right = parent.right - 9  # scroll bar (5) + margin (4)
    visibility = binding:
      if root.editor.content.search.active[]: Visibility.visible
      else: Visibility.collapsed

    - UiRect.new:
      this.fill(parent)
      radius = 6
      color = colorTheme[].bgOverlay

    - UiRectBorder.new:
      this.fill(parent)
      radius = 6
      borderWidth = 1
      color = colorTheme[].borderOverlay

    # --- find row: [toggle replace] [find field] [Aa] [ab|] [.*] [↑] [↓] [×] ---
    # toscel buttons size themselves to their text, so they are anchored to
    # each other from the right edge and the find field takes the rest

    - Button.new as toggleReplaceBtn:
      y = binding: PanelPad + (PanelRowH - this.h[]) / 2
      x = PanelPad
      text = "⇅"
      accent = binding: root.replaceRowVisible[]

      on this.activated:
        root.replaceRowVisible[] = not root.replaceRowVisible[]
        setFocus root.findEdit

    - LineEdit.new as root.findEdit:
      left = toggleReplaceBtn.right + PanelGap
      y = PanelPad
      right = caseSensitiveBtn.left - PanelGroupGap
      placeholder = tr"Find"
      valid = binding:
        not (root.editor.content.search.query[].len > 0 and
            root.editor.content.search.resultsCount[] == 0)
      text = binding: root.editor.content.search.query[]
      root.editor.content.search.query[] = binding: this.text[]

      on this.textArea.textEdited:
        root.performSearch()

      this.textArea.keyDown.connectTo root, event:
        if event.key == Key.enter:
          root.gotoMatch(backwards = (shiftKeys * event.window.keyboard.pressed).len > 0)

    - Button.new as caseSensitiveBtn:
      y = binding: PanelPad + (PanelRowH - this.h[]) / 2
      right = wholeWordBtn.left - PanelBtnGap
      text = "Aa"
      accent = binding: root.editor.content.search.caseSensitive[]

      on this.activated:
        root.editor.content.search.caseSensitive[] = not root.editor.content.search.caseSensitive[]
        root.performSearch()
        setFocus root.findEdit

    - Button.new as wholeWordBtn:
      y = binding: PanelPad + (PanelRowH - this.h[]) / 2
      right = regexBtn.left - PanelBtnGap
      text = "ab|"
      accent = binding: root.editor.content.search.wholeWord[]

      on this.activated:
        root.editor.content.search.wholeWord[] = not root.editor.content.search.wholeWord[]
        root.performSearch()
        setFocus root.findEdit

    - Button.new as regexBtn:
      y = binding: PanelPad + (PanelRowH - this.h[]) / 2
      right = prevMatchBtn.left - PanelGroupGap
      text = ".*"
      accent = binding: root.editor.content.search.regex[]

      on this.activated:
        root.editor.content.search.regex[] = not root.editor.content.search.regex[]
        root.performSearch()
        setFocus root.findEdit

    - Button.new as prevMatchBtn:
      y = binding: PanelPad + (PanelRowH - this.h[]) / 2
      right = nextMatchBtn.left - PanelBtnGap
      text = "↑"

      on this.activated:
        root.gotoMatch(backwards = true)
        setFocus root.findEdit

    - Button.new as nextMatchBtn:
      y = binding: PanelPad + (PanelRowH - this.h[]) / 2
      right = closeBtn.left - PanelBtnGap
      text = "↓"

      on this.activated:
        root.gotoMatch(backwards = false)
        setFocus root.findEdit

    - Button.new as closeBtn:
      y = binding: PanelPad + (PanelRowH - this.h[]) / 2
      right = parent.right - PanelPad
      text = "×"

      on this.activated:
        root.closeFind()

    # --- replace row: [replace field] [Replace] [All] ---

    - LineEdit.new as root.replaceEdit:
      left = toggleReplaceBtn.right + PanelGap
      y = PanelPad + PanelRowH + PanelGap
      right = replaceBtn.left - PanelGroupGap
      placeholder = tr"Replace"
      visibility = binding:
        if root.replaceRowVisible[]: Visibility.visible
        else: Visibility.collapsed
      text = binding: root.editor.content.search.replaceQuery[]
      root.editor.content.search.replaceQuery[] = binding: this.text[]

      this.textArea.keyDown.connectTo root, event:
        if event.key == Key.enter:
          root.replaceCurrent()

    - Button.new as replaceBtn:
      y = binding: PanelPad + PanelRowH + PanelGap + (PanelRowH - this.h[]) / 2
      right = replaceAllBtn.left - PanelBtnGap
      text = tr"Replace"
      visibility = binding:
        if root.replaceRowVisible[]: Visibility.visible
        else: Visibility.collapsed

      on this.activated:
        root.replaceCurrent()
        setFocus root.replaceEdit

    - Button.new as replaceAllBtn:
      y = binding: PanelPad + PanelRowH + PanelGap + (PanelRowH - this.h[]) / 2
      right = parent.right - PanelPad
      text = tr"All"
      visibility = binding:
        if root.replaceRowVisible[]: Visibility.visible
        else: Visibility.collapsed

      on this.activated:
        root.replaceAll()
        setFocus root.replaceEdit

    # --- status line ---

    - UiText.new:
      x = 10
      y = binding:
        PanelPad + PanelRowH + PanelGap +
        (if root.replaceRowVisible[]: PanelRowH + PanelGap else: 0'f32)
      text = binding: root.editor.content.search.status[]
      font = font_monospace.withSize(11)
      color = colorTheme[].fgMuted

    # --- Esc closes the panel when the keyboard focus is inside it ---

    - (shortcut(["Esc"], "edit.closeFind", "Close find or replace", context = scWidgetWithChildren)):
      on this.activated: root.closeFind()

  editor.findRequested.connectTo panel:
    panel.openFind(withReplace = false)

  editor.replaceRequested.connectTo panel:
    panel.openFind(withReplace = true)

  editor.findNavigateRequested.connectTo panel, backwards:
    panel.gotoMatch(backwards)

  result = panel
