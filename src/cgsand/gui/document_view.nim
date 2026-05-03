import std/[locks, options, math]
import pkg/[ecs, shady]
import pkg/siwin/platforms/any/window
import pkg/sigui/[uibase, globalKeybinding, mouseArea]
import pkg/toscel/[button, fonts]
import pkg/rice/[primitives, antialiasing, transform, texts]
import ../logic/[scripts, config]
import ../lib/sandbox except Mat4, mat4, Vec4, Vec3, Vec2, vec2, vec3, vec4
import ../lib/[geom2d, c3d]


type
  DocumentView* = ref object of Uiobj
    script*: Property[Script]
    scriptStage*: Property[ScriptStage]
    viewport*: Property[Mat4]

    documentPixels: AntialiasedFramebuffer

registerComponent DocumentView
  

proc fillHatchingRect*(
  ctx: DrawContext,
  pos, size: Vec2,
  color1, color2: Color,
  dir: Vec2,
  l1, l2: float32,
  transform: Mat4 = mat4()
) =
  # todo: move to rice
  let transform = (
    transform *
    translate(pos.vec3(0)) *
    scale(size.vec3(1))
  )

  let shader = ctx.makeShader:
    proc vert =
      var pos {.inp.}: Vec2
      var uv {.out.}: Vec2
      gl_Position = @(transform) * vec4(pos.x, pos.y, 0, 1)
      uv = pos
    
    proc frag =
      var glCol {.outGl.}: Vec4
      if (uv * @(size) + @(pos)).dot(@(dir.normalize.vec2)) mod (@(l1) + @(l2)) > @(l1):
        glCol = @(color1.vec4)
      else:
        glCol = @(color2.vec4)

  useAndPassUniforms shader
  draw ctx.rect


proc drawLineSection*(ctx: DrawContext, obj: LineSection, color: Color, thickness = none float32, transform = mat4()) =
  if thickness.isSome:
    ctx.drawLine(
      a = sandbox.Vec2(obj.startPoint).vec2.vec3(0),
      b = sandbox.Vec2(obj.endPoint).vec2.vec3(0),
      color = color,
      transform = transform,
      thickness = thickness.get,
    )
  else:
    ctx.drawLine(
      a = sandbox.Vec2(obj.startPoint).vec2.vec3(0),
      b = sandbox.Vec2(obj.endPoint).vec2.vec3(0),
      color = color,
      transform = transform,
    )



proc drawText*(
  ctx: DrawContext,
  text: string, pos: Position2, color: Color, posAt: PositionAt, font: Typeface, fontSize: float,
  transform = mat4(),
) =
  let fontSize = (ctx.viewportToGlMatrix * vec4(0, fontSize, 0, 0)).y / ctx.px.y
  let ts = typeset(font.withSize(fontSize), text)
  let origin = case posAt
    of PositionAtTopLeft: vec2(0, 0)
    of PositionAtTopRight: vec2(1, 0)
    of PositionAtBottomLeft: vec2(0, 1)
    of PositionAtBottomRight: vec2(1, 1)
    of PositionAtLeft: vec2(0, 1/2)
    of PositionAtRight: vec2(1, 1/2)
    of PositionAtTop: vec2(1/2, 0)
    of PositionAtBottom: vec2(1/2, 1)
    of PositionAtCenter: vec2(1/2, 1/2)
  ctx.drawText(vec3(pos.x, pos.y, 0), ts, color.vec4, origin=origin, transform=transform, exactBoundaries=true)


proc projectionMatrix(canvasSettings: CanvasSettings, width, height: float32): Mat4 =
  ## returns a matrix to convert coordinates from document to framebuffer
  ## if viewport matrix is mat4(), whole document will be fit into widget (assuming framebuffer takes whole space of the docuemnt view widget)
  let cmin = min(canvasSettings.size.x, canvasSettings.size.y)
  let cmax = max(canvasSettings.size.x, canvasSettings.size.y)
  let canvasScale =
    if (canvasSettings.size.x < canvasSettings.size.y) == (width / canvasSettings.size.x < height / canvasSettings.size.y):
      cmax / cmin
    else:
      1

  combine(
    scale vec3(2/cmax, 2/cmax, 1),
    (
      if width / canvasSettings.size.x < height / canvasSettings.size.y:
        scale vec3(canvasScale, width / height * canvasScale, 1/1000)
      else:
        scale vec3(height / width * canvasScale, canvasScale, 1/1000)
    ),
  )


proc widgetToViewportPoint(widgetPos: Vec2, width, height: float32, toGl: Mat4): Vec2 =
  let glPos = combine(
    scale(vec3(2 / width, -2 / height, 1)),
    translate(vec3(-1, 1, 0)),
  ) * vec4(widgetPos.x, widgetPos.y, 0, 1)
  (inverse(toGl) * glPos).vec2


proc canvasSettings(w: ptr World): CanvasSettings =
  result = CanvasSettings()
  w[].forEach (v: CanvasSettings):
    result = v


proc projection*(this: DocumentView): Mat4 =
  projectionMatrix(this.script[].world.canvasSettings, this.w[], this.h[])

proc viewportToGlMatrix*(this: DocumentView): Mat4 =
  combine(this.viewport, this.projection)

proc widgetToViewportPoint*(this: DocumentView, pos: Vec2): Vec2 =
  widgetToViewportPoint(pos, this.w[], this.h[], this.viewportToGlMatrix)



proc draw2dDocument(this: DocumentView, w: ptr World, ctx: DrawContext, width, height: float32) =
  glEnable(GlBlend)
  glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)
  # glEnable(GlDepthTest)

  glClearColor(0, 0, 0, 0)
  # glClearDepthf(1)
  glClear(GL_COLOR_BUFFER_BIT #[or GL_DEPTH_BUFFER_BIT]#)

  var canvasSettings = CanvasSettings()
  var foreground = color(1, 1, 1)
  var background = color(0, 0, 0, 0)
  var fontSize = 10.0
  w[].forEach (v: CanvasSettings, opt Foreground, opt Background, opt FontSize):
    canvasSettings = v
    if has Foreground: foreground = the Foreground
    if has Background: background = the Background
    if has FontSize: fontSize = the FontSize
  
  let prevView = ctx.viewportMatrix
  let prevProj = ctx.projectionMatrix
  defer:
    ctx.viewport = prevView
    ctx.projection = prevProj
  
  ctx.viewport = this.viewport[]
  ctx.projection = this.projection

  glDisable(GlBlend)
  ctx.fillHatchingRect(
    vec2(-1, -1 * height / width), vec2(2, 2 * height / width),
    "#252525".color, "#232323".color,
    vec2(1, 1),
    100 / width, 100 / width,
    transform = scale vec3(1, width / height, 1)
  )
  ctx.fillRect(
    rect(
      -canvasSettings.size.vec2/2,
      canvasSettings.size.vec2
    ),
    color = background,
  )
  glEnable(GlBlend)
  glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)


  w[].forEach (line: LineSection, color: Color||foreground, thickness: opt Thickness):
    drawLineSection(ctx, line, color, (if has Thickness: some thickness else: none Thickness))


  w[].forEach (curve: MbArc, color: Color||foreground, count: PointCount||20):
    let points = curve.points(count)
    if curve.closed:
      for i in 0 ..< points.len:
        drawLineSection(ctx, lineSection(points[i], points[(i + 1) mod points.len]), color)
    else:
      for i in 0 ..< points.len-1:
        drawLineSection(ctx, lineSection(points[i], points[i + 1]), color)


  w[].forEach (text: Text, pos: Position2, color: Color||foreground, posAt: PositionAt||PositionAtTopLeft, font: Typeface||font_default, size: FontSize||fontSize):
    drawText(ctx, text, pos, color, posAt, font, size)
  

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
    let efSize = ivec2(this.w[].ceil.int32, this.h[].ceil.int32)
    if this.documentPixels == nil:
      this.documentPixels = ctx.newAntialiasedFramebuffer(efSize)
    else:
      ctx.resize(this.documentPixels, efSize)

    let psh = ctx.push(this.documentPixels)
    try:
      draw2dDocument(this, this.script[].world, ctx, this.w[], this.h[])
    finally:
      ctx.pop psh

  if this.documentPixels != nil:
    ctx.draw(
      this.documentPixels,
      transform = combine(
        translate vec3(0, -this.documentPixels.size.y.float32, 0),
        scale vec3(1, -1, 1),
        translate (this.globalXy + ctx.offset).round.vec3(0),
      )
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
  this.script[] = compileAndRunScript(currentScript[], "build/script")



method init*(this: DocumentView) =
  procCall this.super.init()
  this.viewport[] = mat4()

  var prevDragPos = vec2(0, 0)

  this.parentUiRoot.onTick.connectTo this:
    if this.script[] != nil:
      withLock this.script[].lock:
        this.scriptStage[] = this.script[].stage

  this.makeLayout:
    - UiRect.new:
      this.fill(parent)
      color = "#282828".color
      layer = before root

    - MouseArea.new as cameraMouse:
      this.fill(parent)
      acceptedButtons = {MouseButton.middle}

      this.mouseButton.connectTo root, e:
        if e.button == MouseButton.middle and e.pressed:
          prevDragPos = this.mouseXy[]

      this.moved.connectTo root, e:
        if root.script[].hasWorldToDraw.not: return
        if this.pressed[]:
          let currentMousePos = this.mouseXy[]
          let currentPos = root.widgetToViewportPoint(currentMousePos)
          let previousPos = root.widgetToViewportPoint(prevDragPos)
          root.viewport[] = combine(
            translate((currentPos - previousPos).vec3(0)),  # pan
            root.viewport[]
          )
          prevDragPos = currentMousePos

      this.scrolled.connectTo root, delta:
        if root.script[].hasWorldToDraw.not: return
        if delta.y != 0:
          let anchor = root.widgetToViewportPoint(this.mouseXy[])
          let zoomFactor = pow(1.1'f32, delta.y)
          root.viewport[] = combine(
            translate(-anchor.vec3(0)),
            scale(vec3(zoomFactor, zoomFactor, 1)),  # zoom
            translate((anchor).vec3(0)),
            root.viewport[],
          )

    - globalKeybinding({Key.f5}):
      on this.activated: root.recompileScript()
    
    - Button.new:
      text = tr"Recompile"
      centerX = parent.center
      bottom = parent.bottom - 10
      enabled = binding: root.scriptStage[] == Idle
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
