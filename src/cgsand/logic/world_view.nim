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
  ctx.fillHatching(
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


  template selectThickness: Option[Thickness] {.dirty.} =
    if has PixelThickness: some(the(PixelThickness) / pixelsPerUnit)
    elif has Thickness: some the Thickness
    else: none Thickness
  
  template cache(mesh: Mesh, to: untyped): Mesh =
    meshCache.to.cache(w, the EntityId, mesh)


  w.forEach (line: LineSection2, color: (Foreground|Color)||globals.foreground, opt Thickness|PixelThickness, transform: Transform3||dmat4()):
    let thk = selectThickness()
    drawLineSection(ctx, line, color, thk, transform = mat4(transform))


  w.forEach (curve: CircleArc2, opt PointCount, opt Color|Background|Foreground, opt Thickness|PixelThickness, transform: Transform3||dmat4()):
    let screenRadius = float32(curve.radius) * pixelsPerUnit
    let count =
      if has PointCount: the PointCount
      else: clamp(int(screenRadius * abs(float32(curve.angularLength)) / 4.0), 8, 256)
    let points = curve.points(count)
    let fg =
      if has Foreground: the Foreground
      elif has Color: the Color
      else: globals.foreground
    let thk = selectThickness()
    let t3 = mat4(transform)

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


  w.forEach (arc: EllipseArc2, color: (Foreground|Color)||globals.foreground, opt PointCount, opt Thickness|PixelThickness, transform: Transform3||dmat4()):
    let screenRadius = float32(max(arc.size.x, arc.size.y) / 2) * pixelsPerUnit
    let count =
      if has PointCount: the PointCount
      else: clamp(int(screenRadius * abs(float32(arc.angularLength)) / 4.0), 12, 256)
    let points = arc.points(count)
    let thk = selectThickness()
    let t3 = mat4(transform)

    # todo: Background support (fill ellipse)

    for i in 0 ..< points.len - 1:
      drawLineSection(ctx, lineSection(points[i], points[i + 1]), color, thk, transform = t3)


  w.forEach (path: Path, opt Foreground|Color|Background|Hatching, opt Thickness|PixelThickness, transform: Transform3||dmat4()):
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
    pos: Position2,
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


  w.forEach (sub: SubWorld, pos: Position2, transform: Transform3||dmat4()):
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
