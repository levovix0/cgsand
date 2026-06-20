import sandbox, geom2d, techDraw, tabledef
import std/[sequtils]
import pkg/[vmath]
import ./[seal]
when isMainModule: import tools/measurement


type
  CoverDesc* = object of RootObj
    D*: float
      ## base cover diameter, m
    
    h*: float
      ## appended width, m
    

    hole*: bool
      ## should a cup have a hole for the shaft

    seal*: SealGeomParams
    shaft_d*: float
    

    cutoff*: tuple[top, bottom: float]

    reverseHatching*: bool
    

  CoverGeomParams* = object of CoverDesc
    ## all dimensions are in meters
    ## images/cap_geom.jpg  # todo: draw dimensions in the script
    D1*: float
    D2*: float
    D3*: float
    d*: float
    d1*: float
    M*: float
    n*: int
    H*: float
    s*: float
    boltDepth*: float



proc mm(v: float): float = v / 1e3


columnTable dims, `const`:
  D   | D1  | D2  | D3  | d | d1 | M  | n | H  | s
  62  | +15 | +30 | -10 | 7  | 14  | 6  | 4 | 10 | 5
  75  | +20 | +40 | -10 | 9  | 18  | 8  | 4 | 12 | 6
  95  | +20 | +40 | -10 | 9  | 18  | 8  | 6 | 12 | 6
  145 | +25 | +50 | -15 | 11 | 22  | 10 | 6 | 15 | 7
  180 | +30 | +60 | -15 | 13 | 24  | 12 | 6 | 18 | 8
  220 | +30 | +60 | -20 | 13 | 24  | 12 | 6 | 18 | 8



converter autoComputeGeomParams*(desc: CoverDesc): CoverGeomParams =
  template O: var CoverGeomParams = result
  cast[ptr CoverDesc](O.addr)[] = desc
  
  if desc.shaft_d != 0: O.shaft_d = desc.shaft_d
  else: O.shaft_d = desc.seal.d

  O.cutoff = desc.cutoff
  O.boltDepth = 2.mm
  
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
      break


proc totalHeight*(g: CoverGeomParams): float =
  g.H + g.h


proc hatching*(g: CoverGeomParams): Hatching =
  Hatching(
    period: (g.D / 40),
    angle: (if g.reverseHatching: -Pi/4 else: Pi/4),
  )


proc bounds*(g: CoverGeomParams): Bounds2 =
  bounds2(p2(0, -g.D2/2), p2(g.H + g.h, g.D2/2))



proc draw*(g: CoverGeomParams, sketch = doc, hideBackLines = false) =
  type DrawIf = enum
    Always, Cutoff, NotCutoff

  proc negY(v: P2): P2 = p2(v.x, -v.y)
  if sketch == nil: return

  proc addSymmetric[T, Curve](doc: World, v: Curve, other: T) =
    doc.add v, other
    doc.add v.transform(scale v3(1, -1, 1)), other

  let haLine = (g.hatching, hatchingLine)
  let bevel = 2.mm
  let fillet = bevel

  var contour = @[
    p2(0, (if g.hole: g.shaft_d/2 + 1.mm else: 0)),
    p2(0, g.D1/2 - g.d1/2),  # 1
    p2(g.boltDepth, g.D1/2 - g.d1/2),
    p2(g.boltDepth, g.D1/2 - g.d/2),  # 3
    p2(g.boltDepth, g.D1/2 + g.d/2),  # 4
    p2(g.boltDepth, g.D1/2 + g.d1/2),
    p2(0, g.D1/2 + g.d1/2),  # 6
    p2(0, g.D2/2),
    p2(g.H, g.D2/2),
    p2(g.H, g.D1/2 + g.d/2),
    p2(g.H, g.D1/2 - g.d/2),
    p2(g.H, g.D/2),
    p2(g.H + g.h, g.D/2),
    p2(g.H + g.h, g.D3/2),
    p2(g.s, g.D3/2),  # 14
    p2(g.s, (if g.hole: g.shaft_d/2 + 1.mm else: 0)),
  ]

  if g.hole:
    contour[14..14] = @[
      p2(g.s + g.seal.h + bevel, g.D3/2),
      p2(g.s + g.seal.h + bevel, g.seal.D/2),
      p2(g.s, g.seal.D/2),
    ]
  let last = contour.high

  contour.add @[
    p2(0, g.D2/2 - g.cutoff.bottom),
    p2(g.H, g.D2/2 - g.cutoff.bottom),
    p2(0, g.D2/2 - g.cutoff.top),
    p2(g.H, g.D2/2 - g.cutoff.top),
  ]

  proc addLineSection(a, b: int, drawIf = Always, parts: openArray[bool] = [false, true]) =
    if ((drawIf == Always) or ((g.cutoff.bottom != 0) == (drawIf == Cutoff))) and (false in parts):
      sketch.add line(contour[a], contour[b]), mainLine
    if ((drawIf == Always) or ((g.cutoff.top != 0) == (drawIf == Cutoff))) and (true in parts):
      sketch.add line(contour[a].negY, contour[b].negY), mainLine

  proc addRevolutionLine(a: int) =
    let zero = (if hideBackLines: g.shaft_d/2 else: 0)
    sketch.add line(contour[a], p2(contour[a].x, zero)), mainLine
    sketch.add line(contour[a].negY, p2(contour[a].x, zero).negY), mainLine

  proc addHatching(i: openArray[int], drawIf = Always, parts: openArray[bool] = [false, true]) =
    for up in parts:
      if (drawIf == Always) or (([g.cutoff.bottom, g.cutoff.top][up.int] != 0) == (drawIf == Cutoff)):
        var p = Path2()
        for i2 in countup(0, i.high):
          p.add (if up: contour[i[i2]].negY else: contour[i[i2]])
        close p
        sketch.add p, haLine

  for i in 0 ..< (if g.hole: (last + 1) else: last):
    if i in 13..14: continue
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

  # fillets
  block:
    let c = circleArc(contour[14] + v2(fillet, -fillet), fillet, Pi, Pi/2)
    doc.addSymmetric c, mainLine
    doc.addSymmetric line(c.pointAt(0), contour[15]), mainLine
    doc.addSymmetric line(c.pointAt(1), contour[13]), mainLine
    

defineSketch draw



mainModule:
  doc[globals, CanvasSettings].margin = v2(20.mm, 20.mm)
  
  for i, cutoff in [(0.mm, 0.mm), (10.mm, 0.mm), (0.mm, 20.mm)]:
    doc.add SubWorld CoverDesc(D: 100.mm, h: 20.mm, cutoff: cutoff).sketch():
      Position2 p2((0.mm + i.float * 120.mm), 0)
    
    let sealedCover = CoverDesc(D: 100.mm, h: 20.mm, cutoff: cutoff, hole: true, seal: SealDesc(d: 40.mm))
    
    doc.add SubWorld sealedCover.sketch():
      Position2 p2((60.mm + i.float * 120.mm), 0)

    doc.add SubWorld sealedCover.seal.sketch():
      Position2 p2((60.mm + i.float * 120.mm) + sealedCover.autoComputeGeomParams.s, 0)

