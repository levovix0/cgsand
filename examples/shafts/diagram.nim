import std/[sequtils, strutils, algorithm, math]
import sandbox, geom2d
import annotations/[dimensions]
import ./[shafts]


type
  DistributedLoad* = object
    x*: Slice[float]  ## in meters
    load*: float  ## in newtons/meters, positive means ̲↓ from top, negative means ̅↑ from bottom
  
  ConcentratedForce* = object
    x*: float  ## in meters
    force*: float  ## in newtons, positive means ̲↓ from top, negative means ̅↑ from bottom
  
  RotationalMoment* = object
    x*: float  ## in meters
    moment*: float  ## in newtons*meters, positive means counterclockwise, negative means clockwise
  

  BeamSegment* = object
    length*: float  ## in meters
    section*: Section

  Beam* = object
    segments*: seq[BeamSegment]
    loads*: seq[DistributedLoad]
    forces*: seq[ConcentratedForce]
    moments*: seq[RotationalMoment]
    fixedPositions*: seq[float]

    origin*: Point2
    meterSize*: float = 4  ## units in 1 meter
  
  
  DiagramSettings* = object
    qScale*: float       ## world units per Newton
    mScale*: float       ## world units per Newton·meter
    qOffset*: float      ## world units below beam baseline to Q zero-line
    mGap*: float         ## world units from Q zero-line to M zero-line
    hatchSpacing*: float ## spacing between vertical hatch lines in world units
    displayInC*: bool


let dimensionFontSize = FontSize 0.5
var loadColor: Color = doc.foreground
var forceColor: Color = doc.foreground
var momentColor: Color = doc.foreground
if darkTheme:
  loadColor = parseHtmlHex "#ff9b28"
  forceColor = parseHtmlHex "#1e8fff"
  momentColor = parseHtmlHex "#a860ff"


let steel* = Material(tension_limit: 160 * 1e6)
let duralluminium* = Material(tension_limit: 80 * 1e6)

let rectSection = Section(shape: Rectangle, rectangle: (w: 1, h: 2), material: steel, unknownDimensions: true)
# let circle = Section(shape: Circle, circle: (radius: 1), material: duralluminium, unknownDimensions: true)

let q = 5.0 * 1e3
let l = 1.0



proc `$`(x: float): string =
  result = system.`$` x.round(2)
  result.removeSuffix ".0"

proc addName(x: string, name: string): string =
  if x == "1": result = name
  else: result = x & " " & name



proc draw*(beam: Beam) =
  let w = beam.segments.mapIt(it.length).foldl(a + b)
  let wide = Thickness beam.meterSize / 40

  proc addTextAt(text: string, x: float) =
    var allowedPositions = @[PositionAtBottom, PositionAtBottomRight, PositionAtBottomLeft]
    if beam.fixedPositions.anyIt(it ~== x):
      allowedPositions.excl PositionAtBottom
      if x ~< 0: allowedPositions.excl PositionAtBottomRight
      if x ~> w: allowedPositions.excl PositionAtBottomLeft
    for load in beam.loads:
      if (x ~> load.x.a) and (x ~< load.x.b) and (load.load > 0):
        allowedPositions.excl PositionAtBottom
        if not(x ~< load.x.a): allowedPositions.excl PositionAtBottomRight
        if not(x ~> load.x.b): allowedPositions.excl PositionAtBottomLeft
    if beam.forces.anyIt(it.x ~== x and it.force > 0):
      allowedPositions.excl PositionAtBottom
    if beam.moments.anyIt(it.x ~== x):
      allowedPositions.excl PositionAtBottom
    
    if allowedPositions.len == 0:
      doc.add Text text:
        Position2 beam.origin + vec2(x * beam.meterSize, -2 - textMargin)
        PositionAtBottom
        dimensionFontSize
    else:
      let p = allowedPositions[0]
      doc.add Text text:
        Position2 beam.origin + vec2(
          (
            if p == PositionAtBottomLeft: x * beam.meterSize + textMargin
            elif p == PositionAtBottomRight: x * beam.meterSize - textMargin
            else: x * beam.meterSize
          ),
          -textMargin
        )
        dimensionFontSize
        p


  var x = 0.0
  for i, segment in beam.segments:
    let line = lineSection(beam.origin + vec2(x * beam.meterSize, 0), beam.origin + vec2(x * beam.meterSize + segment.length * beam.meterSize, 0))

    doc.add line, wide
    
    addTextAt $(i + 1), x

    doc.add LinearDimension2(
      a: line.startPoint,
      b: line.endPoint,
      dir: vec2(1, 0),
      dimline: line.startPoint + vec2(0, beam.meterSize * 1.2)
    ), DimensionText (segment.length).`$`.addName("l"), dimensionFontSize
    
    x += segment.length
  
  addTextAt $(beam.segments.len + 1), x

  for fp in beam.fixedPositions:
    let line = lineSection(
      beam.origin + vec2(fp * beam.meterSize, -beam.meterSize / 4),
      beam.origin + vec2(fp * beam.meterSize, beam.meterSize / 4)
    )
    doc.add line, wide
    # todo: hatching
    for y in countup(0, int(beam.meterSize) - 1, 1):
      let y = y / int(beam.meterSize)
      doc.add lineSection(line.pointAtParam(y), line.pointAtParam(y) + vec2(-0.5, 0.5))
  
  
  for load in beam.loads:
    let a = beam.origin + vec2(load.x.a * beam.meterSize, 0)
    let b = beam.origin + vec2(load.x.b * beam.meterSize, 0)
    let dir = (if load.load > 0: vec2(0, -1) else: vec2(0, 1)) * 1
    doc.add lineSection(a, a + dir), loadColor
    doc.add lineSection(a + dir, b + dir), loadColor
    doc.add lineSection(b, b + dir), loadColor

    for x in countup(0, int((load.x.b - load.x.a) * 4)):
      let p = lineSection(a, b).pointAtParam(x / int((load.x.b - load.x.a) * 4))
      doc.add lineSection(p + dir/4, p + dir), loadColor
      addArrow(p, -dir, dir.length / 2, loadColor)
      
    for x in countup(0, int(load.x.b - load.x.a) - 1):
      let p = lineSection(a + vec2((l*beam.meterSize)/2, 0), b - vec2((l*beam.meterSize)/2, 0)).pointAtParam(x / (int(load.x.b - load.x.a) - 1))
      doc.add Text abs(load.load / (q * l.pow(2))).`$`.addName("q"):
        Position2 (p + dir + dir.normalize * textMargin)
        (if load.load > 0: PositionAtBottom else: PositionAtTop)
        loadColor
        dimensionFontSize

  let forceHeight = 2.0

  for force in beam.forces:
    let pos = beam.origin + vec2(force.x * beam.meterSize, 0)
    let dir = (if force.force > 0: vec2(0, -1) else: vec2(0, 1)) * forceHeight

    doc.add lineSection(pos + dir/4, pos + dir), forceColor, wide
    addArrow(pos, -dir, 1, forceColor)

    doc.add Text abs(force.force / (q * l)).`$`.addName("ql"):
      Position2 pos + dir + vec2(textMargin, 0)
      (if force.force > 0: PositionAtTopLeft else: PositionAtBottomLeft)
      forceColor
      dimensionFontSize

  let momentHeight = 2.5
  let momentWidth = 1.0

  for moment in beam.moments:
    let pos = beam.origin + vec2(moment.x * beam.meterSize, 0)
    let dirx = (if moment.moment > 0: vec2(-1, 0) else: vec2(1, 0)) * momentWidth
    let dir = vec2(0, -1) * momentHeight

    doc.add lineSection(pos - dir, pos + dir), momentColor
    doc.add lineSection(pos - dir, pos - dir - dirx), momentColor
    doc.add lineSection(pos + dir, pos + dir + dirx), momentColor
    addArrow(pos + dir + dirx, dirx, momentWidth/2, momentColor)
    addArrow(pos - dir - dirx, -dirx, momentWidth/2, momentColor)

    doc.add Text abs(moment.moment / (q * l)).`$`.addName("ql²"):
      Position2 pos + dir + dirx + dirx.normalize * textMargin
      (if dirx.x > 0: PositionAtLeft else: PositionAtRight)
      momentColor
      dimensionFontSize



proc drawQM*(beam: Beam, settings: DiagramSettings) =
  let totalLength = beam.segments.mapIt(it.length).foldl(a + b)
  let isFixedLeft = beam.fixedPositions.anyIt(it ~== 0.0)

  proc bx(x: float): float = beam.origin.x + x * beam.meterSize

  proc qAt(x: float, includeAt: bool): float =
    ## Q = shear force; positive Q = net downward force to the right of section (Russian convention)
    if isFixedLeft:
      for f in beam.forces:
        if (includeAt and f.x >= x) or (not includeAt and f.x > x):
          result += f.force
      for ld in beam.loads:
        let lo = max(ld.x.a, x)
        let hi = ld.x.b
        if hi > lo: result += ld.load * (hi - lo)
    else:
      for f in beam.forces:
        if (includeAt and f.x <= x) or (not includeAt and f.x < x):
          result -= f.force
      for ld in beam.loads:
        let lo = ld.x.a
        let hi = min(ld.x.b, x)
        if hi > lo: result -= ld.load * (hi - lo)

  proc mAt(x: float, includeAt: bool): float =
    ## M = bending moment; positive M = sagging (lower fiber tension)
    ## Computed by equilibrium of the free-end side
    if isFixedLeft:
      for f in beam.forces:
        if (includeAt and f.x >= x) or (not includeAt and f.x > x):
          result -= f.force * (f.x - x)
      for ld in beam.loads:
        let lo = max(ld.x.a, x)
        let hi = ld.x.b
        if hi > lo:
          result -= ld.load * ((hi - x).pow(2) - (lo - x).pow(2)) / 2
      for m in beam.moments:
        if (includeAt and m.x >= x) or (not includeAt and m.x > x):
          result += m.moment
    else:
      for f in beam.forces:
        if (includeAt and f.x <= x) or (not includeAt and f.x < x):
          result -= f.force * (x - f.x)
      for ld in beam.loads:
        let lo = ld.x.a
        let hi = min(ld.x.b, x)
        if hi > lo:
          result -= ld.load * ((x - lo).pow(2) - (x - hi).pow(2)) / 2
      for m in beam.moments:
        if (includeAt and m.x <= x) or (not includeAt and m.x < x):
          result += m.moment

  # Collect breakpoint x positions
  var keyXs: seq[float] = @[0.0, totalLength]
  for f in beam.forces: keyXs.add f.x
  for m in beam.moments: keyXs.add m.x
  for ld in beam.loads: keyXs.add ld.x.a; keyXs.add ld.x.b
  for fp in beam.fixedPositions: keyXs.add fp
  when false:
    var sx = 0.0
    for seg in beam.segments:
      keyXs.add sx
      sx += seg.length
  keyXs.sort()
  keyXs = keyXs.deduplicate()

  let qBaseY = beam.origin.y + settings.qOffset
  let mBaseY = qBaseY + settings.mGap

  let qColor = if darkTheme: parseHtmlHex "#5dade2" else: doc.foreground
  let mColor = if darkTheme: parseHtmlHex "#58d68d" else: doc.foreground

  # Diagram label name for Q and M
  let qName = "ql"
  let mName = "ql²"
  let qRef = q * l
  let mRef = q * l * l

  proc qWorld(qVal: float): float = qBaseY - qVal * settings.qScale
  proc mWorld(mVal: float): float = mBaseY - mVal * settings.mScale

  proc labelVal(v: float, refV: float, cV: float, refName: string): string =
    if settings.displayInC:
      abs(v / cV).`$`
    else:
      abs(v / refV).`$`.addName(refName)

  # Draw zero-lines (baselines)
  doc.add lineSection(
    beam.origin + vec2(0.0, settings.qOffset),
    beam.origin + vec2(totalLength * beam.meterSize, settings.qOffset)
  ), qColor
  doc.add lineSection(
    beam.origin + vec2(0.0, settings.qOffset + settings.mGap),
    beam.origin + vec2(totalLength * beam.meterSize, settings.qOffset + settings.mGap)
  ), mColor

  # Draw diagram labels "Qy" and "Mx" on the left
  let text_Qy = doc.spawn(
    Text "Qy",
    Position2 beam.origin + vec2(totalLength * beam.meterSize + 1.66 + textMargin, settings.qOffset),
    PositionAtLeft,
    dimensionFontSize,
    qColor,
  )
  doc.add Text "[кН]":
    Position2 beam.origin + vec2(totalLength * beam.meterSize + 2 + textMargin, settings.qOffset + 1)
    PositionAtCenter
    dimensionFontSize
    qColor
  
  let text_Mx = doc.spawn(
    Text "Mx",
    Position2 beam.origin + vec2(totalLength * beam.meterSize + 1.66 + textMargin, settings.qOffset + settings.mGap),
    PositionAtLeft,
    dimensionFontSize,
    mColor,
  )
  doc.add Text "[кН·м]":
    Position2 beam.origin + vec2(totalLength * beam.meterSize + 2 + textMargin, settings.qOffset + settings.mGap + 1)
    PositionAtCenter
    dimensionFontSize
    qColor

  block:
    let b = doc.entityBounds(text_Qy)
    doc.add circle(toPoint(b.min) + (b.max - b.min)/2, max(b.max.x - b.min.x, b.max.y - b.min.y)/2 + 0.2), Thickness 0.05, Foreground qColor
  block:
    let b = doc.entityBounds(text_Mx)
    doc.add circle(toPoint(b.min) + (b.max - b.min)/2, max(b.max.x - b.min.x, b.max.y - b.min.y)/2 + 0.2), Thickness 0.05, Foreground mColor

  # Full-span vertical lines at load boundaries
  let fullSpanTop = beam.origin.y
  let fullSpanBot = mBaseY + settings.mGap * 0.5

  for xi in keyXs:
    doc.add lineSection(
      Point2 vec2(bx(xi), fullSpanTop),
      Point2 vec2(bx(xi), fullSpanBot)
    )

  # For each pair of consecutive breakpoints, draw Q and M segments
  for i in 0..<(keyXs.len - 1):
    let xa = keyXs[i]
    let xb = keyXs[i + 1] - 1e-4
    let steps = 8

    # Check if there's a distributed load in this interval
    var hasLoad = false
    for ld in beam.loads:
      if ld.x.a < xb and ld.x.b > xa: hasLoad = true

    let sampleCount = if hasLoad: steps else: 2

    # Sample points for Q and M
    var qPts: seq[Point2]
    var mPts: seq[Point2]
    for s in 0..sampleCount:
      let t = s.float / sampleCount.float
      let xi = xa + (xb - xa) * t
      let qv = qAt(xi, false)
      let mv = mAt(xi, false)
      qPts.add Point2 vec2(bx(xi), qWorld(qv))
      mPts.add Point2 vec2(bx(xi), mWorld(mv))

    # Draw outline
    for s in 0..<qPts.len - 1:
      doc.add lineSection(qPts[s], qPts[s+1]), qColor, Thickness 0.1
      doc.add lineSection(mPts[s], mPts[s+1]), mColor, Thickness 0.1

    # Vertical hatching for Q
    var hx = xa
    while hx <= xb + 1e-9:
      let qv = qAt(hx, false)
      let y0 = qBaseY
      let y1 = qWorld(qv)
      if abs(y1 - y0) > 1e-6:
        doc.add lineSection(
          Point2 vec2(bx(hx), y0),
          Point2 vec2(bx(hx), y1)
        ), qColor
      hx += settings.hatchSpacing

    # Vertical hatching for M
    hx = xa
    while hx <= xb + 1e-9:
      let mv = mAt(hx, false)
      let y0 = mBaseY
      let y1 = mWorld(mv)
      if abs(y1 - y0) > 1e-6:
        doc.add lineSection(
          Point2 vec2(bx(hx), y0),
          Point2 vec2(bx(hx), y1)
        ), mColor
      hx += settings.hatchSpacing

  # Close left and right edges of diagrams
  let qaLeft = qAt(keyXs[0], false)
  let qaRight = qAt(keyXs[^1], true)
  let maLeft = mAt(keyXs[0], false)
  let maRight = mAt(keyXs[^1], true)
  doc.add lineSection(
    Point2 vec2(bx(keyXs[0]), qBaseY),
    Point2 vec2(bx(keyXs[0]), qWorld(qaLeft))
  ), qColor
  doc.add lineSection(
    Point2 vec2(bx(keyXs[^1]), qBaseY),
    Point2 vec2(bx(keyXs[^1]), qWorld(qaRight))
  ), qColor
  doc.add lineSection(
    Point2 vec2(bx(keyXs[0]), mBaseY),
    Point2 vec2(bx(keyXs[0]), mWorld(maLeft))
  ), mColor
  doc.add lineSection(
    Point2 vec2(bx(keyXs[^1]), mBaseY),
    Point2 vec2(bx(keyXs[^1]), mWorld(maRight))
  ), mColor

  # Vertical jump lines and labels at each breakpoint
  for xi in keyXs:
    let qL = qAt(xi, true)   # left limit (include forces at xi)
    let qR = qAt(xi, false)  # right limit (exclude forces at xi)
    let mL = mAt(xi, true)
    let mR = mAt(xi, false)

    # Draw jump line if values differ
    if abs(qL - qR) > 1e-9:
      doc.add lineSection(
        Point2 vec2(bx(xi), qWorld(qL)),
        Point2 vec2(bx(xi), qWorld(qR))
      ), qColor
    if abs(mL - mR) > 1e-9:
      doc.add lineSection(
        Point2 vec2(bx(xi), mWorld(mL)),
        Point2 vec2(bx(xi), mWorld(mR))
      ), mColor

    # Labels: show left value to the left, right value to the right
    let qLy = qWorld(qL)
    let qRy = qWorld(qR)
    let mLy = mWorld(mL)
    let mRy = mWorld(mR)

    # Label on left side (value just before xi)
    doc.add Text labelVal(qL, qRef, 1000, qName):
      Position2 Point2 vec2(bx(xi) - textMargin, qLy + (if qL > 0: -textMargin else: textMargin))
      (if qL > 0: PositionAtBottomRight else: PositionAtTopRight)
      dimensionFontSize
      qColor
    # Label on right side (value just after xi)
    doc.add Text labelVal(qR, qRef, 1000, qName):
      Position2 Point2 vec2(bx(xi) + textMargin, qRy + (if qR > 0: -textMargin else: textMargin))
      (if qR > 0: PositionAtBottomLeft else: PositionAtTopLeft)
      dimensionFontSize
      qColor

    doc.add Text labelVal(mL, mRef, 1000, mName):
      Position2 Point2 vec2(bx(xi) - textMargin, mLy + (if mL > 0: -textMargin else: textMargin))
      (if mL > 0: PositionAtBottomRight else: PositionAtTopRight)
      dimensionFontSize
      mColor
    doc.add Text labelVal(mR, mRef, 1000, mName):
      Position2 Point2 vec2(bx(xi) + textMargin, mRy + (if mR > 0: -textMargin else: textMargin))
      (if mR > 0: PositionAtBottomLeft else: PositionAtTopLeft)
      dimensionFontSize
      mColor


mainModule:
  let beam = Beam(
    segments: BeamSegment(section: rectSection, length: l).repeat(5),
    loads: @[
      DistributedLoad(x: 1*l .. 4*l, load: -q),
    ],
    forces: @[
      ConcentratedForce(x: 5*l, force: q*l),
      ConcentratedForce(x: 2*l, force: -q*l),
    ],
    moments: @[
      RotationalMoment(x: 5*l, moment: q*l.pow(2)),
      RotationalMoment(x: 2*l, moment: -q*l.pow(2)),
    ],
    fixedPositions: @[0*l],
  )
  

  draw beam
  doc.drawDimensions()

  let refF = q * l
  let refM = q * l * l
  let h = beam.meterSize * 1
  drawQM(beam, DiagramSettings(
    qScale: h / refF / 4,
    mScale: h / refM / 4,
    qOffset: beam.meterSize * 2,
    mGap: beam.meterSize * 3,
    hatchSpacing: beam.meterSize / 32,
    displayInC: true,
  ))

