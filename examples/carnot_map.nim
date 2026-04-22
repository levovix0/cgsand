import sandbox, geom2d, strutils, sequtils


type
  RectTable* = object
    size: Vec2
    cols, rows: int
  
  FigureBracket* = object
    a, b: Point2
    h: Vec2
    power: float = 1


let variables = @["x", "y", "z"]
let data = @[
  @[0, 1, 1, 1],
  @[1, 1, 0, 1],
]
let margin = 3'f32
let rt = RectTable(size: vec2(4*4, 2*2), cols: 4, rows: 2)
doc.add:
  rt
  Position2 point2() + vec2(margin, -margin)


let ca = CanvasSettings(
  size: rt.size + vec2(margin*2),
  mmScale: 1,
)

doc.add:
  ca
  Background color(1, 1, 1)
  Foreground color(0, 0, 0)
  # Foreground color(0.75, 0.75, 0.8)
  FontSize 1



doc.forEach (p: var Position2):
  p = p - vec2(ca.size.x, -ca.size.y) / 2


doc.forEach (r: RectTable, pos: Position2||point2()):
  doc.add lineSection(pos, pos + vec2(r.size.x, 0))
  doc.add lineSection(pos + vec2(r.size.x, 0), pos + vec2(r.size.x, -r.size.y))
  doc.add lineSection(pos + vec2(r.size.x, -r.size.y), pos + vec2(0, -r.size.y))
  doc.add lineSection(pos + vec2(0, -r.size.y), pos)

  for i in 1..r.rows:
    let y = (i / r.rows) * r.size.y
    doc.add lineSection(pos + vec2(0, -y), pos + vec2(r.size.x, -y))

  for i in 1..r.cols:
    let x = (i / r.cols) * r.size.x
    doc.add lineSection(pos + vec2(x, 0), pos + vec2(x, -r.size.y))


  if variables.len == 3:
    let sz = vec2(r.size.x, -(r.size.y))
    doc.add FigureBracket(a: pos + vec2(0, 0) * sz, b: pos + vec2(0.5, 0) * sz, h: vec2(0, 0.5), power: 2)
    doc.add FigureBracket(a: pos + vec2(0.5, 0) * sz, b: pos + vec2(1, 0) * sz, h: vec2(0, 0.5), power: 2)
    doc.add FigureBracket(a: pos + vec2(0.25, 1) * sz, b: pos + vec2(0.75, 1) * sz, h: vec2(0, -0.5), power: 2)
    doc.add Text "!x2":
      Position2 pos + vec2(0.25, 0) * sz + vec2(0, 0.5)
      PositionAtBottom
    doc.add Text "x2":
      Position2 pos + vec2(0.75, 0) * sz + vec2(0, 0.5)
      PositionAtBottom
    doc.add Text "!x3":
      Position2 pos + vec2(1/8, 1) * sz + vec2(0, -0.5)
      PositionAtTop
    doc.add Text "!x3":
      Position2 pos + vec2(7/8, 1) * sz + vec2(0, -0.5)
      PositionAtTop
    doc.add Text "x3":
      Position2 pos + vec2(0.5, 1) * sz + vec2(0, -0.5)
      PositionAtTop
    doc.add Text "!x1":
      Position2 pos + vec2(0, 1/4) * sz + vec2(-0.2, 0)
      PositionAtRight
    doc.add Text "x1":
      Position2 pos + vec2(0, 3/4) * sz + vec2(-0.2, 0)
      PositionAtRight
  
  for x in 0..<r.cols:
    for y in 0..<r.rows:
      let d = data[y][x]
      let p = pos + vec2(((x*2+1) / (r.cols*2)) * r.size.x, ((y*2+1) / (r.rows*2)) * -r.size.y)
      doc.add Text $d:
        Position2 p
        PositionAtCenter
      doc.add Text ($y & $(x div 2) & $(((x mod 2).bool xor (x div 2).bool).int)):
        Position2 p + vec2(2, -1)
        PositionAtBottomRight
        FontSize 0.4


doc.forEach (f: FigureBracket):
  var points: array[128, Point2]
  let w = f.b - f.a
  for i, p in points.mpairs:
    let x = i / (points.len - 1)
    let y =
      if x < (1/4): sin((x - (0/4)) * 4 * Pi/2).pow(1/f.power) / 2
      elif x < (2/4): 0.5 + (1 - sin((x - (1/4)) * 4 * Pi/2 + Pi/2)).pow(f.power*2) / 2
      elif x < (3/4): 0.5 + (1 - sin((1 - (x - (2/4)) * 4) * Pi/2 + Pi/2)).pow(f.power*2) / 2
      else: sin((1 - ((x - (3/4)) * 4)) * Pi/2).pow(1/f.power) / 2
    p = f.a + w * x + f.h * y
  
  for i in 0..<(points.len-1):
    doc.add lineSection(points[i], points[i+1])

