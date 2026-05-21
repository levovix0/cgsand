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
    modulus*: int


proc counterMod*(modulus: int): CounterMod =
  ## Synchronous binary counter with auto-reset at `modulus`.
  ## Builds T-triggers from MS-triggers via packN.
  ## Minimum number of bits is derived automatically.
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

  # Detect state `modulus-1` synchronously: fires during C=1, captured by master.
  # Use !Qᵢ for bits that are 0 in (modulus-1) to avoid S=1,R=1 on the next cycle.
  let hasReset = (1 shl n) != modulus
  r.reset = andN()
  if hasReset:
    let m1 = modulus - 1
    for i in 0..<n:
      if ((m1 shr i) and 1) == 1:
        r.reset.inputs.insert r.msN[i]        # Qᵢ  (port 0)
  let notReset = if hasReset: norN(r.reset) else: Node nil

  # carry[i] = Q₀·Q₁·…·Qᵢ  (running AND chain)
  # sArr[i]  = !reset · carry[i-1] · !Qᵢ   (suppressed by reset to prevent S=1,R=1)
  # rArr[i]  = carry[i] [OR reset]
  r.carry = newSeq[Node](n)
  var sArr = newSeq[Node](n)
  var rArr = newSeq[Node](n)

  r.carry[0] = symN("Q"  & subscript[0], (r.msN[0], 0))
  if hasReset:
    sArr[0] = andN((r.msN[0], 1), notReset)
  else:
    sArr[0] = symN("!Q" & subscript[0], (r.msN[0], 1))
  rArr[0] = if hasReset: orN(r.reset, r.carry[0]) else: r.carry[0]

  for i in 1..<n:
    r.carry[i] = andN(r.carry[i-1], (r.msN[i], 0))
    if hasReset:
      sArr[i] = andN((r.msN[i], 1), notReset, r.carry[i-1])
    else:
      sArr[i] = andN((r.msN[i], 1), r.carry[i-1])
    rArr[i] =
      if hasReset:
        if i == n-1:
          symN("", r.reset)
        else:
          orN(r.reset, r.carry[i])
      else: r.carry[i]


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
  rules.add Line(origin: point2(0, n.float * stepY + 2), nodes: @[r.C])

  for i in 0..<n:
    let x = 6.0  + i.float * stepX
    let y = i.float * stepY
    rules.add Line(origin: point2(x, y - 1.5), nodes: @[sArr[i]], align: Outputs)
    rules.add Line(origin: point2(x, y + 1.5), nodes: @[rArr[i]], align: Outputs)
    rules.add Line(origin: point2(x + 4, y), nodes: @[r.msN[i]])
    if i > 0:
      # carry[i-1] is the AND node feeding both sArr[i] and carry[i]
      rules.add Line(origin: point2(x - 6, y - 0.5), nodes: @[r.carry[i-1]], align: Outputs)
      rules.add loopbackPath((rArr[i-1],1), offset = 1)
      rules.add loopbackPath((r.carry[i],0), offset = (if i > 1: -2 else: -3))

  if hasReset:
    rules.add Line(
      origin: point2(n.float * stepX + 4, n.float * stepY + 2),
      nodes: @[r.reset],
    )
    rules.add Line(
      origin: point2(n.float * stepX + 9, n.float * stepY + 2),
      nodes: @[notReset],
    )
    for i, resInp in r.reset.inputs:
      rules.add bus(point2(n.float * stepX + 2 - i.float * 1, 0), resInp, @[r.reset])

  rules.add Line(
    origin: point2(n.float * stepX + 10, 0),
    nodes:  r.Q,
    align:  Inputs,
  )

  for i in 0..<n:
    rules.add bus(point2(9.0 + i.float * stepX, 0), r.C, @[r.msN[i]])
    rules.add loopbackPath((sArr[i],0), offset = -1)
    rules.add loopbackPath((sArr[i],1), offset = 2.5, hOffset = (-0.5, 0.0))
    rules.add loopbackPath(rArr[i], hOffset = (-1.0, 0.0))

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

  for t in 0..(c.modulus+6):
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
  # echoPlot p
  draw p
