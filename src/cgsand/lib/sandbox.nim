{.used.}
import pkg/[ecs, sigeo/core, chroma]
export ecs, core, chroma

when defined(script):
  import std/os
  static: retainTypeIds(currentSourcePath().parentDir / "typeids.txt")


var doc* {.exportc: "world_instance", dynlib.} = World()


