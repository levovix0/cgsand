import std/[options]
import pkg/[vmath]
import pkg/pixie/[fonts]
import ../lib/sandbox except Mat4, mat4, Vec4, Vec3, Vec2, vec2, vec3, vec4
import ../lib/[geom2d, text]
import ./[document_globals]


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


proc worldBoundsAlongAxis*(w: World, axis: Vec3, globals: DocumentGlobals): (float32, float32) =
  ## Returns the (min, max) projection of all world content onto the given axis vector.
  var minP, maxP: float32
  var found = false

  proc update(p: float32) =
    if not found:
      minP = p; maxP = p; found = true
    else:
      if p < minP: minP = p
      elif p > maxP: maxP = p

  proc addBounds2(b: Bounds2) =
    if b.empty: return
    for c in [b.min, vec2(b.max.x, b.min.y), vec2(b.min.x, b.max.y), b.max]:
      update(c.x * axis.x + c.y * axis.y)

  w.forEach (line: LineSection, thickness: opt Thickness):
    addBounds2(lineBounds(line, if has Thickness: some thickness else: none Thickness))

  w.forEach (curve: CircleArc, count: PointCount||20):
    for pt in curve.points(count):
      let v = sandbox.Vec2(pt).vec2
      update(v.x * axis.x + v.y * axis.y)

  w.forEach (arc: EllipseArc, count: PointCount||32):
    for pt in arc.points(count):
      let v = sandbox.Vec2(pt).vec2
      update(v.x * axis.x + v.y * axis.y)

  w.forEach (text: Text, pos: Position2, posAt: PositionAt||PositionAtTopLeft, font: Typeface||globals.font, size: FontSize||globals.fontSize):
    addBounds2(textBounds(text, pos, posAt, font, size, globals.axisYDirection))

  w.forEach (sub: SubWorld, pos: Position2, transform3: Transform3||dmat4()):
    if sub == nil: continue
    let m = translate(vec3(pos.x, pos.y, 0)) * mat4(transform3)
    # Transform outer axis to inner space: inner_axis[j] = dot(column j of m, outer axis)
    let innerAxis = vec3(
      m[0].x*axis.x + m[0].y*axis.y + m[0].z*axis.z,
      m[1].x*axis.x + m[1].y*axis.y + m[1].z*axis.z,
      m[2].x*axis.x + m[2].y*axis.y + m[2].z*axis.z,
    )
    let offset = m[3].x*axis.x + m[3].y*axis.y + m[3].z*axis.z
    let innerGlobals = sub.documentGlobals
    let (innerMin, innerMax) = sub.worldBoundsAlongAxis(innerAxis, innerGlobals)
    if innerMin <= innerMax:
      update(innerMin + offset)
      update(innerMax + offset)

  if found: (minP, maxP) else: (0'f32, 0'f32)
