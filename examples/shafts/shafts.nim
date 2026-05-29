import std/sequtils
import sandbox, geom2d
import annotations/[dimensions]


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



let darkTheme* = cache[].mgetOrPut(DarkTheme, true)

let mainLine* = PixelThickness 3
let dimFontSize* = FontSize 0.5


proc setShaftsGlobals*(globals: EntityId) =
  doc.update globals: add OwnerModule "shafts"
  doc.update globals: add CanvasSettings(
    autoSize: true,
    margin: vec2(2, 2),
  )
  doc.update globals: add AxisYDown
  doc.update globals: add (if darkTheme: Foreground color(0.75, 0.75, 0.8) else: Foreground color(0, 0, 0))
  doc.update globals: add FontSize 1

  if not darkTheme:
    doc.update globals: add Background color(1, 1, 1)

if not doc.hasComponent(globals, OwnerModule):
  setShaftsGlobals(globals)



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



proc drawConjunction(sketch: World, origin: Position2, dir: Vec2, conjunction: ShaftConjunction, h: float, scale: float) =
  let angle = dir.planarAngle
  proc pt(v: Vec2): Point2 = origin + v.rotate(angle) * scale

  case conjunction.kind
  of None:
    sketch.add lineSection(
      vec2(0, -h/2).pt,
      vec2(0, h/2).pt
    ), mainLine

  of Bevel:
    sketch.add lineSection(
      vec2(0, -h/2 + conjunction.radius).pt,
      vec2(0, h/2 - conjunction.radius).pt
    ), mainLine
    sketch.add lineSection(
      vec2(0, -h/2 + conjunction.radius).pt,
      vec2(conjunction.radius, -h/2).pt
    ), mainLine
    sketch.add lineSection(
      vec2(0, h/2 - conjunction.radius).pt,
      vec2(conjunction.radius, h/2).pt
    ), mainLine

  of Fillet:
    sketch.add lineSection(
      vec2(0, -h/2 + conjunction.radius).pt,
      vec2(0, h/2 - conjunction.radius).pt
    ), mainLine
    sketch.add circleArc(
      center = vec2(conjunction.radius, -h/2 - conjunction.radius).pt,
      radius = conjunction.radius * scale,
      startAngle = 0, endAngle = -Pi/2,
    ), mainLine
    sketch.add circleArc(
      center = vec2(conjunction.radius, h/2 + conjunction.radius).pt,
      radius = conjunction.radius * scale,
      startAngle = 0, endAngle = Pi/2,
    ), mainLine


proc draw*(shaft: Shaft, origin: Position2 = point2(), scale: float = 100, dimensions = doc, sketch = doc) =
  proc pt(v: Vec2): Point2 = origin + v * scale

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
      sketch.drawConjunction(vec2(x, 0).pt, vec2(1, 0), segment.left, h, scale=scale)
      sketch.drawConjunction(vec2(x + segment.length, 0).pt, vec2(-1, 0), segment.right, h, scale=scale)

      sketch.add lineSection(
        vec2(x + leftOffset, -h/2).pt,
        vec2(x + segment.length - rightOffset, -h/2).pt
      ), mainLine
      sketch.add lineSection(
        vec2(x + leftOffset, h/2).pt,
        vec2(x + segment.length - rightOffset, h/2).pt
      ), mainLine

      for (xc, conjunction, dir) in [(x, segment.left, 1.0), (x + segment.length, segment.right, -1.0)]:
        sketch.add lineSection(
          vec2(xc + conjunction.radius * dir, -h/2).pt,
          vec2(xc + conjunction.radius * dir, h/2).pt
        ), mainLine

      if segment.section.shape == Gear:
        let g = segment.section.gear
        for yc in [-h/2 + (g.adhendiumDiameter - g.rootDiameter)/2, h/2 - (g.adhendiumDiameter - g.rootDiameter)/2]:
          sketch.add lineSection(
            vec2(x, yc).pt,
            vec2(x + segment.length, yc).pt
          ), mainLine
        for yc in [-h/2 + (g.adhendiumDiameter - g.pitchDiameter)/2, h/2 - (g.adhendiumDiameter - g.pitchDiameter)/2]:
          sketch.add lineSection(
            vec2(x, yc).pt,
            vec2(x + segment.length, yc).pt
          )

    if dimensions != nil:
      dimensions.add LinearDimension2(
        a: vec2(x, h/2 - leftOffset).pt,
        b: vec2(x + segment.length, h/2 - rightOffset).pt,
        dir: vec2(1, 0),
        dimline: vec2(x, dimlineY).pt,
      ), dimensionText segment.length * 1000, dimFontSize

      dimensions.add LinearDimension2(
        a: vec2(x + segment.length - rightOffset - 0.5/scale, h/2).pt,
        b: vec2(x + segment.length - rightOffset - 0.5/scale, -h/2).pt,
        dir: vec2(0, 1),
        dimline: vec2(x + segment.length - rightOffset - 0.5/scale, 0).pt,
      ), dimensionText h * 1000, dimFontSize

    x += segment.length

  if dimensions != nil:
    dimensions.drawDimensions()



