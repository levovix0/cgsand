import std/[math]
import pkg/[vmath]
import ./[utils]


type
  LoadKind* = enum
    Calm      ## Calm load (belt conveyor)
    Jolt      ## Jolting load (chain conveyor)
    Variable  ## Variable load (chain conveyor)
    Impact    ## Impact load (pneumatic hammers, planing and slotting machines, rolling mills)
    Unknown   ## Unknown load (the working unit the drive is computed for is not specified)
  
  Orientation* = enum
    Horizontal
    Vertical
  
  Regulating* = enum
    Automatic
    Periodic
  
  LubricationMethod* = enum
    Continuous
    Karter
    Periodic
  
  WorkPeriod* = enum
    SingleShift
    DuoShift
    TrioShift
  
  RowCount* = enum
    SingleRow
    DuoRow


  ChainTransmissionInput* = object
    T1*: float
      ## Torque, N*mm
      ## For the smaller (driving) sprocket

    P1*: float
      ## P, Power, W
      ## For the smaller (driving) sprocket

    w1*: float
      ## ω_1, Angular speed, rad/s (s^-1)
      ## For the smaller (driving) sprocket

    n1*: float
      ## Rotational speed, rpm
      ## For the smaller (driving) sprocket

    u*: float
      ## Gear ratio between the gear and the wheel, 1

    loadKind*: LoadKind
    orientation*: Orientation
    regulating*: Regulating = Periodic
    lubricationMethod*: LubricationMethod = Periodic
    workPeriod*: WorkPeriod
    rowCount*: RowCount

    env*: float
      ## Operating conditions (0 - harshest, 1 - mildest)


  ChainGeometry* = object
    ## Chain geometry (GOST 13568-97)

    t*: float
      ## Chain pitch, mm

    B_BH*: float
      ## Distance between inner plates, mm

    d*: float
      ## Pin diameter, mm

    d1*: float
      ## Roller diameter, mm

    h*: float
      ## Plate width, mm

    b*: float
      ## Pin length, mm

    S*: float
      ## Projected bearing area of the joint, mm^2


  ChainTransmissionGeometry* = object
    z1*: int
      ## Number of teeth on the driving (larger) sprocket

    z2*: int
      ## Number of teeth on the driven (smaller) sprocket

    a*: float
      ## Center distance, mm

    a_mount*: float
      ## Mounting center distance, mm

    L*: int
      ## Number of links in the chain

    d1*: float
      ## Pitch diameter of the driving (larger) sprocket, mm

    d2*: float
      ## Pitch diameter of the driven (smaller) sprocket, mm

    De1*: float
      ## Outer diameter of the driving (larger) sprocket, mm

    De2*: float
      ## Outer diameter of the driven (smaller) sprocket, mm


  ChainTransmissionCheck* = object
    `[n1]`*: float
      ## Maximum allowable speed of the small sprocket

    `[p]`*: float
      ## Maximum allowable average pressure in chain joints, MPa

    p*: float
      ## Average pressure in chain joints, MPa

    `[s]`*: float
      ## Standard safety factor

    s*: float
      ## Safety factor

    Fp*: float
      ## Breaking load, N

    FB*: float
      ## Force acting on the shafts, N


  ChainTransmissionOutput* = object
    u*: float

    q*: float
      ## Mass of 1m of chain, kg/m

    chainGeom*: ChainGeometry
    geom*: ChainTransmissionGeometry
    check*: ChainTransmissionCheck


const avgPressure_data = [
  (n: 50,   t: @{12.7:   46,    15.875: 43,    19.05:  39,    25.4:   36,    31.75:  34,    38.1:   31,    44.45:  29,    50.8:   27,  }),
  (n: 100,  t: @{12.7:   37,    15.875: 34,    19.05:  31,    25.4:   29,    31.75:  27,    38.1:   25,    44.45:  23,    50.8:   22,  }),
  (n: 200,  t: @{12.7:   29,    15.875: 27,    19.05:  25,    25.4:   23,    31.75:  22,    38.1:   19,    44.45:  18,    50.8:   17,  }),
  (n: 300,  t: @{12.7:   26,    15.875: 24,    19.05:  22,    25.4:   20,    31.75:  19,    38.1:   17,    44.45:  16,    50.8:   15,  }),
  (n: 500,  t: @{12.7:   22,    15.875: 20,    19.05:  18,    25.4:   17,    31.75:  16,    38.1:   14,    44.45:  13,    50.8:   12,  }),
  (n: 750,  t: @{12.7:   19,    15.875: 17,    19.05:  16,    25.4:   15,    31.75:  14,    38.1:   13,  }),
  (n: 1000, t: @{12.7:   17,    15.875: 16,    19.05:  14,    25.4:   13,    31.75:  13,  }),
  (n: 1250, t: @{12.7:   16,    15.875: 15,    19.05:  13,    25.4:   12,  }),
]


columnTable gost_chain_1, `const`:
  t      | B_BH  | d     | d1    | h    | b  | F_F    | q    | S
  8.0    | 3.0   | 2.31  | 5.0   | 7.5  | 6  | 4600   | 0.2  | 11.0
  9.525  | 5.72  | 3.28  | 6.35  | 8.5  | 13 | 9100   | 0.45 | 28.0
  12.7   | 5.4   | 4.45  | 8.51  | 11.8 | 19 | 17854  | 0.65 | 39.6
  15.875 | 6.48  | 5.08  | 10.16 | 14.8 | 20 | 22268  | 0.8  | 54.8
  19.05  | 12.7  | 5.96  | 11.91 | 18.2 | 33 | 31195  | 1.5  | 105.8
  25.4   | 15.88 | 7.95  | 15.88 | 24.2 | 39 | 55622  | 2.6  | 179.7
  31.75  | 19.05 | 9.55  | 19.05 | 30.2 | 46 | 86818  | 3.8  | 262
  38.10  | 25.4  | 11.1  | 22.23 | 36.2 | 58 | 124587 | 5.5  | 394
  44.45  | 25.4  | 12.7  | 25.4  | 42.4 | 62 | 169124 | 7.5  | 473
  50.8   | 31.75 | 14.29 | 28.58 | 48.3 | 72 | 222490 | 9.7  | 646


columnTable gost_chain_2, `const`:
  t      | B_BH  | d     | d1    | h    | b   | A     | F_p    | q    | S
  12.7   | 7.75  | 4.45  | 8.51  | 11.8 | 35  | 13.92 | 31196  | 1.4  | 105.0
  15.875 | 9.65  | 5.08  | 10.16 | 14.8 | 41  | 16.58 | 44537  | 1.9  | 140.0
  19.05  | 12.7  | 5.88  | 11.91 | 18.2 | 54  | 22.78 | 70632  | 3.5  | 211.0
  25.4   | 15.88 | 7.95  | 15.88 | 24.2 | 68  | 29.29 | 111245 | 5.0  | 359.0
  31.75  | 19.05 | 9.55  | 19.05 | 30.2 | 82  | 35.36 | 173637 | 7.3  | 524.0
  38.10  | 25.4  | 11.12 | 22.23 | 36.2 | 104 | 45.44 | 249174 | 11.0 | 788.0
  44.45  | 25.4  | 12.75 | 25.4  | 42.2 | 110 | 48.87 | 337562 | 14.4 | 946.0
  50.8   | 31.75 | 14.29 | 28.58 | 48.3 | 130 | 53.55 | 445178 | 19.1 | 1292.0


columnTable max_rotation_speed, `const`:
  t      | n
  12.7   | 1250
  15.875 | 1000
  19.05  | 900
  25.4   | 800
  31.75  | 630
  38.1   | 500
  44.45  | 400
  50.8   | 300

# Standard safety factor [s] values for standard-series roller chains

const standard_pitch_strength = (
  t: @[12.7, 15.875, 19.05, 25.4, 31.75, 38.1, 44.5, 50.8],
  s: @[
    (n1: 50, s: @[7.1, 7.2, 7.2, 7.3, 7.4, 7.5, 7.6, 7.6]),
    (n1: 100, s: @[7.3, 7.4, 7.5, 7.6, 7.8, 8.0, 8.1, 8.3]),
    (n1: 300, s: @[7.9, 8.2, 8.4, 8.9, 9.4, 9.8, 10.3, 10.8]),
    (n1: 500, s: @[8.5, 8.9, 9.4, 10.2, 11.0, 11.8, 12.5]),
    (n1: 750, s: @[9.3, 10.0, 10.7, 12.0, 13.0, 14.0]),
    (n1: 1000, s: @[10.0, 10.8, 11.7, 13.3, 15.0]),
    (n1: 1250, s: @[10.6, 11.6, 12.7, 14.5]),
  ],
)




proc standardPitchStrength_for(n: float, t: float): float =
  var tIdx = -1
  for i, tv in standard_pitch_strength.t:
    if abs(tv - t) < 0.1:
      tIdx = i
      break
  if tIdx < 0: raise ValueError.newException("t not found in standard_pitch_strength")
  for row in standard_pitch_strength.s:
    if n <= row.n1.float and tIdx < row.s.len:
      return row.s[tIdx]
  raise ValueError.newException("n too high for given t in standard_pitch_strength")


proc toothHeightCoeff(lambda: float): float =
  if lambda < 1.50: 0.480
  elif lambda < 1.60: 0.532
  elif lambda < 1.70: 0.555
  elif lambda < 1.80: 0.575
  else: 0.565


proc avgPressure_for_n(
  n: float,  # rotational speed, rpm
): seq[(float, int)] =
  for avgp in avgPressure_data:
    if n <= avgp.n.float:
      return avgp.t
  raise ValueError.newException("not found")




proc computeChainTransmission*(I: ChainTransmissionInput): ChainTransmissionOutput =
  template O: var ChainTransmissionOutput = result

  O.geom.z1 = (31 - 2 * I.u).round.int
  #! on the mainModule test parameters this gives a 20% underload; reducing it to 20 (-5) makes the power nearly match (with a microscopic verload)
  O.geom.z2 = (O.geom.z1.float * I.u).round.int
  O.u = O.geom.z2 / O.geom.z1

  let
    K_d = case I.loadKind
      of Calm: 1.0
      of Jolt, Variable: mix(1.25, 1.5, I.env)
      of Impact: mix(2.5, 1.8, I.env)
      of Unknown: 1.5
    
    K_a = 1.0
      ## the center distance is not known yet, assume a=40*t

    K_h = case I.orientation
      of Horizontal: 1.0
      of Vertical: 1.25
    
    K_p = case I.regulating
      of Automatic: 1.0
      of Periodic: 1.25
    
    K_cm = case I.lubricationMethod
      of Continuous: 1.0
      of Karter: 0.8
      of Periodic: mix(1.5, 1.3, I.env)
    
    K_n = case I.workPeriod
      of SingleShift: 1.0
      of DuoShift: 1.25
      of TrioShift: 1.5

    K_sum = K_d * K_a * K_h * K_p * K_cm * K_n

    m = case I.rowCount
      of SingleRow: 1
      of DuoRow: 2

  for (t, `[p]`) in avgPressure_for_n(I.n1):
    var `[p]` = `[p]`.float * (1 + 0.01 * (O.geom.z1.float - 17))
    if I.rowCount != SingleRow: `[p]` -= 15
    
    let min_t = 2.8 * ((I.T1 * K_sum) / (O.geom.z1.float * `[p]` * m.float)).pow(1/3)
    if t >= min_t:
      O.chainGeom.t = t
      O.check.`[p]` = `[p]`
      break
  
  let chains = case I.rowCount
    of SingleRow:
      (
        t:    @(gost_chain_1.t),
        B_BH: @(gost_chain_1.B_BH),
        d:    @(gost_chain_1.d),
        d1:   @(gost_chain_1.d1),
        h:    @(gost_chain_1.h),
        b:    @(gost_chain_1.b),
        F:    @(gost_chain_1.F_F),
        q:    @(gost_chain_1.q),
        S:    @(gost_chain_1.S)
      )
    of DuoRow:
      (t:     @(gost_chain_2.t),
        B_BH: @(gost_chain_2.B_BH),
        d:    @(gost_chain_2.d),
        d1:   @(gost_chain_2.d1),
        h:    @(gost_chain_2.h),
        b:    @(gost_chain_2.b),
        F:    @(gost_chain_2.F_p),
        q:    @(gost_chain_2.q),
        S:    @(gost_chain_2.S)
      )

  for i in 0..<chains.t.len:
    if abs(O.chainGeom.t - chains.t[i]) > 0.001: continue
    O.chainGeom.B_BH = chains.B_BH[i]
    O.chainGeom.d = chains.d[i]
    O.chainGeom.d1 = chains.d1[i]
    O.chainGeom.h = chains.h[i]
    O.chainGeom.b = chains.b[i].float
    O.check.Fp = chains.F[i].float
    O.q = chains.q[i].float
    O.chainGeom.S = chains.S[i].float
    O.chainGeom.B_BH = chains.B_BH[i]

  for i in 0..<max_rotation_speed.t.len:
    if abs(O.chainGeom.t - max_rotation_speed.t[i]) > 0.001: continue
    O.check.`[n1]` = max_rotation_speed.n[i].float
    if I.env >= 0.9: O.check.`[n1]` *= 1.25
  
  let
    V = O.geom.z1.float * I.n1.float * O.chainGeom.t / 60000
    Ft = I.P1 / V

  O.check.p = Ft * K_sum / O.chainGeom.S

  O.geom.a = 40 * O.chainGeom.t

  # number of links, rounded up to an even number
  O.geom.L = (((2*O.geom.a) / O.chainGeom.t) + ((O.geom.z1 + O.geom.z2).float / 2) + ((O.geom.z2 - O.geom.z1).float / (2*Pi)).pow(2) * (O.chainGeom.t / O.geom.a)).round.int
  if O.geom.L mod 2 != 0: inc O.geom.L

  # refined center distance
  block:
    let
      half_sum = (O.geom.z1 + O.geom.z2).float / 2
      corr = 8 * ((O.geom.z2 - O.geom.z1).float / (2*Pi)).pow(2)
    O.geom.a = (O.chainGeom.t / 4) * (O.geom.L.float - half_sum + ((O.geom.L.float - half_sum).pow(2) - corr).sqrt)

  # mounting center distance a'', rounded to an integer
  O.geom.a_mount = (0.997 * O.geom.a).round

  # pitch diameters
  O.geom.d1 = O.chainGeom.t / sin(Pi / O.geom.z1.float)
  O.geom.d2 = O.chainGeom.t / sin(Pi / O.geom.z2.float)

  # outer diameters
  let
    λ = O.chainGeom.t / O.chainGeom.d1
    K = toothHeightCoeff(λ)
  O.geom.De1 = O.chainGeom.t * (K + 1/tan(Pi / O.geom.z1.float))
  O.geom.De2 = O.chainGeom.t * (K + 1/tan(Pi / O.geom.z2.float))

  # safety factor
  let Kf = case I.orientation
    of Horizontal: 6.0
    of Vertical: 1.0
  O.check.`[s]` = standardPitchStrength_for(I.n1, O.chainGeom.t)
  O.check.s = O.check.Fp / (Ft * K_d + O.q * V.pow(2) + ((9.81 * Kf * O.q * O.geom.a_mount) / 1000))

  # force acting on the shafts
  let K_B = case I.orientation
    of Horizontal:
      case I.loadKind
        of Calm: 1.15
        else: 1.3
    of Vertical:
      case I.loadKind
        of Calm: 1.05
        else: 1.15
  
  O.check.FB = (Ft * K_B).round
  

  
  



when isMainModule:
  const I = ChainTransmissionInput(T1: 304156.74204955436, P1: 6091.076549222015, w1: 19.03281549299816, n1: 181.74999999999997, u: 3.1721359154996933, loadKind: Calm, orientation: Horizontal, regulating: Periodic, lubricationMethod: Periodic, workPeriod: SingleShift, rowCount: SingleRow, env: 0.0)

  const O = computeChainTransmission(I)

  dump O

  
  discard dump O.geom.z1
  discard dump O.geom.z2
  discard dump O.u

  discard dump ((I.u - O.u) / I.u) * 100
    # should be < 3%


  
  # -----------------

  discard dump O.chainGeom

  discard dump O.chainGeom.t
    # chain pitch


  
  # -----------------

  discard dump O.geom

  discard dump O.geom.a
  discard dump O.geom.a_mount
  discard dump O.geom.d1
  discard dump O.geom.d2
  discard dump O.geom.L
  discard dump O.geom.De1
  discard dump O.geom.De2



  # -----------------
  discard dump O.check

  discard dump I.n1 / O.check.`[n1]` * 100
    # should be < 100%

  discard dump (O.check.p - O.check.`[p]`) / O.check.`[p]` * 100
    # should be in the range -10%..+5%

  discard dump O.check.s >= O.check.`[s]`
  discard dump (O.check.s - O.check.`[s]`) / O.check.`[s]` * 1
    # safety factor, should be >= 1.3

  discard dump O.check.FB





  discard dump "end"

