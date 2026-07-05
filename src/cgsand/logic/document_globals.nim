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
    dashingScale*: float = 1


proc documentGlobals*(w: World): DocumentGlobals =
  result = DocumentGlobals(settings: CanvasSettings(autoSize: true))
  result.font = font_default
  w.forEach (v: CanvasSettings, opt FontSize, opt AxisYDirection, opt PositionAt, opt Typeface, opt DashingScale):
    result.settings = v
    result.foreground = v.foreground
    result.background = v.background
    if has FontSize: result.fontSize = the FontSize
    if has AxisYDirection: result.axisYDirection = the AxisYDirection
    if has PositionAt: result.originAt = the PositionAt
    if has Typeface: result.font = the Typeface
    if has DashingScale: result.dashingScale = the DashingScale
