import std/[locks, math]
import pkg/[ecs, shady]
import pkg/siwin/platforms/any/window
import pkg/sigui/[uibase, globalKeybinding, mouseArea, layouts]
import pkg/toscel/[button]
import pkg/rice/[primitives, antialiasing, transform]
import ../logic/[scripts, config, bounds, doclayout, world_view, document_globals]
import ../lib/sandbox except Mat4, mat4, Vec4, Vec3, Vec2, vec2, vec3, vec4


type
  DocumentView* = ref object of Uiobj
    script*: Property[Script]
    scriptStage*: Property[ScriptStage]
    viewport*: Property[Mat4]
    documentPixels: AntialiasedFramebuffer

    darkTheme: Property[bool]
    scriptOptLevel: Property[ScriptOptLevel]
    mode3d*: Property[bool]
    grid3MeshCache: Grid3MeshCache

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


proc worldCenter3D*(w: World): Vec3 =
  ## Returns the center of the 3D bounding box of the world.
  let globals = w.documentGlobals
  let (x0, x1) = w.worldBoundsAlongAxis(sandbox.vec3(1, 0, 0), globals)
  let (y0, y1) = w.worldBoundsAlongAxis(sandbox.vec3(0, 1, 0), globals)
  let (z0, z1) = w.worldBoundsAlongAxis(sandbox.vec3(0, 0, 1), globals)
  vec3((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)


proc drawDocumentView(this: DocumentView, ctx: DrawContext) =
  if this.script[].hasWorldToDraw:
    let efSize = ivec2(this.w[].ceil.int32, this.h[].ceil.int32)
    if this.documentPixels == nil:
      this.documentPixels = ctx.newAntialiasedFramebuffer(efSize, depth = true)
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

      if this.mode3d[]:
        glClearColor(globals.background.r, globals.background.g, globals.background.b, globals.background.a)
      else:
        glClearColor(0, 0, 0, 0)
      
      glClearDepthf(1)
      glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)

      let prevView = ctx.viewportMatrix
      let prevProj = ctx.projectionMatrix
      defer:
        ctx.viewport = prevView
        ctx.projection = prevProj
      ctx.viewport = this.viewport[]
      ctx.projection = proj

      if not this.mode3d[]:
        glDisable(GlBlend)
        glDisable(GL_DEPTH_TEST)
        ctx.fillHatchingRect(
          vec2(-1, -1 * this.h[] / this.w[]), vec2(2, 2 * this.h[] / this.w[]),
          "#252525".color, "#232323".color,
          vec2(1, 1),
          100 / this.w[], 100 / this.w[],
          transform = scale vec3(1, this.w[] / this.h[], 1)
        )
        ctx.fillRect(
          rect(layout.pageBounds.min.vec2, layout.pageBounds.size.vec2),
          color = globals.background,
        )

      if this.grid3MeshCache == nil:
        this.grid3MeshCache = Grid3MeshCache()

      glEnable(GlBlend)
      glBlendFuncSeparate(GlOne, GlOneMinusSrcAlpha, GlOne, GlOne)
      
      glEnable(GL_DEPTH_TEST)
      draw3dWorld(ctx, w, this.viewport[], proj, pixelsPerUnit, this.grid3MeshCache)
      glDisable(GL_DEPTH_TEST)

      draw2dWorld(ctx, w, this.viewport[], proj, pixelsPerUnit, this.grid3MeshCache)

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
    this.drawDocumentView(ctx)
  this.drawAfter(ctx)



proc recompileScript*(this: DocumentView) =
  if this.script[] != nil:
    withLock this.script[].lock:
      if this.script[].stage != Idle:
        return  # ignore recompile request while still compiling
  this.grid3MeshCache = nil
  let oldCache =
    if this.script[] != nil and this.script[].filename == currentScript[]:
      this.script[].cache
    else:
      nil
  this.script{} = nil  # unload current script
  this.script[] = compileAndRunScript(currentScript[], "build/script", oldCache, this.scriptOptLevel[])



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

    - MouseArea.new:
      this.fill(parent)
      acceptedButtons = {MouseButton.middle}

      this.mouseButton.connectTo root, e:
        if e.pressed:
          prevDragPos = this.mouseXy[]

      this.moved.connectTo root, e:
        if root.script[].hasWorldToDraw.not: return
        if this.pressed[]:
          let currentMousePos = this.mouseXy[]
          let d = currentMousePos - prevDragPos
          let toGl = root.viewportToGlMatrix
          # w=0: direction vector — inverse gives world-space pan delta with correct z
          let glDelta = vec4(d.x * 2 / root.w[], -d.y * 2 / root.h[], 0, 0)
          let worldDelta = inverse(toGl) * glDelta
          root.viewport[] = combine(
            translate(vec3(worldDelta.x, worldDelta.y, worldDelta.z)),
            root.viewport[]
          )
          prevDragPos = currentMousePos

      this.scrolled.connectTo root, delta:
        if root.script[].hasWorldToDraw.not: return
        if delta.y != 0:
          let toGl = root.viewportToGlMatrix
          # w=1: point — inverse gives correct 3D world anchor under mouse
          let mouseGl = vec4(
            this.mouseXy[].x * 2 / root.w[] - 1,
            1 - this.mouseXy[].y * 2 / root.h[],
            0, 1
          )
          let anchorV = inverse(toGl) * mouseGl
          let anchor = vec3(anchorV.x, anchorV.y, anchorV.z)
          let zoomFactor = pow(1.1'f32, -delta.y)
          root.viewport[] = combine(
            translate(-anchor),
            scale(zoomFactor, zoomFactor, zoomFactor),
            translate(anchor),
            root.viewport[],
          )

    - MouseArea.new:
      this.fill(parent)
      visibility = binding:
        if root.mode3d[]: Visibility.visible
        else: Visibility.collapsed
      acceptedButtons = {MouseButton.right}

      this.mouseButton.connectTo root, e:
        if e.pressed:
          prevDragPos = this.mouseXy[]

      this.moved.connectTo root, e:
        if root.script[].hasWorldToDraw.not: return
        if this.pressed[]:
          let currentMousePos = this.mouseXy[]
          let d = currentMousePos - prevDragPos
          let h = root.h[]
          let w = root.w[]
          let dn = d / vec2(h, h) * 2
          let zv = vec2(
            (prevDragPos.y / h - 0.5),
            (prevDragPos.x / w - 0.5) * (w / h)
          )
          let worldCenter = root.script[].world[].worldCenter3D()
          root.viewport[] = combine(
            root.viewport[],
            translate(-worldCenter),
            rotateY(dn.x * float32(Pi), vec3(0, 0, 0)),
            rotateX(-dn.y * float32(Pi), vec3(0, 0, 0)),
            rotateZ(dn.x / h * 1000 * float32(Pi) * zv.x, vec3(0, 0, 0)),
            rotateZ(-dn.y / h * 1000 * float32(Pi) * zv.y, vec3(0, 0, 0)),
            translate(worldCenter),
          )
          prevDragPos = currentMousePos

    - globalKeybinding({Key.f5}):
      on this.activated: root.recompileScript()
    
    - Layout.row:
      gap = 10
      centerX = parent.center
      bottom = parent.bottom - 10

      - Button.new:
        text = binding:
          case root.scriptOptLevel[]
          of optNone:  "--opt:none"
          of optSpeed: "--opt:speed"
        accent = binding: root.scriptOptLevel[] == optSpeed
        enabled = binding: root.scriptStage[] == Idle
        on this.activated:
          root.scriptOptLevel[] =
            if root.scriptOptLevel[] == optNone: optSpeed else: optNone

      - Button.new:
        text = tr"Recompile"
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
        text = binding:
          if root.mode3d[]: tr"3D" else: tr"2D"
        accent = binding: root.mode3d[]
        on this.activated:
          root.mode3d[] = not root.mode3d[]


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
