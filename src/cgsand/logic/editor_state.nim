## persistent per-file editor state: remembers the cursor position and scroll
## offset of each opened file, so reopening a file restores where the user
## left off instead of jumping to the top


import std/[json, os, tables]
import ./asyncio


type FileEditorState* = object
  line*, col*: int     ## cursor position, 0-based
  scrollY*: float32    ## vertical scroll offset in pixels


var gStates: Table[string, FileEditorState]
var gLoaded = false

proc stateFilePath*(): string =
  getConfigDir() / "cgsand" / "editor_state.json"

proc stateKey(path: string): string =
  path.absolutePath.normalizedPath

proc loadStates() =
  try:
    let statesJson = readFile(stateFilePath()).parseJson
    for path, node in statesJson:
      gStates[path] = FileEditorState(
        line: node{"line"}.getInt(0),
        col: node{"col"}.getInt(0),
        scrollY: node{"scrollY"}.getFloat(0),
      )
  except CatchableError:
    discard  # missing or corrupted state file — start with no saved states

proc ensureLoaded() =
  if not gLoaded:
    gLoaded = true
    loadStates()

proc editorState*(path: string): FileEditorState =
  ## last saved cursor/scroll state for `path`; the default state when unknown,
  ## so callers can simply compare it against FileEditorState()
  ensureLoaded()
  gStates.getOrDefault(stateKey(path))

proc setEditorState*(path: string, state: FileEditorState) =
  ## update the state of `path` and persist all states (the write is async)
  if path.len == 0: return
  ensureLoaded()
  let key = stateKey(path)
  if gStates.getOrDefault(key) == state: return
  gStates[key] = state

  var statesJson = newJObject()
  for savedPath, s in gStates:
    statesJson[savedPath] = %*{"line": s.line, "col": s.col, "scrollY": s.scrollY}
  try: createDir(stateFilePath().parentDir)  # the save thread does not create dirs
  except CatchableError: discard
  scheduleFileSave(stateFilePath(), statesJson.pretty)
