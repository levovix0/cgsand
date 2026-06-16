import ./sandbox
import pkg/sigeo/curves2d
export curves2d

type PointCount* = int


proc arc*(
  center: Point2,
  radius: float64,
  p1, p2: Point2,
  direction: AngleDirection = counterclockwise,
): CircleArc2 =
  result = CircleArc2(
    center: center,
    radius: radius,
    startAngle: arctan2(p1.x - center.x, p1.y - center.y),
    endAngle: arctan2(p2.x - center.x, p2.y - center.y),
    direction: direction,
  )

proc arc*(
  center: Point2,
  radius: float64,
  angle: Slice[float],
  direction: AngleDirection = counterclockwise,
): CircleArc2 =
  result = CircleArc2(
    center: center,
    radius: radius,
    startAngle: angle.a,
    endAngle: angle.b,
    direction: direction,
  )
