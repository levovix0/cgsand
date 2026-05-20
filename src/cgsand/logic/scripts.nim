import std/[os, strformat, dynlib, locks]
import pkg/[ecs]


type
  ScriptStage* = enum
    Idle
    Compiling
    Executing
    # BuildingRenderTree

  Script* = ref ScriptObj
  ScriptObj* = object
    lib*: LibHandle
    world*: ptr World
    cache*: ref World
    filename*: string
    stage* {.guard: lock.}: ScriptStage
    lock*: Lock

    thread: Thread[tuple[script: ptr ScriptObj, filename, outfile: string]]


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



proc compileAndRunScript*(filename: string, outfile: string = "script", existingCache: ref World = nil): Script =
  new result
  initLock result.lock
  withLock result.lock: result.stage = Compiling
  result.filename = filename
  result.cache = if existingCache != nil: existingCache else: new World

  proc worker(info: tuple[script: ptr ScriptObj, filename, outfile: string]) =
    template result: untyped = info.script[]
    template fail {.dirty.} =
      if result.lib != nil: unloadLib(result.lib)
      result.lib = nil
      withLock result.lock: result.stage = Idle
      return

    let outfile = info.outfile.withDllExtension
    
    when defined(cgsand.script_wrapper):
      let wrapperPath = "build/script_wrapper.nim"
    
      try:
        writeFile wrapperPath, wrapScript(readFile(info.filename))
      except:
        echo getCurrentExceptionMsg() & "\n" & getCurrentException().getStackTrace()

      if (execShellCmd &"nim c --app:lib --noMain -o:{quoteShell(outfile)} -d:script {quoteShell(wrapperPath)}") != 0: fail()
    else:
      if (execShellCmd &"nim c --app:lib --noMain -o:{quoteShell(outfile)} -d:script {quoteShell(info.filename)}") != 0: fail()
    
    result.lib = loadLib(outfile)
    if result.lib == nil: fail()

    let nimMain = cast[proc() {.cdecl, gcsafe.}](result.lib.symAddr("NimMain"))
    if nimMain == nil: fail()

    let cacheInstanceAddr = result.lib.symAddr("cache_instance")
    if cacheInstanceAddr != nil:
      cast[ptr ptr World](cacheInstanceAddr)[] = cast[ptr World](result.cache)

    withLock result.lock: result.stage = Executing
    nimMain()

    let scriptHandleError = cast[proc: bool {.cdecl, gcsafe.}](result.lib.symAddr("handleErrorAfterNimMain"))
    if scriptHandleError != nil:
      if scriptHandleError(): fail()

    let w = result.lib.symAddr("world_instance")
    if w == nil: fail()

    result.world = cast[ptr World](w)

    let syncCache = cast[proc() {.cdecl, gcsafe.}](result.lib.symAddr("syncCacheFromDoc"))
    if syncCache != nil:
      syncCache()

    withLock result.lock: result.stage = Idle
    
  result.thread.createThread(worker, (result[].addr, filename, outfile))
  

