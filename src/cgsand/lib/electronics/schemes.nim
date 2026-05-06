import std/[sequtils, tables, hashes, sets, algorithm]
import sandbox, geom2d
import pkg/bumpy

type
  NodeKind* = enum
    SymN
    BoxN
  
  Port* = object
    n: Node
    port*: int

  Node* = ref object
    kind*: NodeKind
    inputs*: seq[Port]
    outputs*: seq[bool]  # true - regular out, false - inversed out
    name*: string
    height*: float  # if equals 0, the calculated automatically: 1 for SymN, min(2, n.inputs.len) for BoxN
  
  Line* = object
    nodes*: seq[Node]
    gap*: float32
    align*: bool  # if true, align all nodes to their inputs, so connection does not need to bend (and ignore gap)
    origin*: Point2
  
  Bus* = object
    input*: Node
    outputs*: seq[Node]
    origin*: Point2
    color*: Color = color(0, 0, 0)
  
  Value* = object
    power*: float

  Connection* = seq[Point2]
  Branch* = Point2


  ValChange* = object
    node*: Node
    value*: Value

  PlotTimestamp* = object
    time*: float
    changes*: seq[ValChange]

  Plot* = object
    data*: seq[seq[Node]]
    gap*: float
    groupGap*: float
    timestamps*: seq[PlotTimestamp]
    origin*: Point2
    timeScale*: float = 1.0
    axiesColor*: Color = color(0, 0, 0, 0.1)

const Eps = 1e-4


proc addDefaultElectronicsGlobals* =
  doc.add CanvasSettings(autoSize: true, margin: vec2(1)):
    AxisYDown
    FontSize 1
    Background color(1, 1, 1)
    Foreground color(0, 0, 0)


converter toNode*(name: string): Node = Node(kind: SymN, name: name)

converter toPort*(name: string): Port = Port(n: Node name, port: 0)
converter toPort*(n: Node): Port = Port(n: n, port: 0)
converter toPort*(n: (Node, int)): Port = Port(n: n[0], port: n[1])

proc `$`*(n: Node): string = n.name


proc orN*(inputs: varargs[Port]): Node =
  Node(kind: BoxN, name: "1", inputs: inputs.toSeq, outputs: @[true])

proc norN*(inputs: varargs[Port]): Node =
  Node(kind: BoxN, name: "1", inputs: inputs.toSeq, outputs: @[false])


proc andN*(inputs: varargs[Port]): Node =
  Node(kind: BoxN, name: "&", inputs: inputs.toSeq, outputs: @[true])

proc nandN*(inputs: varargs[Port]): Node =
  Node(kind: BoxN, name: "&", inputs: inputs.toSeq, outputs: @[false])


proc xorN*(inputs: varargs[Port]): Node =
  Node(kind: BoxN, name: "=1", inputs: inputs.toSeq, outputs: @[true])

proc xnorN*(inputs: varargs[Port]): Node =
  Node(kind: BoxN, name: "=1", inputs: inputs.toSeq, outputs: @[false])


proc symN*(name: string, inputs: varargs[Port]): Node =
  Node(kind: SymN, name: name, inputs: inputs.toSeq, outputs: @[true])



proc hash*(n: Node): Hash = hash(cast[pointer](n))



proc nodeSize*(n: Node): Vec2 =
  case n.kind
  of SymN: vec2(1, (if n.height == 0: 1.0 else: n.height))
  of BoxN: vec2(2, (if n.height == 0: max(2.0, n.inputs.len.float) else: n.height))

proc inputPortY*(n: Node, r: Rect, portIdx: int): float32 =
  case n.kind
  of SymN: r.y
  of BoxN: r.y + r.h * ((portIdx + 1) / (n.inputs.len + 1))

proc outputPortY*(n: Node, r: Rect, portIdx: int): float32 =
  case n.kind
  of SymN: r.y
  of BoxN: r.y + r.h * ((portIdx + 1) / (n.outputs.len + 1))



proc setVal*(node: Node, value: Value): ValChange =
  ValChange(node: node, value: value)



proc placeComponents*(lines: tuple) =
  var nodeRects = initTable[Node, Rect]()

  type ConnKey = tuple[n: pointer, port: int]
  var busHandled = initHashSet[ConnKey]()

  # Pass 1: collect which (node, portIdx) pairs are connected via buses
  for elem in lines.fields:
    when elem is Bus:
      for outNode in elem.outputs:
        for portIdx, inp in outNode.inputs:
          if inp.n == elem.input:
            busHandled.incl (cast[pointer](outNode), portIdx)

  # Pass 2: place (Node, Rect)
  for elem in lines.fields:
    when elem is Line:
      var pos = elem.origin
      for node in elem.nodes:
        let sz = nodeSize(node)
        var r: Rect
        if elem.align and node.inputs.len > 0:
          let inp0 = node.inputs[0]
          if nodeRects.hasKey(inp0.n):
            let inRect = nodeRects[inp0.n]
            let connectY = outputPortY(inp0.n, inRect, inp0.port)
            r = rect(pos.x.float32, connectY, sz.x.float32, sz.y.float32)
        else:
          r = rect(pos.x.float32, pos.y.float32, sz.x.float32, sz.y.float32)
          pos.y += sz.y + elem.gap.float
        nodeRects[node] = r
        doc.add node, r

  # Pass 3: place Connection and Branch
  for elem in lines.fields:
    when elem is Line:
      for node in elem.nodes:
        let r = nodeRects[node]
        for portIdx, inp in node.inputs:
          if (cast[pointer](node), portIdx) notin busHandled and inp.n in nodeRects:
            let inRect = nodeRects[inp.n]
            if node.height != 0 and inp.n.outputs.len == 1:
              let fromY = outputPortY(inp.n, inRect, inp.port)
              let p1 = point2(inRect.x + inRect.w, fromY)
              let p2 = point2(r.x, fromY)
              doc.add Connection(@[p1, p2])
            else:
              let fromY = outputPortY(inp.n, inRect, inp.port)
              let toY = inputPortY(node, r, portIdx)
              let p1 = point2(inRect.x + inRect.w, fromY)
              let p2 = point2(r.x, toY)
              if abs(fromY - toY) < Eps:
                doc.add Connection(@[p1, p2])
              else:
                let midX = (p1.x + p2.x) / 2.0
                doc.add Connection(@[
                  p1,
                  point2(midX, fromY),
                  point2(midX, toY),
                  p2,
                ])
                doc.add Branch point2(midX, fromY)  # todo

    when elem is Bus:
      let inNode = elem.input
      if inNode in nodeRects:
        let inRect = nodeRects[inNode]
        let busX = elem.origin.x.float32
        let startY = outputPortY(inNode, inRect, 0)

        var busConns: seq[tuple[n: Node, port: int]]
        for outNode in elem.outputs:
          for portIdx, inp in outNode.inputs:
            if inp.n == inNode and outNode in nodeRects:
              busConns.add (outNode, portIdx)

        if busConns.len > 0:
          var minBusY = startY
          var maxBusY = startY
          for bc in busConns:
            let portY = inputPortY(bc.n, nodeRects[bc.n], bc.port)
            minBusY = min(minBusY, portY)
            maxBusY = max(maxBusY, portY)

          # horizontal wire from input node output to bus
          doc.add Connection(@[
            point2(inRect.x + inRect.w, startY),
            point2(busX, startY),
          ]), elem.color

          # vertical bus wire
          doc.add Connection(@[
            point2(busX, minBusY),
            point2(busX, maxBusY),
          ]), elem.color

          # horizontal branches from bus to each gate input port
          for i, bc in busConns:
            let outRect = nodeRects[bc.n]
            let portY = inputPortY(bc.n, outRect, bc.port)
            
            doc.add Connection(@[point2(busX, portY), point2(outRect.x, portY)]):
              elem.color
            
            if (i != 0 or startY <= minBusY) and (i != busConns.high or startY >= maxBusY):
              doc.add Branch point2(busX, portY), elem.color
          
          if startY > minBusY and startY < maxBusY:
              doc.add Branch point2(busX, startY), elem.color



proc drawComponents* =
  doc.forEach (c: Connection, color: Color||color(0, 0, 0)):
    for i in 0..<(c.len-1):
      doc.add lineSection(c[i], c[i + 1]):
        color

  doc.forEach (b: Branch, color: Color||color(0, 0, 0)):
    doc.add circle(center = b.Point2, radius = 0.1):
      color
      Background color

  doc.forEach (n: Node, r: Rect):
    case n.kind
    of BoxN:
      let p = [point2(r.x, r.y), point2(r.x + r.w, r.y), point2(r.x + r.w, r.y + r.h), point2(r.x, r.y + r.h)]
      doc.add lineSection(p[0], p[1])
      doc.add lineSection(p[1], p[2])
      doc.add lineSection(p[2], p[3])
      doc.add lineSection(p[3], p[0])
    
      doc.add Text n.name:
        Position2 point2(r.x + r.w/2, r.y + 0.2)
        PositionAtTop
    
      for i, o in n.outputs:
        let p = point2(r.x + r.w, outputPortY(n, r, i))
        if not o:
          doc.add circle(center = p, radius = 0.1):
            Background color(1, 1, 1)
    
    of SymN:
      doc.add lineSection(point2(r.x, r.y), point2(r.x + r.w, r.y))
      doc.add Text n.name:
        Position2 point2(r.x + r.w/2, r.y - 0.2)
        PositionAtBottom


proc simulateNode(n: Node, vals: var Table[Node, Value]): Value =
  if n in vals: return vals[n]
  if n.inputs.len == 0:
    vals[n] = Value(power: 0.0)
    return vals[n]

  case n.kind
  of SymN:
    let v = simulateNode(n.inputs[0].n, vals)
    vals[n] = v
    return v
  
  of BoxN:
    case n.name
    of "&", "1":
      var res = if n.name == "&": 1.0 else: 0.0
      for inp in n.inputs:
        let iv = simulateNode(inp.n, vals).power
        if n.name == "&":
          if iv < res: res = iv
        else:
          if iv > res: res = iv
      if n.outputs.len > 0 and not n.outputs[0]:
        res = 1.0 - res
      vals[n] = Value(power: res)

    of "=1":
      var res = false
      for inp in n.inputs:
        let iv = simulateNode(inp.n, vals).power
        res = res xor (iv > 0.5)
      if n.outputs.len > 0 and not n.outputs[0]:
        res = not res
      vals[n] = Value(power: res.float)

    else:
      ## some unknown operator, leave unchanged
    
    return vals[n]


proc draw*(plot: Plot) =
  const signalH = 1.0
  var stamps = plot.timestamps
  stamps.sort(proc(a, b: PlotTimestamp): int = cmp(a.time, b.time))
  if stamps.len == 0: return
  let firstTime = stamps[0].time

  var nodeValues: Table[Node, seq[tuple[time: float, v: Value]]]
  var cumVals: Table[Node, Value]
  for stamp in stamps:
    for change in stamp.changes:
      cumVals[change.node] = change.value
    var simVals = cumVals
    for group in plot.data:
      for node in group:
        discard simulateNode(node, simVals)
    for group in plot.data:
      for node in group:
        if node in simVals:
          nodeValues.mgetOrPut(node, @[]).add (time: stamp.time, v: simVals[node])

  var y = plot.origin.y
  for groupIdx, group in plot.data:
    for nodeIdx, node in group:
      let rowY = y
      let vals = nodeValues.getOrDefault(node)

      doc.add Text node.name:
        Position2 point2(plot.origin.x - 0.2, rowY + signalH/2)
        PositionAtRight

      doc.add lineSection(point2(plot.origin.x, rowY), point2(plot.origin.x, rowY + signalH))

      var prevVal = Value(power: float.low)

      for i, tv in vals:
        let x1 = plot.origin.x + (tv.time - firstTime) * plot.timeScale
        let x2 = if i < vals.high: plot.origin.x + (vals[i+1].time - firstTime) * plot.timeScale
                 else: x1 + plot.timeScale
        let isHigh = tv.v.power > 0.5
        let lineY = if isHigh: rowY else: rowY + signalH

        doc.add lineSection(point2(x1, lineY), point2(x2, lineY))

        if i > 0 and (vals[i-1].v.power > 0.5) != isHigh:
          let prevY = if vals[i-1].v.power > 0.5: rowY else: rowY + signalH
          doc.add lineSection(point2(x1, prevY), point2(x1, lineY))

        if tv.v != prevVal:
          prevVal = tv.v
          let valStr = if isHigh: "1" else: "0"
          if isHigh:
            doc.add Text valStr:
              Position2 point2(x1 + 0.2, rowY + 0.2)
              PositionAtTopLeft
              FontSize 0.5
          else:
            doc.add Text valStr:
              Position2 point2(x1 + 0.2, rowY + signalH - 0.2)
              PositionAtBottomLeft
              FontSize 0.5

      y += signalH + plot.gap

    if groupIdx < plot.data.high:
      y += plot.groupGap
  
  for t in plot.timestamps[1..^1]:
    doc.add lineSection(
      point2(plot.origin.x + t.time * plot.timeScale, plot.origin.y),
      point2(plot.origin.x + t.time * plot.timeScale, y - plot.gap)
    ), plot.axiesColor
  
  when false:
    let t = plot.timestamps[^1]
    doc.add lineSection(
      point2(plot.origin.x + (t.time + 1) * plot.timeScale, plot.origin.y),
      point2(plot.origin.x + (t.time + 1) * plot.timeScale, y - plot.gap)
    ), plot.axiesColor



when isMainModule:
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

  let lines = (
    Line(origin: point2(0, 3),    nodes: inputs, gap: 7),
    Line(origin: point2(4, 0),    nodes: inverted, gap: 6),
    Bus( origin: point2(8, 0),    input: inputs[0], outputs: outputs, color: color(0.6, 0, 0)),
    Bus( origin: point2(8.5, 0),  input: inverted[0], outputs: outputs, color: color(0, 0, 0)),
    Bus( origin: point2(10, 0),   input: inputs[1], outputs: outputs, color: color(0, 0.6, 0)),
    Bus( origin: point2(10.5, 0), input: inverted[1], outputs: outputs, color: color(0, 0, 0)),
    Bus( origin: point2(12, 0),   input: inputs[2], outputs: outputs, color: color(0, 0, 0.6)),
    Bus( origin: point2(12.5, 0), input: inverted[2], outputs: outputs, color: color(0, 0, 0)),
    Line(origin: point2(16, 0),   nodes: outputs, gap: 0),
    Line(origin: point2(20, 0),   nodes: outputNames, gap: 0, align: true),
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
    data: @[inputs, outputs],
    gap: 1,
    groupGap: 3,
    timestamps: timestamps,
    origin: point2(26, 0),
  )

