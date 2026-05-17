import pkg/[ecs, vmath]
import ../logic/[doclayout, bounds]
import ../lib/sandbox except Mat4, mat4, Vec4, Vec3, Vec2, vec2, vec3, vec4
import ../lib/[geom2d]
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


proc writePdf*(filename: string, r: PdfRenerer) =
  var o = newPdfWriter()
  renderPdf(r, o)
  o.writeToFile(filename)
