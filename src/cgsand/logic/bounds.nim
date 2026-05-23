import std/[options]
import pkg/[vmath]
import pkg/pixie/[fonts]
import ../lib/sandbox except Mat4, mat4, Vec4, Vec3, Vec2, vec2, vec3, vec4
import ../lib/[geom2d, text]


type
  Bounds2* = object
    empty*: bool = true
    min*, max*: Vec2


proc bounds2*(min, max: Vec2): Bounds2 =
  Bounds2(empty: false, min: min, max: max)


proc size*(bounds: Bounds2): Vec2 =
  bounds.max - bounds.min

proc center*(bounds: Bounds2): Vec2 =
  (bounds.min + bounds.max) / 2


proc addPoint*(bounds: var Bounds2, p: Vec2) =
  if bounds.empty:
    bounds = bounds2(p, p)
    return

  bounds.min.x = min(bounds.min.x, p.x)
  bounds.min.y = min(bounds.min.y, p.y)
  bounds.max.x = max(bounds.max.x, p.x)
  bounds.max.y = max(bounds.max.y, p.y)


proc add*(bounds: var Bounds2, other: Bounds2) =
  if other.empty: return
  bounds.addPoint(other.min)
  bounds.addPoint(other.max)


proc expanded*(bounds: var Bounds2, margin: Vec2): Bounds2 =
  if bounds.empty: return bounds
  bounds2(bounds.min - margin, bounds.max + margin)


proc `*`*(transform: Mat4, bounds: Bounds2): Bounds2 =
  if bounds.empty: return bounds

  for p in [
    vec2(bounds.min.x, bounds.min.y),
    vec2(bounds.min.x, bounds.max.y),
    vec2(bounds.max.x, bounds.min.y),
    vec2(bounds.max.x, bounds.max.y),
  ]:
    result.addPoint((transform * vec4(p.x, p.y, 0, 1)).xy)


proc lineBounds*(line: LineSection, thickness: Option[float32]): Bounds2 =
  let a = sandbox.Vec2(line.startPoint).vec2
  let b = sandbox.Vec2(line.endPoint).vec2
  let halfThickness = if thickness.isSome: thickness.get / 2 else: 0'f32

  bounds2(
    vec2(min(a.x, b.x) - halfThickness, min(a.y, b.y) - halfThickness),
    vec2(max(a.x, b.x) + halfThickness, max(a.y, b.y) + halfThickness),
  )


proc pointsBounds*(points: openArray[Point2]): Bounds2 =
  for p in points:
    result.addPoint(sandbox.Vec2(p).vec2)


proc textBounds*(text: string, pos: Position2, posAt: PositionAt, font: Typeface, fontSize: float64, axisYDirection: AxisYDirection = AxisYUp): Bounds2 =
  let arrangement = typeset(font.withSize(fontSize), text)
  let box = arrangement.computeBounds()
  let origin = posAt.factor

  let minX = pos.x.float32 - box.w * origin.x
  let yFactor = if axisYDirection == AxisYUp: 1 - origin.y else: origin.y
  let minY = pos.y.float32 - box.h * yFactor

  bounds2(
    vec2(minX, minY),
    vec2(minX + box.w, minY + box.h),
  )

