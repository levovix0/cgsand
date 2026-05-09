import std/[sequtils, strutils]
import pkg/pixie/paths
import sandbox, geom2d

const useCustomFont = not defined(nimcheck)

when useCustomFont:
  import text


type
  SectionShape* = enum
    Circle
    Rectangle

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
    
    material*: Material
    unknownDimensions*: bool



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
  


  LinearDimension2* = object
    a*, b*: Point2
    dir*: Vec2
    dimline*: Point2

  DimensionText* = string
  ArrowSize* = float


let darkTheme = true


let globals {.used.} = doc.spawn(
  CanvasSettings(
    autoSize: true,
    margin: vec2(2, 2),
  ),
  AxisYDown,
  (if darkTheme: Foreground color(0.75, 0.75, 0.8) else: Foreground color(0, 0, 0)),
  FontSize 1,
)
if not darkTheme:
  doc.update globals: add Background color(1, 1, 1)


when useCustomFont:
  let font = findSystemFont(@["firacode", "tinos", "timesnewroman", "dejavuserif"] & defaultSystemFonts)
  doc.update globals: add font

let textMargin = 0.2
let dimensionFontSize = FontSize 0.5
var loadColor: Color = doc[globals, Foreground]
var forceColor: Color = doc[globals, Foreground]
var momentColor: Color = doc[globals, Foreground]
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



proc `$`(x: float): string =
  result = system.`$` x.round(2)
  result.removeSuffix ".0"

proc addName(x: string, name: string): string =
  if x == "1": result = name
  else: result = x & " " & name



proc addArrow(to: Point2, dir: NormalVec2, size: float, color = doc[globals, Foreground]) =
  # todo: add something like paths to sigeo
  let p = newPath()
  p.moveTo vmath.vec2 to.Vec2
  p.lineTo vmath.vec2 (to - (dir * size).rotate(Pi / 16)).Vec2
  p.lineTo vmath.vec2 (to - (dir * size).rotate(-Pi / 16)).Vec2
  p.closePath()
  doc.add p, Background color



proc drawDimensions* =
  doc.forEach (dim: LinearDimension2, text: opt DimensionText, arrowSize: ArrowSize||0.5, fontSize: FontSize||doc[globals, FontSize]):
    let dimline_a = dim.dimline + projectToAxis(dim.a - dim.dimline, dim.dir)
    let dimline_b = dim.dimline + projectToAxis(dim.b - dim.dimline, dim.dir)
    doc.add lineSection(dim.a, dimline_a)
    doc.add lineSection(dim.b, dimline_b)
    doc.add lineSection(dimline_a, dimline_b)

    if has DimensionText:
      doc.add Text text:
        PositionAtBottom
        Position2 lineSection(dimline_a, dimline_b).center + vec2(0, -textMargin)
        fontSize
    
    addArrow(dimline_a, dimline_a - dimline_b, arrowSize)
    addArrow(dimline_b, dimline_b - dimline_a, arrowSize)


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
      dimline: line.startPoint + vec2(0, beam.meterSize * 1.5)
    ), DimensionText $(segment.length * 1000), dimensionFontSize
    
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


draw beam
drawDimensions()

