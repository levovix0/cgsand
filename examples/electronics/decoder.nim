import std/sequtils
import sandbox
import electronics/schemes

addDefaultElectronicsGlobals()


let inputs = @[Node "x3", "x2", "x1"]
let inverted = inputs.mapIt(norN(it))

var outputs: seq[Node]
block:
  var i = 0
  for x3 in 0..1:
    for x2 in 0..1:
      for x1 in 0..1:
        let n = [inverted, inputs]
        outputs.add andN(n[x3][0], n[x2][1], n[x1][2])
        inc i

var outputNames = (0..<outputs.len).mapIt(symN("y" & $it, outputs[it]))



let lines = placementRules(
  Line(origin: point2(0, 3),    nodes: inputs, gap: 7.1),
  Line(origin: point2(4, 0),    nodes: inverted, gap: 6.1),
  bus(point2(8, 0),    input = inputs[0],   outputs = outputs, color = color(0.6, 0, 0)),
  bus(point2(8.5, 0),  input = inverted[0], outputs = outputs, color = color(0, 0, 0)),
  bus(point2(10, 0),   input = inputs[1],   outputs = outputs, color = color(0, 0.6, 0)),
  bus(point2(10.5, 0), input = inverted[1], outputs = outputs, color = color(0, 0, 0)),
  bus(point2(12, 0),   input = inputs[2],   outputs = outputs, color = color(0, 0, 0.6)),
  bus(point2(12.5, 0), input = inverted[2], outputs = outputs, color = color(0, 0, 0)),
  Line(origin: point2(16, 0),   nodes: outputs, gap: 0),
  Line(origin: point2(20, 0),   nodes: outputNames, gap: 0, align: Inputs),
)



placeComponents(lines)
drawComponents()



var timestamps: seq[PlotTimestamp]
block:
  var i = 0
  for x3 in 0..1:
    for x2 in 0..1:
      for x1 in 0..1:
        timestamps.add PlotTimestamp(
          time: i.float,
          changes: @[
            setVal(inputs[0], Value(power: x3.float)),
            setVal(inputs[1], Value(power: x2.float)),
            setVal(inputs[2], Value(power: x1.float)),
          ]
        )
        inc i

draw Plot(
  data: @[inputs, outputNames],
  gap: 1,
  groupGap: 1,
  timeScale: 2,
  timestamps: timestamps,
  origin: point2(26, 0),
)


