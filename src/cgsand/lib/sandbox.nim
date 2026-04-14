{.used.}
import pkg/[ecs, sigeo/core, chroma]
export ecs, core, chroma

when defined(script):
  import std/os
  static: retainTypeIds(currentSourcePath().parentDir / "typeids.txt")



type
  CanvasSettings* = object
    ## global, add this to the `doc` to apply
    
    size*: Vec2 = vec2(200, 200)   ## in abstract units
    mmScale*: float32 = 1  ## (paper page) millimeters per abstract unit


  Foreground* = Color
  Background* = Color


  Position2* = Point2
    ## used for non-geometry objects that can be displayed (Text)
  
  PositionAt* = enum
    PositionAtTopLeft
    PositionAtTopRight
    PositionAtBottomLeft
    PositionAtBottomRight
    PositionAtLeft
    PositionAtRight
    PositionAtTop
    PositionAtBottom
    PositionAtCenter
  
  
  Text* = string
  FontSize* = float64



var doc* {.exportc: "world_instance", dynlib.} = World()
  ## in the sandbox we have an entire World!



const CanvasSettings_A4_Vertical* = CanvasSettings(
  size: vec2(210, 297),
  mmScale: 1,
)

const CanvasSettings_A4_Horizontal* = CanvasSettings(
  size: vec2(297, 210),
  mmScale: 1,
)



proc `[]`*[T](w: var World, t: typedesc[T]): var T =
  var res: ptr T
  w.forEach (singletonValue: var T):
    res = singletonValue.addr
  if res == nil:
    w.add T.default
    w.forEach (singletonValue: var T):
      res = singletonValue.addr
  res[]

proc `[]=`*[T](w: var World, t: typedesc[T], v: T) =
  var got = false
  w.forEach (singletonValue: var T):
    singletonValue = v
    got = true
  if not got:
    w.add v


