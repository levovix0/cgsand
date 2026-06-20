import std/[sequtils, math, strutils]
import ./utils


type Engine* = object
  name*: string
    ## Engine name

  P*: float
    ## Engine power, kW

  n*: float
    ## Engine rotational speed, rpm

  Tt*: float
    ## T_max / T_norm


columnTable engines, `const`:
  P    | name_3000  | n_3000 | Tt_3000 | name_1500  | n_1500 | Tt_1500 | name_1000   | n_1000 | Tt_1000 | name_750    | n_750 | Tt_750
  0.37 | "-"        | 0.0    | 0.0     | "-"        | 0.0    | 0.0     | "АИР71A6"   | 915.0  | 2.2     | "-"         | 0.0   | 0.0
  0.55 | "-"        | 0      | 0.0     | "АИР71A4"  | 1357   | 2.2     | "АИР71B6"   | 915    | 2.2     | "-"         | 0.0   | 0.0
  0.75 | "АИР71A2"  | 2820   | 2.2     | "АИР71B4"  | 1350   | 2.2     | "АИР80A6"   | 920    | 2.2     | "АИР90LA8"  | 705   | 2.2
  1.1  | "АИР71B2"  | 2805   | 2.2     | "АИР80A4"  | 1395   | 2.2     | "АИР80B6"   | 920    | 2.2     | "АИР90LB8"  | 715   | 2.2
  1.5  | "АИР80A2"  | 2850   | 2.2     | "АИР80B4"  | 1395   | 2.2     | "АИР90L6"   | 925    | 2.2     | "АИР100L8"  | 702   | 2.2
  2.2  | "АИР80B2"  | 2850   | 2.2     | "АИР90L4"  | 1395   | 2.2     | "АИР100L6"  | 945    | 2.2     | "АИР112MA8" | 709   | 2.2
  3.0  | "АИР90L2"  | 2850   | 2.2     | "АИР100S4" | 1410   | 2.2     | "АИР112MA6" | 950    | 2.2     | "АИР112MB8" | 709   | 2.2
  4.0  | "АИР100L2" | 2850   | 2.2     | "АИР100L4" | 1410   | 2.2     | "АИР112MB6" | 950    | 2.2     | "АИР132S8"  | 716   | 2.2
  5.5  | "АИР100S2" | 2850   | 2.2     | "АИР112M4" | 1432   | 2.2     | "АИР132S6"  | 960    | 2.2     | "АИР132M8"  | 712   | 2.2
  7.5  | "АИР112M2" | 2895   | 2.2     | "АИР132S4" | 1440   | 2.2     | "АИР132M6"  | 960    | 2.2     | "АИР160S8"  | 727   | 2.4
  11.0 | "АИР132M2" | 2910   | 2.2     | "АИР132M4" | 1447   | 2.2     | "АИР160S6"  | 970    | 2.5     | "АИР160M8"  | 727   | 2.4
  15.0 | "АИР160S2" | 2910   | 2.7     | "АИР160S4" | 1455   | 2.9     | "АИР160M6"  | 970    | 2.6     | "АИР180M8"  | 731   | 2.2
  18.5 | "АИР160M2" | 2910   | 2.7     | "АИР160M4" | 1455   | 2.9     | "АИР180M6"  | 980    | 2.4     | "-"         | 0     | 0
  22.0 | "АИР180S2" | 2919   | 2.7     | "АИР180S4" | 1462   | 2.4     | "-"         | 0      | 0.0     | "-"         | 0     | 0
  30.0 | "АИР180M2" | 2925   | 2.7     | "АИР180M4" | 1470   | 2.7     | "-"         | 0      | 0.0     | "-"         | 0     | 0


proc selectEngine*(P: float, n: float, env: float): Engine =
  let iP = engines.P.mapIt(it >= P).find(true)  # select the engine with power higher than required
  if iP == -1: raise ValueError.newException("unable to find required engine")
  result.P = engines.P[iP]

  var engines_n = [engines.n_3000[iP], engines.n_1500[iP], engines.n_1000[iP], engines.n_750[iP]]
  let n_scores = engines_n.mapIt((if it == 0: -1000.0 else: 1 / (abs(sqrt(it) - sqrt(n)))))
  let col = n_scores.maxIndex
  result.n = engines_n[col]

  var engines_Tt = [engines.Tt_3000[iP], engines.Tt_1500[iP], engines.Tt_1000[iP], engines.Tt_750[iP]]
  result.Tt = engines_Tt[col]

  var engines_name = [engines.name_3000[iP], engines.name_1500[iP], engines.name_1000[iP], engines.name_750[iP]]
  result.name = engines_name[col]



columnTable engines_geometry, `const`:
  name      | n_pol         | d1
  "АИР71"   | @[2, 4, 6, 8] | 19.0
  "АИР80A"  | @[2, 4, 6, 8] | 22.0
  "АИР80B"  | @[2, 4, 6, 8] | 22.0
  "АИР90L"  | @[2, 4, 6, 8] | 24.0
  "АИР100S" | @[2, 4, 6, 8] | 28.0
  "АИР100L" | @[2, 4, 6, 8] | 28.0
  "АИР112M" | @[2, 4, 6, 8] | 32.0
  "АИР132S" | @[4, 6, 8]    | 38.0
  "АИР132M" | @[2, 4, 6, 8] | 38.0
  "АИР160S" | @[2]          | 42.0
  "АИР160S" | @[4, 6, 8]    | 48.0
  "АИР160M" | @[2]          | 42.0
  "АИР160M" | @[4, 6, 8]    | 48.0
  "АИР180S" | @[2]          | 48.0
  "АИР180S" | @[4, 6, 8]    | 55.0
  "АИР180M" | @[2]          | 48.0
  "АИР180M" | @[4, 6, 8]    | 55.0

proc selectEngineShaftDiameter*(engineName: string): float =
  let poleCount = parseInt($engineName[^1])

  proc tryFind(base: string): float =
    for i in 0..<engines_geometry.name.len:
      if engines_geometry.name[i] == base and poleCount in engines_geometry.n_pol[i]:
        return engines_geometry.d1[i]
    raise ValueError.newException("no value")

  let base = engineName[0 ..< ^1]
  try:
    return tryFind(base)
  except ValueError:
    if base.len > 0 and base[^1] in {'A', 'B'}:
      try:
        return tryFind(base[0 ..< ^1])
      except ValueError:
        discard
    raise ValueError.newException("no geometry data for engine " & engineName)



proc rmp_to_radps*(x: float): float =
  ## Converts rpm to rad/s
  x * (Pi / 30)

proc radps_to_rmp*(x: float): float =
  ## Converts rad/s to rpm
  x / (Pi / 30)

