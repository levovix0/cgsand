import std/[tables]
import sandbox, geom2d, techDraw
import pkg/[vmath]


type
  GearDesc* = object
    teethCount*: int
    modulo*: float  # in meters
    height*: float  # width of the gear, m
    
    shaft_d*: float
    holes*: bool
    reverseHatching*: bool



proc adhendiumDiameter*(g: GearDesc): float {.aliases: [d_a].} =
  g.modulo * (g.teethCount.float + 2)

proc pitchDiameter*(g: GearDesc): float {.aliases: [d].} =
  g.modulo * (g.teethCount.float)

proc rootDiameter*(g: GearDesc): float {.aliases: [d_t].} =
  g.modulo * (g.teethCount.float - 2.5)

proc bevelRadius*(g: GearDesc): float {.aliases: [m].} =
  g.modulo

proc width*(g: GearDesc): float {.aliases: [b].} =
  g.height

proc key*(g: GearDesc): bool = g.holes  # for now



proc bounds*(g: GearDesc): Bounds2 =
  bounds2(p2(0, -g.d_a/2), p2(g.b, +g.d_a/2))

proc transformToCenter*(g: GearDesc): M4 =
  translate v3(-g.b/2, 0, 0)


proc drawSection*(g: GearDesc, sketch = doc, backLines = true, axialLines = true, centralAxial = true, hatching = true) =
  if sketch == nil: return
  
  let dt = max(8.mm, (g.m * 3.5).ceil(1.mm))
  let dhol = (g.d + g.shaft_d)/2
  let dinn = (g.d - g.shaft_d)/8

  let do1 = g.d_t - dt*2 - dhol
  let do2 = dhol - g.shaft_d * 1.6
  let dou1 = g.d_t - dhol
  let dou2 = dhol - g.shaft_d

  let contour = (sketch.foreground, mainLine)
  let hatch = (Hatching(
    period: g.modulo,
    angle: (if g.reverseHatching: -Pi/4 else: Pi/4),
  ), hatchingLine)

  let bevelRadius = g.m/2
  let filletRadius = 5.mm  # Курмаз Л.В. Скойбеда А.Т. - Детали машин. Проектирование - 2005, стр. 139

  if g.holes:
    let pts = @[
      v2(g.b/2, dou1/2),
      v2(g.b, dou1/2),
      v2(g.b, do1/2),
      v2(g.b * (1 - 0.7/2), do1/2),
      v2(g.b * (1 - 0.7/2), (dinn)),
      v2(g.b * 0.7/2, (dinn)),
      v2(g.b * 0.7/2, do1/2),
      v2(0, do1/2),
      v2(0, dou1/2),
    ]
    for yhole in [1.0, -1.0]:
      let yorg = dhol/2 * yhole
      for ydir in [1.0, -1.0]:
        var p = Path2()
        for i, pt in pts:
          var pt = pt
          if pt.y == do1/2 and (ydir * yhole) < 0:
            pt.y = do2/2
          if pt.y == dou1/2 and (ydir * yhole) < 0:
            pt.y = dou2/2

          p.add p2(pt.x, yorg + pt.y * ydir)
          if i in {1, 8} and (ydir * yhole) < 0: p.bevel(bevelRadius)
          if i in {2, 7}: p.bevel(bevelRadius)
          if i in {3, 6}: p.fillet(filletRadius)
        close p
        
        sketch.add p, contour
        if hatching: sketch.add p, hatch

      for i in [2, 7]:
        let x = if i == 2: -1.0 else: 1.0
        sketch.add line(p2(pts[i].x, yorg + do1/2*yhole + bevelRadius*yhole), p2(pts[i].x, yorg - do2/2*yhole - bevelRadius*yhole)), mainLine
        sketch.add line(p2(pts[i].x + x*bevelRadius, yorg + do1/2*yhole), p2(pts[i].x + x*bevelRadius, yorg - do2/2*yhole)), mainLine
      for i in [4, 5]:
        sketch.add line(p2(pts[i].x, yorg + pts[i].y), p2(pts[i].x, yorg - pts[i].y)), mainLine
      
      if axialLines: sketch.add line(p2(-g.m, yorg), p2(g.b+g.m, yorg)), axialLine
    
    for x in [0.0, g.b]:
      let dd = (if backLines: 0.0 else: g.shaft_d/2)
      sketch.add line(p2(x, g.shaft_d/2 + bevelRadius), p2(x, dd)), mainLine
      sketch.add line(p2(x, -g.shaft_d/2 - bevelRadius), p2(x, -dd)), mainLine
      if backLines:
        let x = x + bevelRadius * (if x == 0: 1 else: -1)
        sketch.add line(p2(x, g.shaft_d/2), p2(x, -g.shaft_d/2)), mainLine

  else:
    let pts = @[
      v2(0, g.d_t/2),
      v2(g.b, g.d_t/2),
      v2(g.b, -g.d_t/2),
      v2(0, -g.d_t/2),
    ]
    var p = Path2()
    for i, pt in pts:
      p.add p2(pt.x, pt.y)
    close p
    
    sketch.add p, contour
    if hatching: sketch.add p, hatch
  
  for ydir in [1.0, -1.0]:
    var p = Path2()
    p.add p2(0, g.d_t/2 * ydir)
    p.add p2(0, g.d_a/2 * ydir); p.bevel(g.m)
    p.add p2(g.b, g.d_a/2 * ydir); p.bevel(g.m)
    p.add p2(g.b, g.d_t/2 * ydir)
    close p
    sketch.add p, contour
    if axialLines: sketch.add line(p2(0, g.d/2 * ydir), p2(g.b, g.d/2 * ydir)), axialLine

  if centralAxial: sketch.add line(p2(-g.m, 0), p2(g.b+g.m, 0)), axialLine

defineSketch drawSection



mainModule:
  doc[globals, CanvasSettings].margin = v2(2.mm, 2.mm)
  doc.add SubWorld GearDesc(
    modulo: 2.75.mm, teethCount: 93, height: 39.875.mm, shaft_d: 48.mm, holes: true,
  ).sketchSection(backLines = true)

  doc.add SubWorld GearDesc(
    modulo: 2.75.mm, teethCount: 23, height: 44.875.mm
  ).sketchSection(backLines = true), Position2 p2(60.mm, 0)
