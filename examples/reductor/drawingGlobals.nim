import sandbox


let darkTheme* = cache[].mgetOrPut(DarkTheme, true)

let mainLine* = PixelThickness 3
let hatchingLine* = PixelThickness 1
let hiddenLine* = PixelThickness 1
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

  if not darkTheme:
    doc.update globals: add Background color(1, 1, 1)

if not doc.hasComponent(globals, OwnerModule):
  setDrawingGlobals(globals)

