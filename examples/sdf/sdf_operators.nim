import sandbox
import sigeo/sdf


# SDF combination operators: boolean and smooth operations, onion, displacement,
# twist. Shapes made from a single distance function are translated
# into polygons with `polygonize`.


let columns = 3
let spacingX = 4.4
let spacingY = 5.8


proc place(name: string, col, row: int, mesh: Grid3) =
  let x = (col.Float - (columns - 1) / 2) * spacingX
  let y = row.Float * spacingY
  doc.add polygonalSurface3(mesh):
    Transform3 translate(v3(x, y, 0))
  doc.add Text name:
    Position2 point2(x, y - 1.5)
    PositionAtCenter
    FontSize 0.45


# smooth union: three spheres blended into one blob
place "smooth union", 0, 0:
  sdSphere(p3(-0.55, 0.9, 0), 0.75)
    .opSmoothUnion(sdSphere(p3(0.55, 0.9, 0.2), 0.7), 0.4)
    .opSmoothUnion(sdSphere(p3(0, 1.8, -0.25), 0.65), 0.4)
    .polygonize(step = 0.035)

# smooth subtraction: a box with a spherical dent
place "smooth subtraction", 1, 0:
  sdRoundBox(p3(0, 0.8, 0), v3(0.9, 0.55, 0.9), 0.2)
    .opSmoothSubtraction(sdSphere(p3(0, 1.9, 0), 0.75), 0.25)
    .polygonize(step = 0.035)

# smooth intersection: a pebble
place "smooth intersection", 2, 0:
  sdSphere(p3(0, 0.9, 0), 1)
    .opSmoothIntersection(sdBox(p3(0, 0.9, 0), v3(0.75, 0.55, 0.75)), 0.25)
    .polygonize(step = 0.035)

# onion: a shell with a given thickness
place "onion", 0, 1:
  sdBox(p3(0, 1, 0), v3(0.75, 0.75, 0.75))
    .opOnion(0.22)
    .polygonize(step = 0.03)

# displacement: a sphere with a sine pattern (bounds must be given explicitly,
# because the displacement changes the shape beyond the original bounds)
place "displacement", 1, 1:
  sdSphere(p3(0, 1, 0), 0.8).opDisplace(proc(p: Point3): Float =
    0.1 * (p.x * 8).sin * (p.y * 8).sin * (p.z * 8).sin
  ).polygonize(bounds3(p3(-1.1, -0.1, -1.1), p3(1.1, 2.1, 1.1)), step = 0.025)

# twist: a twisted plate (bounds must be given explicitly,
# because `opTwist` deforms the space and the bounds are no longer known)
place "twist", 2, 1:
  sdBox(p3(0, 1, 0), v3(0.85, 0.3, 0.3)).opTwist(2.2)
    .polygonize(bounds3(p3(-1.6, 0, -1.6), p3(1.6, 2, 1.6)), step = 0.025)

doc.add Text "SDF operators":
  Position2 point2(0, -2.7)
  PositionAtCenter
  FontSize 0.7
