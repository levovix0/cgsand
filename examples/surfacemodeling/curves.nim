import sandbox, geom2d
import sigeo/surfaces

type
  SinSurface = object

proc pointAt(this: SinSurface, uv: Point2): Point3 =
  let t = uv.x
  let a = uv.y*0.5*Pi
  p3(sin(4 * Pi * t), cos(4 * Pi * t), 2 * t) +
  v3(cos(a) * sin(4 * Pi * t), cos(a) * cos(4 * Pi * t), sin(a)) / 5

Surface3.implementInterfaceFor(SinSurface)


let sketch = @[
  # line(p2(-0.5, -1), p2(0.5, -1)).toOwnedCurve2,
  # line(p2(0.5, -1), p2(0.5, 1)).toOwnedCurve2,
  # line(p2(0.5, 1), p2(-0.5, 1)).toOwnedCurve2,
  # line(p2(-0.5, 1), p2(-0.5, -1)).toOwnedCurve2,
  circle(p2(), 1).toOwnedCurve2,
  # circle(p2(), 0.4).toOwnedCurve2,
]
let model = PolygonalSurface3 SinSurface().makeGrid(sketch.view, resolution = 64*4)

doc.add model
