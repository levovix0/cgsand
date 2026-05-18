import std/[strutils, memfiles, importutils, unicode, tables]
import pkg/[vmath, chroma]
import pkg/pixie/fonts
import pkg/pixie/fontformats/opentype

privateAccess(Typeface)


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


proc drawLine*(p: var PdfPage; a, b: Vec2; color: Color; lw: float32) =
  p.setStrokeColor(color)
  p.setLineWidth(lw)
  p.moveTo(a)
  p.lineTo(b)
  p.stroke()


proc drawText*(p: var PdfPage; w: var PdfWriter;
               typeface: Typeface; sizePt: float32;
               color: Color; baselineX, baselineY: float32; text: string) =
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
  p.content.add pdfNum(baselineX) & " " & pdfNum(baselineY) & " Td\n"
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
