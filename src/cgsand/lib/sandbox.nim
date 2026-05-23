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
    mmScale*: float32 = 10  ## (paper page) millimeters per abstract unit
    autoSize*: bool = true  ## if true, `size` is ignored and calculated from document content bounds insted
    margin*: Vec2 = vec2(0, 0)  ## extra page space around auto-sized content


  PositionAt* = enum
    ## can be added to an entity with Text to specify which point of a text Position2 defines
    PositionAtTopLeft
    PositionAtTopRight
    PositionAtBottomLeft
    PositionAtBottomRight
    PositionAtLeft
    PositionAtRight
    PositionAtTop
    PositionAtBottom
    PositionAtCenter

  Position2* = Point2
    ## used for non-geometry objects that can be displayed (Text)


  AxisYDirection* = enum
    ## can be added to an entity with CanvasSettings, to specify if axisY is directed up (it is down by default)
    AxisYDown
    AxisYUp
  

  Transform3* = Mat4
    ## can be added to arbitrary transform 2D/3D object (for example, rotate text) in 3D space. Applied before Position2
  
  
  Text* = string
    ## draws text

  FontSize* = float64
    ## defines height of a line of text


  Foreground* = Color
    ## color of lines of shape, text
    ## can be added onto entity with CanvasSettings to define a default foreground color (it is color(1, 1, 1) by default)
  
  Background* = Color
    ## color of background of shape or document (can be added onto entity with CanvasSettings)


  Thickness* = float32
    ## defines thickness of lines (attachable to 2d curves)
  
  PixelThickness* = float32
    ## thickness of lines in pixels. Stays the same no matter how viewport transforms


  DarkTheme* = bool
    ## set in cache by the app to indicate the current UI theme; scripts read this at startup

  CacheVariable* = string
    ## a name for an entity, that persists between script re-runs
  

  OwnerModule* = string


  SubWorld* = World
    ## attach to an entity with Position2 (and optionally Transform3) to render another world as a sub-canvas
    ## the sub-world is drawn at Position2 in the outer world's coordinate space
    ## the sub-world's background is transparent; its own globals (foreground, font, etc.) are used

  RawBounds2* = object
    ## ABI-stable bounds type used for app -> script callbacks (float32 storage)
    empty*: bool = true
    minX*, minY*, maxX*, maxY*: float32



when defined(script) or defined(nimcheck):
  type
    Bounds2* = object
      ## bounding box in document coordinates
      empty*: bool = true
      min*, max*: Vec2

  proc bounds2*(min, max: Vec2): Bounds2 =
    Bounds2(empty: false, min: min, max: max)

  proc size*(b: Bounds2): Vec2 = b.max - b.min
  proc center*(b: Bounds2): Vec2 = (b.min + b.max) / 2

  proc addPoint*(b: var Bounds2, p: Vec2) =
    if b.empty:
      b = bounds2(p, p)
      return
    b.min.x = min(b.min.x, p.x)
    b.min.y = min(b.min.y, p.y)
    b.max.x = max(b.max.x, p.x)
    b.max.y = max(b.max.y, p.y)

  proc add*(b: var Bounds2, other: Bounds2) =
    if other.empty: return
    b.addPoint(other.min)
    b.addPoint(other.max)

  proc expanded*(b: Bounds2, margin: Vec2): Bounds2 =
    if b.empty: return b
    bounds2(b.min - margin, b.max + margin)

  proc toBounds2*(raw: RawBounds2): Bounds2 =
    if raw.empty: return Bounds2(empty: true)
    bounds2(vec2(raw.minX.float64, raw.minY.float64), vec2(raw.maxX.float64, raw.maxY.float64))

  var textSizeImpl* {.exportc: "sandbox_textSizeImpl", dynlib.}: proc(text: string, fontSize: FontSize): FVec2 {.cdecl.}
  var entityBoundsImpl* {.exportc: "sandbox_entityBoundsImpl", dynlib.}: proc(world: World, eid: EntityId): RawBounds2 {.cdecl.}
  var worldBoundsImpl* {.exportc: "sandbox_worldBoundsImpl", dynlib.}: proc(world: World): RawBounds2 {.cdecl.}

  proc textSize*(text: string, fontSize: FontSize): Vec2 =
    if textSizeImpl != nil:
      let r = textSizeImpl(text, fontSize)
      return vec2(r.x.float64, r.y.float64)

  proc entityBounds*(world: World, eid: EntityId): Bounds2 =
    if entityBoundsImpl != nil: return entityBoundsImpl(world, eid).toBounds2

  proc worldBounds*(world: World): Bounds2 =
    if worldBoundsImpl != nil: return worldBoundsImpl(world).toBounds2
  
  
  var doc* {.exportc: "world_instance", dynlib.} = World()
    ## in the sandbox we have an entire World!

  var cache* {.exportc: "cache_instance", dynlib.}: ptr World
  
  var reserveCache = World()
  if cache == nil: cache = reserveCache.addr

  proc handleErrorAfterNimMain: bool {.exportc, dynlib.} =
    try: discard
    except Defect:
      echo "script defect: ", getCurrentExceptionMsg() & "\n" & getCurrentException().getStackTrace()
      result = true
    except:
      echo "script error: ", getCurrentExceptionMsg() & "\n" & getCurrentException().getStackTrace()
      result = true

  proc syncCacheFromDoc {.exportc, dynlib.} =
    if cache == nil: return
    var toDelete: seq[EntityId]
    cache[].forEach (eid: EntityId, CacheVariable, float):
      toDelete.add eid
    for eid in toDelete:
      cache[].despawn(eid)
    cache[].cleanupDeleted()
    doc.forEach (cv: CacheVariable, v: float):
      discard cache[].spawn(cv, v)
  

  var globals* = doc.spawn(
    CanvasSettings(),
    Foreground color(1, 1, 1),
    Background color(0, 0, 0, 0)
  )



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



proc `[]`*[T](w: World, t: typedesc[T]): var T =
  var res: ptr T
  w.forEach (singletonValue: var T):
    res = singletonValue.addr
  if res == nil:
    w.add T.default
    w.forEach (singletonValue: var T):
      res = singletonValue.addr
  res[]

proc `[]=`*[T](w: World, t: typedesc[T], v: T) =
  var got = false
  w.forEach (singletonValue: var T):
    singletonValue = v
    got = true
  if not got:
    w.add v

proc getOrDefault*[T](w: World, t: typedesc[T], v: T): T =
  var res: ptr T
  w.forEach (singletonValue: var T):
    res = singletonValue.addr
  if res == nil:
    v
  else:
    res[]

proc mgetOrPut*[T](w: World, t: typedesc[T], v: T): var T =
  var res: ptr T
  w.forEach (singletonValue: var T):
    res = singletonValue.addr
  if res == nil:
    w.add v
    w.forEach (singletonValue: var T):
      res = singletonValue.addr
  res[]

template hasSingleton*[T](w: World, t: typedesc[T]): bool =
  var hasV = false
  w.forEach (t): hasV = true
  hasV



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



proc background*(doc: World): Background =
  result = color(0, 0, 0, 0)
  doc.forEach (CanvasSettings, Background): return the Background

proc foreground*(doc: World): Foreground =
  result = color(1, 1, 1)
  doc.forEach (CanvasSettings, Foreground): return the Foreground

proc fontSize*(doc: World): FontSize =
  result = 1
  doc.forEach (CanvasSettings, FontSize): return the FontSize



template withDocument*(newDoc: World, body: untyped) =
  let prevDoc = doc
  doc = newDoc
  body
  doc = prevDoc



template mainModule*(body: untyped) =
  when isMainModule:
    try:
      body
    except Defect:
      echo getCurrentExceptionMsg()
      echo getCurrentException().getStackTrace()
    except:
      echo getCurrentExceptionMsg()
      echo getCurrentException().getStackTrace()


