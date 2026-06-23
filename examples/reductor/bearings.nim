import sandbox, geom2d, techDraw, tabledef
import pkg/[vmath]


type
  RoundRect2Geom_LineIndex {.pure.} = enum
    top, left, bottom, right

  RoundRect2Geom_ArcIndex {.pure.} = enum
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



# todo: add the other series
columnTable middleSeriesBearings, `const`:
  # Средняя серия диаметров 3, узкая серия ширин 0 (ГОСТ 8338-75, табл. 6)
  designation | d   | D   | B  | r
  34          | 4   | 16  | 5  | 0.5
  35          | 5   | 19  | 6  | 0.5
  300         | 10  | 35  | 11 | 1.0
  301         | 12  | 37  | 12 | 1.5
  302         | 15  | 42  | 13 | 1.5
  303         | 17  | 47  | 14 | 2.0
  304         | 20  | 52  | 15 | 2.0
  305         | 25  | 62  | 17 | 2.0
  306         | 30  | 72  | 19 | 2.0
  307         | 35  | 80  | 21 | 2.5
  308         | 40  | 90  | 23 | 2.5
  309         | 45  | 100 | 25 | 2.5
  310         | 50  | 110 | 27 | 3.0
  311         | 55  | 120 | 29 | 3.0
  312         | 60  | 130 | 31 | 3.5
  313         | 65  | 140 | 33 | 3.5
  314         | 70  | 150 | 35 | 4.0
  315         | 75  | 160 | 37 | 4.0
  316         | 80  | 170 | 39 | 4.0
  317         | 85  | 180 | 41 | 4.0
  318         | 90  | 190 | 43 | 4.0
  319         | 95  | 200 | 45 | 4.0
  320         | 100 | 215 | 47 | 4.0
  321         | 105 | 225 | 49 | 5.0
  322         | 110 | 240 | 50 | 5.0
  324         | 120 | 260 | 55 | 5.0
  326         | 130 | 280 | 58 | 5.0
  328         | 140 | 300 | 62 | 5.0
  330         | 150 | 320 | 65 | 5.0


proc selectBearing[T](table: T, d: float): BearingDesc =
  proc rowAt(table: T, i: int): BearingDesc =
    BearingDesc(
      d: table.d[i].float.mm,
      D: table.D[i].float.mm,
      B: table.B[i].float.mm,
      r: table.r[i].float.mm
    )
  for i in 0 ..< table.d.len:
    if table.d[i].float.mm >= d - 1e-9:
      return table.rowAt(i)
  table.rowAt(table.d.high)


proc selectMiddleSeriesBearing*(d: float): BearingDesc =
  selectBearing(middleSeriesBearings, d)



proc draw*(g: BearingParams, sketch = doc, hideBackLines = false) =
  if sketch == nil: return

  let d = g.d; let h = g.h; let B = g.B; let d_w = g.d_w; let d_cp = g.d_cp; let s = g.s; let r = g.r

  let r_t = roundRect2geom(center = p2(0, -d_cp/2), size = v2(B, h), radius = r)
  let r_b = roundRect2geom(center = p2(0, d_cp/2), size = v2(B, h), radius = r)

  draw(r_t, sketch = sketch)
  draw(r_b, sketch = sketch)

  if hideBackLines:
    # todo: cutContour
    sketch.add line(r_t.lines[RoundRect2Geom_LineIndex.left].endPoint, p2(-B/2, -d/2)), mainLine
    sketch.add line(r_b.lines[RoundRect2Geom_LineIndex.left].endPoint, p2(-B/2, d/2)), mainLine
    sketch.add line(r_t.lines[RoundRect2Geom_LineIndex.right].endPoint, p2(B/2, -d/2)), mainLine
    sketch.add line(r_b.lines[RoundRect2Geom_LineIndex.right].endPoint, p2(B/2, d/2)), mainLine
    
  else:
    sketch.add line(r_t.lines[RoundRect2Geom_LineIndex.left].endPoint, r_b.lines[RoundRect2Geom_LineIndex.left].startPoint), mainLine
    sketch.add line(r_t.lines[RoundRect2Geom_LineIndex.bottom].startPoint, r_b.lines[RoundRect2Geom_LineIndex.top].startPoint), mainLine
    sketch.add line(r_t.lines[RoundRect2Geom_LineIndex.bottom].endPoint, r_b.lines[RoundRect2Geom_LineIndex.top].endPoint), mainLine
    sketch.add line(r_t.lines[RoundRect2Geom_LineIndex.right].endPoint, r_b.lines[RoundRect2Geom_LineIndex.right].startPoint), mainLine

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
      let l = line(line.startPoint, line.pointAt(pts[0].curveA))
      let r = line(line.pointAt(pts[1].curveA), line.endPoint)
      doc.add l, mainLine
      doc.add r, mainLine

      when true:
        var arc = circles[i].cut(pts[0].curveB, pts[1].curveB)

        var p = Path2()
        if j == 0:
          p.add l.pointAt(0)
          p.add l; p.add arc; p.add r
          p.add rr.arcs[RoundRect2Geom_ArcIndex.topRight]
          p.add rr.lines[RoundRect2Geom_LineIndex.top].reverse
          p.add rr.arcs[RoundRect2Geom_ArcIndex.topLeft]
          close p
        else:
          p.add l.pointAt(0)
          p.add l; p.add arc; p.add r
          p.add rr.arcs[RoundRect2Geom_ArcIndex.bottomRight].reverse
          p.add rr.lines[RoundRect2Geom_LineIndex.bottom].reverse
          p.add rr.arcs[RoundRect2Geom_ArcIndex.bottomLeft].reverse
          close p
        doc.add p, Hatching(), hatchingLine


proc sketch*(g: BearingParams, hideBackLines = false): World =
  result = newTechDraw()
  withDocument result: draw(g, hideBackLines = hideBackLines)



mainModule:
  doc.add SubWorld BearingDesc(d: 2.m, D: 4.m).sketch


