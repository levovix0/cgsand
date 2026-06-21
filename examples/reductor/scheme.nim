import sandbox, geom2d, techDraw
import ./bearings


type
  RectUgo* = object
    size*: V2

  HousingUgo* = object
    size*: V2
    radius*: float

  BearingUgo* = object
    size*: V2

  CouplingUgo* = object
    size*: V2

  GearUgo* = object
    size*: V2

  ChainUgo* = object
    hw*, hh*: float

  DrumUgo* = object
    size*: V2

  CircleLabelUgo* = object
    r*: float
    text*: string

  AnyUgo* =
    RectUgo | HousingUgo | BearingUgo | CouplingUgo | GearUgo | ChainUgo | DrumUgo | CircleLabelUgo


proc drawSmallCross(c: Point2, sz: float) =
  doc.add line(c + v2(sz, sz), c + v2(-sz, -sz)), thinLine
  doc.add line(c + v2(sz, -sz), c + v2(-sz, sz)), thinLine


proc draw*(g: RectUgo) =
  ## todo: create a unified way to make a rectangle
  let h = g.size / 2
  doc.add line(p2(-h.x, -h.y), p2(+h.x, -h.y)), mainLine
  doc.add line(p2(+h.x, -h.y), p2(+h.x, +h.y)), mainLine
  doc.add line(p2(+h.x, +h.y), p2(-h.x, +h.y)), mainLine
  doc.add line(p2(-h.x, +h.y), p2(-h.x, -h.y)), mainLine


proc draw*(g: HousingUgo) =
  draw roundRect2geom(p2(0, 0), g.size, radius = g.radius)


proc draw*(g: BearingUgo) =
  doc.add line(p2(-g.size.x/2, -g.size.y/2), p2(+g.size.x/2, -g.size.y/2)), mainLine
  doc.add line(p2(-g.size.x/2, +g.size.y/2), p2(+g.size.x/2, +g.size.y/2)), mainLine


proc draw*(g: CouplingUgo) =
  doc.add line(p2(-g.size.x/2, -g.size.y/2), p2(-g.size.x/2, +g.size.y/2)), mainLine
  doc.add line(p2(+g.size.x/2, -g.size.y/2), p2(+g.size.x/2, +g.size.y/2)), mainLine


proc draw*(g: GearUgo) =
  let w = g.size.x / 2
  let h = g.size.y / 2
  let a = p2(-w, -h)
  let b = p2(+w, -h)
  let c = p2(+w, +h)
  let d = p2(-w, +h)
  for (p, q) in [(a, b), (b, c), (c, d), (d, a)]:
    doc.add line(p, q), mainLine
  drawSmallCross(p2(), min(w/4, h/4))


proc draw*(g: ChainUgo) =
  let top = p2(0, -g.hh)
  let bottom = p2(0, +g.hh)
  let left = p2(-g.hw, 0)
  let right = p2(+g.hw, 0)
  for (p, q) in [(top, right), (right, bottom), (bottom, left), (left, top)]:
    doc.add line(p, q), mainLine
  drawSmallCross(p2(), min(g.hw, g.hh)/4)


proc draw*(g: DrumUgo) =
  let h = g.size / 2
  doc.add line(p2(-h.x, -h.y), p2(+h.x, -h.y)), mainLine  # top
  doc.add line(p2(-h.x, -h.y), p2(-h.x, +h.y)), mainLine  # left
  doc.add line(p2(+h.x, -h.y), p2(+h.x, +h.y)), mainLine  # right
  drawSmallCross(p2(), min(g.size.x/8, g.size.y/8))
  var p = Path2()
  p.add p2(-h.x, h.y)
  p.x = -h.x/8
  p.add p2(-h.x/16, h.y*(1 - 1/16))
  p.add p2(+h.x/16, h.y*(1 + 1/16))
  p.add p2(+h.x/8, h.y)
  p.x = h.x
  doc.add p, thinLine


proc draw*(g: CircleLabelUgo) =
  doc.add circle(p2(0, 0), g.r), mainLine
  doc.add Text g.text:
    Position2 p2(0, 0)
    PositionAtCenter
    FontSize g.r


proc sketch*(g: AnyUgo): World =
  result = newTechDraw()
  withDocument result:
    mixin draw
    draw g



proc drawScheme*(sketch = doc) =
  if sketch == nil: return

  let bearing = SubWorld BearingUgo(size: v2(4.mm, 4.mm)).sketch()

  # gears
  let fastGear = doc.spawn SubWorld GearUgo(size: v2(22.mm, 20.mm)).sketch()
  let fastB = doc.bounds(fastGear)

  let slowGear = doc.spawn SubWorld GearUgo(size: v2(16.mm, 32.mm)).sketch():
    Position2 p2(fastB.center.x, fastB.max.y)
    PositionAtTop
  let slowB = doc.bounds(slowGear)

  # gearbox
  let gearsB = fastB + slowB
  let housing = doc.spawn SubWorld HousingUgo(size: gearsB.size + v2(12.mm, 16.mm), radius: 6.mm).sketch():
    Position2 gearsB.center
  let housingB = doc.bounds(housing)

  # motor
  let motor = doc.spawn SubWorld CircleLabelUgo(r: 8.mm, text: "M").sketch():
    Position2 p2(housingB.min.x - 30.mm, fastB.center.y)
  let motorB = doc.bounds(motor)

  let coupling = doc.spawn SubWorld CouplingUgo(size: v2(2.mm, 10.mm)).sketch():
    Position2 line(motorB.right, p2(housingB.left.x, fastB.left.y)).center
  let couplingB = doc.bounds(coupling)

  # chain
  let lowerChain = doc.spawn SubWorld ChainUgo(hw: 7.mm, hh: 11.mm).sketch():
    Position2 p2(housingB.max.x + 17.mm, slowB.center.y)
  let lowerB = doc.bounds(lowerChain)

  let upperChain = doc.spawn SubWorld ChainUgo(hw: 7.mm, hh: 11.mm).sketch():
    Position2 p2(lowerB.center.x, lowerB.center.y - 43.mm)
  let upperB = doc.bounds(upperChain)

  let drum = doc.spawn SubWorld DrumUgo(size: v2(15.mm, 32.mm)).sketch():
    Position2 p2(upperB.max.x + 22.mm, upperB.center.y)
    PositionAtCenter
  let drumB = doc.bounds(drum)

  doc.add line(lowerB.top, upperB.bottom), axialLine
  doc.add line(slowB.right, lowerB.left), mainLine
  doc.add line(slowB.left, p2(housingB.left.x - 2.mm, slowB.center.y)), mainLine
  doc.add line(fastB.right, p2(housingB.right.x + 2.mm, fastB.center.y)), mainLine
  doc.add line(motorB.right, couplingB.left), mainLine
  doc.add line(couplingB.right, fastB.left), mainLine
  doc.add line(upperB.right, drumB.left), mainLine
  doc.add line(drumB.right, drumB.right + v2(10.mm, 0)), mainLine

  doc.add line(slowB.topLeft + v2(0, 4.mm), slowB.topRight + v2(0, 4.mm)), thinLine
  doc.add line(slowB.topLeft + v2(0, 5.mm), slowB.topRight + v2(0, 5.mm)), thinLine

  doc.add bearing, Position2 drumB.right + v2(10.mm, 0), PositionAtRight
  doc.add bearing, Position2 line(upperB.right, drumB.left).center
  doc.add bearing, Position2 p2(housingB.left.x, slowB.center.y)
  doc.add bearing, Position2 p2(housingB.left.x, fastB.center.y)
  doc.add bearing, Position2 p2(housingB.right.x, slowB.center.y)
  doc.add bearing, Position2 p2(housingB.right.x, fastB.center.y)

  let allB = worldBounds(doc)
  doc.add SubWorld RectUgo(size: allB.size + v2(16.mm, 16.mm)).sketch():
    Position2 allB.center

defineSketch drawScheme



mainModule:
  doc[globals, CanvasSettings].margin = v2(5.mm, 5.mm)
  drawScheme()
