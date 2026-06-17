import std/[os, strformat, dynlib, locks, osproc, streams]
import pkg/[ecs, vmath, bumpy]
import pkg/siwin/platforms/any/window
import ../lib/sandbox


type
  ScriptStage* = enum
    Idle
    Compiling
    Executing
    # BuildingRenderTree

  ScriptOptLevel* = enum
    optNone   ## --opt:none (default, checks enabled)
    optSpeed  ## --opt:speed -d:danger (maximum speed, no checks)

  WorkerArgs = object
    script: ptr ScriptObj
    filename, outfile: string
    compile: bool = true
    optLevel: ScriptOptLevel = optNone

  TextSizeCb* = proc(text: string, fontSize: float64): Vec2 {.cdecl.}
  EntityBoundsCb* = proc(world: World, eid: EntityId): Bounds2 {.cdecl.}
  WorldBoundsCb* = proc(world: World): Bounds2 {.cdecl.}

  ProjectionMatrixCb* = proc(): Mat4 {.cdecl.}
  ViewportMatrixCb* = proc(): Mat4 {.cdecl.}
  ViewportWindowBoundsCb* = proc(): Rect {.cdecl.}
  RerunScriptRequestCb* = proc() {.cdecl.}

  ScriptSystems* = object
    ## procs exported by the script lib that forward window events into its ECS
    windowEvent_CloseEvent*: proc(e: CloseEvent) {.cdecl.}
    windowEvent_RenderEvent*: proc(e: RenderEvent) {.cdecl.}
    windowEvent_TickEvent*: proc(e: TickEvent) {.cdecl.}
    windowEvent_ResizeEvent*: proc(e: ResizeEvent) {.cdecl.}
    windowEvent_WindowMoveEvent*: proc(e: WindowMoveEvent) {.cdecl.}
    windowEvent_MouseMoveEvent*: proc(e: MouseMoveEvent) {.cdecl.}
    windowEvent_MouseButtonEvent*: proc(e: MouseButtonEvent) {.cdecl.}
    windowEvent_ScrollEvent*: proc(e: ScrollEvent) {.cdecl.}
    windowEvent_ClickEvent*: proc(e: ClickEvent) {.cdecl.}
    windowEvent_KeyEvent*: proc(e: KeyEvent) {.cdecl.}
    windowEvent_TextInputEvent*: proc(e: TextInputEvent) {.cdecl.}
    windowEvent_TouchEvent*: proc(e: TouchEvent) {.cdecl.}
    windowEvent_TouchMoveEvent*: proc(e: TouchMoveEvent) {.cdecl.}
    windowEvent_TouchPressureChangedEvent*: proc(e: TouchPressureChangedEvent) {.cdecl.}
    windowEvent_StateBoolChangedEvent*: proc(e: StateBoolChangedEvent) {.cdecl.}
    windowEvent_PopupEvent*: proc(e: PopupEvent) {.cdecl.}
    windowEvent_DropEvent*: proc(e: DropEvent) {.cdecl.}
    mainModuleFinished*: proc() {.cdecl, gcsafe.}
    viewportChanged*: proc() {.cdecl, gcsafe.}

  Script* = ref ScriptObj
  ScriptObj* = object
    lib*: LibHandle
    world*: ptr World
    cache*: World
    filename*: string
    outfile*: string
    optLevel*: ScriptOptLevel
    stage* {.guard: lock.}: ScriptStage
    lock*: Lock

    systems*: ScriptSystems

    outputChannel*: ptr Channel[string]

    thread: Thread[WorkerArgs]


var scriptTextSize*: TextSizeCb
var scriptEntityBounds*: EntityBoundsCb
var scriptWorldBounds*: WorldBoundsCb

var scriptProjectionMatrix*: ProjectionMatrixCb
var scriptViewportMatrix*: ViewportMatrixCb
var scriptViewportWindowBounds*: ViewportWindowBoundsCb
var scriptRerunScriptRequest*: RerunScriptRequestCb


proc `=destroy`(this: ScriptObj) =
  if this.lib != nil:
    unloadLib(this.lib)

  if this.thread.running:
    joinThread this.thread



proc withDllExtension(path: string): string =
  let (dir, name, _) = path.splitFile
  when defined(windows):
    dir / name & ".dll"
  else:
    dir / "lib" & name & ".so"



when defined(cgsand.script_wrapper):
  proc wrapScript(code: string): string =
    result.add code
    result.add "\n\n{.emit: \"/*VARSECTION*/ #define nimTestErrorFlag() bool was_excpt__ = *nimErrorFlag(); *nimErrorFlag() = false; nimTestErrorFlag(); *nimErrorFlag() = was_excpt__;\".}"



proc scriptWorker(info: WorkerArgs) {.thread.} =
  let s = info.script
  let outfile = info.outfile.withDllExtension

  template fail {.dirty.} =
    if info.compile:
      if s.lib != nil:
        unloadLib(s.lib)
        s.lib = nil
    withLock s.lock: s.stage = Idle
    return


  if info.compile:
    let optFlags = case info.optLevel
      of optNone:   "--opt:none --debugger:native"
      of optSpeed: "--opt:speed -d:danger"
    
    var compilePath = info.filename
    when defined(cgsand.script_wrapper):
      let wrapperPath = "build/script_wrapper.nim"
      try:
        writeFile wrapperPath, wrapScript(readFile(info.filename))
      except:
        echo getCurrentExceptionMsg() & "\n" & getCurrentException().getStackTrace()
      compilePath = wrapperPath

    let cmdStr = &"nim c --app:lib --noMain {optFlags} -o:{quoteShell(outfile)} -d:script {quoteShell(compilePath)}"
    let process = startProcess(cmdStr, options = {poUsePath, poStdErrToStdOut, poEvalCommand})
    let compileExitCode =
      try:
        let stream = process.outputStream
        while not stream.atEnd:
          let c = stream.readChar()
          if s.outputChannel != nil:
            s.outputChannel[].send($c)
        process.waitForExit
      finally:
        process.close()
    if compileExitCode != 0: fail()

    if s.lib != nil: unloadLib(s.lib)
    s.lib = loadLib(outfile)
    if s.lib == nil: fail()
  
  else:
    if s.lib != nil: unloadLib(s.lib)
    s.lib = loadLib(outfile)
    if s.lib == nil: fail()


  if s.lib == nil: fail()

  let nimMain = cast[proc() {.cdecl, gcsafe.}](s.lib.symAddr("NimMain"))
  if nimMain == nil: fail()

  let cacheInstanceAddr = s.lib.symAddr("cache_instance")
  if cacheInstanceAddr != nil:
    cast[ptr ptr World](cacheInstanceAddr)[] = s.cache.addr

  template setScriptCb(sym: string, cb: typed) =
    let cbAddr = s.lib.symAddr(sym)
    if cbAddr != nil and cb != nil:
      cast[ptr typeof(cb)](cbAddr)[] = cb
  
  setScriptCb("sandbox_textSizeImpl", scriptTextSize)
  setScriptCb("sandbox_entityBoundsImpl", scriptEntityBounds)
  setScriptCb("sandbox_worldBoundsImpl", scriptWorldBounds)

  setScriptCb("interactive_systems_projectionMatrix", scriptProjectionMatrix)
  setScriptCb("interactive_systems_viewportMatrix", scriptViewportMatrix)
  setScriptCb("interactive_systems_viewportWindowBounds", scriptViewportWindowBounds)
  setScriptCb("interactive_systems_rerunScript", scriptRerunScriptRequest)

  template resolveEventProc(fld: untyped, sym: string) =
    s.systems.fld = cast[typeof(s.systems.fld)](s.lib.symAddr(sym))

  resolveEventProc windowEvent_CloseEvent, "interactive_systems_windowEvent_CloseEvent"
  resolveEventProc windowEvent_RenderEvent, "interactive_systems_windowEvent_RenderEvent"
  resolveEventProc windowEvent_TickEvent, "interactive_systems_windowEvent_TickEvent"
  resolveEventProc windowEvent_ResizeEvent, "interactive_systems_windowEvent_ResizeEvent"
  resolveEventProc windowEvent_WindowMoveEvent, "interactive_systems_windowEvent_WindowMoveEvent"
  resolveEventProc windowEvent_MouseMoveEvent, "interactive_systems_windowEvent_MouseMoveEvent"
  resolveEventProc windowEvent_MouseButtonEvent, "interactive_systems_windowEvent_MouseButtonEvent"
  resolveEventProc windowEvent_ScrollEvent, "interactive_systems_windowEvent_ScrollEvent"
  resolveEventProc windowEvent_ClickEvent, "interactive_systems_windowEvent_ClickEvent"
  resolveEventProc windowEvent_KeyEvent, "interactive_systems_windowEvent_KeyEvent"
  resolveEventProc windowEvent_TextInputEvent, "interactive_systems_windowEvent_TextInputEvent"
  resolveEventProc windowEvent_TouchEvent, "interactive_systems_windowEvent_TouchEvent"
  resolveEventProc windowEvent_TouchMoveEvent, "interactive_systems_windowEvent_TouchMoveEvent"
  resolveEventProc windowEvent_TouchPressureChangedEvent, "interactive_systems_windowEvent_TouchPressureChangedEvent"
  resolveEventProc windowEvent_StateBoolChangedEvent, "interactive_systems_windowEvent_StateBoolChangedEvent"
  resolveEventProc windowEvent_PopupEvent, "interactive_systems_windowEvent_PopupEvent"
  resolveEventProc windowEvent_DropEvent, "interactive_systems_windowEvent_DropEvent"
  resolveEventProc mainModuleFinished, "interactive_systems_mainModuleFinished"
  resolveEventProc viewportChanged, "interactive_systems_viewportChanged"

  withLock s.lock: s.stage = Executing
  nimMain()


  let scriptHandleError = cast[proc: bool {.cdecl, gcsafe.}](s.lib.symAddr("handleErrorAfterNimMain"))
  if scriptHandleError != nil:
    if scriptHandleError(): fail()

  if s.systems.mainModuleFinished != nil:
    s.systems.mainModuleFinished()

  let w = s.lib.symAddr("world_instance")
  if w == nil: fail()
  s.world = cast[ptr World](w)

  let syncCache = cast[proc() {.cdecl, gcsafe.}](s.lib.symAddr("syncCacheFromDoc"))
  if syncCache != nil:
    syncCache()

  withLock s.lock: s.stage = Idle



proc compileAndRunScript*(
  filename: string, outfile: string = "script",
  existingCache: World = nil, optLevel: ScriptOptLevel = optNone,
  outputChannel: ptr Channel[string] = nil
): Script =
  new result
  initLock result.lock
  withLock result.lock: result.stage = Compiling
  result.filename = filename
  result.outfile = outfile
  result.optLevel = optLevel
  result.cache = if existingCache != nil: existingCache else: new World
  result.outputChannel = outputChannel

  result.thread.createThread(scriptWorker, WorkerArgs(
    script: result[].addr, filename: filename, outfile: outfile, optLevel: optLevel,
  ))


proc rerunScript*(script: Script) =
  ## Re-execute the already-compiled script .so without recompilation.
  if script.lib == nil: return
  
  withLock script.lock:
    if script.stage != Idle: return
    script.stage = Compiling
  
  if script.thread.running:
    joinThread script.thread
  
  script.thread.createThread(scriptWorker, WorkerArgs(
    script: script[].addr, filename: script.filename, outfile: script.outfile,
    compile: false,
  ))
