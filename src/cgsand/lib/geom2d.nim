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


# todo: move to sigeo

proc polyline*(points: varargs[Point2]): Path2 =
  for p in points: result.add p

proc polygon*(points: varargs[Point2]): Path2 =
  for p in points: result.add p
  close result

proc rectPath*(pos: Point2, size: V2): Path2 =
  polygon(pos, pos + v2(size.x, 0), pos + v2(size.x, size.y), pos + v2(0, size.y))

proc rectPath*(x, y: Float, w, h: Float): Path2 =
  polygon(p2(x, y), p2(x + w, y), p2(x + w, y + h), p2(x, y + h))
