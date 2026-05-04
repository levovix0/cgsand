import std/[unicode, strutils, sequtils]
import pkg/[vmath, bumpy]
import pkg/pixie/fonts
import ./[syntax_highlighting]
export CodeKind


type
  CodeLine* = seq[Rune]

  CodeFile* = ref object
    lines*: seq[CodeLine]
  

  CodeArrangementLine* = ref object
    rect*: Rect
    arrangement*: Arrangement
    kinds*: seq[CodeKind]

  CodeArrangement* = ref object
    lines*: seq[CodeArrangementLine]
    


proc readCodeFile*(filename: string): CodeFile =
  new result
  result.lines = filename.readFile.splitLines.mapIt(it.toRunes)


proc writeCodeFile*(filename: string, v: CodeFile) =
  writeFile filename, v.lines.join("\n")



proc toArrangement*(cf: CodeFile, font: Font, width: float32): CodeArrangement =
  new result
  var y = 0'f32
  
  for line in cf.lines:
    var cline = CodeArrangementLine(arrangement: typeset(font, $line, bounds=vec2(width, 0)))
    cline.rect = rect(vec2(0, y), cline.arrangement.layoutBounds)
    cline.kinds = parseNimCode(line, NimParseState(), line.len).segments
    let lineCount = max(cline.arrangement.lines.len.float32, 1)
    y += lineCount * font.size * (font.typeface.ascent / font.typeface.scale + max(font.typeface.lineGap / font.typeface.scale, 0.25))
    result.lines.add cline
  
