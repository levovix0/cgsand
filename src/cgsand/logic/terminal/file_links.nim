## Detection of file paths printed in terminal output (compiler messages,
## `ls`, stack traces, ...): a token shaped like a path that names an existing
## file becomes a clickable TerminalLink.


import std/[os, strutils, unicode]
import pkg/vmath
import ./emulator
import ../file_openers


type
  TerminalLink* = object
    ## a file path recognized in the terminal text, together with the cell
    ## range it occupies (x = col, y = absolute row, both inclusive)
    target*: Location
    a*, b*: IVec2


proc `==`*(a, b: TerminalLink): bool =
  a.a == b.a and a.b == b.b and
    a.target.path == b.target.path and
    a.target.line == b.target.line and
    a.target.col == b.target.col


proc logicalLine*(this: TerminalArrangement, row: int): tuple[runes: seq[Rune], cells: seq[IVec2]] =
  ## the text of the logical line containing absolute row `row` (wrapped rows
  ## joined without a separator, like `textBetween`), with the cell
  ## (x = col, y = absolute row) of every rune in it
  let rows = this.absoluteRows()
  let mid = row.clamp(0, rows - 1)

  var first = mid
  while first > 0 and this.rowContinuesNext(first - 1): dec first
  var last = mid
  while last + 1 < rows and this.rowContinuesNext(last): inc last

  let w = this.size.x.int
  for r in first .. last:
    # trailing blanks only pad the row to the grid width, they carry no text
    var xEnd = w - 1
    while xEnd >= 0 and this.cellAtAbsRow(r, xEnd).rune == Rune(' '): dec xEnd
    for x in 0 .. xEnd:
      result.runes.add this.cellAtAbsRow(r, x).rune
      result.cells.add ivec2(x.int32, r.int32)


proc isPathRune(r: Rune): bool =
  ## characters that can make up a path as printed by tools:
  ## letters, digits and a set of punctuation that never separates two tokens
  if r.uint32 >= 128:
    return r.isAlpha  # non-ascii letters can appear in file names
  let c = chr(r.uint32)
  c.isAlphaAscii or c in {'0'..'9', '_', '-', '.', '~', '+', '@', '#', '%', '=', ':', '/', '\\'}


proc parseColonPos(s: string): tuple[path: string, line, col: int] =
  ## a `path:line:col` / `path:line` suffix (gcc, python, ...).
  ## A windows drive colon (`D:\`) peels nothing: the tail is not a number
  var rest = s
  var nums: seq[int]
  for i in 0 ..< 2:
    let c = rest.rfind(':')
    if c <= 0: break
    let tail = rest[c + 1 .. ^1]
    if tail.len == 0 or tail.len > 7 or not tail.allCharsInSet({'0'..'9'}): break
    nums.insert(parseInt(tail), 0)
    rest.setLen c
  if rest.len == 0 or nums.len == 0: return (s, 0, 0)
  elif nums.len == 2: return (rest, nums[0], nums[1])
  else: return (rest, nums[0], 0)


proc parseParenPos(runes: seq[Rune], last: int): tuple[line, col: int] =
  ## a `(<line>)` / `(<line>, <col>)` suffix right after rune `last`,
  ## the Nim compiler style: `foo.nim(12, 3) Error: ...`
  if last + 1 >= runes.len or runes[last + 1] != Rune('('): return
  var nums: seq[int]
  var cur = -1
  var i = last + 2
  while i < runes.len:
    let r = runes[i]
    if r.uint32 in 48'u32 .. 57'u32:
      let d = (r.uint32 - 48'u32).int
      cur = if cur < 0: d else: cur * 10 + d
    elif r == Rune(','):
      if cur < 0: return
      nums.add cur
      cur = -1
    elif r == Rune(')'):
      if cur >= 0: nums.add cur
      if nums.len == 1: return (nums[0], 0)
      if nums.len == 2: return (nums[0], nums[1])
      return
    elif r != Rune(' '):
      return  # anything else inside the parens is not a position
    inc i


proc looksLikePath(s: string): bool =
  ## a rough shape check before hitting the disk: the token must look like a
  ## path, not like a random word that happens to name a file
  if s.len == 0: return false
  # a colon is only a windows drive letter (`D:\`), other colons are not ours
  let c = s.find(':')
  if c != -1 and not (c == 1 and s.len > 2 and s[2] in {'/', '\\'}): return false
  if '/' in s or '\\' in s: return true
  if s.startsWith("~"): return true
  # a bare name must carry an extension: `report.pdf`, not `make`
  let dot = s.rfind('.')
  if dot <= 0 or dot == s.len - 1: return false
  let ext = s[dot + 1 .. ^1]
  ext.len <= 8 and ext.allCharsInSet({'a'..'z', 'A'..'Z', '0'..'9'})


proc resolveLinkPath(p: string): string =
  ## the absolute path when `p` names an existing file: `~` expanded, relative
  ## paths tried against the working directory and the app directory.
  ## "" when nothing exists at `p`
  if p.startsWith("~"):
    let full = expandTilde(p)
    return if fileExists(full): full else: ""
  if isAbsolute(p):
    return if fileExists(p): p else: ""
  for base in ["", getAppDir()]:
    let cand = base / p
    if fileExists(cand): return absolutePath(cand)
  ""


proc fileLinkAt*(this: TerminalArrangement, at: IVec2): tuple[link: TerminalLink, found: bool] =
  ## the file path link containing cell `at` (x = col, y = absolute row),
  ## when the text there is a path to an existing file
  if this.size.x <= 0: return

  let (runes, cells) = this.logicalLine(at.y.int)

  var idx = -1
  for i, c in cells:
    if c == at:
      idx = i
      break
  if idx < 0 or not runes[idx].isPathRune: return

  var ta = idx
  while ta > 0 and runes[ta - 1].isPathRune: dec ta
  var tb = idx
  while tb + 1 < runes.len and runes[tb + 1].isPathRune: inc tb

  # trailing sentence punctuation clung to the token is not part of the path
  var token = $runes[ta .. tb]
  while token.len > 1 and token[^1] in {':', ';', ',', '.', '!', '?', '\'', '"'}:
    token.setLen token.len - 1
  if token.len == 0: return

  var (path, line, col) = parseColonPos(token)
  if line == 0:
    (line, col) = runes.parseParenPos(ta + token.runeLen - 1)

  if not looksLikePath(path): return
  let resolved = resolveLinkPath(path)
  if resolved.len == 0: return

  (
    link: TerminalLink(
      target: Location(path: resolved, line: line, col: col),
      a: cells[ta],
      b: cells[ta + path.runeLen - 1],
    ),
    found: true,
  )
