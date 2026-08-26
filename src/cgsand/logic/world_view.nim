import std/[options, math, tables]
import pkg/[ecs, vmath, bumpy]
import pkg/pixie/paths
import pkg/pixie/[fonts]
import pkg/toscel/fonts as toscelFonts
import pkg/rice/[primitives, transform, texts, paths, contexts, polygonal3d, gl, hatching]
import pkg/sigeo/surfaces/[grids]
import ../lib/[sandbox, geom2d]
import ./[bounds, doclayout, scripts, document_globals, dashing]


type
  MeshCache* = ref object
    polygonalSurface3*: Table[(pointer, EntityId), Mesh]
    pathStroke*: Table[(pointer, EntityId), Mesh]
    pathFill*: Table[(pointer, EntityId), Mesh]
    curve2Fill*: Table[(pointer, EntityId), Mesh]


template cache*(tabl: var Table[(pointer, EntityId), Mesh], world: World, ent: EntityId, orCreate: Mesh): var Mesh =
  let mesh = tabl.mgetOrPut((cast[pointer](world), ent), Mesh()).addr
  if mesh[].vao == nil:
    mesh[] = orCreate
  mesh[]


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



proc drawHatchedPath(
  ctx: DrawContext,
  mesh: Mesh, hatching: Hatching,
  fg: Color, bg: Color,
  thickness: Thickness,
  transform: Mat4
) =
  ctx.fillHatchingAA(
    mesh = mesh,
    color1 = fg, color2 = bg,
    dir = transform.mat3 * vec2(1, 0).rotate(hatching.angle).vec3(0),
    l1 = thickness, l2 = max(0, hatching.period - thickness),
    transform = transform,
  )


proc unitsPerPixel*(pageSize: Vec2, widgetSize: Vec2): float =
  ## returns unit/pixel that, if viewport is mat4(), whole document fits into widget area
  let cmin = min(pageSize.x, pageSize.y)
  let cmax = max(pageSize.x, pageSize.y)
  let widthLimiting = widgetSize.x / pageSize.x < widgetSize.y / pageSize.y
  let canvasScale =
    if (pageSize.x < pageSize.y) == widthLimiting:
      cmax / cmin
    else:
      1.0

  let limitingDim = if widthLimiting: widgetSize.x else: widgetSize.y
  cmax / (canvasScale * limitingDim)


proc projectionMatrix*(pageBounds: Bounds2, widgetSize: Vec2, axisYDirection: AxisYDirection): Mat4 =
  ## returns a matrix to convert document coordinates to GL space,
  ## if viewport is mat4(), the whole document fits into the widget
  let upp = unitsPerPixel(pageBounds.size.vec2, widgetSize)

  combine(
    translate(-pageBounds.center.V2.vec3(0)),
    scale(y = (if axisYDirection == AxisYDown: -1 else: 1)),
    scale vec3(2 / (upp * widgetSize.x), 2 / (upp * widgetSize.y), 1/1000),
  )


proc scale*(viewport: Mat4): float =
  let sX = sqrt(viewport[0][0] * viewport[0][0] + viewport[0][1] * viewport[0][1])
  let sY = sqrt(viewport[1][0] * viewport[1][0] + viewport[1][1] * viewport[1][1])
  let sZ = sqrt(viewport[2][0] * viewport[2][0] + viewport[2][1] * viewport[2][1])
  max(sX, max(sY, sZ))

proc unitsPerPixel*(pageSize: Vec2, widgetSize: Vec2, viewport: Mat4): float =
  unitsPerPixel(pageSize, widgetSize) / viewport.scale

proc pixelsPerUnit*(pageSize: Vec2, widgetSize: Vec2, viewport: Mat4): float =
  1 / unitsPerPixel(pageSize, widgetSize, viewport)


proc drawLineSection*(ctx: DrawContext, obj: LineSection2, color: Color, thickness = none Thickness, transform = mat4()) =
  if thickness.isSome:
    # todo: find simpler way to make lines same thickness, independent of their direction
    let a = obj.startPoint.V2.vec2.vec3(0)
    let b = obj.endPoint.V2.vec2.vec3(0)
    let m = ctx.viewportMatrix
    let camDir = vec3(m[0][2], m[1][2], m[2][2])
    let lineDir = normalize(b - a)
    var camNormal = camDir - dot(camDir, lineDir) * lineDir
    if dot(camNormal, camNormal) < 1e-10:
      let camUp = vec3(m[0][1], m[1][1], m[2][1])
      camNormal = camUp - dot(camUp, lineDir) * lineDir
    camNormal = normalize(camNormal)

    ctx.fillCapsule(
      a = a, b = b,
      color = color,
      transform = transform,
      radius = thickness.get / 2,
      normal = camNormal,
    )
  else:
    ctx.drawLine(
      a = obj.startPoint.V2.vec2.vec3(0),
      b = obj.endPoint.V2.vec2.vec3(0),
      color = color,
      transform = transform,
    )


proc drawDashedPolyline*(
  ctx: DrawContext,
  points: openArray[Point2],
  dashing: Dashing,
  color: Color,
  thickness = none Thickness,
  transform = mat4(),
  scale: float = 1,
) =
  ## draws a polyline with the given dashing pattern.
  ## pattern[i*2] are dash lengths (0 = dot), pattern[i*2+1] are gap lengths, in document units.
  ##
  ## the pattern is automatically scaled so that:
  ##   a dash is always drawn at the very start and (for open curves) the very end of the curve
  ##   the number of pattern repetitions stays close to the unscaled one, but always >= minRepeats
  # a zero-length capsule renders as a round dot (when thickness is given)
  for (a, b) in dashedSegments(points, dashing, scale):
    drawLineSection(ctx, line(a, b), color, thickness, transform = transform)


proc toMesh*(
  curve: Curve2,
  pointCount: int,
  windingRule: WindingRule = NonZero,
): Mesh =
  var points: Polygon
  for t in 0..<pointCount:
    points.add curve.pointAt(t / (pointCount - 1)).V2.vec2
  let verts = triangulate([points], windingRule)
  if verts.len > 0:
    result = newMesh(verts, GL_TRIANGLES)


proc recommendedPointCount(curve: Curve2, typicalCount = 32): int =
  # todo: dynamic, per-curve-param point count
  if curve.isOf(Path2):
    for c in curve.castTo(Path2).curves.view:
      result += recommendedPointCount(c, typicalCount)
  else:
    return typicalCount


proc drawDocText*(
  ctx: DrawContext,
  text: string, pos: Position2, color: Color, posAt: PositionAt, font: Typeface, fontSize: float, axisYUp: bool,
  transform = mat4(),
) =
  var f = newFont(font)
  f.size = fontSize
  f.lineHeight = fontSize
  let ts = typeset(f, text)
  let origin = posAt.factor().vec2
  ctx.drawText(vec3(pos.x, pos.y, 0), ts, color.vec4, origin=origin, transform=transform, exactBoundaries=true, axisYUp=axisYUp)



proc draw2dWorld*(
  ctx: DrawContext,
  w: World,
  viewport, projection: Mat4,
  pixelsPerUnit: float32,
  meshCache: MeshCache,
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

  # todo: seems like something in rice disables GlBlend
  glEnable(GlBlend)
  glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)


  template cache(mesh: Mesh, to: untyped): Mesh =
    meshCache.to.cache(w, the EntityId, mesh)

  
  w.forEach (
    curve: Curve2|(OwnedCurve2|CircleArc2|EllipseArc2|Path2),
    Fill,
    opt Color,
    opt PointCount,
    transform: Transform3||dmat4(),
  ):
    let transform = transform.mat4

    let color =
      if has Color: the Color
      else: globals.foreground
    
    let pointCount =
      if has PointCount: the PointCount
      else: int(pixelsPerUnit * curve.bounds.size.length).clamp(8, 256)

    ctx.fill2dMeshFlat(curve.toMesh(pointCount).cache(curve2Fill), color = color, transform = transform)

  
  w.forEach (
    curve: Curve2|(OwnedCurve2|CircleArc2|EllipseArc2|Path2),
    Hatching,
    opt Color,
    opt Thickness|PixelThickness,
    opt PointCount,
    transform: Transform3||dmat4(),
  ):
    let transform = transform.mat4

    let color =
      if has Color: the Color
      else: globals.foreground
    
    let pointCount =
      if has PointCount: the PointCount
      else: int(pixelsPerUnit * curve.bounds.size.length).clamp(8, 256)
    
    let thickness =
      if has PixelThickness: some(the(PixelThickness) / pixelsPerUnit)
      elif has Thickness: some the Thickness
      else: none Thickness

    var hatching = the Hatching
    if hatching.period == 0:
      hatching.period = curve.bounds.size.length / 20
    let hthk = thickness.get(otherwise = hatching.period/4)
    
    ctx.drawHatchedPath(
      curve.toMesh(pointCount).cache(curve2Fill),
      hatching = hatching,
      fg = color,
      bg = color(0, 0, 0, 0),
      thickness = (if has(PixelThickness): min(hthk, hatching.period/4) else: hthk),
      transform = transform,
    )

  
  template prepareStroke {.dirty.} =
    let transform = transform.mat4

    let color =
      if has Color: the Color
      else: globals.foreground
    
    let thickness =
      if has PixelThickness: some(the(PixelThickness) / pixelsPerUnit)
      elif has Thickness: some the Thickness
      else: none Thickness

  template drawStroke {.dirty.} =
    if has Dashing:
      let dashingScale =
        if has DashingScale: the DashingScale
        else: globals.dashingScale
      
      ctx.drawDashedPolyline(pts, the Dashing, color, thickness, transform = transform, scale = dashingScale)
    
    else:
      for i in 0 ..< pts.len - 1:
        ctx.drawLineSection(line(pts[i], pts[i + 1]), color, thickness, transform = transform)
  
  w.forEach (
    curve: LineSection2,
    Stroke | not(Stroke|Fill|Hatching),
    opt Color,
    opt Thickness|PixelThickness,
    opt Dashing|DashingScale,
    transform: Transform3||dmat4(),
  ):
    prepareStroke()
    let pts = [curve.startPoint, curve.endPoint]
    drawStroke()
  
  w.forEach (
    curve: Curve2|(OwnedCurve2|LineSection2|CircleArc2|EllipseArc2|Path2),
    Stroke | not(Stroke|Fill|Hatching),
    opt Color,
    opt Thickness|PixelThickness,
    opt Dashing|DashingScale,
    opt PointCount,
    transform: Transform3||dmat4(),
  ):
    prepareStroke()
    let pts =
      if curve.isOf(LineSection2):
        @[curve.castTo(LineSection2).startPoint, curve.castTo(LineSection2).endPoint]
      else:
        let pointCount =
          if has PointCount: the PointCount
          else: int(pixelsPerUnit * curve.bounds.size.length).clamp(8, 256)
        curve.points(pointCount)
    drawStroke()


  w.forEach (
    text: Text,
    pos: Position2||p2(),
    opt Color,
    posAt: PositionAt||PositionAtTopLeft,
    font: Typeface||globals.font,
    size: FontSize||globals.fontSize,
    transform: Transform3||dmat4(),
  ):
    let fg =
      if has Color: the Color
      else: globals.foreground
    drawDocText(ctx, text, pos, fg, posAt, font, size, axisYUp = globals.axisYDirection == AxisYUp, transform = mat4(transform))


  w.forEach (sub: SubWorld, pos: Position2||p2(), opt PositionAt, transform: Transform3||dmat4()):
    if sub == nil: continue

    # todo: documentLayout is recomputed every frame here; cache it
    var anchor = v2(0, 0)
    if has PositionAt:
      let subGlobals = sub.documentGlobals
      let b = sub.documentLayout(subGlobals).contentBounds
      if not b.empty:
        let f = (the PositionAt).factor()
        let sz = b.size
        let axisYUp = subGlobals.axisYDirection == AxisYUp
        anchor = v2(
          b.min.x + f.x * sz.x,
          (if axisYUp: b.max.y - f.y * sz.y else: b.min.y + f.y * sz.y),
        )

    let innerViewport = combine(
      mat4(transform),
      translate(vec3(pos.x - anchor.x, pos.y - anchor.y, 0)),
      viewport,
    )
    let outerToGl = combine(viewport, projection)
    let innerToGl = combine(innerViewport, projection)
    template screenScale(m: Mat4): float32 =
      let sX = sqrt(m[0][0]*m[0][0] + m[0][1]*m[0][1])
      let sY = sqrt(m[1][0]*m[1][0] + m[1][1]*m[1][1])
      let sZ = sqrt(m[2][0]*m[2][0] + m[2][1]*m[2][1])
      max(sX, max(sY, sZ))
    let outerScale = screenScale(outerToGl)
    let innerScale = screenScale(innerToGl)
    let innerPixelsPerUnit = if outerScale > 0: pixelsPerUnit * innerScale / outerScale else: pixelsPerUnit
    GC_ref(sub)
    draw2dWorld(ctx, sub, innerViewport, projection, innerPixelsPerUnit, meshCache)



proc draw3dWorld*(
  ctx: DrawContext,
  w: World,
  viewport, projection: Mat4,
  pixelsPerUnit: float32,
  meshCache: MeshCache,
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
  
  template cache(mesh: Mesh, to: untyped): Mesh =
    meshCache.to.cache(w, the EntityId, mesh)


  w.forEach (EntityId, surface: PolygonalSurface3, color: Color||globals.foreground, transform: Transform3||dmat4()):
    if surface == nil: continue
    ctx.fill3dMeshShadedByNormalsSingleSide(
      grid3ToMesh(surface[]).cache(polygonalSurface3),
      color = color,
      transform = mat4(transform),
      lightDir = vec3(-0.8, -1, -1.2).normalize,
    )



proc entityBoundsCallback(world: World, eid: EntityId): Bounds2 {.cdecl.} =
  let globals = world.documentGlobals
  let (minX, maxX) = world.worldBoundsAlongAxis(v3(1, 0, 0), globals, filter = proc(x: EntityId): bool = x == eid)
  let (minY, maxY) = world.worldBoundsAlongAxis(v3(0, 1, 0), globals, filter = proc(x: EntityId): bool = x == eid)
  bounds2(p2(minX, minY), p2(maxX, maxY))

proc worldBoundsCallback(world: World): Bounds2 {.cdecl.} =
  let g = world.documentGlobals
  let layout = world.documentLayout(g)
  layout.contentBounds

proc textSizeCallback(text: string, fontSize: float64): Vec2 {.cdecl.} =
  var f = newFont(toscelFonts.font_default)
  f.size = fontSize
  let box = typeset(f, text).computeBounds()
  vec2(box.w, box.h)

scriptEntityBounds = entityBoundsCallback
scriptWorldBounds = worldBoundsCallback
scriptTextSize = textSizeCallback
