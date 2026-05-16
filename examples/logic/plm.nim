import sandbox, geom2d


let darkTheme* = false
let SZ = 2.0


let globals* = doc.spawn(
  CanvasSettings(
    autoSize: true,
    margin: vec2(2, 2),
  ),
  AxisYDown,
  (if darkTheme: Foreground color(0.75, 0.75, 0.8) else: Foreground color(0, 0, 0)),
  FontSize 1,
)
if not darkTheme:
  doc.update globals: add Background color(1, 1, 1)




var matrix = [
  [0, 1, 0, 0, 0, 0, 0, 0],
  [1, 0, 0, 1, 1, 1, 0, 1],
  [0, 0, 1, 0, 0, 0, 1, 0],
  [1, 1, 0, 1, 0, 1, 0, 1],
  [0, 1, 1, 0, 0, 1, 0, 0],
  [1, 0, 0, 0, 0, 0, 0, 0],
  [1, 0, 0, 1, 1, 0, 1, 0],
  [0, 1, 1, 0, 0, 0, 0, 0],
]

let resMatrix = [
  [1, 1, 1, 1, 1, 1, 0, 0],
  [1, 1, 1, 1, 0, 0, 1, 1],
  [1, 0, 0, 0, 1, 1, 1, 1],
]

let combined = @matrix & @resMatrix


let w = matrix[0].len
let h = matrix.len + resMatrix.len


for x in 0..<w:
  doc.add lineSection(point2(x.float * SZ, 0), point2(x.float * SZ, (h-1).float * SZ))

for y in 0..<h:
  doc.add lineSection(point2(0, y.float * SZ), point2((w-1).float * SZ, y.float * SZ))

for x in 0..<w:
  for y in 0..<h:
    if combined[y][x].bool:
      doc.add circle(point2(x.float * SZ, y.float * SZ), 0.2), Background doc.foreground


for i, v in ["x", "y", "z", "t"]:
  let y = i.float * 2 * SZ
  doc.add Text v:
    Position2 point2(-8, y)
    PositionAtRight
  doc.add lineSection(point2(-7, y), point2(0, y))
  doc.add Text v:
    Position2 point2(-6, y + SZ)
    PositionAtRight
  doc.add lineSection(point2(-5, y + SZ), point2(0, y + SZ))
  doc.add lineSection(point2(-6.5, y + SZ/4*3), point2(-5.9, y + SZ/4*3))
  
  let r = (xy: point2(-4, y + SZ/4), wh: vec2(SZ/2, SZ/2))
  doc.add lineSection(r.xy, r.xy + vec2(r.wh.x, 0))
  doc.add lineSection(r.xy + vec2(r.wh.x, 0), r.xy + vec2(r.wh.x, r.wh.y))
  doc.add lineSection(r.xy + vec2(r.wh.x, r.wh.y), r.xy + vec2(0, r.wh.y))
  doc.add lineSection(r.xy + vec2(0, r.wh.y), r.xy)
  doc.add Text "¬":
    Position2 r.xy + r.wh/2
    PositionAtCenter
  doc.add circle(point2(-4 + SZ/4, y), 0.1), Background doc.foreground
  doc.add circle(point2(-4 + SZ/4, y + SZ), 0.1), Background doc.foreground
  doc.add lineSection(point2(-4 + SZ/4, y), point2(-4 + SZ/4, y + SZ/4))
  doc.add lineSection(point2(-4 + SZ/4, y + SZ/4*3), point2(-4 + SZ/4, y + SZ))


# todo: colums of vertical line descriptions (n = x * !z)
# todo: resMatrix ouputs (f1, f2, f3)

