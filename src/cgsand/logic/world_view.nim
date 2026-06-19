import std/[options, math, tables]
import pkg/[ecs, vmath, bumpy]
import pkg/pixie/paths
import pkg/pixie/[fonts]
import pkg/toscel/fonts as toscelFonts
import pkg/rice/[primitives, transform, texts, paths, contexts, polygonal3d, gl, hatching]
import pkg/sigeo/grids/[extrusions, smoothshading]
import ./[bounds, doclayout, scripts, document_globals]
import ../lib/[sandbox, geom2d]


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
    translate(-pageBounds.center.V2.vec3(0)),
    scale(y = (if axisYDirection == AxisYDown: -1 else: 1)),
    scale vec3(2/cmax, 2/cmax, 1),
    (
      if width / pageSize.x < height / pageSize.y:
        scale vec3(canvasScale, width / height * canvasScale, 1/1000)
      else:
        scale vec3(height / width * canvasScale, canvasScale, 1/1000)
    ),
  )


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
  const minRepeats = 2
  
  if points.len < 2:
    return
  if dashing.pattern.len == 0:
    for i in 0 ..< points.len - 1:
      drawLineSection(ctx, line(points[i], points[i + 1]), color, thickness, transform = transform)
    return

  # total length of the polyline, and whether it forms a closed loop
  var total = 0.0
  for i in 0 ..< points.len - 1:
    total += points[i].distanceTo(points[i + 1])
  let closed = points[0] ~== points[^1]

  var pat = dashing.pattern
  if scale != 1:
    for i in 0 ..< pat.len:
      pat[i] *= scale

  let cycleLen = pat.sum
  if cycleLen > 0 and total > 0:
    ## for an open curve, drop the tail of the last cycle that comes after its last positive-length dash,
    ## so the curve always ends on a drawn line (not a gap or a dot).
    ## e.g. for [dash, gap, dot, gap] this drops [gap, dot, gap].
    var trailingGap = 0.0
    if not closed:
      var lastDash = -1
      for i in 0 ..< pat.len:
        if (i mod 2) == 0 and pat[i] > 0:
          lastDash = i
      if lastDash >= 0:
        for i in lastDash + 1 ..< pat.len:
          trailingGap += pat[i]
    
    let reps = max(minRepeats, round(total / cycleLen).int)
    let target = reps.float * cycleLen - trailingGap
    if target > 0:
      let s = total / target
      for i in 0 ..< pat.len:
        pat[i] *= s

  template isDash(idx: int): bool = (idx mod 2) == 0
  template drawDot(p: Point2) =
    # a zero-length capsule renders as a round dot (when thickness is given)
    drawLineSection(ctx, line(p, p), color, thickness, transform = transform)

  var patIdx = 0
  var patRemaining = pat[0]

  # emit a leading dot if the pattern starts with a zero-length dash
  if isDash(patIdx) and pat[patIdx] == 0:
    drawDot(points[0])
    patIdx = (patIdx + 1) mod pat.len
    patRemaining = pat[patIdx]

  for i in 0 ..< points.len - 1:
    let a = points[i]
    let b = points[i + 1]
    let segLen = a.distanceTo(b)
    if segLen <= 0: continue
    let dir = (b - a) / segLen
    var pos = 0.0
    while pos < segLen - 1e-9:
      if patRemaining <= 0:
        patIdx = (patIdx + 1) mod pat.len
        patRemaining = pat[patIdx]
        if isDash(patIdx) and pat[patIdx] == 0:
          drawDot(a + dir * pos)
          patIdx = (patIdx + 1) mod pat.len
          patRemaining = pat[patIdx]
        continue
      let step = min(patRemaining, segLen - pos)
      if isDash(patIdx):
        drawLineSection(ctx, line(a + dir * pos, a + dir * (pos + step)), color, thickness, transform = transform)
      pos += step
      patRemaining -= step


proc toMesh*(
  curve: Curve2,
  pointCount: int,
  windingRule: WindingRule = NonZero,
): Mesh =
  var points: Polygon
  for t in 0..<pointCount:
    points.add curve.pointAtParam(t / (pointCount - 1)).V2.vec2
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


  template selectThickness: Option[Thickness] {.dirty.} =
    if has PixelThickness: some(the(PixelThickness) / pixelsPerUnit)
    elif has Thickness: some the Thickness
    else: none Thickness
  
  template dashScale: float {.dirty.} =
    if has DashingScale: the DashingScale
    else: globals.dashingScale

  template cache(mesh: Mesh, to: untyped): Mesh =
    meshCache.to.cache(w, the EntityId, mesh)

  template drawStroke(pts: openArray[Point2], col: Color, thk: Option[Thickness], t: Mat4) {.dirty.} =
    # draws a polyline stroke, dashed if the entity has a Dashing component
    if has Dashing:
      drawDashedPolyline(ctx, pts, the Dashing, col, thk, transform = t, scale = dashScale)
    else:
      for i in 0 ..< pts.len - 1:
        drawLineSection(ctx, line(pts[i], pts[i + 1]), col, thk, transform = t)


  # todo: instead of all of this, draw in three layers: Background, Hatching, Foreground
  # todo: and unify color selection boilerplate
  # todo: and unify efficiently castable to Curve2 curve rendering
  # todo: and fix the broken OwnedCurve2 and Path2 rendering
  # todo: and add the convinient RefCurve2


  w.forEach (
    line: LineSection2,
    color: (Foreground|Color)||globals.foreground,
    opt Thickness|PixelThickness,
    opt Dashing|DashingScale,
    transform: Transform3||dmat4()
  ):
    let thk = selectThickness()
    drawStroke([line.startPoint, line.endPoint], color, thk, mat4(transform))


  w.forEach (
    curve: CircleArc2,
    opt PointCount,
    opt Color|Background|Foreground|Hatching,
    opt Thickness|PixelThickness,
    opt Dashing|DashingScale,
    transform: Transform3||dmat4()
  ):
    let screenRadius = float32(curve.radius) * pixelsPerUnit
    let pointCount =
      if has PointCount: the PointCount
      else: clamp(int(screenRadius * abs(float32(curve.angularLength)) / 4.0), 8, 256)
    let points = curve.points(pointCount)
    let fg =
      if has Foreground: the Foreground
      elif has Color: the Color
      else: globals.foreground
    let thk = selectThickness()
    let t3 = mat4(transform)

    if curve.closed:
      if has Background:
        ctx.fillCircle(
          color = the Background,
          radius = curve.radius,
          center = curve.center.DVec2.vec2.vec3(0),
          pointCount = pointCount,
          transform = t3,
        )

      if (Background.has.not and Hatching.has.not) or (Color.has and Hatching.has.not) or Foreground.has:
        drawStroke(points, fg, thk, t3)
    else:
      if Foreground.has or Color.has or Background.has.not:
        drawStroke(points, fg, thk, t3)

    if has Hatching:
      var hatching = the Hatching
      if hatching.period == 0:
        hatching.period = curve.bounds.size.length / 20
      let hthk = thk.get(otherwise = hatching.period/4)
      
      ctx.drawHatchedPath(
        curve.toMesh(pointCount).cache(curve2Fill),
        hatching = hatching,
        fg = (if has Color: the Color else: globals.foreground),
        bg = (if has Background: the Background else: color(0, 0, 0, 0)),
        thickness = (if has(PixelThickness): min(hthk, hatching.period/4) else: hthk),
        transform = t3,
      )


  w.forEach (
    arc: EllipseArc2,
    color: (Foreground|Color)||globals.foreground,
    opt PointCount,
    opt Thickness|PixelThickness,
    opt Dashing|DashingScale,
    transform: Transform3||dmat4()
  ):
    let screenRadius = float32(max(arc.size.x, arc.size.y) / 2) * pixelsPerUnit
    let count =
      if has PointCount: the PointCount
      else: clamp(int(screenRadius * abs(float32(arc.angularLength)) / 4.0), 12, 256)
    let points = arc.points(count)
    let thk = selectThickness()
    let t3 = mat4(transform)

    # todo: Background support (fill ellipse)

    drawStroke(points, color, thk, t3)
  
  w.forEach (
    curve: OwnedCurve2|Path2|Curve2,
    opt Foreground|Color|Background|Hatching,
    opt Thickness|PixelThickness,
    opt Dashing|DashingScale,
    pointCount: PointCount||curve.recommendedPointCount,
    transform: Transform3||dmat4()
  ):
    # todo: split into Background and Foreground renderer
    let t3 = mat4(transform)
    let thk = selectThickness()

    if has Hatching:
      var hatching = the Hatching
      if hatching.period == 0:
        hatching.period = curve.bounds.size.length / 20
      let hthk = thk.get(otherwise = hatching.period/4)
      
      ctx.drawHatchedPath(
        curve.toMesh(pointCount).cache(curve2Fill),
        hatching = hatching,
        fg = (if has Color: the Color else: globals.foreground),
        bg = (if has Background: the Background else: color(0, 0, 0, 0)),
        thickness = (if has(PixelThickness): min(hthk, hatching.period/4) else: hthk),
        transform = t3,
      )
    elif has Background:
      ctx.fill2dMeshFlat(curve.toMesh(pointCount).cache(curve2Fill), color = the Background, transform = t3)
    
    if (has Foreground):
      let points = curve.points(pointCount)
      drawStroke(points, the Foreground, thk, t3)
    elif (has Color) and not(has Hatching):
      let points = curve.points(pointCount)
      drawStroke(points, the Color, thk, t3)
    elif not(has Background) and not(has Hatching):
      ctx.fill2dMeshFlat(curve.toMesh(pointCount).cache(curve2Fill), color = globals.foreground, transform = t3)


  w.forEach (
    path: Path,
    opt Foreground|Color|Background|Hatching,
    opt Thickness|PixelThickness,
    transform: Transform3||dmat4()
  ):
    let t3 = mat4(transform)
    let thk = selectThickness()
    # todo: wrong pixelScale
    # todo: line thickness is wrongly cached into mesh

    if has Hatching:
      var hatching = the Hatching
      if hatching.period == 0:
        hatching.period = path.computeBounds().wh.length / 20
      let hthk = thk.get(otherwise = hatching.period/4)
      
      ctx.drawHatchedPath(
        path.toMesh(pixelScale = pixelsPerUnit).cache(pathFill),
        hatching = hatching,
        fg = (if has Color: the Color else: globals.foreground),
        bg = (if has Background: the Background else: color(0, 0, 0, 0)),
        thickness = (if has(PixelThickness): min(hthk, hatching.period/4) else: hthk),
        transform = t3,
      )
    elif has Background:
      ctx.fill2dMeshFlat(path.toMesh(pixelScale = pixelsPerUnit).cache(pathFill), color = the Background, transform = t3)
    
    if (has Foreground):
      ctx.fill2dMeshFlat(path.toStrokeMesh(
        strokeWidth = thk.get(otherwise = 1), pixelScale = pixelsPerUnit, lineCap = RoundCap, lineJoin = RoundJoin
      ).cache(pathStroke), color = the Foreground, transform = t3)
    elif (has Color) and not(has Hatching):
      ctx.fill2dMeshFlat(path.toStrokeMesh(
        strokeWidth = thk.get(otherwise = 1), pixelScale = pixelsPerUnit, lineCap = RoundCap, lineJoin = RoundJoin
      ).cache(pathStroke), color = the Color, transform = t3)
    elif not(has Background) and not(has Hatching):
      ctx.fill2dMeshFlat(path.toMesh(pixelScale = pixelsPerUnit).cache(pathFill), color = globals.foreground, transform = t3)


  w.forEach (
    text: Text,
    pos: Position2||p2(),
    opt Foreground, opt Color,
    posAt: PositionAt||PositionAtTopLeft,
    font: Typeface||globals.font,
    size: FontSize||globals.fontSize,
    transform: Transform3||dmat4(),
  ):
    let fg =
      if has Foreground: the Foreground
      elif has Color: the Color
      else: globals.foreground
    drawDocText(ctx, text, pos, fg, posAt, font, size, axisYUp = globals.axisYDirection == AxisYUp, transform = mat4(transform))


  w.forEach (sub: SubWorld, pos: Position2||p2(), transform: Transform3||dmat4()):
    if sub == nil: continue
    let innerViewport = combine(
      mat4(transform),
      translate(vec3(pos.x, pos.y, 0)),
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


  w.forEach (EntityId, surface: PolygonalSurface3, color: (Foreground|Color)||globals.foreground, transform: Transform3||dmat4()):
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
