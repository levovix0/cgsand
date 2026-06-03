import std/unicode
import pkg/[ecs, vmath]
import pkg/pixie/fonts as pixieFonts
import pkg/toscel/[colors]
import ../logic/[doclayout, document_globals]
import ../lib/sandbox except Mat4, mat4, Vec4, Vec3, Vec2, vec2, vec3, vec4
import ../lib/[geom2d, text]
import ./pdf/writer
import pkg/pixie/paths


type
  PdfRenerer* = object
    doc*: World


proc renderPdf*(r: PdfRenerer, o: var PdfWriter) =
  let globals = r.doc.documentGlobals()
  let layout  = r.doc.documentLayout(globals)
  if layout.pageBounds.empty: return

  let scale        = globals.settings.mmScale
  let pageWidthPt  = layout.pageBounds.size.x * scale * mmToPt.float32
  let pageHeightPt = layout.pageBounds.size.y * scale * mmToPt.float32
  let pi           = o.addPage(pageWidthPt, pageHeightPt)
  let bmin         = layout.pageBounds.min
  let yDown        = globals.axisYDirection == AxisYDown

  proc toPagePos(w: Vec2): Vec2 =
    vec2(
      (w.x - bmin.x) * scale * mmToPt.float32,
      if yDown: pageHeightPt - (w.y - bmin.y) * scale * mmToPt.float32
      else:     (w.y - bmin.y) * scale * mmToPt.float32,
    )

  proc `*`(t: DMat4, p: Vec2): Vec2 =
    let r = t * dvec4(p.x.float64, p.y.float64, 0, 1)
    vec2(r.x.float32, r.y.float32)

  proc is3DRotation(t: DMat4): bool =
    ## true when the transform rotates XY vectors into Z (3D tilt)
    abs(t[0][2]) > 1e-6 or abs(t[1][2]) > 1e-6

  proc textMatrix2D(t: DMat4): tuple[ta, tb, tc, td: float32] =
    ## Builds the PDF Tm 2x2 matrix from Transform3, accounting for the
    ## document-to-PDF y-flip (yDown doc → y-axis inverted in page space).
    ## Includes scale so that Transform3 scale is reflected in rendered size.
    let ySign = if yDown: -1.0 else: 1.0
    (
      ta: float32(t[0][0]),
      tb: float32(t[0][1] * ySign),
      tc: float32(t[1][0] * ySign),
      td: float32(t[1][1]),
    )

  let backgroundColor = blendColor(globals.background, color_bg)
  o.pages[pi].fillRect(0, 0, pageWidthPt, pageHeightPt, backgroundColor)

  proc renderWorld(o: var PdfWriter, w: World, wGlobals: DocumentGlobals, extraT: DMat4) =
    w.forEach (line: LineSection, color: (Foreground|Color)||wGlobals.foreground, thickness: Thickness||(0.1/scale), pixThick: opt PixelThickness, t: Transform3||dmat4()):
      let ct = extraT * t
      let a = ct * sandbox.Vec2(line.startPoint).vec2
      let b = ct * sandbox.Vec2(line.endPoint).vec2
      o.pages[pi].drawLine(
        toPagePos(a),
        toPagePos(b),
        color,
        if has PixelThickness: pixThick else: thickness * scale * mmToPt.float32,
      )

    w.forEach (curve: CircleArc, count: PointCount||20, opt Color, opt Background, opt Foreground, thickness: Thickness||(0.1/scale), pixThick: opt PixelThickness, t3: Transform3||dmat4()):
      let ct = extraT * t3
      let fg =
        if has Foreground: the Foreground
        elif has Color: the Color
        else: wGlobals.foreground
      let lw = if has PixelThickness: pixThick else: thickness * scale * mmToPt.float32

      if not (has PointCount):
        let cx = float32(curve.center.x)
        let cy = float32(curve.center.y)
        let r  = float32(curve.radius)
        let doFill   = curve.closed and (has Background)
        let doStroke = not curve.closed or not (has Background) or (Color.has or Foreground.has)
        let bg       = if has Background: the Background else: color(0, 0, 0, 0)
        let transf   = proc(v: Vec2): Vec2 = toPagePos(ct * v)
        o.pages[pi].drawBezierEllipseArc(
          cx, cy, r, r,
          float32(curve.startAngle), float32(curve.angularLength),
          transf, doStroke, doFill, curve.closed,
          fg, bg, lw,
        )
      else:
        let pts = curve.points(count)
        var pagePts: seq[Vec2]
        for p in pts:
          pagePts.add toPagePos(ct * vec2(p.x.float32, p.y.float32))
        if curve.closed:
          if has Background:
            if Color.has or Foreground.has:
              o.pages[pi].drawPolylineWithFill(pagePts, fg, the Background, lw)
            else:
              o.pages[pi].fillPolygon(pagePts, the Background)
          else:
            o.pages[pi].drawPolyline(pagePts, fg, lw)
        else:
          o.pages[pi].drawPolyline(pagePts, fg, lw)


    w.forEach (arc: EllipseArc, color: (Foreground|Color)||wGlobals.foreground, count: PointCount||32, thickness: Thickness||(0.1/scale), pixThick: opt PixelThickness, t3: Transform3||dmat4()):
      let ct = extraT * t3
      let lw = if has PixelThickness: pixThick else: thickness * scale * mmToPt.float32

      if not (has PointCount):
        let cx = float32(arc.center.x)
        let cy = float32(arc.center.y)
        let rx = float32(arc.size.x / 2)
        let ry = float32(arc.size.y / 2)
        let transf = proc(v: Vec2): Vec2 = toPagePos(ct * v)
        o.pages[pi].drawBezierEllipseArc(
          cx, cy, rx, ry,
          float32(arc.startAngle), float32(arc.angularLength),
          transf, true, false, arc.fullEllipse,
          color, color(0, 0, 0, 0), lw,
        )
      else:
        let pts = arc.points(count)
        var pagePts: seq[Vec2]
        for p in pts:
          pagePts.add toPagePos(ct * vec2(p.x.float32, p.y.float32))
        o.pages[pi].drawPolyline(pagePts, color, lw)


    w.forEach (path: Path, opt Foreground|Color, thickness: Thickness||1, pixThick: opt PixelThickness, opt Background, t3: Transform3||dmat4()):
      let ct = extraT * t3
      let doFill   = Background.has or (Foreground.has.not and Color.has.not)
      let doStroke = Foreground.has or Color.has
      let fg =
        if has Foreground: the Foreground
        elif has Color: the Color
        else: wGlobals.foreground
      let bg = if has Background: the Background else: color(0, 0, 0, 0)
      o.pages[pi].drawPath(
        path,
        proc(v: Vec2): Vec2 = toPagePos(ct * v),
        doStroke,
        doFill,
        fg,
        bg,
        if has PixelThickness: pixThick else: thickness * scale * mmToPt.float32,
      )


    w.forEach (
      text: Text,
      pos: Position2,
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
      let sizePt = fontSize.float32 * scale * mmToPt.float32
      let fnt    = font.withSize(sizePt.float64)
      let arr    = pixieFonts.typeset(fnt, text)
      let box    = arr.layoutBounds()
      let origin = posAt.factor()
      let offX   = -box.x * origin.x
      let offY   =  box.y * origin.y
      let anchor = toPagePos(extraT * vec2(pos.x.float32, pos.y.float32))

      if is3DRotation(ct):
        # Convert glyphs to paths; apply the full projected (non-normalised) transform
        var glyphPath = newPath()
        for spanIdx, (spanStart, spanStop) in arr.spans:
          let spanFont = arr.fonts[spanIdx]
          for ri in spanStart .. spanStop:
            let gp = spanFont.typeface.getGlyphPath(arr.runes[ri])
            gp.transform(translate(arr.positions[ri]) * scale(vec2(spanFont.scale)))
            glyphPath.addPath(gp)

        let ySign = if yDown: -1.0'f32 else: 1.0'f32
        let ta_f = ct[0][0].float32
        let tb_f = ct[0][1].float32 * ySign
        let tc_f = ct[1][0].float32 * ySign
        let td_f = ct[1][1].float32
        let (anchX, anchY, oX, oY) = (anchor.x, anchor.y, offX, offY)
        o.pages[pi].drawPath(
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

      let (ta, tb, tc, td) = textMatrix2D(ct)

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

        o.pages[pi].drawText(o, font, sizePt, fg, baselineX, baselineY, lineText, ta, tb, tc, td)


    w.forEach (sub: SubWorld, pos: Position2, t3: Transform3||dmat4()):
      if sub == nil: continue
      GC_ref(sub)
      let subExtraT = extraT * translate(dvec3(pos.x, pos.y, 0)) * t3
      o.renderWorld(sub, sub.documentGlobals, subExtraT)

  o.renderWorld(r.doc, globals, dmat4())


proc writePdf*(filename: string, r: PdfRenerer) =
  var o = newPdfWriter()
  renderPdf(r, o)
  o.writeToFile(filename)
