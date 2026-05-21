import std/sequtils
import sandbox
import electronics/schemes


mainModule:
  let I = @[Node "x0", "x1", "x2", "x3", "x4", "x5", "x6", "x7", "x8", "x9"]
  let N = I.mapIt(nandN(it))
  let O = @[Node "y4", "y3", "y2", "y1"]

  let outpNodes = @[
    nandN((0..9).toSeq.filterIt(((it div 8) mod 2) == 1).mapIt(Port N[it])),
    nandN((0..9).toSeq.filterIt(((it div 4) mod 2) == 1).mapIt(Port N[it])),
    nandN((0..9).toSeq.filterIt(((it div 2) mod 2) == 1).mapIt(Port N[it])),
    nandN((0..9).toSeq.filterIt(((it div 1) mod 2) == 1).mapIt(Port N[it])),
  ]

  for i in 0..<O.len:
    O[i].inputs.add outpNodes[i][0]

  var rules: seq[PlacementRule]
  rules.add Line(origin: point2(0, 0),   nodes: I, gap: 1)
  rules.add Line(origin: point2(2, -1),  nodes: N, gap: 0)
  rules.add buses(originX = 4, originY = 0, stepX = 1, inputs = N, outputs = outpNodes)
  rules.add Line(origin: point2(14, -10), nodes: outpNodes, gap: 0)
  rules.add Line(origin: point2(17, 0),   nodes: O, align: Inputs, gap: 0)

  placeComponents(rules)
  drawComponents()


  var timestamps: seq[PlotTimestamp]
  for i in 0..<I.len:
    var changes = @[setVal(I[i], 1)]
    if i != 0:
      changes.add setVal(I[i - 1], 0)
    timestamps.add PlotTimestamp(time: i.float, changes: changes)

  draw Plot(
    data: @[I, O],
    gap: 1,
    groupGap: 1,
    timeScale: 2,
    timestamps: timestamps,
    origin: point2(20, -10),
  )
