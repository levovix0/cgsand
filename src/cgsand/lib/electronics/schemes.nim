import std/[sequtils, tables, hashes, sets, algorithm, strutils]
import sandbox, geom2d
import pkg/bumpy

type
  NodeKind* = enum
    SymN
    BoxN
    PackN

  Pack* = ref object
    inputs*: seq[Node]
    outputs*: seq[Node]

  Port* = object
    n*: Node
    port*: int
    delayed*: bool

  Node* = ref object
    kind*: NodeKind
    inputs*: seq[Port]
    outputs*: seq[bool]  # true - regular out, false - inversed out
    name*: string
    height*: float  # if equals 0, the calculated automatically: 1 for SymN, min(2, n.inputs.len) for BoxN
    pack*: Pack
  
  ElementAlignment* = enum
    None     # place items using origin, element heights and gap
    Inputs   # align all nodes to their inputs, so connection does not need to bend (and ignore gap)
    Outputs  # align all nodes to their outputs, so connection does not need to bend (and ignore gap)
  
  Line* = object
    nodes*: seq[Node]
    gap*: float32
    align*: ElementAlignment
    origin*: Point2
  
  Bus* = object
    input*: Port
    outputs*: seq[Node]
    origin*: Point2
    path*: seq[Point2]
    color*: Color = color(0, 0, 0)

  PlacementRuleKind* = enum
    LineR
    BusR

  PlacementRule* = object
    case kind*: PlacementRuleKind
    of LineR: line*: Line
    of BusR: bus*: Bus

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
    skipUnchangedAxes*: bool = false

const Eps = 1e-4
const subscript* = ["₀", "₁", "₂", "₃", "₄", "₅", "₆", "₇", "₈", "₉"]


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

proc delayed*(n: Node, port = 0): Port = Port(n: n, port: port, delayed: true)

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


proc pack*(inputs: openArray[Node], outputs: openArray[Node]): Pack =
  Pack(inputs: @inputs, outputs: @outputs)

proc packN*(pack: Pack, name: string, inputs: varargs[Port]): Node =
  Node(kind: PackN, name: name, inputs: @inputs, pack: pack, outputs: newSeqWith(pack.outputs.len, true))


converter toPlacementRule*(l: Line): PlacementRule = PlacementRule(kind: LineR, line: l)
converter toPlacementRule*(b: Bus): PlacementRule = PlacementRule(kind: BusR, bus: b)

proc bus*(path: openArray[Point2], input: Port, outputs: openArray[Node], color = color(0, 0, 0)): Bus =
  Bus(path: @path, input: input, outputs: @outputs, color: color)

proc bus*(origin: Point2, input: Port, outputs: openArray[Node], color = color(0, 0, 0)): Bus =
  Bus(origin: origin, input: input, outputs: @outputs, color: color)


proc placementRules*(rules: varargs[PlacementRule]): seq[PlacementRule] = @rules

proc move*(rules: var seq[PlacementRule], v: Vec2) =
  for x in rules.mitems:
    case x.kind
    of LineR:
      x.line.origin += v
    of BusR:
      x.bus.origin += v
      for x in x.bus.path.mitems:
        x += v



proc hash*(n: Node): Hash = hash(cast[pointer](n))
proc hash*(p: Point2): Hash = !$(0.Hash !& hash(p.x) !& hash(p.y))



proc nodeSize*(n: Node): Vec2 =
  case n.kind
  of SymN: vec2(1, (if n.height == 0: 1.0 else: n.height))
  of BoxN: vec2(2, (if n.height == 0: max(2.0, n.inputs.len.float) else: n.height))
  of PackN:
    assert(n.pack != nil)
    let nports = max(n.pack.inputs.len, n.pack.outputs.len)
    vec2(6, (if n.height == 0: max(2.0, nports.float * 2) else: n.height))

proc inputPortY*(n: Node, r: Rect, portIdx: int): float32 =
  case n.kind
  of SymN: r.y
  of BoxN: r.y + r.h * ((portIdx + 1) / (n.inputs.len + 1))
  of PackN: (let inpH = r.h / n.pack.inputs.len.float; r.y + inpH * portIdx.float + inpH/2)

proc outputPortY*(n: Node, r: Rect, portIdx: int): float32 =
  case n.kind
  of SymN: r.y
  of BoxN: r.y + r.h * ((portIdx + 1) / (n.outputs.len + 1))
  of PackN: (let outH = r.h / n.pack.outputs.len.float; r.y + outH * portIdx.float + outH/2)



converter toValue*(power: float): Value = Value(power: power)
converter toValue*(power: int): Value = Value(power: power.float)

proc setVal*(node: Node, value: Value): ValChange =
  ValChange(node: node, value: value)

proc `not`*(v: Value): Value =
  Value(power: 1 - v.power)



proc placeComponents*(rules: seq[PlacementRule]) =
  var nodeRects = initTable[Node, Rect]()
  var allConns: seq[tuple[pts: Connection, color: Color, startsFromElement: bool]]

  type ConnKey = tuple[n: pointer, port: int]
  var busHandled = initHashSet[ConnKey]()

  # Pass 1: collect which (node, portIdx) pairs are connected via buses
  for rule in rules:
    if rule.kind == BusR:
      let elem = rule.bus
      for outNode in elem.outputs:
        for portIdx, inp in outNode.inputs:
          if inp.n == elem.input.n and inp.port == elem.input.port:
            busHandled.incl (cast[pointer](outNode), portIdx)

  # Build successor table: node -> [(consuming node, port index)]
  var successors = initTable[Node, seq[tuple[n: Node, port: int]]]()
  for rule in rules:
    case rule.kind
    of LineR:
      for n in rule.line.nodes:
        for portIdx, inp in n.inputs:
          successors.mgetOrPut(inp.n, @[]).add (n, portIdx)
    of BusR:
      for outNode in rule.bus.outputs:
        for portIdx, inp in outNode.inputs:
          successors.mgetOrPut(inp.n, @[]).add (outNode, portIdx)

  # Pass 2a: place nodes from Lines with no alignment (no inter-node dependencies)
  for rule in rules:
    if rule.kind == LineR and rule.line.align == None:
      let elem = rule.line
      var pos = elem.origin
      for node in elem.nodes:
        let sz = nodeSize(node)
        let r = rect(pos.x.float32, pos.y.float32, sz.x.float32, sz.y.float32)
        pos.y += sz.y + elem.gap.float
        nodeRects[node] = r
        doc.add node, r

  # Pass 2b: place nodes from Lines with alignment, preserving original order
  for rule in rules:
    if rule.kind == LineR and rule.line.align != None:
      let elem = rule.line
      var pos = elem.origin
      for node in elem.nodes:
        let sz = nodeSize(node)
        let zeroRect = rect(0f32, 0f32, sz.x.float32, sz.y.float32)
        var r = rect(pos.x.float32, pos.y.float32, sz.x.float32, sz.y.float32)
        var positioned = false

        case elem.align
        of Inputs:
          if node.inputs.len > 0:
            let inp0 = node.inputs[0]
            if nodeRects.hasKey(inp0.n):
              let connectY = outputPortY(inp0.n, nodeRects[inp0.n], inp0.port)
              r = rect(pos.x.float32, connectY - inputPortY(node, zeroRect, 0), sz.x.float32, sz.y.float32)
              positioned = true
        of Outputs:
          if successors.hasKey(node):
            for succ in successors[node]:
              if succ.n in nodeRects:
                let targetY = inputPortY(succ.n, nodeRects[succ.n], succ.port)
                r = rect(pos.x.float32, targetY - outputPortY(node, zeroRect, 0), sz.x.float32, sz.y.float32)
                positioned = true
                break
        of None:
          discard

        if not positioned:
          pos.y += sz.y + elem.gap.float

        nodeRects[node] = r
        doc.add node, r

  # Pass 3: place Connection and collect for branch detection
  for rule in rules:
    case rule.kind
    of LineR:
      let elem {.cursor.} = rule.line
      for node in elem.nodes:
        let r = nodeRects[node]
        for portIdx, inp in node.inputs:
          if (cast[pointer](node), portIdx) notin busHandled and inp.n in nodeRects:
            let inRect = nodeRects[inp.n]
            if node.height != 0 and inp.n.outputs.len == 1:
              let fromY = outputPortY(inp.n, inRect, inp.port)
              let pts = Connection(@[point2(inRect.x + inRect.w, fromY), point2(r.x, fromY)])
              doc.add pts
              allConns.add (pts, color(0, 0, 0), true)
            else:
              let fromY = outputPortY(inp.n, inRect, inp.port)
              let toY = inputPortY(node, r, portIdx)
              let p1 = point2(inRect.x + inRect.w, fromY)
              let p2 = point2(r.x, toY)
              if abs(fromY - toY) < Eps:
                let pts = Connection(@[p1, p2])
                doc.add pts
                allConns.add (pts, color(0, 0, 0), true)
              else:
                let midX = (p1.x + p2.x) / 2.0
                let pts = Connection(@[p1, point2(midX, fromY), point2(midX, toY), p2])
                doc.add pts
                allConns.add (pts, color(0, 0, 0), true)

    of BusR:
      let elem {.cursor.} = rule.bus
      let inNode = elem.input.n
      let inPort = elem.input.port
      if inNode in nodeRects:
        let inRect = nodeRects[inNode]
        let startY = outputPortY(inNode, inRect, inPort)

        let (busX, pathEndY, leadPts) =
          if elem.path.len >= 1:
            let bx = elem.path[^1].x.float32
            let py = elem.path[^1].y.float32
            var pts: seq[Point2] = @[point2(inRect.x + inRect.w, startY)]
            pts.add elem.path
            (bx, py, pts)
          else:
            let bx = elem.origin.x.float32
            (bx, startY, @[point2(inRect.x + inRect.w, startY), point2(bx, startY)])

        var busConns: seq[tuple[n: Node, port: int]]
        for outNode in elem.outputs:
          for portIdx, inp in outNode.inputs:
            if inp.n == inNode and inp.port == inPort and outNode in nodeRects:
              busConns.add (outNode, portIdx)

        if busConns.len > 0:
          var minBusY = pathEndY
          var maxBusY = pathEndY
          for bc in busConns:
            let portY = inputPortY(bc.n, nodeRects[bc.n], bc.port)
            minBusY = min(minBusY, portY)
            maxBusY = max(maxBusY, portY)

          let lead = Connection(leadPts)
          doc.add lead, elem.color
          allConns.add (lead, elem.color, true)

          let vertBus = Connection(@[point2(busX, minBusY), point2(busX, maxBusY)])
          doc.add vertBus, elem.color
          allConns.add (vertBus, elem.color, false)

          for bc in busConns:
            let outRect = nodeRects[bc.n]
            let portY = inputPortY(bc.n, outRect, bc.port)
            let stub = Connection(@[point2(busX, portY), point2(outRect.x, portY)])
            doc.add stub, elem.color
            allConns.add (stub, elem.color, false)

  # todo: check that the Branch points are connecting diffirent signals
  # Pass 4: if 2+ Connection start from the same point, add a Branch
  var starters: seq[tuple[p: Point2, dir: Vec2, count: int, color: Color]]
  for i, conn in allConns:
    if conn.pts.len < 2: continue
    block hasStarter:
      for starter in starters.mitems:
        if starter.p ~== conn.pts[0] and not isParallel(conn.pts[1] - conn.pts[0], starter.dir):
          inc starter.count
          if starter.color == color(0, 0, 0):
            starter.color = conn.color
          break hasStarter
      # not hasStarter
      starters.add (conn.pts[0], conn.pts[1] - conn.pts[0], (if conn.startsFromElement: 1 else: 0), conn.color)
  
  for starter in starters:
    if starter.count > 1:
      doc.add Branch starter.p, starter.color

  # Pass 5: detect T-junction branch points
  var seenBranches: HashSet[Point2]
  for i, conn1 in allConns:
    for v in conn1.pts:
      for j, conn2 in allConns:
        if i == j: continue
        for si in 0..<conn2.pts.high:
          let a = conn2.pts[si]
          let b = conn2.pts[si + 1]
          if v ~== a or v ~== b: continue

          if hasPoint(lineSection(a, b), v):
            if v notin seenBranches:
              seenBranches.incl v
              doc.add Branch v, conn2.color
            break



proc drawRect(r: Rect) =
  doc.add lineSection(point2(r.x, r.y), point2(r.x + r.w, r.y))
  doc.add lineSection(point2(r.x + r.w, r.y), point2(r.x + r.w, r.y + r.h))
  doc.add lineSection(point2(r.x + r.w, r.y + r.h), point2(r.x, r.y + r.h))
  doc.add lineSection(point2(r.x, r.y + r.h), point2(r.x, r.y))



proc drawComponents* =
  doc.forEach (c: Connection, color: Color||color(0, 0, 0)):
    for i in 0..<(c.len-1):
      doc.add lineSection(c[i], c[i + 1]):
        color

  doc.forEach (b: Branch, color: Color||color(0, 0, 0)):
    doc.add circle(center = b.Point2, radius = 0.1):
      Foreground color
      Background color

  doc.forEach (n: Node, r: Rect):
    case n.kind
    of BoxN:
      drawRect(r)
    
      doc.add Text n.name:
        Position2 point2(r.x + r.w/2, r.y + 0.2)
        PositionAtTop
    
      for i, o in n.outputs:
        let p = point2(r.x + r.w, outputPortY(n, r, i))
        if not o:
          doc.add circle(center = p, radius = 0.1):
            Foreground color(0, 0, 0)
            Background color(1, 1, 1)
    
    of SymN:
      var name = n.name
      let negate = name.startsWith("!")
      name.removePrefix("!")

      doc.add lineSection(point2(r.x, r.y), point2(r.x + r.w, r.y))
      doc.add Text name:
        Position2 point2(r.x + r.w/2, r.y - 0.2)
        PositionAtBottom
      
      if negate:
        doc.add lineSection(point2(r.x, r.y - r.h - 0.1), point2(r.x + r.w, r.y - r.h - 0.1)), Thickness 0.05

    of PackN:
      assert(n.pack != nil)

      drawRect(rect(r.x, r.y, r.w, r.h))
      
      doc.add Text n.name:
        Position2 point2(r.x + 3, r.y + 0.2)
        PositionAtTop
      
      doc.add lineSection(point2(r.x + 2, r.y), point2(r.x + 2, r.y + r.h))
      doc.add lineSection(point2(r.x + 4, r.y), point2(r.x + 4, r.y + r.h))

      let inpH = r.h / n.pack.inputs.len.float
      let outH = r.h / n.pack.outputs.len.float
  
      for i, inpN in n.pack.inputs:
        let y = r.y + i.float * inpH
        if i != 0:
          doc.add lineSection(point2(r.x, y), point2(r.x + 2, y))
        var name = inpN.name
        let negate = name.startsWith("!")
        name.removePrefix("!")
        let textPos = point2(r.x + 1, y + inpH/2)
        doc.add Text name:
          Position2 textPos
          PositionAtCenter
        if negate:
          doc.add lineSection(textPos + vec2(-0.5, -0.5), textPos + vec2(0.5, -0.5)), Thickness 0.05

      for i, outN in n.pack.outputs:
        let y = r.y + i.float * outH
        if i != 0:
          doc.add lineSection(point2(r.x + 4, y), point2(r.x + 6, y))
        var name = outN.name
        let negate = name.startsWith("!")
        name.removePrefix("!")
        let textPos = point2(r.x + 5, y + outH/2)
        doc.add Text name:
          Position2 textPos
          PositionAtCenter
        if negate:
          doc.add lineSection(textPos + vec2(-0.5, -0.5), textPos + vec2(0.5, -0.5)), Thickness 0.05
          doc.add circle(point2(r.x + 6, y + outH/2), radius = 0.1):
            Foreground color(0, 0, 0)
            Background color(1, 1, 1)


proc simulateNode(n: Node, vals: var Table[Node, Value], prevVals: Table[Node, Value], computing: var HashSet[Node], skipSim: HashSet[Node]): Value =
  if n in vals and (n.inputs.len == 0 or n in skipSim): return vals[n]
  if n in computing:  # force delay
    return prevVals.getOrDefault(n, Value(power: 0.0))
  if n.inputs.len == 0:
    vals[n] = Value(power: 0.0)
    return vals[n]

  computing.incl n

  template resolveInp(inpP: Port): Value =
    let inp = inpP
    if inp.delayed:
      if inp.n.kind == PackN and inp.n.pack != nil and inp.port < inp.n.pack.outputs.len:
        prevVals.getOrDefault(inp.n.pack.outputs[inp.port], Value(power: 0.0))
      else:
        prevVals.getOrDefault(inp.n, Value(power: 0.0))
    else:
      if inp.n.kind == PackN and inp.n.pack != nil:
        discard simulateNode(inp.n, vals, prevVals, computing, skipSim)
        if inp.port < inp.n.pack.outputs.len:
          simulateNode(inp.n.pack.outputs[inp.port], vals, prevVals, computing, skipSim)
        else:
          Value(power: 0.0)
      else:
        simulateNode(inp.n, vals, prevVals, computing, skipSim)

  case n.kind
  of SymN:
    vals[n] = resolveInp(n.inputs[0])

  of PackN:
    if n.pack != nil:
      for i, inpNode in n.pack.inputs:
        if i < n.inputs.len:
          vals[inpNode] = resolveInp(n.inputs[i])
      if n.pack.outputs.len > 0:
        vals[n] = simulateNode(n.pack.outputs[0], vals, prevVals, computing, skipSim)
        for i in 1..<n.pack.outputs.len:
          discard simulateNode(n.pack.outputs[i], vals, prevVals, computing, skipSim)
      else:
        vals[n] = Value(power: 0.0)
    else:
      vals[n] = Value(power: 0.0)

  of BoxN:
    case n.name
    of "&", "1":
      var res = if n.name == "&": 1.0 else: 0.0
      for inp in n.inputs:
        let iv = resolveInp(inp).power
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
        let iv = resolveInp(inp).power
        res = res xor (iv > 0.5)
      if n.outputs.len > 0 and not n.outputs[0]:
        res = not res
      vals[n] = Value(power: res.float)

    else:
      discard

  computing.excl n
  return vals.getOrDefault(n, Value(power: 0.0))


proc draw*(plot: Plot) =
  const signalH = 1.0
  var stamps = plot.timestamps
  stamps.sort(proc(a, b: PlotTimestamp): int = cmp(a.time, b.time))
  if stamps.len == 0: return

  block mergeStamps:
    var merged: seq[PlotTimestamp]
    for stamp in stamps:
      if merged.len > 0 and merged[^1].time == stamp.time:
        merged[^1].changes.add stamp.changes
      else:
        merged.add stamp
    stamps = merged

  let firstTime = stamps[0].time
  var nodeValues: Table[Node, seq[tuple[time: float, v: Value]]]
  var accumVals: Table[Node, Value]
  for stamp in stamps:
    var skipSim: HashSet[Node]
    for change in stamp.changes:
      accumVals[change.node] = change.value
      skipSim.incl change.node

    var simVals = accumVals
    var computing = initHashSet[Node]()
    for group in plot.data:
      for node in group:
        discard simulateNode(node, simVals, accumVals, computing, skipSim)
    
    for group in plot.data:
      for node in group:
        if node in simVals:
          nodeValues.mgetOrPut(node, @[]).add (time: stamp.time, v: simVals[node])
    
    accumVals = simVals

  var changedTimes: HashSet[float]
  if plot.skipUnchangedAxes:
    for group in plot.data:
      for node in group:
        let vals = nodeValues.getOrDefault(node)
        for i in 1..<vals.len:
          if vals[i].v != vals[i-1].v:
            changedTimes.incl vals[i].time

  var y = plot.origin.y
  for groupIdx, group in plot.data:
    for nodeIdx, node in group:
      let rowY = y
      let vals = nodeValues.getOrDefault(node)

      var name = node.name
      let negate = name.startsWith("!")
      name.removePrefix("!")
      doc.add Text name:
        Position2 point2(plot.origin.x - 0.2, rowY + signalH/2)
        PositionAtRight
      if negate:
        doc.add lineSection(point2(plot.origin.x - 0.1, rowY), point2(plot.origin.x - 1, rowY)), Thickness 0.05

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
  
  for t in stamps[1..^1]:
    if not plot.skipUnchangedAxes or t.time in changedTimes:
      doc.add lineSection(
        point2(plot.origin.x + (t.time - firstTime) * plot.timeScale, plot.origin.y),
        point2(plot.origin.x + (t.time - firstTime) * plot.timeScale, y - plot.gap)
      ), plot.axiesColor
  
  when false:
    let t = plot.timestamps[^1]
    doc.add lineSection(
      point2(plot.origin.x + (t.time + 1) * plot.timeScale, plot.origin.y),
      point2(plot.origin.x + (t.time + 1) * plot.timeScale, y - plot.gap)
    ), plot.axiesColor



proc echoPlot*(plot: Plot) =
  var stamps = plot.timestamps
  stamps.sort(proc(a, b: PlotTimestamp): int = cmp(a.time, b.time))
  if stamps.len == 0: return

  block mergeStamps:
    var merged: seq[PlotTimestamp]
    for stamp in stamps:
      if merged.len > 0 and merged[^1].time == stamp.time:
        merged[^1].changes.add stamp.changes
      else:
        merged.add stamp
    stamps = merged

  var accumVals: Table[Node, Value]
  for stamp in stamps:
    var skipSim: HashSet[Node]
    for change in stamp.changes:
      accumVals[change.node] = change.value
      skipSim.incl change.node

    var simVals = accumVals
    var computing = initHashSet[Node]()
    for group in plot.data:
      for node in group:
        discard simulateNode(node, simVals, accumVals, computing, skipSim)

    var parts: seq[string]
    parts.add "t=" & stamp.time.formatFloat(ffDecimal, 2)
    for group in plot.data:
      for node in group:
        let v = simVals.getOrDefault(node)
        parts.add node.name & "=" & (if v.power > 0.5: "1" else: "0")
    echo parts.join("  ")

    accumVals = simVals


mainModule:
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

  let lines = @[
    PlacementRule Line(origin: point2(0, 3),    nodes: inputs, gap: 7),
    Line(origin: point2(4, 0),    nodes: inverted, gap: 6),
    bus(point2(8,    0), input = inputs[0],    outputs = outputs, color = color(0.6, 0, 0)),
    bus(point2(8.5,  0), input = inverted[0],  outputs = outputs, color = color(0, 0, 0)),
    bus(point2(10,   0), input = inputs[1],    outputs = outputs, color = color(0, 0.6, 0)),
    bus(point2(10.5, 0), input = inverted[1],  outputs = outputs, color = color(0, 0, 0)),
    bus(point2(12,   0), input = inputs[2],    outputs = outputs, color = color(0, 0, 0.6)),
    bus(point2(12.5, 0), input = inverted[2],  outputs = outputs, color = color(0, 0, 0)),
    Line(origin: point2(16, 0),   nodes: outputs, gap: 0),
    Line(origin: point2(20, 0),   nodes: outputNames, gap: 0, align: Inputs),
  ]

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

