import sandbox, geom2d, techDraw, tabledef
import std/[sequtils]
import pkg/[vmath]
import ./[seal]


type
  CapDesc* = object
    D*: float
      ## base cap diameter, m
    
    h*: float
      ## appended width, m
    

    hole*: bool
      ## should a cup have a hole for the shaft

    seal*: SealGeomParams
    shaft_d*: float
    

    cutoff*: tuple[top, bottom: float]
    

  CapGeomParams* = object
    ## all dimensions are in meters
    ## images/cap_geom.jpg  # todo: draw dimensions in the script
    D*: float
    h*: float
    hole*: bool
    shaft_d*: float
    seal_D*: float
    seal_h*: float
    cutoff*: tuple[top, bottom: float]
    
    D1*: float
    D2*: float
    D3*: float
    d*: float
    d1*: float
    M*: float
    n*: int
    H*: float
    s*: float



proc mm(v: float): float = v / 1e3


columnTable dims, `const`:
  D   | D1  | D2  | D3  | d | d1 | M  | n | H  | s
  62  | +15 | +30 | -10 | 7  | 14  | 6  | 4 | 10 | 5
  75  | +20 | +40 | -10 | 9  | 18  | 8  | 4 | 12 | 6
  95  | +20 | +40 | -10 | 9  | 18  | 8  | 6 | 12 | 6
  145 | +25 | +50 | -15 | 11 | 22  | 10 | 6 | 15 | 7
  180 | +30 | +60 | -15 | 13 | 24  | 12 | 6 | 18 | 8
  220 | +30 | +60 | -20 | 13 | 24  | 12 | 6 | 18 | 8



converter autoComputeGeomParams*(desc: CapDesc): CapGeomParams =
  template O: var CapGeomParams = result
  
  O.D = desc.D
  O.h = desc.h

  O.hole = desc.hole
  O.shaft_d = desc.seal.d
  O.seal_D = desc.seal.D
  O.seal_h = desc.seal.h
  if desc.shaft_d != 0: O.shaft_d = desc.shaft_d

  O.cutoff = desc.cutoff
  
  for i, maxD in dims.D:
    if maxD.float.mm > desc.D:
      O.D1 = desc.D + dims.D1[i].float.mm
      O.D2 = desc.D + dims.D2[i].float.mm
      O.D3 = desc.D + dims.D3[i].float.mm
      O.d = dims.d[i].float.mm
      O.d1 = dims.d1[i].float.mm
      O.M = dims.M[i].float.mm
      O.n = dims.n[i]
      O.H = dims.H[i].float.mm
      O.s = (if O.hole: 4.mm else: dims.s[i].float.mm)



proc bounds*(g: CapGeomParams): Bounds2 =
  bounds2(p2(0, -g.D2/2), p2(g.H + g.h, g.D2/2))



proc draw*(g: CapGeomParams, origin: Position2 = point2(), scale: float = 1, axis: V2 = v2(1, 0), sketch = doc, hideBackLines = false) =
  type DrawIf = enum
    Always, Cutoff, NotCutoff

  let x = axis.normalize
  let y = x.rotate(Pi/2)
  proc sc(v: float): float = v * scale
  proc vt(v: V2): V2 = v.x.sc * x + v.y.sc * y
  proc pt(v: V2): Point2 = origin + v.vt
  proc negY(v: V2): V2 = v2(v.x, -v.y)
  if sketch == nil: return

  var contour = @[
    v2(0, (if g.hole: g.shaft_d/2 + 1.mm else: 0)),
    v2(0, g.D1/2 - g.d1/2),  # 1
    v2(2.mm, g.D1/2 - g.d1/2),
    v2(2.mm, g.D1/2 - g.d/2),  # 3
    v2(2.mm, g.D1/2 + g.d/2),  # 4
    v2(2.mm, g.D1/2 + g.d1/2),
    v2(0, g.D1/2 + g.d1/2),  # 6
    v2(0, g.D2/2),
    v2(g.H, g.D2/2),
    v2(g.H, g.D1/2 + g.d/2),
    v2(g.H, g.D1/2 - g.d/2),
    v2(g.H, g.D/2),
    v2(g.H + g.h, g.D/2),
    v2(g.H + g.h, g.D3/2),
    v2(g.s, g.D3/2),  # 14
    v2(g.s, (if g.hole: g.shaft_d/2 + 1.mm else: 0)),
  ]

  if g.hole:
    contour[14..14] = @[
      v2(g.s + g.seal_h + 2.mm, g.D3/2),
      v2(g.s + g.seal_h + 2.mm, g.seal_D/2),
      v2(g.s, g.seal_D/2),
    ]
  let last = contour.high

  contour.add @[
    v2(0, g.D2/2 - g.cutoff.bottom),
    v2(g.H, g.D2/2 - g.cutoff.bottom),
    v2(0, g.D2/2 - g.cutoff.top),
    v2(g.H, g.D2/2 - g.cutoff.top),
  ]

  proc addLineSection(a, b: int, drawIf = Always, parts: openArray[bool] = [false, true]) =
    if ((drawIf == Always) or ((g.cutoff.bottom != 0) == (drawIf == Cutoff))) and (false in parts):
      sketch.add lineSection(contour[a].pt, contour[b].pt), mainLine
    if ((drawIf == Always) or ((g.cutoff.top != 0) == (drawIf == Cutoff))) and (true in parts):
      sketch.add lineSection(contour[a].negY.pt, contour[b].negY.pt), mainLine

  proc addRevolutionLine(a: int) =
    let zero = (if hideBackLines: g.shaft_d/2 else: 0)
    sketch.add lineSection(contour[a].pt, v2(contour[a].x, zero).pt), mainLine
    sketch.add lineSection(contour[a].negY.pt, v2(contour[a].x, zero).negY.pt), mainLine

  proc addHatching(i: openArray[int], drawIf = Always, parts: openArray[bool] = [false, true]) =
    for up in parts:
      if (drawIf == Always) or (([g.cutoff.bottom, g.cutoff.top][up.int] != 0) == (drawIf == Cutoff)):
        var p = create Path2
        # todo: either something in ecs or in sigeo interface macro or in both breaks, if Path2 is allocated on the stack, or is passed to ecs as Path2
        for i2 in countup(0, i.high):
          p[].add (if up: contour[i[i2]].negY else: contour[i[i2]]).pt
        close p[]
        sketch.add p[].Curve2, Hatching(period: g.D / 40 * scale), hatchingLine

  for i in 0 ..< (if g.hole: (last + 1) else: last):
    addLineSection i, (i+1) mod (last + 1), drawIf = (if i in 1..10: NotCutoff else: Always)
  
  addLineSection 1, 6, drawIf = NotCutoff
  addLineSection 3, 10, drawIf = NotCutoff
  addLineSection 4, 9, drawIf = NotCutoff
  addRevolutionLine 0
  addRevolutionLine last - 2

  addLineSection 1, contour.high-3, drawIf = Cutoff, parts = [false]
  addLineSection 1, contour.high-1, drawIf = Cutoff, parts = [true]
  addLineSection contour.high-3, contour.high-2, drawIf = Cutoff, parts = [false]
  addLineSection contour.high-1, contour.high, drawIf = Cutoff, parts = [true]
  addLineSection contour.high-2, 11, drawIf = Cutoff, parts = [false]
  addLineSection contour.high, 11, drawIf = Cutoff, parts = [true]
  
  if g.hole:
    addRevolutionLine last
    addRevolutionLine last - 4
  
  addHatching toSeq(0..3) & toSeq(10..last), drawIf = NotCutoff
  addHatching toSeq(4..9), drawIf = NotCutoff

  addHatching @[0, contour.high-3, contour.high-2] & toSeq(11..last), drawIf = Cutoff, parts = [false]
  addHatching @[0, contour.high-1, contour.high] & toSeq(11..last), drawIf = Cutoff, parts = [true]

  # todo: fillets


proc sketch*(g: CapGeomParams, hideBackLines = false): World =
  result = World()
  withDocument result:
    let globals = doc.spawn()
    setDrawingGlobals(globals)
    draw(g, sketch = result, hideBackLines = hideBackLines)




mainModule:
  for i, cutoff in [(0.mm, 0.mm), (15.mm, 0.mm), (0.mm, 25.mm)]:
    draw CapDesc(D: 100.mm, h: 20.mm, cutoff: cutoff),
      origin = p2((0.mm + i.float * 120.mm) * 100, 0), scale = 100
    
    let sealedCap = CapDesc(D: 100.mm, h: 20.mm, cutoff: cutoff, hole: true, seal: SealDesc(d: 40.mm))
    
    draw sealedCap,
      origin = p2((60.mm + i.float * 120.mm) * 100, 0), scale = 100#, hideBackLines=true

    draw sealedCap.seal,
      origin = p2((60.mm + i.float * 120.mm) * 100 + sealedCap.autoComputeGeomParams.s*100, 0), scale = 100#, hideBackLines=true

