import sandbox
import electronics/schemes
import ./trigger_rs

mainModule: addDefaultElectronicsGlobals()

proc dTrigger*: tuple[pack: Pack, placement: seq[PlacementRule], startup: seq[ValChange]] =
  let rs = rsTrigger()
  
  let I = @[Node "D", Node "C"]
  let O = @[Node "Q", Node "!Q"]

  let D = I[0]
  let C = I[1]

  let rsN = rs.pack.packN("T")
  for i in 0..<O.len: O[i].inputs.add (rsN, i)

  let M = @[andN(D, C), andN(norN(D), C)]
  for i in 0..<M.len: rsN.inputs.add M[i]

  let placement = placementRules(
    Line(
      origin: point2(0, 2/3),
      nodes: I,
      gap: 2.01 - 1/3,
    ),
    Line(
      origin: point2(3, 1),
      nodes: @[M[1].inputs[0].n],
      gap: 1,
    ),
    bus(point2(6, 0), C, M),
    Line(
      origin: point2(8, 0),
      nodes: M,
      gap: 0,
    ),
    Line(
      origin: point2(12, 0),
      nodes: @[rsN],
      gap: 1,
    ),
    Line(
      origin: point2(20, 0),
      nodes: O,
      gap: 1,
      align: Inputs
    ),
  )

  let startup = @[setVal(D, 0), setVal(C, 0), setVal(rs.T[0], 0), setVal(rs.T[1], 1)]

  return (pack(I, O), placement, startup)




mainModule:
  let (r, placement, startup) = dTrigger()


  let D = r.inputs[0]
  let C = r.inputs[1]


  placeComponents(placement)
  drawComponents()



  var timestamps = @[
    PlotTimestamp(time: 0, changes: startup),
    PlotTimestamp(time: 3, changes: @[setVal(D, 1)]),
    PlotTimestamp(time: 6, changes: @[setVal(D, 0)]),
  ]

  for t in 0..2:
    for t2 in 0..<3:
      for t3 in 1..<2:
        let t = t.float * 3 + t2.float + t3.float * 0.05
        timestamps.add PlotTimestamp(time: t)
    timestamps.add PlotTimestamp(time: t.float * 3 + 1, changes: @[setVal(C, 1)])
    timestamps.add PlotTimestamp(time: t.float * 3 + 2, changes: @[setVal(C, 0)])

  draw Plot(
    data: @[r.inputs, r.outputs],
    gap: 0.2,
    groupGap: 0.5,
    timeScale: 2.3,
    timestamps: timestamps,
    origin: point2(0, 5),
    skipUnchangedAxes: true,
  )

