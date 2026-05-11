import sandbox
import electronics/schemes

addDefaultElectronicsGlobals()


let I = @[Node "!S", "!R"]
let M = @[Node "", Node ""]
let O = @[Node "Q", "!Q"]

for i in 0..<O.len: O[i].inputs.add M[i]

let T = @[nandN(I[0], delayed(M[1])), nandN(delayed(M[0]), I[1])]
for i in 0..<O.len: M[i].inputs.add T[i]


let S {.used.} = I[0]
let R {.used.} = I[1]


let lines = placementRules(
  Line(
    origin: point2(0, 1),
    nodes: I,
    gap: 4,
    align: Outputs,
  ),
  Line(
    origin: point2(3, 0),
    nodes: T,
    gap: 2,
  ),
  Line(
    origin: point2(5, 1),
    nodes: M,
    gap: 4,
    align: Inputs,
  ),
  
  bus(@[point2(6, 2), point2(2, 4)], input = M[0], outputs = T),
  bus(@[point2(6, 4), point2(2, 2)], input = M[1], outputs = T),

  Line(
    origin: point2(7, 1),
    nodes: O,
    gap: 4,
    align: Inputs,
  ),
)



placeComponents(lines)
drawComponents()



var timestamps = @[
  PlotTimestamp(time: 0, changes: @[setVal(S, 1), setVal(R, 1), setVal(T[0], 0), setVal(T[1], 1)]),
  PlotTimestamp(time: 0.05),
  PlotTimestamp(time: 1, changes: @[setVal(S, 0)]),
  PlotTimestamp(time: 1.05),
  PlotTimestamp(time: 2, changes: @[setVal(S, 1)]),
  PlotTimestamp(time: 2.05),
  PlotTimestamp(time: 3, changes: @[setVal(R, 0)]),
  PlotTimestamp(time: 3.05),
  PlotTimestamp(time: 4, changes: @[setVal(R, 1)]),
  PlotTimestamp(time: 4.05),
  # PlotTimestamp(time: 5, changes: @[setVal(S, 0), setVal(R, 0)]),
  # PlotTimestamp(time: 5.25),
  # PlotTimestamp(time: 5.5),
  # PlotTimestamp(time: 5.75),
  # PlotTimestamp(time: 6),
]

draw Plot(
  data: @[I, O],
  gap: 0.5,
  groupGap: 0.5,
  timeScale: 2,
  timestamps: timestamps,
  origin: point2(10, 0),
)

