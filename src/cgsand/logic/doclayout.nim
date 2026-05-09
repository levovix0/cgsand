import std/[options, math]
import pkg/[ecs, vmath]
import pkg/pixie/[fonts]
import pkg/toscel/[fonts]
import pkg/rice/[transform]
import ./[bounds]
import ../lib/sandbox except Mat4, mat4, Vec4, Vec3, Vec2, vec2, vec3, vec4
import ../lib/[geom2d]


type
  DocumentGlobals* = object
    settings*: CanvasSettings
    foreground*: Color = color(1, 1, 1)
    background*: Color = color(0, 0, 0, 0)
    fontSize*: float64 = 10
    axisYDirection*: AxisYDirection = AxisYUp
    originAt*: PositionAt = PositionAtCenter
 
  DocumentLayout* = object
    contentBounds*: Bounds2
    pageBounds*: Bounds2
    documentTransform*: Mat4

  

proc pageAnchor*(size: Vec2, originAt: PositionAt): Vec2 =
  let factor = originAt.factor()
  vec2(
    -size.x / 2 + size.x * factor.x,
    size.y / 2 - size.y * factor.y,
  )


proc documentGlobals*(w: ptr World): DocumentGlobals =
  result = DocumentGlobals(settings: CanvasSettings(autoSize: true))
  w[].forEach (v: CanvasSettings, opt Foreground, opt Background, opt FontSize, opt AxisYDirection, opt PositionAt):
    result.settings = v
    if has Foreground: result.foreground = the Foreground
    if has Background: result.background = the Background
    if has FontSize: result.fontSize = the FontSize
    if has AxisYDirection: result.axisYDirection = the AxisYDirection
    if has PositionAt: result.originAt = the PositionAt


proc documentLayout*(w: ptr World, globals: DocumentGlobals): DocumentLayout =
  result = DocumentLayout()
  let yScale = if globals.axisYDirection == AxisYDown: -1'f32 else: 1'f32
  let transform = scale(vec3(1, yScale, 1))

  w[].forEach (line: LineSection, thickness: opt Thickness):
    result.contentBounds.add(lineBounds(line, if has Thickness: some thickness else: none Thickness))

  w[].forEach (curve: CircleArc, count: PointCount||20):
    result.contentBounds.add(pointsBounds(curve.points(count)))

  w[].forEach (text: Text, pos: Position2, posAt: PositionAt||PositionAtTopLeft, font: Typeface||font_default, size: FontSize||globals.fontSize):
    result.contentBounds.add(textBounds(text, pos, posAt, font, size))

  if globals.settings.autoSize and not result.contentBounds.empty:
    let margin = globals.settings.margin.vec2
    result.pageBounds = result.contentBounds.expanded(margin)
  
  else:
    let size = globals.settings.size.vec2
    result.pageBounds = bounds2(-size / 2, size / 2)

  if globals.axisYDirection == AxisYDown:
    result.documentTransform = combine(
      transform,
      translate(-pageAnchor(result.pageBounds.size, globals.originAt).vec3(0)),
      translate(vec3(0, result.pageBounds.size.y, 0)),
    )
  else:
    result.documentTransform = combine(
      transform,
      translate(-pageAnchor(result.pageBounds.size, globals.originAt).vec3(0)),
    )


