import sandbox, geom2d, strutils, sequtils

type
  NodeKind = enum
    SymN
    AndN
    OrN

  Node = object
    case kind: NodeKind
    of AndN, OrN: childs: seq[Node]
    of SymN: name: string
  
  Scheme = Node
  SchemeN = int
  
  Sym = string
  AndGate = object
  OrGate = object
  Input = seq[EntityId]

  Rect = object
    pos: Point2
    wh: Vec2
  
  Final = object


converter toNode(name: string): Node = Node(kind: SymN, name: name)
proc orN(childs: varargs[Node]): Node = Node(kind: OrN, childs: childs.toSeq)
proc andN(childs: varargs[Node]): Node = Node(kind: AndN, childs: childs.toSeq)


doc.add Scheme orN(andN("x", "y", "z"), andN("x", "y", "!z"), andN("!x", "y", "!z"))
doc.add Scheme orN(andN("x", "y"), andN("y", "!z"))
doc.add Scheme andN(orN("x", "!z"), "y")


# todo: allow to define (in CanvasSettings) where the "origin" (0, 0) is located (at courner or at center)
# todo: allow to define (in CanvasSettings) if y is up or down


proc drawNode(n: Node, pos: Point2, schemeN: SchemeN): tuple[id: EntityId, size: Vec2] =
  case n.kind
  of SymN:
    result.size = vec2(1, 1.5)
    result.id = doc.spawn(Sym n.name, Position2 pos, schemeN)

  of AndN, OrN:
    var inp: seq[EntityId]
    var y = 0.0
    var w = 0.0

    for i, child in n.childs:
      if i != 0 and child.kind != SymN: y += 1
      let (id, size) = drawNode(child, pos + vec2(0, -y), schemeN)
      inp.add id
      y += size.y
      w = max(w, size.x)
    
    result.size = vec2(w + 4, y)
    let boxSize = inp.len.float*1.5
    if n.kind == AndN:
      result.id = doc.spawn(AndGate(), Position2 pos + vec2(w + 2, -((y - boxSize) / 2)), Input inp, schemeN)
    else:
      result.id = doc.spawn(AndGate(), Position2 pos + vec2(w + 2, -((y - boxSize) / 2)), Input inp, schemeN)


var x = 0.0
var h = 0.0
var schemeH: seq[float]

doc.forEach (scheme: Scheme):
  if x != 0: x += 4
  let (root, size) = drawNode(scheme, point2(x, 0), schemeH.len)
  doc.update root: add Final()
  x += size.x
  h = max(h, size.y)
  schemeH.add size.y

doc.forEach (p: var Position2, n: SchemeN):
  p = p + vec2(0, -(h - schemeH[n]) / 2)


doc.add:
  CanvasSettings(
    size: vec2(x + 2, h + 2),
    mmScale: 1,
  )
  Background color(1, 1, 1)
  Foreground color(0, 0, 0)
  FontSize 1



doc.forEach (p: var Position2):
  p = p - vec2(x, -h) / 2


doc.forEach (text: Sym, p: Position2):
  var text = text
  if text.startsWith("!"):
    doc.add lineSection(p + vec2(0.2, -0.15), p + vec2(0.8, -0.15))

  text.removePrefix "!"
  
  doc.add Text text:
    Position2 p + vec2(0.5, -1.1)
    PositionAtBottom

  doc.add lineSection(p + vec2(0, -1.25), p + vec2(3, -1.25))


var rects: seq[(EntityId, Rect)]
doc.forEach (id: EntityId, AndGate|OrGate, p: Position2, i: Input):
  rects.add (id, Rect(pos: p, wh: vec2(2, i.len.float*1.5)))
  doc.add Text (if has AndGate: "&" else: "1"):
    Position2 p + vec2(1, -0.25)
    PositionAtTop

for (id, rect) in rects:
  doc.update id: add rect  # todo: allow to update inside forEach


doc.forEach (r2: Rect, AndGate|OrGate, i: Input):
  var x_mid = float.low

  doc.forEach (r1: Rect, AndGate|OrGate, id: EntityId):
    let n = i.find(id)
    if n != -1:
      x_mid = max(x_mid, r1.pos.x + r1.wh.x + (r2.pos.x - (r1.pos.x + r1.wh.x)) / 2)

  doc.forEach (p1: Position2, Sym, id: EntityId):
    let n = i.find(id)
    if n != -1:
      x_mid = max(x_mid, p1.x + 3 + (r2.pos.x - (p1.x + 3)) / 2)
      

  doc.forEach (r1: Rect, AndGate|OrGate, id: EntityId):
    let n = i.find(id)
    if n != -1:
      let p1 = r1.pos + vec2(r1.wh.x, -r1.wh.y / 2)
      let y2 = r2.pos.y - 0.75 - n.float*1.5
      let p = [
        p1,
        point2(x_mid, p1.y),
        point2(x_mid, y2),
        point2(r2.pos.x, y2),
      ]
      # todo: clone() for ecs
      # todo: `doc.add Polyline p` witch will be converted to multiple line segments, with same other components and ExplodedFrom polylineEntityId
      # todo: same for Polygon
      # todo: `doc.massAdd [a, b, c]: props` which will add entities that has same props components and a signle diffirent component
      # todo: let noLines = snapshot(); ...; let withLines = snapshot(); doc.forEach (...) {.includes: noLines..withLines.}: ...
      doc.add lineSection(p[0], p[1])
      doc.add lineSection(p[1], p[2])
      doc.add lineSection(p[2], p[3])
      

  doc.forEach (p1: Position2, Sym, id: EntityId):
    let n = i.find(id)
    if n != -1 and p1.x + 3.1 < r2.pos.x:
      let p1 = p1 + vec2(3, -1.25)
      let y2 = r2.pos.y - 0.75 - n.float*1.5
      let p = [
        p1,
        point2(x_mid, p1.y),
        point2(x_mid, y2),
        point2(r2.pos.x, y2),
      ]
      doc.add lineSection(p[0], p[1])
      doc.add lineSection(p[1], p[2])
      doc.add lineSection(p[2], p[3])


doc.forEach (r: Rect):
  doc.add lineSection(r.pos, r.pos + vec2(r.wh.x, 0))
  doc.add lineSection(r.pos + vec2(r.wh.x, 0), r.pos + vec2(r.wh.x, -r.wh.y))
  doc.add lineSection(r.pos + vec2(r.wh.x, -r.wh.y), r.pos + vec2(0, -r.wh.y))
  doc.add lineSection(r.pos + vec2(0, -r.wh.y), r.pos)


# todo: text

