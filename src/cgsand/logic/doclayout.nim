import pkg/[ecs]
import ./[bounds, document_globals]
import ../lib/sandbox


type
  DocumentLayout* = object
    contentBounds*: Bounds2
    pageBounds*: Bounds2


proc pageAnchor*(size: Vec2, originAt: PositionAt): Vec2 =
  let factor = originAt.factor()
  vec2(
    -size.x / 2 + size.x * factor.x,
    size.y / 2 - size.y * factor.y,
  )


proc documentLayout*(w: World, globals: DocumentGlobals): DocumentLayout =
  result = DocumentLayout()

  let (xMin, xMax) = w.worldBoundsAlongAxis(vec3(1, 0, 0), globals)
  let (yMin, yMax) = w.worldBoundsAlongAxis(vec3(0, 1, 0), globals)

  if xMin <= xMax and yMin <= yMax:
    result.contentBounds = bounds2(vec2(xMin, yMin), vec2(xMax, yMax))

  if globals.settings.autoSize and not result.contentBounds.empty:
    let margin = globals.settings.margin.vec2
    result.pageBounds = result.contentBounds.expanded(margin)

  else:
    let size = globals.settings.size.vec2
    result.pageBounds = bounds2(-size / 2, size / 2)
