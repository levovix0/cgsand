import std/sequtils
import sandbox, geom2d, techDraw
import techDraw/[dimensions]
import ./gears


const useCustomFont = not defined(nimcheck)

when useCustomFont:
  import text


type
  SectionShape* = enum
    Circle
    Rectangle
    Gear

  Material* = object
    tension_limit*: float  ## in pascals


  Section* = object
    case shape*: SectionShape
    of Circle:
      circle*: tuple[
        radius: float  # in meters
      ]
    
    of Rectangle:
      rectangle*: tuple[
        w, h: float  # in meters
      ]
    
    of Gear:
      gear*: GearDesc
    
    material*: Material
    unknownDimensions*: bool



  ShaftConjunctionKind* = enum
    None
    Bevel
    Fillet

  ShaftConjunction* = object
    kind*: ShaftConjunctionKind
    radius*: float

  ShaftSegment* = object
    length*: float  ## in meters
    section*: Section
    left*, right*: ShaftConjunction

  Shaft* = object
    segments*: seq[ShaftSegment]



when useCustomFont:
  let font = findSystemFont(@["firacode", "tinos", "timesnewroman", "dejavuserif"] & defaultSystemFonts)
  doc.update globals: add font



let steel* = Material(tension_limit: 160 * 1e6)

proc cylindricSegment*(
  l, d: float,
  material = steel,
  left = ShaftConjunction(),
  right = ShaftConjunction(),
): ShaftSegment =
  ShaftSegment(
    section: Section(shape: Circle, circle: (radius: d/2), material: material),
    length: l, left: left, right: right
  )



proc gearSegment*(
  l: float,
  z: int, modulo: float,
  material = steel,
  left = ShaftConjunction(),
  right = ShaftConjunction(),
  shaft_d: float = 0,
  reverseHatching = false,
): ShaftSegment =
  ShaftSegment(
    section: Section(shape: Gear, gear: GearDesc(
      teethCount: z, modulo: modulo, shaft_d: shaft_d, holes: shaft_d != 0, height: l,
      reverseHatching: reverseHatching,
    ), material: material),
    length: l, left: left, right: right
  )




proc `==`*(a, b: Section): bool =
  if a.shape != b.shape: return false
  case a.shape
  of Circle: a.circle == b.circle
  of Rectangle: a.rectangle == b.rectangle
  of Gear: a.gear == b.gear



proc drawConjunction(sketch: World, origin: Position2, dir: V2, conjunction: ShaftConjunction, h: float, scale: float) =
  let angle = dir.planarAngle
  proc pt(v: V2): Point2 = origin + v.rotate(angle) * scale

  case conjunction.kind
  of None:
    sketch.add line(
      v2(0, -h/2).pt,
      v2(0, h/2).pt
    ), mainLine

  of Bevel:
    sketch.add line(
      v2(0, -h/2 + conjunction.radius).pt,
      v2(0, h/2 - conjunction.radius).pt
    ), mainLine
    sketch.add line(
      v2(0, -h/2 + conjunction.radius).pt,
      v2(conjunction.radius, -h/2).pt
    ), mainLine
    sketch.add line(
      v2(0, h/2 - conjunction.radius).pt,
      v2(conjunction.radius, h/2).pt
    ), mainLine

  of Fillet:
    sketch.add line(
      v2(0, -h/2 + conjunction.radius).pt,
      v2(0, h/2 - conjunction.radius).pt
    ), mainLine
    if dir.x < 0:
      sketch.add circleArc(
        center = v2(conjunction.radius, -h/2 - conjunction.radius).pt,
        radius = conjunction.radius * scale,
        startAngle = 0, endAngle = -Pi/2,
      ), mainLine
      sketch.add circleArc(
        center = v2(conjunction.radius, h/2 + conjunction.radius).pt,
        radius = conjunction.radius * scale,
        startAngle = Pi/2, endAngle = 0,
      ), mainLine
    else:
      sketch.add circleArc(
        center = v2(conjunction.radius, -h/2 - conjunction.radius).pt,
        radius = conjunction.radius * scale,
        startAngle = Pi, endAngle = Pi/2,
      ), mainLine
      sketch.add circleArc(
        center = v2(conjunction.radius, h/2 + conjunction.radius).pt,
        radius = conjunction.radius * scale,
        startAngle = -Pi/2, endAngle = Pi,
      ), mainLine


proc draw*(shaft: Shaft, origin: Position2 = point2(), scale: float = 1, dimensions = doc, sketch = doc, hatching = true) =
  proc pt(v: V2): Point2 = origin + v * scale

  proc height(segment: ShaftSegment): float =
    case segment.section.shape
    of Circle: segment.section.circle.radius*2
    of Rectangle: max(segment.section.rectangle.w, segment.section.rectangle.h)
    of Gear: segment.section.gear.shaft_d

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

    if sketch != nil:
      if segment.section.shape == Gear:
        sketch.add SubWorld segment.section.gear.sketchSection(hatching = hatching, centralAxial = false, backLines = false),
          Position2 v2(x, 0).pt, Transform3 scale(v3(scale))

      if h != 0:
        sketch.drawConjunction(v2(x, 0).pt, v2(1, 0), segment.left, h, scale=scale)
        sketch.drawConjunction(v2(x + segment.length, 0).pt, v2(-1, 0), segment.right, h, scale=scale)

        sketch.add line(
          v2(x + leftOffset, -h/2).pt,
          v2(x + segment.length - rightOffset, -h/2).pt
        ), mainLine
        sketch.add line(
          v2(x + leftOffset, h/2).pt,
          v2(x + segment.length - rightOffset, h/2).pt
        ), mainLine

        for (xc, conjunction, dir) in [(x, segment.left, 1.0), (x + segment.length, segment.right, -1.0)]:
          if conjunction.kind != Fillet:
            sketch.add line(
              v2(xc + conjunction.radius * dir, -h/2).pt,
              v2(xc + conjunction.radius * dir, h/2).pt
            ), mainLine

    if dimensions != nil:
      dimensions.add LinearDimension2(
        a: v2(x, h/2 - leftOffset).pt,
        b: v2(x + segment.length, h/2 - rightOffset).pt,
        dir: v2(1, 0),
        dimline: v2(x, dimlineY).pt,
      ), dimensionText segment.length * 1000, dimFontSize

      dimensions.add LinearDimension2(
        a: v2(x + segment.length - rightOffset - 0.5/scale, h/2).pt,
        b: v2(x + segment.length - rightOffset - 0.5/scale, -h/2).pt,
        dir: v2(0, 1),
        dimline: v2(x + segment.length - rightOffset - 0.5/scale, 0).pt,
      ), dimensionText h * 1000, dimFontSize

    x += segment.length

  if dimensions != nil:
    dimensions.drawDimensions()

defineSketch draw


