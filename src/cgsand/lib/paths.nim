import pkg/pixie/paths, pkg/vmath
import ./[sandbox, geom2d]
export paths


# todo: add support for Path2 from sigeo instead


proc add*(p: var Path, c: LineSection) =
  p.lineTo(c.startPoint.V2.vec2)
  p.lineTo(c.endPoint.V2.vec2)

proc add*(p: var Path, c: CircleArc) =
  p.arc(c.center.x.float32, c.center.y.float32, c.radius, c.startAngle, c.endAngle, ccw = c.direction == counterclockwise)

proc add*(p: var Path, c: EllipseArc) =
  ## todo

