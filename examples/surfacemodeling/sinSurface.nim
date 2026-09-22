import sandbox, geom2d
import sigeo/surfaces

type
  SinSurface = object

proc pointAt(this: SinSurface, uv: Point2): Point3 =
  p3(uv.x, uv.y, 4 * sin(uv.x / 20 * 2*Pi))

Surface3.implementInterfaceFor(SinSurface)


let sketch = @[
  circle(p2(), 20).toOwnedCurve2,
  circle(p2(4, 8), 5).toOwnedCurve2,
]
let model = PolygonalSurface3 SinSurface().makeGrid(sketch.view, resolution = 64)

doc.add model
