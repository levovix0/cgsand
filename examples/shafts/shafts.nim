import std/sequtils
import sandbox, geom2d
import annotations/[dimensions]
import ../reductor/[drawingGlobals]


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


  GearSection* = object
    modulo*: float  # in meters
    teethCount*: int

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
      gear*: GearSection
    
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




proc adhendiumDiameter*(g: GearSection): float =
  g.modulo * (g.teethCount.float + 2)

proc pitchDiameter*(g: GearSection): float =
  g.modulo * (g.teethCount.float)

proc rootDiameter*(g: GearSection): float =
  g.modulo * (g.teethCount.float - 2.5)


proc gearSegment*(
  l: float,
  z: int, modulo: float,
  material = steel,
  left = ShaftConjunction(),
  right = ShaftConjunction(),
): ShaftSegment =
  ShaftSegment(
    section: Section(shape: Gear, gear: GearSection(teethCount: z, modulo: modulo), material: material),
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
    sketch.add lineSection(
      v2(0, -h/2).pt,
      v2(0, h/2).pt
    ), mainLine

  of Bevel:
    sketch.add lineSection(
      v2(0, -h/2 + conjunction.radius).pt,
      v2(0, h/2 - conjunction.radius).pt
    ), mainLine
    sketch.add lineSection(
      v2(0, -h/2 + conjunction.radius).pt,
      v2(conjunction.radius, -h/2).pt
    ), mainLine
    sketch.add lineSection(
      v2(0, h/2 - conjunction.radius).pt,
      v2(conjunction.radius, h/2).pt
    ), mainLine

  of Fillet:
    sketch.add lineSection(
      v2(0, -h/2 + conjunction.radius).pt,
      v2(0, h/2 - conjunction.radius).pt
    ), mainLine
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


proc draw*(shaft: Shaft, origin: Position2 = point2(), scale: float = 100, dimensions = doc, sketch = doc) =
  proc pt(v: V2): Point2 = origin + v * scale

  proc height(segment: ShaftSegment): float =
    case segment.section.shape
    of Circle: segment.section.circle.radius*2
    of Rectangle: max(segment.section.rectangle.w, segment.section.rectangle.h)
    of Gear: segment.section.gear.adhendiumDiameter

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
      sketch.drawConjunction(v2(x, 0).pt, v2(1, 0), segment.left, h, scale=scale)
      sketch.drawConjunction(v2(x + segment.length, 0).pt, v2(-1, 0), segment.right, h, scale=scale)

      sketch.add lineSection(
        v2(x + leftOffset, -h/2).pt,
        v2(x + segment.length - rightOffset, -h/2).pt
      ), mainLine
      sketch.add lineSection(
        v2(x + leftOffset, h/2).pt,
        v2(x + segment.length - rightOffset, h/2).pt
      ), mainLine

      for (xc, conjunction, dir) in [(x, segment.left, 1.0), (x + segment.length, segment.right, -1.0)]:
        sketch.add lineSection(
          v2(xc + conjunction.radius * dir, -h/2).pt,
          v2(xc + conjunction.radius * dir, h/2).pt
        ), mainLine

      if segment.section.shape == Gear:
        let g = segment.section.gear
        for yc in [-h/2 + (g.adhendiumDiameter - g.rootDiameter)/2, h/2 - (g.adhendiumDiameter - g.rootDiameter)/2]:
          sketch.add lineSection(
            v2(x, yc).pt,
            v2(x + segment.length, yc).pt
          ), mainLine
        for yc in [-h/2 + (g.adhendiumDiameter - g.pitchDiameter)/2, h/2 - (g.adhendiumDiameter - g.pitchDiameter)/2]:
          sketch.add lineSection(
            v2(x, yc).pt,
            v2(x + segment.length, yc).pt
          ), axialLine

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



