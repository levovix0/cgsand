import sandbox
import electronics/schemes
import ./trigger_d


const bits = 4
const rowH = 3.0

type Register4Bit* = tuple[pack: Pack, placement: seq[PlacementRule], startup: seq[ValChange]]

proc register4Bit*: Register4Bit =
  let clk = Node "C"
  var Ds: seq[Node]
  var Qs: seq[Node]
  var dtNs: seq[Node]
  var startup: seq[ValChange]

  for i in 0..<bits:
    let dt = dTrigger()
    let dtN = dt.pack.packN("TT")

    let d = Node("D" & subscript[i])
    let q = Node("Q" & subscript[i])

    dtN.inputs.add d
    dtN.inputs.add clk
    q.inputs.add (dtN, 0)

    Ds.add d
    Qs.add q
    dtNs.add dtN
    startup.add dt.startup

  let placement = placementRules(
    Line(
      origin: point2(0, 0),
      nodes: Ds,
      gap: rowH,
      align: Outputs,
    ),
    Line(
      origin: point2(0, 3),
      nodes: @[clk],
    ),
    bus(point2(2, 0), clk, dtNs),
    Line(
      origin: point2(3, 0),
      nodes: dtNs,
      gap: 1,
    ),
    Line(
      origin: point2(11, 0),
      nodes: Qs,
      align: Inputs,
    ),
  )

  return (pack(Ds & @[clk], Qs), placement, startup)


mainModule:
  let (r, placement, startup) = register4Bit()

  let clk = r.inputs[^1]
  var Ds = r.inputs[0..^2]
  var Qs = r.outputs

  placeComponents(placement)
  drawComponents()

  var timestamps = @[
    PlotTimestamp(time: 0, changes: startup & @[setVal(Ds[0], 1), setVal(Ds[1], 0), setVal(Ds[2], 1), setVal(Ds[3], 0)]),
    PlotTimestamp(time: 3, changes: @[setVal(Ds[0], 0), setVal(Ds[1], 1), setVal(Ds[2], 1), setVal(Ds[3], 0)]),
    PlotTimestamp(time: 6, changes: @[setVal(Ds[0], 1), setVal(Ds[1], 1), setVal(Ds[2], 0), setVal(Ds[3], 1)]),
  ]

  for t in 0..2:
    for t2 in 0..<3:
      for t3 in 1..<2:
        let t = t.float * 3 + t2.float + t3.float * 0.05
        timestamps.add PlotTimestamp(time: t)
    timestamps.add PlotTimestamp(time: t.float * 3 + 1, changes: @[setVal(clk, 1)])
    timestamps.add PlotTimestamp(time: t.float * 3 + 2, changes: @[setVal(clk, 0)])

  draw Plot(
    data: @[@[clk], Ds, Qs],
    gap: 0.6,
    groupGap: 2,
    timeScale: 2,
    timestamps: timestamps,
    origin: point2(16, 0),
    skipUnchangedAxes: true,
  )
