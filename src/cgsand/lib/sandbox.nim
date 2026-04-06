{.used.}
import pkg/[ecs, sigeo/core, chroma]
export ecs, core, chroma

when defined(script):
  import std/os
  static: retainTypeIds(currentSourcePath().parentDir / "typeids.txt")



type
  CanvasSettings* = object
    ## global, add this to the `doc` to apply
    
    width*: float32 = 200   ## in abstract units
    height*: float32 = 200  ## in abstract units

    mmScale*: float32 = 1  ## (paper page) millimeters per abstract unit


const CanvasSettings_A4_Vertical* = CanvasSettings(
  width: 210,
  height: 297,
  mmScale: 1,
)

const CanvasSettings_A4_Horizontal* = CanvasSettings(
  width: 297,
  height: 210,
  mmScale: 1,
)


var doc* {.exportc: "world_instance", dynlib.} = World()
  ## in the sandbox we have an entire World!


