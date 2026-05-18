import std/[strutils, memfiles]
import pkg/[vmath, chroma]


const mmToPt* = 72.0 / 25.4


type
  PdfPage* = object
    widthPt*, heightPt*: float32
    content*: string
    alphas: seq[float32]
    lastR, lastG, lastB, lastA: float32
    lastLW: float32
    colorSet, lwSet: bool

  PdfWriter* = object
    pages*: seq[PdfPage]

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

proc setStrokeColor*(p: var PdfPage; color: Color) =
  if not p.colorSet or p.lastR != color.r or p.lastG != color.g or p.lastB != color.b:
    p.content.add pdfNum(color.r) & " " & pdfNum(color.g) & " " & pdfNum(color.b) & " RG\n"
    p.lastR = color.r; p.lastG = color.g; p.lastB = color.b
    p.colorSet = true
  
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


proc pdfCurrentPos*(o: string): int = o.len
proc pdfSerializeWrite*(s: string,  o: var string)  = o.add s
proc pdfSerializeWrite*(n: int,     o: var string)  = o.add $n
proc pdfSerializeWrite*(f: float32, o: var string)  = o.add pdfNum(f)

proc pdfCurrentPos*(o: int): int = o
proc pdfSerializeWrite*(s: string,  o: var int) = o += s.len
proc pdfSerializeWrite*(n: int,     o: var int) = o += ($n).len
proc pdfSerializeWrite*(f: float32, o: var int) = o += pdfNum(f).len

proc pdfCurrentPos*(o: MemFileContext): int = o.pos
proc pdfSerializeWrite*(s: string, o: var MemFileContext) =
  if s.len > 0:
    copyMem(cast[pointer](cast[int](o.mf.mem) + o.pos), unsafeAddr s[0], s.len)
  o.pos += s.len
proc pdfSerializeWrite*(n: int,     o: var MemFileContext) = pdfSerializeWrite($n, o)
proc pdfSerializeWrite*(f: float32, o: var MemFileContext) = pdfSerializeWrite(pdfNum(f), o)

proc pdfSerializeWrite*(e: PdfXrefEntry, o: var string) =
  o.add ($e.int).align(10, '0') & " 00000 n \n"
proc pdfSerializeWrite*(e: PdfXrefEntry, o: var int) = o += 20
proc pdfSerializeWrite*(e: PdfXrefEntry, o: var MemFileContext) =
  pdfSerializeWrite(($e.int).align(10, '0') & " 00000 n \n", o)


proc pdfSerialize*[T](w: PdfWriter, o: var T) =
  var offsets: seq[int]

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

    var resources = ""
    if page.alphas.len > 0:
      resources = " /Resources << /ExtGState <<"
      for j, a in page.alphas:
        resources.add " /GS" & $j & " << /Type /ExtGState /CA " & pdfNum(a) & " >>"
      resources.add " >> >>"

    offsets.add pdfCurrentPos(o)
    pdfSerializeWrite($pageN & " 0 obj\n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 ", o)
    pdfSerializeWrite(page.widthPt, o)
    pdfSerializeWrite(" ", o)
    pdfSerializeWrite(page.heightPt, o)
    pdfSerializeWrite("] /Contents " & $contentN & " 0 R" & resources & " >>\nendobj\n", o)

    offsets.add pdfCurrentPos(o)
    pdfSerializeWrite($contentN & " 0 obj\n<< /Length ", o)
    pdfSerializeWrite(page.content.len, o)
    pdfSerializeWrite(" >>\nstream\n", o)
    pdfSerializeWrite(page.content, o)
    pdfSerializeWrite("\nendstream\nendobj\n", o)

  let xrefPos = pdfCurrentPos(o)
  let total   = 1 + offsets.len
  pdfSerializeWrite("xref\n0 " & $total & "\n", o)
  pdfSerializeWrite("0000000000 65535 f \n", o)
  for off in offsets:
    pdfSerializeWrite(PdfXrefEntry(off), o)
  pdfSerializeWrite("trailer\n<< /Size " & $total & " /Root 1 0 R >>\nstartxref\n", o)
  pdfSerializeWrite(xrefPos, o)
  pdfSerializeWrite("\n%%EOF\n", o)


proc writeToFile*(w: PdfWriter, filename: string) =
  var totalSize = 0
  pdfSerialize(w, totalSize)

  var ctx = MemFileContext(mf: memfiles.open(filename, fmReadWrite, newFileSize = totalSize))
  pdfSerialize(w, ctx)
  ctx.mf.close()
