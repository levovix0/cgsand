import std/[strutils, algorithm]
import sandbox
import electronics/schemes
from pkg/bumpy import Rect
import ./trigger_t
import ./trigger_ms
import ../logic/carnot_map


type
  CounterStop* = object
    C*: Node
    Q*: seq[Node]
    nQ*: seq[Node]
    tt*: seq[TTrigger]
    ttN*: seq[Node]
    T_expr*: seq[Node]
    intermediates*: seq[seq[Node]]
    n*: int
    excluded*: seq[int]


proc counterStop*(excluded: seq[int], nBits: int): CounterStop =
  template r: untyped = result
  r.n        = nBits
  r.excluded = excluded
  r.C        = Node "C"

  r.tt  = newSeq[TTrigger](nBits)
  r.ttN = newSeq[Node](nBits)
  for i in 0..<nBits:
    r.tt[i]  = tTrigger()
    r.ttN[i] = pack(r.tt[i].I, r.tt[i].O).packN("T" & subscript[i])
    r.ttN[i].pack.outputs[0].name = "Q"  & subscript[i]
    r.ttN[i].pack.outputs[1].name = "!Q" & subscript[i]

  r.Q  = newSeq[Node](nBits)
  r.nQ = newSeq[Node](nBits)
  for i in 0..<nBits:
    r.Q[i]  = symN("Q"  & subscript[i], r.ttN[i][0])
    r.nQ[i] = symN("!Q" & subscript[i], r.ttN[i][1])

  var varNames: seq[string]
  for i in 0..<nBits: varNames.add "q" & $i

  let tables = buildTInputTables(nBits, excluded)

  r.intermediates = newSeq[seq[Node]](nBits)
  r.T_expr = newSeq[Node](nBits)

  for i in 0..<nBits:
    let groups = findSdnf(tables[i], varNames)
    var termNodes: seq[Node]

    for grp in groups:
      if grp.terms.len == 0:
        let c1 = Node(kind: BoxN, name: "1",
          inputs: @[Port(n: r.Q[i], port: 0), Port(n: r.nQ[i], port: 0)],
          outputs: @[true])
        r.intermediates[i].add c1
        termNodes.add c1
        continue

      var lits: seq[Port]
      for term in grp.terms:
        let neg  = term.startsWith("!")
        let base = if neg: term[1..^1] else: term
        let idx  = varNames.high - varNames.find(base)
        lits.add Port(n: if neg: r.nQ[idx] else: r.Q[idx], port: 0)

      if lits.len == 1:
        termNodes.add lits[0].n
      else:
        let a = Node(kind: BoxN, name: "&", inputs: lits, outputs: @[true])
        r.intermediates[i].add a
        termNodes.add a

    if termNodes.len == 0:
      r.T_expr[i] = nil
    elif termNodes.len == 1:
      r.T_expr[i] = termNodes[0]
    else:
      var orPorts: seq[Port]
      for t in termNodes: orPorts.add Port(n: t, port: 0)
      let o = Node(kind: BoxN, name: "1", inputs: orPorts, outputs: @[true])
      r.intermediates[i].add o
      r.T_expr[i] = o

  let zeroNode = Node(kind: SymN, name: "0")
  for i in 0..<nBits:
    r.ttN[i].inputs.add(if r.T_expr[i] != nil: r.T_expr[i] else: zeroNode)
    r.ttN[i].inputs.add r.C


proc place*(c: CounterStop): seq[Rect] =
  const offsetX = 8.0
  const stepX = 26.0
  const stepY = 4.0
  let nf = c.n.float

  var baseRules: seq[PlacementRule]
  baseRules.add Line(origin: point2(0, nf * stepY + 8), nodes: @[c.C])

  for i in 0..<c.n:
    let x = i.float * stepX + offsetX
    let y = i.float * stepY
    if c.intermediates[i].len > 0:
      baseRules.add Line(origin: point2(x - 4, y), nodes: c.intermediates[i][0..^2])
      baseRules.add Line(origin: point2(x + 2, y), nodes: @[c.intermediates[i][^1]])
    baseRules.add Line(origin: point2(x + 6, y), nodes: @[c.ttN[i]])

  baseRules.add Line(origin: point2(nf * stepX + 8, 0), nodes: c.Q,  align: Inputs)
  baseRules.add Line(origin: point2(nf * stepX + 2, 0), nodes: c.nQ, align: Inputs)

  for i in 0..<c.n:
    baseRules.add bus(point2(i.float * stepX + offsetX + 5.5, -2), c.C, @[c.ttN[i]])

  let rects = placeNodes(baseRules)

  result = newSeq[Rect](c.n)
  for i in 0..<c.n:
    result[i] = rects[c.ttN[i]]

  var connRules: seq[PlacementRule]
  for i in 0..<c.n:
    for j in 0..<c.intermediates[i].len:
      let andNode = c.intermediates[i][j]
      for pIdx in 0..<andNode.inputs.len:
        let srcNode = andNode.inputs[pIdx].n
        for k in 0..<c.n:
          let isQ = srcNode == c.Q[k]
          if not isQ and srcNode != c.nQ[k]: continue
          let qNode  = if isQ: c.Q[k] else: c.nQ[k]
          let srcX   = rects[qNode].x + rects[qNode].w + k.float * 0.8 + 1
          let laneY  = if isQ: -3.0 - k.float * 0.5
                       else:   -3.0 - nf * 0.5 - 1.0 - k.float * 0.5
          let dstX   = rects[andNode].x - 1.5 - j.float * 1.5 - pIdx.float * 0.2
          connRules.add bus([point2(srcX, rects[qNode].y), point2(srcX, laneY), point2(dstX, laneY)], srcNode, @[andNode])
          break

  for i in 0..<c.n:
    if c.intermediates.len > 1:
      let orNode = c.intermediates[i][^1]
      if orNode.name != "1": continue
      for pIdx, port in orNode.inputs:
        if port.n.name != "&": continue
        connRules.add bus(point2(rects[orNode].x - 2 + pIdx.float * 0.2, 0), port.n, @[orNode])

  placeConnections(baseRules & connRules, rects)


proc startup*(c: CounterStop, startState: int = -1): seq[ValChange] =
  var s0 = startState
  if s0 < 0:
    s0 = 0
    while s0 in c.excluded: inc s0
  result.add setVal(c.C, 0)
  for i in 0..<c.n:
    let bit = bitVal(s0, i)
    result.add setVal(c.tt[i].ms.t1.T[0], bit)
    result.add setVal(c.tt[i].ms.t1.T[1], not bit)
    result.add setVal(c.tt[i].ms.t2.T[0], bit)
    result.add setVal(c.tt[i].ms.t2.T[1], not bit)


mainModule:
  let excluded = @[0, 1, 10, 12]
  let c = counterStop(excluded, 4)

  let placement = place(c)
  drawComponents()

  var validStates: seq[int]
  for s in 0..<(1 shl c.n):
    if s notin excluded: validStates.add s

  var timestamps = @[PlotTimestamp(time: 0, changes: startup(c))]
  timestamps.add clockPulses(c.C, validStates.len + 3, startTime = 1.0, halfPeriod = 1.5, settle = 0.05)

  draw Plot(
    data:              @[@[c.C], c.Q],
    gap:               0.2,
    groupGap:          1,
    timeScale:         1,
    timestamps:        timestamps,
    origin:            point2(0, 30),
    skipUnchangedAxes: true,
  )

  var varNames: seq[string]
  for i in 0..<c.n: varNames.add "Q" & subscript[i]
  varNames = varNames.reversed

  let tables = buildTInputTables(c.n, c.excluded)

  let mainDoc = doc
  let mainGlobals = globals

  for i in 0..<c.n:
    var carnotWorld = World()
    withDocument carnotWorld:
      let globals = doc.spawn CanvasSettings()
      setCarnotMapGlobals(globals)
      doc[globals, Foreground] = mainDoc[mainGlobals, Foreground]

      doc.drawCarnotMap(varNames, tables[i])

      let sdnf = findSdnf(tables[i], varNames)
      doc.drawKarnaughGroups(sdnf, varNames)
      doc.drawSdnf(sdnf, point2(0, -2.5))

    let b = worldBounds(carnotWorld)
    let tr = placement[i]
    doc.add SubWorld carnotWorld:
      Position2 point2(tr.x - b.min.x, tr.y + tr.h - b.min.y)
      Transform3 scale(vec3(0.5, 0.5, 0.5))
