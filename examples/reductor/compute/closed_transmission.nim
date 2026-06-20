import std/[math, algorithm]
import pkg/[vmath]
import ./[utils, common]


type
  TransmissionElementKind = enum
    Gear   ## the smaller gear
    Wheel  ## the bigger gear


  ClosedTransmissionInput* = object
    T1*: float
      ## Torque, N*mm
      ## For the gear (smaller wheel)

    T2*: float
      ## Torque, N*mm
      ## For the wheel (larger wheel)

    w1*: float
      ## ω_1, Angular speed, rad/s (s^-1)
      ## For the gear (smaller wheel)

    w2*: float
      ## ω_2, Angular speed, rad/s (s^-1)
      ## For the wheel (larger wheel)

    n1*: float
      ## Rotational speed, rpm
      ## For the gear (smaller wheel)

    n2*: float
      ## Rotational speed, rpm
      ## For the wheel (larger wheel)

    u*: float
      ## Gear ratio between the gear and the wheel, 1

    teethKind*: TeethKind
    reverseMotionAllowance*: ReversiveMotionAllowance
    placementKind*: PlacementKind
    gearingKind*: GearingKind
    speedKind*: SpeedKind
    transmissionKind*: TransmissionKind

    env*: float
      ## Operating conditions (0 - harshest, 1 - mildest)


  ClosedTransmissionGeometry* = object
    d1*: float    ## Pitch diameter of the gear
    d2*: float    ## Pitch diameter of the wheel
    a_w*: float   ## Center distance
    d_a1*: float  ## Outer diameter of the gear
    d_a2*: float  ## Outer diameter of the wheel
    d_f1*: float  ## Root diameter of the gear
    d_f2*: float  ## Root diameter of the wheel
    b1*: float    ## Face width of the gear
    b2*: float    ## Face width of the wheel


  ClosedTransmissionCheck* = object
    `[σ_H]`*: float
      ## Maximum allowable contact stress

    `[σ_F]`*: float
      ## Maximum allowable bending stress

    σ_H*: float
      ## Contact stress

    σ_F*: float
      ## Bending stress

    percisionRank*: int

    F_n*: float
      ## Total (normal force)

    F_t*: float
      ## Tangential (the largest)

    F_r*: float
      ## Radial (the medium one)

    F_a*: float
      ## Axial (the smallest, present only in helical transmissions)


  ClosedTransmissionOutput* = object
    d1*: float
      ## Approximate size (diameter) of the gear blank, mm

    d2*: float
      ## Approximate size (diameter) of the wheel blank, mm

    steel1*: SteelMaterial
      ## Gear material

    steel2*: SteelMaterial
      ## Wheel material

    max_contact_tension*: float
      ## [σ]_Н, Allowable contact stress, MPa

    axial_distance*: float
      ## Computed center distance from contact strength conditions

    teeth_modulo*: float
      ## m_n, Gear modulo, mm

    cos_teeth_angle*: float
      ## cos(β)

    teeth_angle*: float
      ## β

    z1*: int
      ## Number of gear teeth

    z2*: int
      ## Number of wheel teeth

    u*: float
      ##

    K_H*: float
      ##

    geom*: ClosedTransmissionGeometry
    check*: ClosedTransmissionCheck



columnTable axialDistances, `const`:
  second  | first
  50.0    | _
  63      | 71.0
  80      | 90
  100     | 112
  140     | 125
  180     | 160
  224     | 200
  280     | 250
  355     | 315
  450     | 400
  560     | 500


columnTable teethModulos, `const`:
  first   | second
  1.5     | 1.75
  2       | 2.25
  2.5     | 2.75
  3       | 3.5
  4       | 4.5
  5       | 5.5
  6       | 7
  8       | 9
  10      | 11



columnTable transmission_percision, `const`:
  # Precision rank | Straight cylindric | Straight conic | Helical cylindric | Helical conic
  rank             | s_cyl              | s_cone         | ns_cyl            | ns_cone
  5 #[ and more ]# | (15.0..999.0)      | (12.0..999.0)  | (30.0..999.0)     | (20.0..999.0)
  6                | (0.0..15.0)        | (0.0..12.0)    | (0.0..30.0)       | (0.0..20.0)
  7                | (0.0..10.0)        | (0.0..8.0)     | (0.0..15.0)       | (0.0..10.0)
  8                | (0.0..6.0)         | (0.0..4.0)     | (0.0..10.0)       | (0.0..7.0)
  9                | (0.0..2.0)         | (0.0..1.5)     | (0.0..4.0)        | (0.0..3.0)


columnTable strain_k_Ha, `const`:
  # Precision rank | V <= 1 | V ~== 5 | V ~== 10 | V ~== 15 | V ~== 20
  rank             | v_1    | v_5     | v_10     | v_15     | v_20
  6                | 1.0    | 1.02    | 1.03     | 1.04     | 1.05
  7                | 1.02   | 1.05    | 1.07     | 1.10     | 1.12
  8                | 1.06   | 1.09    | 1.13     | _        | _
  9                | 1.1    | 1.16    | _        | _        | _


columnTable strain_k_Hb, `const`:
  # Coefficient | Cantilever | Asymmetrical | Symmetrical
  Ψ_bd          | console    | asymmetric   | symmetric
  0.4           | 1.15       | 1.04         | 1.0
  0.6           | 1.24       | 1.06         | 1.02
  0.8           | 1.30       | 1.08         | 1.03
  1.0           | _          | 1.11         | 1.04
  1.2           | _          | 1.15         | 1.05
  1.4           | _          | 1.18         | 1.07
  1.6           | _          | 1.22         | 1.09
  1.8           | _          | 1.25         | 1.11
  2.0           | _          | 1.30         | 1.14


columnTable strain_k_Fb, `const`:
  # Coefficient | Cantilever | Roller | Asymmetrical | Symmetrical
  Ψ_bd          | console    | roller | asymmetric   | symmetric
  0.2           | 1.08       | 1.10   | 1.04         | 1.0
  0.4           | 1.37       | 1.21   | 1.07         | 1.03
  0.6           | 1.62       | 1.40   | 1.12         | 1.05
  0.8           | _          | 1.59   | 1.17         | 1.08
  1.0           | _          | _      | 1.23         | 1.10
  1.2           | _          | _      | 1.30         | 1.13
  1.4           | _          | _      | 1.38         | 1.19
  1.6           | _          | _      | 1.45         | 1.25
  1.8           | _          | _      | 1.53         | 1.32


proc select_percision_rank(V: float, teeth: TeethKind, trans: TransmissionKind): int =
  let vrange = case teeth
  of Straight:
    case trans
    of Cylindric: transmission_percision.s_cyl
    of Conic: transmission_percision.s_cone
  of Helical:
    case trans
    of Cylindric: transmission_percision.ns_cyl
    of Conic: transmission_percision.ns_cone
  for i, x in vrange:
    if V in x: return transmission_percision.rank[i]


proc selectStrain_K_Ha(V: float, rank: int): float =
  if   V <= 1:  strain_k_Ha.v_1[rank - 6]
  elif V <= 5:  strain_k_Ha.v_5[rank - 6]
  elif V <= 10: strain_k_Ha.v_10[rank - 6]
  elif V <= 15: strain_k_Ha.v_15[rank - 6]
  else:         strain_k_Ha.v_20[rank - 6]



proc strain_k_Hv(V: float, kind: TeethKind, rank: int): float =
  if kind == Straight:
    1.05
  else:
    if V <= 5:    1.0
    elif V <= 10: 1.1
    elif V <= 15: 1.2
    else:         1.5


proc teeth_form_Yf(z: float): float =
  let z = z.round.int
  let Zs =  [17,   20,   25,   30,   40,   50,   60,   80]
  let Yfs = [4.18, 4.09, 3.90, 3.80, 3.70, 3.66, 3.62, 3.61]
  if z < 17: return 4.18
  if z >= 100: return 3.61
  for i in 0..<Zs.len:
    if z >= Zs[i]:
      return Yfs[i]


proc selectStrain_K_Hb(Ψ_bd: float, placement: PlacementKind): float =
  for i in countdown(strain_k_Hb.Ψ_bd.high, 0):
    if Ψ_bd > strain_k_Hb.Ψ_bd[i]:
      return case placement
        of Symmetrical: strain_k_Hb.symmetric[i]
        of Asymmetrical: strain_k_Hb.asymmetric[i]
        of Console: strain_k_Hb.console[i]


proc selectStrain_K_Fb(Ψ_bd: float, placement: PlacementKind): float =
  for i in countdown(strain_k_Fb.Ψ_bd.high, 0):
    if Ψ_bd > strain_k_Fb.Ψ_bd[i]:
      return case placement
        of Symmetrical: strain_k_Fb.symmetric[i]
        of Asymmetrical: strain_k_Fb.asymmetric[i]
        of Console: strain_k_Fb.console[i]


proc strain_k_Fv(V: float, kind: TeethKind, rank: int): float =
  case rank
  of 6:
    if V <= 3:   [1.0, 1.0][kind.int]
    elif V <= 8: [1.2, 1.0][kind.int]
    else:        [1.3, 1.1][kind.int]
  of 7:
    if V <= 3:   [1.15, 1.0][kind.int]
    elif V <= 8: [1.35, 1.0][kind.int]
    else:        [1.45, 1.2][kind.int]
  of 8:
    if V <= 3:   [1.45, 1.3][kind.int]
    elif V <= 8: [1.45, 1.3][kind.int]
    else:        [999.0, 1.4][kind.int]
  elif rank > 8:
    strain_k_Fv(V, kind, 8)
  else:
    strain_k_Fv(V, kind, 6)



proc selectClosestAxialDistance(minimal: float): float =
  for x in (@(axialDistances.first) & @(axialDistances.second)).sorted:
    if x >= minimal: return x



proc selectClosestTeethModulo(v: float, speedKind: SpeedKind): float =
  case speedKind
  of Fast:
    for x in (@(teethModulos.first) & @(teethModulos.second)).sorted:
      if x >= v: return x
  of Slow:
    for x in (@(teethModulos.first) & @(teethModulos.second)).sorted(Descending):
      if x <= v: return x


proc selectNextLowerTeethModulo(v: float): float =
  for x in (@(teethModulos.first) & @(teethModulos.second)).sorted(Descending):
    if x < (v - 0.01): return x



proc computeClosedTransmission*(I: ClosedTransmissionInput): ClosedTransmissionOutput =
  template O: var ClosedTransmissionOutput = result

  # ==========================
  # --- Material selection ---
  # ==========================
  let
    c = 1.0

  O.d1 = case I.teethKind
    of Straight: 3   * (I.T2 / (c * I.u.pow(2))).pow(1/3)
    of Helical:  2.2 * (I.T2 / (c * I.u.pow(2))).pow(1/3)

  O.d2 = O.d1 * I.u

  var
    max_contact_tension1: float
      ## [σ]_H1
    max_contact_tension2: float
      ## [σ]_H2
  
  var
    max_bending_tension1: float
      ## [σ]_F1
    max_bending_tension2: float
      ## [σ]_F2

  O.steel2 = selectSteel(
    I.env, I.reverseMotionAllowance, O.d2,
    0,
    max_contact_tension2,
    max_bending_tension2,
  )
  
  ## Select the gear material so that it is strictly harder than the wheel material
  O.steel1 = selectSteel(
    I.env, I.reverseMotionAllowance, O.d1,
    max(O.steel2.hardness + mix(50.0, 20.0, I.env), O.steel2.hardness * I.u.pow(1/6)),
    max_contact_tension1,
    max_bending_tension1,
  )

  O.max_contact_tension = min(max_contact_tension2 * 1.25, (max_contact_tension1 + max_contact_tension2) / 2)



  # ====================================================
  # --- Gearing parameters and gear wheel dimensions ---
  # ====================================================
  let
    ## Load factor
    K_H = case I.placementKind
      of Symmetrical: mix(1.2,  1.1,  I.env)
      of Asymmetrical: mix(1.25, 1.2,  I.env)
      of Console:     mix(1.4,  1.25, I.env)

    ## Wheel width factor relative to the center distance
    ##   = b2 / a_w
    Ψ_ba_w = case I.teethKind
      of Straight: [0.2, 0.25, 0.315]
      of Helical:  [0.315, 0.4, 0.5]

    Ψ_ba_w_i = 1
      ## the middle value is used

    C = case I.teethKind
      of Straight: 310.0
      of Helical:  270.0

    ## Minimum computed center distance from contact strength conditions
    min_axial_distance = (
      case I.gearingKind
      of Outer: I.u + 1
      of Inner: I.u - 1
    ) * (
      (C / (O.max_contact_tension * I.u)).pow(2) *
      (I.T2 * K_H / Ψ_ba_w[Ψ_ba_w_i])
    ).pow(1/3)

  ## Computed center distance from contact strength conditions
  O.axial_distance = selectClosestAxialDistance(min_axial_distance)

  let
    teeth_modulo_k = 0.01

    ## Gear modulo
    teeth_modulo_req = case I.gearingKind
      of Inner: teeth_modulo_k * O.axial_distance
      of Outer: teeth_modulo_k * O.axial_distance * ((I.u + 1) / (I.u - 1))

  ## Gear modulo, standardized per GOST 9563-60
  O.teeth_modulo = selectClosestTeethModulo(teeth_modulo_req, I.speedKind)

  while true:
    let
      β_pre = case I.teethKind
        of Straight: 0..0
        of Helical: 8..15

      teeth_count_both = ((2 * O.axial_distance) / O.teeth_modulo * cos((β_pre.a + β_pre.b) / 2)).round.int

    O.cos_teeth_angle = case I.teethKind
      of Straight: 1.0
      else: (teeth_count_both.float * O.teeth_modulo) / (2 * O.axial_distance)

    O.teeth_angle = arccos(O.cos_teeth_angle)

    O.z1 = case I.gearingKind
      of Outer: (teeth_count_both.float / (I.u + 1)).round.int
      of Inner: ((2 * O.axial_distance) / (O.teeth_modulo * (I.u - 1))).round.int

    O.z2 = case I.gearingKind
      of Outer: teeth_count_both - O.z1
      of Inner: (O.z1.float * I.u).round.int

    if O.z1 < 17:
      O.teeth_modulo = selectNextLowerTeethModulo(O.teethModulo)
      continue
    break

  O.u = O.z2 / O.z1

  O.geom.d1 = O.teeth_modulo * O.z1.float / O.cos_teeth_angle
  O.geom.d2 = O.teeth_modulo * O.z2.float / O.cos_teeth_angle

  O.geom.a_w = case I.gearingKind
    of Outer: (O.geom.d2 + O.geom.d1) / 2
    of Inner: (O.geom.d2 - O.geom.d1) / 2

  O.geom.d_a1 = O.geom.d1 + 2 * O.teeth_modulo
  O.geom.d_a2 = case I.gearingKind
    of Outer: O.geom.d2 + 2 * O.teeth_modulo
    of Inner: O.geom.d2 - 2 * O.teeth_modulo

  O.geom.d_f1 = O.geom.d1 - 2.5 * O.teeth_modulo
  O.geom.d_f2 = case I.gearingKind
    of Outer: O.geom.d2 - 2.5 * O.teeth_modulo
    of Inner: O.geom.d2 + 2.5 * O.teeth_modulo

  O.geom.b2 = Ψ_ba_w[Ψ_ba_w_i] * O.geom.a_w
  O.geom.b1 = O.geom.b2 + 5


  # =================================
  # --- Transmission verification ---
  # =================================

  let
    Ψ_bd = O.geom.b2 / O.geom.d1
    V = (I.w1 * O.geom.d1) / (2 * 1000)
      ## Tangential speed, m/s
      ## = Pi * O.geom.d1 * O.geom.n1 / (60 * 1000)

  O.check.percisionRank = select_percision_rank(V, I.teethKind, I.transmissionKind)

  let
    K_Ha = case I.teethKind
      # of Straight: 1.0
      of Straight: selectStrain_K_Ha(V, O.check.percisionRank)
      of Helical: selectStrain_K_Ha(V, O.check.percisionRank)
    
    K_Hb = selectStrain_K_Hb(Ψ_bd, I.placementKind)
    
    K_Hv = strain_k_Hv(V, I.teethKind, O.check.percisionRank)

  O.K_H = K_Ha * K_Hb * K_Hv

  O.check.`[σ_H]` = O.max_contact_tension

  O.check.σ_H =
    C / (O.geom.a_w * O.u) *
    sqrt(I.T2 * O.K_H / O.geom.b2 * (O.u + (
      case I.gearingKind
      of Outer: 1
      of Inner: -1
    )).pow(3))
  
  let
    Z_V1 = O.z1.float / (O.cos_teeth_angle).pow(3)
    Z_V2 = O.z2.float / (O.cos_teeth_angle).pow(3)

    Y_F1 = teeth_form_Yf(Z_V1)
    Y_F2 = teeth_form_Yf(Z_V2)

    less_durable_teeth = if max_bending_tension1/Y_F1 < max_bending_tension1/Y_F1: Gear else: Wheel

    K_Fa = case I.teethKind
      of Straight: 1.0
      of Helical: 0.75

    K_Fb = selectStrain_K_Fb(Ψ_bd, I.placementKind)

    K_Fv = strain_k_Fv(V, I.teethKind, O.check.percisionRank)

    K_F = K_Fa * K_Fb * K_Fv

    Y_b = 1 - (O.teeth_angle / 140.degToRad)

  O.check.`[σ_F]` = min(max_bending_tension1, max_bending_tension2)
  O.check.σ_F = case less_durable_teeth
    of Gear: (2 * I.T1 * K_F) / (O.z1.float * O.geom.b1 * O.teeth_modulo.pow(2)) * Y_F1 * Y_b
    of Wheel: (2 * I.T2 * K_F) / (O.z2.float * O.geom.b2 * O.teeth_modulo.pow(2)) * Y_F2 * Y_b

  O.check.F_t = 2 * I.T1 / O.geom.d1
  O.check.F_r = 2 * O.check.F_t * tan(20.degToRad)  # 20 degrees is the pressure angle
  O.check.F_a = 2 * O.check.F_t * tan(O.teeth_angle)
  O.check.F_n = 2 * O.check.F_t / (cos(20.degToRad) * cos(O.teeth_angle))



when isMainModule:
  const I = ClosedTransmissionInput(T1: 81640.36787130294, T2: 304156.74204955436, w1: 76.13126197199264, w2: 19.03281549299816, n1: 726.9999999999999, n2: 181.74999999999997, u: 4.0, teethKind: Straight, reverseMotionAllowance: NonReversive, placementKind: Symmetrical, gearingKind: Outer, speedKind: Fast, transmissionKind: Cylindric, env: 0.0)

  const O = computeClosedTransmission(I)

  dump O
  
  discard dump O.d1
  discard dump O.d2

  discard dump O.steel1
  discard dump O.steel2

  discard dump O.max_contact_tension
  discard dump O.axial_distance

  block: # --- gear and wheel ---
    discard dump O.teeth_angle
    discard dump O.teeth_modulo

    # gear
    discard dump O.z1
    discard dump O.geom.b1

    # wheel
    discard dump O.z2
    discard dump O.geom.b2

  discard dump O.geom
  discard dump O.check.percisionRank

  discard dump O.u
  discard dump abs(I.u - O.u) / max(I.u, O.u) * 100
    # should be < 3%

  discard dump:
    case I.teethKind
    of Straight: O.geom.b2 < O.geom.d1
    of Helical: O.geom.b2 < O.geom.d1 * 1.5
    # should be true

  discard dump O.check.`[σ_H]`
  discard dump O.check.`σ_H`
  discard dump (O.check.`σ_H` - O.check.`[σ_H]`) / O.check.`[σ_H]` * 100
    # should be in the range -10%..+5%

  discard dump (O.check.`σ_F` - O.check.`[σ_F]`) / O.check.`[σ_F]` * 100
    # should be < 0%

  discard dump O.check

  discard dump O.check.F_n
  discard dump O.check.F_t  # tangential
  discard dump O.check.F_r  # radial
  discard dump O.check.F_a  # axial



  discard dump "end"

