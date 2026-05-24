import std/[options, math, tables]
import pkg/[ecs, vmath]
import pkg/pixie/paths
import pkg/pixie/[fonts]
import pkg/toscel/fonts as toscelFonts
import pkg/rice/[primitives, transform, texts, paths, contexts, polygonal3d, gl]
import pkg/sigeo/grids/[extrusions, smoothshading]
import ./[bounds, doclayout, scripts, document_globals]
import ../lib/sandbox except Mat4, mat4, Vec4, Vec3, Vec2, vec2, vec3, vec4, Bounds2, bounds2
import ../lib/[geom2d]


type
  Grid3MeshCache* = ref object
    entries: Table[pointer, Mesh]


proc grid3ToMesh(grid: Grid3): Mesh =
  var g = grid
  let tri = triangulate(g)
  var intIndices = newSeq[int](tri.indices.len)
  for i, idx in tri.indices:
    intIndices[i] = int(idx)
  let normals = computeVertexNormals(tri.points, intIndices)
  var verts = newSeq[tuple[pos: Vec3, normal: Vec3]](tri.points.len)
  for i, pt in tri.points:
    let n = normals[i]
    verts[i] = (
      vec3(pt.x.float32, pt.y.float32, pt.z.float32),
      vec3(n.x.float32, n.y.float32, n.z.float32),
    )
  var glIdx = newSeq[GlUint](tri.indices.len)
  for i, idx in tri.indices:
    glIdx[i] = GlUint(idx)
  newMesh(verts, glIdx)


proc projectionMatrix*(pageBounds: Bounds2, width, height: float32, axisYDirection: AxisYDirection): Mat4 =
  ## returns a matrix to convert document coordinates to GL space
  ## if viewport is mat4(), the whole document fits into the widget
  let pageSize = pageBounds.size
  let cmin = min(pageSize.x, pageSize.y)
  let cmax = max(pageSize.x, pageSize.y)
  let canvasScale =
    if (pageSize.x < pageSize.y) == (width / pageSize.x < height / pageSize.y):
      cmax / cmin
    else:
      1

  combine(
    translate(-pageBounds.center.vec3(0)),
    scale(y = (if axisYDirection == AxisYDown: -1 else: 1)),
    scale vec3(2/cmax, 2/cmax, 1),
    (
      if width / pageSize.x < height / pageSize.y:
        scale vec3(canvasScale, width / height * canvasScale, 1/1000)
      else:
        scale vec3(height / width * canvasScale, canvasScale, 1/1000)
    ),
  )


proc drawLineSection*(ctx: DrawContext, obj: LineSection, color: Color, thickness = none float32, transform = mat4()) =
  if thickness.isSome:
    ctx.fillCapsule(
      a = sandbox.Vec2(obj.startPoint).vec2.vec3(0),
      b = sandbox.Vec2(obj.endPoint).vec2.vec3(0),
      color = color,
      transform = transform,
      radius = thickness.get / 2,
    )
  else:
    ctx.drawLine(
      a = sandbox.Vec2(obj.startPoint).vec2.vec3(0),
      b = sandbox.Vec2(obj.endPoint).vec2.vec3(0),
      color = color,
      transform = transform,
    )


proc drawDocText*(
  ctx: DrawContext,
  text: string, pos: Position2, color: Color, posAt: PositionAt, font: Typeface, fontSize: float, axisYUp: bool,
  transform = mat4(),
) =
  var f = newFont(font)
  f.size = fontSize
  let ts = typeset(f, text)
  let origin = posAt.factor().vec2
  ctx.drawText(vec3(pos.x, pos.y, 0), ts, color.vec4, origin=origin, transform=transform, exactBoundaries=true, axisYUp=axisYUp)


proc draw2dWorld*(
  ctx: DrawContext,
  w: World,
  viewport, projection: Mat4,
  pixelsPerUnit: float32,
  meshCache: Grid3MeshCache,
) =
  ## draws the 2d objects of a world using the given viewport and projection
  ## does not touch GL state or background — caller is responsible for that
  let prevView = ctx.viewportMatrix
  let prevProj = ctx.projectionMatrix
  defer:
    ctx.viewport = prevView
    ctx.projection = prevProj

  ctx.viewport = viewport
  ctx.projection = projection

  let globals = w.documentGlobals

  w.forEach (line: LineSection, color: (Foreground|Color)||globals.foreground, thickness: opt Thickness, pixThick: opt PixelThickness, transform3: Transform3||dmat4()):
    let thk =
      if has PixelThickness: some(pixThick / pixelsPerUnit)
      elif has Thickness: some thickness
      else: none float32
    drawLineSection(ctx, line, color, thk, transform = mat4(transform3))


  w.forEach (curve: CircleArc, opt PointCount, opt Color, opt Background, opt Foreground, thickness: opt Thickness, pixThick: opt PixelThickness, transform3: Transform3||dmat4()):
    let screenRadius = float32(curve.radius) * pixelsPerUnit
    let count =
      if has PointCount: the PointCount
      else: clamp(int(screenRadius * abs(float32(curve.angularLength)) / 4.0), 8, 256)
    let points = curve.points(count)
    let fg =
      if has Foreground: the Foreground
      elif has Color: the Color
      else: globals.foreground
    let thk =
      if has PixelThickness: some(pixThick / pixelsPerUnit)
      elif has Thickness: some thickness
      else: none float32
    let t3 = mat4(transform3)

    if curve.closed:
      if has Background:
        ctx.fillCircle(color = the Background, radius = curve.radius, center = curve.center.DVec2.vec2.vec3(0), pointCount = count, transform = t3)
      if Background.has.not or Color.has or Foreground.has:
        for i in 0 ..< points.len - 1:
          drawLineSection(ctx, lineSection(points[i], points[i + 1]), fg, thk, transform = t3)
    else:
      if Foreground.has or Color.has or Background.has.not:
        for i in 0 ..< points.len - 1:
          drawLineSection(ctx, lineSection(points[i], points[i + 1]), fg, thk, transform = t3)


  w.forEach (arc: EllipseArc, color: (Foreground|Color)||globals.foreground, opt PointCount, thickness: opt Thickness, pixThick: opt PixelThickness, transform3: Transform3||dmat4()):
    let screenRadius = float32(max(arc.size.x, arc.size.y) / 2) * pixelsPerUnit
    let count =
      if has PointCount: the PointCount
      else: clamp(int(screenRadius * abs(float32(arc.angularLength)) / 4.0), 12, 256)
    let points = arc.points(count)
    let thk =
      if has PixelThickness: some(pixThick / pixelsPerUnit)
      elif has Thickness: some thickness
      else: none float32
    let t3 = mat4(transform3)
    for i in 0 ..< points.len - 1:
      drawLineSection(ctx, lineSection(points[i], points[i + 1]), color, thk, transform = t3)


  w.forEach (path: Path, opt Foreground|Color, thickness: Thickness||1, pixThick: opt PixelThickness, opt Background, transform3: Transform3||dmat4()):
    let t3 = mat4(transform3)
    let strokeWidth = if has PixelThickness: pixThick / pixelsPerUnit else: thickness
    if has Background:
      ctx.fillPath(path, color = the Background, transform = t3)
    if has Foreground:
      ctx.strokePath(path, color = the Foreground, strokeWidth=strokeWidth, transform = t3)
    elif has Color:
      ctx.strokePath(path, color = the Color, strokeWidth=strokeWidth, transform = t3)
    elif not(has Background):
      ctx.fillPath(path, color = globals.foreground, transform = t3)


  w.forEach (
    text: Text,
    pos: Position2,
    opt Foreground, opt Color,
    posAt: PositionAt||PositionAtTopLeft,
    font: Typeface||globals.font,
    size: FontSize||globals.fontSize,
    transform3: Transform3||dmat4(),
  ):
    let fg =
      if has Foreground: the Foreground
      elif has Color: the Color
      else: globals.foreground
    drawDocText(ctx, text, pos, fg, posAt, font, size, axisYUp = globals.axisYDirection == AxisYUp, transform = mat4(transform3))


  w.forEach (sub: SubWorld, pos: Position2, transform3: Transform3||dmat4()):
    if sub == nil: continue
    let innerViewport = combine(
      mat4(transform3),
      translate(vec3(pos.x, pos.y, 0)),
      viewport,
    )
    let outerToGl = combine(viewport, projection)
    let innerToGl = combine(innerViewport, projection)
    let outerScaleX = sqrt(outerToGl[0][0]*outerToGl[0][0] + outerToGl[1][0]*outerToGl[1][0])
    let innerScaleX = sqrt(innerToGl[0][0]*innerToGl[0][0] + innerToGl[1][0]*innerToGl[1][0])
    let innerPixelsPerUnit = if outerScaleX > 0: pixelsPerUnit * innerScaleX / outerScaleX else: pixelsPerUnit
    GC_ref(sub)
    draw2dWorld(ctx, sub, innerViewport, projection, innerPixelsPerUnit, meshCache)



proc draw3dWorld*(
  ctx: DrawContext,
  w: World,
  viewport, projection: Mat4,
  pixelsPerUnit: float32,
  meshCache: Grid3MeshCache,
) =
  ## draws the 3d objects of a world using the given viewport and projection
  ## does not touch GL state — caller is responsible for that
  let prevView = ctx.viewportMatrix
  let prevProj = ctx.projectionMatrix
  defer:
    ctx.viewport = prevView
    ctx.projection = prevProj

  ctx.viewport = viewport
  ctx.projection = projection

  let globals = w.documentGlobals


  w.forEach (surface: PolygonalSurface3, color: (Foreground|Color)||globals.foreground, transform3: Transform3||dmat4()):
    if surface == nil: continue
    let key = cast[pointer](surface)
    if key notin meshCache.entries:
      meshCache.entries[key] = grid3ToMesh(surface[])
    ctx.fill3dMeshShadedByNormalsSingleSide(
      meshCache.entries[key],
      color = color,
      transform = mat4(transform3),
      lightDir = vec3(-0.8, -1, -1.2).normalize,
    )



proc worldBoundsCallback(world: World): RawBounds2 {.cdecl.} =
  let g = world.documentGlobals
  let layout = world.documentLayout(g)
  if layout.contentBounds.empty: return RawBounds2(empty: true)
  let b = layout.contentBounds
  RawBounds2(empty: false, minX: b.min.x, minY: b.min.y, maxX: b.max.x, maxY: b.max.y)

proc textSizeCallback(text: string, fontSize: float64): Vec2 {.cdecl.} =
  var f = newFont(toscelFonts.font_default)
  f.size = fontSize
  let box = typeset(f, text).computeBounds()
  vec2(box.w, box.h)

scriptWorldBounds = worldBoundsCallback
scriptTextSize = textSizeCallback
