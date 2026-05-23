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

  HOffset* = object
    left*: float
    right*: float

  LoopbackPath* = object
    output*: Port
    input*: Port
    offset*: float
    hOffset*: HOffset
    color*: Color = color(0, 0, 0)

  PlacementRuleKind* = enum
    LineR
    BusR
    LoopbackPathR

  PlacementRule* = object
    case kind*: PlacementRuleKind
    of LineR: line*: Line
    of BusR: bus*: Bus
    of LoopbackPathR: loopbackPath*: LoopbackPath

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

  SchemeTheme* = object
    background*: Color = color(1, 1, 1)
    foreground*: Color = color(0, 0, 0)
    errorColor*: Color = color(1, 0, 0)
    overlapErrorColor*: Color = color(0, 0, 1)
    canvasMargin*: float32 = 1.0
    baseFontSize*: float32 = 1.0
    branchRadius*: float32 = 0.1
    negationCircleRadius*: float32 = 0.1
    negationLineThickness*: float32 = 0.05
    errorCircleRadius*: float32 = 0.15
    errorConnectionThickness*: float32 = 0.15
    plotSignalHeight*: float32 = 1.0
    plotValueFontSize*: float32 = 0.5


let darkTheme* = cache[].mgetOrPut(DarkTheme, false)

var schemeTheme* = SchemeTheme()
if darkTheme:
  schemeTheme = SchemeTheme(
    background:               parseHtmlHex "#202020",
    foreground:               color(0.75, 0.75, 0.8),
    errorColor:               color(1, 0.4, 0.4),
    overlapErrorColor:        color(0.4, 0.4, 1),
    canvasMargin:             1.0,
    baseFontSize:             1.0,
    branchRadius:             0.1,
    negationCircleRadius:     0.1,
    negationLineThickness:    0.05,
    errorCircleRadius:        0.15,
    errorConnectionThickness: 0.15,
    plotSignalHeight:         1.0,
    plotValueFontSize:        0.5,
  )

const Eps = 1e-4
const subscript* = ["₀", "₁", "₂", "₃", "₄", "₅", "₆", "₇", "₈", "₉"]


proc setElectronicsSchemesGlobals*(globals: EntityId) =
  doc.update globals: add OwnerModule "electronics/schemes"
  
  # todo: ecs bug: not (i == -1)` component was not found in destination archetype [AssertionDefect]
  # doc.update globals:
  #   add CanvasSettings(autoSize: true, margin: vec2(schemeTheme.canvasMargin), mmScale: 2.5)
  #   add AxisYDown
  #   add FontSize schemeTheme.baseFontSize
  #   add Background schemeTheme.background
  #   add Foreground schemeTheme.foreground

  doc.update globals: add CanvasSettings(autoSize: true, margin: vec2(schemeTheme.canvasMargin), mmScale: 2.5)
  doc.update globals: add AxisYDown
  doc.update globals: add FontSize schemeTheme.baseFontSize
  doc.update globals: add Background schemeTheme.background
  doc.update globals: add Foreground schemeTheme.foreground

if not doc.hasComponent(globals, OwnerModule):
  setElectronicsSchemesGlobals(globals)



converter toNode*(name: string): Node = Node(kind: SymN, name: name)

converter toPort*(name: string): Port = Port(n: Node name, port: 0)
converter toPort*(n: Node): Port = Port(n: n, port: 0)
converter toPort*(n: (Node, int)): Port = Port(n: n[0], port: n[1])

proc delayed*(n: Node, port = 0): Port = Port(n: n, port: port, delayed: true)

proc `[]`*(n: Node, port: int): Port = Port(n: n, port: port)

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


converter toHOffset*(v: float): HOffset = HOffset(left: -v, right: v)
converter toHOffset*(v: (float, float)): HOffset = HOffset(left: v[0], right: v[1])

converter toPlacementRule*(l: Line): PlacementRule = PlacementRule(kind: LineR, line: l)
converter toPlacementRule*(b: Bus): PlacementRule = PlacementRule(kind: BusR, bus: b)
converter toPlacementRule*(lp: LoopbackPath): PlacementRule = PlacementRule(kind: LoopbackPathR, loopbackPath: lp)

proc loopbackPath*(output: Port, input: Port, offset: float = 0, hOffset: HOffset = 0.0, color = schemeTheme.foreground): LoopbackPath =
  LoopbackPath(output: output, input: input, offset: offset, hOffset: hOffset, color: color)

proc loopbackPath*(output: Port, offset: float = 0, hOffset: HOffset = 0.0, color = schemeTheme.foreground): LoopbackPath =
  LoopbackPath(output: output.n.inputs[output.port], input: output, offset: offset, hOffset: hOffset, color: color)

proc bus*(path: openArray[Point2], input: Port, outputs: openArray[Node], color = schemeTheme.foreground): Bus =
  Bus(path: @path, input: input, outputs: @outputs, color: color)

proc bus*(origin: Point2, input: Port, outputs: openArray[Node], color = schemeTheme.foreground): Bus =
  Bus(origin: origin, input: input, outputs: @outputs, color: color)

proc buses*(originX, originY, stepX: float, inputs: openArray[Node], outputs: openArray[Node], color = schemeTheme.foreground): seq[PlacementRule] =
  for i, inp in inputs:
    result.add bus(point2(originX + i.float * stepX, originY), input = inp, outputs = outputs, color = color)


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
    of LoopbackPathR:
      discard



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

proc bitVal*(x, bit: int): Value = Value(power: float((x shr bit) and 1))

proc clockPulse*(clk: Node, atTime: float, halfPeriod = 0.5, settle = 0.0): seq[PlotTimestamp] =
  result.add PlotTimestamp(time: atTime, changes: @[setVal(clk, 1)])
  if settle > 0: result.add PlotTimestamp(time: atTime + settle)
  result.add PlotTimestamp(time: atTime + halfPeriod, changes: @[setVal(clk, 0)])
  if settle > 0: result.add PlotTimestamp(time: atTime + halfPeriod + settle)

proc clockPulses*(clk: Node, n: int, startTime = 1.0, halfPeriod = 0.5, settle = 0.0): seq[PlotTimestamp] =
  for i in 0..<n:
    result.add clockPulse(clk, startTime + i.float * halfPeriod * 2, halfPeriod, settle)

proc exhaustiveInputStamps*(inputs: openArray[Node], startTime = 0.0, step = 1.0): seq[PlotTimestamp] =
  let count = 1 shl inputs.len
  for i in 0..<count:
    var changes: seq[ValChange]
    for bit in 0..<inputs.len:
      changes.add setVal(inputs[bit], bitVal(i, bit))
    result.add PlotTimestamp(time: startTime + i.float * step, changes: changes)



proc segmentIntersectsRectBorder(a, b: Point2, r: Rect): bool =
  let seg = lineSection(a, b)
  hasIntersectedSegments(seg, lineSection(point2(r.x,       r.y      ), point2(r.x + r.w, r.y      ))) or
  hasIntersectedSegments(seg, lineSection(point2(r.x + r.w, r.y      ), point2(r.x + r.w, r.y + r.h))) or
  hasIntersectedSegments(seg, lineSection(point2(r.x,       r.y + r.h), point2(r.x + r.w, r.y + r.h))) or
  hasIntersectedSegments(seg, lineSection(point2(r.x,       r.y      ), point2(r.x,       r.y + r.h)))


proc segmentPassesThroughRect(a, b: Point2, r: Rect): bool =
  # Returns true if the open segment interior crosses the shrunk rect interior.
  # The margin excludes endpoint-on-border touches (port connections).
  const margin = 0.01f32
  let xMin = r.x + margin
  let xMax = r.x + r.w - margin
  let yMin = r.y + margin
  let yMax = r.y + r.h - margin
  if xMin >= xMax or yMin >= yMax: return false
  var tMin = 0f32
  var tMax = 1f32
  let dx = b.x - a.x
  let dy = b.y - a.y
  if abs(dx) < 1e-9f32:
    if a.x < xMin or a.x > xMax: return false
  else:
    let tLeft  = (xMin - a.x) / dx
    let tRight = (xMax - a.x) / dx
    if dx > 0:
      tMin = max(tMin, tLeft);  tMax = min(tMax, tRight)
    else:
      tMin = max(tMin, tRight); tMax = min(tMax, tLeft)
  if tMin >= tMax: return false
  if abs(dy) < 1e-9f32:
    if a.y < yMin or a.y > yMax: return false
  else:
    let tBot = (yMin - a.y) / dy
    let tTop = (yMax - a.y) / dy
    if dy > 0:
      tMin = max(tMin, tBot);  tMax = min(tMax, tTop)
    else:
      tMin = max(tMin, tTop); tMax = min(tMax, tBot)
  return tMin < tMax


const overlapPalette = [
  color(0.85f32, 0.15f32, 0.15f32),
  color(0.15f32, 0.60f32, 0.15f32),
  color(0.15f32, 0.15f32, 0.85f32),
  color(0.85f32, 0.50f32, 0.00f32),
  color(0.60f32, 0.10f32, 0.75f32),
  color(0.00f32, 0.60f32, 0.65f32),
  color(0.70f32, 0.65f32, 0.00f32),
  color(0.80f32, 0.00f32, 0.50f32),
]

proc segmentsOverlap(a1, a2, b1, b2: Point2): bool =
  const eps = 1e-3f32
  if abs(a1.y - a2.y) < eps and abs(b1.y - b2.y) < eps and abs(a1.y - b1.y) < eps:
    let aMin = min(a1.x, a2.x); let aMax = max(a1.x, a2.x)
    let bMin = min(b1.x, b2.x); let bMax = max(b1.x, b2.x)
    return min(aMax, bMax) - max(aMin, bMin) > eps
  if abs(a1.x - a2.x) < eps and abs(b1.x - b2.x) < eps and abs(a1.x - b1.x) < eps:
    let aMin = min(a1.y, a2.y); let aMax = max(a1.y, a2.y)
    let bMin = min(b1.y, b2.y); let bMax = max(b1.y, b2.y)
    return min(aMax, bMax) - max(aMin, bMin) > eps
  return false


proc placeNodes*(rules: seq[PlacementRule]): Table[Node, Rect] =
  # Build successor table needed for Outputs alignment
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
    of LoopbackPathR:
      let lp = rule.loopbackPath
      successors.mgetOrPut(lp.output.n, @[]).add (lp.input.n, lp.input.port)

  # Pass 2a: place nodes from Lines with no alignment
  for rule in rules:
    if rule.kind == LineR and rule.line.align == None:
      let elem = rule.line
      var pos = elem.origin
      for node in elem.nodes:
        let sz = nodeSize(node)
        let r = rect(pos.x.float32, pos.y.float32, sz.x.float32, sz.y.float32)
        pos.y += sz.y + elem.gap.float
        result[node] = r
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
            if result.hasKey(inp0.n):
              let connectY = outputPortY(inp0.n, result[inp0.n], inp0.port)
              r = rect(pos.x.float32, connectY - inputPortY(node, zeroRect, 0), sz.x.float32, sz.y.float32)
              positioned = true
        of Outputs:
          if successors.hasKey(node):
            for succ in successors[node]:
              if succ.n in result:
                let targetY = inputPortY(succ.n, result[succ.n], succ.port)
                r = rect(pos.x.float32, targetY - outputPortY(node, zeroRect, 0), sz.x.float32, sz.y.float32)
                positioned = true
                break
        of None:
          discard

        if not positioned:
          pos.y += sz.y + elem.gap.float

        result[node] = r
        doc.add node, r


proc placeConnections*(rules: seq[PlacementRule], nodeRects: Table[Node, Rect]) =
  type ConnSource = tuple[n: pointer, port: int]
  var allConns: seq[tuple[pts: Connection, color: Color, startsFromElement: bool, eid: EntityId, source: ConnSource]]

  type ConnKey = tuple[n: pointer, port: int]
  var busHandled = initHashSet[ConnKey]()
  var handledPorts = initHashSet[ConnKey]()

  # Pass 1: collect which (node, portIdx) pairs are connected via buses or loopbacks
  for rule in rules:
    if rule.kind == BusR:
      let elem = rule.bus
      for outNode in elem.outputs:
        for portIdx, inp in outNode.inputs:
          if inp.n == elem.input.n and inp.port == elem.input.port:
            let key = (cast[pointer](outNode), portIdx)
            busHandled.incl key
            handledPorts.incl key
    elif rule.kind == LoopbackPathR:
      let elem = rule.loopbackPath
      let inNode = elem.input.n
      for portIdx, inp in inNode.inputs:
        if inp.n == elem.output.n and inp.port == elem.output.port:
          let key = (cast[pointer](inNode), portIdx)
          busHandled.incl key
          handledPorts.incl key

  var lineNodes = initHashSet[pointer]()
  for rule in rules:
    if rule.kind == LineR:
      for node in rule.line.nodes:
        lineNodes.incl cast[pointer](node)

  # Pass 3: place Connection and collect for branch detection
  for rule in rules:
    case rule.kind
    of LoopbackPathR: discard
    of LineR:
      let elem {.cursor.} = rule.line
      for node in elem.nodes:
        let r = nodeRects[node]
        for portIdx, inp in node.inputs:
          if (cast[pointer](node), portIdx) notin busHandled and inp.n in nodeRects:
            handledPorts.incl (cast[pointer](node), portIdx)
            let inRect = nodeRects[inp.n]
            if node.height != 0 and inp.n.outputs.len == 1:
              let fromY = outputPortY(inp.n, inRect, inp.port)
              let pts = Connection(@[point2(inRect.x + inRect.w, fromY), point2(r.x, fromY)])
              let eid = doc.spawn(pts)
              allConns.add (pts, schemeTheme.foreground, true, eid, (cast[pointer](inp.n), inp.port))
            else:
              let fromY = outputPortY(inp.n, inRect, inp.port)
              let toY = inputPortY(node, r, portIdx)
              let p1 = point2(inRect.x + inRect.w, fromY)
              let p2 = point2(r.x, toY)
              if abs(fromY - toY) < Eps:
                let pts = Connection(@[p1, p2])
                let eid = doc.spawn(pts)
                allConns.add (pts, schemeTheme.foreground, true, eid, (cast[pointer](inp.n), inp.port))
              else:
                let midX = (p1.x + p2.x) / 2.0
                let pts = Connection(@[p1, point2(midX, fromY), point2(midX, toY), p2])
                let eid = doc.spawn(pts)
                allConns.add (pts, schemeTheme.foreground, true, eid, (cast[pointer](inp.n), inp.port))

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

          let busSource: ConnSource = (cast[pointer](inNode), inPort)

          let lead = Connection(leadPts)
          let leadEid = doc.spawn(lead, elem.color)
          allConns.add (lead, elem.color, true, leadEid, busSource)

          let vertBus = Connection(@[point2(busX, minBusY), point2(busX, maxBusY)])
          let vertEid = doc.spawn(vertBus, elem.color)
          allConns.add (vertBus, elem.color, false, vertEid, busSource)

          for bc in busConns:
            let outRect = nodeRects[bc.n]
            let portY = inputPortY(bc.n, outRect, bc.port)
            let stub = Connection(@[point2(busX, portY), point2(outRect.x, portY)])
            let stubEid = doc.spawn(stub, elem.color)
            allConns.add (stub, elem.color, false, stubEid, busSource)

  # Pass 3b: draw LoopbackPath connections
  for rule in rules:
    if rule.kind == LoopbackPathR:
      let elem = rule.loopbackPath
      let outNode = elem.output.n
      let inNode = elem.input.n
      if outNode notin nodeRects or inNode notin nodeRects: continue

      let outRect = nodeRects[outNode]
      let inRect = nodeRects[inNode]
      let outY = outputPortY(outNode, outRect, elem.output.port)
      let inY = inputPortY(inNode, inRect, elem.input.port)

      let topBound = min(outRect.y, inRect.y)
      let bottomBound = max(outRect.y + outRect.h, inRect.y + inRect.h)

      let midY: float32 =
        if elem.offset == 0:
          if outY - topBound < bottomBound - outY:
            topBound - 1
          else:
            bottomBound + 1
        elif elem.offset > 0:
          bottomBound + elem.offset.float32
        else:
          topBound + elem.offset.float32

      let (rightX, leftX) =
        if inRect.x > outRect.x:
          # input is to the right of output: route right-stub → up/down → right-long → down/up → port
          (outRect.x + outRect.w + 1.float32 + elem.hOffset.right.float32,
           inRect.x - 1.float32 + elem.hOffset.left.float32)
        else:
          # loopback: input is to the left; wrap around both nodes
          (max(outRect.x + outRect.w, inRect.x + inRect.w) + 1.float32 + elem.hOffset.right.float32,
           min(outRect.x, inRect.x) - 1.float32 + elem.hOffset.left.float32)

      let pts = Connection(@[
        point2(outRect.x + outRect.w, outY),
        point2(rightX, outY),
        point2(rightX, midY),
        point2(leftX,  midY),
        point2(leftX,  inY),
        point2(inRect.x, inY),
      ])

      let connected = elem.input.port < inNode.inputs.len and
                      inNode.inputs[elem.input.port].n == outNode and
                      inNode.inputs[elem.input.port].port == elem.output.port
      var eid: EntityId
      if connected:
        eid = doc.spawn(pts, elem.color)
      else:
        eid = doc.spawn(pts, schemeTheme.errorColor, Thickness schemeTheme.errorConnectionThickness)
      allConns.add (pts, (if connected: elem.color else: schemeTheme.errorColor), true, eid, (cast[pointer](elem.output.n), elem.output.port))

  # Pass 3c: draw error markers for ports with real connections not covered by any rule
  for node, r in nodeRects:
    for portIdx, inp in node.inputs:
      if (cast[pointer](node) notin lineNodes) == (cast[pointer](inp.n) notin lineNodes): continue
      if (cast[pointer](node), portIdx) in handledPorts: continue

      if cast[pointer](node) in lineNodes:
        let px = r.x
        let py = inputPortY(node, r, portIdx)
        doc.add circle(center = point2(px, py), radius = schemeTheme.errorCircleRadius):
          Foreground schemeTheme.errorColor
          Background schemeTheme.errorColor

      if cast[pointer](inp.n) in lineNodes:
        let inRect = nodeRects[inp.n]
        let px = inRect.x + inRect.w
        let py = outputPortY(inp.n, inRect, inp.port)
        doc.add circle(center = point2(px, py), radius = schemeTheme.errorCircleRadius):
          Foreground schemeTheme.errorColor
          Background schemeTheme.errorColor

  # todo: check that the Branch points are connecting diffirent signals
  # Pass 4: if 2+ Connection start from the same point, add a Branch
  var starters: seq[tuple[p: Point2, dir: Vec2, count: int, color: Color]]
  for i, conn in allConns:
    if conn.pts.len < 2: continue
    block hasStarter:
      for starter in starters.mitems:
        if starter.p ~== conn.pts[0] and not isParallel(conn.pts[1] - conn.pts[0], starter.dir):
          inc starter.count
          if starter.color == schemeTheme.foreground:
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

  # Pass 6: redraw connections that pass through any node rect in bold blue
  for conn in allConns:
    var passesThrough = false
    for i in 0 ..< conn.pts.high:
      if passesThrough: break
      for n, nodeRect in nodeRects:
        if segmentPassesThroughRect(conn.pts[i], conn.pts[i + 1], nodeRect) or
           segmentIntersectsRectBorder(conn.pts[i], conn.pts[i + 1], nodeRect):
          passesThrough = true
          break
    if passesThrough:
      doc.update conn.eid: add schemeTheme.overlapErrorColor
      doc.update conn.eid: add Thickness schemeTheme.errorConnectionThickness

  # Pass 7: highlight overlapping segments from different sources with palette colors
  var overlapSources: seq[ConnSource]
  for i in 0 ..< allConns.len:
    for j in i+1 ..< allConns.len:
      if allConns[i].source == allConns[j].source: continue
      block checkPair:
        let pi = allConns[i].pts
        let pj = allConns[j].pts
        for si in 0 ..< pi.high:
          for sj in 0 ..< pj.high:
            if segmentsOverlap(pi[si], pi[si+1], pj[sj], pj[sj+1]):
              if allConns[i].source notin overlapSources:
                overlapSources.add allConns[i].source
              if allConns[j].source notin overlapSources:
                overlapSources.add allConns[j].source
              break checkPair

  if overlapSources.len > 0:
    for conn in allConns:
      let idx = overlapSources.find(conn.source)
      if idx >= 0:
        let c = overlapPalette[idx mod overlapPalette.len]
        doc.update conn.eid: add Color c


proc placeComponents*(rules: seq[PlacementRule]) =
  placeConnections(rules, placeNodes(rules))


proc drawRect(r: Rect) =
  doc.add lineSection(point2(r.x, r.y), point2(r.x + r.w, r.y))
  doc.add lineSection(point2(r.x + r.w, r.y), point2(r.x + r.w, r.y + r.h))
  doc.add lineSection(point2(r.x + r.w, r.y + r.h), point2(r.x, r.y + r.h))
  doc.add lineSection(point2(r.x, r.y + r.h), point2(r.x, r.y))



proc drawComponents* =
  doc.forEach (c: Connection, color: Color||schemeTheme.foreground, thickness: opt Thickness):
    for i in 0..<(c.len-1):
      if has Thickness:
        doc.add lineSection(c[i], c[i + 1]), Thickness thickness, color
      else:
        doc.add lineSection(c[i], c[i + 1]), color

  doc.forEach (b: Branch, color: Color||schemeTheme.foreground):
    doc.add circle(center = b.Point2, radius = schemeTheme.branchRadius):
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
          doc.add circle(center = p, radius = schemeTheme.negationCircleRadius):
            Foreground schemeTheme.foreground
            Background schemeTheme.background
    
    of SymN:
      var name = n.name
      let negate = name.startsWith("!")
      name.removePrefix("!")

      doc.add lineSection(point2(r.x, r.y), point2(r.x + r.w, r.y))
      doc.add Text name:
        Position2 point2(r.x + r.w/2, r.y - 0.2)
        PositionAtBottom
      
      if negate:
        doc.add lineSection(point2(r.x, r.y - r.h - 0.1), point2(r.x + r.w, r.y - r.h - 0.1)), Thickness schemeTheme.negationLineThickness

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
          doc.add lineSection(textPos + vec2(-0.5, -0.5), textPos + vec2(0.5, -0.5)), Thickness schemeTheme.negationLineThickness

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
          doc.add lineSection(textPos + vec2(-0.5, -0.5), textPos + vec2(0.5, -0.5)), Thickness schemeTheme.negationLineThickness
          doc.add circle(point2(r.x + 6, y + outH/2), radius = schemeTheme.negationCircleRadius):
            Foreground schemeTheme.foreground
            Background schemeTheme.background


proc simulateNode(n: Node, vals: var Table[Node, Value], prevVals: Table[Node, Value], computing: var HashSet[Node], skipSim: HashSet[Node], computed: var HashSet[Node], cacheable: bool = true): Value =
  if n in computed: return vals[n]
  if n in vals and (n.inputs.len == 0 or n in skipSim): return vals[n]
  if n in computing:  # force delay
    return prevVals.getOrDefault(n, Value(power: 0.0))
  if n.inputs.len == 0:
    vals[n] = Value(power: 0.0)
    if cacheable: computed.incl n
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
        discard simulateNode(inp.n, vals, prevVals, computing, skipSim, computed, cacheable)
        if inp.port < inp.n.pack.outputs.len:
          # If the PackN is currently in a computing cycle, its internal nodes
          # are traversed with stale pack inputs — don't cache those results.
          let c = cacheable and not (inp.n in computing)
          simulateNode(inp.n.pack.outputs[inp.port], vals, prevVals, computing, skipSim, computed, c)
        else:
          Value(power: 0.0)
      else:
        simulateNode(inp.n, vals, prevVals, computing, skipSim, computed, cacheable)

  case n.kind
  of SymN:
    vals[n] = resolveInp(n.inputs[0])

  of PackN:
    if n.pack != nil:
      for i, inpNode in n.pack.inputs:
        if i < n.inputs.len:
          vals[inpNode] = resolveInp(n.inputs[i])
      if n.pack.outputs.len > 0:
        vals[n] = simulateNode(n.pack.outputs[0], vals, prevVals, computing, skipSim, computed, cacheable)
        for i in 1..<n.pack.outputs.len:
          discard simulateNode(n.pack.outputs[i], vals, prevVals, computing, skipSim, computed, cacheable)
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

  if cacheable: computed.incl n
  computing.excl n
  return vals.getOrDefault(n, Value(power: 0.0))


proc draw*(plot: Plot) =
  let signalH = schemeTheme.plotSignalHeight
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
    var computed = initHashSet[Node]()
    for group in plot.data:
      for node in group:
        discard simulateNode(node, simVals, accumVals, computing, skipSim, computed)

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
              FontSize schemeTheme.plotValueFontSize
          else:
            doc.add Text valStr:
              Position2 point2(x1 + 0.2, rowY + signalH - 0.2)
              PositionAtBottomLeft
              FontSize schemeTheme.plotValueFontSize

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
    var computed = initHashSet[Node]()
    for group in plot.data:
      for node in group:
        discard simulateNode(node, simVals, accumVals, computing, skipSim, computed)

    var parts: seq[string]
    parts.add "t=" & stamp.time.formatFloat(ffDecimal, 2)
    for group in plot.data:
      for node in group:
        let v = simVals.getOrDefault(node)
        parts.add node.name & "=" & (if v.power > 0.5: "1" else: "0")
    echo parts.join("  ")

    accumVals = simVals


mainModule:
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

