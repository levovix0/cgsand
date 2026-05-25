import sandbox
import electronics/schemes
import ./trigger_ms


type
  TTrigger* = object
    I*: seq[Node]
    O*: seq[Node]
    ms*: MsTrigger
    msN*: Node
    placement*: seq[PlacementRule]


proc T*(t: TTrigger): var Node = t.I.addr[][0]
proc C*(t: TTrigger): var Node = t.I.addr[][1]
proc Q*(t: TTrigger): var Node = t.O.addr[][0]
proc nQ*(t: TTrigger): var Node = t.O.addr[][1]


proc tTrigger*: TTrigger =
  result.I = @[Node "T", Node "C"]
  result.O = @[Node "Q", Node "!Q"]

  result.ms = msTrigger()
  result.msN = result.ms.msPack.packN("MS")

  # S = T AND !Q, R = T AND Q
  let S_in = andN(result.T, result.msN[1])
  let R_in = andN(result.T, result.msN[0])

  result.msN.inputs.add S_in
  result.msN.inputs.add result.C
  result.msN.inputs.add R_in

  for i in 0..<result.O.len:
    result.O[i].inputs.add result.msN[i]

  result.placement = placementRules(
    Line(origin: point2(0, 0),  nodes: result.I,            align: Outputs),
    bus(point2(2, 0), result.T, @[S_in, R_in]),
    Line(origin: point2(4, 0),  nodes: @[S_in, R_in],       gap: 2),
    Line(origin: point2(8, 0),  nodes: @[result.msN]),
    Line(origin: point2(20, 0), nodes: result.O,             gap: 2, align: Inputs),
    bus(@[point2(18, 1.5), point2(18, 7), point2(3, 7)],    input = result.msN[0], outputs = @[R_in]),
    bus(@[point2(16, 1.5+3), point2(16, -1), point2(3, -1)], input = result.msN[1], outputs = @[S_in]),
  )


proc startup*(t: TTrigger, v: Value = 0): seq[ValChange] =
  @[
    setVal(t.T, 0), setVal(t.C, 0),
    setVal(t.ms.t1.T[0], v), setVal(t.ms.t1.T[1], not v),
    setVal(t.ms.t2.T[0], v), setVal(t.ms.t2.T[1], not v),
  ]



mainModule:
  let r = tTrigger()

  placeComponents(r.placement)
  drawComponents()

  var timestamps = @[
    PlotTimestamp(time: 0,  changes: startup(r)),
    PlotTimestamp(time: 3,  changes: @[setVal(r.T, 1)]),
    PlotTimestamp(time: 6,  changes: @[setVal(r.T, 0)]),
    PlotTimestamp(time: 9,  changes: @[setVal(r.T, 1)]),
    PlotTimestamp(time: 18, changes: @[setVal(r.T, 0)]),
  ]

  for t in 0..6:
    for t2 in 0..<3:
      timestamps.add PlotTimestamp(time: t.float * 3 + t2.float + 0.05)
    timestamps.add PlotTimestamp(time: t.float * 3 + 1, changes: @[setVal(r.C, 1)])
    timestamps.add PlotTimestamp(time: t.float * 3 + 2, changes: @[setVal(r.C, 0)])

  draw Plot(
    data: @[@[r.T, r.C], r.O],
    gap: 0.2,
    groupGap: 0.5,
    timeScale: 1,
    timestamps: timestamps,
    origin: point2(0, 8),
    skipUnchangedAxes: true,
  )
