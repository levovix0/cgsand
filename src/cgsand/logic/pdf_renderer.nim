import std/unicode
import pkg/[ecs, vmath]
import pkg/pixie/fonts as pixieFonts
import pkg/toscel/[colors]
import ../logic/[doclayout, bounds]
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
    ## Extracts the normalized 2D text-direction matrix for PDF Tm from Transform3.
    ## Accounts for document-to-PDF y-flip (yDown → yUp).
    ## Returns (a,b,c,d) where (a,b) is text x-direction and (c,d) is text y-direction in PDF space.
    let ySign = if yDown: -1.0 else: 1.0
    let sx = sqrt(t[0][0]*t[0][0] + t[0][1]*t[0][1])
    let sy = sqrt(t[1][0]*t[1][0] + t[1][1]*t[1][1])
    let invSx = if sx > 1e-9: 1.0 / sx else: 1.0
    let invSy = if sy > 1e-9: 1.0 / sy else: 1.0
    (
      ta: float32(t[0][0] * invSx),
      tb: float32(-t[0][1] * ySign * invSx),
      tc: float32(t[1][0] * invSy),
      td: float32(-t[1][1] * ySign * invSy),
    )

  let backgroundColor = blendColor(globals.background, color_bg)
  o.pages[pi].fillRect(0, 0, pageWidthPt, pageHeightPt, backgroundColor)

  r.doc.forEach (line: LineSection, color: (Foreground|Color)||globals.foreground, thickness: Thickness||(0.1/scale), pixThick: opt PixelThickness, t: Transform3||dmat4()):
    let a = t * sandbox.Vec2(line.startPoint).vec2
    let b = t * sandbox.Vec2(line.endPoint).vec2
    o.pages[pi].drawLine(
      toPagePos(a),
      toPagePos(b),
      color,
      if has PixelThickness: pixThick else: thickness * scale * mmToPt.float32,
    )

  r.doc.forEach (curve: CircleArc, count: PointCount||20, opt Color, opt Background, opt Foreground, thickness: Thickness||(0.1/scale), pixThick: opt PixelThickness, t3: Transform3||dmat4()):
    let pts = curve.points(count)
    var pagePts: seq[Vec2]
    for p in pts:
      pagePts.add toPagePos(t3 * vec2(p.x.float32, p.y.float32))

    let fg =
      if has Foreground: the Foreground
      elif has Color: the Color
      else: globals.foreground
    let lw = if has PixelThickness: pixThick else: thickness * scale * mmToPt.float32

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


  r.doc.forEach (arc: EllipseArc, color: (Foreground|Color)||globals.foreground, count: PointCount||32, thickness: Thickness||(0.1/scale), pixThick: opt PixelThickness, t3: Transform3||dmat4()):
    let pts = arc.points(count)
    var pagePts: seq[Vec2]
    for p in pts:
      pagePts.add toPagePos(t3 * vec2(p.x.float32, p.y.float32))
    o.pages[pi].drawPolyline(pagePts, color, if has PixelThickness: pixThick else: thickness * scale * mmToPt.float32)


  r.doc.forEach (path: Path, opt Foreground|Color, thickness: Thickness||1, pixThick: opt PixelThickness, opt Background, t3: Transform3||dmat4()):
    let doFill   = Background.has or (Foreground.has.not and Color.has.not)
    let doStroke = Foreground.has or Color.has
    let fg =
      if has Foreground: the Foreground
      elif has Color: the Color
      else: globals.foreground
    let bg = if has Background: the Background else: color(0, 0, 0, 0)
    o.pages[pi].drawPath(
      path,
      proc(v: Vec2): Vec2 = toPagePos(t3 * v),
      doStroke,
      doFill,
      fg,
      bg,
      if has PixelThickness: pixThick else: thickness * scale * mmToPt.float32,
    )


  r.doc.forEach (
    text: Text,
    pos: Position2,
    posAt: PositionAt || PositionAtTopLeft,
    font: Typeface || globals.font,
    fontSize: FontSize || globals.fontSize,
    opt Foreground, opt Color,
    t3: Transform3||dmat4(),
  ):
    let fg =
      if has Foreground: the Foreground
      elif has Color: the Color
      else: globals.foreground

    if is3DRotation(t3): continue

    let sizePt    = fontSize.float32 * scale * mmToPt.float32
    let fnt       = font.withSize(sizePt.float64)
    let arr       = pixieFonts.typeset(fnt, text)
    let box       = arr.layoutBounds()
    let origin    = posAt.factor()

    let (ta, tb, tc, td) = textMatrix2D(t3)
    let anchor = toPagePos(vec2(pos.x.float32, pos.y.float32))

    # top-left offset of text box relative to anchor, in PDF space (rotated by ta..td)
    let offX = -box.x * origin.x
    let offY =  box.y * origin.y
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


proc writePdf*(filename: string, r: PdfRenerer) =
  var o = newPdfWriter()
  renderPdf(r, o)
  o.writeToFile(filename)
