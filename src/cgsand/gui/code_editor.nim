import std/[sets, os, strutils, times]
import pkg/[vmath, chroma]
import pkg/toscel/[focus]
import pkg/sigui/[uibase, events, scrollArea, mouseArea]
import pkg/sigui/rendering/rice_backend
import pkg/rice/[paths, contextutils]
import ../logic/[configuration, code_editor, asyncio, diagnostics, editor_state, file_openers, shortcuts]
import ./[highlighted_text]


type
  DragSelectMode* = enum
    ## what granularity an ongoing mouse drag selection uses
    charDrag
    wordDrag
    lineDrag

  ContextMenu* = ref object of MouseArea
    ## fullscreen transparent area hosting the editor context menu panel.
    ## It is created on first use, stays alive afterwards and is only shown
    ## and hidden by toggling visibility, so it is never deleted while its
    ## own event handlers are running.
    editor: CodeEditorContent
    menuX*, menuY*: Property[float32]
    cutEnabled*, copyEnabled*, pasteEnabled*: Property[bool]

  ShownDiagnostic* = object
    ## a compiler diagnostic prepared for rendering in the editor
    line*: int              ## 0-based editor line index
    range*: Slice[int]      ## rune range to underline
    severity*: DiagnosticSeverity
    message*: string        ## full message of the diagnostic

  CodeEditorContent* = ref object of Uiobj
    font*: Property[Font]
    breakpointBarWidth*: Property[float32] = 20'f32.property
    lineNumberBarWidth*: Property[float32] = 20'f32.property
    changesBarWidth*: Property[float32] = 5'f32.property
    arrowBarWidth*: Property[float32] = 20'f32.property

    path*: Property[string]   ## path to save on disk (if empty, read-only/no_file)

    nonFoldedArrowsVisible: Property[bool]

    arrangement*: CodeArrangement

    # automatic reload of the file when it changes on disk
    lastReloadCheck: float      ## epochTime of the last disk change check
    lastKnownMtime: Time        ## last modification time seen on disk
    lastKnownSize: BiggestInt   ## last file size seen on disk

    # per-file cursor state recording
    recordedPath: string
    recordedState: FileEditorState

    dragingCursorI: int
    dragSelectMode: DragSelectMode
    wordDragLine: int
    wordDragFirstCol: int
    wordDragLastCol: int
    lineDragLine: int
    contextMenu*: ContextMenu
    modifierKeysDown: set[Key]
    mouseDownCount: int
    lastMouseDown: float
    lastMouseDownPos: Vec2
    wordHighlightSuppressed: bool  ## true right after a text edit, until the cursor is moved freely
    undoHistory: seq[CodeArrangementSnapshot]

    search*: SearchState
      ## state of the find/replace search; managed together with the
      ## find/replace panel (gui/find_replace.nim)

    # compiler diagnostics highlighting (see logic/diagnostics.nim)
    diagnostics*: seq[Diagnostic]
      ## all messages of the last completed check
    diagnosticsShown*: seq[ShownDiagnostic]
      ## messages for the current file, converted into editor coordinates
    diagnosticsDirty: bool
      ## the text changed since the last requested check
    diagnosticsAwaiting: bool
      ## a check is running and its results have not been received yet
    lastDiagnosticsEdit: float
      ## epochTime of the last text change
    nimsuggest: NimsuggestClient
    nimsuggestPath: string
      ## project file the current nimsuggest process was started for
    lastNimsuggestStart: float
      ## epochTime of the last nimsuggest spawn, so a crashing process is
      ## not restarted on every frame
    nimCheckRun: NimCheckRun

  CodeEditor* = ref object of Uiobj
    content*: CodeEditorContent
    scrollArea*: ScrollArea
    findRequested*: Event[void]
      ## the "edit.find" (Ctrl+F) shortcut activated
    replaceRequested*: Event[void]
      ## the "edit.replace" (Ctrl+H) shortcut activated
    findNavigateRequested*: Event[bool]
      ## the "edit.findNext"/"edit.findPrev" shortcuts activated, true = backwards

  CodeEditorFileOpener* = ref object of FileOpener
    editor*: CodeEditor

const MinSelectionWidth = 6'f32
const ScrollBarWidth = 5'f32
const MultiClickTime = 0.4'f32
const MultiClickRadius = 6'f32
const FileReloadCheckInterval = 0.5'f32
const DiagnosticsDebounce = 0.5'f32
  ## delay between a text edit and running the diagnostics backend
const NimsuggestRestartCooldown = 3.0'f32
  ## minimum time between nimsuggest spawns, so a crashing process is not
  ## restarted on every frame
const MaxUndoHistory = 15
const ContextMenuItemH = 24'f32
const ContextMenuWidth = 130'f32
const ContextMenuHeight = 3'f32 * ContextMenuItemH


registerComponent CodeEditor
registerComponent CodeEditorContent
registerComponent ContextMenu



proc textOffsetX(this: CodeEditorContent): float32 =
  this.breakpointBarWidth[] + this.lineNumberBarWidth[] + this.changesBarWidth[] + this.arrowBarWidth[]


proc markDiagnosticsStale(this: CodeEditorContent)
  ## remembers that the text changed and the diagnostics should be rechecked

proc lineNumberBarOffsetX(this: CodeEditorContent): float32 =
  this.breakpointBarWidth[]

proc arrowBarOffsetX(this: CodeEditorContent): float32 =
  this.breakpointBarWidth[] + this.lineNumberBarWidth[] + this.changesBarWidth[]




proc updateHeight*(this: CodeEditorContent) =
  if this.arrangement == nil:
    this.h[] = 0
    return
  this.h[] = this.arrangement.visibleHeight()


proc pushUndoSnapshot*(this: CodeEditorContent) =
  if this.arrangement == nil: return
  this.search.dirty = true
  this.markDiagnosticsStale()
  if this.undoHistory.len >= MaxUndoHistory:
    this.undoHistory.delete(0)
  this.undoHistory.add this.arrangement.snapshot()


proc discardUnchangedUndoSnapshot*(this: CodeEditorContent) =
  if this.undoHistory.len > 0 and this.arrangement != nil and
      this.undoHistory[^1].text == this.arrangement.fileContent():
    this.undoHistory.setLen(this.undoHistory.len - 1)


proc nearestMatchAfterCursor(arr: CodeArrangement, matches: seq[CursorPos]): int =
  ## index of the first match starting at or after the cursor position,
  ## 0 (the first match) when there is no match after it
  if arr.cursors.len == 0: return 0
  let c = arr.cursors[0]
  let cursorPos = (c.line, c.col)
  for i, m in matches:
    if (m.anchorLine, m.anchorCol) >= cursorPos: return i
  return 0


proc recomputeSearch*(this: CodeEditorContent) =
  ## recomputes search matches after the text or the search settings changed.
  ## Updates only the search state — the current match selection and scrolling
  ## are handled by the find panel, so this is also safe to call from drawInner
  this.search.dirty = false
  if not this.search.active[] or this.arrangement == nil:
    this.search.matches.setLen(0)
    this.search.currentI = -1
    return

  let query = this.search.query[]
  if query.len == 0:
    this.search.matches.setLen(0)
    this.search.currentI = -1
    this.search.resultsCount[] = 0
    this.search.status[] = ""
    return

  let options = searchOptions(this.search.caseSensitive[], this.search.wholeWord[], this.search.regex[])
  var matches: seq[CursorPos]
  var status: string
  try:
    matches = this.arrangement.findMatches(query, options)
  except ValueError:
    status = tr"Invalid regular expression"

  if status.len == 0 and matches.len == 0:
    status = tr"No results"

  # keep the current match when it still exists in the new text, otherwise
  # take the nearest match at or after the cursor position
  let oldCurrentI = this.search.currentI
  let oldMatches = this.search.matches
  var newCurrentI = -1
  if matches.len > 0:
    if oldCurrentI >= 0 and oldCurrentI < oldMatches.len:
      let oldMatch = oldMatches[oldCurrentI]
      for i, m in matches:
        if m.sameSelection(oldMatch):
          newCurrentI = i
          break
    if newCurrentI < 0:
      newCurrentI = this.arrangement.nearestMatchAfterCursor(matches)

  this.search.matches = matches
  this.search.currentI = newCurrentI
  this.search.resultsCount[] = matches.len
  this.search.status[] =
    if status.len > 0: status
    else: $(newCurrentI + 1) & "/" & $matches.len


proc closeSearch*(this: CodeEditorContent) =
  ## closes the find/replace search, hiding the panel and match highlights
  if not this.search.active[]: return
  this.search.active[] = false
  this.search.dirty = true
  setFocus this
  redraw(this)


# ----- compiler diagnostics (see logic/diagnostics.nim) -----

proc markDiagnosticsStale(this: CodeEditorContent) =
  ## remember that the text changed and the diagnostics should be rechecked
  this.diagnosticsDirty = true
  this.lastDiagnosticsEdit = epochTime()


proc clearDiagnostics(this: CodeEditorContent) =
  this.diagnostics.setLen(0)
  this.diagnosticsShown.setLen(0)


proc updateShownDiagnostics(this: CodeEditorContent) =
  ## filters the latest check results for the current file and converts their
  ## positions into editor arrangement coordinates
  this.diagnosticsShown.setLen(0)
  if this.arrangement == nil: return
  let currentPath = this.path[].absolutePath
  for d in this.diagnostics:
    if d.file.absolutePath != currentPath: continue
    if d.line < 0 or d.line >= this.arrangement.lines.len: continue
    this.diagnosticsShown.add ShownDiagnostic(
      line: d.line,
      range: diagnosticRange(this.arrangement.lines[d.line].runes, d.col),
      severity: d.severity,
      message: d.message,
    )


proc applyDiagnostics(this: CodeEditorContent, results: seq[Diagnostic]) =
  this.diagnostics = results
  this.updateShownDiagnostics()
  redraw(this)


proc stopDiagnosticsTools(this: CodeEditorContent) =
  ## stops the running diagnostics backend, if any
  if this.nimsuggest != nil:
    this.nimsuggest.stop()
    this.nimsuggest = nil
  if this.nimCheckRun != nil:
    this.nimCheckRun.stop()
    this.nimCheckRun = nil
  this.nimsuggestPath = ""


proc updateNimsuggestDiagnostics(this: CodeEditorContent) =
  ## polls the nimsuggest process and requests a new check after the debounce
  if this.diagnosticsAwaiting:
    let (done, results) = this.nimsuggest.pollResults()
    if done:
      this.diagnosticsAwaiting = false
      if this.nimsuggest.finished() and results.len == 0:
        # the process died before answering — check again after its restart
        this.diagnosticsDirty = true
      else:
        this.applyDiagnostics(results)

  if this.diagnosticsDirty and not this.diagnosticsAwaiting and
      epochTime() - this.lastDiagnosticsEdit >= DiagnosticsDebounce and
      not fileSavesPending():
    this.diagnosticsDirty = false
    this.diagnosticsAwaiting = true
    this.nimsuggest.requestCheck(this.path[].absolutePath)


proc updateNimCheckDiagnostics(this: CodeEditorContent) =
  ## polls the nim check process and starts a new one after the debounce
  if this.nimCheckRun != nil:
    let (done, results) = this.nimCheckRun.pollResults()
    if done:
      this.nimCheckRun.stop()
      this.nimCheckRun = nil
      this.diagnosticsAwaiting = false
      this.applyDiagnostics(results)

  if this.diagnosticsDirty and this.nimCheckRun == nil and
      epochTime() - this.lastDiagnosticsEdit >= DiagnosticsDebounce and
      not fileSavesPending():
    this.diagnosticsDirty = false
    this.diagnosticsAwaiting = true
    this.nimCheckRun = startNimCheck(this.path[].absolutePath)
    if this.nimCheckRun == nil:
      this.diagnosticsAwaiting = false


proc updateDiagnostics(this: CodeEditorContent) =
  ## drives the diagnostics backend: (re)starts it, polls the results and
  ## applies them to the editor (called on every frame tick)
  let backend = config.diagnosticsBackend[]
  if backend == "off" or this.path[].len == 0 or this.arrangement == nil or
      this.path[].splitFile.ext != ".nim":
    if this.nimsuggest != nil or this.nimCheckRun != nil:
      this.stopDiagnosticsTools()
    if this.diagnostics.len > 0:
      this.clearDiagnostics()
      redraw(this)
    return

  let absPath = this.path[].absolutePath

  if backend == "nimsuggest":
    if this.nimCheckRun != nil:
      this.nimCheckRun.stop()
      this.nimCheckRun = nil

    if this.nimsuggest != nil and
        (this.nimsuggest.finished() or this.nimsuggestPath != absPath):
      # the process died, or another file was opened — restart it
      this.nimsuggest.stop()
      this.nimsuggest = nil
      this.nimsuggestPath = ""
      this.diagnosticsAwaiting = false

    if this.nimsuggest == nil and
        epochTime() - this.lastNimsuggestStart >= NimsuggestRestartCooldown:
      this.nimsuggest = newNimsuggestClient(absPath)
      this.nimsuggestPath = absPath
      this.lastNimsuggestStart = epochTime()
      if this.nimsuggest == nil:
        # nimsuggest is not installed — fall back to nim check
        this.updateNimCheckDiagnostics()
        return

    if this.nimsuggest != nil:
      this.updateNimsuggestDiagnostics()
    return

  # backend == "nimCheck"
  if this.nimsuggest != nil:
    this.nimsuggest.stop()
    this.nimsuggest = nil
    this.nimsuggestPath = ""
    this.diagnosticsAwaiting = false
  this.updateNimCheckDiagnostics()


proc drawSelectionRange(
  this: CodeEditorContent,
  ctx: DrawContext,
  line: CodeArrangementLine,
  lineI: int,
  cursor: CursorPos,
  selection: Slice[int],
  fill: Color,
) =
  if selection.len <= 0: return
  let textOffsetX = this.textOffsetX
  let lineH = this.font[].lineHeightPixels
  let text = line.arrangement

  if text.runes.len == 0:
    ctx.fillRect(
      rect(this.globalXy + vec2(textOffsetX, line.rect.y), vec2(MinSelectionWidth, lineH)),
      fill,
    )
    return

  for subRowIdx, span in text.lines:
    let rowFirst = span[0]
    let rowLast = span[1]
    if rowFirst > rowLast: continue
    if selection.a > rowLast: continue
    if selection.b <= rowFirst: continue
    let subRowY = line.rect.y + text.selectionRects[rowFirst].y
    let leftRune = max(selection.a, rowFirst)
    let startX = text.selectionRects[leftRune].x
    let rightRune = min(selection.b - 1, rowLast)
    let endX = text.selectionRects[rightRune].x + text.selectionRects[rightRune].w
    let extraW: float32 =
      if selection.b >= text.runes.len and subRowIdx == text.lines.high and
          cursor.anchorLine != cursor.line and lineI < max(cursor.anchorLine, cursor.line): MinSelectionWidth
      else: 0.0'f32
    let selectionW = max(endX - startX, 0.0'f32) + extraW
    if selectionW <= 0: continue

    ctx.fillRect(
      rect(
        this.globalXy + vec2(textOffsetX + startX, subRowY),
        vec2(selectionW, lineH),
      ),
      fill,
    )


proc drawSquiggle(
  this: CodeEditorContent,
  ctx: DrawContext,
  line: CodeArrangementLine,
  selection: Slice[int],
  color: Color,
) =
  ## wavy underline under the given rune range, following wrapped sub-rows
  let textOffsetX = this.textOffsetX
  let scale = this.root.uiScale[]
  let lineH = this.font[].lineHeightPixels
  let text = line.arrangement

  let last = min(selection.b, text.runes.len)
  let first = min(selection.a, last)
  if last - first <= 0: return

  let amplitude = 1.4'f32 * scale
  let period = 5'f32 * scale
  let thickness = 1.2'f32 * scale
  let bottomGap = 1.2'f32 * scale
  let waveTopY = lineH - (amplitude * 2 + bottomGap)

  # the mesh is mapped through the projection directly (unlike fillRect,
  # which applies the clip rect offset), so the origin of the enclosing
  # clip rect must be subtracted here
  let riceCtx = RiceDrawContext(ctx)
  let clipOrigin =
    if riceCtx.clipStack.len > 0: riceCtx.clipStack[^1].pos
    else: vec2(0'f32, 0'f32)

  for span in text.lines:
    let rowFirst = span[0]
    let rowLast = span[1]
    if rowFirst > rowLast: continue
    if first > rowLast: continue
    if last <= rowFirst: continue
    let subRowY = line.rect.y + text.selectionRects[rowFirst].y
    let leftRune = max(first, rowFirst)
    let startX = text.selectionRects[leftRune].x
    let rightRune = min(last - 1, rowLast)
    let endX = text.selectionRects[rightRune].x + text.selectionRects[rightRune].w
    let w = endX - startX
    if w <= 1'f32: continue

    var path = newPath()
    path.moveTo(vec2(0, amplitude))
    var x = 0'f32
    var up = true
    while x < w:
      let nx = min(x + period / 2, w)
      path.lineTo(vec2(nx, if up: 0'f32 else: amplitude * 2))
      up = not up
      x = nx

    let pos = this.globalXy + vec2(textOffsetX + startX, subRowY + waveTopY) - clipOrigin
    riceCtx.raw.withPushPopIf blendRgbx, true:
      riceCtx.raw.fill2dMeshFlat(
        path.toStrokeMesh(thickness, ButtCap),
        color,
        translate(vec3(pos.x, pos.y, 0)),
      )


proc drawDiagnosticMessage(
  this: CodeEditorContent,
  ctx: DrawContext,
  line: CodeArrangementLine,
  scaledFont: Font,
  spaceW: float32,
  message: string,
  color: Color,
) =
  ## the diagnostic message in the severity color at the end of the line,
  ## over a translucent band of the same color; only the first line of a
  ## multi-line message is shown, the rest is cut off by the editor edge
  let text = message.splitLines()
  if text.len == 0 or text[0].len == 0: return

  let textOffsetX = this.textOffsetX
  let scale = this.root.uiScale[]
  let lineH = this.font[].lineHeightPixels
  let arr = line.arrangement

  # after the end of the line content, on its last wrapped sub-row
  var endX = 0'f32
  var subRowY = 0'f32
  if arr.runes.len > 0:
    endX = arr.selectionRects[^1].x + arr.selectionRects[^1].w
    subRowY = arr.selectionRects[arr.lines[^1][0]].y

  let bandW = this.w[] - textOffsetX - endX
  if bandW > 0:
    var bandColor = color
    bandColor.a = bandColor.a * 0.15'f32
    ctx.fillRect(
      rect(
        this.globalXy + vec2(textOffsetX + endX, line.rect.y + subRowY),
        vec2(bandW, lineH),
      ),
      bandColor,
    )

  ctx.drawRasterText_physicalScale(
    this.globalXy + vec2(textOffsetX + endX + spaceW * 3, line.rect.y + subRowY),
    typeset(scaledFont, text[0]),
    color,
    origin = vec2(0, 0),
  )


method drawInner*(this: CodeEditorContent, ctx: DrawContext) =
  let winRect = rect(vec2(), this.root.wh)
  let textOffsetX = this.textOffsetX
  let lineNumberBarOffsetX_r = this.lineNumberBarOffsetX + this.lineNumberBarWidth[]
  let arrowBarCenterX = this.arrowBarOffsetX + this.arrowBarWidth[] / 2
  var scaledFont = copy this.font[]
  scaledFont.size = scaledFont.size * this.root.uiScale[]

  # recompute stale search matches (text or search settings changed);
  # data-only — the current match selection/scrolling is handled by the panel
  if this.search.dirty:
    this.recomputeSearch()

  var matchingSelections: seq[CursorPos]
  if this.arrangement.cursors.len > 0 and not this.search.active[]:
    let selected = this.arrangement.selectedText(0)
    if selected.len > 0:
      matchingSelections = this.arrangement.matchingSelections(selected)
    elif this.arrangement.cursors.len == 1 and not this.wordHighlightSuppressed:
      let word = this.arrangement.wordAtCursor(0)
      if word.len > 0:
        let matches = this.arrangement.matchingSelections(word, wholeWord = true)
        if matches.len > 1:  # counting the word under the cursor itself
          matchingSelections = matches

  let spaceW = typeset(this.font[], " ").layoutBounds.x
  for i, line in this.arrangement.lines:
    if line.isHidden: continue

    if this.globalY[] + line.rect.y + line.rect.h < winRect.y: continue
    if this.globalY[] + line.rect.y > winRect.y + winRect.h: continue

    # line number
    ctx.drawRasterText_physicalScale(
      this.globalXy + vec2(lineNumberBarOffsetX_r, line.rect.y),
      typeset(scaledFont, $(i + 1)),
      colorTheme[].sLineNumber,
      origin=vec2(1, 0),
    )

    if line.foldable:
      let arrowChar = if i in this.arrangement.foldedLines: "▶" else: "▼"
      if i in this.arrangement.foldedLines or this.nonFoldedArrowsVisible[]:
        # fold arrow
        ctx.drawRasterText_physicalScale(
          this.globalXy + vec2(arrowBarCenterX, line.rect.y),
          typeset(scaledFont, arrowChar),
          colorTheme[].sLineNumber,
          origin=vec2(0.5, 0),
        )

    for offset in line.indentOffsets:
      let guideX = textOffsetX + offset.float32 * spaceW
      ctx.fillRect(
        rect(this.globalXy + vec2(guideX, line.rect.y), vec2(1'f32, line.rect.h)),
        colorTheme[].bgVerticalLine,
      )

    for matchSelection in matchingSelections:
      this.drawSelectionRange(
        ctx,
        line,
        i,
        matchSelection,
        this.arrangement.selectionRangeForLine(matchSelection, i),
        colorTheme[].sWordHighlight,
      )

    if this.search.active[]:
      # highlights of all search matches except the current one — the current
      # match is the real editor selection, drawn below in the selection color
      for matchI, matchSelection in this.search.matches:
        if matchI == this.search.currentI: continue
        this.drawSelectionRange(
          ctx,
          line,
          i,
          matchSelection,
          this.arrangement.selectionRangeForLine(matchSelection, i),
          colorTheme[].sSearchHighlight,
        )

    for c_idx in 0..<this.arrangement.cursors.len:
      if this.arrangement.cursors[c_idx].isDuplicate: continue
      this.drawSelectionRange(
        ctx,
        line,
        i,
        this.arrangement.cursors[c_idx],
        this.arrangement.selectionRangeForLine(c_idx, i),
        colorTheme[].sSelection,
      )

    # the code
    drawHighlightedText(
      ctx,
      this.globalXy + vec2(textOffsetX, line.rect.y),
      line.arrangement,
      line.kinds,
    )

    # compiler diagnostics: a mark in the left gutter, a squiggle underline
    # and the message text at the end of the line
    var primaryDiagI = -1  # the most severe diagnostic of this line
    block findPrimaryDiagnostic:
      var firstWarningI = -1
      for diagI, diag in this.diagnosticsShown:
        if diag.line != i: continue
        if diag.severity == dsError:
          primaryDiagI = diagI
          break findPrimaryDiagnostic
        if firstWarningI < 0: firstWarningI = diagI
      primaryDiagI = firstWarningI

    if primaryDiagI >= 0:
      let diagColor = case this.diagnosticsShown[primaryDiagI].severity
        of dsError: colorTheme[].sErrorSquiggle
        of dsWarning: colorTheme[].sWarningSquiggle

      let lineH = this.font[].lineHeightPixels
      let markH = min(lineH * 0.6, 10'f32 * this.root.uiScale[])
      ctx.fillRect(
        rect(
          this.globalXy + vec2(3'f32, line.rect.y + (lineH - markH) / 2),
          vec2(3'f32, markH),
        ),
        diagColor,
      )

    for diag in this.diagnosticsShown:
      if diag.line != i: continue
      this.drawSquiggle(
        ctx,
        line,
        diag.range,
        case diag.severity
        of dsError: colorTheme[].sErrorSquiggle
        of dsWarning: colorTheme[].sWarningSquiggle,
      )

    if primaryDiagI >= 0:
      let diag = this.diagnosticsShown[primaryDiagI]
      this.drawDiagnosticMessage(
        ctx,
        line,
        scaledFont,
        spaceW,
        diag.message,
        case diag.severity
        of dsError: colorTheme[].sErrorSquiggle
        of dsWarning: colorTheme[].sWarningSquiggle,
      )

    if currentFocus[] == this:
      for cursor in this.arrangement.cursors:
        if cursor.line == i:
          const cursorW = 1.5'f32
          let pos = vec2(textOffsetX, line.rect.y) + line.colToPos(cursor.col)
          # text cursor
          ctx.fillRect(
            rect(this.globalXy + pos, vec2(cursorW, this.font[].lineHeightPixels)),
            colorTheme[].sText,
          )

    if line.foldable and i in this.arrangement.foldedLines:
      const lineH = 1'f32
      let rect = line.visibleRect

      # line for folded line
      ctx.fillRect(
        rect(
          this.globalXy + vec2(textOffsetX + rect.x, rect.y + rect.h - lineH),
          vec2(rect.w, lineH),
        ),
        colorTheme[].bgSelectionLabel,
      )


proc saveFile*(this: CodeEditorContent) =
  if this.path[].len == 0: return
  if this.arrangement == nil: return
  scheduleFileSave(this.path[], this.arrangement.fileContent())


proc setArrangement(this: CodeEditorContent, text: string)


proc parentCodeEditor(this: CodeEditorContent): CodeEditor =
  var obj: Uiobj = this
  while obj != nil:
    if obj of CodeEditor: return CodeEditor(obj)
    obj = obj.parent


proc maxScrollY(this: CodeEditorContent): float32 =
  ## largest vertical scroll offset the ScrollArea allows for the current text
  ## (scrollH = contentH + verticalScrollOverFit, so the max scroll is
  ##  contentH + (editorH - 2*fontSize) - editorH)
  max(this.arrangement.visibleHeight() - this.font[].size * 2, 0'f32)


proc markOnDiskState(this: CodeEditorContent, path: string) =
  ## remember the current on-disk state of `path`, so later polling of external
  ## changes is relative to it
  this.lastReloadCheck = epochTime()
  this.lastKnownMtime = default(Time)
  this.lastKnownSize = 0
  try:
    let info = getFileInfo(path)
    this.lastKnownMtime = info.lastWriteTime
    this.lastKnownSize = info.size
  except CatchableError:
    discard


proc restoreViewState(
  this: CodeEditorContent,
  oldCursors: seq[CursorPos],
  oldFoldedLines: HashSet[int],
  prevScrollY: float32,
) =
  ## after the arrangement was replaced (reload or width change), put cursors,
  ## selections, folds and scroll position back, clamped into the new text
  var cursors = oldCursors
  for c in cursors.mitems:
    c.line = c.line.clamp(0, this.arrangement.lines.high)
    c.anchorLine = c.anchorLine.clamp(0, this.arrangement.lines.high)
    c.col = c.col.clamp(0, this.arrangement.lines[c.line].runes.len)
    c.anchorCol = c.anchorCol.clamp(0, this.arrangement.lines[c.line].runes.len)
    c.snapCol = c.col
    c.hasSelection = c.hasSelection and (c.line != c.anchorLine or c.col != c.anchorCol)
  this.arrangement.cursors = cursors
  this.arrangement.collapseDuplicatedCursors()

  this.arrangement.foldedLines = initHashSet[int]()
  for lineI in oldFoldedLines:
    if lineI >= 0 and lineI < this.arrangement.lines.len:
      this.arrangement.foldedLines.incl lineI
  this.arrangement.updateRects()

  let editor = this.parentCodeEditor()
  if editor != nil:
    editor.scrollArea.targetY[] = prevScrollY.clamp(0, this.maxScrollY())


proc reloadFromDisk(this: CodeEditorContent, text: string) =
  ## replace the edited text with the version now on disk, keeping the cursor,
  ## selections, folds and scroll position as close as the new text allows
  let cursors = this.arrangement.cursors
  let foldedLines = this.arrangement.foldedLines
  let editor = this.parentCodeEditor()
  let scrollY = if editor != nil: editor.scrollArea.targetY[] else: 0'f32

  this.setArrangement(text)
  # undoing across an externally rewritten text would silently revert the
  # external change, so the old undo history is dropped
  this.undoHistory.setLen(0)
  this.search.dirty = true
  this.restoreViewState(cursors, foldedLines, scrollY)


proc checkExternalChanges(this: CodeEditorContent) =
  ## reload the file if it was changed on disk by another program
  var mtime: Time
  var size: BiggestInt
  try:
    let info = getFileInfo(this.path[])
    mtime = info.lastWriteTime
    size = info.size
  except CatchableError:
    return  # file deleted or temporarily unavailable — keep the current text

  if mtime == this.lastKnownMtime and size == this.lastKnownSize: return

  var text: string
  try: text = readFile(this.path[])
  except CatchableError: return

  # a write scheduled by this editor may be in flight right now (even racing
  # with the read above); don't mistake its content for an external change —
  # the next check will see it once the write is finished
  if fileSavesPending(): return
  this.lastKnownMtime = mtime
  this.lastKnownSize = size

  if text == this.arrangement.fileContent():
    return  # this is our own write that just reached the disk
  this.reloadFromDisk(text)


proc recordCursorState(this: CodeEditorContent) =
  ## remember the cursor position, so reopening this file restores it
  let path = this.path[]
  if path.len == 0 or this.arrangement == nil or this.arrangement.cursors.len == 0: return
  let editor = this.parentCodeEditor()
  let state = FileEditorState(
    line: this.arrangement.cursors[0].line,
    col: this.arrangement.cursors[0].col,
    scrollY: if editor != nil: editor.scrollArea.targetY[] else: 0'f32,
  )
  if path == this.recordedPath and state == this.recordedState: return
  this.recordedPath = path
  this.recordedState = state
  setEditorState(path, state)


proc restoreSavedState(this: CodeEditorContent, state: FileEditorState) =
  ## jump to a remembered cursor position and scroll offset
  if this.arrangement == nil or this.arrangement.lines.len == 0: return
  let line = state.line.clamp(0, this.arrangement.lines.high)
  let col = state.col.clamp(0, this.arrangement.lines[line].runes.len)
  this.arrangement.setCursorPos(line, col)
  let editor = this.parentCodeEditor()
  if editor != nil:
    editor.scrollArea.targetY[] = state.scrollY.clamp(0, this.maxScrollY())
  redraw(this)


proc undo(this: CodeEditorContent): bool =
  if this.undoHistory.len == 0: return
  let previous = this.undoHistory.pop()
  this.wordHighlightSuppressed = true
  this.search.dirty = true
  this.markDiagnosticsStale()
  this.arrangement = previous.toArrangement(this.font[], this.w[] - this.textOffsetX)
  this.updateHeight()
  let lineNumberMaxWidth = typeset(this.font[], $this.arrangement.lines.len).layoutBounds.x
  this.lineNumberBarWidth[] = lineNumberMaxWidth
  redraw(this)
  this.saveFile()
  result = true

proc scrollToLine*(this: CodeEditor, line: int) =
  if this.content.arrangement.lines.len == 0:
    this.scrollArea.targetY[] = 0
  else:
    let line = line.clamp(0, this.content.arrangement.lines.high)
    let y = this.content.arrangement.lines[line].rect.y
    if this.scrollArea != nil:
      this.scrollArea.targetY[] = max(0'f32, y - this.scrollArea.h[] / 3)


proc getClipboardText(this: CodeEditorContent): string =
  ## clipboard read that survives platforms with no working clipboard
  try:
    result = this.root.clipboardText
  except NilAccessDefect:
    discard


proc setClipboardText(this: CodeEditorContent, text: string) =
  ## clipboard write that survives platforms with no working clipboard
  try:
    this.root.clipboardText = text
  except NilAccessDefect:
    discard


proc copySelection(this: CodeEditorContent) =
  let text = this.arrangement.selectedText()
  if text.len > 0:
    this.setClipboardText(text)


proc cutSelection(this: CodeEditorContent) =
  let text = this.arrangement.selectedText()
  if text.len > 0:
    this.setClipboardText(text)
    this.pushUndoSnapshot()
    this.wordHighlightSuppressed = true
    deleteForward(this.arrangement)
    this.discardUnchangedUndoSnapshot()
    this.updateHeight()
    redraw(this)
    this.saveFile()


proc pasteClipboard(this: CodeEditorContent) =
  let text = this.getClipboardText()
  if text.len > 0:
    this.pushUndoSnapshot()
    this.wordHighlightSuppressed = true
    this.arrangement.insert(text)
    this.discardUnchangedUndoSnapshot()
    this.updateHeight()
    redraw(this)
    this.saveFile()


proc contextMenuItemActivated(this: CodeEditorContent, itemI: int) =
  case itemI
  of 0: this.cutSelection()
  of 1: this.copySelection()
  of 2: this.pasteClipboard()
  else: discard


proc contextMenuOpen*(this: CodeEditorContent): bool =
  this.contextMenu != nil and this.contextMenu.visibility[] == visible


proc closeContextMenu(this: CodeEditorContent) =
  if this.contextMenu != nil:
    this.contextMenu.visibility[] = collapsed


proc openContextMenu(this: CodeEditorContent, globalPos: Vec2) =
  if this.root == nil: return
  if this.arrangement == nil: return

  let menuPos = vec2(
    globalPos.x.clamp(0'f32, max(this.root.w[] - ContextMenuWidth, 0'f32)),
    globalPos.y.clamp(0'f32, max(this.root.h[] - ContextMenuHeight, 0'f32)),
  )

  if this.contextMenu == nil:
    let menu = ContextMenu.new()
    menu.editor = this
    this.root.addChild(menu)
    initIfNeeded(menu)
    this.contextMenu = menu

    menu.makeLayout:
      x = 0
      y = 0
      w = binding: parent.w[]
      h = binding: parent.h[]
      visibility = collapsed

      # invisible fullscreen area: closes the menu when the user clicks or
      # scrolls outside of it, while letting the events reach other components
      acceptedButtons = {MouseButton.left, MouseButton.middle, MouseButton.right}
      allowEventFallthrough = true

      on this.pressed[] == true:
        let p = this.mouseXy[]
        if not (p.x in root.menuX[] .. root.menuX[] + ContextMenuWidth and
            p.y in root.menuY[] .. root.menuY[] + ContextMenuHeight):
          root.editor.closeContextMenu()

      on this.scrolled:
        root.editor.closeContextMenu()

      - UiRect.new:
        x = binding: root.menuX[]
        y = binding: root.menuY[]
        w = ContextMenuWidth
        h = ContextMenuHeight
        radius = 4
        color = colorTheme[].bgExplorer

      # menu items; enabled state is a property of the menu, so bindings
      # built from it track its changes
      - MouseArea.new:
        x = binding: root.menuX[]
        y = binding: root.menuY[]
        w = ContextMenuWidth
        h = ContextMenuItemH

        - UiRect.new:
          this.fill(parent)
          radius = 2
          color = binding:
            if parent.hovered[] and root.cutEnabled[]: colorTheme[].bgSelection
            else: color(0'f32, 0'f32, 0'f32, 0'f32)

        - UiText.new:
          x = 10
          centerY = parent.center
          text = tr"Cut"
          font = font_monospace.withSize(12)
          color = binding:
            if root.cutEnabled[]: colorTheme[].sText
            else: colorTheme[].sLineNumber

        on this.clicked:
          if root.cutEnabled[]:
            root.editor.contextMenuItemActivated(0)
            root.editor.closeContextMenu()

      - MouseArea.new:
        x = binding: root.menuX[]
        y = binding: root.menuY[] + ContextMenuItemH
        w = ContextMenuWidth
        h = ContextMenuItemH

        - UiRect.new:
          this.fill(parent)
          radius = 2
          color = binding:
            if parent.hovered[] and root.copyEnabled[]: colorTheme[].bgSelection
            else: color(0'f32, 0'f32, 0'f32, 0'f32)

        - UiText.new:
          x = 10
          centerY = parent.center
          text = tr"Copy"
          font = font_monospace.withSize(12)
          color = binding:
            if root.copyEnabled[]: colorTheme[].sText
            else: colorTheme[].sLineNumber

        on this.clicked:
          if root.copyEnabled[]:
            root.editor.contextMenuItemActivated(1)
            root.editor.closeContextMenu()

      - MouseArea.new:
        x = binding: root.menuX[]
        y = binding: root.menuY[] + 2 * ContextMenuItemH
        w = ContextMenuWidth
        h = ContextMenuItemH

        - UiRect.new:
          this.fill(parent)
          radius = 2
          color = binding:
            if parent.hovered[] and root.pasteEnabled[]: colorTheme[].bgSelection
            else: color(0'f32, 0'f32, 0'f32, 0'f32)

        - UiText.new:
          x = 10
          centerY = parent.center
          text = tr"Paste"
          font = font_monospace.withSize(12)
          color = binding:
            if root.pasteEnabled[]: colorTheme[].sText
            else: colorTheme[].sLineNumber

        on this.clicked:
          if root.pasteEnabled[]:
            root.editor.contextMenuItemActivated(2)
            root.editor.closeContextMenu()

  let menu = this.contextMenu
  menu.menuX[] = menuPos.x
  menu.menuY[] = menuPos.y
  menu.cutEnabled[] = this.arrangement.selectedText().len > 0
  menu.copyEnabled[] = menu.cutEnabled[]
  menu.pasteEnabled[] = this.getClipboardText().len > 0
  menu.visibility[] = visible


method recieve*(this: CodeEditorContent, signal: Signal) =
  procCall this.super.recieve(signal)

  signal.match StateBoolChangedEvent:
    if e.kind == StateBoolChangedEventKind.focus:
      # Modifier key-up events can be swallowed by Alt+Tab on Windows.
      # Start with a clean state whenever the window focus changes.
      this.modifierKeysDown = {}

  signal.match KeyEvent:
    if e.key in {Key.lshift, Key.rshift, Key.lcontrol, Key.rcontrol, Key.lalt, Key.ralt}:
      if e.pressed:
        this.modifierKeysDown.incl e.key
      else:
        this.modifierKeysDown.excl e.key
  
  block:
    var n = this.Uiobj
    while n != nil:
      if n.visibility[] == collapsed: return
      n = n.parent

  signal.match TextInputEvent:
    if currentFocus[] == this and this.arrangement != nil and not e.repeated:
      this.pushUndoSnapshot()
      this.wordHighlightSuppressed = true
      this.arrangement.insert(e.text)
      this.discardUnchangedUndoSnapshot()
      this.updateHeight()
      redraw(this)
      this.saveFile()
      signal.handled = true

  signal.match KeyEvent:
    # shortcuts (registered below in init) consume their keys before this,
    # so a `handled` key must not be processed here
    if e.pressed and not signal.handled and currentFocus[] == this and this.arrangement != nil:
      let shift = (this.modifierKeysDown * {Key.lshift, Key.rshift}).len > 0
      let ctrl = (this.modifierKeysDown * {Key.lcontrol, Key.rcontrol}).len > 0
      
      case e.key
      of Key.left:
        this.arrangement.moveCursorLeft(extend = shift, prevWord = ctrl)
        this.wordHighlightSuppressed = false
        redraw(this)

      of Key.right:
        this.arrangement.moveCursorRight(extend = shift, nextWord = ctrl)
        this.wordHighlightSuppressed = false
        redraw(this)

      of Key.up:
        this.arrangement.moveCursorUp(extend = shift)
        this.wordHighlightSuppressed = false
        redraw(this)

      of Key.down:
        this.arrangement.moveCursorDown(extend = shift)
        this.wordHighlightSuppressed = false
        redraw(this)

      of Key.home:
        this.arrangement.moveCursorHome(extend = shift)
        this.wordHighlightSuppressed = false
        redraw(this)

      of Key.End:
        this.arrangement.moveCursorEnd(extend = shift)
        this.wordHighlightSuppressed = false
        redraw(this)

      of Key.backspace:
        this.pushUndoSnapshot()
        this.wordHighlightSuppressed = true
        deleteBack(this.arrangement)
        this.discardUnchangedUndoSnapshot()
        this.updateHeight()
        redraw(this)
        this.saveFile()

      of Key.del:
        this.pushUndoSnapshot()
        this.wordHighlightSuppressed = true
        deleteForward(this.arrangement)
        this.discardUnchangedUndoSnapshot()
        this.updateHeight()
        redraw(this)
        this.saveFile()

      of Key.enter:
        this.pushUndoSnapshot()
        this.wordHighlightSuppressed = true
        insertNewline(this.arrangement)
        this.discardUnchangedUndoSnapshot()
        this.updateHeight()
        redraw(this)
        this.saveFile()

      of Key.escape:
        if this.search.active[]:
          this.closeSearch()
        elif this.contextMenuOpen():
          this.closeContextMenu()
        elif this.arrangement.cursors.len > 1:
          this.arrangement.cursors = @[this.arrangement.cursors[0]]
          this.wordHighlightSuppressed = false
          redraw(this)

      else: discard


proc setArrangement(this: CodeEditorContent, text: string) =
  # todo: if only the width changed, update arrangement instead of regenerating it
  this.arrangement = text.toArrangement(this.font[], this.w[] - this.textOffsetX)
  this.wordHighlightSuppressed = false
  this.markDiagnosticsStale()
  this.updateHeight()

  let lineNumberMaxWidth = typeset(this.font[], $this.arrangement.lines.len).layoutBounds.x
  this.lineNumberBarWidth[] = lineNumberMaxWidth
  redraw(this)


proc rearrange(this: CodeEditorContent) =
  ## re-typeset the text for a new width, keeping the cursor, folds and scroll
  if this.arrangement == nil: return
  let cursors = this.arrangement.cursors
  let foldedLines = this.arrangement.foldedLines
  let editor = this.parentCodeEditor()
  let scrollY = if editor != nil: editor.scrollArea.targetY[] else: 0'f32
  this.setArrangement(this.arrangement.fileContent())
  this.restoreViewState(cursors, foldedLines, scrollY)


proc undoLast*(this: CodeEditorContent) =
  discard this.undo()

proc duplicateSelections(this: CodeEditorContent) =
  this.pushUndoSnapshot()
  this.wordHighlightSuppressed = true
  this.arrangement.duplicateSelectionsOrLines()
  this.discardUnchangedUndoSnapshot()
  this.updateHeight()
  redraw(this)
  this.saveFile()

proc addSelectionToNextMatch(this: CodeEditorContent) =
  if this.arrangement.addSelectionToNextMatch():
    redraw(this)

proc toggleSelectionMode(this: CodeEditorContent) =
  this.arrangement.selectionMode = case this.arrangement.selectionMode
    of LineSelection: BlockSelection
    of BlockSelection: LineSelection
  redraw(this)


method init*(this: CodeEditorContent) =
  procCall this.super.init()

  this.font{} = font_monospace.withSize(12)

  # diagnostics of one file must not be shown for another one
  this.path.changed.connectTo this:
    this.clearDiagnostics()

  this.root.onTick.connectTo this:
    # automatic reload of the file when it is changed on disk by another program
    if this.path[].len > 0 and this.arrangement != nil and
        epochTime() - this.lastReloadCheck >= FileReloadCheckInterval:
      this.lastReloadCheck = epochTime()
      this.checkExternalChanges()

    # compiler diagnostics: run the backend and apply its results
    this.updateDiagnostics()

    # remember the cursor position for each opened file
    this.recordCursorState()

  this.makeLayout:
    - MouseArea.new:
      this.fillVertical(parent)
      x = binding: parent.breakpointBarWidth[] + parent.lineNumberBarWidth[] + parent.changesBarWidth[]
      w = binding: parent.arrowBarWidth[]

      root.nonFoldedArrowsVisible[] = binding: this.hovered[]

      on this.pressed[] == true:
        setFocus root

      on this.clicked:
        let clickY = this.mouseY[]
        for i, line in root.arrangement.lines:
          if line.isHidden: continue
          if clickY >= line.rect.y and clickY < line.rect.y + line.rect.h:
            if line.foldable:
              root.arrangement.toggleFold(i)
              root.updateHeight()
              redraw(root)
            break

    - MouseArea.new:
      this.fillVertical(parent)
      x = binding: root.breakpointBarWidth[] + root.lineNumberBarWidth[] + root.changesBarWidth[] + root.arrowBarWidth[]
      w = binding: parent.w[] - (root.breakpointBarWidth[] + root.lineNumberBarWidth[] + root.changesBarWidth[] + root.arrowBarWidth[])

      allowEventFallthrough = true

      on this.pressed[] == true:
        setFocus root
        root.wordHighlightSuppressed = false
        for i, line in root.arrangement.lines:
          if line.isHidden: continue
          if this.mouseY[] >= line.rect.y and this.mouseY[] < line.rect.y + line.rect.h:
            let col = line.posToCol(vec2(this.mouseX[], this.mouseY[] - line.rect.y))
            let append = (root.modifierKeysDown * {Key.lalt, Key.ralt}).len > 0
            let extend = (root.modifierKeysDown * {Key.lshift, Key.rshift}).len > 0

            let clickPos = this.mouseXy[]
            let now = epochTime()
            if not append and not extend and
                now - root.lastMouseDown < MultiClickTime and
                (clickPos - root.lastMouseDownPos).length < MultiClickRadius:
              root.mouseDownCount = root.mouseDownCount mod 3 + 1
            else:
              root.mouseDownCount = 1
            root.lastMouseDown = now
            root.lastMouseDownPos = clickPos

            if extend and not append and root.arrangement.cursors.len > 0:
              # Shift+click extends the primary selection from its original
              # anchor. A regular click still replaces all extra cursors.
              let cursor = root.arrangement.cursors[0]
              let anchorLine = if cursor.hasSelection: cursor.anchorLine else: cursor.line
              let anchorCol = if cursor.hasSelection: cursor.anchorCol else: cursor.col
              root.arrangement.cursors.setLen(1)
              root.arrangement.setSelection(0, anchorLine, anchorCol, i, col)
              root.dragSelectMode = charDrag
              root.dragingCursorI = 0
            elif not append and root.mouseDownCount == 2:
              root.arrangement.cursors.setLen(1)
              root.arrangement.selectWordAt(0, i, col)
              let cursor = root.arrangement.cursors[0]
              root.wordDragLine = cursor.anchorLine
              root.wordDragFirstCol = cursor.anchorCol
              root.wordDragLastCol = cursor.col
              root.dragSelectMode = wordDrag
              root.dragingCursorI = 0
            elif not append and root.mouseDownCount == 3:
              root.arrangement.cursors.setLen(1)
              root.arrangement.selectLineAt(0, i)
              root.lineDragLine = i
              root.dragSelectMode = lineDrag
              root.dragingCursorI = 0
            else:
              root.arrangement.setCursorPos(i, col, append)
              root.dragSelectMode = charDrag
              root.dragingCursorI = root.arrangement.cursors.high
            redraw(root)
            break

      on this.moved:
        if this.pressed[] and root.dragingCursorI >= 0:
          root.wordHighlightSuppressed = false
          case root.dragSelectMode
          of charDrag:
            root.arrangement.selectToPos(root.dragingCursorI, this.mouseXy[])
          of wordDrag:
            root.arrangement.selectWordsToPos(
              root.dragingCursorI, this.mouseXy[],
              root.wordDragLine, root.wordDragFirstCol, root.wordDragLastCol,
            )
          of lineDrag:
            root.arrangement.selectLinesToPos(root.dragingCursorI, this.mouseXy[], root.lineDragLine)
          redraw(root)

      this.mouseButton.connectTo root, e:
        if e.button == MouseButton.right and e.pressed:
          setFocus root
          if root.arrangement != nil:
            block foundLine:
              for i, line in root.arrangement.lines:
                if line.isHidden: continue
                if this.mouseY[] >= line.rect.y and this.mouseY[] < line.rect.y + line.rect.h:
                  let col = line.posToCol(vec2(this.mouseX[], this.mouseY[] - line.rect.y))
                  let sel = root.arrangement.selectionRangeForLine(0, i)
                  if sel.len == 0 or col < sel.a or col > sel.b:
                    # clicking outside of the selection moves the cursor to it
                    root.arrangement.setCursorPos(i, col)
                    redraw(root)
                  break foundLine
            root.openContextMenu(this.globalXy + this.mouseXy[])

    # --- editor shortcuts (active only when the editor is focused, also
    # listed in the "Key combinations" dialog) ---

    - (shortcut(["Ctrl+C"], "edit.copy", "Copy", context = scWidgetWithChildren)):
      on this.activated: root.copySelection()

    - (shortcut(["Ctrl+X"], "edit.cut", "Cut", context = scWidgetWithChildren)):
      on this.activated: root.cutSelection()

    - (shortcut(["Ctrl+V"], "edit.paste", "Paste", context = scWidgetWithChildren)):
      on this.activated: root.pasteClipboard()

    - (shortcut(["Ctrl+Z"], "edit.undo", "Undo", context = scWidgetWithChildren)):
      on this.activated: root.undoLast()

    - (shortcut(["Ctrl+D"], "edit.duplicate", "Duplicate line or selection", context = scWidgetWithChildren)):
      on this.activated: root.duplicateSelections()

    - (shortcut(["Ctrl+Alt+D"], "edit.addCursorToNextMatch", "Add cursor to next occurrence", context = scWidgetWithChildren)):
      on this.activated: root.addSelectionToNextMatch()

    - (shortcut(["Ctrl+B"], "edit.toggleBlockSelection", "Toggle block selection", context = scWidgetWithChildren)):
      on this.activated: root.toggleSelectionMode()

proc open*(this: CodeEditor, target: Location) =
  setFocus this.content

  # location lines/columns start from 1, the editor arrangement is 0-based
  let line = max(target.line - 1, 0)
  let col = max(target.col - 1, 0)

  if this.content.arrangement != nil and
      this.content.path[].absolutePath == target.path.absolutePath:
    # already open — jump to the location without discarding the undo history
    if target.line > 0:
      # an explicit location is given (e.g. an error link in the terminal)
      this.content.arrangement.setCursorPos(line, col)
      this.scrollToLine(line)
      redraw(this.content)
    # otherwise the cursor stays where the user left it
    return

  this.content.undoHistory.setLen(0)
  try:
    this.content.path[] = target.path
    this.content.setArrangement(readFile(target.path))
    this.content.markOnDiskState(target.path)
    if target.line > 0:
      # an explicit location is given (e.g. an error link in the terminal)
      this.content.arrangement.setCursorPos(line, col)
      this.scrollToLine(line)
    else:
      # restore where the user left off in this file last time
      this.content.restoreSavedState(editorState(target.path))
  except CatchableError as exc:
    this.content.path[] = ""
    this.content.setArrangement("Unable to read file: " & target.path & "\n" & exc.msg)


method canOpen(this: CodeEditorFileOpener, target: Location): bool =
  fileExists(target.path)


method open(this: CodeEditorFileOpener, target: Location) =
  this.editor.open(target)


method init*(this: CodeEditor) =
  procCall this.super.init()

  this.makeLayout:
    - UiRect.new:
      this.fill(parent)
      color = binding: colorTheme[].bgTextArea

    - ScrollArea.new as root.scrollArea:
      this.fill(parent)

      color = binding: colorTheme[].bgScrollBar

      - CodeEditorContent.new as root.content:
        w = binding: parent.w[] - ScrollBarWidth

      verticalScrollOverFit = binding: this.h[] - root.content.font[].size * 2

    - MouseArea.new:
      # right clicks anywhere in the editor open the context menu; the text
      # MouseArea handles clicks on the text itself, this one covers the rest
      this.fill(parent)
      acceptedButtons = {MouseButton.right}

      on this.pressed[] == true:
        if root.content.arrangement != nil:
          root.content.openContextMenu(this.globalXy + this.mouseXy[])

    # --- find & replace shortcuts (active anywhere in the editor, including
    # the find/replace panel itself; the panel is connected in setupApp, see
    # gui/find_replace.nim; also listed in the "Key combinations" dialog) ---

    - (shortcut(["Ctrl+F"], "edit.find", "Find", context = scWidgetWithChildren)):
      on this.activated: root.findRequested.emit()

    - (shortcut(["Ctrl+H"], "edit.replace", "Replace", context = scWidgetWithChildren)):
      on this.activated: root.replaceRequested.emit()

    - (shortcut(["F3"], "edit.findNext", "Find next", context = scWidgetWithChildren)):
      on this.activated: root.findNavigateRequested.emit(false)

    - (shortcut(["Shift+F3"], "edit.findPrev", "Find previous", context = scWidgetWithChildren)):
      on this.activated: root.findNavigateRequested.emit(true)

    root.open(Location(path: config.scriptFile[]))
    on this.w.changed: root.content.rearrange()
