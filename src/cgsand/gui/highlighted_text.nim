import pkg/[vmath]
import pkg/rice/[rasterTexts, contexts, gl]
import pkg/sigui/[uibase]
import ../logic/[syntax_highlighting]


proc drawHighlightedText*(
  ctx: DrawContext,
  pos: Vec3,
  arrangement: Arrangement,
  kinds: openArray[CodeKind],
  origin: Vec2 = vec2(0, 0),
  exactBoundaries = false,
  transform = mat4(),
) =
  if arrangement == nil or arrangement.fonts.len == 0:
    return

  var context = ctx.startRasterTextDrawing(arrangement.fonts[0])

  let pos = ctx.viewportToGlMatrix * transform * pos
  let box = arrangement.computeBounds()

  let offset =
    if exactBoundaries: vec2(box.x, -box.y) * ctx.px + vec2(box.w, -box.h) * origin * ctx.px
    else: vec2(box.w + box.x, -(box.h + box.y)) * origin * ctx.px

  for i, rune in arrangement.runes:
    var rect = arrangement.selectionRects[i]
    rect.wh = rect.wh + vec2(2, 2)

    context.color.uniform = kinds[i].color.vec4
    ctx.fastRasterDrawRune(rune, rect(pos.xy + vec2(rect.x, -rect.y) * ctx.px - offset, rect.wh), context)

  ctx.endRasterTextDrawing()

