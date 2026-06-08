import std/[os, strformat, dynlib, locks, osproc, streams]
import pkg/[ecs, vmath]
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

    outputChannel*: ptr Channel[string]

    thread: Thread[WorkerArgs]


var scriptTextSize*: TextSizeCb
var scriptEntityBounds*: EntityBoundsCb
var scriptWorldBounds*: WorldBoundsCb


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
      of optNone:   "--opt:none"
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

  withLock s.lock: s.stage = Executing
  nimMain()


  let scriptHandleError = cast[proc: bool {.cdecl, gcsafe.}](s.lib.symAddr("handleErrorAfterNimMain"))
  if scriptHandleError != nil:
    if scriptHandleError(): fail()

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
