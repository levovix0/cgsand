import std/strutils
import sandbox
import electronics/schemes
import ./trigger_ms


type
  CounterMod* = object
    C*: Node
    Q*: seq[Node]
    ms*: seq[MsTrigger]
    msN*: seq[Node]
    carry*: seq[Node]    ## carry[i] = Q₀·Q₁·…·Qᵢ
    reset*: Node         ## nil when modulus is a power of 2 (natural rollover)
    placement*: seq[PlacementRule]


proc counterMod*(modulus: int): CounterMod =
  ## Synchronous binary counter with auto-reset at `modulus`.
  ## Builds T-triggers from MS-triggers via packN.
  ## Minimum number of bits is derived automatically.
  template r: untyped = result
  assert modulus >= 2

  var n = 1
  while (1 shl n) < modulus:
    inc n

  r.C = Node "C"

  r.ms  = newSeq[MsTrigger](n)
  r.msN = newSeq[Node](n)
  for i in 0..<n:
    r.ms[i]  = msTrigger()
    r.msN[i] = r.ms[i].msPack.packN("MS" & subscript[i])

  # Detect state `modulus`: AND together the Q outputs whose bit is set in modulus.
  block:
    var acc: Node = nil
    for i in 0..<n:
      if ((modulus shr i) and 1) == 1:
        acc = if acc == nil: symN("", (r.msN[i], 0))
              else:          andN(acc, (r.msN[i], 0))
    r.reset = acc  # nil when modulus is power of 2

  # carry[i] = Q₀·Q₁·…·Qᵢ  (running AND chain)
  # sArr[i]  = carry[i-1] · !Qᵢ   (= Tᵢ · !Qᵢ, the S input)
  # rArr[i]  = carry[i] [OR reset] (= Tᵢ · Qᵢ [+ forced reset], the R input)
  r.carry = newSeq[Node](n)
  var sArr = newSeq[Node](n)
  var rArr = newSeq[Node](n)

  sArr[0]    = symN("!Q" & subscript[0], (r.msN[0], 1))
  r.carry[0] = symN("Q"  & subscript[0], (r.msN[0], 0))
  rArr[0]    = if r.reset != nil: orN(r.carry[0], r.reset) else: r.carry[0]

  for i in 1..<n:
    r.carry[i] = andN((r.msN[i], 0), r.carry[i-1])
    sArr[i]    = andN((r.msN[i], 1), r.carry[i-1])
    rArr[i]    = if r.reset != nil: orN(r.reset, r.carry[i]) else: r.carry[i]

  for i in 0..<n:
    r.msN[i].inputs.add sArr[i]
    r.msN[i].inputs.add r.C
    r.msN[i].inputs.add rArr[i]
    for x in r.msN[i].pack.inputs: x.name.removeSuffix subscript[1]
    r.msN[i].pack.outputs[0].name = "Q" & subscript[i]
    r.msN[i].pack.outputs[1].name = "!Q" & subscript[i]

  r.Q = newSeq[Node](n)
  for i in 0..<n:
    r.Q[i] = symN("Q" & subscript[i], (r.msN[i], 0))

  # Layout: each trigger is offset by (stepX, stepY) from the previous.
  const stepX = 19.0
  const stepY = 4.0 - 1e-3  # todo: if stepY is ideally aligned, some branches are not drawn

  var rules: seq[PlacementRule]
  rules.add Line(origin: point2(0, n.float * stepY + 6), nodes: @[r.C])

  for i in 0..<n:
    let x = 6.0  + i.float * stepX
    let y = i.float * stepY
    rules.add Line(origin: point2(x, y - 1.5), nodes: @[sArr[i]], align: Outputs)
    rules.add Line(origin: point2(x, y + 1.5), nodes: @[rArr[i]], align: Outputs)
    rules.add Line(origin: point2(x + 4, y), nodes: @[r.msN[i]])
    if i > 0:
      # carry[i-1] is the AND node feeding both sArr[i] and carry[i]
      rules.add Line(origin: point2(x - 6, y - 0.5), nodes: @[r.carry[i-1]], align: Outputs)
      rules.add loopbackPath(r.carry[i-1], (rArr[i-1],1), offset = 1)

  # if r.reset != nil:
  #   rules.add Line(
  #     origin: point2(n.float * stepX + 4, n.float * stepY + 2),
  #     nodes: @[r.reset],
  #   )

  rules.add Line(
    origin: point2(n.float * stepX + 10, 0),
    nodes:  r.Q,
    align:  Inputs,
  )

  for i in 0..<n:
    rules.add bus(point2(9.0 + i.float * stepX, 0), r.C, @[r.msN[i]])
    rules.add loopbackPath((r.msN[i],1), (sArr[i],0), offset = -1)

  r.placement = rules


proc startup*(c: CounterMod): seq[ValChange] =
  result.add setVal(c.C, 0)
  for i in 0..<c.ms.len:
    result.add setVal(c.ms[i].t1.T[0], 0)
    result.add setVal(c.ms[i].t1.T[1], 1)
    result.add setVal(c.ms[i].t2.T[0], 0)
    result.add setVal(c.ms[i].t2.T[1], 1)



mainModule:
  let c = counterMod(14)

  placeComponents(c.placement)
  drawComponents()

  var timestamps = @[PlotTimestamp(time: 0, changes: startup(c))]
  timestamps.add PlotTimestamp(time: 0.05)

  for t in 0..<15:
    let base = 1.0 + t.float * 3.0
    timestamps.add PlotTimestamp(time: base,       changes: @[setVal(c.C, 1)])
    timestamps.add PlotTimestamp(time: base + 0.05)
    timestamps.add PlotTimestamp(time: base + 1.5, changes: @[setVal(c.C, 0)])
    timestamps.add PlotTimestamp(time: base + 1.55)

  let plotData =
    if c.reset != nil: @[@[c.C], c.Q, @[c.reset]]
    else:              @[@[c.C], c.Q]

  let p = Plot(
    data:              plotData,
    gap:               0.2,
    groupGap:          0.5,
    timeScale:         1.5,
    timestamps:        timestamps,
    origin:            point2(0, 14),
    skipUnchangedAxes: true,
  )
