import std/[unicode, strutils, sequtils]
import pkg/[vmath, bumpy]


type
  CodeLine* = seq[Rune]

  CodeFile* = ref object
    lines*: seq[CodeLine]


  CodeRenderer* = ref object of RootObj
  

  Node* = ref object of RootObj
    box*: Rect

  TextNode* = ref object of Node
    rune*: Rune

  CodeArrangementLine* = ref object
    box*: Rect
    data*: seq[Node]

  CodeArrangement* = ref object
    box*: Rect
    lines*: seq[CodeArrangementLine]
    


proc readCodeFile*(filename: string): CodeFile =
  new result
  result.lines = filename.readFile.splitLines.mapIt(it.toRunes)


proc writeCodeFile*(filename: string, v: CodeFile) =
  writeFile filename, v.lines.join("\n")



method toTextNodes*(this: CodeRenderer, text: openArray[Rune], width: float32): seq[TextNode] {.base.} = discard

method minimumLineHeight*(this: CodeRenderer): float32 {.base.} = 0
  ## minimum line height in pixels

method interval*(this: CodeRenderer, data: openArray[Node], i: int): float32 {.base.} = 0
  ## (additional) interval between nodes
  


method updateSize*(this: Node) {.base.} =
  this.box.wh = vec2()

method updateSize*(this: TextNode) =
  discard  # managed by renderer, unchangable


proc arrange*(data: seq[Node], renderer: CodeRenderer, width: float32): CodeArrangementLine =
  new result
  result.data = data

  var x = 0'f32
  var y = 0'f32
  var lineHeight = renderer.minimumLineHeight

  for i, node in data:
    let x2 = x + node.box.w
    if x2 > width:
      x = 0
      y += lineHeight
      lineHeight = renderer.minimumLineHeight
    
    node.box.x = x
    node.box.y = y

    x += node.box.w + renderer.interval(data, i + 1)
    lineHeight = max(lineHeight, node.box.h)
  
  result.box.h = y + lineHeight
  result.box.w = width  #?



proc updatePositions*(arrangement: CodeArrangement) =
  var y = 0'f32
  var w = 0'f32

  for line in arrangement.lines:
    line.box.x = 0
    line.box.y = y
    w = max(line.box.w, line.box.w)
    y += line.box.h
  
  arrangement.box.h = y
  arrangement.box.w = w



proc toArrangement*(cf: CodeFile, renderer: CodeRenderer, width: float32): CodeArrangement =
  new result
  for line in cf.lines:
    result.lines.add arrange(renderer.toTextNodes(line, width).mapIt(it.Node), renderer, width)



when isMainModule:
  import pkg/print


  let cf = readCodeFile("examples/script.nim")
  

  type
    MyRenderer = ref object of CodeRenderer
  
  method toTextNodes*(this: MyRenderer, text: openArray[Rune], width: float32): seq[TextNode] =
    for rune in text:
      result.add TextNode(box: rect(0, 0, 1, 1), rune: rune)
  
  method minimumLineHeight*(this: MyRenderer): float32 = 1
  

  print cf.toArrangement(MyRenderer(), 10)
  

