import sandbox, geom2d
import pkg/[bumpy]
import ../shafts/[shafts]
import ./[bearings {.all.}, caps, seal, drawingGlobals]


type
  ShaftEx* = object
    shaft*: Shaft
    sketch*: World
    gear*: ShaftSegment
    pos*: Point2
    entity*: EntityId
    bearing*: BearingParams
    seal*: SealGeomParams
    caps*: array[2, CapGeomParams]
    bearingEnt*: array[2, EntityId]
    capEnt*: array[2, EntityId]
    sealEnt*: EntityId


var mmScale = 1e-3
proc mm*(m: float): float = m * mmScale


proc drawRects(doc: World) =
  doc.forEach (r: Rect):
    let x1 = r.x.Float
    let x2 = (r.x + r.w).Float
    let y1 = r.y.Float
    let y2 = (r.y + r.h).Float
    doc.add lineSection(point2(x1, y1), point2(x2, y1))
    doc.add lineSection(point2(x2, y1), point2(x2, y2))
    doc.add lineSection(point2(x2, y2), point2(x1, y2))
    doc.add lineSection(point2(x1, y2), point2(x1, y1))


proc sketch*(shaft: Shaft, dimensions: World = nil): World =
  result = World()
  withDocument result:
    let globals = doc.spawn()
    setDrawingGlobals(globals)
    draw(shaft, dimensions = dimensions, scale = 1)


proc segmentX*(shaft: Shaft, segmentI: int, p = PositionAtLeft): float =
  result = 0
  for i, seg in shaft.segments:
    if i == segmentI:
      case p
      of PositionAtLeft: return result
      of PositionAtCenter: return result + seg.length/2
      of PositionAtRight: return result + seg.length
      else: return result
    result += seg.length

proc segmentX*(shaft: Shaft, segment: ShaftSegment): float =
  result = 0
  for seg in shaft.segments:
    if seg == segment:
      return
    result += seg.length


proc gearPitchDiameter*(x: ShaftEx): float =
  x.gear.section.gear.pitchDiameter


proc ceil(x: float, step: float): float =
  ceil(x / step) * step



mainModule:
  var fastShaft = ShaftEx()
  var slowShaft = ShaftEx()

  doc[globals, CanvasSettings].margin = v2(10.mm, 10.mm)

  fastShaft.gear = gearSegment(l = 44.875.mm, z = 23, modulo = 2.75.mm)
  slowShaft.gear = gearSegment(l = 39.875.mm, z = 93, modulo = 2.75.mm)

  # parameters choosen for the middle series  # todo: autocompute
  fastShaft.bearing = BearingDesc(d: 45.mm, D: 100.mm, B: 25.mm, r: 2.5.mm)
  slowShaft.bearing = BearingDesc(d: 55.mm, D: 120.mm, B: 29.mm, r: 3.mm)


  let axial_distance = fastShaft.gearPitchDiameter/2 + slowShaft.gearPitchDiameter/2
  let wall_thickness: float =
    if axial_distance <= 80: 6.mm
    elif axial_distance <= 180: 8.mm
    elif axial_distance <= 280: 10.mm
    elif axial_distance <= 355: 12.mm
    elif axial_distance <= 450: 14.mm
    else: 16.mm
  
  let padding = (wall_thickness * 1.5).ceil(5.mm)
  let bead = padding
  let slowShaftBead = (fastShaft.gear.length - slowShaft.gear.length)/2 + bead

  let bearingOnShaftEndPadding = 5.mm


  let bevel = ShaftConjunction(kind: Bevel, radius: 1.6.mm)
  let fillet = ShaftConjunction(kind: Fillet, radius: 2.mm)
  fastShaft.shaft = Shaft(
    segments: @[
      cylindricSegment(d = 40.mm, l = 82.mm, left = bevel, right = fillet),
      cylindricSegment(d = 45.mm, l = 87.mm),
      cylindricSegment(d = 53.mm, l = bead),  # ! was extended so bearings has a detent
      fastShaft.gear,
      cylindricSegment(d = 53.mm, l = bead),  # ! was extended so bearings has a detent
      cylindricSegment(d = 45.mm, l = fastShaft.bearing.B + 5.mm, right = bevel),
    ]
  )

  slowShaft.shaft = Shaft(
    segments: @[
      cylindricSegment(d = 48.mm, l = 82.mm, left = bevel, right = fillet),
      cylindricSegment(d = 55.mm, l = 79.mm),
      cylindricSegment(d = 70.mm, l = slowShaftBead),
      slowShaft.gear,
      cylindricSegment(d = 55.mm, l = slowShaftBead + slowShaft.bearing.B + bearingOnShaftEndPadding, right = bevel),
    ]
  )

  
  # parameters choosen from table  # todo: autocompute
  fastShaft.seal = SealDesc(d: fastShaft.shaft.segments[1].section.circle.radius*2)
  slowShaft.seal = SealDesc(d: slowShaft.shaft.segments[^1].section.circle.radius*2)


  # parameters choosen from table  # todo: autocompute
  fastShaft.caps[0] = CapDesc(
    D: fastShaft.bearing.D, h: 20.mm,
    shaft_d: fastShaft.shaft.segments[^1].section.circle.radius*2,
  )
  fastShaft.caps[1] = CapDesc(
    D: fastShaft.bearing.D, h: 20.mm,
    # shaft_d: fastShaft.shaft.segments[1].section.circle.radius*2,
    hole: true, seal: fastShaft.seal,
  )

  slowShaft.caps[0] = CapDesc(
    D: slowShaft.bearing.D, h: 20.mm - (slowShaft.bearing.B - fastShaft.bearing.B).ceil(1.mm),
    # shaft_d: slowShaft.shaft.segments[^1].section.circle.radius*2,
    hole: true, seal: slowShaft.seal,
  )
  slowShaft.caps[1] = CapDesc(
    D: slowShaft.bearing.D, h: 20.mm - (slowShaft.bearing.B - fastShaft.bearing.B).ceil(1.mm),
    shaft_d: slowShaft.shaft.segments[1].section.circle.radius*2,
  )

  let capCutoff = max(0, fastShaft.caps[0].D2/2 + slowShaft.caps[0].D2/2 + 4.mm - axial_distance)/2  # ! gap must be 2.mm .. 4.mm
  fastShaft.caps[0].cutoff = (capCutoff, 0.mm)
  fastShaft.caps[1].cutoff = (0.mm, capCutoff)
  slowShaft.caps[0].cutoff = (0.mm, capCutoff)
  slowShaft.caps[1].cutoff = (capCutoff, 0.mm)


  fastShaft.sketch = sketch fastShaft.shaft
  slowShaft.sketch = sketch slowShaft.shaft

  fastShaft.pos = point2(0, 0)
  slowShaft.pos = point2(-axial_distance, 0)



  # --- shafts ---

  fastShaft.entity = doc.spawn SubWorld fastShaft.sketch:
    Position2 fastShaft.pos
    Transform3 (rotateZ(Pi/2) * translate(v3(-fastShaft.shaft.segmentX(fastShaft.gear) - fastShaft.gear.length/2, 0, 0)))

  slowShaft.entity = doc.spawn SubWorld slowShaft.sketch:
    Position2 slowShaft.pos
    Transform3 (rotateZ(-Pi/2) * translate(v3(-slowShaft.shaft.segmentX(slowShaft.gear) - slowShaft.gear.length/2, 0, 0)))



  # --- bearings ---
  
  fastShaft.bearingEnt[0] = doc.spawn SubWorld fastShaft.bearing.sketch(hideBackLines = true):
    Position2 fastShaft.pos + v2(0, fastShaft.shaft.segmentX(1, PositionAtRight) - fastShaft.bearing.B/2 - fastShaft.shaft.segmentX(3, PositionAtCenter))
    Transform3 rotateZ(-Pi/2)

  fastShaft.bearingEnt[1] = doc.spawn SubWorld fastShaft.bearing.sketch(hideBackLines = true):
    Position2 fastShaft.pos + v2(0, fastShaft.shaft.segmentX(5, PositionAtLeft) + fastShaft.bearing.B/2 - fastShaft.shaft.segmentX(3, PositionAtCenter))
    Transform3 rotateZ(-Pi/2)

  
  slowShaft.bearingEnt[0] = doc.spawn SubWorld slowShaft.bearing.sketch(hideBackLines = true):
    Position2 slowShaft.pos + v2(0, fastShaft.shaft.segmentX(1, PositionAtRight) - slowShaft.bearing.B/2 - fastShaft.shaft.segmentX(3, PositionAtCenter))
    Transform3 rotateZ(-Pi/2)

  slowShaft.bearingEnt[1] = doc.spawn SubWorld slowShaft.bearing.sketch(hideBackLines = true):
    Position2 slowShaft.pos + v2(0, fastShaft.shaft.segmentX(5, PositionAtLeft) + slowShaft.bearing.B/2 - fastShaft.shaft.segmentX(3, PositionAtCenter))
    Transform3 rotateZ(-Pi/2)
  
  let shaftsBounds = doc.bounds(fastShaft.bearingEnt[0]) + doc.bounds(slowShaft.entity)


  # --- caps ---

  fastShaft.capEnt[0] = doc.spawn SubWorld fastShaft.caps[0].sketch(hideBackLines = true):
    Position2 fastShaft.pos + v2(0,
      + fastShaft.shaft.segmentX(5, PositionAtRight) +
      - fastShaft.shaft.segmentX(3, PositionAtCenter) +
      + fastShaft.caps[0].bounds.size.x +
      - bearingOnShaftEndPadding +
    0)
    Transform3 rotateZ(-Pi/2)

  fastShaft.capEnt[1] = doc.spawn SubWorld fastShaft.caps[1].sketch(hideBackLines = true):
    Position2 fastShaft.pos + v2(0,
      + fastShaft.shaft.segmentX(1, PositionAtRight) +
      - fastShaft.shaft.segmentX(3, PositionAtCenter) +
      - fastShaft.caps[1].bounds.size.x +
      - fastShaft.bearing.B +
    0)
    Transform3 rotateZ(Pi/2)


  slowShaft.capEnt[0] = doc.spawn SubWorld slowShaft.caps[0].sketch(hideBackLines = true):
    Position2 slowShaft.pos + v2(0,
      + slowShaft.shaft.segmentX(4, PositionAtRight) +
      - slowShaft.shaft.segmentX(3, PositionAtCenter) +
      + slowShaft.caps[0].bounds.size.x +
      - bearingOnShaftEndPadding +
    0)
    Transform3 rotateZ(-Pi/2)

  slowShaft.capEnt[1] = doc.spawn SubWorld slowShaft.caps[1].sketch(hideBackLines = true):
    Position2 slowShaft.pos + v2(0,
      + slowShaft.shaft.segmentX(1, PositionAtRight) +
      - slowShaft.shaft.segmentX(3, PositionAtCenter) +
      - slowShaft.caps[1].bounds.size.x +
      - slowShaft.bearing.B +
    0)
    Transform3 rotateZ(Pi/2)



  # --- seals ---

  fastShaft.sealEnt = doc.spawn SubWorld fastShaft.seal.sketch(hideBackLines = true):
    Position2 fastShaft.pos + v2(0,
      + fastShaft.shaft.segmentX(1, PositionAtRight) +
      - fastShaft.shaft.segmentX(3, PositionAtCenter) +
      - fastShaft.caps[1].bounds.size.x +
      + fastShaft.caps[1].s +
      - fastShaft.bearing.B +
    0)
    Transform3 rotateZ(Pi/2)

  slowShaft.sealEnt = doc.spawn SubWorld slowShaft.seal.sketch(hideBackLines = true):
    Position2 slowShaft.pos + v2(0,
      - slowShaft.shaft.segmentX(2, PositionAtLeft) +
      + slowShaft.shaft.segmentX(3, PositionAtCenter) +
      + slowShaft.caps[0].bounds.size.x +
      - slowShaft.caps[0].s +
      + slowShaft.bearing.B +
    0)
    Transform3 rotateZ(-Pi/2)



  # --- box ---

  let innerBox = roundRect2geom(point2(shaftsBounds.center.x, 0), v2(shaftsBounds.size.x + padding*2, fastShaft.gear.length + padding*2), 1.mm)
  
  # todo: automatically clip
  for i, line in innerBox.lines:
    if i notin {RoundRect2Geom_LineIndex.top, bottom}:
      doc.add line, mainLine
  for arc in innerBox.arcs:
    doc.add arc, mainLine

  for line in [innerBox.lines[top], innerBox.lines[bottom]]:
    doc.add line.cut(
      0,
      line.paramAtPoint(p2(doc.bounds(slowShaft.bearingEnt[0]).min.x + slowShaft.bearing.r, 0)),
    ), mainLine
    doc.add line.cut(
      line.paramAtPoint(p2(doc.bounds(slowShaft.bearingEnt[0]).max.x - slowShaft.bearing.r, 0)),
      line.paramAtPoint(p2(doc.bounds(fastShaft.bearingEnt[0]).min.x + fastShaft.bearing.r, 0)),
    ), mainLine
    doc.add line.cut(
      line.paramAtPoint(p2(doc.bounds(fastShaft.bearingEnt[0]).max.x - fastShaft.bearing.r, 0)),
      1,
    ), mainLine

  let outerBox = roundRect2geom(point2(shaftsBounds.center.x, 0), v2(shaftsBounds.size.x + padding*2 + wall_thickness*2, fastShaft.gear.length + padding*2 + wall_thickness*2), 1.mm + wall_thickness)

  # todo: automatically clip
  for i, line in outerBox.lines:
    if i notin {RoundRect2Geom_LineIndex.top, bottom}:
      doc.add line, hiddenLine
  for arc in outerBox.arcs:
    doc.add arc, hiddenLine

  for line in [outerBox.lines[top], outerBox.lines[bottom]]:
    doc.add line.cut(
      0,
      line.paramAtPoint(p2(doc.bounds(slowShaft.bearingEnt[0]).min.x, 0)),
    ), hiddenLine
    doc.add line.cut(
      line.paramAtPoint(p2(doc.bounds(slowShaft.bearingEnt[0]).max.x, 0)),
      line.paramAtPoint(p2(doc.bounds(fastShaft.bearingEnt[0]).min.x, 0)),
    ), hiddenLine
    doc.add line.cut(
      line.paramAtPoint(p2(doc.bounds(fastShaft.bearingEnt[0]).max.x, 0)),
      1,
    ), hiddenLine
    


  doc.drawRects()


