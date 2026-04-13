import std/[locks]
import pkg/[ecs, shady]
import pkg/sigui/[uibase, globalKeybinding]
import pkg/toscel/[button]
import ../logic/[scripts, config]
import ../lib/sandbox except Mat4, mat4, Vec4, Vec3, Vec2, vec2, vec3, vec4
import ../lib/[geom2d, c3d]


type
  DocumentView* = ref object of Uiobj
    script*: Property[Script]
    scriptStage*: Property[ScriptStage]

    documentPixels: EffectBuffer
    line: Shape  # todo: use rice

registerComponent DocumentView



proc newEffectBuffer*(ctx: DrawContext, size: IVec2): EffectBuffer =
  ## create new effect buffer with exact size
  ## todo: move to sigui
  new result

  template ef: untyped = result
  ef.size = size
  ef.fbo = newFrameBuffers(1)
  ef.tex = newTexture()

  let prevFbo =
    if ctx.frameBufferHierarchy.len != 0: ctx.frameBufferHierarchy[^1].fbo
    else: 0
  
  glBindFramebuffer(GlFramebuffer, ef.fbo[0])
  glBindTexture(GlTexture2d, ef.tex.raw)
  glTexImage2D(GlTexture2d, 0, GlRgba.Glint, ef.size.x, ef.size.y, 0, GlRgba, GlUnsignedByte, nil)
  glTexParameteri(GlTexture2d, GlTextureMinFilter, GlNearest)
  glTexParameteri(GlTexture2d, GlTextureMagFilter, GlNearest)
  glFramebufferTexture2D(GlFramebuffer, GlColorAttachment0, GlTexture2d, ef.tex.raw, 0)
      
  glBindFramebuffer(GlFramebuffer, prevFbo)


proc drawLine*(ctx: DrawContext, lineShape: Shape, a, b: Vec3, color: Color, transform: Mat4 = mat4()) =
  # todo: use rice
  let d = b - a
  let transform = (
    transform *
    translate(a) *
    mat4(
      d.x, d.y, d.z, 0,
      0,   0,   0,   0,
      0,   0,   0,   0,
      0,   0,   0,   1,
    )
  )

  let shader = ctx.makeShader:
    proc vert(
      t: float32,
      transform: Uniform[Mat4],
    ) =
      gl_Position = transform * vec4(t, 0, 0, 1)
    
    proc frag(
      glCol: var Vec4,
      color: Uniform[Vec4],
    ) =
      glCol = color

  use shader.shader
  shader.color.uniform = color.vec4
  shader.transform.uniform = transform
  draw lineShape


proc drawLine*(ctx: DrawContext, lineShape: Shape, a, b: Vec2, color: Color, transform: Mat4 = mat4()) =
  # todo: use rice
  drawLine(ctx, lineShape, vec3(a.x, a.y, 0), vec3(b.x, b.y, 0), color, transform)
  

proc fillRect*(ctx: DrawContext, pos, size: Vec2, color: Color, transform: Mat4 = mat4()) =
  # todo: use rice
  let transform = (
    transform *
    translate(pos.vec3(0)) *
    scale(size.vec3(1))
  )

  let shader = ctx.makeShader:
    proc vert(
      pos: Vec2,
      transform: Uniform[Mat4],
    ) =
      gl_Position = transform * vec4(pos.x, pos.y, 0, 1)
    
    proc frag(
      glCol: var Vec4,
      color: Uniform[Vec4],
    ) =
      glCol = color

  use shader.shader
  shader.color.uniform = color.vec4
  shader.transform.uniform = transform
  draw ctx.rect
  

proc fillHatchingRect*(
  ctx: DrawContext,
  pos, size: Vec2,
  color1, color2: Color,
  dir: Vec2,
  l1, l2: float32,
  transform: Mat4 = mat4()
) =
  # todo: use rice
  let transform = (
    transform *
    translate(pos.vec3(0)) *
    scale(size.vec3(1))
  )

  let shader = ctx.makeShader:
    proc vert(
      pos: Vec2,
      transform: Uniform[Mat4],
      uv: var Vec2,
    ) =
      gl_Position = transform * vec4(pos.x, pos.y, 0, 1)
      uv = pos
    
    proc frag(
      glCol: var Vec4,
      uv: Vec2,
      color1: Uniform[Vec4],
      color2: Uniform[Vec4],
      dir: Uniform[Vec2],
      l1: Uniform[float32],
      l2: Uniform[float32],
      size: Uniform[Vec2],
      pos: Uniform[Vec2],
    ) =
      if (uv * size + pos).dot(dir / dir.length) mod (l1 + l2) > l1:
        glCol = color1
      else:
        glCol = color2

  use shader.shader
  shader.color1.uniform = color1.vec4
  shader.color2.uniform = color2.vec4
  shader.dir.uniform = dir
  shader.l1.uniform = l1
  shader.l2.uniform = l2
  shader.transform.uniform = transform
  shader.size.uniform = size
  shader.pos.uniform = pos
  draw ctx.rect


proc drawLineSection*(this: DocumentView, ctx: DrawContext, obj: LineSection, color: Color, view, projection: Mat4) =
  ## todo: port sigui to rice and use drawLine from rice
  if this.line == nil:
    this.line = newShape(
      [
        0'f32,
        1,
      ],
      [
        0'u32,
        1
      ],
      kind = GL_LINES
    )
  drawLine(ctx, this.line, sandbox.Vec2(obj.startPoint).vec2, sandbox.Vec2(obj.endPoint).vec2, color, projection * view)



proc draw2dDocument(this: DocumentView, w: ptr World, ctx: DrawContext, width, height: float32) =
  glEnable(GlBlend)
  glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)
  # glEnable(GlDepthTest)

  glClearColor(0, 0, 0, 0)
  # glClearDepthf(1)
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)

  var canvasSettings = CanvasSettings()
  w[].forEach (v: CanvasSettings): canvasSettings = v
  
  let cmin = min(canvasSettings.size.x, canvasSettings.size.y)
  let cmax = max(canvasSettings.size.x, canvasSettings.size.y)
  let canvasScale =
    if (canvasSettings.size.x < canvasSettings.size.y) == (width / canvasSettings.size.x < height / canvasSettings.size.y):
      cmax / cmin
    else:
      1

  let view = (
    (scale vec3(2/cmax, 2/cmax, 1))
  )

  let projection = (
    if width / canvasSettings.size.x < height / canvasSettings.size.y:
      scale vec3(canvasScale, width / height * canvasScale, 1/1000)
    else:
      scale vec3(height / width * canvasScale, canvasScale, 1/1000)
  )

  glDisable(GlBlend)
  ctx.fillHatchingRect(
    vec2(-1, -1 * height / width), vec2(2, 2 * height / width),
    "#252525".color, "#232323".color,
    vec2(1, 1),
    100 / width, 100 / width,
    transform = scale vec3(1, width / height, 1)
  )
  ctx.fillRect(-canvasSettings.size.vec2/2, canvasSettings.size.vec2, color(0, 0, 0, 0), projection * view)
  glEnable(GlBlend)
  glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)


  w[].forEach (line: LineSection, color: Color||color(1, 1, 1)):
    drawLineSection(this, ctx, line, color, view, projection)


  w[].forEach (curve: MbArc, color: Color||color(1, 1, 1), count: PointCount||20):
    let points = curve.points(count)
    if curve.closed:
      for i in 0 ..< points.len:
        drawLineSection(this, ctx, lineSection(points[i], points[(i + 1) mod points.len]), color, view, projection)
    else:
      for i in 0 ..< points.len-1:
        drawLineSection(this, ctx, lineSection(points[i], points[i + 1]), color, view, projection)
  

  glDisable(GlBlend)
  # glDisable(GlDepthTest)


proc hasWorldToDraw(script: Script): bool =
  if script == nil: return false
  withLock script.lock:
    if script.stage != Idle: return false
    if script.world == nil: return false
  true



proc draw2dDocumentView(this: DocumentView, ctx: DrawContext) =
  if this.script[].hasWorldToDraw:
    if (let efSize = ivec2(this.w[].ceil.int32, this.h[].ceil.int32); this.documentPixels == nil or this.documentPixels.size != efSize):
      if this.documentPixels != nil:
        ctx.free this.documentPixels
      this.documentPixels = ctx.newEffectBuffer(efSize)

    ctx.push this.documentPixels, clear = false
    try:
      draw2dDocument(this, this.script[].world, ctx, this.w[], this.h[])
    finally:
      ctx.pop this.documentPixels


  if this.documentPixels != nil:
    ctx.drawImage(
      (this.globalXy + ctx.offset).round, this.wh,
      this.documentPixels.tex.raw, color(1, 1, 1).vec4, 0, true, 0, flipY=true,
      imageSize = this.documentPixels.size.vec2,
    )




method draw*(this: DocumentView, ctx: DrawContext) =
  this.drawBefore(ctx)
  if this.visibility[] == visible:
    this.draw2dDocumentView(ctx)
  this.drawAfter(ctx)



proc recompileScript*(this: DocumentView) =
  if this.script[] != nil:
    withLock this.script[].lock:
      if this.script[].stage != Idle:
        return  # ignore recompile request while still compiling
  this.script{} = nil  # unload current script
  this.script[] = compileAndRunScript("examples/script.nim", "build/script")



method init*(this: DocumentView) =
  procCall this.super.init()

  this.parentUiRoot.onTick.connectTo this:
    if this.script[] != nil:
      withLock this.script[].lock:
        this.scriptStage[] = this.script[].stage

  this.makeLayout:
    - UiRect.new:
      this.fill(parent)
      color = "#282828".color
      layer = before root

    - globalKeybinding({Key.f5}):
      on this.activated: root.recompileScript()
    
    - Button.new:
      text = tr"Recompile"
      centerX = parent.center
      bottom = parent.bottom - 10
      on this.activated: root.recompileScript()
    
    - UiRect.new:
      h = 2
      w = binding:
        case root.scriptStage[]
        of Idle: parent.w[] * (0 / 2)
        of Compiling: parent.w[] * (1 / 2)
        of Executing: parent.w[] * (2 / 2)
      bottom = parent.bottom
      color = "#76b1ffff".color

