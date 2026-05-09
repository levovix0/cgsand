import std/sequtils
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


let globals {.used.} = doc.spawn(
  CanvasSettings(
    autoSize: true,
    margin: vec2(2, 2),
  ),
  AxisYDown,
  # Foreground color(0.75, 0.75, 0.8),
  Foreground color(0, 0, 0),
  Background color(1, 1, 1),
  FontSize 1,
)


when useCustomFont:
  let font = findSystemFont(@["firacode", "tinos", "timesnewroman", "dejavuserif"] & defaultSystemFonts)
  doc.update globals: add font

let textMargin = 0.2


let steel* = Material(tension_limit: 160 * 1e6)
let duralluminium* = Material(tension_limit: 80 * 1e6)

let rectSection = Section(shape: Rectangle, rectangle: (w: 1, h: 2), material: steel, unknownDimensions: true)
# let circle = Section(shape: Circle, circle: (radius: 1), material: duralluminium, unknownDimensions: true)

let q = 5.0 * 1e3
let l = 1.0

let beam = Beam(
  segments: BeamSegment(section: rectSection, length: l).repeat(5),
  loads: @[
    DistributedLoad(x: 2*l .. 5*l, load: -q),
  ],
  forces: @[
    ConcentratedForce(x: 6*l, force: q*l),
    ConcentratedForce(x: 3*l, force: -q*l),
  ],
  moments: @[
    RotationalMoment(x: 6*l, moment: q*l.pow(2)),
    RotationalMoment(x: 3*l, moment: -q*l.pow(2)),
  ],
  fixedPositions: @[0*l],
)


proc drawDimensions* =
  doc.forEach (dim: LinearDimension2, text: opt DimensionText, arrowSize: ArrowSize||0.5):
    let dimline_a = dim.dimline + projectToAxis(dim.a - dim.dimline, dim.dir)
    let dimline_b = dim.dimline + projectToAxis(dim.b - dim.dimline, dim.dir)
    doc.add lineSection(dim.a, dimline_a)
    doc.add lineSection(dim.b, dimline_b)
    doc.add lineSection(dimline_a, dimline_b)

    if has DimensionText:
      doc.add Text text:
        PositionAtBottom
        Position2 lineSection(dimline_a, dimline_b).center + vec2(0, -textMargin)
    
    block:  # todo: add paths to sigeo
      let p = newPath()
      p.moveTo vmath.vec2 (dimline_a).Vec2
      p.lineTo vmath.vec2 (dimline_a + ((dimline_b - dimline_a).normalize * arrowSize).rotate(Pi / 16)).Vec2
      p.lineTo vmath.vec2 (dimline_a + ((dimline_b - dimline_a).normalize * arrowSize).rotate(-Pi / 16)).Vec2
      p.closePath()
      doc.add copy p
      p.transform (
        translate(vmath.vec2 dimline_b.Vec2) *
        scale(vmath.vec2(-1, 1)) *
        translate(vmath.vec2 -dimline_a.Vec2)
      )
      doc.add p


proc draw*(beam: Beam) =
  var x = 0.0
  for i, segment in beam.segments:
    let length = segment.length * beam.meterSize
    let line = lineSection(beam.origin + vec2(x, 0), beam.origin + vec2(x + length, 0))

    doc.add line:
      Thickness 0.1
    
    doc.add Text $(i + 1):
      (if x notin beam.fixedPositions: PositionAtBottom else: PositionAtBottomLeft)
      Position2 beam.origin + vec2((if x notin beam.fixedPositions: x else: x + textMargin), -textMargin)

    doc.add LinearDimension2(
      a: line.startPoint,
      b: line.endPoint,
      dir: vec2(1, 0),
      dimline: line.startPoint + vec2(0, 4)
    ), DimensionText "l"
    
    x += length
  
  doc.add Text $(beam.segments.len + 1):
    (if x notin beam.fixedPositions: PositionAtBottom else: PositionAtBottomRight)
    Position2 beam.origin + vec2((if x notin beam.fixedPositions: x else: x - textMargin), -textMargin)

  for fp in beam.fixedPositions:
    let line = lineSection(
      beam.origin + vec2(fp * beam.meterSize, -beam.meterSize / 4),
      beam.origin + vec2(fp * beam.meterSize, beam.meterSize / 4)
    )
    doc.add line, Thickness 0.1
    for y in countup(0, int(beam.meterSize * 2), 1):
      let y = y / int(beam.meterSize)
      doc.add lineSection(line.pointAtParam(y), line.pointAtParam(y) + vec2(-0.5, 0.5))


draw beam
drawDimensions()

