import std/strutils
import sandbox
import electronics/schemes
import ./trigger_ms


type
  CounterModDown* = object
    C*: Node
    Q*: seq[Node]
    ms*: seq[MsTrigger]
    msN*: seq[Node]
    borrow*: seq[Node]   ## borrow[i] = !Q₀·!Q₁·…·!Qᵢ (fires when lower bits all 0)
    reset*: Node          ## nil when modulus is a power of 2 (natural rollover)
    placement*: seq[PlacementRule]
    modulus*: int


proc counterModDown*(modulus: int): CounterModDown =
  ## Synchronous binary down counter with auto-reload at `modulus`.
  ## Counts: modulus-1, modulus-2, …, 1, 0, modulus-1, …
  ## Built from MS-triggers via packN.
  template r: untyped = result
  assert modulus >= 2
  r.modulus = modulus

  var n = 1
  while (1 shl n) < modulus:
    inc n

  r.C = Node "C"

  r.ms  = newSeq[MsTrigger](n)
  r.msN = newSeq[Node](n)
  for i in 0..<n:
    r.ms[i]  = msTrigger()
    r.msN[i] = r.ms[i].msPack.packN("MS" & subscript[i])

  let hasReset = (1 shl n) != modulus
  let m1 = modulus - 1

  # borrow[i] = !Q₀·!Q₁·…·!Qᵢ  (running AND of all inverted outputs)
  r.borrow = newSeq[Node](n)
  r.borrow[0] = symN("!Q" & subscript[0], (r.msN[0], 1))
  for i in 1..<n:
    r.borrow[i] = andN(r.borrow[i-1], (r.msN[i], 1))

  # load fires when state = 0 (all Q = 0); on next clock reload to m1
  let load = if hasReset: r.borrow[n-1] else: Node nil
  r.reset = if hasReset: norN(load) else: Node nil

  # sArr[i]: S input — set Qᵢ to 1
  # rArr[i]: R input — reset Qᵢ to 0
  #
  # Down-counting rule (no load): Qᵢ toggles when borrow[i-1] = 1
  #   S[i] = !Qᵢ & borrow[i-1]
  #   R[i] =  Qᵢ & borrow[i-1]
  #
  # Load correction for non-power-of-2: when state = 0, load m1.
  #   At state 0 all Qᵢ = 0, so borrow[i-1] = 1 for every i — without
  #   correction every bit would be set to 1. Suppress S for bits that
  #   must stay 0 in m1 by gating with notLoad.
  var sArr = newSeq[Node](n)
  var rArr = newSeq[Node](n)

  # bit 0: always toggles (borrow[-1] ≡ 1)
  let m1b0 = m1 and 1
  if hasReset and m1b0 == 0:
    sArr[0] = andN((r.msN[0], 1), r.reset)
  else:
    sArr[0] = symN("!Q" & subscript[0], (r.msN[0], 1))
  rArr[0] = symN("Q" & subscript[0], (r.msN[0], 0))

  for i in 1..<n:
    let m1bi = (m1 shr i) and 1
    if hasReset and m1bi == 0:
      sArr[i] = andN((r.msN[i], 1), r.reset, r.borrow[i-1])
    else:
      sArr[i] = andN((r.msN[i], 1), r.borrow[i-1])
    rArr[i] = andN((r.msN[i], 0), r.borrow[i-1])

  for i in 0..<n:
    r.msN[i].inputs.add sArr[i]
    r.msN[i].inputs.add r.C
    r.msN[i].inputs.add rArr[i]
    for x in r.msN[i].pack.inputs: x.name.removeSuffix subscript[1]
    r.msN[i].pack.outputs[0].name = "Q"  & subscript[i]
    r.msN[i].pack.outputs[1].name = "!Q" & subscript[i]

  r.Q = newSeq[Node](n)
  for i in 0..<n:
    r.Q[i] = symN("Q" & subscript[i], (r.msN[i], 0))

  const stepX = 19.0
  const stepY = 4.0 - 1e-3

  var rules: seq[PlacementRule]
  rules.add Line(origin: point2(0, n.float * stepY + 4), nodes: @[r.C])

  for i in 0..<n:
    let x = 6.0  + i.float * stepX
    let y = i.float * stepY
    rules.add Line(origin: point2(x, y - 1.5), nodes: @[sArr[i]], align: Outputs)
    rules.add Line(origin: point2(x, y + 1.5), nodes: @[rArr[i]], align: Outputs)
    rules.add Line(origin: point2(x + 4, y), nodes: @[r.msN[i]])
    if i > 0:
      rules.add Line(origin: point2(x - 6, y - 0.5), nodes: @[r.borrow[i-1]], align: Outputs)
      rules.add loopbackPath((r.borrow[i], 0), offset = (if i > 1: -2.0 else: -3.5), hOffset = (0.0, 1.0))

  if hasReset:
    rules.add Line(
      origin: point2(n.float * stepX + 6, n.float * stepY + 2),
      nodes: @[load],
    )
    rules.add Line(
      origin: point2(n.float * stepX + 9, n.float * stepY + 2),
      nodes: @[r.reset],
    )

  rules.add Line(
    origin: point2(n.float * stepX + 10, 0),
    nodes:  r.Q,
    align:  Inputs,
  )

  for i in 0..<n:
    let m1bi = if i == 0: m1 and 1 else: (m1 shr i) and 1
    rules.add bus(point2(9.0 + i.float * stepX, 0), r.C, @[r.msN[i]])
    rules.add loopbackPath((sArr[i], 0), offset = -1, hOffset = (0.0, -0.5))
    if hasReset and m1bi == 0:
      # sArr[i] = andN(!Qᵢ, notLoad[, borrow]); port 1 = notLoad
      rules.add loopbackPath((sArr[i], 1), offset = 2.5, hOffset = (-1.0, 1.0))
    rules.add loopbackPath(rArr[i], offset = 1, hOffset = (0.0, 0.0))

  r.placement = rules


proc startup*(c: CounterModDown): seq[ValChange] =
  ## Start at modulus-1 (top of the count).
  result.add setVal(c.C, 0)
  let startVal = c.modulus - 1
  for i in 0..<c.ms.len:
    let bit = Value((startVal shr i) and 1)
    result.add setVal(c.ms[i].t1.T[0], bit)
    result.add setVal(c.ms[i].t1.T[1], not bit)
    result.add setVal(c.ms[i].t2.T[0], bit)
    result.add setVal(c.ms[i].t2.T[1], not bit)



mainModule:
  let c = counterModDown(14)

  placeComponents(c.placement)
  drawComponents()

  var timestamps = @[PlotTimestamp(time: 0, changes: startup(c))]

  for t in 0..(c.modulus + 6):
    let base = 1.0 + t.float * 3.0
    timestamps.add PlotTimestamp(time: base,       changes: @[setVal(c.C, 1)])
    timestamps.add PlotTimestamp(time: base + 0.05)
    timestamps.add PlotTimestamp(time: base + 1.5, changes: @[setVal(c.C, 0)])
    timestamps.add PlotTimestamp(time: base + 1.55)

  let p = Plot(
    data:              @[@[c.C], c.Q],
    gap:               0.2,
    groupGap:          1,
    timeScale:         1.4,
    timestamps:        timestamps,
    origin:            point2(0, 26),
    skipUnchangedAxes: true,
  )
  draw p
