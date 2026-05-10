import sandbox
import electronics/schemes

addDefaultElectronicsGlobals()


let I = @[Node "!R", "!S"]
let M = @[Node "", Node ""]
let O = @[Node "Q", "!Q"]

for i in 0..<O.len: O[i].inputs.add M[i]

let T = @[nandN(I[0], M[1]), nandN(M[0], I[1])]
for i in 0..<O.len: M[i].inputs.add T[i]


let R {.used.} = I[0]
let S {.used.} = I[1]
let Q {.used.} = O[0]


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
  PlotTimestamp(time: 0, changes: @[setVal(S, 1), setVal(R, 1)]),
  PlotTimestamp(time: 1),
  PlotTimestamp(time: 2, changes: @[setVal(S, 0), setVal(R, 1)]),
  PlotTimestamp(time: 3),
  PlotTimestamp(time: 4, changes: @[setVal(S, 1), setVal(R, 1)]),
  PlotTimestamp(time: 5),
]

draw Plot(
  data: @[I, O],
  gap: 0.5,
  groupGap: 0.5,
  timeScale: 1,
  timestamps: timestamps,
  origin: point2(10, 0),
)

