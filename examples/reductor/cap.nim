import sandbox, geom2d, tabledef
import pkg/[vmath]
import ./[drawingGlobals]


type
  CapDesc* = object
    shaft_d*: float
      ## diameter of a shaft segment and the inner diameter of a cuff, m
    
    D*: float
      ## outer diameter of a cuff, m
    
    h*: float
      ## width of a cuff, m
    
  CapGeomParams* = object
    ## all dimensions are in meters
    ## images/cap_geom.jpg
    shaft_d*: float
    D*: float
    h*: float
    
    D1*: float
    D2*: float
    D3*: float
    d*: float
    d1*: float
    M*: float
    n*: float
    H*: float
    s*: float



columnTable cap_dimensions, `const`:
  D   | D1  | D2  | D3  | ld | ld1 | M  | n | H  | s
  62  | +15 | +30 | -10 | 7  | 14  | 6  | 4 | 10 | 5
  75  | +20 | +40 | -10 | 9  | 18  | 8  | 4 | 12 | 6
  95  | +20 | +40 | -10 | 9  | 18  | 8  | 6 | 12 | 6
  145 | +25 | +50 | -15 | 11 | 22  | 10 | 6 | 15 | 7
  180 | +30 | +60 | -15 | 13 | 24  | 12 | 6 | 18 | 8
  220 | +30 | +60 | -20 | 13 | 24  | 12 | 6 | 18 | 8



converter autoComputeGeomParams*(desc: CapDesc): CapGeomParams =
  template O: var CapGeomParams = result
  O.shaft_d = desc.shaft_d
  O.D = desc.D
  O.h = desc.h
  for i, maxD in cap_dimensions_D:
    if maxD.float > desc.D:
      O.D1 = desc.D + cap_dimensions_D1[i].float
      O.D2 = desc.D + cap_dimensions_D2[i].float
      O.D3 = desc.D + cap_dimensions_D3[i].float
      O.d = cap_dimensions_ld[i].float
      O.d1 = cap_dimensions_ld1[i].float
      O.M = cap_dimensions_M[i].float
      O.n = cap_dimensions_n[i].float
      O.H = cap_dimensions_H[i].float
      O.s = cap_dimensions_s[i].float



proc draw*(g: CapGeomParams, origin: Position2 = point2(), scale: float = 1, axis: V2 = v2(1, 0), sketch = doc, hideBackLines = false) =
  let x = axis.normalize
  let y = x.rotate(Pi/2)
  proc sc(v: float): float = v * scale
  proc vt(v: V2): V2 = v.x.sc * x + v.y.sc * y
  proc pt(v: V2): Point2 = origin + v.vt
  if sketch == nil: return

  # let contour = [
    
  # ]


