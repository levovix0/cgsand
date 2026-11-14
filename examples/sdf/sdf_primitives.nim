import sandbox
import sigeo/sdf


# SDF primitives from Inigo Quilez's article "Distance functions",
# polygonized into triangle meshes for rendering


let shapes: seq[tuple[name: string, sdf: Sdf3]] = @[
  ("sphere", sdSphere(p3(0, 1, 0), 1)),
  ("box", sdBox(p3(0, 1, 0), v3(0.75, 0.75, 0.75))),
  ("round box", sdRoundBox(p3(0, 1, 0), v3(0.75, 0.75, 0.75), 0.3)),
  ("box frame", sdBoxFrame(p3(0, 1, 0), v3(0.75, 0.75, 0.75), 0.22)),
  ("torus", sdTorus(p3(0, 1, 0), 0.65, 0.3)),
  ("capsule", sdVerticalCapsule(p3(0, 1, 0), 0.7, 0.45)),
  ("cylinder", sdCappedCylinder(p3(0, 1, 0), 0.7, 0.9)),
  ("cone", sdCone(p3(0, 1.7, 0), v2(0.45, 0.893025), 1.7)),
  ("octahedron", sdOctahedron(p3(0, 1, 0), 1)),
  ("hex prism", sdHexPrism(p3(0, 1, 0), 0.8, 0.8)),
  ("pyramid", sdPyramid(p3(0, 0, 0), 1).opScale(2.2)),
  ("ellipsoid", sdEllipsoid(p3(0, 1, 0), v3(1, 0.6, 0.75))),
]

let columns = 6
let spacingX = 2.9
let spacingY = 4.6

for i, (name, shape) in shapes:
  let col = i mod columns
  let row = i div columns
  let x = (col.Float - (columns - 1) / 2) * spacingX
  let y = row.Float * spacingY

  doc.add polygonalSurface3(shape.polygonize(resolution = 48)):
    Transform3 translate(v3(x, y, 0))

  doc.add Text name:
    Position2 point2(x, y - 0.7)
    PositionAtCenter
    FontSize 0.45

doc.add Text "SDF primitives - Inigo Quilez, \"Distance functions\"":
  Position2 point2(0, -1.6)
  PositionAtCenter
  FontSize 0.7
