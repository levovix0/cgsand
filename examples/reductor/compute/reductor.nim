import std/[math, sequtils]
import std/sugar except dump
import pkg/[vmath]
import ./[utils, stators, engines, common, closed_transmission, chain_transmission, shafts]


type
  TransmissionKind* = enum
    cylindric_closed  ## closed cylindric gear transmission
    cylindric_opened  ## open cylindric gear transmission
    conic_closed  ## closed conic gear transmission
    conic_opened  ## open conic gear transmission
    chain_closed
    chain_opened
    worm_closed
    worm_opened
    belt_opened
    bearing  ## bearing pair
    muft

    belt_final  ## final belt stage (affects efficiency only)
  
  ReductorInput* = object
    env*: float
      ## Operating conditions (0 - harshest, 1 - mildest)

    D*: float
      ## Drum diameter, m

    F*: float
      ## Belt pulling force, kN

    V*: float
      ## Belt speed, m/s

  ReductorOutput* = object
    P_work_part*, kuw*, P_req*, w_shaft*, u_rec*, n_req*: float
    engine*: Engine

    u_summ*, u_open_rec*, u_closed_recx*, u_closed*, u_opened*: float
    u_stages*: array[2, float]

    stage_speeds*, stage_speeds_revMin*, stage_powers*, powers_between_shafts*, stage_rotational_moments*: seq[float]

    ## w, n, P, T at the engine shaft [0], after the closed stage [1], after the open stage [2]
    kinematic_w*, kinematic_n*, kinematic_P*, kinematic_T*: array[3, float]

    ## u of the closed [0] and open [1] stages
    kinematic_u*: array[2, float]

    ## stage_rotational_moments[^1] - F*D/2, should be close to 0
    momentBalanceCheck*: float

    closedTransmissionInput*: ClosedTransmissionInput
    closedTransmission*: ClosedTransmissionOutput

    chainTransmissionInput*: ChainTransmissionInput
    chainTransmission*: ChainTransmissionOutput

    shaftsInput*: ShaftsInput
    shafts*: ShaftsOutput

const
  OpenTransmissions* = {cylindric_opened, conic_opened, chain_opened, worm_opened, belt_opened}
  ClosedTransmissions* = {cylindric_closed, conic_closed, chain_closed, worm_closed}
  K1to1Transmissions* = {bearing, muft, belt_final}

const
  ## Recommended gear ratios for each transmission kind, W:w
  k1k2Std = [
    cylindric_closed:  4'f64,
    cylindric_opened:  4,
    conic_closed:      3,
    conic_opened:      3,
    chain_closed:      3,
    chain_opened:      3,
    worm_closed:       25,
    worm_opened:       25,
    belt_opened:       2.5,
    bearing:           1,
    muft:              1,
    belt_final:        1,
  ]

  ## Kinematic transmissions on the schematic, in order from the engine to the working unit (conveyor)
  structure = [
    muft,
    bearing,
    cylindric_closed,
    bearing,
    chain_opened,
    bearing,
    belt_final,
  ]


columnTable transmission_closed_rows, `const`:
  cylindric                         | conic                   | worm
  @[2.0,  2.5, 3.15, 4,   5,   6.3] | @[2.0,  2.5, 3.15, 4  ] | @[10.0, 12.5, 16, 20, 25, 31.5, 40, 50]
  @[2.24, 2.8, 3.55, 4.5, 5.6, 7.1] | @[2.24, 2.8, 3.55, 4.5] | @[]

proc selectClosestTransmissionRatio*(x: float, kind: TransmissionKind, rowScores: array[2, float] = [2, 1]): float =
  let rows =
    case kind
    of cylindric_closed: transmission_closed_rows.cylindric
    of conic_closed: transmission_closed_rows.conic
    of worm_closed: transmission_closed_rows.worm
    of OpenTransmissions, K1to1Transmissions, chain_closed:
      raise ValueError.newException("no data for " & $kind & " available transmission ratios")

  var maxScore = 0.0
  for rowN, row in rows:
    for col in row:
      let score = 1 / abs(col - x) * rowScores[rowN]
      if score > maxScore:
        result = col
        maxScore = score


proc count_speeds_between_transmissions(engine: Engine, transmissions_u: openArray[float]): seq[float] =
  ## result[0] - engine speed, rad/s
  ## result[1] - speed after the first transmission, etc., rad/s
  result.add engine.n.rmp_to_radps
  for i, u in transmissions_u:
    result.add result[^1] / u


proc count_powers_between_transmissions(P_req: float, transmissions_kuw: openArray[float]): seq[float] =
  ## result[0] - power at the first shaft, equal to the required engine power, kW
  ## result[1] - power after the first transmission, etc., kW
  result.add P_req
  for i, kuw in transmissions_kuw:
    result.add result[^1] * kuw


proc `kN*m -> N*mm`(v: float): float =
  v * 1e3 #[kN -> N]# * 1e3 #[m -> mm]#

proc `kVt -> Vt`(v: float): float =
  v * 1e3


static: assert structure.filterIt(it in OpenTransmissions).allIt(it == chain_opened), "other open transmissions not implemented"



proc computeReductor*(I: ReductorInput): ReductorOutput =
  template O: var ReductorOutput = result

  ## Efficiency factors, 1
  let kuwStd = [
    cylindric_closed:  mix(0.96,  0.98,  I.env),
    cylindric_opened:  mix(0.93,  0.95,  I.env),
    conic_closed:      mix(0.95,  0.97,  I.env),
    conic_opened:      mix(0.92,  0.94,  I.env),
    chain_closed:      mix(0.95,  0.97,  I.env),
    chain_opened:      mix(0.90,  0.93,  I.env),
    worm_closed:       mix(0.65,  0.70,  I.env),
    worm_opened:       mix(0.50,  0.60,  I.env),
    belt_opened:       mix(0.94,  0.97,  I.env),
    bearing:           mix(0.990, 0.995, I.env),
    muft:              mix(0.98,  1.00,  I.env),
    belt_final:        mix(0.94,  0.97,  I.env),
  ]


  # ========================
  # --- Engine selection ---
  # ========================

  ## Power at the working unit shaft, kW
  O.P_work_part = I.F * I.V

  ## Efficiency factor, 1
  O.kuw = structure.mapIt(kuwStd[it]).foldl(a * b)

  ## Required electric engine power, kW
  O.P_req = O.P_work_part / O.kuw

  ## Angular speed of the working shaft, rad/s
  O.w_shaft = 2 * I.V / I.D

  ## Recommended gear ratio between the engine and the conveyor, W:w
  O.u_rec = structure.mapIt(k1k2Std[it]).foldl(a * b)

  ## Required electric engine rotational speed, rpm
  O.n_req = O.w_shaft * O.u_rec * (30 / Pi)

  O.engine = selectEngine(O.P_req, O.n_req, I.env)


  # ==============================================================
  # --- Refining the gear ratios of the open and closed stages ---
  # ==============================================================

  ## Total gear ratio of the drive, 1
  O.u_summ = O.engine.n.rmp_to_radps / O.w_shaft

  ## Desired gear ratio of the open transmissions
  O.u_open_rec = structure.filterIt(it in OpenTransmissions).mapIt(k1k2Std[it]).foldl(a * b)

  ## Desired gear ratio of the closed transmissions
  O.u_closed_recx = O.u_summ / O.u_open_rec

  ## Rounded gear ratio of the closed transmissions
  O.u_closed = O.u_closed_recx
    .selectClosestTransmissionRatio(
      (@structure).iter.filterSt(x => x in ClosedTransmissions).get
    )

  ## Gear ratio of the open transmission
  O.u_opened = O.u_summ / O.u_closed


  # ==========================================================
  # --- Determining the angular speeds of the drive shafts ---
  # ==========================================================

  ## u, Gear ratios of all stages, 1
  O.u_stages = [O.u_closed, O.u_opened]

  ## w, Shaft speeds, rad/s
  O.stage_speeds = O.engine.count_speeds_between_transmissions(O.u_stages)

  ## w, Shaft rotational speeds, rpm
  O.stage_speeds_revMin = O.stage_speeds.mapIt(it / (Pi / 30))

  ## P, Power at each structural element, including couplings, bearings, etc., kW
  O.stage_powers = count_powers_between_transmissions(O.P_req, structure.mapIt(kuwStd[it]))

  ## P, Power at each shaft, [0] - at the engine, kW
  O.powers_between_shafts = block:
    var res = collect newSeq:
      for i in 1..<O.stage_powers.len:
        if structure[i-1] notin K1to1Transmissions:
          O.stage_powers[i]
    res.insert O.stage_powers[0]
    res[^1] = O.stage_powers[^1]
    res


  # ===================================================
  # --- Determining the torques on the drive shafts ---
  # ===================================================

  ## T, Torques on the shafts, kW / rad/s = kN*m
  O.stage_rotational_moments = collect newSeq:
    for i in 0..<O.stage_speeds.len:
      O.powers_between_shafts[i] / O.stage_speeds[i]

  O.momentBalanceCheck = O.stage_rotational_moments[^1] - (I.F * I.D / 2)


  O.kinematic_w = [O.stage_speeds[0], O.stage_speeds[1], O.stage_speeds[2]]
  O.kinematic_n = [O.kinematic_w[0].radps_to_rmp, O.kinematic_w[1].radps_to_rmp, O.kinematic_w[2].radps_to_rmp]
  O.kinematic_P = [O.stage_powers[0], O.stage_powers[1], O.stage_powers[2]]
  O.kinematic_T = [O.stage_rotational_moments[0], O.stage_rotational_moments[1], O.stage_rotational_moments[2]]
  O.kinematic_u = O.u_stages

  const
    before_closed = 0
    after_closed = 1
    before_opened = 1


  # ===========================
  # --- Closed transmission ---
  # ===========================

  O.closedTransmissionInput = ClosedTransmissionInput(
    T1: O.kinematic_T[before_closed].`kN*m -> N*mm`,
    T2: O.kinematic_T[after_closed].`kN*m -> N*mm`,
    w1: O.kinematic_w[before_closed],
    w2: O.kinematic_w[after_closed],
    n1: O.kinematic_n[before_closed],
    n2: O.kinematic_n[after_closed],
    u: O.kinematic_u[before_closed],

    teethKind: Straight,
    reverseMotionAllowance: NonReversive,
    placementKind: Symmetrical,
    gearingKind: Outer,
    speedKind: Fast,
    transmissionKind: Cylindric,

    env: I.env,
  )

  O.closedTransmission = computeClosedTransmission(O.closedTransmissionInput)


  # =========================
  # --- Open transmission ---
  # =========================

  O.chainTransmissionInput = ChainTransmissionInput(
    T1: O.kinematic_T[before_opened].`kN*m -> N*mm`,
    P1: O.kinematic_P[before_opened].`kVt -> Vt`,
    w1: O.kinematic_w[before_opened],
    n1: O.kinematic_n[before_opened],
    u: O.kinematic_u[before_opened],

    loadKind: Calm,
    orientation: Horizontal,
    regulating: Periodic,
    lubricationMethod: Periodic,
    workPeriod: SingleShift,
    rowCount: SingleRow,

    env: I.env,
  )

  O.chainTransmission = computeChainTransmission(O.chainTransmissionInput)


  # ==============
  # --- Shafts ---
  # ==============

  O.shaftsInput = ShaftsInput(
    T_B: O.kinematic_T[before_closed].`kN*m -> N*mm`,
    T_T: O.kinematic_T[after_closed].`kN*m -> N*mm`,
    d_ed: selectEngineShaftDiameter(O.engine.name),

    lengthKind: Short,
    endKind_B: Coupling,
    endKind_T: OpenTransmission,

    env: I.env,
  )

  O.shafts = computeShafts(O.shaftsInput)


when isMainModule:
  let I = ReductorInput(env: 0.0, D: 0.5, F: 3.2, V: 1.5)
  let O = computeReductor(I)

  echo O
