import std/[tables]
import sandbox, geom2d, techDraw
import pkg/[vmath]
import pkg/sigeo/macros/[genAliases, cursors]


type
  GearDesc* = object
    teethCount*: int
    modulo*: float  # in meters
    height*: float  # width of the gear, m
    
    shaft_d*: float
    holesAndKey*: bool



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

  let contour = (doc.foreground, mainLine)
  let hatch = (Hatching(period: if g.holesAndKey: g.modulo else: g.modulo/2), hatchingLine)

  if g.holesAndKey:
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
        letCur p: create(Path2)[]
        for i, pt in pts:
          var pt = pt
          if pt.y == do1/2 and (ydir * yhole) < 0:
            pt.y = do2/2
          if pt.y == dou1/2 and (ydir * yhole) < 0:
            pt.y = dou2/2

          p.add p2(pt.x, yorg + pt.y * ydir)
          if i == 2 and (ydir * yhole) < 0: p.addBevel(g.m/2)
          if i in {3, 8}: p.addBevel(g.m/2)
          if i in {4, 7}: p.addFillet(g.m)
        close p
        if (ydir * yhole) < 0: p.addBevel(g.m/2)
        
        doc.add p.Curve2, contour
        if hatching: doc.add p.Curve2, hatch

      for i in [2, 7]:
        let x = if i == 2: -1.0 else: 1.0
        doc.add line(p2(pts[i].x, yorg + do1/2*yhole + g.m/2*yhole), p2(pts[i].x, yorg - do2/2*yhole - g.m/2*yhole)), mainLine
        doc.add line(p2(pts[i].x + x*g.m/2, yorg + do1/2*yhole), p2(pts[i].x + x*g.m/2, yorg - do2/2*yhole)), mainLine
      for i in [4, 5]:
        doc.add line(p2(pts[i].x, yorg + pts[i].y), p2(pts[i].x, yorg - pts[i].y)), mainLine
      
      if axialLines: doc.add line(p2(-g.m, yorg), p2(g.b+g.m, yorg)), axialLine
    
    for x in [0.0, g.b]:
      let dd = (if backLines: 0.0 else: g.shaft_d/2)
      doc.add line(p2(x, g.shaft_d/2 + g.m/2), p2(x, dd)), mainLine
      doc.add line(p2(x, -g.shaft_d/2 - g.m/2), p2(x, -dd)), mainLine
      if backLines:
        let x = x + g.m/2 * (if x == 0: 1 else: -1)
        doc.add line(p2(x, g.shaft_d/2), p2(x, -g.shaft_d/2)), mainLine

  else:
    let pts = @[
      v2(0, g.d_t/2),
      v2(g.b, g.d_t/2),
      v2(g.b, -g.d_t/2),
      v2(0, -g.d_t/2),
    ]
    letCur p: create(Path2)[]
    for i, pt in pts:
      p.add p2(pt.x, pt.y)
    close p
    
    doc.add p.Curve2, contour
    if hatching: doc.add p.Curve2, hatch
  
  for ydir in [1.0, -1.0]:
    letCur p: create(Path2)[]
    p.add p2(0, g.d_t/2 * ydir)
    p.add p2(0, g.d_a/2 * ydir)
    p.add p2(g.b, g.d_a/2 * ydir)
    p.addBevel g.m
    p.add p2(g.b, g.d_t/2 * ydir)
    p.addBevel g.m
    close p
    doc.add p.Curve2, contour
    if axialLines: doc.add line(p2(0, g.d/2 * ydir), p2(g.b, g.d/2 * ydir)), axialLine

  if centralAxial: doc.add line(p2(-g.m, 0), p2(g.b+g.m, 0)), axialLine





proc sketchSection*(g: GearDesc, backLines = true, axialLines = true, centralAxial = true, hatching = true): World =
  result = newTechDraw()
  withDocument result: drawSection(g, backLines = backLines, axialLines = axialLines, centralAxial = centralAxial, hatching = hatching)




mainModule:
  doc[globals, CanvasSettings].margin = v2(2.mm, 2.mm)
  doc.add SubWorld GearDesc(
    modulo: 2.75.mm, teethCount: 93, height: 39.875.mm, shaft_d: 48.mm, holesAndKey: true,
  ).sketchSection(backLines = true)

  doc.add SubWorld GearDesc(
    modulo: 2.75.mm, teethCount: 23, height: 44.875.mm
  ).sketchSection(backLines = true), Position2 p2(60.mm, 0)
