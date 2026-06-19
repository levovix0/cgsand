import sandbox, geom2d, techDraw
import pkg/[bumpy]
import ../shafts/[shafts, gears]
import ./[bearings {.all.}, covers, seal, bushing]
when isMainModule: import tools/measurement


type
  ShaftEx* = object
    shaft*: Shaft
    sketch*: World
    gear*: ShaftSegment
    pos*: Point2
    exitDiameter*: float

    entity*: EntityId
    bearing*: BearingParams
    seal*: SealGeomParams
    covers*: array[2, CoverGeomParams]
    bearingEnt*: array[2, EntityId]
    coverEnt*: array[2, EntityId]
    sealEnt*: EntityId


var mmScale = 1e-3
proc mm*(m: float): float = m * mmScale


proc drawRects(doc: World) =
  doc.forEach (r: Rect):
    let x1 = r.x.Float
    let x2 = (r.x + r.w).Float
    let y1 = r.y.Float
    let y2 = (r.y + r.h).Float
    doc.add line(point2(x1, y1), point2(x2, y1))
    doc.add line(point2(x2, y1), point2(x2, y2))
    doc.add line(point2(x2, y2), point2(x1, y2))
    doc.add line(point2(x1, y2), point2(x1, y1))


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


proc secondDiameter*(shaft: ShaftEx): float =
  (shaft.exitDiameter + 5.mm).ceil(5.mm)
  
proc thirdDiameter*(shaft: ShaftEx): float =
  (shaft.secondDiameter + 5.mm).ceil(5.mm)


mainModule:
  var fastShaft = ShaftEx(exitDiameter: 40.mm)
  var slowShaft = ShaftEx(exitDiameter: 48.mm)

  doc[globals, CanvasSettings].margin = v2(10.mm, 10.mm)

  fastShaft.gear = gearSegment(l = 44.875.mm, z = 23, modulo = 2.75.mm, reverseHatching = true)
  slowShaft.gear = gearSegment(l = 39.875.mm, z = 93, modulo = 2.75.mm, shaft_d = slowShaft.thirdDiameter)

  # parameters choosen for the middle series  # todo: autocompute
  fastShaft.bearing = BearingDesc(d: 45.mm, D: 100.mm, B: 25.mm, r: 2.5.mm)
  slowShaft.bearing = BearingDesc(d: 55.mm, D: 120.mm, B: 29.mm, r: 3.mm)


  let axial_distance = fastShaft.gearPitchDiameter/2 + slowShaft.gearPitchDiameter/2
  var wall_thickness: float =
    if axial_distance <= 80.mm: 6.mm
    elif axial_distance <= 180.mm: 8.mm
    elif axial_distance <= 280.mm: 10.mm
    elif axial_distance <= 355.mm: 12.mm
    elif axial_distance <= 450.mm: 14.mm
    else: 16.mm
  
  wall_thickness += 2.mm  # ! was extended because covers are too big
  
  let padding = (wall_thickness * 1.5).ceil(5.mm)
  let bead = padding
  let slowShaftBead = (fastShaft.gear.length - slowShaft.gear.length)/2 + bead

  let bearingOnShaftEndPadding = 5.mm

  
  fastShaft.seal = SealDesc(d: fastShaft.secondDiameter)
  slowShaft.seal = SealDesc(d: slowShaft.secondDiameter)


  let bushing = BushingDesc(d: slowShaft.secondDiameter, H: slowShaftBead, reversedHatching: true)


  # height choosen from table  # todo: autocompute
  fastShaft.covers[0] = CoverDesc(
    D: fastShaft.bearing.D,
    h: 20.mm,
    shaft_d: fastShaft.secondDiameter,
    reverseHatching: true,
  )
  fastShaft.covers[1] = CoverDesc(
    D: fastShaft.bearing.D,
    h: 20.mm,
    # shaft_d: fastShaft.secondDiameter,
    hole: true, seal: fastShaft.seal,
    reverseHatching: true,
  )

  slowShaft.covers[0] = CoverDesc(
    D: slowShaft.bearing.D,
    h: 20.mm - (slowShaft.bearing.B - fastShaft.bearing.B).ceil(1.mm),
    shaft_d: slowShaft.secondDiameter,
    reverseHatching: true,
  )
  slowShaft.covers[1] = CoverDesc(
    D: slowShaft.bearing.D,
    h: 20.mm - (slowShaft.bearing.B - fastShaft.bearing.B).ceil(1.mm),
    # shaft_d: slowShaft.secondDiameter,
    hole: true, seal: slowShaft.seal,
    reverseHatching: true,
  )

  let boltHeadHeight = 7.mm  # choosen from table # todo: autocomplete
  let distanceFromBoltHeight = 4.mm  # 3.mm .. 5.mm


  let bevel = ShaftConjunction(kind: Bevel, radius: 1.6.mm)  # choosen from table # todo: autocomplete
  let fillet = ShaftConjunction(kind: Fillet, radius: 2.mm)  # choosen from table # todo: autocomplete
  fastShaft.shaft = Shaft(
    segments: @[
      cylindricSegment(
        d = fastShaft.exitDiameter,
        l = 82.mm,  # legth choosen form table # todo: autocomplete
        left = bevel, right = fillet,
      ),
      
      cylindricSegment(
        d = fastShaft.bearing.d,
        l = fastShaft.bearing.B + fastShaft.covers[1].totalHeight + boltHeadHeight + distanceFromBoltHeight - fastShaft.covers[1].boltDepth,
        right = fillet,
      ),
      
      cylindricSegment(d = 53.mm, l = bead, right = fillet),  # ! diameter was extended so bearings has a detent
      
      fastShaft.gear,
      
      cylindricSegment(d = 53.mm, l = bead, left = fillet),  # ! diameter was extended so bearings has a detent
      
      cylindricSegment(
        d = fastShaft.bearing.d,
        l = fastShaft.bearing.B + 5.mm,
        right = bevel
      ),
    ]
  )

  slowShaft.shaft = Shaft(
    segments: @[
      cylindricSegment(
        d = slowShaft.exitDiameter,
        l = 82.mm,  # legth choosen form table # todo: autocomplete
        left = bevel, right = fillet
      ),
      
      cylindricSegment(
        d = slowShaft.bearing.d,
        l = slowShaft.bearing.B + slowShaft.covers[1].totalHeight + boltHeadHeight + distanceFromBoltHeight - slowShaft.covers[1].boltDepth,
      ),
      
      cylindricSegment(d = 70.mm, l = slowShaftBead),
      
      slowShaft.gear,
      
      cylindricSegment(
        d = slowShaft.bearing.d,
        l = slowShaftBead + slowShaft.bearing.B + bearingOnShaftEndPadding,
        right = bevel,
      ),
    ]
  )


  let coverGap = 4.mm  # 2.mm .. 4.mm
  let coverCutoff = max(0, fastShaft.covers[0].D2/2 + slowShaft.covers[1].D2/2 + coverGap - axial_distance)/2
  fastShaft.covers[0].cutoff = (coverCutoff, 0.mm)
  fastShaft.covers[1].cutoff = (0.mm, coverCutoff)
  slowShaft.covers[1].cutoff = (0.mm, coverCutoff)
  slowShaft.covers[0].cutoff = (coverCutoff, 0.mm)


  fastShaft.sketch = fastShaft.shaft.sketch.sketch
  slowShaft.sketch = slowShaft.shaft.sketch.sketch

  fastShaft.pos = point2(0, 0)
  slowShaft.pos = point2(-axial_distance, 0)



  # --- shafts ---

  fastShaft.entity = doc.spawn SubWorld fastShaft.sketch:
    Position2 fastShaft.pos
    Transform3 (rotateZ(Pi/2) * translate(v3(-fastShaft.shaft.segmentX(fastShaft.gear) - fastShaft.gear.length/2, 0, 0)))

  slowShaft.entity = doc.spawn SubWorld slowShaft.sketch:
    Position2 slowShaft.pos
    Transform3 (rotateZ(-Pi/2) * translate(v3(-slowShaft.shaft.segmentX(slowShaft.gear) - slowShaft.gear.length/2, 0, 0)))

  doc.add line(
    fastShaft.pos + v2(0, fastShaft.shaft.segmentX(0, PositionAtLeft) - fastShaft.shaft.segmentX(3, PositionAtCenter) - 5.mm),
    fastShaft.pos + v2(0, fastShaft.shaft.segmentX(5, PositionAtRight) - fastShaft.shaft.segmentX(3, PositionAtCenter) + 5.mm),
  ), axialLine

  doc.add line(
    slowShaft.pos + v2(0, -(slowShaft.shaft.segmentX(4, PositionAtRight) - slowShaft.shaft.segmentX(3, PositionAtCenter)) - 5.mm),
    slowShaft.pos + v2(0, -(slowShaft.shaft.segmentX(0, PositionAtLeft) - slowShaft.shaft.segmentX(3, PositionAtCenter)) + 5.mm),
  ), axialLine



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


  # --- covers ---

  fastShaft.coverEnt[0] = doc.spawn SubWorld fastShaft.covers[0].sketch(hideBackLines = true):
    Position2 fastShaft.pos + v2(0,
      + fastShaft.shaft.segmentX(5, PositionAtRight) +
      - fastShaft.shaft.segmentX(3, PositionAtCenter) +
      + fastShaft.covers[0].bounds.size.x +
      - bearingOnShaftEndPadding +
    0)
    Transform3 rotateZ(-Pi/2)

  fastShaft.coverEnt[1] = doc.spawn SubWorld fastShaft.covers[1].sketch(hideBackLines = true):
    Position2 fastShaft.pos + v2(0,
      + fastShaft.shaft.segmentX(1, PositionAtRight) +
      - fastShaft.shaft.segmentX(3, PositionAtCenter) +
      - fastShaft.covers[1].bounds.size.x +
      - fastShaft.bearing.B +
    0)
    Transform3 rotateZ(Pi/2)


  slowShaft.coverEnt[0] = doc.spawn SubWorld slowShaft.covers[0].sketch(hideBackLines = true):
    Position2 slowShaft.pos + v2(0,
      + slowShaft.shaft.segmentX(1, PositionAtRight) +
      - slowShaft.shaft.segmentX(3, PositionAtCenter) +
      - slowShaft.covers[0].bounds.size.x +
      - slowShaft.bearing.B +
    0)
    Transform3 rotateZ(Pi/2)

  slowShaft.coverEnt[1] = doc.spawn SubWorld slowShaft.covers[1].sketch(hideBackLines = true):
    Position2 slowShaft.pos + v2(0,
      + slowShaft.shaft.segmentX(4, PositionAtRight) +
      - slowShaft.shaft.segmentX(3, PositionAtCenter) +
      + slowShaft.covers[1].bounds.size.x +
      - bearingOnShaftEndPadding +
    0)
    Transform3 rotateZ(-Pi/2)



  # --- seals ---

  fastShaft.sealEnt = doc.spawn SubWorld fastShaft.seal.sketch(hideBackLines = true):
    Position2 fastShaft.pos + v2(0,
      + fastShaft.shaft.segmentX(1, PositionAtRight) +
      - fastShaft.shaft.segmentX(3, PositionAtCenter) +
      - fastShaft.covers[1].bounds.size.x +
      + fastShaft.covers[1].s +
      - fastShaft.bearing.B +
    0)
    Transform3 rotateZ(Pi/2)

  slowShaft.sealEnt = doc.spawn SubWorld slowShaft.seal.sketch(hideBackLines = true):
    Position2 slowShaft.pos + v2(0,
      - slowShaft.shaft.segmentX(2, PositionAtLeft) +
      + slowShaft.shaft.segmentX(3, PositionAtCenter) +
      + slowShaft.covers[1].bounds.size.x +
      - slowShaft.covers[1].s +
      + slowShaft.bearing.B +
    0)
    Transform3 rotateZ(-Pi/2)

  
  # --- bushing ---

  doc.add SubWorld bushing.sketch(backlines = false):
    Position2 slowShaft.pos + v2(0,
      - slowShaft.shaft.segmentX(4, PositionAtLeft) +
      + slowShaft.shaft.segmentX(3, PositionAtCenter) +
      - bushing.H +
    0)
    Transform3 rotateZ(Pi/2)




  # --- box ---

  let innerBox = roundRect2geom(
    point2(shaftsBounds.center.x, 0), v2(shaftsBounds.size.x + padding*2, fastShaft.gear.length + padding*2),
    radius = (0.5*wall_thickness).ceil(1.mm),
  )
  
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

  let outerBox = roundRect2geom(
    point2(shaftsBounds.center.x, 0),
    v2(shaftsBounds.size.x + padding*2 + wall_thickness*2, fastShaft.gear.length + padding*2 + wall_thickness*2),
    radius = (0.5*wall_thickness).ceil(1.mm) + wall_thickness,
  )

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
    

  # --- corpus ---
  when true:
    # ! this is not parametric
    proc addSymmetric[T](doc: World, v: Curve2, other: T) =
      let oc = create(OwnedCurve2)
      oc[] = v.transform(m4())
      doc.add oc[].Curve2, other

      let oc2 = create(OwnedCurve2)
      oc2[] = v.transform(scale v3(1, -1, 1))
      doc.add oc2[].Curve2, other
    
    proc addAxial(doc: World, circle: CircleArc2) =
      doc.add line(circle.center - v2(circle.radius * 1.1, 0), circle.center + v2(circle.radius * 1.1, 0)), axialLine
      doc.add line(circle.center - v2(0, circle.radius * 1.1), circle.center + v2(0, circle.radius * 1.1)), axialLine


    let K2 = 32.mm  # selected from table # todo: autocomplete
    let C2 = 16.mm  # selected from table # todo: autocomplete
    let d2 = 15.mm  # selected from table # todo: autocomplete

    let K3 = 29.mm  # selected from table # todo: autocomplete
    let C3 = 15.mm  # selected from table # todo: autocomplete
    let d3 = 12.mm  # selected from table # todo: autocomplete

    let owH = (fastShaft.gear.length/2 + padding + wall_thickness) * 2  # = 0.094875
    let H = owH + K3 * 2  # = 0.152875

    let jointBoltCount = 3
    # let jointPadding = 0.mm
    let jointPadding = H * 1/5/2

    # --- right-side ---
    block:
      let wallX = outerBox.lines[RoundRect2Geom_LineIndex.right].pointAtParam(0).x
      let X = wallX + K3
      let coverPoint = doc.bounds(fastShaft.coverEnt[0]).max - v2(0, fastShaft.covers[0].H)
      
      let boltHole = circle(p2(coverPoint.x, owH/2 + C2), d2/2)
      doc.addSymmetric boltHole, (doc.foreground, mainLine)
      doc.addSymmetric boltHole, (Hatching(), color doc.foreground, hatchingLine)
      doc.addAxial boltHole
      doc.addAxial boltHole.transform(scale v3(1, -1, 1))

      let boltCorpus = circle(boltHole.center, C2, Pi/2, -Pi/2)
      # doc.add boltCorpus, mainLine
      
      doc.addSymmetric line(boltCorpus.pointAtParam(0), coverPoint), (doc.foreground, mainLine)
      doc.addSymmetric line(boltCorpus.pointAtParam(1), outerBox.lines[RoundRect2Geom_LineIndex.right].pointAtParam(1)), hiddenLine


      block:
        var p = Path2()
        
        p.add p2(X, 0)
        p.y = H/2; p.fillet(K3)
        p.x -= 50.mm

        # doc.add p.Curve2, doc.foreground, mainLine
        
        var ig = buildIntersectionGraph(@[p.toOwnedCurve2, boltCorpus.toOwnedCurve2])

        for x in ig.edges:
          if x.curve == 0 and x.startParam < (1/3 + 0.01):
            doc.addSymmetric ig.curves[x.curve].cut(x.startParam, x.endParam), (doc.foreground, mainLine)

          elif x.curve == 1:
            if x.startParam ~== 0:
              # todo: allow conditionals in ecs spawn macro
              doc.addSymmetric ig.curves[x.curve].cut(x.startParam, x.endParam), (doc.foreground, mainLine)
            else:
              # note: components in conditionals should owerride components already added
              doc.addSymmetric ig.curves[x.curve].cut(x.startParam, x.endParam), hiddenLine
    

      # bolts on the half-corpus joint
      block:
        for boltI in 0..<jointBoltCount:
          let y = (((1 + boltI) / (jointBoltCount + 1)) - 0.5) * (H - jointPadding*2)
          let bolt3Hole = circle(p2(wallX + C3, y), d3/2)
          # CircleArc drawing should be unified with Curve2 drawing (by default - drawn as contour line)
          doc.add bolt3Hole, mainLine
          doc.add bolt3Hole, Hatching(), color doc.foreground, hatchingLine
          doc.addAxial bolt3Hole


    # --- left-side
    block:
      let wallX = outerBox.lines[RoundRect2Geom_LineIndex.left].pointAtParam(0).x
      let X = wallX - K3
      let coverPoint = doc.bounds(slowShaft.coverEnt[1]).min + v2(0, fastShaft.covers[0].h)

      let boltHole = circle(p2(coverPoint.x, owH/2 + C2), d2/2)
      doc.addSymmetric boltHole, (doc.foreground, mainLine)
      doc.addSymmetric boltHole, (Hatching(), color doc.foreground, hatchingLine)
      doc.addAxial boltHole
      doc.addAxial boltHole.transform(scale v3(1, -1, 1))

      let boltCorpus = circle(boltHole.center, C2, Pi/2, Pi, clockwise)
      # doc.add boltCorpus, mainLine

      doc.addSymmetric line(boltCorpus.pointAtParam(0), coverPoint), (doc.foreground, mainLine)
      
      block:
        var p = Path2()
        
        p.add p2(X, 0)
        p.y = H/2; p.fillet(K3)
        p.x = slowShaft.pos.x

        # doc.add p.Curve2, doc.foreground, mainLine
        
        var ig = buildIntersectionGraph(@[p.toOwnedCurve2, boltCorpus.toOwnedCurve2])

        for x in ig.edges:
          if x.curve == 0 and x.startParam < (1/3 + 0.01):
            doc.addSymmetric ig.curves[x.curve].cut(x.startParam, x.endParam), (doc.foreground, mainLine)

          elif x.curve == 1:
            if x.startParam ~== 0:
              # todo: allow conditionals in ecs spawn macro
              doc.addSymmetric ig.curves[x.curve].cut(x.startParam, x.endParam), (doc.foreground, mainLine)
            else:
              # note: components in conditionals should owerride components already added
              doc.addSymmetric ig.curves[x.curve].cut(x.startParam, x.endParam), hiddenLine


      # bolts on the half-corpus joint
      block:
        for boltI in 0..<jointBoltCount:
          let y = (((1 + boltI) / (jointBoltCount + 1)) - 0.5) * (H - jointPadding*2)
          let bolt3Hole = circle(p2(wallX - C3, y), d3/2)
          # CircleArc drawing should be unified with Curve2 drawing (by default - drawn as contour line)
          doc.add bolt3Hole, mainLine
          doc.add bolt3Hole, Hatching(), color doc.foreground, hatchingLine
          doc.addAxial bolt3Hole


  doc.drawRects()


