import sandbox
import sigeo/sdf


# 2D SDF primitives from Inigo Quilez's article "2D distance functions",
# shown as thin extruded plates. Sketches like these are usually extruded
# or revolved into 3D parts.


let shapes: seq[tuple[name: string, sdf: Sdf2]] = @[
  ("circle", sdCircle(p2(0, 0), 0.9)),
  ("box", sdBox(p2(0, 0), v2(0.8, 0.6))),
  ("rounded box", sdRoundedBox(p2(0, 0), v2(0.8, 0.6), 0.3)),
  ("chamfer box", sdChamferBox(p2(0, 0), v2(0.8, 0.6), 0.4)),
  ("rhombus", sdRhombus(p2(0, 0), v2(1.0, 0.65))),
  ("trapezoid", sdTrapezoid(p2(0, 0), 1.0, 0.5, 0.75)),

  ("parallelogram", sdParallelogram(p2(0, 0), 0.75, 0.55, 0.45)),
  ("triangle", sdTriangle(p2(0, 0.8), p2(-1, -0.6), p2(1, -0.6))),
  ("equilateral", sdEquilateralTriangle(p2(0, 0), 1.0).opTranslate(v2(0, -0.3))),
  ("uneven capsule", sdUnevenCapsule(p2(0, -0.8), 0.75, 0.4, 1.6)),
  ("pentagon", sdPentagon(p2(0, 0), 0.8)),
  ("hexagon", sdHexagon(p2(0, 0), 0.85)),

  ("octagon", sdOctogon(p2(0, 0), 0.85)),
  ("star", sdStar(p2(0, 0), 1.0, 5, 2.5)),
  ("hexagram", sdHexagram(p2(0, 0), 0.5)),
  ("pentagram", sdPentagram(p2(0, 0), 1.0)),
  ("pie", sdPie(p2(0, -0.5), v2(0.5, 0.866025), 1.5)),
  ("cut disk", sdCutDisk(p2(0, -0.15), 1.0, -0.35)),

  ("arc", sdArc(p2(0, -0.5), v2(0.5, 0.866025), 1.0, 0.28)),
  ("ring", sdRing(p2(0, 0.2), v2(0, -1).NormalVec2, 0.8, 0.4)),
  ("vesica", sdVesica(p2(0, 0), 1.0, 0.45)),
  ("moon", sdMoon(p2(-0.15, 0), 0.7, 0.9, 0.6)),
  ("heart", sdHeart(p2(0, -0.45))),
  ("ellipse", sdEllipse(p2(0, 0), v2(1.0, 0.6))),
]

let columns = 6
let spacingX = 3.2
let spacingY = 3.6

for i, (name, shape) in shapes:
  let col = i mod columns
  let row = i div columns
  let x = (col.Float - (columns - 1) / 2) * spacingX
  let y = row.Float * spacingY

  doc.add polygonalSurface3(shape.opExtrusion(0.12).polygonize(resolution = 36)):
    Transform3 translate(v3(x, y, 0))

  doc.add Text name:
    Position2 point2(x, y - 1.5)
    PositionAtCenter
    FontSize 0.38

doc.add Text "2D SDF primitives - Inigo Quilez, \"2D distance functions\"":
  Position2 point2(0, -2.4)
  PositionAtCenter
  FontSize 0.7
