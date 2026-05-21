import std/sequtils
import sandbox
import electronics/schemes


mainModule:
  let A = @[Node "A1", "A2", "A3"]
  let B = @[Node "B1", "B2", "B3"]
  let C = Node "Cx"

  let l1 = @[xorN(A[0], B[0]), andN(A[0], B[0])]
  let l1a = @[xorN(C, l1[0]), andN(C, l1[0])]
  let l1b = @[orN(l1a[1], l1[1])]
  l1b[0].height = 4

  let l2 = @[xorN(A[1], B[1]), andN(A[1], B[1])]
  let l2a = @[xorN(l1b[0], l2[0]), andN(l1b[0], l2[0])]
  let l2b = @[orN(l2a[1], l2[1])]
  l2b[0].height = 4

  let l3 = @[xorN(A[2], B[2]), andN(A[2], B[2])]
  let l3a = @[xorN(l2b[0], l3[0]), andN(l2b[0], l3[0])]
  let l3b = @[orN(l3a[1], l3[1])]
  l3b[0].height = 4

  let S = @[l1a[0], l2a[0], l3a[0]]
  let O = @[Node "S1", "S2", "S3"]
  for i in 0..<O.len: O[i].inputs.add S[i][0]

  let Oc = Node "Cy"
  Oc.inputs.add l3b[0][0]

  let xx = @[4.0, 12, 20]

  let lines = placementRules(
    Line(origin: point2(0, 3),  nodes: @[A[0], B[0]], gap: 1),
    Line(origin: point2(0, 8),  nodes: @[A[1], B[1]], gap: 1),
    Line(origin: point2(0, 13), nodes: @[A[2], B[2]], gap: 1),
    Line(origin: point2(0, 0),  nodes: @[C], gap: 1),

    bus(point2(xx[0], 0),       input = A[0],   outputs = l1),
    bus(point2(xx[0] + 0.5, 0), input = B[0],   outputs = l1),
    Line(origin: point2(xx[0] + 2, 2),  nodes: l1,  gap: 0),
    bus(point2(xx[0] + 5, 0),   input = C,      outputs = l1a),
    bus(point2(xx[0] + 5.5, 0), input = l1[0],  outputs = l1a),
    Line(origin: point2(xx[0] + 7, 0),  nodes: l1a, gap: 0),
    Line(origin: point2(xx[0] + 10, 2), nodes: l1b, gap: 0),

    bus(point2(xx[1], 0),       input = A[1],    outputs = l2),
    bus(point2(xx[1] + 0.5, 0), input = B[1],    outputs = l2),
    Line(origin: point2(xx[1] + 2, 7),  nodes: l2,  gap: 0),
    bus(point2(xx[1] + 5, 0),   input = l1b[0],  outputs = l2a),
    bus(point2(xx[1] + 5.5, 0), input = l2[0],   outputs = l2a),
    Line(origin: point2(xx[1] + 7, 5),  nodes: l2a, gap: 0),
    Line(origin: point2(xx[1] + 10, 7), nodes: l2b, gap: 0),

    bus(point2(xx[2], 0),       input = A[2],    outputs = l3),
    bus(point2(xx[2] + 0.5, 0), input = B[2],    outputs = l3),
    Line(origin: point2(xx[2] + 2, 12),  nodes: l3,  gap: 0),
    bus(point2(xx[2] + 5, 0),   input = l2b[0],  outputs = l3a),
    bus(point2(xx[2] + 5.5, 0), input = l3[0],   outputs = l3a),
    Line(origin: point2(xx[2] + 7, 10),  nodes: l3a, gap: 0),
    Line(origin: point2(xx[2] + 10, 12), nodes: l3b, gap: 0),

    Line(origin: point2(35, 0), nodes: O,       align: Inputs, gap: 1),
    Line(origin: point2(35, 8), nodes: @[Oc],   align: Inputs, gap: 1),
  )

  placeComponents(lines)
  drawComponents()


  let timestamps = (0..<64).mapIt(PlotTimestamp(
    time: it.float,
    changes: @[
      setVal(A[0], bitVal(it, 3)),
      setVal(A[1], bitVal(it, 4)),
      setVal(A[2], bitVal(it, 5)),
      setVal(B[0], bitVal(it, 0)),
      setVal(B[1], bitVal(it, 1)),
      setVal(B[2], bitVal(it, 2)),
    ]
  ))

  draw Plot(
    data: @[A, B, @[C], O, @[Oc]],
    gap: 0.5,
    groupGap: 0.5,
    timeScale: 0.6,
    timestamps: timestamps,
    origin: point2(40, -2),
  )
