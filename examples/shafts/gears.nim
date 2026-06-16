import std/[tables]
import sandbox, geom2d, techDraw
import pkg/[vmath]


type
  GearDesc* = object
    d*: float
      ## inner diameter (shaft / bore), m

  GearGeomParams* = object



converter autoComputeGeomParams*(desc: GearDesc): GearGeomParams =
  template O: var GearGeomParams = result
  
  ## todo


proc bounds*(g: GearGeomParams): Bounds2 =
  ## todo


proc draw*(g: GearGeomParams, sketch = doc, hideBackLines = false) =
  if sketch == nil: return

  sketch.add line(p2(0, 0), p2(10.mm, 10.mm)), mainLine

  


proc sketch*(g: GearGeomParams, hideBackLines = false): World =
  result = newTechDraw()
  withDocument result: draw(g, hideBackLines = hideBackLines)




mainModule:
  doc[globals, CanvasSettings].margin = v2(2.mm, 2.mm)
  doc.add SubWorld GearDesc(d: 48.mm).sketch(hideBackLines = true), Position2 p2()
