import pkg/[vmath]
import ./[utils]


type
  TeethKind* = enum
    Straight  ## Spur teeth
    Helical   ## Helical teeth

  ReversiveMotionAllowance* = enum
    NonReversive
    Reversive

  PlacementKind* = enum
    Symmetrical
    Asymmetrical
    Console  ## Cantilever (overhung) placement of wheels

  GearingKind* = enum
    Inner
    Outer

  SpeedKind* = enum
    Fast  ## High-speed stage (next to the engine)
    Slow  ## Low-speed stage (next to the working unit)

  TransmissionKind* = enum
    Cylindric
    Conic  ## Bevel


  SteelWorkpieceKind* = enum
    Forged
    Rolled
    Casted

  HeatingKind* = enum
    Normalizing
    Optimizing  ## Quenching and tempering

  SteelMaterial* = object
    mark*: string
      ## Steel grade

    d*: Slice[int]
      ## Diameter range, mm

    madeKind*: SteelWorkpieceKind
      ## Manufacturing method

    tensileLimit*: float
      ## σ_в, Tensile strength limit, MPa

    fluidityLimit*: float
      ## σ_Т, Yield strength limit, MPa

    hardness*: float
      ## HB, Hardness (average), 1

    heatingKind*: HeatingKind
      ## Heat treatment method


columnTable steel, `const`:
  mark      | d           | kind   | tensile_limit | fluidity_limit | hardness | heating
  "40"      | (100..300)  | Forged | 470.0         | 245.0          | 165.0    | Normalizing
  "45"      | (100..300)  | Forged | 530           | 275            | 175      | Normalizing
  "50"      | (100..300)  | Forged | 570           | 315            | 185      | Normalizing
  "40"      | (0..90)     | Rolled | 780           | 630            | 220      | Optimizing
  "45"      | (0..90)     | Rolled | 820           | 570            | 230      | Optimizing
  "45"      | (90..120)   | Rolled | 750           | 545            | 210      | Optimizing
  "45"      | (130..999)  | Forged | 680           | 425            | 200      | Optimizing
  "30ХГС"   | (0..80)     | Rolled | 860           | 730            | 250      | Optimizing
  "30ХГС"   | (80..999)   | Forged | 785           | 625            | 225      | Optimizing
  "40Х"     | (0..100)    | Rolled | 980           | 780            | 270      | Optimizing
  "40Х"     | (100..200)  | Forged | 860           | 720            | 260      | Optimizing
  "40ХН"    | (0..100)    | Rolled | 980           | 785            | 280      | Optimizing
  "40ХН"    | (100..300)  | Forged | 910           | 760            | 265      | Optimizing
  "35ХМ"    | (0..100)    | Rolled | 950           | 840            | 300      | Optimizing
  "35ХМ"    | (0..300)    | Forged | 780           | 590            | 260      | Optimizing
  "40ХМ2МА" | (0..100)    | Rolled | 1070          | 950            | 310      | Optimizing
  "40ХМ2МА" | (100..999)  | Forged | 960           | 860            | 265      | Optimizing
  "45Л"     | (300..999)  | Casted | 520           | 290            | 180      | Normalizing
  "40Л"     | (300..999)  | Casted | 550           | 350            | 170      | Optimizing
  "45Л"     | (300..999)  | Casted | 550           | 320            | 190      | Optimizing
  "35ГЛ"    | (300..999)  | Casted | 600           | 350            | 200      | Optimizing
  "35ГСЛ"   | (300..999)  | Casted | 650           | 400            | 210      | Optimizing



proc selectSteel*(
  env: float, ## Operating conditions (0 - harshest, 1 - mildest)
  reversive: ReversiveMotionAllowance,
  d: float,   ## Wheel diameter
  minHardness: float,
  out_max_contact_tension: var float,
  out_max_bending_tension: var float,
): SteelMaterial =
  ## Selects a material from the table
  let
    K_HL = 1.0
      ## K_HL, Durability factor for gearbox design

    S_H = 1.1
      ## S_H, Safety factor

    S_F = 1.8
      ## S_F, Safety factor

    K_FL = 1.0
      ## Durability factor for gearbox design

    K_FC = case reversive  ## Reversive motion factor
      of NonReversive: 1.0
      of Reversive: mix(0.7, 0.8, env)

  for iSt in 0..<steel.mark.len:
    let mat = SteelMaterial(
      mark: steel.mark[iSt],
      d: steel.d[iSt],
      madeKind: steel.kind[iSt],
      tensileLimit: steel.tensile_limit[iSt],
      fluidityLimit: steel.fluidity_limit[iSt],
      hardness: steel.hardness[iSt],
      heatingKind: steel.heating[iSt],
    )

    if d < mat.d.a.float or d > mat.d.b.float: continue
    if mat.hardness < minHardness: continue

    let
      σ_H_lim_b2 = 2 * mat.hardness + 70
        ## Endurance limit at the base number of cycles, MPa (N / mm^2)

      max_contact_tension = σ_H_lim_b2 / S_H * K_HL
        ## [σ]_Н2, Allowable contact stress for the gear wheel, MPa (N / mm^2)

      max_bending_tension = (S_F * mat.hardness) / S_F * K_FL * K_FC
        ## [σ]_F2, Allowable bending stress for the gear wheel, MPa (N / mm^2)

    if mat.fluidity_limit < max_bending_tension or mat.fluidity_limit < max_contact_tension: continue

    out_max_contact_tension = max_contact_tension
    out_max_bending_tension = max_bending_tension
    return mat
