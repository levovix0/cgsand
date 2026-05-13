import sandbox
import electronics/schemes
import ./trigger_rs

when isMainModule: addDefaultElectronicsGlobals()

type
  RcsTrigger* = object
    I*: seq[Node]
    O*: seq[Node]
    placement*: seq[PlacementRule]
    rs*: RsTrigger
    rsN*: Node


proc S*(t: RcsTrigger): var Node = t.I.addr[][0]
proc C*(t: RcsTrigger): var Node = t.I.addr[][1]
proc R*(t: RcsTrigger): var Node = t.I.addr[][2]
proc Q*(t: RcsTrigger): var Node = t.O.addr[][0]
proc nQ*(t: RcsTrigger): var Node = t.O.addr[][1]


proc rcsTrigger*: RcsTrigger =
  template S: untyped = result.S
  template C: untyped = result.C
  template R: untyped = result.R
  # template I: untyped = result.I
  template O: untyped = result.O
  result.I = @[Node "S", "C", "R"]
  result.O = @[Node "Q", "!Q"]

  let M = @[andN(S, C), andN(C, R)]

  result.rs = rsTrigger()
  result.rsN = result.rs.pack.packN("T", M[0], M[1])
  for i in 0..<O.len: O[i].inputs.add (result.rsN, i)


  result.placement = placementRules(
    Line(
      origin: point2(0, 2/3),
      nodes: @[S, C, R],
      gap: 0 + 1/3,
    ),
    Line(
      origin: point2(4, 0),
      nodes: M,
    ),
    Line(
      origin: point2(8, 0),
      nodes: @[result.rsN],
    ),
    
    # bus(@[point2(9, 2), point2(5, 4)], input = M[0], outputs = T),
    # bus(@[point2(9, 4), point2(5, 2)], input = M[1], outputs = T),

    Line(
      origin: point2(16, 1),
      nodes: O,
      align: Inputs,
    ),
  )


proc startup*(t: RcsTrigger, v: Value = 0): seq[ValChange] =
  @[setVal(t.S, 0), setVal(t.R, 0), setVal(t.rs.T[0], v), setVal(t.rs.T[1], not v)]



when isMainModule:
  let t = rcsTrigger()


  placeComponents(t.placement)
  drawComponents()



  var timestamps = @[
    PlotTimestamp(time: 0, changes: startup(t) & @[setVal(t.C, 1)]),
    PlotTimestamp(time: 0.05),
    PlotTimestamp(time: 1, changes: @[setVal(t.S, 1)]),
    PlotTimestamp(time: 1.05),
    PlotTimestamp(time: 2, changes: @[setVal(t.S, 0)]),
    PlotTimestamp(time: 2.05),
    PlotTimestamp(time: 3, changes: @[setVal(t.R, 1)]),
    PlotTimestamp(time: 3.05),
    PlotTimestamp(time: 4, changes: @[setVal(t.R, 0)]),
    PlotTimestamp(time: 4.05),
    PlotTimestamp(time: 5.6, changes: @[setVal(t.S, 1)]),
    PlotTimestamp(time: 5.9, changes: @[setVal(t.S, 0)]),
  ]

  for i in 0..6:
    timestamps.add PlotTimestamp(time: i.float, changes: @[setVal(t.C, 1)])
    timestamps.add PlotTimestamp(time: i.float + 0.5, changes: @[setVal(t.C, 0)])

  draw Plot(
    data: @[@[t.S, t.R, t.C], @[t.Q, t.nQ]],
    gap: 0.5,
    groupGap: 0.5,
    timeScale: 2,
    timestamps: timestamps,
    origin: point2(20, 0),
  )

