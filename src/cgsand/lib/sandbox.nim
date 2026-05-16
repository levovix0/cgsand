{.used.}
import pkg/[ecs, sigeo/core, chroma]
export ecs, core, chroma

when defined(script):
  import std/os
  static: retainTypeIds(currentSourcePath().parentDir / "typeids.txt")



type
  CanvasSettings* = object
    ## global, add this to the `doc` to apply
    ## add any other global settings to an entity with CanvasSettings

    size*: Vec2             ## in abstract units
    mmScale*: float32 = 1   ## (paper page) millimeters per abstract unit
    autoSize*: bool = true  ## if true, `size` is ignored and calculated from document content bounds insted
    margin*: Vec2 = vec2(0, 0)  ## extra page space around auto-sized content


  PositionAt* = enum
    ## can be added to an entity with Text to specify which point of a text Position2 defines
    ## can be added to an entity with CanvasSettings, to specify if axisY is directed down (it is up by default)
    PositionAtTopLeft
    PositionAtTopRight
    PositionAtBottomLeft
    PositionAtBottomRight
    PositionAtLeft
    PositionAtRight
    PositionAtTop
    PositionAtBottom
    PositionAtCenter

  AxisYDirection* = enum
    ## can be added to an entity with CanvasSettings, to specify if axisY is directed down (it is up by default)
    AxisYUp
    AxisYDown


  Foreground* = Color
    ## color of lines of shape, text
    ## can be added onto entity with CanvasSettings to define a default foreground color (it is color(1, 1, 1) by default)
  
  Background* = Color
    ## color of background of shape or document (can be added onto entity with CanvasSettings)


  Position2* = Point2
    ## used for non-geometry objects that can be displayed (Text)
  
  
  Text* = string
    ## draws text

  FontSize* = float64
    ## defines height of a line of text


  Thickness* = float32
    ## defines thickness of lines (attachable to 2d curves)
  
  PixelThickness* = float32
    ## thickness of lines in pixels. Stays the same no matter how viewport transforms
    ## todo



when defined(script) or defined(nimcheck):
  var doc* {.exportc: "world_instance", dynlib.} = World()
    ## in the sandbox we have an entire World!
  
  proc handleErrorAfterNimMain: bool {.exportc, dynlib.} =
    try: discard
    except Defect:
      echo "script defect: ", getCurrentExceptionMsg() & "\n" & getCurrentException().getStackTrace()
      result = true
    except:
      echo "script error: ", getCurrentExceptionMsg() & "\n" & getCurrentException().getStackTrace()
      result = true



const CanvasSettings_A4_Vertical* = CanvasSettings(
  size: vec2(210, 297),
  mmScale: 1,
  autoSize: false,
)

const CanvasSettings_A4_Horizontal* = CanvasSettings(
  size: vec2(297, 210),
  mmScale: 1,
  autoSize: false,
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



proc excl*[T](arr: var seq[T], v: T) =
  let i = arr.find(v)
  if i != -1: arr.delete i



proc factor*(posAt: PositionAt): Vec2 =
  case posAt
  of PositionAtTopLeft: vec2(0, 0)
  of PositionAtTopRight: vec2(1, 0)
  of PositionAtBottomLeft: vec2(0, 1)
  of PositionAtBottomRight: vec2(1, 1)
  of PositionAtLeft: vec2(0, 1/2)
  of PositionAtRight: vec2(1, 1/2)
  of PositionAtTop: vec2(1/2, 0)
  of PositionAtBottom: vec2(1/2, 1)
  of PositionAtCenter: vec2(1/2, 1/2)



proc background*(doc: var World): Background =
  result = color(0, 0, 0, 0)
  doc.forEach (CanvasSettings, Background): return the Background

proc foreground*(doc: var World): Foreground =
  result = color(1, 1, 1)
  doc.forEach (CanvasSettings, Foreground): return the Foreground

proc fontSize*(doc: var World): FontSize =
  result = 1
  doc.forEach (CanvasSettings, FontSize): return the FontSize

