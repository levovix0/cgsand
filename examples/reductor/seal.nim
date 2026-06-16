import std/[tables]
import sandbox, geom2d, tabledef
import pkg/[vmath]
import pkg/sigeo/macros/cursors
import ./[drawingGlobals]


type
  SealDesc* = object
    d*: float
      ## inner diameter (shaft / bore), m

  SealGeomParams* = object
    ## images/seal_geom.jpg  # todo: draw dimensions in the script
    
    d*: float
      ## inner diameter (shaft / bore), m
    D*: float
      ## outer diameter (press-fit into housing), m
    h*: float
      ## width of the seal (axial), m


proc mm(v: float): float = v / 1e3



columnTable dims, `const`:
  d   | D   | h
  11  | 26  | 7
  14  | 28  | 7
  16  | 30  | 7
  17  | 32  | 7
  19  | 35  | 7
  22  | 40  | 10
  24  | 41  | 10
  25  | 42  | 10
  26  | 45  | 10
  32  | 52  | 10
  38  | 58  | 10
  40  | 60  | 10
  42  | 62  | 10
  45  | 65  | 10
  50  | 70  | 10
  52  | 75  | 10
  58  | 80  | 12
  60  | 85  | 12
  65  | 90  | 12
  71  | 95  | 12
  75  | 100 | 12
  80  | 105 | 12
  85  | 110 | 12
  95  | 120 | 12
  100 | 125 | 12



converter autoComputeGeomParams*(desc: SealDesc): SealGeomParams =
  template O: var SealGeomParams = result
  O.d = desc.d

  for i, max_d in dims.d:
    if max_d >= (desc.d * 1e3).int:
      O.D = dims.D[i].float.mm
      O.h = dims.h[i].float.mm
      break


proc bounds*(g: SealGeomParams): Bounds2 =
  bounds2(p2(0, -g.D/2), p2(g.h, g.D/2))


proc draw*(g: SealGeomParams, origin: Position2 = point2(), scale: float = 1, axis: V2 = v2(1, 0), sketch = doc, hideBackLines = false) =
  let x = axis.normalize
  let y = x.rotate(Pi/2)
  proc sc(v: float): float = v * scale
  proc vt(v: V2): V2 = v.x.sc * x + v.y.sc * y
  proc pt(v: V2): Point2 = origin + v.vt
  if sketch == nil: return

  let contour = @[
    v2(100, 0),
    v2(100, 30),
    v2(40, 30),  # 2
    v2(40, 70),  # 3
    v2(60, 70),  # 4
    v2(90, 70),  # 5
    v2(90, 90),
    v2(90-17.5, 100),
    v2(90-17.5*2, 90),
    v2(90-17.5*2, 88),
    v2(10, 67),
    v2(0, 57),
    v2(0, 52),
    v2(10, 52),
    v2(10, 32),
    v2(0, 32),
    v2(0, 22),
    v2(22, 0),
  ]

  let armored = @[
    v2(100-17.5, 10),
    v2(20, 10),  # 1
    v2(20, 52),
    v2(30, 52),
    v2(30, 20),  # 4
    v2(100-17.5, 20),
  ]

  let fillets = {
    2: 5.0,
    3: 5.0,
  }.toTable

  let armoredFillets = {
    1: 12.0,
    4: 2.0,
  }.toTable

  let scaleX = g.h / 100
  let scaleY = (g.D - g.d)/2 / 100

  proc world(p: V2, top: bool): V2 =
    v2(p.x * scaleX, (g.D/2 - p.y * scaleY) * (if top: -1 else: 1))
  
  proc world(v: AngleDirection, top: bool): AngleDirection =
    if top: v
    else: v.bool.not.AngleDirection

  for top in [false, true]:
    # todo: either something in ecs or in sigeo interface macro or in both breaks,
    # if Path2 is allocated on the stack, or is passed to ecs as Path2
    
    letCur profile: create(Path2)[]
    letCur armoredProfile: create(Path2)[]

    block:
      letCur p: profile
      for i in 0 ..< contour.len:
        if i == 5:
          p.add circleArc(v2(67.5, 70).world(top).pt, (7.5 * min(scaleX, scaleY)).sc, Pi, 0, counterclockwise.world(top))
          p.add circleArc(v2(82.5, 70).world(top).pt, (7.5 * min(scaleX, scaleY)).sc, Pi, 0, clockwise.world(top))

        p.add contour[i].world(top).pt

        if fillets.hasKey(i - 1):
          p.addFillet (fillets[i-1] * min(scaleX, scaleY)).sc
      
      close p
      sketch.add p.Curve2, doc.foreground, mainLine

    block:
      letCur p: armoredProfile
      for i in 0 ..< armored.len:
        p.add armored[i].world(top).pt

        if armoredFillets.hasKey(i - 1):
          p.addFillet (armoredFillets[i-1] * min(scaleX, scaleY)).sc
      
      close p
      sketch.add p.Curve2, doc.foreground, mainLine
      sketch.add p.Curve2, Hatching(period: (g.D - g.d) / 70 * scale), hatchingLine
      sketch.add p.Curve2, Hatching(angle: -Pi/4, period: (g.D - g.d) / 70 * scale), hatchingLine
    
    block:
      letCur p: create(Path2)[]
      for i in 0..4: p.add profile.curves[i]
      for i in 5..8: p.add armoredProfile.curves[i]
      close p
      # sketch.add p.Curve2, Foreground color(1, 0.4, 0.4), PixelThickness 5
      sketch.add p.Curve2, Hatching(period: (g.D - g.d) / 40 * scale), hatchingLine
    
    block:
      letCur p: create(Path2)[]
      for i in countdown(profile.curves.high, 5): p.add profile.curves[i].cut(1, 0)
      for i in countdown(4, 0): p.add armoredProfile.curves[i].cut(1, 0)
      close p
      # sketch.add p.Curve2, Foreground color(1, 0.4, 0.4), PixelThickness 5
      sketch.add p.Curve2, Hatching(period: (g.D - g.d) / 40 * scale), hatchingLine
    
    block:
      letCur p: create(CircleArc2)[]
      p = circleArc(v2(67.5, 70).world(top).pt, (7.5 * min(scaleX, scaleY)).sc)
      sketch.add p, doc.foreground, mainLine
      sketch.add p.Curve2, Hatching(period: (g.D - g.d) / 70 * scale), hatchingLine
    
    block:
      letCur p: create(CircleArc2)[]
      p = circleArc(v2(67.5, 70).world(top).pt, (5 * min(scaleX, scaleY)).sc)
      sketch.add p, doc.foreground, mainLine
      sketch.add p.Curve2, Hatching(angle: -Pi/4, period: (g.D - g.d) / 70 * scale), hatchingLine
    
    block:
      for i in {1, 6..11, 15}:
        sketch.add lineSection(contour[i].world(top).pt, (
          if hideBackLines: v2(contour[i].x, 100).world(top)
          else: v2(v2(contour[i].x, 100).world(top).x, 0)).pt
        ), mainLine


proc sketch*(g: SealGeomParams, hideBackLines = false): World =
  result = World()
  withDocument result:
    let globals = doc.spawn()
    setDrawingGlobals(globals)
    draw(g, sketch = result, hideBackLines = hideBackLines)




mainModule:
  draw SealDesc(d: 48.mm),
    origin = p2(0, 0), scale = 1000, hideBackLines = true
