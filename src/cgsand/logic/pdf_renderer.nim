import std/[unicode, math]
import pkg/[ecs, vmath]
import pkg/pixie/[paths, fonts as pixieFonts]
import pkg/toscel/[colors]
import ../lib/[sandbox, geom2d, text]
import ./[doclayout, document_globals, dashing]
import ./fileformats/[pdf]


type
  PdfRenerer* = object
    doc*: ptr World

  PdfRenderCtx = object
    pi: int
    scale: float32
    bmin: Point2
    pageHeightPt: float32
    yDown: bool

let transparent = color(0, 0, 0, 0)


proc recommendedPointCount(curve: Curve2, typicalCount = 32): int =
  # mirrors world_view.recommendedPointCount
  if curve.isOf(Path2):
    for c in curve.castTo(Path2).curves.view:
      result += recommendedPointCount(c, typicalCount)
  else:
    return typicalCount


proc `*`(t: DMat4, p: Vec2): Vec2 =
  let r = t * dvec4(p.x.float64, p.y.float64, 0, 1)
  vec2(r.x.float32, r.y.float32)

proc toPagePos(ctx: PdfRenderCtx, w: Vec2): Vec2 =
  vec2(
    (w.x - ctx.bmin.x) * ctx.scale * mmToPt.float32,
    if ctx.yDown: ctx.pageHeightPt - (w.y - ctx.bmin.y) * ctx.scale * mmToPt.float32
    else:         (w.y - ctx.bmin.y) * ctx.scale * mmToPt.float32,
  )

proc is3DRotation(t: DMat4): bool =
  ## true when the transform rotates XY vectors into Z (3D tilt)
  abs(t[0][2]) > 1e-6 or abs(t[1][2]) > 1e-6

proc textMatrix2D(ctx: PdfRenderCtx, t: DMat4): tuple[ta, tb, tc, td: float32] =
  ## Builds the PDF Tm 2x2 matrix from Transform3, accounting for the
  ## document-to-PDF y-flip (yDown doc → y-axis inverted in page space).
  ## Includes scale so that Transform3 scale is reflected in rendered size.
  let ySign = if ctx.yDown: -1.0 else: 1.0
  (
    ta: float32(t[0][0]),
    tb: float32(t[0][1] * ySign),
    tc: float32(t[1][0] * ySign),
    td: float32(t[1][1]),
  )


proc renderWorld(o: var PdfWriter, ctx: PdfRenderCtx, w: World, wGlobals: DocumentGlobals, extraT: DMat4) =
  template dashScaleOf: float {.dirty.} =
    (if has DashingScale: the DashingScale else: wGlobals.dashingScale)

  template lwOf(defWorld: float): float32 {.dirty.} =
    ## stroke width in points; PixelThickness is taken as already-in-points
    (if has PixelThickness: the(PixelThickness).float32
      elif has Thickness: the(Thickness).float32 * ctx.scale * mmToPt.float32
      else: defWorld.float32 * ctx.scale * mmToPt.float32)

  template drawStrokeW(worldPts: untyped, col: Color, lw: float32, ct: DMat4) {.dirty.} =
    ## strokes a world-space polyline to the page, honouring a Dashing component.
    ## dots (zero-length dashes) render via the round line cap of drawLine.
    if has Dashing:
      for seg in dashedSegments(worldPts, the Dashing, dashScaleOf):
        o.pages[ctx.pi].drawLine(ctx.toPagePos(ct * seg.a.V2.vec2), ctx.toPagePos(ct * seg.b.V2.vec2), col, lw)
    else:
      var pp: seq[Vec2]
      for q in worldPts:
        pp.add ctx.toPagePos(ct * q.V2.vec2)
      o.pages[ctx.pi].drawPolyline(pp, col, lw)

  template hatchFill(localLo, localHi: Vec2, ctm: DMat4, hat0: Hatching, fg: Color, thicknessW: float, emitClipBody: untyped) =
    ## fills the clip region (set by emitClipBody) with periodic parallel hatch lines.
    block:
      var hat = hat0
      let hsz = localHi - localLo
      if hat.period <= 0: hat.period = hsz.length / 20
      if hat.period > 0:
        let thk = (if thicknessW > 0: thicknessW else: hat.period / 4)
        let ang = hat.angle.float32
        let dd  = vec2(cos(ang), sin(ang))
        let nn  = vec2(-sin(ang), cos(ang))
        let cc  = (localLo + localHi) / 2
        let corners = [localLo, vec2(localHi.x, localLo.y), localHi, vec2(localLo.x, localHi.y)]
        let big = 1e30'f32
        var nmin = big; var nmax = -big; var dmin = big; var dmax = -big
        for v in corners:
          let r = v - cc
          let pn = dot(r, nn); let pd = dot(r, dd)
          nmin = min(nmin, pn); nmax = max(nmax, pn)
          dmin = min(dmin, pd); dmax = max(dmax, pd)
        o.pages[ctx.pi].saveState()
        emitClipBody
        let lwh = thk.float32 * ctx.scale * mmToPt.float32
        let per = hat.period.float32
        var k = ceil(nmin / per).int
        while k.float32 * per <= nmax:
          let off = k.float32 * per
          let p1 = cc + nn * off + dd * dmin
          let p2 = cc + nn * off + dd * dmax
          o.pages[ctx.pi].drawLine(ctx.toPagePos(ctm * p1), ctx.toPagePos(ctm * p2), fg, lwh)
          inc k
        o.pages[ctx.pi].restoreState()


  w.forEach (
    line: LineSection2,
    color: (Foreground|Color)||wGlobals.foreground,
    opt Thickness|PixelThickness,
    opt Dashing|DashingScale,
    t: Transform3||dmat4()
  ):
    let ct = extraT * t
    let lw = lwOf(0.1 / ctx.scale)
    drawStrokeW([line.startPoint, line.endPoint], color, lw, ct)


  w.forEach (
    curve: CircleArc2,
    opt PointCount,
    opt Color|Background|Foreground|Hatching,
    opt Thickness|PixelThickness,
    opt Dashing|DashingScale,
    t3: Transform3||dmat4()
  ):
    let ct = extraT * t3
    let fg =
      if has Foreground: the Foreground
      elif has Color: the Color
      else: wGlobals.foreground
    let lw = lwOf(0.1 / ctx.scale)
    let smooth = not (has PointCount)
    let count =
      if has PointCount: the PointCount
      else: max(24, int(float32(curve.radius) * ctx.scale * mmToPt.float32 * abs(float32(curve.angularLength)) / 4))
    let points = curve.points(count)
    let transf = proc(v: Vec2): Vec2 = ctx.toPagePos(ct * v)

    let doStroke =
      if curve.closed:
        (Background.has.not and Hatching.has.not) or (Color.has and Hatching.has.not) or Foreground.has
      else:
        Foreground.has or Color.has or Background.has.not

    if curve.closed and (has Background):
      if smooth:
        o.pages[ctx.pi].drawBezierEllipseArc(
          float32(curve.center.x), float32(curve.center.y), float32(curve.radius), float32(curve.radius),
          float32(curve.startAngle), float32(curve.angularLength),
          transf, false, true, true, transparent, the Background, lw,
        )
      else:
        var pagePts: seq[Vec2]
        for p in points: pagePts.add ctx.toPagePos(ct * vec2(p.x.float32, p.y.float32))
        o.pages[ctx.pi].fillPolygon(pagePts, the Background)

    if doStroke:
      if smooth and not (has Dashing):
        o.pages[ctx.pi].drawBezierEllipseArc(
          float32(curve.center.x), float32(curve.center.y), float32(curve.radius), float32(curve.radius),
          float32(curve.startAngle), float32(curve.angularLength),
          transf, true, false, curve.closed, fg, transparent, lw,
        )
      else:
        drawStrokeW(points, fg, lw, ct)

    if has Hatching:
      var pagePts: seq[Vec2]
      for p in points: pagePts.add ctx.toPagePos(ct * vec2(p.x.float32, p.y.float32))
      let hatFg = if has Color: the Color else: wGlobals.foreground
      hatchFill(
        curve.bounds.min.V2.vec2, curve.bounds.max.V2.vec2, ct, the Hatching, hatFg,
        (if has Thickness: the Thickness else: 0.0)
      ):
        o.pages[ctx.pi].clipPolygon(pagePts)


  w.forEach (
    arc: EllipseArc2,
    color: (Foreground|Color)||wGlobals.foreground,
    opt PointCount,
    opt Thickness|PixelThickness,
    opt Dashing|DashingScale,
    t3: Transform3||dmat4()
  ):
    let ct = extraT * t3
    let lw = lwOf(0.1 / ctx.scale)

    if not (has PointCount) and not (has Dashing):
      let transf = proc(v: Vec2): Vec2 = ctx.toPagePos(ct * v)
      o.pages[ctx.pi].drawBezierEllipseArc(
        float32(arc.center.x), float32(arc.center.y), float32(arc.size.x / 2), float32(arc.size.y / 2),
        float32(arc.startAngle), float32(arc.angularLength),
        transf, true, false, arc.fullEllipse,
        color, transparent, lw,
      )
    else:
      let count = if has PointCount: the PointCount else: 32
      drawStrokeW(arc.points(count), color, lw, ct)


  w.forEach (
    curve: Curve2|OwnedCurve2|Path2,
    opt Foreground|Color|Background|Hatching,
    opt Thickness|PixelThickness,
    opt Dashing|DashingScale,
    pointCount: PointCount||curve.recommendedPointCount,
    t3: Transform3||dmat4()
  ):
    let ct = extraT * t3
    let lw = lwOf(0.1 / ctx.scale)
    let points = curve.points(pointCount)
    var pagePts: seq[Vec2]
    for q in points: pagePts.add ctx.toPagePos(ct * q.V2.vec2)

    if has Hatching:
      if has Background:
        o.pages[ctx.pi].fillPolygon(pagePts, the Background)
      let hatFg = if has Color: the Color else: wGlobals.foreground
      hatchFill(
        curve.bounds.min.V2.vec2, curve.bounds.max.V2.vec2, ct, the Hatching, hatFg,
        (if has Thickness: the Thickness else: 0.0)
      ):
        o.pages[ctx.pi].clipPolygon(pagePts)
    elif has Background:
      o.pages[ctx.pi].fillPolygon(pagePts, the Background)

    if has Foreground:
      drawStrokeW(points, the Foreground, lw, ct)
    elif (has Color) and not (has Hatching):
      drawStrokeW(points, the Color, lw, ct)
    elif not (has Background) and not (has Hatching):
      drawStrokeW(points, wGlobals.foreground, lw, ct)


  w.forEach (path: Path, opt Foreground|Color|Background|Hatching, opt Thickness|PixelThickness, t3: Transform3||dmat4()):
    let ct = extraT * t3
    let lw = lwOf(1.0)
    let transf = proc(v: Vec2): Vec2 = ctx.toPagePos(ct * v)

    if has Hatching:
      if has Background:
        o.pages[ctx.pi].drawPath(path, transf, false, true, transparent, the Background, lw)
      let hatFg = if has Color: the Color else: wGlobals.foreground
      let b = path.computeBounds()
      hatchFill(
        vec2(b.x, b.y), vec2(b.x + b.w, b.y + b.h), ct, the Hatching, hatFg,
        (if has Thickness: the Thickness else: 0.0)
      ):
        o.pages[ctx.pi].clipPath(path, transf)
    else:
      let doFill   = has Background
      let doStroke = Foreground.has or Color.has or Background.has.not
      let fg =
        if has Foreground: the Foreground
        elif has Color: the Color
        else: wGlobals.foreground
      let bg = if has Background: the Background else: transparent
      o.pages[ctx.pi].drawPath(path, transf, doStroke, doFill, fg, bg, lw)


  w.forEach (
    text: Text,
    pos: Position2 || p2(),
    posAt: PositionAt || PositionAtTopLeft,
    font: Typeface || wGlobals.font,
    fontSize: FontSize || wGlobals.fontSize,
    opt Foreground, opt Color,
    t3: Transform3||dmat4(),
  ):
    let fg =
      if has Foreground: the Foreground
      elif has Color: the Color
      else: wGlobals.foreground

    let ct     = extraT * t3
    let sizePt = fontSize.float32 * ctx.scale * mmToPt.float32
    let fnt    = font.withSize(sizePt.float64)
    let arr    = pixieFonts.typeset(fnt, text)
    let box    = arr.layoutBounds()
    let origin = posAt.factor()
    let offX   = -box.x * origin.x
    let offY   =  box.y * origin.y
    let anchor = ctx.toPagePos(extraT * vec2(pos.x.float32, pos.y.float32))

    if is3DRotation(ct):
      # Convert glyphs to paths; apply the full projected (non-normalised) transform
      var glyphPath = newPath()
      for spanIdx, (spanStart, spanStop) in arr.spans:
        let spanFont = arr.fonts[spanIdx]
        for ri in spanStart .. spanStop:
          let gp = spanFont.typeface.getGlyphPath(arr.runes[ri])
          gp.transform(translate(arr.positions[ri]) * scale(vec2(spanFont.scale)))
          glyphPath.addPath(gp)

      let ySign = if ctx.yDown: -1.0'f32 else: 1.0'f32
      let ta_f = ct[0][0].float32
      let tb_f = ct[0][1].float32 * ySign
      let tc_f = ct[1][0].float32 * ySign
      let td_f = ct[1][1].float32
      let (anchX, anchY, oX, oY) = (anchor.x, anchor.y, offX, offY)
      o.pages[ctx.pi].drawPath(
        glyphPath,
        proc(p: Vec2): Vec2 =
          let dx = p.x + oX
          let dy = oY - p.y
          vec2(anchX + ta_f * dx + tc_f * dy, anchY + tb_f * dx + td_f * dy),
        false, true,
        color(0, 0, 0, 0),
        fg,
        0,
      )
      continue

    let (ta, tb, tc, td) = ctx.textMatrix2D(ct)

    # top-left offset of text box relative to anchor, in PDF space (rotated by ta..td)
    let textTopX = anchor.x + ta * offX + tc * offY
    let textTopY = anchor.y + tb * offX + td * offY

    for (lineStart, lineStop) in arr.lines:
      # find first non-LF rune to get baseline position
      var firstIdx = lineStart
      while firstIdx <= lineStop and arr.runes[firstIdx].uint32 == 10:
        inc firstIdx
      if firstIdx > lineStop: continue

      var lineText = $arr.runes[lineStart..lineStop]
      # per-line offset in text-layout space (x: right, y: down), rotated to PDF space
      let lx = arr.positions[firstIdx].x
      let ly = -arr.positions[firstIdx].y  # pixie y-down → PDF y-up
      let baselineX = textTopX + ta * lx + tc * ly
      let baselineY = textTopY + tb * lx + td * ly

      o.pages[ctx.pi].drawText(o, font, sizePt, fg, baselineX, baselineY, lineText, ta, tb, tc, td)


  w.forEach (sub: SubWorld, pos: Position2 || p2(), opt PositionAt, t3: Transform3||dmat4()):
    if sub == nil: continue
    GC_ref(sub)
    var anchorX = 0.0
    var anchorY = 0.0
    if has PositionAt:
      let subGlobals = sub.documentGlobals
      let b = sub.documentLayout(subGlobals).contentBounds
      if not b.empty:
        let f = (the PositionAt).factor()
        let sz = b.size
        let axisYUp = subGlobals.axisYDirection == AxisYUp
        anchorX = b.min.x + f.x.float64 * sz.x
        anchorY = (if axisYUp: b.max.y - f.y.float64 * sz.y else: b.min.y + f.y.float64 * sz.y)
    let subExtraT = extraT * translate(dvec3(pos.x - anchorX, pos.y - anchorY, 0)) * t3
    renderWorld(o, ctx, sub, sub.documentGlobals, subExtraT)


proc renderPdf*(r: PdfRenerer, o: var PdfWriter) =
  if r.doc == nil or r.doc[] == nil: return
  let globals = r.doc[].documentGlobals()
  let layout  = r.doc[].documentLayout(globals)
  if layout.pageBounds.empty: return

  let scale        = globals.settings.mmScale
  let pageWidthPt  = layout.pageBounds.size.x * scale * mmToPt.float32
  let pageHeightPt = layout.pageBounds.size.y * scale * mmToPt.float32
  let pi           = o.addPage(pageWidthPt, pageHeightPt)

  let ctx = PdfRenderCtx(
    pi: pi,
    scale: scale,
    bmin: layout.pageBounds.min,
    pageHeightPt: pageHeightPt,
    yDown: globals.axisYDirection == AxisYDown,
  )

  let backgroundColor = blendColor(globals.background, color_bg)
  o.pages[pi].fillRect(0, 0, pageWidthPt, pageHeightPt, backgroundColor)

  renderWorld(o, ctx, r.doc[], globals, dmat4())


proc writePdf*(filename: string, r: PdfRenerer) =
  var o = newPdfWriter()
  renderPdf(r, o)
  o.writeToFile(filename)
