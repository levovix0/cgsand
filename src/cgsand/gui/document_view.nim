import std/[locks, math]
import pkg/[ecs, shady]
import pkg/siwin/platforms/any/window
import pkg/sigui/[uibase, globalKeybinding, mouseArea, layouts]
import pkg/toscel/[button]
import pkg/rice/[primitives, antialiasing, transform]
import ../logic/[scripts, config, bounds, doclayout, world_view]
import ../lib/sandbox except Mat4, mat4, Vec4, Vec3, Vec2, vec2, vec3, vec4


type
  DocumentView* = ref object of Uiobj
    script*: Property[Script]
    scriptStage*: Property[ScriptStage]
    viewport*: Property[Mat4]
    documentPixels: AntialiasedFramebuffer

    darkTheme: Property[bool]

registerComponent DocumentView


proc fillHatchingRect(
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


proc widgetToViewportPoint(widgetPos: Vec2, width, height: float32, toGl: Mat4): Vec2 =
  let glPos = combine(
    scale(vec3(2 / width, -2 / height, 1)),
    translate(vec3(-1, 1, 0)),
  ) * vec4(widgetPos.x, widgetPos.y, 0, 1)
  (inverse(toGl) * glPos).vec2


proc projection*(this: DocumentView): Mat4 =
  let globals = this.script[].world[].documentGlobals
  let layout = this.script[].world[].documentLayout(globals)
  projectionMatrix(layout.pageBounds, this.w[], this.h[], globals.axisYDirection)

proc viewportToGlMatrix*(this: DocumentView): Mat4 =
  combine(this.viewport, this.projection)

proc widgetToViewportPoint*(this: DocumentView, pos: Vec2): Vec2 =
  widgetToViewportPoint(pos, this.w[], this.h[], this.viewportToGlMatrix)




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
      let w = this.script[].world[]
      let globals = w.documentGlobals
      let layout = w.documentLayout(globals)
      let proj = projectionMatrix(layout.pageBounds, this.w[], this.h[], globals.axisYDirection)
      let toGl = combine(this.viewport[], proj)
      let pixelsPerUnit = sqrt(toGl[0][0]*toGl[0][0] + toGl[1][0]*toGl[1][0]) * this.w[] / 2

      glEnable(GlBlend)
      glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)
      glClearColor(0, 0, 0, 0)
      glClear(GL_COLOR_BUFFER_BIT)

      let prevView = ctx.viewportMatrix
      let prevProj = ctx.projectionMatrix
      defer:
        ctx.viewport = prevView
        ctx.projection = prevProj
      ctx.viewport = this.viewport[]
      ctx.projection = proj

      glDisable(GlBlend)
      ctx.fillHatchingRect(
        vec2(-1, -1 * this.h[] / this.w[]), vec2(2, 2 * this.h[] / this.w[]),
        "#252525".color, "#232323".color,
        vec2(1, 1),
        100 / this.w[], 100 / this.w[],
        transform = scale vec3(1, this.w[] / this.h[], 1)
      )
      ctx.fillRect(
        rect(layout.pageBounds.min, layout.pageBounds.size),
        color = globals.background,
      )
      glEnable(GlBlend)
      glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)

      draw2dWorld(ctx, w, this.viewport[], proj, pixelsPerUnit)

      glDisable(GlBlend)
    finally:
      ctx.pop psh

  if this.documentPixels != nil:
    glEnable(GlBlend)
    ctx.draw(
      this.documentPixels,
      transform = combine(
        translate vec3(0, -this.documentPixels.size.y.float32, 0),
        scale vec3(1, -1, 1),
        translate (this.globalXy + ctx.offset).round.vec3(0),
      )
    )
    glDisable(GlBlend)




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
  let oldCache =
    if this.script[] != nil and this.script[].filename == currentScript[]:
      this.script[].cache
    else:
      nil
  this.script{} = nil  # unload current script
  this.script[] = compileAndRunScript(currentScript[], "build/script", oldCache)



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
          let zoomFactor = pow(1.1'f32, -delta.y)
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


    - Layout.row:
      gap = 10
      centerX = parent.center
      top = parent.top+10


      - Button.new:
        text = tr"Reset view"
        on this.activated: root.viewport[] = mat4()


      - Button.new:
        visibility = Visibility.collapsed

        on root.scriptStage[] == Idle:
          if root.script[] != nil:
            this.visibility[] =
              if root.script[].cache.hasSingleton(DarkTheme):
                Visibility.visible
              else:
                Visibility.collapsed
        
        enabled = binding:
          root.scriptStage[] == Idle and root.script[] != nil

        text = binding:
          if root.darkTheme[]: tr"Theme: dark" else: tr"Theme: light"
        
        on this.activated:
          let cache = root.script[].cache
          root.darkTheme[] = not cache[DarkTheme]
          cache[DarkTheme] = root.darkTheme[]
          rerunScript(root.script[])
