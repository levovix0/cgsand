import std/[options]
import pkg/[vmath]
import pkg/pixie/[fonts]
import pkg/pixie/paths
import pkg/sigeo/[curves2d]
import ../lib/[sandbox, geom2d, text]
import ./[document_globals]



proc `*`*(transform: M4, bounds: Bounds2): Bounds2 =
  ## Expands Bounds2 with transformed itself
  if bounds.empty: return bounds

  for p in [
    v2(bounds.min.x, bounds.min.y),
    v2(bounds.min.x, bounds.max.y),
    v2(bounds.max.x, bounds.min.y),
    v2(bounds.max.x, bounds.max.y),
  ]:
    result.add((transform * v4(p.x, p.y, 0, 1)).xy.Point2)


proc lineBounds*(line: LineSection2, thickness: Option[Thickness]): Bounds2 =
  let a = line.startPoint.V2.vec2
  let b = line.endPoint.V2.vec2
  let halfThickness = if thickness.isSome: thickness.get / 2 else: 0'f32

  bounds2(
    p2(min(a.x, b.x) - halfThickness, min(a.y, b.y) - halfThickness),
    p2(max(a.x, b.x) + halfThickness, max(a.y, b.y) + halfThickness),
  )


proc pointsBounds*(points: openArray[Point2]): Bounds2 =
  for p in points:
    result.add(p)


proc textBounds*(text: string, pos: Position2, posAt: PositionAt, font: Typeface, fontSize: float64, axisYDirection: AxisYDirection = AxisYUp): Bounds2 =
  let arrangement = typeset(font.withSize(fontSize), text)
  let box = arrangement.computeBounds()
  let origin = posAt.factor

  let minX = pos.x.float32 - box.w * origin.x
  let yFactor = if axisYDirection == AxisYUp: 1 - origin.y else: origin.y
  let minY = pos.y.float32 - box.h * yFactor

  bounds2(
    p2(minX, minY),
    p2(minX + box.w, minY + box.h),
  )


proc worldBoundsAlongAxis*(
  w: World,
  axis: V3,
  globals: DocumentGlobals,
  filter: proc(eid: EntityId): bool = proc(eid: EntityId): bool = true,
): (float32, float32) =
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
    for c in [b.min, p2(b.max.x, b.min.y), p2(b.min.x, b.max.y), b.max]:
      update(c.x * axis.x + c.y * axis.y)

  w.forEach (EntityId, line: LineSection2, thickness: opt Thickness, not NoBounds):
    if not filter(the EntityId): continue
    addBounds2(lineBounds(line, if has Thickness: some thickness else: none Thickness))

  w.forEach (EntityId, curve: CircleArc2, count: PointCount||20, not NoBounds):
    if not filter(the EntityId): continue
    for pt in curve.points(count):
      let v = pt.V2.vec2
      update(v.x * axis.x + v.y * axis.y)

  w.forEach (EntityId, curve: EllipseArc2, count: PointCount||32, not NoBounds):
    if not filter(the EntityId): continue
    for pt in curve.points(count):
      let v = pt.V2.vec2
      update(v.x * axis.x + v.y * axis.y)

  w.forEach (EntityId, curve: Curve2, transform3: Transform3||m4(), not NoBounds):
    if not filter(the EntityId): continue
    addBounds2(transform3 * bounds(curve))

  w.forEach (EntityId, curve: OwnedCurve2, transform3: Transform3||m4(), not NoBounds):
    if not filter(the EntityId): continue
    addBounds2(transform3 * bounds(cast[Curve2](curve)))

  w.forEach (EntityId, path: Path2, transform3: Transform3||m4(), not NoBounds):
    if not filter(the EntityId): continue
    addBounds2(transform3 * bounds(path.toCurve2))

  w.forEach (EntityId, path: Path, transform3: Transform3||m4(), not NoBounds):
    if not filter(the EntityId): continue
    try:
      let r = path.computeBounds()
      addBounds2(transform3 * bounds2(p2(float64(r.x), float64(r.y)), p2(float64(r.x + r.w), float64(r.y + r.h))))
    except: discard

  w.forEach (EntityId, surface: PolygonalSurface3, transform3: Transform3||m4(), not NoBounds):
    if not filter(the EntityId): continue
    if surface == nil: continue
    for pt in surface[].points:
      let p = (transform3 * v4(pt.x, pt.y, pt.z, 1)).xyz
      update(p.x * axis.x + p.y * axis.y + p.z * axis.z)

  w.forEach (
    EntityId, text: Text, pos: Position2||p2(),
    posAt: PositionAt||PositionAtTopLeft, font: Typeface||globals.font, size: FontSize||globals.fontSize, not NoBounds
  ):
    if not filter(the EntityId): continue
    addBounds2(textBounds(text, pos, posAt, font, size, globals.axisYDirection))

  w.forEach (EntityId, sub: SubWorld, pos: Position2||p2(), transform3: Transform3||m4(), not NoBounds):
    if not filter(the EntityId): continue
    if sub == nil: continue
    let m = translate(v3(pos.x, pos.y, 0)) * transform3
    # Transform outer axis to inner space: inner_axis[j] = dot(column j of m, outer axis)
    let innerAxis = v3(
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
