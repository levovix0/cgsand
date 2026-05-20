import std/sequtils
import sandbox
import electronics/schemes


let I = @[Node "x0", "x1", "x2", "x3", "x4", "x5", "x6", "x7", "x8", "x9"]
let O = @[Node "y4", "y3", "y2", "y1"]

let Ou = @[
  orN((0..9).toSeq.filterIt(((it div 8) mod 2) == 1).mapIt(Port I[it])),
  orN((0..9).toSeq.filterIt(((it div 4) mod 2) == 1).mapIt(Port I[it])),
  orN((0..9).toSeq.filterIt(((it div 2) mod 2) == 1).mapIt(Port I[it])),
  orN((0..9).toSeq.filterIt(((it div 1) mod 2) == 1).mapIt(Port I[it])),
]

for i in 0..<O.len:
  O[i].inputs.add (Ou[i], 0)




let lines = placementRules(
  Line(
    origin: point2(0, 0),
    nodes: I,
    gap: 1,
  ),
  bus(point2(4, 0),  input = I[0], outputs = Ou, color = color(0, 0, 0)),
  bus(point2(5, 0),  input = I[1], outputs = Ou, color = color(0, 0, 0)),
  bus(point2(6, 0),  input = I[2], outputs = Ou, color = color(0, 0, 0)),
  bus(point2(7, 0),  input = I[3], outputs = Ou, color = color(0, 0, 0)),
  bus(point2(8, 0),  input = I[4], outputs = Ou, color = color(0, 0, 0)),
  bus(point2(9, 0),  input = I[5], outputs = Ou, color = color(0, 0, 0)),
  bus(point2(10, 0), input = I[6], outputs = Ou, color = color(0, 0, 0)),
  bus(point2(11, 0), input = I[7], outputs = Ou, color = color(0, 0, 0)),
  bus(point2(12, 0), input = I[8], outputs = Ou, color = color(0, 0, 0)),
  bus(point2(13, 0), input = I[9], outputs = Ou, color = color(0, 0, 0)),
  Line(
    origin: point2(14, -10),
    nodes: Ou,
    gap: 0,
  ),
  Line(
    origin: point2(17, 0),
    nodes: O,
    align: Inputs,
    gap: 0,
  ),
)



placeComponents(lines)
drawComponents()



var timestamps: seq[PlotTimestamp]
block:
  for i in 0..<I.len:
    var changes = @[setVal(I[i], Value(power: 1))]
    if i != 0:
      changes.add setVal(I[i - 1], Value(power: 0))
    timestamps.add PlotTimestamp(
      time: i.float,
      changes: changes,
    )

draw Plot(
  data: @[I, O],
  gap: 1,
  groupGap: 1,
  timeScale: 2,
  timestamps: timestamps,
  origin: point2(20, -10),
)


