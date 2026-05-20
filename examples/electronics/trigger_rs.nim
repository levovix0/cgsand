import sandbox
import electronics/schemes

addDefaultElectronicsGlobals()


type RsTrigger* = tuple[pack: Pack, placement: seq[PlacementRule], T: seq[Node]]


proc rsTrigger*: RsTrigger =
  let In = @[Node "S", "R"]
  let I = @[nandN(In[0], In[0]), nandN(In[1], In[1])]
  let M = @[Node "", Node ""]
  let O = @[Node "Q", "!Q"]

  for i in 0..<O.len: O[i].inputs.add M[i]

  let T = @[nandN(I[0], delayed(M[1])), nandN(delayed(M[0]), I[1])]
  for i in 0..<O.len: M[i].inputs.add T[i]


  let placement = placementRules(
    Line(
      origin: point2(2, 1),
      nodes: I,
      align: Outputs,
    ),
    Line(
      origin: point2(0, 1),
      nodes: In,
      align: Outputs,  # todo: fix order of aligning
    ),
    Line(
      origin: point2(6, 0),
      nodes: T,
      gap: 2,
    ),
    Line(
      origin: point2(8, 1),
      nodes: M,
      align: Inputs,
    ),
    
    bus(@[point2(9, 2), point2(5, 4)], input = M[0], outputs = T),
    bus(@[point2(9, 4), point2(5, 2)], input = M[1], outputs = T),

    Line(
      origin: point2(10, 1),
      nodes: O,
      align: Inputs,
    ),
  )

  return (pack(In, O), placement, T)



mainModule:
  var (n, placement, T) = rsTrigger()

  placeComponents(placement)
  drawComponents()

  doc[CanvasSettings].mmScale = 2.5

  let S {.used.} = n.inputs[0]
  let R {.used.} = n.inputs[1]

  var timestamps = @[
    PlotTimestamp(time: 0, changes: @[setVal(S, 0), setVal(R, 1), setVal(T[0], 0), setVal(T[1], 1)]),
    PlotTimestamp(time: 0.05),
    PlotTimestamp(time: 1, changes: @[setVal(S, 1), setVal(R, 0)]),
    PlotTimestamp(time: 1.05),
    PlotTimestamp(time: 2, changes: @[setVal(S, 0)]),
    PlotTimestamp(time: 2.05),
    PlotTimestamp(time: 3, changes: @[setVal(R, 1), setVal(S, 0)]),
    PlotTimestamp(time: 3.05),
    PlotTimestamp(time: 4, changes: @[setVal(R, 0)]),
    PlotTimestamp(time: 4.05),
  ]

  draw Plot(
    data: @[n.inputs, n.outputs],
    gap: 0.5,
    groupGap: 0.5,
    timeScale: 2,
    timestamps: timestamps,
    origin: point2(13, 0),
  )

