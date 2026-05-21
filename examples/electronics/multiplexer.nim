import std/sequtils
import sandbox
import electronics/schemes


mainModule:
  let D = @[Node "D0", "D1", "D2", "D3", "D4", "D5", "D6", "D7"]
  let I = @[Node "x1", "x2", "x3"]
  let Ii = I.mapIt(norN(it))
  let M = (0..<D.len).mapIt(andN(D[it]))

  let O = @[Node "y"]
  let On = @[orN(M.mapIt(Port it))]
  On[0].height = float D.len*4
  for i in 0..<O.len: O[i].inputs.add On[i][0]

  for i in 0..<8:
    let n = [Ii, I]
    M[i].inputs.add n[(i shr 2) and 1][0][0]
    M[i].inputs.add n[(i shr 1) and 1][1][0]
    M[i].inputs.add n[i and 1][2][0]

  var rules: seq[PlacementRule]
  rules.add Line(origin: point2(0, 0),    nodes: D,  gap: 1)
  rules.add Line(origin: point2(0, 20),   nodes: I,  gap: 5)
  rules.add Line(origin: point2(4, 17.5), nodes: Ii, gap: 4)
  rules.add buses(originX = 11.5, originY = 0, stepX = -0.5, inputs = D, outputs = M)
  rules.add bus(point2(14, 0),   input = Ii[0], outputs = M, color = color(1, 0, 0).darken(0.2).spin(45))
  rules.add bus(point2(14.5, 0), input = I[0],  outputs = M, color = color(1, 0, 0).desaturate(0.1))
  rules.add bus(point2(16, 0),   input = Ii[1], outputs = M, color = color(0, 1, 0).darken(0.2).spin(45))
  rules.add bus(point2(16.5, 0), input = I[1],  outputs = M, color = color(0, 1, 0).desaturate(0.1))
  rules.add bus(point2(18, 0),   input = Ii[2], outputs = M, color = color(0, 0, 1).darken(0.2).spin(45))
  rules.add bus(point2(18.5, 0), input = I[2],  outputs = M, color = color(0, 0, 1).desaturate(0.1))
  rules.add Line(origin: point2(22, 0), nodes: M,  gap: 0)
  rules.add Line(origin: point2(26, 0), nodes: On, gap: 0)
  rules.add Line(origin: point2(30, 0), nodes: O,  gap: 0, align: Inputs)

  placeComponents(rules)
  drawComponents()


  var timestamps: seq[PlotTimestamp]
  var i = 0
  for d in 0..2:
    case d
    of 0, 1:
      timestamps.add PlotTimestamp(
        time: i.float,
        changes: (0..<D.len).mapIt(setVal(D[it], d))
      )
    of 2:
      timestamps.add PlotTimestamp(
        time: i.float,
        changes:
          (0..<(D.len div 2)).mapIt(setVal(D[it], 0)) &
          ((D.len div 2)..<D.len).mapIt(setVal(D[it], 1))
      )
    else: discard

    for ij in 0..<8:
      timestamps.add PlotTimestamp(
        time: i.float,
        changes: @[
          setVal(I[0], bitVal(ij, 2)),
          setVal(I[1], bitVal(ij, 1)),
          setVal(I[2], bitVal(ij, 0)),
        ]
      )
      inc i

  draw Plot(
    data: @[D, I, O],
    gap: 1.2,
    groupGap: 3,
    timeScale: 1,
    timestamps: timestamps,
    origin: point2(34, 0),
  )
