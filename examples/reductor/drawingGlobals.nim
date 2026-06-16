import sandbox


proc mm(v: float): float = v * 1e-3


let darkTheme* = cache[].mgetOrPut(DarkTheme, true)

let mainLine* = PixelThickness 3
let hatchingLine* = PixelThickness 1
let hiddenLine* = (PixelThickness 1, Dashing(pattern: @[1, 1]), Foreground (if darkTheme: "#8e93ff".parseHtmlHex else: "#000000".parseHtmlHex))
let axialLine* = (PixelThickness 2, Dashing(pattern: @[1, 0.5, 0, 0.5]), Foreground (if darkTheme: "#ff9e49".parseHtmlHex else: "#000000".parseHtmlHex))
let dimFontSize* = FontSize 0.5


proc setDrawingGlobals*(globals: EntityId) =
  doc.update globals:
    add OwnerModule "shafts"
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

if not doc.hasComponent(globals, OwnerModule):
  setDrawingGlobals(globals)

