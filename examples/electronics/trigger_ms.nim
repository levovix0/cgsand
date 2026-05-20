import sandbox
import electronics/schemes
import ./trigger_rs

mainModule: addDefaultElectronicsGlobals()


type
  MsTrigger* = object
    I: seq[Node]
    O: seq[Node]
    t1O: seq[Node]
    t1*, t2*: RsTrigger
    placement: seq[PlacementRule]


proc msPack*(r: MsTrigger): Pack = pack(r.I, r.O)

proc S*(r: MsTrigger): var Node = r.I.addr[][0]
proc C*(r: MsTrigger): var Node = r.I.addr[][1]
proc R*(r: MsTrigger): var Node = r.I.addr[][2]
proc Q*(r: MsTrigger): var Node = r.O.addr[][0]
proc nQ*(r: MsTrigger): var Node = r.O.addr[][1]


proc msTrigger*: MsTrigger =
  template r: untyped = result

  r.I = @[Node "S₁", "C₁", "R₁"]
  r.O = @[Node "Q₂", "!Q₂"]

  let notC = norN(r.C)

  let M1 = @[andN(r.S, r.C), andN(r.C, r.R)]
  r.t1 = rsTrigger()
  let rsN1 = r.t1.pack.packN("T₁")
  for i in 0..<M1.len: rsN1.inputs.add M1[i]

  r.t1O = @[symN("Q" & subscript[1], (rsN1,0)), symN("!Q" & subscript[1], (rsN1,1))]

  let M2 = @[andN(r.t1O[0], notC), andN(notC, r.t1O[1])]
  r.t2 = rsTrigger()
  let rsN2 = r.t2.pack.packN("T₂")
  for i in 0..<M2.len: rsN2.inputs.add M2[i]

  for i in 0..<r.O.len: r.O[i].inputs.add (rsN2, i)

  r.placement = placementRules(
    Line(
      origin: point2(0, 1),
      nodes: r.I,
      align: Outputs,
    ),
    Line(
      origin: point2(5, 5),
      nodes: @[notC],
    ),
    bus(point2(4, 0), r.C, M1),
    Line(
      origin: point2(5, 0),
      nodes: M1,
    ),
    Line(
      origin: point2(9, 0),
      nodes: @[rsN1],
    ),
    Line(
      origin: point2(16, 0),
      nodes: r.t1O,
      align: Inputs,
    ),
    bus(point2(19, 0), notC, M2),
    Line(
      origin: point2(20, 0),
      nodes: M2,
    ),
    Line(
      origin: point2(24, 0),
      nodes: @[rsN2],
    ),
    Line(
      origin: point2(32, 1),
      nodes: r.O,
      align: Inputs,
    ),
  )


proc startup*(r: MsTrigger, v: Value = 0): seq[ValChange] =
  @[
    setVal(r.S, 0), setVal(r.R, 0),
    setVal(r.t1.T[0], v), setVal(r.t1.T[1], not v),
    setVal(r.t2.T[0], v), setVal(r.t2.T[1], not v)
  ]



mainModule:
  let r = msTrigger()


  placeComponents(r.placement)
  drawComponents()


  doc[CanvasSettings].mmScale = 2.5


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
    data: @[@[r.C], @[r.S, r.R], r.t1O, r.O],
    gap: 0.2,
    groupGap: 0.5,
    timeScale: 5.1,
    timestamps: timestamps,
    origin: point2(0, 10),
    skipUnchangedAxes: true,
  )
