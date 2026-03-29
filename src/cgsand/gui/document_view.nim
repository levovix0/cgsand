import std/[locks]
import pkg/[ecs, shady]
import pkg/sigui/[uibase, globalKeybinding]
import pkg/toscel/[button]
import ../logic/[scripts, config]
import ../lib/sandbox except Mat4
import ../lib/[geom2d]


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
  drawLine(ctx, this.line, obj.startPoint.Vec2, obj.endPoint.Vec2, color, projection * view)



proc draw2dDocument(this: DocumentView, w: ptr World, ctx: DrawContext, view, projection: Mat4) =
  glEnable(GlBlend)
  glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)
  # glEnable(GlDepthTest)

  glClearColor(0, 0, 0, 0)
  # glClearDepthf(1)
  glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)

  w[].forEach (line: LineSection):
    drawLineSection(this, ctx, line, color(1, 1, 1), view, projection)
  
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

    let view = (
      (scale vec3(1/100, 1/100, 1))
    )

    let projection = (
      (if this.w[] < this.h[]: scale vec3(1, this.w[] / this.h[], 1/1000) else: scale vec3(this.h[] / this.w[], 1, 1/1000))
    )

    ctx.push this.documentPixels, clear = false
    try:
      draw2dDocument(this, this.script[].world, ctx, view, projection)
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

