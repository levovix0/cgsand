import std/[sequtils, math]
import sandbox
import electronics/schemes

type
  Multiplexer* = object
    I*: seq[Node]
    D*: seq[Node]
    O*: Node
    placement: seq[PlacementRule]

proc pack*(r: Multiplexer): Pack = pack(r.I & r.D, @[r.O])


proc multiplexer*(bitCount = 8): Multiplexer =
  template r: untyped = result
  template I: untyped = result.I
  template D: untyped = result.D

  let dLen = bitCount
  let addrBits = max(1, ceil(log2(dLen.float)).int)

  D = (0..<dLen).mapIt(Node("D" & $it))
  I = (0..<addrBits).mapIt(Node("x" & $(it + 1)))
  let Ii = I.mapIt(norN(it))
  let M = (0..<dLen).mapIt(andN(D[it]))

  r.O = Node "Q"
  let On = orN(M.mapIt(Port it))
  On.height = float dLen * 4
  r.O.inputs.add On

  for i in 0..<dLen:
    let n = [Ii, I]
    for bit in 0..<addrBits:
      M[i].inputs.add n[(i shr (addrBits - 1 - bit)) and 1][bit][0]

  let dGap = 1.0
  let iOriginY = dLen.float * (1 + dGap) - dGap
  let iGap = iOriginY / addrBits.float

  r.placement.add Line(origin: point2(0, 0),        nodes: D,  gap: dGap)
  r.placement.add Line(origin: point2(0, iOriginY),  nodes: I,  gap: iGap)
  r.placement.add Line(origin: point2(4, iOriginY - iGap * 0.5), nodes: Ii, gap: iGap)
  r.placement.add buses(originX = 11.5, originY = 0, stepX = -0.5, inputs = D, outputs = M)

  let busColors = [
    (color(1, 0, 0), color(1, 0, 0)),
    (color(0, 1, 0), color(0, 1, 0)),
    (color(0, 0, 1), color(0, 0, 1)),
    (color(1, 1, 0), color(1, 1, 0)),
  ]
  for bit in 0..<addrBits:
    let (c, _) = busColors[bit mod busColors.len]
    let x = 14.0 + bit.float * 2
    r.placement.add bus(point2(x,       0), input = Ii[bit], outputs = M, color = c.darken(0.2).spin(45))
    r.placement.add bus(point2(x + 0.5, 0), input = I[bit],  outputs = M, color = c.desaturate(0.1))

  let mX = 14.0 + addrBits.float * 2 + 4
  r.placement.add Line(origin: point2(mX,       0), nodes: M,     gap: 0)
  r.placement.add Line(origin: point2(mX + 4,   0), nodes: @[On], gap: 0)
  r.placement.add Line(origin: point2(mX + 8,   0), nodes: @[r.O], gap: 0, align: Inputs)



mainModule:
  let r = multiplexer(8)

  placeComponents(r.placement)
  drawComponents()

  var timestamps: seq[PlotTimestamp]
  var i = 0
  for d in 0..2:
    case d
    of 0, 1:
      timestamps.add PlotTimestamp(
        time: i.float,
        changes: (0..<r.D.len).mapIt(setVal(r.D[it], d))
      )
    of 2:
      timestamps.add PlotTimestamp(
        time: i.float,
        changes:
          (0..<(r.D.len div 2)).mapIt(setVal(r.D[it], 0)) &
          ((r.D.len div 2)..<r.D.len).mapIt(setVal(r.D[it], 1))
      )
    else: discard

    for ij in 0..<(1 shl r.I.len):
      timestamps.add PlotTimestamp(
        time: i.float,
        changes: (0..<r.I.len).mapIt(setVal(r.I[it], bitVal(ij, r.I.len - 1 - it)))
      )
      inc i

  draw Plot(
    data: @[r.D, r.I, @[r.O]],
    gap: 1.2,
    groupGap: 3,
    timeScale: 1,
    timestamps: timestamps,
    origin: point2(r.I.len.float * 2 + 30, 0),
  )
