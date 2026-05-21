import std/strutils
import sandbox
import electronics/schemes
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
    T_expr*: seq[Node]   ## computed T input per bit (nil = never toggles)
    placement*: seq[PlacementRule]
    n*: int
    excluded*: seq[int]


proc counterStop*(excluded: seq[int], nBits: int): CounterStop =
  template r: untyped = result
  r.n       = nBits
  r.excluded = excluded
  r.C       = Node "C"

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
    r.Q[i]  = symN("Q"  & subscript[i], (r.ttN[i], 0))
    r.nQ[i] = symN("!Q" & subscript[i], (r.ttN[i], 1))

  # Variable names for the Karnaugh map (must match lookup in the loop below)
  var varNames: seq[string]
  for i in 0..<nBits: varNames.add "q" & $i

  let tables = buildTInputTables(nBits, excluded)

  # Build combinational T-input logic from SDNF groups
  # Each T_i = OR of AND-terms derived from prime implicants
  var intermediates = newSeq[seq[Node]](nBits)  # newly created AND/OR nodes per bit
  r.T_expr = newSeq[Node](nBits)

  for i in 0..<nBits:
    let groups = findSdnf(tables[i], varNames)
    var termNodes: seq[Node]

    for grp in groups:
      if grp.terms.len == 0:
        # Tautology: T = 1 always — use OR(Q, !Q)
        let c1 = Node(kind: BoxN, name: "1",
          inputs: @[Port(n: r.Q[i], port: 0), Port(n: r.nQ[i], port: 0)],
          outputs: @[true])
        intermediates[i].add c1
        termNodes.add c1
        continue

      var lits: seq[Port]
      for term in grp.terms:
        let neg  = term.startsWith("!")
        let base = if neg: term[1..^1] else: term
        let idx  = varNames.find(base)
        lits.add Port(n: if neg: r.nQ[idx] else: r.Q[idx], port: 0)

      if lits.len == 1:
        termNodes.add lits[0].n   # single literal — reuse existing node
      else:
        let a = Node(kind: BoxN, name: "&", inputs: lits, outputs: @[true])
        intermediates[i].add a
        termNodes.add a

    if termNodes.len == 0:
      r.T_expr[i] = nil
    elif termNodes.len == 1:
      r.T_expr[i] = termNodes[0]
    else:
      var orPorts: seq[Port]
      for t in termNodes: orPorts.add Port(n: t, port: 0)
      let o = Node(kind: BoxN, name: "1", inputs: orPorts, outputs: @[true])
      intermediates[i].add o
      r.T_expr[i] = o

  # Wire T inputs and clock into each trigger
  let zeroNode = Node(kind: SymN, name: "0")
  for i in 0..<nBits:
    r.ttN[i].inputs.add(if r.T_expr[i] != nil: r.T_expr[i] else: zeroNode)
    r.ttN[i].inputs.add r.C

  # Placement — one Line per logic layer, no loopback paths
  const stepX = 14.0
  var rules: seq[PlacementRule]
  let nf = nBits.float

  rules.add Line(origin: point2(0, nf * 2 + 4), nodes: @[r.C])

  for i in 0..<nBits:
    let x = i.float * stepX
    if intermediates[i].len > 0:
      rules.add Line(origin: point2(x, 0), nodes: intermediates[i])
    rules.add Line(origin: point2(x + 6, 0), nodes: @[r.ttN[i]])

  rules.add Line(origin: point2(nf * stepX + 6, 0), nodes: r.Q,  align: Inputs)
  rules.add Line(origin: point2(nf * stepX + 6, -4), nodes: r.nQ, align: Inputs)

  for i in 0..<nBits:
    rules.add bus(point2(i.float * stepX + 6, -2), r.C, @[r.ttN[i]])

  r.placement = rules


proc startup*(c: CounterStop, startState: int = -1): seq[ValChange] =
  var s0 = startState
  if s0 < 0:
    s0 = 0
    while s0 in c.excluded: inc s0
  result.add setVal(c.C, 0)
  for i in 0..<c.n:
    let bit = Value((s0 shr i) and 1)
    result.add setVal(c.tt[i].ms.t1.T[0], bit)
    result.add setVal(c.tt[i].ms.t1.T[1], not bit)
    result.add setVal(c.tt[i].ms.t2.T[0], bit)
    result.add setVal(c.tt[i].ms.t2.T[1], not bit)


mainModule:
  let excluded = @[0, 1, 10, 12]
  let c = counterStop(excluded, 4)

  placeComponents(c.placement)
  drawComponents()

  var timestamps = @[PlotTimestamp(time: 0, changes: startup(c))]

  var validStates: seq[int]
  for s in 0..<(1 shl c.n):
    if s notin excluded: validStates.add s

  for t in 0..<(validStates.len + 3):
    let base = 1.0 + t.float * 3.0
    timestamps.add PlotTimestamp(time: base,        changes: @[setVal(c.C, 1)])
    timestamps.add PlotTimestamp(time: base + 0.05)
    timestamps.add PlotTimestamp(time: base + 1.5,  changes: @[setVal(c.C, 0)])
    timestamps.add PlotTimestamp(time: base + 1.55)

  draw Plot(
    data:              @[@[c.C], c.Q],
    gap:               0.2,
    groupGap:          1,
    timeScale:         1.4,
    timestamps:        timestamps,
    origin:            point2(0, 20),
    skipUnchangedAxes: true,
  )
