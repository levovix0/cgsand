import sandbox, geom2d, techDraw
import pkg/[vmath]


type
  RoundRect2Geom_LineIndex = enum
    top, left, bottom, right

  RoundRect2Geom_ArcIndex = enum
    topLeft, bottomLeft, bottomRight, topRight

  RoundRect2Geom* = object
    lines*: array[RoundRect2Geom_LineIndex, LineSection2]
    arcs*: array[RoundRect2Geom_ArcIndex, CircleArc2]

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
    ## images/bearing_geom.jpg  # todo: draw dimensions in the script
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
      line(center + v2(-sx + radius, -sy), center + v2(sx - radius, -sy)),
      line(center + v2(-sx, -sy + radius), center + v2(-sx, sy - radius)),
      line(center + v2(-sx + radius, sy), center + v2(sx - radius, sy)),
      line(center + v2(sx, -sy + radius), center + v2(sx, sy - radius)),
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
  #! note: O.r autocompute is visual-only, check bearing tables for the correct fillet radius values



proc draw*(g: BearingParams, sketch = doc, hideBackLines = false) =
  if sketch == nil: return

  let d = g.d; let h = g.h; let B = g.B; let d_w = g.d_w; let d_cp = g.d_cp; let s = g.s; let r = g.r

  let r_t = roundRect2geom(center = p2(0, -d_cp/2), size = v2(B, h), radius = r)
  let r_b = roundRect2geom(center = p2(0, d_cp/2), size = v2(B, h), radius = r)

  draw(r_t, sketch = sketch)
  draw(r_b, sketch = sketch)

  if hideBackLines:
    # todo: cutContour
    sketch.add line(r_t.lines[left].endPoint, p2(-B/2, -d/2)), mainLine
    sketch.add line(r_b.lines[left].endPoint, p2(-B/2, d/2)), mainLine
    sketch.add line(r_t.lines[right].endPoint, p2(B/2, -d/2)), mainLine
    sketch.add line(r_b.lines[right].endPoint, p2(B/2, d/2)), mainLine
    
  else:
    sketch.add line(r_t.lines[left].endPoint, r_b.lines[left].startPoint), mainLine
    sketch.add line(r_t.lines[bottom].startPoint, r_b.lines[top].startPoint), mainLine
    sketch.add line(r_t.lines[bottom].endPoint, r_b.lines[top].endPoint), mainLine
    sketch.add line(r_t.lines[right].endPoint, r_b.lines[right].startPoint), mainLine

  let circles = [
    circle(p2(0, -d_cp/2), d_w/2),
    circle(p2(0, d_cp/2), d_w/2)
  ]
  for circle in circles: sketch.add circle, mainLine

  for i, cy in [-d_cp/2, d_cp/2]:
    let rr = [r_t, r_b][i]

    for j, y in [
      cy - d_w/2 + s,
      cy + d_w/2 - s,
    ]:
      # todo: cutContour
      let line = line(p2(-B/2, y), p2(B/2, y))
      let pts = intersectionPointsParams(line, circles[i])
      let l = line(line.startPoint, line.pointAtParam(pts[0].curveA))
      let r = line(line.pointAtParam(pts[1].curveA), line.endPoint)
      doc.add l, mainLine
      doc.add r, mainLine

      when true:
        var arc = circles[i].cut(pts[0].curveB, pts[1].curveB)

        var p = Path2()
        if j == 0:
          p.add l.pointAtParam(0)
          p.add l; p.add arc; p.add r
          p.add rr.arcs[topRight]
          p.add rr.lines[top].reverse
          p.add rr.arcs[topLeft]
          close p
        else:
          p.add l.pointAtParam(0)
          p.add l; p.add arc; p.add r
          p.add rr.arcs[bottomRight].reverse
          p.add rr.lines[bottom].reverse
          p.add rr.arcs[bottomLeft].reverse
          close p
        doc.add p, Hatching(), hatchingLine


proc sketch*(g: BearingParams, hideBackLines = false): World =
  result = newTechDraw()
  withDocument result: draw(g, hideBackLines = hideBackLines)



mainModule:
  doc.add SubWorld BearingDesc(d: 2.m, D: 4.m).sketch


