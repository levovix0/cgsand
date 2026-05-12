import sandbox
import electronics/schemes
import ./trigger_rcs

# todo: load trigger_rcs as another world
# todo: allow to place multiple World's inside a doc World

when isMainModule: addDefaultElectronicsGlobals()


type
  MsTrigger* = object
    I: seq[Node]
    O: seq[Node]
    t1, t2: RcsTrigger
    placement: seq[PlacementRule]


proc S*(r: MsTrigger): var Node = r.I.addr[][0]
proc C*(r: MsTrigger): var Node = r.I.addr[][1]
proc R*(r: MsTrigger): var Node = r.I.addr[][2]
proc Q*(r: MsTrigger): var Node = r.O.addr[][0]
proc nQ*(r: MsTrigger): var Node = r.O.addr[][1]


proc msTrigger: MsTrigger =
  template r: untyped = result
  r.t1 = rcsTrigger()
  r.t2 = rcsTrigger()
  r.t1.placement.move vec2(4, 0)
  r.t2.placement.move vec2(18, 0)
  r.placement.add r.t1.placement
  r.placement.add r.t2.placement

  r.I = @[Node "S₁", "C₁", "R₁"]
  r.O = @[Node "Q₂", "!Q₂"]

  for i in 0..<r.I.len: r.t1.I[i].inputs.add r.I[i]
  for i in 0..<r.O.len: r.O[i].inputs.add r.t2.O[i]

  r.t2.S.inputs.add r.t1.Q
  r.t2.R.inputs.add r.t1.nQ

  let n = norN(r.C)
  r.t2.C.inputs.add n

  r.t1.Q.name = "Q₁"
  r.t1.nQ.name = "!Q₁"

  for x in r.t1.I.mitems: x.name = ""
  for x in r.t2.I.mitems: x.name = ""
  for x in r.t2.O.mitems: x.name = ""

  r.placement.add placementRules(
    Line(
      origin: point2(0, 1),
      nodes: r.I,
      align: Outputs,
    ),
    bus(point2(3, 0), r.C, @[n]),
    bus(point2(16, 0), n, r.t2.I),
    Line(
      origin: point2(10, 7),
      nodes: @[n],
    ),
    Line(
      origin: point2(32, 0),
      nodes: r.O,
      align: Inputs,
    ),
  )


proc startup*(r: MsTrigger, v: Value = 0): seq[ValChange] =
  startup(r.t1, v) & startup(r.t2, v)



when isMainModule:
  let r = msTrigger()


  placeComponents(r.placement)
  drawComponents()



  var timestamps = @[
    PlotTimestamp(time: 0, changes: startup(r) & @[setVal(r.S, 1), setVal(r.R, 0)]),
    PlotTimestamp(time: 3, changes: @[setVal(r.S, 0), setVal(r.R, 1)]),
  ]

  for t in 0..1:
    for t2 in 0..<3:
      for t3 in 1..<2:
        let t = t.float * 3 + t2.float + t3.float * 0.05
        timestamps.add PlotTimestamp(time: t)
    timestamps.add PlotTimestamp(time: t.float * 3 + 1, changes: @[setVal(r.C, 1)])
    timestamps.add PlotTimestamp(time: t.float * 3 + 2, changes: @[setVal(r.C, 0)])

  draw Plot(
    data: @[@[r.C], @[r.S, r.R], r.t1.O, r.O],
    # todo: remove quantum mechanics
    #       (if r.t1.O is not visible on the Plot, the scheme breaks)
    gap: 0.2,
    groupGap: 0.5,
    timeScale: 5.5,
    timestamps: timestamps,
    origin: point2(0, 10),
    skipUnchangedAxes: true,
  )

