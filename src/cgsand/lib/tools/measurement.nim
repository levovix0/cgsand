import std/[math]
import ../[sandbox, geom2d, techDraw]
import ../interactive
import pkg/[vmath, bumpy]

## Interactive distance-measurement tool for the drawing.
##
## Call `measurementTool()` once from the top level of a script to activate it.
## While active:
##   - left click places measurement points: the first click starts a new
##     measurement, the second fixes it. Each measurement shows three dimensions
##     at once - the aligned (point-to-point) distance plus its horizontal and
##     vertical components. Points snap to the nearest curve endpoint.
##   - right click over a measurement's bounds erases it.
##   - Escape cancels the measurement currently being placed.
##
## Measurements can also be created from code (`addMeasurement`), interrupted
## (`cancelMeasurement`) and removed (`removeMeasurement` / `clearMeasurements`).


const maxMeasurements* = 64
  ## measurements are kept in a fixed-size value-type array so the whole state
  ## is plain-old-data and survives script re-runs safely (see cache mechanics)
  ## todo: allow to cache non plain-old-data

const
  snapPixels = 12.0       ## snap radius to curve endpoints
  markerPixels = 5.0      ## half-size of the placement crosshair
  arrowPixels = 20.0      ## dimension arrow size
  textPixels = 20.0       ## dimension text height
  dimMarginPixels = 24.0  ## gap from the points to the H/V dimension lines
  hitPadPixels = 8.0      ## extra padding of the right-click hit area


type
  MeasurementPhase* = enum
    mpEmpty       ## unused slot
    mpPlacingB    ## first point placed, second point follows the cursor
    mpDone        ## both points fixed

  Measurement* = object
    phase*: MeasurementPhase
    a*, b*: Point2

  MeasurementState* = object
    items*: array[maxMeasurements, Measurement]
    activeCreation*: int      ## index of the measurement being placed, or -1
    worldPerPixel*: float     ## captured from the viewport during input events


var measurementUnit* = 1.mm
var measurementUnitName* = "mm"


## the measurement geometry lives in its own SubWorld for easier deletion
## The SubWorld is drawn at identity, so its coordinates match the document's,
## and it is tagged NoBounds so it never affects the page layout.
var measureWorld: SubWorld      ## the current measurement SubWorld
var measureEntity: EntityId     ## the SubWorld entity inside `doc`  # todo: typed EntityId[SubWorld]
var measureSpawned = false



proc mstate(): var MeasurementState =
  cache[].mgetOrPut(MeasurementState, MeasurementState(activeCreation: -1))


proc firstEmptySlot(s: MeasurementState): int =
  result = -1
  for i in 0 ..< maxMeasurements:
    if s.items[i].phase == mpEmpty:
      return i


proc anyMeasurement(s: MeasurementState): bool =
  for i in 0 ..< maxMeasurements:
    if s.items[i].phase != mpEmpty:
      return true



# --- viewport <-> world conversion ---
# todo: should raycast to the XY plane, instead of assuming that vieport is 2D
# todo: move to lib/

proc viewTransform(): tuple[ok: bool, toGl: Mat4, wb: Rect] =
  if projectionMatrix == nil or viewportMatrix == nil or viewportWindowBounds == nil:
    return (false, mat4(), rect(0, 0, 0, 0))
  let wb = viewportWindowBounds()
  if wb.w <= 0 or wb.h <= 0:
    return (false, mat4(), wb)
  (true, projectionMatrix() * viewportMatrix(), wb)


proc screenToWorld(window: Window): tuple[ok: bool, p: Point2] =
  let (ok, toGl, wb) = viewTransform()
  if not ok:
    return (false, point2(0, 0))
  # window pixel -> point on the component (its framebuffer), normalized to [0; 1]
  # (wb origin is the component's position inside the window)
  let nx = (window.mouse.pos.x - wb.x) / wb.w
  let ny = (window.mouse.pos.y - wb.y) / wb.h
  # normalized framebuffer point -> GL clip space -> world
  let clip = vec4(nx * 2 - 1, 1 - ny * 2, 0, 1)
  let world = inverse(toGl) * clip
  (true, point2(world.x.float, world.y.float))


proc viewportWorldPerPixel(): float =
  ## world units per screen pixel
  let (ok, toGl, wb) = viewTransform()
  if not ok:
    return 0
  let sX = sqrt(toGl[0][0]*toGl[0][0] + toGl[0][1]*toGl[0][1])
  let sY = sqrt(toGl[1][0]*toGl[1][0] + toGl[1][1]*toGl[1][1])
  let sZ = sqrt(toGl[2][0]*toGl[2][0] + toGl[2][1]*toGl[2][1])
  let ppu = max(sX, max(sY, sZ)) * wb.w / 2
  if ppu <= 0: 0.0 else: 1.0 / ppu



# --- snapping to curve endpoints ---
# todo: snapping to points on curves
# todo: move to lib/

proc allSnapPointsAux(w: World, toWorld: M4, acc: var seq[Point2]) =
  template emit(t3: M4, p: Point2) =
    let v = (toWorld * t3) * v4(p.x, p.y, 0, 1)
    acc.add point2(v.x, v.y)

  w.forEach (c: LineSection2, t3: Transform3||m4()):
    emit(t3, c.startPoint)
    emit(t3, c.endPoint)

  w.forEach (c: CircleArc2, t3: Transform3||m4()):
    emit(t3, c.startPoint)
    emit(t3, c.endPoint)

  w.forEach (c: EllipseArc2, t3: Transform3||m4()):
    emit(t3, c.pointAtParam(0.FloatParam))
    emit(t3, c.pointAtParam(1.FloatParam))

  w.forEach (c: Curve2, t3: Transform3||m4()):
    emit(t3, c.pointAtParam(0.FloatParam))
    emit(t3, c.pointAtParam(1.FloatParam))

  w.forEach (c: OwnedCurve2, t3: Transform3||m4()):
    let cc = cast[Curve2](c)
    emit(t3, cc.pointAtParam(0.FloatParam))
    emit(t3, cc.pointAtParam(1.FloatParam))

  w.forEach (c: Path2, t3: Transform3||m4()):
    emit(t3, c.pointAtParam(0.FloatParam))
    emit(t3, c.pointAtParam(1.FloatParam))

  w.forEach (sub: SubWorld, pos: Position2||p2(), t3: Transform3||m4()):
    if sub == nil or sub == measureWorld: continue
    allSnapPointsAux(sub, toWorld * (translate(v3(pos.x, pos.y, 0)) * t3), acc)

proc allSnapPoints(w: World): seq[Point2] =
  allSnapPointsAux(w, m4(), result)


proc snap(p: Point2, wpp: float, pts = doc.allSnapPoints): Point2 =
  ## snap `p` to the nearest curve endpoint within the snap radius
  if wpp <= 0: return p
  let radius = snapPixels * wpp
  result = p
  var bestD = radius
  for e in pts:
    let d = (e - p).length
    if d < bestD:
      bestD = d
      result = e



# --- API ---

proc addMeasurement*(a, b: Point2): int {.discardable.} =
  ## create a finished measurement between two known points, returns its index (or -1 if full)
  letCur s: mstate()
  result = s.firstEmptySlot
  if result < 0: return
  s.items[result] = Measurement(phase: mpDone, a: a, b: b)


proc cancelMeasurement*() =
  ## interrupt the measurement currently being placed (if any)
  letCur s: mstate()
  if s.activeCreation >= 0:
    s.items[s.activeCreation] = Measurement()
    s.activeCreation = -1


proc removeMeasurement*(i: int) =
  letCur s: mstate()
  if i in 0 ..< maxMeasurements:
    s.items[i] = Measurement()
    if s.activeCreation == i:
      s.activeCreation = -1


proc clearMeasurements*() =
  letCur s: mstate()
  for i in 0 ..< maxMeasurements:
    s.items[i] = Measurement()
  s.activeCreation = -1



# --- layout & bounds ---
# todo: use existant host-side bounds computation instead

proc hvDimlines(m: Measurement, wpp: float): tuple[h, v: Point2] =
  ## the points the horizontal / vertical dimension lines pass through, placed
  ## just outside the measured points
  let mg = (if wpp > 0: wpp * dimMarginPixels else: 0.0)
  result.h = point2((m.a.x + m.b.x) / 2, max(m.a.y, m.b.y) + mg)
  result.v = point2(max(m.a.x, m.b.x) + mg, (m.a.y + m.b.y) / 2)


proc measurementBounds(m: Measurement, wpp: float): tuple[lo, hi: Point2] =
  ## axis-aligned hit area for right-click erasing
  let (h, v) = hvDimlines(m, wpp)
  var lo = m.a
  var hi = m.a
  for p in [m.a, m.b, h, v]:
    lo = point2(min(lo.x, p.x), min(lo.y, p.y))
    hi = point2(max(hi.x, p.x), max(hi.y, p.y))
  let pad = (if wpp > 0: wpp * hitPadPixels else: 0.0)
  (point2(lo.x - pad, lo.y - pad), point2(hi.x + pad, hi.y + pad))


proc contains(b: tuple[lo, hi: Point2], p: Point2): bool =
  p.x >= b.lo.x and p.x <= b.hi.x and p.y >= b.lo.y and p.y <= b.hi.y



# --- drawing ---

proc drawMarker(p: Point2, halfSize: float) =
  if halfSize <= 0: return
  doc.add line(point2(p.x - halfSize, p.y), point2(p.x + halfSize, p.y)), PixelThickness 4, color(1, 0.4, 0.4)
  doc.add line(point2(p.x, p.y - halfSize), point2(p.x, p.y + halfSize)), PixelThickness 4, color(1, 0.4, 0.4)


proc addDim(a, b: Point2, dir: V2, dimline: Point2, value, wpp: float) =
  let arrowSz = (if wpp > 0: wpp * arrowPixels else: value * 0.04)
  let fontSz = (if wpp > 0: wpp * textPixels else: value * 0.08)
  doc.add LinearDimension2(a: a, b: b, dir: dir, dimline: dimline):
    dimensionText(value / measurementUnit, measurementUnitName)
    ArrowSize arrowSz
    FontSize fontSz


proc emitMeasurements(w: World) =
  ## (re)build all measurement geometry into the (assumed empty) world `w`
  letCur s: mstate()
  let wpp = if s.worldPerPixel > 0: s.worldPerPixel else: 0.0
  let eps = (if wpp > 0: wpp * 2 else: 0.0)   # skip degenerate (near-zero) dimensions

  withDocument w:
    for i in 0 ..< maxMeasurements:
      let m = s.items[i]
      if m.phase == mpEmpty: continue

      let (hLine, vLine) = hvDimlines(m, wpp)
      let dAligned = (m.b - m.a).length
      let dx = abs(m.b.x - m.a.x)
      let dy = abs(m.b.y - m.a.y)

      if dAligned > eps:         addDim(m.a, m.b, (m.b - m.a), m.a, dAligned, wpp)
      if dx > eps and dy > eps:  addDim(m.a, m.b, v2(1, 0), hLine, dx, wpp)
      if dy > eps and dx > eps:  addDim(m.a, m.b, v2(0, 1), vLine, dy, wpp)

      # placement crosshairs only while still placing; gone once fixed
      if m.phase != mpDone:
        let mk = wpp * markerPixels
        drawMarker(m.a, mk)
        drawMarker(m.b, mk)

    doc.drawDimensions()


proc rebuildMeasurements*() =
  ## remove existing dimensions SubWorld and create the newer one
  let w = newTechDraw()
  emitMeasurements(w)
  measureWorld = w
  if not measureSpawned:
    measureEntity = doc.spawn(SubWorld w, NoBounds())
    measureSpawned = true
  else:
    doc[measureEntity, SubWorld] = w



# --- input systems ---

proc registerMeasurementSystems() =
  ecs_system windowEvent(e: MouseButtonEvent):
    if not e.pressed: return
    let (ok, raw) = screenToWorld(e.window)
    if not ok: return

    letCur s: mstate()
    s.worldPerPixel = viewportWorldPerPixel()

    if e.button == MouseButton.left:
      let p = snap(raw, s.worldPerPixel)
      if s.activeCreation < 0:
        let i = s.firstEmptySlot
        if i < 0: return
        s.items[i] = Measurement(phase: mpPlacingB, a: p, b: p)
        s.activeCreation = i
      else:
        s.items[s.activeCreation].b = p
        s.items[s.activeCreation].phase = mpDone
        s.activeCreation = -1
      rebuildMeasurements()
      redraw e.window

    elif e.button == MouseButton.right:
      var removed = false
      for i in 0 ..< maxMeasurements:
        if s.items[i].phase == mpEmpty: continue
        if measurementBounds(s.items[i], s.worldPerPixel).contains(raw):
          if s.activeCreation == i: s.activeCreation = -1
          s.items[i] = Measurement()
          removed = true
          break
      if removed:
        rebuildMeasurements()
        redraw e.window

  ecs_system windowEvent(e: MouseMoveEvent):
    letCur s: mstate()
    if s.activeCreation < 0: return
    let (ok, raw) = screenToWorld(e.window)
    if not ok: return
    s.worldPerPixel = viewportWorldPerPixel()
    s.items[s.activeCreation].b = snap(raw, s.worldPerPixel)
    rebuildMeasurements()
    redraw e.window

  ecs_system windowEvent(e: KeyEvent):
    if e.key != Key.escape or not e.pressed: return
    letCur s: mstate()
    if s.activeCreation < 0: return
    s.items[s.activeCreation] = Measurement()
    s.activeCreation = -1
    rebuildMeasurements()
    redraw e.window

  ecs_system viewportChanged():
    letCur s: mstate()
    if not s.anyMeasurement: return
    s.worldPerPixel = viewportWorldPerPixel()
    rebuildMeasurements()


var systemsRegistered = false


proc measurementTool*() =
  ## enable the interactive measurement tool
  ## todo: add ability to disable the tool
  if not systemsRegistered:
    registerMeasurementSystems()
    systemsRegistered = true
  rebuildMeasurements()
