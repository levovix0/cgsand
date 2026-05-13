import ./sandbox
import pkg/sigeo/curves2d
export curves2d

type PointCount* = int

proc circle*(center: Point2, radius: float64): CircleArc =
  result = CircleArc(
    center: center,
    radius: radius,
    startAngle: 0,
    endAngle: 0,
    direction: counterclockwise
  )

proc points*(arc: CircleArc, count: int = 20): seq[Point2] =
  for t in 0..count:
    result.add(arc.pointAtParam(t / count))

proc arc*(
  center: Point2,
  radius: float64,
  p1, p2: Point2,
  ccw: bool = true,  ## true if counterclockwise, false if clockwise
): CircleArc =
  result = CircleArc(
    center: center,
    radius: radius,
    startAngle: arctan2(p1.x - center.x, p1.y - center.y),
    endAngle: arctan2(p2.x - center.x, p2.y - center.y),
    direction: (if ccw: counterclockwise else: clockwise)
  )