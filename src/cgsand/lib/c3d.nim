import std/[strutils, os]
import ./sandbox

const c3d_lib_path {.strdefine.} = ""
when c3d_lib_path == "":
  {.error: "please, provide -d:c3d_lib_path:path/to/c3d/lib".}

when defined(windows):
  {.passl: c3d_lib_path / "libc3d.lib".}
else:
  {.passl: c3d_lib_path / "libc3d.so".}


type
  # SArray[T] = object
  #   count: int
  #   upper: int
  #   delta: uint16
  #   parr: ptr UncheckedArray[T]
  
  StdVector[T] = object
    data: ptr UncheckedArray[T]
    dataEnd: ptr T
    dataCapEnd: ptr T
  
  MbArc* {.byref.} = object
    data: array[192, byte]
  
  # MbPolygon {.byref.} = object
  #   data: array[104, byte]
  
  PointCount* = int


proc len[T](v: StdVector[T]): int =
  (cast[int](v.dataEnd) - cast[int](v.data)) div sizeof(T)

proc toSeq[T](v: StdVector[T]): seq[T] =
  if v.len == 0: return
  result = newSeqUninit[T](v.len)
  copyMem(result[0].addr, v.data, v.len * sizeof(T))


proc EnableMathModules(name: cstring, nameLength: int32, key: cstring, keyLength: int32) {.importc.}
proc IsMathModelerEnable(): bool {.importc.}


proc arc*(
  center: Point2,
  radius: float64,
  p1, p2: Point2,
  ccw: bool = true,  ## true if counterclockwise, false if clockwise
): MbArc =
  proc impl(
    result: var MbArc,
    pc {.byref.}: Point2,
    rad: float64,
    p1 {.byref.}: Point2,
    p2 {.byref.}: Point2,
    initSense: int32,
  ) {.importc: "_ZN5MbArcC1ERK11MbCartPointdS2_S2_i".}

  impl(result, center, radius, p1, p2, (if ccw: 1 else: -1))


proc pointsByEventParamDelta*(arc: MbArc, count: int = 20): seq[Point2] =
  proc impl(
    this: MbArc,
    n: int,
    points: var StdVector[Point2],
  ) {.importc: "_ZNK7MbCurve25GetPointsByEvenParamDeltaEmRSt6vectorI11MbCartPointSaIS1_EE".}

  var poly: StdVector[Point2]
  impl(arc, count, poly)
  poly.toSeq


proc points*(arc: MbArc, count: int = 20): seq[Point2] =
  pointsByEventParamDelta(arc, count)


proc closed*(curve: MbArc): bool {.importc: "_ZNK5MbArc8IsClosedEv".}


proc circle*(center: Point2, radius: float64): MbArc =
  arc(center, radius, point2(1, 0), point2(1, 0))



let lic = readFile(getHomeDir()/"c3d.lic").splitLines

EnableMathModules(lic[0].cstring, lic[0].len.int32, lic[1].cstring, lic[1].len.int32)
assert IsMathModelerEnable()



when isMainModule:
  block:
    let arc = arc(point2(0, 0), 50, point2(1, 0), point2(0, 1))
    for p in arc.points(5):
      echo p

