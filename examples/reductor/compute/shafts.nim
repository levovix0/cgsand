import std/[math, algorithm]
import pkg/[vmath]
import ./[utils, common]


type
  ShaftEndKind* = enum
    OpenTransmission  ## Open transmission (pulley, sprocket), [τ]_k = 15 MPa
    Coupling          ## Coupling, [τ]_k = 25 MPa

  ShaftLengthKind* = enum
    Long
    Short


  ShaftsInput* = object
    T_B*: float
      ## Torque of the high-speed shaft, N·mm

    T_T*: float
      ## Torque of the low-speed shaft, N·mm

    d_ed*: float
      ## Engine shaft diameter, mm

    lengthKind*: ShaftLengthKind
      ## Whether long or short shafts are needed; determines the shaft design

    endKind_B*: ShaftEndKind
      ## Output end type of the high-speed shaft

    endKind_T*: ShaftEndKind
      ## Output end type of the low-speed shaft

    env*: float
      ## Operating conditions (0 - harshest, 1 - mildest)


  ShaftGeometry* = object
    d*: float
      ## Diameter of the shaft output end, mm

    l*: float
      ## Length of the shaft output end (design 1), mm

    r*: float
      ## Fillet radius r, mm

    c*: float
      ## Chamfer c×45°, mm

    key_l*: float
      ## Key length

    b*: float
      ## Key width b, mm

    h*: float
      ## Key height h, mm

    t1*: float
      ## Shaft keyway depth t1, mm

    t2*: float
      ## Hub keyway depth t2, mm


  ShaftsGeometry* = object
    B*: ShaftGeometry
      ## High-speed shaft

    T*: ShaftGeometry
      ## Low-speed shaft


  ShaftsCheck* = object
    d_min_B*: float
      ## Computed minimum diameter of the high-speed shaft, formula 4.1, mm

    d_min_T*: float
      ## Computed minimum diameter of the low-speed shaft, formula 4.1, mm

    d_B_coupling_ok*: bool
      ## d_Б ∈ (0.8·d_эд … 1.2·d_эд) — compatibility with the coupling, formula 4.2

    d_B_leq_d_T*: bool
      ## d_Б ≤ d_Т — condition 4.4


  ShaftsOutput* = object
    r*: float
      ## Fillet radius, mm

    geom*: ShaftsGeometry
    check*: ShaftsCheck




columnTable gear_series_data, `const`:
  # ------------- Diameter d ----------- --------- Length l ----------
  #     row 1      |       row 2       | design 1      | design 2     |
  d_row1           | d_row2            | l_mk1         | l_mk2        | r     | c
  @[10, 11]        | newSeq[int]()     | 23.0          | 20.0         | 0.6   | 0.4
  @[12, 14]        | @[]               | 30            | 25           | 1.0   | 0.6
  @[16, 18]        | @[19]             | 40            | 28           | 1.0   | 0.6
  @[20, 22]        | @[24]             | 50            | 36           | 1.6   | 1.0
  @[25, 28]        | @[]               | 60            | 42           | 1.6   | 1.0
  @[32, 36]        | @[30, 35, 38]     | 80            | 58           | 2.0   | 1.6
  @[40, 45]        | @[42, 48]         | 110           | 82           | 2.0   | 1.6
  @[50, 55]        | @[52, 56]         | 110           | 82           | 2.5   | 2.0
  @[60, 70]        | @[63, 65, 71, 75] | 140           | 105          | 2.5   | 2.0
  @[80, 90]        | @[85, 95]         | 170           | 130          | 3.0   | 2.5
  @[100, 110, 125] | @[120]            | 210           | 165          | 3.0   | 2.5
  @[140]           | @[130, 150]       | 250           | 200          | 4.0   | 3.0
  @[160, 180]      | @[170]            | 300           | 240          | 4.0   | 3.0
  @[200, 220]      | @[190]            | 350           | 280          | 5.0   | 4.0
  @[250]           | @[240, 260]       | 410           | 330          | 5.0   | 4.0
  @[280, 320]      | @[300]            | 470           | 380          | 5.0   | 4.0


columnTable key_data, `const`:
  # Prismatic keys (per GOST 23360-78)
  d        | b  | h  | t1   | t2
  (10..12) | 4  | 4  | 2.5  | 1.8
  (12..17) | 5  | 5  | 3.0  | 2.3
  (17..22) | 6  | 6  | 3.5  | 2.8
  (22..30) | 8  | 7  | 4.0  | 3.3
  (30..38) | 10 | 8  | 5.0  | 3.3
  (38..44) | 12 | 8  | 5.0  | 3.3
  (44..50) | 14 | 9  | 5.5  | 3.8
  (50..58) | 16 | 10 | 6.0  | 4.3
  (58..65) | 18 | 11 | 7.0  | 4.4
  (65..75) | 20 | 12 | 7.5  | 4.9
  (75..85) | 22 | 14 | 9.0  | 5.4
  (85..95) | 25 | 14 | 9.0  | 5.4
  (95..11) | 28 | 16 | 10.0 | 6.4


# key lengths per GOST 23360-78
const key_l_gost = @[
  @[6.0, 8, 10, 12, 14, 16, 18, 20, 22, 25, 28, 32, 36, 40, 45, 50, 56, 63, 70, 80, 90, 100, 110, 125, 140, 160, 180, 200, 220, 250, 280, 320, 360, 400, 450, 500],
  @[2.0, 13, 14, 16, 18, 20, 22, 23, 26, 30, 35, 40, 48, 54, 60, 66, 75, 80, 90, 100, 110, 120, 140, 160, 175, 195, 220, 250],
  @[12.0, 14, 16, 18, 20, 22, 25, 28, 32, 35, 40, 45, 50, 55, 62, 70, 80, 90, 100, 110, 125, 140, 158, 178, 200, 225],
  @[6.0, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 18, 20, 22, 25, 30, 35, 40, 45, 50, 55, 60, 70, 80, 90, 100],
]




proc selectStandardDiam(d_min: float, lengthKind: ShaftLengthKind): tuple[d, l, r, c: float] =
  ## Selects the standard shaft end diameter and length from table 4.1.
  ## Returns the smallest standard d >= d_min.
  for i in 0..<gear_series_data.d_row1.len:
    var group_d = gear_series_data.d_row1[i] & gear_series_data.d_row2[i]
    group_d.sort()
    for d in group_d:
      if d.float >= d_min:
        case lengthKind
        of Long:
          return (d.float, gear_series_data.l_mk1[i], gear_series_data.r[i], gear_series_data.c[i])
        of Short:
          return (d.float, gear_series_data.l_mk2[i], gear_series_data.r[i], gear_series_data.c[i])
  raise ValueError.newException("d_min too large for gear_series_data")


proc selectKeyDims(d: float): tuple[b, h, t1, t2: float] =
  ## Selects key dimensions from table 4.2.
  for i in 0..<key_data.d.len:
    if d > key_data.d[i].a.float and d <= key_data.d[i].b.float:
      return (key_data.b[i].float, key_data.h[i].float, key_data.t1[i], key_data.t2[i])
  raise ValueError.newException("d out of range for key_data")


proc findClosestKeyL(l: float): float =
  for i, x in key_l_gost[0]:
    if l <= x: return key_l_gost[0][max(i-1, 0)]


proc applyKeyDims(geom: var ShaftGeometry) =
  let (b, h, t1, t2) = selectKeyDims(geom.d)
  geom.b  = b
  geom.h  = h
  geom.t1 = t1
  geom.t2 = t2
  geom.key_l = (geom.l - 2).findClosestKeyL  #? key length with a 2 mm margin


proc computeShafts*(I: ShaftsInput): ShaftsOutput =
  template O: var ShaftsOutput = result

  # formula 4.1 — computed diameter
  let
    tau_k_B = case I.endKind_B
      of OpenTransmission: 15.0
      of Coupling: 25.0

    tau_k_T = case I.endKind_T
      of OpenTransmission: 15.0
      of Coupling: 25.0

  O.check.d_min_B = (I.T_B / (0.2 * tau_k_B)).pow(1.0/3.0)
  O.check.d_min_T = (I.T_T / (0.2 * tau_k_T)).pow(1.0/3.0)

  # low-speed shaft
  let (d_T, l_T, r_T, c_T) = selectStandardDiam(O.check.d_min_T, I.lengthKind)
  O.geom.T = ShaftGeometry(d: d_T, l: l_T, r: r_T, c: c_T)
  O.geom.T.applyKeyDims()


  # high-speed shaft (formula 4.1), coupling constraint (formula 4.2)
  let d_B_lower = case I.endKind_B
    of Coupling:
      max(O.check.d_min_B, 0.8 * I.d_ed)
    of OpenTransmission:
      O.check.d_min_B

  let (d_B, l_B, r_B, c_B) = selectStandardDiam(d_B_lower, I.lengthKind)
  O.geom.B = ShaftGeometry(d: d_B, l: l_B, r: r_B, c: c_B)
  O.geom.B.applyKeyDims()

  # checks
  O.check.d_B_coupling_ok = (I.d_ed * 0.8 <= O.geom.B.d.float and O.geom.B.d.float <= I.d_ed * 1.2)
  O.check.d_B_leq_d_T     = (O.geom.B.d <= O.geom.T.d)


  O.r = 0.4 * (O.geom.T.d - O.geom.B.d)




when isMainModule:
  const I = ShaftsInput(T_B: 81640.36787130294, T_T: 304156.74204955436, d_ed: 48.0, lengthKind: Short, endKind_B: Coupling, endKind_T: OpenTransmission, env: 0.0)

  const O = computeShafts(I)

  dump O

  discard dump O.r

  # -----------------
  discard dump O.check

  discard dump O.check.d_min_B
  discard dump O.check.d_min_T

  discard dump O.geom.B.d.float / I.d_ed
  discard dump O.check.d_B_coupling_ok
    # d_Б should be within (0.8 .. 1.2) * d_эд

  discard dump O.geom.B.d / O.geom.T.d * 100
  discard dump O.check.d_B_leq_d_T
    # d_Б <= d_Т

  # -----------------
  discard dump O.geom.B
  discard dump O.geom.T

  discard dump "end"
