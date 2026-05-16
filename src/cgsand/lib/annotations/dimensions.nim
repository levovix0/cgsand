import std/[strutils]
import sandbox, geom2d
import pkg/pixie/paths


type
  LinearDimension2* = object
    a*, b*: Point2
    dir*: Vec2
    dimline*: Point2

  DimensionText* = string
  ArrowSize* = float

  DrawnDimension = object

let textMargin* = 0.2



proc addArrow*(to: Point2, dir: NormalVec2, size: float, color = doc.foreground) =
  # todo: add something like paths to sigeo
  # todo: proc arrow(to: Point2, dir: NormalVec2, size: float, color = doc.foreground): (Path, Background)
  let p = newPath()
  p.moveTo vmath.vec2 to.Vec2
  p.lineTo vmath.vec2 (to - (dir * size).rotate(Pi / 16)).Vec2
  p.lineTo vmath.vec2 (to - (dir * size).rotate(-Pi / 16)).Vec2
  p.closePath()
  doc.add p, Background color



proc dimensionText*(x: float, units = ""): DimensionText =
  result = system.`$` x.round(2)
  result.removeSuffix ".0"
  if units != "":
    result.add " " & units



proc drawDimensions*(doc: var World) =
  var dimEntIds: seq[EntityId]

  doc.forEach (
    id: EntityId,
    dim: LinearDimension2,
    text: opt DimensionText,
    arrowSize: ArrowSize||0.5,
    fontSize: FontSize||doc.fontSize,
    not DrawnDimension,
  ):
    dimEntIds.add id

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
  
  for x in dimEntIds:
    doc.update x: add DrawnDimension()

