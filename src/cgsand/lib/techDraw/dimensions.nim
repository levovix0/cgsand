import std/[strutils]
import ../[sandbox, geom2d]


type
  LinearDimension2* = object
    a*, b*: Point2
    dir*: V2
    dimline*: Point2

  DimensionText* = string
  ArrowSize* = float

  FigureBracket* = object
    a*, b*: Point2
    h*: V2
    power*: float = 1

  AlreadyDrawn* = object

let textMargin* = 0.2



proc addArrow*(to: Point2, dir: NormalVec2, size: float, color = doc.foreground, noBounds = false) =
  # todo: proc arrow(to: Point2, dir: NormalVec2, size: float, color = doc.foreground): (Path, Background)
  var p = Path2()
  p.add to
  p.add to - (dir * size).rotate(Pi / 16)
  p.add to - (dir * size).rotate(-Pi / 16)
  close p
  if noBounds:
    doc.add p, Background color, NoBounds()
  else:
    doc.add p, Background color



proc dimensionText*(x: float, units = ""): DimensionText =
  result = system.`$` x.round(2)
  result.removeSuffix ".0"
  if units != "":
    result.add " " & units



proc drawDimensions*(doc: World) =
  var entIds: seq[EntityId]

  doc.forEach (
    id: EntityId,
    dim: LinearDimension2,
    text: opt DimensionText,
    arrowSize: ArrowSize||0.5,
    fontSize: FontSize||doc.fontSize,
    opt NoBounds,
    not AlreadyDrawn,
  ):
    entIds.add id
    var drawnIds: seq[EntityId]

    let dimline_a = dim.dimline + projectToAxis(dim.a - dim.dimline, dim.dir)
    let dimline_b = dim.dimline + projectToAxis(dim.b - dim.dimline, dim.dir)
    drawnIds.add doc.spawn line(dim.a, dimline_a)
    drawnIds.add doc.spawn line(dim.b, dimline_b)
    drawnIds.add doc.spawn line(dimline_a, dimline_b)

    if has DimensionText:
      let angle = (dimline_b - dimline_a).toPolar.theta
      drawnIds.add:
        doc.spawn Text text:
          PositionAtBottom
          Position2 line(dimline_a, dimline_b).center
          Transform3 (rotateZ(if abs(angle) < Pi/2: angle else: Pi + angle) * translate(v3(0, fontSize * -textMargin, 0)))
          fontSize

    addArrow(dimline_a, dimline_a - dimline_b, arrowSize, noBounds = has NoBounds)
    addArrow(dimline_b, dimline_b - dimline_a, arrowSize, noBounds = has NoBounds)

    if has NoBounds:
      for x in drawnIds:
        doc.update x: add NoBounds()

  for x in entIds:
    doc.update x: add AlreadyDrawn()


proc drawFigureBrackets*(doc: World) =
  var entIds: seq[EntityId]

  doc.forEach (id: EntityId, f: FigureBracket, not AlreadyDrawn):
    entIds.add id

    var points: array[128, Point2]
    let w = f.b - f.a
    for i, p in points.mpairs:
      let x = i / (points.len - 1)
      let y =
        if x < (1/4): sin((x - (0/4)) * 4 * Pi/2).pow(1/f.power) / 2
        elif x < (2/4): 0.5 + (1 - sin((x - (1/4)) * 4 * Pi/2 + Pi/2)).pow(f.power*2) / 2
        elif x < (3/4): 0.5 + (1 - sin((1 - (x - (2/4)) * 4) * Pi/2 + Pi/2)).pow(f.power*2) / 2
        else: sin((1 - ((x - (3/4)) * 4)) * Pi/2).pow(1/f.power) / 2
      p = f.a + w * x + f.h * y

    for i in 0..<(points.len - 1):
      doc.add line(points[i], points[i+1])

  for x in entIds:
    doc.update x: add AlreadyDrawn()
