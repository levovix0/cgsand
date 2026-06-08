import pkg/pixie/[fonts]
import ../lib/[sandbox, text]


type
  DocumentGlobals* = object
    settings*: CanvasSettings
    foreground*: Color = color(1, 1, 1)
    background*: Color = color(0, 0, 0, 0)
    fontSize*: float64 = 1
    font*: Typeface
    axisYDirection*: AxisYDirection = AxisYUp
    originAt*: PositionAt = PositionAtCenter


proc documentGlobals*(w: World): DocumentGlobals =
  result = DocumentGlobals(settings: CanvasSettings(autoSize: true))
  result.font = font_default
  w.forEach (v: CanvasSettings, opt Foreground, opt Background, opt FontSize, opt AxisYDirection, opt PositionAt, opt Typeface):
    result.settings = v
    if has Foreground: result.foreground = the Foreground
    if has Background: result.background = the Background
    if has FontSize: result.fontSize = the FontSize
    if has AxisYDirection: result.axisYDirection = the AxisYDirection
    if has PositionAt: result.originAt = the PositionAt
    if has Typeface: result.font = the Typeface
