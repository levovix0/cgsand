import pkg/[vmath]
import pkg/sigui/[uibase]
import ../logic/code_editor/[syntax_highlighting]


proc drawHighlightedText*(
  ctx: DrawContext,
  pos: Vec2,
  arrangement: Arrangement,
  kinds: openArray[CodeKind],
  origin: Vec2 = vec2(0, 0),
  exactBoundaries = false,
) =
  if arrangement == nil or arrangement.fonts.len == 0:
    return

  var context = ctx.startRasterTextDrawing(arrangement.fonts[0], pos)

  let box = arrangement.computeBounds

  let offset =
    if exactBoundaries: vec2(box.x, box.y) + vec2(box.w, box.h) * origin
    else: vec2(box.w + box.x, box.h + box.y) * origin

  for i, rune in arrangement.runes:
    var rect = arrangement.selectionRects[i]
    rect.wh = rect.wh + vec2(2, 2)

    context.color = kinds[i].color
    ctx.fastRasterDrawRune(rune, rect(rect.xy - offset, rect.wh), context)

  ctx.endRasterTextDrawing()

