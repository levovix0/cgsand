import ../sandbox

## some global setting for tech drawing documents


var drawingMmScale*: float = 1e-3
  ## world millimiters per document unit


proc mm*(v: float): float = v * drawingMmScale
  ## world millimiters to doc units

proc m*(v: float): float = v * 1e3 * drawingMmScale
  ## meters to doc units


proc ceil*(x: float, step: float): float =
  ceil(x / step) * step


let darkTheme* = cache[].mgetOrPut(DarkTheme, true)

let mainLine* = PixelThickness 2
let thinLine* = PixelThickness 0.75
let hatchingLine* = PixelThickness 0.75
let hiddenLine* = (
  PixelThickness 0.75,
  Dashing(pattern: @[1, 1]),
  Foreground (if darkTheme: "#8e93ff".parseHtmlHex else: "#000000".parseHtmlHex)
)
let axialLine* = (
  PixelThickness 1.5,
  Dashing(pattern: @[1, 0.5, 0, 0.5]),
  Foreground (if darkTheme: "#ff9e49".parseHtmlHex else: "#000000".parseHtmlHex)
)
let dimFontSize* = FontSize 0.5


proc setTechDrawGlobals*(globals: EntityId) =
  doc.update globals:
    add OwnerModule "drawing"
    add CanvasSettings(
      autoSize: true,
      margin: v2(2, 2),
    )
    add AxisYDown
    add (if darkTheme: Foreground color(0.75, 0.75, 0.8) else: Foreground color(0, 0, 0))
    add FontSize 1
    add DashingScale 4.mm

  if not darkTheme:
    doc.update globals: add Background color(1, 1, 1)

proc setDrawingGlobals*(globals: EntityId) {.deprecated: "use setTechDrawGlobals instead".} =
  setTechDrawGlobals(globals)


if not doc.hasComponent(sandbox.globals, OwnerModule):
  setTechDrawGlobals(sandbox.globals)


proc newTechDraw*(): World =
  result = World()
  withDocument result:
    let globals = doc.spawn()
    setTechDrawGlobals(globals)

