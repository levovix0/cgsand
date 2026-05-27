import std/sequtils
import sandbox
import electronics/schemes


mainModule:
  let inputs = @[Node "x3", "x2", "x1"]
  let inverted = inputs.mapIt(norN(it))

  var outputs: seq[Node]
  for i in 0..<8:
    let n = [inverted, inputs]
    outputs.add andN(n[(i shr 2) and 1][0], n[(i shr 1) and 1][1], n[i and 1][2])

  var outputNames = (0..<outputs.len).mapIt(symN("y" & $it, outputs[it]))


  let lines = placementRules(
    Line(origin: point2(0, 3),    nodes: inputs,   gap: 7.1),
    Line(origin: point2(4, 0),    nodes: inverted, gap: 6.1),
    bus(point2(8, 0),    input = inputs[0],   outputs = outputs, color = color(0.6, 0, 0)),
    bus(point2(8.5, 0),  input = inverted[0], outputs = outputs, color = color(0, 0, 0)),
    bus(point2(10, 0),   input = inputs[1],   outputs = outputs, color = color(0, 0.6, 0)),
    bus(point2(10.5, 0), input = inverted[1], outputs = outputs, color = color(0, 0, 0)),
    bus(point2(12, 0),   input = inputs[2],   outputs = outputs, color = color(0, 0, 0.6)),
    bus(point2(12.5, 0), input = inverted[2], outputs = outputs, color = color(0, 0, 0)),
    Line(origin: point2(16, 0), nodes: outputs,     gap: 0),
    Line(origin: point2(20, 0), nodes: outputNames, gap: 0, align: Inputs),
  )

  placeComponents(lines)
  drawComponents()


  let timestamps = (0..<8).mapIt(PlotTimestamp(
    time: it.float,
    changes: @[
      setVal(inputs[0], bitVal(it, 2)),
      setVal(inputs[1], bitVal(it, 1)),
      setVal(inputs[2], bitVal(it, 0)),
    ]
  ))

  draw Plot(
    data: @[inputs, outputNames],
    gap: 1,
    groupGap: 1,
    timeScale: 2,
    timestamps: timestamps,
    origin: point2(26, 0),
  )
