import std/[strutils, unicode]
import sandbox, geom2d, text
import annotations/[dimensions]


type
  RectTable* = object
    size: Vec2
    cols, rows: int

  KarnaughRect* = object
    x*, y*: Slice[int]

  KarnaughGroup* = object
    terms*: seq[string]
    rect*: KarnaughRect


proc varValues(y, x, nVars: int): seq[int] =
  result = newSeq[int](nVars)
  if nVars == 3:
    result[0] = y
    result[1] = x div 2
    result[2] = (x mod 2) xor (x div 2)
  elif nVars >= 4:
    result[0] = y div 2
    result[1] = (y mod 2) xor (y div 2)
    result[2] = x div 2
    result[3] = (x mod 2) xor (x div 2)


proc findGroups*(data: seq[seq[int]], variables: seq[string], targetVal: int): seq[KarnaughGroup] =
  let rows = data.len
  let cols = if rows > 0: data[0].len else: 0
  let nVars = variables.len

  type ImplicantInfo = tuple[y0, x0, h, w: int]
  var implicants: seq[ImplicantInfo] = @[]

  var h = 1
  while h <= rows:
    var w = 1
    while w <= cols:
      let y0Max = if h == rows: 0 else: rows - 1
      let x0Max = if w == cols: 0 else: cols - 1
      for y0 in 0..y0Max:
        for x0 in 0..x0Max:
          var valid = true
          var hasTarget = false
          block checkRect:
            for dy in 0..<h:
              for dx in 0..<w:
                let cy = (y0 + dy) mod rows
                let cx = (x0 + dx) mod cols
                let v = data[cy][cx]
                if v != targetVal and v != 2:
                  valid = false
                  break checkRect
                if v == targetVal:
                  hasTarget = true
          if valid and hasTarget:
            implicants.add (y0, x0, h, w)
      w *= 2
    h *= 2

  proc cellsOf(imp: ImplicantInfo): set[uint8] =
    for dy in 0..<imp.h:
      for dx in 0..<imp.w:
        result.incl uint8((imp.y0 + dy) mod rows * cols + (imp.x0 + dx) mod cols)

  for i in 0..<implicants.len:
    let aCells = cellsOf(implicants[i])
    var isPrime = true
    for j in 0..<implicants.len:
      if i == j: continue
      if aCells < cellsOf(implicants[j]):
        isPrime = false
        break
    if not isPrime: continue

    let imp = implicants[i]

    let xRange =
      if imp.x0 + imp.w <= cols: imp.x0..(imp.x0 + imp.w - 1)
      else: (imp.x0 - cols)..(imp.x0 - cols + imp.w - 1)
    let yRange =
      if imp.y0 + imp.h <= rows: imp.y0..(imp.y0 + imp.h - 1)
      else: (imp.y0 - rows)..(imp.y0 - rows + imp.h - 1)

    var vMins = newSeq[int](nVars)
    var vMaxs = newSeq[int](nVars)
    for vi in 0..<nVars:
      vMins[vi] = 2
      vMaxs[vi] = -1

    for dy in 0..<imp.h:
      for dx in 0..<imp.w:
        let vals = varValues((imp.y0 + dy) mod rows, (imp.x0 + dx) mod cols, nVars)
        for vi in 0..<nVars:
          vMins[vi] = min(vMins[vi], vals[vi])
          vMaxs[vi] = max(vMaxs[vi], vals[vi])

    var terms: seq[string] = @[]
    for vi in 0..<nVars:
      if vMins[vi] == vMaxs[vi]:
        if targetVal == 1:
          if vMins[vi] == 1: terms.add variables[vi]
          else: terms.add "!" & variables[vi]
        else:
          if vMins[vi] == 0: terms.add variables[vi]
          else: terms.add "!" & variables[vi]

    result.add KarnaughGroup(terms: terms, rect: KarnaughRect(x: xRange, y: yRange))


proc findSdnf*(data: seq[seq[int]], variables: seq[string]): seq[KarnaughGroup] =
  findGroups(data, variables, 1)

proc findSknf*(data: seq[seq[int]], variables: seq[string]): seq[KarnaughGroup] =
  findGroups(data, variables, 0)


proc drawNormalFormImpl(
  docPtr: ptr World, groups: seq[KarnaughGroup], origin: Point2, font: Font, isSdnf: bool
) =
  var text = ""
  var overlines: seq[tuple[a, b: int]] = @[]

  proc addLit(term: string) =
    let neg = term.startsWith("!")
    let name = if neg: term[1..^1] else: term
    if neg:
      let a = text.runeLen
      text.add name
      overlines.add (a, text.runeLen - 1)
    else:
      text.add name

  if isSdnf:
    for gi, group in groups:
      if gi > 0: text.add " | "
      for li, lit in group.terms:
        if li > 0: text.add " "
        addLit(lit)
  else:
    for group in groups:
      text.add "("
      for li, lit in group.terms:
        if li > 0: text.add " | "
        addLit(lit)
      text.add ")"

  docPtr[].add Text text:
    Position2 origin
    PositionAtLeft
    FontSize float64(font.size)

  if overlines.len == 0:
    return

  # Scale up to avoid integer-pixel rounding at small font sizes in pixie
  const sf = 100.0f32
  let arr = font.typeface.withSize(float64(font.size * sf)).typeset(text)
  let sels = arr.selectionRects
  if sels.len == 0:
    return

  # Tight glyph bounds — renderer uses these for vertical centering (PositionAtLeft, exactBoundaries)
  # world_y of pixie py = origin.y + (boxY + boxH/2 - py) / sf
  var boxX = 0.0f32
  var boxY = 0.0f32
  var boxH = font.size * sf
  try:
    let box = arr.computeBounds()
    boxX = box.x
    boxY = box.y
    boxH = box.h
  except:
    discard

  let sel0 = sels[0]
  let oy = float64(boxY + boxH * 0.5f32 - sel0.y) / float64(sf) + float64(font.size) * 0.05

  for (a, b) in overlines:
    if b < sels.len:
      let x0 = float64(sels[a].x - boxX) / float64(sf)
      let x1 = float64(sels[b].x + sels[b].w - boxX) / float64(sf)
      docPtr[].add lineSection(origin + vec2(x0, oy), origin + vec2(x1, oy))


proc drawSdnf*(doc: var World, groups: seq[KarnaughGroup], origin: Point2, typeface = font_default, fontSize: float = 1.0) =
  drawNormalFormImpl(doc.addr, groups, origin, typeface.withSize(fontSize), true)

proc drawSknf*(doc: var World, groups: seq[KarnaughGroup], origin: Point2, typeface = font_default, fontSize: float = 1.0) =
  drawNormalFormImpl(doc.addr, groups, origin, typeface.withSize(fontSize), false)


proc drawKarnaughGroups*(
  doc: var World,
  groups: seq[KarnaughGroup],
  variables: seq[string],
  origin: Point2 = point2(),
  cellSize: float = 2.0,
  thickness: Thickness = 0.09,
) =
  let tableRows = if variables.len >= 4: 4 else: 2
  let tableW = 4.0 * cellSize
  let tableH = tableRows.float * cellSize
  let margin = -cellSize * 0.05

  const palette = [
    color(0.86'f32, 0.20'f32, 0.18'f32),
    color(0.16'f32, 0.50'f32, 0.73'f32),
    color(0.18'f32, 0.60'f32, 0.18'f32),
    color(0.80'f32, 0.50'f32, 0.00'f32),
    color(0.60'f32, 0.10'f32, 0.80'f32),
    color(0.00'f32, 0.60'f32, 0.60'f32),
  ]

  for gi, group in groups:
    let col = palette[gi mod palette.len]
    let xa = group.rect.x.a
    let xb = group.rect.x.b
    let ya = group.rect.y.a
    let yb = group.rect.y.b

    let cy = origin.y - (ya + yb + 1).float * cellSize / 2
    let ry = (yb - ya + 1).float * cellSize / 2 + margin
    let cx = origin.x + (xa + xb + 1).float * cellSize / 2
    let rx = (xb - xa + 1).float * cellSize / 2 + margin

    let wrapX = xa < 0
    let wrapY = ya < 0

    template addArc(centerX, centerY, sizeX, sizeY, sa, ea: float) =
      doc.add EllipseArc(
        center: point2(centerX, centerY),
        size: vec2(sizeX, sizeY),
        startAngle: sa,
        endAngle: ea,
      ), col, thickness

    if not wrapX and not wrapY:
      addArc(cx, cy, rx * 2, ry * 2, 0, 0)

    elif wrapX and not wrapY:
      let rxRight = (-xa).float * cellSize + margin
      let rxLeft = (xb + 1).float * cellSize + margin
      addArc(origin.x + tableW, cy, rxRight * 2, ry * 2, Pi / 2, Pi * 3 / 2)
      addArc(origin.x, cy, rxLeft * 2, ry * 2, -Pi / 2, Pi / 2)

    elif not wrapX and wrapY:
      let ryBottom = (-ya).float * cellSize + margin
      let ryTop = (yb + 1).float * cellSize + margin
      addArc(cx, origin.y - tableH, rx * 2, ryBottom * 2, 0, Pi)
      addArc(cx, origin.y, rx * 2, ryTop * 2, Pi, 2 * Pi)

    else:
      let rxRight = (-xa).float * cellSize + margin
      let rxLeft = (xb + 1).float * cellSize + margin
      let ryBottom = (-ya).float * cellSize + margin
      let ryTop = (yb + 1).float * cellSize + margin
      addArc(origin.x + tableW, origin.y - tableH, rxRight * 2, ryBottom * 2, Pi / 2, Pi)
      addArc(origin.x, origin.y - tableH, rxLeft * 2, ryBottom * 2, 0, Pi / 2)
      addArc(origin.x + tableW, origin.y, rxRight * 2, ryTop * 2, Pi, Pi * 3 / 2)
      addArc(origin.x, origin.y, rxLeft * 2, ryTop * 2, Pi * 3 / 2, 2 * Pi)


proc drawCarnotMap*(doc: var World, variables: seq[string], data: seq[seq[int]], cellSize: float = 2.0) =
  let tableRows = if variables.len >= 4: 4 else: 2
  let tableSize = vec2(4.0 * cellSize, float(tableRows) * cellSize)
  let doc = doc.addr  # cannot capture var params
  # todo: make World a ref? or at least make doc a ref World

  doc[].add RectTable(size: tableSize, cols: 4, rows: tableRows):
    Position2 point2()

  doc[].forEach (r: RectTable, pos: Position2||point2()):
    doc[].add lineSection(pos, pos + vec2(r.size.x, 0))
    doc[].add lineSection(pos + vec2(r.size.x, 0), pos + vec2(r.size.x, -r.size.y))
    doc[].add lineSection(pos + vec2(r.size.x, -r.size.y), pos + vec2(0, -r.size.y))
    doc[].add lineSection(pos + vec2(0, -r.size.y), pos)

    for i in 1..r.rows:
      let y = (i / r.rows) * r.size.y
      doc[].add lineSection(pos + vec2(0, -y), pos + vec2(r.size.x, -y))

    for i in 1..r.cols:
      let x = (i / r.cols) * r.size.x
      doc[].add lineSection(pos + vec2(x, 0), pos + vec2(x, -r.size.y))

    let cs = r.size.x / float(r.cols)
    let bH = cs * 0.125
    let bW = bH
    let sz = vec2(r.size.x, -(r.size.y))

    proc drawLabel(name: string, labelPos: Point2, anchor: PositionAt) =
      var name = name
      if name.startsWith("!"):
        let v = case anchor
          of PositionAtBottom: vec2(0, 1 - 0.1)
          of PositionAtTop:    vec2(0, 0.1)
          of PositionAtRight:  vec2(-0.3, 0.5)
          of PositionAtLeft:   vec2(0.3, 0.5)
          else: vec2()
        doc[].add lineSection(labelPos + v - vec2(0.3, 0), labelPos + v + vec2(0.3, 0))
      name.removePrefix("!")
      doc[].add Text name:
        Position2 labelPos
        anchor

    if variables.len == 3:
      doc[].add FigureBracket(a: pos + vec2(0, 0) * sz, b: pos + vec2(0.5, 0) * sz, h: vec2(0, bH), power: 2)
      doc[].add FigureBracket(a: pos + vec2(0.5, 0) * sz, b: pos + vec2(1, 0) * sz, h: vec2(0, bH), power: 2)
      doc[].add FigureBracket(a: pos + vec2(0.25, 1) * sz, b: pos + vec2(0.75, 1) * sz, h: vec2(0, -bH), power: 2)
      drawLabel "!" & variables[0], pos + vec2(0, 1/4) * sz + vec2(-0.2, 0),      PositionAtRight
      drawLabel variables[0],       pos + vec2(0, 3/4) * sz + vec2(-0.2, 0),      PositionAtRight
      drawLabel "!" & variables[1], pos + vec2(0.25, 0) * sz + vec2(0, bH+0.1),   PositionAtBottom
      drawLabel variables[1],       pos + vec2(0.75, 0) * sz + vec2(0, bH+0.1),   PositionAtBottom
      drawLabel "!" & variables[2], pos + vec2(1/8, 1) * sz + vec2(0, -(bH+0.1)), PositionAtTop
      drawLabel "!" & variables[2], pos + vec2(7/8, 1) * sz + vec2(0, -(bH+0.1)), PositionAtTop
      drawLabel variables[2],       pos + vec2(0.5, 1) * sz + vec2(0, -(bH+0.1)), PositionAtTop

    elif variables.len >= 4:
      doc[].add FigureBracket(a: pos + vec2(0, 0) * sz,    b: pos + vec2(0.5, 0) * sz,    h: vec2(0, bH),   power: 2)
      doc[].add FigureBracket(a: pos + vec2(0.5, 0) * sz,  b: pos + vec2(1, 0) * sz,      h: vec2(0, bH),   power: 2)
      doc[].add FigureBracket(a: pos + vec2(0.25, 1) * sz, b: pos + vec2(0.75, 1) * sz,   h: vec2(0, -bH),  power: 2)
      doc[].add FigureBracket(a: pos + vec2(0, 0) * sz,    b: pos + vec2(0, 0.5) * sz,    h: vec2(-bW, 0),  power: 2)
      doc[].add FigureBracket(a: pos + vec2(0, 0.5) * sz,  b: pos + vec2(0, 1) * sz,      h: vec2(-bW, 0),  power: 2)
      doc[].add FigureBracket(a: pos + vec2(1, 0.25) * sz, b: pos + vec2(1, 0.75) * sz,   h: vec2(bW, 0),   power: 2)
      drawLabel "!" & variables[2], pos + vec2(0.25, 0) * sz + vec2(0, bH+0.1),     PositionAtBottom
      drawLabel variables[2],       pos + vec2(0.75, 0) * sz + vec2(0, bH+0.1),     PositionAtBottom
      drawLabel "!" & variables[3], pos + vec2(1/8, 1) * sz + vec2(0, -(bH+0.1)),   PositionAtTop
      drawLabel "!" & variables[3], pos + vec2(7/8, 1) * sz + vec2(0, -(bH+0.1)),   PositionAtTop
      drawLabel variables[3],       pos + vec2(0.5, 1) * sz + vec2(0, -(bH+0.1)),   PositionAtTop
      drawLabel "!" & variables[0], pos + vec2(0, 1/4) * sz + vec2(-(bW+0.2), 0),   PositionAtRight
      drawLabel variables[0],       pos + vec2(0, 3/4) * sz + vec2(-(bW+0.2), 0),   PositionAtRight
      drawLabel "!" & variables[1], pos + vec2(1, 1/8) * sz + vec2(bW+0.2, 0),      PositionAtLeft
      drawLabel "!" & variables[1], pos + vec2(1, 7/8) * sz + vec2(bW+0.2, 0),      PositionAtLeft
      drawLabel variables[1],       pos + vec2(1, 1/2) * sz + vec2(bW+0.2, 0),      PositionAtLeft

    let cellHalfW = r.size.x / float(r.cols) / 2 - 0.1
    let cellHalfH = r.size.y / float(r.rows) / 2 - 0.1
    for x in 0..<r.cols:
      for y in 0..<r.rows:
        let d = data[y][x]
        let p = pos + vec2(((x*2+1) / (r.cols*2)) * r.size.x, ((y*2+1) / (r.rows*2)) * -r.size.y)
        doc[].add Text (if d == 2: "-" else: $d):
          Position2 p
          PositionAtCenter
        let mintermsText =
          if variables.len >= 4:
            $(y div 2) & $(((y mod 2).bool xor (y div 2).bool).int) & $(x div 2) & $(((x mod 2).bool xor (x div 2).bool).int)
          else:
            $y & $(x div 2) & $(((x mod 2).bool xor (x div 2).bool).int)
        doc[].add Text mintermsText:
          Position2 p + vec2(cellHalfW, -cellHalfH)
          PositionAtBottomRight
          FontSize 0.4

  doc[].drawFigureBrackets()


mainModule:
  doc.add CanvasSettings(autoSize: true, margin: vec2(1)):
    Background color(1, 1, 1)
    Foreground color(0, 0, 0)
    FontSize 1
    AxisYUp

  let variables = @["x", "y", "z"]
  let data = @[
    @[0, 2, 1, 0],
    @[1, 0, 0, 0],
    @[1, 0, 0, 0],
    @[0, 0, 0, 1],
  ]

  doc.drawCarnotMap(variables, data)

  let sdnf = findSdnf(data, variables)
  doc.drawKarnaughGroups(sdnf, variables)
  doc.drawSdnf(sdnf, point2(0, 2.5))

  # let sknf = findSknf(data, variables)
  # doc.drawKarnaughGroups(sknf, variables)
  # doc.drawSknf(sknf, point2(0, 4))
