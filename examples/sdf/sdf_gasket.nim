import sandbox
import sigeo/sdf


# A gasket made from a 2D sketch:
# a closed polyline contour (octagon), rounded with `opRound`,
# with the bore and 4 bolt holes subtracted, then extruded into a plate.


# outline sketch: a closed polyline consisting of 8 points
var outerPts: seq[Point2] = @[]
for i in 0..<8:
  let a = Pi/8 + i.Float * Pi/4
  outerPts.add (v2(a.cos, a.sin) * 5.0).toPoint
let outer = sdPolygon(outerPts).opRound(0.35)

# internal contours: central hole and 4 bolt holes
# (one hole + two symmetries yield 4 holes)
let bore = sdCircle(p2(0, 0), 1.6)
let bolts = sdCircle(p2(3.2, 1.6), 0.45).opSymX.opSymY

let gasket = outer
  .opSubtraction(bore)
  .opSubtraction(bolts)
  .opExtrusion(0.7)

doc.add polygonalSurface3(gasket.polygonize(step = 0.09)):
  Transform3 translate(v3(0, 0.6, 0))
