import std/[strutils, memfiles, importutils, unicode, tables, math]
import pkg/[vmath, chroma]
import pkg/pixie/fonts
import pkg/pixie/fontformats/opentype
import pkg/pixie/paths as pixiePaths

privateAccess(Typeface)
privateAccess(pixiePaths.Path)


const mmToPt* = 72.0 / 25.4


type
  PdfEmbeddedFont = object
    typeface: Typeface
    usedGlyphs: OrderedTable[uint16, Rune]  # glyphId → rune (for ToUnicode CMap)

  PdfPage* = object
    widthPt*, heightPt*: float32
    content*: string
    alphas: seq[float32]
    lastR, lastG, lastB, lastA: float32
    lastLW: float32
    colorSet, lwSet: bool
    lastFR, lastFG, lastFB: float32
    fillColorSet: bool
    usedFonts: seq[int]

  PdfWriter* = object
    pages*: seq[PdfPage]
    fonts: seq[PdfEmbeddedFont]

  MemFileContext* = object
    mf*: MemFile
    pos*: int

  PdfXrefEntry* = distinct int


proc pdfNum*(f: float32): string =
  result = formatFloat(f.float64, ffDecimal, 4)
  if '.' in result:
    var i = result.high
    while i > 0 and result[i] == '0': dec i
    if result[i] == '.': inc i
    result.setLen(i + 1)


proc newPdfWriter*(): PdfWriter = PdfWriter()

proc addPage*(w: var PdfWriter; widthPt, heightPt: float32): int =
  w.pages.add PdfPage(widthPt: widthPt, heightPt: heightPt, lastA: 1.0)
  w.pages.high


proc ensureAlpha(p: var PdfPage; a: float32): int =
  for i, v in p.alphas:
    if v == a: return i
  result = p.alphas.len
  p.alphas.add a

proc ensureFont(w: var PdfWriter; tf: Typeface): int =
  if tf.filePath.len == 0: return -1
  for i, f in w.fonts:
    if f.typeface == tf: return i
  w.fonts.add PdfEmbeddedFont(typeface: tf)
  w.fonts.high


proc setStrokeColor*(p: var PdfPage; color: Color) =
  if not p.colorSet or p.lastR != color.r or p.lastG != color.g or p.lastB != color.b:
    p.content.add pdfNum(color.r) & " " & pdfNum(color.g) & " " & pdfNum(color.b) & " RG\n"
    p.lastR = color.r; p.lastG = color.g; p.lastB = color.b
    p.colorSet = true

  if p.lastA != color.a:
    let idx = p.ensureAlpha(color.a)
    p.content.add "/GS" & $idx & " gs\n"
    p.lastA = color.a


proc setFillColor*(p: var PdfPage; color: Color) =
  if not p.fillColorSet or p.lastFR != color.r or p.lastFG != color.g or p.lastFB != color.b:
    p.content.add pdfNum(color.r) & " " & pdfNum(color.g) & " " & pdfNum(color.b) & " rg\n"
    p.lastFR = color.r; p.lastFG = color.g; p.lastFB = color.b
    p.fillColorSet = true

  if p.lastA != color.a:
    let idx = p.ensureAlpha(color.a)
    p.content.add "/GS" & $idx & " gs\n"
    p.lastA = color.a


proc setLineWidth*(p: var PdfPage; w: float32) =
  if not p.lwSet or p.lastLW != w:
    p.content.add pdfNum(w) & " w\n"
    p.lastLW = w
    p.lwSet = true


proc moveTo*(p: var PdfPage; pos: Vec2) =
  p.content.add pdfNum(pos.x) & " " & pdfNum(pos.y) & " m\n"

proc lineTo*(p: var PdfPage; pos: Vec2) =
  p.content.add pdfNum(pos.x) & " " & pdfNum(pos.y) & " l\n"

proc stroke*(p: var PdfPage) =
  p.content.add "S\n"


proc closePath*(p: var PdfPage) =
  p.content.add "h\n"

proc fill*(p: var PdfPage) =
  p.content.add "f\n"

proc fillStroke*(p: var PdfPage) =
  p.content.add "B\n"


proc drawLine*(p: var PdfPage; a, b: Vec2; color: Color; lw: float32) =
  p.setStrokeColor(color)
  p.setLineWidth(lw)
  p.moveTo(a)
  p.lineTo(b)
  p.stroke()


proc fillRect*(p: var PdfPage; x, y, w, h: float32; color: Color) =
  p.setFillColor(color)
  p.content.add pdfNum(x) & " " & pdfNum(y) & " " & pdfNum(w) & " " & pdfNum(h) & " re\nf\n"


proc drawPolyline*(p: var PdfPage; points: openArray[Vec2]; color: Color; lw: float32) =
  if points.len < 2: return
  p.setStrokeColor(color)
  p.setLineWidth(lw)
  p.moveTo(points[0])
  for i in 1 ..< points.len:
    p.lineTo(points[i])
  p.stroke()


proc fillPolygon*(p: var PdfPage; points: openArray[Vec2]; color: Color) =
  if points.len < 2: return
  p.setFillColor(color)
  p.moveTo(points[0])
  for i in 1 ..< points.len:
    p.lineTo(points[i])
  p.closePath()
  p.fill()


proc drawPolylineWithFill*(p: var PdfPage; points: openArray[Vec2]; strokeColor, fillColor: Color; lw: float32) =
  if points.len < 2: return
  p.setStrokeColor(strokeColor)
  p.setFillColor(fillColor)
  p.setLineWidth(lw)
  p.moveTo(points[0])
  for i in 1 ..< points.len:
    p.lineTo(points[i])
  p.closePath()
  p.fillStroke()


proc pathCubicTo*(p: var PdfPage; c1, c2, ep: Vec2) =
  p.content.add pdfNum(c1.x) & " " & pdfNum(c1.y) & " " &
               pdfNum(c2.x) & " " & pdfNum(c2.y) & " " &
               pdfNum(ep.x) & " " & pdfNum(ep.y) & " c\n"


proc arcSegmentToBeziers(cx, cy, rx, ry, phi, theta, dtheta: float32): seq[(Vec2, Vec2, Vec2)] =
  let n = max(1, int(abs(dtheta) / (Pi * 0.5) + 0.9999))
  let step = dtheta / float32(n)
  let cosPhi = cos(phi)
  let sinPhi = sin(phi)

  proc pt(a: float32): Vec2 =
    vec2(cx + rx * cosPhi * cos(a) - ry * sinPhi * sin(a),
         cy + rx * sinPhi * cos(a) + ry * cosPhi * sin(a))

  proc dt(a: float32): Vec2 =
    vec2(-rx * cosPhi * sin(a) - ry * sinPhi * cos(a),
         -rx * sinPhi * sin(a) + ry * cosPhi * cos(a))

  var angle = theta
  var cur = pt(angle)
  for _ in 0 ..< n:
    let next = angle + step
    let tHalf = tan(step * 0.5)
    let alpha = sin(step) * (sqrt(4 + 3 * tHalf * tHalf) - 1) / 3
    let ep = pt(next)
    result.add((cur + dt(angle) * alpha, ep - dt(next) * alpha, ep))
    cur = ep
    angle = next


proc svgArcToBeziers(p1: Vec2; rx0, ry0, phi, fA, fS: float32; p2: Vec2): seq[(Vec2, Vec2, Vec2)] =
  var rx = abs(rx0)
  var ry = abs(ry0)
  if rx == 0 or ry == 0: return
  let cosPhi = cos(phi)
  let sinPhi = sin(phi)
  let dx = (p1.x - p2.x) * 0.5
  let dy = (p1.y - p2.y) * 0.5
  let x1p =  cosPhi * dx + sinPhi * dy
  let y1p = -sinPhi * dx + cosPhi * dy
  let lambda2 = (x1p / rx)^2 + (y1p / ry)^2
  if lambda2 > 1:
    let lam = sqrt(lambda2)
    rx *= lam; ry *= lam
  let num = max(0.0'f32, rx*rx*ry*ry - rx*rx*y1p*y1p - ry*ry*x1p*x1p)
  let den = rx*rx*y1p*y1p + ry*ry*x1p*x1p
  let sq = if den == 0: 0.0'f32 else: sqrt(num / den)
  let sign = if (fA != 0) == (fS != 0): -1.0'f32 else: 1.0'f32
  let cxp =  sign * sq * rx * y1p / ry
  let cyp = -sign * sq * ry * x1p / rx
  let cx = cosPhi * cxp - sinPhi * cyp + (p1.x + p2.x) * 0.5
  let cy = sinPhi * cxp + cosPhi * cyp + (p1.y + p2.y) * 0.5

  proc vecAngle(ux, uy, vx, vy: float32): float32 =
    let n = sqrt(ux*ux + uy*uy) * sqrt(vx*vx + vy*vy)
    if n == 0: return 0
    result = arccos(clamp((ux*vx + uy*vy) / n, -1.0'f32, 1.0'f32))
    if ux*vy - uy*vx < 0: result = -result

  let theta1 = vecAngle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
  var dtheta = vecAngle((x1p - cxp) / rx, (y1p - cyp) / ry,
                        (-x1p - cxp) / rx, (-y1p - cyp) / ry)
  if fS == 0 and dtheta > 0: dtheta -= 2 * Pi
  elif fS != 0 and dtheta < 0: dtheta += 2 * Pi

  arcSegmentToBeziers(cx, cy, rx, ry, phi, theta1, dtheta)


proc drawPath*(
  p:           var PdfPage;
  path:        pixiePaths.Path;
  transform:   proc(v: Vec2): Vec2;
  doStroke:    bool;
  doFill:      bool;
  strokeColor: Color;
  fillColor:   Color;
  lw:          float32
) =
  if not doStroke and not doFill: return
  if doStroke: p.setStrokeColor(strokeColor)
  if doFill:   p.setFillColor(fillColor)
  if doStroke: p.setLineWidth(lw)

  var cur    = vec2(0'f32, 0'f32)
  var start  = vec2(0'f32, 0'f32)
  var lastC2 = vec2(0'f32, 0'f32)
  var lastQ1 = vec2(0'f32, 0'f32)

  template emit(pt: Vec2; op: string) =
    let tpt = transform(pt)
    p.content.add pdfNum(tpt.x) & " " & pdfNum(tpt.y) & " " & op & "\n"

  var i = 0
  while i < path.commands.len:
    let cmd = int(path.commands[i])
    inc i
    case cmd
    of 0:  # Close
      p.closePath()
      cur = start
    of 1:  # Move
      let pt = vec2(path.commands[i], path.commands[i+1]); i += 2
      emit(pt, "m"); cur = pt; start = pt
    of 2:  # Line
      let pt = vec2(path.commands[i], path.commands[i+1]); i += 2
      emit(pt, "l"); cur = pt
    of 3:  # HLine
      let pt = vec2(path.commands[i], cur.y); i += 1
      emit(pt, "l"); cur = pt
    of 4:  # VLine
      let pt = vec2(cur.x, path.commands[i]); i += 1
      emit(pt, "l"); cur = pt
    of 5:  # Cubic
      let c1 = vec2(path.commands[i],   path.commands[i+1])
      let c2 = vec2(path.commands[i+2], path.commands[i+3])
      let ep = vec2(path.commands[i+4], path.commands[i+5]); i += 6
      p.pathCubicTo(transform(c1), transform(c2), transform(ep))
      lastC2 = c2; cur = ep
    of 6:  # SCubic (smooth, absolute)
      let c1 = cur * 2 - lastC2
      let c2 = vec2(path.commands[i],   path.commands[i+1])
      let ep = vec2(path.commands[i+2], path.commands[i+3]); i += 4
      p.pathCubicTo(transform(c1), transform(c2), transform(ep))
      lastC2 = c2; cur = ep
    of 7:  # Quad
      let q1 = vec2(path.commands[i],   path.commands[i+1])
      let ep = vec2(path.commands[i+2], path.commands[i+3]); i += 4
      p.pathCubicTo(transform(cur + (q1-cur)*(2/3)), transform(ep + (q1-ep)*(2/3)), transform(ep))
      lastQ1 = q1; cur = ep
    of 8:  # TQuad (smooth, absolute)
      let q1 = cur * 2 - lastQ1
      let ep = vec2(path.commands[i], path.commands[i+1]); i += 2
      p.pathCubicTo(transform(cur + (q1-cur)*(2/3)), transform(ep + (q1-ep)*(2/3)), transform(ep))
      lastQ1 = q1; cur = ep
    of 9:  # Arc
      let rx  = path.commands[i];   let ry  = path.commands[i+1]
      let phi = path.commands[i+2] * Pi / 180.0
      let fA  = path.commands[i+3]; let fS  = path.commands[i+4]
      let ep  = vec2(path.commands[i+5], path.commands[i+6]); i += 7
      for item in svgArcToBeziers(cur, rx, ry, phi, fA, fS, ep):
        p.pathCubicTo(transform(item[0]), transform(item[1]), transform(item[2]))
      cur = ep
    of 10: # RMove
      let pt = cur + vec2(path.commands[i], path.commands[i+1]); i += 2
      emit(pt, "m"); cur = pt; start = pt
    of 11: # RLine
      let pt = cur + vec2(path.commands[i], path.commands[i+1]); i += 2
      emit(pt, "l"); cur = pt
    of 12: # RHLine
      let pt = cur + vec2(path.commands[i], 0'f32); i += 1
      emit(pt, "l"); cur = pt
    of 13: # RVLine
      let pt = cur + vec2(0'f32, path.commands[i]); i += 1
      emit(pt, "l"); cur = pt
    of 14: # RCubic
      let c1 = cur + vec2(path.commands[i],   path.commands[i+1])
      let c2 = cur + vec2(path.commands[i+2], path.commands[i+3])
      let ep = cur + vec2(path.commands[i+4], path.commands[i+5]); i += 6
      p.pathCubicTo(transform(c1), transform(c2), transform(ep))
      lastC2 = c2; cur = ep
    of 15: # RSCubic
      let c1 = cur * 2 - lastC2
      let c2 = cur + vec2(path.commands[i],   path.commands[i+1])
      let ep = cur + vec2(path.commands[i+2], path.commands[i+3]); i += 4
      p.pathCubicTo(transform(c1), transform(c2), transform(ep))
      lastC2 = c2; cur = ep
    of 16: # RQuad
      let q1 = cur + vec2(path.commands[i],   path.commands[i+1])
      let ep = cur + vec2(path.commands[i+2], path.commands[i+3]); i += 4
      p.pathCubicTo(transform(cur + (q1-cur)*(2/3)), transform(ep + (q1-ep)*(2/3)), transform(ep))
      lastQ1 = q1; cur = ep
    of 17: # RTQuad
      let q1 = cur * 2 - lastQ1
      let ep = cur + vec2(path.commands[i], path.commands[i+1]); i += 2
      p.pathCubicTo(transform(cur + (q1-cur)*(2/3)), transform(ep + (q1-ep)*(2/3)), transform(ep))
      lastQ1 = q1; cur = ep
    of 18: # RArc
      let rx  = path.commands[i];   let ry  = path.commands[i+1]
      let phi = path.commands[i+2] * Pi / 180.0
      let fA  = path.commands[i+3]; let fS  = path.commands[i+4]
      let ep  = cur + vec2(path.commands[i+5], path.commands[i+6]); i += 7
      for item in svgArcToBeziers(cur, rx, ry, phi, fA, fS, ep):
        p.pathCubicTo(transform(item[0]), transform(item[1]), transform(item[2]))
      cur = ep
    else: break

    # reset smooth-curve anchors for non-cubic / non-quad commands
    if cmd notin {5, 6, 14, 15}: lastC2 = cur
    if cmd notin {7, 8, 16, 17}: lastQ1 = cur

  if doFill and doStroke: p.fillStroke()
  elif doFill:            p.fill()
  elif doStroke:          p.stroke()


proc drawText*(p: var PdfPage; w: var PdfWriter;
               typeface: Typeface; sizePt: float32;
               color: Color; baselineX, baselineY: float32; text: string;
               ta: float32 = 1; tb: float32 = 0; tc: float32 = 0; td: float32 = 1) =
  ## ta..td: 2D text matrix columns (a,b = text-x direction; c,d = text-y direction in PDF space).
  ## Defaults to identity (horizontal text). Use non-default values to apply rotation/shear.
  if text.len == 0: return
  let fontIdx = w.ensureFont(typeface)
  if fontIdx < 0: return

  if fontIdx notin p.usedFonts:
    p.usedFonts.add fontIdx

  var hexGlyphs = ""
  for rune in text.runes:
    let gid: uint16 =
      if typeface.opentype != nil and typeface.opentype.cmap != nil:
        typeface.opentype.cmap.runeToGlyphId.getOrDefault(rune, 0)
      else:
        0'u16
    w.fonts[fontIdx].usedGlyphs[gid] = rune
    hexGlyphs.add toHex(gid.int, 4)

  p.setFillColor(color)
  p.content.add "BT\n"
  p.content.add "/Ff" & $fontIdx & " " & pdfNum(sizePt) & " Tf\n"
  p.content.add pdfNum(ta) & " " & pdfNum(tb) & " " & pdfNum(tc) & " " & pdfNum(td) & " " & pdfNum(baselineX) & " " & pdfNum(baselineY) & " Tm\n"
  p.content.add "<" & hexGlyphs & "> Tj\n"
  p.content.add "ET\n"


proc pdfCurrentPos(o: string): int = o.len
proc pdfSerializeWrite(s: string,  o: var string)  = o.add s
proc pdfSerializeWrite(n: int,     o: var string)  = o.add $n
proc pdfSerializeWrite(f: float32, o: var string)  = o.add pdfNum(f)

proc pdfCurrentPos(o: int): int = o
proc pdfSerializeWrite(s: string,  o: var int) = o += s.len
proc pdfSerializeWrite(n: int,     o: var int) = o += ($n).len
proc pdfSerializeWrite(f: float32, o: var int) = o += pdfNum(f).len

proc pdfCurrentPos(o: MemFileContext): int = o.pos
proc pdfSerializeWrite(s: string, o: var MemFileContext) =
  if s.len > 0:
    copyMem(cast[pointer](cast[int](o.mf.mem) + o.pos), unsafeAddr s[0], s.len)
  o.pos += s.len
proc pdfSerializeWrite(n: int,     o: var MemFileContext) = pdfSerializeWrite($n, o)
proc pdfSerializeWrite(f: float32, o: var MemFileContext) = pdfSerializeWrite(pdfNum(f), o)

proc pdfSerializeWrite(e: PdfXrefEntry, o: var string) =
  o.add ($e.int).align(10, '0') & " 00000 n \n"
proc pdfSerializeWrite(e: PdfXrefEntry, o: var int) = o += 20
proc pdfSerializeWrite(e: PdfXrefEntry, o: var MemFileContext) =
  pdfSerializeWrite(($e.int).align(10, '0') & " 00000 n \n", o)


proc writeCMap[T](font: PdfEmbeddedFont; j: int; o: var T) =
  pdfSerializeWrite("/CIDInit /ProcSet findresource begin\n12 dict begin\nbegincmap\n", o)
  pdfSerializeWrite("/CIDSystemInfo << /Registry (Adobe) /Ordering (UCS) /Supplement 0 >> def\n", o)
  pdfSerializeWrite("/CMapName /Ff", o)
  pdfSerializeWrite(j, o)
  pdfSerializeWrite("-UCS def\n/CMapType 2 def\n1 begincodespacerange\n<0000> <FFFF>\nendcodespacerange\n", o)
  if font.usedGlyphs.len > 0:
    pdfSerializeWrite(font.usedGlyphs.len, o)
    pdfSerializeWrite(" beginbfchar\n", o)
    for gid, rune in font.usedGlyphs:
      let cp = rune.uint32
      pdfSerializeWrite("<", o)
      pdfSerializeWrite(toHex(gid.int, 4), o)
      pdfSerializeWrite("> <", o)
      if cp < 0x10000'u32:
        pdfSerializeWrite(toHex(cp.int, 4), o)
      else:
        let u  = cp - 0x10000'u32
        let hi = 0xD800'u32 + (u shr 10)
        let lo = 0xDC00'u32 + (u and 0x3FF)
        pdfSerializeWrite(toHex(hi.int, 4), o)
        pdfSerializeWrite(toHex(lo.int, 4), o)
      pdfSerializeWrite(">\n", o)
    pdfSerializeWrite("endbfchar\n", o)
  pdfSerializeWrite("endcmap\nCMapName currentdict /CMap defineresource pop\nend\nend\n", o)


proc pdfSerialize[T](w: PdfWriter, o: var T) =
  var offsets: seq[int]
  let fontBase = 3 + w.pages.len * 2

  pdfSerializeWrite("%PDF-1.4\n", o)

  offsets.add pdfCurrentPos(o)
  pdfSerializeWrite("1 0 obj\n<< /Type /Catalog /Pages 2 0 R >>\nendobj\n", o)

  offsets.add pdfCurrentPos(o)
  pdfSerializeWrite("2 0 obj\n<< /Type /Pages /Count ", o)
  pdfSerializeWrite(w.pages.len, o)
  pdfSerializeWrite(" /Kids [", o)
  for i in 0 ..< w.pages.len:
    if i > 0: pdfSerializeWrite(" ", o)
    pdfSerializeWrite(3 + i * 2, o)
    pdfSerializeWrite(" 0 R", o)
  pdfSerializeWrite("] >>\nendobj\n", o)

  for i, page in w.pages:
    let pageN    = 3 + i * 2
    let contentN = pageN + 1

    offsets.add pdfCurrentPos(o)
    pdfSerializeWrite(pageN, o)
    pdfSerializeWrite(" 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ", o)
    pdfSerializeWrite(page.widthPt, o)
    pdfSerializeWrite(" ", o)
    pdfSerializeWrite(page.heightPt, o)
    pdfSerializeWrite("] /Contents ", o)
    pdfSerializeWrite(contentN, o)
    pdfSerializeWrite(" 0 R", o)
    if page.alphas.len > 0 or page.usedFonts.len > 0:
      pdfSerializeWrite(" /Resources <<", o)
      if page.alphas.len > 0:
        pdfSerializeWrite(" /ExtGState <<", o)
        for j, a in page.alphas:
          pdfSerializeWrite(" /GS", o)
          pdfSerializeWrite(j, o)
          pdfSerializeWrite(" << /Type /ExtGState /CA ", o)
          pdfSerializeWrite(a, o)
          pdfSerializeWrite(" /ca ", o)
          pdfSerializeWrite(a, o)
          pdfSerializeWrite(" >>", o)
        pdfSerializeWrite(" >>", o)
      if page.usedFonts.len > 0:
        pdfSerializeWrite(" /Font <<", o)
        for fontIdx in page.usedFonts:
          pdfSerializeWrite(" /Ff", o)
          pdfSerializeWrite(fontIdx, o)
          pdfSerializeWrite(" ", o)
          pdfSerializeWrite(fontBase + fontIdx * 5, o)
          pdfSerializeWrite(" 0 R", o)
        pdfSerializeWrite(" >>", o)
      pdfSerializeWrite(" >>", o)
    pdfSerializeWrite(" >>\nendobj\n", o)

    offsets.add pdfCurrentPos(o)
    pdfSerializeWrite(contentN, o)
    pdfSerializeWrite(" 0 obj\n<< /Length ", o)
    pdfSerializeWrite(page.content.len, o)
    pdfSerializeWrite(" >>\nstream\n", o)
    pdfSerializeWrite(page.content, o)
    pdfSerializeWrite("\nendstream\nendobj\n", o)

  for j, font in w.fonts:
    let type0N = fontBase + j * 5
    let cidN   = type0N + 1
    let descN  = type0N + 2
    let fileN  = type0N + 3
    let toUniN = type0N + 4

    let fontBytes  = readFile(font.typeface.filePath)
    let unitsPerEm = font.typeface.scale
    let ascent     = font.typeface.ascent    * 1000.0 / unitsPerEm
    let descent    = font.typeface.descent   * 1000.0 / unitsPerEm
    let capHeight  = font.typeface.capHeight * 1000.0 / unitsPerEm

    offsets.add pdfCurrentPos(o)
    pdfSerializeWrite(type0N, o)
    pdfSerializeWrite(" 0 obj\n<< /Type /Font /Subtype /Type0 /BaseFont /Ff", o)
    pdfSerializeWrite(j, o)
    pdfSerializeWrite(" /Encoding /Identity-H /DescendantFonts [", o)
    pdfSerializeWrite(cidN, o)
    pdfSerializeWrite(" 0 R] /ToUnicode ", o)
    pdfSerializeWrite(toUniN, o)
    pdfSerializeWrite(" 0 R >>\nendobj\n", o)

    offsets.add pdfCurrentPos(o)
    pdfSerializeWrite(cidN, o)
    pdfSerializeWrite(" 0 obj\n<< /Type /Font /Subtype /CIDFontType2 /BaseFont /Ff", o)
    pdfSerializeWrite(j, o)
    pdfSerializeWrite(" /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >>", o)
    pdfSerializeWrite(" /FontDescriptor ", o)
    pdfSerializeWrite(descN, o)
    pdfSerializeWrite(" 0 R /DW 1000 /W [", o)
    for gid, rune in font.usedGlyphs:
      let adv =
        if font.typeface.opentype != nil:
          let idx = min(gid.int, font.typeface.opentype.hmtx.hMetrics.high)
          font.typeface.opentype.hmtx.hMetrics[idx].advanceWidth.float32 * 1000.0 / unitsPerEm
        else:
          1000.0
      pdfSerializeWrite(gid.int, o)
      pdfSerializeWrite(" [", o)
      pdfSerializeWrite(adv, o)
      pdfSerializeWrite("] ", o)
    pdfSerializeWrite("] /CIDToGIDMap /Identity >>\nendobj\n", o)

    offsets.add pdfCurrentPos(o)
    pdfSerializeWrite(descN, o)
    pdfSerializeWrite(" 0 obj\n<< /Type /FontDescriptor /FontName /Ff", o)
    pdfSerializeWrite(j, o)
    pdfSerializeWrite(" /Flags 4 /FontBBox [0 ", o)
    pdfSerializeWrite(descent, o)
    pdfSerializeWrite(" 1000 ", o)
    pdfSerializeWrite(ascent, o)
    pdfSerializeWrite("] /ItalicAngle 0 /Ascent ", o)
    pdfSerializeWrite(ascent, o)
    pdfSerializeWrite(" /Descent ", o)
    pdfSerializeWrite(descent, o)
    pdfSerializeWrite(" /CapHeight ", o)
    pdfSerializeWrite(capHeight, o)
    pdfSerializeWrite(" /StemV 80 /FontFile2 ", o)
    pdfSerializeWrite(fileN, o)
    pdfSerializeWrite(" 0 R >>\nendobj\n", o)

    offsets.add pdfCurrentPos(o)
    pdfSerializeWrite(fileN, o)
    pdfSerializeWrite(" 0 obj\n<< /Length ", o)
    pdfSerializeWrite(fontBytes.len, o)
    pdfSerializeWrite(" /Length1 ", o)
    pdfSerializeWrite(fontBytes.len, o)
    pdfSerializeWrite(" >>\nstream\n", o)
    pdfSerializeWrite(fontBytes, o)
    pdfSerializeWrite("\nendstream\nendobj\n", o)

    var cmapLen = 0
    writeCMap(font, j, cmapLen)
    offsets.add pdfCurrentPos(o)
    pdfSerializeWrite(toUniN, o)
    pdfSerializeWrite(" 0 obj\n<< /Length ", o)
    pdfSerializeWrite(cmapLen, o)
    pdfSerializeWrite(" >>\nstream\n", o)
    writeCMap(font, j, o)
    pdfSerializeWrite("\nendstream\nendobj\n", o)

  let xrefPos = pdfCurrentPos(o)
  let total   = 1 + offsets.len
  pdfSerializeWrite("xref\n0 ", o)
  pdfSerializeWrite(total, o)
  pdfSerializeWrite("\n0000000000 65535 f \n", o)
  for off in offsets:
    pdfSerializeWrite(PdfXrefEntry(off), o)
  pdfSerializeWrite("trailer\n<< /Size ", o)
  pdfSerializeWrite(total, o)
  pdfSerializeWrite(" /Root 1 0 R >>\nstartxref\n", o)
  pdfSerializeWrite(xrefPos, o)
  pdfSerializeWrite("\n%%EOF\n", o)


proc writeToFile*(w: PdfWriter, filename: string) =
  var totalSize = 0
  pdfSerialize(w, totalSize)

  var ctx = MemFileContext(mf: memfiles.open(filename, fmReadWrite, newFileSize = totalSize))
  pdfSerialize(w, ctx)
  ctx.mf.close()
