## Selection of the default monospace typeface.
##
## The generic `findSystemFont` of toscel matches font *file names* in a fixed
## pair of directories and only looks at `.ttf` files, so on Linux it often
## misses monospace fonts entirely: a file literally named `monospace*.ttf`
## does not exist (`"monospace"` is a fontconfig alias, not a file name), and
## many distro fonts are `.otf`. The miss falls through to proportional fonts
## like roboto, silently breaking the terminal cell grid. This module picks a
## monospace font the reliable way: well-known file names first, then every
## font in the standard directories (.ttf and .otf) verified for equal glyph
## advance widths. A proportional font is only ever used when nothing
## monospace exists on the system.

import std/[os, strutils, math]
import pkg/pixie/[fontloading, fonts]


proc isMonospace*(t: Typeface): bool =
  ## whether the glyph advance widths are all equal, checked by typesetting a
  ## few probe characters (the same metric the terminal cell size uses)
  if t == nil: return false
  let font = newFont(t)
  font.size = 20

  proc width(s: string): float32 =
    let arr = font.typeset(s)
    if arr.selectionRects.len == 0: return -1
    arr.selectionRects[0].w

  let w = width("W")
  if w <= 0: return false
  for s in ["i", "M", "0", " ", "|", "_"]:
    let x = width(s)
    if x <= 0 or (x - w).abs > w * 0.01'f32: return false
  true


proc loadTypeface(path: string): Typeface =
  try: readTypeface(path)
  except CatchableError: nil


iterator fontFiles*(): string =
  ## all font files in the standard font directories, `.ttf` and `.otf`
  when defined(windows):
    let dirs = @["C:/Windows/Fonts"]
  elif defined(macosx):
    let dirs = @["/System/Library/Fonts", "/Library/Fonts", getHomeDir() / "Library/Fonts"]
  else:
    var dirs = @[
      getHomeDir() / ".local/share/fonts",
      getHomeDir() / ".fonts",
      "/usr/local/share/fonts",
      "/usr/share/fonts",
    ]
    let dataHome = getEnv("XDG_DATA_HOME")
    if dataHome.len > 0: dirs.insert(dataHome / "fonts", 0)
    for d in getEnv("XDG_DATA_DIRS").split(':'):
      if d.len > 0: dirs.add(d / "fonts")

  for dir in dirs:
    if dirExists(dir):
      for path in walkDirRec(dir):
        let ext = path.splitFile.ext.toLowerAscii
        if ext == ".ttf" or ext == ".otf":
          yield path


proc fontFileName(path: string): string =
  ## normalized file name, the same matching rule as toscel's findSystemFont
  var name = path.splitFile.name.normalize
  name.removeSuffix("-regular")
  name


proc matchesFontName(path, query: string): bool =
  cmpIgnoreStyle(fontFileName(path), query) == 0


proc looksLikeMonospace(path: string): bool =
  ## a rough name check, to try the likely candidates before the rest
  let n = path.splitFile.name.toLowerAscii
  for hint in ["mono", "code", "consol", "hack", "courier", "menlo", "terminus"]:
    if hint in n: return true
  false


const PreferredMonospaceFonts* = [
  ## normalized file names of the common monospace fonts, most wanted first
  "firacode", "jetbrainsmono", "cascadiacode", "cascadiamono", "monospace",
  "consola", "consolamono", "adwaitamono", "dejavusansmono", "liberationmono",
  "notosansmono", "ubuntumono", "firamono", "hack", "inconsolata", "menlo",
  "monaco",
]


proc findMonospaceTypeface*(userFont = ""): Typeface =
  ## the typeface for the terminal and the code editor: `userFont` (a font
  ## file path or a font name from the config) when set, otherwise an
  ## auto-detected monospace system font
  var files: seq[string]
  for p in fontFiles(): files.add p

  if userFont.len > 0:
    if fileExists(userFont):
      result = loadTypeface(userFont)
      if result != nil: return
    for p in files:
      if matchesFontName(p, userFont):
        result = loadTypeface(p)
        if result != nil: return

  # 1. a known monospace file name, each verified to actually be monospace
  for name in PreferredMonospaceFonts:
    for p in files:
      if matchesFontName(p, name):
        let t = loadTypeface(p)
        if t != nil and isMonospace(t): return t

  # 2. any font file with equal advance widths, monospace-looking names first
  for look in [true, false]:
    for p in files:
      if looksLikeMonospace(p) == look:
        let t = loadTypeface(p)
        if t != nil and isMonospace(t): return t

  # 3. nothing monospace exists: a proportional font keeps the app usable
  #    (the terminal cell grid degrades, as it did before)
  for p in files:
    result = loadTypeface(p)
    if result != nil: return
