import std/[tables]
import sandbox, geom2d, techDraw
import pkg/[vmath]
when isMainModule: import tools/measurement


type
  BushingDesc* = object
    d*: float
      ## inner diameter of the bushing, m
    
    H*: float
      ## width of the bushing, m
    
    reversedHatching*: bool



proc outerDiameter*(g: BushingDesc): float {.aliases: [D].} =
  g.d + 6.mm

proc stopDiameter*(g: BushingDesc): float {.aliases: [D2].} =
  g.outerDiameter + 4.mm

proc stopWidth*(g: BushingDesc): float {.aliases: [h].} =
  if g.outerDiameter < 10.5.mm: 2.mm
  elif g.outerDiameter < 19.5.mm: 3.mm
  elif g.outerDiameter < 28.mm: 4.mm
  else: 5.mm

proc b1*(g: BushingDesc): float =
  2.mm

proc width*(g: BushingDesc): float {.aliases: [height].} =
  g.H


proc hatching*(g: BushingDesc): Hatching =
  Hatching(period: g.d / 40, angle: (if g.reversedHatching: -Pi/4 else: Pi/4))


proc bounds*(g: BushingDesc): Bounds2 =
  bounds2(p2(0, -g.D/2), p2(g.H, +g.D/2))

proc transformToCenter*(g: BushingDesc): M4 =
  translate v3(-g.H/2, 0, 0)


proc draw*(g: BushingDesc, sketch = doc, backLines = true, axialLines = true, hatching = true) =
  if sketch == nil: return

  let fgLine = (doc.foreground, mainLine)
  let haLine = (g.hatching, hatchingLine)

  let bevel = 0.6.mm
  let fillet = bevel

  for ydir in [1.0, -1.0]:
    var p = Path2()
    
    p.add p2(g.H, g.d/2 * ydir); p.fillet(fillet)
    p.y = g.D/2 * ydir; p.bevel(bevel)
    p.add p2(g.h + g.b1 + bevel, g.D/2 * ydir)
    p.add p2(g.h + g.b1, (g.D/2 - bevel) * ydir)
    p.x = g.h
    p.y = g.D2/2 * ydir
    p.x = 0; p.bevel(bevel)
    p.y = g.d/2 * ydir; p.fillet(fillet)
    close p

    doc.add p, fgLine
    if hatching: doc.add p, haLine
  
    let y = (if backLines: 0.0 else: g.d/2 * ydir)
    for pt in [p2(0, (g.d/2 + fillet) * ydir), p2(fillet, g.d/2 * ydir), p2(g.H, (g.d/2 + fillet) * ydir), p2(g.H - fillet, g.d/2 * ydir)]:
      doc.add line(p2(pt.x, pt.y), p2(pt.x, y)), mainLine

defineSketch draw




mainModule:
  doc[globals, CanvasSettings].margin = v2(2.mm, 2.mm)
  doc.add SubWorld BushingDesc(
    d: 40.mm, H: 10.mm,
  ).sketch

  doc.add SubWorld BushingDesc(
    d: 48.mm, H: 10.mm,
  ).sketch, Position2 p2(20.mm, 0)

  doc.add SubWorld BushingDesc(
    d: 40.mm, H: 10.mm,
  ).sketch(backLines = false), Position2 p2(40.mm, 0)
