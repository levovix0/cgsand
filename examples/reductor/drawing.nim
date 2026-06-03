import sandbox, geom2d
import pkg/[bumpy]
import ../shafts/[shafts]


type
  ShaftEx* = object
    shaft*: Shaft
    sketch*: World
    gear*: ShaftSegment
    pos*: Point2


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
    setShaftsGlobals(globals)
    draw(shaft, dimensions = dimensions, scale = 1)

proc segmentX*(shaft: Shaft, segment: ShaftSegment): float =
  result = 0
  for seg in shaft.segments:
    if seg == segment:
      return
    result += seg.length


proc gearPitchDiameter*(x: ShaftEx): float =
  x.gear.section.gear.pitchDiameter



mainModule:
  var fastShaft = ShaftEx()
  var slowShaft = ShaftEx()

  doc[globals, CanvasSettings].margin = vec2(10.mm, 10.mm)

  fastShaft.gear = gearSegment(l = 44.875.mm, z = 23, modulo = 2.75.mm)
  slowShaft.gear = gearSegment(l = 39.875.mm, z = 93, modulo = 2.75.mm)

  let bead = 22.5.mm  # длинна буртика
  let bearingLength = 25.mm  # B подшипника
  let slowShaftBead = (fastShaft.gear.length - slowShaft.gear.length)/2 + bead

  let bevel = ShaftConjunction(kind: Bevel, radius: 1.6.mm)
  let fillet = ShaftConjunction(kind: Fillet, radius: 2.mm)
  fastShaft.shaft = Shaft(
    segments: @[
      cylindricSegment(d = 40.mm, l = 82.mm, left = bevel, right = fillet),
      cylindricSegment(d = 45.mm, l = 87.mm),
      cylindricSegment(d = 50.mm, l = bead),
      fastShaft.gear,
      cylindricSegment(d = 50.mm, l = bead),
      cylindricSegment(d = 45.mm, l = bearingLength + 5.mm, right = bevel),
    ]
  )

  slowShaft.shaft = Shaft(
    segments: @[
      cylindricSegment(d = 48.mm, l = 82.mm, left = bevel, right = fillet),
      cylindricSegment(d = 55.mm, l = 79.mm),
      cylindricSegment(d = 70.mm, l = slowShaftBead),
      slowShaft.gear,
      cylindricSegment(d = 55.mm, l = slowShaftBead + bearingLength + 5.mm, right = bevel),
    ]
  )

  fastShaft.sketch = sketch fastShaft.shaft
  slowShaft.sketch = sketch slowShaft.shaft

  fastShaft.pos = point2(0, 0)
  slowShaft.pos = point2(-(fastShaft.gearPitchDiameter/2 + slowShaft.gearPitchDiameter/2), 0)

  # doc.add rect()

  doc.add SubWorld fastShaft.sketch:
    Position2 fastShaft.pos
    Transform3 (rotateZ(Pi/2) * translate(vec3(-fastShaft.shaft.segmentX(fastShaft.gear) - fastShaft.gear.length/2, 0, 0)))

  doc.add SubWorld slowShaft.sketch:
    Position2 slowShaft.pos
    Transform3 (rotateZ(-Pi/2) * translate(vec3(-slowShaft.shaft.segmentX(slowShaft.gear) - slowShaft.gear.length/2, 0, 0)))

  doc.drawRects()


