import sandbox, geom2d, paths
import pkg/[vmath]
import pkg/pixie/paths
import ./[drawingGlobals]


type
  RoundRect2Geom_LineIndex = enum
    top, left, bottom, right

  RoundRect2Geom_ArcIndex = enum
    topLeft, bottomLeft, bottomRight, topRight

  RoundRect2Geom* = object
    lines*: array[RoundRect2Geom_LineIndex, LineSection]
    arcs*: array[RoundRect2Geom_ArcIndex, CircleArc]

  BearingDesc* = object
    d*: float
      ## diameter to smaller wall, m
    
    D*: float
      ## diameter to greater wall, m
    
    B*: float
      ## width, m
      ## if zero, calculated automatically
    
    r*: float
      ## filler radius, m
      ## if zero, calculated automatically
  
  BearingParams* = object
    ## images/bearing_geom.jpg
    d*: float
    D*: float
    B*: float
    h*: float
    d_w*: float
    d_cp*: float
    s*: float
    r*: float  ## fillet radius



proc roundRect2geom*(center: Point2, size: V2, radius: float): RoundRect2Geom =
  let sx = size.x / 2
  let sy = size.y / 2
  RoundRect2Geom(
    lines: [
      lineSection(center + v2(-sx + radius, -sy), center + v2(sx - radius, -sy)),
      lineSection(center + v2(-sx, -sy + radius), center + v2(-sx, sy - radius)),
      lineSection(center + v2(-sx + radius, sy), center + v2(sx - radius, sy)),
      lineSection(center + v2(sx, -sy + radius), center + v2(sx, sy - radius)),
    ],
    arcs: [
      arc(center + v2(-sx + radius, -sy + radius), radius, -Pi/2 .. -Pi),
      arc(center + v2(-sx + radius, sy - radius), radius, Pi .. Pi/2),
      arc(center + v2(sx - radius, sy - radius), radius, Pi/2 .. 0.0),
      arc(center + v2(sx - radius, -sy + radius), radius, 0.0 .. -Pi/2),
    ],
  )


proc draw*(geom: RoundRect2Geom, sketch = doc, thickness = mainLine) =
  for line in geom.lines:
    sketch.add line, thickness
  for arc in geom.arcs:
    sketch.add arc, thickness



converter autoComputeParams*(desc: BearingDesc): BearingParams =
  template O: var BearingParams = result
  O.d = desc.d
  O.D = desc.D
  O.h = (O.D - O.d) / 2
  O.B = if desc.B != 0: desc.B else: 0.8 * O.h
  
  O.d_w = (0.6) * O.h
  O.d_cp = (desc.D + desc.d) / 2
  O.s = 0.15 * O.d_w

  O.r = if desc.r != 0: desc.r else: (desc.D - desc.d - O.d_w) / 16



proc draw*(g: BearingParams, origin: Position2 = point2(), scale: float = 1, axis: V2 = v2(1, 0), sketch = doc, hideBackLines = false) =
  let x = axis.normalize
  let y = x.rotate(Pi/2)
  proc sc(v: float): float = v * scale
  proc vt(v: V2): V2 = v.x.sc * x + v.y.sc * y
  proc pt(v: V2): Point2 = origin + v.vt
  if sketch == nil: return

  let d = g.d; let h = g.h; let B = g.B; let d_w = g.d_w; let d_cp = g.d_cp; let s = g.s; let r = g.r

  let r_t = roundRect2geom(center = v2(0, -d_cp/2).pt, size = v2(B, h).vt, radius = r.sc)
  let r_b = roundRect2geom(center = v2(0, d_cp/2).pt, size = v2(B, h).vt, radius = r.sc)

  draw(r_t, sketch = sketch)
  draw(r_b, sketch = sketch)

  if hideBackLines:
    # todo: cutContour
    sketch.add lineSection(r_t.lines[left].endPoint, v2(-B/2, -d/2).pt), mainLine
    sketch.add lineSection(r_b.lines[left].endPoint, v2(-B/2, d/2).pt), mainLine
    sketch.add lineSection(r_t.lines[right].endPoint, v2(B/2, -d/2).pt), mainLine
    sketch.add lineSection(r_b.lines[right].endPoint, v2(B/2, d/2).pt), mainLine
    
  else:
    sketch.add lineSection(r_t.lines[left].endPoint, r_b.lines[left].startPoint), mainLine
    sketch.add lineSection(r_t.lines[bottom].startPoint, r_b.lines[top].startPoint), mainLine
    sketch.add lineSection(r_t.lines[bottom].endPoint, r_b.lines[top].endPoint), mainLine
    sketch.add lineSection(r_t.lines[right].endPoint, r_b.lines[right].startPoint), mainLine

  let circles = [
    circle(v2(0, -d_cp/2).pt, d_w.sc/2),
    circle(v2(0, d_cp/2).pt, d_w.sc/2)
  ]
  for circle in circles: sketch.add circle, mainLine

  for i, cy in [-d_cp/2, d_cp/2]:
    let rr = [r_t, r_b][i]

    for j, y in [
      cy - d_w/2 + s,
      cy + d_w/2 - s,
    ]:
      # todo: cutContour
      let line = lineSection(v2(-B/2, y).pt, v2(B/2, y).pt)
      let pts = intersectionPointsParams(line, circles[i])
      let l = lineSection(line.startPoint, line.pointAtParam(pts[0].curveA))
      let r = lineSection(line.pointAtParam(pts[1].curveA), line.endPoint)
      doc.add l, mainLine
      doc.add r, mainLine

      when true:
        var arc = circles[i].cut(pts[0].curveB, pts[1].curveB)

        var p = newPath()
        if j == 0:
          p.moveTo(l.pointAtParam(0).V2.vec2)
          p.add l; p.add arc; p.add r
          p.add rr.arcs[topRight]
          p.add rr.lines[top].reverse
          p.add rr.arcs[topLeft]
          p.closePath()
        else:
          p.moveTo(l.pointAtParam(0).V2.vec2)
          p.add l; p.add arc; p.add r
          p.add rr.arcs[bottomRight].reverse
          p.add rr.lines[bottom].reverse
          p.add rr.arcs[bottomLeft].reverse
          p.closePath()
        doc.add p, Hatching(), hatchingLine


proc sketch*(g: BearingParams, hideBackLines = false): World =
  result = World()
  withDocument result:
    let globals = doc.spawn()
    setDrawingGlobals(globals)
    draw(g, sketch = result, hideBackLines = hideBackLines)



mainModule:
  draw BearingDesc(d: 2, D: 4)


