import sandbox, geom2d

type
  Scheme = seq[seq[string]]
  SchemeN = int
  
  Lit = string
  AndGate = object
  OrGate = object
  Input = seq[EntityId]

  Rect = object
    pos: Point2
    wh: Vec2


# x y z x̅ y̅ z̅
doc.add Scheme @[@["x", "y", "z"], @["x", "y", "z̅"], @["x̅", "y", "z̅"]]
doc.add Scheme @[@["x", "y"], @["x", "z̅"]]


# todo: allow to define (in CanvasSettings) where the "origin" (0, 0) is located (at courner or at center)
# todo: allow to define (in CanvasSettings) if y is up or down


var x = 0.0
var h = 0.0
var schemeH: seq[float]

doc.forEach (scheme: Scheme):
  if x != 0: x += 5
  var y = 0.0

  let schemeN = SchemeN schemeH.len
  var orInp: seq[EntityId]

  for andGate in scheme:
    var andInp: seq[EntityId]
    let p = point2(x + 3, -y)
    
    for sym in andGate:
      andInp.add doc.spawn(Lit sym, point2(x, -y), schemeN)
      y += 1.5
    
    orInp.add doc.spawn(AndGate(), p, Input andInp, schemeN)
    y += 1
  
  y -= 1
  orInp.add doc.spawn(OrGate(), point2(x + 8, -(y - orInp.len.float*1.5) / 2), Input orInp, schemeN)
  
  x += 10
  h = max(h, y)
  schemeH.add y

doc.forEach (p: var Point2, n: SchemeN):
  p = p + vec2(0, -(h - schemeH[n]) / 2)


doc.add:
  CanvasSettings(
    size: vec2(x + 2, h + 2),
    mmScale: 1,
  )
  Background color(1, 1, 1)
  Foreground color(0, 0, 0)


doc.forEach (p: var Point2):
  p = p - vec2(x, -h) / 2


doc.forEach (Lit, p: Point2):
  doc.add Rect(pos: p, wh: vec2(1, 1))
  doc.add lineSection(p + vec2(0, -1.25), p + vec2(3, -1.25))

var rects: seq[(EntityId, Rect)]
doc.forEach (id: EntityId, AndGate|OrGate, p: Point2, i: Input):
  rects.add (id, Rect(pos: p, wh: vec2(2, i.len.float*1.5)))
for (id, rect) in rects:
  doc.update id: add rect  # todo: allow to update inside forEach


doc.forEach (r2: Rect, AndGate|OrGate, i: Input):
  doc.forEach (r1: Rect, AndGate|OrGate, id: EntityId):
    let n = i.find(id)
    if n != -1:
      let p1 = r1.pos + vec2(r1.wh.x, -r1.wh.y / 2)
      let y2 = r2.pos.y - 0.75 - n.float*1.5
      let x_mid = r1.pos.x + r1.wh.x + (r2.pos.x - (r1.pos.x + r1.wh.x)) / 2
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


doc.forEach (r: Rect):
  doc.add lineSection(r.pos, r.pos + vec2(r.wh.x, 0))
  doc.add lineSection(r.pos + vec2(r.wh.x, 0), r.pos + vec2(r.wh.x, -r.wh.y))
  doc.add lineSection(r.pos + vec2(r.wh.x, -r.wh.y), r.pos + vec2(0, -r.wh.y))
  doc.add lineSection(r.pos + vec2(0, -r.wh.y), r.pos)


# todo: text

