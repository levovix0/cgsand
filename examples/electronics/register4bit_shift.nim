import sandbox
import electronics/schemes
import ./trigger_rs

mainModule: addDefaultElectronicsGlobals()


const bits = 4
const stageW = 16.0

type RegisterShift4Bit* = tuple[pack: Pack, placement: seq[PlacementRule], startup: seq[ValChange]]

proc registerShift4Bit*: RegisterShift4Bit =
  let clk = Node "C"
  let din = Node "D"
  let notClk = norN(clk)
  var Qs: seq[Node]
  var rsNs: seq[Node]
  var mSs: seq[Node]
  var mRs: seq[Node]
  var notDs: seq[Node]
  var mSsClk: seq[Node]
  var mRsClk: seq[Node]
  var mSsNotClk: seq[Node]
  var mRsNotClk: seq[Node]
  var startupInits: seq[ValChange]

  for i in 0..<bits:
    let rs = rsTrigger()
    let rsN = rs.pack.packN("T")

    let dInput = if i == 0: din else: Qs[i - 1]

    let notD = norN(dInput)
    let trigger = if i mod 2 == 0: clk else: notClk
    let mS = andN(dInput, trigger)
    let mR = andN(notD, trigger)

    rsN.inputs.add mS
    rsN.inputs.add mR

    let q = Node("Q" & subscript[i])
    q.inputs.add (rsN, 0)

    Qs.add q
    rsNs.add rsN
    mSs.add mS
    mRs.add mR
    notDs.add notD
    if i mod 2 == 0:
      mSsClk.add mS
      mRsClk.add mR
    else:
      mSsNotClk.add mS
      mRsNotClk.add mR
    startupInits.add setVal(rs.T[0], 0)
    startupInits.add setVal(rs.T[1], 1)

  let startup = @[setVal(din, 0), setVal(clk, 0)] & startupInits

  var rules = placementRules(
    Line(origin: point2(0, 0), nodes: @[din], align: Outputs),
    Line(origin: point2(0, 4+1/3), nodes: @[clk]),
    Line(origin: point2(12, 6), nodes: @[notClk]),
    bus(point2(1, 0), din, @[mSs[0], notDs[0]]),
    bus(point2(2, 3), clk, @[notClk] & mSsClk & mRsClk),
    bus(point2(16, 10), notClk, mSsNotClk & mRsNotClk),
  )

  for i in 0..<bits:
    let sx = 2.0 + i.float * stageW
    rules.add Line(origin: point2(sx + 1, 1.75 + i.float*4), nodes: @[notDs[i]])
    rules.add Line(origin: point2(sx + 4, 0 + i.float*4), nodes: @[mSs[i], mRs[i]], gap: 1)
    rules.add Line(origin: point2(sx + 7, 0 + i.float*4), nodes: @[rsNs[i]])
    rules.add Line(origin: point2(64, 0 + i.float*4), nodes: @[Qs[i]], align: Inputs)
    if i < bits - 1:
      rules.add bus(point2(sx + 15, 0), Qs[i], @[mSs[i + 1], notDs[i + 1]])

  return (pack(@[din, clk], Qs), rules, startup)


mainModule:
  let (r, placement, startup) = registerShift4Bit()

  let din = r.inputs[0]
  let clk = r.inputs[1]
  var Qs = r.outputs

  placeComponents(placement)
  drawComponents()

  doc[CanvasSettings].mmScale = 2.5

  var timestamps = @[
    PlotTimestamp(time: 0, changes: startup & @[setVal(din, 1)]),
    PlotTimestamp(time: 3, changes: @[setVal(din, 0)]),
    PlotTimestamp(time: 6, changes: @[setVal(din, 1)]),
    PlotTimestamp(time: 9, changes: @[setVal(din, 0)]),
    PlotTimestamp(time: 15, changes: @[setVal(din, 1)]),
    PlotTimestamp(time: 21, changes: @[setVal(din, 0)]),
  ]

  for t in 0..9:
    for t2 in 0..<3:
      for t3 in 1..<2:
        let t = t.float * 3 + t2.float + t3.float * 0.05
        timestamps.add PlotTimestamp(time: t)
    timestamps.add PlotTimestamp(time: t.float * 3 + 1, changes: @[setVal(clk, 1)])
    timestamps.add PlotTimestamp(time: t.float * 3 + 2, changes: @[setVal(clk, 0)])

  draw Plot(
    data: @[@[din, clk], Qs],
    gap: 0.6,
    groupGap: 2,
    timeScale: 2,
    timestamps: timestamps,
    origin: point2(2, 18),
    skipUnchangedAxes: true,
  )
