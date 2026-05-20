import std/sequtils
import sandbox
import electronics/schemes


let D = @[Node "D0", "D1", "D2", "D3", "D4", "D5", "D6", "D7"]

let I = @[Node "x1", "x2", "x3"]
let Ii = I.mapIt(norN(it))

let M = (0..<D.len).mapIt(andN(D[it]))

let O = @[Node "y"]
let On = @[orN(M.mapIt(Port it))]
On[0].height = float D.len*4
for i in 0..<O.len: O[i].inputs.add (On[i], 0)


block:
  var i = 0
  for x3 in 0..1:
    for x2 in 0..1:
      for x1 in 0..1:
        let n = [Ii, I]
        M[i].inputs.add { n[x3][0]:0, n[x2][1]:0, n[x1][2]:0 }.mapIt(Port it)
        inc i

let lines = placementRules(
  Line(
    origin: point2(0, 0),
    nodes: D,
    gap: 1,
  ),
  Line(
    origin: point2(0, 20),
    nodes: I,
    gap: 5,
  ),
  Line(
    origin: point2(4, 17.5),
    nodes: Ii,
    gap: 4,
  ),
  bus(point2(8, 0),    input = D[7],  outputs = M, color = color(0, 0, 0)),
  bus(point2(8.5, 0),  input = D[6],  outputs = M, color = color(0, 0, 0)),
  bus(point2(9, 0),    input = D[5],  outputs = M, color = color(0, 0, 0)),
  bus(point2(9.5, 0),  input = D[4],  outputs = M, color = color(0, 0, 0)),
  bus(point2(10, 0),   input = D[3],  outputs = M, color = color(0, 0, 0)),
  bus(point2(10.5, 0), input = D[2],  outputs = M, color = color(0, 0, 0)),
  bus(point2(11, 0),   input = D[1],  outputs = M, color = color(0, 0, 0)),
  bus(point2(11.5, 0), input = D[0],  outputs = M, color = color(0, 0, 0)),

  bus(point2(14, 0),   input = Ii[0], outputs = M, color = color(1, 0, 0).darken(0.2).spin(45)),
  bus(point2(14.5, 0), input = I[0],  outputs = M, color = color(1, 0, 0).desaturate(0.1)),

  bus(point2(16, 0),   input = Ii[1], outputs = M, color = color(0, 1, 0).darken(0.2).spin(45)),
  bus(point2(16.5, 0), input = I[1],  outputs = M, color = color(0, 1, 0).desaturate(0.1)),

  bus(point2(18, 0),   input = Ii[2], outputs = M, color = color(0, 0, 1).darken(0.2).spin(45)),
  bus(point2(18.5, 0), input = I[2],  outputs = M, color = color(0, 0, 1).desaturate(0.1)),
  Line(
    origin: point2(22, 0),
    nodes: M,
    gap: 0,
  ),
  Line(
    origin: point2(26, 0),
    nodes: On,
    gap: 0,
  ),
  Line(
    origin: point2(30, 0),
    nodes: O,
    align: Inputs,
    gap: 0,
  ),
)



placeComponents(lines)
drawComponents()



var timestamps: seq[PlotTimestamp]
block:
  var i = 0
  for d in 0..2:
    case d
    of 0, 1:
      timestamps.add PlotTimestamp(
        time: i.float,
        changes: (0..<D.len).mapIt(setVal(D[it], Value(power: d.float)))
      )
    of 2:
      timestamps.add PlotTimestamp(
        time: i.float,
        changes: (
          (0..<(D.len div 2)).mapIt(setVal(D[it], Value(power: 0))) &
          ((D.len div 2)..<D.len).mapIt(setVal(D[it], Value(power: 1)))
        )
      )
    else: discard

    for x3 in 0..1:
      for x2 in 0..1:
        for x1 in 0..1:
          timestamps.add PlotTimestamp(
            time: i.float,
            changes: @[
              setVal(I[0], Value(power: x3.float)),
              setVal(I[1], Value(power: x2.float)),
              setVal(I[2], Value(power: x1.float)),
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


