import sandbox
import sigeo/sdf


# A mounting bracket made from a 2D sketch:
# a closed polyline contour (elongated hexagonal plate) rounded with `opRound`,
# a capsule slot and 4 mounting holes subtracted, then extruded thicker.


# эскиз внешнего контура: замкнутая полилиния из 6 точек
let outerPts = [
  p2(-5, -2.4), p2(0, -3.4), p2(5, -2.4),
  p2(5, 2.4), p2(0, 3.4), p2(-5, 2.4),
]
let outer = sdPolygon(outerPts).opRound(0.4)

# внутренние контуры: паз-капсула и 4 крепёжных отверстия
let slot = sdCapsule(p2(-1.6, 0), p2(1.6, 0), 0.65)
let mounting = sdCircle(p2(3.3, 1.4), 0.5).opSymX.opSymY

let bracket = outer
  .opSubtraction(slot)
  .opSubtraction(mounting)
  .opExtrusion(0.2)

doc.add polygonalSurface3(bracket.polygonize(step = 0.1)):
  Transform3 translate(v3(0, 0.4, 0))

doc.add Text "bracket: polygon sketch - subtract slot and mounting holes - extrude":
  Position2 point2(0, -5.0)
  PositionAtCenter
  FontSize 0.6
