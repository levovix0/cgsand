import std/[sequtils]
import sandbox, geom2d
import annotations/[dimensions]
import ./[shafts]


proc mm*(m: float): float = m * 1e-3

let mainLine = Thickness 0.05
let dimFontSize = FontSize 0.5


proc drawConjunction(doc: var World, origin: Position2, dir: Vec2, conjunction: ShaftConjunction, h: float, scale: float) =
  let angle = dir.planarAngle
  proc pt(v: Vec2): Point2 = origin + v.rotate(angle) * scale

  case conjunction.kind
  of None:
    doc.add lineSection(
      vec2(0, -h/2).pt,
      vec2(0, h/2).pt
    ), mainLine
  
  of Bevel:
    doc.add lineSection(
      vec2(0, -h/2 + conjunction.radius).pt,
      vec2(0, h/2 - conjunction.radius).pt
    ), mainLine
    doc.add lineSection(
      vec2(0, -h/2 + conjunction.radius).pt,
      vec2(conjunction.radius, -h/2).pt
    ), mainLine
    doc.add lineSection(
      vec2(0, h/2 - conjunction.radius).pt,
      vec2(conjunction.radius, h/2).pt
    ), mainLine
  
  of Fillet:
    doc.add lineSection(
      vec2(0, -h/2 + conjunction.radius).pt,
      vec2(0, h/2 - conjunction.radius).pt
    ), mainLine
    doc.add circleArc(
      center = vec2(conjunction.radius, -h/2 - conjunction.radius).pt,
      radius = conjunction.radius * scale,
      startAngle = 0, endAngle = -Pi/2,
    ), mainLine
    doc.add circleArc(
      center = vec2(conjunction.radius, h/2 + conjunction.radius).pt,
      radius = conjunction.radius * scale,
      startAngle = 0, endAngle = Pi/2,
    ), mainLine


proc draw2d*(doc: var World, shaft: Shaft, origin: Position2, scale: float = 100) =
  proc pt(v: Vec2): Point2 = origin + v * scale

  proc height(segment: ShaftSegment): float =
    case segment.section.shape
    of Circle: segment.section.circle.radius*2
    of Rectangle: max(segment.section.rectangle.w, segment.section.rectangle.h)
  
  let maxH = shaft.segments.mapIt(it.height).max
  let dimlineY = maxH/2 + 5/scale

  var x = 0.0
  for segment in shaft.segments:
    let h = segment.height
    
    let leftOffset = case segment.left.kind
      of Bevel, Fillet: segment.left.radius
      of None: 0

    let rightOffset = case segment.right.kind
      of Bevel, Fillet: segment.right.radius
      of None: 0
    
    doc.drawConjunction(vec2(x, 0).pt, vec2(1, 0), segment.left, h, scale=scale)
    doc.drawConjunction(vec2(x + segment.length, 0).pt, vec2(-1, 0), segment.right, h, scale=scale)

    doc.add lineSection(
      vec2(x + leftOffset, -h/2).pt,
      vec2(x + segment.length - rightOffset, -h/2).pt
    ), mainLine
    doc.add lineSection(
      vec2(x + leftOffset, h/2).pt,
      vec2(x + segment.length - rightOffset, h/2).pt
    ), mainLine
    
    for (x, conjunction, dir) in [(x, segment.left, 1.0), (x + segment.length, segment.right, -1.0)]:
      doc.add lineSection(
        vec2(x + conjunction.radius * dir, -h/2).pt,
        vec2(x + conjunction.radius * dir, h/2).pt
      ), mainLine
    
    doc.add LinearDimension2(
      a: vec2(x, h/2 - leftOffset).pt,
      b: vec2(x + segment.length, 0).pt,
      dir: vec2(1, 0),
      dimline: vec2(x, dimlineY).pt,
    ), dimensionText segment.length * 1000, dimFontSize
    
    doc.add LinearDimension2(
      a: vec2(x + segment.length - rightOffset - 0.5/scale, h/2).pt,
      b: vec2(x + segment.length - rightOffset - 0.5/scale, -h/2).pt,
      dir: vec2(0, 1),
      dimline: vec2(x + segment.length - rightOffset - 0.5/scale, 0).pt,
    ), dimensionText h * 1000, dimFontSize

    x += segment.length
  
  doc.drawDimensions()



mainModule:
  let bevel = ShaftConjunction(kind: Bevel, radius: 1.6.mm)
  let fillet = ShaftConjunction(kind: Fillet, radius: 2.mm)
  let shaft = Shaft(
    segments: @[
      cylindricSegment(d = 40.mm, l = 82.mm, left = bevel, right = fillet),
      cylindricSegment(d = 45.mm, l = 87.mm),
      cylindricSegment(d = 50.mm, l = 22.5.mm),
      cylindricSegment(d = 68.75.mm, l = 44.875.mm),
      cylindricSegment(d = 50.mm, l = 22.5.mm),
      cylindricSegment(d = 45.mm, l = 23.mm, right = bevel),
    ]
  )

  doc.draw2d shaft, point2(0, 0)


