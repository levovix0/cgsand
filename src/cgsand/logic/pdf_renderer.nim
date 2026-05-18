import std/unicode
import pkg/[ecs, vmath]
import pkg/pixie/fonts as pixieFonts
import ../logic/[doclayout, bounds]
import ../lib/sandbox except Mat4, mat4, Vec4, Vec3, Vec2, vec2, vec3, vec4
import ../lib/[geom2d, text]
import ./pdf/writer


type
  PdfRenerer* = object
    doc*: ptr World


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

  r.doc[].forEach (line: LineSection, color: Color||globals.foreground, thickness: Thickness||(0.1/scale)):
    let a = sandbox.Vec2(line.startPoint).vec2
    let b = sandbox.Vec2(line.endPoint).vec2
    o.pages[pi].drawLine(
      toPagePos(a),
      toPagePos(b),
      color,
      thickness * scale * mmToPt.float32,
    )

  r.doc[].forEach (
    text: Text,
    pos: Position2,
    posAt: PositionAt || PositionAtTopLeft,
    font: Typeface || globals.font,
    fontSize: FontSize || globals.fontSize,
    opt Foreground, opt Color
  ):
    let fg =
      if has Foreground: the Foreground
      elif has Color: the Color
      else: globals.foreground

    let sizePt    = fontSize.float32 * scale * mmToPt.float32
    let fnt       = font.withSize(sizePt.float64)
    let arr       = pixieFonts.typeset(fnt, text)
    let box       = arr.layoutBounds()
    let origin    = posAt.factor()
    let anchor    = toPagePos(vec2(pos.x.float32, pos.y.float32))

    # top-left of text box in PDF Y-up coordinates
    let textTopX  = anchor.x - box.x * origin.x
    let textTopY  = anchor.y + box.y * origin.y

    for (lineStart, lineStop) in arr.lines:
      # find first non-LF rune to get baseline position
      var firstIdx = lineStart
      while firstIdx <= lineStop and arr.runes[firstIdx].uint32 == 10:
        inc firstIdx
      if firstIdx > lineStop: continue

      var lineText = $arr.runes[lineStart..lineStop]
      let baselineX = textTopX + arr.positions[firstIdx].x
      let baselineY = textTopY - arr.positions[firstIdx].y

      o.pages[pi].drawText(o, font, sizePt, fg, baselineX, baselineY, lineText)


proc writePdf*(filename: string, r: PdfRenerer) =
  var o = newPdfWriter()
  renderPdf(r, o)
  o.writeToFile(filename)
