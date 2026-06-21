import sandbox, geom2d, techDraw, tabledef
import pkg/[bumpy]
import ../shafts/[shafts, gears]
import ./[bearings {.all.}, covers, seal, bushing]
import ./compute/[reductor, shafts]
when isMainModule: import tools/measurement


type
  ReductorShaftDesc* = object
    exitDiameter*: float
      ## diameter of the exit stage of the shaft, m
    exitLength*: float
      ## length of the exit stage (the one with exitDiameter), m
    gear_l*: float
      ## gear height (length of the shaft stage with the gear), m
    gear_z*: int
      ## gear teeth count
  

  ReductorDesc* = object
    gearModulo*: float
      ## modulo for all gears

    fast*: ReductorShaftDesc
    slow*: ReductorShaftDesc


    # --- corrections ---

    wallThicknessExtend*: float
      ## extension of the corpus wall thickness, m

    bearingDetentDiameterExtend*: float
      ## extension of the diameter of the shaft beads next to the fast shaft gear, m


  ShaftEx = object
    shaft: Shaft
    sketch: World
    gear: ShaftSegment
    pos: Point2
    exitDiameter: float

    entity: EntityId
    bearing: BearingParams
    seal: SealGeomParams
    covers: array[2, CoverGeomParams]
    bearingEnt: array[2, EntityId]
    coverEnt: array[2, EntityId]
    sealEnt: EntityId



columnTable corpusBolts, `const`:
  #    (>=)              (=)            (=M)        (=M)     (=M)
  axial_distance | wall_thickness | fundamental | bearing | flange
  0              | 6              | 12          | 10      | 8
  90             | 8              | 16          | 12      | 10
  200            | 10             | 20          | 16      | 12
  315            | 12             | 24          | 20      | 14
  400            | 14             | 27          | 24      | 16
  500            | 16             | 30          | 27      | 16

proc corpusBoltsAt(i: int): tuple[wall_thickness: float, fundamental_M, bearing_M, flange_M: int] =
  return (
    corpusBolts.wall_thickness[i].float.mm,
    corpusBolts.fundamental[i],
    corpusBolts.bearing[i],
    corpusBolts.flange[i],
  )

proc selectCorpusBolts(axial_distance: float): tuple[wall_thickness: float, fundamental_M, bearing_M, flange_M: int] =
  for i in countdown(corpusBolts.axial_distance.high, 0):
    if axial_distance >= corpusBolts.axial_distance[i].float.mm:
      return corpusBoltsAt(i)



columnTable boltParams, `const`:
  M   | S    | d   | D    | C   | K
  6   | 10.0 | 7.0 | 13.5 | 9.0 | 18.0
  8   | 13   | 10  | 18   | 11  | 22
  10  | 17   | 12  | 22   | 15  | 29
  12  | 19   | 15  | 26   | 16  | 32
  14  | 22   | 17  | 30   | 17  | 34
  16  | 24   | 19  | 33   | 19  | 37
  20  | 30   | 24  | 40   | 23  | 45
  24  | 36   | 28  | 48   | 28  | 54
  27  | 41   | 32  | 52   | 30  | 58
  30  | 46   | 35  | 61   | 34  | 66

proc selectBoltParams(M: int): tuple[S, d, D, C, K: float] =
  for i in 0 ..< boltParams.M.len:
    if boltParams.M[i] == M:
      return (
        boltParams.S[i].mm,
        boltParams.d[i].mm,
        boltParams.D[i].mm,
        boltParams.C[i].mm,
        boltParams.K[i].mm,
      )



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


proc segmentX(shaft: Shaft, segmentI: int, p = PositionAtLeft): float =
  result = 0
  for i, seg in shaft.segments:
    if i == segmentI:
      case p
      of PositionAtLeft: return result
      of PositionAtCenter: return result + seg.length/2
      of PositionAtRight: return result + seg.length
      else: return result
    result += seg.length

proc segmentX(shaft: Shaft, segment: ShaftSegment): float =
  result = 0
  for seg in shaft.segments:
    if seg == segment:
      return
    result += seg.length


proc gearPitchDiameter(x: ShaftEx): float =
  x.gear.section.gear.pitchDiameter


proc secondDiameter(shaft: ShaftEx): float =
  (shaft.exitDiameter + 5.mm).ceil(5.mm)
  
proc thirdDiameter(shaft: ShaftEx): float =
  (shaft.secondDiameter + 5.mm).ceil(5.mm)


proc draw*(doc: World, desc: ReductorDesc) =
  var fastShaft = ShaftEx(exitDiameter: desc.fast.exitDiameter)
  var slowShaft = ShaftEx(exitDiameter: desc.slow.exitDiameter)

  fastShaft.gear = gearSegment(
    l = desc.fast.gear_l, z = desc.fast.gear_z, modulo = desc.gearModulo,
    reverseHatching = true,
  )
  slowShaft.gear = gearSegment(
    l = desc.slow.gear_l, z = desc.slow.gear_z, modulo = desc.gearModulo,
    shaft_d = slowShaft.thirdDiameter,
  )
  slowShaft.gear.left = ShaftConjunction(kind: Fillet, radius: (slowShaft.gear.section.gear.bevelRadius * 0.5).ceil(0.1.mm))


  let axial_distance = fastShaft.gearPitchDiameter/2 + slowShaft.gearPitchDiameter/2
  var (wall_thickness, fundamental_M, bearing_M, flange_M) = selectCorpusBolts(axial_distance)
  
  wall_thickness += desc.wallThicknessExtend

  discard fundamental_M  # todo
  # let fundamental = fundamental_M.selectBoltParams()  # todo
  let bearingBolts = bearing_M.selectBoltParams()
  let flange = flange_M.selectBoltParams()
  
  let padding = (wall_thickness * 1.5).ceil(5.mm)
  let bead = padding
  let slowShaftBead = (fastShaft.gear.length - slowShaft.gear.length)/2 + bead

  let bearingOnShaftEndPadding = 5.mm


  fastShaft.bearing = selectMiddleSeriesBearing(fastShaft.secondDiameter)
  slowShaft.bearing = selectMiddleSeriesBearing(slowShaft.secondDiameter)

  
  fastShaft.seal = SealDesc(d: fastShaft.secondDiameter)
  slowShaft.seal = SealDesc(d: slowShaft.secondDiameter)


  let bushing = BushingDesc(d: slowShaft.secondDiameter, H: slowShaftBead, reversedHatching: true)


  fastShaft.covers[0] = CoverDesc(
    D: fastShaft.bearing.D,
    h: (bearingBolts.K + wall_thickness - fastShaft.bearing.B).ceil(1.mm),
    shaft_d: fastShaft.secondDiameter,
    reverseHatching: true,
  )
  fastShaft.covers[1] = CoverDesc(
    D: fastShaft.bearing.D,
    h: (bearingBolts.K + wall_thickness - fastShaft.bearing.B).ceil(1.mm),
    # shaft_d: fastShaft.secondDiameter,
    hole: true, seal: fastShaft.seal,
    reverseHatching: true,
  )

  slowShaft.covers[0] = CoverDesc(
    D: slowShaft.bearing.D,
    h: (bearingBolts.K + wall_thickness - slowShaft.bearing.B).ceil(1.mm),
    shaft_d: slowShaft.secondDiameter,
    reverseHatching: true,
  )
  slowShaft.covers[1] = CoverDesc(
    D: slowShaft.bearing.D,
    h: (bearingBolts.K + wall_thickness - slowShaft.bearing.B).ceil(1.mm),
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
        l = desc.fast.exitLength,
        left = bevel, right = fillet,
      ),
      
      cylindricSegment(
        d = fastShaft.bearing.d,
        l = fastShaft.bearing.B + fastShaft.covers[1].totalHeight + boltHeadHeight + distanceFromBoltHeight - fastShaft.covers[1].boltDepth,
        right = fillet,
      ),
      
      cylindricSegment(d = fastShaft.thirdDiameter + desc.bearingDetentDiameterExtend, l = bead, right = fillet),

      fastShaft.gear,

      cylindricSegment(d = fastShaft.thirdDiameter + desc.bearingDetentDiameterExtend, l = bead, left = fillet),
      
      cylindricSegment(
        d = fastShaft.bearing.d,
        l = fastShaft.bearing.B + 5.mm,
        right = bevel, left = fillet,
      ),
    ]
  )

  slowShaft.shaft = Shaft(
    segments: @[
      cylindricSegment(
        d = slowShaft.exitDiameter,
        l = desc.slow.exitLength,
        left = bevel, right = fillet
      ),
      
      cylindricSegment(
        d = slowShaft.bearing.d,
        l = slowShaft.bearing.B + slowShaft.covers[1].totalHeight + boltHeadHeight + distanceFromBoltHeight - slowShaft.covers[1].boltDepth,
        right = fillet,
      ),
      
      cylindricSegment(
        d = 70.mm,
        l = slowShaftBead,
      ),
      
      slowShaft.gear,
      
      cylindricSegment(
        d = slowShaft.bearing.d,
        l = slowShaftBead + slowShaft.bearing.B + bearingOnShaftEndPadding,
        right = bevel, left = fillet,
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


  # --- keys ---
  block:
    block:
      let (d, l) = (
        selectKeyDims(fastShaft.exitDiameter / drawingMmScale).b.mm,
        ((desc.fast.exitLength - 2.mm) / drawingMmScale).findClosestKeyL.mm,
      )
      draw roundRect2geom(
        fastShaft.pos + v2(0,
          + fastShaft.shaft.segmentX(0, PositionAtCenter) +
          - fastShaft.shaft.segmentX(3, PositionAtCenter) +
        0),
        v2(d, l),
        radius = d/2,
      )

    block:
      let (d, l) = (
        selectKeyDims(slowShaft.exitDiameter / drawingMmScale).b.mm,
        ((desc.slow.exitLength - 2.mm) / drawingMmScale).findClosestKeyL.mm,
      )
      draw roundRect2geom(
        slowShaft.pos + v2(0,
          - slowShaft.shaft.segmentX(0, PositionAtCenter) +
          + slowShaft.shaft.segmentX(3, PositionAtCenter) +
        0),
        v2(d, l),
        radius = d/2,
      )

    block:
      let (d, l) = (
        selectKeyDims(slowShaft.gear.section.gear.shaft_d / drawingMmScale).b.mm,
        ((slowShaft.gear.length - 2.mm - keyedGearMargin) / drawingMmScale).findClosestKeyL.mm,
      )
      draw roundRect2geom(
        slowShaft.pos + v2(0,
          - slowShaft.shaft.segmentX(3, PositionAtCenter) +
          + slowShaft.shaft.segmentX(3, PositionAtCenter) +
          + keyedGearMargin/2 +
        0),
        v2(d, l),
        radius = d/2,
      )


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


  doc.add line(
    fastShaft.pos + v2(0, fastShaft.shaft.segmentX(0, PositionAtLeft) - fastShaft.shaft.segmentX(3, PositionAtCenter) - 5.mm),
    p2(fastShaft.pos.x, doc.bounds(fastShaft.coverEnt[0]).max.y + 5.mm),
  ), axialLine

  doc.add line(
    p2(slowShaft.pos.x, doc.bounds(slowShaft.coverEnt[0]).min.y - 5.mm),
    slowShaft.pos + v2(0, -(slowShaft.shaft.segmentX(0, PositionAtLeft) - slowShaft.shaft.segmentX(3, PositionAtCenter)) + 5.mm),
  ), axialLine



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
    0)
    Transform3 rotateZ(-Pi/2)




  # --- box ---

  
  let innerBox = roundRect2geom(
    point2(shaftsBounds.center.x, 0), v2(shaftsBounds.size.x + padding*2, fastShaft.gear.length + padding*2),
    radius = (0.5*wall_thickness).ceil(1.mm),
  )
  
  block:
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

  block:
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
      doc.add v.transform(m4()), other
      doc.add v.transform(scale v3(1, -1, 1)), other
    
    proc addAxial(doc: World, circle: CircleArc2) =
      doc.add line(circle.center - v2(circle.radius * 1.1, 0), circle.center + v2(circle.radius * 1.1, 0)), axialLine
      doc.add line(circle.center - v2(0, circle.radius * 1.1), circle.center + v2(0, circle.radius * 1.1)), axialLine

    
    let C2 = bearingBolts.C
    let d2 = bearingBolts.d

    let K3 = flange.K
    let C3 = flange.C
    let d3 = flange.d

    let owH = (fastShaft.gear.length/2 + padding + wall_thickness) * 2  # = 0.094875
    let H = owH + K3 * 2  # = 0.152875

    let jointBoltCount = 3
    let jointPadding = 0.mm
    # let jointPadding = H * 1/5/2

    # --- right-side ---
    block:
      let wallX = outerBox.lines[RoundRect2Geom_LineIndex.right].pointAt(0).x
      let X = wallX + K3
      let coverPoint = doc.bounds(fastShaft.coverEnt[0]).max - v2(0, fastShaft.covers[0].H)
      
      let boltHole = circle(p2(coverPoint.x, owH/2 + C2), d2/2)
      doc.addSymmetric boltHole, (doc.foreground, mainLine)
      doc.addSymmetric boltHole, (Hatching(), color doc.foreground, hatchingLine)
      doc.addAxial boltHole
      doc.addAxial boltHole.transform(scale v3(1, -1, 1))

      let boltCorpus = circle(boltHole.center, C2, Pi/2, -Pi/2)
      # doc.add boltCorpus, mainLine
      
      doc.addSymmetric line(boltCorpus.pointAt(0), coverPoint), (doc.foreground, mainLine)
      doc.addSymmetric line(boltCorpus.pointAt(1), outerBox.lines[RoundRect2Geom_LineIndex.right].pointAt(1)), hiddenLine


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
      let wallX = outerBox.lines[RoundRect2Geom_LineIndex.left].pointAt(0).x
      let X = wallX - K3
      let coverPoint = doc.bounds(slowShaft.coverEnt[1]).min + v2(0, fastShaft.covers[0].h)

      let boltHole = circle(p2(coverPoint.x, owH/2 + C2), d2/2)
      doc.addSymmetric boltHole, (doc.foreground, mainLine)
      doc.addSymmetric boltHole, (Hatching(), color doc.foreground, hatchingLine)
      doc.addAxial boltHole
      doc.addAxial boltHole.transform(scale v3(1, -1, 1))

      let boltCorpus = circle(boltHole.center, C2, Pi/2, Pi, clockwise)
      # doc.add boltCorpus, mainLine

      doc.addSymmetric line(boltCorpus.pointAt(0), coverPoint), (doc.foreground, mainLine)

      block:
        let pt = p2(boltCorpus.pointAt(1).x, outerBox.lines[RoundRect2Geom_LineIndex.bottom].pointAt(0).y)
        let r = (0.5 * wall_thickness).ceil(1.mm)
        let c = circleArc(pt + v2(-r, +r), r, 0, -Pi/2)
        doc.addSymmetric c, hiddenLine
        doc.addSymmetric line(c.pointAt(0), boltCorpus.pointAt(1)), hiddenLine
      
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
    

    # --- center ---
    block:
      let coverA = doc.bounds(fastShaft.coverEnt[0]).min + v2(0, fastShaft.covers[0].h)
      let coverB = doc.bounds(slowShaft.coverEnt[1]).max - v2(0, slowShaft.covers[1].H)

      doc.addSymmetric line(coverA, coverB), (doc.foreground, mainLine)

      let boltHole = circle(p2(line(coverA, coverB).center.x, owH/2 + C2), d2/2)
      doc.addSymmetric boltHole, (doc.foreground, mainLine)
      doc.addSymmetric boltHole, (Hatching(), color doc.foreground, hatchingLine)
      doc.addAxial boltHole
      doc.addAxial boltHole.transform(scale v3(1, -1, 1))


  doc.drawRects()

defineSketch draw



mainModule:
  doc[globals, CanvasSettings].margin = v2(10.mm, 10.mm)

  when true:
    let I = computeReductor ReductorInput(env: 0.0, D: 0.5, F: 3.2, V: 1.5)

    doc.add SubWorld ReductorDesc(
      gearModulo: I.closedTransmission.teeth_modulo.mm,
      fast: ReductorShaftDesc(
        exitDiameter: I.shafts.geom.B.d.mm,
        exitLength: I.shafts.geom.B.l.mm,
        gear_l: I.closedTransmission.geom.b1.mm,
        gear_z: I.closedTransmission.z1,
      ),
      slow: ReductorShaftDesc(
        exitDiameter: I.shafts.geom.T.d.mm,
        exitLength: I.shafts.geom.T.l.mm,
        gear_l: I.closedTransmission.geom.b2.mm,
        gear_z: I.closedTransmission.z2,
      ),

      wallThicknessExtend: 2.mm,
      bearingDetentDiameterExtend: 3.mm,
    ).sketch()

  else:
    doc.add SubWorld ReductorDesc(
      gearModulo: 2.75.mm,
      fast: ReductorShaftDesc(
        exitDiameter: 40.mm,
        exitLength: 82.mm,
        gear_l: 44.875.mm,
        gear_z: 23,
      ),
      slow: ReductorShaftDesc(
        exitDiameter: 48.mm,
        exitLength: 82.mm,
        gear_l: 39.875.mm,
        gear_z: 93,
      ),

      wallThicknessExtend: 2.mm,
      bearingDetentDiameterExtend: 3.mm,
    ).sketch()


