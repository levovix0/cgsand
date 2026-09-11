import pkg/[ecs]
import ../../lib/[sandbox]
import ./[bounds, document_globals]


type
  DocumentLayout* = object
    contentBounds*: Bounds2
    pageBounds*: Bounds2


proc pageAnchor*(size: V2, originAt: PositionAt): V2 =
  let factor = originAt.factor()
  v2(
    -size.x / 2 + size.x * factor.x,
    size.y / 2 - size.y * factor.y,
  )


proc documentLayout*(w: World, globals: DocumentGlobals): DocumentLayout =
  result = DocumentLayout()

  let (xMin, xMax) = w.worldBoundsAlongAxis(v3(1, 0, 0), globals)
  let (yMin, yMax) = w.worldBoundsAlongAxis(v3(0, 1, 0), globals)

  if xMin <= xMax and yMin <= yMax:
    result.contentBounds = bounds2(p2(xMin, yMin), p2(xMax, yMax))

  if globals.settings.autoSize and not result.contentBounds.empty:
    let margin = globals.settings.margin.v2
    result.pageBounds = result.contentBounds.expanded(margin)

  else:
    let size = globals.settings.size.v2
    result.pageBounds = bounds2((-size / 2).Point2, (size / 2).Point2)
