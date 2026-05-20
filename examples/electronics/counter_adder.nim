import sandbox
import electronics/schemes
import ./trigger_ms

mainModule: addDefaultElectronicsGlobals()


type
  Counter14* = object
    C*: Node
    Q*: seq[Node]
    ms*: seq[MsTrigger]
    msN*: seq[Node]
    reset*: Node
    placement*: seq[PlacementRule]


proc counter14*: Counter14 =
  template r: untyped = result

  r.C = Node "C"

  r.ms = newSeq[MsTrigger](4)
  r.msN = newSeq[Node](4)
  for i in 0..<4:
    r.ms[i] = msTrigger()
    r.msN[i] = r.ms[i].msPack.packN("T" & subscript[i])

  # Auto-reset: detect state 14 = 1110₂ → Q₃·Q₂·Q₁
  r.reset = andN((r.msN[3], 0), (r.msN[2], 0), (r.msN[1], 0))

  # FF0: T=1 → S = !Q₀, R_eff = Q₀ OR reset
  let s0 = symN("!Q" & subscript[0], (r.msN[0], 1))
  let r0 = orN((r.msN[0], 0), r.reset)
  r.msN[0].inputs.add s0
  r.msN[0].inputs.add r.C
  r.msN[0].inputs.add r0

  # FF1: T₁ = Q₀ → S = Q₀·!Q₁, R_eff = Q₀·Q₁ OR reset
  let s1 = andN((r.msN[0], 0), (r.msN[1], 1))
  let r1 = orN(andN((r.msN[0], 0), (r.msN[1], 0)), r.reset)
  r.msN[1].inputs.add s1
  r.msN[1].inputs.add r.C
  r.msN[1].inputs.add r1

  # FF2: T₂ = Q₀·Q₁ → S = Q₀·Q₁·!Q₂, R_eff = Q₀·Q₁·Q₂ OR reset
  let s2 = andN((r.msN[0], 0), (r.msN[1], 0), (r.msN[2], 1))
  let r2 = orN(andN((r.msN[0], 0), (r.msN[1], 0), (r.msN[2], 0)), r.reset)
  r.msN[2].inputs.add s2
  r.msN[2].inputs.add r.C
  r.msN[2].inputs.add r2

  # FF3: T₃ = Q₀·Q₁·Q₂ → S = Q₀·Q₁·Q₂·!Q₃, R_eff = Q₀·Q₁·Q₂·Q₃ OR reset
  let s3 = andN((r.msN[0], 0), (r.msN[1], 0), (r.msN[2], 0), (r.msN[3], 1))
  let r3 = orN(andN((r.msN[0], 0), (r.msN[1], 0), (r.msN[2], 0), (r.msN[3], 0)), r.reset)
  r.msN[3].inputs.add s3
  r.msN[3].inputs.add r.C
  r.msN[3].inputs.add r3

  r.Q = @[
    symN("Q" & subscript[0], (r.msN[0], 0)),
    symN("Q" & subscript[1], (r.msN[1], 0)),
    symN("Q" & subscript[2], (r.msN[2], 0)),
    symN("Q" & subscript[3], (r.msN[3], 0)),
  ]

  r.placement = placementRules(
    Line(origin: point2(0, 10),  nodes: @[r.C]),

    Line(origin: point2(6, -1.5),  nodes: @[s0]),
    Line(origin: point2(6,  1.5),  nodes: @[r0]),
    Line(origin: point2(12, 0),    nodes: @[r.msN[0]]),

    Line(origin: point2(20, -1.5), nodes: @[s1]),
    Line(origin: point2(20,  1.5), nodes: @[r1]),
    Line(origin: point2(26, 0),    nodes: @[r.msN[1]]),

    Line(origin: point2(34, -1.5), nodes: @[s2]),
    Line(origin: point2(34,  1.5), nodes: @[r2]),
    Line(origin: point2(40, 0),    nodes: @[r.msN[2]]),

    Line(origin: point2(48, -1.5), nodes: @[s3]),
    Line(origin: point2(48,  1.5), nodes: @[r3]),
    Line(origin: point2(54, 0),    nodes: @[r.msN[3]]),

    Line(origin: point2(32, 8),    nodes: @[r.reset]),

    Line(origin: point2(62, 0), nodes: r.Q, gap: 2, align: Inputs),

    bus(point2(2, 0), r.C, @[s0, r0, r1, r2, r3]),
  )


proc startup*(c: Counter14): seq[ValChange] =
  result.add setVal(c.C, 0)
  for i in 0..<4:
    result.add setVal(c.ms[i].t1.T[0], 0)
    result.add setVal(c.ms[i].t1.T[1], 1)
    result.add setVal(c.ms[i].t2.T[0], 0)
    result.add setVal(c.ms[i].t2.T[1], 1)



mainModule:
  let c = counter14()

  placeComponents(c.placement)
  drawComponents()

  doc[CanvasSettings].mmScale = 2.0

  var timestamps = @[PlotTimestamp(time: 0, changes: startup(c))]
  timestamps.add PlotTimestamp(time: 0.05)

  for t in 0..<15:
    let base = 1.0 + t.float * 3.0
    timestamps.add PlotTimestamp(time: base,        changes: @[setVal(c.C, 1)])
    timestamps.add PlotTimestamp(time: base + 0.05)
    timestamps.add PlotTimestamp(time: base + 1.5,  changes: @[setVal(c.C, 0)])
    timestamps.add PlotTimestamp(time: base + 1.55)

  let p = Plot(
    data: @[@[c.C], c.Q, @[c.reset]],
    gap: 0.2,
    groupGap: 0.5,
    timeScale: 1.5,
    timestamps: timestamps,
    origin: point2(0, 14),
    skipUnchangedAxes: true,
  )
